# Session Handoff — 2026-06-05 (Session 5)

## Work Completed

### Lighthouse Building (3×3)
- **Y-sorted rendering** — Bottom row (ry=2) on `LighthouseBottomLayer` at z=1 (under player at z=2); top rows (ry=0-1) on `LighthouseTopLayer` at z=3 (above player)
- **Collision** — Only center tile (1,1) blocks movement; top row, side columns, and entrance (1,2) are all open
- **Road under building** — Center tile removed from `road_blocked` (stays in `_blocked_tiles`) so road BFS traverses through it, matching vault behavior
- **Road connection** — Center tile (1,1) used as road entrance (not added to `_building_bases` to avoid vault's wrong 5×3 offsets)
- **Deterministic placement** — Separate seeded RNG (`run_seed ^ 0xF00D`), no overlap with vaults or enemies

### Lighthouse Fog Reveal (HoMM3 mechanic)
- Walking onto entrance tile (1,2) triggers `_activate_lighthouse()`
- Reveals all tiles within 15-tile Euclidean radius of lighthouse center permanently
- One-time effect per run (`_lighthouse_activated` flag)
- `_lighthouse_base` promoted from local to member variable for cross-method access

### Fog Z-Index Fix
- Fog sprite z_index raised from 0 to 4 — now renders above all building layers (max z=3), hiding lighthouse in unexplored areas

### Modified Files

| File | Change |
|---|---|
| `assets/buildings/lighthouse.png` | New 96×96 asset (3×3 tiles) |
| `scripts/adventure_map/AdventureMap.gd` | Added lighthouse constants/layers/TileSet/placement/collision, road_blocked exception, road entrance, `_activate_lighthouse()` method, `_lighthouse_base`/`_lighthouse_activated` member vars, fog z_index to 4, `LIGHTHOUSE_REVEAL_RADIUS` constant |
| `docs/development/Project_State.md` | Added lighthouse to Core Systems, implemented list, architecture decisions (y-sorting, fog reveal, road-under-building); bumped date |
| `docs/development/Session_Handoff.md` | This file |

## Unfinished Tasks

- **Building connectivity fallback** — Some buildings may lack road connection if BFS path fully blocked
- **Diagonal roads** — Roads between buildings are cardinal-only; no diagonal segments
- **Map objects** — mines, chests, dwellings, terrain types remain unimplemented (Milestone 3)
- **Building interaction** — only lighthouse has activation; vaults are decorative only
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **Milestone 2 (Full Combat)** — Spells, hero integration, war machines, siege, advanced AI, large units all unimplemented

## Next Recommended Action

**Add interactive map objects** — mines (resource generation), chests (gold/XP choice), and dwellings (unit recruitment). Road, movement, enemy collision, and building systems are stable.

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
