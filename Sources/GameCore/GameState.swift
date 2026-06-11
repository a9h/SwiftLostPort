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

    public init(data: GameData = .load(),
                rng: GameRandom = SystemGameRandom(),
                saveStore: SaveStore = FileSaveStore()) {
        self.data = data
        self.rng = rng
        self.saveStore = saveStore
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
        log = []
        say("Welcome to LOST. Find your way out... or don't.", .narration)
        generateRoom()
    }

    func gameOver(_ reason: String) {
        screen = .gameOver(reason: reason, money: player.money)
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
        depth = roomsExplored / 2 // depth advances once every two rooms

        // Hunger/thirst decay: 50% chance to lose 1–10 of each.
        if rng.int(in: 1...100) > 50 {
            player.hunger -= rng.int(in: 1...10)
            player.thirst -= rng.int(in: 1...10)
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

        let traderRarity = rng.int(in: 1...170)
        let encounterChance = rng.int(in: 1...130)
        let enemyAppears = encounterChance < 25 && !previousEncounter
        previousEncounter = false

        // A boss gate: once depth reaches the milestone, the boss is forced
        // every room (bypassing the previous flag and the encounter roll) until
        // it is defeated.
        if depth >= nextBossDepth {
            startBossEncounter(BossKind(rawValue: bossSequenceIndex) ?? .cowboy)
        } else if enemyAppears {
            startEncounter()
        } else if traderRarity < 20 {
            startTrader()
        } else {
            roomName = rng.choice(data.roomNames)
            doors = rng.int(in: 1...3)
            hasLooted = false
            // The Tunnel trends dark; modifier chances scale with depth (4b).
            let darkBonus = roomName == "Tunnel" ? Balance.RoomModifiers.tunnelDarkBonus : 0
            roomModifier = RoomModifier.roll(rng.int(in: 1...100), depth: depth, darkBonus: darkBonus)
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

        // Fewer doors = luckier roll.
        let lucky: Int
        switch doors {
        case 1: lucky = rng.int(in: 1...101)
        case 2: lucky = rng.int(in: 1...76)
        default: lucky = rng.int(in: 1...51)
        }
        guard lucky < 33 else {
            say(flavour(.lootFailure), .info)
            return
        }

        let table = data.rooms[roomName] ?? []
        guard !table.isEmpty else {
            say(flavour(.lootFailure), .info)
            return
        }
        let itemID = rng.choice(table)

        // Money brackets (de-overlapped, same intent as the original):
        // key 101–125 -> £25–40, key 1–49 -> £15–25, key 50–100 -> nothing.
        let key = rng.int(in: 1...125)
        var money = 0
        if key > 100 {
            money = rng.int(in: 25...40)
        } else if key < 50 {
            money = rng.int(in: 15...25)
        }

        inventory.add(itemID)
        player.money += money

        var message = flavour(.lootSuccess, ["item": ItemCatalog.label(itemID)])
        if money > 0 { message += " & £\(money)!" }
        say(message, .reward)
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
