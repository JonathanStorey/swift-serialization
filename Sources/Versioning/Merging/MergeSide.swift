/// A side of a merge, which strategies such as `KeepMerge` name.
public enum MergeSide: Hashable, Sendable {
    case ours
    case theirs
}
