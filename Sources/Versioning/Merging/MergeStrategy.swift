/// How a value merges when both sides changed it. A strategy is a plain
/// value, so it can hold settings of its own.
///
/// A strategy decides only when both sides changed a value. Where only one
/// side changed it, the caller keeps that side, as the JSON merge does at
/// every node. `KeepMerge.ours` called on a value only theirs changed
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
///
/// The package's strategies have dot syntax wherever a strategy is
/// expected. Each one that can conflict takes `favoring:`, the side kept
/// wherever it does:
///
/// ```swift
/// try ours.merging(with: theirs, from: base, using: .byWord(favoring: .ours))
/// ```
public protocol MergeStrategy<Value>: Sendable {
    /// The type merged. It need not be `Sendable`, so a strategy can merge
    /// a class such as a SwiftData model.
    associatedtype Value

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
