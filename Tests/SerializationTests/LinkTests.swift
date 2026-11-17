import Foundation
import Testing
@testable import Serialization

@Suite struct LinkTests {
    typealias Link = RecordRepresentation.Link

    private let note = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let tag = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test func putsTheDeclaringRecordFirst() {
        let link = Link(keyPath: "Note.tags", from: note, to: tag)
        #expect(link.keyPath == "Note.tags")
        #expect(link.references == [note, tag])
        #expect(link.order == 0)
    }

    @Test func orderIsNotPartOfTheID() {
        let link = Link(keyPath: "Note.tags", from: note, to: tag, order: 3)
        #expect(link.id == Link(keyPath: "Note.tags", from: note, to: tag).id)
        #expect(link != Link(keyPath: "Note.tags", from: note, to: tag))
    }

    @Test func differentKeyPathsAreDifferentLinks() {
        #expect(Link(keyPath: "Photo.tags", from: note, to: tag).id != Link(keyPath: "Note.tags", from: note, to: tag).id)
    }

    @Test func differentRecordsAreDifferentLinks() {
        #expect(Link(keyPath: "Note.tags", from: note, to: UUID()).id != Link(keyPath: "Note.tags", from: note, to: tag).id)
    }

    @Test func directionMatters() {
        #expect(Link(keyPath: "Person.follows", from: tag, to: note) != Link(keyPath: "Person.follows", from: note, to: tag))
    }

    @Test func symmetricRelationshipsSortByID() {
        let link = Link(keyPath: "Person.friends", from: tag, to: note, symmetric: true)
        #expect(link == Link(keyPath: "Person.friends", from: note, to: tag, symmetric: true))
        #expect(link.references == [note, tag])
    }

    @Test func targetIsTheOtherEnd() {
        let link = Link(keyPath: "Note.tags", from: note, to: tag)
        #expect(link.target(from: note) == tag)
        #expect(link.target(from: tag) == note)
    }

    @Test func idIsStable() {
        #expect(Link(keyPath: "Note.tags", from: note, to: tag).id == UUID(stableHashOf: "Note.tags|00000000-0000-0000-0000-00000000000A|00000000-0000-0000-0000-00000000000B"))
    }

    @Test func encodesLikeAModel() throws {
        let link = Link(keyPath: "Note.tags", from: note, to: tag, order: 2)
        let json = try JSONRepresentation(link)
        #expect(json["id"] == nil)
        #expect(json["keyPath"] == "Note.tags")
        #expect(json["references"] == [
            ["recordName": .string(note.uuidString), "action": "none"],
            ["recordName": .string(tag.uuidString), "action": "none"],
        ])
        #expect(json["order"] == 2)
    }

    @Test func roundTrips() throws {
        let link = Link(keyPath: "Note.tags", from: note, to: tag)
        #expect(try JSONDecoder().decode(Link.self, from: JSONEncoder().encode(link)) == link)
        #expect(try JSONRepresentation(link).decode(Link.self) == link)
    }
}
