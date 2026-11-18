import Foundation
import Testing
@testable import Serialization

private struct Tag: Codable, Identifiable {
    var id: UUID
    var notes: [UUID] = []
}

private struct Note: Codable, Hashable {
    @References(to: \Tag.notes) var tags: [UUID] = []

    /// The wrapper's storage is private, so only this file can read it.
    var tagsStorage: References<Tag>.Storage? { _tags.storage }
}

private struct Attachment: Codable, Identifiable {
    var id: UUID
}

private struct Folder: Codable, Hashable {
    @References(Attachment.self) var attachments: [UUID] = []

    var attachmentsStorage: References<Attachment>.Storage? { _attachments.storage }
}

private struct Post: Codable, Identifiable {
    var id: UUID
    @References(to: \Label.posts) var labels: [UUID] = []
}

private struct Label: Codable, Hashable, Identifiable {
    var id = UUID()
    @References(from: \Post.labels) var posts: [UUID] = []

    var postsStorage: References<Post>.Storage? { _posts.storage }
    var postsInverse: String? { get throws { try _posts.inverse } }
}

/// Stores `labels` under another coding key.
private struct Article: Codable, Identifiable {
    var id: UUID
    @References(to: \Sticker.articles) var labels: [UUID] = []

    enum CodingKeys: String, CodingKey {
        case id
        case labels = "stickers"
    }
}

private struct Sticker: Codable, Identifiable {
    var id = UUID()
    @References(from: \Article.labels) var articles: [UUID] = []

    var articlesInverse: String? { get throws { try _articles.inverse } }
}

private struct Match: Codable, Hashable {
    @References(Tag.self, action: .deleteSelf) var tags: [UUID] = []

    var tagsAction: RecordRepresentation.Reference.Action { _tags.action }
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
        #expect(decoded.tagsAction == .deleteSelf)
        #expect(try JSONDecoder().decode(Match.self, from: Data("{}".utf8)).tagsAction == .none)
    }

    @Test func initializerPicksTheStorage() {
        #expect(Folder().attachmentsStorage == .field)
        #expect(Note().tagsStorage == .links)
        #expect(Label().postsStorage == .inverse)
    }

    @Test func inverseNamesTheDeclaringCodingKey() throws {
        #expect(try Label().postsInverse == "Post.labels")
        #expect(try Sticker().articlesInverse == "Article.stickers")
    }

    @Test func decodedListHasNoStorageAndStillEqualsTheOriginal() throws {
        let model = Note(tags: [a, b])
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(model))
        #expect(decoded.tagsStorage == nil)
        #expect(decoded == model)
        #expect(try JSONDecoder().decode(Note.self, from: Data("{}".utf8)).tagsStorage == nil)
    }

    @Test func fieldAndLinksEncodeAlike() throws {
        #expect(try json(Folder(attachments: [a])) == #"{"attachments":[{"action":"none","recordName":"00000000-0000-0000-0000-0000000000A1"}]}"#)
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
