import Foundation
import Testing
@testable import Serialization

@Suite struct DescriptionTests {
    @Test func compactText() {
        let value: JSONRepresentation = ["name": "Ada", "age": 36, "tags": ["swift", "json"], "active": true, "nickname": nil]
        #expect(value.description == #"{"name":"Ada","age":36,"tags":["swift","json"],"active":true,"nickname":null}"#)
    }

    @Test func emptyContainers() {
        #expect(JSONRepresentation.array([]).description == "[]")
        #expect(JSONRepresentation.object([]).description == "{}")
    }

    @Test func stringEscaping() {
        #expect(JSONRepresentation.string("a\"b\\c").description == #""a\"b\\c""#)
        #expect(JSONRepresentation.string("\n\r\t\u{8}\u{C}").description == #""\n\r\t\b\f""#)
        #expect(JSONRepresentation.string("\u{0}\u{1F}").description == #""\u0000\u001f""#)
        #expect(JSONRepresentation.string("a/b").description == #""a/b""#)
        #expect(JSONRepresentation.string("é👩‍👩‍👧").description == "\"é👩‍👩‍👧\"")
    }

    @Test func keysAreEscapedToo() {
        let value: JSONRepresentation = .object([(key: "a\"b", value: 1)])
        #expect(value.description == #"{"a\"b":1}"#)
    }

    @Test func schemaDescriptionIsSchemaText() {
        let schema: JSONSchema = .object([(key: "name", value: .string()), (key: "note", value: .optional(.string()))])
        #expect(schema.description == #"{"type":"object","properties":{"name":{"type":"string"},"note":{"type":"string"}},"required":["name"]}"#)
    }

    /// For values without floating-point numbers or control characters, and
    /// with keys already sorted, the description matches `JSONEncoder` output
    /// with `.sortedKeys` and `.withoutEscapingSlashes` byte for byte.
    @Test func matchesJSONEncoderForSortedValues() throws {
        let value: JSONRepresentation = [
            "a": [1, -2, 9_007_199_254_740_993],
            "b": ["c": true, "d": nil, "e": "x/y é"],
            "f": [],
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        #expect(String(decoding: data, as: UTF8.self) == value.description)
    }
}

@Suite struct CodableTests {
    @Test(arguments: [
        nil, true, false, 0, -7, 9_007_199_254_740_993, 0.1, -2.5, "", "Ada", "a/b\n",
        [], [1, "two", nil, [3]], ["a": 1], ["outer": ["inner": [true, false]]],
    ] as [JSONRepresentation])
    func roundTripsThroughFoundation(_ value: JSONRepresentation) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONRepresentation.self, from: data)
        #expect(decoded == value)
    }

    @Test func multiKeyObjectsKeepTheirContent() throws {
        let value: JSONRepresentation = ["z": 1, "a": 2, "m": ["y": 3, "b": 4]]
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONRepresentation.self, from: data)
        #expect(decoded == value)
    }

    @Test func largeUnsignedIntegersKeepFullPrecision() throws {
        let value = UInt64.max.json
        let decoded = try JSONDecoder().decode(JSONRepresentation.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
    }

    @Test func numberTextIsNormalized() throws {
        let decoded = try JSONDecoder().decode(JSONRepresentation.self, from: Data("[1e2, 1.50]".utf8))
        #expect(decoded == [100, 1.5])
    }

    @Test func invalidNumberTextFailsToEncode() {
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(JSONRepresentation.number("abc"))
        }
    }

    @Test func nonFiniteNumbersUseTheDecoderStrategy() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let decoded = try decoder.decode(JSONRepresentation.self, from: Data(#"["Infinity", "NaN", "Ada"]"#.utf8))
        #expect(decoded == ["Infinity", "NaN", "Ada"])
    }

    @Test func embedsInCodableModels() throws {
        struct Event: Codable, Equatable {
            var name: String
            var metadata: JSONRepresentation
        }
        let event = Event(name: "launch", metadata: ["attempt": 3, "tags": ["beta"]])
        let decoded = try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(event))
        #expect(decoded == event)
    }

    @Test(arguments: [
        JSONSchema.string(),
        .array(.optional(.integer())),
        .object([(key: "name", value: .string())]),
        .optional(.object([(key: "tags", value: .array(.string()))])),
    ])
    func schemaRoundTripsThroughFoundation(_ schema: JSONSchema) throws {
        let decoded = try JSONDecoder().decode(JSONSchema.self, from: JSONEncoder().encode(schema))
        #expect(decoded == schema)
    }

    @Test func schemaDecodingRejectsUnsupportedSchemas() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(JSONSchema.self, from: Data(#"{"type":"string","minLength":1}"#.utf8))
        }
    }
}
