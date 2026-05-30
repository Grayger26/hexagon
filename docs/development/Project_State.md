# Project State — Hexagon Legends

**Engine:** Godot 4.6.2  
**Genre:** HoMM3-inspired turn-based strategy roguelike  
**Last updated:** 2026-05-30

---

## Architecture

### Autoloads (6)
| System | Purpose |
|---|---|
| `GameState` | Single source of truth for active run (phase, resources, hero, day/week/month) |
| `EventBus` | Global signal bus — all decoupled communication |
| `DataManager` | Loads/caches `.tres` resource files at startup |
| `SceneManager` | Scene transitions with black fade; 14 registered scene paths |
| `SaveManager` | Run save (single slot) + meta save (permanent) with JSON I/O |
| `AudioManager` | Music cross-fade + SFX pool |

### Data Resources (5 types)
- `UnitData` — Static unit stats, abilities, cost, sprites
- `HeroData` — Archetype data, stat weights, specialty, skill bias
- `HeroState` — Mutable per-run hero state (skills, spells, artifacts, army, serialization)
- `ArtifactData` — Artifact stats, slot, tier, bonuses
- `SpellData` — Spell stats, school, damage formula, target type

### Core Systems
- `StateMachine` (Node) — Reusable FSM base with `State` inner class, transitions, input routing
- `CombatTurnManager` (RefCounted) — Speed-sorted turn queue, wait queue, round management
- `HexGrid` (RefCounted) — Cube-coordinate hex grid (pointy-top, odd-r), A* pathfinding, LoS
- `SquareGrid` (RefCounted) — 8-directional square grid for adventure map, Chebyshev A*
- `DamageCalculator` (RefCounted) — Static HoMM3 damage formula with luck, morale, ranged penalty
- **`FogOfWar`** (Sprite2D + shader) — Pixelated fog overlay using noise texture (FastNoiseLite) for organic appearance. Red channel of a 1px-per-tile image drives transparency via shader (`a -= r`). Three states: UNSEEN (fully fogged), EXPLORED (fully clear), with pathfinding blocked through unexplored fog.

### Shaders
- `fog_of_war.gdshader` — CanvasItem shader for fog of war. Samples a simplex-noise texture, uses the fog image's red channel as a transparency mask, replaces colour with a dark blue-grey tinted noise for a dense mist effect.

---

## Milestone Status

### Milestone 0 — Foundation (COMPLETE)
- All 6 autoloads, 5 resource types, folder structure, StateMachine base class

### Milestone 1 — Combat Prototype (COMPLETE)
- HexGrid with A* pathfinding, LoS, BFS reachability
- CombatTileMap with 4 layers (terrain, highlight, cursor, attack positions)
- UnitStack with HP model, effects, turn reset, visual badge
- CombatTurnManager with speed queue, wait/defend, round cycling
- DamageCalculator with full HoMM3 formula
- CombatScene with animated movement, melee attack-direction picker, ranged combat, AI, combat over detection, test battle

### Milestone 2 — Full Combat (NOT STARTED)
- Spells, hero integration, war machines, siege, special abilities, advanced AI — all unimplemented
- Morale/luck code exists in CombatScene but has no visible feedback
- Large (2-hex) units not implemented

### Milestone 3 — Adventure Map (PARTIALLY COMPLETE)
- SquareGrid with 8-dir A* pathfinding
- AdventureMap with 50×35 grid, obstacles, movement points, path preview, click-to-move animation, Camera2D, HUD (movement label, tile info, End Turn button)
- **Fog of war** — Sprite2D + shader overlay using FastNoiseLite noise. Binary unseen/explored visibility, vision radius of 5 tiles, pathfinding blocked through fog, smooth tile-by-tile reveal during movement
- No fog of war save/load integration (GameState.explored_tiles serialized but not wired to adventure map load)
- No map objects, no time system, no full HUD, no terrain variety

### Milestone 4+ — Not started

---

## Key Architecture Decisions

- **Cube coordinates for hex grid** (q+r+s=0) with odd-r offset for Godot TileMap
- **HoMM3 attack-direction picker** — mouse angle selects attack hex around target
- **Combat phase enum** — SETUP → PLAYER_SELECT/MOVE/ATTACK → ENEMY_TURN → RESOLVE_DAMAGE → COMBAT_OVER
- **Adventure map phase enum** — IDLE → MOVING (input blocked during animation)
- **A* tie-breaking** — Cardinal directions explored before diagonals to avoid zigzag paths
- **Path arrows** — Forward-looking (each tile shows direction to next tile), atlas layout NW/N/NE on row 0, W/+/E on row 1, SW/S/SE on row 2
- **Fog of war rendering** — Sprite2D with procedural pixel image (1px per tile) scaled to cover map, ShaderMaterial with noise-driven fog colour, red channel as transparency mask. NOT a TileMapLayer overlay (avoids per-tile rendering cost and enables smooth gradient edges and noise effects)
- **Visibility radius** — Euclidean distance (circular), not Chebyshev (diamond), for a natural circular reveal edge
- **Pathfinding blocked by fog** — Combined cache of obstacles + unexplored tiles rebuilt after each fog update. Prevents A* from routing through unseen terrain
