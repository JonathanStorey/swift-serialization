import Foundation
import Testing
@testable import Serialization

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

@Suite struct JSONPatchTests {
    @Test func patchText() {
        let old: JSONRepresentation = ["a/b": 1, "list": [1, 2], "gone": true]
        let new: JSONRepresentation = ["a/b": 2, "list": [1, 2, 3], "new~": nil]
        #expect(new.difference(from: old).jsonPatch.description == """
            [{"op":"test","path":"/gone","value":true},\
            {"op":"remove","path":"/gone"},\
            {"op":"test","path":"/a~1b","value":1},\
            {"op":"replace","path":"/a~1b","value":2},\
            {"op":"add","path":"/list/2","value":3},\
            {"op":"add","path":"/new~0","value":null}]
            """)
    }

    @Test func wholeDocumentReplacement() {
        let patch = JSONRepresentation(stringLiteral: "new").difference(from: [1]).jsonPatch
        #expect(patch.description == #"[{"op":"test","path":"","value":[1]},{"op":"replace","path":"","value":"new"}]"#)
    }

    /// An independent RFC 6902 applier must turn the old value into the new.
    @Test func randomPatchesApply() {
        var generator = SplitMix64(seed: 6902)
        for _ in 0..<400 {
            let old = JSONRepresentation.random(depth: 3, using: &generator)
            let new = Bool.random(using: &generator)
                ? old.mutated(using: &generator)
                : JSONRepresentation.random(depth: 3, using: &generator)
            let patch = new.difference(from: old).jsonPatch
            #expect(old.applyingJSONPatch(patch) == new, "\(old) → \(new)\n\(patch)")
        }
    }

    @Test func patchFailsOnTheWrongDocument() {
        let old: JSONRepresentation = ["a": 1]
        let patch = (["a": 2] as JSONRepresentation).difference(from: old).jsonPatch
        #expect(old.applyingJSONPatch(patch) == ["a": 2])
        #expect((["a": 5] as JSONRepresentation).applyingJSONPatch(patch) == nil)
    }
}

// MARK: - A minimal RFC 6902 applier

private extension JSONRepresentation {
    func applyingJSONPatch(_ patch: JSONRepresentation) -> JSONRepresentation? {
        guard case .array(let operations) = patch else { return nil }
        var document = self
        for operation in operations {
            guard case .string(let op)? = operation["op"], case .string(let pointer)? = operation["path"] else { return nil }
            let tokens = pointer.isEmpty ? [] : pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
                $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            }
            if op == "test" {
                guard document.resolving(tokens[...]) == operation["value"] else { return nil }
            } else {
                guard document.patch(tokens[...], op, operation["value"]) else { return nil }
            }
        }
        return document
    }

    func resolving(_ tokens: ArraySlice<String>) -> JSONRepresentation? {
        guard let token = tokens.first else { return self }
        switch self {
        case .object(let pairs): return pairs.first { $0.key == token }?.value.resolving(tokens.dropFirst())
        case .array(let elements): return Int(token).flatMap { elements.indices.contains($0) ? elements[$0] : nil }?.resolving(tokens.dropFirst())
        default: return nil
        }
    }

    mutating func patch(_ tokens: ArraySlice<String>, _ op: String, _ value: JSONRepresentation?) -> Bool {
        guard let token = tokens.first else {
            guard op == "add" || op == "replace", let value else { return false }
            self = value
            return true
        }
        let rest = tokens.dropFirst()
        switch self {
        case .object(var pairs):
            let position = pairs.firstIndex { $0.key == token }
            if !rest.isEmpty {
                guard let position, pairs[position].value.patch(rest, op, value) else { return false }
            } else {
                switch (op, position, value) {
                case ("remove", let position?, _): pairs.remove(at: position)
                case ("replace", let position?, let value?), ("add", let position?, let value?): pairs[position].value = value
                case ("add", nil, let value?): pairs.append((key: token, value: value))
                default: return false
                }
            }
            self = .object(pairs)
            return true
        case .array(var elements):
            guard let index = Int(token) else { return false }
            if !rest.isEmpty {
                guard elements.indices.contains(index), elements[index].patch(rest, op, value) else { return false }
            } else {
                switch (op, value) {
                case ("remove", _) where elements.indices.contains(index): elements.remove(at: index)
                case ("replace", let value?) where elements.indices.contains(index): elements[index] = value
                case ("add", let value?) where (0...elements.count).contains(index): elements.insert(value, at: index)
                default: return false
                }
            }
            self = .array(elements)
            return true
        default:
            return false
        }
    }
}
