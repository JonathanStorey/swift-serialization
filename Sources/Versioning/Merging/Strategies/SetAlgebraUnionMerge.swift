/// Merges a set so that no addition is lost, such as recipients. With a
/// base, it merges by membership. Without one, an addition cannot be told
/// from a removal, so it keeps every element either side has.
public struct SetAlgebraUnionMerge<Value: SetAlgebra & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        ours.union(theirs)
    }
}
