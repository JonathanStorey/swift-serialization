/// Merges text word by word, so edits to different words combine and
/// edits to the same word conflict, unless `favoring` names a side.
///
/// ```swift
/// try StringWordMerge(favoring: .ours).merge(base: base, ours: mine, theirs: yours)
/// ```
public struct StringWordMerge<Value: StringProtocol & Sendable>: MergeStrategy {
    /// The side kept wherever the merge conflicts, or `nil` to throw.
    public var favoring: KeepMerge<Value>?

    public init(favoring: KeepMerge<Value>? = nil) {
        self.favoring = favoring
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            let merged = try ours.words.mergingElements(with: theirs.words, from: base.words)
            return Value(decoding: merged.joined().utf8, as: UTF8.self)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict) -> Value {
        try favoring.resolving(ours: ours, theirs: theirs) { () throws(MergeConflict) in
            guard ours == theirs else { throw MergeConflict() }
            return ours
        }
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
