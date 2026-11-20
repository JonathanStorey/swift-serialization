/// Merges a set by what each side added and removed: an element either
/// side added is kept, and one either side removed is dropped. Works on
/// `Set` and any `OptionSet`. Needs a base.
public struct SetAlgebraMembershipMerge<Value: SetAlgebra & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }
}

extension SetAlgebra {
    /// What both sides kept, plus what either added.
    static func mergedByMembership(base: Self, ours: Self, theirs: Self) -> Self {
        ours.intersection(theirs).union(ours.subtracting(base)).union(theirs.subtracting(base))
    }
}
