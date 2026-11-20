/// A Swift-first description of the shape of a ``JSONRepresentation`` value.
///
/// The cases line up with ``JSONRepresentation`` and are written as JSON
/// Schema draft 2020-12. A few differences follow Swift rather than JSON:
/// `integer` and `number` are separate, `set` and `dictionary` have cases of
/// their own, and there is no `required` list. Every property is required
/// unless its schema is ``optional(_:)``.
public indirect enum JSONSchema: Sendable {
    public typealias Properties = [(key: String, value: JSONSchema)]

    case null
    case boolean
    /// A whole number. `cases` lists the raw values of an `Int` raw-value enum,
    /// the only values permitted, and `nil` permits any integer. `minimum`
    /// and `maximum` are inclusive bounds, such as `0...255` for `UInt8`.
    case integer(cases: Set<Int64>? = nil, minimum: Int64? = nil, maximum: Int64? = nil)
    case number
    /// A string. `cases` lists the raw values of a `String` raw-value enum,
    /// the only values permitted, and `nil` permits any string. `format`
    /// says what the text holds, such as a `UUID`.
    case string(cases: Set<String>? = nil, format: Format? = nil)
    case array(JSONSchema)
    /// An array whose elements are all different, as `Set` writes.
    case set(JSONSchema)
    /// An object. Property names must be unique, and writing ``json`` checks
    /// this in debug builds.
    case object(Properties)
    /// An object with any keys and values of one schema, as a `Dictionary`
    /// keyed by `String` writes.
    case dictionary(JSONSchema)
    /// A value that may also be `null`, or a property that may be missing.
    /// Nested optionals mean the same as one, as with `Int??` in JSON, so
    /// `.optional(.optional(x))` equals, hashes and writes as `.optional(x)`.
    case optional(JSONSchema)
}

extension JSONSchema {
    /// What a string holds, written with the JSON Schema 2020-12 keyword
    /// for it.
    public enum Format: String, CaseIterable, Hashable, Sendable {
        /// A `UUID`, written as `"format": "uuid"`.
        case uuid
        /// A `URL`, written as `"format": "uri-reference"`, because a URL
        /// may be relative.
        case uriReference = "uri-reference"
        /// `Data`, written as `"contentEncoding": "base64"`.
        case base64
    }
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
        case let (.integer(l, lMin, lMax), .integer(r, rMin, rMax)): (l, lMin, lMax) == (r, rMin, rMax)
        case let (.string(l, lFormat), .string(r, rFormat)): l == r && lFormat == rFormat
        case let (.array(l), .array(r)), let (.set(l), .set(r)), let (.dictionary(l), .dictionary(r)), let (.optional(l), .optional(r)): l == r
        case let (.object(l), .object(r)): l.hasSamePairs(as: r)
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch flattened {
        case .null: hasher.combine(0)
        case .boolean: hasher.combine(1)
        case .integer(let cases, let minimum, let maximum):
            hasher.combine(2)
            hasher.combine(cases)
            hasher.combine(minimum)
            hasher.combine(maximum)
        case .number: hasher.combine(3)
        case .string(let cases, let format):
            hasher.combine(4)
            hasher.combine(cases)
            hasher.combine(format)
        case .array(let items):
            hasher.combine(5)
            hasher.combine(items)
        case .object(let properties):
            hasher.combine(6)
            properties.hashPairsIgnoringOrder(into: &hasher)
        case .optional(let wrapped):
            hasher.combine(7)
            hasher.combine(wrapped)
        case .set(let items):
            hasher.combine(8)
            hasher.combine(items)
        case .dictionary(let values):
            hasher.combine(9)
            hasher.combine(values)
        }
    }
}
