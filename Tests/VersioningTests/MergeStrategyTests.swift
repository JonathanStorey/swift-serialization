import Testing
@testable import Versioning

/// Keeps the longer text when both sides changed it.
private struct LongerMerge: MergeStrategy {
    func merge(base: String, ours: String, theirs: String) throws(MergeConflict) -> String {
        ours.count >= theirs.count ? ours : theirs
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
    @Test func theStrategyDecidesAThreeWayMerge() throws {
        #expect(try LongerMerge().merge(base: "Draft", ours: "Longer one", theirs: "Short") == "Longer one")
        #expect(throws: MergeConflict()) { try RefuseMerge().merge(base: 1, ours: 2, theirs: 3) }
    }

    @Test func withoutABaseEqualValuesMergeAndOthersConflict() throws {
        #expect(try LongerMerge().merge(ours: "Same", theirs: "Same") == "Same")
        #expect(throws: MergeConflict()) { try LongerMerge().merge(ours: "Ours", theirs: "Theirs") }
    }

    @Test func aStrategyCanMergeWithoutABase() throws {
        #expect(try LargerBoxMerge().merge(ours: Box(1), theirs: Box(4)).number == 4)
    }

    @Test func withoutABaseValuesThatAreNotEquatableConflictByDefault() {
        #expect(throws: MergeConflict()) { try BaseOnlyBoxMerge().merge(ours: Box(1), theirs: Box(2)) }
    }
}
