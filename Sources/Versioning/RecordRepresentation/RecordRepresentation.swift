import Foundation

/// One CloudKit record, independent of the CloudKit framework: a model's
/// id, its record type, its fields as JSON, and the server's metadata.
///
/// ```swift
/// let schema = try RecordSchema(for: Note.self)
/// let record = try RecordRepresentation(note, schema: schema)
/// var store: [RecordRepresentation.RecordID: RecordRepresentation] = [:]
/// ```
///
/// The zone is not stored. A store keys each record by its
/// ``RecordID``, which holds the zone, and the record name is held here
/// too, so each can check the other.
///
/// Creating one checks everything CloudKit would reject, so a record that
/// exists can be saved. The checked properties are read-only, so it stays
/// valid. Decoding one from a store you wrote does not check it again.
public struct RecordRepresentation: Codable, Hashable, Sendable {
    /// The model's id, whose `uuidString` is the record name.
    public let id: UUID
    /// The record type, as in `"Note"`.
    public let type: String
    /// The model, encoded.
    public let fields: JSONRepresentation
    /// The server's system fields, or `nil` until the server confirms the
    /// record.
    public var metadata: Metadata?

    /// The record for `value`, whose type `schema` describes.
    ///
    /// Throws `EncodingError.invalidValue`, at the field's coding path where
    /// there is one, when:
    /// - `schema` does not describe `Value`, or does not have a field the
    ///   value encodes,
    /// - a field name does not start with a letter, holds anything but
    ///   letters, digits and underscores, is longer than 255 characters,
    ///   or is a name CloudKit reserves,
    /// - an `INT64` field holds a number that does not fit in `Int64`,
    /// - the record holds more than 750 references, or
    /// - its fields encode to more than 1,000,000 bytes, a conservative
    ///   estimate of CloudKit's 1 MB limit, which assets do not count
    ///   toward.
    public init<Value: Identifiable & Encodable>(_ value: Value, schema: RecordSchema, metadata: Metadata? = nil) throws where Value.ID == UUID {
        guard schema.recordType == String(describing: Value.self) else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "The schema describes \(schema.recordType), not \(Value.self)."))
        }
        let fields = try JSONRepresentation(value)
        try fields.validate(as: schema)
        id = value.id
        type = schema.recordType
        self.fields = fields
        self.metadata = metadata
    }
}

extension RecordRepresentation {
    /// The server's system fields, archived with
    /// `CKRecord.encodeSystemFields(with:)`. They carry the change tag
    /// CloudKit checks on each save.
    public struct Metadata: RawRepresentable, Codable, Hashable, Sendable {
        public var rawValue: Data

        public init(rawValue: Data) {
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(Data.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// Where a record lives: its name and its zone, as `CKRecord.ID`
    /// holds them, so a store can key records by it.
    public struct RecordID: Codable, Hashable, Sendable {
        public var recordName: String
        public var zoneName: String
        /// The zone's owner. `"__defaultOwner__"`, CloudKit's
        /// `CKCurrentUserDefaultName`, means the current user.
        public var ownerName: String

        public init(recordName: String, zoneName: String = "_defaultZone", ownerName: String = "__defaultOwner__") {
            self.recordName = recordName
            self.zoneName = zoneName
            self.ownerName = ownerName
        }
    }
}

extension RecordRepresentation.Metadata: Mergeable {
    /// Theirs, because the server's change tag is the one the next save
    /// must carry.
    public func merging(with theirs: Self, from base: Self) throws(MergeConflict) -> Self {
        theirs
    }

    /// Theirs, as with a base.
    public func merging(with theirs: Self) throws(MergeConflict) -> Self {
        theirs
    }
}

private extension JSONRepresentation {
    /// The names CloudKit gives a record's own fields.
    static let reservedFieldNames: Set<String> = [
        "recordName", "recordID", "recordType", "creationDate", "creatorUserRecordID",
        "modificationDate", "modifiedByUserRecordID", "recordChangeTag", "share", "parent",
    ]

    /// Throws where CloudKit would reject this object as a record's fields
    /// under `schema`.
    func validate(as schema: RecordSchema) throws {
        func invalid(_ message: String, at key: String? = nil) -> EncodingError {
            EncodingError.invalidValue(self, .init(codingPath: key.map { [Path.Segment.key($0) as any CodingKey] } ?? [], debugDescription: message))
        }
        guard case .object(let members) = self else { throw invalid("A record's fields must be an object.") }
        var references = 0
        for (key, value) in members {
            guard key.count <= 255, key.first?.isASCII == true, key.first?.isLetter == true,
                  key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
                throw invalid("\"\(key)\" is not a valid CloudKit field name.", at: key)
            }
            guard !Self.reservedFieldNames.contains(key) else { throw invalid("CloudKit reserves the field name \"\(key)\".", at: key) }
            guard let field = schema.fields[key] else { throw invalid("The schema has no field \"\(key)\".", at: key) }
            switch (field.type, value) {
            case (.int64, .number(let text)):
                guard Int64(text) != nil else { throw invalid("\(text) does not fit in INT64.", at: key) }
            case (.list(.int64), .array(let elements)):
                for case .number(let text) in elements where Int64(text) == nil {
                    throw invalid("\(text) does not fit in INT64.", at: key)
                }
            case (.reference, .object):
                references += 1
            case (.list(.reference), .array(let elements)):
                references += elements.count
            default:
                break
            }
        }
        guard references <= 750 else { throw invalid("A record can hold at most 750 references, not \(references).") }
        let size = try JSONEncoder().encode(self).count
        guard size <= 1_000_000 else { throw invalid("The fields encode to \(size) bytes, over CloudKit's 1 MB limit.") }
    }
}

extension RecordRepresentation {
    /// A reference to another record in the same zone, as CloudKit's
    /// `CKRecord.Reference` stores it.
    ///
    /// CloudKit requires a reference to point into the zone of the record
    /// that holds it, so the zone is not stored here.
    public struct Reference: Codable, Hashable, Sendable {
        /// What CloudKit does to the record holding the reference when the
        /// target record is deleted. The cases match `CKRecord.ReferenceAction`.
        public enum Action: String, CaseIterable, Codable, Hashable, Sendable {
            /// Nothing. The reference is left pointing at a missing record.
            case none
            /// The record holding the reference is deleted too.
            case deleteSelf
        }

        /// The target record's name.
        public var recordName: String
        public var action: Action
        /// Whether the target is the record's `parent`, which CloudKit
        /// shares the record with. A parent's action is always `.none`.
        public var isParent: Bool

        public init(recordName: String, action: Action = .none) {
            self.recordName = recordName
            self.action = action
            isParent = false
        }

        /// A reference to the record's parent.
        public init(parent recordName: String) {
            self.recordName = recordName
            action = .none
            isParent = true
        }
    }
}

// `isParent` is written only when it is true, so a plain reference encodes
// as it always has, and a missing flag decodes as `false`.
extension RecordRepresentation.Reference {
    private enum CodingKeys: String, CodingKey {
        case recordName, action, isParent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordName = try container.decode(String.self, forKey: .recordName)
        action = try container.decode(Action.self, forKey: .action)
        isParent = try container.decodeIfPresent(Bool.self, forKey: .isParent) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordName, forKey: .recordName)
        try container.encode(action, forKey: .action)
        if isParent { try container.encode(true, forKey: .isParent) }
    }
}
