# Session Handoff — 2026-06-03 (Session 2)

## Work Completed

### Road-to-Building Connection Fix
- Identified and fixed two bugs causing building-to-building roads to fail:
  - BFS had an `idx < 200` iteration cap — too low for buildings 15+ tiles apart with cardinal-only movement; removed the cap entirely
  - Tile below building entrance `(base.x+2, base.y+3)` could be blocked by an obstacle, making the entrance a dead-end; reserved from obstacle placement

### Road-to-Building Path Integrity
- Removed unused/wrong `BUILDING_ENTRANCE_LOCAL` constant (pointed to col 3 instead of col 2)
- Unblocked middle row center tile (ry=1, cx=2) so the road BFS can traverse it
- Road BFS set (`road_blocked`) blocks side entrance tiles (bottom col 1 & 3), forcing the spur to exit through the center column only — no road tiles on side entrance tiles
- Road now runs exactly on tile 2 of the bottom row and tile 2 of the middle row

### Road Network Rewrite
- **Removed random road grid generation** — `RoadGenerator.generate()` no longer calls `generate_network()`
- **New approach**: building-to-building connections only, using a growing-connected-set (Prim's-like) algorithm
  - First building's entrance tiles seed the connected set
  - Each remaining building BFSes (cardinal-only, unlimited) to the nearest tile in the existing network
  - Result: roads only exist between buildings, no needless roads
- `dead code left in place`: `generate_network()`, `_add_road_tile()`, `_add_entrance_connections()` are no longer called but remain defined (minor cleanup for a future session)

## Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/AdventureMap.gd` | Removed `BUILDING_ENTRANCE_LOCAL` const; unblocked middle center tile; added `_building_bases` tracking; simplified `building_entrances` (middle center only); built `road_blocked` set; reserved entrance-adjacent tiles from obstacles |
| `scripts/adventure_map/RoadGenerator.gd` | Rewrote `generate()` — building-to-building only, no grid network; removed `idx < 200` BFS cap |
| `docs/development/Project_State.md` | Updated road generation, building placement, architecture decisions |
| `docs/development/Session_Handoff.md` | This file |

## Unfinished Tasks

- **Some buildings not connected** — the BFS may fail when obstacles fully wall off a building from the network; needs a connectivity fallback
- **Map objects** — mines, chests, dwellings, terrain types remain unimplemented (Milestone 3)
- **Building interaction** — buildings are visual only; no click/interaction functionality yet
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **Multiple building types** — only vault.png exists; no town, mine, or dwelling sprites yet

## Next Recommended Action

**Add interactive map objects** — mines (resource generation), chests (gold/XP choice), and dwellings (unit recruitment). Road system is now stable and buildings-only — moving to map content.

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
