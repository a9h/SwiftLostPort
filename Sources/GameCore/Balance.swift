import Foundation

/// Every tunable balance number for the update lives here, grouped by system.
/// Logic elsewhere should reference these rather than hard-coding magic numbers.
public enum Balance {

    // MARK: - Armour (A1: diminishing-returns soft cap; Part 3: tiers + slots)

    public enum Armour {
        /// Max fraction of damage that can ever be removed (asymptote, never reached).
        public static let ceiling = 0.85
        /// Controls how fast diminishing returns kick in. Higher = slower climb.
        public static let scale = 120.0
        /// Flat HP removed from every hit before the percentage is applied.
        public static let flat = 2

        // MARK: Tier base values (Part 3a)

        /// Per-slot, per-tier base reduction value feeding `rawArmour`. Chest is
        /// the backbone (highest values); boots the lightest.
        public static let tierBaseValue: [ArmourSlot: [ArmourMaterial: Int]] = [
            .head:  [.leather: 10, .scrap: 20, .iron: 30, .steel: 42],
            .chest: [.leather: 12, .scrap: 25, .iron: 38, .steel: 52],
            .legs:  [.leather: 8,  .scrap: 15, .iron: 22, .steel: 30],
        ]

        public static func baseValue(_ material: ArmourMaterial, slot: ArmourSlot) -> Int {
            tierBaseValue[slot]?[material] ?? 0
        }

        /// Maps an old save's summed slot integer to the nearest tier by base
        /// value (ties resolve to the lower tier). Used by save migration (3d).
        public static func nearestTier(forRaw value: Int, slot: ArmourSlot) -> ArmourMaterial {
            let table = tierBaseValue[slot] ?? [:]
            return ArmourMaterial.allCases.min { a, b in
                let da = abs((table[a] ?? 0) - value)
                let db = abs((table[b] ?? 0) - value)
                if da != db { return da < db }
                return a.tierIndex < b.tierIndex
            } ?? .leather
        }

        // MARK: Upgrade costs (Part 3b)

        /// What it costs (ingredient + count) to reach a given tier from the one
        /// below it, consuming the current piece in place. Leather is the base
        /// tier and so has no upgrade-in cost.
        public static func upgradeCost(to material: ArmourMaterial) -> (ingredient: String, count: Int)? {
            switch material {
            case .leather: return nil
            case .scrap:   return ("scrapmetal", 5)
            case .iron:    return ("iron", 4)
            case .steel:   return ("ironBar", 3)
            }
        }

        // MARK: Slot specialisation (Part 3c)

        /// Helmet poison-resist chance by tier (when an enemy would poison you).
        public static let poisonResistPercent: [ArmourMaterial: Int] = [
            .leather: 10, .scrap: 20, .iron: 35, .steel: 50,
        ]

        /// Fraction of flooded-room damage the boots negate by tier. Leather
        /// halves it, scrap takes most, iron/steel make you immune.
        public static let floodReduction: [ArmourMaterial: Double] = [
            .leather: 0.5, .scrap: 0.75, .iron: 1.0, .steel: 1.0,
        ]

        // MARK: Durability pools (Part 2a)

        /// Total damage-absorption a piece has before it breaks, per slot/tier.
        /// A freshly crafted or upgraded piece starts at this full value.
        public static let durabilityPool: [ArmourSlot: [ArmourMaterial: Int]] = [
            .head:  [.leather: 25, .scrap: 35, .iron: 55, .steel: 75],
            .chest: [.leather: 35, .scrap: 55, .iron: 75, .steel: 100],
            .legs:  [.leather: 28, .scrap: 42, .iron: 62, .steel: 85],
        ]

        public static func durability(_ material: ArmourMaterial, slot: ArmourSlot) -> Int {
            durabilityPool[slot]?[material] ?? 0
        }

        // MARK: Break drops (Part 2c) — a broken piece falls apart into these.

        public static let breakDrop: [ArmourMaterial: [String: Int]] = [
            .leather: ["rope": 1],
            .scrap:   ["scrapmetal": 2],
            .iron:    ["scrapmetal": 2, "iron": 1],
            .steel:   ["scrapmetal": 3, "ironBar": 1],
        ]

        // MARK: Repair (Part 2d) — diminishing returns, all tiers.

        /// Scaling factor: at zero durability a repair restores up to 60% of max.
        public static let repairBase = 0.6
        /// Floor: a repair always restores at least 10% of max (rounded up).
        public static let repairFloor = 0.10

        /// How much a single repair restores, given current/max durability.
        /// The lower the current durability, the more is restored.
        public static func repairAmount(maxDurability: Int, currentDurability: Int) -> Int {
            let floor = Int((Double(maxDurability) * repairFloor).rounded(.up))
            let scaled = Int((Double(maxDurability) * repairBase
                              * (1.0 - Double(currentDurability) / Double(maxDurability))).rounded())
            return Swift.max(floor, scaled)
        }

        /// Repair material cost per slot/tier (fixed regardless of amount
        /// restored). Chest costs 1 more than head/legs; the material escalates
        /// with tier: rope → scrapmetal → iron → ironBar.
        public static func repairCost(_ slot: ArmourSlot, _ material: ArmourMaterial) -> (ingredient: String, count: Int) {
            let ingredient: String
            switch material {
            case .leather: ingredient = "rope"
            case .scrap:   ingredient = "scrapmetal"
            case .iron:    ingredient = "iron"
            case .steel:   ingredient = "ironBar"
            }
            return (ingredient, slot == .chest ? 3 : 2)
        }
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

    // MARK: - Enemy tier gating by room (Lost update Part 1)

    /// Room-gated weighted tier selection. The early game shows only easy
    /// enemies; medium phases in across a bracket; all three tiers unlock late
    /// with hard climbing slowly. Easy is never removed entirely.
    public enum EnemyTiers {
        /// Up to and including this room, only easy enemies spawn.
        public static let easyOnlyMaxRoom = 75
        /// First room at which medium can appear (start of the easy/medium ramp).
        public static let mediumStartRoom = 76
        /// First room at which all three tiers (incl. hard) are available.
        public static let allTiersRoom = 126
        /// End of the easy↔medium interpolation bracket (medium fully ramped in).
        public static let mediumRampEndRoom = 125

        /// Hard weight climbs as `(room - allTiersRoom) / hardWeightDivisor`,
        /// capped at `hardWeightCap`.
        public static let hardWeightDivisor = 300.0
        public static let hardWeightCap = 0.5
        /// Of the non-hard probability, this fraction goes to easy (rest medium).
        public static let easyShareOfNonHard = 0.40

        /// Medium's share across the 76–125 bracket: 0 at room 76, 1 at room 125.
        public static func mediumWeight(roomsExplored: Int) -> Double {
            let span = Double(mediumRampEndRoom - mediumStartRoom) // 49
            let t = Double(roomsExplored - mediumStartRoom) / span
            return Swift.min(1.0, Swift.max(0.0, t))
        }

        /// Hard's share at/after room 126 (slow climb, capped).
        public static func hardWeight(roomsExplored: Int) -> Double {
            Swift.min(hardWeightCap, Double(roomsExplored - allTiersRoom) / hardWeightDivisor)
        }
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

        /// Traps cannot spawn before this room (Lost update Part 6). Dark and
        /// flooded are unaffected and may still spawn earlier.
        public static let trapMinRoom = 25

        /// Trap damage (depth-scaled, armour-reduced). Reduced base range in the
        /// Lost update (Part 6) so early traps sting rather than kill.
        public static let trapDamageRange = 5...15
        /// Flooded damage when no boots equipped (environmental, NOT reduced).
        public static let floodedDamageRange = 5...15

        public static func trapChance(depth: Int) -> Int { depth < scalingDepth ? earlyTrapChance : lateTrapChance }
        public static func darkChance(depth: Int) -> Int { depth < scalingDepth ? earlyDarkChance : lateDarkChance }
        public static func floodedChance(depth: Int) -> Int { depth < scalingDepth ? earlyFloodedChance : lateFloodedChance }
    }

    // MARK: - Hunger/thirst decay (Lost update Part 7)

    public enum Decay {
        /// When decay triggers (50% per room, unchanged), each of hunger and
        /// thirst drops by a random 1…this. Lowered from 10 to 7.
        public static let maxPerRoom = 7
    }

    // MARK: - Loot pacing (Lost update Parts 8 & 9)

    public enum Loot {
        /// Loot success threshold: `lucky < threshold`. More forgiving early.
        public static let earlyThreshold = 40   // rooms 0–50
        public static let lateThreshold = 33    // rooms 51+
        /// Crossover room for both the loot threshold and money brackets.
        public static let scalingRoom = 50

        /// Money found on a successful loot, by room bracket. "Big" is the ~20%
        /// high bracket, "small" the ~40% low bracket; else nothing.
        public static let earlyBig = 10...20
        public static let earlySmall = 5...12
        public static let lateBig = 25...40
        public static let lateSmall = 15...25
    }

    // MARK: - Depth-weighted loot material modifier (Lost update Part 11)

    /// Re-weights a loot pick so early rooms favour branches and later rooms
    /// favour scrapmetal. Applied at pick time; the room tables are unchanged.
    public enum LootWeighting {
        /// Before this room, branch is favoured; at/after it, scrapmetal is.
        public static let crossoverRoom = 40
        /// Relative weight bonus to the favoured material (+50%).
        public static let favouredMaterialBonus = 0.5
        /// Relative weight penalty to the disfavoured material (−33%).
        public static let disfavouredMaterialPenalty = 0.33
        /// Integer base weight a neutral entry carries (scaled for clean maths:
        /// favoured = 6·1.5 = 9, disfavoured = 6·0.67 ≈ 4).
        public static let baseWeight = 6
        public static let favouredWeight = Int((Double(baseWeight) * (1.0 + favouredMaterialBonus)).rounded())     // 9
        public static let disfavouredWeight = Int((Double(baseWeight) * (1.0 - disfavouredMaterialPenalty)).rounded()) // 4
    }

    // MARK: - Trader spawning (Lost update Part 2)

    public enum Trader {
        /// Trader rarity (restored to the original): a trader appears when
        /// `randint(1, rarityRollMax) < rarityThreshold` (~12% per room).
        public static let rarityRollMax = 170
        public static let rarityThreshold = 20
        /// Type weights *within* a trader room. Must sum to 100.
        public static let merchantWeight = 60
        public static let medicWeight = 25
        public static let scavengerWeight = 15
    }

    // MARK: - Medic trader (Lost update Part 1)

    public enum Medic {
        /// The pool the Medic stocks from (3 distinct picks per visit).
        public static let pool = ["bandage", "medkit", "medicine", "pills"]
        /// How many distinct items the Medic offers each visit.
        public static let itemCount = 3
        /// Flat discount off the merchant price (25% off → pay 75%).
        public static let discountPercent = 25
        /// Multiplier applied to the merchant price. Derived so it stays in sync
        /// if merchant prices ever change (never hardcode the discounted values).
        public static let priceMultiplier = Double(100 - discountPercent) / 100.0
    }

    // MARK: - Scavenger trader (Part 5a)

    public enum Scavenger {
        /// Base buy-back prices the scavenger pays. Weapon prices are scaled by
        /// remaining durability fraction at sell time (minimum £1).
        public static let sellPrices: [String: Int] = [
            "scrapmetal": 8, "iron": 20, "ironBar": 35,
            // food / consumables — £12 each
            "cannedfood": 12, "chocolate": 12, "carrot": 12, "tomato": 12,
            "mushroom": 12, "waterbottle": 12, "steak": 12,
            // health (Lost update Part 2d: lowered with shop prices)
            "bandage": 9, "medicine": 18, "medkit": 19, "pills": 28,
            // weapons (~40% of shop price)
            "fork": 8, "branch": 8, "knife": 16, "bat": 20, "shovel": 20,
            "crowbar": 20, "sword": 40, "longsword": 60,
            // armour
            "leatherCap": 8, "leatherVest": 9, "leatherBoots": 6,
            "scrapHelmet": 18, "scrapBoots": 12, "scrapChestplate": 20,
            "ironHelmet": 30, "ironBoots": 25, "ironChestplate": 40,
            "steelHelmet": 45, "steelBoots": 40, "steelChestplate": 60,
            // tools
            "grindstone": 50,
        ]
    }

    // MARK: - Grindstone system (Part 5b)

    public enum Grindstone {
        /// Weapon conversion recipes: source weapon + scrap -> better weapon.
        public struct Conversion { public let result: String; public let scrapCost: Int }
        /// A single clean linear chain (Lost update Part 4). Branch has no
        /// conversion; longsword is the end tier. The old crowbar→shovel
        /// downgrade is gone.
        public static let conversions: [String: Conversion] = [
            "fork": Conversion(result: "bat", scrapCost: 2),
            "bat": Conversion(result: "shovel", scrapCost: 3),
            "shovel": Conversion(result: "crowbar", scrapCost: 4),
            "crowbar": Conversion(result: "knife", scrapCost: 5),
            "knife": Conversion(result: "sword", scrapCost: 4),
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

    // MARK: - Crafting yields (Part 1: rope chain)

    public enum Crafting {
        /// Rope crafted per branch (the recipe's single output is multiplied by
        /// this). All other recipes output 1. Trimmed 3 → 2 to offset Garden's
        /// guaranteed branch (branches are more abundant, worth less rope each).
        public static let ropePerBranch = 2

        /// Scrapmetal consumed by the iron craft recipe (Lost update Part 13:
        /// 4 scrapmetal → 1 iron). Mirrors the value in recipes.json.
        public static let ironRecipeCost = 4

        /// Number of items a recipe produces (default 1).
        public static func outputCount(for recipeID: String) -> Int {
            recipeID == "rope" ? ropePerBranch : 1
        }
    }

    // MARK: - Weapon repair (Part 4)

    public enum WeaponRepair {
        public struct Cost: Sendable {
            public let ingredient: String
            public let count: Int
            public let restore: Int
        }
        /// Per-weapon repair: material cost and durability restored per repair.
        public static let costs: [String: Cost] = [
            "branch":    Cost(ingredient: "rope",       count: 1, restore: 8),
            "fork":      Cost(ingredient: "rope",       count: 2, restore: 8),
            "bat":       Cost(ingredient: "scrapmetal", count: 2, restore: 10),
            "shovel":    Cost(ingredient: "scrapmetal", count: 2, restore: 10),
            "crowbar":   Cost(ingredient: "scrapmetal", count: 3, restore: 12),
            "knife":     Cost(ingredient: "scrapmetal", count: 3, restore: 12),
            "sword":     Cost(ingredient: "iron",       count: 3, restore: 15),
            "longsword": Cost(ingredient: "iron",       count: 4, restore: 15),
        ]
    }
}
