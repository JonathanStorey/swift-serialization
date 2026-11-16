import Foundation
import Testing
@testable import Serialization

private enum Size: Int, Codable, CaseIterable { case small = 1, large = 2 }
private enum Tone: String, Codable, CaseIterable { case warm, cool }

private struct Item: Codable {
    var name: String
    var size: Size
    var tone: Tone?
    var price: Double
    var tags: [String]
    var note: String?
}

@Suite struct JSONSchemaContainsTests {
    @Test func followsJSONDecoderRules() throws {
        let schema = try JSONSchema(for: Item.self)
        let item: JSONRepresentation = ["name": "A", "size": 1, "price": 2, "tags": ["x"]]
        #expect(schema.contains(item))

        var json = item
        json[["extra"]] = [1, 2]
        #expect(schema.contains(json), "Undeclared keys are ignored.")
        json = item
        json[["note"]] = .null
        #expect(schema.contains(json), "An optional may be null.")
        json[["tone"]] = "cool"
        #expect(schema.contains(json))
        json[["tone"]] = "hot"
        #expect(!schema.contains(json), "Enum values must be cases.")
        json = item
        json[["size"]] = 3
        #expect(!schema.contains(json), "Enum values must be cases.")
        json = item
        json[["name"]] = nil
        #expect(!schema.contains(json), "A required property must be present.")
        json = item
        json[["name"]] = .null
        #expect(!schema.contains(json), "A required property cannot be null.")
        json = item
        json[["tags"]] = ["x", 1]
        #expect(!schema.contains(json), "Every element must match.")
        #expect(!schema.contains([item]))
    }

    @Test func numbers() {
        let integer = JSONSchema.integer()
        #expect(integer.contains(.number("-42")))
        #expect(integer.contains(.number("18446744073709551615")))
        #expect(!integer.contains(.number("18446744073709551616")))
        #expect(!integer.contains(.number("1.5")))
        #expect(!integer.contains(.string("1")))
        #expect(JSONSchema.number.contains(.number("1")))
        #expect(JSONSchema.number.contains(.number("1.5e3")))
        #expect(!JSONSchema.number.contains(.number("1e400")))
        #expect(!JSONSchema.number.contains(.number("01")))
    }

    /// `contains` should say yes exactly when decoding succeeds, for values
    /// inside each type's width.
    @Test(arguments: [
        .null, true, .number("0"), .number("-7"), .number("1.0"), .number("1e2"), .number("1.5"), .number("-0"),
        .number("9007199254740993"), .number("1e400"), "s", [], [1, 2], [1, nil], ["a": 1],
    ] as [JSONRepresentation])
    func agreesWithDecoding(_ json: JSONRepresentation) throws {
        try check(Int.self, json)
        try check(Int?.self, json)
        try check(Double.self, json)
        try check(Bool.self, json)
        try check(String.self, json)
        try check([Int].self, json)
        try check([Int?].self, json)
    }

    private func check<T: Codable>(_ type: T.Type, _ json: JSONRepresentation) throws {
        let decodes = (try? json.decode(T.self)) != nil
        #expect(try JSONSchema(for: T.self).contains(json) == decodes, "\(T.self) and \(json)")
    }

    /// A schema is a set of values, so membership must respect subsets.
    @Test func membershipRespectsSubsets() {
        var generator = SeededGenerator(seed: 11)
        var checkedSubsets = 0
        for _ in 0..<2_000 {
            let a = JSONSchema.random(depth: 2, using: &generator)
            let b = Bool.random(using: &generator) ? a.loosened(using: &generator) : .random(depth: 2, using: &generator)
            let value = a.sample(using: &generator)
            #expect(a.contains(value), "\(a) should contain its own sample \(value)")
            if a.isSubset(of: b) {
                checkedSubsets += 1
                #expect(b.contains(value), "\(a) ⊆ \(b) but only \(a) contains \(value)")
            }
        }
        #expect(checkedSubsets > 200)
    }
}

// MARK: - Random schemas

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension JSONSchema {
    static func random(depth: Int, using generator: inout SeededGenerator) -> JSONSchema {
        switch Int.random(in: 0..<(depth > 0 ? 9 : 6), using: &generator) {
        case 0: return .null
        case 1: return .boolean
        case 2: return .integer(cases: Bool.random(using: &generator) ? nil : Set([1, 2, 3].filter { _ in Bool.random(using: &generator) } + [1]))
        case 3: return .number
        case 4: return .string(cases: Bool.random(using: &generator) ? nil : Set(["x", "y"].filter { _ in Bool.random(using: &generator) } + ["x"]))
        case 5: return .optional(random(depth: 0, using: &generator))
        case 6: return .array(random(depth: depth - 1, using: &generator))
        case 7: return .optional(random(depth: depth - 1, using: &generator))
        default:
            let keys = ["a", "b", "c"].filter { _ in Bool.random(using: &generator) }
            return .object(keys.map { (key: $0, value: random(depth: depth - 1, using: &generator)) })
        }
    }

    /// A schema that accepts at least as much: optional wrappers added,
    /// cases removed, properties dropped and integers widened to numbers.
    func loosened(using generator: inout SeededGenerator) -> JSONSchema {
        switch self {
        case .integer: Bool.random(using: &generator) ? .number : .integer()
        case .string: .string()
        case .array(let items): .array(items.loosened(using: &generator))
        case .optional(let wrapped): .optional(wrapped.loosened(using: &generator))
        case .object(let properties):
            .object(properties.filter { _ in Bool.random(using: &generator) }.map { (key: $0.key, value: $0.value.loosened(using: &generator)) })
        default: Bool.random(using: &generator) ? .optional(self) : self
        }
    }

    /// A random value this schema contains, sometimes with undeclared keys
    /// and missing or null optional properties.
    func sample(using generator: inout SeededGenerator) -> JSONRepresentation {
        switch self {
        case .null: return .null
        case .boolean: return .bool(Bool.random(using: &generator))
        case .integer(let cases): return .number(String(cases?.randomElement(using: &generator) ?? Int64.random(in: -3...3, using: &generator)))
        case .number: return Bool.random(using: &generator) ? .number("2.5") : .number("4")
        case .string(let cases): return .string(cases?.randomElement(using: &generator) ?? "z")
        case .array(let items): return .array((0..<Int.random(in: 0...3, using: &generator)).map { _ in items.sample(using: &generator) })
        case .optional(let wrapped): return Bool.random(using: &generator) ? .null : wrapped.sample(using: &generator)
        case .object(let properties):
            var pairs: JSONRepresentation.Object = []
            for (key, value) in properties where !(value.isOptional && Bool.random(using: &generator)) {
                pairs.append((key: key, value: value.sample(using: &generator)))
            }
            if Bool.random(using: &generator) { pairs.append((key: "extra", value: true)) }
            return .object(pairs)
        }
    }
}
