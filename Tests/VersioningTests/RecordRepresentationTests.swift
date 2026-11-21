import Foundation
import Testing
@testable import Versioning

private struct Photo: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Identifiable, Hashable {
    var id: UUID
    var title = "Title"
    var count: UInt64 = 1
    @References(Photo.self) var photos: [UUID] = []
}

private struct Folder: Codable, Identifiable {
    var id: UUID
    var parent = "reserved"
}

private struct Hidden: Codable, Identifiable {
    var id: UUID
    var score = 0

    enum CodingKeys: String, CodingKey {
        case id
        case score = "_score"
    }
}

private let noteID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

@Suite struct RecordRepresentationTests {
    @Test func holdsTheIDTypeAndFields() throws {
        let note = Note(id: noteID, photos: [UUID()])
        let record = try RecordRepresentation(note, schema: RecordSchema(for: Note.self))
        #expect(record.id == noteID)
        #expect(record.type == "Note")
        let fields = try JSONRepresentation(note)
        #expect(record.fields == fields)
        #expect(record.metadata == nil)
        #expect(try record.fields.decode(Note.self) == note)
    }

    @Test func roundTripsThroughAStore() throws {
        var record = try RecordRepresentation(Note(id: noteID), schema: RecordSchema(for: Note.self))
        record.metadata = RecordRepresentation.Metadata(rawValue: Data([1, 2, 3]))
        let key = RecordRepresentation.RecordID(recordName: noteID.uuidString)
        let store = [key: record]
        let decoded = try JSONDecoder().decode([RecordRepresentation.RecordID: RecordRepresentation].self, from: JSONEncoder().encode(store))
        #expect(decoded == store)
        #expect(key.zoneName == "_defaultZone")
        #expect(key.ownerName == "__defaultOwner__")
    }

    @Test func aSchemaForAnotherTypeThrows() {
        #expect(throws: EncodingError.self) { try RecordRepresentation(Note(id: noteID), schema: RecordSchema(for: Folder.self)) }
    }

    @Test func invalidFieldNamesThrow() {
        #expect(throws: EncodingError.self) { try RecordRepresentation(Folder(id: noteID), schema: RecordSchema(for: Folder.self)) }
        #expect(throws: EncodingError.self) { try RecordRepresentation(Hidden(id: noteID), schema: RecordSchema(for: Hidden.self)) }
    }

    @Test func anIntegerOutsideInt64Throws() throws {
        let schema = try RecordSchema(for: Note.self)
        #expect(throws: EncodingError.self) { try RecordRepresentation(Note(id: noteID, count: .max), schema: schema) }
        #expect(try RecordRepresentation(Note(id: noteID, count: UInt64(Int64.max)), schema: schema).id == noteID)
    }

    @Test func tooManyReferencesThrow() throws {
        let schema = try RecordSchema(for: Note.self)
        #expect(try RecordRepresentation(Note(id: noteID, photos: (0..<750).map { _ in UUID() }), schema: schema).id == noteID)
        #expect(throws: EncodingError.self) { try RecordRepresentation(Note(id: noteID, photos: (0..<751).map { _ in UUID() }), schema: schema) }
    }

    @Test func aRecordOverOneMegabyteThrows() throws {
        let schema = try RecordSchema(for: Note.self)
        #expect(throws: EncodingError.self) { try RecordRepresentation(Note(id: noteID, title: String(repeating: "a", count: 1_000_001)), schema: schema) }
    }

    @Test func metadataMergesToTheirs() throws {
        let ours = RecordRepresentation.Metadata(rawValue: Data([1]))
        let theirs = RecordRepresentation.Metadata(rawValue: Data([2]))
        #expect(try ours.merging(with: theirs, from: RecordRepresentation.Metadata(rawValue: Data())) == theirs)
        #expect(try ours.merging(with: theirs) == theirs)
        #expect(try JSONEncoder().encode(ours) == JSONEncoder().encode(Data([1])))
    }
}
