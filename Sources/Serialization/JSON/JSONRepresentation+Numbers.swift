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

extension String {
    /// Whether the text matches the JSON number grammar (RFC 8259):
    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`
    var isJSONNumber: Bool {
        var bytes = utf8[...]

        func skipDigits() -> Int {
            let count = bytes.prefix { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }.count
            bytes = bytes.dropFirst(count)
            return count
        }

        if bytes.first == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        if bytes.first == UInt8(ascii: "0") {
            bytes = bytes.dropFirst()
        } else if skipDigits() == 0 {
            return false
        }
        if bytes.first == UInt8(ascii: ".") {
            bytes = bytes.dropFirst()
            guard skipDigits() > 0 else { return false }
        }
        if bytes.first == UInt8(ascii: "e") || bytes.first == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if bytes.first == UInt8(ascii: "+") || bytes.first == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
            guard skipDigits() > 0 else { return false }
        }
        return bytes.isEmpty
    }
}

extension BinaryFloatingPoint where Self: LosslessStringConvertible {
    /// The number text `JSONEncoder` writes: `description` without a
    /// trailing `.0`, so `8.0` is written as `8`.
    var jsonNumberText: String {
        let text = description
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// Non-finite values have no JSON number form. They are written as the
    /// strings `"NaN"`, `"Infinity"` and `"-Infinity"`, matching
    /// `JSONEncoder.NonConformingFloatEncodingStrategy.convertToString`
    /// with those names, so every value round-trips.
    var jsonRepresentation: JSONRepresentation {
        if isNaN { return .string("NaN") }
        if isInfinite { return .string(sign == .minus ? "-Infinity" : "Infinity") }
        return .number(jsonNumberText)
    }
}
