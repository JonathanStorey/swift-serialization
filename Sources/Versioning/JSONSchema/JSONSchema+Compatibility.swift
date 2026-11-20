/// Compatibility follows `JSONDecoder`. A schema is read as the set of JSON
/// values a type decodes successfully:
///
/// - An object ignores keys it does not declare.
/// - An optional property may be missing or `null`.
/// - An `integer` is a valid `number`, because `Double` decodes `1`.
/// - Restricted `cases` must contain every case the other side can send,
///   and integer bounds must contain the other side's bounds, so an `Int8`
///   reader does not accept an `Int` writer.
/// - A string `format` must match, because a `UUID` cannot decode any
///   string. A plain string reader accepts every format.
/// - An `array` accepts a `set`, but a `set` does not accept an `array`,
///   because `Set` would silently drop repeated elements.
///
/// `Int`, `Int64`, `UInt` and `UInt64` have no upper bound in a schema, so
/// that their schemas are the same on every platform.
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
        case let (.integer(cases, minimum, maximum), .integer(otherCases, otherMinimum, otherMaximum)):
            if let otherCases {
                otherCases
                    .filter { Self.integer($0, isAtLeast: otherMinimum, atMost: otherMaximum) }
                    .allSatisfy { (cases?.contains($0) ?? true) && Self.integer($0, isAtLeast: minimum, atMost: maximum) }
            } else {
                cases == nil
                    && (otherMinimum ?? .min) >= (minimum ?? .min)
                    && (otherMaximum ?? .max) <= (maximum ?? .max)
            }
        case let (.string(cases, format), .string(otherCases, otherFormat)):
            (format == nil || format == otherFormat) && Self.cases(cases, include: otherCases)
        case let (.array(items), .array(otherItems)), let (.array(items), .set(otherItems)),
             let (.set(items), .set(otherItems)), let (.dictionary(items), .dictionary(otherItems)):
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

extension JSONSchema {
    /// Whether `value` lies within the inclusive bounds, where `nil` means
    /// unbounded.
    static func integer(_ value: Int64, isAtLeast minimum: Int64?, atMost maximum: Int64?) -> Bool {
        value >= (minimum ?? .min) && value <= (maximum ?? .max)
    }
}
