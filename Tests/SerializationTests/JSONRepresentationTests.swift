import Testing
@testable import Serialization

@Suite struct JSONLiteralTests {
    @Test func scalars() {
        #expect((nil as JSONRepresentation) == .null)
        #expect((true as JSONRepresentation) == .bool(true))
        #expect((36 as JSONRepresentation) == .number("36"))
        #expect((9.5 as JSONRepresentation) == .number("9.5"))
        #expect((8.0 as JSONRepresentation) == .number("8"))
        #expect(("Ada" as JSONRepresentation) == .string("Ada"))
    }

    @Test func multipleProperties() {
        let person: JSONRepresentation = ["name": "Ada", "age": 36, "active": true, "nickname": nil]
        let expected: JSONRepresentation = .object([
            (key: "name", value: .string("Ada")),
            (key: "age", value: .number("36")),
            (key: "active", value: .bool(true)),
            (key: "nickname", value: .null),
        ])
        #expect(person == expected)
    }

    @Test func nested() {
        let project: JSONRepresentation = [
            "id": 7,
            "owner": ["name": "Ada", "address": ["city": "London", "zip": "N1"]],
            "tags": ["swift", "json"],
            "scores": [9.5, 8, 10],
        ]
        #expect(project["owner"]?["address"]?["city"] == .string("London"))
        #expect(project["tags"]?[1] == .string("json"))
        #expect(project["scores"]?[0] == .number("9.5"))
    }

    @Test func objectKeysKeepInsertionOrder() {
        let json: JSONRepresentation = ["zeta": 1, "alpha": 2, "mid": 3]
        guard case .object(let object) = json else {
            Issue.record("Expected an object")
            return
        }
        #expect(object.map(\.key) == ["zeta", "alpha", "mid"])
    }
}

@Suite struct JSONHashableTests {
    @Test func objectEqualityIgnoresKeyOrder() {
        let first: JSONRepresentation = ["a": 1, "b": ["c": true, "d": nil]]
        let second: JSONRepresentation = ["b": ["d": nil, "c": true], "a": 1]
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(Set([first, second]).count == 1)
    }

    @Test func storedOrderIsStillKept() {
        let first: JSONRepresentation = ["a": 1, "b": 2]
        let second: JSONRepresentation = ["b": 2, "a": 1]
        #expect(first == second)
        #expect(first.description != second.description)
    }

    @Test func objectsWithDifferentContentAreNotEqual() {
        #expect((["a": 1] as JSONRepresentation) != ["a": 2])
        #expect((["a": 1] as JSONRepresentation) != ["b": 1])
        #expect((["a": 1] as JSONRepresentation) != ["a": 1, "b": 2])
        #expect(JSONRepresentation.object([(key: "a", value: 1), (key: "a", value: 1)]) != ["a": 1])
    }

    @Test func arraysStayOrdered() {
        #expect(([1, 2] as JSONRepresentation) != [2, 1])
    }

    @Test func differentKindsAreNotEqual() {
        #expect(JSONRepresentation.string("1") != JSONRepresentation.number("1"))
        #expect(JSONRepresentation.array([]) != JSONRepresentation.object([]))
    }

    @Test func equalValuesHashEqually() {
        let values: Set<JSONRepresentation> = [["a": [1, 2]], ["a": [1, 2]], ["a": [2, 1]]]
        #expect(values.count == 2)
    }
}

@Suite struct JSONSubscriptTests {
    @Test func missingKeyOrWrongKindIsNil() {
        let json: JSONRepresentation = ["a": [1, 2]]
        #expect(json["b"] == nil)
        #expect(json[0] == nil)
        #expect(json["a"]?["x"] == nil)
    }

    @Test func outOfBoundsIndexIsNil() {
        let json: JSONRepresentation = [1, 2]
        #expect(json[2] == nil)
        #expect(json[-1] == nil)
    }
}

@Suite struct JSONRepresentableTests {
    @Test func stringAndBool() {
        #expect(String(json: "Ada") == "Ada")
        #expect(Bool(json: true) == true)
        #expect(String(json: 1) == nil)
        #expect("Ada".json == .string("Ada"))
    }

    @Test func integersKeepFullPrecision() {
        let big: Int64 = 9_007_199_254_740_993
        #expect(big.json == .number("9007199254740993"))
        #expect(Int64(json: .number("9007199254740993")) == big)
        #expect(UInt8(json: .number("256")) == nil)
        #expect(Int(json: .number("1.5")) == nil)
    }

    @Test func floatingPoint() {
        #expect(Double(json: .number("0.1")) == 0.1)
        #expect(Double(json: .number("1e3")) == 1000)
        #expect((0.1).json == .number("0.1"))
        #expect((8.0).json == .number("8"))
        #expect(Double.infinity.json == .string("Infinity"))
        #expect(Double.nan.json == .string("NaN"))
        #expect(Double(json: .number("nan")) == nil)
    }

    @Test func optional() {
        #expect(Optional<Int>(json: .null) == .some(nil))
        #expect(Optional<Int>(json: 3) == .some(3))
        #expect(Optional<Int>(json: "x") == nil)
        #expect((nil as Int?).json == .null)
    }

    @Test func arrayFailsWhenAnyElementFails() {
        #expect([Int](json: [1, 2, 3]) == [1, 2, 3])
        #expect([Int](json: [1, "two", 3]) == nil)
        #expect([1, 2].json == [1, 2])
    }
}
