/// A JSON value.
///
/// The cases mirror the value model used by Foundation's `JSONEncoder` and
/// `JSONDecoder`. A number keeps its original text so that no precision is
/// lost. It is converted to a concrete numeric type only when one is
/// requested through ``JSONRepresentable``.
///
/// An object is stored as key-value pairs in insertion order, using the same
/// tuple labels as `Dictionary.Element`.
public enum JSONRepresentation: Sendable {
    public typealias Object = [(key: String, value: JSONRepresentation)]

    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONRepresentation])
    case object(Object)
}

// Tuples cannot conform to protocols, so `Equatable` and `Hashable` are
// written by hand. Objects compare in order: the same pairs in a different
// order are not equal.
extension JSONRepresentation: Hashable {
    public static func == (lhs: JSONRepresentation, rhs: JSONRepresentation) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case let (.bool(l), .bool(r)): l == r
        case let (.number(l), .number(r)): l == r
        case let (.string(l), .string(r)): l == r
        case let (.array(l), .array(r)): l == r
        case let (.object(l), .object(r)): l.elementsEqual(r) { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0)
        case .bool(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .number(let text):
            hasher.combine(2)
            hasher.combine(text)
        case .string(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .array(let elements):
            hasher.combine(4)
            hasher.combine(elements)
        case .object(let object):
            hasher.combine(5)
            hasher.combine(object.count)
            for (key, value) in object {
                hasher.combine(key)
                hasher.combine(value)
            }
        }
    }
}
