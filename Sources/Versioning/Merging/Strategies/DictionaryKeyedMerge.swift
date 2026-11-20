/// Merges a dictionary key by key, whatever the key's type. A key only one
/// side changed, added or removed keeps that side, and a key both sides
/// changed differently conflicts. Needs a base.
public struct DictionaryKeyedMerge<Key: Hashable & Sendable, Element: Equatable & Sendable>: MergeStrategy {
    public typealias Value = [Key: Element]

    public init() {}

    public func merge(base: [Key: Element], ours: [Key: Element], theirs: [Key: Element]) throws(MergeConflict) -> [Key: Element] {
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
