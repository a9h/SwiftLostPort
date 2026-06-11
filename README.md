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
| `GameCore` | Pure game logic — no UI, no `print`. `Player`, `Inventory`, `Armour`, `Enemy`/`BossKind`, `GameData`, `Balance`, and an `ObservableObject` `GameState` that owns all randomness, combat, looting, crafting, bosses and the economy. Fully unit-testable with injectable RNG (`ScriptedGameRandom`/`SeededGameRandom`) and persistence (`MemorySaveStore`). |
| `GameCore/Resources` | The original's data as bundled JSON (`rooms`, `weapons`, `breakdown`, `stats`, `recipes`, `shop`, `prompts`), decoded with `Codable`. The game stays data-driven. |
| `LostUI` | SwiftUI views observing `GameState`: HUD (❤️ 🍗 🚰 💷 + rooms/poison/modifier), rooms with tappable 🚪 doors, boss encounters, merchant/scavenger traders, gambling, a reusable tabbed list (`TabbedPanel`), and sheets for inventory/stats/armour/Workbench/equip/drop/use/save. |
| `LostApp` | Executable app target (`@main`). |
| `GameCoreTests` | 100 tests: armour curve/tiers/durability/breaking/repair, weapon repair, rope + leather crafting chain, removed-recipe checks, prompt-pool variety, slot specialisation, save migration, depth ratio, weapon/enemy damage & weighted HP, the full boss sequence + specials, room modifiers, the Workbench, hardened blade, tabbed-list sort, scavenger pricing, save/load round-trip, plus a randomized soak run. |

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

---

## What changed in this update (rebalance + features)

A large balance + feature pass layered on the original port. Every tunable
number lives in [`Balance.swift`](Sources/GameCore/Balance.swift); the save
format is now **v3** and loads older saves with sensible defaults.

### Armour — diminishing-returns soft cap
The flat `round((head+chest+legs)/3)%` model is replaced by a soft cap that
can never trivialise the game: `pct = 0.85·raw/(raw+120)`, a flat 2 HP off
every hit, clamped so a hit is always ≥1 and never heals. One `reducedDamage()`
function handles every damage route. Constants: `Balance.Armour.ceiling/scale/flat`.

### Depth : room ratio (1:2)
`depth` is now internal and advances once every **two** rooms
(`depth = roomsExplored / 2`). The HUD shows **Rooms Explored**, never depth.
So scaling starts at depth 30 = 60 rooms, the first boss at depth 50 = 100
rooms — matching the ~100–200 room arc to a longsword.

### Combat rebalance
- **Weapon damage** (smoother curve, [`weapons.json`](Sources/GameCore/Resources/weapons.json)):
  branch 12–22, fork 22–32, bat 30–42, shovel 28–45, crowbar 35–50, knife
  40–55, sword 58–75, longsword 80–100.
- **Enemy damage** (`Balance.EnemyCombat`): easy 3–12, medium 15–35, hard 28–55.
- **Enemy HP** is a depth-weighted roll (quadratic low-early/high-late bias +
  ±15 jitter), clamped per difficulty (easy 75–115, medium 120–150, hard
  155–200). No enemy scaling below depth 30.

### Boss system — fixed sequence + specials
Bosses gate the run at depth 50/100/150/200/250 (= rooms 100…500), in order,
each a tunable stat block in `Balance.Bosses`:

| Boss | HP | Special |
|---|---|---|
| 🤠 Cowboy | 360 | 50% dodge per round |
| 👻 Ghoul | 320 | 50% poison-on-hit |
| 🧙 Plague Doctor | 340 | one-time self-heal below 50% |
| 🗡️ Warlord | 380 | hits twice/round, torch-immune |
| 🐺 Packmaster | 340 | 20%/round summon for extra damage |

Each has a unique banner/decoration/intro and its own coin + item drops.
Defeating one advances `bossSequenceIndex` (wrapping) and `nextBossDepth += 50`.
Completing a full cycle sets **`maxDamageFlag`** — thereafter every boss hit
(and summon) deals the top of its range, marked with 💀 in the banner.

### UI fixes + modifier frequency
- The **Loot** button is filled green while a room is lootable, disabled once
  picked clean.
- Room-modifier chances now scale with depth (`Balance.RoomModifiers`): early
  (depth < 50) trap/dark/flooded 5/5/4%, late 9/8/7% — far calmer early runs.

### Loot & economy
- Six new rooms (Scrapyard, Street, Tunnel, Workshop, Abandoned Shop, Garage);
  scrapmetal is now common; the **Tunnel trends dark**.
- **Grindstone** costs £125 (from £225) and powers two functions, available
  from an owned grindstone *and free at either trader* (one shared
  implementation): **convert** a weapon (knife+4🔩→sword, bat+3→crowbar,
  crowbar+5→shovel, sword+6→longsword) and **sharpen** a specific weapon
  instance (+5 damage/level, 3🔩 each, per-weapon caps). Upgrade level is
  tracked per `WeaponInstance`, shown as e.g. "🗡️ Sword +2 (24/30)", and
  persists.
- The **scavenger trader** (~40% of traders, 🪤) buys your items instead of
  selling; weapon buy-back scales with remaining durability. Prices in
  `Balance.Scavenger`.
- Confirmed the door-luck logic is correct (more doors = luckier, success when
  `lucky < 33`) and pinned it with a test.

### Tests
`GameCoreTests` covers the armour curve, the 1:2 ratio, weapon/enemy damage and
weighted HP, the full boss sequence and every special, post-cycle max damage,
room-modifier frequency, grindstone convert/upgrade deduction and caps,
scavenger sell pricing, and a full save/load round-trip across all new state.

---

## What changed in the "Lost" update (Workbench, armour, healing, tabbed UI)

A second feature pass on top of the rebalance. The save format is now **v4**
and migrates v1–v3 saves (especially the old summed-integer armour) without
crashing. New balance lives in `Balance.swift`; recipes/rooms in the JSON.

### Tabbed list UI
A reusable `TabbedPanel` (plus `TabItemList`/`QuietPlaceholder`) replaces every
dropdown / `<`–`>` category control. A horizontal, horizontally-scrolling row
of pressable tabs sits above the selected category's items, **sorted by
quantity (most owned first), alphabetical by name on ties**
(`Inventory.itemsByQuantity`). Per-instance weapons group by type, most-owned
first, with instances shown durability/upgrade-first. Empty tabs show a quiet
"Nothing here yet." Applied to the **Inventory** (Consumables, Weapons,
Healables, Crafting, Armour, Tools), the **Use** menu (Consumables + Healables
only — the usable categories), the **scavenger sell** menu (tabbed by category),
and the **Workbench**.

### Workbench consolidation
The three old metalworking menus (grindstone, breakdown, crafting) are merged
into one **Workbench** sheet with three tabs:
- **Craft** — make items from materials (armour pieces, 🩹/🧰 healing, 🧱 iron
  bars, 🔦 torches, …).
- **Upgrade** — weapon convert (knife→sword…) + sharpen, **reforge armour a
  tier**, and **harden a blade**. (Armour upgrades live here, not in Craft —
  "Upgrade" = improve existing gear; documented choice.)
- **Breakdown** — grind weapons into 🔩.

It opens from **three access points that all call the same shared functions**:
an owned 🪨 grindstone (room), the merchant, and the scavenger. **Crafting and
breakdown are now available free at both traders** — an intended power increase.
Breakdown no longer self-checks for a grindstone; access is the gate. The old
`CraftingSheet`/`BreakdownSheet`/`GrindstoneSheet` and their entry points are
gone.

### Armour rework (tiers + slot specialisation)
One piece per slot, upgraded up a material ladder — no more stacking duplicates.
- **Tiers** Leather → Scrap → Iron → Steel per slot, with base values in
  `Balance.Armour.tierBaseValue` (head 10/20/30/42, chest 12/25/38/52, legs
  8/15/22/30). `rawArmour` sums the equipped tiers and feeds the unchanged
  diminishing-returns curve.
- **Equip** a found/crafted piece into an empty slot for free; equipping over a
  filled slot swaps (old piece returns to the pack). **Upgrade** at the
  Workbench consumes the current piece in place + materials
  (`Balance.Armour.upgradeCost`: →Scrap 5🔩, →Iron 4⛓️, →Steel 3🧱).
- **Slot specialisation:** 🦺 chest is the damage backbone (highest values);
  🪖 head gives tier-scaled **poison resist** (`poisonResistPercent`: 10/20/35/50%);
  👢 boots give tier-scaled **flood protection** (`floodReduction`:
  leather 50%, scrap 75%, iron/steel immune). Surfaced on the armour screen.
- **Migration:** old summed-int slots map to the nearest tier by base value
  (0 → empty), handled in `Armour`'s `Codable`.

### Healing availability
- More health loot: heavier bandages/medkits in Bathroom, weapons-room
  Workshop and AbandonedShop now stock medical supplies, and a new health-dense
  **Pharmacy** room (💊) — eligible for room modifiers like any other.
- Craftable heals: **Bandage** (2🔩 + 1💧) and **Medkit** (2🩹 + 1💉) give a
  deterministic route off the loot RNG.

### New crafting recipes (`recipes.json`)
Scrap Helmet 5🔩, Scrap Chestplate 8🔩, Scrap Boots 3🔩 (iron/steel tiers come
via the upgrade path, not crafted from scratch — documented choice); Iron Bar
3⛓️ + 2🔩; Bandage 2🔩 + 1💧; Medkit 2🩹 + 1💉; Torch 1🌿 + 1🔩. Hardened Blade
(Upgrade tab): any durability-tracked weapon + 1🧱 → +50% max durability
(`Balance.Durability.hardenedMultiplier`).

### New `Balance.swift` constants
`Armour.tierBaseValue`, `Armour.baseValue`, `Armour.nearestTier`,
`Armour.upgradeCost`, `Armour.poisonResistPercent`, `Armour.floodReduction`;
new scavenger sell prices for the leather/steel armour tiers. (Existing
`Armour.ceiling/scale/flat`, `Durability.hardenedMultiplier` reused.)

---

## What changed in the "Lost" update (rope, armour durability, repair, prompts)

A sixth feature pass. Save format is now **v5** and loads v1–v4 saves gracefully
(equipped pieces without stored durability load at full). New mechanical tuning
is in `Balance.swift`; recipe ingredient lists stay in `recipes.json`; flavour
text lives in the new `prompts.json`.

### Rope material + crafting chain
- New early material **rope** (🪢, crafting category). **Rope recipe: 1 branch →
  3 rope** (the multi-output yield is `Balance.Crafting.ropePerBranch`).
- **Leather armour is rope-crafted:** Leather Cap 4 rope, Leather Vest 6 rope,
  Leather Boots 3 rope — the only craftable armour, and the way into each slot.
- **Torch recipe changed** to `1 branch + 1 rope` (was branch + scrapmetal); the
  old entry is removed.

### Armour durability + breaking
- Each equipped piece has a durability pool by slot/tier
  (`Balance.Armour.durabilityPool`: leather 25/35/28 … steel 75/100/85). Fresh
  craft/upgrade starts full; tracked per slot and persisted.
- **Every hit the player takes** (combat, failed-run, no-weapon, "too long
  looking", trap-room) wears **1 durability on 1–2 random equipped slots** (50/50).
  When boots negate/reduce a flood, the boots wear 1.
- At 0 a piece **breaks**, emptying the slot and dropping tier-scaled scrap
  (`Balance.Armour.breakDrop`: leather→1 rope, scrap→2🔩, iron→2🔩+1⛓️,
  steel→3🔩+1🧱), with a flavour message. A broken slot means crafting fresh
  leather and climbing the tiers again.

### Armour repair (all tiers, diminishing returns)
At the Workbench Upgrade tab. Restore amount scales inversely with current
durability: `repairAmount = max(ceil(max·REPAIR_FLOOR), round(max·REPAIR_BASE·
(1−cur/max)))`, capped at max. `Balance.Armour.repairBase = 0.6`,
`repairFloor = 0.10`. Fixed material cost per tier/slot (`Armour.repairCost`):
rope→scrapmetal→iron→ironBar by tier; chest costs 1 more than head/legs. A 🔧
shows next to any piece below max that you can currently afford to repair.

### Armour crafting rework
Direct-craft **Scrap/Iron/Steel** armour recipes were removed from
`recipes.json` (scrap helmet/chestplate/boots — and the old raw-iron-from-scrap
recipe). Leather is the only craftable armour; all higher tiers are reached only
by **upgrading** an equipped piece (Leather→Scrap 5🔩, Scrap→Iron 4⛓️,
Iron→Steel 3🧱), which sets full durability of the new tier. Craft tab now shows:
rope, leather cap/vest/boots, torch, bandage, medkit, iron bar, hardened blade.

### Weapon repair
At the Workbench Upgrade tab, per-instance, preserving upgrade level
(`Balance.WeaponRepair.costs`): branch 1 rope/+8, fork 2 rope/+8, bat·knife 2🔩/
+10, shovel 3🔩/+10, crowbar 3🔩/+12, sword 3⛓️/+15, longsword 4⛓️/+15. Capped at
max; a 🔧 marks affordable, below-max weapons in the lists.

### Expanded prompt pool
Repeated-event flavour now lives in `prompts.json` as arrays (5–6 variants each)
for: room entry, loot success/failure, enemy encounter, escape success/failure,
player-lands-hit, player-takes-hit, trap/dark/flooded entry, merchant/scavenger
appearance, and armour-break. A dedicated flavour RNG (separate from the gameplay
RNG) picks one per event, so the variety never disturbs gameplay determinism.

### New `Balance.swift` constants
`Crafting.ropePerBranch` / `Crafting.outputCount`; `Armour.durabilityPool` /
`Armour.durability`; `Armour.breakDrop`; `Armour.repairBase` /
`Armour.repairFloor` / `Armour.repairAmount` / `Armour.repairCost`;
`WeaponRepair.costs`.
