# LOST — SwiftUI port

A native SwiftUI port of *Lost*, a tiny Python terminal dungeon-crawler. Same
numbers, same probabilities, same slightly janky charm — but with buttons,
emoji, bars and animations instead of `input()` prompts.

```
╔══════════════════════╗
║   L  O  S  T   🚪    ║
╚══════════════════════╝
```

Targets **iOS 17+** and **macOS 14+**.

## Layout

| Target | What it is |
|---|---|
| `GameCore` | Pure game logic — no UI, no `print`. `Player`, `Inventory`, `Armour`, `Enemy`, `GameData`, and an `@Observable` `GameState` that owns all randomness, combat, looting, crafting and the economy. Fully unit-testable with injectable RNG (`ScriptedGameRandom`/`SeededGameRandom`) and persistence (`MemorySaveStore`). |
| `GameCore/Resources` | The original's data as bundled JSON (`rooms`, `weapons`, `breakdown`, `stats`, `recipes`, `shop`), decoded with `Codable`. The game stays data-driven. |
| `LostUI` | SwiftUI views observing `GameState`: HUD (❤️ 🍗 🚰 💷), rooms with tappable 🚪 doors, encounters, the trader, gambling, and sheets for inventory/stats/armour/crafting/breakdown/equip/drop/use/save. |
| `LostApp` | Executable app target (`@main`). |
| `GameCoreTests` | 32 tests: combat damage & armour reduction, hunger/thirst decay, crafting deduction, loot money brackets, gambling payouts, trader stock, save/load round-trip, plus a randomized soak run. |

## Build & run

```sh
# macOS app
swift run LostApp

# tests
swift test
```

**iOS:** open the package in Xcode (`open Package.swift`), or add `LostUI` to
an iOS app target and set `LostRootView()` as its content view. The whole
package cross-compiles for the simulator:

```sh
swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -Xswiftc -target -Xswiftc arm64-apple-ios17.0-simulator
```

## What matches the original

All the numbers: 50% chance of 1–10 hunger **and** thirst decay per room;
death at ≤0 and warnings under 20; trader on `randint(1,170) < 20`; enemies on
`randint(1,130) < 25` (blocked right after a fight by the `previous` flag);
1–3 doors; loot luck `randint(1,101/76/51) < 33` by door count; enemy
difficulty `randint(1,200)` → hard <25 (250 HP) / medium ≤125 (150 HP) / easy
otherwise (100 HP); per-difficulty damage (50–90 / 25–50 / 2–25) and coin
drops (100–150 / 30–75 / 10–30); escape fails under 30; the torch's 25% scare;
armour reduction `round(raw − raw·total/100)` with `total = round((head+chest+legs)/3)`;
every weapon damage array, heal/food table, recipe, breakdown yield and shop
price. Messages keep the original wording (lightly cleaned).

## What was deliberately fixed (the ⚠️ list)

- **Menus aren't recursive functions.** Game flow is a `Screen` enum
  (`title / room / encounter / trader / gameOver`) the UI switches on.
- **Inventory is `[itemID: count]`** instead of duplicated `"\nknife"`
  strings, browsed by category with quantities ("🔦 Torch ×4").
- **Crafting deducts correctly** — the original's `=-` typo is gone; a craft
  consumes exactly its recipe.
- **The trader actually sells weapons** — the rolled weapon used to land in
  the wrong field and never appear. It now shows up and is buyable, **with**
  the insufficient-funds check the original skipped for weapons.
- **Loot money brackets de-overlapped**: key 1–125 → over 100 pays £25–40,
  under 50 pays £15–25, 50–100 pays nothing (same intent, no overlap).
- **50/50 works as labelled** — the menu said "50/50" but only accepted
  "5050"; play-again was broken. Both work, and you can't bet more than you
  have (new sanity check, also applied to H/L).
- **H/L reimplemented cleanly** (the original crashed on a nonexistent
  `.content` and inverted comparisons): a secret 1–100 is rolled, the hint
  comes from the same half, higher/lower pays 1.5×, calling the exact number
  pays 8×, a wrong call loses the bet.

## Design choices

- Saves are JSON via `Codable` in Application Support; **two slots** (the
  original had one), with overwrite confirmation. Save is a room action, as
  in the original; the title screen offers Continue when a save exists.
- The combat "loop" is interactive: pick a weapon, see your hit land, take
  the counter-hit — one round per tap, matching the original's turn order.
- `run` keeps re-rolling escape just like the original, so one tap can cost
  several failed-escape hits before you slip away.
- The hidden `admin` menu survives as a debug panel: long-press the **LOST**
  logo (title screen or HUD).
- Typewriter text reveal is kept for the message feed; looting, hits, coin
  flips and game-over all animate.
- Emoji map: rooms 🍳🛏️🛁🪜🌳, enemies 🧟👹🐉, weapons 🔪🍴🏏🔦🪛🌿⛏️🗡️⚔️,
  consumables 🍅🥕💧🥩🍫🍄🥫, healables 🧰💊🩹💉, crafting 🔩⛓️, armour 🪖🦺👢,
  tools 🪨. (Shovel uses ⛏️ since U+1FA8F isn't widely available yet.)
