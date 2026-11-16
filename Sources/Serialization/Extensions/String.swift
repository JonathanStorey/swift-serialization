extension String {
    /// Whether the text matches the JSON number grammar (RFC 8259):
    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`
    var isJSONNumber: Bool {
        var bytes = utf8[...]

        func skipDigits() -> Int {
            let count = bytes.prefix { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }.count
            bytes = bytes.dropFirst(count)
            return count
        }

        if bytes.first == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        if bytes.first == UInt8(ascii: "0") {
            bytes = bytes.dropFirst()
        } else if skipDigits() == 0 {
            return false
        }
        if bytes.first == UInt8(ascii: ".") {
            bytes = bytes.dropFirst()
            guard skipDigits() > 0 else { return false }
        }
        if bytes.first == UInt8(ascii: "e") || bytes.first == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if bytes.first == UInt8(ascii: "+") || bytes.first == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
            guard skipDigits() > 0 else { return false }
        }
        return bytes.isEmpty
    }
}
