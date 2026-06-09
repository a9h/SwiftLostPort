import Foundation

/// Injectable randomness so GameCore is fully unit-testable.
/// `int(in:)` matches Python's `randint(a, b)` — both bounds inclusive.
public protocol GameRandom {
    mutating func int(in range: ClosedRange<Int>) -> Int
}

public extension GameRandom {
    /// Matches Python's `random.choice(list)`.
    mutating func choice<T>(_ array: [T]) -> T {
        precondition(!array.isEmpty, "choice from empty array")
        return array[int(in: 0...(array.count - 1))]
    }
}

/// Production randomness.
public struct SystemGameRandom: GameRandom {
    private var generator = SystemRandomNumberGenerator()
    public init() {}
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &generator)
    }
}

/// Deterministic seeded randomness (SplitMix64), for reproducible runs.
public struct SeededGameRandom: GameRandom {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed }

    private mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) &+ 1
        return range.lowerBound + Int(nextUInt64() % span)
    }
}

/// Test-only randomness: returns the queued values in order, clamped into
/// the requested range so a mis-scripted value can never crash the game.
public struct ScriptedGameRandom: GameRandom {
    public private(set) var values: [Int]
    public init(_ values: [Int]) { self.values = values }
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let value = values.isEmpty ? range.lowerBound : values.removeFirst()
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
