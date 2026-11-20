/// A strategy that keeps one side wherever another strategy conflicts.
/// Made by ``MergeStrategy/keep(_:)``.
///
/// ```swift
/// try ours.merging(with: theirs, from: base, using: .byWord().keep(.ours))
/// ```
///
/// The side replaces the whole value. For a `Codable` value, use
/// `.json(onConflict:)` to keep a side only where the versions conflict.
public struct KeepingMerge<Strategy: MergeStrategy>: MergeStrategy {
    let strategy: Strategy
    let side: KeepMerge<Strategy.Value>

    public func merge(base: Strategy.Value, ours: Strategy.Value, theirs: Strategy.Value) throws(MergeConflict) -> Strategy.Value {
        do {
            return try strategy.merge(base: base, ours: ours, theirs: theirs)
        } catch {
            return try side.merge(ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Strategy.Value, theirs: Strategy.Value) throws(MergeConflict) -> Strategy.Value {
        do {
            return try strategy.merge(ours: ours, theirs: theirs)
        } catch {
            return try side.merge(ours: ours, theirs: theirs)
        }
    }
}

extension MergeStrategy {
    /// This strategy, keeping `side` wherever it conflicts.
    public func keep(_ side: KeepMerge<Value>) -> KeepingMerge<Self> {
        KeepingMerge(strategy: self, side: side)
    }
}
