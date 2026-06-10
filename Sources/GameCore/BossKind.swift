import Foundation

/// The five bosses, in their fixed encounter order (Part 3). The cycle repeats
/// from the start after the Packmaster, with max-damage active.
public enum BossKind: Int, Codable, CaseIterable, Sendable {
    case cowboy = 0
    case ghoul
    case plagueDoctor
    case warlord
    case packmaster

    public var displayName: String {
        switch self {
        case .cowboy: return "The Cowboy"
        case .ghoul: return "The Ghoul"
        case .plagueDoctor: return "The Plague Doctor"
        case .warlord: return "The Warlord"
        case .packmaster: return "The Packmaster"
        }
    }

    public var emoji: String {
        switch self {
        case .cowboy: return "🤠"
        case .ghoul: return "👻"
        case .plagueDoctor: return "🧙"
        case .warlord: return "🗡️"
        case .packmaster: return "🐺"
        }
    }

    /// The flanked decoration line shown in the encounter banner.
    public var decoration: String {
        switch self {
        case .cowboy: return "🌵 🤠 🌵"
        case .ghoul: return "💀 👻 💀"
        case .plagueDoctor: return "🦠 🧙 🦠"
        case .warlord: return "⚔️ 🗡️ ⚔️"
        case .packmaster: return "🐾 🐺 🐾"
        }
    }

    /// A unique, in-voice line announcing the boss.
    public var intro: String {
        switch self {
        case .cowboy: return "A figure in a dusty hat blocks your path, spurs jangling…"
        case .ghoul: return "The air turns cold and rotten — a ghoul drags itself from the dark…"
        case .plagueDoctor: return "A masked figure in a long coat tilts their beaked head at you…"
        case .warlord: return "An armoured brute hefts a notched blade and grins…"
        case .packmaster: return "Howls echo down the corridor — the Packmaster has caught your scent…"
        }
    }

    public var stats: Balance.Bosses.Stats {
        switch self {
        case .cowboy: return Balance.Bosses.cowboy
        case .ghoul: return Balance.Bosses.ghoul
        case .plagueDoctor: return Balance.Bosses.plagueDoctor
        case .warlord: return Balance.Bosses.warlord
        case .packmaster: return Balance.Bosses.packmaster
        }
    }

    /// Only the Warlord shrugs off the torch.
    public var isTorchImmune: Bool { self == .warlord }
}
