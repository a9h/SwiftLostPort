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
            // Depth-scaled, armour-reduced spike/collapse damage.
            let multiplier = 1.0 + Double(depth) * Balance.Depth.damagePerDepth
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
            // Boots (any legs armour) keep you dry; otherwise environmental,
            // NON-armour-reduced water damage and a thirst note.
            if player.armour.legs > 0 {
                say("🌊 You wade through the flood — good thing you have boots.", .info)
            } else {
                let damage = rng.int(in: Balance.RoomModifiers.floodedDamageRange)
                player.currentHealth -= damage
                say("🌊 Freezing water soaks you for \(damage) damage. At least it's wet.", .warning)
                if player.currentHealth <= 0 {
                    gameOver("You went under in a flooded room")
                }
            }
        }
    }
}
