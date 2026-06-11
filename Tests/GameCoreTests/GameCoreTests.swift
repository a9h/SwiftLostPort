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
        // pct = 0.85 * raw / (raw + 120). The curve is a pure function of rawArmour.
        XCTAssertEqual(Armour.reductionPercent(forRaw: 20), 12)   // ~12%
        XCTAssertEqual(Armour.reductionPercent(forRaw: 60), 28)   // raw 60 -> ~28%
        XCTAssertEqual(Armour.reductionPercent(forRaw: 240), 57)  // raw 240 -> ~57%
    }

    func testArmourReductionNeverReaches85Percent() {
        // Even at absurd armour totals the fraction stays strictly below the ceiling.
        for raw in [0, 100, 1_000, 100_000] {
            XCTAssertLessThan(Armour.reductionFraction(forRaw: raw), Balance.Armour.ceiling)
        }
    }

    func testArmourIsMonotonicAndNeverInvertsOrHeals() {
        var lastReduction = -1.0
        var lastDamage = Int.max
        for raw in stride(from: 0, through: 600, by: 20) {
            // More armour never reduces less (monotonic) and never exceeds ceiling.
            let reduction = Armour.reductionFraction(forRaw: raw)
            XCTAssertGreaterThanOrEqual(reduction, lastReduction)
            lastReduction = reduction
            // A 100-damage hit is always >= 1, never negative, never increasing health,
            // and never more than the raw damage.
            let final = Armour.reducedDamage(100, rawArmour: raw)
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
        XCTAssertEqual(Armour.reducedDamage(50, rawArmour: 60), 34)
    }

    // MARK: - Armour tiers, upgrades & slot specialisation (Part 3)

    func testArmourTierBaseValuesFeedRawArmour() {
        XCTAssertEqual(Balance.Armour.baseValue(.leather, slot: .head), 10)
        XCTAssertEqual(Balance.Armour.baseValue(.steel, slot: .chest), 52)
        XCTAssertEqual(Balance.Armour.baseValue(.iron, slot: .legs), 22)
        // rawArmour sums each slot's equipped tier value.
        let kit = Armour(head: .iron, chest: .iron, legs: .iron) // 30 + 38 + 22
        XCTAssertEqual(kit.rawArmour, 90)
        XCTAssertEqual(Armour(head: .scrap, chest: nil, legs: .scrap).rawArmour, 35) // 20 + 15
    }

    func testEquipSwapReturnsOldPieceAndUpgradeConsumesIt() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("scrapHelmet")
        game.equip("scrapHelmet")
        XCTAssertEqual(game.player.armour.head, ArmourMaterial.scrap)
        XCTAssertTrue(game.inventory.isEmpty)

        // Swapping in a different head piece returns the old one to the pack.
        game.inventory.add("ironHelmet")
        game.equip("ironHelmet")
        XCTAssertEqual(game.player.armour.head, ArmourMaterial.iron)
        XCTAssertEqual(game.inventory.count(of: "scrapHelmet"), 1) // old piece returned

        // Upgrading the equipped piece consumes it in place (no return) + materials.
        game.inventory.add("ironBar", count: 3)
        XCTAssertTrue(game.canUpgradeArmour(.head))
        game.upgradeArmour(.head)
        XCTAssertEqual(game.player.armour.head, ArmourMaterial.steel)
        XCTAssertEqual(game.inventory.count(of: "ironBar"), 0) // 3 - 3 exactly
        XCTAssertEqual(game.inventory.count(of: "ironHelmet"), 0) // consumed, not returned
    }

    func testArmourUpgradeCostsDeductCorrectIngredient() {
        let game = startInRoom(doors: 1, thenScript: [])
        // scrap -> iron costs 4 iron.
        game.inventory.add("scrapChestplate")
        game.equip("scrapChestplate")
        game.inventory.add("iron", count: 5)
        XCTAssertTrue(game.canUpgradeArmour(.chest))
        game.upgradeArmour(.chest)
        XCTAssertEqual(game.player.armour.chest, ArmourMaterial.iron)
        XCTAssertEqual(game.inventory.count(of: "iron"), 1) // 5 - 4
        // Not enough materials gates the upgrade.
        let poor = startInRoom(doors: 1, thenScript: [])
        poor.inventory.add("scrapBoots")
        poor.equip("scrapBoots")
        poor.inventory.add("iron", count: 1)
        XCTAssertFalse(poor.canUpgradeArmour(.legs))
        poor.upgradeArmour(.legs)
        XCTAssertEqual(poor.player.armour.legs, ArmourMaterial.scrap) // unchanged
        XCTAssertEqual(poor.inventory.count(of: "iron"), 1)
    }

    func testHelmetPoisonResistByTier() {
        XCTAssertEqual(Armour(head: .leather).poisonResistPercent, 10)
        XCTAssertEqual(Armour(head: .scrap).poisonResistPercent, 20)
        XCTAssertEqual(Armour(head: .iron).poisonResistPercent, 35)
        XCTAssertEqual(Armour(head: .steel).poisonResistPercent, 50)
        XCTAssertEqual(Armour().poisonResistPercent, 0)

        // In combat: a steel helmet resists the ghoul's poison on a winning roll.
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife")
        game.player.armour.head = .steel
        game.startBossEncounter(.ghoul)
        game.beginFight()
        // knife idx0=40; ghoul counter raw 20; poison chance roll 1 (<=50, lands);
        // resist roll 1 (<=50, resisted) -> no poison applied.
        game.rng = ScriptedGameRandom([0, 20, 1, 1])
        game.attack(with: "knife")
        XCTAssertFalse(game.player.isPoisoned)
    }

    func testBootTierFloodNegation() {
        XCTAssertTrue(Armour(legs: .iron).isFloodImmune)
        XCTAssertTrue(Armour(legs: .steel).isFloodImmune)
        XCTAssertFalse(Armour(legs: .leather).isFloodImmune)
        XCTAssertEqual(Armour(legs: .leather).floodReduction, 0.5)

        // Leather boots halve flood damage; iron boots negate it.
        let leather = makeGame(script: [50, 100, 100, 4, 1, 12, 15]) // flooded, base damage 15
        leather.startNewGame()
        leather.player.armour.legs = .leather
        // Re-enter a flooded room so the leather reduction applies.
        leather.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 12, 15])
        let before = leather.player.currentHealth
        leather.takeDoor(1)
        XCTAssertEqual(leather.roomModifier, .flooded)
        XCTAssertEqual(leather.player.currentHealth, before - 8) // round(15 * 0.5) = 8
    }

    func testArmourSaveMigrationFromOldSummedModel() throws {
        // A v3-style save with integer slot values migrates to nearest tiers.
        let json = """
        {"head": 30, "chest": 25, "legs": 0}
        """
        let armour = try JSONDecoder().decode(Armour.self, from: Data(json.utf8))
        XCTAssertEqual(armour.head, ArmourMaterial.iron)   // 30 == iron head base
        XCTAssertEqual(armour.chest, ArmourMaterial.scrap) // 25 == scrap chest base
        XCTAssertNil(armour.legs)                          // 0 -> empty slot
        // Round-trips back out as material tiers.
        let reencoded = try JSONEncoder().encode(armour)
        let again = try JSONDecoder().decode(Armour.self, from: reencoded)
        XCTAssertEqual(again.head, ArmourMaterial.iron)
        XCTAssertEqual(again.chest, ArmourMaterial.scrap)
        XCTAssertNil(again.legs)
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
        game.player.armour = Armour(head: .iron, chest: .iron, legs: .iron) // raw 90 -> ~36% reduction
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

    func testRoomModifierFrequencyByDepth() {
        // Early (depth < 50): trap 1-5, dark 6-10, flooded 11-14, else none.
        XCTAssertEqual(RoomModifier.roll(1, depth: 0), .trap)
        XCTAssertEqual(RoomModifier.roll(5, depth: 0), .trap)
        XCTAssertEqual(RoomModifier.roll(6, depth: 0), .dark)
        XCTAssertEqual(RoomModifier.roll(10, depth: 0), .dark)
        XCTAssertEqual(RoomModifier.roll(11, depth: 0), .flooded)
        XCTAssertEqual(RoomModifier.roll(14, depth: 0), .flooded)
        XCTAssertEqual(RoomModifier.roll(15, depth: 0), .none)
        XCTAssertEqual(RoomModifier.roll(100, depth: 0), .none)

        // Late (depth >= 50): trap 1-9, dark 10-17, flooded 18-24, else none.
        XCTAssertEqual(RoomModifier.roll(9, depth: 50), .trap)
        XCTAssertEqual(RoomModifier.roll(10, depth: 50), .dark)
        XCTAssertEqual(RoomModifier.roll(17, depth: 50), .dark)
        XCTAssertEqual(RoomModifier.roll(18, depth: 50), .flooded)
        XCTAssertEqual(RoomModifier.roll(24, depth: 50), .flooded)
        XCTAssertEqual(RoomModifier.roll(25, depth: 50), .none)
        // A value that's "none" early becomes a hazard late.
        XCTAssertEqual(RoomModifier.roll(16, depth: 0), .none)
        XCTAssertEqual(RoomModifier.roll(16, depth: 50), .dark)
    }

    func testTunnelDarkBiasWidensDarkBand() {
        // With the Tunnel bonus, values that would be flooded/none become dark.
        let bonus = Balance.RoomModifiers.tunnelDarkBonus
        // Early dark band is 6-10; the bonus widens it to 6-48.
        XCTAssertEqual(RoomModifier.roll(40, depth: 0, darkBonus: bonus), .dark)
        XCTAssertEqual(RoomModifier.roll(48, depth: 0, darkBonus: bonus), .dark)
        // Trap chance is unchanged by the bonus.
        XCTAssertEqual(RoomModifier.roll(5, depth: 0, darkBonus: bonus), .trap)
        // Without the bonus, 40 is a normal room.
        XCTAssertEqual(RoomModifier.roll(40, depth: 0), .none)
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
        // doors 1, modifier 1 (trap, early band), trap damage roll 25.
        let game = makeGame(script: [50, 100, 100, 4, 1, 1, 25])
        game.startNewGame()
        XCTAssertEqual(game.roomModifier, .trap)
        // depth 0 (room 1): no scaling. trap range 10...25, roll 25;
        // no armour -> afterFlat 23 -> 23 damage.
        XCTAssertEqual(game.player.currentHealth, 100 - 23)
    }

    func testDarkRoomBlocksLootingWithoutTorch() {
        // modifier 8 -> dark (early band 6-10).
        let game = makeGame(script: [50, 100, 100, 4, 1, 8])
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
        // modifier 12 -> flooded (early band 11-14), water damage roll 15.
        let game = makeGame(script: [50, 100, 100, 4, 1, 12, 15])
        game.startNewGame()
        XCTAssertEqual(game.roomModifier, .flooded)
        XCTAssertEqual(game.player.currentHealth, 100 - 15) // not armour-reduced
    }

    func testFloodedRoomSafeWithBoots() {
        // Enter a flooded room (modifier 12) with no boots, then with boots.
        let game = makeGame(script: [50, 100, 100, 4, 1, 12, 15])
        game.startNewGame() // takes 15 with no boots
        XCTAssertEqual(game.player.currentHealth, 85)
        // Now give iron boots (flood-immune) and walk into another flooded room.
        game.player.armour.legs = .iron
        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 12, 15])
        game.takeDoor(1)
        XCTAssertEqual(game.roomModifier, .flooded)
        XCTAssertEqual(game.player.currentHealth, 85) // unchanged — iron boots kept it dry
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
        game.inventory.add("rope", count: 6)
        XCTAssertTrue(game.craftableRecipes.contains("leatherCap"))
        game.craft("leatherCap") // 4 rope
        XCTAssertEqual(game.inventory.count(of: "rope"), 2) // 6 - 4 exactly
        XCTAssertEqual(game.inventory.count(of: "leatherCap"), 1)
    }

    func testCannotCraftWithoutIngredients() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("rope", count: 2)
        XCTAssertFalse(game.canCraft("leatherCap")) // needs 4
        game.craft("leatherCap")
        XCTAssertEqual(game.inventory.count(of: "rope"), 2) // unchanged
        XCTAssertEqual(game.inventory.count(of: "leatherCap"), 0)
    }

    // MARK: - Rope material + crafting chain (Part 1)

    func testRopeRecipeYieldsThreePerBranch() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("branch")
        XCTAssertTrue(game.canCraft("rope"))
        game.craft("rope")
        XCTAssertEqual(game.inventory.count(of: "rope"), 3) // 1 branch → 3 rope
        XCTAssertFalse(game.inventory.has("branch"))         // branch consumed
    }

    func testLeatherArmourRecipesDeductRope() {
        let cap = startInRoom(doors: 1, thenScript: [])
        cap.inventory.add("rope", count: 4)
        cap.craft("leatherCap")
        XCTAssertEqual(cap.inventory.count(of: "rope"), 0)
        XCTAssertEqual(cap.inventory.count(of: "leatherCap"), 1)

        let vest = startInRoom(doors: 1, thenScript: [])
        vest.inventory.add("rope", count: 6)
        vest.craft("leatherVest")
        XCTAssertEqual(vest.inventory.count(of: "rope"), 0)
        XCTAssertEqual(vest.inventory.count(of: "leatherVest"), 1)

        let boots = startInRoom(doors: 1, thenScript: [])
        boots.inventory.add("rope", count: 3)
        boots.craft("leatherBoots")
        XCTAssertEqual(boots.inventory.count(of: "rope"), 0)
        XCTAssertEqual(boots.inventory.count(of: "leatherBoots"), 1)
    }

    func testTorchRecipeUsesBranchAndRope() {
        let game = startInRoom(doors: 1, thenScript: [])
        // Torch now needs 1 branch + 1 rope (not scrapmetal).
        game.inventory.add("branch")
        game.inventory.add("scrapmetal")
        XCTAssertFalse(game.canCraft("torch")) // scrapmetal no longer counts
        game.inventory.add("rope")
        XCTAssertTrue(game.canCraft("torch"))
        game.craft("torch")
        XCTAssertEqual(game.inventory.count(of: "torch"), 1)
        XCTAssertFalse(game.inventory.has("branch"))
        XCTAssertFalse(game.inventory.has("rope"))
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 1) // untouched
    }

    func testIronBarRecipeDeductsCorrectly() {
        let bar = startInRoom(doors: 1, thenScript: [])
        bar.inventory.add("iron", count: 3)
        bar.inventory.add("scrapmetal", count: 2)
        XCTAssertTrue(bar.canCraft("ironBar"))
        bar.craft("ironBar")
        XCTAssertEqual(bar.inventory.count(of: "iron"), 0)
        XCTAssertEqual(bar.inventory.count(of: "scrapmetal"), 0)
        XCTAssertEqual(bar.inventory.count(of: "ironBar"), 1)
    }

    func testRemovedDirectArmourRecipesAreNotCraftable() {
        let game = startInRoom(doors: 1, thenScript: [])
        // Plenty of every material — still none of these craft (recipes gone).
        game.inventory.add("scrapmetal", count: 20)
        game.inventory.add("iron", count: 20)
        game.inventory.add("ironBar", count: 20)
        let armourPieces = ["scrapHelmet", "scrapChestplate", "scrapBoots",
                            "ironHelmet", "ironChestplate", "ironBoots",
                            "steelHelmet", "steelChestplate", "steelBoots"]
        for removed in armourPieces {
            XCTAssertNil(game.data.recipes[removed], "\(removed) recipe should be gone")
            XCTAssertFalse(game.canCraft(removed), "\(removed) should not be craftable")
            game.craft(removed) // no-op
            XCTAssertEqual(game.inventory.count(of: removed), 0, "\(removed) should not have been made")
        }
        // The raw-iron-from-scrap recipe is gone too (iron comes from loot now).
        XCTAssertNil(game.data.recipes["iron"])
        XCTAssertFalse(game.canCraft("iron"))
        // The craftable set is exactly the leather/torch/healing/material list.
        XCTAssertEqual(Set(game.data.recipes.keys),
                       ["rope", "leatherCap", "leatherVest", "leatherBoots",
                        "torch", "bandage", "medkit", "ironBar"])
    }

    func testCraftableHealingBandageAndMedkit() {
        let game = startInRoom(doors: 1, thenScript: [])
        // Bandage: 2 scrapmetal + 1 waterbottle.
        game.inventory.add("scrapmetal", count: 2)
        game.inventory.add("waterbottle")
        XCTAssertTrue(game.canCraft("bandage"))
        game.craft("bandage")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 0)
        XCTAssertEqual(game.inventory.count(of: "waterbottle"), 0)
        XCTAssertEqual(game.inventory.count(of: "bandage"), 1)

        // Medkit: 2 bandage + 1 medicine.
        game.inventory.add("bandage") // now 2 bandages
        game.inventory.add("medicine")
        XCTAssertTrue(game.canCraft("medkit"))
        game.craft("medkit")
        XCTAssertEqual(game.inventory.count(of: "bandage"), 0)
        XCTAssertEqual(game.inventory.count(of: "medicine"), 0)
        XCTAssertEqual(game.inventory.count(of: "medkit"), 1)
    }

    func testHardenedBladeBoostsMaxDurability() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("sword") // 30/30
        game.inventory.add("ironBar")
        XCTAssertTrue(game.canHardenBlade("sword"))
        game.hardenBlade("sword")
        // 30 * 1.5 = 45 max, with the +15 delta credited to current durability.
        let inst = game.inventory.instances(of: "sword").first
        XCTAssertEqual(inst?.maxDurability, 45)
        XCTAssertEqual(inst?.durability, 45)
        XCTAssertEqual(game.inventory.count(of: "ironBar"), 0) // consumed
        // The torch (no durability) can't be hardened.
        game.inventory.add("torch")
        game.inventory.add("ironBar")
        XCTAssertFalse(game.canHardenBlade("torch"))
    }

    func testPharmacyRoomExistsAndIsHealthDense() {
        let table = GameData.load().rooms["Pharmacy"]
        XCTAssertNotNil(table)
        XCTAssertTrue(table?.contains("medkit") ?? false)
        XCTAssertTrue(table?.contains("bandage") ?? false)
    }

    // MARK: - Armour durability + breaking (Part 2)

    /// Helper: a fully-armoured leather kit at full durability.
    private func fullLeatherKit() -> Armour {
        Armour(head: .leather, chest: .leather, legs: .leather,
               headDurability: 25, chestDurability: 35, legsDurability: 28)
    }

    func testArmourWearOneSlotLosesOneDurability() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.armour = fullLeatherKit()
        // affected = 1, pick index 1 (chest).
        game.rng = ScriptedGameRandom([1, 1])
        game.wearArmour()
        XCTAssertEqual(game.player.armour.currentDurability(in: .head), 25)
        XCTAssertEqual(game.player.armour.currentDurability(in: .chest), 34) // -1
        XCTAssertEqual(game.player.armour.currentDurability(in: .legs), 28)
    }

    func testArmourWearTwoDistinctSlots() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.armour = fullLeatherKit()
        // affected = 2; first index 0 (head); second index 1 of remaining [chest,legs] -> legs.
        game.rng = ScriptedGameRandom([2, 0, 1])
        game.wearArmour()
        XCTAssertEqual(game.player.armour.currentDurability(in: .head), 24) // -1
        XCTAssertEqual(game.player.armour.currentDurability(in: .chest), 35) // untouched
        XCTAssertEqual(game.player.armour.currentDurability(in: .legs), 27) // -1
    }

    func testArmourWearRespectsNumberOfEquippedSlots() {
        let game = startInRoom(doors: 1, thenScript: [])
        // Only legs equipped; even rolling "2 slots" only that slot can wear.
        game.player.armour = Armour(legs: .leather, legsDurability: 28)
        game.rng = ScriptedGameRandom([2, 0])
        game.wearArmour()
        XCTAssertEqual(game.player.armour.currentDurability(in: .legs), 27)
        // Unarmoured: no slots, no wear, consumes no RNG.
        let bare = startInRoom(doors: 1, thenScript: [])
        bare.rng = ScriptedGameRandom([]) // empty — must not be read
        bare.wearArmour()
        XCTAssertNil(bare.player.armour.material(in: .head))
    }

    func testFloodedRoomWearsBootsByOne() {
        // Iron boots negate the flood but still wear 1 durability.
        let game = makeGame(script: [50, 100, 100, 4, 1, 12, 15])
        game.startNewGame()
        game.player.armour = Armour(legs: .iron, legsDurability: 62)
        game.rng = ScriptedGameRandom([50, 100, 100, 4, 1, 12, 15]) // flooded again
        game.takeDoor(1)
        XCTAssertEqual(game.roomModifier, .flooded)
        XCTAssertEqual(game.player.currentHealth, 85) // immune, no HP lost
        XCTAssertEqual(game.player.armour.currentDurability(in: .legs), 61) // boots wore 1
    }

    func testArmourBreakingDropsTierScaledMaterials() {
        // Leather → 1 rope.
        let g1 = startInRoom(doors: 1, thenScript: [])
        g1.player.armour = Armour(head: .leather, headDurability: 1)
        g1.wearArmourSlot(.head)
        XCTAssertNil(g1.player.armour.material(in: .head))
        XCTAssertEqual(g1.inventory.count(of: "rope"), 1)

        // Scrap → 2 scrapmetal.
        let g2 = startInRoom(doors: 1, thenScript: [])
        g2.player.armour = Armour(chest: .scrap, chestDurability: 1)
        g2.wearArmourSlot(.chest)
        XCTAssertNil(g2.player.armour.material(in: .chest))
        XCTAssertEqual(g2.inventory.count(of: "scrapmetal"), 2)

        // Iron → 2 scrapmetal + 1 iron.
        let g3 = startInRoom(doors: 1, thenScript: [])
        g3.player.armour = Armour(legs: .iron, legsDurability: 1)
        g3.wearArmourSlot(.legs)
        XCTAssertNil(g3.player.armour.material(in: .legs))
        XCTAssertEqual(g3.inventory.count(of: "scrapmetal"), 2)
        XCTAssertEqual(g3.inventory.count(of: "iron"), 1)

        // Steel → 3 scrapmetal + 1 ironBar.
        let g4 = startInRoom(doors: 1, thenScript: [])
        g4.player.armour = Armour(head: .steel, headDurability: 1)
        g4.wearArmourSlot(.head)
        XCTAssertNil(g4.player.armour.material(in: .head))
        XCTAssertEqual(g4.inventory.count(of: "scrapmetal"), 3)
        XCTAssertEqual(g4.inventory.count(of: "ironBar"), 1)
    }

    func testArmourBreakMessageFiresOneOfTheVariants() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.promptRng = ScriptedGameRandom([0]) // first armourBreak variant
        game.player.armour = Armour(legs: .leather, legsDurability: 1)
        game.wearArmourSlot(.legs)
        let last = game.log.last
        XCTAssertEqual(last?.kind, .warning)
        // Variant 0: "Your {tier} {slot} finally gives out, crumbling into {materials}."
        XCTAssertTrue(last?.text.contains("Leather") ?? false)
        XCTAssertTrue(last?.text.contains("legs") ?? false)
        XCTAssertTrue(last?.text.contains("Rope") ?? false)
    }

    // MARK: - Armour repair (Part 2d)

    func testArmourRepairFormulaDiminishingReturns() {
        // Steel chest, max 100. repairAmount = max(ceil(10), round(60*(1-cur/100))).
        let max = 100
        XCTAssertEqual(Balance.Armour.repairAmount(maxDurability: max, currentDurability: 0), 60)   // 0%
        XCTAssertEqual(Balance.Armour.repairAmount(maxDurability: max, currentDurability: 25), 45)  // 25%
        XCTAssertEqual(Balance.Armour.repairAmount(maxDurability: max, currentDurability: 50), 30)  // 50%
        XCTAssertEqual(Balance.Armour.repairAmount(maxDurability: max, currentDurability: 75), 15)  // 75%
        XCTAssertEqual(Balance.Armour.repairAmount(maxDurability: max, currentDurability: 95), 10)  // floor kicks in (3 -> 10)
        XCTAssertEqual(Balance.Armour.repairBase, 0.6)
        XCTAssertEqual(Balance.Armour.repairFloor, 0.10)
    }

    func testArmourRepairCostsByTierAndSlot() {
        XCTAssertEqual(Balance.Armour.repairCost(.head, .leather).ingredient, "rope")
        XCTAssertEqual(Balance.Armour.repairCost(.head, .leather).count, 2)
        XCTAssertEqual(Balance.Armour.repairCost(.chest, .leather).count, 3) // chest +1
        XCTAssertEqual(Balance.Armour.repairCost(.head, .scrap).ingredient, "scrapmetal")
        XCTAssertEqual(Balance.Armour.repairCost(.legs, .iron).ingredient, "iron")
        XCTAssertEqual(Balance.Armour.repairCost(.head, .steel).ingredient, "ironBar")
        XCTAssertEqual(Balance.Armour.repairCost(.chest, .steel).count, 3)
    }

    func testArmourRepairAppliesAmountAndDeductsMaterials() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.armour = Armour(chest: .steel, chestDurability: 50)
        game.inventory.add("ironBar", count: 3)
        game.repairArmour(.chest)
        XCTAssertEqual(game.player.armour.currentDurability(in: .chest), 80) // +30
        XCTAssertEqual(game.inventory.count(of: "ironBar"), 0)
    }

    func testArmourRepairNeverExceedsMax() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.armour = Armour(chest: .steel, chestDurability: 95)
        game.inventory.add("ironBar", count: 3)
        game.repairArmour(.chest) // amount 10 capped to 5 (100-95)
        XCTAssertEqual(game.player.armour.currentDurability(in: .chest), 100)
    }

    func testCanRepairArmourGatesOnBelowFullAndMaterials() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.armour = Armour(head: .leather, headDurability: 10) // max 25, below full
        XCTAssertFalse(game.canRepairArmour(.head)) // no rope
        game.inventory.add("rope", count: 2)
        XCTAssertTrue(game.canRepairArmour(.head)) // below full + materials
        game.player.armour.setStoredDurability(25, in: .head) // now full
        XCTAssertFalse(game.canRepairArmour(.head)) // not below full
    }

    func testArmourUpgradeSetsFullDurabilityOfNewTier() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.player.armour = Armour(head: .leather, headDurability: 5) // damaged leather
        game.inventory.add("scrapmetal", count: 5)
        game.upgradeArmour(.head)
        XCTAssertEqual(game.player.armour.head, ArmourMaterial.scrap)
        XCTAssertEqual(game.player.armour.currentDurability(in: .head), 35) // full scrap, not 5
    }

    // MARK: - Weapon repair (Part 4)

    func testWeaponRepairPerWeaponCostRestoreAndCap() {
        let table: [(weapon: String, ingredient: String, count: Int, restore: Int)] = [
            ("branch", "rope", 1, 8), ("fork", "rope", 2, 8),
            ("bat", "scrapmetal", 2, 10), ("knife", "scrapmetal", 2, 10),
            ("shovel", "scrapmetal", 3, 10), ("crowbar", "scrapmetal", 3, 12),
            ("sword", "iron", 3, 15), ("longsword", "iron", 4, 15),
        ]
        for row in table {
            let game = startInRoom(doors: 1, thenScript: [])
            game.inventory.add(row.weapon)
            let max = Balance.Durability.maxByWeapon[row.weapon]!
            for _ in 0..<(max - 2) { _ = game.inventory.degradeWeapon(row.weapon) } // -> 2
            game.inventory.add(row.ingredient, count: row.count)
            XCTAssertTrue(game.canRepairWeapon(row.weapon), row.weapon)
            game.repairWeapon(row.weapon)
            let inst = game.inventory.instances(of: row.weapon).first
            XCTAssertEqual(inst?.durability, min(max, 2 + row.restore), row.weapon)
            XCTAssertEqual(game.inventory.count(of: row.ingredient), 0, row.weapon)
        }
    }

    func testWeaponRepairPreservesUpgradeLevelAndCapsAtMax() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife") // max 15
        game.inventory.add("scrapmetal", count: 3)
        game.upgradeWeaponDamage("knife") // level 1
        for _ in 0..<10 { _ = game.inventory.degradeWeapon("knife") } // 15 -> 5
        game.inventory.add("scrapmetal", count: 2)
        game.repairWeapon("knife") // +10 -> capped at 15
        let inst = game.inventory.instances(of: "knife").first
        XCTAssertEqual(inst?.durability, 15)
        XCTAssertEqual(inst?.upgradeLevel, 1) // preserved
    }

    func testCanRepairWeaponGatesOnBelowMaxAndMaterials() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("sword") // 30/30, full
        XCTAssertFalse(game.canRepairWeapon("sword")) // at max
        _ = game.inventory.degradeWeapon("sword") // 29/30
        XCTAssertFalse(game.canRepairWeapon("sword")) // no iron
        game.inventory.add("iron", count: 3)
        XCTAssertTrue(game.canRepairWeapon("sword")) // below max + materials
    }

    // MARK: - Prompt pool (Part 5)

    func testPromptPoolsHaveEnoughVariantsAndSubstituteCleanly() {
        let prompts = GameData.load().prompts
        var rng: GameRandom = SeededGameRandom(seed: 7)
        let tokens = ["room": "Kitchen", "item": "🔪 Knife", "damage": "5",
                      "enemy": "a ghoul", "tier": "Leather", "slot": "head",
                      "materials": "1× Rope", "bootsNote": "take the hit"]
        for event in PromptEvent.allCases {
            XCTAssertGreaterThanOrEqual(prompts.variants(event).count, 5, "\(event) needs >= 5 variants")
            // Pick a few times — never empty, never leaves an unsubstituted token.
            for _ in 0..<10 {
                let text = prompts.pick(event, using: &rng, replacing: tokens)
                XCTAssertFalse(text.isEmpty, "\(event) produced empty text")
                XCTAssertFalse(text.contains("{"), "\(event) left a token: \(text)")
            }
        }
    }

    // MARK: - Armour durability save migration (Part 6)

    func testArmourDurabilityPersistsAndOldSavesDefaultToFull() throws {
        // Round-trip: a worn equipped piece keeps its durability.
        let game = startInRoom(doors: 2, thenScript: [])
        game.inventory.add("rope", count: 4)
        game.craft("leatherCap")
        game.equip("leatherCap")        // head leather, durability 25
        game.wearArmourSlot(.head)      // -> 24
        game.saveGame(slot: 1)
        game.startNewGame()
        XCTAssertTrue(game.loadGame(slot: 1))
        XCTAssertEqual(game.player.armour.head, ArmourMaterial.leather)
        XCTAssertEqual(game.player.armour.currentDurability(in: .head), 24)

        // Old save (material but no durability key) loads as full durability.
        let oldJSON = "{\"head\":\"iron\"}"
        let migrated = try JSONDecoder().decode(Armour.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(migrated.head, ArmourMaterial.iron)
        XCTAssertNil(migrated.headDurability)                       // nothing stored
        XCTAssertEqual(migrated.currentDurability(in: .head), 55)   // reads full iron pool
    }

    // MARK: - Tabbed list sort (Part 1)

    func testItemsByQuantitySortDescendingWithAlphabeticalTiebreak() {
        var inv = Inventory()
        inv.add("tomato", count: 1)
        inv.add("carrot", count: 3)
        inv.add("chocolate", count: 3) // ties with carrot on count
        inv.add("steak", count: 2)
        let order = inv.itemsByQuantity(in: .consumable).map(\.id)
        // 3s first (Carrot < Chocolate alphabetically), then 2 (Steak), then 1 (Tomato).
        XCTAssertEqual(order, ["carrot", "chocolate", "steak", "tomato"])
    }

    // MARK: - Workbench shared logic across access points (Part 2)

    func testWorkbenchFunctionsShareLogicRegardlessOfAccessPoint() {
        // The same craft/convert/breakdown functions are reachable whether the
        // player owns a grindstone (room), or is at a merchant/scavenger — the
        // logic doesn't fork per access point. Exercise each with no grindstone
        // and while parked at a trader.
        let game = startInRoom(doors: 1, thenScript: [])
        game.screen = .trader
        game.traderKind = .scavenger
        XCTAssertFalse(game.hasGrindstone)

        // Craft (leather is the only craftable armour now).
        game.inventory.add("rope", count: 4)
        game.craft("leatherCap")
        XCTAssertEqual(game.inventory.count(of: "leatherCap"), 1)

        // Convert.
        game.inventory.add("knife")
        game.inventory.add("scrapmetal", count: 4)
        game.convertWeapon("knife")
        XCTAssertEqual(game.inventory.count(of: "sword"), 1)

        // Breakdown — no grindstone, works because access is the gate, not this.
        game.breakdown("sword")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 5) // sword -> 5 scrap
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

    func testBreakdownYieldsScrapWithoutAGrindstoneGate() {
        // Part 2: breakdown is a Workbench function — access is gated by the UI
        // (own a grindstone, or free at a trader), so the function itself no
        // longer re-checks for a grindstone.
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("sword")
        game.breakdown("sword")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 5)
        XCTAssertEqual(game.inventory.count(of: "sword"), 0)
    }

    func testTorchAndBranchCannotBeBrokenDown() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("torch")
        game.inventory.add("branch")
        game.breakdown("torch")
        game.breakdown("branch")
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 0)
        XCTAssertEqual(game.inventory.count(of: "torch"), 1)
        XCTAssertEqual(game.inventory.count(of: "branch"), 1)
    }

    // MARK: - Equip

    func testEquippingArmourSetsSlotTierAndConsumesPiece() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("scrapHelmet")
        game.inventory.add("scrapBoots")
        game.equip("scrapHelmet")
        game.equip("scrapBoots")
        XCTAssertEqual(game.player.armour.head, ArmourMaterial.scrap)
        XCTAssertEqual(game.player.armour.legs, ArmourMaterial.scrap)
        XCTAssertEqual(game.player.armour.rawArmour, 35) // 20 + 15
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
        // trader-kind 50 (>40 -> merchant); loadShop: foods 0,1; tool roll 50
        // (<100 -> grindstone, choice 0); weapon roll 30 (>25 -> longsword).
        game.rng = ScriptedGameRandom([50, 0, 1, 50, 0, 30, 0])
        game.startTrader()
        XCTAssertEqual(game.traderKind, .merchant)
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
        // trader-kind 50 (merchant); foods collide (0,0) then resolve (1);
        // tool roll/choice; weapon roll 10 (no weapon).
        game.rng = ScriptedGameRandom([50, 0, 0, 1, 50, 0, 10])
        game.startTrader()
        XCTAssertEqual(game.traderKind, .merchant)
        let foods = game.shopStock?.foods ?? []
        XCTAssertEqual(foods.count, 2)
        XCTAssertEqual(Set(foods).count, 2)
        XCTAssertNil(game.shopStock?.weapon)
    }

    // MARK: - Scavenger trader + grindstone (Part 5)

    func testScavengerAppearsOnLowRoll() {
        let scav = startInRoom(doors: 1, thenScript: [])
        scav.rng = ScriptedGameRandom([20]) // <=40 -> scavenger
        scav.startTrader()
        XCTAssertEqual(scav.traderKind, .scavenger)
        XCTAssertNil(scav.shopStock)

        let merch = startInRoom(doors: 1, thenScript: [])
        merch.rng = ScriptedGameRandom([50, 0, 1, 50, 0, 10]) // >40 -> merchant + loadShop
        merch.startTrader()
        XCTAssertEqual(merch.traderKind, .merchant)
        XCTAssertNotNil(merch.shopStock)
    }

    func testScavengerSellPricesBaseAndDurabilityScaled() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("scrapmetal", count: 3)
        XCTAssertEqual(game.sellPrice(of: "scrapmetal"), 8) // non-weapon base
        game.inventory.add("sword") // 30/30
        XCTAssertEqual(game.sellPrice(of: "sword"), 40) // full durability -> base
        for _ in 0..<15 { _ = game.inventory.degradeWeapon("sword") } // 15/30
        XCTAssertEqual(game.sellPrice(of: "sword"), 20) // 40 * 0.5
    }

    func testScavengerBuysItemForMoney() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.screen = .trader
        game.traderKind = .scavenger
        game.inventory.add("iron", count: 2)
        let before = game.player.money
        game.sell("iron")
        XCTAssertEqual(game.player.money, before + 20)
        XCTAssertEqual(game.inventory.count(of: "iron"), 1)
    }

    func testWeaponConversionConsumesSourceAndScrap() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife")
        game.inventory.add("scrapmetal", count: 5)
        XCTAssertTrue(game.canConvertWeapon("knife"))
        game.convertWeapon("knife")
        XCTAssertEqual(game.inventory.count(of: "knife"), 0)
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 1) // 5 - 4
        XCTAssertEqual(game.inventory.count(of: "sword"), 1)
        XCTAssertEqual(game.inventory.upgradeLevel(of: "sword"), 0) // full, fresh
    }

    func testWeaponDamageUpgradeDeductionAndCap() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife") // cap 3
        game.inventory.add("scrapmetal", count: 10)
        for expected in 1...3 {
            XCTAssertTrue(game.canUpgradeWeaponDamage("knife"))
            game.upgradeWeaponDamage("knife")
            XCTAssertEqual(game.inventory.upgradeLevel(of: "knife"), expected)
        }
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 1) // 10 - 3*3
        XCTAssertFalse(game.canUpgradeWeaponDamage("knife")) // at cap
        game.upgradeWeaponDamage("knife") // no-op at cap
        XCTAssertEqual(game.inventory.upgradeLevel(of: "knife"), 3)
    }

    func testUpgradeBonusAppliesInCombat() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.depth = 0
        game.inventory.add("knife")
        game.inventory.add("scrapmetal", count: 6)
        game.upgradeWeaponDamage("knife")
        game.upgradeWeaponDamage("knife") // level 2 -> +10
        XCTAssertEqual(game.inventory.upgradeBonus(of: "knife"), 10)
        game.rng = ScriptedGameRandom([150, 0]) // easy, HP 75
        game.startEncounter()
        game.enemy?.hp = 1000
        game.beginFight()
        game.rng = ScriptedGameRandom([0, 3]) // knife idx0=40 (+10), counter raw 3
        game.attack(with: "knife")
        XCTAssertEqual(game.enemy?.hp, 1000 - 50)
    }

    // MARK: - Save / load round trip

    func testWeaponUpgradeLevelPersistsThroughSaveLoad() {
        let game = startInRoom(doors: 2, thenScript: [])
        game.inventory.add("sword")
        game.inventory.add("scrapmetal", count: 6)
        game.upgradeWeaponDamage("sword")
        game.upgradeWeaponDamage("sword") // level 2
        game.saveGame(slot: 2)
        game.startNewGame()
        XCTAssertTrue(game.loadGame(slot: 2))
        XCTAssertEqual(game.inventory.upgradeLevel(of: "sword"), 2)
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 0) // 6 - 2*3
    }

    func testSaveLoadRoundTrip() {
        let game = startInRoom(doors: 2, thenScript: [])
        game.inventory.add("knife", count: 2)
        game.inventory.add("scrapmetal", count: 4)
        game.player.money = 123
        game.player.armour.head = .iron
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
        XCTAssertEqual(game.player.armour.head, ArmourMaterial.iron)
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
                    if game.canCraft("rope") { game.craft("rope") }
                    if game.canCraft("leatherCap") { game.craft("leatherCap") }
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
