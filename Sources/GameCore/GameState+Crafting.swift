import Foundation

public extension GameState {

    // MARK: - Crafting

    /// Recipe names the player can currently afford, in a stable order.
    var craftableRecipes: [String] {
        data.recipes.keys.sorted().filter(canCraft)
    }

    func canCraft(_ recipeID: String) -> Bool {
        guard let ingredients = data.recipes[recipeID] else { return false }
        return ingredients.allSatisfy { inventory.count(of: $0.key) >= $0.value }
    }

    /// Crafting consumes exactly the recipe's ingredients (fixing the
    /// original's `=-` typo that mis-deducted them).
    func craft(_ recipeID: String) {
        guard let ingredients = data.recipes[recipeID], canCraft(recipeID) else {
            say("You don't have the materials to make that.", .info)
            return
        }
        for (ingredientID, count) in ingredients {
            inventory.remove(ingredientID, count: count)
        }
        let yield = Balance.Crafting.outputCount(for: recipeID)
        inventory.add(recipeID, count: yield)
        runStats.itemsCrafted += yield
        let used = ingredients
            .sorted { $0.key < $1.key }
            .map { "\($0.value)× \(ItemCatalog.label($0.key))" }
            .joined(separator: ", ")
        let made = yield > 1 ? "\(yield)× \(ItemCatalog.label(recipeID))" : "a \(ItemCatalog.label(recipeID))"
        say("You crafted \(made) using \(used).", .reward)
    }

    // MARK: - Breakdown (a Workbench function — access is gated at the menu)

    var hasGrindstone: Bool { inventory.has("grindstone") }

    /// Owned weapons, whether breakable or not (the UI shows both;
    /// unbreakable ones produce the original's refusal message).
    var breakdownCandidates: [(id: String, count: Int)] {
        inventory.items(in: .weapon)
    }

    /// Scrap a weapon. Reachable only through the Workbench, whose access points
    /// (owned grindstone, or free at either trader) are gated by the UI — so the
    /// function itself no longer re-checks for a grindstone (Part 2).
    func breakdown(_ weaponID: String) {
        guard inventory.has(weaponID) else { return }
        guard let yield = data.breakdown[weaponID] else {
            say("You cannot breakdown \(ItemCatalog.name(weaponID)) into metal scrap!", .info)
            return
        }
        inventory.remove(weaponID)
        inventory.add("scrapmetal", count: yield)
        say("You ground the \(ItemCatalog.label(weaponID)) down into \(yield) 🔩 scrap metal.", .reward)
    }

    // MARK: - Equipping armour (Part 3a: one piece per slot, swaps return the old)

    var ownedArmourItems: [(id: String, count: Int)] {
        inventory.items(in: .armor)
    }

    /// Equips a found/crafted piece into its slot. An empty slot equips free; a
    /// filled slot is swapped, returning the old piece to the inventory.
    func equip(_ armourID: String) {
        guard inventory.has(armourID), let info = ArmourCatalog.info(armourID) else {
            say("You can't equip that.", .info)
            return
        }
        inventory.remove(armourID)
        if let existing = player.armour.material(in: info.slot) {
            let oldID = ArmourCatalog.id(slot: info.slot, material: existing)
            inventory.add(oldID)
            say("You swapped your \(ItemCatalog.label(oldID)) for the \(ItemCatalog.label(armourID)) — the old piece goes back in your pack.", .info)
        }
        player.armour.setMaterial(info.material, in: info.slot)
        player.armour.refillDurability(in: info.slot) // fresh piece at full durability
        say("You equipped the \(ItemCatalog.label(armourID)). Damage reduction: \(player.armour.reductionPercent)%.", .reward)
    }

    // MARK: - Armour upgrades (Part 3b: a Workbench function)

    /// Slots whose equipped piece can still be reforged up a tier.
    var upgradeableArmourSlots: [ArmourSlot] {
        ArmourSlot.allCases.filter { slot in
            guard let current = player.armour.material(in: slot) else { return false }
            return current.next != nil
        }
    }

    func canUpgradeArmour(_ slot: ArmourSlot) -> Bool {
        guard let current = player.armour.material(in: slot), let next = current.next,
              let cost = Balance.Armour.upgradeCost(to: next) else { return false }
        return inventory.count(of: cost.ingredient) >= cost.count
    }

    /// Reforges a slot's piece into the next tier, consuming the current piece
    /// in place plus the tier's materials (distinct from a swap — nothing is
    /// returned to the inventory).
    func upgradeArmour(_ slot: ArmourSlot) {
        guard let current = player.armour.material(in: slot), let next = current.next,
              let cost = Balance.Armour.upgradeCost(to: next) else {
            say("There's nothing here to upgrade.", .info)
            return
        }
        guard inventory.count(of: cost.ingredient) >= cost.count else {
            say("You need \(cost.count)× \(ItemCatalog.label(cost.ingredient)) to forge \(next.displayName) \(slot.displayName.lowercased()) armour.", .info)
            return
        }
        inventory.remove(cost.ingredient, count: cost.count)
        player.armour.setMaterial(next, in: slot)
        player.armour.refillDurability(in: slot) // upgraded piece starts at full
        let newID = ArmourCatalog.id(slot: slot, material: next)
        say("You reforged your \(slot.displayName.lowercased()) armour into a \(ItemCatalog.label(newID)) using \(cost.count)× \(ItemCatalog.label(cost.ingredient)). Damage reduction: \(player.armour.reductionPercent)%.", .reward)
    }

    // MARK: - Hardened Blade (Part 5: a Workbench function)

    /// Weapons whose active instance can take a hardened-blade boost (excludes
    /// the durability-less torch).
    var hardenableWeapons: [(id: String, count: Int)] {
        inventory.items(in: .weapon).filter { inventory.activeMaxDurability(of: $0.id) != nil }
    }

    func canHardenBlade(_ weaponID: String) -> Bool {
        inventory.count(of: "ironBar") >= 1 && inventory.activeMaxDurability(of: weaponID) != nil
    }

    /// Spends 1 ironBar to raise the active instance's max durability by the
    /// hardened multiplier (Balance.Durability.hardenedMultiplier).
    func hardenBlade(_ weaponID: String) {
        guard inventory.count(of: "ironBar") >= 1 else {
            say("You need 1× \(ItemCatalog.label("ironBar")) to harden a blade.", .info)
            return
        }
        guard inventory.hardenWeapon(weaponID, multiplier: Balance.Durability.hardenedMultiplier) else {
            say("You can't harden that.", .info)
            return
        }
        inventory.remove("ironBar")
        let maxD = inventory.activeMaxDurability(of: weaponID) ?? 0
        say("You hardened your \(ItemCatalog.label(weaponID)) with an iron bar — it now lasts up to \(maxD) hits.", .reward)
    }

    // MARK: - Admin / debug (hidden panel)

    func adminRemove(_ itemID: String) {
        if inventory.remove(itemID) {
            say("[admin] Removed one \(ItemCatalog.name(itemID)).", .info)
        } else {
            say("[admin] No \(ItemCatalog.name(itemID)) to remove.", .info)
        }
    }

    func adminAdd(_ itemID: String, count: Int = 1) {
        inventory.add(itemID, count: count)
        say("[admin] Added \(count)× \(ItemCatalog.name(itemID)).", .info)
    }

    func adminSetMoney(_ amount: Int) {
        player.money = max(0, amount)
        say("[admin] Money set to £\(player.money).", .info)
    }
}
