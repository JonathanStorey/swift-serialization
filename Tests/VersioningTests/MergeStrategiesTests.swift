import Foundation
import Testing
@testable import Versioning

private struct Level: Comparable, Sendable {
    var number: Int
    static func < (lhs: Level, rhs: Level) -> Bool { lhs.number < rhs.number }
}

private struct Spot: Hashable, Codable, Sendable {
    var x: Int
    var y: Int
}

private struct Shipping: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let fast = Shipping(rawValue: 1)
    static let gift = Shipping(rawValue: 2)
    static let signed = Shipping(rawValue: 4)
}

/// A counter that merges by adding both sides' changes.
private struct Tally: Mergeable, Equatable, Sendable {
    var count = 0

    func merging(with theirs: Tally, from base: Tally) throws(MergeConflict) -> Tally {
        guard count >= 0, theirs.count >= 0 else { throw MergeConflict() }
        return Tally(count: count + theirs.count - base.count)
    }
}

@Suite struct MergeStrategiesTests {
    @Test func keepTakesTheNamedSide() throws {
        let ours: KeepMerge<String> = .ours
        #expect(try ours.merge(base: "a", ours: "b", theirs: "c") == "b")
        #expect(try KeepMerge<String>.theirs.merge(ours: "b", theirs: "c") == "c")
    }

    @Test func maximumKeepsTheLargerByTheTypesOwnOrder() throws {
        #expect(try ComparableMaximumMerge<Int>().merge(base: 10, ours: 30, theirs: 20) == 30)
        #expect(try ComparableMaximumMerge<Level>().merge(base: Level(number: 1), ours: Level(number: 5), theirs: Level(number: 3)) == Level(number: 5))
        let later = Date(timeIntervalSinceReferenceDate: 300)
        #expect(try ComparableMaximumMerge<Date>().merge(ours: Date(timeIntervalSinceReferenceDate: 200), theirs: later) == later)
    }

    @Test func sumCountsBothSides() throws {
        #expect(try NumericSumMerge<Int>().merge(base: 3, ours: 5, theirs: 4) == 6)
        #expect(try NumericSumMerge<Int>().merge(base: 3, ours: 4, theirs: 4) == 5, "Equal increments both count.")
        #expect(try NumericSumMerge<Double>().merge(base: 1.5, ours: 2.5, theirs: 2) == 3)
        #expect(try NumericSumMerge<UInt8>().merge(base: 10, ours: 6, theirs: 11) == 7)
    }

    @Test func aSumThatOverflowsConflicts() {
        #expect(throws: MergeConflict()) { try NumericSumMerge<UInt8>().merge(base: 100, ours: 200, theirs: 200) }
        #expect(throws: MergeConflict()) { try NumericSumMerge<Int>().merge(base: 0, ours: .max, theirs: 1) }
    }

    @Test func aSumNeedsABaseUnlessEqual() throws {
        #expect(throws: MergeConflict()) { try NumericSumMerge<Int>().merge(ours: 1, theirs: 2) }
        #expect(try NumericSumMerge<Int>().merge(ours: 5, theirs: 5) == 5)
    }

    @Test func trueWinsSetsTheFlag() throws {
        #expect(try BoolTrueWinsMerge().merge(base: false, ours: true, theirs: false) == true)
        #expect(try BoolTrueWinsMerge().merge(ours: false, theirs: true) == true)
        #expect(try BoolTrueWinsMerge().merge(base: true, ours: false, theirs: false) == false)
    }

    @Test func wordEditsCombine() throws {
        let strategy = StringWordMerge<String>()
        #expect(try strategy.merge(base: "the quick brown fox", ours: "the slow brown fox", theirs: "the quick brown cat, again") == "the slow brown cat, again")
    }

    @Test func editsToTheSameWordConflict() throws {
        let strategy = StringWordMerge<String>()
        #expect(throws: MergeConflict()) { try strategy.merge(base: "the quick brown fox", ours: "the slow brown fox", theirs: "the fast brown fox") }
        #expect(try strategy.merge(ours: "the fox", theirs: "the fox") == "the fox")
    }

    @Test func insertionsFromBothSidesAreKept() throws {
        let strategy = RangeReplaceableCollectionElementMerge<[String]>()
        #expect(try strategy.merge(base: ["boil", "stir", "serve"], ours: ["boil", "salt", "stir", "serve"], theirs: ["stir", "serve", "eat"]) == ["salt", "stir", "serve", "eat"])
    }

    @Test func textMergesByCharacter() throws {
        let strategy = RangeReplaceableCollectionElementMerge<String>()
        #expect(try strategy.merge(base: "soup", ours: "soups", theirs: "Soup") == "Soups")
        #expect(try strategy.merge(base: "cat", ours: "cart", theirs: "cats") == "carts")
    }

    @Test func anElementBothReplacedDifferentlyConflicts() throws {
        let strategy = RangeReplaceableCollectionElementMerge<[Int]>()
        #expect(try strategy.merge(base: [1, 2, 3], ours: [0, 1, 2, 3], theirs: [1, 2, 3, 4]) == [0, 1, 2, 3, 4])
        #expect(throws: MergeConflict()) { try strategy.merge(base: [1], ours: [2], theirs: [3]) }
        #expect(try strategy.merge(base: [1], ours: [2], theirs: [2]) == [2])
    }

    @Test func setsMergeByMembership() throws {
        let strategy = SetAlgebraMembershipMerge<Set<String>>()
        #expect(try strategy.merge(base: ["a", "b", "c"], ours: ["c", "a", "ours"], theirs: ["b", "a", "theirs"]) == ["a", "ours", "theirs"])
        #expect(try SetAlgebraMembershipMerge<Shipping>().merge(base: [.fast], ours: [.fast, .gift], theirs: [.signed]) == [.gift, .signed])
        #expect(try strategy.merge(ours: ["a"], theirs: ["a"]) == ["a"])
        #expect(throws: MergeConflict()) { try strategy.merge(ours: ["a", "b"], theirs: ["a"]) }
    }

    @Test func manySetsMergeWhateverTheirOrder() throws {
        let big = Set((0..<200).map(String.init))
        let strategy = SetAlgebraMembershipMerge<Set<String>>()
        #expect(try strategy.merge(base: big, ours: big.union(["x"]), theirs: big.subtracting(["7"])) == big.subtracting(["7"]).union(["x"]))
    }

    @Test func unionLosesNothingWithoutABase() throws {
        #expect(try SetAlgebraUnionMerge<Set<String>>().merge(ours: ["ana", "cy"], theirs: ["bo", "di", "ana"]) == ["ana", "cy", "bo", "di"])
    }

    @Test func unionKeepsRemovalsWithABase() throws {
        #expect(try SetAlgebraUnionMerge<Set<String>>().merge(base: ["ana", "bo"], ours: ["ana"], theirs: ["ana", "bo", "cy"]) == ["ana", "cy"])
    }

    @Test func aDictionaryMergesByKey() throws {
        let base: [Spot: String] = [Spot(x: 0, y: 0): "home"]
        let ours: [Spot: String] = [Spot(x: 0, y: 0): "home", Spot(x: 1, y: 1): "ours"]
        let theirs: [Spot: String] = [Spot(x: 0, y: 0): "start", Spot(x: 2, y: 2): "theirs"]
        #expect(try DictionaryKeyedMerge().merge(base: base, ours: ours, theirs: theirs) == [
            Spot(x: 0, y: 0): "start", Spot(x: 1, y: 1): "ours", Spot(x: 2, y: 2): "theirs",
        ])
    }

    @Test func aDictionaryKeyBothChangedConflicts() throws {
        let strategy = DictionaryKeyedMerge<String, Int>()
        #expect(throws: MergeConflict()) { try strategy.merge(base: ["a": 1], ours: ["a": 2], theirs: ["a": 3]) }
        #expect(try strategy.merge(base: ["a": 1], ours: ["a": 2], theirs: ["a": 2]) == ["a": 2])
        #expect(try strategy.merge(base: ["a": 1, "b": 1], ours: ["b": 1], theirs: ["a": 1, "b": 2]) == ["b": 2])
        #expect(throws: MergeConflict()) { try strategy.merge(base: ["a": 1], ours: [:], theirs: ["a": 2]) }
    }

    @Test func mergeableMergesByItsOwnFunctions() throws {
        var tally = Tally(count: 3)
        #expect(try tally.merging(with: Tally(count: 5), from: Tally(count: 1)) == Tally(count: 7))
        try tally.merge(with: Tally(count: 5), from: Tally(count: 1))
        #expect(tally == Tally(count: 7))
        #expect(try tally.merging(with: Tally(count: 7)) == tally, "Without a base, equal versions merge.")
        #expect(throws: MergeConflict()) { try tally.merging(with: Tally(count: 2)) }
    }
}
