extension JSONRepresentation {
    /// The changes that turn `other` into this value, as with
    /// `BidirectionalCollection.difference(from:)`.
    ///
    /// Objects are compared key by key. Arrays are aligned with the standard
    /// library's `difference(from:by:)`, then equivalent elements that were
    /// removed and inserted are linked as moves, and elements left over at
    /// the same place are compared in turn. Two objects or two arrays are
    /// compared inside, and any other pair is linked as a replacement.
    public func difference(from other: JSONRepresentation) -> JSONDifference {
        var recorder = DifferenceRecorder()
        recorder.compare(other, self, oldPath: [], newPath: [])
        return JSONDifference(removals: recorder.removals.reversed(), insertions: recorder.insertions)
    }

    /// The changes that turn `other` into this value as `type` reads them,
    /// leaving out what `JSONDecoder` cannot see.
    ///
    /// `type` is the reader of both values, usually the current version of a
    /// stored type. Keys it does not declare are ignored, and an optional
    /// property that is missing or `null` counts as unchanged. Every other
    /// rule matches ``difference(from:)``.
    ///
    /// Applying the result to `other` gives a value that `type` decodes the
    /// same as this one, though the two can differ in what `type` ignores.
    /// Throws the errors of ``JSONSchema/init(for:)``.
    public func difference<T: Decodable>(from other: JSONRepresentation, as type: T.Type) throws -> JSONDifference {
        var recorder = DifferenceRecorder()
        recorder.compare(other, self, oldPath: [], newPath: [], schema: try JSONSchema(for: type))
        return JSONDifference(removals: recorder.removals.reversed(), insertions: recorder.insertions)
    }
}

/// Collects changes in document order: removals by their place in the old
/// value and insertions by their place in the new one. Reversing the
/// removals gives an order in which none shifts the index of another.
private struct DifferenceRecorder {
    typealias Path = JSONRepresentation.Path
    var removals: [JSONDifference.Change] = []
    var insertions: [JSONDifference.Change] = []

    /// `schema` is the reader's view of this position, or `nil` to compare
    /// everything. A schema that does not fit the values is ignored.
    mutating func compare(_ old: JSONRepresentation, _ new: JSONRepresentation, oldPath: Path, newPath: Path, schema: JSONSchema? = nil) {
        var schema = schema?.flattened
        if case .optional(let wrapped)? = schema, old != .null, new != .null { schema = wrapped }
        switch (old, new, schema) {
        case let (.object(old), .object(new), .object(properties)?):
            compareDeclared(old, new, properties, oldPath: oldPath, newPath: newPath)
        case let (.object(old), .object(new), _):
            let values: JSONSchema? = if case .dictionary(let valueSchema)? = schema { valueSchema } else { nil }
            compareObjects(old, new, oldPath: oldPath, newPath: newPath, values: values)
        case let (.array(old), .array(new), _):
            let items: JSONSchema? = switch schema {
            case .array(let elementSchema)?, .set(let elementSchema)?: elementSchema
            default: nil
            }
            compareArrays(old, new, oldPath: oldPath, newPath: newPath, items: items)
        case _ where old.isEquivalent(to: new, under: schema):
            break
        default:
            recordReplacement(old, new, oldPath: oldPath, newPath: newPath)
        }
    }

    mutating func recordReplacement(_ old: JSONRepresentation, _ new: JSONRepresentation, oldPath: Path, newPath: Path) {
        removals.append(.remove(path: oldPath, element: old, associatedWith: newPath.last))
        insertions.append(.insert(path: newPath, element: new, associatedWith: oldPath.last))
    }

    /// Compares only the keys `properties` declares. An optional property
    /// that is missing or `null` on both sides is unchanged. Otherwise a
    /// missing key is a removal or insertion, and a `null` that stands for a
    /// missing value is replaced, so the difference still inverts.
    mutating func compareDeclared(_ old: JSONRepresentation.Object, _ new: JSONRepresentation.Object, _ properties: JSONSchema.Properties, oldPath: Path, newPath: Path) {
        for (key, schema) in properties {
            let oldValue = old.first { $0.key == key }?.value
            let newValue = new.first { $0.key == key }?.value
            let oldIsNil = oldValue == nil || (schema.isOptional && oldValue == .null)
            let newIsNil = newValue == nil || (schema.isOptional && newValue == .null)
            let oldKeyPath = oldPath + [.key(key)]
            let newKeyPath = newPath + [.key(key)]
            switch (oldValue, newValue) {
            case _ where oldIsNil && newIsNil:
                break
            case let (oldValue?, newValue?) where !oldIsNil && !newIsNil:
                compare(oldValue, newValue, oldPath: oldKeyPath, newPath: newKeyPath, schema: schema)
            case let (oldValue?, newValue?):
                recordReplacement(oldValue, newValue, oldPath: oldKeyPath, newPath: newKeyPath)
            case let (oldValue?, nil):
                removals.append(.remove(path: oldKeyPath, element: oldValue, associatedWith: nil))
            case let (nil, newValue?):
                insertions.append(.insert(path: newKeyPath, element: newValue, associatedWith: nil))
            case (nil, nil):
                break
            }
        }
    }

    /// Keys in both are compared inside. A removed key and an added key with
    /// equivalent values are linked as a rename. A repeated key in a
    /// hand-built object is read as its first occurrence. `values` is the
    /// schema of a dictionary's values, or `nil` to compare everything.
    mutating func compareObjects(_ old: JSONRepresentation.Object, _ new: JSONRepresentation.Object, oldPath: Path, newPath: Path, values: JSONSchema? = nil) {
        let oldValues = Dictionary(old.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let newValues = Dictionary(new.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let removed = Self.uniqueKeys(of: old).filter { newValues[$0] == nil }
        let added = Self.uniqueKeys(of: new).filter { oldValues[$0] == nil }

        var renamedTo: [String: String] = [:]
        var renamedFrom: [String: String] = [:]
        for key in removed {
            if let match = added.first(where: { renamedFrom[$0] == nil && oldValues[key]!.isEquivalent(to: newValues[$0]!) }) {
                renamedTo[key] = match
                renamedFrom[match] = key
            }
        }

        for key in Self.uniqueKeys(of: old) {
            if let newValue = newValues[key] {
                compare(oldValues[key]!, newValue, oldPath: oldPath + [.key(key)], newPath: newPath + [.key(key)], schema: values)
            } else {
                removals.append(.remove(path: oldPath + [.key(key)], element: oldValues[key]!, associatedWith: renamedTo[key].map { .key($0) }))
            }
        }
        for key in added {
            insertions.append(.insert(path: newPath + [.key(key)], element: newValues[key]!, associatedWith: renamedFrom[key].map { .key($0) }))
        }
    }

    /// Aligns the arrays, then walks each run of removed and inserted
    /// elements between unchanged ones. Equivalent elements removed in one
    /// place and inserted in another are linked as moves. The rest of a run
    /// is paired in order and compared, and any extra elements are plain
    /// removals or insertions.
    mutating func compareArrays(_ old: [JSONRepresentation], _ new: [JSONRepresentation], oldPath: Path, newPath: Path, items: JSONSchema?) {
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in new.difference(from: old, by: { $0.isEquivalent(to: $1, under: items) }) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var movedTo: [Int: Int] = [:]
        var movedFrom: [Int: Int] = [:]
        let insertedInOrder = inserted.sorted()
        for oldIndex in removed.sorted() {
            if let newIndex = insertedInOrder.first(where: { movedFrom[$0] == nil && old[oldIndex].isEquivalent(to: new[$0], under: items) }) {
                movedTo[oldIndex] = newIndex
                movedFrom[newIndex] = oldIndex
            }
        }

        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            var oldRun: [Int] = []
            var newRun: [Int] = []
            while oldIndex < old.count, removed.contains(oldIndex) { oldRun.append(oldIndex); oldIndex += 1 }
            while newIndex < new.count, inserted.contains(newIndex) { newRun.append(newIndex); newIndex += 1 }
            recordRun(oldRun, newRun, old, new, movedTo: movedTo, movedFrom: movedFrom, oldPath: oldPath, newPath: newPath, items: items)
            guard oldIndex < old.count, newIndex < new.count else { break }
            oldIndex += 1  // An element present in both, unchanged.
            newIndex += 1
        }
    }

    /// The keys in order, without repeats.
    private static func uniqueKeys(of object: JSONRepresentation.Object) -> [String] {
        var seen: Set<String> = []
        return object.compactMap { seen.insert($0.key).inserted ? $0.key : nil }
    }

    /// Records one run in document order on both sides. Insertions before a
    /// paired element are written before the pair is compared, so the
    /// insertions stay in order too.
    private mutating func recordRun(
        _ oldRun: [Int], _ newRun: [Int], _ old: [JSONRepresentation], _ new: [JSONRepresentation],
        movedTo: [Int: Int], movedFrom: [Int: Int], oldPath: Path, newPath: Path, items: JSONSchema?
    ) {
        let unmovedNew = newRun.filter { movedFrom[$0] == nil }
        var pairedNew: Set<Int> = []
        var pairCount = 0
        var insertionCursor = newRun.startIndex

        func insertion(_ index: Int) -> JSONDifference.Change {
            .insert(path: newPath + [.index(index)], element: new[index], associatedWith: movedFrom[index].map { .index($0) })
        }

        for index in oldRun {
            if let target = movedTo[index] {
                removals.append(.remove(path: oldPath + [.index(index)], element: old[index], associatedWith: .index(target)))
            } else if pairCount < unmovedNew.count {
                let partner = unmovedNew[pairCount]
                pairCount += 1
                pairedNew.insert(partner)
                while insertionCursor < newRun.endIndex, newRun[insertionCursor] < partner {
                    insertions.append(insertion(newRun[insertionCursor]))
                    insertionCursor += 1
                }
                insertionCursor += 1  // The partner, recorded by the comparison below.
                compare(old[index], new[partner], oldPath: oldPath + [.index(index)], newPath: newPath + [.index(partner)], schema: items)
            } else {
                removals.append(.remove(path: oldPath + [.index(index)], element: old[index], associatedWith: nil))
            }
        }
        for index in newRun[insertionCursor...] where !pairedNew.contains(index) {
            insertions.append(insertion(index))
        }
    }
}
