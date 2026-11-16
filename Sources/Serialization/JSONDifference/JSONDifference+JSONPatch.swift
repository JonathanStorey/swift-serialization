extension JSONDifference {
    /// The difference as a JSON Patch (RFC 6902), for tools in other
    /// languages. Its `description` is the patch text.
    ///
    /// Every removed or replaced value is checked first with a `test`
    /// operation, so the patch fails on a document it was not made for.
    /// A replaced object key becomes `replace`, other insertions become
    /// `add`, and a move becomes a `remove` and an `add`. Paths are JSON
    /// Pointers, such as `/rooms/0/name`.
    ///
    /// A JSON Pointer cannot tell an index from a numeric key without the
    /// document, so a patch is an export only. Store a difference through
    /// `Codable` instead.
    public var jsonPatch: JSONRepresentation {
        var operations: [JSONRepresentation] = []
        for removal in removals {
            let (path, element, associatedWith) = removal.parts
            let pointer = JSONRepresentation.string(path.jsonPointer)
            operations.append(["op": "test", "path": pointer, "value": element])
            if !path.keepsPlace(associatedWith: associatedWith) {
                operations.append(["op": "remove", "path": pointer])
            }
        }
        for insertion in insertions {
            let (path, element, associatedWith) = insertion.parts
            let op: JSONRepresentation = path.keepsPlace(associatedWith: associatedWith) ? "replace" : "add"
            operations.append(["op": op, "path": .string(path.jsonPointer), "value": element])
        }
        return .array(operations)
    }
}

private extension JSONRepresentation.Path {
    /// `/` before each segment, with `~` and `/` in keys escaped as `~0`
    /// and `~1`. The whole document is the empty string.
    var jsonPointer: String {
        var pointer = ""
        for segment in self {
            pointer += "/"
            switch segment {
            case .index(let index):
                pointer += String(index)
            case .key(let key):
                for character in key {
                    switch character {
                    case "~": pointer += "~0"
                    case "/": pointer += "~1"
                    default: pointer.append(character)
                    }
                }
            }
        }
        return pointer
    }

    /// Whether a change here replaces a value where it stands: the whole
    /// document, or an object key linked to itself.
    func keepsPlace(associatedWith: Element?) -> Bool {
        guard let last else { return true }
        if case .key = last { return associatedWith == last }
        return false
    }
}
