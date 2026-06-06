# Session Handoff — 2026-06-06 (Session 9)

## Work Completed

### Camera Zoom (Mouse Wheel + Trackpad)
Added mouse wheel zoom and trackpad pinch-to-zoom to the adventure map. Zoom uses a multiplicative 15% step (ZOOM_FACTOR = 1.15), clamped to [0.5, 3.0]. Both mouse wheel (`MOUSE_BUTTON_WHEEL_UP/DOWN`) and trackpad magnify gesture (`InputEventMagnifyGesture`) call a shared `_zoom_pan_toward_mouse()` helper that pans the camera so the tile under the cursor stays fixed during the zoom change.

### Camera Border Clamping
Camera is now constrained to the map world bounds (5120×3520 px). A `_compute_camera_bounds()` method returns (min_x, max_x, min_y, max_y) accounting for viewport size and current zoom. Three clamping strategies work together:
- **Edge-scroll pre-clamp** — candidate scroll position clamped before assignment, preventing the scroll-vs-clamp frame fight.
- **Player-movement pre-clamp** — `_camera_position_for_tile()` clamps the camera tween target, while the player sprite targets the raw tile centre, so the camera stops at the boundary while the sprite reaches the edge tile.
- **Safety-net `_clamp_camera()`** — runs every frame in `_process` and after zoom pan; catches any camera movement not covered above.

### Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/AdventureMap.gd` | Zoom constants, `_compute_camera_bounds()`, `_clamp_camera()`, `_camera_position_for_tile()`, `_zoom_pan_toward_mouse()`; restructured `_process` edge-scrolling; separated camera/sprite targets in `_animate_movement`; updated `_sync_player_position` and `_center_camera_on_player` to use clamped position |
| `docs/development/Project_State.md` | Bumped session, added CameraZoom and CameraClamp core systems, added zoom and clamp architecture decisions |

## Unfinished Tasks

- **Obstacle visibility** — 800 obstacles block pathfinding but have no visual indicator (stone.png/wood.png sprites unused)
- **Building connectivity fallback** — Some buildings may lack road connection if BFS path fully blocked
- **Map objects** — mines, chests, dwellings, terrain types remain unimplemented (Milestone 3)
- **Building interaction** — only lighthouse has activation; vaults are decorative
- **Enemy variety** — only 3 types (goblin/skeleton/archer); no scaling by distance from start
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **Milestone 2 (Full Combat)** — Spells, hero integration, war machines, siege, advanced AI, large units all unimplemented
- **Resource HUD** — movement points and army shown; gold, resources, hero stats, minimap not displayed

## Next Recommended Action

**Add obstacle sprites** — Place stone.png/wood.png sprites on the 800 obstacle tiles so players can visually distinguish blocked ground tiles from passable ones. Quick visual fix before moving on to interactive map objects.

## Known Issues

- SceneManager has no fade between AdventureMap ↔ CombatScene transitions
- Combat AI uses a hardcoded 0.55s delay timer
- All adventure map UI positions are hardcoded for 1920×1080
- Path arrow preview flickers on rapid mouse movement
- Camera has no input deadzone on adventure map (minor scroll drift on centre-released touchpad)
- Camera smoothing coordinate mismatch between `_tile_to_local` scale and map scale
- `DataManager.get_spells_by_school()` references `units.values()` instead of `spells.values()`
- `CombatScene._load_test_battle()` creates duplicate `UnitData` instances
- Some buildings may not be road-connected if the BFS path is fully blocked
- Combat arena visual size halved after tile size correction; camera position (450,420) may need retuning
