/// A difference encodes as an array of changes in the order they apply:
///
/// ```json
/// [{"op": "remove", "path": "$.rooms[0].name", "value": "A", "associatedWith": "name"},
///  {"op": "insert", "path": "$.rooms[0].name", "value": "B", "associatedWith": "name"}]
/// ```
///
/// Paths are JSONPath text, so a decoded difference equals the one encoded.
/// This is the form to store a difference or send it elsewhere, and
/// `description` is the form for people to read.
extension JSONDifference: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var removals: [Change] = []
        var insertions: [Change] = []
        while !container.isAtEnd {
            let change = try container.decode(Change.self)
            switch change {
            case .remove: removals.append(change)
            case .insert: insertions.append(change)
            }
        }
        self.init(removals: removals, insertions: insertions)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for change in self {
            try container.encode(change)
        }
    }
}

extension JSONDifference.Change: Codable {
    private enum CodingKeys: String, CodingKey {
        case op, path, value, associatedWith
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(JSONRepresentation.Path.self, forKey: .path)
        let element = try container.decode(JSONRepresentation.self, forKey: .value)
        let associatedWith = try container.decodeIfPresent(JSONRepresentation.Path.Segment.self, forKey: .associatedWith)
        switch try container.decode(String.self, forKey: .op) {
        case "insert": self = .insert(path: path, element: element, associatedWith: associatedWith)
        case "remove": self = .remove(path: path, element: element, associatedWith: associatedWith)
        case let op: throw DecodingError.dataCorruptedError(forKey: .op, in: container, debugDescription: "\"\(op)\" is not \"insert\" or \"remove\".")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let (path, element, associatedWith) = parts
        switch self {
        case .insert: try container.encode("insert", forKey: .op)
        case .remove: try container.encode("remove", forKey: .op)
        }
        try container.encode(path, forKey: .path)
        try container.encode(element, forKey: .value)
        try container.encodeIfPresent(associatedWith, forKey: .associatedWith)
    }
}
