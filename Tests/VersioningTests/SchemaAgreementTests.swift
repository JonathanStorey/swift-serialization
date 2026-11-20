import Foundation
import Testing
@testable import Versioning

// MARK: - Fixtures

private enum Level: Int, Codable, CaseIterable { case low = 1, high = 2 }
private enum Shade: String, Codable, CaseIterable { case light, dark }

private struct Room: Codable {
    var name: String
    var level: Level
    var note: String?
}

private struct Building: Codable {
    var title: String
    var floors: Int
    var height: Double
    var open: Bool
    var shade: Shade?
    var rooms: [Room]
    var lobby: Room?
    var grid: [[Int?]]

    enum CodingKeys: String, CodingKey {
        case title = "display_title"
        case floors, height, open, shade, rooms, lobby, grid
    }
}

// MARK: - Tests

/// `JSONSchema(for:)` and `JSONRepresentation(_:)` are built by separate
/// machinery. These tests check that the schema of a type describes every
/// value of that type, so the two cannot drift apart.
@Suite struct SchemaAgreementTests {
    @Test func schemaDescribesEncodedValues() throws {
        let schema = try JSONSchema(for: Building.self)
        let full = Building(
            title: "Main", floors: 3, height: 12.5, open: true, shade: .dark,
            rooms: [Room(name: "A", level: .low, note: "corner"), Room(name: "B", level: .high, note: nil)],
            lobby: Room(name: "L", level: .high, note: nil),
            grid: [[1, nil], []]
        )
        let empty = Building(
            title: "", floors: 0, height: 0, open: false, shade: nil,
            rooms: [], lobby: nil, grid: []
        )
        for building in [full, empty] {
            #expect(schema.describes(try JSONRepresentation(building)))
        }
    }

    @Test func schemaRejectsAValueOfAnotherShape() throws {
        let schema = try JSONSchema(for: Room.self)
        #expect(schema.describes(["name": "A", "level": 1]))
        #expect(!schema.describes(["name": "A", "level": 3]))
        #expect(!schema.describes(["name": "A"]))
        #expect(!schema.describes(["name": "A", "level": 1, "extra": true]))
        #expect(!schema.describes(["name": 1, "level": 1]))
    }
}

private extension JSONSchema {
    /// Whether `json` has exactly this shape: every required property is
    /// present, there are no extra properties, and enum values are cases.
    func describes(_ json: JSONRepresentation) -> Bool {
        switch (self, json) {
        case (.optional, .null), (.null, .null), (.boolean, .bool):
            true
        case (.optional(let inner), _):
            inner.describes(json)
        case (.integer(let cases, let minimum, let maximum), .number):
            if let value = json.int64Value {
                (cases?.contains(value) ?? true) && JSONSchema.integer(value, isAtLeast: minimum, atMost: maximum)
            } else {
                cases == nil && maximum == nil && json.uint64Value != nil
            }
        case (.number, .number):
            true
        case (.string(let cases, let format), .string(let value)):
            (cases?.contains(value) ?? true) && (format?.accepts(value) ?? true)
        case (.array(let element), .array(let values)), (.set(let element), .array(let values)):
            values.allSatisfy(element.describes)
        case (.dictionary(let element), .object(let pairs)):
            pairs.allSatisfy { element.describes($0.value) }
        case (.object(let properties), .object(let pairs)):
            pairs.allSatisfy { pair in properties.contains { $0.key == pair.key } }
                && properties.allSatisfy { property in
                    guard let value = json[property.key] else { return property.value.isOptional }
                    return property.value.describes(value)
                }
        default:
            false
        }
    }
}
