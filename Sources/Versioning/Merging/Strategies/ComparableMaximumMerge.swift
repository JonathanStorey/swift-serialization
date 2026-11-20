/// Keeps the larger value, by the type's own `<`: a high score, the
/// furthest progress, the latest date. Merges with or without a base.
public struct ComparableMaximumMerge<Value: Comparable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try merge(ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        Swift.max(ours, theirs)
    }
}
