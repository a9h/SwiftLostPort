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

    /// Rolls a modifier from a 1...100 value using the Balance thresholds.
    /// `darkBonus` widens the dark band (the Tunnel room passes a bonus so it
    /// trends dark); it doesn't change the trap chance.
    public static func roll(_ value: Int, darkBonus: Int = 0) -> RoomModifier {
        let trap = Balance.RoomModifiers.trapChance
        let dark = trap + Balance.RoomModifiers.darkChance + darkBonus
        let flooded = dark + Balance.RoomModifiers.floodedChance
        if value <= trap { return .trap }
        if value <= dark { return .dark }
        if value <= flooded { return .flooded }
        return .none
    }
}
