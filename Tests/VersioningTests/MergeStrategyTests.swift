import Testing
@testable import Versioning

/// Keeps the longer text when both sides changed it.
private struct LongerMerge: MergeStrategy {
    func merge(base: String, ours: String, theirs: String) throws(MergeConflict) -> String {
        ours.count >= theirs.count ? ours : theirs
    }
}

/// Adds both sides' changes, as a counter does.
private struct SumMerge: MergeStrategy {
    func merge(base: Int, ours: Int, theirs: Int) throws(MergeConflict) -> Int {
        ours + theirs - base
    }
}

/// Never merges, to test conflicts.
private struct RefuseMerge: MergeStrategy {
    func merge(base: Int, ours: Int, theirs: Int) throws(MergeConflict) -> Int {
        throw MergeConflict()
    }
}

/// A value that is not `Equatable`.
private final class Box: Sendable {
    let number: Int
    init(_ number: Int) { self.number = number }
}

/// Keeps the larger box, with or without a base.
private struct LargerBoxMerge: MergeStrategy {
    func merge(base: Box, ours: Box, theirs: Box) throws(MergeConflict) -> Box {
        try merge(ours: ours, theirs: theirs)
    }

    func merge(ours: Box, theirs: Box) throws(MergeConflict) -> Box {
        ours.number >= theirs.number ? ours : theirs
    }
}

/// Uses the default two-way merge of a value that is not `Equatable`.
private struct BaseOnlyBoxMerge: MergeStrategy {
    func merge(base: Box, ours: Box, theirs: Box) throws(MergeConflict) -> Box { ours }
}

@Suite struct MergeStrategyTests {
    @Test func aSideOnlyOneChangedIsKept() throws {
        let title = MergedProperty("Draft", LongerMerge())
        #expect(try title.merging(with: "Final", from: "Draft") == "Final", "Only theirs changed.")
        #expect(try MergedProperty("Mine", LongerMerge()).merging(with: "Draft", from: "Draft") == "Mine", "Only ours changed.")
    }

    @Test func theStrategyDecidesWhenBothChanged() throws {
        #expect(try MergedProperty("Longer one", LongerMerge()).merging(with: "Short", from: "Draft") == "Longer one")
        #expect(try MergedProperty(6, SumMerge()).merging(with: 6, from: 5) == 7, "Both raised the counter by 1, even to the same value.")
    }

    @Test func conflictsThrowAndLeaveTheValueUnchanged() {
        var count = MergedProperty(2, RefuseMerge())
        #expect(throws: MergeConflict()) { try count.merge(with: 3, from: 1) }
        #expect(count.value == 2)
    }

    @Test func mutatingMergeStoresTheResult() throws {
        var count = MergedProperty(6, SumMerge())
        try count.merge(with: 8, from: 5)
        #expect(count.value == 9)
    }

    @Test func withoutABaseEqualValuesMergeAndOthersConflict() throws {
        #expect(try MergedProperty("Same", LongerMerge()).merging(with: "Same") == "Same")
        #expect(throws: MergeConflict()) { try MergedProperty("Ours", LongerMerge()).merging(with: "Theirs") }
    }

    @Test func aStrategyCanMergeWithoutABase() throws {
        #expect(try MergedProperty(Box(1), LargerBoxMerge()).merging(with: Box(4)).number == 4)
    }

    @Test func valuesThatAreNotEquatableLeaveEveryMergeToTheStrategy() throws {
        let base = Box(1)
        let merged = try MergedProperty(base, LargerBoxMerge()).merging(with: Box(3), from: base)
        #expect(merged.number == 3)
        #expect(throws: MergeConflict()) { try MergedProperty(Box(1), BaseOnlyBoxMerge()).merging(with: Box(2)) }
    }
}
