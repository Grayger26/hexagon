# Session Handoff — 2026-06-06 (Session 8)

## Work Completed

### Tile Size Correction (32×16)
All tile atlases and building sprites were designed at 16×16 pixels per tile but the project used `TILE_SIZE = 32`. This caused sprites to render at 2x their intended resolution (blurry upscaled). Fixed by changing the core constants and correcting hardcoded scene values.

### Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/SquareGrid.gd` | `TILE_SIZE: 32 → 16` |
| `scripts/combat/HexGrid.gd` | `TILE_W/TILE_H: 32 → 16` + inline computed-value comments |
| `scripts/combat/CombatTileMap.gd` | `TILE_SIZE: 32 → 16` + atlas comment |
| `scenes/tilemaps/map_roads.tscn` | `texture_region_size` & `tile_size`: `(32,32) → (16,16)` |
| `scripts/adventure_map/AdventureMap.gd` | All atlas/building dimension comments + MAP_SCALE comment |
| `scripts/combat/CombatScene.gd` | Camera centering math comment |
| `scripts/combat/UnitStack.gd` | Sprite/badge positioning comments |
| `docs/development/Project_State.md` | Architecture decisions: merged tile size entries, date bumped |

### What Did NOT Need Changing
- `MAP_SCALE = 2.0` — stays; 16×16 tiles render at 32×32 display pixels (1:2 pixel doubling, looks crisp)
- All `ts.tile_size` / `texture_region_size` — reference the constants, auto-updated
- `_tile_to_local()` — uses TileMap's `map_to_local` (reads tile_size from TileSet)
- Fallback textures — draw into same image sizes at 16px regions; unused atlas tiles are black but never referenced
- Unit sprites (32×32 PNGs) — correct for 2×2 tile coverage at 16×16
- Camera/zoom pixel values — functional as-is; may need tuning for visual centering

## Unfinished Tasks

- **Obstacle visibility** — 800 obstacles block pathfinding but have no visual indicator (ground tiles only). `stone.png`/`wood.png` sprites exist but are unused.
- **Building connectivity fallback** — Some buildings may lack road connection if BFS path fully blocked
- **Map objects** — mines, chests, dwellings, terrain types remain unimplemented (Milestone 3)
- **Building interaction** — only lighthouse has activation; vaults are decorative
- **Enemy variety** — only 3 types (goblin/skeleton/archer); no scaling by distance from start
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **Milestone 2 (Full Combat)** — Spells, hero integration, war machines, siege, advanced AI, large units all unimplemented
- **Combat scene visual size** — with 16px tiles at scale 2.5, the combat arena is now ~680×330 px (was ~1360×660). Camera position (450,420) may need adjustment for better centering.

## Next Recommended Action

**Add obstacle sprites** — Place `stone.png`/`wood.png` sprites on the 800 obstacle tiles so players can visually distinguish blocked ground tiles from passable ones. Quick visual fix before moving on to interactive map objects.

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
- Combat arena visual size halved after tile size correction; camera position (450,420) may need retuning
