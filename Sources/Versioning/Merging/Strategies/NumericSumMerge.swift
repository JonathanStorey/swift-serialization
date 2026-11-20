/// Adds both sides' changes to the base, as a counter does, so two
/// increments both count. Needs a base. A whole number that would overflow
/// conflicts, unless `favoring` names a side.
public struct NumericSumMerge<Value: Numeric & Sendable>: MergeStrategy {
    /// The side kept wherever the merge conflicts, or `nil` to throw.
    public var favoring: KeepMerge<Value>?

    public init(favoring: KeepMerge<Value>? = nil) {
        self.favoring = favoring
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            guard let whole = ours as? any FixedWidthInteger else { return ours + theirs - base }
            guard let sum = checkedSum(whole, theirs, base) as? Value else { throw MergeConflict() }
            return sum
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            guard ours == theirs else { throw MergeConflict() }
            return ours
        }
    }
}

/// `ours + theirs - base` for a whole number, or `nil` if it overflows.
private func checkedSum<Whole: FixedWidthInteger>(_ ours: Whole, _ theirs: Any, _ base: Any) -> Whole? {
    guard let theirs = theirs as? Whole, let base = base as? Whole else { return nil }
    let (added, overflowed) = ours.addingReportingOverflow(theirs)
    let (sum, underflowed) = added.subtractingReportingOverflow(base)
    return overflowed || underflowed ? nil : sum
}
