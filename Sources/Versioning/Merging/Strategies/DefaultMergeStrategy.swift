/// The best merge for a `Codable` value, and what a `Codable` ``Mergeable``
/// type uses unless it names another. It merges property by property, as
/// ``PropertyMerge`` does, but lets each property's type decide wherever
/// both sides changed it, at any depth:
///
/// - A ``Mergeable`` type merges by its own merge, so a `Views` counter sums.
/// - An array or set of `Identifiable` elements merges by `id`, as
///   ``IdentifiedElementMerge`` does.
/// - A dictionary merges by key, whatever its key type, each value by its
///   own type.
///
/// Every rule comes from something a type declares, so a type that declares
/// nothing merges exactly as ``PropertyMerge`` does. Without `favoring`, a
/// conflict that no rule settles throws. With it, each conflicting value
/// takes that side.
///
/// ```swift
/// try ours.merging(with: theirs, from: base, using: .favoring(.theirs))
/// ```
public struct DefaultMergeStrategy<Value>: Sendable {
    /// The side kept at each conflicting value, or `nil` to throw.
    public var favoring: KeepMerge<Value>?

    public init(favoring: KeepMerge<Value>? = nil) {
        self.favoring = favoring
    }
}

extension DefaultMergeStrategy: MergeStrategy where Value: Codable {
    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            try Self.decoded { try MergeContext(ours, theirs, base: JSONRepresentation(base), favoring: favoring, readingTypes: true) }
        }
    }

    /// Without a base, only what both sides share merges. See
    /// ``JSONRepresentation/merging(_:base:under:)``.
    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            try Self.decoded { try MergeContext(ours, theirs, base: nil, favoring: favoring, readingTypes: true) }
        }
    }

    /// The value the context decodes, with any failure as a conflict.
    private static func decoded(_ context: () throws -> MergeContext) throws(MergeConflict) -> Value {
        do {
            return try context().decode(Value.self)
        } catch {
            throw MergeConflict()
        }
    }
}
