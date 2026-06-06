# Project State — Hexagon Legends

**Engine:** Godot 4.6.2
**Genre:** HoMM3-inspired turn-based strategy roguelike
**Last updated:** 2026-06-06 (session 7)

---

## Architecture

### Autoloads (6)
| System | Purpose |
|---|---|
| `GameState` | Single source of truth for active run (phase, resources, hero, day/week/month, **player_army**, **map_enemies**, **combat_result**) |
| `EventBus` | Global signal bus — all decoupled communication |
| `DataManager` | Loads/caches `.tres` resource files at startup; **creates default test units if no files exist** |
| `SceneManager` | Scene transitions with black fade; **scene preservation** (hides AdventureMap during combat, restores on return); 14 registered scene paths |
| `SaveManager` | Run save (single slot) + meta save (permanent) with JSON I/O |
| `AudioManager` | Music cross-fade + SFX pool |

### Data Resources (5 types)
- `UnitData` — Static unit stats, abilities, cost, sprites
- `HeroData` — Archetype data, stat weights, specialty, skill bias
- `HeroState` — Mutable per-run hero state (skills, spells, artifacts, army, serialization)
- `ArtifactData` — Artifact stats, slot, tier, bonuses
- `SpellData` — Spell stats, school, damage formula, target type

No `.tres` files exist yet — all units use runtime-created defaults via `DataManager._create_default_units()`.

### Core Systems
- `StateMachine` (Node) — Reusable FSM base with `State` inner class, transitions, input routing
- `CombatTurnManager` (RefCounted) — Speed-sorted turn queue, wait queue, round management
- `HexGrid` (RefCounted) — Cube-coordinate hex grid (pointy-top, odd-r), A* pathfinding, LoS
- `SquareGrid` (RefCounted) — 8-directional square grid for adventure map, Chebyshev A*
- `DamageCalculator` (RefCounted) — Static HoMM3 damage formula with luck, morale, ranged penalty
- `FogOfWar` (Sprite2D + shader) — Pixelated fog overlay using noise texture, BFS gradient edge, Euclidean visibility
- `RoadGenerator` (RefCounted) — Building-to-building road connections only; growing-connected-set approach (Prim's-like) using cardinal-only BFS
- `Lighthouse` (inline in AdventureMap) — 3x3 building with y-sorting (two TileMapLayer instances at z=1/z=3); only center tile blocks movement; activation reveals 15-tile Euclidean fog radius
- `MovementCost` (inline in AdventureMap) — Per-tile movement cost calculation: road tiles cost 70 (30% less); uses per-tile cost for path preview and deduction
- `BuildingPlacement` (inline in AdventureMap) — Seeded RNG placement of 5 vault buildings (5x3 tiles) and 1 lighthouse (3x3); building footprint blocks pathfinding except entrance; **middle center tile now blocked for player, unblocked for roads** (same pattern as lighthouse)
- `EnemyPlacement` (inline in AdventureMap) — Procedural enemy placement after buildings, before obstacles; seeded RNG, ~25 enemies per run from 3 unit types; avoids buildings and start area
- `HUD` (inline in AdventureMap) — Movement points label, army composition label (merged stacks with unit names), tile info, End Turn button

### Cross-Scene Combat Flow
- `GameState.player_army: Array[Dictionary]` — player's current army, persisted across AdventureMap ↔ CombatScene transitions
- `GameState.map_enemies: Dictionary` — enemies placed on adventure map tiles, keyed by `"x,y"` string; populated procedurally in `_place_enemies()` during map generation
- `GameState.combat_result: Dictionary` — communication channel: AdventureMap writes `enemy_key`, CombatScene writes `result` + `player_army`, AdventureMap reads on re-entry
- **Scene preservation** — AdventureMap hidden (not freed) during combat via SceneManager
- `MainMenu` bypasses missing FactionSelect scene — "New Run" calls `GameState.init_run()` directly

### Shaders
- `fog_of_war.gdshader` — CanvasItem shader for fog of war, noise-driven blue-grey mist

---

## Milestone Status

### Milestone 0 — Foundation (COMPLETE)
All 6 autoloads, 5 resource types, folder structure, StateMachine base class, default unit data generation

### Milestone 1 — Combat Prototype (COMPLETE)
HexGrid with A*/LoS/BFS, CombatTileMap with 4 layers, UnitStack with HP/effects, CombatTurnManager with speed queue, DamageCalculator with full HoMM3 formula, CombatScene with animated movement/melee/ranged/AI/combat-end, test battle, Camera2D

### Milestone 2 — Full Combat (NOT STARTED)
Spells, hero integration, war machines, siege, special abilities, advanced AI — all unimplemented. Morale/luck code exists but has no visible feedback. Large (2-hex) units not implemented.

### Milestone 3 — Adventure Map (PARTIALLY COMPLETE)
**Implemented:**
- SquareGrid with A*, AdventureMap with 160x110 grid/movement/path preview/Camera2D/HUD
- Fog of War with noise shader/BFS gradient/Euclidean radius
- Enemy placement on map tiles, combat encounter triggers — enemies block pathfinding passage; procedurally placed (~25 per run) instead of 2 hardcoded
- Scene preservation (AdventureMap persists across battles with all state intact)
- Deterministic obstacle seeding, combat result processing on return
- Free camera edge-scrolling, Space to snap camera to player
- Enemy sprites hidden by fog of war, player position saved/restored across combat
- Auto-init for editor testing
- Building placement (5 vaults + 1 lighthouse) with collision, entrances, road connections
- Lighthouse y-sorting, fog reveal activation
- Building-to-building road connections with per-tile movement cost (road = 70, normal = 100)
- Varied ground tiles from 3x3 atlas (9 ground variations, seeded RNG)
- Army HUD label showing merged stack counts, unit names from DataManager, total count
- Procedural enemy placement in `_place_enemies()` — avoids buildings and start area, 3 enemy types

**Missing:** map objects (mines, chests, dwellings), time system, full HUD (resources, minimap, hero stats), terrain variety, underground layer, fog save/load, seeded generation for map features beyond buildings/obstacles/enemies

### Milestone 4+ — Not started

---

## Key Architecture Decisions

- **Square tiles 3x3 atlas** — `square_tiles.png` is 96x96 (3x3 tiles, 32x32 each). All 9 tiles are ground variations; obstacle tiles removed from the atlas. Obstacles still block pathfinding but keep whatever ground tile was placed.
- **Seeded ground variation** — Ground tile selection uses `_get_map_seed() ^ 0xDEAD` for deterministic per-run terrain patterns.
- **Map size 10x area** — MAP_COLS 50→160, MAP_ROWS 35→110 (sqrt(10) scaling). Constants scaled proportionally (obstacles: 80→800, movement 1500→4500).
- **Procedural enemy placement** — Enemies are no longer hardcoded in `GameState.init_default_run_data()`. `_place_enemies()` runs after building placement (avoids footprints), before obstacle placement (obstacles avoid enemies). Uses `_get_map_seed() ^ 0xCAFE` for deterministic placement. Target count = map area / 700, clamped 5–80 (~25 for current map).
- **Army HUD via `_format_army_string()`** — Merges duplicate unit stacks, resolves display names from `DataManager.get_unit()`, shows total count. `Resource.get()` takes one argument (unlike Dictionary's two-argument version).
- **Enemy placement order** — Buildings → enemies → obstacles → roads. This ensures enemies don't overlap buildings, and obstacles don't block enemy tiles.
- **Vault building collision** — Only bottom-row tiles 1–3 (0-indexed) are open for player entry. Middle center tile is blocked for player pathfinding but unblocked for road BFS (same pattern as lighthouse). This prevents players from walking into the building interior while allowing roads to pass underneath.
