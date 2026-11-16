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
