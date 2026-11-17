import Foundation
import Testing
@testable import Serialization

private struct Folder: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Hashable, Identifiable {
    var id: UUID
    @Reference(to: Folder.self, action: .deleteSelf) var folder: Folder.ID? = nil
}

private struct Board: Codable, Identifiable {
    var id: UUID
}

private struct Card: Codable, Hashable {
    @Reference(to: Board.self) var board: Board.ID? = nil
}

@Suite struct ReferenceTests {
    private let folderID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    private let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func encodesRecordNameAndAction() throws {
        let note = Note(id: noteID, folder: folderID)
        #expect(try json(note) == #"{"folder":{"action":"deleteSelf","recordName":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"},"id":"00000000-0000-0000-0000-000000000001"}"#)
    }

    @Test func leavesOutNil() throws {
        #expect(try json(Note(id: noteID, folder: nil)) == #"{"id":"00000000-0000-0000-0000-000000000001"}"#)
        #expect(try JSONRepresentation(Note(id: noteID, folder: nil)) == ["id": "00000000-0000-0000-0000-000000000001"])
    }

    @Test func decodesMissingAndNullAsNil() throws {
        for text in [#"{"id":"00000000-0000-0000-0000-000000000001"}"#, #"{"id":"00000000-0000-0000-0000-000000000001","folder":null}"#] {
            let note = try JSONDecoder().decode(Note.self, from: Data(text.utf8))
            #expect(note.folder == nil)
            #expect(note.$folder.action == .none)
        }
    }

    @Test func roundTrips() throws {
        let note = Note(id: noteID, folder: folderID)
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(decoded == note)
        #expect(decoded.folder == folderID)
        #expect(decoded.$folder.action == .deleteSelf)
        #expect(try JSONRepresentation(note).decode(Note.self) == note)
    }

    @Test func keepsTheSavedAction() throws {
        let text = #"{"id":"00000000-0000-0000-0000-000000000001","folder":{"recordName":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","action":"none"}}"#
        let note = try JSONDecoder().decode(Note.self, from: Data(text.utf8))
        #expect(note.$folder.action == .none)
    }

    @Test func attributeActionAppliesToNewValues() {
        var note = Note(id: noteID)
        #expect(note.$folder.action == .deleteSelf)
        note.folder = folderID
        #expect(note.$folder.action == .deleteSelf)
        note.$folder.action = .none
        #expect(note.$folder.action == .none)
        #expect(Card().$board.action == .none)
    }

    @Test func readsLowercaseRecordNames() throws {
        let text = #"{"board":{"recordName":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","action":"none"}}"#
        #expect(try JSONDecoder().decode(Card.self, from: Data(text.utf8)).board == folderID)
    }

    @Test func rejectsARecordNameThatIsNotAUUID() {
        let text = #"{"board":{"recordName":"42","action":"none"}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Card.self, from: Data(text.utf8)) }
    }

    @Test func recordReferenceIsCodable() throws {
        let reference = RecordRepresentation.Reference(recordName: "A")
        #expect(reference.action == .none)
        #expect(try json(reference) == #"{"action":"none","recordName":"A"}"#)
        #expect(try JSONDecoder().decode(RecordRepresentation.Reference.self, from: Data(json(reference).utf8)) == reference)
    }
}
