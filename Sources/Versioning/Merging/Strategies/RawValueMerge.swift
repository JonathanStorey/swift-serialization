/// Merges a `RawRepresentable` value by merging its raw value with another
/// strategy. A merged raw value that `init(rawValue:)` rejects, such as one
/// that is not an enum's case, conflicts.
///
/// ```swift
/// struct Views: RawRepresentable, Codable, Mergeable {
///     var rawValue: Int
///     func merging(with theirs: Views, from base: Views) throws(MergeConflict) -> Views {
///         try merging(with: theirs, from: base, using: .rawValue(.sum()))
///     }
/// }
/// ```
public struct RawValueMerge<Value: RawRepresentable, Strategy: MergeStrategy>: MergeStrategy
where Strategy.Value == Value.RawValue {
    let strategy: Strategy

    public init(_ strategy: Strategy) {
        self.strategy = strategy
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try Self.value(strategy.merge(base: base.rawValue, ours: ours.rawValue, theirs: theirs.rawValue))
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try Self.value(strategy.merge(ours: ours.rawValue, theirs: theirs.rawValue))
    }

    private static func value(_ rawValue: Value.RawValue) throws(MergeConflict) -> Value {
        guard let value = Value(rawValue: rawValue) else { throw MergeConflict() }
        return value
    }
}
