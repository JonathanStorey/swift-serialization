/// Merges a set by what each side added and removed: an element either
/// side added is kept, and one either side removed is dropped. Works on
/// `Set` and any `OptionSet`. Without a base, different sets conflict, unless `favoring`
/// names a side.
public struct SetAlgebraMembershipMerge<Value: SetAlgebra & Sendable>: MergeStrategy {
    /// The side kept wherever the merge conflicts, or `nil` to throw.
    public var favoring: KeepMerge<Value>?

    public init(favoring: KeepMerge<Value>? = nil) {
        self.favoring = favoring
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            guard ours == theirs else { throw MergeConflict() }
            return ours
        }
    }
}

extension SetAlgebra {
    /// What both sides kept, plus what either added.
    static func mergedByMembership(base: Self, ours: Self, theirs: Self) -> Self {
        ours.intersection(theirs).union(ours.subtracting(base)).union(theirs.subtracting(base))
    }
}
