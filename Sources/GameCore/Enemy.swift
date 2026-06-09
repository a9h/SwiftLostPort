import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    public var maxHP: Int {
        switch self {
        case .easy: return 100
        case .medium: return 150
        case .hard: return 250
        }
    }

    /// Damage the enemy deals per hit (before armour reduction).
    public var damageRange: ClosedRange<Int> {
        switch self {
        case .easy: return 2...25
        case .medium: return 25...50
        case .hard: return 50...90
        }
    }

    /// Coins looted from the enemy's corpse.
    public var coinRange: ClosedRange<Int> {
        switch self {
        case .easy: return 10...30
        case .medium: return 30...75
        case .hard: return 100...150
        }
    }

    public var emoji: String {
        switch self {
        case .easy: return "🧟"
        case .medium: return "👹"
        case .hard: return "🐉"
        }
    }

    /// Rolled once when the enemy is first seen:
    /// randint(1,200) -> <25 hard, 25–125 medium, >125 easy.
    public static func roll(using rng: inout GameRandom) -> Difficulty {
        let chance = rng.int(in: 1...200)
        if chance < 25 { return .hard }
        if chance <= 125 { return .medium }
        return .easy
    }
}

public struct Enemy: Equatable, Sendable {
    public let difficulty: Difficulty
    public var hp: Int

    public init(difficulty: Difficulty) {
        self.difficulty = difficulty
        self.hp = difficulty.maxHP
    }
}
