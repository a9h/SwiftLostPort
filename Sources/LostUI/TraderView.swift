import SwiftUI
import GameCore

/// The wild trader: shop stock with buy-confirmation, gambling games,
/// and the usual utility actions.
struct TraderView: View {
    @EnvironmentObject private var game: GameState
    @Binding var sheet: ActiveSheet?

    @State private var confirmingItem: String?
    @State private var showGames = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("🧙").font(.system(size: 56))
                Text("\"Care to browse my wares... or play a little game?\"")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .lostPanel()

            // Shop stock
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(game.shopStock?.allItemIDs ?? [], id: \.self) { itemID in
                        shopRow(itemID)
                    }
                    if (game.shopStock?.allItemIDs ?? []).isEmpty {
                        Text("The trader's bag is empty today.")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }

            let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ActionButton("Games", "🎲", prominent: true) { showGames = true }
                ActionButton("Use", "🍽️") { sheet = .use }
                ActionButton("Inventory", "🎒") { sheet = .inventory }
                ActionButton("Health", "❤️") { sheet = .stats }
                ActionButton("Drop", "🗑️") { sheet = .drop }
                ActionButton("Leave", "🚪") { game.leaveTrader() }
            }
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { confirmingItem != nil },
                set: { if !$0 { confirmingItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let itemID = confirmingItem {
                Button("Buy for £\(game.price(of: itemID) ?? 0)") {
                    game.buy(itemID)
                    confirmingItem = nil
                }
                Button("Cancel", role: .cancel) { confirmingItem = nil }
            }
        }
        .sheet(isPresented: $showGames) {
            GamesSheet()
                .environmentObject(game)
                #if os(macOS)
                .frame(minWidth: 440, minHeight: 520)
                #endif
        }
    }

    private var confirmTitle: String {
        guard let itemID = confirmingItem else { return "" }
        return "This costs £\(game.price(of: itemID) ?? 0) — are you sure?"
    }

    private func shopRow(_ itemID: String) -> some View {
        let price = game.price(of: itemID) ?? 0
        let affordable = game.player.money >= price
        return HStack {
            Text(ItemCatalog.label(itemID))
                .font(.callout.monospaced())
            Spacer()
            Text("£\(price)")
                .font(.callout.monospaced().bold())
                .foregroundStyle(affordable ? Color.green : Color.red)
            Button("Buy") { confirmingItem = itemID }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!affordable)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
