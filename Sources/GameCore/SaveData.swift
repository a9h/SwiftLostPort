import Foundation

/// Everything needed to restore a run: stats, inventory (which covers the
/// original's per-category lists, metal/iron counts and tools), armour,
/// and the current room. New fields added by the update default gracefully
/// when an older save (lower `version`) is loaded.
public struct SaveData: Codable, Equatable, Sendable {
    /// Bumped whenever the save shape changes. v1 = original; v2 = update
    /// (depth/boss, durability, status effects, room modifier, trader type).
    public static let currentVersion = 2

    public var version: Int
    public var player: Player
    public var inventoryCounts: [String: Int]
    public var roomName: String
    public var doors: Int
    public var hasLooted: Bool
    public var previousEncounter: Bool
    public var roomsVisited: Int
    public var savedAt: Date

    // v2 additions
    public var depth: Int
    public var bossPending: Bool

    public init(version: Int = SaveData.currentVersion,
                player: Player,
                inventoryCounts: [String: Int],
                roomName: String,
                doors: Int,
                hasLooted: Bool,
                previousEncounter: Bool,
                roomsVisited: Int,
                savedAt: Date,
                depth: Int,
                bossPending: Bool) {
        self.version = version
        self.player = player
        self.inventoryCounts = inventoryCounts
        self.roomName = roomName
        self.doors = doors
        self.hasLooted = hasLooted
        self.previousEncounter = previousEncounter
        self.roomsVisited = roomsVisited
        self.savedAt = savedAt
        self.depth = depth
        self.bossPending = bossPending
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        player = try c.decode(Player.self, forKey: .player)
        inventoryCounts = try c.decode([String: Int].self, forKey: .inventoryCounts)
        roomName = try c.decode(String.self, forKey: .roomName)
        doors = try c.decode(Int.self, forKey: .doors)
        hasLooted = try c.decode(Bool.self, forKey: .hasLooted)
        previousEncounter = try c.decode(Bool.self, forKey: .previousEncounter)
        roomsVisited = try c.decode(Int.self, forKey: .roomsVisited)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        // v2 fields: default for older saves. Depth falls back to roomsVisited
        // so an old run keeps a sensible difficulty when resumed.
        depth = try c.decodeIfPresent(Int.self, forKey: .depth) ?? roomsVisited
        bossPending = try c.decodeIfPresent(Bool.self, forKey: .bossPending) ?? false
    }
}

/// Pluggable persistence so GameCore stays testable without touching disk.
public protocol SaveStore {
    func save(_ data: SaveData, slot: Int) throws
    func load(slot: Int) throws -> SaveData?
    func hasSave(slot: Int) -> Bool
    func deleteSave(slot: Int)
}

/// JSON files in Application Support (sandbox-friendly on iOS and macOS).
public final class FileSaveStore: SaveStore {
    private let directory: URL

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("LostGame", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for slot: Int) -> URL {
        directory.appendingPathComponent("save\(slot).json")
    }

    public func save(_ data: SaveData, slot: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: url(for: slot), options: .atomic)
    }

    public func load(slot: Int) throws -> SaveData? {
        let fileURL = url(for: slot)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(SaveData.self, from: Data(contentsOf: fileURL))
    }

    public func hasSave(slot: Int) -> Bool {
        FileManager.default.fileExists(atPath: url(for: slot).path)
    }

    public func deleteSave(slot: Int) {
        try? FileManager.default.removeItem(at: url(for: slot))
    }
}

/// In-memory store for unit tests.
public final class MemorySaveStore: SaveStore {
    private var slots: [Int: SaveData] = [:]
    public init() {}
    public func save(_ data: SaveData, slot: Int) throws { slots[slot] = data }
    public func load(slot: Int) throws -> SaveData? { slots[slot] }
    public func hasSave(slot: Int) -> Bool { slots[slot] != nil }
    public func deleteSave(slot: Int) { slots[slot] = nil }
}

public extension GameState {
    /// Two slots: the original's single slot, plus one spare.
    static let saveSlots = [1, 2]

    func hasSave(slot: Int = 1) -> Bool {
        saveStore.hasSave(slot: slot)
    }

    func savedAt(slot: Int) -> Date? {
        (try? saveStore.load(slot: slot))?.savedAt
    }

    /// Saving is a room-menu action, as in the original. The UI asks for
    /// overwrite confirmation before calling this.
    func saveGame(slot: Int = 1) {
        guard screen == .room else { return }
        let data = SaveData(
            player: player,
            inventoryCounts: inventory.counts,
            roomName: roomName,
            doors: doors,
            hasLooted: hasLooted,
            previousEncounter: previousEncounter,
            roomsVisited: roomsVisited,
            savedAt: Date(),
            depth: depth,
            bossPending: bossPending
        )
        do {
            try saveStore.save(data, slot: slot)
            say("Game saved. 💾", .info)
        } catch {
            say("Saving failed: \(error.localizedDescription)", .warning)
        }
    }

    /// Restores a save and drops you back into the saved room.
    @discardableResult
    func loadGame(slot: Int = 1) -> Bool {
        guard let saved = (try? saveStore.load(slot: slot)) ?? nil else {
            say("No save found.", .warning)
            return false
        }
        player = saved.player
        inventory = Inventory(counts: saved.inventoryCounts)
        roomName = saved.roomName
        doors = saved.doors
        hasLooted = saved.hasLooted
        previousEncounter = saved.previousEncounter
        roomsVisited = saved.roomsVisited
        depth = saved.depth
        bossPending = saved.bossPending
        enemy = nil
        shopStock = nil
        hlRound = nil
        encounterPhase = .choosing
        screen = .room
        say("Game loaded. You're back in the \(roomName).", .info)
        return true
    }
}
