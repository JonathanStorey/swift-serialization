import Foundation
import Testing
@testable import Versioning

private struct Card: Codable, Equatable, Mergeable {
    var title = "Title"
    var body = "Body"
}

private struct Views: RawRepresentable, Codable, Equatable, Mergeable {
    var rawValue: Int

    func merging(with theirs: Views, from base: Views) throws(MergeConflict) -> Views {
        try merging(with: theirs, from: base, using: .rawValue(.sum()))
    }
}

private enum Stage: String, Codable {
    case draft, review, published
}

private enum Level: Int, Codable {
    case low = 1, high = 2
}

/// Merges by `strategy`, so each call resolves its dot syntax against
/// `some MergeStrategy<Value>`.
private func merged<Value>(base: Value, ours: Value, theirs: Value, using strategy: some MergeStrategy<Value>) throws(MergeConflict) -> Value {
    try strategy.merge(base: base, ours: ours, theirs: theirs)
}

private func merged<Value>(ours: Value, theirs: Value, using strategy: some MergeStrategy<Value>) throws(MergeConflict) -> Value {
    try strategy.merge(ours: ours, theirs: theirs)
}

@Suite struct MergeStrategyDotSyntaxTests {
    @Test func namesEachStrategy() throws {
        #expect(try merged(base: "a", ours: "b", theirs: "c", using: .keep(.theirs)) == "c")
        #expect(try merged(ours: 3, theirs: 7, using: .maximum()) == 7)
        #expect(try merged(base: 3, ours: 5, theirs: 4, using: .sum()) == 6)
        #expect(try merged(base: false, ours: true, theirs: false, using: .trueWins()))
        #expect(try merged(ours: Set(["a"]), theirs: Set(["b"]), using: .union()) == ["a", "b"])
        #expect(try merged(base: Set(["a", "b"]), ours: Set(["a"]), theirs: Set(["a", "b", "c"]), using: .byMembership()) == ["a", "c"])
        #expect(try merged(base: ["x": 1], ours: ["x": 2], theirs: ["x": 1, "y": 3], using: .byKey()) == ["x": 2, "y": 3])
        #expect(try merged(base: [1, 2], ours: [0, 1, 2], theirs: [1, 2, 3], using: .byElement()) == [0, 1, 2, 3])
        #expect(try merged(base: "the quick fox", ours: "the slow fox", theirs: "the quick dog", using: .byWord()) == "the slow dog")
    }

    @Test func favoringKeepsTheSideOnlyWhereTheStrategyConflicts() throws {
        #expect(try merged(base: "the quick fox", ours: "the slow fox", theirs: "the quick dog", using: .byWord(favoring: .ours)) == "the slow dog")
        #expect(try merged(base: "the quick fox", ours: "the slow fox", theirs: "the fast fox", using: .byWord(favoring: .ours)) == "the slow fox")
        #expect(try merged(ours: "ours", theirs: "theirs", using: .byWord(favoring: .theirs)) == "theirs", "Without a base, the word merge conflicts.")
        #expect(try merged(base: UInt8(100), ours: UInt8(200), theirs: UInt8(210), using: .sum(favoring: .theirs)) == 210, "An overflow keeps theirs.")
        #expect(try merged(base: ["x": 1], ours: ["x": 2], theirs: ["x": 3], using: .byKey(favoring: .theirs)) == ["x": 3])
        #expect(try merged(ours: Set(["a"]), theirs: Set(["b"]), using: .byMembership(favoring: .ours)) == ["a"])
        #expect(try merged(base: [1], ours: [2], theirs: [3], using: .byElement(favoring: .ours)) == [2])
        #expect(throws: MergeConflict()) {
            try merged(base: "the quick fox", ours: "the slow fox", theirs: "the fast fox", using: .byWord())
        }
    }

    @Test func favoringIsASettableProperty() throws {
        var strategy = StringWordMerge<String>()
        #expect(strategy.favoring == nil)
        strategy.favoring = .theirs
        #expect(try strategy.merge(base: "a b", ours: "a c", theirs: "a d") == "a d")
    }

    @Test func rawValueMergesTheRawValue() throws {
        #expect(try merged(base: Views(rawValue: 3), ours: Views(rawValue: 5), theirs: Views(rawValue: 4), using: .rawValue(.sum())) == Views(rawValue: 6))
        #expect(try merged(base: Stage.draft, ours: .review, theirs: .published, using: .rawValue(.maximum())) == .review, "\"review\" sorts after \"published\".")
    }

    @Test func aRawValueThatIsNotACaseConflicts() {
        #expect(throws: MergeConflict()) {
            try merged(base: Level.low, ours: .high, theirs: .high, using: .rawValue(.sum()))  // 2 + 2 - 1 = 3
        }
    }

    @Test func jsonKeepsASideOnlyAtEachConflict() throws {
        let base = Card()
        var ours = base, theirs = base
        ours.title = "Ours"
        theirs.title = "Theirs"
        ours.body = "Ours"
        #expect(try merged(base: base, ours: ours, theirs: theirs, using: .byProperty(favoring: .theirs)) == Card(title: "Theirs", body: "Ours"))
        #expect(throws: MergeConflict()) { try merged(base: base, ours: ours, theirs: theirs, using: .byProperty()) }
    }
}

@Suite struct MergeableStrategyTests {
    @Test func aCodableTypeMergesWithNothingToWrite() throws {
        let base = Card()
        var ours = base, theirs = base
        ours.title = "Ours"
        theirs.body = "Theirs"
        #expect(try ours.merging(with: theirs, from: base) == Card(title: "Ours", body: "Theirs"))
        #expect(try base.merging(with: base) == base)
        #expect(throws: MergeConflict()) { try ours.merging(with: theirs) }
    }

    @Test func aTypeMergesByTheStrategyItNames() throws {
        var views = Views(rawValue: 5)
        try views.merge(with: Views(rawValue: 4), from: Views(rawValue: 3))
        #expect(views == Views(rawValue: 6))
    }

    @Test func aCallerCanChooseTheStrategy() throws {
        let base = Card()
        var ours = base, theirs = base
        ours.title = "Ours"
        theirs.title = "Theirs"
        #expect(throws: MergeConflict()) { try ours.merging(with: theirs, from: base) }
        #expect(try ours.merging(with: theirs, from: base, using: .byProperty(favoring: .theirs)).title == "Theirs")
        #expect(try ours.merging(with: theirs, using: .keep(.ours)) == ours)
    }
}
