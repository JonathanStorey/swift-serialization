import Foundation
import Testing
@testable import Versioning

private struct Card: Codable, Equatable, Sendable {
    var title = "Title"
    var body = "Body"
}

@Suite struct AnyMergeStrategyTests {
    @Test func wrapsAStrategy() throws {
        let strategy = AnyMergeStrategy(NumericSumMerge<Int>())
        #expect(try strategy.merge(base: 3, ours: 5, theirs: 4) == 6)
        #expect(throws: MergeConflict()) { try strategy.merge(ours: 1, theirs: 2) }
    }

    @Test func dotSyntaxNamesEachStrategy() throws {
        let maximum: AnyMergeStrategy<Int> = .maximum
        #expect(try maximum.merge(ours: 3, theirs: 7) == 7)
        let trueWins: AnyMergeStrategy<Bool> = .trueWins
        #expect(try trueWins.merge(base: false, ours: true, theirs: false))
        let union: AnyMergeStrategy<Set<String>> = .union
        #expect(try union.merge(ours: ["a"], theirs: ["b"]) == ["a", "b"])
        let membership: AnyMergeStrategy<Set<String>> = .byMembership
        #expect(try membership.merge(base: ["a", "b"], ours: ["a"], theirs: ["a", "b", "c"]) == ["a", "c"])
        let byKey: AnyMergeStrategy<[String: Int]> = .byKey()
        #expect(try byKey.merge(base: ["x": 1], ours: ["x": 2], theirs: ["x": 1, "y": 3]) == ["x": 2, "y": 3])
        let byElement: AnyMergeStrategy<[Int]> = .byElement
        #expect(try byElement.merge(base: [1, 2], ours: [0, 1, 2], theirs: [1, 2, 3]) == [0, 1, 2, 3])
        let byWord: AnyMergeStrategy<String> = .byWord
        #expect(try byWord.merge(base: "the quick fox", ours: "the slow fox", theirs: "the quick dog") == "the slow dog")
        let keep: AnyMergeStrategy<String> = .keep(.theirs)
        #expect(try keep.merge(base: "a", ours: "b", theirs: "c") == "c")
    }

    @Test func keepTakesTheSideOnlyWhereTheStrategyConflicts() throws {
        let strategy: AnyMergeStrategy<String> = .byWord.keep(.ours)
        #expect(try strategy.merge(base: "the quick fox", ours: "the slow fox", theirs: "the quick dog") == "the slow dog")
        #expect(try strategy.merge(base: "the quick fox", ours: "the slow fox", theirs: "the fast fox") == "the slow fox")
        #expect(try strategy.merge(ours: "ours", theirs: "theirs") == "ours", "Without a base, the word merge conflicts.")

        let sum: AnyMergeStrategy<UInt8> = .sum.keep(.theirs)
        #expect(try sum.merge(base: 100, ours: 200, theirs: 210) == 210, "An overflow keeps theirs.")
    }

    @Test func jsonKeepsASideOnlyAtEachConflict() throws {
        let base = Card()
        var ours = base, theirs = base
        ours.title = "Ours"
        theirs.title = "Theirs"
        ours.body = "Ours"
        let total: AnyMergeStrategy<Card> = .json(onConflict: .theirs)
        #expect(try total.merge(base: base, ours: ours, theirs: theirs) == Card(title: "Theirs", body: "Ours"))
        let whole: AnyMergeStrategy<Card> = .json.keep(.theirs)
        #expect(try whole.merge(base: base, ours: ours, theirs: theirs) == theirs)
        let strict: AnyMergeStrategy<Card> = .json
        #expect(throws: MergeConflict()) { try strict.merge(base: base, ours: ours, theirs: theirs) }
    }
}
