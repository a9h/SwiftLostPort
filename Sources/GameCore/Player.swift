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

public struct Player: Codable, Equatable, Sendable {
    public var currentHealth: Int = 100
    public var maxHealth: Int = 100
    public var money: Int = 50
    public var hunger: Int = 100
    public var thirst: Int = 100
    public var armour: Armour = Armour()

    public init() {}
}
