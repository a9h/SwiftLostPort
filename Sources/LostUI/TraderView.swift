import SwiftUI
import GameCore

/// The trader — either a merchant (sells stock) or a scavenger (buys your
/// items). Both offer gambling and a free grindstone service.
struct TraderView: View {
    @EnvironmentObject private var game: GameState
    @Binding var sheet: ActiveSheet?

    @State private var confirmingBuy: String?
    @State private var confirmingSell: String?
    @State private var showGames = false
    @State private var showWorkbench = false

    private var isScavenger: Bool { game.traderKind == .scavenger }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(isScavenger ? "🪤" : "🧙").font(.system(size: 56))
                Text(isScavenger
                     ? "\"Got anything worth a few coins? I'll take it off your hands.\""
                     : "\"Care to browse my wares... or play a little game?\"")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .lostPanel()

            if isScavenger {
                sellList
            } else {
                shopList
            }

            let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ActionButton("Workbench", "🛠️", prominent: true) { showWorkbench = true }
                ActionButton("Games", "🎲", prominent: true) { showGames = true }
                ActionButton("Use", "🍽️") { sheet = .use }
                ActionButton("Inventory", "🎒") { sheet = .inventory }
                ActionButton("Equip", "🪖") { sheet = .equip }
                ActionButton("Health", "❤️") { sheet = .stats }
                ActionButton("Drop", "🗑️") { sheet = .drop }
                ActionButton("Leave", "🚪") { game.leaveTrader() }
            }
        }
        .confirmationDialog(buyTitle, isPresented: bindingForBuy, titleVisibility: .visible) {
            if let itemID = confirmingBuy {
                Button("Buy for £\(game.price(of: itemID) ?? 0)") {
                    game.buy(itemID); confirmingBuy = nil
                }
                Button("Cancel", role: .cancel) { confirmingBuy = nil }
            }
        }
        .confirmationDialog(sellTitle, isPresented: bindingForSell, titleVisibility: .visible) {
            if let itemID = confirmingSell {
                Button("Sell for £\(game.sellPrice(of: itemID))") {
                    game.sell(itemID); confirmingSell = nil
                }
                Button("Cancel", role: .cancel) { confirmingSell = nil }
            }
        }
        .sheet(isPresented: $showGames) {
            GamesSheet().environmentObject(game)
                #if os(macOS)
                .frame(minWidth: 440, minHeight: 520)
                #endif
        }
        .sheet(isPresented: $showWorkbench) {
            WorkbenchSheet().environmentObject(game)
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 460)
                #endif
        }
    }

    // MARK: - Merchant stock

    private var shopList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(game.shopStock?.allItemIDs ?? [], id: \.self) { itemID in
                    let price = game.price(of: itemID) ?? 0
                    let affordable = game.player.money >= price
                    HStack {
                        Text(ItemCatalog.label(itemID)).font(.callout.monospaced())
                        Spacer()
                        Text("£\(price)").font(.callout.monospaced().bold())
                            .foregroundStyle(affordable ? Color.green : Color.red)
                        Button("Buy") { confirmingBuy = itemID }
                            .buttonStyle(.borderedProminent).tint(.green)
                            .disabled(!affordable)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                if (game.shopStock?.allItemIDs ?? []).isEmpty {
                    Text("The trader's bag is empty today.")
                        .font(.callout.monospaced()).foregroundStyle(.secondary).padding()
                }
            }
        }
    }

    // MARK: - Scavenger sell list (tabbed by category, Part 1)

    /// Categories the scavenger buys, in display order. Only categories with at
    /// least one sellable item type ever appear as tabs.
    private var sellableCategories: [ItemCategory] {
        ItemCategory.displayOrder.filter { cat in
            game.sellableItems.contains { ItemCatalog.info($0.id).category == cat }
        }
    }

    private var sellList: some View {
        Group {
            if game.sellableItems.isEmpty {
                Text("You've nothing the scavenger wants.")
                    .font(.callout.monospaced()).foregroundStyle(.secondary).padding()
            } else {
                TabbedPanel(tabs: sellableCategories.map { cat in
                    TabbedPanel.Tab(id: cat.rawValue, label: "\(cat.emoji) \(cat.displayName)") {
                        sellTab(cat)
                    }
                })
            }
        }
    }

    /// Sellable items in one category, sorted most-owned first (alpha tiebreak).
    private func sellTab(_ category: ItemCategory) -> some View {
        let items = game.sellableItems
            .filter { ItemCatalog.info($0.id).category == category }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return ItemCatalog.name(lhs.id) < ItemCatalog.name(rhs.id)
            }
        return Group {
            if items.isEmpty {
                QuietPlaceholder(text: "Nothing here to sell.")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(items, id: \.id) { item in
                            HStack {
                                Text("\(ItemCatalog.label(item.id)) ×\(item.count)").font(.callout.monospaced())
                                Spacer()
                                Text("£\(item.price)").font(.callout.monospaced().bold()).foregroundStyle(.green)
                                Button("Sell") { confirmingSell = item.id }
                                    .buttonStyle(.borderedProminent).tint(.green)
                            }
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private var buyTitle: String {
        guard let id = confirmingBuy else { return "" }
        return "This costs £\(game.price(of: id) ?? 0) — are you sure?"
    }
    private var sellTitle: String {
        guard let id = confirmingSell else { return "" }
        return "The scavenger offers £\(game.sellPrice(of: id)) for your \(ItemCatalog.name(id)). Sell?"
    }
    private var bindingForBuy: Binding<Bool> {
        Binding(get: { confirmingBuy != nil }, set: { if !$0 { confirmingBuy = nil } })
    }
    private var bindingForSell: Binding<Bool> {
        Binding(get: { confirmingSell != nil }, set: { if !$0 { confirmingSell = nil } })
    }
}
