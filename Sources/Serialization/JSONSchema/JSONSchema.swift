/// A Swift-first description of the shape of a ``JSONRepresentation`` value.
///
/// The cases line up with ``JSONRepresentation``. Two differences follow Swift rather than
/// JSON: `integer` and `number` are separate, and there is no `required`
/// list. Every property is required unless its schema is ``optional(_:)``.
public indirect enum JSONSchema: Sendable {
    public typealias Properties = [(key: String, value: JSONSchema)]

    case null
    case boolean
    /// A whole number. `allowed` lists the only permitted values, as for an
    /// `Int` raw-value enum, and `nil` permits any integer.
    case integer(allowed: Set<Int64>? = nil)
    case number
    /// A string. `allowed` lists the only permitted values, as for a `String`
    /// raw-value enum, and `nil` permits any string.
    case string(allowed: Set<String>? = nil)
    case array(JSONSchema)
    case object(Properties)
    case optional(JSONSchema)
}

// Tuples cannot conform to protocols, so `Equatable` and `Hashable` are
// written by hand. Properties compare and hash without regard to order, like
// `Dictionary`.
extension JSONSchema: Hashable {
    public static func == (lhs: JSONSchema, rhs: JSONSchema) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null), (.boolean, .boolean), (.number, .number): true
        case let (.integer(l), .integer(r)): l == r
        case let (.string(l), .string(r)): l == r
        case let (.array(l), .array(r)): l == r
        case let (.optional(l), .optional(r)): l == r
        case let (.object(l), .object(r)): l.hasSamePairs(as: r)
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null: hasher.combine(0)
        case .boolean: hasher.combine(1)
        case .integer(let allowed):
            hasher.combine(2)
            hasher.combine(allowed)
        case .number: hasher.combine(3)
        case .string(let allowed):
            hasher.combine(4)
            hasher.combine(allowed)
        case .array(let items):
            hasher.combine(5)
            hasher.combine(items)
        case .object(let properties):
            hasher.combine(6)
            properties.hashPairsIgnoringOrder(into: &hasher)
        case .optional(let wrapped):
            hasher.combine(7)
            hasher.combine(wrapped)
        }
    }
}
