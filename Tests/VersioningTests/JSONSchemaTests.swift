import Testing
@testable import Versioning

@Suite struct JSONSchemaTests {
    let person: JSONSchema = .object([
        (key: "name", value: .string()),
        (key: "age", value: .integer()),
        (key: "nickname", value: .optional(.string())),
        (key: "scores", value: .array(.number)),
    ])

    @Test func scalarsWriteTheirType() {
        #expect(JSONSchema.null.body == ["type": "null"])
        #expect(JSONSchema.boolean.body == ["type": "boolean"])
        #expect(JSONSchema.integer().body == ["type": "integer"])
        #expect(JSONSchema.number.body == ["type": "number"])
        #expect(JSONSchema.string().body == ["type": "string"])
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
            "required": ["age", "name", "scores"],
        ]
        #expect(person.body == expected)
    }

    @Test func objectWithOnlyOptionalPropertiesOmitsRequired() {
        let schema: JSONSchema = .object([(key: "note", value: .optional(.string()))])
        #expect(schema["required"] == nil)
    }

    @Test func optionalOutsideAPropertyIsNullable() {
        let schema: JSONSchema = .array(.optional(.integer()))
        let expected: JSONRepresentation = ["type": "array", "items": ["anyOf": [["type": "integer"], ["type": "null"]]]]
        #expect(schema.body == expected)
    }

    @Test(arguments: [
        JSONSchema.null, .boolean, .integer(), .number, .string(),
        .array(.optional(.string())),
        .optional(.array(.integer())),
        .object([]),
        .object([
            (key: "id", value: .integer()),
            (key: "owner", value: .object([(key: "name", value: .string()), (key: "email", value: .optional(.string()))])),
            (key: "note", value: .optional(.optional(.string()))),
        ]),
    ])
    func roundTrips(_ schema: JSONSchema) {
        #expect(JSONSchema(json: schema.body) == schema)
    }

    @Test func rejectsUnknownSchemas() {
        #expect(JSONSchema(json: ["type": "date"]) == nil)
        #expect(JSONSchema(json: ["items": ["type": "string"]]) == nil)
        #expect(JSONSchema(json: ["type": "array"]) == nil)
    }

    @Test func propertyOrderIsIgnoredForEquality() {
        let reordered: JSONSchema = .object([(key: "b", value: .string()), (key: "a", value: .optional(.integer()))])
        let original: JSONSchema = .object([(key: "a", value: .optional(.integer())), (key: "b", value: .string())])
        #expect(reordered == original)
        #expect(Set([original, original, reordered]).count == 1)
        #expect(reordered != .object([(key: "a", value: .integer()), (key: "b", value: .string())]))
    }
}

private extension JSONSchema {
    subscript(key: String) -> JSONRepresentation? { json[key] }
}
