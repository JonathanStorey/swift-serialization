import Foundation

/// A schema's `id` is computed from the schema alone, so it is the same on
/// every launch, platform and Swift version, and equal schemas share it.
///
/// The id is a 128-bit MurmurHash3 (x64, seed 0) of the schema's JSON text
/// with every object's keys sorted. Sorting makes property order irrelevant,
/// matching `==`. The id is not an RFC 9562 UUID and carries no version bits.
extension JSONSchema: Identifiable {
    /// Computed on every access by writing and hashing the whole schema.
    /// Store it when you need it repeatedly, such as in a SwiftUI `ForEach`.
    public var id: UUID {
        UUID(stableHashOf: body.canonicalized().description)
    }
}

private extension JSONRepresentation {
    /// Keys sorted, and keys and strings in Unicode normalization form C,
    /// because Swift compares strings by canonical equivalence.
    func canonicalized() -> JSONRepresentation {
        switch self {
        case .string(let text):
            .string(text.precomposedStringWithCanonicalMapping)
        case .array(let elements):
            .array(elements.map { $0.canonicalized() })
        case .object(let pairs):
            .object(pairs
                .map { (key: $0.key.precomposedStringWithCanonicalMapping, value: $0.value.canonicalized()) }
                .sorted { $0.key < $1.key })
        case .null, .bool, .number:
            self
        }
    }
}
