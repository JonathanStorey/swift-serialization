import Testing
@testable import Serialization

private enum Size: String, Codable, CaseIterable {
    case small, medium, large
}

/// The same cases as `Size`, declared in a different order.
private enum ReorderedSize: String, Codable, CaseIterable {
    case large, small, medium
}

/// `Size` with one more case.
private enum GrownSize: String, Codable, CaseIterable {
    case small, medium, large, huge
}

private enum Renamed: String, Codable, CaseIterable {
    case small = "S", medium = "M"
}

private enum Rank: UInt8, Codable, CaseIterable {
    case first = 1, second = 2, third = 3
}

private enum Signed: Int16, Codable, CaseIterable {
    case negative = -1, zero = 0, positive = 1
}

/// Not CaseIterable, and `""` is a valid case, so values stay unrestricted.
private enum Open: String, Codable {
    case none = "", some
}

private struct Shirt: Codable {
    var size: Size
    var sizes: [Size]
    var preferred: Size?
}

@Suite struct AllowedValuesTests {
    // MARK: Recording

    @Test func caseIterableEnumsRecordTheirRawValues() throws {
        #expect(try JSONSchema(for: Size.self) == .string(allowed: ["small", "medium", "large"]))
        #expect(try JSONSchema(for: Renamed.self) == .string(allowed: ["S", "M"]))
        #expect(try JSONSchema(for: Rank.self) == .integer(allowed: [1, 2, 3]))
        #expect(try JSONSchema(for: Signed.self) == .integer(allowed: [-1, 0, 1]))
    }

    @Test func nonCaseIterableEnumsStayUnrestricted() throws {
        #expect(try JSONSchema(for: Open.self) == .string())
    }

    @Test func allowedValuesFollowEnumsIntoArraysAndOptionals() throws {
        let size: JSONSchema = .string(allowed: ["small", "medium", "large"])
        let expected: JSONSchema = .object([
            (key: "size", value: size),
            (key: "sizes", value: .array(size)),
            (key: "preferred", value: .optional(size)),
        ])
        #expect(try JSONSchema(for: Shirt.self) == expected)
    }

    // MARK: Equality

    @Test func caseOrderDoesNotMatter() throws {
        #expect(try JSONSchema(for: Size.self) == JSONSchema(for: ReorderedSize.self))
        #expect(try JSONSchema(for: Size.self).hashValue == JSONSchema(for: ReorderedSize.self).hashValue)
    }

    @Test func addingACaseChangesTheSchema() throws {
        #expect(try JSONSchema(for: Size.self) != JSONSchema(for: GrownSize.self))
    }

    @Test(arguments: [
        (JSONSchema.string(), JSONSchema.string(allowed: ["a"])),
        (.string(allowed: []), .string()),
        (.string(allowed: ["a"]), .string(allowed: ["b"])),
        (.integer(allowed: [1]), .integer()),
        (.integer(allowed: [1]), .integer(allowed: [1, 2])),
        (.integer(allowed: [1]), .string(allowed: ["1"])),
    ])
    func restrictionsAreDistinct(_ pair: (JSONSchema, JSONSchema)) {
        #expect(pair.0 != pair.1)
        #expect(pair.1 != pair.0)
    }

    // MARK: JSON Schema text

    @Test func writesSortedEnumLists() {
        #expect(JSONSchema.string(allowed: ["medium", "large", "small"]).description == #"{"type":"string","enum":["large","medium","small"]}"#)
        #expect(JSONSchema.integer(allowed: [10, -2, 3]).description == #"{"type":"integer","enum":[-2,3,10]}"#)
        #expect(JSONSchema.string().description == #"{"type":"string"}"#)
        #expect(JSONSchema.string(allowed: []).description == #"{"type":"string","enum":[]}"#)
    }

    @Test func equalSchemasWriteEqualText() throws {
        #expect(try JSONSchema(for: Size.self).description == JSONSchema(for: ReorderedSize.self).description)
    }

    @Test(arguments: [
        JSONSchema.string(allowed: ["a", "b"]),
        .string(allowed: []),
        .integer(allowed: [Int64.min, 0, Int64.max]),
        .array(.optional(.string(allowed: ["x"]))),
        .object([(key: "size", value: .string(allowed: ["s", "m"])), (key: "rank", value: .optional(.integer(allowed: [1])))]),
    ])
    func roundTripsThroughJSON(_ schema: JSONSchema) {
        #expect(JSONSchema(json: schema.json) == schema)
    }

    @Test(arguments: [
        ["type": "string", "enum": ["a", "a"]],
        ["type": "string", "enum": [1]],
        ["type": "string", "enum": "a"],
        ["type": "integer", "enum": [1.5]],
        ["type": "integer", "enum": ["1"]],
        ["type": "number", "enum": [1]],
        ["type": "boolean", "enum": [true]],
    ] as [JSONRepresentation])
    func rejectsMalformedEnumLists(_ json: JSONRepresentation) {
        #expect(JSONSchema(json: json) == nil)
    }
}
