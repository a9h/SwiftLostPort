import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    /// Damage the enemy deals per hit (before armour). See `Balance.EnemyCombat`.
    public var baseDamageRange: ClosedRange<Int> {
        Balance.EnemyCombat.damage(for: self)
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

/// A live enemy. HP, damage and coin ranges are baked in at creation time so
/// combat just rolls within them. Bosses carry a `boss` kind plus the runtime
/// state for their specials (Plague Doctor's one-time heal).
public struct Enemy: Equatable, Sendable {
    public let difficulty: Difficulty
    public let boss: BossKind?
    public let maxHP: Int
    public var hp: Int
    public let damageRange: ClosedRange<Int>
    public let coinRange: ClosedRange<Int>
    /// True once the Plague Doctor has used its one-time self-heal.
    public var hasHealed = false

    public var isBoss: Bool { boss != nil }
    public var emoji: String { boss?.emoji ?? difficulty.emoji }
    public var displayName: String { boss?.displayName ?? difficulty.rawValue }

    /// Scales a range by a multiplier, rounding each bound and keeping it valid.
    static func scale(_ range: ClosedRange<Int>, by multiplier: Double) -> ClosedRange<Int> {
        let lo = Int((Double(range.lowerBound) * multiplier).rounded())
        let hi = Int((Double(range.upperBound) * multiplier).rounded())
        return lo...max(lo, hi)
    }

    /// Builds a normal enemy. HP is a depth-weighted roll (2c: low end early,
    /// high end late, plus jitter); damage uses the flat new ranges (2b); coins
    /// still ramp gently with depth so deep fights pay more.
    /// (Bosses are built separately — see the Boss system in Part 3.)
    public static func make(difficulty: Difficulty, depth: Int, isBoss: Bool,
                            using rng: inout GameRandom) -> Enemy {
        let jitter = rng.int(in: 0...Balance.EnemyCombat.hpJitter)
        let hp = Balance.EnemyCombat.rolledHP(for: difficulty, depth: depth, jitterRoll: jitter)
        let damage = difficulty.baseDamageRange
        let coinMultiplier = 1.0 + Double(Balance.Depth.effectiveDepth(depth)) * Balance.Depth.coinRampPerRoom
        let coins = scale(difficulty.baseCoinRange, by: coinMultiplier)
        return Enemy(difficulty: difficulty, boss: nil, maxHP: hp, hp: hp,
                     damageRange: damage, coinRange: coins)
    }

    /// Builds a boss from its fixed stat block (Part 3). When `maxDamage` is
    /// active (post-cycle), the damage range collapses to its top value so every
    /// hit deals maximum.
    public static func makeBoss(_ kind: BossKind, maxDamage: Bool) -> Enemy {
        let s = kind.stats
        let damage = maxDamage ? (s.damage.upperBound...s.damage.upperBound) : s.damage
        return Enemy(difficulty: .hard, boss: kind, maxHP: s.hp, hp: s.hp,
                     damageRange: damage, coinRange: s.coins)
    }
}
