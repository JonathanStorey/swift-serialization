import Foundation
import Testing
@testable import Serialization

// MARK: - Fixtures

private enum V1 {
    struct User: Codable { var name: String }
}

private enum V2 {
    /// Adds an optional property.
    struct User: Codable { var name: String; var nickname: String? }
}

private enum V3 {
    /// Adds a required property.
    struct User: Codable { var name: String; var age: Int }
}

private enum V4 {
    /// Retypes V2's optional property.
    struct User: Codable { var name: String; var nickname: Int? }
}

private enum FewerColors: String, Codable, CaseIterable { case red, green }
private enum MoreColors: String, Codable, CaseIterable { case red, green, blue }

// MARK: - Tests

@Suite struct JSONSchemaCompatibilityTests {
    @Test func scalars() {
        #expect(JSONSchema.string().isSuperset(of: .string()))
        #expect(JSONSchema.boolean.isSuperset(of: .boolean))
        #expect(JSONSchema.null.isSuperset(of: .null))
        #expect(!JSONSchema.string().isSuperset(of: .integer()))
        #expect(!JSONSchema.boolean.isSuperset(of: .null))
    }

    @Test func integersWidenToNumbers() {
        #expect(JSONSchema.number.isSuperset(of: .integer()))
        #expect(JSONSchema.number.isSuperset(of: .integer(cases: [1, 2])))
        #expect(!JSONSchema.integer().isSuperset(of: .number))
        #expect(!JSONSchema.number.isCompatible(with: .integer()))
    }

    @Test func cases() {
        #expect(JSONSchema.string().isSuperset(of: .string(cases: ["a"])))
        #expect(!JSONSchema.string(cases: ["a"]).isSuperset(of: .string()))
        #expect(JSONSchema.string(cases: ["a", "b"]).isSuperset(of: .string(cases: ["a"])))
        #expect(!JSONSchema.string(cases: ["a"]).isSuperset(of: .string(cases: ["a", "b"])))
        #expect(JSONSchema.integer(cases: [1, 2]).isSuperset(of: .integer(cases: [2])))
        #expect(JSONSchema.integer(cases: []).isSubset(of: .integer(cases: [1])))
    }

    @Test func optionals() {
        #expect(JSONSchema.optional(.string()).isSuperset(of: .string()))
        #expect(JSONSchema.optional(.string()).isSuperset(of: .null))
        #expect(!JSONSchema.string().isSuperset(of: .optional(.string())))
        #expect(JSONSchema.optional(.number).isSuperset(of: .optional(.integer())))
        #expect(JSONSchema.optional(.string()).isCompatible(with: .optional(.optional(.string()))))
        #expect(JSONSchema.null.isSuperset(of: .optional(.null)))
    }

    @Test func arrays() {
        #expect(JSONSchema.array(.optional(.string())).isSuperset(of: .array(.string())))
        #expect(!JSONSchema.array(.string()).isSuperset(of: .array(.optional(.string()))))
        #expect(JSONSchema.array(.number).isSuperset(of: .array(.integer())))
        #expect(!JSONSchema.array(.string()).isSuperset(of: .string()))
    }

    @Test func objects() {
        let name: JSONSchema = .object([(key: "name", value: .string())])
        let withNickname: JSONSchema = .object([(key: "name", value: .string()), (key: "nickname", value: .optional(.string()))])
        let withAge: JSONSchema = .object([(key: "name", value: .string()), (key: "age", value: .integer())])
        let requiredNull: JSONSchema = .object([(key: "gap", value: .null)])

        #expect(name.isSuperset(of: withAge), "Extra keys are ignored")
        #expect(!withAge.isSuperset(of: name), "A required key must be written")
        #expect(withNickname.isSuperset(of: name), "An optional key may be missing")
        #expect(name.isCompatible(with: withNickname))
        #expect(!requiredNull.isSuperset(of: .object([])), "A required null must still be present")
        #expect(JSONSchema.object([]).isSuperset(of: withAge))
        #expect(!JSONSchema.object([]).isSuperset(of: .array(.string())))
    }

    @Test func nestedObjects() {
        let reader: JSONSchema = .object([(key: "child", value: .object([(key: "id", value: .number)]))])
        let writer: JSONSchema = .object([(key: "child", value: .object([(key: "id", value: .integer()), (key: "extra", value: .boolean)]))])
        #expect(reader.isSuperset(of: writer))
        #expect(!writer.isSuperset(of: reader))
    }

    @Test func compatibilityIsNotTransitive() {
        let plain: JSONSchema = .object([(key: "name", value: .string())])
        let textNickname: JSONSchema = .object([(key: "name", value: .string()), (key: "nickname", value: .optional(.string()))])
        let numberNickname: JSONSchema = .object([(key: "name", value: .string()), (key: "nickname", value: .optional(.integer()))])
        #expect(plain.isCompatible(with: textNickname))
        #expect(plain.isCompatible(with: numberNickname))
        #expect(!textNickname.isCompatible(with: numberNickname))
    }

    @Test(arguments: [
        .null, .boolean, .number, .integer(), .integer(cases: [1]), .string(), .string(cases: ["a"]),
        .array(.string()), .optional(.integer()), .object([(key: "a", value: .optional(.string()))]),
    ] as [JSONSchema])
    func everySchemaIsCompatibleWithItself(_ schema: JSONSchema) {
        #expect(schema.isSuperset(of: schema))
        #expect(schema.isSubset(of: schema))
        #expect(schema.isCompatible(with: schema))
    }

    @Test func subsetMirrorsSuperset() {
        let schemas: [JSONSchema] = [.number, .integer(), .optional(.integer()), .string(cases: ["a"]), .string(), .null]
        for lhs in schemas {
            for rhs in schemas {
                #expect(lhs.isSubset(of: rhs) == rhs.isSuperset(of: lhs))
            }
        }
    }

    // MARK: Checked against JSONDecoder

    /// Encodes `value` with `JSONEncoder`, then reports whether `Reader`
    /// decodes it.
    private func decodes<Reader: Decodable>(_ reader: Reader.Type, from value: some Encodable) throws -> Bool {
        let data = try JSONEncoder().encode(value)
        return (try? JSONDecoder().decode(Reader.self, from: data)) != nil
    }

    @Test func versionedTypesAgreeWithJSONDecoder() throws {
        let v1 = try JSONSchema(for: V1.User.self)
        let v2 = try JSONSchema(for: V2.User.self)
        let v3 = try JSONSchema(for: V3.User.self)
        let v4 = try JSONSchema(for: V4.User.self)

        let v2ReadsV1 = try decodes(V2.User.self, from: V1.User(name: "a"))
        let v1ReadsV2 = try decodes(V1.User.self, from: V2.User(name: "a", nickname: "b"))
        let v3ReadsV1 = try decodes(V3.User.self, from: V1.User(name: "a"))
        let v1ReadsV3 = try decodes(V1.User.self, from: V3.User(name: "a", age: 1))
        let v4ReadsV2 = try decodes(V4.User.self, from: V2.User(name: "a", nickname: "b"))
        #expect(v2.isSuperset(of: v1) == v2ReadsV1)
        #expect(v1.isSuperset(of: v2) == v1ReadsV2)
        #expect(v3.isSuperset(of: v1) == v3ReadsV1)
        #expect(v1.isSuperset(of: v3) == v1ReadsV3)
        #expect(v4.isSuperset(of: v2) == v4ReadsV2)

        #expect(v1.isCompatible(with: v2))
        #expect(!v1.isCompatible(with: v3))
        #expect(!v2.isCompatible(with: v4))
    }

    @Test func enumCasesAgreeWithJSONDecoder() throws {
        let fewer = try JSONSchema(for: FewerColors.self)
        let more = try JSONSchema(for: MoreColors.self)
        #expect(more.isSuperset(of: fewer))
        #expect(!fewer.isSuperset(of: more))
        #expect(try decodes(MoreColors.self, from: FewerColors.green))
        #expect(try !decodes(FewerColors.self, from: MoreColors.blue))
    }

    @Test func integerToDoubleAgreesWithJSONDecoder() throws {
        #expect(try JSONSchema(for: Double.self).isSuperset(of: JSONSchema(for: Int.self)))
        #expect(try decodes(Double.self, from: 42))
    }
}
