# Session Handoff — 2026-05-31

## Work Completed

### Bug: Player Unable to Move After Combat
- **Root cause:** `_trigger_combat()` sets `phase = MapPhase.MOVING` before transitioning, but `_on_scene_entered()` never reset it to `IDLE` on return. All input gated behind `phase == IDLE` was silently dropped.
- **Fix:** Added `phase = MapPhase.IDLE` at the top of `AdventureMap._on_scene_entered()`.

### Feature: Free Camera (Edge-Scrolling + Snap)
- Added `_process(delta)` with mouse-edge detection — camera scrolls toward screen edges when mouse is within 20px of viewport bounds (400 px/s, only while `phase == IDLE`).
- Space key (`KEY_SPACE`) snaps camera to player via `_center_camera_on_player()`.

### Feature: Fog Hides Enemies
- Added `_update_enemy_visibility()` — iterates all enemy sprites and sets `visible = tile in GameState.explored_tiles`.
- Called from `_update_fog()` (on movement/fog changes) and `_setup_enemies()` (on scene re-entry).

### Bug: Player Position Reset After Combat
- **Root cause:** `_ready()` fires again when preserved scene is re-added to tree (Godot 4 behavior), resetting `player_tile = START_TILE` and creating duplicate player sprite.
- **Fix:** Added `_initialized` guard to `AdventureMap._ready()` to skip re-init on restoration.
- **Defensive layer:** `player_tile` saved to `GameState.combat_result.saved_player_tile` in `_trigger_combat()`, restored in `_process_combat_result()` after combat with `_sync_player_position()`.

## Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/AdventureMap.gd` | Phase reset on scene entry; free camera (edge-scroll + Space snap); `_update_enemy_visibility()` for fog gating; `_initialized` guard on `_ready()`; save/restore `player_tile` across combat |
| `docs/development/Project_State.md` | Updated architecture, milestones, and key decisions |
| `docs/development/Session_Handoff.md` | This file |

## Unfinished Tasks

- **Map objects on adventure map** — mines, chests, neutral creature stacks, terrain types remain unimplemented (Milestone 3)
- **FactionSelect scene** — still bypassed; "New Run" goes directly to AdventureMap
- **No persistent FadeRect** — SceneManager has no fade after initial MainMenu→AdventureMap transition (fade_rect is lost when MainMenu is freed)
- **Pre-existing issues unchanged:** combat AI 0.55s timer, hardcoded UI positions, path arrow flicker, no input deadzone

## Next Recommended Action

**Implement map objects on the adventure map** — mines (resource generation), chests (gold/XP), dwellings (unit recruitment), and terrain type tiles. This is the next Milestone 3 deliverable and the most impactful addition now that the combat flow, scene persistence, and camera controls are solid.

## Known Issues

- SceneManager has no fade between AdventureMap ↔ CombatScene transitions (fade_rect from MainMenu was freed; need a persistent overlay)
- Combat AI uses a hardcoded 0.55s delay timer
- All adventure map UI positions are hardcoded for 1920×1080
- Path arrow preview flickers on rapid mouse movement
- Camera has no input deadzone on adventure map
- Camera smoothing coordinate mismatch between `_tile_to_local` scale and map scale
