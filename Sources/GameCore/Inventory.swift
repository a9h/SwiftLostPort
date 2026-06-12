import Foundation

/// One physical weapon the player owns, tracked individually so two of the
/// same type wear out independently (B2). `durability == nil` means the
/// weapon is not durability-tracked (the torch, which is consumed by its
/// scare mechanic instead).
public struct WeaponInstance: Codable, Equatable, Identifiable, Sendable {
    public var instanceID: UUID
    public let id: String
    public var durability: Int?
    public let maxDurability: Int?
    /// Damage-upgrade level (Part 5b): each level adds a flat bonus to every
    /// value in this instance's damage array.
    public var upgradeLevel: Int

    /// Fresh instance at full durability for its type.
    public init(id: String, instanceID: UUID = UUID()) {
        self.instanceID = instanceID
        self.id = id
        self.upgradeLevel = 0
        if let maxD = Balance.Durability.maxByWeapon[id] {
            self.durability = maxD
            self.maxDurability = maxD
        } else {
            self.durability = nil
            self.maxDurability = nil
        }
    }

    /// Instance with explicit durability (used by upgrades / hardened blades).
    public init(id: String, durability: Int?, maxDurability: Int?, upgradeLevel: Int = 0, instanceID: UUID = UUID()) {
        self.instanceID = instanceID
        self.id = id
        self.durability = durability
        self.maxDurability = maxDurability
        self.upgradeLevel = upgradeLevel
    }

    // Custom decode so older saves (no upgradeLevel key) default to 0.
    enum CodingKeys: String, CodingKey {
        case instanceID, id, durability, maxDurability, upgradeLevel
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instanceID = try c.decode(UUID.self, forKey: .instanceID)
        id = try c.decode(String.self, forKey: .id)
        durability = try c.decodeIfPresent(Int.self, forKey: .durability)
        maxDurability = try c.decodeIfPresent(Int.self, forKey: .maxDurability)
        upgradeLevel = try c.decodeIfPresent(Int.self, forKey: .upgradeLevel) ?? 0
    }

    /// Total flat damage bonus from upgrades.
    public var damageBonus: Int { upgradeLevel * Balance.Grindstone.upgradeDamageBonus }

    /// 0...1 fraction remaining (1 if untracked). Drives worn-weapon sell pricing.
    public var durabilityFraction: Double {
        guard let durability, let maxDurability, maxDurability > 0 else { return 1 }
        return Double(durability) / Double(maxDurability)
    }
}

/// Quantity-based inventory for stackable items, with weapons promoted to
/// per-instance tracking so durability is independent (B2). The public API
/// (`count(of:)`, `add`, `remove`, `items(in:)`) is unchanged for callers —
/// weapon ids are simply routed to the instance store internally.
public struct Inventory: Codable, Equatable, Sendable {
    /// Non-weapon stackables.
    public private(set) var counts: [String: Int] = [:]
    /// Per-instance weapons.
    public private(set) var weapons: [WeaponInstance] = []

    public init() {}

    /// Builds from a plain count map. Weapon ids become full-durability
    /// instances — this is also how a v1 save (weapons stored as counts) loads.
    public init(counts: [String: Int]) {
        for (id, n) in counts where n > 0 { add(id, count: n) }
    }

    /// Builds from explicit non-weapon counts plus saved weapon instances (v2).
    public init(counts: [String: Int], weapons: [WeaponInstance]) {
        self.counts = counts.filter { $0.value > 0 }
        self.weapons = weapons
    }

    private static func isWeapon(_ id: String) -> Bool {
        ItemCatalog.info(id).category == .weapon
    }

    public func count(of itemID: String) -> Int {
        if Self.isWeapon(itemID) { return weapons.lazy.filter { $0.id == itemID }.count }
        return counts[itemID] ?? 0
    }

    public func has(_ itemID: String) -> Bool { count(of: itemID) > 0 }
    public var isEmpty: Bool { counts.isEmpty && weapons.isEmpty }
    public var totalItemCount: Int { counts.values.reduce(0, +) + weapons.count }

    public mutating func add(_ itemID: String, count: Int = 1) {
        guard count > 0 else { return }
        if Self.isWeapon(itemID) {
            for _ in 0..<count { weapons.append(WeaponInstance(id: itemID)) }
        } else {
            counts[itemID, default: 0] += count
        }
    }

    /// Adds a specific weapon instance (upgrades / hardened blades).
    public mutating func addWeapon(_ instance: WeaponInstance) {
        weapons.append(instance)
    }

    /// Removes up to `count` of an item. For weapons, removes the most-worn
    /// instances first. Returns false (removing nothing) if not enough owned.
    @discardableResult
    public mutating func remove(_ itemID: String, count: Int = 1) -> Bool {
        guard count > 0 else { return false }
        if Self.isWeapon(itemID) {
            let matching = weapons.indices.filter { weapons[$0].id == itemID }
            guard matching.count >= count else { return false }
            let removeIdx = matching
                .sorted { durabilityKey(weapons[$0]) < durabilityKey(weapons[$1]) }
                .prefix(count)
                .sorted(by: >) // remove high indices first to keep offsets valid
            for idx in removeIdx { weapons.remove(at: idx) }
            return true
        }
        guard (counts[itemID] ?? 0) >= count else { return false }
        let remaining = (counts[itemID] ?? 0) - count
        if remaining == 0 { counts.removeValue(forKey: itemID) } else { counts[itemID] = remaining }
        return true
    }

    /// The instance that `remove(id)` would take first (most worn). Lets the
    /// scavenger preview a worn weapon's sell price before removing it.
    public func mostWornWeapon(of itemID: String) -> WeaponInstance? {
        weapons.filter { $0.id == itemID }.min { durabilityKey($0) < durabilityKey($1) }
    }

    /// Index of the "active" instance of a type — the most-worn one, which is
    /// what swings in combat (and so wears, takes the upgrade, and provides the
    /// damage bonus). Untracked instances (torch) sort last.
    func activeWeaponIndex(of itemID: String) -> Int? {
        weapons.indices
            .filter { weapons[$0].id == itemID }
            .min { durabilityKey(weapons[$0]) < durabilityKey(weapons[$1]) }
    }

    /// Damage bonus contributed by the active instance of a weapon type.
    public func upgradeBonus(of itemID: String) -> Int {
        guard let idx = activeWeaponIndex(of: itemID) else { return 0 }
        return weapons[idx].damageBonus
    }

    /// The active instance's current upgrade level (0 if none owned).
    public func upgradeLevel(of itemID: String) -> Int {
        guard let idx = activeWeaponIndex(of: itemID) else { return 0 }
        return weapons[idx].upgradeLevel
    }

    /// True if the active instance can still be upgraded (below its cap).
    public func canUpgradeWeapon(_ itemID: String) -> Bool {
        guard let idx = activeWeaponIndex(of: itemID) else { return false }
        return weapons[idx].upgradeLevel < Balance.Grindstone.cap(for: itemID)
    }

    /// Upgrades the active instance by one level if below its cap.
    @discardableResult
    public mutating func upgradeWeapon(_ itemID: String) -> Bool {
        guard let idx = activeWeaponIndex(of: itemID),
              weapons[idx].upgradeLevel < Balance.Grindstone.cap(for: itemID) else { return false }
        weapons[idx].upgradeLevel += 1
        return true
    }

    /// The active instance's current max durability (nil for untracked weapons
    /// like the torch, or if none owned). Lets callers gate the hardened blade.
    public func activeMaxDurability(of itemID: String) -> Int? {
        guard let idx = activeWeaponIndex(of: itemID) else { return nil }
        return weapons[idx].maxDurability
    }

    /// True if the active (most-worn) instance is durability-tracked and below
    /// its max — i.e. it can be repaired (Part 4).
    public func weaponNeedsRepair(_ itemID: String) -> Bool {
        guard let idx = activeWeaponIndex(of: itemID),
              let max = weapons[idx].maxDurability,
              let current = weapons[idx].durability else { return false }
        return current < max
    }

    /// Repairs the active (most-worn) instance by `amount`, capped at its max,
    /// preserving its upgrade level. Returns false if nothing to repair.
    @discardableResult
    public mutating func repairWeapon(_ itemID: String, amount: Int) -> Bool {
        guard let idx = activeWeaponIndex(of: itemID),
              let max = weapons[idx].maxDurability,
              let current = weapons[idx].durability,
              current < max else { return false }
        weapons[idx].durability = Swift.min(max, current + amount)
        return true
    }

    /// Hardened Blade (Part 5): boosts the active instance's max durability by
    /// `multiplier`, crediting the same delta to its current durability so the
    /// boost is felt immediately. Returns false if the active instance isn't
    /// durability-tracked (e.g. the torch) or none is owned.
    @discardableResult
    public mutating func hardenWeapon(_ itemID: String, multiplier: Double) -> Bool {
        guard let idx = activeWeaponIndex(of: itemID),
              let oldMax = weapons[idx].maxDurability,
              let current = weapons[idx].durability else { return false }
        let newMax = Int((Double(oldMax) * multiplier).rounded())
        guard newMax > oldMax else { return false }
        weapons[idx] = WeaponInstance(
            id: weapons[idx].id,
            durability: current + (newMax - oldMax),
            maxDurability: newMax,
            upgradeLevel: weapons[idx].upgradeLevel,
            instanceID: weapons[idx].instanceID
        )
        return true
    }

    /// Wears the active (most-worn) tracked instance of a type by one hit.
    /// Returns true if it broke (and was removed), false if it merely wore,
    /// nil if there's no durability-tracked instance (e.g. the torch).
    public mutating func degradeWeapon(_ itemID: String) -> Bool? {
        let tracked = weapons.indices.filter { weapons[$0].id == itemID && weapons[$0].durability != nil }
        guard let idx = tracked.min(by: { (weapons[$0].durability ?? 0) < (weapons[$1].durability ?? 0) }) else {
            return nil
        }
        weapons[idx].durability! -= 1
        if weapons[idx].durability! <= 0 {
            weapons.remove(at: idx)
            return true
        }
        return false
    }

    private func durabilityKey(_ w: WeaponInstance) -> Int { w.durability ?? Int.max }

    /// Sorted (id, count) pairs for one category page of the inventory UI.
    public func items(in category: ItemCategory) -> [(id: String, count: Int)] {
        if category == .weapon {
            return Dictionary(grouping: weapons, by: { $0.id })
                .map { (id: $0.key, count: $0.value.count) }
                .sorted { $0.id < $1.id }
        }
        return counts
            .filter { ItemCatalog.info($0.key).category == category }
            .sorted { $0.key < $1.key }
            .map { (id: $0.key, count: $0.value) }
    }

    /// One category page sorted for the tabbed list UI (Part 1): most-owned
    /// first, ties broken alphabetically by display name for stable ordering.
    /// For weapons (no simple quantity) this groups by type, most-owned type
    /// first — within a type, instances are shown upgrade/durability-first by
    /// `instances(of:)`, which sorts durability descending.
    public func itemsByQuantity(in category: ItemCategory) -> [(id: String, count: Int)] {
        items(in: category).sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return ItemCatalog.name(lhs.id) < ItemCatalog.name(rhs.id)
        }
    }

    /// All weapon instances of a type, freshest first (for durability display).
    public func instances(of itemID: String) -> [WeaponInstance] {
        weapons.filter { $0.id == itemID }
            .sorted { ($0.durability ?? Int.max) > ($1.durability ?? Int.max) }
    }

    public var allItems: [(id: String, count: Int)] {
        let stackables = counts.sorted { $0.key < $1.key }.map { (id: $0.key, count: $0.value) }
        let weaponGroups = items(in: .weapon)
        return (stackables + weaponGroups).sorted { $0.id < $1.id }
    }
}
