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
        inventory.add(recipeID)
        let used = ingredients
            .sorted { $0.key < $1.key }
            .map { "\($0.value)× \(ItemCatalog.label($0.key))" }
            .joined(separator: ", ")
        say("You crafted a \(ItemCatalog.label(recipeID)) using \(used).", .reward)
    }

    // MARK: - Breakdown (needs a grindstone)

    var hasGrindstone: Bool { inventory.has("grindstone") }

    /// Owned weapons, whether breakable or not (the UI shows both;
    /// unbreakable ones produce the original's refusal message).
    var breakdownCandidates: [(id: String, count: Int)] {
        inventory.items(in: .weapon)
    }

    func breakdown(_ weaponID: String) {
        guard hasGrindstone else {
            say("You do not have a grindstone!", .info)
            return
        }
        guard inventory.has(weaponID) else { return }
        guard let yield = data.breakdown[weaponID] else {
            say("You cannot breakdown \(ItemCatalog.name(weaponID)) into metal scrap!", .info)
            return
        }
        inventory.remove(weaponID)
        inventory.add("scrapmetal", count: yield)
        say("You ground the \(ItemCatalog.label(weaponID)) down into \(yield) 🔩 scrap metal.", .reward)
    }

    // MARK: - Equipping armour

    var ownedArmourItems: [(id: String, count: Int)] {
        inventory.items(in: .armor)
    }

    /// Adds the piece's value to its slot and consumes the item.
    func equip(_ armourID: String) {
        guard inventory.has(armourID) else { return }
        if let value = data.stats.armourHead[armourID] {
            player.armour.head += value
            inventory.remove(armourID)
            say("You equipped the \(ItemCatalog.label(armourID)) — head armour is now \(player.armour.head). Damage reduction: \(player.armour.total)%.", .reward)
        } else if let value = data.stats.armourChest[armourID] {
            player.armour.chest += value
            inventory.remove(armourID)
            say("You equipped the \(ItemCatalog.label(armourID)) — chest armour is now \(player.armour.chest). Damage reduction: \(player.armour.total)%.", .reward)
        } else if let value = data.stats.armourFeet[armourID] {
            player.armour.legs += value
            inventory.remove(armourID)
            say("You equipped the \(ItemCatalog.label(armourID)) — leg armour is now \(player.armour.legs). Damage reduction: \(player.armour.total)%.", .reward)
        } else {
            say("You can't equip that.", .info)
        }
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
