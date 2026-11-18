import Foundation
import Testing
@testable import Serialization

private struct Tag: Codable, Identifiable {
    var id: UUID
}

private struct Note: Codable, Hashable {
    @References(to: Tag.self) var tags: [UUID] = []
}

private struct Post: Codable, Identifiable {
    var id: UUID
}

private struct Label: Codable, Hashable {
    @References(from: Post.self, key: "labels") var posts: [UUID] = []
}

private struct Match: Codable, Hashable {
    @References(to: Tag.self, action: .deleteSelf) var tags: [UUID] = []
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

    @Test func encodesEachReferenceWithTheAction() throws {
        #expect(try json(Note(tags: [a])) == #"{"tags":[{"action":"none","recordName":"00000000-0000-0000-0000-0000000000A1"}]}"#)
        #expect(try json(Match(tags: [a])) == #"{"tags":[{"action":"deleteSelf","recordName":"00000000-0000-0000-0000-0000000000A1"}]}"#)
    }

    @Test func keepsTheAction() throws {
        let model = Match(tags: [a, b])
        let decoded = try JSONDecoder().decode(Match.self, from: JSONEncoder().encode(model))
        #expect(decoded == model)
        #expect(decoded._tags.action == .deleteSelf)
        #expect(try JSONDecoder().decode(Match.self, from: Data("{}".utf8))._tags.action == .none)
    }

    @Test func inverseNamesTheDeclaringKeyPath() {
        #expect(Label()._posts.inverse == "Post.labels")
        #expect(Note()._tags.inverse == nil)
    }

    @Test func inverseSortsByInverseOrder() {
        let links = [
            Relationship(keyPath: "Post.labels", from: a, to: note, order: 0, inverseOrder: 2),
            Relationship(keyPath: "Post.labels", from: b, to: note, order: 5, inverseOrder: 1),
        ]
        #expect(References<Post>(links, from: note).wrappedValue == [b, a])
    }

    @Test func rejectsARecordNameThatIsNotAUUID() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Note.self, from: Data(#"{"tags":[{"recordName":"42","action":"none"}]}"#.utf8)) }
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
        let model = References<Tag>(links, from: note, action: .deleteSelf)
        #expect(model.wrappedValue == [b, a, c])
        #expect(model.action == .deleteSelf)
    }
}
