import Foundation

/// Repeated-event flavour text (Part 5). Variants live in `prompts.json` so
/// they're easy to extend; one is picked at random per event. Selection uses a
/// dedicated flavour RNG (not the gameplay RNG), so adding variety never shifts
/// any gameplay sequence.
public enum PromptEvent: String, Sendable, CaseIterable {
    case roomEntry
    case lootSuccess
    case lootFailure
    case enemyEncounter
    case escapeSuccess
    case escapeFailure
    case playerHit          // player lands a hit on the enemy
    case playerTakesHit     // enemy lands a hit on the player
    case trapRoom
    case darkRoom
    case floodedRoom
    case merchant
    case scavenger
    case armourBreak
}

public struct Prompts: Sendable {
    /// event rawValue -> variant strings.
    public let pools: [String: [String]]

    public init(pools: [String: [String]]) { self.pools = pools }

    public func variants(_ event: PromptEvent) -> [String] {
        pools[event.rawValue] ?? []
    }

    /// Picks a random variant and substitutes any `{token}` placeholders.
    /// Returns "" only if the pool is somehow empty (never in shipped data).
    public func pick(_ event: PromptEvent,
                     using rng: inout GameRandom,
                     replacing tokens: [String: String] = [:]) -> String {
        let pool = variants(event)
        guard !pool.isEmpty else { return "" }
        var text = rng.choice(pool)
        for (key, value) in tokens {
            text = text.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return text
    }
}

extension Prompts: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        pools = try container.decode([String: [String]].self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(pools)
    }
}
