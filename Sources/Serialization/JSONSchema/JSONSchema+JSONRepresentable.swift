/// Converts to and from standard JSON Schema text.
///
/// An optional property is left out of `required`, matching `JSONEncoder`,
/// which omits `nil` properties. Anywhere else, an optional schema is written
/// as `{"anyOf": [<wrapped>, {"type": "null"}]}`.
///
/// `init?(json:)` reads the subset of JSON Schema that `json` writes.
extension JSONSchema: JSONRepresentable {
    public init?(json: JSON) {
        if case .array(let options)? = json["anyOf"] {
            guard options.count == 2, options[1] == Self.null.json, let wrapped = JSONSchema(json: options[0]) else { return nil }
            self = .optional(wrapped)
            return
        }
        guard case .string(let type)? = json["type"] else { return nil }
        switch type {
        case "null": self = .null
        case "boolean": self = .boolean
        case "integer": self = .integer
        case "number": self = .number
        case "string": self = .string
        case "array":
            guard let items = json["items"].flatMap(JSONSchema.init(json:)) else { return nil }
            self = .array(items)
        case "object":
            guard case .object(let properties) = json["properties"] ?? [:],
                  let required = [String](json: json["required"] ?? [])
            else { return nil }
            var result: Properties = []
            for (key, value) in properties {
                guard let schema = JSONSchema(json: value) else { return nil }
                result.append((key: key, value: required.contains(key) ? schema : .optional(schema)))
            }
            self = .object(result)
        default:
            return nil
        }
    }

    public var json: JSON {
        switch self {
        case .null: return ["type": "null"]
        case .boolean: return ["type": "boolean"]
        case .integer: return ["type": "integer"]
        case .number: return ["type": "number"]
        case .string: return ["type": "string"]
        case .array(let items): return ["type": "array", "items": items.json]
        case .optional(let wrapped): return ["anyOf": [wrapped.json, Self.null.json]]
        case .object(let properties):
            var object: JSON.Object = [
                (key: "type", value: "object"),
                (key: "properties", value: .object(properties.map { (key: $0.key, value: $0.value.propertySchema.json) })),
            ]
            let required = properties.filter { !$0.value.isOptional }.map { JSON.string($0.key) }
            if !required.isEmpty {
                object.append((key: "required", value: .array(required)))
            }
            return .object(object)
        }
    }
}

private extension JSONSchema {
    var isOptional: Bool {
        if case .optional = self { true } else { false }
    }

    /// The schema written under `properties`. Optionality is carried by the
    /// `required` list instead.
    var propertySchema: JSONSchema {
        if case .optional(let wrapped) = self { wrapped } else { self }
    }
}
