/// Number text and typed reads used inside the package.
extension JSONRepresentation {
    /// The text of a number that matches the JSON number grammar, otherwise
    /// `nil`. Swift's numeric parsers accept text JSON does not, such as
    /// `"+1"`, `".5"` and `"0x1p3"`, so the grammar is checked first.
    var numberText: String? {
        guard case .number(let text) = self, text.isJSONNumber else { return nil }
        return text
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var int64Value: Int64? {
        numberText.flatMap { Int64($0, radix: 10) }
    }

    var uint64Value: UInt64? {
        numberText.flatMap { UInt64($0, radix: 10) }
    }

    var doubleValue: Double? {
        numberText.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
    }

    var arrayValue: [JSONRepresentation]? {
        if case .array(let elements) = self { elements } else { nil }
    }
}
