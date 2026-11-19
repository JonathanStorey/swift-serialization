/// Converts to and from JSON Schema draft 2020-12 text.
///
/// Every keyword written is one the 2020-12 dialect defines: `type`,
/// `enum`, `minimum`, `maximum`, `format`, `contentEncoding`, `items`,
/// `uniqueItems`, `properties`, `required`, `additionalProperties` and
/// `anyOf`. A document in the ``Style/standard`` style also declares the
/// dialect with `"$schema"`.
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
    /// The URI that declares the JSON Schema 2020-12 dialect.
    static let dialect: JSONRepresentation = "https://json-schema.org/draft/2020-12/schema"

    /// Reads a whole document, whose root may declare the dialect with
    /// `"$schema"`. Any other dialect is refused.
    init?(document: JSONRepresentation) {
        guard case .object(var object) = document else { return nil }
        if let index = object.firstIndex(where: { $0.key == "$schema" }) {
            guard object[index].value == Self.dialect else { return nil }
            object.remove(at: index)
        }
        self.init(json: .object(object))
    }

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
                guard let cases = Self.cases(from: json, \.int64Value),
                      let minimum = Self.bound(json["minimum"]),
                      let maximum = Self.bound(json["maximum"])
                else { return nil }
                schema = .integer(cases: cases, minimum: minimum, maximum: maximum)
            case "number": schema = .number
            case "string":
                guard let cases = Self.cases(from: json, \.stringValue), let format = Self.format(from: json) else { return nil }
                schema = .string(cases: cases, format: format)
            case "array":
                guard let items = json["items"].flatMap(JSONSchema.init(json:)),
                      case .bool(let isUnique) = json["uniqueItems"] ?? false
                else { return nil }
                schema = isUnique ? .set(items) : .array(items)
            case "object":
                switch json["additionalProperties"] {
                case nil, .bool(false)?:
                    guard let properties = Self.properties(from: json) else { return nil }
                    schema = .object(properties)
                case .object?:
                    guard json["properties"] == nil, json["required"] == nil,
                          let values = json["additionalProperties"].flatMap(JSONSchema.init(json:))
                    else { return nil }
                    schema = .dictionary(values)
                default:
                    return nil
                }
            default:
                return nil
            }
            allowedKeys = switch type {
            case "array": ["type", "items", "uniqueItems"]
            case "object": ["type", "properties", "required", "additionalProperties"]
            case "integer": ["type", "enum", "minimum", "maximum"]
            case "string": ["type", "enum", "format", "contentEncoding"]
            default: ["type"]
            }
        }

        guard allowedKeys.isSuperset(of: keys) else { return nil }
        self = schema
    }

    /// The schema in the ``Style/standard`` style, without `"$schema"`.
    /// It is what ``description`` and ``id`` are made from.
    var json: JSONRepresentation {
        body(.standard)
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

    /// The schema as a JSON Schema 2020-12 document in the given style.
    /// The ``Style/standard`` style declares the dialect with `"$schema"`,
    /// and the ``Style/strict`` style leaves it out, as structured-output
    /// APIs expect. Both read back to the same schema.
    public func json(_ style: Style) -> JSONRepresentation {
        guard style == .standard, case .object(let object) = body(style) else { return body(style) }
        return .object([(key: "$schema", value: Self.dialect)] + object)
    }

    /// The schema without `"$schema"`, as it is written inside another.
    func body(_ style: Style) -> JSONRepresentation {
        switch flattened {
        case .null: return ["type": "null"]
        case .boolean: return ["type": "boolean"]
        case .integer(let cases, let minimum, let maximum):
            var object = Self.scalar("integer", cases: cases?.sorted().map { JSONRepresentation.number(String($0)) })
            if let minimum { object.append((key: "minimum", value: .number(String(minimum)))) }
            if let maximum { object.append((key: "maximum", value: .number(String(maximum)))) }
            return .object(object)
        case .number: return ["type": "number"]
        case .string(let cases, let format):
            var object = Self.scalar("string", cases: cases?.sorted().map(JSONRepresentation.string))
            switch format {
            case nil: break
            case .base64: object.append((key: "contentEncoding", value: "base64"))
            case let format?: object.append((key: "format", value: .string(format.rawValue)))
            }
            return .object(object)
        case .array(let items): return ["type": "array", "items": items.body(style)]
        case .set(let items): return ["type": "array", "items": items.body(style), "uniqueItems": true]
        case .dictionary(let values): return ["type": "object", "additionalProperties": values.body(style)]
        case .optional(let wrapped): return ["anyOf": [wrapped.body(style), Self.null.json]]
        case .object(let properties):
            assert(Set(properties.map(\.key)).count == properties.count, "JSONSchema.object has duplicate property names")
            // `required` is a set in JSON Schema. Sorting it means equal
            // schemas, whatever their property order, write equal JSON.
            switch style {
            case .standard:
                var object: JSONRepresentation.Object = [
                    (key: "type", value: "object"),
                    (key: "properties", value: .object(properties.map { (key: $0.key, value: $0.value.propertySchema.body(style)) })),
                ]
                let required = properties.filter { !$0.value.isOptional }.map(\.key).sorted().map(JSONRepresentation.string)
                if !required.isEmpty {
                    object.append((key: "required", value: .array(required)))
                }
                return .object(object)
            case .strict:
                return .object([
                    (key: "type", value: "object"),
                    (key: "properties", value: .object(properties.map { (key: $0.key, value: $0.value.body(style)) })),
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
    static func scalar(_ type: String, cases: [JSONRepresentation]?) -> JSONRepresentation.Object {
        var object: JSONRepresentation.Object = [(key: "type", value: .string(type))]
        if let cases {
            object.append((key: "enum", value: .array(cases)))
        }
        return object
    }

    /// Reads an optional `"minimum"` or `"maximum"`. Returns `.some(nil)`
    /// when there is none, and `nil` when it is not a 64-bit integer.
    static func bound(_ json: JSONRepresentation?) -> Int64?? {
        guard let json else { return .some(nil) }
        guard let value = json.int64Value else { return nil }
        return .some(value)
    }

    /// Reads an optional `"format"` or `"contentEncoding"`. Returns
    /// `.some(nil)` when there is neither, and `nil` when either is unknown
    /// or both are present.
    static func format(from json: JSONRepresentation) -> Format?? {
        switch (json["format"], json["contentEncoding"]) {
        case (nil, nil):
            return .some(nil)
        case (.string(let name)?, nil):
            guard let format = Format(rawValue: name), format != .base64 else { return nil }
            return .some(format)
        case (nil, .string("base64")?):
            return .some(.base64)
        default:
            return nil
        }
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
