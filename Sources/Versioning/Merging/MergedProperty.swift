/// A property's value paired with the strategy it merges by.
///
/// ```swift
/// var title = MergedProperty(note.title, LongerMerge())
/// try title.merge(with: theirs.title, from: base.title)
/// note.title = title.value
/// ```
///
/// An `Equatable` value keeps the side that changed when only one did, so
/// the strategy decides only when both sides changed it, even to the same
/// value, since a counter both sides raised by 1 has gone up by 2. For any
/// other value, the strategy decides every three-way merge.
public struct MergedProperty<Value: Sendable>: Sendable {
    /// Ours: the property's value, and the merged value after `merge`.
    public private(set) var value: Value
    private let threeWay: @Sendable (Value, Value, Value) throws(MergeConflict) -> Value
    private let twoWay: @Sendable (Value, Value) throws(MergeConflict) -> Value
    private let isEqual: (@Sendable (Value, Value) -> Bool)?

    private init<Strategy: MergeStrategy<Value>>(value: Value, strategy: Strategy, isEqual: (@Sendable (Value, Value) -> Bool)?) {
        self.value = value
        self.threeWay = { base, ours, theirs throws(MergeConflict) in try strategy.merge(base: base, ours: ours, theirs: theirs) }
        self.twoWay = { ours, theirs throws(MergeConflict) in try strategy.merge(ours: ours, theirs: theirs) }
        self.isEqual = isEqual
    }

    /// A value that is not `Equatable`, whose strategy decides every merge.
    public init<Strategy: MergeStrategy<Value>>(_ value: Value, _ strategy: Strategy) {
        self.init(value: value, strategy: strategy, isEqual: nil)
    }
}

extension MergedProperty where Value: Equatable {
    /// An `Equatable` value, which keeps the side that changed when only
    /// one did.
    public init<Strategy: MergeStrategy<Value>>(_ value: Value, _ strategy: Strategy) {
        self.init(value: value, strategy: strategy, isEqual: { $0 == $1 })
    }
}

extension MergedProperty {
    /// This value, which is ours, merged with `theirs`, knowing their common
    /// ancestor.
    public func merging(with theirs: Value, from base: Value) throws(MergeConflict) -> Value {
        if let isEqual {
            if isEqual(value, base) { return theirs }
            if isEqual(theirs, base) { return value }
        }
        return try threeWay(base, value, theirs)
    }

    /// This value, which is ours, merged with `theirs` without a common
    /// ancestor.
    public func merging(with theirs: Value) throws(MergeConflict) -> Value {
        try twoWay(value, theirs)
    }

    /// Merges `theirs` into this value, knowing their common ancestor. On a
    /// conflict, the value is left unchanged.
    public mutating func merge(with theirs: Value, from base: Value) throws(MergeConflict) {
        value = try merging(with: theirs, from: base)
    }

    /// Merges `theirs` into this value without a common ancestor. On a
    /// conflict, the value is left unchanged.
    public mutating func merge(with theirs: Value) throws(MergeConflict) {
        value = try merging(with: theirs)
    }
}
