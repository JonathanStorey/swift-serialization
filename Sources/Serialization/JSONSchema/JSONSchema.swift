/// A Swift-first description of the shape of a ``JSONRepresentation`` value.
///
/// The cases line up with ``JSONRepresentation``. Two differences follow Swift rather than
/// JSON: `integer` and `number` are separate, and there is no `required`
/// list. Every property is required unless its schema is ``optional(_:)``.
public indirect enum JSONSchema: Sendable {
    public typealias Properties = [(key: String, value: JSONSchema)]

    case null
    case boolean
    /// A whole number. `cases` lists the raw values of an `Int` raw-value enum,
    /// the only values permitted, and `nil` permits any integer.
    case integer(cases: Set<Int64>? = nil)
    case number
    /// A string. `cases` lists the raw values of a `String` raw-value enum,
    /// the only values permitted, and `nil` permits any string.
    case string(cases: Set<String>? = nil)
    case array(JSONSchema)
    /// An object. Property names must be unique, and writing ``json(_:)`` checks
    /// this in debug builds.
    case object(Properties)
    /// A value that may also be `null`, or a property that may be missing.
    /// Nested optionals mean the same as one, as with `Int??` in JSON, so
    /// `.optional(.optional(x))` equals, hashes and writes as `.optional(x)`.
    case optional(JSONSchema)
}

extension JSONSchema {
    var isOptional: Bool {
        if case .optional = self { true } else { false }
    }

    /// The schema with nested optionals collapsed to one.
    var flattened: JSONSchema {
        if case .optional(.optional(let inner)) = self { JSONSchema.optional(inner).flattened } else { self }
    }
}

// Tuples cannot conform to protocols, so `Equatable` and `Hashable` are
// written by hand. Properties compare and hash without regard to order, like
// `Dictionary`.
extension JSONSchema: Hashable {
    public static func == (lhs: JSONSchema, rhs: JSONSchema) -> Bool {
        switch (lhs.flattened, rhs.flattened) {
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
        switch flattened {
        case .null: hasher.combine(0)
        case .boolean: hasher.combine(1)
        case .integer(let cases):
            hasher.combine(2)
            hasher.combine(cases)
        case .number: hasher.combine(3)
        case .string(let cases):
            hasher.combine(4)
            hasher.combine(cases)
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
