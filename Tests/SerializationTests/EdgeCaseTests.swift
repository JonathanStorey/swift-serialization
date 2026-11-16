import Testing
@testable import Serialization

// MARK: - Numbers

@Suite struct NumberGrammarTests {
    @Test(arguments: [
        "", "-", "+1", ".5", "1.", "01", "-01", "00", "1e", "1e+", "1E-",
        "0x10", "0x1p3", " 1", "1 ", "1_000", "1,5", "nan", "NaN", "inf", "Infinity", "--1", "1.2.3", "1e2e3",
    ])
    func rejectsMalformedNumberText(_ text: String) {
        #expect(Int(json: .number(text)) == nil)
        #expect(Double(json: .number(text)) == nil)
    }

    @Test(arguments: ["0", "-0", "7", "-7", "1234567890"])
    func acceptsIntegers(_ text: String) {
        #expect(Int(json: .number(text)) != nil)
        #expect(Double(json: .number(text)) != nil)
    }

    @Test(arguments: ["0.5", "-0.5", "1e2", "1E2", "1e+2", "1e-2", "-1.5e-3", "0e0", "1e07"])
    func acceptsFloatingPoint(_ text: String) {
        #expect(Double(json: .number(text)) != nil)
    }

    @Test func integersRejectFractionsAndExponents() {
        #expect(Int(json: .number("1.0")) == nil)
        #expect(Int(json: .number("1e2")) == nil)
    }

    @Test func textIsComparedNotNumericValue() {
        #expect(JSON.number("1") != JSON.number("1.0"))
        #expect(JSON.number("100") != JSON.number("1e2"))
    }
}

@Suite struct IntegerBoundaryTests {
    @Test func signedBoundsRoundTrip() {
        #expect(Int8(json: Int8.min.json) == .min)
        #expect(Int8(json: Int8.max.json) == .max)
        #expect(Int16(json: Int16.min.json) == .min)
        #expect(Int16(json: Int16.max.json) == .max)
        #expect(Int32(json: Int32.min.json) == .min)
        #expect(Int32(json: Int32.max.json) == .max)
        #expect(Int64(json: Int64.min.json) == .min)
        #expect(Int64(json: Int64.max.json) == .max)
        #expect(Int(json: Int.min.json) == .min)
        #expect(Int(json: Int.max.json) == .max)
    }

    @Test func unsignedBoundsRoundTrip() {
        #expect(UInt8(json: UInt8.max.json) == .max)
        #expect(UInt16(json: UInt16.max.json) == .max)
        #expect(UInt32(json: UInt32.max.json) == .max)
        #expect(UInt64(json: UInt64.max.json) == .max)
        #expect(UInt(json: UInt.max.json) == .max)
        #expect(UInt64(json: 0) == 0)
    }

    @Test func outOfRangeFails() {
        #expect(Int8(json: .number("128")) == nil)
        #expect(Int8(json: .number("-129")) == nil)
        #expect(Int64(json: .number("9223372036854775808")) == nil)
        #expect(UInt8(json: .number("-1")) == nil)
        #expect(UInt64(json: .number("18446744073709551616")) == nil)
    }
}

@Suite struct FloatingPointEdgeTests {
    @Test(arguments: [
        0.0, 0.1, 1.0, -1.5, 123_456_789.125, 1e20, 1e-7, 1e300, -1e300,
        Double.pi, .greatestFiniteMagnitude, -Double.greatestFiniteMagnitude,
        .leastNormalMagnitude, .leastNonzeroMagnitude, .ulpOfOne,
    ])
    func finiteDoublesRoundTripExactly(_ value: Double) throws {
        let decoded = try #require(Double(json: value.json))
        #expect(decoded.bitPattern == value.bitPattern)
    }

    @Test func negativeZeroKeepsItsSign() throws {
        #expect((-0.0).json == .number("-0"))
        let decoded = try #require(Double(json: (-0.0).json))
        #expect(decoded.sign == .minus)
    }

    @Test func wholeNumbersDropTrailingZero() {
        #expect((8.0).json == .number("8"))
        #expect((-8.0).json == .number("-8"))
        #expect(Float(8).json == .number("8"))
    }

    @Test func nonFiniteValuesRoundTripAsStrings() throws {
        #expect(Double.nan.json == .string("NaN"))
        #expect(Double.infinity.json == .string("Infinity"))
        #expect((-Double.infinity).json == .string("-Infinity"))

        #expect(try #require(Double(json: Double.nan.json)).isNaN)
        #expect(Double(json: Double.infinity.json) == .infinity)
        #expect(Double(json: (-Double.infinity).json) == -Double.infinity)
        #expect(try #require(Float(json: Float.nan.json)).isNaN)
        #expect(Float(json: Float.infinity.json) == .infinity)
    }

    @Test func nonFiniteStringsAreCaseSensitive() {
        #expect(Double(json: "nan") == nil)
        #expect(Double(json: "infinity") == nil)
        #expect(Double(json: "+Infinity") == nil)
    }

    @Test func optionalNaNIsNotMistakenForNil() throws {
        let value: Double? = .nan
        let decoded = try #require(Optional<Double>(json: value.json))
        #expect(try #require(decoded).isNaN)
    }

    @Test func overflowFails() {
        #expect(Double(json: .number("1e309")) == nil)
        #expect(Double(json: .number("-1e309")) == nil)
        #expect(Float(json: .number("1e39")) == nil)
    }

    @Test func underflowRoundsToZero() {
        #expect(Double(json: .number("1e-400")) == 0)
    }

    @Test func floatRoundTrips() throws {
        for value: Float in [0.1, -2.5, 3.4028235e38, 1.0e-45, 16_777_216] {
            let decoded = try #require(Float(json: value.json))
            #expect(decoded.bitPattern == value.bitPattern)
        }
    }
}

// MARK: - Strings and containers

@Suite struct StringAndContainerEdgeTests {
    @Test(arguments: ["", " ", "\"", "\\", "/", "\n\t\r", "\u{0}", "é", "e\u{301}", "👩‍👩‍👧", "日本語"])
    func stringsRoundTrip(_ value: String) {
        #expect(String(json: value.json) == value)
    }

    @Test func emptyContainersAreDistinct() {
        #expect(JSON.array([]) != JSON.object([]))
        #expect([Int](json: []) == [])
        #expect([Int](json: [:]) == nil)
    }

    @Test func nestedArraysRoundTrip() {
        let value: [[Int?]] = [[1, nil], [], [3]]
        #expect([[Int?]](json: value.json) == value)
    }

    @Test func nestedOptionalCollapsesNullToOuterNil() {
        let decoded = Optional<Int?>(json: .null)
        #expect(decoded == .some(.none))
    }

    @Test func duplicateKeysAreKeptAndSubscriptReturnsFirst() {
        let json: JSON = .object([(key: "a", value: 1), (key: "a", value: 2)])
        #expect(json["a"] == 1)
        guard case .object(let object) = json else {
            Issue.record("Expected an object")
            return
        }
        #expect(object.count == 2)
    }

    @Test func deepNestingCompareAndHash() {
        var a: JSON = 0
        var b: JSON = 0
        for _ in 0..<1_000 {
            a = ["next": a]
            b = ["next": b]
        }
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - JSONSchema

@Suite struct JSONSchemaEdgeTests {
    @Test(arguments: [
        ["type": "string", "minLength": 1],
        ["type": "array", "items": ["type": "string"], "maxItems": 3],
        ["type": "object", "properties": [:], "additionalProperties": false],
        ["anyOf": [["type": "string"], ["type": "null"]], "description": "x"],
    ] as [JSON])
    func rejectsUnknownKeywords(_ json: JSON) {
        #expect(JSONSchema(json: json) == nil)
    }

    @Test func rejectsDuplicateKeys() {
        let duplicateKeyword: JSON = .object([(key: "type", value: "string"), (key: "type", value: "integer")])
        let duplicateProperty: JSON = [
            "type": "object",
            "properties": .object([(key: "a", value: ["type": "string"]), (key: "a", value: ["type": "string"])]),
        ]
        #expect(JSONSchema(json: duplicateKeyword) == nil)
        #expect(JSONSchema(json: duplicateProperty) == nil)
    }

    @Test func rejectsBadRequiredLists() {
        let unknownName: JSON = ["type": "object", "properties": ["a": ["type": "string"]], "required": ["b"]]
        let repeatedName: JSON = ["type": "object", "properties": ["a": ["type": "string"]], "required": ["a", "a"]]
        let notStrings: JSON = ["type": "object", "properties": ["a": ["type": "string"]], "required": [1]]
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
    ] as [JSON])
    func rejectsShapesItDoesNotWrite(_ json: JSON) {
        #expect(JSONSchema(json: json) == nil)
    }

    @Test func emptyRequiredListIsAccepted() {
        let json: JSON = ["type": "object", "properties": ["a": ["type": "string"]], "required": []]
        #expect(JSONSchema(json: json) == .object([(key: "a", value: .optional(.string))]))
    }

    @Test func deepNestingRoundTrips() {
        var schema: JSONSchema = .string
        for depth in 0..<200 {
            schema = depth.isMultiple(of: 2)
                ? .array(.optional(schema))
                : .object([(key: "child", value: schema), (key: "note", value: .optional(.string))])
        }
        #expect(JSONSchema(json: schema.json) == schema)
    }
}
