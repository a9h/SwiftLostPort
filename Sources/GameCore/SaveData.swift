import Foundation

/// Everything needed to restore a run: stats, inventory (which covers the
/// original's per-category lists, metal/iron counts and tools), armour,
/// and the current room.
public struct SaveData: Codable, Equatable, Sendable {
    public var player: Player
    public var inventoryCounts: [String: Int]
    public var roomName: String
    public var doors: Int
    public var hasLooted: Bool
    public var previousEncounter: Bool
    public var roomsVisited: Int
    public var savedAt: Date
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
            savedAt: Date()
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
        enemy = nil
        shopStock = nil
        hlRound = nil
        encounterPhase = .choosing
        screen = .room
        say("Game loaded. You're back in the \(roomName).", .info)
        return true
    }
}
