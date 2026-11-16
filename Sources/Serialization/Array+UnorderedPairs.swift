// Equality and hashing for key-value lists that ignore order, the way
// `Dictionary` compares and hashes. Used by object values and schema
// properties, which are stored in order but compared without it.
extension Array {
    /// Whether both lists hold the same key-value pairs in any order. Pairs
    /// that share a key are compared in their relative order.
    func hasSamePairs<Value: Equatable>(as other: Self) -> Bool where Element == (key: String, value: Value) {
        guard count == other.count else { return false }
        let byKey: (Element, Element) -> Bool = { $0.key < $1.key }
        return sorted(by: byKey).elementsEqual(other.sorted(by: byKey)) { $0.key == $1.key && $0.value == $1.value }
    }

    /// Feeds an order-independent hash of the pairs into `hasher`. Each pair
    /// is hashed on its own and the results are summed, so any order of the
    /// same pairs produces the same hash.
    func hashPairsIgnoringOrder<Value: Hashable>(into hasher: inout Hasher) where Element == (key: String, value: Value) {
        var sum = 0
        for (key, value) in self {
            var pairHasher = Hasher()
            pairHasher.combine(key)
            pairHasher.combine(value)
            sum &+= pairHasher.finalize()
        }
        hasher.combine(count)
        hasher.combine(sum)
    }
}
