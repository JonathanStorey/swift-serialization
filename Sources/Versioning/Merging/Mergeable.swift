/// A type that merges with another version of itself.
///
/// Implement the three-way merge, and the two-way merge too if the type can
/// merge without a common ancestor. The mutating `merge` functions come with
/// them.
///
/// ```swift
/// let merged = try ours.merging(with: theirs, from: base)
/// try ours.merge(with: theirs)
/// ```
public protocol Mergeable {
    /// This version merged with `theirs`, knowing their common ancestor.
    func merging(with theirs: Self, from base: Self) throws(MergeConflict) -> Self
    /// This version merged with `theirs`, without a common ancestor.
    func merging(with theirs: Self) throws(MergeConflict) -> Self
}

extension Mergeable {
    /// Without a base, the versions conflict.
    public func merging(with theirs: Self) throws(MergeConflict) -> Self {
        throw MergeConflict()
    }

    /// Merges `theirs` into this version, knowing their common ancestor. On a
    /// conflict, this version is left unchanged.
    public mutating func merge(with theirs: Self, from base: Self) throws(MergeConflict) {
        self = try merging(with: theirs, from: base)
    }

    /// Merges `theirs` into this version without a common ancestor. On a
    /// conflict, this version is left unchanged.
    public mutating func merge(with theirs: Self) throws(MergeConflict) {
        self = try merging(with: theirs)
    }
}

extension Mergeable where Self: Equatable {
    /// Without a base, equal versions merge, and any others conflict.
    public func merging(with theirs: Self) throws(MergeConflict) -> Self {
        guard self == theirs else { throw MergeConflict() }
        return self
    }
}
