# Heroes of Might and Magic 3 — Game Mechanics Research
## Reference Document for Godot Clone Project

---

## 1. GAME OVERVIEW

**Original Release:** 1999 by New World Computing  
**Genre:** Turn-based Strategy / RPG hybrid  
**Setting:** Fantasy world of Erathia (continent of Antagarich)  
**Core Loop:** Explore map → Gather resources → Build towns → Recruit armies → Defeat enemies

HoMM3 is fundamentally split into **two game layers**:
1. **Adventure Map** — exploration, resource collection, town management, hero movement
2. **Tactical Combat** — turn-based hex-grid battles between armies

---

## 2. THE ADVENTURE MAP

### 2.1 Map Structure
- Top-down 2D tile-based map (isometric look in original)
- Two layers: **Surface** and **Underground** (connected by cave entrances)
- Terrain types: Grass, Snow, Swamp, Desert, Lava, Rough, Dirt, Sand, Water, Rock, Highlands
- Fog of war: unexplored tiles are blacked out; explored but not "seen" are darkened

### 2.2 Time System
- Each player's turn = **1 Day**
- **7 Days = 1 Week** (named week; some have special effects)
  - e.g. "Week of the Pikeman" doubles pikeman growth
  - "Week of Plague" halves all creature growth
- **4 Weeks = 1 Month**
- On Week 1, all creature dwellings are populated
- Every subsequent week, creature dwellings replenish with new units to recruit

### 2.3 Resources (7 types)
| Resource | Primary Use |
|---|---|
| Gold | Recruiting creatures, building construction |
| Wood | Buildings, town halls |
| Ore | Buildings, creature dwellings |
| Mercury | Magic buildings, certain faction structures |
| Sulfur | Magic buildings, certain faction structures |
| Crystal | Magic buildings, certain creatures |
| Gems | Magic buildings, certain creatures |

Resources are gained by:
- **Mines** — flagged mines produce 1 unit/day (e.g. Gold Mine = +1000 gold/day)
- **Treasure Chests** — one-time pickups on map (gold or XP choice)
- **Town income** — Town Hall / City Hall / Capitol building tiers
- **Map structures** — sawmills, alchemist labs, etc.

### 2.4 Adventure Map Objects (Key Types)
- **Mines:** Gold, Wood, Ore, Mercury, Sulfur, Crystal, Gem
- **Creature Dwellings:** External creature recruitment (e.g. Gnoll Hut)
- **Treasure/Pickups:** Chests, resource piles, artifacts on ground
- **Stat Boosters:** Mercenary Camp (+Attack), Garden of Revelation (+Knowledge), etc.
- **Spell Sites:** Mage Guild (in towns), Magic Spring (restore mana), Learning Stone
- **Portals/Teleports:** Monolith pairs, Whirlpool (sea), Subterranean Gate
- **Obstacle/Gating:** Garrison (owned fortification guarding a pass)
- **Creature Banks:** Crypt, Dragon Utopia, Cyclops Stockpile — guarded by neutral creatures, reward artifacts/resources
- **Tavern:** Hire heroes, view rumors
- **Windmill / Watermill:** Weekly resource bonus
- **Obelisk:** Reveals part of Grail puzzle map
- **Arena / Colosseum:** Trade resources for primary stat increases
- **Stables:** Bonus movement to visiting hero

---

## 3. HEROES

### 3.1 Hero Archetypes
- **Might Heroes** (Knights, Rangers, Overlords, etc.) — higher Attack/Defense growth, start without spellbook, favor combat skills
- **Magic Heroes** (Wizards, Necromancers, Warlocks, etc.) — higher Spell Power/Knowledge growth, start with spellbook, favor magic skills

### 3.2 Primary Stats (4 stats)
| Stat | Effect |
|---|---|
| Attack | Increases damage dealt by friendly creatures |
| Defense | Reduces damage received from enemy creatures (NOT spells) |
| Spell Power | Increases damage/duration of spells |
| Knowledge | Increases mana pool (Knowledge × 10 = max mana) |

Each level-up grants +1 to one primary stat (weighted by hero class).

### 3.3 Secondary Skills
Heroes can learn up to **8 secondary skills**, each with 3 tiers: Basic → Advanced → Expert.  
There are **28 secondary skills** total, grouped into:

**Combat Skills (Red)**
- Offence — increases creature attack damage %
- Armorer — reduces damage taken %
- Artillery — unlocks/improves Ballista war machine
- Tactics — allows repositioning troops before combat
- Leadership — boosts troop Morale
- Luck — boosts Luck stat
- Resistance — chance to resist enemy spells
- First Aid — improves Tent war machine
- Archery — boosts ranged damage

**Adventure Skills (Yellow)**
- Logistics — increases daily movement points
- Navigation — increases movement on water
- Scouting — increases vision radius
- Pathfinding — reduces movement penalty on rough terrain
- Estates — generates daily gold income
- Intelligence — increases mana as % of enemy hero's mana
- Mysticism — regenerates mana each day

**Magic Skills (Blue)**
- Wisdom — allows learning level 3/4/5 spells
- Air/Earth/Fire/Water Magic — each boosts respective spell school
- Scholar — can share spells with allied heroes
- Eagle Eye — chance to learn enemy-cast spells
- Sorcery — boosts spell damage %
- Necromancy — raises fallen enemies as Skeletons after combat
- Learning — increases XP gained per level

### 3.4 Hero Specialties
Each hero has a **unique specialty** (shown on hero card):
- Unit specialist (e.g. Archers get +1 Attack per level)
- Spell specialist (e.g. Slow is always cast at Expert level)
- Skill specialist (e.g. Logistics bonus doubled)
- Resource/gold production bonuses
- Unique unit bonuses

### 3.5 Experience & Leveling
- XP needed per level increases geometrically
- At each level: gain +1 primary stat + offered choice of 2 secondary skills
- Level cap: effectively 74 (in practice heroes rarely exceed 20–25 in a scenario)

### 3.6 Hero Movement
- Heroes have a movement point pool per day
- Terrain type affects movement cost (roads reduce cost greatly)
- Abilities like Logistics (secondary skill) and Stables (map object) increase movement
- Heroes can **board ships** to travel water, using separate sea movement points
- A hero with no movement left must **End Turn**

---

## 4. TOWNS

### 4.1 Town Structure
Each town belongs to a **faction** and provides:
- **Building tree** — one building per day, buildings unlock other buildings
- **Creature dwellings** — produce weekly creatures for hire (7 tiers per town)
- **Mage Guild** — teaches spells (up to level 5 depending on guild level built)
- **Town Hall → City Hall → Capitol** — increases daily gold income
- **Fort → Citadel → Castle** — improves garrison strength and combat walls
- **Blacksmith** — buys war machines (Ballista, Ammo Cart, First Aid Tent)
- **Tavern** — hire heroes, read rumors
- **Special Buildings** — unique per faction (see below)

### 4.2 The Grail
A hidden object on the adventure map. Found by visiting Obelisks (each reveals part of the puzzle).  
When dug up (hero uses Dig action), gives a **Grail artifact** — placed in any town for a massive gold bonus and unique special building.

### 4.3 Creature Tiers (7 per town)
- Tier 1–2: Cheap, weak; used as cannon fodder or fillers
- Tier 3–4: Mid-range; often most cost-effective
- Tier 5–6: Powerful; expensive
- Tier 7: "Elite" — most powerful, very expensive, slow to accumulate
- Most creatures have an **upgraded** version (stronger stats, often new ability, higher cost)

### 4.4 The 9 Factions (base game + expansions)
| Town | Theme | Notable Units |
|---|---|---|
| **Castle** | Human kingdom, high morale | Archangel (resurrect), Marksman (double shot), Cavalier |
| **Rampart** | Elves/dwarves/nature | Unicorn (blind), Grand Elf (ranged), Green Dragon |
| **Tower** | Wizards/constructs | Titan (ranged powerhouse), Naga, Master Genie (buffs) |
| **Inferno** | Demons | Pit Lord (summon demons), Efreet (fire immunity), Devil |
| **Necropolis** | Undead | Vampire Lord (no retaliation + life drain), Lich, Bone Dragon; Necromancy mechanic |
| **Dungeon** | Dark elves/warlocks | Black Dragon (spell immune), Minotaur, Manticore |
| **Stronghold** | Orcs/barbarians | Cyclops (wall destruction), Behemoth |
| **Fortress** | Lizardmen/gnolls/swamp | Wyvern, Serpent Fly, Gorgon (death stare) |
| **Conflux** | Elementals | Firebird, Phoenix, various elemental types |

---

## 5. COMBAT SYSTEM

### 5.1 Combat Trigger
Combat begins when a hero:
- Moves onto a hex occupied by enemy creatures (neutral or opposing hero)
- Attacks a town (siege combat)
- Is attacked by an enemy hero

### 5.2 Combat Battlefield
- **11 × 17 hex grid** (hexagonal tiles)
- Attacker enters from **left**, defender from **right**
- Obstacles scattered randomly (rocks, trees, etc.)
- In **siege combat**: walls, gate, towers, and moat added

### 5.3 Initiative & Turn Order
- All unit stacks sorted by **Speed** (fastest acts first)
- On equal speed, attacker goes before defender
- Each stack gets **one action per round**
- A round ends when all stacks have acted

### 5.4 Unit Stack Actions
Each turn, a unit stack can:
- **Move** — up to its Speed value in hexes
- **Attack** — melee (must be adjacent) or ranged (if ranged unit)
- **Wait** — defer action to later in the round
- **Defend** — skip action, gain temporary +defense bonus
- **Special Ability** — some units have unique actions (e.g. cast spell)

### 5.5 Damage Formula
```
Base Damage = Random value in unit's damage range × stack count
Attack Modifier = if Attacker > Defender: +(5% per diff, max +300%)
Defense Modifier = if Defender > Attacker: -(2.5% per diff, max -70%)
Final Damage = Base Damage × Attack Modifier × Defense Modifier
```
- Luck: 12.5% chance of dealing double damage (with +3 Luck)
- Morale: positive morale = chance to act twice; negative = chance to freeze

### 5.6 Special Unit Abilities (Examples)
- **No retaliation** — attacks don't trigger counter-attack (Vampire Lords, Devils)
- **Double attack** — attacks twice per turn (Crusaders, Wolves)
- **Ranged** — can attack any target without moving (Archers, Liches)
- **Shooter penalty** — ranged attack halved at close range or through obstacles
- **Flying** — ignores terrain/obstacles, can land anywhere
- **Large creature** — occupies 2 hexes
- **Spell casting** — some units cast spells (Master Genies, Archangels, Liches)
- **Resurrect** — Archangel can resurrect one stack once per combat
- **Life drain** — Vampire Lords restore HP equal to damage dealt
- **Petrify / Blind / Paralyze** — status effects
- **Fire immunity, magic immunity** — some creatures immune to certain spell schools

### 5.7 Hero Role in Combat
- Hero stands behind army, is NOT on the hex grid (cannot be targeted directly)
- Each round, hero can cast **one spell** (limited by mana)
- Hero's Attack/Defense stats boost friendly creature damage/resistance
- If hero is defeated (all creatures die), hero is captured (loses army, reduced to 1 creature, sent to nearest prison/starting town)

### 5.8 Morale & Luck
- **Morale** (-3 to +3): Positive = chance to take extra turn; negative = chance to lose a turn
- Affected by: Leadership skill, faction mix (different races = morale penalty), artifacts, undead (always neutral morale)
- **Luck** (0 to +3): Chance for double damage roll
- Affected by: Luck secondary skill, artifacts, certain map structures

### 5.9 War Machines (Hero Equipment)
- **Ballista** — shoots as a creature each round (hero controls it with Artillery skill)
- **Ammo Cart** — extends ranged ammo for all shooters to unlimited
- **First Aid Tent** — heals a friendly stack each round (hero controls with First Aid skill)
- **Catapult** — only in siege; automatically attacks walls

### 5.10 Siege Combat Specifics
- Defender has **walls** (can be destroyed), **towers** (auto-attack each round), **gate**
- Attacker uses **Catapult** to break walls; Cyclops units are excellent wall destroyers
- Defenders inside walls cannot be melee-attacked until walls are breached or gate broken
- **Moat** slows movement of attacking units
- If defender has Citadel/Castle building, extra towers/turrets are active

### 5.11 Spell Schools (4 schools, 5 levels each)
| School | Theme |
|---|---|
| Fire Magic | Damage spells, combat buffs/debuffs |
| Air Magic | Speed/Haste, Lightning, Dimension Door, Fly |
| Water Magic | Healing, Slow, Blizzard, Forgetfulness |
| Earth Magic | Earthquake (siege), Implosion, Shield, Resurrection |

Key spells:
- **Haste/Slow** — most impactful movement modifiers
- **Blind/Paralyze/Berserk** — CC spells removing enemy stacks from action
- **Implosion** — highest single-target damage (Earth)
- **Chain Lightning** — high AoE damage (Air)
- **Resurrection** — revives fallen friendly stack (Earth, expensive)
- **Dimension Door** — teleport hero anywhere on map (Air, powerful utility)
- **Town Portal** — return to any friendly town instantly (Earth, essential utility)
- **Armageddon** — damages ALL units on battlefield (Fire, used by immune armies)
- **Animate Dead** — resurrects undead units

---

## 6. ARTIFACTS

- **150+ artifacts** across multiple tiers: Treasure, Minor, Major, Relic, Combination
- Equipped on hero paper-doll: Head, Shoulders, Neck, Torso, Hand (×2), Ring (×2), Feet, misc
- Give stat bonuses, special abilities, immunities
- **Combination Artifacts** — assemble multiple artifacts into one superpowered set (e.g. Cornucopia, Admiral's Hat)
- Found on adventure map, in creature banks, bought in artifact merchants, rewarded from quests

---

## 7. VICTORY & DEFEAT CONDITIONS

Standard conditions (plus custom map editor options):
- **Win:** Defeat all enemy heroes + capture all towns
- **Win:** Capture a specific town
- **Win:** Defeat a specific hero
- **Win:** Find a specific artifact
- **Win:** Accumulate X resources
- **Win:** Build a specific building (Grail)
- **Lose:** Lose your starting hero
- **Lose:** Time limit expires
- **Lose:** Lose a specific town

---

## 8. ROGUELIKE ADAPTATION NOTES

For your Godot clone with roguelike elements, consider these mappings:

### Adventure Map → Roguelike Run
- Procedurally generated maps each run
- Limited hero "lives" (lose hero = run over or penalty)
- Permanent upgrades between runs (meta-progression)
- Random artifact/spell pools per run

### Town System → Roguelike Simplification
- Replace multi-town management with a **single evolving base**
- Building choices = run-specific upgrades
- Weekly creature growth = unlocked unit slots per milestone

### Faction → Character Class
- Each faction becomes a **starting class** with unique unit roster and spell school
- Class determines starting hero stats and ability bias

### Combat → Hex Tactical Battles
- Keep the hex grid turn-based combat as-is (core HoMM feel)
- Roguelike twist: post-battle loot drops, relics, HP doesn't fully restore between fights
- Boss encounters every N battles

### Hero Leveling → Roguelike Build Path
- Each level-up offers **3 choices** (instead of 2) for roguelike feel
- Secondary skills become "talents" with run-specific synergies
- Remove repetitive skills — every pick should feel meaningful

---

## 9. KEY SYSTEMS PRIORITY FOR GODOT IMPLEMENTATION

### Phase 1 — Core (MVP)
1. Hex grid combat engine
2. Unit stacks with speed/attack/defense/HP
3. Hero with 4 primary stats
4. Spell system (at least 2 schools)
5. Simple adventure map with movement

### Phase 2 — Depth
6. Town building tree
7. Resource management (at least Gold + 2-3 rare resources)
8. Morale & Luck systems
9. War machines
10. Siege combat

### Phase 3 — Roguelike Layer
11. Procedural map generation
12. Run meta-progression
13. Artifact / relic system
14. Multiple factions/classes
15. Victory/defeat conditions per run

---

## 10. GODOT-SPECIFIC NOTES

- Use **TileMap** for both adventure map and hex combat grid
- Hex grid: use Godot's built-in offset coordinate system (or cube coordinates for pathfinding)
- For turn order: a simple **priority queue** sorted by unit Speed
- Hero data: use **Resources (.tres)** for heroes, units, spells, artifacts
- Combat state machine: **StateMachine** pattern (PlayerTurn → EnemyTurn → ResolveCombat → etc.)
- Adventure map: consider a **Scene-per-zone** approach with transitions, or a single large TileMap with chunking
- Signals for event-driven systems (unit dies → trigger necromancy, etc.)

---

*Document compiled for HoMM3 Godot clone project. Last updated: 2026.*
