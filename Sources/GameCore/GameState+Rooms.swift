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
            say("🌑 \(flavour(.darkRoom))", .info)

        case .trap:
            // Depth-scaled (past the threshold), armour-reduced spike/collapse damage.
            let multiplier = 1.0 + Double(Balance.Depth.effectiveDepth(depth)) * Balance.Depth.damageRampPerRoom
            let scaled = Enemy.scale(Balance.RoomModifiers.trapDamageRange, by: multiplier)
            let raw = rng.int(in: scaled)
            let damage = player.armour.reducedDamage(raw)
            player.currentHealth -= damage
            runStats.damageTaken += damage
            say("⚠️ \(flavour(.trapRoom, ["damage": "\(damage)"]))", .warning)
            wearArmour() // Part 2b: trap-room damage wears armour too.
            if player.currentHealth <= 0 {
                gameOver("A trap room got the better of you")
            }

        case .flooded:
            // Boots negate flooded damage by tier: iron/steel keep you bone dry,
            // leather/scrap only soften it. Environmental damage is NOT armour-
            // reduced — the boot tier is the only mitigation. When boots help at
            // all, they wear 1 durability (Part 2b).
            let hasBoots = player.armour.legs != nil
            let bootsNote = !hasBoots ? "would've come in handy"
                : (player.armour.isFloodImmune ? "keep your feet dry" : "take the hit")
            if player.armour.isFloodImmune {
                say("🌊 \(flavour(.floodedRoom, ["bootsNote": bootsNote]))", .info)
                wearArmourSlot(.legs)
            } else {
                let base = rng.int(in: Balance.RoomModifiers.floodedDamageRange)
                let damage = max(1, Int((Double(base) * (1.0 - player.armour.floodReduction)).rounded()))
                player.currentHealth -= damage
                runStats.damageTaken += damage
                say("🌊 \(flavour(.floodedRoom, ["bootsNote": bootsNote]))", .warning)
                if hasBoots { wearArmourSlot(.legs) }
                if player.currentHealth <= 0 {
                    gameOver("You went under in a flooded room")
                }
            }
        }
    }
}
