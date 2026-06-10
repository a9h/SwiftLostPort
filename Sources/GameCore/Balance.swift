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
        /// Per-room damage ramp past the threshold (used by trap rooms).
        public static let damageRampPerRoom = 0.012
        /// Per-room coin ramp past the threshold (+3%/room) — rewards still grow.
        public static let coinRampPerRoom = 0.03

        /// Depth measured past the scaling threshold (0 below it).
        public static func effectiveDepth(_ depth: Int) -> Int {
            max(0, depth - scalingStartDepth)
        }
    }

    // MARK: - Boss system (Part 3: fixed sequence + specials)

    public enum Bosses {
        /// First boss at this depth (= 100 rooms under the 1:2 ratio)...
        public static let depthStart = 50
        /// ...then every this-many depths after (50, 100, 150, 200, 250).
        public static let depthInterval = 50
        /// Number of bosses in the cycle before it repeats.
        public static let sequenceCount = 5

        /// One boss's tunable stat block.
        public struct Stats {
            public let hp: Int
            public let damage: ClosedRange<Int>
            public let coins: ClosedRange<Int>
        }

        public static let cowboy = Stats(hp: 360, damage: 18...28, coins: 150...200)
        public static let ghoul = Stats(hp: 320, damage: 18...30, coins: 100...150)
        public static let plagueDoctor = Stats(hp: 340, damage: 20...32, coins: 120...160)
        /// Warlord hits twice per round at this per-hit range.
        public static let warlord = Stats(hp: 380, damage: 12...20, coins: 140...180)
        public static let packmaster = Stats(hp: 340, damage: 15...25, coins: 130...170)

        // Specials
        public static let cowboyDodgePercent = 50
        public static let ghoulPoisonPercent = 50
        public static let plagueDoctorHealFraction = 0.5
        public static let plagueDoctorHealRange = 40...55
        public static let packmasterSummonPercent = 20
        public static let packmasterSummonHP = 30...40
        public static let packmasterSummonDamage = 5...12
        /// Packmaster's random drop pool (food + health).
        public static let packmasterDropPool = [
            "steak", "cannedfood", "chocolate", "carrot", "waterbottle", "mushroom", "tomato",
            "bandage", "medkit", "medicine", "pills",
        ]
    }

    // MARK: - Enemy combat (Part 2 rebalance: damage + weighted HP)

    public enum EnemyCombat {
        /// Damage dealt to the player per hit (2b). Applies on every damage
        /// route via `reducedDamage()`.
        public static let easyDamage = 3...12
        public static let mediumDamage = 15...35
        public static let hardDamage = 28...55

        public static func damage(for difficulty: Difficulty) -> ClosedRange<Int> {
            switch difficulty {
            case .easy: return easyDamage
            case .medium: return mediumDamage
            case .hard: return hardDamage
            }
        }

        /// HP min/max per difficulty (2c). The actual HP is a depth-weighted
        /// roll within this range — low end early, high end late.
        public static let easyHP = (min: 75, max: 115)
        public static let mediumHP = (min: 120, max: 150)
        public static let hardHP = (min: 155, max: 200)
        /// Depth at which the weighting reaches the high end (weight caps at 1).
        public static let depthWeightCap = 150.0
        /// Random ± added to the weighted HP for per-encounter variety.
        public static let hpJitter = 15

        public static func hpRange(for difficulty: Difficulty) -> (min: Int, max: Int) {
            switch difficulty {
            case .easy: return easyHP
            case .medium: return mediumHP
            case .hard: return hardHP
            }
        }

        /// The depth-weighted HP roll: quadratic bias toward the low end early,
        /// the high end late, plus jitter, clamped into [min, max].
        public static func rolledHP(for difficulty: Difficulty, depth: Int, jitterRoll: Int) -> Int {
            let (minHP, maxHP) = hpRange(for: difficulty)
            let depthWeight = Swift.min(1.0, Double(depth) / depthWeightCap)
            let t = depthWeight * depthWeight
            let raw = Int(Double(minHP) + t * Double(maxHP - minHP)) + jitterRoll
            return Swift.min(maxHP, Swift.max(minHP, raw))
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
        /// Modifier chances out of 100 before the scaling depth (calmer early game).
        public static let earlyTrapChance = 5
        public static let earlyDarkChance = 5
        public static let earlyFloodedChance = 4
        /// Modifier chances from the scaling depth onward (rooms get nastier).
        public static let lateTrapChance = 9
        public static let lateDarkChance = 8
        public static let lateFloodedChance = 7
        /// Internal depth at/after which the late chances apply (= 100 rooms).
        public static let scalingDepth = 50
        /// Extra dark-modifier width for the Tunnel room (trends dark).
        public static let tunnelDarkBonus = 38

        /// Trap damage (depth-scaled, armour-reduced).
        public static let trapDamageRange = 10...25
        /// Flooded damage when no boots equipped (environmental, NOT reduced).
        public static let floodedDamageRange = 5...15

        public static func trapChance(depth: Int) -> Int { depth < scalingDepth ? earlyTrapChance : lateTrapChance }
        public static func darkChance(depth: Int) -> Int { depth < scalingDepth ? earlyDarkChance : lateDarkChance }
        public static func floodedChance(depth: Int) -> Int { depth < scalingDepth ? earlyFloodedChance : lateFloodedChance }
    }

    // MARK: - Scavenger trader (Part 5a)

    public enum Scavenger {
        /// Chance a rolled trader is a scavenger (else a normal merchant).
        public static let chancePercent = 40

        /// Base buy-back prices the scavenger pays. Weapon prices are scaled by
        /// remaining durability fraction at sell time (minimum £1).
        public static let sellPrices: [String: Int] = [
            "scrapmetal": 8, "iron": 20, "ironBar": 35,
            // food / consumables — £12 each
            "cannedfood": 12, "chocolate": 12, "carrot": 12, "tomato": 12,
            "mushroom": 12, "waterbottle": 12, "steak": 12,
            // health
            "bandage": 15, "medicine": 20, "medkit": 25, "pills": 30,
            // weapons (~40% of shop price)
            "fork": 8, "branch": 8, "knife": 16, "bat": 20, "shovel": 20,
            "crowbar": 20, "sword": 40, "longsword": 60,
            // armour
            "scrapHelmet": 18, "scrapBoots": 12, "scrapChestplate": 20,
            "ironHelmet": 30, "ironBoots": 25, "ironChestplate": 40,
            // tools
            "grindstone": 50,
        ]
    }

    // MARK: - Grindstone system (Part 5b)

    public enum Grindstone {
        /// Weapon conversion recipes: source weapon + scrap -> better weapon.
        public struct Conversion { public let result: String; public let scrapCost: Int }
        public static let conversions: [String: Conversion] = [
            "knife": Conversion(result: "sword", scrapCost: 4),
            "bat": Conversion(result: "crowbar", scrapCost: 3),
            "crowbar": Conversion(result: "shovel", scrapCost: 5),
            "sword": Conversion(result: "longsword", scrapCost: 6),
        ]

        /// Per-weapon damage-upgrade caps (number of +bonus upgrades allowed).
        public static let upgradeCaps: [String: Int] = [
            "branch": 2, "fork": 2, "bat": 3, "shovel": 3,
            "crowbar": 3, "knife": 3, "sword": 4, "longsword": 3,
        ]
        /// Scrapmetal cost per damage upgrade.
        public static let upgradeCost = 3
        /// Flat damage added to every value in the array, per upgrade level.
        public static let upgradeDamageBonus = 5

        public static func cap(for weaponID: String) -> Int { upgradeCaps[weaponID] ?? 0 }
    }
}
