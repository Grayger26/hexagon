# Session Handoff — 2026-05-30

## Completed Work

### Combat Scene — Animated Unit Movement
- Units now animate along an A* path when moving, instead of teleporting
- Path avoids obstacles, allies, and enemies via `HexGrid.find_path()`
- Uses `Tween` with 0.08s step duration per hex
- Input blocked during animation via `RESOLVE_DAMAGE` phase
- Player click-to-move, auto-move-before-attack, and AI movement all use the same animation pipeline
- AI flying units get their own blocked set (only units, not obstacles)

### Adventure Map Prototype
- **SquareGrid.gd** — 8-directional A* pathfinding with Chebyshev distance heuristic, flat 100 cost per tile
- **AdventureMap.tscn** — Minimal scene, all setup in script
- **AdventureMap.gd** — Full prototype with:
  - 50×35 tile map with 80 random obstacles
  - Player sprite (swordsman.png) with 2x scale
  - Movement points system (1500 max, 100/tile, End Turn resets)
  - Hover path preview with directional arrows from `path_arrows.png`
  - Path truncated to movement budget (arrows only drawn up to reachable range)
  - Click-to-move with tween animation (0.1s per step)
  - Camera2D with smoothing (speed 8.0) following player
  - Mouse coordinate conversion uses `get_global_mouse_position()` (camera-aware)
  - Fallback textures for dev without asset files

## Modified Files

| File | Status |
|---|---|
| `scripts/combat/CombatScene.gd` | Modified — added `_animate_movement()`, updated all 4 teleport sites to use it, added RESOLVE_DAMAGE input guard |
| `scripts/adventure_map/SquareGrid.gd` | New — grid utilities, 8-dir A*, arrow atlas lookup |
| `scripts/adventure_map/AdventureMap.gd` | New — full adventure map controller |
| `scenes/adventure_map/AdventureMap.tscn` | New — minimal scene (root + script ref) |

## Architecture Decisions

### Combat Movement
- `_animate_movement(stack, target_hex, blocked)` is a coroutine (`await tween.finished`)
- Sets `phase = RESOLVE_DAMAGE` to block input during animation
- `stack.hex` and `_hex_to_stack` are updated only after the tween finishes
- `_move_stack_to()` is now a thin wrapper that calls `_animate_movement` and logs
- Flying AI excludes obstacles from blocked set for pathfinding

### Adventure Map
- **8-directional movement** — `SquareGrid.DIRECTIONS_MOVE` includes diagonals
- **Chebyshev heuristic** — admissible for 8-dir with uniform cost
- **Scene tree**: AdventureMap (Node2D) → TerrainLayer (TileMapLayer, z=0), PathLayer (TileMapLayer, z=1), Player (Sprite2D, z=2), Camera2D, UI (CanvasLayer, layer=10)
- **State**: Simple enum (`IDLE`, `MOVING`) — no StateMachine pattern
- **Coordinate flow**: `get_global_mouse_position()` → /2 (scale) → `local_to_map()` → tile Vector2i
- **Path preview**: Computed on hover, drawn on separate TileMapLayer, cleared each frame
- **Camera**: `ANCHOR_MODE_DRAG_CENTER`, smoothing enabled, position updated in `_sync_player_position()`

### Asset Tile Layouts
- **square_tiles.png** (64×64, 2×2 grid of 32×32): (0,0)=orange/ground, (1,0)=gray/obstacle, (0,1)=brown/spare, (1,1)=darkred/spare
- **path_arrows.png** (96×96, 3×3 grid of 32×32): row0=NW/N/NE, row1=W/target/E, row2=SW/S/SE
- **Direction→Atlas mapping** in `SquareGrid.DIRECTION_ARROW_ATLAS`

## Unfinished Tasks

### Combat (Milestone 1–2 gaps)
- [ ] No ranged unit ammo display in UI
- [ ] No `RESOLVE_DAMAGE` actually plays damage animation (phase exists but nothing animates)
- [ ] Flying units ignore obstacles but still animate step-by-step (no "flyover" arc)
- [ ] Large (2-hex) units not implemented
- [ ] Hero integration (stats affecting stacks, spellcasting) not implemented
- [ ] Morale/Luck systems exist in code but have no visible feedback
- [ ] War machines not implemented
- [ ] Siege combat not implemented
- [ ] Combat AI is very simple (basic melee/ranged/flying)

### Adventure Map (Milestone 3 gaps)
- [ ] No fog of war
- [ ] No map objects (mines, chests, towns, neutral creatures)
- [ ] No day/week/month time system
- [ ] No HUD beyond movement points label and End Turn button
- [ ] No path cost variation by terrain type
- [ ] Map is randomly generated with no seed control
- [ ] No underground layer
- [ ] No hero stats panel

### Integration
- [ ] No way to get to adventure map from menus (MainMenu → New Run goes to FACTION_SELECT, not implemented yet)
- [ ] No way to trigger combat from adventure map
- [ ] Save/load not tested with new scenes

## Next Recommended Steps

1. **Add fog of war** — 3 states (UNSEEN/EXPLORED/VISIBLE) with visibility radius around player
2. **Add map objects** — Neutral creature stacks that trigger combat on contact, resource pickups, mines
3. **Wire combat transition** — Stepping on a neutral stack calls `SceneManager.go_to(Scene.COMBAT, data)`
4. **Time system** — End Turn advances day, resets movement, triggers events
5. **MainMenu → AdventureMap flow** — Wire the "New Run" path through FACTION_SELECT to actually start a run and load the map

## Known Issues

1. **Combat AI after movement** — The 0.55s AI timer at the start of `_run_ai_turn()` adds delay even when movement animation already took time. AI move+attack feels slow.
2. **Adventure map obstacle placement** — Uses `rng.randomize()` (not seeded), so map is different every time. Should use `GameState.run_seed` for reproducibility.
3. **Adventure map map_to_local scale** — `_tile_to_local()` multiplies by `MAP_SCALE`. This assumes the root node has no additional transform. If AdventureMap root is repositioned/scaled, all tile-to-world conversions break.
4. **UI not camera-aware** — The UI CanvasLayer is positioned in screen space but hardcoded at pixel positions (860, 1020 for the button). Works at 1920×1080 only.
5. **Path arrows flicker** — `_path_layer.clear()` is called every `_on_hover` call (every mouse-motion frame). On very fast mouse movement this could cause flicker.
6. **No input deadzone** — Clicking very close to the player registers as a valid movement target; there's no minimum-distance threshold.
7. **Duplicate function bug was fixed** — An earlier edit duplicated `_setup_player()` and `_sync_player_position()`. The duplicates were removed; verify no regressions.
