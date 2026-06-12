import Foundation

/// The tracked statistics for a run (Lost update Part 4). The same shape is
/// reused for the lifetime totals — death folds a run's stats into the lifetime
/// store. Cause of death is tracked separately on `GameState` (per-run only,
/// never accumulated), so it isn't part of this struct.
public struct RunStats: Codable, Equatable, Sendable {
    public var roomsExplored = 0
    public var enemiesFought = 0
    public var bossesDefeated = 0
    public var damageDealt = 0
    public var damageTaken = 0
    public var itemsCrafted = 0
    public var moneyEarned = 0
    public var moneySpent = 0

    public init(roomsExplored: Int = 0, enemiesFought: Int = 0, bossesDefeated: Int = 0,
                damageDealt: Int = 0, damageTaken: Int = 0, itemsCrafted: Int = 0,
                moneyEarned: Int = 0, moneySpent: Int = 0) {
        self.roomsExplored = roomsExplored
        self.enemiesFought = enemiesFought
        self.bossesDefeated = bossesDefeated
        self.damageDealt = damageDealt
        self.damageTaken = damageTaken
        self.itemsCrafted = itemsCrafted
        self.moneyEarned = moneyEarned
        self.moneySpent = moneySpent
    }

    /// Component-wise sum — used to fold a finished run into lifetime totals.
    public static func + (a: RunStats, b: RunStats) -> RunStats {
        RunStats(
            roomsExplored: a.roomsExplored + b.roomsExplored,
            enemiesFought: a.enemiesFought + b.enemiesFought,
            bossesDefeated: a.bossesDefeated + b.bossesDefeated,
            damageDealt: a.damageDealt + b.damageDealt,
            damageTaken: a.damageTaken + b.damageTaken,
            itemsCrafted: a.itemsCrafted + b.itemsCrafted,
            moneyEarned: a.moneyEarned + b.moneyEarned,
            moneySpent: a.moneySpent + b.moneySpent
        )
    }

    /// A labelled, ordered view for the death and lifetime screens. Cause of
    /// death is appended separately by the death screen.
    public var labelledRows: [(label: String, value: String)] {
        [
            ("Rooms explored", "\(roomsExplored)"),
            ("Enemies fought", "\(enemiesFought)"),
            ("Bosses defeated", "\(bossesDefeated)"),
            ("Damage dealt", "\(damageDealt)"),
            ("Damage taken", "\(damageTaken)"),
            ("Items crafted", "\(itemsCrafted)"),
            ("Money earned", "£\(moneyEarned)"),
            ("Money spent", "£\(moneySpent)"),
        ]
    }
}
