import Foundation

/// Three armour slots, each holding at most one piece of a material tier
/// (Part 3 rework — one piece per slot, upgrade it, instead of stacking
/// duplicates). Damage reduction uses a diminishing-returns soft cap (see
/// `Balance.Armour`): each point of armour is worth less than the last, the
/// reduction asymptotically approaches an 85% ceiling it never reaches, and a
/// small flat component makes the first piece feel useful. The slot material
/// (not a raw int) is the source of truth; `rawArmour` derives from each
/// equipped tier's base value, so the curve maths is unchanged.
public struct Armour: Equatable, Sendable {
    public var head: ArmourMaterial?
    public var chest: ArmourMaterial?
    public var legs: ArmourMaterial?

    /// Per-slot remaining durability (Part 2). `nil` means "full" — either the
    /// slot is empty, or it was set before durability tracking (old save / a
    /// direct test assignment), in which case it reads as the tier's full pool.
    public var headDurability: Int?
    public var chestDurability: Int?
    public var legsDurability: Int?

    public init(head: ArmourMaterial? = nil, chest: ArmourMaterial? = nil, legs: ArmourMaterial? = nil,
                headDurability: Int? = nil, chestDurability: Int? = nil, legsDurability: Int? = nil) {
        self.head = head
        self.chest = chest
        self.legs = legs
        self.headDurability = headDurability
        self.chestDurability = chestDurability
        self.legsDurability = legsDurability
    }

    /// The material equipped in a slot (nil if empty).
    public func material(in slot: ArmourSlot) -> ArmourMaterial? {
        switch slot {
        case .head: return head
        case .chest: return chest
        case .legs: return legs
        }
    }

    /// Sets (or clears) a slot's material. Clearing also clears its durability.
    public mutating func setMaterial(_ material: ArmourMaterial?, in slot: ArmourSlot) {
        switch slot {
        case .head: head = material
        case .chest: chest = material
        case .legs: legs = material
        }
        if material == nil { setStoredDurability(nil, in: slot) }
    }

    // MARK: - Per-slot durability (Part 2)

    /// Full durability pool for the slot's current tier (nil if empty).
    public func maxDurability(in slot: ArmourSlot) -> Int? {
        guard let material = material(in: slot) else { return nil }
        return Balance.Armour.durability(material, slot: slot)
    }

    /// The raw stored value (nil = unset/"full" or empty).
    public func storedDurability(in slot: ArmourSlot) -> Int? {
        switch slot {
        case .head: return headDurability
        case .chest: return chestDurability
        case .legs: return legsDurability
        }
    }

    public mutating func setStoredDurability(_ value: Int?, in slot: ArmourSlot) {
        switch slot {
        case .head: headDurability = value
        case .chest: chestDurability = value
        case .legs: legsDurability = value
        }
    }

    /// Current durability for an occupied slot — the stored value, or the full
    /// pool when unset (old saves / direct assignment default to full). nil for
    /// an empty slot.
    public func currentDurability(in slot: ArmourSlot) -> Int? {
        guard let max = maxDurability(in: slot) else { return nil }
        return storedDurability(in: slot) ?? max
    }

    /// Sets a slot to full durability for its current tier (on equip/upgrade).
    public mutating func refillDurability(in slot: ArmourSlot) {
        setStoredDurability(maxDurability(in: slot), in: slot)
    }

    /// "(28/35)" for an occupied slot, nil if empty.
    public func durabilityText(in slot: ArmourSlot) -> String? {
        guard let cur = currentDurability(in: slot), let max = maxDurability(in: slot) else { return nil }
        return "\(cur)/\(max)"
    }

    /// True if the slot is occupied and below full durability.
    public func needsRepair(in slot: ArmourSlot) -> Bool {
        guard let cur = currentDurability(in: slot), let max = maxDurability(in: slot) else { return false }
        return cur < max
    }

    /// Base reduction value contributed by a slot's equipped tier (0 if empty).
    public func value(in slot: ArmourSlot) -> Int {
        guard let material = material(in: slot) else { return 0 }
        return Balance.Armour.baseValue(material, slot: slot)
    }

    /// Sum of the three slots' tier values (NOT averaged) — feeds the curve.
    public var rawArmour: Int {
        value(in: .head) + value(in: .chest) + value(in: .legs)
    }

    // MARK: - The diminishing-returns curve (pure function of rawArmour)

    public static func reductionFraction(forRaw raw: Int) -> Double {
        Balance.Armour.ceiling * (Double(raw) / (Double(raw) + Balance.Armour.scale))
    }

    public static func reductionPercent(forRaw raw: Int) -> Int {
        Int((reductionFraction(forRaw: raw) * 100).rounded())
    }

    /// The single damage-reduction function every hit routes through.
    /// Applies the flat component first, then the percentage, and clamps so a
    /// hit can never fall below 1, go negative, or heal the player.
    public static func reducedDamage(_ raw: Int, rawArmour: Int) -> Int {
        let afterFlat = max(0, raw - Balance.Armour.flat)
        let reduced = Double(afterFlat) * (1.0 - reductionFraction(forRaw: rawArmour))
        return max(1, Int(reduced.rounded()))
    }

    /// The diminishing-returns reduction fraction (0..<ceiling). Monotonic in
    /// `rawArmour`; approaches `Balance.Armour.ceiling` but never reaches it.
    public var reductionFraction: Double { Self.reductionFraction(forRaw: rawArmour) }

    /// Whole-percent reduction for display, e.g. "~28%".
    public var reductionPercent: Int { Self.reductionPercent(forRaw: rawArmour) }

    /// Every hit routes through here.
    public func reducedDamage(_ raw: Int) -> Int { Self.reducedDamage(raw, rawArmour: rawArmour) }

    // MARK: - Slot specialisation (Part 3c)

    /// Helmet poison-resist chance (0 if no head piece).
    public var poisonResistPercent: Int {
        guard let head else { return 0 }
        return Balance.Armour.poisonResistPercent[head] ?? 0
    }

    /// Fraction of flooded-room damage the boots negate (0…1). Iron/Steel = 1.
    public var floodReduction: Double {
        guard let legs else { return 0 }
        return Balance.Armour.floodReduction[legs] ?? 0
    }
    public var isFloodImmune: Bool { floodReduction >= 1.0 }
}

// MARK: - Codable + old-save migration (Part 3d)

extension Armour: Codable {
    enum CodingKeys: String, CodingKey {
        case head, chest, legs
        case headDurability, chestDurability, legsDurability
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        head = Self.decodeSlot(c, .head, slot: .head)
        chest = Self.decodeSlot(c, .chest, slot: .chest)
        legs = Self.decodeSlot(c, .legs, slot: .legs)
        // Durability is absent on pre-v5 saves; nil reads as full via
        // currentDurability(in:), so old equipped pieces load at full.
        headDurability = try c.decodeIfPresent(Int.self, forKey: .headDurability)
        chestDurability = try c.decodeIfPresent(Int.self, forKey: .chestDurability)
        legsDurability = try c.decodeIfPresent(Int.self, forKey: .legsDurability)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(head, forKey: .head)
        try c.encodeIfPresent(chest, forKey: .chest)
        try c.encodeIfPresent(legs, forKey: .legs)
        try c.encodeIfPresent(headDurability, forKey: .headDurability)
        try c.encodeIfPresent(chestDurability, forKey: .chestDurability)
        try c.encodeIfPresent(legsDurability, forKey: .legsDurability)
    }

    /// Decodes a slot from either the new material-tier format or an old
    /// (≤ v3) summed-integer save. For old saves, the integer is mapped to the
    /// nearest tier by base value (0 → empty slot).
    private static func decodeSlot(_ c: KeyedDecodingContainer<CodingKeys>,
                                   _ key: CodingKeys, slot: ArmourSlot) -> ArmourMaterial? {
        if let material = try? c.decode(ArmourMaterial.self, forKey: key) { return material }
        if let value = try? c.decode(Int.self, forKey: key), value > 0 {
            return Balance.Armour.nearestTier(forRaw: value, slot: slot)
        }
        return nil
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
