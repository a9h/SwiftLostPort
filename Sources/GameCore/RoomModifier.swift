import Foundation

/// An optional hazard layered onto a normal room (B3). At most one per room;
/// most rooms have none.
public enum RoomModifier: String, Codable, Sendable {
    case none, trap, dark, flooded

    public var emoji: String {
        switch self {
        case .none: return ""
        case .trap: return "⚠️"
        case .dark: return "🌑"
        case .flooded: return "🌊"
        }
    }

    public var banner: String? {
        switch self {
        case .none: return nil
        case .trap: return "⚠️ Something feels off about the floor here..."
        case .dark: return "🌑 This room is pitch black."
        case .flooded: return "🌊 This room is flooded with murky water."
        }
    }

    /// Rolls a modifier from a 1...100 value against explicit chances.
    /// `darkBonus` widens the dark band (the Tunnel room passes a bonus so it
    /// trends dark); it doesn't change the trap chance.
    public static func roll(_ value: Int, trap: Int, dark: Int, flooded: Int, darkBonus: Int = 0) -> RoomModifier {
        let trapMax = trap
        let darkMax = trapMax + dark + darkBonus
        let floodedMax = darkMax + flooded
        if value <= trapMax { return .trap }
        if value <= darkMax { return .dark }
        if value <= floodedMax { return .flooded }
        return .none
    }

    /// Depth-aware roll (Part 4b): picks the early or late chance set.
    public static func roll(_ value: Int, depth: Int, darkBonus: Int = 0) -> RoomModifier {
        roll(value,
             trap: Balance.RoomModifiers.trapChance(depth: depth),
             dark: Balance.RoomModifiers.darkChance(depth: depth),
             flooded: Balance.RoomModifiers.floodedChance(depth: depth),
             darkBonus: darkBonus)
    }
}
