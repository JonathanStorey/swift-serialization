import Foundation

/// A read-only to-many relationship, stored as ``Relationship`` records
/// instead of a field on the record, so it has no size limit and edits from
/// two devices merge.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @References(to: Tag.self) var tags: [UUID] = []
/// }
/// ```
///
/// The property holds the targets' ids in order. It is set when the model
/// is created or decoded and cannot be assigned afterwards. The wrapper
/// stores only the ids. An empty list is left out of a keyed container, and
/// a missing key decodes as an empty list.
@propertyWrapper
public struct References<Target: Identifiable>: Hashable, Sendable where Target.ID == UUID {
    public let wrappedValue: [UUID]

    public init(wrappedValue: [UUID] = [], to target: Target.Type) {
        self.wrappedValue = wrappedValue
    }
}

extension References {
    /// The targets of the links that the record `source` declares, sorted by
    /// order, with unplaced links last.
    package init(_ links: [Relationship], from source: UUID) {
        let sorted = links.sorted { ($0.order ?? .max, $0.id.uuidString) < ($1.order ?? .max, $1.id.uuidString) }
        self.init(wrappedValue: sorted.map { $0.target(from: source) }, to: Target.self)
    }
}

extension References: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(wrappedValue: try decoder.singleValueContainer().decode([UUID].self), to: Target.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    public func decode<Target>(_ type: References<Target>.Type, forKey key: Key) throws -> References<Target> {
        try decodeIfPresent(type, forKey: key) ?? References(to: Target.self)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: References<Target>, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
