/// Encodes and decodes as JSON Schema text, through ``JSONRepresentation``.
extension JSONSchema: Codable {
    public init(from decoder: any Decoder) throws {
        let representation = try JSONRepresentation(from: decoder)
        guard let schema = JSONSchema(document: representation) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "The value is not a JSON Schema that JSONSchema can represent."
            ))
        }
        self = schema
    }

    /// Writes the ``json`` document, which declares the dialect with
    /// `"$schema"`.
    public func encode(to encoder: any Encoder) throws {
        try json.encode(to: encoder)
    }
}

/// The schema as compact JSON Schema text.
extension JSONSchema: CustomStringConvertible {
    public var description: String { body.description }
}
