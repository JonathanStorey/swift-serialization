/// Keeps one side: ours, the local version, or theirs, the incoming one.
/// Merges with or without a base.
///
/// ```swift
/// let strategy: KeepMerge<String> = .ours
/// try strategy.merge(base: "a", ours: "b", theirs: "c")   // "b"
/// ```
public enum KeepMerge<Value: Sendable>: MergeStrategy {
    case ours
    case theirs

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try merge(ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        switch self {
        case .ours: ours
        case .theirs: theirs
        }
    }
}
