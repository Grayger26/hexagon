# Session Handoff — 2026-06-06 (Session 7)

## Work Completed

### Vault Building Collision Fix
- Middle center tile (2,1) of vault buildings was incorrectly left unblocked for player movement, allowing players to walk into the building interior
- Vault blocking loop: removed the `ry == 1 and cx == 2` exception — all vault tiles except bottom-row entrance (tiles 1–3 on the bottom row) now block the player
- Road blocked set: vault middle center tiles are explicitly unblocked for road generation only (same pattern as lighthouse), so roads still pass through building interiors

### Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/AdventureMap.gd` | Removed middle-center tile exception from vault blocking loop; added vault middle-center unblocking in road blocked set |
| `docs/development/Project_State.md` | Updated for session 7 (new architecture decision, date) |

## Unfinished Tasks

- **Obstacle visibility** — 800 obstacles block pathfinding but have no visual indicator (ground tiles only). `stone.png`/`wood.png` sprites exist but are unused.
- **Building connectivity fallback** — Some buildings may lack road connection if BFS path fully blocked
- **Map objects** — mines, chests, dwellings, terrain types remain unimplemented (Milestone 3)
- **Building interaction** — only lighthouse has activation; vaults are decorative
- **Enemy variety** — only 3 types (goblin/skeleton/archer); no scaling by distance from start
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **Milestone 2 (Full Combat)** — Spells, hero integration, war machines, siege, advanced AI, large units all unimplemented

## Next Recommended Action

**Add obstacle sprites** — Place `stone.png`/`wood.png` sprites on the 800 obstacle tiles so players can visually distinguish blocked ground tiles from passable ones. This is a quick visual fix before moving on to interactive map objects.

## Known Issues

- SceneManager has no fade between AdventureMap ↔ CombatScene transitions
- Combat AI uses a hardcoded 0.55s delay timer
- All adventure map UI positions are hardcoded for 1920×1080
- Path arrow preview flickers on rapid mouse movement
- Camera has no input deadzone on adventure map
- Camera smoothing coordinate mismatch between `_tile_to_local` scale and map scale
- `DataManager.get_spells_by_school()` references `units.values()` instead of `spells.values()`
- `CombatScene._load_test_battle()` creates duplicate UnitData instances
- Some buildings may not be road-connected if the BFS path is fully blocked
