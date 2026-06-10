import Foundation

public extension GameState {

    /// Rolls poison application after an enemy lands a hit. Easy enemies never
    /// poison; medium/hard/boss roll their tier chance. Only consumes RNG when
    /// there's a non-zero chance, so easy-enemy combat stays deterministic.
    internal func rollPoison(from enemy: Enemy) {
        let chance: Int
        if enemy.isBoss {
            chance = Balance.Poison.bossChancePercent
        } else {
            switch enemy.difficulty {
            case .hard: chance = Balance.Poison.hardChancePercent
            case .medium: chance = Balance.Poison.mediumChancePercent
            case .easy: chance = 0
            }
        }
        guard chance > 0, rng.int(in: 1...100) <= chance else { return }
        applyPoison()
    }

    /// Applies (or refreshes) poison to its full duration.
    internal func applyPoison() {
        if let idx = player.statusEffects.firstIndex(where: { $0.kind == .poison }) {
            player.statusEffects[idx].remaining = Balance.Poison.duration
        } else {
            player.statusEffects.append(StatusEffect(kind: .poison, remaining: Balance.Poison.duration))
        }
        say("☠️ You've been poisoned! It will sap your health for the next few rooms.", .warning)
    }

    /// Ticks status effects on room entry. Poison deals flat damage that is
    /// NOT armour-reduced. Returns false if the tick was fatal (caller should
    /// stop generating the room — the game-over flow has already fired).
    @discardableResult
    internal func tickStatusEffects() -> Bool {
        guard !player.statusEffects.isEmpty else { return true }

        if let idx = player.statusEffects.firstIndex(where: { $0.kind == .poison }) {
            player.currentHealth -= Balance.Poison.damagePerRoom
            player.statusEffects[idx].remaining -= 1
            if player.statusEffects[idx].remaining <= 0 {
                player.statusEffects.remove(at: idx)
                say("The poison finally works its way out of your system.", .info)
            } else {
                say("☠️ The poison burns — you lose \(Balance.Poison.damagePerRoom) health.", .warning)
            }
            if player.currentHealth <= 0 {
                gameOver("The poison finished you off")
                return false
            }
        }
        return true
    }
}
