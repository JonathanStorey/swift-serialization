/// Keeps one side: ours, the local version, or theirs, the incoming one.
/// Merges with or without a base.
///
/// ```swift
/// let strategy: KeepMerge<String> = .ours
/// try strategy.merge(base: "a", ours: "b", theirs: "c")   // "b"
/// ```
public enum KeepMerge<Value>: MergeStrategy {
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

extension Optional {
    /// The result of `merge`, or, where it conflicts, the favored side.
    /// Without a side, the conflict stands.
    func resolving<V>(ours: V, theirs: V, _ merge: () throws(MergeConflict) -> V) throws(MergeConflict) -> V
    where Wrapped == KeepMerge<V> {
        do {
            return try merge()
        } catch let conflict as MergeConflict {
            guard let side = self else { throw conflict }
            return try side.merge(ours: ours, theirs: theirs)
        } catch {
            guard let side = self else { throw MergeConflict() }
            return try side.merge(ours: ours, theirs: theirs)
        }
    }
}

extension KeepMerge {
    /// The same side, for another type.
    func retyped<Other>() -> KeepMerge<Other> {
        switch self {
        case .ours: .ours
        case .theirs: .theirs
        }
    }

    /// Whether a value that `changer` changed and the other side removed
    /// stays: it does when this side is the one that changed it.
    func keeps<Other>(changedBy changer: KeepMerge<Other>) -> Bool {
        switch (self, changer) {
        case (.ours, .ours), (.theirs, .theirs): true
        default: false
        }
    }
}
