import Foundation
import Testing
@testable import Versioning

private struct Count: RawRepresentable, Codable, Equatable, Mergeable {
    var rawValue: Int

    func merging(with theirs: Count, from base: Count) throws(MergeConflict) -> Count {
        try merging(with: theirs, from: base, using: .rawValue(.sum()))
    }
}

private struct Note: Codable, Equatable {
    var title = "A"
    var body = "B"
    var views = Count(rawValue: 1)
}

@Suite struct JSONMergeAsTypeTests {
    @Test func aKeyANewerVersionAddedIsKept() throws {
        let base: JSONRepresentation = ["title": "A", "body": "B", "views": 1]
        let ours: JSONRepresentation = ["title": "Ours", "body": "B", "views": 1]
        let theirs: JSONRepresentation = ["title": "A", "body": "B", "views": 1, "color": "red"]
        let merged = try ours.merging(theirs, base: base, as: Note.self)
        #expect(merged[["color"]] == "red")
        #expect(try merged.decode(Note.self) == Note(title: "Ours"))
    }

    @Test func aNestedUndeclaredKeyIsKept() throws {
        struct Place: Codable, Equatable { var city = "Oslo" }
        struct Listing: Codable, Equatable { var title = "A"; var place = Place() }
        let base: JSONRepresentation = ["title": "A", "place": ["city": "Oslo"]]
        let ours: JSONRepresentation = ["title": "Ours", "place": ["city": "Oslo"]]
        let theirs: JSONRepresentation = ["title": "A", "place": ["city": "Bergen", "zip": "5003"]]
        let merged = try ours.merging(theirs, base: base, as: Listing.self)
        #expect(merged[["place", "zip"]] == "5003")
        #expect(try merged.decode(Listing.self) == Listing(title: "Ours", place: Place(city: "Bergen")))
    }

    @Test func aBaseThatDoesNotDecodeIsStillTheAncestor() throws {
        let base: JSONRepresentation = ["title": "A"]  // written before `body` and `views` existed
        let ours: JSONRepresentation = ["title": "A", "body": "B", "views": 1]
        let theirs: JSONRepresentation = ["title": "Theirs", "body": "B", "views": 1]
        #expect(try ours.merging(theirs, base: base, as: Note.self).decode(Note.self) == Note(title: "Theirs"))
    }

    @Test func declaredPropertiesMergeByTheirTypesRules() throws {
        let base: JSONRepresentation = ["title": "A", "body": "B", "views": 3]
        let ours: JSONRepresentation = ["title": "A", "body": "B", "views": 5]
        let theirs: JSONRepresentation = ["title": "A", "body": "B", "views": 4, "color": "red"]
        let merged = try ours.merging(theirs, base: base, as: Note.self)
        #expect(try merged.decode(Note.self).views == Count(rawValue: 6))
        #expect(merged[["color"]] == "red")
    }

    @Test func aConflictAtAnUndeclaredKeyThrowsAtItsPath() throws {
        let base: JSONRepresentation = ["title": "A", "body": "B", "views": 1, "color": "red"]
        let ours: JSONRepresentation = ["title": "A", "body": "B", "views": 1, "color": "blue"]
        let theirs: JSONRepresentation = ["title": "A", "body": "B", "views": 1, "color": "green"]
        #expect(throws: MergeConflict(at: [["color"]])) { try ours.merging(theirs, base: base, as: Note.self) }
        #expect(try ours.merging(theirs, base: base, as: Note.self, favoring: .theirs)[["color"]] == "green")
    }

    @Test func aResultThatDoesNotDecodeThrows() {
        let base: JSONRepresentation = ["title": "A", "body": "B", "views": 1]
        let theirs: JSONRepresentation = ["title": 5, "body": "B", "views": 1]
        #expect(throws: MergeConflict.self) { try base.merging(theirs, base: base, as: Note.self) }
        #expect(throws: MergeConflict.self) { try base.merging(theirs, base: base, as: Note.self, favoring: .ours) }
    }
}
