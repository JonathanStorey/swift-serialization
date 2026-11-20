import Foundation
import Testing
@testable import Versioning

// MARK: - Fixtures

private class Animal: Codable {
    var name = ""
}

/// Decodes its superclass from the same decoder, the common pattern.
private final class Dog: Animal {
    var breed = ""

    private enum CodingKeys: String, CodingKey { case breed }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        breed = try container.decode(String.self, forKey: .breed)
        try super.init(from: decoder)
    }
}

/// Decodes its superclass from `superDecoder()`, under a "super" key.
private final class Cat: Animal {
    var lives = 0

    private enum CodingKeys: String, CodingKey { case lives }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lives = try container.decode(Int.self, forKey: .lives)
        try super.init(from: container.superDecoder())
    }
}

private enum Shape: Codable {
    case circle(radius: Double)
    case square(side: Double)
}

private enum Plain: Codable {
    case on, off
}

private struct Box<Value: Codable>: Codable {
    var value: Value
}

private struct UserID: Decodable {
    var raw: String

    init(from decoder: any Decoder) throws {
        raw = try decoder.singleValueContainer().decode(String.self)
    }
}

private struct Coordinates: Codable {
    var lat: Double
    var lon: Double
}

/// A single-value wrapper around a struct.
private struct Location: Decodable {
    var coordinates: Coordinates

    init(from decoder: any Decoder) throws {
        coordinates = try decoder.singleValueContainer().decode(Coordinates.self)
    }
}

private struct DoubleOptional: Codable {
    var value: Int??
}

private enum Level: Int, Codable {
    case zero = 0, one
}

private enum Tag: String, Codable {
    case none = "", urgent
}

private struct DecodesKeyTwice: Decodable {
    var first: Int
    var second: Int

    private enum CodingKeys: String, CodingKey { case value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        first = try container.decode(Int.self, forKey: .value)
        second = try container.decode(Int.self, forKey: .value)
    }
}

private struct DecodesKeyAsTwoKinds: Decodable {
    private enum CodingKeys: String, CodingKey { case value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(Int.self, forKey: .value)
        _ = try container.decode(String.self, forKey: .value)
    }
}

private struct NonEmptyName: Decodable {
    var value: String

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard !text.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty name"))
        }
        value = text
    }
}

private struct Lenient: Decodable {
    var count: Int

    private enum CodingKeys: String, CodingKey { case count }

    init(from decoder: any Decoder) throws {
        count = (try? decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .count)) ?? 0
    }
}

private struct Outer: Decodable {
    var inner: Inner
}

private final class Inner: Decodable {
    var outer: Outer?
}

private struct CustomFailure: Error {}

/// Throws its own error type from an object container.
private struct ThrowsCustomError: Decodable {
    private enum CodingKeys: String, CodingKey { case value }

    init(from decoder: any Decoder) throws {
        _ = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .value)
        throw CustomFailure()
    }
}

private struct HoldsCustomError: Decodable {
    var inner: ThrowsCustomError
}

/// Checks for keys with `contains(_:)` instead of `decodeIfPresent`.
private struct ChecksKeys: Codable {
    var name: String
    var nickname: String?

    private enum CodingKeys: String, CodingKey { case name, nickname, legacy }

    init(name: String, nickname: String?) {
        self.name = name
        self.nickname = nickname
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        nickname = try container.contains(.nickname) ? container.decode(String.self, forKey: .nickname) : nil
        _ = container.contains(.legacy)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(nickname, forKey: .nickname)
    }
}

// Large fixture for the scale test: 8 × 8 × 8 leaf properties.
private struct Leaf: Codable {
    var a: String, b: Int, c: Double, d: Bool, e: String?, f: [Int], g: Int?, h: [String?]
}

private struct Branch: Codable {
    var a: Leaf, b: Leaf?, c: [Leaf], d: Leaf, e: Leaf?, f: [Leaf], g: Leaf, h: Leaf
}

private struct Trunk: Codable {
    var a: Branch, b: Branch?, c: [Branch], d: Branch, e: Branch?, f: [Branch], g: Branch, h: Branch
}

// MARK: - Tests

@Suite struct JSONSchemaDecodableEdgeCaseTests {
    @Test func subclassDecodingSuperFromSameDecoder() throws {
        let expected: JSONSchema = .object([(key: "breed", value: .string()), (key: "name", value: .string())])
        #expect(try JSONSchema(for: Dog.self) == expected)
    }

    @Test func subclassDecodingSuperFromSuperDecoder() throws {
        let expected: JSONSchema = .object([
            (key: "lives", value: .integer()),
            (key: "super", value: .object([(key: "name", value: .string())])),
        ])
        #expect(try JSONSchema(for: Cat.self) == expected)
    }

    @Test func enumsWithoutRawValuesThrow() {
        #expect(throws: DecodingError.self) { try JSONSchema(for: Shape.self) }
        #expect(throws: DecodingError.self) { try JSONSchema(for: Plain.self) }
    }

    @Test func genericWrappers() throws {
        #expect(try JSONSchema(for: Box<Int>.self) == .object([(key: "value", value: .integer())]))
        #expect(try JSONSchema(for: Box<[String]>.self) == .object([(key: "value", value: .array(.string()))]))
        let nested: JSONSchema = .object([(key: "value", value: .object([(key: "value", value: .optional(.boolean))]))])
        #expect(try JSONSchema(for: Box<Box<Bool?>>.self) == nested)
    }

    @Test func singleValueWrappers() throws {
        #expect(try JSONSchema(for: UserID.self) == .string())
        let coordinates: JSONSchema = .object([(key: "lat", value: .number), (key: "lon", value: .number)])
        #expect(try JSONSchema(for: Location.self) == coordinates)
    }

    @Test func nestedOptionalsCollapseToOne() throws {
        #expect(try JSONSchema(for: Int??.self) == .optional(.integer()))
        #expect(try JSONSchema(for: DoubleOptional.self) == .object([(key: "value", value: .optional(.integer()))]))
    }

    @Test func optionalCollectionsAtTopLevel() throws {
        #expect(try JSONSchema(for: [Int]?.self) == .optional(.array(.integer())))
        #expect(try JSONSchema(for: [Coordinates?].self) == .array(.optional(.object([(key: "lat", value: .number), (key: "lon", value: .number)]))))
    }

    @Test func rawValueEnumsWhosePlaceholderIsACase() throws {
        #expect(try JSONSchema(for: Level.self) == .integer())
        #expect(try JSONSchema(for: Tag.self) == .string())
    }

    @Test func sameKeyDecodedTwiceIsOneProperty() throws {
        #expect(try JSONSchema(for: DecodesKeyTwice.self) == .object([(key: "value", value: .integer())]))
    }

    @Test func sameKeyDecodedAsTwoKindsThrows() {
        #expect(throws: DecodingError.self) { try JSONSchema(for: DecodesKeyAsTwoKinds.self) }
    }

    @Test func validatingInitThrowsWithPlaceholderMessage() {
        do {
            _ = try JSONSchema(for: NonEmptyName.self)
            Issue.record("Expected an error")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("placeholder"))
            #expect(context.debugDescription.contains("Other types that validate"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func errorsSwallowedByTheTypeStillRecord() throws {
        #expect(try JSONSchema(for: Lenient.self) == .object([(key: "count", value: .integer())]))
    }

    @Test func recursionErrorNamesTheType() {
        do {
            _ = try JSONSchema(for: Outer.self)
            Issue.record("Expected an error")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("Outer"))
            #expect(context.codingPath.map(\.stringValue) == ["inner", "outer"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func foreignErrorsAreWrappedInDecodingError() {
        do {
            _ = try JSONSchema(for: HoldsCustomError.self)
            Issue.record("Expected an error")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.underlyingError is CustomFailure)
            #expect(context.debugDescription.contains("ThrowsCustomError"))
            #expect(context.codingPath.map(\.stringValue) == ["inner"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func keysCheckedWithContainsAreOptional() throws {
        let expected: JSONSchema = .object([(key: "name", value: .string()), (key: "nickname", value: .optional(.string()))])
        #expect(try JSONSchema(for: ChecksKeys.self) == expected)

        // JSONDecoder agrees that the key may be missing.
        let data = try JSONEncoder().encode(ChecksKeys(name: "a", nickname: nil))
        #expect(try JSONDecoder().decode(ChecksKeys.self, from: data).nickname == nil)
    }

    @Test func largeTypesRecordQuickly() throws {
        let start = Date()
        var schema: JSONSchema = .null
        for _ in 0..<200 {
            schema = try JSONSchema(for: Trunk.self)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 10, "200 recordings of a ~600-property type took \(elapsed) seconds")

        guard case .object(let branches) = schema, case .object(let leaves)? = branches.first.map(\.value) else {
            Issue.record("Expected nested objects")
            return
        }
        #expect(branches.count == 8)
        #expect(leaves.count == 8)
    }
}
