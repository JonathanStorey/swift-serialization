import Foundation

/// A file stored as a CloudKit asset, read as `Data` and located by its URL.
///
/// ```swift
/// struct Note: Codable {
///     @Asset var attachment: Data? = nil
/// }
///
/// note.attachment = bytes           // writes a temporary file
/// note.$attachment = fileURL        // points at a file you own
/// let pdf = PDFDocument(url: note.$attachment!)
/// ```
///
/// The file's URL is the stored value and the projected value. Reading the
/// wrapped value maps the file into memory, so the bytes are paged in only
/// as they are used, and a missing or unreadable file reads as `nil`.
/// Setting the wrapped value writes the bytes to a new file in the temporary
/// directory and points at it, and a failed write leaves the asset `nil`.
///
/// It encodes the URL, not the bytes, so encoding and decoding never touch
/// the disk. Equality compares URLs, so the same bytes in two files are not
/// equal. A `nil` asset is left out of a keyed container, and a missing key
/// decodes as `nil`.
@propertyWrapper
public struct Asset: Hashable, Sendable {
    /// The file holding the asset's bytes.
    public var projectedValue: URL?

    public init(wrappedValue: Data? = nil) {
        projectedValue = wrappedValue.flatMap { try? $0.writtenToTemporaryFile() }
    }

    public var wrappedValue: Data? {
        get { projectedValue.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) } }
        set { projectedValue = newValue.flatMap { try? $0.writtenToTemporaryFile() } }
    }
}

extension Asset: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        projectedValue = container.decodeNil() ? nil : try container.decode(URL.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let projectedValue {
            try container.encode(projectedValue)
        } else {
            try container.encodeNil()
        }
    }
}

extension Asset: RawRepresentable {
    /// The file holding the asset's bytes, the same as ``projectedValue``,
    /// so a plain `Asset` property works where a wrapper cannot, as in a
    /// SwiftData model.
    public var rawValue: URL? { projectedValue }

    public init(rawValue: URL?) {
        projectedValue = rawValue
    }
}

extension Asset: Mergeable {
    /// The side that changed the file. Two files with the same bytes are the
    /// same asset, so both sides saving the same bytes does not conflict,
    /// and two different files do.
    public func merging(with theirs: Asset, from base: Asset) throws(MergeConflict) -> Asset {
        if theirs.holdsSameBytes(as: base) || holdsSameBytes(as: theirs) { return self }
        if holdsSameBytes(as: base) { return theirs }
        throw MergeConflict()
    }

    /// This asset, when both hold the same bytes.
    public func merging(with theirs: Asset) throws(MergeConflict) -> Asset {
        guard holdsSameBytes(as: theirs) else { throw MergeConflict() }
        return self
    }
}

private extension Asset {
    /// Whether both point at the same file, or at files with the same bytes.
    func holdsSameBytes(as other: Asset) -> Bool {
        if projectedValue == other.projectedValue { return true }
        guard let bytes = wrappedValue else { return false }
        return bytes == other.wrappedValue
    }
}

// Synthesized `Codable` calls these instead of the generic methods, so a
// `nil` asset behaves like an optional property.
extension KeyedDecodingContainer {
    public func decode(_ type: Asset.Type, forKey key: Key) throws -> Asset {
        try decodeIfPresent(type, forKey: key) ?? Asset()
    }
}

extension KeyedEncodingContainer {
    public mutating func encode(_ value: Asset, forKey key: Key) throws {
        guard value.projectedValue != nil else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}

private extension Data {
    func writtenToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try write(to: url, options: .atomic)
        return url
    }
}
