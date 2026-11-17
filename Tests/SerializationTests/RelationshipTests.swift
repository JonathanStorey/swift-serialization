import Foundation
import Testing
@testable import Serialization

@Suite struct RelationshipTests {
    typealias Relationship = RecordRepresentation.Relationship

    private let note = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let tag = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test func isTheSameFromEitherSide() {
        let fromNote = Relationship("tags", note, "notes", tag)
        let fromTag = Relationship("notes", tag, "tags", note)
        #expect(fromNote == fromTag)
        #expect(fromNote.id == fromTag.id)
        #expect(fromNote.fields == ["notes", "tags"])
        #expect(fromNote.references == [tag, note])
    }

    @Test func differentFieldsAreDifferentLinks() {
        #expect(Relationship("authors", note, "notes", tag).id != Relationship("tags", note, "notes", tag).id)
    }

    @Test func differentRecordsAreDifferentLinks() {
        #expect(Relationship("tags", note, "notes", UUID()).id != Relationship("tags", note, "notes", tag).id)
    }

    @Test func selfRelationshipsSortByID() {
        let link = Relationship("friends", tag, "friends", note)
        #expect(link == Relationship("friends", note, "friends", tag))
        #expect(link.references == [note, tag])
    }

    @Test func idIsStable() {
        #expect(Relationship("tags", note, "notes", tag).id == UUID(stableHashOf: "notes|tags|00000000-0000-0000-0000-00000000000B|00000000-0000-0000-0000-00000000000A"))
    }

    @Test func encodesLikeAModel() throws {
        let link = Relationship("tags", note, "notes", tag)
        let json = try JSONRepresentation(link)
        #expect(json["id"] == .string(link.id.uuidString))
        #expect(json["fields"] == ["notes", "tags"])
        #expect(json["references"] == [
            ["recordName": .string(tag.uuidString), "action": "none"],
            ["recordName": .string(note.uuidString), "action": "none"],
        ])
        #expect(link.$references.action == .none)
    }

    @Test func roundTrips() throws {
        let link = Relationship("tags", note, "notes", tag)
        #expect(try JSONDecoder().decode(Relationship.self, from: JSONEncoder().encode(link)) == link)
        #expect(try JSONRepresentation(link).decode(Relationship.self) == link)
    }
}
