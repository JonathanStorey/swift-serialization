/// The changes that turn one ``JSONRepresentation`` into another, modeled on
/// `CollectionDifference`.
///
/// Create one with ``JSONRepresentation/difference(from:)`` and apply it with
/// ``JSONRepresentation/applying(_:)``. Changes are deep: a value that
/// differs inside an object or array that is otherwise unchanged is reported
/// at its own path, not as a change to the whole container.
///
/// Removal paths locate values in the original, and insertion paths locate
/// values in the result, as with `CollectionDifference` offsets. A removal
/// and an insertion can be linked through `associatedWith`, which names the
/// partner's last path segment within the same parent:
/// - When the two elements are equivalent, the pair is a move, such as an
///   array element that changed position or a key that was renamed.
/// - Otherwise the pair is a replacement, such as a string that changed or
///   a value that changed type.
///
/// Numbers are compared by value, so `1` and `1.0` are not a change.
public struct JSONDifference: Hashable, Sendable {
    public typealias ChangeElement = JSONRepresentation

    public enum Change: Hashable, Sendable {
        case insert(path: JSONRepresentation.Path, element: ChangeElement, associatedWith: JSONRepresentation.Path.Segment?)
        case remove(path: JSONRepresentation.Path, element: ChangeElement, associatedWith: JSONRepresentation.Path.Segment?)
    }

    /// The removals, in the order they apply: deepest and last first, so no
    /// removal shifts the index of another.
    public let removals: [Change]

    /// The insertions, in the order they apply: from the start of the result
    /// to its end.
    public let insertions: [Change]

    init(removals: [Change], insertions: [Change]) {
        self.removals = removals
        self.insertions = insertions
    }

    /// The difference that undoes this one, as `CollectionDifference.inverse()`
    /// does: removals become insertions and insertions become removals.
    public func inverted() -> JSONDifference {
        JSONDifference(removals: insertions.reversed().map(\.inverted), insertions: removals.reversed().map(\.inverted))
    }
}

// MARK: - Collection

extension JSONDifference: RandomAccessCollection {
    /// Removals come first, then insertions, so applying the changes in
    /// order produces the result.
    public var startIndex: Int { 0 }
    public var endIndex: Int { removals.count + insertions.count }

    public subscript(position: Int) -> Change {
        position < removals.count ? removals[position] : insertions[position - removals.count]
    }
}

// MARK: - Description

extension JSONDifference: CustomStringConvertible {
    /// One line per change, in document order:
    /// - `- $.path: value` for a removal
    /// - `+ $.path: value` for an insertion
    /// - `~ $.path: old → new` for a replacement, with both paths when they differ
    /// - `> $.from → $.to: value` for a move
    ///
    /// A linked pair is shown on one line when its partner is found by path.
    /// Inside an array element that itself moved, the two paths can differ
    /// above the partner segment, and the pair is shown as two lines.
    public var description: String {
        var lines: [String] = []
        var described: Set<Int> = []
        for removal in removals.reversed() {
            let (path, old, associated) = removal.parts
            if let match = partner(of: path, associatedWith: associated) {
                described.insert(match.index)
                let new = match.element
                let target = insertions[match.index].parts.path
                if old.isEquivalent(to: new) {
                    lines.append("> \(path) → \(target): \(old)")
                } else if path == target {
                    lines.append("~ \(path): \(old) → \(new)")
                } else {
                    lines.append("~ \(path) → \(target): \(old) → \(new)")
                }
            } else {
                lines.append("- \(path): \(old)")
            }
        }
        for (index, insertion) in insertions.enumerated() where !described.contains(index) {
            let (path, new, _) = insertion.parts
            lines.append("+ \(path): \(new)")
        }
        return lines.joined(separator: "\n")
    }

    /// The insertion linked to a removal at `path`, found by replacing the
    /// path's last segment with `associatedWith`. A removal of the whole
    /// value pairs with an insertion of the whole value.
    private func partner(of path: JSONRepresentation.Path, associatedWith: JSONRepresentation.Path.Segment?) -> (index: Int, element: ChangeElement)? {
        let target: JSONRepresentation.Path
        if let associatedWith {
            target = JSONRepresentation.Path(path.dropLast()) + [associatedWith]
        } else if path.isEmpty {
            target = path
        } else {
            return nil
        }
        guard let index = insertions.firstIndex(where: { $0.parts.path == target && $0.parts.associatedWith == path.last }) else { return nil }
        return (index, insertions[index].parts.element)
    }
}

extension JSONDifference.Change {
    var parts: (path: JSONRepresentation.Path, element: JSONRepresentation, associatedWith: JSONRepresentation.Path.Segment?) {
        switch self {
        case let .insert(path, element, associatedWith), let .remove(path, element, associatedWith):
            (path, element, associatedWith)
        }
    }

    var inverted: Self {
        switch self {
        case let .insert(path, element, associatedWith): .remove(path: path, element: element, associatedWith: associatedWith)
        case let .remove(path, element, associatedWith): .insert(path: path, element: element, associatedWith: associatedWith)
        }
    }
}
