import Foundation

/// The grindstone system (Part 5b): weapon conversion and per-instance damage
/// upgrades. Both are available when the player owns a grindstone and for free
/// at either trader — the UI decides when to offer them; these shared methods
/// only validate and apply the ingredients.
public extension GameState {

    // MARK: - Weapon conversion

    var weaponConversions: [(source: String, result: String, cost: Int)] {
        Balance.Grindstone.conversions
            .sorted { $0.key < $1.key }
            .map { (source: $0.key, result: $0.value.result, cost: $0.value.scrapCost) }
    }

    func canConvertWeapon(_ source: String) -> Bool {
        guard let recipe = Balance.Grindstone.conversions[source] else { return false }
        return inventory.has(source) && inventory.count(of: "scrapmetal") >= recipe.scrapCost
    }

    /// Consumes the source weapon + exact scrap and produces the upgraded
    /// weapon at full durability and upgrade level 0.
    func convertWeapon(_ source: String) {
        guard let recipe = Balance.Grindstone.conversions[source], canConvertWeapon(source) else {
            say("You can't convert that right now.", .info)
            return
        }
        inventory.remove(source)
        inventory.remove("scrapmetal", count: recipe.scrapCost)
        inventory.add(recipe.result)
        say("You ground your \(ItemCatalog.label(source)) into a \(ItemCatalog.label(recipe.result)) using \(recipe.scrapCost)× 🔩.", .reward)
    }

    // MARK: - Weapon damage upgrade

    /// Owned weapons that can ever be damage-upgraded (have a cap).
    var upgradeableWeapons: [(id: String, count: Int)] {
        inventory.items(in: .weapon).filter { Balance.Grindstone.cap(for: $0.id) > 0 }
    }

    func canUpgradeWeaponDamage(_ weaponID: String) -> Bool {
        inventory.canUpgradeWeapon(weaponID)
            && inventory.count(of: "scrapmetal") >= Balance.Grindstone.upgradeCost
    }

    /// Spends scrap to add a flat damage bonus to the active weapon instance.
    func upgradeWeaponDamage(_ weaponID: String) {
        guard inventory.canUpgradeWeapon(weaponID) else {
            say("Your \(ItemCatalog.name(weaponID)) can't be improved any further.", .info)
            return
        }
        guard inventory.count(of: "scrapmetal") >= Balance.Grindstone.upgradeCost else {
            say("You need \(Balance.Grindstone.upgradeCost)× 🔩 to upgrade that.", .info)
            return
        }
        inventory.remove("scrapmetal", count: Balance.Grindstone.upgradeCost)
        inventory.upgradeWeapon(weaponID)
        let level = inventory.upgradeLevel(of: weaponID)
        say("You sharpened your \(ItemCatalog.label(weaponID)) — now +\(level * Balance.Grindstone.upgradeDamageBonus) damage (level \(level)).", .reward)
    }
}
