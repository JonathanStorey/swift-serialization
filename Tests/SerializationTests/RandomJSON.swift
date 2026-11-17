@testable import Serialization

/// A small seeded generator, so randomized tests repeat exactly.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension JSONRepresentation {
    static let randomKeys = ["a", "b", "c", "d", "0"]

    /// Small scalars repeat often, which exercises moves and pairing.
    static func random(depth: Int, using generator: inout SplitMix64) -> JSONRepresentation {
        switch Int.random(in: 0..<(depth > 0 ? 7 : 4), using: &generator) {
        case 0: return .null
        case 1: return .bool(Bool.random(using: &generator))
        case 2: return .number(String(Int.random(in: 0..<4, using: &generator)))
        case 3: return .string(["x", "y", "z"].randomElement(using: &generator)!)
        case 4, 5:
            let count = Int.random(in: 0..<5, using: &generator)
            return .array((0..<count).map { _ in random(depth: depth - 1, using: &generator) })
        default:
            let chosen = randomKeys.filter { _ in Bool.random(using: &generator) }.shuffled(using: &generator)
            return .object(chosen.map { (key: $0, value: random(depth: depth - 1, using: &generator)) })
        }
    }

    /// A few random edits somewhere in the value.
    func mutated(using generator: inout SplitMix64) -> JSONRepresentation {
        switch self {
        case .array(var elements):
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                switch Int.random(in: 0..<4, using: &generator) {
                case 0: elements.insert(.random(depth: 1, using: &generator), at: Int.random(in: 0...elements.count, using: &generator))
                case 1 where !elements.isEmpty: elements.remove(at: Int.random(in: 0..<elements.count, using: &generator))
                case 2 where !elements.isEmpty:
                    let index = Int.random(in: 0..<elements.count, using: &generator)
                    elements[index] = elements[index].mutated(using: &generator)
                case 3 where elements.count > 1: elements.swapAt(0, elements.count - 1)
                default: break
                }
            }
            return .array(elements)
        case .object(var pairs):
            if !pairs.isEmpty, Bool.random(using: &generator) {
                let index = Int.random(in: 0..<pairs.count, using: &generator)
                pairs[index].value = pairs[index].value.mutated(using: &generator)
            } else if let key = Self.randomKeys.first(where: { key in !pairs.contains { $0.key == key } }) {
                pairs.append((key: key, value: .random(depth: 1, using: &generator)))
            } else {
                pairs.removeFirst()
            }
            return .object(pairs)
        default:
            return .random(depth: 1, using: &generator)
        }
    }
}
