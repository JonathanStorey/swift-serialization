import Foundation
import Testing
@testable import Serialization

private struct Tag: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Hashable {
    @References(to: Tag.self) var tags: [UUID] = []
}

@Suite struct ReferencesTests {
    private let note = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private let c = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func holdsTheIDsInOrder() {
        #expect(Note(tags: [b, a]).tags == [b, a])
        #expect(Note().tags == [])
    }

    @Test func encodesTheIDs() throws {
        #expect(try json(Note(tags: [a])) == #"{"tags":["00000000-0000-0000-0000-0000000000A1"]}"#)
    }

    @Test func leavesOutAnEmptyList() throws {
        #expect(try json(Note()) == "{}")
        #expect(try JSONDecoder().decode(Note.self, from: Data("{}".utf8)).tags == [])
    }

    @Test func roundTrips() throws {
        let model = Note(tags: [a, b])
        #expect(try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(model)) == model)
        #expect(try JSONRepresentation(model).decode(Note.self) == model)
    }

    @Test func fetchedLinksSortByOrderWithUnplacedLinksLast() {
        let links = [
            Relationship(keyPath: "Note.tags", from: note, to: a, order: 4),
            Relationship(keyPath: "Note.tags", from: note, to: c, inverseOrder: 0),
            Relationship(keyPath: "Note.tags", from: note, to: b, order: 0),
        ]
        #expect(References<Tag>(links, from: note).wrappedValue == [b, a, c])
    }
}
