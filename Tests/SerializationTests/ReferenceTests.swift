import Foundation
import Testing
@testable import Serialization

private struct Folder: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Hashable, Identifiable {
    var id: UUID
    @Reference(to: Folder.self) var folder: Folder.ID? = nil
}

private struct Child: Codable, Hashable {
    @Reference(to: Folder.self, action: .deleteSelf) var folder: Folder.ID? = nil
}

@Suite struct ReferenceTests {
    private let folderID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    private let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func holdsTheID() {
        #expect(Note(id: noteID, folder: folderID).folder == folderID)
        #expect(Note(id: noteID).folder == nil)
    }

    @Test func encodesARecordReference() throws {
        #expect(try json(Note(id: noteID, folder: folderID)) == #"{"folder":{"action":"none","recordName":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"},"id":"00000000-0000-0000-0000-000000000001"}"#)
    }

    @Test func leavesOutNil() throws {
        #expect(try json(Note(id: noteID)) == #"{"id":"00000000-0000-0000-0000-000000000001"}"#)
        #expect(try JSONRepresentation(Note(id: noteID)) == ["id": "00000000-0000-0000-0000-000000000001"])
    }

    @Test func decodesMissingAndNullAsNil() throws {
        for text in [#"{"id":"00000000-0000-0000-0000-000000000001"}"#, #"{"id":"00000000-0000-0000-0000-000000000001","folder":null}"#] {
            #expect(try JSONDecoder().decode(Note.self, from: Data(text.utf8)).folder == nil)
        }
    }

    @Test func roundTrips() throws {
        let note = Note(id: noteID, folder: folderID)
        #expect(try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note)) == note)
        #expect(try JSONRepresentation(note).decode(Note.self) == note)
    }

    @Test func readsLowercaseRecordNames() throws {
        let text = #"{"id":"00000000-0000-0000-0000-000000000001","folder":{"recordName":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","action":"none"}}"#
        #expect(try JSONDecoder().decode(Note.self, from: Data(text.utf8)).folder == folderID)
    }

    @Test func rejectsARecordNameThatIsNotAUUID() {
        let text = #"{"id":"00000000-0000-0000-0000-000000000001","folder":{"recordName":"42","action":"none"}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Note.self, from: Data(text.utf8)) }
    }

    @Test func keepsTheAction() throws {
        let child = Child(folder: folderID)
        #expect(child._folder.action == .deleteSelf)
        #expect(try json(child) == #"{"folder":{"action":"deleteSelf","recordName":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}}"#)
        let decoded = try JSONDecoder().decode(Child.self, from: JSONEncoder().encode(child))
        #expect(decoded == child)
        #expect(decoded._folder.action == .deleteSelf)
    }

    @Test func aNilReferenceDecodesWithNone() throws {
        #expect(try JSONDecoder().decode(Child.self, from: Data("{}".utf8))._folder.action == .none)
    }

    @Test func recordReferenceIsCodable() throws {
        let reference = RecordRepresentation.Reference(recordName: "A")
        #expect(reference.action == .none)
        #expect(try json(reference) == #"{"action":"none","recordName":"A"}"#)
        #expect(try JSONDecoder().decode(RecordRepresentation.Reference.self, from: Data(json(reference).utf8)) == reference)
    }
}
