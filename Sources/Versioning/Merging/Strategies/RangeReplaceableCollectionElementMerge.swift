/// Merges a collection element by element, like a three-way merge of
/// lines: an element either side removed is removed, and what each side
/// inserted goes where it was inserted, ours first. Elements match by `==`,
/// so an element both sides replaced differently conflicts. A `String`
/// merges character by character. Needs a base.
public struct RangeReplaceableCollectionElementMerge<Value: RangeReplaceableCollection & Sendable>: MergeStrategy
where Value.Element: Equatable {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        Value(try Array(ours).mergingElements(with: Array(theirs), from: Array(base)))
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        guard ours.elementsEqual(theirs) else { throw MergeConflict() }
        return ours
    }
}

extension Array where Element: Equatable {
    /// Merges element by element, like a three-way merge of lines. An
    /// element either side removed is removed, and what each side inserted
    /// goes where it was inserted, ours first. Where both sides replaced one
    /// element with one element each, `replaced` merges ours, theirs and the
    /// base element, and by default only equal replacements merge. Any other
    /// replacement both sides made conflicts.
    func mergingElements(
        with theirs: [Element], from base: [Element],
        replaced: (Element, Element, Element) throws(MergeConflict) -> Element = { ours, theirs, _ throws(MergeConflict) in
            guard ours == theirs else { throw MergeConflict() }
            return ours
        }
    ) throws(MergeConflict) -> [Element] {
        let mine = Edits(self, from: base)
        let other = Edits(theirs, from: base)
        var merged: [Element] = []
        for index in 0...base.count {
            let (inserted, theirsInserted) = (mine.inserted[index], other.inserted[index])
            if inserted == theirsInserted || theirsInserted.isEmpty {
                merged += inserted
            } else if inserted.isEmpty {
                merged += theirsInserted
            } else if index < base.count, mine.removed.contains(index), other.removed.contains(index) {
                // Both replaced the element that follows.
                guard inserted.count == 1, theirsInserted.count == 1 else { throw MergeConflict() }
                merged.append(try replaced(inserted[0], theirsInserted[0], base[index]))
            } else {
                merged += inserted + theirsInserted
            }
            if index < base.count, !mine.removed.contains(index), !other.removed.contains(index) {
                merged.append(base[index])
            }
        }
        return merged
    }
}

/// One side's changes to an array: the base elements it removed, and what it
/// inserted before each base element, with the last slot for what it added
/// at the end. A changed element is removed, with its new version inserted
/// before it.
private struct Edits<Element: Equatable> {
    var removed: Set<Int> = []
    var inserted: [[Element]]

    init(_ side: [Element], from base: [Element]) {
        inserted = Array(repeating: [], count: base.count + 1)
        var insertedOffsets: Set<Int> = []
        for change in side.difference(from: base) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }
        // The side's other elements are the base's kept ones, in order.
        var next = 0
        for index in 0...base.count {
            while insertedOffsets.contains(next) {
                inserted[index].append(side[next])
                next += 1
            }
            if index < base.count, !removed.contains(index) { next += 1 }
        }
    }
}
