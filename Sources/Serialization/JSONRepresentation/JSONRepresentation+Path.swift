extension JSONRepresentation {
    /// The location of a value inside a ``JSONRepresentation``, from the root.
    ///
    /// A path is a collection of segments and can be written as an array
    /// literal, such as `["rooms", 0, "name"]`. Its `description` is a JSONPath
    /// expression (RFC 9535), such as `$.rooms[0].name`, and `init(_:)` reads
    /// that text back.
    public struct Path: Hashable, Sendable {
        private var segments: [Segment]
    }
}

extension JSONRepresentation.Path {
    /// One step in a path, an object key or an array index. RFC 9535 calls
    /// each `.name` or `[0]` in a JSONPath a segment.
    ///
    /// As a `CodingKey`, an index's `stringValue` is `"Index n"`, as in
    /// Foundation's coding paths, so a path can serve as a `codingPath`.
    public enum Segment: Hashable, Sendable, CodingKey, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
        case key(String)
        case index(Int)

        public var stringValue: String {
            switch self {
            case .key(let key): key
            case .index(let index): "Index \(index)"
            }
        }

        public var intValue: Int? {
            if case .index(let index) = self { index } else { nil }
        }

        public init(stringValue: String) { self = .key(stringValue) }
        public init(intValue: Int) { self = .index(intValue) }
        public init(stringLiteral value: String) { self = .key(value) }
        public init(integerLiteral value: Int) { self = .index(value) }
    }
}

// MARK: - Collection

extension JSONRepresentation.Path: RandomAccessCollection, RangeReplaceableCollection, ExpressibleByArrayLiteral {
    public init() { segments = [] }
    public init(arrayLiteral elements: Segment...) { segments = elements }

    public var startIndex: Int { segments.startIndex }
    public var endIndex: Int { segments.endIndex }
    public subscript(position: Int) -> Segment { segments[position] }

    public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C) where C.Element == Segment {
        segments.replaceSubrange(subrange, with: newElements)
    }
}

// MARK: - Text

extension JSONRepresentation.Path: LosslessStringConvertible {
    /// The path as a JSONPath expression: `$` for the root, `.name` for a key
    /// made of ASCII letters, digits and underscores that does not start
    /// with a digit, `['any key']` for any other key, and `[0]` for an index.
    public var description: String {
        var text = "$"
        for segment in segments {
            switch segment {
            case .index(let index):
                text += "[\(index)]"
            case .key(let key) where key.isJSONPathShorthand:
                text += "." + key
            case .key(let key):
                text += "['"
                key.writeJSONPathEscaped(to: &text)
                text += "']"
            }
        }
        return text
    }

    /// Reads the JSONPath expressions that `description` writes, with keys
    /// in either the `.name` or `['name']` form. Returns `nil` for any other
    /// text, including an index with a leading zero or a plus sign.
    public init?(_ description: String) {
        var scalars = Substring(description).unicodeScalars
        guard scalars.popFirst() == "$" else { return nil }
        var segments: [Segment] = []
        while !scalars.isEmpty {
            guard let segment = scalars.popJSONPathSegment() else { return nil }
            segments.append(segment)
        }
        self.segments = segments
    }
}

// MARK: - Lookup

extension JSONRepresentation {
    /// The value at `path`.
    ///
    /// Reading returns `nil` when a key is missing, an index is out of bounds,
    /// or a segment does not match the value's type. An empty path returns
    /// the value itself.
    ///
    /// Writing follows `Dictionary` and optional chaining:
    /// - A value replaces the one at `path`, and a missing final key is added
    ///   at the end of its object.
    /// - `nil` removes the final key. Assign `.null` to store a JSON null.
    /// - When the rest of the path does not exist, nothing changes.
    /// - An index only replaces an element in bounds. Inserting and removing
    ///   elements shifts later indices, so `nil` never removes one.
    /// - `nil` at the empty path changes nothing.
    ///
    /// A hand-built object with a repeated key reads and writes the first.
    public subscript(path: Path) -> JSONRepresentation? {
        get {
            var value: JSONRepresentation? = self
            for segment in path {
                value = switch segment {
                case .key(let key): value?[key]
                case .index(let index): value?[index]
                }
            }
            return value
        }
        set {
            assign(newValue, at: path[...])
        }
    }
}

private extension JSONRepresentation {
    mutating func assign(_ newValue: JSONRepresentation?, at path: Path.SubSequence) {
        guard let segment = path.first else {
            if let newValue { self = newValue }
            return
        }
        let rest = path.dropFirst()
        switch (segment, self) {
        case (.key(let key), .object(var object)):
            self = .null  // Releases the storage so the edit below does not copy it.
            defer { self = .object(object) }
            let position = object.firstIndex { $0.key == key }
            switch (position, newValue, rest.isEmpty) {
            case (let position?, _, false): object[position].value.assign(newValue, at: rest)
            case (let position?, let newValue?, true): object[position].value = newValue
            case (let position?, nil, true): object.remove(at: position)
            case (nil, let newValue?, true): object.append((key: key, value: newValue))
            case (nil, _, _): break
            }
        case (.index(let index), .array(var array)) where array.indices.contains(index):
            self = .null  // Releases the storage so the edit below does not copy it.
            defer { self = .array(array) }
            if !rest.isEmpty {
                array[index].assign(newValue, at: rest)
            } else if let newValue {
                array[index] = newValue
            }
        default:
            break
        }
    }
}

// MARK: - Helpers

private extension String {
    var isJSONPathShorthand: Bool {
        guard let first = unicodeScalars.first, !first.isASCIIDigit else { return false }
        return unicodeScalars.allSatisfy { $0.isASCIILetter || $0.isASCIIDigit || $0 == "_" }
    }

    /// Escapes as RFC 9535 normalized paths do: the quote, the backslash and
    /// control characters.
    func writeJSONPathEscaped(to text: inout String) {
        for scalar in unicodeScalars {
            switch scalar {
            case "'": text += "\\'"
            case "\\": text += "\\\\"
            case "\u{8}": text += "\\b"
            case "\u{C}": text += "\\f"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case _ where scalar.value < 0x20:
                text += scalar.value < 0x10 ? "\\u000" : "\\u00"
                text += String(scalar.value, radix: 16)
            default: text.unicodeScalars.append(scalar)
            }
        }
    }
}

private extension Unicode.Scalar {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
    var isASCIILetter: Bool { ("a"..."z").contains(self) || ("A"..."Z").contains(self) }
    var isASCIIHexDigit: Bool { isASCIIDigit || ("a"..."f").contains(self) || ("A"..."F").contains(self) }
}

private extension Substring.UnicodeScalarView {
    mutating func popJSONPathSegment() -> JSONRepresentation.Path.Segment? {
        guard let scalar = popFirst() else { return nil }
        switch scalar {
        case ".":
            let name = prefix { $0.isASCIILetter || $0.isASCIIDigit || $0 == "_" }
            guard let first = name.first, !first.isASCIIDigit else { return nil }
            removeFirst(name.count)
            return .key(String(Substring(name)))
        case "[":
            let segment = first == "'" ? popQuotedKey() : popIndex()
            guard let segment, popFirst() == "]" else { return nil }
            return segment
        default:
            return nil
        }
    }

    /// An integer with no leading zeros or plus sign, so each index has one
    /// spelling.
    mutating func popIndex() -> JSONRepresentation.Path.Segment? {
        let digits = prefix { $0 == "-" || $0.isASCIIDigit }
        let text = String(Substring(digits))
        guard let index = Int(text), String(index) == text else { return nil }
        removeFirst(digits.count)
        return .index(index)
    }

    mutating func popQuotedKey() -> JSONRepresentation.Path.Segment? {
        _ = popFirst()
        var key = String.UnicodeScalarView()
        while let scalar = popFirst() {
            switch scalar {
            case "'": return .key(String(key))
            case "\\":
                guard let escaped = popEscape() else { return nil }
                key.append(escaped)
            case _ where scalar.value < 0x20: return nil
            default: key.append(scalar)
            }
        }
        return nil
    }

    mutating func popEscape() -> Unicode.Scalar? {
        guard let scalar = popFirst() else { return nil }
        return switch scalar {
        case "b": "\u{8}"
        case "f": "\u{C}"
        case "n": "\n"
        case "r": "\r"
        case "t": "\t"
        case "/": "/"
        case "\\": "\\"
        case "'": "'"
        case "u": popUnicodeEscape()
        default: nil
        }
    }

    /// The scalar after `\u`, joining a surrogate pair written as two escapes.
    mutating func popUnicodeEscape() -> Unicode.Scalar? {
        guard let unit = popHexUnit() else { return nil }
        switch unit {
        case 0xD800...0xDBFF:
            guard popFirst() == "\\", popFirst() == "u", let low = popHexUnit(), (0xDC00...0xDFFF).contains(low) else { return nil }
            return Unicode.Scalar(0x10000 + (unit - 0xD800) << 10 + (low - 0xDC00))
        default:
            return Unicode.Scalar(unit)
        }
    }

    mutating func popHexUnit() -> UInt32? {
        let hex = prefix(4)
        guard hex.count == 4, hex.allSatisfy(\.isASCIIHexDigit) else { return nil }
        removeFirst(4)
        return UInt32(String(Substring(hex)), radix: 16)
    }
}
