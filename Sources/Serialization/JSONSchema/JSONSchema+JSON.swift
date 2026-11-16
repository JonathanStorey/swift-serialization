/// Converts to and from standard JSON Schema text.
///
/// An optional property is left out of `required`, matching `JSONEncoder`,
/// which omits `nil` properties. `required` is written sorted, so equal
/// schemas write equal JSON. Anywhere else, an optional schema is written
/// as `{"anyOf": [<wrapped>, {"type": "null"}]}`.
///
/// Schemas come from types through `JSONSchema(for:)`. A stored schema is
/// read back with `Codable`, which uses the internal `init?(json:)`. That
/// initializer reads exactly the subset of JSON Schema that `json(_:)`
/// writes in either ``Style``, so it restores schemas this library wrote
/// rather than importing arbitrary ones. Anything it cannot represent fails
/// instead of being dropped: an unknown keyword, a duplicate key, or a
/// `required` name with no matching property.
extension JSONSchema {
    init?(json: JSONRepresentation) {
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
                guard let cases = Self.cases(from: json, \.int64Value) else { return nil }
                schema = .integer(cases: cases)
            case "number": schema = .number
            case "string":
                guard let cases = Self.cases(from: json, \.stringValue) else { return nil }
                schema = .string(cases: cases)
            case "array":
                guard let items = json["items"].flatMap(JSONSchema.init(json:)) else { return nil }
                schema = .array(items)
            case "object":
                guard (json["additionalProperties"] ?? false) == false,
                      let properties = Self.properties(from: json)
                else { return nil }
                schema = .object(properties)
            default:
                return nil
            }
            allowedKeys = switch type {
            case "array": ["type", "items"]
            case "object": ["type", "properties", "required", "additionalProperties"]
            case "integer", "string": ["type", "enum"]
            default: ["type"]
            }
        }

        guard allowedKeys.isSuperset(of: keys) else { return nil }
        self = schema
    }

    /// The schema in the ``Style/standard`` style.
    var json: JSONRepresentation {
        json(.standard)
    }
}

extension JSONSchema {
    /// How optional properties and undeclared keys are written.
    public enum Style: Sendable {
        /// Matches `JSONEncoder` output. An optional property is left out of
        /// `required`, because `JSONEncoder` omits `nil` properties.
        case standard
        /// The form structured-output APIs require in strict mode. Every
        /// property is listed in `required`, an optional property is written
        /// as nullable, and every object sets `"additionalProperties": false`.
        case strict
    }

    /// The schema as JSON Schema in the given style. Both styles read back
    /// to the same schema with `init?(json:)`.
    public func json(_ style: Style) -> JSONRepresentation {
        switch flattened {
        case .null: return ["type": "null"]
        case .boolean: return ["type": "boolean"]
        case .integer(let cases): return Self.scalar("integer", cases: cases?.sorted().map { JSONRepresentation.number(String($0)) })
        case .number: return ["type": "number"]
        case .string(let cases): return Self.scalar("string", cases: cases?.sorted().map(JSONRepresentation.string))
        case .array(let items): return ["type": "array", "items": items.json(style)]
        case .optional(let wrapped): return ["anyOf": [wrapped.json(style), Self.null.json]]
        case .object(let properties):
            assert(Set(properties.map(\.key)).count == properties.count, "JSONSchema.object has duplicate property names")
            // `required` is a set in JSON Schema. Sorting it means equal
            // schemas, whatever their property order, write equal JSON.
            switch style {
            case .standard:
                var object: JSONRepresentation.Object = [
                    (key: "type", value: "object"),
                    (key: "properties", value: .object(properties.map { (key: $0.key, value: $0.value.propertySchema.json(style)) })),
                ]
                let required = properties.filter { !$0.value.isOptional }.map(\.key).sorted().map(JSONRepresentation.string)
                if !required.isEmpty {
                    object.append((key: "required", value: .array(required)))
                }
                return .object(object)
            case .strict:
                return .object([
                    (key: "type", value: "object"),
                    (key: "properties", value: .object(properties.map { (key: $0.key, value: $0.value.json(style)) })),
                    (key: "required", value: .array(properties.map(\.key).sorted().map(JSONRepresentation.string))),
                    (key: "additionalProperties", value: false),
                ])
            }
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
    static func cases<Value: Hashable>(from json: JSONRepresentation, _ read: (JSONRepresentation) -> Value?) -> Set<Value>?? {
        guard let list = json["enum"] else { return .some(nil) }
        guard let elements = list.arrayValue else { return nil }
        let values = elements.compactMap(read)
        guard values.count == elements.count else { return nil }
        let allowed = Set(values)
        guard allowed.count == values.count else { return nil }
        return allowed
    }

    /// Reads `properties` and `required` from an object schema. A property
    /// missing from `required` becomes ``JSONSchema/optional(_:)``.
    static func properties(from json: JSONRepresentation) -> Properties? {
        guard case .object(let object) = json["properties"] ?? [:],
              let requiredList = (json["required"] ?? []).arrayValue
        else { return nil }
        let required = requiredList.compactMap(\.stringValue)
        guard required.count == requiredList.count else { return nil }
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
        if case .optional(let wrapped) = flattened { wrapped } else { self }
    }
}
