/// Merges an array of `Identifiable` elements by `id`, so each element
/// merges with its own other version wherever it moved.
///
/// - An element only one side changed keeps that side.
/// - An element both sides changed merges by its own merge if it is
///   ``Mergeable``, otherwise property by property, as ``PropertyMerge``
///   does.
/// - An element either side added is kept. Theirs goes after the element it
///   follows in theirs.
/// - An element one side removed is removed, unless the other side changed
///   it, which conflicts.
///
/// The order is ours, with theirs's additions placed among it. Each
/// version's ids must be unique. Without a base, an element only one side
/// has conflicts. With `favoring`, each conflicting element takes that side.
///
/// ```swift
/// try IdentifiedElementMerge<Task>(favoring: .theirs).merge(base: base, ours: mine, theirs: yours)
/// ```
public struct IdentifiedElementMerge<Element: Identifiable & Codable>: MergeStrategy {
    public typealias Value = [Element]

    /// The side kept at each conflicting element, or `nil` to throw.
    public var favoring: KeepMerge<[Element]>?

    public init(favoring: KeepMerge<[Element]>? = nil) {
        self.favoring = favoring
    }

    public func merge(base: [Element], ours: [Element], theirs: [Element]) throws(MergeConflict) -> [Element] {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            try merged(ours, theirs, base: Self.byID(base))
        }
    }

    public func merge(ours: [Element], theirs: [Element]) throws(MergeConflict) -> [Element] {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            try merged(ours, theirs, base: nil)
        }
    }
}

private extension IdentifiedElementMerge {
    func merged(_ ours: [Element], _ theirs: [Element], base original: [Element.ID: Element]?) throws(MergeConflict) -> [Element] {
        let mine = try Self.byID(ours)
        let other = try Self.byID(theirs)
        var merged: [Element] = []
        for element in ours {
            if let yours = other[element.id] {
                merged.append(try Element.mergedElement(element, yours, base: original?[element.id], favoring: favoring?.retyped()))
            } else if try keeps(element, changedBy: KeepMerge<Element>.ours, base: original) {
                merged.append(element)
            }
        }
        for (offset, element) in theirs.enumerated() where mine[element.id] == nil {
            guard try keeps(element, changedBy: KeepMerge<Element>.theirs, base: original) else { continue }
            let predecessor = theirs[..<offset].last { earlier in merged.contains { $0.id == earlier.id } }
            let index = predecessor.flatMap { earlier in merged.firstIndex { $0.id == earlier.id } }.map { $0 + 1 } ?? 0
            merged.insert(element, at: index)
        }
        return merged
    }

    /// Whether an element only `changer` has stays: it does if that side
    /// added it, not if the other side removed it unchanged, and by
    /// `favoring` if the other side removed what this side changed.
    func keeps(_ element: Element, changedBy changer: KeepMerge<Element>, base original: [Element.ID: Element]?) throws(MergeConflict) -> Bool {
        if let original {
            guard let was = original[element.id] else { return true }
            if element.encodesLike(was) { return false }
        }
        guard let favoring else { throw MergeConflict() }
        return favoring.keeps(changedBy: changer)
    }

    static func byID(_ elements: [Element]) throws(MergeConflict) -> [Element.ID: Element] {
        var byID: [Element.ID: Element] = [:]
        for element in elements {
            guard byID.updateValue(element, forKey: element.id) == nil else { throw MergeConflict() }
        }
        return byID
    }
}

extension Encodable where Self: Decodable {
    /// This value merged with `theirs` by its own merge if it is
    /// `Mergeable`, otherwise property by property. A conflict takes `side`,
    /// or throws without one.
    static func mergedElement(_ ours: Self, _ theirs: Self, base: Self?, favoring side: KeepMerge<Self>?) throws(MergeConflict) -> Self {
        if let base {
            if theirs.encodesLike(base) { return ours }
            if ours.encodesLike(base) { return theirs }
        }
        if ours.encodesLike(theirs) { return ours }
        do {
            if let mergeable = Self.self as? any Mergeable.Type, let value = try mergeable.merged(ours, theirs, base: base) as? Self {
                return value
            }
            let strategy = PropertyMerge<Self>(favoring: side)
            guard let base else { return try strategy.merge(ours: ours, theirs: theirs) }
            return try strategy.merge(base: base, ours: ours, theirs: theirs)
        } catch {
            guard let side else { throw MergeConflict() }
            return try side.merge(ours: ours, theirs: theirs)
        }
    }

    /// Whether this value and `other` encode alike.
    func encodesLike(_ other: Self) -> Bool {
        guard let lhs = try? JSONRepresentation(self), let rhs = try? JSONRepresentation(other) else { return false }
        return lhs.isEquivalent(to: rhs)
    }
}
