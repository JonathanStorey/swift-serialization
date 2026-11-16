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
    var numberText: String? {
        guard case .number(let text) = self else { return nil }
        return text
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
    public init?(json: JSON) {
        guard let text = json.numberText, let value = Self(text), value.isFinite else { return nil }
        self = value
    }

    /// Non-finite values have no JSON representation and become ``JSON/null``.
    public var json: JSON { isFinite ? .number(jsonNumberText) : .null }
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
