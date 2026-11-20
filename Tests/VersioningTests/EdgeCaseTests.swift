import Testing
@testable import Versioning

// MARK: - Helpers

private extension JSONRepresentation {
    /// `decode(_:)`, with a thrown error as `nil`.
    func value<T: Decodable>(_ type: T.Type) -> T? { try? decode(type) }
}

/// `JSONRepresentation(_:)` for values that always encode.
private func json(_ value: some Encodable) -> JSONRepresentation {
    try! JSONRepresentation(value)
}

// MARK: - Numbers

@Suite struct NumberGrammarTests {
    @Test(arguments: [
        "", "-", "+1", ".5", "1.", "01", "-01", "00", "1e", "1e+", "1E-",
        "0x10", "0x1p3", " 1", "1 ", "1_000", "1,5", "nan", "NaN", "inf", "Infinity", "--1", "1.2.3", "1e2e3",
    ])
    func rejectsMalformedNumberText(_ text: String) {
        #expect(JSONRepresentation.number(text).value(Int.self) == nil)
        #expect(JSONRepresentation.number(text).value(Double.self) == nil)
    }

    @Test(arguments: ["0", "-0", "7", "-7", "1234567890"])
    func acceptsIntegers(_ text: String) {
        #expect(JSONRepresentation.number(text).value(Int.self) != nil)
        #expect(JSONRepresentation.number(text).value(Double.self) != nil)
    }

    @Test(arguments: ["0.5", "-0.5", "1e2", "1E2", "1e+2", "1e-2", "-1.5e-3", "0e0", "1e07"])
    func acceptsFloatingPoint(_ text: String) {
        #expect(JSONRepresentation.number(text).value(Double.self) != nil)
    }

    @Test func textIsComparedNotNumericValue() {
        #expect(JSONRepresentation.number("1") != JSONRepresentation.number("1.0"))
        #expect(JSONRepresentation.number("100") != JSONRepresentation.number("1e2"))
    }
}

@Suite struct IntegerBoundaryTests {
    @Test func signedBoundsRoundTrip() {
        #expect(json(Int8.min).value(Int8.self) == .min)
        #expect(json(Int8.max).value(Int8.self) == .max)
        #expect(json(Int16.min).value(Int16.self) == .min)
        #expect(json(Int16.max).value(Int16.self) == .max)
        #expect(json(Int32.min).value(Int32.self) == .min)
        #expect(json(Int32.max).value(Int32.self) == .max)
        #expect(json(Int64.min).value(Int64.self) == .min)
        #expect(json(Int64.max).value(Int64.self) == .max)
        #expect(json(Int.min).value(Int.self) == .min)
        #expect(json(Int.max).value(Int.self) == .max)
    }

    @Test func unsignedBoundsRoundTrip() {
        #expect(json(UInt8.max).value(UInt8.self) == .max)
        #expect(json(UInt16.max).value(UInt16.self) == .max)
        #expect(json(UInt32.max).value(UInt32.self) == .max)
        #expect(json(UInt64.max).value(UInt64.self) == .max)
        #expect(json(UInt.max).value(UInt.self) == .max)
        #expect(JSONRepresentation.number("0").value(UInt64.self) == 0)
    }

    @Test func outOfRangeFails() {
        #expect(JSONRepresentation.number("128").value(Int8.self) == nil)
        #expect(JSONRepresentation.number("-129").value(Int8.self) == nil)
        #expect(JSONRepresentation.number("9223372036854775808").value(Int64.self) == nil)
        #expect(JSONRepresentation.number("-1").value(UInt8.self) == nil)
        #expect(JSONRepresentation.number("18446744073709551616").value(UInt64.self) == nil)
    }
}

@Suite struct FloatingPointEdgeTests {
    @Test(arguments: [
        0.0, 0.1, 1.0, -1.5, 123_456_789.125, 1e20, 1e-7, 1e300, -1e300,
        Double.pi, .greatestFiniteMagnitude, -Double.greatestFiniteMagnitude,
        .leastNormalMagnitude, .leastNonzeroMagnitude, .ulpOfOne,
    ])
    func finiteDoublesRoundTripExactly(_ value: Double) throws {
        let decoded = try #require(json(value).value(Double.self))
        #expect(decoded.bitPattern == value.bitPattern)
    }

    @Test func negativeZeroKeepsItsSign() throws {
        #expect(json(-0.0) == .number("-0"))
        let decoded = try #require(json(-0.0).value(Double.self))
        #expect(decoded.sign == .minus)
    }

    @Test func wholeNumbersDropTrailingZero() {
        #expect(json(8.0) == .number("8"))
        #expect(json(-8.0) == .number("-8"))
        #expect(json(Float(8)) == .number("8"))
    }

    @Test func nonFiniteValuesRoundTripAsStrings() throws {
        #expect(json(Double.nan) == .string("NaN"))
        #expect(json(Double.infinity) == .string("Infinity"))
        #expect(json(-Double.infinity) == .string("-Infinity"))

        #expect(try #require(json(Double.nan).value(Double.self)).isNaN)
        #expect(json(Double.infinity).value(Double.self) == .infinity)
        #expect(json(-Double.infinity).value(Double.self) == -Double.infinity)
        #expect(try #require(json(Float.nan).value(Float.self)).isNaN)
        #expect(json(Float.infinity).value(Float.self) == .infinity)
    }

    @Test func nonFiniteStringsAreCaseSensitive() {
        #expect(JSONRepresentation.string("nan").value(Double.self) == nil)
        #expect(JSONRepresentation.string("infinity").value(Double.self) == nil)
        #expect(JSONRepresentation.string("+Infinity").value(Double.self) == nil)
    }

    @Test func optionalNaNIsNotMistakenForNil() throws {
        let value: Double? = .nan
        let decoded = try #require(json(value).value(Double?.self))
        #expect(try #require(decoded).isNaN)
    }

    @Test func overflowFails() {
        #expect(JSONRepresentation.number("1e309").value(Double.self) == nil)
        #expect(JSONRepresentation.number("-1e309").value(Double.self) == nil)
        #expect(JSONRepresentation.number("1e39").value(Float.self) == nil)
    }

    @Test func floatRoundTrips() throws {
        for value: Float in [0.1, -2.5, .greatestFiniteMagnitude, .leastNonzeroMagnitude, 16_777_216] {
            let decoded = try #require(json(value).value(Float.self))
            #expect(decoded.bitPattern == value.bitPattern)
        }
    }
}

// MARK: - Strings and containers

@Suite struct StringAndContainerEdgeTests {
    @Test(arguments: ["", " ", "\"", "\\", "/", "\n\t\r", "\u{0}", "é", "e\u{301}", "👩‍👩‍👧", "日本語"])
    func stringsRoundTrip(_ value: String) {
        #expect(json(value).value(String.self) == value)
    }

    @Test func emptyContainersAreDistinct() {
        #expect(JSONRepresentation.array([]) != JSONRepresentation.object([]))
        #expect(([] as JSONRepresentation).value([Int].self) == [])
        #expect(([:] as JSONRepresentation).value([Int].self) == nil)
    }

    @Test func nestedArraysRoundTrip() {
        let value: [[Int?]] = [[1, nil], [], [3]]
        #expect(json(value).value([[Int?]].self) == value)
    }

    @Test func nestedOptionalDecodesNullAsOuterNil() throws {
        let decoded = try JSONRepresentation.null.decode(Int??.self)
        #expect(decoded == nil)
    }

    @Test func duplicateKeysAreKeptAndSubscriptReturnsFirst() {
        let json: JSONRepresentation = .object([(key: "a", value: 1), (key: "a", value: 2)])
        #expect(json["a"] == 1)
        guard case .object(let object) = json else {
            Issue.record("Expected an object")
            return
        }
        #expect(object.count == 2)
    }

    // Comparison, hashing and conversion recurse once per level. Swift Testing
    // runs tests on secondary threads, which have 512 KB stacks on macOS, and
    // 1,000 levels overflowed there in debug builds. 100 levels keeps a wide
    // margin. A future parser will cap depth the way JSONDecoder does.
    @Test func deepNestingCompareAndHash() {
        var a: JSONRepresentation = 0
        var b: JSONRepresentation = 0
        for _ in 0..<100 {
            a = ["next": a]
            b = ["next": b]
        }
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - JSONRepresentationSchema

@Suite struct JSONSchemaEdgeTests {
    @Test(arguments: [
        ["type": "string", "minLength": 1],
        ["type": "array", "items": ["type": "string"], "maxItems": 3],
        ["type": "object", "properties": [:], "additionalProperties": true],
        ["anyOf": [["type": "string"], ["type": "null"]], "description": "x"],
    ] as [JSONRepresentation])
    func rejectsUnknownKeywords(_ json: JSONRepresentation) {
        #expect(JSONSchema(json: json) == nil)
    }

    @Test func rejectsDuplicateKeys() {
        let duplicateKeyword: JSONRepresentation = .object([(key: "type", value: "string"), (key: "type", value: "integer")])
        let duplicateProperty: JSONRepresentation = [
            "type": "object",
            "properties": .object([(key: "a", value: ["type": "string"]), (key: "a", value: ["type": "string"])]),
        ]
        #expect(JSONSchema(json: duplicateKeyword) == nil)
        #expect(JSONSchema(json: duplicateProperty) == nil)
    }

    @Test func rejectsBadRequiredLists() {
        let unknownName: JSONRepresentation = ["type": "object", "properties": ["a": ["type": "string"]], "required": ["b"]]
        let repeatedName: JSONRepresentation = ["type": "object", "properties": ["a": ["type": "string"]], "required": ["a", "a"]]
        let notStrings: JSONRepresentation = ["type": "object", "properties": ["a": ["type": "string"]], "required": [1]]
        #expect(JSONSchema(json: unknownName) == nil)
        #expect(JSONSchema(json: repeatedName) == nil)
        #expect(JSONSchema(json: notStrings) == nil)
    }

    @Test(arguments: [
        ["anyOf": [["type": "null"], ["type": "string"]]],
        ["anyOf": [["type": "string"]]],
        ["anyOf": [["type": "string"], ["type": "null"], ["type": "integer"]]],
        ["type": ["string", "null"]],
        ["type": "date"],
        "string",
        [],
    ] as [JSONRepresentation])
    func rejectsShapesItDoesNotWrite(_ json: JSONRepresentation) {
        #expect(JSONSchema(json: json) == nil)
    }

    @Test func emptyRequiredListIsAccepted() {
        let json: JSONRepresentation = ["type": "object", "properties": ["a": ["type": "string"]], "required": []]
        #expect(JSONSchema(json: json) == .object([(key: "a", value: .optional(.string()))]))
    }

    @Test func deepNestingRoundTrips() {
        var schema: JSONSchema = .string()
        for depth in 0..<60 {
            schema = depth.isMultiple(of: 2)
                ? .array(.optional(schema))
                : .object([(key: "child", value: schema), (key: "note", value: .optional(.string()))])
        }
        #expect(JSONSchema(json: schema.body) == schema)
    }
}
