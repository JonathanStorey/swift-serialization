/// How a value merges when both sides changed it. A strategy is a plain
/// value, so it can hold settings of its own.
///
/// A strategy decides only when both sides changed a value. Where only one
/// side changed it, the caller keeps that side, as the JSON merge does at
/// every node. `KeepMerge(.ours)` called on a value only theirs changed
/// still keeps ours.
///
/// Implement the three-way merge, and the two-way merge too if the strategy
/// needs no common ancestor.
///
/// ```swift
/// struct LongerMerge: MergeStrategy {
///     func merge(base: String, ours: String, theirs: String) throws(MergeConflict) -> String {
///         ours.count >= theirs.count ? ours : theirs
///     }
/// }
/// ```
///
/// A strategy throws ``MergeConflict`` when the versions cannot be merged.
public protocol MergeStrategy<Value>: Sendable {
    associatedtype Value: Sendable

    /// The merged value, knowing the versions' common ancestor.
    func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value
    /// The merged value without a common ancestor.
    func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value
}

extension MergeStrategy {
    /// Without a base, a strategy cannot tell what either side changed, so
    /// the versions conflict.
    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        throw MergeConflict()
    }
}

extension MergeStrategy where Value: Equatable {
    /// Without a base, equal versions merge, and any others conflict.
    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        guard ours == theirs else { throw MergeConflict() }
        return ours
    }
}

/// Both sides changed a value differently, and the strategy cannot settle
/// it. It carries nothing, as `CancellationError` does.
public struct MergeConflict: Error, Hashable, Sendable {
    public init() {}
}
