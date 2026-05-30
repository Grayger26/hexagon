# Session Handoff — 2026-05-30

## Work Completed

### Fog of War — Major Visual Overhaul

**Shader (`shaders/fog_of_war.gdshader`):**
- Multiple iterations on fog colour: started near-black → lighter grey → saturated blue-grey → dense deep blue-grey
- Final colours: `FOG_DARK (0.10, 0.12, 0.22)`, `FOG_LIGHT (0.18, 0.20, 0.30)`
- Noise range compressed to `n.r * 0.26 + 0.37` (range 0.37–0.63) — nearly uniform colour for a dense, solid feel with subtle organic variation

**Smooth borders (`scripts/adventure_map/AdventureMap.gd`):**
- Replaced binary fog red channel (0.0 or 1.0) with BFS-based distance field
- `SMOOTH_RADIUS = 3` — tiles at distance 1 get red=0.667, distance 2 get red=0.333, distance 3+ get red=0.0
- Linear texture filter (`TEXTURE_FILTER_LINEAR`) on fog sprite enables GPU bilinear interpolation between the 1px-per-tile fog pixels, naturally smoothing the gradient across tile boundaries

**Round visible area:**
- Changed `_get_visible_tiles` from Chebyshev distance (square) to Euclidean distance (circular)

**Clickable border zone + bug fix:**
- Introduced `_moveable_tiles` dictionary — explored tiles + gradient zone (distance < SMOOTH_RADIUS)
- Pathfinding, hover path preview, and click-to-move all use `_moveable_tiles` instead of raw `GameState.explored_tiles`
- Outermost BFS ring (distance == SMOOTH_RADIUS, red=0.0) excluded from `_moveable_tiles` — prevents clicking into solid fog
- `_rebuild_pathfinding_blocked()` updated to use `_moveable_tiles` so A* can route through the gradient zone

### Modified Files

| File | Change |
|---|---|
| `shaders/fog_of_war.gdshader` | Multiple colour and noise-range iterations; final dense blue-grey atmosphere |
| `scripts/adventure_map/AdventureMap.gd` | Added `SMOOTH_RADIUS`, `_moveable_tiles`; rewrote `_update_fog()` with BFS gradient; Euclidean visibility; linear filter on fog sprite; input/pathfinding uses `_moveable_tiles` |

### Unfinished Tasks
*(same as Project_State.md — no changes)*
- Combat: spells, hero integration, war machines, siege, special abilities, large units, damage visuals, advanced AI
- Adventure map: map objects (neutral stacks, mines, chests), time system, full HUD, terrain types, seeded generation, underground layer, fog save/load, hero stats panel
- Integration: MainMenu → AdventureMap flow (FactionSelect missing), no combat trigger, 11 missing scenes, save stubs

### Known Issues
*(same as Project_State.md — no changes)*
- Combat AI delay (0.55s timer)
- Adventure map unseeded
- UI hardcoded positions (1920×1080 only)
- Path arrows flicker
- No input deadzone
- Camera smoothing coordinate mismatch

## Next Recommended Action
**Map objects on adventure map** — Place neutral creature stacks, mines, and chests. This unlocks combat triggering from the adventure map and resource income, which are the highest-impact missing features.
