import Testing
@testable import Serialization

// Objects and schema properties are stored in order but compare and hash
// without regard to it, like `Dictionary`. Arrays stay ordered.

@Suite struct JSONRepresentationEqualityTests {
    @Test(arguments: [
        (["a": 1, "b": 2], ["b": 2, "a": 1]),
        (["a": ["x": 1, "y": 2]], ["a": ["y": 2, "x": 1]]),
        ([["a": 1, "b": 2], ["c": 3]], [["b": 2, "a": 1], ["c": 3]]),
        (["outer": ["mid": ["z": nil, "a": [true, ["q": 1, "p": 2]]]]], ["outer": ["mid": ["a": [true, ["p": 2, "q": 1]], "z": nil]]]),
        ([:], [:]),
    ] as [(JSONRepresentation, JSONRepresentation)])
    func reorderedObjectsAreEqualAndHashEqually(_ pair: (JSONRepresentation, JSONRepresentation)) {
        let (lhs, rhs) = pair
        #expect(lhs == rhs)
        #expect(rhs == lhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test(arguments: [
        ([1, 2], [2, 1]),
        ([["a": 1], ["b": 2]], [["b": 2], ["a": 1]]),
        (["a": 1], ["a": 2]),
        (["a": 1], ["b": 1]),
        (["a": 1], ["a": 1, "b": 2]),
        (["a": ["x": [1, 2]]], ["a": ["x": [2, 1]]]),
        (["a": nil], [:]),
        (["a": 1], [["a", 1]]),
        (.object([(key: "a", value: 1), (key: "a", value: 1)]), ["a": 1]),
    ] as [(JSONRepresentation, JSONRepresentation)])
    func differentContentIsNotEqual(_ pair: (JSONRepresentation, JSONRepresentation)) {
        let (lhs, rhs) = pair
        #expect(lhs != rhs)
        #expect(rhs != lhs)
    }

    @Test func everyPermutationIsEqualAndHashesEqually() {
        let pairs: JSONRepresentation.Object = [(key: "a", value: 1), (key: "b", value: "two"), (key: "c", value: [3]), (key: "d", value: ["e": nil])]
        let values = pairs.permutations().map { JSONRepresentation.object($0) }
        #expect(values.count == 24)
        #expect(values.allSatisfy { $0 == values[0] })
        #expect(Set(values.map(\.hashValue)).count == 1)
        #expect(Set(values).count == 1)
    }

    @Test func storedOrderIsUnchangedByEquality() {
        let first: JSONRepresentation = ["a": 1, "b": 2]
        let second: JSONRepresentation = ["b": 2, "a": 1]
        #expect(first == second)
        #expect(first.description == #"{"a":1,"b":2}"#)
        #expect(second.description == #"{"b":2,"a":1}"#)
    }

    @Test func worksAsDictionaryKey() {
        var counts: [JSONRepresentation: Int] = [:]
        counts[["a": 1, "b": 2], default: 0] += 1
        counts[["b": 2, "a": 1], default: 0] += 1
        #expect(counts.count == 1)
        #expect(counts[["a": 1, "b": 2]] == 2)
    }

    @Test func duplicateKeysCompareInRelativeOrder() {
        let first: JSONRepresentation = .object([(key: "a", value: 1), (key: "b", value: 0), (key: "a", value: 2)])
        let moved: JSONRepresentation = .object([(key: "b", value: 0), (key: "a", value: 1), (key: "a", value: 2)])
        let swapped: JSONRepresentation = .object([(key: "a", value: 2), (key: "b", value: 0), (key: "a", value: 1)])
        #expect(first == moved)
        #expect(first != swapped)
    }
}

@Suite struct JSONSchemaEqualityTests {
    @Test(arguments: [
        (.object([(key: "a", value: .string), (key: "b", value: .integer)]),
         .object([(key: "b", value: .integer), (key: "a", value: .string)])),
        (.array(.object([(key: "x", value: .boolean), (key: "y", value: .optional(.number))])),
         .array(.object([(key: "y", value: .optional(.number)), (key: "x", value: .boolean)]))),
        (.optional(.object([(key: "inner", value: .object([(key: "p", value: .string), (key: "q", value: .null)])), (key: "n", value: .number)])),
         .optional(.object([(key: "n", value: .number), (key: "inner", value: .object([(key: "q", value: .null), (key: "p", value: .string)]))]))),
        (.object([]), .object([])),
    ] as [(JSONSchema, JSONSchema)])
    func reorderedPropertiesAreEqualAndHashEqually(_ pair: (JSONSchema, JSONSchema)) {
        let (lhs, rhs) = pair
        #expect(lhs == rhs)
        #expect(rhs == lhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test(arguments: [
        (.object([(key: "a", value: .string)]), .object([(key: "a", value: .optional(.string))])),
        (.object([(key: "a", value: .string)]), .object([(key: "b", value: .string)])),
        (.object([(key: "a", value: .string)]), .object([(key: "a", value: .string), (key: "b", value: .string)])),
        (.integer, .number),
        (.array(.string), .array(.optional(.string))),
        (.optional(.optional(.string)), .optional(.string)),
        (.object([]), .array(.null)),
    ] as [(JSONSchema, JSONSchema)])
    func differentSchemasAreNotEqual(_ pair: (JSONSchema, JSONSchema)) {
        let (lhs, rhs) = pair
        #expect(lhs != rhs)
        #expect(rhs != lhs)
    }

    @Test func everyPermutationIsEqualAndHashesEqually() {
        let properties: JSONSchema.Properties = [(key: "a", value: .string), (key: "b", value: .optional(.integer)), (key: "c", value: .array(.number)), (key: "d", value: .boolean)]
        let schemas = properties.permutations().map { JSONSchema.object($0) }
        #expect(schemas.count == 24)
        #expect(schemas.allSatisfy { $0 == schemas[0] })
        #expect(Set(schemas).count == 1)
    }

    @Test func equalSchemasCanWriteDifferentText() {
        let first: JSONSchema = .object([(key: "a", value: .string), (key: "b", value: .string)])
        let second: JSONSchema = .object([(key: "b", value: .string), (key: "a", value: .string)])
        #expect(first == second)
        #expect(first.json == second.json)
        #expect(first.description != second.description)
    }
}

private extension Array {
    /// Every ordering of the elements.
    func permutations() -> [[Element]] {
        guard count > 1 else { return [self] }
        return indices.flatMap { index in
            var rest = self
            let first = rest.remove(at: index)
            return rest.permutations().map { [first] + $0 }
        }
    }
}
