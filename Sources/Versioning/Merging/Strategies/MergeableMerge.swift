/// Merges a `Mergeable` value by its own `merging` functions. Merges with
/// or without a base, as the type does.
///
/// With a favored side, a conflict keeps that whole side instead of
/// throwing.
///
/// ```swift
/// MergeableMerge<Tally>()                     // conflicts throw
/// MergeableMerge<Tally>(favoring: .theirs)    // conflicts keep theirs
/// ```
public struct MergeableMerge<Value: Mergeable & Sendable>: MergeStrategy {
    let side: MergeSide?

    public init(favoring side: MergeSide? = nil) {
        self.side = side
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        do {
            return try ours.merging(with: theirs, from: base)
        } catch {
            return try favored(ours, theirs, error)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        do {
            return try ours.merging(with: theirs)
        } catch {
            return try favored(ours, theirs, error)
        }
    }

    private func favored(_ ours: Value, _ theirs: Value, _ conflict: MergeConflict) throws(MergeConflict) -> Value {
        guard let side else { throw conflict }
        return side == .ours ? ours : theirs
    }
}
