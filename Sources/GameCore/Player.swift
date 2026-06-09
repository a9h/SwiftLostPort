import Foundation

/// Three armour slots; `total` is the percentage damage reduction:
/// round((head + chest + legs) / 3).
public struct Armour: Codable, Equatable, Sendable {
    public var head: Int = 0
    public var chest: Int = 0
    public var legs: Int = 0

    public init(head: Int = 0, chest: Int = 0, legs: Int = 0) {
        self.head = head
        self.chest = chest
        self.legs = legs
    }

    public var total: Int {
        Int((Double(head + chest + legs) / 3.0).rounded())
    }

    /// finalDamage = round(raw - raw * total / 100)
    public func reducedDamage(_ raw: Int) -> Int {
        Int((Double(raw) - Double(raw) * Double(total) / 100.0).rounded())
    }
}

public struct Player: Codable, Equatable, Sendable {
    public var currentHealth: Int = 100
    public var maxHealth: Int = 100
    public var money: Int = 50
    public var hunger: Int = 100
    public var thirst: Int = 100
    public var armour: Armour = Armour()

    public init() {}
}
