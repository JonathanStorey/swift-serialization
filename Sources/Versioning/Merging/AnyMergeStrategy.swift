/// Any merge strategy for `Value`, in the style of `AnySequence`.
///
/// It lets a strategy be stored and passed without making the type that
/// holds it generic, and it gives the package's strategies dot syntax. End a
/// strategy with ``keep(_:)`` to keep a side wherever it conflicts.
///
/// ```swift
/// let title: AnyMergeStrategy<String> = .byWord.keep(.ours)
/// let count: AnyMergeStrategy<Int> = .sum.keep(.theirs)
/// let note: AnyMergeStrategy<Note> = .json(onConflict: .theirs)
/// ```
public struct AnyMergeStrategy<Value: Sendable>: MergeStrategy {
    private let threeWay: @Sendable (Value, Value, Value) throws(MergeConflict) -> Value
    private let twoWay: @Sendable (Value, Value) throws(MergeConflict) -> Value

    /// Wraps `strategy`.
    public init(_ strategy: some MergeStrategy<Value>) {
        threeWay = { base, ours, theirs throws(MergeConflict) in try strategy.merge(base: base, ours: ours, theirs: theirs) }
        twoWay = { ours, theirs throws(MergeConflict) in try strategy.merge(ours: ours, theirs: theirs) }
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try threeWay(base, ours, theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try twoWay(ours, theirs)
    }
}

// MARK: - Keep

extension AnyMergeStrategy {
    /// The named side, `.ours` or `.theirs`.
    public static func keep(_ side: KeepMerge<Value>) -> Self {
        Self(side)
    }

    /// This strategy, keeping the named side wherever it conflicts.
    ///
    /// The side replaces the whole value. For a `Codable` value, use
    /// ``json(onConflict:)`` to keep a side only where the versions
    /// conflict.
    public func keep(_ side: KeepMerge<Value>) -> Self {
        Self(KeepingMerge(strategy: self, side: side))
    }
}

/// A strategy, and the side to keep wherever it conflicts.
private struct KeepingMerge<Value: Sendable>: MergeStrategy {
    let strategy: AnyMergeStrategy<Value>
    let side: KeepMerge<Value>

    func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        do {
            return try strategy.merge(base: base, ours: ours, theirs: theirs)
        } catch {
            return try side.merge(ours: ours, theirs: theirs)
        }
    }

    func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        do {
            return try strategy.merge(ours: ours, theirs: theirs)
        } catch {
            return try side.merge(ours: ours, theirs: theirs)
        }
    }
}

// MARK: - Dot syntax

extension AnyMergeStrategy where Value: Comparable {
    /// ``ComparableMaximumMerge``: the larger value.
    public static var maximum: Self { Self(ComparableMaximumMerge<Value>()) }
}

extension AnyMergeStrategy where Value: Numeric {
    /// ``NumericSumMerge``: a counter, so both sides' changes count.
    public static var sum: Self { Self(NumericSumMerge<Value>()) }
}

extension AnyMergeStrategy where Value == Bool {
    /// ``BoolTrueWinsMerge``: `true` if either side is.
    public static var trueWins: Self { Self(BoolTrueWinsMerge()) }
}

extension AnyMergeStrategy where Value: SetAlgebra {
    /// ``SetAlgebraMembershipMerge``: what each side added and removed.
    public static var byMembership: Self { Self(SetAlgebraMembershipMerge<Value>()) }
    /// ``SetAlgebraUnionMerge``: as membership, or every element without a
    /// base.
    public static var union: Self { Self(SetAlgebraUnionMerge<Value>()) }
}

extension AnyMergeStrategy {
    /// ``DictionaryKeyedMerge``: a dictionary key by key.
    public static func byKey<Key: Hashable & Sendable, Element: Equatable & Sendable>() -> Self where Value == [Key: Element] {
        Self(DictionaryKeyedMerge<Key, Element>())
    }
}

extension AnyMergeStrategy where Value: RangeReplaceableCollection, Value.Element: Equatable {
    /// ``RangeReplaceableCollectionElementMerge``: element by element, like
    /// lines, or text character by character.
    public static var byElement: Self { Self(RangeReplaceableCollectionElementMerge<Value>()) }
}

extension AnyMergeStrategy where Value: StringProtocol {
    /// ``StringWordMerge``: text word by word.
    public static var byWord: Self { Self(StringWordMerge<Value>()) }
}

extension AnyMergeStrategy where Value: Codable {
    /// ``JSONMerge``: node by node, throwing on any conflict.
    public static var json: Self { Self(JSONMerge<Value>()) }

    /// ``JSONMerge``: node by node, keeping the named side at each conflict
    /// and every other change from both sides.
    public static func json(onConflict side: KeepMerge<Value>) -> Self {
        Self(JSONMerge<Value>(onConflict: side))
    }
}
