/// Encodes and decodes through any `Encoder` and `Decoder`, so a `Codable`
/// type can hold a free-form `JSONRepresentation` property.
///
/// Foundation's coders do not carry everything this type keeps:
/// - `JSONDecoder` hands back typed values, so number text is normalized.
///   `1e2` decodes as `100`.
/// - `JSONDecoder` does not promise key order, so decoded objects may be
///   reordered.
/// - A number is encoded as `Int64`, then `UInt64`, then `Double`, so a
///   decimal with more precision than `Double` is rounded.
extension JSONRepresentation: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: AnyCodingKey.self) {
            self = .object(try container.allKeys.map { key in
                (key: key.stringValue, value: try container.decode(JSONRepresentation.self, forKey: key))
            })
        } else if var container = try? decoder.unkeyedContainer() {
            var elements: [JSONRepresentation] = []
            while !container.isAtEnd {
                elements.append(try container.decode(JSONRepresentation.self))
            }
            self = .array(elements)
        } else {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = value.json
            } else if let value = try? container.decode(UInt64.self) {
                self = value.json
            } else if let value = try? container.decode(Double.self) {
                self = value.json
            } else {
                self = .string(try container.decode(String.self))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number:
            var container = encoder.singleValueContainer()
            if let value = Int64(json: self) {
                try container.encode(value)
            } else if let value = UInt64(json: self) {
                try container.encode(value)
            } else if let value = Double(json: self) {
                try container.encode(value)
            } else {
                throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Number text is not a valid JSON number."))
            }
        case .array(let elements):
            var container = encoder.unkeyedContainer()
            for element in elements {
                try container.encode(element)
            }
        case .object(let object):
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, value) in object {
                try container.encode(value, forKey: AnyCodingKey(stringValue: key))
            }
        }
    }
}

/// A coding key for arbitrary object keys.
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
