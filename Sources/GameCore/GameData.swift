import Foundation

/// All static game data, decoded from the bundled JSON resources.
/// Mirrors the original game's data files: rooms, weapons, stats, recipes, shop.
public struct GameData: Sendable {
    /// RoomName -> loot table (duplicates increase an item's looting weight).
    public let rooms: [String: [String]]
    /// Weapon -> damage array (one value picked at random per hit).
    /// The torch has an empty array: it never deals damage, it scares instead.
    public let weapons: [String: [Int]]
    /// Weapon -> scrapmetal yield. Missing key = not breakable.
    public let breakdown: [String: Int]
    public let stats: StatsData
    /// Recipe name -> ingredient counts (e.g. scrapHelmet needs 5 scrapmetal).
    public let recipes: [String: [String: Int]]
    public let shop: ShopData

    public var roomNames: [String] { rooms.keys.sorted() }

    public static func load() -> GameData {
        load(bundle: .module)
    }

    public static func load(bundle: Bundle) -> GameData {
        GameData(
            rooms: decode("rooms", from: bundle),
            weapons: decode("weapons", from: bundle),
            breakdown: decode("breakdown", from: bundle),
            stats: decode("stats", from: bundle),
            recipes: decode("recipes", from: bundle),
            shop: decode("shop", from: bundle)
        )
    }

    private static func decode<T: Decodable>(_ name: String, from bundle: Bundle) -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            fatalError("Missing or malformed game data resource: \(name).json")
        }
        return decoded
    }
}

/// The stats tables: armour values per slot, and the random gain tables
/// for max health, healing, thirst and hunger.
public struct StatsData: Codable, Sendable {
    public let armourHead: [String: Int]
    public let armourChest: [String: Int]
    public let armourFeet: [String: Int]
    public let maxhealth: [String: [Int]]
    public let currenthealth: [String: [Int]]
    public let thirst: [String: [Int]]
    public let hunger: [String: [Int]]

    enum CodingKeys: String, CodingKey {
        case armourHead = "armour.head"
        case armourChest = "armour.chest"
        case armourFeet = "armour.feet"
        case maxhealth, currenthealth, thirst, hunger
    }
}

public struct ShopData: Codable, Sendable {
    public let food: [String: Int]
    public let weapons: [String: Int]
    public let tools: [String: Int]

    public func price(of itemID: String) -> Int? {
        food[itemID] ?? weapons[itemID] ?? tools[itemID]
    }
}
