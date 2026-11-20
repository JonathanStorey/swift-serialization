/// Merges text word by word, so edits to different words combine and
/// edits to the same word conflict. Needs a base.
public struct StringWordMerge<Value: StringProtocol & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        let merged = try ours.words.mergingElements(with: theirs.words, from: base.words)
        return Value(decoding: merged.joined().utf8, as: UTF8.self)
    }
}

extension StringProtocol {
    /// The text as words, each a run of letters, digits and apostrophes with
    /// the spaces and punctuation after it, so joining them gives back the
    /// text. Anything before the first word is one of its own. The rule is
    /// simple and the same everywhere, since both sides of a merge must cut
    /// text alike.
    var words: [String] {
        var words: [String] = []
        var word = ""
        var inSeparator = false
        for character in self {
            let isWord = character.isLetter || character.isNumber || character == "'" || character == "’"
            if isWord, inSeparator, !word.isEmpty {
                words.append(word)
                word = ""
            }
            inSeparator = !isWord
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words
    }
}
