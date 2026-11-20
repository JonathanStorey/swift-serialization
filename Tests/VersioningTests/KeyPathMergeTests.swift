import Testing
@testable import Versioning

/// A counter that merges by adding both sides' changes, and is not `Codable`.
private struct Score: Equatable, Mergeable {
    var value = 0

    func merging(with theirs: Score, from base: Score) throws(MergeConflict) -> Score {
        Score(value: value + theirs.value - base.value)
    }
}

private struct Spot: Equatable, Mergeable {
    var x = 0
    var y = 0

    func merging(with theirs: Spot, from base: Spot) throws(MergeConflict) -> Spot {
        try merging(with: theirs, from: base, using: .byKeyPath().merging(\.x).merging(\.y))
    }
}

/// Not `Codable`, so only a key-path merge can merge it by property.
private struct Board: Equatable, Mergeable {
    var title = "Title"
    var body = "the quick fox"
    var tags: Set<String> = []
    var score = Score()
    var spot = Spot()
    var note = "Unlisted"

    func merging(with theirs: Board, from base: Board) throws(MergeConflict) -> Board {
        try merging(with: theirs, from: base, using: .byKeyPath()
            .merging(\.title)
            .merging(\.body, using: .byWord())
            .merging(\.tags, using: .union())
            .merging(\.score)
            .merging(\.spot))
    }
}

private final class Folder {
    var name: String
    var count: Int

    init(name: String = "Folder", count: Int = 0) {
        self.name = name
        self.count = count
    }
}

private func merged<Value>(base: Value, ours: Value, theirs: Value, using strategy: some MergeStrategy<Value>) throws(MergeConflict) -> Value {
    try strategy.merge(base: base, ours: ours, theirs: theirs)
}

@Suite struct KeyPathMergeTests {
    @Test func eachListedPropertyMergesByItsStrategy() throws {
        let base = Board()
        var ours = base, theirs = base
        ours.title = "Ours"
        ours.body = "the slow fox"
        theirs.body = "the quick dog"
        ours.tags = ["a"]
        theirs.tags = ["b"]
        ours.score = Score(value: 2)
        theirs.score = Score(value: 3)
        theirs.note = "Theirs"
        let result = try ours.merging(with: theirs, from: base)
        #expect(result.title == "Ours")
        #expect(result.body == "the slow dog")
        #expect(result.tags == ["a", "b"])
        #expect(result.score == Score(value: 5), "A Mergeable property merges by its own merge.")
        #expect(result.note == "Unlisted", "A property it does not list keeps ours.")
    }

    @Test func aConflictReportsEveryKeyPath() {
        let base = Board()
        var ours = base, theirs = base
        ours.title = "Ours"
        theirs.title = "Theirs"
        ours.spot.x = 1
        theirs.spot.x = 2
        #expect(throws: MergeConflict(at: [\Board.title, \Board.spot.x])) { try ours.merging(with: theirs, from: base) }
    }

    @Test func favoringKeepsTheSideOnlyAtEachConflict() throws {
        let base = Board()
        var ours = base, theirs = base
        ours.title = "Ours"
        theirs.title = "Theirs"
        ours.body = "the slow fox"
        let strategy = KeyPathMerge<Board>(favoring: .theirs).merging(\.title).merging(\.body)
        let result = try merged(base: base, ours: ours, theirs: theirs, using: strategy)
        #expect(result.title == "Theirs")
        #expect(result.body == "the slow fox")
    }

    @Test func withoutABaseOnlyEqualPropertiesMerge() throws {
        let strategy = KeyPathMerge<Board>().merging(\.title)
        var theirs = Board()
        theirs.note = "Theirs"
        #expect(try strategy.merge(ours: Board(), theirs: theirs) == Board())
        theirs.title = "Theirs"
        #expect(throws: MergeConflict(at: [\Board.title])) { try strategy.merge(ours: Board(), theirs: theirs) }
    }

    @Test func aClassMergesIntoOurs() throws {
        let base = Folder(), ours = Folder(name: "Ours"), theirs = Folder(count: 4)
        let strategy = KeyPathMerge<Folder>().merging(\.name).merging(\.count, using: .sum())
        let result = try strategy.merge(base: base, ours: ours, theirs: theirs)
        #expect(result === ours)
        #expect((result.name, result.count) == ("Ours", 4))
    }

    @Test func aConflictWritesNothing() {
        let base = Folder(), ours = Folder(name: "Ours"), theirs = Folder(name: "Theirs", count: 4)
        let strategy = KeyPathMerge<Folder>().merging(\.count).merging(\.name)
        #expect(throws: MergeConflict(at: [\Folder.name])) { try strategy.merge(base: base, ours: ours, theirs: theirs) }
        #expect(ours.count == 0)
    }

    @Test func aKeyPathConflictInsideACodingPathIsAtThatPath() {
        #expect(MergeConflict(at: [\Board.title]).inside(["board"]) == MergeConflict(at: [["board"]]))
    }
}
