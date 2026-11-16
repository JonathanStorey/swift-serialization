/// A type that can be converted to and from a ``JSON`` value.
///
/// The shape follows `RawRepresentable`: a failable initializer and a
/// read-only property.
public protocol JSONRepresentable {
    init?(json: JSON)
    var json: JSON { get }
}

// MARK: - JSON

extension JSON: JSONRepresentable {
    public init?(json: JSON) {
        self = json
    }

    public var json: JSON { self }
}

// MARK: - Strings and Booleans

extension String: JSONRepresentable {
    public init?(json: JSON) {
        guard case .string(let value) = json else { return nil }
        self = value
    }

    public var json: JSON { .string(self) }
}

extension Bool: JSONRepresentable {
    public init?(json: JSON) {
        guard case .bool(let value) = json else { return nil }
        self = value
    }

    public var json: JSON { .bool(self) }
}

// MARK: - Numbers

private extension JSON {
    /// The text of a number that matches the JSON number grammar, otherwise
    /// `nil`. Swift's numeric parsers accept text JSON does not, such as
    /// `"+1"`, `".5"` and `"0x1p3"`, so the grammar is checked first.
    var numberText: String? {
        guard case .number(let text) = self, text.isJSONNumber else { return nil }
        return text
    }
}

private extension String {
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

extension JSONRepresentable where Self: FixedWidthInteger {
    public init?(json: JSON) {
        guard let text = json.numberText, let value = Self(text, radix: 10) else { return nil }
        self = value
    }

    public var json: JSON { .number(description) }
}

extension Int: JSONRepresentable {}
extension Int8: JSONRepresentable {}
extension Int16: JSONRepresentable {}
extension Int32: JSONRepresentable {}
extension Int64: JSONRepresentable {}
extension UInt: JSONRepresentable {}
extension UInt8: JSONRepresentable {}
extension UInt16: JSONRepresentable {}
extension UInt32: JSONRepresentable {}
extension UInt64: JSONRepresentable {}

extension JSONRepresentable where Self: BinaryFloatingPoint & LosslessStringConvertible {
    /// Reads a number, or one of the strings `"NaN"`, `"Infinity"` and
    /// `"-Infinity"`. A number too large for the type returns `nil`.
    public init?(json: JSON) {
        switch json {
        case .string("NaN"):
            self = .nan
        case .string("Infinity"):
            self = .infinity
        case .string("-Infinity"):
            self = -Self.infinity
        default:
            guard let text = json.numberText, let value = Self(text), value.isFinite else { return nil }
            self = value
        }
    }

    /// Non-finite values have no JSON number form. They are written as the
    /// strings `"NaN"`, `"Infinity"` and `"-Infinity"`, matching
    /// `JSONEncoder.NonConformingFloatEncodingStrategy.convertToString`
    /// with those names, so every value round-trips.
    public var json: JSON {
        if isNaN { return .string("NaN") }
        if isInfinite { return .string(sign == .minus ? "-Infinity" : "Infinity") }
        return .number(jsonNumberText)
    }
}

extension BinaryFloatingPoint where Self: LosslessStringConvertible {
    /// The number text `JSONEncoder` writes: `description` without a
    /// trailing `.0`, so `8.0` is written as `8`.
    var jsonNumberText: String {
        let text = description
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

extension Float: JSONRepresentable {}
extension Double: JSONRepresentable {}

// MARK: - Containers

extension Optional: JSONRepresentable where Wrapped: JSONRepresentable {
    public init?(json: JSON) {
        if case .null = json {
            self = nil
            return
        }
        guard let wrapped = Wrapped(json: json) else { return nil }
        self = wrapped
    }

    public var json: JSON { map(\.json) ?? .null }
}

extension Array: JSONRepresentable where Element: JSONRepresentable {
    public init?(json: JSON) {
        guard case .array(let elements) = json else { return nil }
        let values = elements.compactMap { Element(json: $0) }
        guard values.count == elements.count else { return nil }
        self = values
    }

    public var json: JSON { .array(map(\.json)) }
}
