// Dot syntax for the package's strategies, wherever a strategy is expected,
// as `ButtonStyle` has `.bordered`:
//
//     try ours.merging(with: theirs, from: base, using: .maximum())
//
// Each is a generic function rather than a property. Swift rejects
// `where Self == ComparableMaximumMerge<Value>` on a protocol extension as a
// recursive constraint, so the value type must come in as a generic
// parameter, and only a function can declare one.

extension MergeStrategy {
    /// ``KeepMerge``: the named side, `.ours` or `.theirs`.
    public static func keep<V>(_ side: KeepMerge<V>) -> Self where Self == KeepMerge<V> {
        side
    }

    /// ``ComparableMaximumMerge``: the larger value.
    public static func maximum<V: Comparable & Sendable>() -> Self where Self == ComparableMaximumMerge<V> {
        Self()
    }

    /// ``NumericSumMerge``: a counter, so both sides' changes count.
    public static func sum<V: Numeric & Sendable>() -> Self where Self == NumericSumMerge<V> {
        Self()
    }

    /// ``BoolTrueWinsMerge``: `true` if either side is.
    public static func trueWins() -> Self where Self == BoolTrueWinsMerge {
        Self()
    }

    /// ``SetAlgebraMembershipMerge``: what each side added and removed.
    public static func byMembership<V: SetAlgebra & Sendable>() -> Self where Self == SetAlgebraMembershipMerge<V> {
        Self()
    }

    /// ``SetAlgebraUnionMerge``: as membership, or every element without a
    /// base.
    public static func union<V: SetAlgebra & Sendable>() -> Self where Self == SetAlgebraUnionMerge<V> {
        Self()
    }

    /// ``DictionaryKeyedMerge``: a dictionary key by key.
    public static func byKey<Key: Hashable & Sendable, Element: Equatable & Sendable>() -> Self where Self == DictionaryKeyedMerge<Key, Element> {
        Self()
    }

    /// ``RangeReplaceableCollectionElementMerge``: element by element, like
    /// lines, or text character by character.
    public static func byElement<V: RangeReplaceableCollection & Sendable>() -> Self where V.Element: Equatable, Self == RangeReplaceableCollectionElementMerge<V> {
        Self()
    }

    /// ``StringWordMerge``: text word by word.
    public static func byWord<V: StringProtocol & Sendable>() -> Self where Self == StringWordMerge<V> {
        Self()
    }

    /// ``JSONMerge``: node by node, throwing on any conflict, or keeping the
    /// named side at each conflict and every other change from both sides.
    public static func json<V: Codable>(onConflict side: KeepMerge<V>? = nil) -> Self where Self == JSONMerge<V> {
        Self(onConflict: side)
    }

    /// ``RawValueMerge``: the raw value, merged by `strategy`.
    public static func rawValue<V: RawRepresentable, Strategy: MergeStrategy>(_ strategy: Strategy) -> Self
    where Strategy.Value == V.RawValue, Self == RawValueMerge<V, Strategy> {
        Self(strategy)
    }
}
