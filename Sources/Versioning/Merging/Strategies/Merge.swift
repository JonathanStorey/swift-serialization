/// Merges a value property by property. A `Codable` value merges through
/// its coding keys, node by node, guided by its ``JSONSchema``: a
/// property only one side changed keeps that side, and where both changed
/// it, objects merge key by key, a `Set` by membership, a `Dictionary` by
/// key and an array element by element. The result must decode.
///
/// Without `favoring`, any value both sides changed differently throws.
/// With it, every change that does not conflict still applies, from both
/// sides, and each conflicting value takes the named side, as
/// `git merge -X theirs` does. If the merge cannot decode, the whole named
/// side is kept.
///
/// ```swift
/// try Merge<Note>().merge(base: base, ours: mine, theirs: yours)
/// try Merge<Note>(favoring: .theirs).merge(base: base, ours: mine, theirs: yours)
/// ```
///
/// It encodes and decodes on every merge, which suits syncing better than
/// tight loops. To see which paths conflict, call
/// ``JSONRepresentation/merging(_:base:under:)`` directly.
public struct Merge<Value>: Sendable {
    /// The side kept at each conflicting value, or `nil` to throw.
    public var favoring: KeepMerge<Value>?

    public init(favoring: KeepMerge<Value>? = nil) {
        self.favoring = favoring
    }
}

extension Merge: MergeStrategy where Value: Codable {
    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try merge(ours, theirs, base: base)
    }

    /// Without a base, only what both sides share merges. See
    /// ``JSONRepresentation/merging(_:base:under:)``.
    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try merge(ours, theirs, base: nil)
    }
}

private extension Merge where Value: Codable {
    func merge(_ ours: Value, _ theirs: Value, base: Value?) throws(MergeConflict) -> Value {
        do {
            let mine = try JSONRepresentation(ours)
            let other = try JSONRepresentation(theirs)
            let original = try base.map { try JSONRepresentation($0) }
            // A type the schema cannot describe still merges by shape.
            let schema = try? JSONSchema(for: Value.self)
            var conflicts: [JSONRepresentation.Path] = []
            var merged = mine.merging(other, base: original, under: schema, at: [], conflicts: &conflicts)
            if !conflicts.isEmpty {
                guard let favoring else { throw MergeConflict() }
                if case .theirs = favoring {
                    for path in conflicts { merged[path] = other[path] }
                }
            }
            return try merged.decode(Value.self)
        } catch {
            guard let favoring else { throw MergeConflict() }
            return try favoring.merge(ours: ours, theirs: theirs)
        }
    }
}
