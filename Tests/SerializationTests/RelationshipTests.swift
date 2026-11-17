import Foundation
import Testing
@testable import Serialization

@Suite struct RelationshipTests {
    typealias Relationship = RecordRepresentation.Relationship
    typealias Endpoint = RecordRepresentation.Relationship.Endpoint

    private let n = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let t = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private var note: Endpoint { Endpoint(recordType: "Note", field: "tags", id: n) }
    private var tag: Endpoint { Endpoint(recordType: "Tag", field: "notes", id: t) }

    @Test func isTheSameFromEitherSide() {
        let fromNote = Relationship(note, tag)
        let fromTag = Relationship(tag, note)
        #expect(fromNote == fromTag)
        #expect(fromNote.id == fromTag.id)
        #expect(fromNote.first == note)
        #expect(fromNote.second == tag)
    }

    @Test func namesTheFieldPair() {
        #expect(Relationship(tag, note).name == "Note.tags|Tag.notes")
    }

    @Test func differentFieldsAreDifferentRelationships() {
        let authors = Relationship(Endpoint(recordType: "Note", field: "authors", id: n), Endpoint(recordType: "Tag", field: "notes", id: t))
        #expect(authors.name != Relationship(note, tag).name)
        #expect(authors.id != Relationship(note, tag).id)
    }

    @Test func differentRecordsAreDifferentLinks() {
        let other = Endpoint(recordType: "Tag", field: "notes", id: UUID())
        let link = Relationship(note, other)
        #expect(link.name == Relationship(note, tag).name)
        #expect(link.id != Relationship(note, tag).id)
    }

    @Test func selfRelationshipsOrderByID() {
        let a = Endpoint(recordType: "Person", field: "friends", id: n)
        let b = Endpoint(recordType: "Person", field: "friends", id: t)
        #expect(Relationship(b, a) == Relationship(a, b))
        #expect(Relationship(b, a).first == a)
        #expect(Relationship(a, b).name == "Person.friends|Person.friends")
    }

    @Test func idIsStable() {
        #expect(Relationship(note, tag).id == UUID(stableHashOf: "Note.tags|Tag.notes|00000000-0000-0000-0000-00000000000A|00000000-0000-0000-0000-00000000000B"))
    }

    @Test func roundTripsAndRestoresOrder() throws {
        let link = Relationship(note, tag)
        #expect(try JSONDecoder().decode(Relationship.self, from: JSONEncoder().encode(link)) == link)

        // Endpoints written out of order decode in canonical order.
        let swapped: JSONRepresentation = try ["first": JSONRepresentation(tag), "second": JSONRepresentation(note)]
        #expect(try swapped.decode(Relationship.self) == link)
    }
}
