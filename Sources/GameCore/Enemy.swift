import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    /// Base HP before depth scaling.
    public var baseHP: Int {
        switch self {
        case .easy: return 100
        case .medium: return 150
        case .hard: return 250
        }
    }

    /// Base damage the enemy deals per hit (before depth scaling and armour).
    public var baseDamageRange: ClosedRange<Int> {
        switch self {
        case .easy: return 2...25
        case .medium: return 25...50
        case .hard: return 50...90
        }
    }

    /// Base coins looted from the enemy (before depth scaling).
    public var baseCoinRange: ClosedRange<Int> {
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

/// A live enemy. HP, damage and coin ranges are baked in at creation time,
/// already scaled for depth (and boss status), so combat just rolls within them.
public struct Enemy: Equatable, Sendable {
    public let difficulty: Difficulty
    public let isBoss: Bool
    public let maxHP: Int
    public var hp: Int
    public let damageRange: ClosedRange<Int>
    public let coinRange: ClosedRange<Int>

    public var emoji: String { isBoss ? "👺" : difficulty.emoji }
    public var displayName: String { isBoss ? "BOSS" : difficulty.rawValue }

    /// Scales a range by a multiplier, rounding each bound and keeping it valid.
    static func scale(_ range: ClosedRange<Int>, by multiplier: Double) -> ClosedRange<Int> {
        let lo = Int((Double(range.lowerBound) * multiplier).rounded())
        let hi = Int((Double(range.upperBound) * multiplier).rounded())
        return lo...max(lo, hi)
    }

    /// Builds an enemy scaled for the given depth. Bosses use hard-tier stats,
    /// ×3 HP and ×1.25 damage, with the depth multipliers layered on top.
    public static func make(difficulty: Difficulty, depth: Int, isBoss: Bool) -> Enemy {
        let hpMultiplier = 1.0 + Double(depth) * Balance.Depth.hpPerDepth
        let damageMultiplier = 1.0 + Double(depth) * Balance.Depth.damagePerDepth
        let coinMultiplier = 1.0 + Double(depth) * Balance.Depth.coinPerDepth

        if isBoss {
            let baseHP = Difficulty.hard.baseHP * Balance.Depth.bossHPMultiplier
            let maxHP = Int((Double(baseHP) * hpMultiplier).rounded())
            let damage = scale(Difficulty.hard.baseDamageRange,
                               by: damageMultiplier * Balance.Depth.bossDamageMultiplier)
            let coins = scale(Balance.Depth.bossCoinRange, by: coinMultiplier)
            return Enemy(difficulty: .hard, isBoss: true, maxHP: maxHP, hp: maxHP,
                         damageRange: damage, coinRange: coins)
        }

        let maxHP = Int((Double(difficulty.baseHP) * hpMultiplier).rounded())
        let damage = scale(difficulty.baseDamageRange, by: damageMultiplier)
        let coins = scale(difficulty.baseCoinRange, by: coinMultiplier)
        return Enemy(difficulty: difficulty, isBoss: false, maxHP: maxHP, hp: maxHP,
                     damageRange: damage, coinRange: coins)
    }
}
