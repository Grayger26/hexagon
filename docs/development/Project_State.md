# Project State — Hexagon Legends

**Engine:** Godot 4.6.2
**Genre:** HoMM3-inspired turn-based strategy roguelike
**Last updated:** 2026-06-03 (session 2)

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
- `RoadGenerator` (RefCounted) — **Building-to-building road connections only**; growing-connected-set approach (Prim's-like) using cardinal-only BFS; no random road network
- `BuildingPlacement` (inline in AdventureMap) — Seeded RNG placement of 7 vault buildings (5×3 tiles); footprint blocks pathfinding except entrance opening (bottom row col 1-3) and middle center (col 2) for road traversal; rendered on dedicated TileMapLayer below fog overlay

### Cross-Scene Combat Flow
- `GameState.player_army: Array[Dictionary]` — player's current army, persisted across AdventureMap ↔ CombatScene transitions
- `GameState.map_enemies: Dictionary` — enemies placed on adventure map tiles, keyed by `"x,y"` string
- `GameState.combat_result: Dictionary` — communication channel: AdventureMap writes `enemy_key`, CombatScene writes `result` + `player_army`, AdventureMap reads on re-entry
- **Scene preservation** — AdventureMap is hidden (not freed) during combat via SceneManager; restored on return with all state intact (obstacles, player position, fog, HUD, enemy visibility, road tiles)
- `MainMenu` bypasses missing FactionSelect scene — "New Run" calls `GameState.init_run()` directly and transitions to `AdventureMap`
- `AdventureMap` auto-initializes `GameState` if `run_active` is false (handles running from editor)

### Shaders
- `fog_of_war.gdshader` — CanvasItem shader for fog of war, noise-driven blue-grey mist

---

## Milestone Status

### Milestone 0 — Foundation (COMPLETE)
All 6 autoloads, 5 resource types, folder structure, StateMachine base class, default unit data generation

### Milestone 1 — Combat Prototype (COMPLETE)
HexGrid with A*/LoS/BFS, CombatTileMap with 4 layers, UnitStack with HP/effects, CombatTurnManager with speed queue, DamageCalculator with full HoMM3 formula, CombatScene with animated movement/melee/ranged/AI/combat-end, test battle, Camera2D

### Milestone 2 — Full Combat (NOT STARTED)
Spells, hero integration, war machines, siege, special abilities, advanced AI — all unimplemented. Morale/luck code exists in CombatScene but has no visible feedback. Large (2-hex) units not implemented.

### Milestone 3 — Adventure Map (PARTIALLY COMPLETE)
**Implemented:**
- SquareGrid with A*, AdventureMap with 50×35 grid/movement/path preview/Camera2D/HUD
- Fog of War with noise shader/BFS gradient/Euclidean radius
- Enemy placement on map tiles, combat encounter triggers
- Scene preservation (AdventureMap persists across battles with all state intact)
- Deterministic obstacle seeding, combat result processing on return
- Free camera edge-scrolling, Space to snap camera to player
- Enemy sprites hidden by fog of war, player position saved/restored across combat
- Auto-init for editor testing
- **Building placement** — 7 vault buildings placed on the map with 5×3 tile footprint, collision blocking (entrance tiles open), rendered on BuildingLayer TileMapLayer, hidden by fog in unexplored areas
- **Building-to-building road connections** — no random road network; roads only connect buildings using a growing-connected-set approach (cardinal-only BFS). Side entrance tiles (bottom col 1, 3) blocked in road BFS to force center-column exit. Tiles below building entrances reserved from obstacle placement to guarantee a connection path.

**Missing:** map objects (mines, chests, towns), time system, full HUD, terrain variety, seeded generation for map features beyond buildings/obstacles, underground layer, fog save/load, hero stats panel

### Milestone 4+ — Not started

---

## Key Architecture Decisions

- **Cube coordinates for hex grid** (q+r+s=0) with odd-r offset for Godot TileMap
- **HoMM3 attack-direction picker** — mouse angle selects attack hex around target
- **Combat phase enum** — SETUP → PLAYER_SELECT/MOVE/ATTACK → ENEMY_TURN → RESOLVE_DAMAGE → COMBAT_OVER
- **Adventure map phase enum** — IDLE → MOVING (input blocked during animation)
- **A* tie-breaking** — Cardinal directions explored before diagonals to avoid zigzag paths
- **Path arrows** — Forward-looking, 9-arrow atlas layout
- **Fog of war rendering** — Sprite2D with procedural pixel image, ShaderMaterial with noise, red channel as transparency mask, linear filtering for smooth tile boundaries
- **Visibility radius** — Euclidean distance (circular) for natural reveal edge
- **Pathfinding blocked by fog** — Combined cache of obstacles + unexplored tiles rebuilt after each fog update
- **Map enemies stored in GameState** — Dictionary keyed by `"x,y"` tile string, each entry has `unit_id`, `count`, `tile`
- **Combat result back-channel** — `GameState.combat_result` dictionary shared between AdventureMap and CombatScene; AdventureMap writes `enemy_key` before transition, CombatScene adds `result`/`player_army`, AdventureMap reads on re-entry
- **AdventureMap camera** — position_smoothing disabled, movement tween drives camera + sprite in parallel; free edge-scrolling when idle
- **SceneManager fade fallback** — `go_to()` skips `await` when `fade_rect` is invalid, preventing one-frame yield glitch
- **Scene preservation** — AdventureMap is hidden (not freed) during combat and restored after; avoids map regeneration, player position reset, and state loss on return from combat
- **CombatScene deferred init** — `_ready()` defers test-battle creation via `call_deferred()` so SceneManager's `_on_scene_entered()` delivers real army data first; `_initialized` flag prevents double initialization
- **AdventureMap _initialized guard** — `_ready()` uses `_initialized` flag to skip re-init when scene is re-added to tree after preservation (Godot 4 fires `_ready()` on reparent)
- **Player position saved across combat** — `player_tile` stored in `GameState.combat_result.saved_player_tile` before combat, restored in `_process_combat_result()` after combat
- **Enemy visibility gated by fog** — enemy sprites hidden unless their tile is in `GameState.explored_tiles`, updated on fog recalculation and enemy sprite sync
- **Deterministic obstacle placement** — `_generate_map()` seeds RNG from `GameState.run_seed` so obstacles remain consistent when preserved scene is restored
- **Default unit data** — `DataManager._create_default_units()` creates 4 test units (swordsman, archer, goblin, skeleton) when no `.tres` files exist
- **Building placement** — Buildings rendered on a dedicated `BuildingLayer` TileMapLayer with `vault.png` as a 5×3 atlas source (each tile 32×32). Positions determined by seeded RNG (`run_seed ^ 0xBEEF`) for deterministic generation per run. Building footprint tiles added to `_blocked_tiles` (pathfinding blocked) except entrance opening (bottom row tiles 1-3) and middle center (cx=2, ry=1) for road traversal. Building layer sits at z_index 0 below fog overlay so buildings are naturally hidden in unexplored areas.
- **Road network: building-to-building only** — No random grid roads. `RoadGenerator.generate()` uses a growing-connected-set approach: the first building's entrance tiles seed the set, then each remaining entrance BFSes (cardinal-only, unlimited iteration) to the nearest tile in the existing set (like Prim's MST). Roads only exist between buildings.
- **road_blocked set** — A separate blocked set for road generation extends `_blocked_tiles` with building side entrance tiles (bottom col 1, 3). This forces the road BFS to always exit a building through the center column, never routing through side entrance tiles. Player pathfinding is unaffected.
- **Entrance-adjacent tile reservation** — The tile directly below each building entrance `(base.x+2, base.y+3)` is excluded from obstacle placement, guaranteeing at least one open neighbor for the road BFS to connect through.
- **Middle center road passage** — The middle row center tile (cx=2, ry=1) is unblocked so the road can run vertically through the building center (middle center → bottom center → outward to the network).
