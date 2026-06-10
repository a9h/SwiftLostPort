import XCTest
@testable import GameCore

final class GameCoreTests: XCTestCase {

    /// GameState with scripted randomness and no disk access.
    private func makeGame(script: [Int]) -> GameState {
        GameState(data: .load(), rng: ScriptedGameRandom(script), saveStore: MemorySaveStore())
    }

    /// Puts the game into a plain Kitchen room with the given door count,
    /// consuming a known script prefix:
    /// decay-roll(no decay), traderRarity(no), encounterChance(no),
    /// room(choice 4 = Kitchen, rooms sorted), doors, modifier-roll(100 = none).
    private func startInRoom(doors: Int, thenScript rest: [Int]) -> GameState {
        // Pick Kitchen by its index in the sorted room list (robust to new rooms).
        let kitchenIndex = GameData.load().roomNames.firstIndex(of: "Kitchen")!
        let prefix = [50, 100, 100, kitchenIndex, doors, 100]
        let game = makeGame(script: prefix + rest)
        game.startNewGame()
        XCTAssertEqual(game.screen, .room)
        XCTAssertEqual(game.roomName, "Kitchen")
        XCTAssertEqual(game.doors, doors)
        return game
    }

    // MARK: - Armour / combat damage (A1: diminishing-returns soft cap)

    func testArmourReductionCurveHitsExpectedPoints() {
        // pct = 0.85 * raw / (raw + 120)
        XCTAssertEqual(Armour(head: 20, chest: 0, legs: 0).reductionPercent, 12)   // ~12%
        XCTAssertEqual(Armour(head: 20, chest: 25, legs: 15).reductionPercent, 28) // raw 60 -> ~28%
        XCTAssertEqual(Armour(head: 80, chest: 80, legs: 80).reductionPercent, 57) // raw 240 -> ~57%
    }

    func testArmourReductionNeverReaches85Percent() {
        // Even at absurd armour totals the fraction stays strictly below the ceiling.
        for raw in [0, 100, 1_000, 100_000] {
            let armour = Armour(head: raw, chest: 0, legs: 0)
            XCTAssertLessThan(armour.reductionFraction, Balance.Armour.ceiling)
        }
    }

    func testArmourIsMonotonicAndNeverInvertsOrHeals() {
        var lastReduction = -1.0
        var lastDamage = Int.max
        for raw in stride(from: 0, through: 600, by: 20) {
            let armour = Armour(head: raw, chest: 0, legs: 0)
            // More armour never reduces less (monotonic) and never exceeds ceiling.
            XCTAssertGreaterThanOrEqual(armour.reductionFraction, lastReduction)
            lastReduction = armour.reductionFraction
            // A 100-damage hit is always >= 1, never negative, never increasing health,
            // and never more than the raw damage.
            let final = armour.reducedDamage(100)
            XCTAssertGreaterThanOrEqual(final, 1)
            XCTAssertLessThanOrEqual(final, 100)
            XCTAssertLessThanOrEqual(final, lastDamage) // more armour -> less or equal damage
            lastDamage = final
        }
    }

    func testArmourFlatComponentAndFloor() {
        // No armour: only the flat 2 is removed.
        XCTAssertEqual(Armour().reducedDamage(10), 8)
        // Tiny hits never drop below 1 even after the flat reduction.
        XCTAssertEqual(Armour().reducedDamage(2), 1)
        XCTAssertEqual(Armour().reducedDamage(1), 1)
        // raw 60 armour (28%) on a 50 hit: afterFlat 48 * (1-0.2833) = ~34.
        XCTAssertEqual(Armour(head: 20, chest: 25, legs: 15).reducedDamage(50), 34)
    }

    func testEnemyDifficultyRollBrackets() {
        var rng: GameRandom = ScriptedGameRandom([24, 25, 125, 126, 200, 1])
        XCTAssertEqual(Difficulty.roll(using: &rng), .hard)    // <25
        XCTAssertEqual(Difficulty.roll(using: &rng), .medium)  // 25
        XCTAssertEqual(Difficulty.roll(using: &rng), .medium)  // 125
        XCTAssertEqual(Difficulty.roll(using: &rng), .easy)    // >125
        XCTAssertEqual(Difficulty.roll(using: &rng), .easy)
        XCTAssertEqual(Difficulty.roll(using: &rng), .hard)
    }

    // MARK: - Depth : room ratio (1:2)

    func testDepthIsHalfRoomsExplored() {
        // Walk a handful of rooms and confirm depth == roomsExplored / 2.
        let game = startInRoom(doors: 1, thenScript: []) // room 1, depth 0
        XCTAssertEqual(game.roomsExplored, 1)
        XCTAssertEqual(game.depth, 0)
        // Step through several plain rooms.
        let expected: [(rooms: Int, depth: Int)] = [(2, 1), (3, 1), (4, 2)]
        for step in expected {
            game.rng = ScriptedGameRandom([50, 100, 100, 0, 1, 100]) // plain room, no modifier
            game.takeDoor(1)
            XCTAssertEqual(game.roomsExplored, step.rooms)
            XCTAssertEqual(game.depth, step.depth, "rooms \(step.rooms)")
        }
        // Spot-check the arithmetic directly at higher counts.
        XCTAssertEqual(60 / 2, 30)   // scaling starts: depth 30 = 60 rooms
        XCTAssertEqual(100 / 2, 50)  // first boss: depth 50 = 100 rooms
        XCTAssertEqual(200 / 2, 100) // depth 100 = 200 rooms
    }

    // MARK: - Combat rebalance (Part 2: weapon/enemy damage + weighted HP)

    func testWeaponDamageArraysUseNewRanges() {
        let data = GameData.load()
        XCTAssertEqual(data.weapons["branch"]?.first, 12);    XCTAssertEqual(data.weapons["branch"]?.last, 22)
        XCTAssertEqual(data.weapons["fork"]?.first, 22);      XCTAssertEqual(data.weapons["fork"]?.last, 32)
        XCTAssertEqual(data.weapons["bat"]?.first, 30);       XCTAssertEqual(data.weapons["bat"]?.last, 42)
        XCTAssertEqual(data.weapons["shovel"]?.first, 28);    XCTAssertEqual(data.weapons["shovel"]?.last, 45)
        XCTAssertEqual(data.weapons["crowbar"]?.first, 35);   XCTAssertEqual(data.weapons["crowbar"]?.last, 50)
        XCTAssertEqual(data.weapons["knife"]?.first, 40);     XCTAssertEqual(data.weapons["knife"]?.last, 55)
        XCTAssertEqual(data.weapons["sword"]?.first, 58);     XCTAssertEqual(data.weapons["sword"]?.last, 75)
        XCTAssertEqual(data.weapons["longsword"]?.first, 80); XCTAssertEqual(data.weapons["longsword"]?.last, 100)
    }

    func testEnemyDamageRangesUseNewValues() {
        var rng: GameRandom = ScriptedGameRandom([0])
        XCTAssertEqual(Enemy.make(difficulty: .easy, depth: 0, isBoss: false, using: &rng).damageRange, 3...12)
        rng = ScriptedGameRandom([0])
        XCTAssertEqual(Enemy.make(difficulty: .medium, depth: 0, isBoss: false, using: &rng).damageRange, 15...35)
        rng = ScriptedGameRandom([0])
        XCTAssertEqual(Enemy.make(difficulty: .hard, depth: 0, isBoss: false, using: &rng).damageRange, 28...55)
    }

    func testWeightedEnemyHPBiasesLowEarlyHighLate() {
        // Depth 0 sits at the low end (plus jitter).
        XCTAssertEqual(Balance.EnemyCombat.rolledHP(for: .easy, depth: 0, jitterRoll: 0), 75)
        XCTAssertEqual(Balance.EnemyCombat.rolledHP(for: .hard, depth: 0, jitterRoll: 0), 155)
        XCTAssertEqual(Balance.EnemyCombat.rolledHP(for: .easy, depth: 0, jitterRoll: 15), 90)
        // At/after the cap the roll reaches the high end and stays clamped.
        XCTAssertEqual(Balance.EnemyCombat.rolledHP(for: .easy, depth: 150, jitterRoll: 0), 115)
        XCTAssertEqual(Balance.EnemyCombat.rolledHP(for: .hard, depth: 150, jitterRoll: 0), 200)
        XCTAssertEqual(Balance.EnemyCombat.rolledHP(for: .hard, depth: 300, jitterRoll: 0), 200)
        // Mid depth lands between, biased low (quadratic weight).
        let mid = Balance.EnemyCombat.rolledHP(for: .hard, depth: 75, jitterRoll: 0) // weight .5 -> t .25
        XCTAssertEqual(mid, 166) // 155 + floor(0.25*45)
        XCTAssertGreaterThanOrEqual(mid, 155)
        XCTAssertLessThan(mid, 200)
    }

    // MARK: - Boss system (Part 3)

    func testBossStatBlocksAndSequenceOrder() {
        XCTAssertEqual(BossKind.allCases.map(\.self), [.cowboy, .ghoul, .plagueDoctor, .warlord, .packmaster])
        XCTAssertEqual(Enemy.makeBoss(.cowboy, maxDamage: false).maxHP, 360)
        XCTAssertEqual(Enemy.makeBoss(.cowboy, maxDamage: false).damageRange, 18...28)
        XCTAssertEqual(Enemy.makeBoss(.ghoul, maxDamage: false).maxHP, 320)
        XCTAssertEqual(Enemy.makeBoss(.plagueDoctor, maxDamage: false).maxHP, 340)
        XCTAssertEqual(Enemy.makeBoss(.warlord, maxDamage: false).maxHP, 380)
        XCTAssertEqual(Enemy.makeBoss(.warlord, maxDamage: false).damageRange, 12...20)
        XCTAssertEqual(Enemy.makeBoss(.packmaster, maxDamage: false).maxHP, 340)
    }

    func testMaxDamageCollapsesBossRangeToTop() {
        XCTAssertEqual(Enemy.makeBoss(.cowboy, maxDamage: true).damageRange, 28...28)
        XCTAssertEqual(Enemy.makeBoss(.warlord, maxDamage: true).damageRange, 20...20)
    }

    func testBossGateSpawnsCowboyAtDepth50() {
        // depth 50 = room 100. Boss spawns regardless of the previous flag.
        let game = startInRoom(doors: 1, thenScript: [])
        game.roomsExplored = 99
        game.previousEncounter = true
        game.rng = ScriptedGameRandom([50, 100, 100]) // decay/trader/encounter ignored for boss
        game.takeDoor(1)
        XCTAssertEqual(game.depth, 50)
        XCTAssertEqual(game.screen, .encounter)
        XCTAssertEqual(game.enemy?.boss, .cowboy)
    }

    func testBossDefeatAdvancesSequenceWrapsAndArmsMaxDamage() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("sword")
        game.bossSequenceIndex = 4 // Packmaster is next; defeating it wraps to 0
        game.nextBossDepth = 50
        game.maxDamageFlag = false
        game.startBossEncounter(.packmaster)
        game.enemy?.hp = 1
        game.beginFight()
        // summon 100(none), sword idx0=58 (kills), coins 130, drop idx0=steak,
        // then a plain next room.
        game.rng = ScriptedGameRandom([100, 0, 130, 0, 50, 100, 100, 0, 1, 100])
        game.attack(with: "sword")
        XCTAssertEqual(game.bossSequenceIndex, 0)
        XCTAssertEqual(game.nextBossDepth, 100)
        XCTAssertTrue(game.maxDamageFlag) // wrapped a full cycle
        XCTAssertTrue(game.inventory.has("steak")) // packmaster drop
        XCTAssertEqual(game.player.money, 50 + 130)
    }

    func testCowboyDodge() {
        // Dodge (roll < 50): the swing misses, no damage.
        let dodged = startInRoom(doors: 1, thenScript: [])
        dodged.inventory.add("sword")
        dodged.startBossEncounter(.cowboy)
        dodged.beginFight()
        dodged.rng = ScriptedGameRandom([10, 18]) // dodge 10, counter raw 18
        dodged.attack(with: "sword")
        XCTAssertEqual(dodged.enemy?.hp, 360)
        XCTAssertEqual(dodged.player.currentHealth, 100 - 16) // 18 -> 16 after flat

        // No dodge (roll >= 50): the hit lands.
        let hit = startInRoom(doors: 1, thenScript: [])
        hit.inventory.add("sword")
        hit.startBossEncounter(.cowboy)
        hit.beginFight()
        hit.rng = ScriptedGameRandom([50, 0, 18]) // no dodge, sword idx0=58, counter 18
        hit.attack(with: "sword")
        XCTAssertEqual(hit.enemy?.hp, 360 - 58)
    }

    func testPlagueDoctorHealsOnceBelowHalf() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("longsword")
        game.startBossEncounter(.plagueDoctor)
        game.enemy?.hp = 175 // just above half (170)
        game.beginFight()
        // sword idx0=80 -> 95 (<170, heals 40 -> 135); counter 20.
        game.rng = ScriptedGameRandom([0, 40, 20])
        game.attack(with: "longsword")
        XCTAssertEqual(game.enemy?.hp, 135)
        XCTAssertEqual(game.enemy?.hasHealed, true)
        // Below half again: no second heal.
        game.enemy?.hp = 160
        game.rng = ScriptedGameRandom([0, 20]) // sword idx0=80, counter 20
        game.attack(with: "longsword")
        XCTAssertEqual(game.enemy?.hp, 80)
    }

    func testWarlordHitsTwiceAndIsTorchImmune() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("torch")
        game.startBossEncounter(.warlord)
        game.beginFight()
        game.rng = ScriptedGameRandom([12, 20]) // two warlord hits, raw 12 and 20
        game.attack(with: "torch")
        XCTAssertEqual(game.enemy?.hp, 380) // torch did nothing
        XCTAssertTrue(game.inventory.has("torch")) // immune -> not scared/consumed
        XCTAssertEqual(game.player.currentHealth, 100 - 10 - 18) // two armour-reduced hits
    }

    func testPackmasterSummonDealsExtraDamage() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife")
        game.startBossEncounter(.packmaster)
        game.beginFight()
        // summon 5(<=20 yes), summonHP 35, summon dmg 10->8; knife idx0=40;
        // counter 15 -> 13.
        game.rng = ScriptedGameRandom([5, 35, 10, 0, 15])
        game.attack(with: "knife")
        XCTAssertEqual(game.enemy?.hp, 340 - 40)
        XCTAssertEqual(game.player.currentHealth, 100 - 8 - 13)
    }

    func testCombatRoundDealsWeaponDamageAndArmourReducedCounterhit() {
        // Room first, then: encounter difficulty roll, weapon damage choice,
        // enemy counter-hit raw damage.
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife")
        game.player.armour = Armour(head: 30, chest: 30, legs: 30) // raw 90 -> ~36% reduction
        game.depth = 0 // isolate from depth scaling

        // Force an encounter: difficulty roll 150 -> easy; jitter 0 -> HP 75.
        game.rng = ScriptedGameRandom([150, 0])
        game.startEncounter()
        XCTAssertEqual(game.enemy?.difficulty, .easy)
        XCTAssertEqual(game.enemy?.hp, 75)

        // Attack: knife damage index 5 -> damages[5] = 45; counter-hit raw 12
        // (easy 3–12). afterFlat 10 * (1 - 0.85*90/210) = 10 * 0.6357 = ~6.
        game.rng = ScriptedGameRandom([5, 12])
        game.beginFight()
        game.attack(with: "knife")
        XCTAssertEqual(game.enemy?.hp, 75 - 45)
        XCTAssertEqual(game.player.currentHealth, 100 - 6)
    }

    func testKillingEnemyAwardsCoinsInDifficultyRange() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("longsword")
        game.depth = 0 // isolate from depth scaling

        game.rng = ScriptedGameRandom([150, 0]) // easy, jitter 0 -> HP 75
        game.startEncounter()
        // longsword damage index 0 -> 80 (kills the 75-HP enemy), coins roll 30
        // (easy 10...30), then a normal next room: decay 50, trader 100,
        // encounter 100, room 0, doors 2, modifier 100 (none).
        game.rng = ScriptedGameRandom([0, 30, 50, 100, 100, 0, 2, 100])
        game.beginFight()
        game.attack(with: "longsword")
        XCTAssertNil(game.enemy)
        XCTAssertEqual(game.player.money, 50 + 30)
        XCTAssertEqual(game.screen, .room)
    }

    func testFightWithNoWeaponsCostsOneArmouredHit() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.depth = 0 // isolate from depth scaling
        game.rng = ScriptedGameRandom([150]) // easy
        game.startEncounter()
        game.rng = ScriptedGameRandom([10]) // raw hit 10 -> 8 after the flat-2 component
        game.beginFight()
        XCTAssertEqual(game.player.currentHealth, 92)
        XCTAssertEqual(game.encounterPhase, .choosing) // fight ended
    }

    // MARK: - Weapon durability (B2)

    func testWeaponDurabilityDecrementsPerHitAndBreaks() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.depth = 0
        game.inventory.add("branch") // durability 8
        XCTAssertEqual(game.inventory.instances(of: "branch").first?.durability, 8)

        game.rng = ScriptedGameRandom([150, 0]) // easy enemy
        game.startEncounter()
        game.enemy?.hp = 1000 // make it tanky so it survives all 8 swings
        game.beginFight()

        // Branch index 0 (=12) each swing so it never kills, with a tiny
        // counter-hit. 8 swings should break the branch (durability 8).
        for hit in 1...8 {
            game.rng = ScriptedGameRandom([0, 2]) // weapon dmg idx 0, counter raw 2
            game.attack(with: "branch")
            if hit < 8 {
                XCTAssertEqual(game.inventory.instances(of: "branch").first?.durability, 8 - hit)
            }
        }
        XCTAssertFalse(game.inventory.has("branch")) // broke on the 8th hit
    }

    func testTwoWeaponsWearIndependently() {
        var inv = Inventory()
        inv.add("sword") // two swords, durability 30 each
        inv.add("sword")
        XCTAssertEqual(inv.count(of: "sword"), 2)
        // Wear one down — degradeWeapon hits the most-worn instance.
        for _ in 0..<5 { _ = inv.degradeWeapon("sword") }
        let durabilities = inv.instances(of: "sword").compactMap { $0.durability }.sorted()
        XCTAssertEqual(durabilities, [25, 30]) // one worn, one pristine
    }

    func testLastWeaponBreakingReturnsToChoosing() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.depth = 0
        // A branch with 1 durability left.
        game.inventory.add("branch")
        for _ in 0..<7 { _ = game.inventory.degradeWeapon("branch") } // now 1 left
        game.rng = ScriptedGameRandom([150]) // easy
        game.startEncounter()
        game.beginFight()
        game.rng = ScriptedGameRandom([0, 2]) // hit (enemy survives), branch breaks
        game.attack(with: "branch")
        XCTAssertFalse(game.inventory.has("branch"))
        XCTAssertEqual(game.encounterPhase, .choosing) // fell back to the menu
    }

    // MARK: - Status effects / poison (B2)

    func testPoisonAppliesTicksAndWearsOff() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.applyPoison()
        XCTAssertEqual(game.player.poisonRemaining, 3)

        let startHealth = game.player.currentHealth
        // Walk three rooms; each entry ticks 5 poison damage then wears off.
        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 100]) // no decay/trader/enemy
        game.takeDoor(1)
        XCTAssertEqual(game.player.currentHealth, startHealth - 5)
        XCTAssertEqual(game.player.poisonRemaining, 2)

        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 100])
        game.takeDoor(1)
        XCTAssertEqual(game.player.poisonRemaining, 1)

        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 100])
        game.takeDoor(1)
        XCTAssertEqual(game.player.currentHealth, startHealth - 15)
        XCTAssertFalse(game.player.isPoisoned) // worn off

        // A fourth room deals no further poison damage.
        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 100])
        game.takeDoor(1)
        XCTAssertEqual(game.player.currentHealth, startHealth - 15)
    }

    func testPoisonRefreshesDuration() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.applyPoison()
        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 100])
        game.takeDoor(1)
        XCTAssertEqual(game.player.poisonRemaining, 2)
        game.applyPoison() // refresh back to full
        XCTAssertEqual(game.player.poisonRemaining, 3)
    }

    func testPoisonCanKill() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.currentHealth = 4 // less than one poison tick
        game.applyPoison()
        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 100])
        game.takeDoor(1)
        XCTAssertEqual(game.screen, .gameOver(reason: "The poison finished you off", money: game.player.money))
    }

    func testEasyEnemyNeverPoisons() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.depth = 0
        game.rng = ScriptedGameRandom([150]) // easy
        game.startEncounter()
        // Easy enemy: rollPoison must consume no RNG and never poison. Verify
        // by giving a no-weapon hit and checking no poison stuck.
        game.rng = ScriptedGameRandom([10])
        game.beginFight() // takes one hit
        XCTAssertFalse(game.player.isPoisoned)
    }

    // MARK: - Room modifiers (B3)

    func testRoomModifierRollThresholds() {
        XCTAssertEqual(RoomModifier.roll(1), .trap)
        XCTAssertEqual(RoomModifier.roll(12), .trap)
        XCTAssertEqual(RoomModifier.roll(13), .dark)
        XCTAssertEqual(RoomModifier.roll(24), .dark)
        XCTAssertEqual(RoomModifier.roll(25), .flooded)
        XCTAssertEqual(RoomModifier.roll(34), .flooded)
        XCTAssertEqual(RoomModifier.roll(35), .none)
        XCTAssertEqual(RoomModifier.roll(100), .none)
    }

    func testTunnelDarkBiasWidensDarkBand() {
        // With the Tunnel bonus, values that would be flooded/none become dark.
        let bonus = Balance.RoomModifiers.tunnelDarkBonus
        XCTAssertEqual(RoomModifier.roll(40, darkBonus: bonus), .dark) // 40 <= 12+12+38
        XCTAssertEqual(RoomModifier.roll(50, darkBonus: bonus), .dark)
        // Trap chance is unchanged by the bonus.
        XCTAssertEqual(RoomModifier.roll(12, darkBonus: bonus), .trap)
        // Without the bonus, 40 is a normal room.
        XCTAssertEqual(RoomModifier.roll(40), .none)
    }

    // MARK: - Loot door luck (rebalance 2d: verify, not rewrite)

    func testLootDoorLuckRangesAndThreshold() {
        // Confirmed: success when lucky < 33, and fewer doors = a wider (less
        // lucky) range. Here we verify the shared <33 threshold per door count
        // by scripting the boundary value and a known item/no-money roll.
        for doors in 1...3 {
            // lucky 32 -> success, item index 0, key 75 -> no money, flavour 0.
            let win = startInRoom(doors: doors, thenScript: [32, 0, 75, 0])
            win.loot()
            XCTAssertEqual(win.inventory.totalItemCount, 1, "doors \(doors): 32 should succeed")

            // lucky 33 -> failure, nothing gained.
            let lose = startInRoom(doors: doors, thenScript: [33])
            lose.loot()
            XCTAssertTrue(lose.inventory.isEmpty, "doors \(doors): 33 should fail")
        }
    }

    func testTrapRoomDealsArmourReducedDamageOnEntry() {
        // Enter a trap room: decay 50, trader 100, encounter 100, room 4,
        // doors 1, modifier 1 (trap), trap damage roll 25.
        let game = makeGame(script: [50, 100, 100, 4, 1, 1, 25])
        game.startNewGame()
        XCTAssertEqual(game.roomModifier, .trap)
        // depth 1: trap range 10...25 * 1.03 -> 10...26, roll 25 clamped within;
        // no armour -> afterFlat 23 -> 23 damage.
        XCTAssertEqual(game.player.currentHealth, 100 - 23)
    }

    func testDarkRoomBlocksLootingWithoutTorch() {
        // modifier 13 -> dark.
        let game = makeGame(script: [50, 100, 100, 4, 1, 13])
        game.startNewGame()
        XCTAssertEqual(game.roomModifier, .dark)
        game.loot() // no torch -> blocked, no roll consumed
        XCTAssertFalse(game.hasLooted)
        XCTAssertTrue(game.inventory.isEmpty)

        // With a torch the loot proceeds (lucky 10, item 0, key 75 -> no money).
        game.inventory.add("torch")
        game.rng = ScriptedGameRandom([10, 0, 75, 0])
        game.loot()
        XCTAssertTrue(game.hasLooted)
        XCTAssertTrue(game.inventory.has("torch")) // torch not consumed
        XCTAssertEqual(game.inventory.totalItemCount, 2) // torch + looted item
    }

    func testFloodedRoomDamagesWhenNoBoots() {
        // modifier 25 -> flooded, water damage roll 15.
        let game = makeGame(script: [50, 100, 100, 4, 1, 25, 15])
        game.startNewGame()
        XCTAssertEqual(game.roomModifier, .flooded)
        XCTAssertEqual(game.player.currentHealth, 100 - 15) // not armour-reduced
    }

    func testFloodedRoomSafeWithBoots() {
        // Pre-place the player with leg armour, then enter a flooded room.
        // Use startInRoom then verify by re-entering. Simplest: set legs and
        // build the flooded room directly.
        let game = makeGame(script: [50, 100, 100, 4, 1, 25, 15])
        game.startNewGame() // takes 15 with no boots
        XCTAssertEqual(game.player.currentHealth, 85)
        // Now give boots and walk into another flooded room.
        game.player.armour.legs = 15
        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 25, 15])
        game.takeDoor(1)
        XCTAssertEqual(game.roomModifier, .flooded)
        XCTAssertEqual(game.player.currentHealth, 85) // unchanged — boots kept it dry
    }

    // MARK: - Hunger / thirst decay

    func testDecayHappensWhenRollAboveFifty() {
        // decay roll 51 -> decay; hunger -7, thirst -3; no trader/enemy; room 4; doors 1
        let game = makeGame(script: [51, 7, 3, 100, 100, 4, 1, 100])
        game.startNewGame()
        XCTAssertEqual(game.player.hunger, 93)
        XCTAssertEqual(game.player.thirst, 97)
    }

    func testNoDecayWhenRollFiftyOrBelow() {
        let game = makeGame(script: [50, 100, 100, 4, 1, 100])
        game.startNewGame()
        XCTAssertEqual(game.player.hunger, 100)
        XCTAssertEqual(game.player.thirst, 100)
    }

    func testRunningOutOfHungerKillsYou() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.hunger = 5
        // Next room: decay roll 60 -> hunger -10 => dead before anything else.
        game.rng = ScriptedGameRandom([60, 10, 1])
        game.takeDoor(1)
        XCTAssertEqual(game.screen, .gameOver(reason: "You ran out of hunger and died", money: 50))
    }

    // MARK: - Crafting deduction (original `=-` bug fixed)

    func testCraftingConsumesExactIngredients() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("scrapmetal", count: 7)
        XCTAssertTrue(game.craftableRecipes.contains("scrapHelmet"))
        game.craft("scrapHelmet")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 2) // 7 - 5 exactly
        XCTAssertEqual(game.inventory.count(of: "scrapHelmet"), 1)
    }

    func testCannotCraftWithoutIngredients() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("scrapmetal", count: 2)
        XCTAssertFalse(game.canCraft("scrapHelmet"))
        game.craft("scrapHelmet")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 2) // unchanged
        XCTAssertEqual(game.inventory.count(of: "scrapHelmet"), 0)
    }

    // MARK: - Loot money brackets

    func testLootBigMoneyBracket() {
        // lucky 10 (<33 success), item choice 0, key 125 -> money roll 33, flavour 0
        let game = startInRoom(doors: 1, thenScript: [10, 0, 125, 33, 0])
        let moneyBefore = game.player.money
        game.loot()
        XCTAssertEqual(game.player.money, moneyBefore + 33)
        XCTAssertEqual(game.inventory.totalItemCount, 1)
    }

    func testLootSmallMoneyBracket() {
        // key 49 -> small bracket, roll 20
        let game = startInRoom(doors: 1, thenScript: [10, 0, 49, 20, 0])
        let moneyBefore = game.player.money
        game.loot()
        XCTAssertEqual(game.player.money, moneyBefore + 20)
    }

    func testLootNoMoneyBracket() {
        // key 75 -> 50...100 means no money (and no money roll consumed: flavour gets 0)
        let game = startInRoom(doors: 1, thenScript: [10, 0, 75, 0])
        let moneyBefore = game.player.money
        game.loot()
        XCTAssertEqual(game.player.money, moneyBefore)
        XCTAssertEqual(game.inventory.totalItemCount, 1) // still found an item
    }

    func testLootOnlyOncePerRoom() {
        let game = startInRoom(doors: 1, thenScript: [10, 0, 75, 0])
        game.loot()
        XCTAssertEqual(game.inventory.totalItemCount, 1)
        game.loot()
        XCTAssertEqual(game.inventory.totalItemCount, 1) // nothing new
    }

    func testLootFailureGivesNothing() {
        let game = startInRoom(doors: 1, thenScript: [40]) // lucky 40 >= 33
        game.loot()
        XCTAssertTrue(game.inventory.isEmpty)
        XCTAssertEqual(game.player.money, 50)
    }

    // MARK: - Using items

    func testEatingCapsAtHundredAndConsumesItem() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("steak")
        game.player.hunger = 60
        game.player.thirst = 99
        // steak: hunger choice index 0 -> 60, thirst choice index 0 -> 5
        game.rng = ScriptedGameRandom([0, 0])
        game.use("steak")
        XCTAssertEqual(game.player.hunger, 100) // 60+60 capped
        XCTAssertEqual(game.player.thirst, 100) // 99+5 capped
        XCTAssertEqual(game.inventory.count(of: "steak"), 0)
    }

    func testHealingNeverOvershootsMaxHealth() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("medkit")
        game.player.currentHealth = 80
        game.rng = ScriptedGameRandom([10]) // medkit choice index 10 -> 50 heal
        game.use("medkit")
        XCTAssertEqual(game.player.currentHealth, 100) // only healed the 20 missing
    }

    func testUsingWeaponOutsideCombatDoesNothing() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife")
        game.use("knife")
        XCTAssertEqual(game.inventory.count(of: "knife"), 1) // not consumed
    }

    // MARK: - Breakdown

    func testBreakdownNeedsGrindstone() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("sword")
        game.breakdown("sword")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 0)
        game.inventory.add("grindstone")
        game.breakdown("sword")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 5)
        XCTAssertEqual(game.inventory.count(of: "sword"), 0)
    }

    func testTorchAndBranchCannotBeBrokenDown() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("grindstone")
        game.inventory.add("torch")
        game.inventory.add("branch")
        game.breakdown("torch")
        game.breakdown("branch")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 0)
        XCTAssertEqual(game.inventory.count(of: "torch"), 1)
        XCTAssertEqual(game.inventory.count(of: "branch"), 1)
    }

    // MARK: - Equip

    func testEquippingArmourAddsToSlotAndConsumesPiece() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("scrapHelmet")
        game.inventory.add("scrapBoots")
        game.equip("scrapHelmet")
        game.equip("scrapBoots")
        XCTAssertEqual(game.player.armour.head, 20)
        XCTAssertEqual(game.player.armour.legs, 15)
        XCTAssertEqual(game.player.armour.rawArmour, 35)
        XCTAssertEqual(game.player.armour.reductionPercent, 19) // 0.85*35/155 -> ~19%
        XCTAssertTrue(game.inventory.isEmpty)
    }

    // MARK: - Gambling

    func testCoinFlipWinPaysOneAndAHalfTimes() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.screen = .trader
        game.rng = ScriptedGameRandom([1]) // heads
        let result = game.playCoinFlip(choice: .heads, bet: 20)
        XCTAssertEqual(result?.won, true)
        XCTAssertEqual(game.player.money, 50 + 10) // net +bet/2
    }

    func testCoinFlipLossLosesBet() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.screen = .trader
        game.rng = ScriptedGameRandom([2]) // tails
        let result = game.playCoinFlip(choice: .heads, bet: 20)
        XCTAssertEqual(result?.won, false)
        XCTAssertEqual(game.player.money, 30)
    }

    func testCannotBetMoreThanYouHave() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.screen = .trader
        game.rng = ScriptedGameRandom([1])
        XCTAssertNil(game.playCoinFlip(choice: .heads, bet: 999))
        XCTAssertEqual(game.player.money, 50)
    }

    func testHigherLowerHintSharesSecretHalfAndPaysOut() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.screen = .trader
        // secret 80 (>50), hint roll 60 -> hint in 50...100; "higher" is correct.
        game.rng = ScriptedGameRandom([80, 60])
        XCTAssertTrue(game.startHigherLower(bet: 20))
        XCTAssertEqual(game.hlRound?.hint, 60)
        let result = game.guessHigherLower(.higher)
        XCTAssertEqual(result?.won, true)
        XCTAssertEqual(game.player.money, 60) // 50 + 10
    }

    func testHigherLowerExactGuessPaysEightTimes() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.screen = .trader
        game.rng = ScriptedGameRandom([42, 30]) // secret 42, hint 30
        game.startHigherLower(bet: 10)
        let result = game.guessHigherLower(.exact(42))
        XCTAssertEqual(result?.exact, true)
        XCTAssertEqual(game.player.money, 50 + 70) // net +7×bet
    }

    // MARK: - Trader stock & buying

    func testShopWeaponAppearsAndIsBuyable() {
        let game = startInRoom(doors: 1, thenScript: [])
        // loadShop: food choices 0,1 distinct; tool roll 50 (<100 -> grindstone, choice 0);
        // weapon roll 30 (>25 -> stocked, choice 0 -> longsword (sorted)).
        game.rng = ScriptedGameRandom([0, 1, 50, 0, 30, 0])
        game.startTrader()
        XCTAssertEqual(game.shopStock?.weapon, "longsword")
        // Can't afford £150 with £50 — insufficient-funds check applies to weapons too.
        game.buy("longsword")
        XCTAssertEqual(game.player.money, 50)
        XCTAssertEqual(game.inventory.count(of: "longsword"), 0)
        game.player.money = 200
        game.buy("longsword")
        XCTAssertEqual(game.player.money, 50)
        XCTAssertEqual(game.inventory.count(of: "longsword"), 1)
    }

    func testShopStocksTwoDistinctFoods() {
        let game = startInRoom(doors: 1, thenScript: [])
        // Food choices collide (0, 0) then resolve (1); tool roll, tool choice; weapon roll 10 (no weapon).
        game.rng = ScriptedGameRandom([0, 0, 1, 50, 0, 10])
        game.startTrader()
        let foods = game.shopStock?.foods ?? []
        XCTAssertEqual(foods.count, 2)
        XCTAssertEqual(Set(foods).count, 2)
        XCTAssertNil(game.shopStock?.weapon)
    }

    // MARK: - Save / load round trip

    func testSaveLoadRoundTrip() {
        let game = startInRoom(doors: 2, thenScript: [])
        game.inventory.add("knife", count: 2)
        game.inventory.add("scrapmetal", count: 4)
        game.player.money = 123
        game.player.armour.head = 20
        // New state: depth, boss sequence, a worn weapon, active poison.
        game.depth = 14
        game.nextBossDepth = 100
        game.bossSequenceIndex = 1
        game.maxDamageFlag = true
        _ = game.inventory.degradeWeapon("knife") // one knife now 14/15
        game.applyPoison()
        game.saveGame(slot: 1)

        game.startNewGame() // scripted RNG empty -> clamps; we only care it resets
        XCTAssertEqual(game.player.money, 50)
        XCTAssertEqual(game.roomsExplored, 1) // new run entered its first room
        XCTAssertEqual(game.depth, 0)          // depth 0 at room 1 (1:2 ratio)

        XCTAssertTrue(game.loadGame(slot: 1))
        XCTAssertEqual(game.player.money, 123)
        XCTAssertEqual(game.player.armour.head, 20)
        XCTAssertEqual(game.inventory.count(of: "knife"), 2)
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 4)
        XCTAssertEqual(game.roomName, "Kitchen")
        XCTAssertEqual(game.doors, 2)
        XCTAssertEqual(game.screen, .room)
        // New state restored intact.
        XCTAssertEqual(game.depth, 14)
        XCTAssertEqual(game.roomsExplored, 1)
        XCTAssertEqual(game.nextBossDepth, 100)
        XCTAssertEqual(game.bossSequenceIndex, 1)
        XCTAssertTrue(game.maxDamageFlag)
        XCTAssertEqual(game.player.poisonRemaining, 3)
        let durabilities = game.inventory.instances(of: "knife").compactMap { $0.durability }.sorted()
        XCTAssertEqual(durabilities, [14, 15]) // worn knife persisted
    }

    // MARK: - Encounter generation flags

    /// Randomized soak: play many rooms with arbitrary valid actions and
    /// real randomness — nothing should crash, hang, or corrupt state.
    func testRandomSoakRun() {
        for seed in 0..<20 {
            let game = GameState(data: .load(),
                                 rng: SeededGameRandom(seed: UInt64(seed)),
                                 saveStore: MemorySaveStore())
            game.startNewGame()
            var steps = 0
            loop: while steps < 400 {
                steps += 1
                switch game.screen {
                case .room:
                    game.loot()
                    if let food = game.inventory.items(in: .consumable).first { game.use(food.id) }
                    if game.canCraft("scrapHelmet") { game.craft("scrapHelmet") }
                    game.takeDoor(1)
                case .encounter:
                    if game.ownedWeapons.isEmpty || steps % 2 == 0 {
                        game.run()
                    } else {
                        game.beginFight()
                        if let weapon = game.ownedWeapons.first { game.attack(with: weapon.id) }
                    }
                case .trader:
                    if let stocked = game.shopStock?.allItemIDs.first { game.buy(stocked) }
                    game.playCoinFlip(choice: .heads, bet: min(5, game.player.money))
                    game.leaveTrader()
                case .gameOver:
                    break loop
                case .title:
                    XCTFail("Unexpected title screen mid-run")
                    break loop
                }
                XCTAssertLessThanOrEqual(game.player.hunger, 100)
                XCTAssertLessThanOrEqual(game.player.thirst, 100)
                XCTAssertLessThanOrEqual(game.player.currentHealth, game.player.maxHealth)
                XCTAssertGreaterThanOrEqual(game.player.money, 0)
            }
        }
    }

    func testPreviousEncounterBlocksBackToBackEnemies() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.previousEncounter = true
        // Next room: no decay (50), trader 100 (no), encounter 10 (<25 but blocked), room 4, doors 1
        game.rng = ScriptedGameRandom([50, 100, 10, 4, 1, 100])
        game.takeDoor(1)
        XCTAssertEqual(game.screen, .room)
        XCTAssertNil(game.enemy)
        // And the flag was consumed: the same rolls now would spawn an enemy.
        game.rng = ScriptedGameRandom([50, 100, 10, 150])
        game.takeDoor(1)
        XCTAssertEqual(game.screen, .encounter)
        XCTAssertNotNil(game.enemy)
    }
}
