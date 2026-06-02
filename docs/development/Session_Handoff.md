# Session Handoff — 2026-06-02

## Work Completed

### Road Generator Rewrite (hybrid terrain system)
- Replaced manual tile classification (300+ lines of connection masks, lookup tables, corner cap logic) with a hybrid approach
- **Phase 1** — Cardinal road cells passed to `set_cells_terrain_connect()`: Godot's TileSet terrain system auto-selects straights, corners, T-junctions, crossroads, and cardinal↔diagonal transition tiles from `map_roads.png`
- **Phase 2** — Pure diagonal cells (no cardinal neighbours) placed with `set_cell()`: correct atlas tile selected based on 8-direction connection mask (NW+SE = `\`, NE+SW = `/`, single-bit = end caps)
- **Phase 3** — Corner cap fill tiles at all 4 cardinal positions (N, W, E, S) around each diagonal tile to smooth the staircase visual, using Dictionary-based dedup to avoid overwriting existing road tiles

Corner cap tile mapping per user specification:
| Diagonal | N | W | E | S |
|---|---|---|---|---|
| `\` (NW→SE) | (2,3) lower-left | (1,4) upper-right | (2,3) lower-left | (1,4) upper-right |
| `/` (SW→NE) | (4,4) lower-right | (4,4) lower-right | (6,4) upper-left | (1,4) upper-right |

- `generate()` now returns `Array[Vector2i]` (positions) instead of `Dictionary` (position→atlas_coord)
- `place()` cleared of all manual atlas-coordinate and corner-cap logic

### AdventureMap Integration
- Updated `_generate_map()` to pass `Array[Vector2i]` to RoadGenerator.place()

## Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/RoadGenerator.gd` | Full rewrite — hybrid terrain/manual placement, corner cap support. ~330 lines |
| `scripts/adventure_map/AdventureMap.gd` | Updated road generation call (Dictionary → Array[Vector2i]) |
| `docs/development/Project_State.md` | Updated core systems, milestone status, architecture decisions |

## Unfinished Tasks

- **Map objects on adventure map** — mines, chests, neutral creature stacks, terrain types remain unimplemented (Milestone 3)
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **No persistent FadeRect** — SceneManager has no fade after initial MainMenu→AdventureMap transition (fade_rect is lost when MainMenu is freed)
- **Cardinal↔diagonal transition tiles** — some cardinal↔diagonal junctions lack matching transition tiles in the atlas (e.g. horizontal→`\` right_side+bottom_right_corner), producing a visual gap at the transition point
- **Diagonal road corner overlap with cardinal roads** — corner caps are correctly skipped at cardinal road positions, but this means some diagonal staircase edges adjacent to cardinal roads have unfilled gaps

## Next Recommended Action

**Implement map objects on the adventure map** — mines (resource generation), chests (gold/XP), dwellings (unit recruitment), and terrain type tiles. This is the next Milestone 3 deliverable and the most impactful addition now that road generation with proper diagonal handling, combat flow, scene persistence, and camera controls are solid.

## Known Issues

- SceneManager has no fade between AdventureMap ↔ CombatScene transitions (fade_rect from MainMenu was freed; need a persistent overlay)
- Combat AI uses a hardcoded 0.55s delay timer
- All adventure map UI positions are hardcoded for 1920×1080
- Path arrow preview flickers on rapid mouse movement
- Camera has no input deadzone on adventure map
- Camera smoothing coordinate mismatch between `_tile_to_local` scale and map scale
- `DataManager.get_spells_by_school()` references `units.values()` instead of `spells.values()` (copy-paste bug, line ~96)
- `CombatScene._load_test_battle()` creates duplicate UnitData instances even though DataManager already has identical fallback units
- Friendly-stack-switching code commented out in `CombatScene._on_click()` (lines 456-463)
- Cardinal↔diagonal road transitions may leave visual gaps where the atlas lacks a matching transition tile
