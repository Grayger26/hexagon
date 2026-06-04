# Session Handoff — 2026-06-04 (Session 3)

## Work Completed

### Attempted Diagonal Roads (Reverted)
- Tried expanding `_find_road_spur()` BFS from cardinal-only to all 8 directions
- Produced worse results (terrain system cannot cleanly render mixed cardinal+diagonal transitions at spur junctions); reverted immediately

### Per-Tile Movement Cost with Road Discount
- Road tiles now cost 70 movement points per tile (30% less than the base 100)
- Added `MOVE_COST_ROAD = 70` constant
- Added `_tile_move_cost(tile)` helper — checks `_road_layer.get_cell_source_id()` to detect road tiles
- Added `_path_cost(path)` helper — sums per-tile costs across the full path (handles mixed road/normal paths)
- Updated all three cost calculation sites to use per-tile logic:
  - `_update_path()` — hover preview budget now steps through per-tile costs
  - `_on_input_clicked()` — non-cached path budget uses `_path_cost()`
  - `_animate_movement()` — actual deduction uses `_path_cost()`
- Removed `movement_points` as `max_cost` from `SquareGrid.find_path()` call — the old flat 100-per-tile budget would prune valid road-heavy paths. Real budget check runs after pathfinding.

## Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/AdventureMap.gd` | Added `MOVE_COST_ROAD` const, `_tile_move_cost()`, `_path_cost()`; updated 3 cost sites to per-tile; removed stale `movement_points` from `find_path()` call |
| `scripts/adventure_map/RoadGenerator.gd` | Reverted experimental 8-directional BFS change (back to cardinal-only) |
| `docs/development/Project_State.md` | Updated to session 3; added movement cost system and architecture decisions |
| `docs/development/Session_Handoff.md` | This file |

## Unfinished Tasks

- **Building connectivity fallback** — Some buildings may not be road-connected if BFS path is fully blocked by obstacles; needs a connectivity fallback
- **Diagonal roads** — Roads between buildings are purely cardinal (NSEW); no diagonal road segments. The terrain system + `place()` already support diagonal tiles but building-to-building BFS stays cardinal-only for rendering stability.
- **Map objects** — mines, chests, dwellings, terrain types remain unimplemented (Milestone 3)
- **Building interaction** — buildings are visual only; no click/interaction functionality yet
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **Multiple building types** — only vault.png exists; no town, mine, or dwelling sprites yet

## Next Recommended Action

**Add interactive map objects** — mines (resource generation), chests (gold/XP choice), and dwellings (unit recruitment). Road and movement systems are stable.

## Known Issues

- SceneManager has no fade between AdventureMap ↔ CombatScene transitions (fade_rect from MainMenu was freed)
- Combat AI uses a hardcoded 0.55s delay timer
- All adventure map UI positions are hardcoded for 1920×1080
- Path arrow preview flickers on rapid mouse movement
- Camera has no input deadzone on adventure map
- Camera smoothing coordinate mismatch between `_tile_to_local` scale and map scale
- `DataManager.get_spells_by_school()` references `units.values()` instead of `spells.values()` (copy-paste bug, line ~96)
- `CombatScene._load_test_battle()` creates duplicate UnitData instances even though DataManager already has identical fallback units
- Some buildings may not be road-connected if the BFS path is fully blocked by obstacles or other buildings — no connectivity fallback exists yet
