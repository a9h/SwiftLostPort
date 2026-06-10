import Foundation

/// Three armour slots. Damage reduction uses a diminishing-returns soft cap
/// (see `Balance.Armour`): each point of armour is worth less than the last,
/// the reduction asymptotically approaches an 85% ceiling it never reaches,
/// and a small flat component makes the first piece feel useful.
public struct Armour: Codable, Equatable, Sendable {
    public var head: Int = 0
    public var chest: Int = 0
    public var legs: Int = 0

    public init(head: Int = 0, chest: Int = 0, legs: Int = 0) {
        self.head = head
        self.chest = chest
        self.legs = legs
    }

    /// Sum of the three slots (NOT averaged) — feeds the reduction curve.
    public var rawArmour: Int { head + chest + legs }

    /// The diminishing-returns reduction fraction (0..<ceiling). Monotonic in
    /// `rawArmour`; approaches `Balance.Armour.ceiling` but never reaches it.
    public var reductionFraction: Double {
        Balance.Armour.ceiling * (Double(rawArmour) / (Double(rawArmour) + Balance.Armour.scale))
    }

    /// Whole-percent reduction for display, e.g. "~28%".
    public var reductionPercent: Int {
        Int((reductionFraction * 100).rounded())
    }

    /// The single damage-reduction function every hit routes through.
    /// Applies the flat component first, then the percentage, and clamps so a
    /// hit can never fall below 1, go negative, or heal the player.
    public func reducedDamage(_ raw: Int) -> Int {
        let afterFlat = max(0, raw - Balance.Armour.flat)
        let reduced = Double(afterFlat) * (1.0 - reductionFraction)
        return max(1, Int(reduced.rounded()))
    }
}

/// A lightweight, extensible status-effect system. Only poison ships now,
/// but the shape (kind + remaining duration) leaves room for more.
public enum StatusEffectKind: String, Codable, Sendable {
    case poison
}

public struct StatusEffect: Codable, Equatable, Identifiable, Sendable {
    public var id: StatusEffectKind { kind }
    public var kind: StatusEffectKind
    /// Rooms of effect remaining.
    public var remaining: Int

    public init(kind: StatusEffectKind, remaining: Int) {
        self.kind = kind
        self.remaining = remaining
    }
}

public struct Player: Codable, Equatable, Sendable {
    public var currentHealth: Int = 100
    public var maxHealth: Int = 100
    public var money: Int = 50
    public var hunger: Int = 100
    public var thirst: Int = 100
    public var armour: Armour = Armour()
    public var statusEffects: [StatusEffect] = []

    public init() {}

    public var poisonRemaining: Int {
        statusEffects.first { $0.kind == .poison }?.remaining ?? 0
    }
    public var isPoisoned: Bool { poisonRemaining > 0 }

    // Custom Codable so a v1 save (no statusEffects key) decodes cleanly.
    enum CodingKeys: String, CodingKey {
        case currentHealth, maxHealth, money, hunger, thirst, armour, statusEffects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentHealth = try c.decode(Int.self, forKey: .currentHealth)
        maxHealth = try c.decode(Int.self, forKey: .maxHealth)
        money = try c.decode(Int.self, forKey: .money)
        hunger = try c.decode(Int.self, forKey: .hunger)
        thirst = try c.decode(Int.self, forKey: .thirst)
        armour = try c.decode(Armour.self, forKey: .armour)
        statusEffects = try c.decodeIfPresent([StatusEffect].self, forKey: .statusEffects) ?? []
    }
}
