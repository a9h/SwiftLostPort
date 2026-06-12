import Foundation

/// The game flow as explicit state — replaces the original's
/// recursive menu functions.
public enum Screen: Equatable, Sendable {
    case title
    case room
    case encounter
    case trader
    case gameOver(reason: String, money: Int)
}

public enum EncounterPhase: Equatable, Sendable {
    /// Choosing RUN / FIGHT / USE.
    case choosing
    /// Mid-fight: picking a weapon each round.
    case fighting
}

public struct LogEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case narration, info, combat, warning, reward
    }
    public let id: UUID
    public let text: String
    public let kind: Kind

    init(_ text: String, _ kind: Kind) {
        self.id = UUID()
        self.text = text
        self.kind = kind
    }
}

public final class GameState: ObservableObject {
    public let data: GameData
    var rng: GameRandom
    /// A separate RNG for flavour-text selection (Part 5). Kept apart from the
    /// gameplay `rng` so expanding the prompt pools never shifts any gameplay
    /// sequence (and never disturbs the scripted tests).
    var promptRng: GameRandom = SystemGameRandom()
    let saveStore: SaveStore

    @Published public internal(set) var screen: Screen = .title
    @Published public internal(set) var player = Player()
    @Published public internal(set) var inventory = Inventory()

    // Current room
    @Published public internal(set) var roomName: String = ""
    @Published public internal(set) var doors: Int = 1
    @Published public internal(set) var hasLooted = false
    /// Hazard on the current room (B3): trap, dark, flooded, or none.
    @Published public internal(set) var roomModifier: RoomModifier = .none
    /// True right after fleeing/winning a fight; blocks back-to-back
    /// encounters and is consumed by the next room generation.
    @Published var previousEncounter = false
    /// Internal scaling authority (B1), derived as `roomsExplored / 2` — depth
    /// advances once every two rooms. Never shown to the player directly.
    @Published public internal(set) var depth = 0
    /// Boss sequence state (Part 3). Once depth reaches `nextBossDepth`, every
    /// encounter is forced to be the boss at `bossSequenceIndex` until it is
    /// defeated; then the index advances (wrapping) and the milestone moves on.
    @Published public internal(set) var nextBossDepth = Balance.Bosses.depthStart
    @Published public internal(set) var bossSequenceIndex = 0
    /// Set once the player completes a full boss cycle — all later boss damage
    /// is fixed at maximum.
    @Published public internal(set) var maxDamageFlag = false

    // Current encounter
    @Published public internal(set) var enemy: Enemy?
    @Published public internal(set) var encounterPhase: EncounterPhase = .choosing

    // Current trader
    @Published public internal(set) var traderKind: TraderKind = .merchant
    @Published public internal(set) var shopStock: ShopStock?
    @Published public internal(set) var hlRound: HLRound?

    /// Message feed; the newest entry is typewriter-animated by the UI.
    @Published public internal(set) var log: [LogEntry] = []
    /// Total rooms entered this run — shown in the HUD as "Rooms".
    @Published public internal(set) var roomsExplored = 0

    /// True once a trader room is generated; blocks a second trader room
    /// immediately after (Lost update Part 3). Reset on any non-trader room.
    @Published public internal(set) var lastRoomWasTrader = false

    // MARK: - Stats (Lost update Part 4)

    /// Per-run tracked statistics. Reset on a new game, persisted in the active
    /// save, and folded into the lifetime totals on death.
    @Published public internal(set) var runStats = RunStats()
    /// Lifetime totals across all runs. Loaded from a store separate from any
    /// active save, so they survive death, new games and save overwrites.
    @Published public internal(set) var lifetimeStats = RunStats()
    /// How the current run ended (death screen only — never accumulated).
    @Published public internal(set) var causeOfDeath = ""

    public init(data: GameData = .load(),
                rng: GameRandom = SystemGameRandom(),
                saveStore: SaveStore = FileSaveStore()) {
        self.data = data
        self.rng = rng
        self.saveStore = saveStore
        self.lifetimeStats = saveStore.loadLifetime()
    }

    // MARK: - Money helpers (route every change through stat tracking)

    /// Adds money and records it as earned this run.
    func earn(_ amount: Int) {
        guard amount > 0 else { return }
        player.money += amount
        runStats.moneyEarned += amount
    }

    /// Subtracts money and records it as spent this run.
    func spend(_ amount: Int) {
        guard amount > 0 else { return }
        player.money -= amount
        runStats.moneySpent += amount
    }

    // MARK: - Logging

    func say(_ text: String, _ kind: LogEntry.Kind = .narration) {
        log.append(LogEntry(text, kind))
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }

    /// Picks a random flavour variant for an event (Part 5), substituting any
    /// `{token}` placeholders. Uses the dedicated flavour RNG.
    func flavour(_ event: PromptEvent, _ tokens: [String: String] = [:]) -> String {
        data.prompts.pick(event, using: &promptRng, replacing: tokens)
    }

    // MARK: - Run lifecycle

    public func startNewGame() {
        player = Player()
        inventory = Inventory()
        enemy = nil
        shopStock = nil
        hlRound = nil
        previousEncounter = false
        depth = 0
        nextBossDepth = Balance.Bosses.depthStart
        bossSequenceIndex = 0
        maxDamageFlag = false
        roomModifier = .none
        roomsExplored = 0
        lastRoomWasTrader = false
        runStats = RunStats()
        causeOfDeath = ""
        log = []
        say("Welcome to LOST. Find your way out... or don't.", .narration)
        generateRoom()
    }

    /// Ends the run: records the cause, folds this run's stats into the lifetime
    /// totals (which live in a store separate from any active save), then shows
    /// the death screen.
    func gameOver(_ reason: String) {
        causeOfDeath = reason
        foldRunIntoLifetime()
        screen = .gameOver(reason: reason, money: player.money)
    }

    /// Accumulates the finished run into the persistent lifetime store.
    func foldRunIntoLifetime() {
        let updated = saveStore.loadLifetime() + runStats
        try? saveStore.saveLifetime(updated)
        lifetimeStats = updated
    }

    /// Reloads the lifetime totals from the store (for the main-menu screen).
    public func refreshLifetimeStats() {
        lifetimeStats = saveStore.loadLifetime()
    }

    public func returnToTitle() {
        screen = .title
    }

    // MARK: - Room generation (the original `generation()`)

    func generateRoom() {
        enemy = nil
        encounterPhase = .choosing
        shopStock = nil
        hlRound = nil
        roomModifier = .none
        roomsExplored += 1
        runStats.roomsExplored += 1
        depth = roomsExplored / 2 // depth advances once every two rooms

        // Hunger/thirst decay: 50% chance to lose 1–7 of each (Lost update Part 7).
        if rng.int(in: 1...100) > 50 {
            player.hunger -= rng.int(in: 1...Balance.Decay.maxPerRoom)
            player.thirst -= rng.int(in: 1...Balance.Decay.maxPerRoom)
        }
        if player.hunger <= 0 {
            gameOver("You ran out of hunger and died")
            return
        }
        if player.thirst <= 0 {
            gameOver("You ran out of thirst and died")
            return
        }
        if player.hunger < 20 { say("⚠️ Your hunger is getting dangerously low!", .warning) }
        if player.thirst < 20 { say("⚠️ Your thirst is getting dangerously low!", .warning) }

        // Status effects (poison) tick on room entry and can be fatal.
        guard tickStatusEffects() else { return }

        // Trader rarity roll (restored to ~12%/room) and the encounter roll. Both
        // are always drawn so the RNG sequence stays stable; the flags below decide.
        let traderRoll = rng.int(in: 1...Balance.Trader.rarityRollMax)
        let encounterChance = rng.int(in: 1...130)
        let enemyAppears = encounterChance < 25 && !previousEncounter
        // A trader can't follow a trader (Part 3): the roll is suppressed when
        // the previous room was one.
        let traderAppears = traderRoll < Balance.Trader.rarityThreshold && !lastRoomWasTrader
        previousEncounter = false

        // A boss gate: once depth reaches the milestone, the boss is forced
        // every room (bypassing the previous flag and the encounter roll) until
        // it is defeated.
        if depth >= nextBossDepth {
            lastRoomWasTrader = false
            startBossEncounter(BossKind(rawValue: bossSequenceIndex) ?? .cowboy)
        } else if enemyAppears {
            lastRoomWasTrader = false
            startEncounter()
        } else if traderAppears {
            lastRoomWasTrader = true
            startTrader()
        } else {
            lastRoomWasTrader = false
            roomName = rng.choice(data.roomNames)
            doors = rng.int(in: 1...3)
            hasLooted = false
            // The Tunnel trends dark; modifier chances scale with depth (4b).
            let darkBonus = roomName == "Tunnel" ? Balance.RoomModifiers.tunnelDarkBonus : 0
            roomModifier = RoomModifier.roll(rng.int(in: 1...100), depth: depth,
                                             roomsExplored: roomsExplored, darkBonus: darkBonus)
            screen = .room
            say(flavour(.roomEntry, ["room": roomName]), .narration)
            applyRoomEntryEffects()
        }
    }

    /// Take door 1/2/3 — only valid if the room has that many doors.
    public func takeDoor(_ number: Int) {
        guard screen == .room, number >= 1, number <= doors else { return }
        say("You head through door \(number)...", .info)
        generateRoom()
    }

    // MARK: - Looting

    public func loot() {
        guard screen == .room else { return }
        if hasLooted {
            say("You have already looted this room!", .info)
            return
        }
        // Dark rooms need a torch in the pack as a light source (not consumed).
        if roomModifier == .dark {
            if inventory.has("torch") {
                say("You hold up your torch and search the gloom.", .info)
            } else {
                say("It's pitch black — you can't see anything to loot without a light.", .info)
                return
            }
        }
        hasLooted = true

        // A Garden always has a fallen branch to grab — guaranteed on every loot
        // (no roll), on top of whatever random loot turns up, so two branches in
        // one haul is possible. Consumes no RNG, so other rooms are unaffected.
        let gardenBranch = roomName == "Garden"
        if gardenBranch { inventory.add("branch") }

        // Fewer doors = luckier roll.
        let lucky: Int
        switch doors {
        case 1: lucky = rng.int(in: 1...101)
        case 2: lucky = rng.int(in: 1...76)
        default: lucky = rng.int(in: 1...51)
        }
        // Early rooms loot more forgivingly (Part 8): <40 up to room 50, else <33.
        let threshold = roomsExplored <= Balance.Loot.scalingRoom
            ? Balance.Loot.earlyThreshold
            : Balance.Loot.lateThreshold
        guard lucky < threshold else {
            if gardenBranch {
                say("You comb the garden and pocket a fallen branch.", .reward)
            } else {
                say(flavour(.lootFailure), .info)
            }
            return
        }

        let table = data.rooms[roomName] ?? []
        guard !table.isEmpty else {
            if gardenBranch {
                say("You comb the garden and pocket a fallen branch.", .reward)
            } else {
                say(flavour(.lootFailure), .info)
            }
            return
        }
        let itemID = pickLootItem(from: table)

        // Money brackets (de-overlapped, same intent as the original):
        // key 101–125 -> big find, key 1–49 -> small find, key 50–100 -> nothing.
        // Amounts are lower early and restore later (Part 9), crossing at room 50.
        let early = roomsExplored <= Balance.Loot.scalingRoom
        let key = rng.int(in: 1...125)
        var money = 0
        if key > 100 {
            money = rng.int(in: early ? Balance.Loot.earlyBig : Balance.Loot.lateBig)
        } else if key < 50 {
            money = rng.int(in: early ? Balance.Loot.earlySmall : Balance.Loot.lateSmall)
        }

        inventory.add(itemID)
        earn(money)

        var message = flavour(.lootSuccess, ["item": ItemCatalog.label(itemID)])
        if money > 0 { message += " & £\(money)!" }
        if gardenBranch { message += " (plus a fallen branch from the garden)" }
        say(message, .reward)
    }

    /// Picks one item from a loot table, applying the depth-weighted material
    /// modifier (Part 11): early rooms favour branch and dock scrapmetal; later
    /// rooms do the reverse. The room tables themselves are untouched. If the
    /// table holds neither material the pick is an unweighted choice (and uses
    /// the same single RNG draw, so sequencing is unchanged for those rooms).
    func pickLootItem(from table: [String]) -> String {
        let hasBranch = table.contains("branch")
        let hasScrap = table.contains("scrapmetal")
        guard hasBranch || hasScrap else { return rng.choice(table) }

        let branchFavoured = roomsExplored < Balance.LootWeighting.crossoverRoom
        let favoured = branchFavoured ? "branch" : "scrapmetal"
        let disfavoured = branchFavoured ? "scrapmetal" : "branch"
        let weights = table.map { id -> Int in
            if id == favoured { return Balance.LootWeighting.favouredWeight }
            if id == disfavoured { return Balance.LootWeighting.disfavouredWeight }
            return Balance.LootWeighting.baseWeight
        }
        var roll = rng.int(in: 1...weights.reduce(0, +))
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll <= 0 { return table[index] }
        }
        return table[table.count - 1]
    }

    // MARK: - Using items

    /// Usable from the room, an encounter, or the trader — same effects.
    public func use(_ itemID: String) {
        guard inventory.has(itemID) else {
            say("You don't have a \(ItemCatalog.name(itemID)).", .info)
            return
        }
        if data.weapons[itemID] != nil {
            say("You can't use a weapon when there is no enemies to use it on", .info)
            return
        }
        if let gains = data.stats.maxhealth[itemID] {
            let gain = rng.choice(gains)
            player.maxHealth += gain
            inventory.remove(itemID)
            say("You used \(ItemCatalog.label(itemID)) and gained +\(gain) max health (now \(player.maxHealth)).", .reward)
        } else if let gains = data.stats.currenthealth[itemID] {
            var gain = rng.choice(gains)
            if player.currentHealth + gain > player.maxHealth {
                gain = player.maxHealth - player.currentHealth
            }
            player.currentHealth += gain
            inventory.remove(itemID)
            say("You used \(ItemCatalog.label(itemID)) and healed +\(gain) health (now \(player.currentHealth)/\(player.maxHealth)).", .reward)
        } else if let hungerGains = data.stats.hunger[itemID], let thirstGains = data.stats.thirst[itemID] {
            let hungerGain = rng.choice(hungerGains)
            let thirstGain = rng.choice(thirstGains)
            player.hunger = min(100, player.hunger + hungerGain)
            player.thirst = min(100, player.thirst + thirstGain)
            inventory.remove(itemID)
            say("You consumed \(ItemCatalog.label(itemID)): +\(hungerGain) hunger, +\(thirstGain) thirst (hunger \(player.hunger), thirst \(player.thirst)).", .reward)
        } else {
            say("You can't use that.", .info)
        }
    }

    // MARK: - Dropping items

    public func drop(_ itemID: String) {
        guard inventory.remove(itemID) else { return }
        say("You dropped a \(ItemCatalog.label(itemID)).", .info)
    }
}
