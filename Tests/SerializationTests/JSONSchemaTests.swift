import Testing
@testable import Serialization

@Suite struct JSONSchemaTests {
    let person: JSONSchema = .object([
        (key: "name", value: .string),
        (key: "age", value: .integer),
        (key: "nickname", value: .optional(.string)),
        (key: "scores", value: .array(.number)),
    ])

    @Test func scalarsWriteTheirType() {
        #expect(JSONSchema.null.json == ["type": "null"])
        #expect(JSONSchema.boolean.json == ["type": "boolean"])
        #expect(JSONSchema.integer.json == ["type": "integer"])
        #expect(JSONSchema.number.json == ["type": "number"])
        #expect(JSONSchema.string.json == ["type": "string"])
    }

    @Test func objectDerivesRequiredFromOptional() {
        let expected: JSONRepresentation = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "age": ["type": "integer"],
                "nickname": ["type": "string"],
                "scores": ["type": "array", "items": ["type": "number"]],
            ],
            "required": ["name", "age", "scores"],
        ]
        #expect(person.json == expected)
    }

    @Test func objectWithOnlyOptionalPropertiesOmitsRequired() {
        let schema: JSONSchema = .object([(key: "note", value: .optional(.string))])
        #expect(schema["required"] == nil)
    }

    @Test func optionalOutsideAPropertyIsNullable() {
        let schema: JSONSchema = .array(.optional(.integer))
        let expected: JSONRepresentation = ["type": "array", "items": ["anyOf": [["type": "integer"], ["type": "null"]]]]
        #expect(schema.json == expected)
    }

    @Test(arguments: [
        JSONSchema.null, .boolean, .integer, .number, .string,
        .array(.optional(.string)),
        .optional(.array(.integer)),
        .object([]),
        .object([
            (key: "id", value: .integer),
            (key: "owner", value: .object([(key: "name", value: .string), (key: "email", value: .optional(.string))])),
            (key: "note", value: .optional(.optional(.string))),
        ]),
    ])
    func roundTrips(_ schema: JSONSchema) {
        #expect(JSONSchema(json: schema.json) == schema)
    }

    @Test func rejectsUnknownSchemas() {
        #expect(JSONSchema(json: ["type": "date"]) == nil)
        #expect(JSONSchema(json: ["items": ["type": "string"]]) == nil)
        #expect(JSONSchema(json: ["type": "array"]) == nil)
    }

    @Test func propertyOrderMatters() {
        let reordered: JSONSchema = .object([(key: "b", value: .string), (key: "a", value: .string)])
        let original: JSONSchema = .object([(key: "a", value: .string), (key: "b", value: .string)])
        #expect(reordered != original)
        #expect(Set([original, original, reordered]).count == 2)
    }
}

private extension JSONSchema {
    subscript(key: String) -> JSONRepresentation? { json[key] }
}
