import SwiftUI
import GameCore

/// Enemy encounter: RUN / FIGHT / USE (plus inventory, health, drop),
/// and the weapon picker once a fight starts.
struct EncounterView: View {
    @EnvironmentObject private var game: GameState
    @Binding var sheet: ActiveSheet?
    @State private var shake = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            if let enemy = game.enemy {
                VStack(spacing: 8) {
                    if let boss = enemy.boss {
                        // Boss banner: decoration line + name, max-damage marker.
                        Text(game.maxDamageFlag ? "💀 \(boss.decoration) 💀" : boss.decoration)
                            .font(.system(size: 40))
                            .offset(x: shake ? -10 : 0)
                            .animation(.spring(duration: 0.18, bounce: 0.7), value: shake)
                        Text(boss.displayName)
                            .font(.system(.title2, design: .monospaced).bold())
                            .foregroundStyle(.purple)
                        if game.maxDamageFlag {
                            Text("💀 MAX DAMAGE 💀")
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text(enemy.emoji)
                            .font(.system(size: 96))
                            .offset(x: shake ? -10 : 0)
                            .animation(.spring(duration: 0.18, bounce: 0.7), value: shake)
                        Text("The enemy is \(enemy.displayName)")
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundStyle(difficultyColor(enemy.difficulty))
                    }

                    // Enemy HP bar
                    VStack(spacing: 2) {
                        StatBar(emoji: "💢", value: max(enemy.hp, 0), max: enemy.maxHP,
                                tint: enemy.isBoss ? .purple : difficultyColor(enemy.difficulty),
                                label: "\(max(enemy.hp, 0))/\(enemy.maxHP)")
                    }
                    .frame(maxWidth: 320)
                }
                .onChange(of: enemy.hp) { shake.toggle() }
            }

            Spacer(minLength: 0)

            if game.encounterPhase == .fighting {
                weaponPicker
            } else {
                encounterActions
            }
        }
    }

    private var encounterActions: some View {
        let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ActionButton("Run", "🏃", prominent: true) { game.run() }
            ActionButton("Fight", "⚔️", prominent: true) { game.beginFight() }
            ActionButton("Use", "🍽️") { sheet = .use }
            ActionButton("Inventory", "🎒") { sheet = .inventory }
            ActionButton("Health", "❤️") { sheet = .stats }
            ActionButton("Drop", "🗑️") { sheet = .drop }
        }
    }

    private var weaponPicker: some View {
        VStack(spacing: 8) {
            Text("Pick a weapon — the enemy strikes back after every swing!")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(game.ownedWeapons, id: \.id) { weapon in
                    Button {
                        game.attack(with: weapon.id)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(ItemCatalog.emoji(weapon.id)) \(ItemCatalog.name(weapon.id))")
                                .font(.callout.monospaced())
                            Text(weaponSubtitle(weapon.id, count: weapon.count))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }

            Button {
                game.stopFighting()
            } label: {
                Text("Back").font(.callout.monospaced())
            }
            .buttonStyle(.bordered)
        }
    }

    /// Torch shows its scare odds; other weapons show the freshest instance's
    /// remaining durability (the one a swing will use).
    private func weaponSubtitle(_ weaponID: String, count: Int) -> String {
        if weaponID == "torch" { return "25% scare ×\(count)" }
        let lvl = game.inventory.upgradeLevel(of: weaponID)
        let prefix = lvl > 0 ? "+\(lvl) " : ""
        if let best = game.inventory.instances(of: weaponID).first,
           let d = best.durability, let m = best.maxDurability {
            return count > 1 ? "\(prefix)\(d)/\(m) ×\(count)" : "\(prefix)\(d)/\(m)"
        }
        return "×\(count)"
    }

    private func difficultyColor(_ difficulty: Difficulty) -> Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}
