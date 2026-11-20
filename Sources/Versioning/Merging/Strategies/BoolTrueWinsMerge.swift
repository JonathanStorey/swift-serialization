/// `true` if either side is, for a flag anyone can set, such as "read".
/// Merges with or without a base.
public struct BoolTrueWinsMerge: MergeStrategy {
    public init() {}

    public func merge(base: Bool, ours: Bool, theirs: Bool) throws(MergeConflict) -> Bool {
        ours || theirs
    }

    public func merge(ours: Bool, theirs: Bool) throws(MergeConflict) -> Bool {
        ours || theirs
    }
}
