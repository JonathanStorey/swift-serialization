import Foundation

extension JSONRepresentation {
    /// Whether two values hold the same data, comparing numbers by value so
    /// that `1`, `1.0` and `1e0` match. Everything else compares as `==`
    /// does, with object keys in any order.
    func isEquivalent(to other: JSONRepresentation) -> Bool {
        switch (self, other) {
        case let (.number(lhs), .number(rhs)):
            lhs == rhs || lhs.jsonNumberValue.map { $0 == rhs.jsonNumberValue } ?? false
        case let (.array(lhs), .array(rhs)):
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.isEquivalent(to: $1) }
        case let (.object(lhs), .object(rhs)):
            lhs.count == rhs.count && lhs.allSatisfy { pair in
                rhs.first { $0.key == pair.key }.map { $0.value.isEquivalent(to: pair.value) } ?? false
            }
        default:
            self == other
        }
    }
}

extension JSONRepresentation {
    /// Whether `schema`'s type would decode both values the same: keys it
    /// does not declare are ignored, and a missing optional property equals
    /// `null`. A schema that does not fit the values is ignored, and `nil`
    /// compares everything.
    func isEquivalent(to other: JSONRepresentation, under schema: JSONSchema?) -> Bool {
        switch (schema?.flattened, self, other) {
        case (nil, _, _):
            return isEquivalent(to: other)
        case (.optional(let wrapped)?, _, _):
            return self == .null || other == .null ? self == other : isEquivalent(to: other, under: wrapped)
        case let (.array(items)?, .array(lhs), .array(rhs)), let (.set(items)?, .array(lhs), .array(rhs)):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.isEquivalent(to: $1, under: items) }
        case let (.dictionary(values)?, .object(lhs), .object(rhs)):
            return lhs.count == rhs.count && lhs.allSatisfy { pair in
                rhs.first { $0.key == pair.key }.map { $0.value.isEquivalent(to: pair.value, under: values) } ?? false
            }
        case let (.object(properties)?, .object, .object):
            return properties.allSatisfy { property in
                let schema = property.value
                let lhs = self[property.key], rhs = other[property.key]
                if schema.isOptional { return (lhs ?? .null).isEquivalent(to: rhs ?? .null, under: schema) }
                guard let lhs, let rhs else { return lhs == nil && rhs == nil }
                return lhs.isEquivalent(to: rhs, under: schema)
            }
        default:
            return isEquivalent(to: other)
        }
    }
}

private extension String {
    /// The exact value of valid JSON number text, or `nil`. `Decimal` holds
    /// 38 significant digits, so longer numbers compare after rounding.
    var jsonNumberValue: Decimal? {
        guard isJSONNumber, let value = Decimal(string: self), !value.isNaN else { return nil }
        return value
    }
}
