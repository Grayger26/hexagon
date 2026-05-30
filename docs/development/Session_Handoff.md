# Session Handoff — 2026-05-30

## Work Completed

- **Fixed A* zigzag paths on adventure map** — Reordered `DIRECTIONS_MOVE` in `SquareGrid.gd` so cardinal directions (N, E, S, W) are explored before diagonals (NE, SE, SW, NW). This prevents A* from producing zigzag paths when cardinal and diagonal steps have equal f-cost under Chebyshev heuristic.

- **Fixed path arrow directions** — Changed `_draw_path_arrows` in `AdventureMap.gd` from backward-looking (`diff = curr - prev`) to forward-looking (`diff = nxt - curr`). Arrows now point toward the next tile instead of back toward the player.

- **Fixed diagonal arrow atlas mapping** — Reverted accidental diagonal swap in `DIRECTION_ARROW_ATLAS`. The atlas follows natural corner layout: (0,0)=NW, (2,0)=NE, (0,2)=SW, (2,2)=SE. The shaft extends toward the opposite corner; the arrowhead is at the atlas-position corner.

- **Created docs/development/Project_State.md** — Project architecture and milestone status reference.

## Modified Files

| File | Change |
|---|---|
| `scripts/adventure_map/SquareGrid.gd` | DIRECTIONS_MOVE ordering (cardinals first); DIRECTION_ARROW_ATLAS diagonal entries reverted to original |
| `scripts/adventure_map/AdventureMap.gd` | `_draw_path_arrows` forward-looking diff |
| `docs/development/Project_State.md` | New — project state reference |

## Unfinished Tasks

### Combat (Milestone 2)
- Spell system (SpellData exists, no casting, targeting, or SpellSystem.gd)
- Hero integration (hero panels on battlefield, hero action, hero death)
- War machines (Ballista, Ammo Cart, First Aid Tent)
- Siege combat (walls, gate, moat, towers, catapult)
- Special abilities (double_attack, life_drain, etc. defined but not checked in combat)
- Damage animation / floating numbers / projectile visuals
- Large (2-hex) units
- Combat AI lacking hero spellcasting and target prioritization

### Adventure Map (Milestone 3)
- Fog of war (GameState.explored_tiles exists, no render-time overlay)
- Map objects (mines, chests, towns, neutral creature stacks)
- Day/Week/Month time system (GameState has fields, no TimeManager)
- Full HUD (resource bar, mini-map, day counter)
- Terrain types and movement cost variation
- Seeded map generation
- Underground layer
- Hero stats panel on map

### Integration
- MainMenu → AdventureMap flow broken (FactionSelect.tscn doesn't exist)
- No combat trigger from adventure map (no neutral stacks to walk into)
- 11 missing scenes registered in SceneManager
- Save/load serialization stubs rely on unimplemented factory classes (HeroFactory, TownFactory)

### Known Issues
1. **Combat AI delay** — 0.55s timer at `_run_ai_turn()` start adds delay even when movement animation already took time
2. **Adventure map unseeded** — `rng.randomize()` instead of `GameState.run_seed`
3. **UI hardcoded positions** — HUD elements at pixel positions (860, 1020) work at 1920×1080 only
4. **Path arrows flicker** — `_path_layer.clear()` every mouse-motion frame
5. **No input deadzone** — clicking very close to player registers as valid movement target
6. **Camera smoothing** — `position_smoothing` may cause brief coordinate mismatch during movement

## Next Recommended Action

**Fog of war** — 3-state system (UNSEEN/EXPLORED/VISIBLE) with visibility radius around the hero. This is the highest-impact missing feature for the adventure map and a prerequisite for meaningful map exploration.
