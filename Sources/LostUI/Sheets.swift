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

    /// e.g. "+2 24/30" per instance ("∞" for the torch).
    private func durabilityDetail(_ weaponID: String) -> String {
        let parts = game.inventory.instances(of: weaponID).map { inst -> String in
            let lvl = inst.upgradeLevel > 0 ? "+\(inst.upgradeLevel) " : ""
            if let d = inst.durability, let m = inst.maxDurability { return "\(lvl)\(d)/\(m)" }
            return "\(lvl)∞"
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        SheetScaffold(title: "🎒 Inventory") {
            TabbedPanel(tabs: ItemCategory.displayOrder.map { cat in
                TabbedPanel.Tab(id: cat.rawValue, label: "\(cat.emoji) \(cat.displayName)") {
                    TabItemList(items: game.inventory.itemsByQuantity(in: cat),
                                emptyText: "No \(cat.displayName.lowercased()) yet.") { id, count in
                        ItemRow(id: id, count: count,
                                detail: cat == .weapon ? durabilityDetail(id) : nil)
                    }
                }
            })
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
                statLine("🚪 Rooms Explored", "\(game.roomsExplored)")
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
                ForEach(ArmourSlot.allCases) { slot in
                    armourLine(slot)
                }
                Divider()
                Text("Your armour reduces incoming damage by ~\(game.player.armour.reductionPercent)%")
                    .font(.callout.monospaced().bold())
                    .foregroundStyle(.green)
                Text("(diminishing returns — approaches but never reaches 85%)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("Upgrade pieces at the 🛠️ Workbench. 🦺 Chest is your damage backbone, 🪖 head resists poison, 👢 boots fend off floods.")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
            )
        }
    }

    private func armourLine(_ slot: ArmourSlot) -> some View {
        let armour = game.player.armour
        let material = armour.material(in: slot)
        return VStack(spacing: 2) {
            HStack {
                Text(material.map { ItemCatalog.emoji(ArmourCatalog.id(slot: slot, material: $0)) } ?? slot.emoji)
                    .font(.title)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.displayName).font(.callout.monospaced())
                    Text(specialisation(slot, material))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(material.map { "\($0.displayName) (\(armour.value(in: slot)))" } ?? "—")
                    .font(.callout.monospaced().bold())
            }
        }
        .frame(maxWidth: 300)
    }

    /// The slot-specialisation summary line (Part 3c).
    private func specialisation(_ slot: ArmourSlot, _ material: ArmourMaterial?) -> String {
        guard let material else { return "empty" }
        switch slot {
        case .head:
            return "\(Balance.Armour.poisonResistPercent[material] ?? 0)% poison resist"
        case .chest:
            return "primary damage reducer"
        case .legs:
            let r = Balance.Armour.floodReduction[material] ?? 0
            return r >= 1.0 ? "immune to flooding" : "\(Int(r * 100))% flood protection"
        }
    }
}

// MARK: - Workbench (Part 2: Craft + Upgrade + Breakdown, one tabbed menu)

/// The combined metalworking menu. Reachable from an owned grindstone (room),
/// or free at either trader — all three open this same sheet and call the same
/// shared functions. Three tabs via the Part 1 tabbed component.
struct WorkbenchSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "🛠️ Workbench") {
            HStack(spacing: 12) {
                Text("🔩 ×\(game.inventory.count(of: "scrapmetal"))")
                Text("⛓️ ×\(game.inventory.count(of: "iron"))")
                Text("🧱 ×\(game.inventory.count(of: "ironBar"))")
            }
            .font(.callout.monospaced())

            TabbedPanel(tabs: [
                TabbedPanel.Tab(id: "craft", label: "🛠️ Craft") { craftTab },
                TabbedPanel.Tab(id: "upgrade", label: "🪒 Upgrade") { upgradeTab },
                TabbedPanel.Tab(id: "breakdown", label: "🪨 Breakdown") { breakdownTab },
            ])
        }
    }

    // MARK: Craft

    private var craftTab: some View {
        let craftable = game.craftableRecipes
        return Group {
            if craftable.isEmpty {
                QuietPlaceholder(text: "Nothing craftable yet — gather more materials.")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        Text("You can make:").font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(craftable, id: \.self) { recipeID in
                            ItemRow(id: recipeID, count: 1,
                                    detail: recipeDetail(recipeID),
                                    actionLabel: "Craft",
                                    action: { game.craft(recipeID) })
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

    // MARK: Upgrade (weapon convert + sharpen + armour tiers + hardened blade)

    private var upgradeTab: some View {
        ScrollView {
            VStack(spacing: 8) {
                sectionHeader("Convert a weapon")
                let convertible = game.weaponConversions.filter { game.inventory.has($0.source) }
                if convertible.isEmpty {
                    quietLine("Nothing to convert.")
                }
                ForEach(convertible, id: \.source) { recipe in
                    ItemRow(id: recipe.source, count: game.inventory.count(of: recipe.source),
                            detail: "+\(recipe.cost)× 🔩 → \(ItemCatalog.label(recipe.result))",
                            actionLabel: "Convert",
                            actionDisabled: !game.canConvertWeapon(recipe.source),
                            action: { game.convertWeapon(recipe.source) })
                }

                Divider().padding(.vertical, 2)
                sectionHeader("Sharpen for +\(GameCore.Balance.Grindstone.upgradeDamageBonus) damage (\(GameCore.Balance.Grindstone.upgradeCost)× 🔩 each)")
                if game.upgradeableWeapons.isEmpty {
                    quietLine("No upgradeable weapons.")
                }
                ForEach(game.upgradeableWeapons, id: \.id) { weapon in
                    let level = game.inventory.upgradeLevel(of: weapon.id)
                    let cap = GameCore.Balance.Grindstone.cap(for: weapon.id)
                    ItemRow(id: weapon.id, count: weapon.count,
                            detail: "+\(level)/\(cap)",
                            actionLabel: level >= cap ? "Maxed" : "Sharpen",
                            actionDisabled: !game.canUpgradeWeaponDamage(weapon.id),
                            action: { game.upgradeWeaponDamage(weapon.id) })
                }

                Divider().padding(.vertical, 2)
                sectionHeader("Reforge armour to the next tier")
                if game.upgradeableArmourSlots.isEmpty {
                    quietLine("No armour to upgrade — equip a piece first.")
                }
                ForEach(game.upgradeableArmourSlots) { slot in
                    armourUpgradeRow(slot)
                }

                Divider().padding(.vertical, 2)
                sectionHeader("Harden a blade (1× 🧱 → +50% durability)")
                if game.hardenableWeapons.isEmpty {
                    quietLine("No hardenable weapons.")
                }
                ForEach(game.hardenableWeapons, id: \.id) { weapon in
                    ItemRow(id: weapon.id, count: weapon.count,
                            detail: "max \(game.inventory.activeMaxDurability(of: weapon.id) ?? 0)",
                            actionLabel: "Harden",
                            actionDisabled: !game.canHardenBlade(weapon.id),
                            action: { game.hardenBlade(weapon.id) })
                }
            }
        }
    }

    private func armourUpgradeRow(_ slot: ArmourSlot) -> some View {
        let current = game.player.armour.material(in: slot)
        let next = current?.next
        let cost = next.flatMap { Balance.Armour.upgradeCost(to: $0) }
        let nextID = next.map { ArmourCatalog.id(slot: slot, material: $0) } ?? ""
        let currentID = current.map { ArmourCatalog.id(slot: slot, material: $0) } ?? ""
        return ItemRow(
            id: currentID,
            count: 1,
            detail: cost.map { "+\($0.count)× \(ItemCatalog.emoji($0.ingredient)) → \(ItemCatalog.label(nextID))" },
            actionLabel: "Reforge",
            actionDisabled: !game.canUpgradeArmour(slot),
            action: { game.upgradeArmour(slot) }
        )
    }

    // MARK: Breakdown

    private var breakdownTab: some View {
        Group {
            if game.breakdownCandidates.isEmpty {
                QuietPlaceholder(text: "No weapons to break down.")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(game.breakdownCandidates, id: \.id) { weapon in
                            ItemRow(id: weapon.id, count: weapon.count,
                                    detail: yieldText(weapon.id),
                                    actionLabel: "Grind",
                                    actionDisabled: game.data.breakdown[weapon.id] == nil,
                                    action: { game.breakdown(weapon.id) })
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.callout.monospaced().bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func quietLine(_ text: String) -> some View {
        Text(text).font(.caption.monospaced()).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Equip

struct EquipSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        SheetScaffold(title: "🪖 Equip Armour") {
            if game.ownedArmourItems.isEmpty {
                ContentUnavailableView("No armour owned", systemImage: "shield.slash",
                                       description: Text("Craft a scrap helmet, chestplate or boots at the Workbench."))
            } else {
                TabItemList(items: game.inventory.itemsByQuantity(in: .armor),
                            emptyText: "No armour owned.") { id, count in
                    ItemRow(id: id, count: count,
                            detail: slotText(id),
                            actionLabel: "Equip",
                            action: { game.equip(id) })
                }
                Text("Damage reduction now: \(game.player.armour.reductionPercent)%")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slotText(_ armourID: String) -> String {
        guard let info = ArmourCatalog.info(armourID) else { return "" }
        return "\(info.slot.displayName.lowercased()) +\(Balance.Armour.baseValue(info.material, slot: info.slot))"
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

    /// Only the categories whose items actually do something when used.
    private let usableCategories: [ItemCategory] = [.consumable, .health]

    var body: some View {
        SheetScaffold(title: "🍽️ Use Item") {
            TabbedPanel(tabs: usableCategories.map { cat in
                TabbedPanel.Tab(id: cat.rawValue, label: "\(cat.emoji) \(cat.displayName)") {
                    TabItemList(items: game.inventory.itemsByQuantity(in: cat),
                                emptyText: "No \(cat.displayName.lowercased()) to use.") { id, count in
                        ItemRow(id: id, count: count,
                                detail: effectText(id),
                                actionLabel: "Use",
                                action: { game.use(id) })
                    }
                }
            })
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
                down as you wander; hit zero and you die. ☠️ Poison saps health \
                each room for a while.
                ⚔️ Fight — enemies grow tougher the deeper you go (after ~60 \
                rooms). The 🔦 torch can scare most foes off (25%).
                👹 Bosses — every 50 depth (≈100 rooms) a named boss gates the \
                way: 🤠 Cowboy dodges, 👻 Ghoul poisons, 🧙 Plague Doctor heals, \
                🗡️ Warlord hits twice & ignores torches, 🐺 Packmaster summons.
                🏃 Run — escaping can cost you a few hits.
                🛠️ Workbench — one menu, three tabs: CRAFT (armour, 🩹 bandages, \
                🧰 medkits, 🧱 iron bars, 🔦 torches), UPGRADE (convert/sharpen \
                weapons, reforge armour a tier, harden a blade) and BREAKDOWN \
                (grind weapons into 🔩). Carry a 🪨 grindstone to use it in a \
                room, or use it free at any trader.
                🪖 Equip — one piece per slot, upgraded at the Workbench. 🦺 chest \
                is your damage backbone, 🪖 head resists poison, 👢 boots fend \
                off floods. Reduction has diminishing returns.
                🧙 Trader — a merchant sells; a 🪤 scavenger buys your loot. \
                Both gamble at 50/50 or H/L, and both open the Workbench free.
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

