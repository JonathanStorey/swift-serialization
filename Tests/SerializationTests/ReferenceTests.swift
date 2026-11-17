import Foundation
import Testing
@testable import Serialization

private struct Folder: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Hashable, Identifiable {
    var id: Int
    @Reference(to: Folder.self, action: .deleteSelf) var folder: Folder.ID? = nil
}

private struct Board: Codable, Identifiable {
    var id: Int
}

private struct Card: Codable, Hashable {
    @Reference(to: Board.self) var board: Board.ID? = nil
}

@Suite struct ReferenceTests {
    private let folderID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func encodesRecordNameAndAction() throws {
        let note = Note(id: 1, folder: folderID)
        #expect(try json(note) == #"{"folder":{"action":"deleteSelf","recordName":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"},"id":1}"#)
    }

    @Test func leavesOutNil() throws {
        #expect(try json(Note(id: 1, folder: nil)) == #"{"id":1}"#)
        #expect(try JSONRepresentation(Note(id: 1, folder: nil)) == ["id": 1])
    }

    @Test func decodesMissingAndNullAsNil() throws {
        for text in [#"{"id":1}"#, #"{"id":1,"folder":null}"#] {
            let note = try JSONDecoder().decode(Note.self, from: Data(text.utf8))
            #expect(note.folder == nil)
            #expect(note.$folder.action == .none)
        }
    }

    @Test func roundTrips() throws {
        let note = Note(id: 1, folder: folderID)
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(decoded == note)
        #expect(decoded.folder == folderID)
        #expect(decoded.$folder.action == .deleteSelf)
        #expect(try JSONRepresentation(note).decode(Note.self) == note)
    }

    @Test func keepsTheSavedAction() throws {
        let text = #"{"id":1,"folder":{"recordName":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","action":"none"}}"#
        let note = try JSONDecoder().decode(Note.self, from: Data(text.utf8))
        #expect(note.$folder.action == .none)
    }

    @Test func attributeActionAppliesToNewValues() {
        var note = Note(id: 1)
        #expect(note.$folder.action == .deleteSelf)
        note.folder = folderID
        #expect(note.$folder.action == .deleteSelf)
        note.$folder.action = .none
        #expect(note.$folder.action == .none)
        #expect(Card().$board.action == .none)
    }

    @Test func integerIdsUseTheirDigits() throws {
        let card = Card(board: 42)
        #expect(try json(card) == #"{"board":{"action":"none","recordName":"42"}}"#)
        #expect(try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card)) == card)
    }

    @Test func rejectsARecordNameTheIdCannotRead() {
        let text = #"{"board":{"recordName":"forty-two","action":"none"}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Card.self, from: Data(text.utf8)) }
    }

    @Test func recordReferenceIsCodable() throws {
        let reference = RecordRepresentation.Reference(recordName: "A")
        #expect(reference.action == .none)
        #expect(try json(reference) == #"{"action":"none","recordName":"A"}"#)
        #expect(try JSONDecoder().decode(RecordRepresentation.Reference.self, from: Data(json(reference).utf8)) == reference)
    }
}
