# Project State — Hexagon Legends

**Engine:** Godot 4.6.2
**Genre:** HoMM3-inspired turn-based strategy roguelike
**Last updated:** 2026-05-31

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

### Cross-Scene Combat Flow
- `GameState.player_army: Array[Dictionary]` — player's current army, persisted across AdventureMap ↔ CombatScene transitions
- `GameState.map_enemies: Dictionary` — enemies placed on adventure map tiles, keyed by `"x,y"` string
- `GameState.combat_result: Dictionary` — communication channel: AdventureMap writes `enemy_key`, CombatScene writes `result` + `player_army`, AdventureMap reads on re-entry
- **Scene preservation** — AdventureMap is hidden (not freed) during combat via SceneManager; restored on return with all state intact (obstacles, player position, fog, HUD, enemy visibility)
- `MainMenu` bypasses missing FactionSelect scene — "New Run" calls `GameState.init_run()` directly and transitions to `AdventureMap`
- `AdventureMap` auto-initializes `GameState` if `run_active` is false (handles running from editor)

### Shaders
- `fog_of_war.gdshader` — CanvasItem shader for fog of war, noise-driven blue-grey mist

---

## Milestone Status

### Milestone 0 — Foundation (COMPLETE)
All 6 autoloads, 5 resource types, folder structure, StateMachine base class, **default unit data generation**

### Milestone 1 — Combat Prototype (COMPLETE)
HexGrid with A*/LoS/BFS, CombatTileMap with 4 layers, UnitStack with HP/effects, CombatTurnManager with speed queue, DamageCalculator with full HoMM3 formula, CombatScene with animated movement/melee/ranged/AI/combat-end, test battle, Camera2D

### Milestone 2 — Full Combat (NOT STARTED)
Spells, hero integration, war machines, siege, special abilities, advanced AI — all unimplemented. Morale/luck code exists in CombatScene but has no visible feedback. Large (2-hex) units not implemented.

### Milestone 3 — Adventure Map (PARTIALLY COMPLETE)
**Implemented:** SquareGrid with A*, AdventureMap with 50×35 grid/movement/path preview/Camera2D/HUD, Fog of War with noise shader/BFS gradient/Euclidean radius, enemy placement on map tiles, combat encounter triggers, **scene preservation (AdventureMap persists across battles with all state intact)**, deterministic obstacle seeding, combat result processing on return, **free camera edge-scrolling**, **space to snap camera to player**, **enemy sprites hidden by fog of war**, **player position saved/restored across combat**, auto-init for editor testing

**Missing:** map objects (mines, chests, towns), time system, full HUD, terrain variety, seeded generation, underground layer, fog save/load, hero stats panel

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
- **Enemy visibility gated by fog** — enemy sprites are hidden unless their tile is in `GameState.explored_tiles`, updated on fog recalculation and enemy sprite sync
- **Deterministic obstacle placement** — `_generate_map()` seeds RNG from `GameState.run_seed` so obstacles remain consistent when preserved scene is restored
- **Default unit data** — `DataManager._create_default_units()` creates 4 test units (swordsman, archer, goblin, skeleton) when no `.tres` files exist
