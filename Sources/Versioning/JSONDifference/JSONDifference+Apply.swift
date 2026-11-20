extension JSONRepresentation {
    /// This value with `difference` applied, or `nil` when the difference
    /// does not fit, as with `RangeReplaceableCollection.applying(_:)`.
    ///
    /// Each removal must find an equivalent element at its path, and each
    /// insertion must find its place free. A replaced object key keeps its
    /// position, and a newly inserted key is added at the end of its object.
    public func applying(_ difference: JSONDifference) -> JSONRepresentation? {
        var result: JSONRepresentation? = self
        for change in difference {
            guard result.apply(change) else { return nil }
        }
        return result
    }
}

private extension Optional<JSONRepresentation> {
    /// Applies one change, returning `false` when it does not fit. Removing
    /// the whole value leaves `nil` until an insertion of the whole value.
    mutating func apply(_ change: JSONDifference.Change) -> Bool {
        let (path, element, associatedWith) = change.parts
        switch change {
        case .remove where path.isEmpty:
            guard let value = self, value.isEquivalent(to: element) else { return false }
            self = nil
            return true
        case .insert where path.isEmpty:
            guard self == nil else { return false }
            self = element
            return true
        case .remove:
            return self?.withParent(of: path[...]) { $0.remove(element, at: $1, associatedWith: associatedWith) } ?? false
        case .insert:
            return self?.withParent(of: path[...]) { $0.insert(element, at: $1, associatedWith: associatedWith) } ?? false
        }
    }
}

private extension JSONRepresentation {
    /// Calls `body` with the container that holds the last segment of
    /// `path`, edited in place.
    mutating func withParent(of path: Path.SubSequence, _ body: (inout JSONRepresentation, Path.Segment) -> Bool) -> Bool {
        guard let segment = path.first else { return false }
        let rest = path.dropFirst()
        guard !rest.isEmpty else { return body(&self, segment) }
        switch (segment, self) {
        case (.key(let key), .object(var object)):
            guard let position = object.firstIndex(where: { $0.key == key }) else { return false }
            self = .null  // Releases the storage so the edit below does not copy it.
            defer { self = .object(object) }
            return object[position].value.withParent(of: rest, body)
        case (.index(let index), .array(var array)) where array.indices.contains(index):
            self = .null  // Releases the storage so the edit below does not copy it.
            defer { self = .array(array) }
            return array[index].withParent(of: rest, body)
        default:
            return false
        }
    }

    /// Removes `element` from this container at `segment`. An object key
    /// linked to itself is being replaced, so it stays for the insertion to
    /// overwrite in place.
    mutating func remove(_ element: JSONRepresentation, at segment: Path.Segment, associatedWith: Path.Segment?) -> Bool {
        switch (segment, self) {
        case (.key(let key), .object(var object)):
            guard let position = object.firstIndex(where: { $0.key == key }), object[position].value.isEquivalent(to: element) else { return false }
            guard associatedWith != segment else { return true }
            self = .null  // Releases the storage so the edit below does not copy it.
            object.remove(at: position)
            self = .object(object)
            return true
        case (.index(let index), .array(var array)):
            guard array.indices.contains(index), array[index].isEquivalent(to: element) else { return false }
            self = .null  // Releases the storage so the edit below does not copy it.
            array.remove(at: index)
            self = .array(array)
            return true
        default:
            return false
        }
    }

    /// Inserts `element` into this container at `segment`. An object key
    /// linked to itself replaces the value its removal kept in place.
    mutating func insert(_ element: JSONRepresentation, at segment: Path.Segment, associatedWith: Path.Segment?) -> Bool {
        switch (segment, self) {
        case (.key(let key), .object(var object)):
            let position = object.firstIndex { $0.key == key }
            self = .null  // Releases the storage so the edit below does not copy it.
            defer { self = .object(object) }
            switch (position, associatedWith == segment) {
            case (let position?, true): object[position].value = element
            case (nil, false): object.append((key: key, value: element))
            default: return false
            }
            return true
        case (.index(let index), .array(var array)):
            guard (0...array.count).contains(index) else { return false }
            self = .null  // Releases the storage so the edit below does not copy it.
            array.insert(element, at: index)
            self = .array(array)
            return true
        default:
            return false
        }
    }
}
