/// Converts to and from standard JSON Schema text.
///
/// An optional property is left out of `required`, matching `JSONEncoder`,
/// which omits `nil` properties. Anywhere else, an optional schema is written
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
            case "integer": schema = .integer
            case "number": schema = .number
            case "string": schema = .string
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
        case .integer: return ["type": "integer"]
        case .number: return ["type": "number"]
        case .string: return ["type": "string"]
        case .array(let items): return ["type": "array", "items": items.json]
        case .optional(let wrapped): return ["anyOf": [wrapped.json, Self.null.json]]
        case .object(let properties):
            var object: JSONRepresentation.Object = [
                (key: "type", value: "object"),
                (key: "properties", value: .object(properties.map { (key: $0.key, value: $0.value.propertySchema.json) })),
            ]
            let required = properties.filter { !$0.value.isOptional }.map { JSONRepresentation.string($0.key) }
            if !required.isEmpty {
                object.append((key: "required", value: .array(required)))
            }
            return .object(object)
        }
    }
}

private extension JSONSchema {
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

    var isOptional: Bool {
        if case .optional = self { true } else { false }
    }

    /// The schema written under `properties`. Optionality is carried by the
    /// `required` list instead.
    var propertySchema: JSONSchema {
        if case .optional(let wrapped) = self { wrapped } else { self }
    }
}
