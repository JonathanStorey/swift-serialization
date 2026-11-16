import Testing
@testable import Serialization

@Suite struct StrictStyleTests {
    private let schema: JSONSchema = .object([
        (key: "name", value: .string()),
        (key: "nickname", value: .optional(.string())),
        (key: "tags", value: .array(.object([(key: "label", value: .string(cases: ["a", "b"]))]))),
        (key: "owner", value: .optional(.object([(key: "id", value: .integer()), (key: "note", value: .optional(.string()))]))),
    ])

    @Test func strictListsEveryPropertyAndClosesObjects() {
        let expected = #"{"type":"object","properties":{"name":{"type":"string"},"nickname":{"anyOf":[{"type":"string"},{"type":"null"}]},"tags":{"type":"array","items":{"type":"object","properties":{"label":{"type":"string","enum":["a","b"]}},"required":["label"],"additionalProperties":false}},"owner":{"anyOf":[{"type":"object","properties":{"id":{"type":"integer"},"note":{"anyOf":[{"type":"string"},{"type":"null"}]}},"required":["id","note"],"additionalProperties":false},{"type":"null"}]}},"required":["name","nickname","owner","tags"],"additionalProperties":false}"#
        #expect(schema.json(.strict).description == expected)
    }

    @Test func standardIsUnchanged() {
        #expect(schema.json(.standard) == schema.json)
        let expected = #"{"type":"object","properties":{"name":{"type":"string"},"nickname":{"type":"string"},"tags":{"type":"array","items":{"type":"object","properties":{"label":{"type":"string","enum":["a","b"]}},"required":["label"]}},"owner":{"type":"object","properties":{"id":{"type":"integer"},"note":{"type":"string"}},"required":["id"]}},"required":["name","tags"]}"#
        #expect(schema.json.description == expected)
    }

    @Test func emptyObjectsWriteAnEmptyRequiredList() {
        #expect(JSONSchema.object([]).json(.strict).description == #"{"type":"object","properties":{},"required":[],"additionalProperties":false}"#)
    }

    @Test(arguments: [
        JSONSchema.null, .boolean, .integer(cases: [1, 2]), .number, .string(),
        .array(.optional(.string())),
        .optional(.array(.integer())),
        .object([]),
        .object([(key: "a", value: .optional(.optional(.string()))), (key: "b", value: .object([(key: "c", value: .optional(.null))]))]),
    ])
    func bothStylesReadBack(_ value: JSONSchema) {
        #expect(JSONSchema(json: value.json(.strict)) == value)
        #expect(JSONSchema(json: value.json(.standard)) == value)
    }

    @Test func idAndDescriptionUseStandard() {
        #expect(schema.description == schema.json(.standard).description)
        #expect(schema.json(.strict) != schema.json(.standard))
    }

    @Test func onlyFalseAdditionalPropertiesIsAccepted() {
        #expect(JSONSchema(json: ["type": "object", "properties": [:], "additionalProperties": false]) == .object([]))
        #expect(JSONSchema(json: ["type": "object", "properties": [:], "additionalProperties": true]) == nil)
        #expect(JSONSchema(json: ["type": "object", "properties": [:], "additionalProperties": ["type": "string"]]) == nil)
        #expect(JSONSchema(json: ["type": "string", "additionalProperties": false]) == nil)
    }
}
