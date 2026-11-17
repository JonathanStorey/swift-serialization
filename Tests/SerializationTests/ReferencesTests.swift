import Foundation
import Testing
@testable import Serialization

private struct Tag: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Hashable {
    @References(to: Tag.self, action: .deleteSelf) var tags: [UUID] = []
}

@Suite struct ReferencesTests {
    private let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func encodesEachReference() throws {
        #expect(try json(Note(tags: [a, b])) == """
            {"tags":[{"action":"deleteSelf","recordName":"00000000-0000-0000-0000-00000000000A"},\
            {"action":"deleteSelf","recordName":"00000000-0000-0000-0000-00000000000B"}]}
            """)
    }

    @Test func leavesOutAnEmptyList() throws {
        #expect(try json(Note()) == "{}")
        #expect(try JSONDecoder().decode(Note.self, from: Data("{}".utf8)).tags == [])
    }

    @Test func roundTrips() throws {
        let note = Note(tags: [a, b])
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(decoded == note)
        #expect(decoded.$tags.action == .deleteSelf)
        #expect(try JSONRepresentation(note).decode(Note.self) == note)
    }

    @Test func takesTheFirstElementsAction() throws {
        let text = #"{"tags":[{"recordName":"00000000-0000-0000-0000-00000000000A","action":"none"}]}"#
        #expect(try JSONDecoder().decode(Note.self, from: Data(text.utf8)).$tags.action == .none)
    }

    @Test func untypedReferencesUseUUIDAsTheTarget() throws {
        struct Link: Codable, Hashable {
            @References<UUID>() var references: [UUID]
            init() {}
        }
        var link = Link()
        link.references = [a, b]
        #expect(link.$references.action == .none)
        #expect(try JSONDecoder().decode(Link.self, from: JSONEncoder().encode(link)) == link)
    }

    @Test func rejectsARecordNameThatIsNotAUUID() {
        let text = #"{"tags":[{"recordName":"x","action":"none"}]}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Note.self, from: Data(text.utf8)) }
    }
}
