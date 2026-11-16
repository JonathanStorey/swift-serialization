import Foundation
import Testing
@testable import Serialization

// MARK: - Fixtures

private struct Person: Codable {
    var name: String
    var age: Int
    var nickname: String?
    var scores: [Double]
}

private struct Address: Codable {
    var city: String
    var zip: String?
}

private struct Company: Codable {
    var name: String
    var headquarters: Address
    var offices: [Address]
    var parent: Address?
    var tags: [String?]
    var grid: [[Int]]
    var flags: Set<Bool>
}

private struct Renamed: Codable {
    var firstName: String
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case isActive = "active"
    }
}

private enum Color: String, Codable, CaseIterable {
    case red, green
}

private enum Priority: Int, Codable, CaseIterable {
    case low = 1, high = 2
}

private enum Mood: String, Codable {
    case happy
}

private struct Palette: Codable {
    var primary: Color
    var accent: Color?
    var priority: Priority
}

private struct Stamped: Codable {
    var created: Date
    var link: URL
    var payload: Data
    var amount: Decimal
    var id: UUID
}

private struct HandWritten: Decodable {
    var x: Int
    var label: String

    enum CodingKeys: String, CodingKey { case point, label }
    enum PointKeys: String, CodingKey { case x }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let point = try container.nestedContainer(keyedBy: PointKeys.self, forKey: .point)
        x = try point.decode(Int.self, forKey: .x)
        label = try container.decode(String.self, forKey: .label)
    }
}

private struct Tree: Codable {
    var value: Int
    var children: [Tree]
}

private final class LinkedNode: Codable {
    var value = 0
    var next: LinkedNode?
}

private struct WithDictionary: Codable {
    var counts: [String: Int]
}

private struct WithMood: Codable {
    var mood: Mood
}

private struct Pair: Decodable {
    var first: Int
    var second: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        first = try container.decode(Int.self)
        second = try container.decode(Int.self)
    }
}

// MARK: - Tests

@Suite struct JSONSchemaDecodableTests {
    @Test func scalarsAndCollections() throws {
        #expect(try JSONSchema(for: String.self) == .string())
        #expect(try JSONSchema(for: Bool.self) == .boolean)
        #expect(try JSONSchema(for: Int.self) == .integer())
        #expect(try JSONSchema(for: UInt8.self) == .integer())
        #expect(try JSONSchema(for: Double.self) == .number)
        #expect(try JSONSchema(for: Float.self) == .number)
        #expect(try JSONSchema(for: Int?.self) == .optional(.integer()))
        #expect(try JSONSchema(for: [String].self) == .array(.string()))
        #expect(try JSONSchema(for: [Int?].self) == .array(.optional(.integer())))
        #expect(try JSONSchema(for: [[Bool]].self) == .array(.array(.boolean)))
    }

    @Test func flatStruct() throws {
        let expected: JSONSchema = .object([
            (key: "name", value: .string()),
            (key: "age", value: .integer()),
            (key: "nickname", value: .optional(.string())),
            (key: "scores", value: .array(.number)),
        ])
        #expect(try JSONSchema(for: Person.self) == expected)
    }

    @Test func propertiesFollowDeclarationOrder() throws {
        guard case .object(let properties) = try JSONSchema(for: Person.self) else {
            Issue.record("Expected an object")
            return
        }
        #expect(properties.map(\.key) == ["name", "age", "nickname", "scores"])
    }

    @Test func nestedStructsArraysAndOptionals() throws {
        let address: JSONSchema = .object([(key: "city", value: .string()), (key: "zip", value: .optional(.string()))])
        let expected: JSONSchema = .object([
            (key: "name", value: .string()),
            (key: "headquarters", value: address),
            (key: "offices", value: .array(address)),
            (key: "parent", value: .optional(address)),
            (key: "tags", value: .array(.optional(.string()))),
            (key: "grid", value: .array(.array(.integer()))),
            (key: "flags", value: .array(.boolean)),
        ])
        #expect(try JSONSchema(for: Company.self) == expected)
    }

    @Test func customCodingKeysAreUsed() throws {
        let expected: JSONSchema = .object([(key: "first_name", value: .string()), (key: "active", value: .boolean)])
        #expect(try JSONSchema(for: Renamed.self) == expected)
    }

    @Test func caseIterableRawValueEnums() throws {
        #expect(try JSONSchema(for: Color.self) == .string(cases: ["red", "green"]))
        #expect(try JSONSchema(for: Priority.self) == .integer(cases: [1, 2]))
        let expected: JSONSchema = .object([
            (key: "primary", value: .string(cases: ["red", "green"])),
            (key: "accent", value: .optional(.string(cases: ["red", "green"]))),
            (key: "priority", value: .integer(cases: [1, 2])),
        ])
        #expect(try JSONSchema(for: Palette.self) == expected)
    }

    @Test func foundationTypesMatchJSONEncoderDefaults() throws {
        let expected: JSONSchema = .object([
            (key: "created", value: .number),
            (key: "link", value: .string()),
            (key: "payload", value: .string()),
            (key: "amount", value: .number),
            (key: "id", value: .string()),
        ])
        #expect(try JSONSchema(for: Stamped.self) == expected)
    }

    @Test func handWrittenNestedContainers() throws {
        let expected: JSONSchema = .object([
            (key: "point", value: .object([(key: "x", value: .integer())])),
            (key: "label", value: .string()),
        ])
        #expect(try JSONSchema(for: HandWritten.self) == expected)
    }

    @Test func schemaKeysMatchJSONEncoderOutput() throws {
        let person = Person(name: "Ada", age: 36, nickname: "A", scores: [9.5])
        let encoded = try JSONDecoder().decode(JSONRepresentation.self, from: JSONEncoder().encode(person))
        guard case .object(let object) = encoded, case .object(let properties) = try JSONSchema(for: Person.self) else {
            Issue.record("Expected objects")
            return
        }
        #expect(Set(object.map(\.key)) == Set(properties.map(\.key)))
    }

    @Test func recursiveTypesThrow() {
        #expect(throws: DecodingError.self) { try JSONSchema(for: Tree.self) }
        #expect(throws: DecodingError.self) { try JSONSchema(for: LinkedNode.self) }
    }

    @Test func dictionariesThrow() {
        #expect(throws: DecodingError.self) { try JSONSchema(for: [String: Int].self) }
        #expect(throws: DecodingError.self) { try JSONSchema(for: WithDictionary.self) }
    }

    @Test func rawValueEnumsWithoutCaseIterableThrow() {
        #expect(throws: DecodingError.self) { try JSONSchema(for: WithMood.self) }
    }

    @Test func positionalArraysThrow() {
        #expect(throws: DecodingError.self) { try JSONSchema(for: Pair.self) }
    }
}
