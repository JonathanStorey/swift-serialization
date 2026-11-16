extension JSONRepresentation {
    /// The value for `key` when this is an object, otherwise `nil`.
    ///
    /// Keys are unique in any value built by `init(_:)` or decoded through
    /// `Codable`. A hand-built object with a repeated key returns the first.
    public subscript(key: String) -> JSONRepresentation? {
        guard case .object(let object) = self else { return nil }
        return object.first { $0.key == key }?.value
    }

    /// The element at `index` when this is an array and the index is in
    /// bounds, otherwise `nil`.
    public subscript(index: Int) -> JSONRepresentation? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }
}
