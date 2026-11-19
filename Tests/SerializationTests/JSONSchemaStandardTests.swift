import Foundation
import Testing
@testable import Serialization

// Checks that every schema is written in JSON Schema draft 2020-12, the
// dialect its documents declare with "$schema". The keyword test below runs
// everywhere. In CI, `JSON_SCHEMA_FIXTURES` names a folder, and the fixture
// test writes each schema there with values that must and must not validate,
// so `Scripts/validate-json-schemas.py` can check them with an independent
// 2020-12 validator.

private enum Shade: String, Codable, CaseIterable { case light, dark }
private enum Rank: UInt8, Codable, CaseIterable { case low = 1, high = 9 }

private struct Line: Codable { var text: String; var count: Int }

private struct Sample: Codable {
    var id: UUID
    var link: URL
    var photo: Data
    var tags: Set<String>
    var counts: [String: Int]
    var small: Int8
    var flag: UInt8?
    var big: UInt64
    var whole: Int
    var ratio: Double
    var isOn: Bool
    var created: Date
    var shade: Shade
    var rank: Rank?
    var lines: [Line]
    var byName: [String: Line]
    var groups: Set<[Int]>
    var note: String?
}

private let sample = Sample(
    id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
    link: URL(string: "https://example.com/a?b=c")!,
    photo: Data([0, 1, 254, 255]),
    tags: ["a", "b"],
    counts: ["x": 1, "y": -2],
    small: -128,
    flag: 255,
    big: .max,
    whole: .min,
    ratio: 0.5,
    isOn: true,
    created: Date(timeIntervalSinceReferenceDate: 812_345_678.25),
    shade: .dark,
    rank: .high,
    lines: [Line(text: "t", count: 2)],
    byName: ["one": Line(text: "u", count: 3)],
    groups: [[1, 2], [2, 1]],
    note: "n"
)

/// The keywords of the 2020-12 vocabularies this library writes, with a
/// check of each value's JSON type, as the 2020-12 meta-schema states it.
private let keywords: [String: @Sendable (JSONRepresentation) -> Bool] = [
    "$schema": { $0 == JSONSchema.dialect },
    "type": { ["null", "boolean", "integer", "number", "string", "array", "object"].contains($0.stringValue ?? "") },
    "enum": { $0.arrayValue != nil },
    "minimum": { $0.doubleValue != nil },
    "maximum": { $0.doubleValue != nil },
    "format": { $0.stringValue != nil },
    "contentEncoding": { $0.stringValue != nil },
    "items": { $0.isSchema },
    "uniqueItems": { if case .bool = $0 { true } else { false } },
    "properties": { if case .object(let pairs) = $0 { pairs.allSatisfy(\.value.isSchema) } else { false } },
    "required": { value in
        guard let names = value.arrayValue?.compactMap(\.stringValue), names.count == value.arrayValue?.count else { return false }
        return Set(names).count == names.count
    },
    "additionalProperties": { if case .bool = $0 { true } else { $0.isSchema } },
    "anyOf": { value in
        guard let options = value.arrayValue, !options.isEmpty else { return false }
        return options.allSatisfy(\.isSchema)
    },
]

private extension JSONRepresentation {
    /// An object, as every schema this library writes is.
    var isSchema: Bool {
        if case .object = self { true } else { false }
    }

    /// Every key of every schema in the document, checked against
    /// `keywords`. Keys under `properties` are property names, not keywords.
    func unknownKeywords(isRoot: Bool = true) -> [String] {
        guard case .object(let pairs) = self else { return ["<not an object>"] }
        return pairs.flatMap { key, value -> [String] in
            guard let check = keywords[key], key != "$schema" || isRoot else { return [key] }
            guard check(value) else { return ["\(key) (malformed)"] }
            switch key {
            case "items", "additionalProperties" where value.isSchema:
                return value.unknownKeywords(isRoot: false)
            case "properties":
                guard case .object(let properties) = value else { return [] }
                return properties.flatMap { $0.value.unknownKeywords(isRoot: false) }
            case "anyOf":
                return (value.arrayValue ?? []).flatMap { $0.unknownKeywords(isRoot: false) }
            default:
                return []
            }
        }
    }
}

private func json(_ value: some Encodable) throws -> JSONRepresentation {
    try JSONDecoder().decode(JSONRepresentation.self, from: JSONEncoder().encode(value))
}

/// Schemas that cover every case and keyword.
private let corpus: [JSONSchema] = [
    .null, .boolean, .number, .integer(), .integer(cases: [3, 1]), .integer(minimum: 0), .integer(minimum: -128, maximum: 127),
    .string(), .string(cases: ["b", "a"]), .string(format: .uuid), .string(format: .uriReference), .string(format: .base64),
    .array(.string()), .set(.integer()), .dictionary(.optional(.number)), .optional(.set(.string(format: .uuid))),
    .object([(key: "a", value: .string()), (key: "b", value: .optional(.dictionary(.array(.boolean))))]),
]

@Suite struct JSONSchemaStandardTests {
    // MARK: Keywords

    @Test(arguments: [JSONSchema.Style.standard, .strict])
    func writesOnly2020_12Keywords(style: JSONSchema.Style) throws {
        for schema in try corpus + [JSONSchema(for: Sample.self)] {
            #expect(schema.json(style).unknownKeywords().isEmpty, "\(schema.json(style))")
        }
    }

    @Test func standardDocumentsDeclareTheDialect() throws {
        let schema = try JSONSchema(for: Sample.self)
        #expect(schema.json(.standard)["$schema"] == "https://json-schema.org/draft/2020-12/schema")
        #expect(schema.json(.strict)["$schema"] == nil)
        #expect(schema.description.contains("$schema") == false, "The description and id leave the declaration out.")

        let encoded = String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)
        #expect(encoded.contains("draft\\/2020-12") || encoded.contains("draft/2020-12"))
    }

    @Test func readsDocumentsWithOrWithoutTheDialect() throws {
        let decoder = JSONDecoder()
        let declared = #"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","format":"uuid"}"#
        #expect(try decoder.decode(JSONSchema.self, from: Data(declared.utf8)) == .string(format: .uuid))
        #expect(try decoder.decode(JSONSchema.self, from: Data(#"{"type":"string","format":"uuid"}"#.utf8)) == .string(format: .uuid))

        let otherDialect = #"{"$schema":"http://json-schema.org/draft-07/schema#","type":"string"}"#
        #expect(throws: DecodingError.self) { try decoder.decode(JSONSchema.self, from: Data(otherDialect.utf8)) }
        let nested = #"{"type":"array","items":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string"}}"#
        #expect(throws: DecodingError.self) { try decoder.decode(JSONSchema.self, from: Data(nested.utf8)) }
    }

    @Test(arguments: corpus)
    func roundTripsInBothStyles(schema: JSONSchema) throws {
        let data = try JSONEncoder().encode(schema)
        #expect(try JSONDecoder().decode(JSONSchema.self, from: data) == schema)
        #expect(JSONSchema(document: schema.json(.strict)) == schema)
    }

    @Test func refusesKeywordsItCannotRepresent() {
        for text in [
            #"{"type":"string","format":"email"}"#,
            #"{"type":"string","format":"base64"}"#,
            #"{"type":"string","contentEncoding":"base32"}"#,
            #"{"type":"string","format":"uuid","contentEncoding":"base64"}"#,
            #"{"type":"integer","minimum":1.5}"#,
            #"{"type":"array","items":{"type":"string"},"uniqueItems":"yes"}"#,
            #"{"type":"object","additionalProperties":{"type":"string"},"properties":{}}"#,
            #"{"type":"object","additionalProperties":true}"#,
        ] {
            #expect(throws: DecodingError.self, "\(text)") { try JSONDecoder().decode(JSONSchema.self, from: Data(text.utf8)) }
        }
    }

    // MARK: Output

    @Test func writesEachKeywordAsTheStandardSpells() {
        #expect(JSONSchema.integer(minimum: -128, maximum: 127).description == #"{"type":"integer","minimum":-128,"maximum":127}"#)
        #expect(JSONSchema.string(format: .uuid).description == #"{"type":"string","format":"uuid"}"#)
        #expect(JSONSchema.string(format: .uriReference).description == #"{"type":"string","format":"uri-reference"}"#)
        #expect(JSONSchema.string(format: .base64).description == #"{"type":"string","contentEncoding":"base64"}"#)
        #expect(JSONSchema.set(.string()).description == #"{"type":"array","items":{"type":"string"},"uniqueItems":true}"#)
        #expect(JSONSchema.dictionary(.integer()).description == #"{"type":"object","additionalProperties":{"type":"integer"}}"#)
    }

    // MARK: Recording

    @Test func recordsFormatsBoundsSetsAndDictionaries() throws {
        let schema = try JSONSchema(for: Sample.self)
        guard case .object(let properties) = schema else { Issue.record("Not an object"); return }
        let fields = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.value) })
        #expect(fields["id"] == .string(format: .uuid))
        #expect(fields["link"] == .string(format: .uriReference))
        #expect(fields["photo"] == .string(format: .base64))
        #expect(fields["tags"] == .set(.string()))
        #expect(fields["counts"] == .dictionary(.integer()))
        #expect(fields["small"] == .integer(minimum: -128, maximum: 127))
        #expect(fields["flag"] == .optional(.integer(minimum: 0, maximum: 255)))
        #expect(fields["big"] == .integer(minimum: 0))
        #expect(fields["whole"] == .integer())
        #expect(fields["rank"] == .optional(.integer(cases: [1, 9])))
        #expect(fields["byName"] == .dictionary(.object([(key: "text", value: .string()), (key: "count", value: .integer())])))
        #expect(fields["groups"] == .set(.array(.integer())))
        #expect(try JSONSchema(for: UInt.self) == .integer(minimum: 0))
        #expect(try JSONSchema(for: Int16.self) == .integer(minimum: -32768, maximum: 32767))
    }

    // MARK: Compatibility

    @Test func boundsFormatsAndSetsAffectCompatibility() throws {
        let int8 = try JSONSchema(for: Int8.self), int = try JSONSchema(for: Int.self), uint8 = try JSONSchema(for: UInt8.self)
        #expect(int.isSuperset(of: int8))
        #expect(!int8.isSuperset(of: int))
        #expect(!int8.isSuperset(of: uint8), "128 fits a UInt8 but not an Int8.")
        #expect(int8.isSuperset(of: .integer(cases: [1, 2])))
        #expect(!int8.isSuperset(of: .integer(cases: [1, 200])))

        #expect(JSONSchema.string().isSuperset(of: .string(format: .uuid)))
        #expect(!JSONSchema.string(format: .uuid).isSuperset(of: .string()))
        #expect(!JSONSchema.string(format: .uuid).isSuperset(of: .string(format: .base64)))

        #expect(JSONSchema.array(.string()).isSuperset(of: .set(.string())))
        #expect(!JSONSchema.set(.string()).isSuperset(of: .array(.string())), "A Set would drop repeated elements.")
        #expect(JSONSchema.dictionary(.number).isSuperset(of: .dictionary(.integer())))
        #expect(!JSONSchema.dictionary(.integer()).isSuperset(of: .object([(key: "a", value: .integer())])))
    }

    // MARK: Values

    @Test func containsChecksFormatsBoundsAndUniqueness() {
        #expect(JSONSchema.integer(minimum: 0, maximum: 255).contains(255))
        #expect(!JSONSchema.integer(minimum: 0, maximum: 255).contains(256))
        #expect(!JSONSchema.integer(minimum: 0).contains(-1))
        #expect(JSONSchema.integer(minimum: 0).contains(.number("18446744073709551615")))
        #expect(JSONSchema.string(format: .uuid).contains("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        #expect(!JSONSchema.string(format: .uuid).contains("E621E1F8"))
        #expect(JSONSchema.string(format: .base64).contains("AAH+/w=="))
        #expect(!JSONSchema.string(format: .base64).contains("not base64!"))
        #expect(JSONSchema.set(.integer()).contains([1, 2]))
        #expect(!JSONSchema.set(.integer()).contains([1, .number("1.0")]), "1 and 1.0 are the same JSON value.")
        #expect(!JSONSchema.set(.object([(key: "a", value: .integer())])).contains([["a": 1, "b": 2], ["b": 2, "a": 1]]))
        #expect(JSONSchema.dictionary(.integer()).contains(["x": 1, "y": 2]))
        #expect(!JSONSchema.dictionary(.integer()).contains(["x": 1, "y": "2"]))
    }

    // MARK: Independent validation

    /// Schemas with values that must validate, written by `JSONEncoder`, and
    /// values that must not. `contains(_:)` agrees with each verdict here,
    /// and an independent 2020-12 validator checks the same verdicts in CI.
    private static func fixtures() throws -> [(name: String, schema: JSONSchema, valid: [JSONRepresentation], invalid: [JSONRepresentation])] {
        let schema = try JSONSchema(for: Sample.self)
        var withoutOptionals = sample
        (withoutOptionals.flag, withoutOptionals.rank, withoutOptionals.note) = (nil, nil, nil)
        let valid = try json(sample)

        func changing(_ key: String, to value: JSONRepresentation?) -> JSONRepresentation {
            var changed = valid
            if let value {
                changed[[key]] = value
            } else if case .object(let pairs) = changed {
                changed = .object(pairs.filter { $0.key != key })
            }
            return changed
        }

        return [
            ("sample", schema, [valid, try json(withoutOptionals), changing("small", to: .number("127.0"))], [
                changing("small", to: 128),
                changing("flag", to: -1),
                changing("big", to: -1),
                changing("id", to: "not-a-uuid"),
                changing("tags", to: ["a", "a"]),
                changing("groups", to: [[1], [1]]),
                changing("counts", to: ["x": "1"]),
                changing("byName", to: ["one": ["text": "u"]]),
                changing("shade", to: "dim"),
                changing("rank", to: 2),
                changing("whole", to: 1.5),
                changing("id", to: nil),
            ]),
            ("set", .set(.optional(.number)), [[1, 2.5, .null], []], [[1, 1], [.null, .null], ["1"]]),
            ("dictionary", .dictionary(.set(.string())), [["a": ["x"], "b": []]], [["a": ["x", "x"]], ["a": "x"]]),
            ("bounds", .integer(minimum: -1, maximum: 1), [-1, 0, 1, .number("1e0")], [-2, 2, 0.5]),
        ]
    }

    @Test func containsAgreesWithTheFixtureVerdicts() throws {
        for fixture in try Self.fixtures() {
            for value in fixture.valid {
                #expect(fixture.schema.contains(value), "\(fixture.name) should accept \(value)")
            }
            for value in fixture.invalid {
                #expect(!fixture.schema.contains(value), "\(fixture.name) should refuse \(value)")
            }
        }
    }

    @Test func writesFixturesForAnIndependentValidator() throws {
        guard let folder = ProcessInfo.processInfo.environment["JSON_SCHEMA_FIXTURES"] else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var fixtures = try Self.fixtures().map { fixture -> JSONRepresentation in
            ["name": .string(fixture.name), "schema": fixture.schema.json(.standard), "strict": fixture.schema.json(.strict),
             "valid": .array(fixture.valid), "invalid": .array(fixture.invalid)]
        }
        fixtures += corpus.enumerated().map { index, schema in
            ["name": .string("corpus-\(index)"), "schema": schema.json(.standard), "strict": schema.json(.strict), "valid": [], "invalid": []]
        }
        for fixture in fixtures {
            let name = fixture["name"]?.stringValue ?? "fixture"
            try encoder.encode(fixture).write(to: directory.appendingPathComponent("\(name).json"))
        }
    }
}
