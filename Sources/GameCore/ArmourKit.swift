import Foundation

/// The three armour slots. Each holds at most one piece (Part 3 rework —
/// replacing the old "stack duplicates, sum values" model).
public enum ArmourSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case head, chest, legs
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .head: return "Head"
        case .chest: return "Chest"
        case .legs: return "Legs"
        }
    }

    /// The slot emoji used on the armour screen.
    public var emoji: String {
        switch self {
        case .head: return "🪖"
        case .chest: return "🦺"
        case .legs: return "👢"
        }
    }
}

/// Ascending material tiers a slot's piece can be. `leather` is the weakest,
/// `steel` the strongest. Upgrading walks one step up this ladder.
public enum ArmourMaterial: String, Codable, CaseIterable, Sendable, Comparable {
    case leather, scrap, iron, steel

    /// Position in the ascending ladder (leather = 0 … steel = 3).
    public var tierIndex: Int { Self.allCases.firstIndex(of: self)! }

    /// The next tier up, or nil if already at the top (steel).
    public var next: ArmourMaterial? {
        let i = tierIndex
        return i + 1 < Self.allCases.count ? Self.allCases[i + 1] : nil
    }

    public var displayName: String { rawValue.capitalized }

    public static func < (lhs: ArmourMaterial, rhs: ArmourMaterial) -> Bool {
        lhs.tierIndex < rhs.tierIndex
    }
}

/// Static description of one armour piece — which slot it occupies and its
/// material tier. Lets the equip/upgrade/migration logic translate freely
/// between an inventory item id and its (slot, tier).
public struct ArmourPieceInfo: Sendable, Equatable {
    public let id: String
    public let slot: ArmourSlot
    public let material: ArmourMaterial
}

public enum ArmourCatalog {
    /// itemID -> (slot, material). The single source of truth for which item
    /// belongs in which slot at which tier.
    public static let pieces: [String: ArmourPieceInfo] = {
        var table: [String: ArmourPieceInfo] = [:]
        func add(_ id: String, _ slot: ArmourSlot, _ material: ArmourMaterial) {
            table[id] = ArmourPieceInfo(id: id, slot: slot, material: material)
        }
        // Head
        add("leatherCap", .head, .leather)
        add("scrapHelmet", .head, .scrap)
        add("ironHelmet", .head, .iron)
        add("steelHelmet", .head, .steel)
        // Chest
        add("leatherVest", .chest, .leather)
        add("scrapChestplate", .chest, .scrap)
        add("ironChestplate", .chest, .iron)
        add("steelChestplate", .chest, .steel)
        // Legs
        add("leatherBoots", .legs, .leather)
        add("scrapBoots", .legs, .scrap)
        add("ironBoots", .legs, .iron)
        add("steelBoots", .legs, .steel)
        return table
    }()

    /// Reverse lookup: (slot, material) -> itemID.
    private static let idsBySlotMaterial: [ArmourSlot: [ArmourMaterial: String]] = {
        var table: [ArmourSlot: [ArmourMaterial: String]] = [:]
        for (id, info) in pieces {
            table[info.slot, default: [:]][info.material] = id
        }
        return table
    }()

    public static func id(slot: ArmourSlot, material: ArmourMaterial) -> String {
        idsBySlotMaterial[slot]?[material] ?? ""
    }

    public static func info(_ id: String) -> ArmourPieceInfo? { pieces[id] }
}
