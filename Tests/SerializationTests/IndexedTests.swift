import Foundation
import Testing
@testable import Serialization

private struct Note: Codable, Hashable {
    @Indexed var created: Int = 0
    @Indexed([.queryable, .searchable]) var title: String = ""
    @Indexed var rank: Int? = nil

    /// The wrapper's storage is private, so only this file can read it.
    var createdIndex: RecordRepresentation.Index? { _created.index }
    var titleIndex: RecordRepresentation.Index? { _title.index }
}

@Suite struct IndexedTests {
    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func defaultsToQueryableAndSortable() {
        #expect(Note().createdIndex == [.queryable, .sortable])
        #expect(Note().titleIndex == [.queryable, .searchable])
    }

    @Test func encodesLikeItsValue() throws {
        #expect(try json(Note(created: 3, title: "hi", rank: 1)) == #"{"created":3,"rank":1,"title":"hi"}"#)
    }

    @Test func leavesOutNilAndDecodesMissingAsNil() throws {
        #expect(try json(Note()) == #"{"created":0,"title":""}"#)
        #expect(try JSONDecoder().decode(Note.self, from: Data(#"{"created":0,"title":""}"#.utf8)).rank == nil)
    }

    @Test func decodedWrapperHasNoIndexAndStillEqualsTheOriginal() throws {
        let model = Note(created: 3, title: "hi", rank: 1)
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(model))
        #expect(decoded.createdIndex == nil)
        #expect(decoded == model)
        #expect(decoded.hashValue == model.hashValue)
        #expect(try JSONRepresentation(model).decode(Note.self) == model)
    }
}
