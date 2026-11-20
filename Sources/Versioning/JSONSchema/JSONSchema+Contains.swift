import Foundation

extension JSONSchema {
    /// Whether a type with this schema can decode `value`, following the same
    /// `JSONDecoder` rules as ``isSuperset(of:)``:
    ///
    /// - An object ignores keys it does not declare.
    /// - An optional property may be missing or `null`.
    /// - An `integer` accepts any number with a whole value, including text
    ///   such as `1.0` and `1e2`, and a `number` accepts any finite number.
    /// - A restricted `cases` list must contain the value, and an integer
    ///   must lie within its bounds.
    /// - A string with a `format` must parse as that type, with
    ///   `UUID(uuidString:)`, `URL(string:)` or `Data(base64Encoded:)`.
    /// - A `set` must not repeat an element, comparing numbers by value.
    ///
    /// `Float` has no bounds in a schema, so `1e39` is reported as
    /// decodable by a `Float` property.
    ///
    /// A schema is the set of values its type decodes, so this agrees with
    /// the set relations: when `a.isSubset(of: b)` and `a.contains(v)`, then
    /// `b.contains(v)`.
    public func contains(_ value: JSONRepresentation) -> Bool {
        switch (self, value) {
        case (.optional, .null), (.null, .null), (.boolean, .bool):
            true
        case (.optional(let wrapped), _):
            wrapped.contains(value)
        case (.number, .number):
            value.doubleValue != nil
        case let (.integer(cases, minimum, maximum), .number):
            if let integer = value.int64Value ?? value.doubleValue.flatMap(Int64.init(exactly:)) {
                (cases?.contains(integer) ?? true) && Self.integer(integer, isAtLeast: minimum, atMost: maximum)
            } else {
                // Above `Int64.max`, so only an unbounded integer holds it.
                cases == nil && maximum == nil && (value.uint64Value ?? value.doubleValue.flatMap(UInt64.init(exactly:))) != nil
            }
        case let (.string(cases, format), .string(text)):
            (cases?.contains(text) ?? true) && (format?.accepts(text) ?? true)
        case let (.array(items), .array(elements)):
            elements.allSatisfy(items.contains)
        case let (.set(items), .array(elements)):
            elements.allSatisfy(items.contains) && elements.indices.allSatisfy { index in
                elements[..<index].allSatisfy { !$0.isEquivalent(to: elements[index]) }
            }
        case let (.dictionary(values), .object(pairs)):
            pairs.allSatisfy { values.contains($0.value) }
        case let (.object(properties), .object):
            properties.allSatisfy { property in
                guard let written = value[property.key] else { return property.value.isOptional }
                return property.value.contains(written)
            }
        default:
            false
        }
    }
}

extension JSONSchema.Format {
    /// Whether the type behind the format decodes `text`.
    func accepts(_ text: String) -> Bool {
        switch self {
        case .uuid: UUID(uuidString: text) != nil
        case .uriReference: URL(string: text) != nil
        case .base64: Data(base64Encoded: text) != nil
        }
    }
}
