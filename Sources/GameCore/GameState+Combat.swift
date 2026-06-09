import Foundation

public extension GameState {

    /// Weapons the player currently owns (what the fight UI offers).
    var ownedWeapons: [(id: String, count: Int)] {
        inventory.items(in: .weapon)
    }

    internal func startEncounter() {
        // Difficulty is rolled once on first sight and persists.
        let difficulty = Difficulty.roll(using: &rng)
        enemy = Enemy(difficulty: difficulty)
        encounterPhase = .choosing
        screen = .encounter
        say("Uh Oh, you have come across an enemy! You can RUN, FIGHT or USE an item.", .narration)
        say("The enemy is \(difficulty.rawValue) with \(difficulty.maxHP) health \(difficulty.emoji)", .combat)
    }

    /// One armour-reduced enemy hit. Returns the damage dealt to the player.
    private func enemyHitsPlayer() -> Int {
        guard let enemy else { return 0 }
        let raw = rng.int(in: enemy.difficulty.damageRange)
        let damage = player.armour.reducedDamage(raw)
        player.currentHealth -= damage
        return damage
    }

    /// RUN: keep rolling escape attempts; every roll under 30 costs an
    /// armour-reduced hit, then you slip away to a new room.
    func run() {
        guard screen == .encounter, enemy != nil else { return }
        while rng.int(in: 1...100) < 30 {
            let damage = enemyHitsPlayer()
            say("You failed to escape and took \(damage) damage!", .combat)
            if player.currentHealth <= 0 {
                gameOver("The enemy caught you as you tried to escape")
                return
            }
        }
        say("You escaped to another room! 🏃", .narration)
        previousEncounter = true
        generateRoom()
    }

    /// FIGHT: with no weapons you take one free hit and the fight is over.
    func beginFight() {
        guard screen == .encounter, enemy != nil else { return }
        if ownedWeapons.isEmpty {
            let damage = enemyHitsPlayer()
            say("You don't have any weapons to attack with, and lost \(damage) health", .combat)
            if player.currentHealth <= 0 {
                gameOver("You were beaten by the enemy, unarmed")
            } else {
                encounterPhase = .choosing
            }
            return
        }
        encounterPhase = .fighting
        say("Choose a weapon to attack with!", .combat)
    }

    /// One round of combat: your hit, then (if it survives) the enemy's.
    func attack(with weaponID: String) {
        guard screen == .encounter, enemy != nil else { return }

        // Faithful to the original: naming a weapon you don't own means you
        // "spent too long looking" and eat a hit. (The UI only offers owned
        // weapons, so normally unreachable.)
        guard inventory.has(weaponID) else {
            let damage = enemyHitsPlayer()
            say("You spent too long looking for a weapon you don't have, and the enemy hit you for \(damage)!", .combat)
            checkCombatDeath()
            return
        }

        if weaponID == "torch" {
            // Special: 25% chance to scare the enemy off (consumes the torch);
            // otherwise nothing happens and the enemy gets its hit in.
            if rng.int(in: 1...100) < 25 {
                inventory.remove("torch")
                say("You waved your torch and scared the enemy off! 🔥", .reward)
                enemy = nil
                previousEncounter = true
                generateRoom()
                return
            }
            say("The enemy did not care about your torch", .combat)
        } else if let damages = data.weapons[weaponID], !damages.isEmpty {
            let damage = rng.choice(damages)
            enemy?.hp -= damage
            say("You hit the enemy with your \(ItemCatalog.label(weaponID)) for \(damage) damage!", .combat)
        }

        if let enemy, enemy.hp <= 0 {
            let coins = rng.int(in: enemy.difficulty.coinRange)
            player.money += coins
            say("You killed the enemy and ran to another room, and looted £\(coins) 💷", .reward)
            self.enemy = nil
            previousEncounter = true
            generateRoom()
            return
        }

        let damage = enemyHitsPlayer()
        say("The enemy hit you back for \(damage) — you have \(player.currentHealth) health remaining", .combat)
        checkCombatDeath()
    }

    /// Back out of the weapon picker to RUN/FIGHT/USE (UI convenience;
    /// the enemy doesn't get a free hit for hesitating).
    func stopFighting() {
        guard screen == .encounter else { return }
        encounterPhase = .choosing
    }

    private func checkCombatDeath() {
        if player.currentHealth <= 0 {
            gameOver("You were killed by the enemy")
        }
    }
}
