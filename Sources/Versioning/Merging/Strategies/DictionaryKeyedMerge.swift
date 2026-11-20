/// Merges a dictionary key by key, whatever the key's type. A key only one
/// side changed, added or removed keeps that side, and a key both sides
/// changed differently conflicts, unless `favoring` names a side, which
/// then replaces the whole dictionary. Needs a base.
public struct DictionaryKeyedMerge<Key: Hashable & Sendable, Element: Equatable & Sendable>: MergeStrategy {
    public typealias Value = [Key: Element]

    /// The side kept wherever the merge conflicts, or `nil` to throw.
    public var favoring: KeepMerge<[Key: Element]>?

    public init(favoring: KeepMerge<[Key: Element]>? = nil) {
        self.favoring = favoring
    }

    public func merge(base: [Key: Element], ours: [Key: Element], theirs: [Key: Element]) throws(MergeConflict) -> [Key: Element] {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            try Self.merged(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: [Key: Element], theirs: [Key: Element]) throws(MergeConflict) -> [Key: Element] {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            guard ours == theirs else { throw MergeConflict() }
            return ours
        }
    }

    private static func merged(base: [Key: Element], ours: [Key: Element], theirs: [Key: Element]) throws(MergeConflict) -> [Key: Element] {
        var merged: [Key: Element] = [:]
        for key in Set(base.keys).union(ours.keys).union(theirs.keys) {
            let (original, mine, other) = (base[key], ours[key], theirs[key])
            if mine == original {
                merged[key] = other
            } else if other == original || mine == other {
                merged[key] = mine
            } else {
                throw MergeConflict()
            }
        }
        return merged
    }
}
