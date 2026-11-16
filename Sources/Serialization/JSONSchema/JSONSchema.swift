/// A Swift-first description of the shape of a ``JSON`` value.
///
/// The cases line up with ``JSON``. Two differences follow Swift rather than
/// JSON: `integer` and `number` are separate, and there is no `required`
/// list. Every property is required unless its schema is ``optional(_:)``.
public indirect enum JSONSchema: Sendable {
    public typealias Properties = [(key: String, value: JSONSchema)]

    case null
    case boolean
    case integer
    case number
    case string
    case array(JSONSchema)
    case object(Properties)
    case optional(JSONSchema)
}

// Tuples cannot conform to protocols, so `Equatable` and `Hashable` are
// written by hand. Properties compare in order.
extension JSONSchema: Hashable {
    public static func == (lhs: JSONSchema, rhs: JSONSchema) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null), (.boolean, .boolean), (.integer, .integer), (.number, .number), (.string, .string): true
        case let (.array(l), .array(r)): l == r
        case let (.optional(l), .optional(r)): l == r
        case let (.object(l), .object(r)): l.elementsEqual(r) { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null: hasher.combine(0)
        case .boolean: hasher.combine(1)
        case .integer: hasher.combine(2)
        case .number: hasher.combine(3)
        case .string: hasher.combine(4)
        case .array(let items):
            hasher.combine(5)
            hasher.combine(items)
        case .object(let properties):
            hasher.combine(6)
            hasher.combine(properties.count)
            for (key, value) in properties {
                hasher.combine(key)
                hasher.combine(value)
            }
        case .optional(let wrapped):
            hasher.combine(7)
            hasher.combine(wrapped)
        }
    }
}
