/// Compact JSON text, for example `{"name":"Ada","tags":["swift"]}`.
///
/// Object keys are written in stored order. Strings escape `"`, `\` and
/// control characters. `/` is not escaped, matching `JSONEncoder` with
/// `.withoutEscapingSlashes`.
extension JSONRepresentation: CustomStringConvertible {
    public var description: String {
        var output = ""
        write(to: &output)
        return output
    }
}

private extension JSONRepresentation {
    func write(to output: inout String) {
        switch self {
        case .null:
            output += "null"
        case .bool(let value):
            output += value ? "true" : "false"
        case .number(let text):
            output += text
        case .string(let value):
            value.writeJSONString(to: &output)
        case .array(let elements):
            output += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { output += "," }
                element.write(to: &output)
            }
            output += "]"
        case .object(let object):
            output += "{"
            for (index, pair) in object.enumerated() {
                if index > 0 { output += "," }
                pair.key.writeJSONString(to: &output)
                output += ":"
                pair.value.write(to: &output)
            }
            output += "}"
        }
    }
}

private extension String {
    func writeJSONString(to output: inout String) {
        output += "\""
        for scalar in unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{8}": output += "\\b"
            case "\u{C}": output += "\\f"
            case "\u{0}"..."\u{1F}":
                let hex = String(scalar.value, radix: 16)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}
