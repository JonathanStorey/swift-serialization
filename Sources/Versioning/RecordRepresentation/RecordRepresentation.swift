/// The namespace for CloudKit record values that need a type of their own,
/// such as ``Reference``, independent of the CloudKit framework.
public enum RecordRepresentation {}

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
