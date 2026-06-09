import Foundation

/// Quantity-based inventory: replaces the original's duplicated raw strings
/// (`"\nknife"`) with `[itemID: count]`.
public struct Inventory: Codable, Equatable, Sendable {
    public private(set) var counts: [String: Int] = [:]

    public init() {}
    public init(counts: [String: Int]) {
        self.counts = counts.filter { $0.value > 0 }
    }

    public func count(of itemID: String) -> Int { counts[itemID] ?? 0 }
    public func has(_ itemID: String) -> Bool { count(of: itemID) > 0 }
    public var isEmpty: Bool { counts.isEmpty }
    public var totalItemCount: Int { counts.values.reduce(0, +) }

    public mutating func add(_ itemID: String, count: Int = 1) {
        guard count > 0 else { return }
        counts[itemID, default: 0] += count
    }

    /// Removes up to `count` of the item. Returns false (and removes nothing)
    /// if the player doesn't own enough.
    @discardableResult
    public mutating func remove(_ itemID: String, count: Int = 1) -> Bool {
        guard count > 0, self.count(of: itemID) >= count else { return false }
        let remaining = self.count(of: itemID) - count
        if remaining == 0 {
            counts.removeValue(forKey: itemID)
        } else {
            counts[itemID] = remaining
        }
        return true
    }

    /// Sorted (id, count) pairs for one category page of the inventory UI.
    public func items(in category: ItemCategory) -> [(id: String, count: Int)] {
        counts
            .filter { ItemCatalog.info($0.key).category == category }
            .sorted { $0.key < $1.key }
            .map { (id: $0.key, count: $0.value) }
    }

    public var allItems: [(id: String, count: Int)] {
        counts.sorted { $0.key < $1.key }.map { (id: $0.key, count: $0.value) }
    }
}
