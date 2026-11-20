/// Keeps one side. Merges with or without a base.
///
/// ```swift
/// KeepMerge<String>(.ours)      // a draft only this device should finish
/// KeepMerge<Int>(.theirs)       // a value the other side recomputed
/// ```
public struct KeepMerge<Value: Sendable>: MergeStrategy {
    let side: MergeSide

    public init(_ side: MergeSide) {
        self.side = side
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try merge(ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        side == .ours ? ours : theirs
    }
}
