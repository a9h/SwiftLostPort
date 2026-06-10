import SwiftUI
import GameCore

/// Shared scaffolding for every modal panel.
struct SheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(.title3, design: .monospaced).bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            content
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

struct ItemRow: View {
    let id: String
    let count: Int
    var detail: String? = nil
    var actionLabel: String? = nil
    var actionDisabled = false
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text("\(ItemCatalog.emoji(id)) \(ItemCatalog.name(id)) ×\(count)")
                .font(.callout.monospaced())
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .disabled(actionDisabled)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Inventory (categorised, like the original's < / > pages)

struct InventorySheet: View {
    @EnvironmentObject private var game: GameState
    @State private var category: ItemCategory = .consumable

    /// "24/30" for one weapon, "30/30, 24/30" for several; "∞" for the torch.
    private func durabilityDetail(_ weaponID: String) -> String {
        let parts = game.inventory.instances(of: weaponID).map { inst -> String in
            if let d = inst.durability, let m = inst.maxDurability { return "\(d)/\(m)" }
            return "∞"
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        SheetScaffold(title: "🎒 Inventory") {
            Picker("Category", selection: $category) {
                ForEach(ItemCategory.displayOrder) { cat in
                    Text("\(cat.emoji) \(cat.displayName)").tag(cat)
                }
            }
            .pickerStyle(.menu)

            let items = game.inventory.items(in: category)
            if items.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "tray",
                                       description: Text("No \(category.displayName.lowercased()) yet."))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items, id: \.id) { item in
                            ItemRow(id: item.id, count: item.count,
                                    detail: category == .weapon ? durabilityDetail(item.id) : nil)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Stats ("health" command)

struct StatsSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "❤️ Stats") {
            VStack(alignment: .leading, spacing: 10) {
                statLine("❤️ Health", "\(game.player.currentHealth) / \(game.player.maxHealth)")
                statLine("🍗 Hunger", "\(game.player.hunger) / 100")
                statLine("🚰 Thirst", "\(game.player.thirst) / 100")
                statLine("💷 Money", "£\(game.player.money)")
                statLine("🪜 Depth", "\(game.depth)")
                statLine("🚪 Rooms visited", "\(game.roomsVisited)")
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
            )
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout.monospaced())
            Spacer()
            Text(value).font(.callout.monospaced().bold())
        }
    }
}

// MARK: - Armour figure

struct ArmourSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "🛡️ Armour") {
            VStack(spacing: 10) {
                armourLine("🪖", "Head", game.player.armour.head)
                armourLine("🦺", "Chest", game.player.armour.chest)
                armourLine("👢", "Legs", game.player.armour.legs)
                Divider()
                Text("Your armour reduces incoming damage by ~\(game.player.armour.reductionPercent)%")
                    .font(.callout.monospaced().bold())
                    .foregroundStyle(.green)
                Text("(diminishing returns — approaches but never reaches 85%)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
            )
        }
    }

    private func armourLine(_ emoji: String, _ slot: String, _ value: Int) -> some View {
        HStack {
            Text(emoji).font(.title)
            Text(slot).font(.callout.monospaced())
            Spacer()
            Text("\(value)").font(.title3.monospaced().bold())
        }
        .frame(maxWidth: 260)
    }
}

// MARK: - Crafting

struct CraftingSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "🛠️ Crafting") {
            HStack {
                Text("🔩 ×\(game.inventory.count(of: "scrapmetal"))")
                Text("⛓️ ×\(game.inventory.count(of: "iron"))")
            }
            .font(.callout.monospaced())

            let craftable = game.craftableRecipes
            if craftable.isEmpty {
                ContentUnavailableView("Nothing craftable", systemImage: "hammer",
                                       description: Text("Collect more scrap metal — break down weapons with a grindstone."))
            } else {
                Text("You can make:").font(.callout.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(craftable, id: \.self) { recipeID in
                            ItemRow(
                                id: recipeID,
                                count: 1,
                                detail: recipeDetail(recipeID),
                                actionLabel: "Craft",
                                action: { game.craft(recipeID) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func recipeDetail(_ recipeID: String) -> String {
        (game.data.recipes[recipeID] ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.value)× \(ItemCatalog.emoji($0.key))" }
            .joined(separator: " + ")
    }
}

// MARK: - Breakdown

struct BreakdownSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "🪨 Breakdown") {
            if !game.hasGrindstone {
                ContentUnavailableView("You do not have a grindstone!", systemImage: "circle.slash",
                                       description: Text("The trader sometimes sells one... for a price."))
            } else if game.breakdownCandidates.isEmpty {
                ContentUnavailableView("No weapons to break down", systemImage: "tray")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(game.breakdownCandidates, id: \.id) { weapon in
                            ItemRow(
                                id: weapon.id,
                                count: weapon.count,
                                detail: yieldText(weapon.id),
                                actionLabel: "Grind",
                                actionDisabled: game.data.breakdown[weapon.id] == nil,
                                action: { game.breakdown(weapon.id) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func yieldText(_ weaponID: String) -> String {
        if let yield = game.data.breakdown[weaponID] { return "→ \(yield)× 🔩" }
        return "not breakable"
    }
}

// MARK: - Equip

struct EquipSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "🪖 Equip Armour") {
            if game.ownedArmourItems.isEmpty {
                ContentUnavailableView("No armour owned", systemImage: "shield.slash",
                                       description: Text("Craft a scrap helmet or boots from scrap metal."))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(game.ownedArmourItems, id: \.id) { piece in
                            ItemRow(
                                id: piece.id,
                                count: piece.count,
                                detail: slotText(piece.id),
                                actionLabel: "Equip",
                                action: { game.equip(piece.id) }
                            )
                        }
                    }
                }
                Text("Damage reduction now: \(game.player.armour.reductionPercent)%")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slotText(_ armourID: String) -> String {
        if let value = game.data.stats.armourHead[armourID] { return "head +\(value)" }
        if let value = game.data.stats.armourChest[armourID] { return "chest +\(value)" }
        if let value = game.data.stats.armourFeet[armourID] { return "legs +\(value)" }
        return ""
    }
}

// MARK: - Drop (with confirmation)

struct DropSheet: View {
    @EnvironmentObject private var game: GameState
    @State private var confirming: String?

    var body: some View {
        SheetScaffold(title: "🗑️ Drop Item") {
            if game.inventory.isEmpty {
                ContentUnavailableView("Inventory is empty", systemImage: "tray")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(game.inventory.allItems, id: \.id) { item in
                            ItemRow(id: item.id, count: item.count,
                                    actionLabel: "Drop",
                                    action: { confirming = item.id })
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Drop one \(ItemCatalog.name(confirming ?? ""))?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let itemID = confirming {
                Button("Drop it", role: .destructive) {
                    game.drop(itemID)
                    confirming = nil
                }
                Button("Keep it", role: .cancel) { confirming = nil }
            }
        }
    }
}

// MARK: - Use

struct UseSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "🍽️ Use Item") {
            let usable = game.inventory.items(in: .consumable) + game.inventory.items(in: .health)
            if usable.isEmpty {
                ContentUnavailableView("Nothing usable", systemImage: "fork.knife",
                                       description: Text("Loot rooms for food, drink and medical supplies."))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(usable, id: \.id) { item in
                            ItemRow(id: item.id, count: item.count,
                                    detail: effectText(item.id),
                                    actionLabel: "Use",
                                    action: { game.use(item.id) })
                        }
                    }
                }
            }
        }
    }

    private func effectText(_ itemID: String) -> String {
        let stats = game.data.stats
        if let gains = stats.maxhealth[itemID], let low = gains.first, let high = gains.last {
            return "max ❤️ +\(low)–\(high)"
        }
        if let gains = stats.currenthealth[itemID], let low = gains.first, let high = gains.last {
            return "❤️ +\(low)–\(high)"
        }
        if let hunger = stats.hunger[itemID], let thirst = stats.thirst[itemID],
           let hungerLow = hunger.first, let hungerHigh = hunger.last,
           let thirstLow = thirst.first, let thirstHigh = thirst.last {
            return "🍗 +\(hungerLow)–\(hungerHigh)  🚰 +\(thirstLow)–\(thirstHigh)"
        }
        return ""
    }
}

// MARK: - Save / Load

struct SaveLoadSheet: View {
    @EnvironmentObject private var game: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingOverwrite: Int?

    var body: some View {
        SheetScaffold(title: "💾 Save / Load") {
            ForEach(GameState.saveSlots, id: \.self) { slot in
                HStack {
                    VStack(alignment: .leading) {
                        Text("Slot \(slot)").font(.callout.monospaced().bold())
                        Text(slotSubtitle(slot))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save") {
                        if game.hasSave(slot: slot) {
                            confirmingOverwrite = slot
                        } else {
                            game.saveGame(slot: slot)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Button("Load") {
                        if game.loadGame(slot: slot) { dismiss() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!game.hasSave(slot: slot))
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .confirmationDialog(
            "Overwrite the save in slot \(confirmingOverwrite ?? 0)?",
            isPresented: Binding(get: { confirmingOverwrite != nil }, set: { if !$0 { confirmingOverwrite = nil } }),
            titleVisibility: .visible
        ) {
            if let slot = confirmingOverwrite {
                Button("Overwrite", role: .destructive) {
                    game.saveGame(slot: slot)
                    confirmingOverwrite = nil
                }
                Button("Cancel", role: .cancel) { confirmingOverwrite = nil }
            }
        }
    }

    private func slotSubtitle(_ slot: Int) -> String {
        if let date = game.savedAt(slot: slot) {
            return "Saved \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Empty"
    }
}

// MARK: - Help

struct HelpSheet: View {
    var body: some View {
        SheetScaffold(title: "❓ Help") {
            ScrollView {
                Text("""
                You are LOST in an endless house. Pick a 🚪 door to move on.

                🔍 Loot — search each room once. Fewer doors = better luck.
                🍽️ Use — eat 🍅, drink 💧, heal 🩹. Hunger and thirst tick \
                down as you wander; hit zero and you die.
                ⚔️ Fight — enemies are easy 🧟 (100hp), medium 👹 (150hp) or \
                hard 🐉 (250hp). The 🔦 torch can scare them off (25%).
                🏃 Run — escaping can cost you a few hits.
                🛠️ Craft — 5×🔩 → 🪖 helmet, 3×🔩 → 👢 boots, 5×🔩 → ⛓️ iron.
                🪨 Breakdown — with a grindstone, grind weapons into 🔩.
                🪖 Equip — armour reduces damage by its average percent.
                🧙 Trader — buys appear rarely; shop, and gamble at 50/50 or H/L.
                💾 Save — from any normal room.

                Good luck. You'll need it.
                """)
                .font(.callout.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Hidden admin / debug panel

struct DebugSheet: View {
    @EnvironmentObject private var game: GameState
    @State private var itemID = ""
    @State private var moneyText = ""

    var body: some View {
        SheetScaffold(title: "🛠️ Admin") {
            HStack {
                TextField("item id (e.g. sword)", text: $itemID)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { game.adminAdd(itemID) }
                    .buttonStyle(.bordered)
                    .disabled(itemID.isEmpty)
                Button("Remove") { game.adminRemove(itemID) }
                    .buttonStyle(.bordered)
                    .disabled(itemID.isEmpty)
            }
            HStack {
                TextField("money", text: $moneyText)
                    .textFieldStyle(.roundedBorder)
                Button("Set £") {
                    if let amount = Int(moneyText) { game.adminSetMoney(amount) }
                }
                .buttonStyle(.bordered)
                .disabled(Int(moneyText) == nil)
            }
            Text("Known ids: \(ItemCatalog.all.keys.sorted().joined(separator: ", "))")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
