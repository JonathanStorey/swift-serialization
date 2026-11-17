import Foundation
import Testing
@testable import Serialization

private enum Kind: String, Codable { case house, flat }
private enum Rank: Int, Codable { case first = 1, second }

private struct Address: Codable {
    var street: String
    var unit: Int?
}

private struct Listing: Codable {
    var title: String
    var path: String
    var kind: Kind
    var rank: Rank
    var count: Int
    var big: UInt64
    var negative: Int8
    var price: Double
    var ratio: Float
    var whole: Double
    var tiny: Double
    var huge: Double
    var amount: Decimal
    var precise: Decimal
    var listed: Date
    var photo: Data
    var link: URL
    var address: Address
    var previous: Address?
    var tags: [String]
    var grid: [[Int?]]
    var lookup: [String: Int]
}

/// `JSONEncoder` writes a value and its representation the same way. Its
/// key order is only fixed with `.sortedKeys`, so that is the comparison.
@Suite struct EncoderParityTests {
    private static let listing = Listing(
        title: "Line \"one\"\n</script> é👩‍👩‍👧", path: "a/b\\c", kind: .flat, rank: .second,
        count: -42, big: .max, negative: -128, price: 0.1 + 0.2, ratio: 0.1, whole: 3, tiny: 5e-324,
        huge: 1.7976931348623157e308, amount: Decimal(string: "12.50")!,
        precise: Decimal(string: "3.1415926535897932384626433832795028841")!,
        listed: Date(timeIntervalSinceReferenceDate: 812_345_678.25), photo: Data([0, 1, 254, 255]),
        link: URL(string: "https://example.com/a?b=c&d=e")!,
        address: Address(street: "Main", unit: nil), previous: Address(street: "Elm", unit: 4),
        tags: ["x", "", "y/z"], grid: [[1, nil], []], lookup: ["b": 2, "a": 1, "c": 3]
    )

    @Test func encodedDataMatches() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let expected = try encoder.encode(Self.listing)
        let actual = try encoder.encode(JSONRepresentation(Self.listing))
        #expect(String(decoding: actual, as: UTF8.self) == String(decoding: expected, as: UTF8.self))
    }

    @Test func prettyPrintedDataMatches() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let expected = try encoder.encode(Self.listing)
        let actual = try encoder.encode(JSONRepresentation(Self.listing))
        #expect(String(decoding: actual, as: UTF8.self) == String(decoding: expected, as: UTF8.self))
    }
}
