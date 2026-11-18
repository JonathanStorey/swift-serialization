import Foundation
import Testing
@testable import Serialization

private struct Tag: Codable, Hashable, Identifiable {
    var id: UUID
    var name = ""
}

private struct Note: Codable, Hashable {
    @References(to: Tag.self) var tags: [UUID] = []
}

/// A declaring side and its inverse.
private struct Post: Codable, Hashable, Identifiable {
    var id: UUID
    @References(to: Label.self) var labels: [UUID] = []
}

private struct Label: Codable, Hashable, Identifiable {
    var id: UUID
    @References(from: \Post.labels) var posts: [UUID] = []
}

private struct Cascade: Codable, Hashable {
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

    /// A note saved with `ids` and no changes since.
    private func saved(_ ids: [UUID]) -> Note {
        var model = Note(tags: ids)
        model.$tags.commit(keyPath: "Note.tags", from: note)
        return model
    }

    /// A note fetched with links to `a`, `b` and `c` at the given orders.
    private func fetched(a: Int? = nil, b: Int? = nil, c: Int? = nil) -> Note {
        let links = [(self.a, a), (self.b, b), (self.c, c)].compactMap { id, order in
            order.map { Relationship(keyPath: "Note.tags", from: note, to: id, order: $0) }
        }
        var model = Note()
        model.$tags = References(links, from: note)
        return model
    }

    /// The target ids and orders of the links a save would write.
    private func saves(_ model: Note) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: model.$tags.changes(keyPath: "Note.tags", from: note).save.map { ($0.target(from: note), $0.order ?? -1) })
    }

    // MARK: Changes

    @Test func appendHoldsANewTarget() {
        var model = Note()
        let tag = Tag(id: a, name: "Swift")
        model.$tags.append(tag)
        #expect(model.tags == [a])
        #expect(model.$tags.inserted == [tag])
        #expect(model.$tags.added == [a])
    }

    @Test func appendingAgainReplacesTheHeldCopy() {
        var model = Note()
        model.$tags.append(Tag(id: a, name: "Swift"))
        model.$tags.append(Tag(id: a, name: "SwiftUI"))
        #expect(model.tags == [a])
        #expect(model.$tags.inserted.map(\.name) == ["SwiftUI"])
    }

    @Test func removingAnIDDropsItsHeldTarget() {
        var model = Note()
        model.$tags.append(Tag(id: a))
        model.tags.removeAll { $0 == a }
        #expect(model.$tags.inserted.isEmpty)
        #expect(model.$tags.added.isEmpty)
    }

    @Test func tracksAddedAndRemovedSinceTheLastSave() {
        var model = saved([a])
        #expect(model.$tags.added.isEmpty)
        #expect(model.$tags.removed.isEmpty)
        model.tags = [b]
        #expect(model.$tags.added == [b])
        #expect(model.$tags.removed == [a])
    }

    @Test func changesSaveNewLinksAndDeleteSavedOnes() {
        var model = saved([a])
        model.tags = [b]
        let changes = model.$tags.changes(keyPath: "Note.tags", from: note)
        #expect(changes.save == [Relationship(keyPath: "Note.tags", from: note, to: b, order: 0)])
        #expect(changes.delete == [Relationship(keyPath: "Note.tags", from: note, to: a)])
    }

    @Test func commitKeepsTheSavedLinks() {
        var model = Note()
        model.$tags.append(Tag(id: a))
        model.tags.append(b)
        model.$tags.commit(keyPath: "Note.tags", from: note)
        #expect(model.$tags.links == [
            Relationship(keyPath: "Note.tags", from: note, to: a, order: 0),
            Relationship(keyPath: "Note.tags", from: note, to: b, order: 1),
        ])
        #expect(model.$tags.inserted.isEmpty)
        #expect(model.$tags.added.isEmpty)
        #expect(model.$tags.removed.isEmpty)
    }

    @Test func commitDropsDeletedLinks() {
        var model = saved([a, b])
        model.tags = [b]
        model.$tags.commit(keyPath: "Note.tags", from: note)
        #expect(model.$tags.links == [Relationship(keyPath: "Note.tags", from: note, to: b, order: 1)])
    }

    // MARK: Orders

    @Test func newLinksAreNumberedInOrder() {
        #expect(saves(Note(tags: [a, b, c])) == [a: 0, b: 1, c: 2])
    }

    @Test func fetchedLinksSortByOrder() {
        let model = fetched(a: 4, b: 0, c: 2)
        #expect(model.tags == [b, c, a])
        #expect(model.$tags.links.map(\.order) == [0, 2, 4])
        #expect(model.$tags.added.isEmpty)
        #expect(saves(model).isEmpty)
    }

    @Test func deletesLeaveTheOtherOrdersAlone() {
        var model = saved([a, b, c])
        model.tags = [a, c]
        #expect(saves(model).isEmpty)
        #expect(model.$tags.changes(keyPath: "Note.tags", from: note).delete.count == 1)
    }

    @Test func appendWritesOneLinkAfterTheLast() {
        var model = fetched(a: 0, c: 5)
        model.tags.append(b)
        #expect(saves(model) == [b: 6])
    }

    @Test func insertWritesTheLinksThatNoLongerSort() {
        var model = saved([a, c])
        model.tags = [a, b, c]
        #expect(saves(model) == [b: 1, c: 2])
    }

    @Test func moveKeepsOrdersThatStillIncrease() {
        var model = saved([a, b, c])
        model.tags = [b, c, a]
        #expect(saves(model) == [a: 3])
    }

    // MARK: Action

    @Test func actionDefaultsToNone() {
        #expect(Note().$tags.action == .none)
    }

    @Test func encodesTheActionOnlyWhenItIsNotNone() throws {
        #expect(try JSONRepresentation(Note(tags: [a]))["tags"]?["action"] == nil)
        let model = Cascade(tags: [a])
        #expect(try JSONRepresentation(model)["tags"]?["action"] == "deleteSelf")
        let decoded = try JSONDecoder().decode(Cascade.self, from: JSONEncoder().encode(model))
        #expect(decoded.$tags.action == .deleteSelf)
        #expect(decoded == model)
    }

    @Test func fetchedRelationshipsTakeTheAction() {
        let model = References<Tag>([], from: note, action: .deleteSelf)
        #expect(model.action == .deleteSelf)
    }

    // MARK: Inverse

    @Test func inverseNamesTheDeclaringKeyPath() {
        #expect(Label(id: a).$posts.inverse == "Post.labels")
        #expect(Post(id: a).$labels.inverse == nil)
    }

    @Test func inverseBuildsTheDeclaringSidesLink() {
        var label = Label(id: a)
        label.posts = [note]
        let changes = label.$posts.changes(keyPath: "Label.posts", from: a)
        #expect(changes.save == [Relationship(keyPath: "Post.labels", from: note, to: a, inverseOrder: 0)])
        var post = Post(id: note)
        post.labels = [a]
        #expect(post.$labels.changes(keyPath: "Post.labels", from: note).save.map(\.id) == changes.save.map(\.id))
    }

    @Test func eachSideWritesOnlyItsOwnOrder() {
        let shared = [Relationship(keyPath: "Post.labels", from: note, to: a, order: 3, inverseOrder: 0)]
        var label = Label(id: a)
        label.$posts = References(shared + [Relationship(keyPath: "Post.labels", from: b, to: a, order: 0, inverseOrder: 1)], from: a, inverse: "Post.labels")
        #expect(label.posts == [note, b])
        label.posts = [b, note]
        let saved = label.$posts.changes(keyPath: "Label.posts", from: a).save
        #expect(saved == [Relationship(keyPath: "Post.labels", from: note, to: a, order: 3, inverseOrder: 2)])
    }

    @Test func linksFromTheOtherSideSortLastAndArePlacedOnSave() {
        var model = fetched(a: 0, b: 1)
        model.$tags = References(model.$tags.links + [Relationship(keyPath: "Note.tags", from: note, to: c, inverseOrder: 0)], from: note)
        #expect(model.tags == [a, b, c])
        #expect(model.$tags.added.isEmpty)
        let saved = model.$tags.changes(keyPath: "Note.tags", from: note).save
        #expect(saved == [Relationship(keyPath: "Note.tags", from: note, to: c, order: 2, inverseOrder: 0)])
    }

    @Test func inverseRoundTrips() throws {
        var label = Label(id: a)
        label.posts = [note]
        let decoded = try JSONDecoder().decode(Label.self, from: JSONEncoder().encode(label))
        #expect(decoded == label)
        #expect(decoded.$posts.inverse == "Post.labels")
    }

    // MARK: Coding

    @Test func encodesOnlyTheIDsBeforeASave() throws {
        #expect(try json(Note(tags: [a])) == #"{"tags":{"ids":["00000000-0000-0000-0000-0000000000A1"]}}"#)
    }

    @Test func encodesSavedLinksWithoutRepeatingTheIDs() throws {
        let json = try JSONRepresentation(saved([a]))
        #expect(json["tags"]?["ids"] == nil)
        #expect(json["tags"]?["links"]?[a.uuidString]?["order"] == 0)
    }

    @Test func leavesOutAnEmptyRelationship() throws {
        #expect(try json(Note()) == "{}")
        #expect(try JSONDecoder().decode(Note.self, from: Data("{}".utf8)).tags == [])
    }

    @Test func keepsARemovalOfTheLastID() throws {
        var model = saved([a])
        model.tags = []
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(model))
        #expect(decoded.$tags.removed == [a])
    }

    @Test func gapsSurviveALocalCopy() throws {
        var copy = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(fetched(a: 0, c: 5)))
        #expect(copy == fetched(a: 0, c: 5))
        copy.tags.append(b)
        #expect(saves(copy) == [b: 6])
    }

    @Test func roundTripsUnsavedChanges() throws {
        var model = saved([a])
        model.tags = []
        model.$tags.append(Tag(id: b, name: "Swift"))
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(model))
        #expect(decoded == model)
        #expect(decoded.$tags.inserted.map(\.name) == ["Swift"])
        #expect(decoded.$tags.removed == [a])
        #expect(try JSONRepresentation(model).decode(Note.self) == model)
    }
}
