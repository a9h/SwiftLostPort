import SwiftUI
import GameCore

/// A normal room: big room emoji, the doors, and every room-menu action
/// from the original as buttons.
struct RoomView: View {
    @Environment(GameState.self) private var game
    @Binding var sheet: ActiveSheet?
    @State private var lootBounce = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text(RoomStyle.emoji(for: game.roomName))
                    .font(.system(size: 84))
                    .scaleEffect(lootBounce ? 1.12 : 1)
                    .animation(.bouncy(duration: 0.35), value: lootBounce)
                Text(game.roomName)
                    .font(.system(.title2, design: .monospaced).bold())
                Text(game.hasLooted ? "Picked clean." : "Looks like there could be something here...")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Doors: tap to move on (door N only if the room has N doors).
            HStack(spacing: 18) {
                ForEach(1...game.doors, id: \.self) { door in
                    Button {
                        game.takeDoor(door)
                    } label: {
                        VStack(spacing: 2) {
                            Text("🚪").font(.system(size: 44))
                            Text("Door \(door)").font(.caption.monospaced())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            Spacer(minLength: 0)

            actionGrid
        }
    }

    private var actionGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ActionButton("Loot", "🔍", prominent: !game.hasLooted) {
                game.loot()
                lootBounce.toggle()
            }
            ActionButton("Use", "🍽️") { sheet = .use }
            ActionButton("Inventory", "🎒") { sheet = .inventory }
            ActionButton("Health", "❤️") { sheet = .stats }
            ActionButton("Armour", "🛡️") { sheet = .armour }
            ActionButton("Equip", "🪖") { sheet = .equip }
            ActionButton("Crafting", "🛠️") { sheet = .crafting }
            ActionButton("Breakdown", "🪨") { sheet = .breakdown }
            ActionButton("Drop", "🗑️") { sheet = .drop }
            ActionButton("Save/Load", "💾") { sheet = .saveLoad }
            ActionButton("Help", "❓") { sheet = .help }
        }
    }
}

struct ActionButton: View {
    let title: String
    let emoji: String
    var prominent = false
    let action: () -> Void

    init(_ title: String, _ emoji: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.emoji = emoji
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                Text(title).font(.callout.monospaced())
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? .green : .gray)
    }
}
