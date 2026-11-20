import Foundation
import Testing
@testable import Versioning

private struct Folder: Codable, Identifiable {
    var id: UUID
}

private struct Tag: Codable, Identifiable {
    var id: UUID
    @References(from: \Note.tags) var notes: [UUID] = []
    var related: [UUID] = []
}

private enum Mood: String, Codable, CaseIterable {
    case calm, busy
}

private struct Size: Codable {
    var width: Double
    var height: Double
}

private struct Note: Codable, Identifiable {
    var id: UUID
    var title: String
    var count: Int
    var isPinned: Bool
    var score: Double
    var created: Date
    var thumbnail: Data?
    var mood: Mood
    var size: Size
    var words: [String]
    var maybeWords: [String?]
    var home: Location?
    @Asset var attachment: Data? = nil
    @Encrypted var body: String = ""
    @Encrypted var pin: Int? = nil
    @Reference(Folder.self) var folder: UUID? = nil
    @Parent(Folder.self) var owner: UUID? = nil
    @References(to: \Tag.notes) var tags: [UUID] = []
    @Timestamp var updatedOnServer: Date? = nil
    @Transient var draft: String? = nil
}

/// Versions of one record type, named `Item` so they share a record type.
private enum V1 {
    struct Item: Codable {
        var name: String
        var count: Int
        var mood: Mood
    }
}

private enum Added {
    struct Item: Codable {
        var name: String
        var count: Int
        var mood: Mood
        var note: String?
    }
}

private enum Required {
    struct Item: Codable {
        var name: String
        var count: Int
        var mood: Mood
        var note: String
    }
}

private enum Removed {
    struct Item: Codable {
        var name: String
        var mood: Mood
    }
}

private enum Retyped {
    struct Item: Codable {
        var name: String
        var count: Double
        var mood: Mood
    }
}

private enum Encrypting {
    struct Item: Codable {
        var name: String
        @Encrypted var count: Int = 0
        var mood: Mood
    }
}

private enum MoreMoods {
    enum Mood: String, Codable, CaseIterable {
        case calm, busy, sleepy
    }

    struct Item: Codable {
        var name: String
        var count: Int
        var mood: Mood
    }
}

@Suite struct RecordSchemaTests {
    private func schema<T: Decodable>(_ type: T.Type) throws -> RecordSchema {
        try RecordSchema(for: type)
    }

    @Test func namesTheRecordType() throws {
        #expect(try schema(Note.self).recordType == "Note")
    }

    @Test func mapsFieldsToCloudKitTypes() throws {
        let fields = try schema(Note.self).fields
        let types = fields.mapValues(\.type.description)
        #expect(types == [
            "id": "STRING",
            "title": "STRING",
            "count": "INT64",
            "isPinned": "INT64",
            "score": "DOUBLE",
            "created": "TIMESTAMP",
            "thumbnail": "BYTES",
            "mood": "STRING",
            "size": "BYTES",
            "words": "LIST<STRING>",
            "maybeWords": "BYTES",
            "home": "LOCATION",
            "attachment": "ASSET",
            "body": "STRING",
            "pin": "INT64",
            "folder": "REFERENCE",
            "owner": "REFERENCE",
            "tags": "LIST<REFERENCE>",
        ])
    }

    @Test func leavesOutTimestampsAndTransientValues() throws {
        let fields = try schema(Note.self).fields
        #expect(fields["updatedOnServer"] == nil)
        #expect(fields["draft"] == nil)
    }

    @Test func marksEncryptedAndOptionalFields() throws {
        let fields = try schema(Note.self).fields
        #expect(fields["body"]?.isEncrypted == true)
        #expect(fields["pin"]?.isEncrypted == true)
        #expect(fields["title"]?.isEncrypted == false)
        #expect(fields["pin"]?.schema.isOptional == true)
        #expect(fields["folder"]?.schema.isOptional == true)
        #expect(fields["title"]?.schema.isOptional == false)
        #expect(fields["mood"]?.schema == .string(cases: ["calm", "busy"]))
    }

    @Test func addingAnOptionalFieldIsCompatible() throws {
        #expect(try schema(Added.Item.self).isCompatible(with: schema(V1.Item.self)))
    }

    @Test func addingARequiredFieldCannotReadOldRecords() throws {
        let old = try schema(V1.Item.self)
        let new = try schema(Required.Item.self)
        #expect(!new.isSuperset(of: old))
        #expect(new.isSubset(of: old))
    }

    @Test func removingAFieldStillReads() throws {
        let old = try schema(V1.Item.self)
        let new = try schema(Removed.Item.self)
        #expect(new.isSuperset(of: old))
        #expect(!old.isSuperset(of: new))
    }

    @Test func changingAFieldTypeIsIncompatible() throws {
        let old = try schema(V1.Item.self)
        let new = try schema(Retyped.Item.self)
        #expect(!new.isSuperset(of: old))
        #expect(!new.isSubset(of: old))
    }

    @Test func encryptingAFieldIsIncompatible() throws {
        #expect(try !schema(Encrypting.Item.self).isCompatible(with: schema(V1.Item.self)))
    }

    @Test func enumCasesMustCoverTheWriter() throws {
        let old = try schema(V1.Item.self)
        let new = try schema(MoreMoods.Item.self)
        #expect(new.isSuperset(of: old))
        #expect(!old.isSuperset(of: new))
    }

    @Test func idIsStableAndFollowsEquality() throws {
        #expect(try schema(V1.Item.self).id == schema(V1.Item.self).id)
        #expect(try schema(V1.Item.self).id != schema(Added.Item.self).id)
    }

    @Test func roundTripsThroughCodable() throws {
        let original = try schema(Note.self)
        let decoded = try JSONDecoder().decode(RecordSchema.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.id == original.id)
    }

    @Test func namesAKeyPathByItsCodingKey() throws {
        #expect(try RecordSchema.name(of: \Note.tags) == "Note.tags")
        #expect(throws: DecodingError.self) { try RecordSchema.name(of: \Tag.related) }
    }
}

#if canImport(CloudKit)
import CloudKit

private enum Listed {
    struct Item: Codable {
        var words: [String]
    }
}

@Suite struct RecordSchemaRecordTests {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    private func item(_ values: [String: CKRecordValue?], encrypted: [String: CKRecordValue?] = [:], type: String = "Item") -> CKRecord {
        let record = CKRecord(recordType: type)
        for (key, value) in values { record[key] = value }
        for (key, value) in encrypted { record.encryptedValues[key] = value }
        return record
    }

    private let valid: [String: CKRecordValue?] = ["name": "A" as NSString, "count": 2 as NSNumber, "mood": "calm" as NSString]

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    @Test func readsAMatchingRecord() throws {
        #expect(try RecordSchema(for: V1.Item.self).contains(item(valid)))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    @Test func rejectsAnotherRecordType() throws {
        #expect(try !RecordSchema(for: V1.Item.self).contains(item(valid, type: "Other")))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    @Test func requiresRequiredFieldsOnly() throws {
        var missing = valid
        missing["count"] = nil
        #expect(try !RecordSchema(for: V1.Item.self).contains(item(missing)))
        #expect(try RecordSchema(for: Added.Item.self).contains(item(valid)))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    @Test func checksTypesAndCases() throws {
        let schema = try RecordSchema(for: V1.Item.self)
        var fractional = valid
        fractional["count"] = 1.5 as NSNumber
        #expect(!schema.contains(item(fractional)))
        var unknownCase = valid
        unknownCase["mood"] = "sleepy" as NSString
        #expect(!schema.contains(item(unknownCase)))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    @Test func readsEncryptedFieldsFromEncryptedValues() throws {
        let schema = try RecordSchema(for: Encrypting.Item.self)
        var plain = valid
        plain["count"] = nil
        #expect(schema.contains(item(plain, encrypted: ["count": 2 as NSNumber])))
        #expect(!schema.contains(item(valid)))
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    @Test func checksListElements() throws {
        let schema = try RecordSchema(for: Listed.Item.self)
        #expect(schema.contains(item(["words": ["a", "b"] as NSArray])))
        #expect(!schema.contains(item(["words": [1, 2] as NSArray])))
    }
}
#endif
