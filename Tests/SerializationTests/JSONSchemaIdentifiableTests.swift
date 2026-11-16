import Foundation
import Testing
@testable import Serialization

@Suite struct JSONSchemaIdentifiableTests {
    // Reference values from the `mmh3` Python package (`mmh3.hash_bytes`,
    // seed 0, x64), cross-checked against an independent implementation.
    // The lengths cover an empty input, a tail on each side of 8 bytes,
    // exactly one block, and a block plus a tail.
    @Test(arguments: [
        ("", "00000000-0000-0000-0000-000000000000"),
        ("aaaaaaaa", "393471F3-DA18-7A02-F20F-ECCF379E9BC7"),
        ("aaaaaaaaa", "647F6878-78E1-BAF7-9FD0-8A9F9F25ED3B"),
        ("aaaaaaaaaaaaaaa", "BC7F2EFD-DBA8-077D-59F9-5FA84A04A88F"),
        ("aaaaaaaaaaaaaaaa", "CEA6AA62-0D18-C1F2-4239-B22B03F3F66A"),
        ("aaaaaaaaaaaaaaaaa", "98D6F2CE-C714-726F-BBA5-DE4E53BCFDA4"),
    ])
    func hashMatchesMurmurHash3(_ text: String, _ expected: String) {
        #expect(UUID(stableHashOf: text).uuidString == expected)
    }

    // These values must never change. A failure here means every stored id
    // changed with it.
    @Test func idsAreStableAcrossReleases() {
        #expect(JSONSchema.string().id.uuidString == "AB2A80C4-451A-F34D-D30D-7ADE06021EB0")
        let object: JSONSchema = .object([
            (key: "b", value: .integer()),
            (key: "a", value: .optional(.string(cases: ["y", "x"]))),
        ])
        #expect(object.id.uuidString == "A3308D59-5945-4A5B-8A15-91419D02DDE6")
        #expect(JSONSchema.array(.optional(.number)).id.uuidString == "2DD93B85-EFC4-06C2-1C01-4001A07C74D3")
    }

    @Test func orderDoesNotChangeTheId() {
        let first: JSONSchema = .object([(key: "a", value: .string(cases: ["x", "y", "z"])), (key: "b", value: .optional(.integer(cases: [3, 1, 2])))])
        let second: JSONSchema = .object([(key: "b", value: .optional(.integer(cases: [2, 3, 1]))), (key: "a", value: .string(cases: ["z", "x", "y"]))])
        #expect(first.id == second.id)
    }

    @Test func canonicallyEquivalentKeysShareAnId() {
        let composed: JSONSchema = .object([(key: "caf\u{E9}", value: .string(cases: ["\u{E9}t\u{E9}"]))])
        let decomposed: JSONSchema = .object([(key: "cafe\u{301}", value: .string(cases: ["e\u{301}te\u{301}"]))])
        #expect(composed == decomposed)
        #expect(composed.id == decomposed.id)
    }

    @Test func idsMatchEquality() {
        let schemas: [JSONSchema] = [
            .null, .boolean, .number,
            .integer(), .integer(cases: []), .integer(cases: [1]), .integer(cases: [1, 2]),
            .string(), .string(cases: []), .string(cases: ["a"]), .string(cases: ["a", "b"]),
            .array(.string()), .array(.optional(.string())), .array(.array(.string())),
            .optional(.string()), .optional(.optional(.string())),
            .object([]),
            .object([(key: "a", value: .string())]),
            .object([(key: "a", value: .optional(.string()))]),
            .object([(key: "a", value: .optional(.optional(.string())))]),
            .object([(key: "b", value: .string())]),
            .object([(key: "a", value: .string()), (key: "b", value: .string())]),
            .object([(key: "b", value: .string()), (key: "a", value: .string())]),
            .object([(key: "a", value: .object([(key: "a", value: .string())]))]),
            .optional(.object([(key: "a", value: .string())])),
        ]
        for lhs in schemas {
            for rhs in schemas {
                #expect((lhs == rhs) == (lhs.id == rhs.id), "\(lhs) vs \(rhs)")
            }
        }
    }

    @Test func idTracksTheTypeItWasDerivedFrom() throws {
        struct Before: Decodable { var name: String }
        struct After: Decodable { var name: String; var nickname: String? }
        struct Renamed: Decodable { var title: String }
        let before = try JSONSchema(for: Before.self).id
        #expect(try JSONSchema(for: Before.self).id == before)
        #expect(try JSONSchema(for: After.self).id != before)
        #expect(try JSONSchema(for: Renamed.self).id != before)
    }
}
