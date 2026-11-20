// Dot syntax for the package's strategies, wherever a strategy is expected,
// as `ButtonStyle` has `.bordered`:
//
//     try ours.merging(with: theirs, from: base, using: .maximum)

extension MergeStrategy {
    /// ``KeepMerge``: the named side, `.ours` or `.theirs`.
    public static func keep(_ side: KeepMerge<Value>) -> Self where Self == KeepMerge<Value> {
        side
    }
}

extension MergeStrategy where Value: Comparable & Sendable, Self == ComparableMaximumMerge<Value> {
    /// ``ComparableMaximumMerge``: the larger value.
    public static var maximum: Self { Self() }
}

extension MergeStrategy where Value: Numeric & Sendable, Self == NumericSumMerge<Value> {
    /// ``NumericSumMerge``: a counter, so both sides' changes count.
    public static var sum: Self { Self() }
}

extension MergeStrategy where Self == BoolTrueWinsMerge {
    /// ``BoolTrueWinsMerge``: `true` if either side is.
    public static var trueWins: Self { Self() }
}

extension MergeStrategy where Value: SetAlgebra & Sendable, Self == SetAlgebraMembershipMerge<Value> {
    /// ``SetAlgebraMembershipMerge``: what each side added and removed.
    public static var byMembership: Self { Self() }
}

extension MergeStrategy where Value: SetAlgebra & Sendable, Self == SetAlgebraUnionMerge<Value> {
    /// ``SetAlgebraUnionMerge``: as membership, or every element without a
    /// base.
    public static var union: Self { Self() }
}

extension MergeStrategy {
    /// ``DictionaryKeyedMerge``: a dictionary key by key.
    public static func byKey<Key: Hashable & Sendable, Element: Equatable & Sendable>() -> Self where Self == DictionaryKeyedMerge<Key, Element> {
        Self()
    }
}

extension MergeStrategy where Value: RangeReplaceableCollection & Sendable, Value.Element: Equatable, Self == RangeReplaceableCollectionElementMerge<Value> {
    /// ``RangeReplaceableCollectionElementMerge``: element by element, like
    /// lines, or text character by character.
    public static var byElement: Self { Self() }
}

extension MergeStrategy where Value: StringProtocol & Sendable, Self == StringWordMerge<Value> {
    /// ``StringWordMerge``: text word by word.
    public static var byWord: Self { Self() }
}

extension MergeStrategy where Value: Codable, Self == JSONMerge<Value> {
    /// ``JSONMerge``: node by node, throwing on any conflict.
    public static var json: Self { Self() }

    /// ``JSONMerge``: node by node, keeping the named side at each conflict
    /// and every other change from both sides.
    public static func json(onConflict side: KeepMerge<Value>) -> Self {
        Self(onConflict: side)
    }
}

extension MergeStrategy {
    /// ``RawValueMerge``: the raw value, merged by `strategy`.
    public static func rawValue<Strategy: MergeStrategy>(_ strategy: Strategy) -> Self
    where Value: RawRepresentable, Strategy.Value == Value.RawValue, Self == RawValueMerge<Value, Strategy> {
        Self(strategy)
    }
}
