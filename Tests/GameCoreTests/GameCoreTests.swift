import XCTest
@testable import GameCore

final class GameCoreTests: XCTestCase {

    /// GameState with scripted randomness and no disk access.
    private func makeGame(script: [Int]) -> GameState {
        GameState(data: .load(), rng: ScriptedGameRandom(script), saveStore: MemorySaveStore())
    }

    /// Puts the game into a plain Kitchen room with the given door count,
    /// consuming a known script prefix:
    /// decay-roll(no decay), traderRarity(no), encounterChance(no), room(choice 0 = Basement... rooms sorted), doors.
    private func startInRoom(doors: Int, thenScript rest: [Int]) -> GameState {
        // Room names sorted: Basement, Bathroom, Bedroom, Garden, Kitchen -> index 4 = Kitchen
        let prefix = [50, 100, 100, 4, doors]
        let game = makeGame(script: prefix + rest)
        game.startNewGame()
        XCTAssertEqual(game.screen, .room)
        XCTAssertEqual(game.roomName, "Kitchen")
        XCTAssertEqual(game.doors, doors)
        return game
    }

    // MARK: - Armour / combat damage

    func testArmourTotalIsRoundedAverage() {
        let armour = Armour(head: 20, chest: 25, legs: 15)
        XCTAssertEqual(armour.total, 20) // round(60/3)
        XCTAssertEqual(Armour(head: 20, chest: 0, legs: 0).total, 7) // round(20/3) = 6.67 -> 7
    }

    func testArmourReducesDamageByPercentage() {
        let armour = Armour(head: 20, chest: 25, legs: 15) // total 20%
        XCTAssertEqual(armour.reducedDamage(50), 40) // 50 - 50*0.2
        XCTAssertEqual(armour.reducedDamage(90), 72)
        XCTAssertEqual(Armour().reducedDamage(37), 37) // no armour, no reduction
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

    func testCombatRoundDealsWeaponDamageAndArmourReducedCounterhit() {
        // Room first, then: encounter difficulty roll, weapon damage choice,
        // enemy counter-hit raw damage.
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("knife")
        game.player.armour = Armour(head: 30, chest: 30, legs: 30) // 30% reduction

        // Force an encounter: difficulty roll 150 -> easy (100 HP)
        game.rng = ScriptedGameRandom([150])
        game.startEncounter()
        XCTAssertEqual(game.enemy?.difficulty, .easy)
        XCTAssertEqual(game.enemy?.hp, 100)

        // Attack: knife damage index 5 -> damages[5] = 45; counter-hit raw 20 -> 14 after 30%.
        game.rng = ScriptedGameRandom([5, 20])
        game.beginFight()
        game.attack(with: "knife")
        XCTAssertEqual(game.enemy?.hp, 100 - 45)
        XCTAssertEqual(game.player.currentHealth, 100 - 14)
    }

    func testKillingEnemyAwardsCoinsInDifficultyRange() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.inventory.add("longsword")

        game.rng = ScriptedGameRandom([150]) // easy, 100 HP
        game.startEncounter()
        // longsword damage choice index 0 -> 125 (kills), coins roll 30 (clamped to easy 10...30),
        // then the next room generation: no decay, no trader, no enemy, room 0, doors 2.
        game.rng = ScriptedGameRandom([0, 30, 50, 100, 100, 0, 2])
        game.beginFight()
        game.attack(with: "longsword")
        XCTAssertNil(game.enemy)
        XCTAssertEqual(game.player.money, 50 + 30)
        XCTAssertEqual(game.screen, .room)
    }

    func testFightWithNoWeaponsCostsOneArmouredHit() {
        let game = startInRoom(doors: 1, thenScript: [])
        game.rng = ScriptedGameRandom([150]) // easy
        game.startEncounter()
        game.rng = ScriptedGameRandom([10]) // raw hit 10
        game.beginFight()
        XCTAssertEqual(game.player.currentHealth, 90)
        XCTAssertEqual(game.encounterPhase, .choosing) // fight ended
    }

    // MARK: - Hunger / thirst decay

    func testDecayHappensWhenRollAboveFifty() {
        // decay roll 51 -> decay; hunger -7, thirst -3; no trader/enemy; room 4; doors 1
        let game = makeGame(script: [51, 7, 3, 100, 100, 4, 1])
        game.startNewGame()
        XCTAssertEqual(game.player.hunger, 93)
        XCTAssertEqual(game.player.thirst, 97)
    }

    func testNoDecayWhenRollFiftyOrBelow() {
        let game = makeGame(script: [50, 100, 100, 4, 1])
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
        XCTAssertEqual(game.player.armour.total, 12) // round(35/3)
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
        game.saveGame(slot: 1)

        game.startNewGame() // scripted RNG empty -> clamps; we only care it resets
        XCTAssertEqual(game.player.money, 50)

        XCTAssertTrue(game.loadGame(slot: 1))
        XCTAssertEqual(game.player.money, 123)
        XCTAssertEqual(game.player.armour.head, 20)
        XCTAssertEqual(game.inventory.count(of: "knife"), 2)
        XCTAssertEqual(game.inventory.count(of: "scrapmetal"), 4)
        XCTAssertEqual(game.roomName, "Kitchen")
        XCTAssertEqual(game.doors, 2)
        XCTAssertEqual(game.screen, .room)
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
        game.rng = ScriptedGameRandom([50, 100, 10, 4, 1])
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
