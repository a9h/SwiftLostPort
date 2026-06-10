import Foundation

/// Every tunable balance number for the update lives here, grouped by system.
/// Logic elsewhere should reference these rather than hard-coding magic numbers.
public enum Balance {

    // MARK: - Armour (A1: diminishing-returns soft cap)

    public enum Armour {
        /// Max fraction of damage that can ever be removed (asymptote, never reached).
        public static let ceiling = 0.85
        /// Controls how fast diminishing returns kick in. Higher = slower climb.
        public static let scale = 120.0
        /// Flat HP removed from every hit before the percentage is applied.
        public static let flat = 2
    }

    // MARK: - Depth scaling + bosses (B1, rebalanced: delayed start + slow ramp)

    public enum Depth {
        /// No depth scaling at all below this depth — a long, fair early game
        /// where the player gathers gear before threats grow.
        public static let scalingStartDepth = 30
        /// Per-room HP ramp past the threshold (+1.5%/room).
        public static let hpRampPerRoom = 0.015
        /// Per-room damage ramp past the threshold (+1.2%/room).
        public static let damageRampPerRoom = 0.012
        /// Per-room coin ramp past the threshold (+3%/room) — rewards still grow.
        public static let coinRampPerRoom = 0.03

        /// The first boss appears at this depth...
        public static let firstBossDepth = 50
        /// ...then every this-many depths after (50, 85, 120, ...).
        public static let bossInterval = 35
        /// Boss HP = hard-tier HP × this (before depth multiplier).
        public static let bossHPMultiplier = 3
        /// Boss damage = hard-tier range, depth-scaled, × this.
        public static let bossDamageMultiplier = 1.25
        /// Boss coin reward range (before depth multiplier).
        public static let bossCoinRange = 200...350
        /// Curated guaranteed drop pool on boss death.
        public static let bossLootPool = ["ironHelmet", "ironChestplate", "ironBoots", "sword", "longsword", "medkit"]

        /// Depth measured past the scaling threshold (0 below it).
        public static func effectiveDepth(_ depth: Int) -> Int {
            max(0, depth - scalingStartDepth)
        }
        /// True when `depth` is a boss milestone (50, 85, 120, ...).
        public static func isBossDepth(_ depth: Int) -> Bool {
            depth >= firstBossDepth && (depth - firstBossDepth) % bossInterval == 0
        }
    }

    // MARK: - Weapon durability (B2)

    public enum Durability {
        /// Max hit count per weapon type. Torch is exempt (uses scare mechanic).
        public static let maxByWeapon: [String: Int] = [
            "knife": 15, "fork": 10, "bat": 20, "crowbar": 25,
            "branch": 8, "shovel": 22, "sword": 30, "longsword": 25,
        ]
        /// Durability multiplier applied by the hardenedBlade upgrade path.
        public static let hardenedMultiplier = 1.5
    }

    // MARK: - Status effects (B2: poison)

    public enum Poison {
        /// Chance a medium enemy inflicts poison on a landed hit.
        public static let mediumChancePercent = 15
        /// Chance a hard enemy inflicts poison on a landed hit.
        public static let hardChancePercent = 30
        /// Chance a boss inflicts poison on a landed hit.
        public static let bossChancePercent = 50
        /// HP lost per room entered while poisoned (NOT armour-reduced).
        public static let damagePerRoom = 5
        /// Rooms the poison lasts (refreshed on re-application).
        public static let duration = 3
    }

    // MARK: - Room modifiers (B3)

    public enum RoomModifiers {
        /// Roll thresholds out of 100; remainder is a normal room.
        public static let trapChance = 12
        public static let darkChance = 12
        public static let floodedChance = 10
        /// Extra dark-modifier width for the Tunnel room (12 + 38 = ~50% dark).
        public static let tunnelDarkBonus = 38

        /// Trap damage (depth-scaled, armour-reduced).
        public static let trapDamageRange = 10...25
        /// Flooded damage when no boots equipped (environmental, NOT reduced).
        public static let floodedDamageRange = 5...15
    }

    // MARK: - Scavenger trader + upgrades (B4)

    public enum Scavenger {
        /// Chance a rolled trader is a scavenger (else a normal merchant).
        public static let chancePercent = 40

        /// Buy-back prices the scavenger pays for player items.
        public static let sellPrices: [String: Int] = [
            "scrapmetal": 8, "iron": 20, "ironBar": 35,
            // food / consumables
            "tomato": 10, "carrot": 10, "waterbottle": 15, "chocolate": 15,
            "steak": 20, "cannedfood": 18, "mushroom": 12,
            "bandage": 12, "medicine": 18, "medkit": 25, "pills": 30,
            // weapons (~40% of shop price)
            "knife": 15, "fork": 8, "bat": 12, "crowbar": 16, "branch": 5,
            "shovel": 16, "sword": 40, "longsword": 60,
            // armour
            "scrapHelmet": 18, "scrapBoots": 12, "scrapChestplate": 20,
            "ironHelmet": 30, "ironBoots": 25, "ironChestplate": 40,
            // tools
            "grindstone": 50,
        ]
    }
}
