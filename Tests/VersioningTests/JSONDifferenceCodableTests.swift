import Foundation
import Testing
@testable import Versioning

@Suite struct JSONDifferenceCodableTests {
    @Test func encodesChangesInApplyOrder() throws {
        let old: JSONRepresentation = ["rooms": [["name": "A"]], "tags": ["x", "y", "z"]]
        let new: JSONRepresentation = ["rooms": [["name": "B"]], "tags": ["z", "x", "y"]]
        let difference = new.difference(from: old)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(difference), as: UTF8.self)
        #expect(text == """
            [{"associatedWith":0,"op":"remove","path":"$.tags[2]","value":"z"},\
            {"associatedWith":"name","op":"remove","path":"$.rooms[0].name","value":"A"},\
            {"associatedWith":"name","op":"insert","path":"$.rooms[0].name","value":"B"},\
            {"associatedWith":2,"op":"insert","path":"$.tags[0]","value":"z"}]
            """)
        #expect(try JSONDecoder().decode(JSONDifference.self, from: Data(text.utf8)) == difference)
    }

    @Test func randomDifferencesRoundTrip() throws {
        var generator = SplitMix64(seed: 7)
        for _ in 0..<200 {
            let old = JSONRepresentation.random(depth: 3, using: &generator)
            let difference = old.mutated(using: &generator).difference(from: old)
            let data = try JSONEncoder().encode(difference)
            #expect(try JSONDecoder().decode(JSONDifference.self, from: data) == difference)
        }
    }

    @Test func rejectsMalformedChanges() {
        for text in [
            #"[{"op":"move","path":"$.a","value":1}]"#,
            #"[{"op":"insert","path":"/a","value":1}]"#,
            #"[{"op":"insert","path":"$.a"}]"#,
            #"{"op":"insert","path":"$.a","value":1}"#,
        ] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(JSONDifference.self, from: Data(text.utf8)) }
        }
    }
}
