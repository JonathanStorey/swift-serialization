/// Merges a value property by property, and each property's own
/// properties the same way. A property only one side changed keeps that
/// side. Where both changed one whose type is ``Mergeable``, that type's
/// own merge decides, so a `Views` counter can sum. Otherwise, guided by
/// the value's ``JSONSchema``, a `Set` merges by membership, a `Dictionary`
/// by key and an array element by element. The result must decode.
///
/// Without `favoring`, any value both sides changed differently throws.
/// With it, every change that does not conflict still applies, from both
/// sides, and each conflicting value takes the named side, as
/// `git merge -X theirs` does. If the merge cannot decode, the whole named
/// side is kept.
///
/// ```swift
/// try PropertyMerge<Note>().merge(base: base, ours: mine, theirs: yours)
/// try PropertyMerge<Note>(favoring: .theirs).merge(base: base, ours: mine, theirs: yours)
/// ```
///
/// It encodes and decodes on every merge, which suits syncing better than
/// tight loops. To see which paths conflict, call
/// ``JSONRepresentation/merging(_:base:under:)`` directly.
public struct PropertyMerge<Value>: Sendable {
    /// The side kept at each conflicting value, or `nil` to throw.
    public var favoring: KeepMerge<Value>?

    public init(favoring: KeepMerge<Value>? = nil) {
        self.favoring = favoring
    }
}

extension PropertyMerge: MergeStrategy where Value: Codable {
    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            try Self.decoded { try PropertyMergeContext(ours, theirs, base: JSONRepresentation(base), favoring: favoring) }
        }
    }

    /// Without a base, only what both sides share merges. See
    /// ``JSONRepresentation/merging(_:base:under:)``.
    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            try Self.decoded { try PropertyMergeContext(ours, theirs, base: nil, favoring: favoring) }
        }
    }

    /// The value the context decodes, with any failure as a conflict.
    private static func decoded(_ context: () throws -> PropertyMergeContext) throws(MergeConflict) -> Value {
        do {
            return try context().decode(Value.self)
        } catch {
            throw MergeConflict()
        }
    }
}
