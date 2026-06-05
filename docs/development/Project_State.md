# Project State — Hexagon Legends

**Engine:** Godot 4.6.2
**Genre:** HoMM3-inspired turn-based strategy roguelike
**Last updated:** 2026-06-05 (session 5)

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
- `RoadGenerator` (RefCounted) — Building-to-building road connections only; growing-connected-set approach (Prim's-like) using cardinal-only BFS; no random road network
- `Lighthouse` (inline in AdventureMap) — 3×3 building with y-sorting (two TileMapLayer instances at z=1/z=3); only center tile blocks movement; road runs under center; activation reveals 15-tile Euclidean fog radius
- `MovementCost` (inline in AdventureMap) — Per-tile movement cost calculation: road tiles cost 70 (30% less than normal tiles at 100); `_tile_move_cost()` checks `_road_layer` for road detection; `_path_cost()` sums per-tile costs across mixed paths
- `BuildingPlacement` (inline in AdventureMap) — Seeded RNG placement of 7 vault buildings (5×3 tiles) and 1 lighthouse (3×3 tiles); vault footprint blocks pathfinding except entrance opening, lighthouse only blocks center tile; each rendered on dedicated TileMapLayer below fog overlay

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
- **Enemy placement on map tiles, combat encounter triggers** — enemies block pathfinding passage; player can walk TO an enemy to fight, not THROUGH
- Scene preservation (AdventureMap persists across battles with all state intact)
- Deterministic obstacle seeding, combat result processing on return
- Free camera edge-scrolling, Space to snap camera to player
- Enemy sprites hidden by fog of war, player position saved/restored across combat
- Auto-init for editor testing
- **Building placement** — 7 vault buildings placed on the map with 5×3 tile footprint, collision blocking (entrance tiles open), rendered on BuildingLayer TileMapLayer, hidden by fog in unexplored areas
- **Lighthouse building** — Single 3×3 lighthouse with y-sorting: bottom row on LighthouseBottomLayer (z=1, under player z=2), top rows on LighthouseTopLayer (z=3, above player). Only the center tile (1,1) blocks movement — the top row, side columns, and entrance are all open. Road-connected via its own spur to the nearest road tile. **Activation**: walking onto the entrance (bottom-center, 1,2) permanently reveals a `LIGHTHOUSE_REVEAL_RADIUS` (15) Euclidean-radius area around the lighthouse, adding all those tiles to `GameState.explored_tiles`. One-time effect per run (`_lighthouse_activated` flag).
- **Building-to-building road connections** — no random road network; roads only connect buildings using a growing-connected-set approach (cardinal-only BFS). Side entrance tiles (bottom col 1, 3) blocked in road BFS to force center-column exit. Tiles below building entrances reserved from obstacle placement to guarantee a connection path.
- **Per-tile movement costs** — Road tiles cost 70 movement points per tile (30% less than the base 100). The path preview uses per-tile costs to build the reachable path, and the actual movement deduction uses the same per-tile calculation. `SquareGrid.find_path()` no longer receives `movement_points` as `max_cost` (the old flat-cost bound was too tight for road-heavy paths).

**Missing:** map objects (mines, chests, dwellings), time system, full HUD, terrain variety, seeded generation for map features beyond buildings/obstacles, underground layer, fog save/load, hero stats panel

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
- **Per-tile movement cost with road discount** — `MOVE_COST_ROAD = 70` (30% less than `MOVE_COST_PER_TILE = 100`). `_tile_move_cost()` checks `_road_layer.get_cell_source_id()` for road detection; road tiles cost 70, normal tiles cost 100. `_path_cost()` sums per-tile costs across the full path, correctly handling mixed road/normal paths. Road cost is checked at deduction time, hover-preview time, and click-to-move budget time — all three use the same per-tile logic.
- **No max_cost in A*** — `SquareGrid.find_path()` received `movement_points` as `max_cost` (flat 100-per-tile budget), which would prune valid road-heavy paths. Removed; the real budget check (`_path_cost(path) > movement_points`) runs after pathfinding and is correct regardless of road composition.
- **Enemy tiles block pathfinding passage** — A `_enemy_tiles` dictionary tracks which tiles have enemies. These are added to `_pathfinding_blocked` so A* never routes through an enemy to reach a tile beyond. The player can still walk *to* an enemy tile (the blocked set temporarily excludes the target tile when it IS an enemy) to trigger combat. After combat victory, `_refresh_enemy_tiles()` and `_rebuild_pathfinding_blocked()` are called to unblock the defeated enemy's tile.
- **Lighthouse y-sorting** — Lighthouse uses two TileMapLayer instances for y-sorting. The bottom row (ry=2) is placed on `LighthouseBottomLayer` at z_index=1 (below player at z=2) so the player sprite covers it when walking in front. The top two rows (ry=0,1) are on `LighthouseTopLayer` at z_index=3 (above player). Both layers share the same TileSet (one source, lighthouse.png 3×3 atlas). A separate seeded RNG (`run_seed ^ 0xF00D`) picks the lighthouse position from candidates that don't overlap vault buildings or enemies. Only the center tile (1,1) blocks player movement — top row, side columns, and entrance are all passable. The center tile is removed from `road_blocked` (while staying in `_blocked_tiles`) so the road BFS can traverse through it, making the road run under the building like the vault. Lighthouse entrance is NOT added to `_building_bases` — the vault's road-blocked offsets (intended for 5×3 buildings) would incorrectly block the lighthouse entrance. Instead, the lighthouse center tile is added to `building_entrances` for road connection, and its reserved road tile is handled separately.
- **Fog z_index raised to 4** — The fog overlay was moved from z_index=0 to z_index=4 to ensure it renders above all building layers (max z=3 for LighthouseTopLayer). This fixes a bug where the lighthouse top tiles were never hidden by fog. The fog shader uses the red channel as a transparency mask (r=1.0 → transparent, r=0.0 → opaque), so explored/visible tiles still show through correctly while unexplored areas are fully obscured. The UI sits on a separate CanvasLayer (layer=10) and is unaffected.
- **Lighthouse fog reveal** — Walking onto the lighthouse entrance (bottom-center tile) triggers `_activate_lighthouse()`, which adds all tiles within a Euclidean radius of `LIGHTHOUSE_REVEAL_RADIUS` (15 tiles) to `GameState.explored_tiles` and then calls `_update_fog()`. The effect is permanent for the run — the `_lighthouse_activated` flag prevents re-triggering. The center point is the middle of the building (base+1, base+1) for a circular reveal. The `_lighthouse_base` was promoted from a local variable in `_generate_map()` to a member variable so it's accessible from the activation check in `_animate_movement()`.
