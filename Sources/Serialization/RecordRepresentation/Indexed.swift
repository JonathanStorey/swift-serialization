/// A value CloudKit indexes, so queries can filter and sort by it.
///
/// ```swift
/// struct Note: Codable {
///     @Indexed var created: Date = Date()
///     @Indexed([.queryable, .searchable]) var title: String = ""
/// }
/// ```
///
/// The wrapper only marks the property. It encodes its value through a
/// single-value container, so JSON is unchanged, and it takes no part in
/// equality or hashing beyond its value. A record schema will read the
/// indexes from a model it creates, so the record type is indexed before it
/// reaches production, where a query on an unindexed field fails.
///
/// Swift does not pass the attribute's arguments to `init(from:)`, so a
/// decoded wrapper's ``index`` is `nil`. An optional `nil` value is left out
/// of a keyed container, and a missing key decodes as `nil`.
@propertyWrapper
public struct Indexed<Value> {
    public var wrappedValue: Value

    /// The indexes CloudKit keeps, or `nil` when the wrapper was decoded.
    package let index: RecordRepresentation.Index?

    /// Indexed for `==`, `CONTAINS`, ranges and sorting unless `index` says
    /// otherwise. Add ``RecordRepresentation/Index/searchable`` for word
    /// search in a string.
    public init(wrappedValue: Value, _ index: RecordRepresentation.Index = [.queryable, .sortable]) {
        self.wrappedValue = wrappedValue
        self.index = index
    }

    fileprivate init(decoded value: Value) {
        wrappedValue = value
        index = nil
    }
}

extension RecordRepresentation {
    /// The indexes CloudKit keeps for a field, as a record type's schema
    /// declares them.
    public struct Index: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Filtering with `==`, `!=` and `CONTAINS`.
        public static let queryable = Index(rawValue: 1 << 0)
        /// Filtering with `<` and `>`, and sorting.
        public static let sortable = Index(rawValue: 1 << 1)
        /// Word search inside a string, with `self CONTAINS`.
        public static let searchable = Index(rawValue: 1 << 2)
    }
}

extension Indexed: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension Indexed: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

extension Indexed: Sendable where Value: Sendable {}

extension Indexed: Encodable where Value: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension Indexed: Decodable where Value: Decodable {
    public init(from decoder: any Decoder) throws {
        self.init(decoded: try decoder.singleValueContainer().decode(Value.self))
    }
}

extension KeyedDecodingContainer {
    public func decode<Wrapped: Decodable>(_ type: Indexed<Wrapped?>.Type, forKey key: Key) throws -> Indexed<Wrapped?> {
        try decodeIfPresent(type, forKey: key) ?? Indexed(decoded: nil)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Wrapped: Encodable>(_ value: Indexed<Wrapped?>, forKey key: Key) throws {
        try encodeIfPresent(value.wrappedValue, forKey: key)
    }
}
