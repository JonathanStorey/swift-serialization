/// Adds both sides' changes to the base, as a counter does, so two
/// increments both count. Needs a base. A whole number that would overflow
/// conflicts.
public struct NumericSumMerge<Value: Numeric & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        guard let whole = ours as? any FixedWidthInteger else { return ours + theirs - base }
        guard let sum = checkedSum(whole, theirs, base) as? Value else { throw MergeConflict() }
        return sum
    }
}

/// `ours + theirs - base` for a whole number, or `nil` if it overflows.
private func checkedSum<Whole: FixedWidthInteger>(_ ours: Whole, _ theirs: Any, _ base: Any) -> Whole? {
    guard let theirs = theirs as? Whole, let base = base as? Whole else { return nil }
    let (added, overflowed) = ours.addingReportingOverflow(theirs)
    let (sum, underflowed) = added.subtractingReportingOverflow(base)
    return overflowed || underflowed ? nil : sum
}
