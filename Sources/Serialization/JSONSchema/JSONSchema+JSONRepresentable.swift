/// Converts to and from standard JSON Schema text.
///
/// An optional property is left out of `required`, matching `JSONEncoder`,
/// which omits `nil` properties. `required` is written sorted, so equal
/// schemas write equal JSON. Anywhere else, an optional schema is written
/// as `{"anyOf": [<wrapped>, {"type": "null"}]}`.
///
/// `init?(json:)` reads exactly the subset of JSON Schema that `json` writes.
/// Anything it cannot represent fails instead of being dropped: an unknown
/// keyword, a duplicate key, or a `required` name with no matching property.
extension JSONSchema: JSONRepresentable {
    public init?(json: JSONRepresentation) {
        guard case .object(let object) = json else { return nil }
        let keys = object.map(\.key)
        guard Set(keys).count == keys.count else { return nil }

        let schema: JSONSchema
        let allowedKeys: Set<String>

        if case .array(let options)? = json["anyOf"] {
            guard options.count == 2, options[1] == Self.null.json, let wrapped = JSONSchema(json: options[0]) else { return nil }
            schema = .optional(wrapped)
            allowedKeys = ["anyOf"]
        } else {
            guard case .string(let type)? = json["type"] else { return nil }
            switch type {
            case "null": schema = .null
            case "boolean": schema = .boolean
            case "integer":
                guard let cases = Self.cases(Int64.self, from: json) else { return nil }
                schema = .integer(cases: cases)
            case "number": schema = .number
            case "string":
                guard let cases = Self.cases(String.self, from: json) else { return nil }
                schema = .string(cases: cases)
            case "array":
                guard let items = json["items"].flatMap(JSONSchema.init(json:)) else { return nil }
                schema = .array(items)
            case "object":
                guard let properties = Self.properties(from: json) else { return nil }
                schema = .object(properties)
            default:
                return nil
            }
            allowedKeys = switch type {
            case "array": ["type", "items"]
            case "object": ["type", "properties", "required"]
            case "integer", "string": ["type", "enum"]
            default: ["type"]
            }
        }

        guard allowedKeys.isSuperset(of: keys) else { return nil }
        self = schema
    }

    public var json: JSONRepresentation {
        switch self {
        case .null: return ["type": "null"]
        case .boolean: return ["type": "boolean"]
        case .integer(let cases): return Self.scalar("integer", cases: cases?.sorted().map(\.json))
        case .number: return ["type": "number"]
        case .string(let cases): return Self.scalar("string", cases: cases?.sorted().map(\.json))
        case .array(let items): return ["type": "array", "items": items.json]
        case .optional(let wrapped): return ["anyOf": [wrapped.json, Self.null.json]]
        case .object(let properties):
            var object: JSONRepresentation.Object = [
                (key: "type", value: "object"),
                (key: "properties", value: .object(properties.map { (key: $0.key, value: $0.value.propertySchema.json) })),
            ]
            // `required` is a set in JSON Schema. Sorting it means equal
            // schemas, whatever their property order, write equal JSON.
            let required = properties.filter { !$0.value.isOptional }.map(\.key).sorted().map(JSONRepresentation.string)
            if !required.isEmpty {
                object.append((key: "required", value: .array(required)))
            }
            return .object(object)
        }
    }
}

private extension JSONSchema {
    /// `{"type": <type>}`, plus a sorted `"enum"` list when values are
    /// restricted, so equal schemas write equal JSON.
    static func scalar(_ type: String, cases: [JSONRepresentation]?) -> JSONRepresentation {
        var object: JSONRepresentation.Object = [(key: "type", value: .string(type))]
        if let cases {
            object.append((key: "enum", value: .array(cases)))
        }
        return .object(object)
    }

    /// Reads an optional `"enum"` list. Returns `.some(nil)` when there is no
    /// list, and `nil` when the list is malformed or repeats a value.
    static func cases<Value: JSONRepresentable & Hashable>(_ type: Value.Type, from json: JSONRepresentation) -> Set<Value>?? {
        guard let list = json["enum"] else { return .some(nil) }
        guard let values = [Value](json: list) else { return nil }
        let allowed = Set(values)
        guard allowed.count == values.count else { return nil }
        return allowed
    }

    /// Reads `properties` and `required` from an object schema. A property
    /// missing from `required` becomes ``JSONSchema/optional(_:)``.
    static func properties(from json: JSONRepresentation) -> Properties? {
        guard case .object(let object) = json["properties"] ?? [:],
              let required = [String](json: json["required"] ?? [])
        else { return nil }
        let names = object.map(\.key)
        guard Set(names).count == names.count,
              Set(required).count == required.count,
              Set(required).isSubset(of: names)
        else { return nil }

        var properties: Properties = []
        for (name, value) in object {
            guard let schema = JSONSchema(json: value) else { return nil }
            properties.append((key: name, value: required.contains(name) ? schema : .optional(schema)))
        }
        return properties
    }

    /// The schema written under `properties`. Optionality is carried by the
    /// `required` list instead.
    var propertySchema: JSONSchema {
        if case .optional(let wrapped) = self { wrapped } else { self }
    }
}
