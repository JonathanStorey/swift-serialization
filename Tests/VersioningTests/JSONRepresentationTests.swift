import Foundation
import Testing
@testable import Versioning

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

@Suite struct EncodableAndDecodeTests {
    @Test func stringAndBool() throws {
        #expect(try JSONRepresentation("Ada" as String) == .string("Ada"))
        #expect(try JSONRepresentation(true as Bool) == .bool(true))
        #expect(try JSONRepresentation.string("Ada").decode(String.self) == "Ada")
        #expect(throws: DecodingError.self) { try JSONRepresentation.number("1").decode(String.self) }
    }

    @Test func integersKeepFullPrecision() throws {
        let big: Int64 = 9_007_199_254_740_993
        #expect(try JSONRepresentation(big) == .number("9007199254740993"))
        #expect(try JSONRepresentation.number("9007199254740993").decode(Int64.self) == big)
        #expect(throws: DecodingError.self) { try JSONRepresentation.number("256").decode(UInt8.self) }
        #expect(throws: DecodingError.self) { try JSONRepresentation.number("1.5").decode(Int.self) }
    }

    @Test func floatingPoint() throws {
        #expect(try JSONRepresentation.number("0.1").decode(Double.self) == 0.1)
        #expect(try JSONRepresentation.number("1e3").decode(Double.self) == 1000)
        #expect(try JSONRepresentation(0.1 as Double) == .number("0.1"))
        #expect(try JSONRepresentation(8.0 as Double) == .number("8"))
        #expect(try JSONRepresentation(Double.infinity) == .string("Infinity"))
        #expect(try JSONRepresentation(Double.nan) == .string("NaN"))
        #expect(throws: DecodingError.self) { try JSONRepresentation.number("nan").decode(Double.self) }
    }

    @Test func optional() throws {
        #expect(try JSONRepresentation.null.decode(Int?.self) == nil)
        #expect(try JSONRepresentation.number("3").decode(Int?.self) == 3)
        #expect(throws: DecodingError.self) { try JSONRepresentation.string("x").decode(Int?.self) }
        #expect(try JSONRepresentation(nil as Int?) == .null)
    }

    @Test func arrayFailsWhenAnyElementFails() throws {
        #expect(try JSONRepresentation([1, 2, 3] as [Int]).decode([Int].self) == [1, 2, 3])
        #expect(throws: DecodingError.self) { try ([1, "two", 3] as JSONRepresentation).decode([Int].self) }
    }

    @Test func keysFollowEncodeOrderAndMatchJSONEncoder() throws {
        struct Profile: Codable, Equatable {
            var zeta: String
            var alpha: Int
            var nested: [String: [Bool]]
            var missing: String?
        }
        let profile = Profile(zeta: "z", alpha: 1, nested: ["only": [true, false]], missing: nil)
        let json = try JSONRepresentation(profile)
        guard case .object(let object) = json else {
            Issue.record("Expected an object")
            return
        }
        #expect(object.map(\.key) == ["zeta", "alpha", "nested"])
        #expect(try json.decode(Profile.self) == profile)
    }

    /// Properties are declared in sorted order, so `.sortedKeys` output and
    /// encode order agree and the text can be compared byte for byte.
    @Test func textMatchesJSONEncoder() throws {
        struct Sorted: Encodable {
            var a = [0.5, 8, -2.25]
            var b = "x/y é"
            var c: Int? = nil
            var d = [true]
            var e = UInt64.max
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expected = String(decoding: try encoder.encode(Sorted()), as: UTF8.self)
        #expect(try JSONRepresentation(Sorted()).description == expected)
    }

    @Test func foundationTypesMatchJSONEncoder() throws {
        struct Stamped: Codable, Equatable {
            var created: Date
            var link: URL
            var payload: Data
            var amount: Decimal
            var id: UUID
        }
        let value = Stamped(
            created: Date(timeIntervalSinceReferenceDate: 1_000.5),
            link: URL(string: "https://example.com/a?b=c")!,
            payload: Data([1, 2, 255]),
            amount: Decimal(string: "12.5")!,
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        )
        let json = try JSONRepresentation(value)
        let foundation = try JSONDecoder().decode(JSONRepresentation.self, from: JSONEncoder().encode(value))
        #expect(json == foundation)
        #expect(try json.decode(Stamped.self) == value)
    }

    @Test func nestedContainersAndSuperEncoders() throws {
        class Base: Codable { var name = "base" }
        final class Derived: Base {
            var extra = 2
            private enum CodingKeys: String, CodingKey { case extra }
            override init() { super.init() }
            required init(from decoder: any Decoder) throws { fatalError("Not used") }
            override func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(extra, forKey: .extra)
                try super.encode(to: container.superEncoder())
            }
        }
        #expect(try JSONRepresentation(Derived()) == ["extra": 2, "super": ["name": "base"]])
    }

    @Test func repeatedKeysReplaceInPlace() throws {
        struct Twice: Encodable {
            enum CodingKeys: String, CodingKey { case a, b }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(1, forKey: .a)
                try container.encode(2, forKey: .b)
                try container.encode(3, forKey: .a)
            }
        }
        #expect(try JSONRepresentation(Twice()).description == #"{"a":3,"b":2}"#)
    }

    /// `JSONEncoder` keeps only the second value when a key is encoded twice,
    /// even when the first was an object.
    @Test func repeatedKeyReplacesEarlierObject() throws {
        struct Twice: Encodable {
            enum CodingKeys: String, CodingKey { case a }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(["x": 1], forKey: .a)
                try container.encode(["y": 2], forKey: .a)
            }
        }
        #expect(try JSONRepresentation(Twice()) == ["a": ["y": 2]])
        #expect(try matchesJSONEncoder(Twice()))
    }

    /// A nested container on a repeated key adds to what the key already holds.
    @Test func repeatedNestedContainerMerges() throws {
        struct Twice: Encodable {
            enum CodingKeys: String, CodingKey { case a, x, y }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var first = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .a)
                try first.encode(1, forKey: .x)
                var second = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .a)
                try second.encode(2, forKey: .y)
            }
        }
        #expect(try JSONRepresentation(Twice()) == ["a": ["x": 1, "y": 2]])
        #expect(try matchesJSONEncoder(Twice()))
    }

    @Test func nestedContainersInsideUnkeyedContainers() throws {
        class Base: Encodable { var name = "base" }
        struct Mixed: Encodable {
            enum CodingKeys: String, CodingKey { case list, label }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var list = container.nestedUnkeyedContainer(forKey: .list)
                try list.encode(1)
                try list.encodeNil()
                var keyed = list.nestedContainer(keyedBy: CodingKeys.self)
                try keyed.encode("inner", forKey: .label)
                var unkeyed = list.nestedUnkeyedContainer()
                try unkeyed.encode(true)
                try Base().encode(to: list.superEncoder())
                #expect(list.count == 5)
            }
        }
        let expected: JSONRepresentation = ["list": [1, nil, ["label": "inner"], [true], ["name": "base"]]]
        #expect(try JSONRepresentation(Mixed()) == expected)
        #expect(try matchesJSONEncoder(Mixed()))
    }

    /// `Int` keys become strings, and other keys turn the dictionary into an
    /// array of alternating keys and values, as with `JSONEncoder`.
    @Test func dictionaryKeys() throws {
        let byInt: [Int: String] = [1: "a", 2: "b"]
        #expect(try JSONRepresentation(byInt) == ["1": "a", "2": "b"])
        #expect(try JSONRepresentation(byInt).decode([Int: String].self) == byInt)
        #expect(try matchesJSONEncoder(byInt))

        let byDouble: [Double: String] = [1.5: "a"]
        #expect(try JSONRepresentation(byDouble) == [1.5, "a"])
        #expect(try JSONRepresentation(byDouble).decode([Double: String].self) == byDouble)
    }

    @Test func decimalNaNThrows() {
        struct Price: Encodable { var amount = Decimal.nan }
        #expect(throws: EncodingError.self) { try JSONRepresentation(Decimal.nan) }
        #expect(throws: EncodingError.self) { try JSONRepresentation(Price()) }
    }

    /// The standard library's default `Int128` overloads throw, so every
    /// container must implement them.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func int128InEveryContainer() throws {
        struct Wide: Encodable {
            var low = Int128.min
            var high = [UInt128.max]
            var single = Single()
        }
        struct Single: Encodable {
            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(Int128(1) << 100)
            }
        }
        let expected: JSONRepresentation = [
            "low": .number("-170141183460469231731687303715884105728"),
            "high": [.number("340282366920938463463374607431768211455")],
            "single": .number("1267650600228229401496703205376"),
        ]
        #expect(try JSONRepresentation(Wide()) == expected)
    }

    @Test func emptyEncodingThrows() {
        struct Nothing: Encodable { func encode(to encoder: any Encoder) throws {} }
        #expect(throws: EncodingError.self) { try JSONRepresentation(Nothing()) }
    }

    @Test func decodeRejectsWhatJSONDecoderWouldTolerate() {
        #expect(throws: DecodingError.self) { try JSONRepresentation.number(" 1").decode(Int.self) }
        #expect(throws: DecodingError.self) {
            try JSONRepresentation.object([(key: "a", value: 1), (key: "a", value: 2)]).decode([String: Int].self)
        }
    }
}

/// Whether `init(_:)` and `JSONEncoder` produce the same value, ignoring key
/// order.
private func matchesJSONEncoder(_ value: some Encodable) throws -> Bool {
    let foundation = try JSONDecoder().decode(JSONRepresentation.self, from: JSONEncoder().encode(value))
    return try JSONRepresentation(value) == foundation
}
