import Foundation

/// What the trader has for sale this visit. Rolled once per appearance.
public struct ShopStock: Equatable, Sendable {
    public var foods: [String]
    public var tool: String?
    public var weapon: String?

    public var allItemIDs: [String] {
        var ids = foods
        if let tool { ids.append(tool) }
        if let weapon { ids.append(weapon) }
        return ids
    }

    public func contains(_ itemID: String) -> Bool { allItemIDs.contains(itemID) }
}

/// An in-progress Higher/Lower round.
public struct HLRound: Equatable, Sendable {
    public let bet: Int
    public let hint: Int
    let secret: Int
}

public struct GambleResult: Equatable, Sendable {
    public let won: Bool
    public let exact: Bool
    /// Net change to the player's money (negative on a loss).
    public let netChange: Int
    /// What actually happened, e.g. "heads" or "the number was 73".
    public let reveal: String
}

public enum CoinSide: String, CaseIterable, Sendable {
    case heads, tails
}

public enum HLGuess: Equatable, Sendable {
    case higher
    case lower
    case exact(Int)
}

public extension GameState {

    internal func startTrader() {
        loadShop()
        screen = .trader
        say("You have come across a wild trader, who is willing to sell items to you for a fee. The trader will also play games with you...", .narration)
    }

    /// `loadShop` — two distinct foods, a tool almost always, a weapon ~50%
    /// of the time. (Original bug fixed: the weapon roll was stored in the
    /// wrong field so weapons never appeared; here it lands in `weapon`.)
    private func loadShop() {
        let foodNames = data.shop.food.keys.sorted()
        var foods: [String] = []
        while foods.count < 2 {
            let food = rng.choice(foodNames)
            if !foods.contains(food) { foods.append(food) }
        }
        var tool: String?
        if rng.int(in: 1...100) < 100 {
            tool = rng.choice(data.shop.tools.keys.sorted())
        }
        var weapon: String?
        if rng.int(in: 1...50) > 25 {
            weapon = rng.choice(data.shop.weapons.keys.sorted())
        }
        shopStock = ShopStock(foods: foods, tool: tool, weapon: weapon)
    }

    func price(of itemID: String) -> Int? {
        data.shop.price(of: itemID)
    }

    /// Buy a stocked item. The insufficient-funds check applies to every
    /// item type, including weapons (fixing the original's omission).
    func buy(_ itemID: String) {
        guard screen == .trader,
              let stock = shopStock, stock.contains(itemID),
              let price = price(of: itemID) else { return }
        guard player.money >= price else {
            say("You do not have enough money for this item.", .warning)
            return
        }
        player.money -= price
        inventory.add(itemID)
        say("You bought a \(ItemCatalog.label(itemID)) for £\(price).", .reward)
    }

    func leaveTrader() {
        guard screen == .trader else { return }
        shopStock = nil
        hlRound = nil
        say("You wave the trader goodbye and move on.", .narration)
        generateRoom()
    }

    // MARK: - 50/50 (coin flip)

    /// Win: stake comes back as bet × 1.5 (net +half the bet).
    /// Loss: the bet is gone. Bets are clamped to what you can afford.
    @discardableResult
    func playCoinFlip(choice: CoinSide, bet: Int) -> GambleResult? {
        guard screen == .trader else { return nil }
        guard validateBet(bet) else { return nil }
        let coin: CoinSide = rng.int(in: 1...2) == 1 ? .heads : .tails
        let result: GambleResult
        if coin == choice {
            let payout = Int((Double(bet) * 1.5).rounded())
            player.money += payout - bet
            result = GambleResult(won: true, exact: false, netChange: payout - bet, reveal: coin.rawValue)
            say("The coin landed on \(coin.rawValue) — you won £\(payout - bet)! New balance: £\(player.money)", .reward)
        } else {
            player.money -= bet
            result = GambleResult(won: false, exact: false, netChange: -bet, reveal: coin.rawValue)
            say("The coin landed on \(coin.rawValue) — you lost £\(bet). New balance: £\(player.money)", .warning)
        }
        return result
    }

    // MARK: - H/L (higher/lower)

    /// Starts a round: a secret 1–100 is rolled and the player is shown a
    /// hint from the same half (secret > 50 → hint 50–100, else 1–50).
    @discardableResult
    func startHigherLower(bet: Int) -> Bool {
        guard screen == .trader, hlRound == nil else { return false }
        guard validateBet(bet) else { return false }
        let secret = rng.int(in: 1...100)
        let hint = secret > 50 ? rng.int(in: 50...100) : rng.int(in: 1...50)
        hlRound = HLRound(bet: bet, hint: hint, secret: secret)
        say("The trader whispers: \"the number is somewhere around \(hint)...\" Higher or lower?", .narration)
        return true
    }

    /// Resolve the round. Correct higher/lower pays bet × 1.5; guessing the
    /// exact number pays bet × 8; otherwise the bet is lost.
    @discardableResult
    func guessHigherLower(_ guess: HLGuess) -> GambleResult? {
        guard let round = hlRound else { return nil }
        hlRound = nil
        let won: Bool
        let exact: Bool
        switch guess {
        case .higher:
            won = round.secret > round.hint
            exact = false
        case .lower:
            won = round.secret < round.hint
            exact = false
        case .exact(let number):
            exact = number == round.secret
            won = exact
        }
        let reveal = "the number was \(round.secret)"
        let result: GambleResult
        if exact {
            let net = round.bet * 8 - round.bet
            player.money += net
            result = GambleResult(won: true, exact: true, netChange: net, reveal: reveal)
            say("Unbelievable — \(reveal)! Exact match pays 8×: you won £\(net)! New balance: £\(player.money)", .reward)
        } else if won {
            let payout = Int((Double(round.bet) * 1.5).rounded())
            let net = payout - round.bet
            player.money += net
            result = GambleResult(won: true, exact: false, netChange: net, reveal: reveal)
            say("Correct — \(reveal). You won £\(net)! New balance: £\(player.money)", .reward)
        } else {
            player.money -= round.bet
            result = GambleResult(won: false, exact: false, netChange: -round.bet, reveal: reveal)
            say("Wrong — \(reveal). You lost £\(round.bet). New balance: £\(player.money)", .warning)
        }
        return result
    }

    /// You can only bet whole pounds you actually have (original had no check).
    private func validateBet(_ bet: Int) -> Bool {
        guard bet > 0 else {
            say("The trader laughs at your bet of £\(bet).", .info)
            return false
        }
        guard bet <= player.money else {
            say("You can't bet £\(bet) — you only have £\(player.money)!", .warning)
            return false
        }
        return true
    }
}
