import Foundation

/// Armour durability/breaking (Part 2) and the Workbench repair functions
/// (Parts 2d + 4). Armour wear is driven by the gameplay RNG only when armour
/// is actually equipped, so unarmoured combat stays deterministic.
public extension GameState {

    // MARK: - Armour wear (Part 2b)

    /// Applies durability loss for one hit the player takes: 50/50 between 1 and
    /// 2 affected slots, each picked slot losing exactly 1 durability. Picks
    /// only from occupied slots; no-ops (and consumes no RNG) when unarmoured.
    func wearArmour() {
        let occupied = ArmourSlot.allCases.filter { player.armour.material(in: $0) != nil }
        guard !occupied.isEmpty else { return }

        let affected = rng.int(in: 1...2)
        var targets: [ArmourSlot] = []
        if affected == 1 || occupied.count == 1 {
            targets = [occupied[rng.int(in: 0...(occupied.count - 1))]]
        } else {
            var pool = occupied
            let first = pool.remove(at: rng.int(in: 0...(pool.count - 1)))
            let second = pool.remove(at: rng.int(in: 0...(pool.count - 1)))
            targets = [first, second]
        }
        for slot in targets { wearArmourSlot(slot) }
    }

    /// Wears a single named slot by 1 durability (used by flooded rooms, Part
    /// 2b). Breaks the piece if it hits 0.
    func wearArmourSlot(_ slot: ArmourSlot) {
        guard let material = player.armour.material(in: slot),
              let max = player.armour.maxDurability(in: slot) else { return }
        let current = player.armour.currentDurability(in: slot) ?? max
        let next = current - 1
        if next <= 0 {
            breakArmour(slot, material: material)
        } else {
            player.armour.setStoredDurability(next, in: slot)
        }
    }

    /// Breaks a piece (Part 2c): empties the slot and drops tier-scaled scrap.
    private func breakArmour(_ slot: ArmourSlot, material: ArmourMaterial) {
        player.armour.setMaterial(nil, in: slot) // also clears stored durability
        let drops = Balance.Armour.breakDrop[material] ?? [:]
        for (itemID, count) in drops.sorted(by: { $0.key < $1.key }) {
            inventory.add(itemID, count: count)
        }
        let materialsText = drops
            .sorted { $0.key < $1.key }
            .map { "\($0.value)× \(ItemCatalog.label($0.key))" }
            .joined(separator: " + ")
        say(flavour(.armourBreak, [
            "tier": material.displayName,
            "slot": slot.displayName.lowercased(),
            "materials": materialsText,
        ]), .warning)
    }

    // MARK: - Armour repair (Part 2d)

    /// Occupied slots that are below full durability (regardless of materials).
    var repairableArmourSlots: [ArmourSlot] {
        ArmourSlot.allCases.filter { player.armour.needsRepair(in: $0) }
    }

    /// True when the slot is below full AND the player can afford the repair —
    /// drives the 🔧 indicator.
    func canRepairArmour(_ slot: ArmourSlot) -> Bool {
        guard let material = player.armour.material(in: slot),
              player.armour.needsRepair(in: slot) else { return false }
        let cost = Balance.Armour.repairCost(slot, material)
        return inventory.count(of: cost.ingredient) >= cost.count
    }

    func repairArmour(_ slot: ArmourSlot) {
        guard let material = player.armour.material(in: slot),
              let max = player.armour.maxDurability(in: slot),
              let current = player.armour.currentDurability(in: slot),
              current < max else {
            say("That armour doesn't need repairing.", .info)
            return
        }
        let cost = Balance.Armour.repairCost(slot, material)
        guard inventory.count(of: cost.ingredient) >= cost.count else {
            say("You need \(cost.count)× \(ItemCatalog.label(cost.ingredient)) to patch up that \(material.displayName.lowercased()) \(slot.displayName.lowercased()) armour.", .info)
            return
        }
        inventory.remove(cost.ingredient, count: cost.count)
        let amount = Balance.Armour.repairAmount(maxDurability: max, currentDurability: current)
        let actual = min(amount, max - current)
        player.armour.setStoredDurability(current + actual, in: slot)
        say("You patch up your \(material.displayName.lowercased()) \(slot.displayName.lowercased()) armour (+\(actual), now \(current + actual)/\(max)) with \(cost.count)× \(ItemCatalog.label(cost.ingredient)).", .reward)
    }

    // MARK: - Weapon repair (Part 4)

    /// Owned weapon types that have a repair recipe and a below-max instance.
    var repairableWeapons: [(id: String, count: Int)] {
        inventory.items(in: .weapon).filter {
            Balance.WeaponRepair.costs[$0.id] != nil && inventory.weaponNeedsRepair($0.id)
        }
    }

    /// True when the active instance is below max AND the materials are in hand.
    func canRepairWeapon(_ weaponID: String) -> Bool {
        guard let cost = Balance.WeaponRepair.costs[weaponID],
              inventory.weaponNeedsRepair(weaponID) else { return false }
        return inventory.count(of: cost.ingredient) >= cost.count
    }

    /// Repairs the most-worn instance of a weapon type by its restore amount,
    /// capped at max, preserving its upgrade level.
    func repairWeapon(_ weaponID: String) {
        guard let cost = Balance.WeaponRepair.costs[weaponID],
              inventory.weaponNeedsRepair(weaponID) else {
            say("That weapon doesn't need repairing.", .info)
            return
        }
        guard inventory.count(of: cost.ingredient) >= cost.count else {
            say("You need \(cost.count)× \(ItemCatalog.label(cost.ingredient)) to repair your \(ItemCatalog.name(weaponID)).", .info)
            return
        }
        inventory.remove(cost.ingredient, count: cost.count)
        inventory.repairWeapon(weaponID, amount: cost.restore)
        say("You patch up your \(ItemCatalog.label(weaponID)) with \(cost.count)× \(ItemCatalog.label(cost.ingredient)).", .reward)
    }
}
