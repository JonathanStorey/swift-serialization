import Testing
@testable import Versioning

private typealias Change = JSONDifference.Change

/// Checks that `difference` turns `old` into `new` and its inverse turns
/// `new` back into `old`, then returns it for further checks.
@discardableResult
private func checkedDifference(from old: JSONRepresentation, to new: JSONRepresentation) -> JSONDifference {
    let difference = new.difference(from: old)
    #expect(old.applying(difference) == new, "\(old) → \(new)\n\(difference)")
    #expect(new.applying(difference.inverted()) == old, "\(new) ← \(old)\n\(difference)")
    return difference
}

@Suite struct JSONDifferenceTests {
    @Test func equalValuesHaveNoChanges() {
        let value: JSONRepresentation = ["a": [1, "x", ["b": nil]], "c": true]
        #expect(value.difference(from: value).isEmpty)
        #expect(value.applying(value.difference(from: value)) == value)
    }

    @Test func numbersCompareByValue() {
        let old: JSONRepresentation = ["a": .number("1"), "b": [.number("2.50"), .number("1e3")]]
        let new: JSONRepresentation = ["a": .number("1.0"), "b": [.number("2.5"), .number("1000")]]
        #expect(new.difference(from: old).isEmpty)
        #expect(!JSONRepresentation.number("1").difference(from: .number("1.5")).isEmpty)
    }

    @Test func objectKeysAddedRemovedAndReplaced() {
        let old: JSONRepresentation = ["keep": 1, "drop": "x", "change": "A"]
        let new: JSONRepresentation = ["keep": 1, "change": "B", "add": true]
        let difference = checkedDifference(from: old, to: new)
        #expect(difference.removals == [
            .remove(path: ["change"], element: "A", associatedWith: "change"),
            .remove(path: ["drop"], element: "x", associatedWith: nil),
        ])
        #expect(difference.insertions == [
            .insert(path: ["change"], element: "B", associatedWith: "change"),
            .insert(path: ["add"], element: true, associatedWith: nil),
        ])
        #expect(difference.description == """
            - $.drop: "x"
            ~ $.change: "A" → "B"
            + $.add: true
            """)
    }

    @Test func replacedKeyKeepsItsPosition() throws {
        let old: JSONRepresentation = ["a": 1, "b": 2, "c": 3]
        let new: JSONRepresentation = ["a": 1, "b": "two", "c": 3]
        let applied = try #require(old.applying(new.difference(from: old)))
        #expect(applied.description == #"{"a":1,"b":"two","c":3}"#)
    }

    @Test func changesAreDeep() {
        let old: JSONRepresentation = ["rooms": [["name": "A", "floor": 1], ["name": "B", "floor": 2]]]
        let new: JSONRepresentation = ["rooms": [["name": "A", "floor": 1], ["name": "C", "floor": 2]]]
        let difference = checkedDifference(from: old, to: new)
        #expect(difference.count == 2)
        #expect(difference.description == #"~ $.rooms[1].name: "B" → "C""#)
    }

    @Test func arrayInsertionInTheMiddle() {
        let difference = checkedDifference(from: ["a", "c"], to: ["a", "b", "c"])
        #expect(Array(difference) == [.insert(path: [1], element: "b", associatedWith: nil)])
    }

    @Test func arrayRemoval() {
        let difference = checkedDifference(from: [1, 2, 3, 4], to: [1, 4])
        #expect(difference.removals == [
            .remove(path: [2], element: 3, associatedWith: nil),
            .remove(path: [1], element: 2, associatedWith: nil),
        ])
        #expect(difference.insertions.isEmpty)
    }

    @Test func movesAreLinked() {
        let difference = checkedDifference(from: ["x", "y", "z"], to: ["z", "x", "y"])
        #expect(Array(difference) == [
            .remove(path: [2], element: "z", associatedWith: .index(0)),
            .insert(path: [0], element: "z", associatedWith: .index(2)),
        ])
        #expect(difference.description == #"> $[2] → $[0]: "z""#)
    }

    /// Two encodings of the same set differ only in order, so every change
    /// is a move.
    @Test func reorderedSetIsOnlyMoves() {
        let difference = checkedDifference(from: [1, 2, 3, 4, 5], to: [4, 2, 5, 1, 3])
        let allMoves = difference.allSatisfy { change in
            let (path, element, associated) = change.parts
            guard let associated else { return false }
            let source: JSONRepresentation = [1, 2, 3, 4, 5]
            let target: JSONRepresentation = [4, 2, 5, 1, 3]
            let partner = JSONRepresentation.Path(path.dropLast()) + [associated]
            return element == (change.isRemoval ? target[partner] : source[partner])
        }
        #expect(allMoves)
    }

    @Test func renamedKeyIsLinked() {
        let difference = checkedDifference(from: ["nickname": ["first": "Ada"]], to: ["alias": ["first": "Ada"]])
        #expect(Array(difference) == [
            .remove(path: ["nickname"], element: ["first": "Ada"], associatedWith: "alias"),
            .insert(path: ["alias"], element: ["first": "Ada"], associatedWith: "nickname"),
        ])
        #expect(difference.description == #"> $.nickname → $.alias: {"first":"Ada"}"#)
    }

    @Test func typeChangeIsAReplacement() {
        let difference = checkedDifference(from: ["a": "1"], to: ["a": 1])
        #expect(difference.description == #"~ $.a: "1" → 1"#)
        checkedDifference(from: ["a": [1]], to: ["a": ["b": 1]])
        checkedDifference(from: [[1]], to: [["x": 1]])
    }

    @Test func wholeValueReplacement() {
        let difference = checkedDifference(from: "old", to: 42)
        #expect(Array(difference) == [
            .remove(path: [], element: "old", associatedWith: nil),
            .insert(path: [], element: 42, associatedWith: nil),
        ])
        #expect(difference.description == #"~ $: "old" → 42"#)
        checkedDifference(from: [1, 2], to: ["a": 1])
        checkedDifference(from: nil, to: [])
    }

    /// A group moves to a new index while its own array changes, so the
    /// removal and insertion paths differ above the changed element.
    @Test func changesInsideAnElementThatShifted() {
        checkedDifference(
            from: ["groups": [["tags": ["a", "b"], "id": 1], ["id": 2]]],
            to: ["groups": [["id": 0], ["tags": ["b", "a", "c"], "id": 1], ["id": 2, "x": nil]]]
        )
        checkedDifference(from: [[1, 2], [3, 4], [5]], to: [[0], [1, 2, 9], [4, 3], [5, 6]])
    }

    @Test func applyingToTheWrongValueFails() {
        let difference = (["a": 2] as JSONRepresentation).difference(from: ["a": 1])
        #expect((["a": 5] as JSONRepresentation).applying(difference) == nil)
        #expect((["b": 1] as JSONRepresentation).applying(difference) == nil)
        #expect(([1] as JSONRepresentation).applying(difference) == nil)
        let insertion = (["a": 1, "b": 2] as JSONRepresentation).difference(from: ["a": 1])
        #expect((["a": 1, "b": 3] as JSONRepresentation).applying(insertion) == nil)
    }

    @Test func collectionHoldsRemovalsThenInsertions() {
        let difference = checkedDifference(from: ["a": 1, "b": 2], to: ["b": 3, "c": 4])
        #expect(difference.count == difference.removals.count + difference.insertions.count)
        #expect(Array(difference) == difference.removals + difference.insertions)
        #expect(difference.inverted().inverted() == difference)
    }

    /// Random pairs of related values, from a fixed seed so failures repeat.
    @Test func randomValuesRoundTrip() {
        var generator = SplitMix64(seed: 2026)
        for _ in 0..<400 {
            let old = JSONRepresentation.random(depth: 3, using: &generator)
            let new = Bool.random(using: &generator)
                ? old.mutated(using: &generator)
                : JSONRepresentation.random(depth: 3, using: &generator)
            checkedDifference(from: old, to: new)
        }
    }
}

// MARK: - Helpers

private extension JSONDifference.Change {
    var isRemoval: Bool {
        if case .remove = self { true } else { false }
    }
}
