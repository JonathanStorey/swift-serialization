extension JSONRepresentation: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSONRepresentation: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONRepresentation: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .number(String(value))
    }
}

extension JSONRepresentation: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value.jsonNumberText)
    }
}

extension JSONRepresentation: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONRepresentation: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONRepresentation...) {
        self = .array(elements)
    }
}

extension JSONRepresentation: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONRepresentation)...) {
        self = .object(elements.map { (key: $0, value: $1) })
    }
}
