# Session Handoff — 2026-05-30

## Work Completed

- **Fog of war (initial implementation)** — TileMapLayer overlay with three visibility states, Chebyshev distance radius, flat-colour tiles. Later replaced.

- **Fog of war (visual upgrade)** — Switched from TileMapLayer to Sprite2D with procedural pixel image (50×35 px, 1px per tile) and ShaderMaterial. FastNoiseLite simplex noise provides organic cloudy appearance. Red channel encodes visibility; shader does `a -= r` for transparency. Dark blue-grey fog colour (`0.04–0.22` range) for dense mist effect. Binary state: explored tiles fully clear, unexplored tiles fully fogged.

- **Fog movement blocking** — `_on_hover` and `_on_click` reject unexplored tiles. `_pathfinding_blocked` cache combines obstacles + unexplored tiles, rebuilt after each fog update. A* cannot route through fog.

- **Step-by-step fog reveal** — `_animate_movement` refactored to iterate each step individually, updating `player_tile` and calling `_update_fog()` after every tile instead of only at the end.

## New Files

| File | Purpose |
|---|---|
| `shaders/fog_of_war.gdshader` | CanvasItem shader: noise-sampled fog colour, red-channel transparency mask |

## Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/AdventureMap.gd` | Replaced TileMapLayer fog overlay with Sprite2D + shader system; added `_pathfinding_blocked` cache; step-by-step fog reveal; fogged-tile input rejection |
| `docs/development/Project_State.md` | Updated with fog system, shader, and architecture decisions |

## Unfinished Tasks

### Combat (Milestone 2)
- Spell system (SpellData exists, no casting, targeting, or SpellSystem.gd)
- Hero integration (hero panels on battlefield, hero action, hero death)
- War machines (Ballista, Ammo Cart, First Aid Tent)
- Siege combat (walls, gate, moat, towers, catapult)
- Special abilities (`double_attack`, `life_drain` etc. defined but not checked in combat)
- Damage animation / floating numbers / projectile visuals
- Large (2-hex) units
- Combat AI lacking hero spellcasting and target prioritization

### Adventure Map (Milestone 3)
- Map objects (mines, chests, towns, neutral creature stacks)
- Day/Week/Month time system (GameState has fields, no TimeManager)
- Full HUD (resource bar, minimap, day counter)
- Terrain types and movement cost variation
- Seeded map generation (still uses `rng.randomize()` instead of `GameState.run_seed`)
- Underground layer
- Fog of war save/load integration (explored_tiles serialized but not restored on map load)
- Hero stats panel on map

### Integration
- MainMenu → AdventureMap flow broken (FactionSelect.tscn doesn't exist)
- No combat trigger from adventure map (no neutral stacks to walk into)
- 11 missing scenes registered in SceneManager
- Save/load serialization stubs rely on unimplemented factory classes (HeroFactory, TownFactory)

## Known Issues

1. **Combat AI delay** — 0.55s timer at `_run_ai_turn()` start adds delay even when movement animation already took time
2. **Adventure map unseeded** — `rng.randomize()` instead of `GameState.run_seed`  
3. **UI hardcoded positions** — HUD elements at pixel positions (860, 1020) work at 1920×1080 only
4. **Path arrows flicker** — `_path_layer.clear()` every mouse-motion frame
5. **No input deadzone** — clicking very close to player registers as valid movement target
6. **Camera smoothing** — `position_smoothing` may cause brief coordinate mismatch during movement

## Next Recommended Action

**Map objects on adventure map** — Place neutral creature stacks, mines, and chests on the map. This unlocks combat triggering from the adventure map (walk into a neutral stack → CombatScene) and resource income from captured mines, which are the highest-impact missing features for creating a meaningful gameplay loop.
