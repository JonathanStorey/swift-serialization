extension JSONSchema {
    /// Whether a type with this schema can decode `value`, following the same
    /// `JSONDecoder` rules as ``isSuperset(of:)``:
    ///
    /// - An object ignores keys it does not declare.
    /// - An optional property may be missing or `null`.
    /// - An `integer` must be written without a fraction or exponent, and a
    ///   `number` accepts any finite JSON number, integers included.
    /// - A restricted `cases` list must contain the value.
    ///
    /// Width is not part of a schema, so `300` is reported as decodable by
    /// an `Int8` property and `1e39` by a `Float` property.
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
        case let (.integer(cases), .number):
            if let integer = value.int64Value { cases?.contains(integer) ?? true } else { cases == nil && value.uint64Value != nil }
        case let (.string(cases), .string(text)):
            cases?.contains(text) ?? true
        case let (.array(items), .array(elements)):
            elements.allSatisfy(items.contains)
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
