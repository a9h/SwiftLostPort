import Foundation

public extension GameState {

    /// Weapons the player currently owns (what the fight UI offers).
    var ownedWeapons: [(id: String, count: Int)] {
        inventory.items(in: .weapon)
    }

    internal func startEncounter() {
        let difficulty = Difficulty.roll(roomsExplored: roomsExplored, using: &rng)
        let newEnemy = Enemy.make(difficulty: difficulty, depth: depth, isBoss: false, using: &rng)
        enemy = newEnemy
        runStats.enemiesFought += 1
        encounterPhase = .choosing
        screen = .encounter
        say(flavour(.enemyEncounter), .narration)
        say("The enemy is \(newEnemy.displayName) with \(newEnemy.maxHP) health \(newEnemy.emoji)", .combat)
    }

    /// A fixed-sequence boss at its milestone depth (Part 3).
    internal func startBossEncounter(_ kind: BossKind) {
        let boss = Enemy.makeBoss(kind, maxDamage: maxDamageFlag)
        enemy = boss
        runStats.enemiesFought += 1
        encounterPhase = .choosing
        screen = .encounter
        let prefix = maxDamageFlag ? "💀 " : ""
        say(kind.intro, .narration)
        say("\(prefix)\(kind.decoration)  —  \(kind.displayName), \(boss.maxHP) HP", .combat)
        if maxDamageFlag {
            say("Something is different this time… the air itself feels lethal.", .warning)
        }
    }

    /// One armour-reduced enemy hit. Returns the damage dealt to the player.
    /// A landed hit may also apply poison (B2 / the Ghoul's special).
    func enemyHitsPlayer() -> Int {
        guard let enemy else { return 0 }
        let raw = rng.int(in: enemy.damageRange)
        let damage = player.armour.reducedDamage(raw)
        player.currentHealth -= damage
        runStats.damageTaken += damage
        rollPoison(from: enemy)
        wearArmour() // Part 2b: every hit the player takes wears 1–2 slots.
        return damage
    }

    /// RUN: keep rolling escape attempts; every roll under 30 costs an
    /// armour-reduced hit, then you slip away to a new room.
    func run() {
        guard screen == .encounter, enemy != nil else { return }
        while rng.int(in: 1...100) < 30 {
            _ = enemyHitsPlayer() // applies the hit; flavour omits the number
            say(flavour(.escapeFailure), .combat)
            if player.currentHealth <= 0 {
                gameOver("The enemy caught you as you tried to escape")
                return
            }
        }
        say(flavour(.escapeSuccess), .narration)
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

    /// One round of combat: (boss pre-round special →) your hit → (specials →)
    /// the enemy's hit(s).
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

        // Packmaster summon rolls at the very start of the round.
        if enemy?.boss == .packmaster {
            rollPackmasterSummon()
            if player.currentHealth <= 0 { gameOver("The Packmaster's pack overwhelmed you"); return }
        }

        if weaponID == "torch" {
            // 25% scare. The Warlord shrugs it off; other bosses can be scared
            // (they simply leave — not defeated, so the gate re-spawns them).
            if enemy?.boss?.isTorchImmune == true {
                say("The Warlord bats the torch aside, unimpressed.", .combat)
            } else if rng.int(in: 1...100) < 25 {
                inventory.remove("torch")
                say("You waved your torch and scared the enemy off! 🔥", .reward)
                enemy = nil
                previousEncounter = true
                generateRoom()
                return
            } else {
                say("The enemy did not care about your torch", .combat)
            }
        } else if let damages = data.weapons[weaponID], !damages.isEmpty {
            // The Cowboy may dodge the swing entirely.
            if enemy?.boss == .cowboy && rng.int(in: 1...100) < Balance.Bosses.cowboyDodgePercent {
                say("The Cowboy sidesteps your swing!", .combat)
            } else {
                let damage = rng.choice(damages) + inventory.upgradeBonus(of: weaponID)
                enemy?.hp -= damage
                runStats.damageDealt += damage
                say(flavour(.playerHit, ["enemy": enemy?.displayName ?? "the enemy", "damage": "\(damage)"]), .combat)
                if inventory.degradeWeapon(weaponID) == true {
                    say("Your \(ItemCatalog.name(weaponID)) snapped and broke!", .warning)
                }
                rollPlagueDoctorHeal()
            }
        }

        if let enemy, enemy.hp <= 0 {
            defeatEnemy(enemy)
            return
        }

        enemyCounterAttack()
        if screen != .encounter { return } // died, or fight resolved

        // If the player's last weapon broke this round, return to the menu so
        // the no-weapon path applies next.
        if ownedWeapons.isEmpty {
            encounterPhase = .choosing
            say("You're out of weapons!", .warning)
        }
    }

    // MARK: - Enemy / boss counter-attacks

    /// The enemy's hit(s) back. The Warlord strikes twice per round.
    private func enemyCounterAttack() {
        guard let enemy else { return }
        if enemy.boss == .warlord {
            let d1 = enemyHitsPlayer()
            if player.currentHealth <= 0 {
                say("The Warlord's first blow lands for \(d1)…", .combat)
                checkCombatDeath()
                return
            }
            let d2 = enemyHitsPlayer()
            say("The Warlord strikes twice — \(d1) then \(d2)! You have \(player.currentHealth) health left", .combat)
        } else {
            let damage = enemyHitsPlayer()
            say(flavour(.playerTakesHit, ["damage": "\(damage)"]), .combat)
        }
        checkCombatDeath()
    }

    /// The Packmaster's 20% per-round summon: a weak creature that bites once
    /// (armour-reduced) then vanishes. Damage is fixed at max when post-cycle.
    private func rollPackmasterSummon() {
        guard rng.int(in: 1...100) <= Balance.Bosses.packmasterSummonPercent else { return }
        let summonHP = rng.int(in: Balance.Bosses.packmasterSummonHP) // flavour only
        let raw = maxDamageFlag
            ? Balance.Bosses.packmasterSummonDamage.upperBound
            : rng.int(in: Balance.Bosses.packmasterSummonDamage)
        let damage = player.armour.reducedDamage(raw)
        player.currentHealth -= damage
        runStats.damageTaken += damage
        say("The Packmaster lets out a howl — a \(summonHP)-HP creature lunges and bites for \(damage)!", .combat)
    }

    /// The Plague Doctor heals once, the first time it drops below 50% HP.
    private func rollPlagueDoctorHeal() {
        guard let e = enemy, e.boss == .plagueDoctor, !e.hasHealed, e.hp > 0,
              Double(e.hp) < Balance.Bosses.plagueDoctorHealFraction * Double(e.maxHP) else { return }
        let heal = rng.int(in: Balance.Bosses.plagueDoctorHealRange)
        enemy?.hp = min(e.maxHP, e.hp + heal)
        enemy?.hasHealed = true
        say("The Plague Doctor reaches into their coat and drinks a vial… their wounds close.", .warning)
    }

    // MARK: - Defeat & drops

    private func defeatEnemy(_ enemy: Enemy) {
        let coins = rng.int(in: enemy.coinRange)
        earn(coins)
        if let kind = enemy.boss {
            runStats.bossesDefeated += 1
            applyBossDrop(kind)
            say("You felled \(kind.displayName)! It dropped £\(coins) 💷", .reward)
            advanceBossSequence()
        } else {
            say("You killed the enemy and ran to another room, and looted £\(coins) 💷", .reward)
        }
        self.enemy = nil
        previousEncounter = true
        generateRoom()
    }

    private func applyBossDrop(_ kind: BossKind) {
        switch kind {
        case .cowboy:
            if rng.int(in: 1...100) <= 50 {
                let weapon = rng.int(in: 1...2) == 1 ? "sword" : "longsword"
                inventory.add(weapon)
                say("\(kind.displayName) dropped a \(ItemCatalog.label(weapon))!", .reward)
            }
        case .ghoul:
            inventory.add("medkit")
            say("\(kind.displayName) dropped a \(ItemCatalog.label("medkit"))!", .reward)
        case .plagueDoctor:
            inventory.add("medicine")
            inventory.add("pills")
            say("\(kind.displayName) dropped \(ItemCatalog.label("medicine")) and \(ItemCatalog.label("pills"))!", .reward)
        case .warlord:
            let armour = rng.int(in: 1...2) == 1 ? "ironHelmet" : "ironChestplate"
            inventory.add(armour)
            say("\(kind.displayName) dropped \(ItemCatalog.label(armour))!", .reward)
        case .packmaster:
            let drop = rng.choice(Balance.Bosses.packmasterDropPool)
            inventory.add(drop)
            say("\(kind.displayName) dropped \(ItemCatalog.label(drop))!", .reward)
        }
    }

    /// Advance to the next boss, wrapping the cycle and arming max-damage.
    private func advanceBossSequence() {
        bossSequenceIndex = (bossSequenceIndex + 1) % Balance.Bosses.sequenceCount
        nextBossDepth += Balance.Bosses.depthInterval
        if bossSequenceIndex == 0 {
            maxDamageFlag = true
            say("You've bested them all once… but something tells you they'll be back, and angrier.", .warning)
        }
    }

    /// Back out of the weapon picker to RUN/FIGHT/USE.
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
