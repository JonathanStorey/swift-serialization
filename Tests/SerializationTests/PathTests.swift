import Foundation
import Testing
@testable import Serialization

private typealias Path = JSONRepresentation.Path

@Suite struct PathTests {
    @Test func literalsAndCollection() {
        var path: Path = ["rooms", 0, "name"]
        #expect(path.count == 3)
        #expect(path[1] == .index(0))
        #expect(Array(path) == [.key("rooms"), .index(0), .key("name")])

        path.removeLast()
        path.append("title")
        #expect(path == ["rooms", 0, "title"])
        let extended: Path = path + [1]
        #expect(extended == ["rooms", 0, "title", 1])
        #expect(Path(path.dropLast(2)) == ["rooms"])
        #expect(Path().isEmpty)
    }

    @Test(arguments: [
        ([], "$"),
        (["rooms", 0, "name"], "$.rooms[0].name"),
        (["_x9", "Camel_Case"], "$._x9.Camel_Case"),
        (["first name"], "$['first name']"),
        (["0"], "$['0']"),
        ([0], "$[0]"),
        ([-1], "$[-1]"),
        ([""], "$['']"),
        (["9lives"], "$['9lives']"),
        (["café"], "$['café']"),
        (["a.b", "c[d]"], "$['a.b']['c[d]']"),
    ] as [(Path, String)])
    func descriptionRoundTrips(path: JSONRepresentation.Path, text: String) {
        #expect(path.description == text)
        #expect(Path(text) == path)
    }

    @Test func escapesRoundTrip() {
        let path: Path = ["it's", #"a\b"#, "line\nbreak", "tab\t", "\u{1}\u{1F}", "e\u{301}"]
        #expect(path.description == #"$['it\'s']['a\\b']['line\nbreak']['tab\t']['\u0001\u001f']['é']"#)
        #expect(Path(path.description) == path)
    }

    @Test func readsEscapesItDoesNotWrite() {
        #expect(Path(#"$['a\/b']"#) == ["a/b"])
        #expect(Path(#"$['éé']"#) == ["éé"])
        #expect(Path(#"$['😀']"#) == ["😀"])
        #expect(Path(#"$['x'].y[2]"#) == ["x", "y", 2])
    }

    @Test(arguments: [
        "", "rooms", "$.", "$..a", "$.9a", "$.a-b", "$[01]", "$[+1]", "$[-0]", "$[]", "$[0", "$['a'",
        "$['a']x", #"$["a"]"#, #"$['\q']"#, #"$['\u12']"#, #"$['\ud83d']"#, #"$['\ude00']"#,
        "$['tab\there']", "$ ", " $",
    ])
    func rejectsOtherText(_ text: String) {
        #expect(Path(text) == nil)
    }

    @Test func segmentIsACodingKey() {
        let index: Path.Segment = .index(2)
        #expect(index.stringValue == "Index 2")
        #expect(index.intValue == 2)
        #expect(Path.Segment(intValue: 2) == index)
        #expect(Path.Segment(stringValue: "a") == .key("a"))
        #expect(Path.Segment.key("a").intValue == nil)
    }

    @Test func subscriptFollowsThePath() {
        let json: JSONRepresentation = ["rooms": [["name": "A"], ["name": "B"]], "0": "zero"]
        #expect(json[path: []] == json)
        #expect(json[path: ["rooms", 1, "name"]] == "B")
        #expect(json[path: ["0"]] == "zero")
        #expect(json[path: [0]] == nil)
        #expect(json[path: ["rooms", 2]] == nil)
        #expect(json[path: ["rooms", "name"]] == nil)
        #expect(json[path: ["missing", 0]] == nil)
    }

    /// Paths and decoding errors describe locations the same way.
    @Test func matchesDecodingErrorCodingPath() throws {
        struct Room: Decodable { var name: String }
        struct Building: Decodable { var rooms: [Room] }
        let json: JSONRepresentation = ["rooms": [["name": "A"], ["name": 2]]]
        do {
            _ = try json.decode(Building.self)
            Issue.record("Expected a type mismatch")
        } catch DecodingError.typeMismatch(_, let context) {
            let path = Path(context.codingPath.map { key in key.intValue.map(Path.Segment.index) ?? .key(key.stringValue) })
            #expect(path == ["rooms", 1, "name"])
            #expect(json[path: path] == 2)
        }
    }
}
