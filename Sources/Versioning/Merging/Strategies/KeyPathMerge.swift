/// Merges the properties it lists by key path, one by one, so it works on
/// any type, `Codable` or not, including a class such as a SwiftData model.
///
/// - A property only one side changed keeps that side.
/// - A property both sides changed merges by the strategy named for it,
///   by its own merge if it is ``Mergeable`` and none is named, and
///   otherwise conflicts.
/// - A property it does not list keeps ours.
///
/// ```swift
/// extension Note: Mergeable {
///     func merging(with theirs: Note, from base: Note) throws(MergeConflict) -> Note {
///         try merging(with: theirs, from: base, using: .byKeyPath()
///             .merging(\.title)
///             .merging(\.body, using: .byWord())
///             .merging(\.tags, using: .union()))
///     }
/// }
/// ```
///
/// Every property merges before any is written, so a conflict leaves the
/// versions as they were, and it reports each conflicting key path in
/// ``MergeConflict/keyPaths``. With `favoring`, each conflicting property
/// takes that side. A class merges into ours and returns it.
public struct KeyPathMerge<Value>: MergeStrategy {
    /// The side kept at each conflicting property, or `nil` to throw.
    public var favoring: KeepMerge<Value>?

    private var properties: [Listed] = []

    public init(favoring: KeepMerge<Value>? = nil) {
        self.favoring = favoring
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try merged(ours, theirs, base: base)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try merged(ours, theirs, base: nil)
    }

    /// This merge, also merging the property at `keyPath` by `strategy`
    /// where both sides changed it.
    public func merging<Property: Equatable>(_ keyPath: WritableKeyPath<Value, Property> & Sendable, using strategy: some MergeStrategy<Property>) -> Self {
        adding(keyPath) { ours, theirs, base throws(MergeConflict) in
            guard let base else { return try strategy.merge(ours: ours, theirs: theirs) }
            return try strategy.merge(base: base, ours: ours, theirs: theirs)
        }
    }

    /// This merge, also merging the property at `keyPath`, which conflicts
    /// where both sides changed it.
    public func merging<Property: Equatable>(_ keyPath: WritableKeyPath<Value, Property> & Sendable) -> Self {
        adding(keyPath) { _, _, _ throws(MergeConflict) in throw MergeConflict() }
    }

    /// This merge, also merging the property at `keyPath` by its own merge
    /// where both sides changed it.
    public func merging<Property: Equatable & Mergeable>(_ keyPath: WritableKeyPath<Value, Property> & Sendable) -> Self {
        adding(keyPath) { ours, theirs, base throws(MergeConflict) in
            guard let base else { return try ours.merging(with: theirs) }
            return try ours.merging(with: theirs, from: base)
        }
    }
}

private extension KeyPathMerge {
    /// One listed property: its merge of the three versions, as a write to
    /// make once every property has merged, or `nil` to keep ours.
    typealias Listed = @Sendable (_ ours: Value, _ theirs: Value, _ base: Value?, _ side: KeepMerge<Void>?) throws(MergeConflict) -> ((inout Value) -> Void)?

    func adding<P: Equatable>(_ keyPath: WritableKeyPath<Value, P> & Sendable, _ merge: @escaping @Sendable (P, P, P?) throws(MergeConflict) -> P) -> Self {
        var copy = self
        copy.properties.append { ours, theirs, base, side throws(MergeConflict) in
            let mine = ours[keyPath: keyPath]
            let other = theirs[keyPath: keyPath]
            let original = base.map { $0[keyPath: keyPath] }
            if let original {
                if other == original { return nil }
                if mine == original { return { $0[keyPath: keyPath] = other } }
            }
            if mine == other { return nil }
            let merged: P
            do {
                merged = try merge(mine, other, original)
            } catch let conflict as MergeConflict {
                guard let side else { throw conflict.inside(keyPath) }
                if case .ours = side { merged = mine } else { merged = other }
            } catch {
                guard let side else { throw MergeConflict(at: [keyPath]) }
                if case .ours = side { merged = mine } else { merged = other }
            }
            return { $0[keyPath: keyPath] = merged }
        }
        return copy
    }

    func merged(_ ours: Value, _ theirs: Value, base: Value?) throws(MergeConflict) -> Value {
        let side: KeepMerge<Void>? = favoring?.retyped()
        var writes: [(inout Value) -> Void] = []
        var conflicts: [AnyKeyPath] = []
        for property in properties {
            do {
                if let write = try property(ours, theirs, base, side) { writes.append(write) }
            } catch let conflict as MergeConflict {
                conflicts += conflict.keyPaths
            } catch {
                conflicts.append(\Value.self)
            }
        }
        guard conflicts.isEmpty else { throw MergeConflict(at: conflicts) }
        var result = ours
        for write in writes { write(&result) }
        return result
    }
}
