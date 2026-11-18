import Foundation
import Testing
@testable import Serialization

private struct Folder: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Hashable {
    @Parent(Folder.self) var folder: UUID? = nil
}

@Suite struct ParentTests {
    private let folder = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func encodesAReferenceWithNoAction() throws {
        #expect(try json(Note(folder: folder)) == #"{"folder":{"action":"none","recordName":"00000000-0000-0000-0000-00000000000F"}}"#)
    }

    @Test func leavesOutNilAndDecodesMissingAsNil() throws {
        #expect(try json(Note()) == "{}")
        #expect(try JSONDecoder().decode(Note.self, from: Data("{}".utf8)).folder == nil)
    }

    @Test func roundTrips() throws {
        let model = Note(folder: folder)
        #expect(try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(model)) == model)
        #expect(try JSONRepresentation(model).decode(Note.self) == model)
    }

    @Test func rejectsARecordNameThatIsNotAUUID() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Note.self, from: Data(#"{"folder":{"recordName":"42","action":"none"}}"#.utf8)) }
    }
}
