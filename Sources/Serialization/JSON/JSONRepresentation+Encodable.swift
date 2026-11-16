import Foundation

extension JSONRepresentation {
    /// The JSON `JSONEncoder` writes for `value`, built directly as a tree.
    ///
    /// Keys keep the order `encode(to:)` writes them, so `description`
    /// matches `JSONEncoder` output. Foundation types follow `JSONEncoder`'s
    /// default strategies: `Date` is seconds since 2001, `Data` is Base64,
    /// `URL` is its absolute string and `Decimal` is a number. Non-finite
    /// floating-point values are written as `"NaN"`, `"Infinity"` and
    /// `"-Infinity"`, which `decode(_:)` reads back. `Decimal.nan` has no
    /// JSON form and throws `EncodingError.invalidValue`.
    public init(_ value: some Encodable) throws {
        let node = EncodingNode()
        try node.encode(value, codingPath: [])
        guard let representation = node.representation else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "\(type(of: value)) did not encode any values."))
        }
        self = representation
    }

    /// Decodes `T` with `JSONDecoder`, reading non-finite numbers from the
    /// strings `init(_:)` writes.
    ///
    /// Throws `DecodingError.dataCorrupted` first when a number's text is
    /// not valid JSON or an object repeats a key, since `JSONDecoder` would
    /// otherwise tolerate or silently drop them.
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try validate(codingPath: [])
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try decoder.decode(T.self, from: Data(description.utf8))
    }
}

private extension JSONRepresentation {
    func validate(codingPath: [any CodingKey]) throws {
        func corrupted(_ message: String) -> DecodingError {
            .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
        }
        switch self {
        case .null, .bool, .string:
            break
        case .number(let text):
            guard text.isJSONNumber else { throw corrupted("\"\(text)\" is not a valid JSON number.") }
        case .array(let elements):
            for (index, element) in elements.enumerated() {
                try element.validate(codingPath: codingPath + [JSONRepresentation.Path.Component.index(index)])
            }
        case .object(let object):
            var keys: Set<String> = []
            for (key, value) in object {
                guard keys.insert(key).inserted else { throw corrupted("The key \"\(key)\" appears more than once.") }
                try value.validate(codingPath: codingPath + [JSONRepresentation.Path.Component.key(key)])
            }
        }
    }
}

// MARK: - Encoder

/// One position in the tree being encoded. Containers hold a node and fill
/// it in, so nested containers can keep writing after they are created.
private final class EncodingNode {
    enum Content {
        case empty
        case value(JSONRepresentation)
        case array([EncodingNode])
        case object([(key: String, node: EncodingNode)])
    }

    var content: Content = .empty

    /// `nil` when nothing was encoded. A nested value that encodes nothing
    /// is written as `{}`, as `JSONEncoder` does.
    var representation: JSONRepresentation? {
        switch content {
        case .empty: nil
        case .value(let value): value
        case .array(let nodes): .array(nodes.map { $0.representation ?? [:] })
        case .object(let pairs): .object(pairs.map { (key: $0.key, value: $0.node.representation ?? [:]) })
        }
    }

    /// Replaces whatever the node held, so encoding a key twice keeps only
    /// the second value, as `JSONEncoder` does.
    func encode(_ value: some Encodable, codingPath: [any CodingKey]) throws {
        content = .empty
        if let leaf = try Self.leaf(value, codingPath: codingPath) {
            content = .value(leaf)
        } else {
            try value.encode(to: RepresentationEncoder(node: self, codingPath: codingPath))
        }
    }

    /// Values written directly instead of through their own `encode(to:)`,
    /// either because they are primitives or because `JSONEncoder` writes
    /// them differently from their `Encodable` conformance.
    static func leaf(_ value: some Encodable, codingPath: [any CodingKey]) throws -> JSONRepresentation? {
        switch value {
        case let value as JSONRepresentation: value
        case let value as String: .string(value)
        case let value as any FixedWidthInteger: .number(String(describing: value))
        case let value as Bool: .bool(value)
        case let value as Double: value.jsonRepresentation
        case let value as Float: value.jsonRepresentation
        case let value as Decimal where value.isNaN:
            throw EncodingError.invalidValue(value, .init(codingPath: codingPath, debugDescription: "Decimal.nan cannot be written as a JSON number."))
        case let value as Decimal: .number(value.description)
        case let value as URL: .string(value.absoluteString)
        case let value as Data: .string(value.base64EncodedString())
        default: nil
        }
    }

    /// The child for `key`, reused when the key was written before. The key
    /// keeps its first position. A nested container on a repeated key adds
    /// to the earlier contents, and an encoded value replaces them.
    func child(forKey key: String) -> EncodingNode {
        guard case .object(var pairs) = content else {
            let child = EncodingNode()
            content = .object([(key: key, node: child)])
            return child
        }
        if let existing = pairs.first(where: { $0.key == key }) { return existing.node }
        let child = EncodingNode()
        content = .empty  // Releases the array so the append below does not copy it.
        pairs.append((key: key, node: child))
        content = .object(pairs)
        return child
    }

    func appendChild() -> EncodingNode {
        guard case .array(var nodes) = content else {
            let child = EncodingNode()
            content = .array([child])
            return child
        }
        let child = EncodingNode()
        content = .empty  // Releases the array so the append below does not copy it.
        nodes.append(child)
        content = .array(nodes)
        return child
    }

    func becomeObject() {
        if case .object = content { return }
        content = .object([])
    }

    func becomeArray() {
        if case .array = content { return }
        content = .array([])
    }

    var count: Int {
        if case .array(let nodes) = content { nodes.count } else { 0 }
    }
}

private struct RepresentationEncoder: Encoder {
    let node: EncodingNode
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        node.becomeObject()
        return KeyedEncodingContainer(KeyedWriter<Key>(node: node, codingPath: codingPath))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        node.becomeArray()
        return UnkeyedWriter(node: node, codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleValueWriter(node: node, codingPath: codingPath)
    }
}

// MARK: - Containers

private struct KeyedWriter<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let node: EncodingNode
    let codingPath: [any CodingKey]

    private func write(_ value: some Encodable, forKey key: Key) throws {
        try node.child(forKey: key.stringValue).encode(value, codingPath: codingPath + [key])
    }

    mutating func encodeNil(forKey key: Key) throws { node.child(forKey: key.stringValue).content = .value(.null) }
    mutating func encode(_ value: Bool, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: String, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { try write(value, forKey: key) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try write(value, forKey: key) }
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    mutating func encode(_ value: Int128, forKey key: Key) throws { try write(value, forKey: key) }
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    mutating func encode(_ value: UInt128, forKey key: Key) throws { try write(value, forKey: key) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        RepresentationEncoder(node: node.child(forKey: key.stringValue), codingPath: codingPath + [key]).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        RepresentationEncoder(node: node.child(forKey: key.stringValue), codingPath: codingPath + [key]).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        let key = JSONRepresentation.Path.Component.key("super")
        return RepresentationEncoder(node: node.child(forKey: key.stringValue), codingPath: codingPath + [key])
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
        RepresentationEncoder(node: node.child(forKey: key.stringValue), codingPath: codingPath + [key])
    }
}

private struct UnkeyedWriter: UnkeyedEncodingContainer {
    let node: EncodingNode
    let codingPath: [any CodingKey]
    var count: Int { node.count }

    private func write(_ value: some Encodable) throws {
        let key = JSONRepresentation.Path.Component.index(count)
        try node.appendChild().encode(value, codingPath: codingPath + [key])
    }

    mutating func encodeNil() throws { node.appendChild().content = .value(.null) }
    mutating func encode(_ value: Bool) throws { try write(value) }
    mutating func encode(_ value: String) throws { try write(value) }
    mutating func encode(_ value: Double) throws { try write(value) }
    mutating func encode(_ value: Float) throws { try write(value) }
    mutating func encode(_ value: Int) throws { try write(value) }
    mutating func encode(_ value: Int8) throws { try write(value) }
    mutating func encode(_ value: Int16) throws { try write(value) }
    mutating func encode(_ value: Int32) throws { try write(value) }
    mutating func encode(_ value: Int64) throws { try write(value) }
    mutating func encode(_ value: UInt) throws { try write(value) }
    mutating func encode(_ value: UInt8) throws { try write(value) }
    mutating func encode(_ value: UInt16) throws { try write(value) }
    mutating func encode(_ value: UInt32) throws { try write(value) }
    mutating func encode(_ value: UInt64) throws { try write(value) }
    mutating func encode<T: Encodable>(_ value: T) throws { try write(value) }
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    mutating func encode(_ value: Int128) throws { try write(value) }
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    mutating func encode(_ value: UInt128) throws { try write(value) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let key = JSONRepresentation.Path.Component.index(count)
        return RepresentationEncoder(node: node.appendChild(), codingPath: codingPath + [key]).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let key = JSONRepresentation.Path.Component.index(count)
        return RepresentationEncoder(node: node.appendChild(), codingPath: codingPath + [key]).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
        let key = JSONRepresentation.Path.Component.index(count)
        return RepresentationEncoder(node: node.appendChild(), codingPath: codingPath + [key])
    }
}

private struct SingleValueWriter: SingleValueEncodingContainer {
    let node: EncodingNode
    let codingPath: [any CodingKey]

    private func write(_ value: some Encodable) throws {
        try node.encode(value, codingPath: codingPath)
    }

    mutating func encodeNil() throws { node.content = .value(.null) }
    mutating func encode(_ value: Bool) throws { try write(value) }
    mutating func encode(_ value: String) throws { try write(value) }
    mutating func encode(_ value: Double) throws { try write(value) }
    mutating func encode(_ value: Float) throws { try write(value) }
    mutating func encode(_ value: Int) throws { try write(value) }
    mutating func encode(_ value: Int8) throws { try write(value) }
    mutating func encode(_ value: Int16) throws { try write(value) }
    mutating func encode(_ value: Int32) throws { try write(value) }
    mutating func encode(_ value: Int64) throws { try write(value) }
    mutating func encode(_ value: UInt) throws { try write(value) }
    mutating func encode(_ value: UInt8) throws { try write(value) }
    mutating func encode(_ value: UInt16) throws { try write(value) }
    mutating func encode(_ value: UInt32) throws { try write(value) }
    mutating func encode(_ value: UInt64) throws { try write(value) }
    mutating func encode<T: Encodable>(_ value: T) throws { try write(value) }
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    mutating func encode(_ value: Int128) throws { try write(value) }
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    mutating func encode(_ value: UInt128) throws { try write(value) }
}
