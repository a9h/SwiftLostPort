import Foundation

public extension GameState {

    /// Applies a room modifier's on-entry effect (B3). Trap and flooded can be
    /// lethal and trigger the normal game-over flow; dark has no entry effect
    /// (it gates looting instead).
    internal func applyRoomEntryEffects() {
        switch roomModifier {
        case .none:
            break

        case .dark:
            say("🌑 It's pitch black in here — you'll need a light to search.", .info)

        case .trap:
            // Depth-scaled (past the threshold), armour-reduced spike/collapse damage.
            let multiplier = 1.0 + Double(Balance.Depth.effectiveDepth(depth)) * Balance.Depth.damageRampPerRoom
            let scaled = Enemy.scale(Balance.RoomModifiers.trapDamageRange, by: multiplier)
            let raw = rng.int(in: scaled)
            let damage = player.armour.reducedDamage(raw)
            player.currentHealth -= damage
            let flavour = rng.choice([
                "The floor gives way — spikes!",
                "The floor gives way — a collapse!",
                "A tripwire snaps and darts whistle out!",
            ])
            say("⚠️ \(flavour) You take \(damage) damage.", .warning)
            if player.currentHealth <= 0 {
                gameOver("A trap room got the better of you")
            }

        case .flooded:
            // Boots negate flooded damage by tier (Part 3c): iron/steel keep you
            // bone dry, leather/scrap only soften it. Environmental damage is
            // NOT armour-reduced — the boot tier is the only mitigation.
            if player.armour.isFloodImmune {
                say("🌊 You wade through the flood — your boots keep you bone dry.", .info)
            } else {
                let base = rng.int(in: Balance.RoomModifiers.floodedDamageRange)
                let damage = max(1, Int((Double(base) * (1.0 - player.armour.floodReduction)).rounded()))
                player.currentHealth -= damage
                if player.armour.floodReduction > 0 {
                    say("🌊 Cold water seeps past your boots for \(damage) damage. Could've been worse.", .warning)
                } else {
                    say("🌊 Freezing water soaks you for \(damage) damage. At least it's wet.", .warning)
                }
                if player.currentHealth <= 0 {
                    gameOver("You went under in a flooded room")
                }
            }
        }
    }
}
