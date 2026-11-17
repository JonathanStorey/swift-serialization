import Foundation
import Testing
@testable import Serialization

private struct Tag: Codable, Hashable, Identifiable {
    var id: UUID
    var name = ""
}

private struct Note: Codable, Hashable {
    @Relationship(to: Tag.self) var tags: [UUID] = []
}

@Suite struct RelationshipWrapperTests {
    private let note = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// A note as fetched from a server, linked to `ids` with no changes.
    private func fetched(_ ids: [UUID]) throws -> Note {
        var note = Note(tags: ids)
        note.$tags.commit()
        return note
    }

    @Test func appendHoldsANewTarget() {
        var note = Note()
        let tag = Tag(id: a, name: "Swift")
        note.$tags.append(tag)
        #expect(note.tags == [a])
        #expect(note.$tags.inserted == [tag])
        #expect(note.$tags.added == [a])
    }

    @Test func appendingAgainReplacesTheHeldCopy() {
        var note = Note()
        note.$tags.append(Tag(id: a, name: "Swift"))
        note.$tags.append(Tag(id: a, name: "SwiftUI"))
        #expect(note.tags == [a])
        #expect(note.$tags.inserted.map(\.name) == ["SwiftUI"])
    }

    @Test func removingAnIDDropsItsHeldTarget() {
        var note = Note()
        note.$tags.append(Tag(id: a))
        note.tags.removeAll { $0 == a }
        #expect(note.$tags.inserted.isEmpty)
        #expect(note.$tags.added.isEmpty)
    }

    @Test func tracksAddedAndRemovedSinceTheLastSave() throws {
        var note = try fetched([a])
        #expect(note.$tags.added.isEmpty)
        #expect(note.$tags.removed.isEmpty)
        note.tags = [b]
        #expect(note.$tags.added == [b])
        #expect(note.$tags.removed == [a])
    }

    @Test func changesBuildLinksFromTheDeclaringRecord() throws {
        var model = try fetched([a])
        model.tags = [b]
        let changes = model.$tags.changes(keyPath: "Note.tags", from: note)
        #expect(changes.added == [RecordRepresentation.Relationship(keyPath: "Note.tags", from: note, to: b)])
        #expect(changes.removed.map(\.id) == [RecordRepresentation.Relationship(keyPath: "Note.tags", from: note, to: a).id])
    }

    @Test func commitClearsTheChanges() {
        var note = Note()
        note.$tags.append(Tag(id: a))
        note.$tags.commit()
        #expect(note.$tags.inserted.isEmpty)
        #expect(note.$tags.added.isEmpty)
        #expect(note.$tags.removed.isEmpty)
    }

    @Test func encodesOnlyTheIDsWhenSaved() throws {
        #expect(try json(fetched([a])) == #"{"tags":{"ids":["00000000-0000-0000-0000-0000000000A1"]}}"#)
    }

    @Test func leavesOutAnEmptyRelationship() throws {
        #expect(try json(Note()) == "{}")
        #expect(try JSONDecoder().decode(Note.self, from: Data("{}".utf8)).tags == [])
    }

    @Test func keepsARemovalOfTheLastID() throws {
        var note = try fetched([a])
        note.tags = []
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(decoded.$tags.removed == [a])
    }

    @Test func decodedIDsAreSaved() throws {
        let decoded = try JSONDecoder().decode(Note.self, from: Data(#"{"tags":{"ids":["00000000-0000-0000-0000-0000000000A1"]}}"#.utf8))
        #expect(decoded.tags == [a])
        #expect(decoded.$tags.added.isEmpty)
    }

    @Test func roundTripsUnsavedChanges() throws {
        var note = try fetched([a])
        note.tags = []
        note.$tags.append(Tag(id: b, name: "Swift"))
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        #expect(decoded == note)
        #expect(decoded.$tags.inserted.map(\.name) == ["Swift"])
        #expect(decoded.$tags.removed == [a])
        #expect(try JSONRepresentation(note).decode(Note.self) == note)
    }
}
