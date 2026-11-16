/// Compatibility follows `JSONDecoder`. A schema is read as the set of JSON
/// values a type decodes successfully:
///
/// - An object ignores keys it does not declare.
/// - An optional property may be missing or `null`.
/// - An `integer` is a valid `number`, because `Double` decodes `1`.
/// - Restricted `cases` must contain every case the other side can send.
///
/// Integer width is not part of a schema, so an `Int8` reader is reported
/// as accepting an `Int` writer even though large values will fail.
extension JSONSchema {
    /// Whether a type with this schema can decode every value written under
    /// `other`, as in `reader.isSuperset(of: writer)`.
    public func isSuperset(of other: JSONSchema) -> Bool {
        switch (self, other) {
        case (_, .optional(let wrapped)):
            isSuperset(of: .null) && isSuperset(of: wrapped)
        case (.optional, .null):
            true
        case (.optional(let wrapped), _):
            wrapped.isSuperset(of: other)
        case (.null, .null), (.boolean, .boolean), (.number, .number), (.number, .integer):
            true
        case let (.integer(cases), .integer(otherCases)):
            Self.cases(cases, include: otherCases)
        case let (.string(cases), .string(otherCases)):
            Self.cases(cases, include: otherCases)
        case let (.array(items), .array(otherItems)):
            items.isSuperset(of: otherItems)
        case let (.object(properties), .object(otherProperties)):
            properties.allSatisfy { property in
                guard let written = otherProperties.first(where: { $0.key == property.key }) else {
                    return property.value.isOptional
                }
                return property.value.isSuperset(of: written.value)
            }
        default:
            false
        }
    }

    /// Whether every value valid under this schema is valid under `other`,
    /// as in `writer.isSubset(of: reader)`.
    public func isSubset(of other: JSONSchema) -> Bool {
        other.isSuperset(of: self)
    }

    /// Whether each schema can decode every value written under the other.
    ///
    /// This is broader than `==`. `{"a"}` and `{"a", "b"?}` are compatible,
    /// because the first ignores `b` and the second treats it as missing.
    /// It is not transitive, so it cannot be captured by an id.
    public func isCompatible(with other: JSONSchema) -> Bool {
        isSuperset(of: other) && isSubset(of: other)
    }
}

private extension JSONSchema {
    /// `nil` permits any value, so it includes every list. A restricted list
    /// never includes an unrestricted one.
    static func cases<Value>(_ cases: Set<Value>?, include other: Set<Value>?) -> Bool {
        guard let cases else { return true }
        guard let other else { return false }
        return cases.isSuperset(of: other)
    }
}
