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

private extension String {
    /// The exact value of valid JSON number text, or `nil`. `Decimal` holds
    /// 38 significant digits, so longer numbers compare after rounding.
    var jsonNumberValue: Decimal? {
        guard isJSONNumber, let value = Decimal(string: self), !value.isNaN else { return nil }
        return value
    }
}
