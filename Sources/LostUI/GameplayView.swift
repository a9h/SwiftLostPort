import SwiftUI
import GameCore

enum ActiveSheet: String, Identifiable {
    case inventory, stats, armour, workbench, equip, drop, use, saveLoad, help, debug
    var id: String { rawValue }
}

/// Shared shell for room / encounter / trader: HUD on top, the screen's
/// own content in the middle, the message log at the bottom.
struct GameplayView: View {
    @EnvironmentObject private var game: GameState
    @State private var sheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 10) {
            HUDView(onTitleHold: { sheet = .debug })

            Group {
                switch game.screen {
                case .room:
                    RoomView(sheet: $sheet)
                case .encounter:
                    EncounterView(sheet: $sheet)
                case .trader:
                    TraderView(sheet: $sheet)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LogView()
                .frame(height: 168)
        }
        .padding(12)
        .sheet(item: $sheet) { which in
            sheetContent(which)
                .environmentObject(game)
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 460)
                #endif
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: ActiveSheet) -> some View {
        switch which {
        case .inventory: InventorySheet()
        case .stats: StatsSheet()
        case .armour: ArmourSheet()
        case .workbench: WorkbenchSheet()
        case .equip: EquipSheet()
        case .drop: DropSheet()
        case .use: UseSheet()
        case .saveLoad: SaveLoadSheet()
        case .help: HelpSheet()
        case .debug: DebugSheet()
        }
    }
}

/// Persistent HUD: ❤️ 🍗 🚰 bars, 💷 money, room + doors.
struct HUDView: View {
    @EnvironmentObject private var game: GameState
    var onTitleHold: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("LOST")
                    .font(.system(.headline, design: .monospaced).bold())
                    .foregroundStyle(.green)
                    .onLongPressGesture(minimumDuration: 1.2) { onTitleHold() }
                Spacer()
                if case .room = game.screen {
                    Text("\(RoomStyle.emoji(for: game.roomName)) \(RoomStyle.displayName(for: game.roomName))  \(doorIcons)")
                        .font(.callout.monospaced())
                }
                Spacer()
                Text("💷 £\(game.player.money)")
                    .font(.callout.monospaced().bold())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: game.player.money)
            }

            HStack(spacing: 12) {
                Text("🚪 Rooms \(game.roomsExplored)")
                    .font(.caption.monospaced())
                if game.player.isPoisoned {
                    Text("☠️ Poisoned (\(game.player.poisonRemaining))")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.green)
                }
                if game.roomModifier != .none, case .room = game.screen {
                    Text("\(game.roomModifier.emoji) \(game.roomModifier.rawValue.capitalized)")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                StatBar(emoji: "❤️", value: game.player.currentHealth, max: max(game.player.maxHealth, 1), tint: .red,
                        label: "\(game.player.currentHealth)/\(game.player.maxHealth)")
                StatBar(emoji: "🍗", value: game.player.hunger, max: 100, tint: .orange,
                        label: "\(game.player.hunger)")
                StatBar(emoji: "🚰", value: game.player.thirst, max: 100, tint: .blue,
                        label: "\(game.player.thirst)")
                Text("🛡️\(game.player.armour.reductionPercent)%")
                    .font(.caption.monospaced())
                    .help("Armour damage reduction")
            }
        }
        .lostPanel()
    }

    private var doorIcons: String {
        String(repeating: "🚪", count: max(0, min(game.doors, 3)))
    }
}

struct StatBar: View {
    let emoji: String
    let value: Int
    let max: Int
    let tint: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji).font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: geo.size.width * fraction)
                        .animation(.snappy, value: value)
                }
            }
            .frame(height: 10)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var fraction: CGFloat {
        guard max > 0 else { return 0 }
        return CGFloat(Swift.max(0, Swift.min(value, max))) / CGFloat(max)
    }
}

enum RoomStyle {
    static func emoji(for room: String) -> String {
        switch room {
        case "Kitchen": return "🍳"
        case "Bedroom": return "🛏️"
        case "Bathroom": return "🛁"
        case "Basement": return "🪜"
        case "Garden": return "🌳"
        case "Scrapyard": return "🏗️"
        case "Street": return "🛣️"
        case "Tunnel": return "🚇"
        case "Workshop": return "🔧"
        case "AbandonedShop": return "🏚️"
        case "Pharmacy": return "💊"
        case "Garage": return "🚗"
        default: return "🚪"
        }
    }

    /// Spaces out camel-cased room ids for display (e.g. "Abandoned Shop").
    static func displayName(for room: String) -> String {
        switch room {
        case "AbandonedShop": return "Abandoned Shop"
        default: return room
        }
    }
}
