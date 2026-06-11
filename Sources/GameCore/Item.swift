import Foundation

public enum ItemCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case consumable, weapon, health, crafting, armor, tool

    public var id: String { rawValue }

    /// Display order and labels match the original's inventory pages.
    public static let displayOrder: [ItemCategory] = [.consumable, .weapon, .health, .crafting, .armor, .tool]

    public var displayName: String {
        switch self {
        case .consumable: return "Consumables"
        case .weapon: return "Weapons"
        case .health: return "Healables"
        case .crafting: return "Crafting"
        case .armor: return "Armour"
        case .tool: return "Tools"
        }
    }

    public var emoji: String {
        switch self {
        case .consumable: return "🍅"
        case .weapon: return "🗡️"
        case .health: return "🩹"
        case .crafting: return "🔩"
        case .armor: return "🪖"
        case .tool: return "🪨"
        }
    }
}

/// Static description of an item: replaces the original's raw
/// `"\nitemname"` strings with stable IDs, categories and emoji.
public struct ItemInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: ItemCategory
    public let emoji: String
    public let displayName: String
}

public enum ItemCatalog {
    public static let all: [String: ItemInfo] = {
        var catalog: [String: ItemInfo] = [:]
        func add(_ id: String, _ category: ItemCategory, _ emoji: String, _ name: String) {
            catalog[id] = ItemInfo(id: id, category: category, emoji: emoji, displayName: name)
        }
        // Weapons
        add("knife", .weapon, "🔪", "Knife")
        add("fork", .weapon, "🍴", "Fork")
        add("bat", .weapon, "🏏", "Bat")
        add("torch", .weapon, "🔦", "Torch")
        add("crowbar", .weapon, "🪛", "Crowbar")
        add("branch", .weapon, "🌿", "Branch")
        add("shovel", .weapon, "⛏️", "Shovel")
        add("sword", .weapon, "🗡️", "Sword")
        add("longsword", .weapon, "⚔️", "Longsword")
        // Crafting materials
        add("scrapmetal", .crafting, "🔩", "Scrap Metal")
        add("iron", .crafting, "⛓️", "Iron")
        add("ironBar", .crafting, "🧱", "Iron Bar")
        add("rope", .crafting, "🪢", "Rope")
        // Consumables (food & drink)
        add("tomato", .consumable, "🍅", "Tomato")
        add("cannedfood", .consumable, "🥫", "Canned Food")
        add("carrot", .consumable, "🥕", "Carrot")
        add("waterbottle", .consumable, "💧", "Water Bottle")
        add("steak", .consumable, "🥩", "Steak")
        add("chocolate", .consumable, "🍫", "Chocolate")
        add("mushroom", .consumable, "🍄", "Mushroom")
        // Healables
        add("medkit", .health, "🧰", "Medkit")
        add("pills", .health, "💊", "Pills")
        add("bandage", .health, "🩹", "Bandage")
        add("medicine", .health, "💉", "Medicine")
        // Armour — head
        add("leatherCap", .armor, "🧢", "Leather Cap")
        add("scrapHelmet", .armor, "🪖", "Scrap Helmet")
        add("ironHelmet", .armor, "⛑️", "Iron Helmet")
        add("steelHelmet", .armor, "🛡️", "Steel Helmet")
        // Armour — chest
        add("leatherVest", .armor, "🧥", "Leather Vest")
        add("scrapChestplate", .armor, "🦺", "Scrap Chestplate")
        add("ironChestplate", .armor, "🦺", "Iron Chestplate")
        add("steelChestplate", .armor, "🛡️", "Steel Chestplate")
        // Armour — legs
        add("leatherBoots", .armor, "🥾", "Leather Boots")
        add("scrapBoots", .armor, "👢", "Scrap Boots")
        add("ironBoots", .armor, "👢", "Iron Boots")
        add("steelBoots", .armor, "👢", "Steel Boots")
        // Tools
        add("grindstone", .tool, "🪨", "Grindstone")
        add("hardenedBlade", .tool, "🪒", "Hardened Blade")
        return catalog
    }()

    public static func info(_ id: String) -> ItemInfo {
        all[id] ?? ItemInfo(id: id, category: .tool, emoji: "❓", displayName: id)
    }

    public static func emoji(_ id: String) -> String { info(id).emoji }
    public static func name(_ id: String) -> String { info(id).displayName }
    /// Emoji + name, e.g. "🔦 Torch".
    public static func label(_ id: String) -> String { "\(info(id).emoji) \(info(id).displayName)" }
}
