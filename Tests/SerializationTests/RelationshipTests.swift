import Foundation
import Testing
@testable import Serialization

@Suite struct RelationshipTests {

    private let note = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let tag = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test func putsTheDeclaringRecordFirst() {
        let link = Relationship(keyPath: "Note.tags", from: note, to: tag)
        #expect(link.keyPath == "Note.tags")
        #expect(link.references == [note, tag])
        #expect(link.order == nil)
        #expect(link.inverseOrder == nil)
    }

    @Test func orderIsNotPartOfTheID() {
        let link = Relationship(keyPath: "Note.tags", from: note, to: tag, order: 3)
        #expect(link.id == Relationship(keyPath: "Note.tags", from: note, to: tag).id)
        #expect(link != Relationship(keyPath: "Note.tags", from: note, to: tag))
    }

    @Test func differentKeyPathsAreDifferentLinks() {
        #expect(Relationship(keyPath: "Photo.tags", from: note, to: tag).id != Relationship(keyPath: "Note.tags", from: note, to: tag).id)
    }

    @Test func differentRecordsAreDifferentLinks() {
        #expect(Relationship(keyPath: "Note.tags", from: note, to: UUID()).id != Relationship(keyPath: "Note.tags", from: note, to: tag).id)
    }

    @Test func directionMatters() {
        #expect(Relationship(keyPath: "Person.follows", from: tag, to: note) != Relationship(keyPath: "Person.follows", from: note, to: tag))
    }

    @Test func keepsBothOrders() {
        let link = Relationship(keyPath: "Note.tags", from: note, to: tag, order: 1, inverseOrder: 7)
        #expect(link.order == 1)
        #expect(link.inverseOrder == 7)
    }

    @Test func symmetricRelationshipsSortTheirOrdersWithTheirIDs() {
        let link = Relationship(keyPath: "Person.friends", from: tag, to: note, order: 1, inverseOrder: 2, symmetric: true)
        #expect(link.references == [note, tag])
        #expect(link.order == 2)
        #expect(link.inverseOrder == 1)
    }

    @Test func symmetricRelationshipsSortByID() {
        let link = Relationship(keyPath: "Person.friends", from: tag, to: note, symmetric: true)
        #expect(link == Relationship(keyPath: "Person.friends", from: note, to: tag, symmetric: true))
        #expect(link.references == [note, tag])
    }

    @Test func targetIsTheOtherEnd() {
        let link = Relationship(keyPath: "Note.tags", from: note, to: tag)
        #expect(link.target(from: note) == tag)
        #expect(link.target(from: tag) == note)
    }

    @Test func idIsStable() {
        #expect(Relationship(keyPath: "Note.tags", from: note, to: tag).id == UUID(stableHashOf: "Note.tags|00000000-0000-0000-0000-00000000000A|00000000-0000-0000-0000-00000000000B"))
    }

    @Test func encodesLikeAModel() throws {
        let link = Relationship(keyPath: "Note.tags", from: note, to: tag, order: 2)
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
        let link = Relationship(keyPath: "Note.tags", from: note, to: tag)
        #expect(try JSONDecoder().decode(Relationship.self, from: JSONEncoder().encode(link)) == link)
        #expect(try JSONRepresentation(link).decode(Relationship.self) == link)
    }
}
