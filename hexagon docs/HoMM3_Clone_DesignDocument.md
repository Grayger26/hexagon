# HoMM3 Roguelike Clone — Project Design Document
## Godot Engine | Turn-Based Strategy / Roguelike / RPG

**Version:** 1.0  
**Engine:** Godot 4.x  
**Genre:** 2D Turn-Based Strategy + Roguelike + RPG  
**Reference:** Heroes of Might and Magic 3 (1999, New World Computing)

---

## DESIGN PILLARS

Before anything else, three pillars guide every decision in this project:

1. **Feel like HoMM3** — Hex combat, hero progression, army stacks. The core tactical loop must feel authentic.
2. **Play like a roguelike** — Each run is unique. Procedural maps, random artifacts, build variety, meaningful permadeath stakes.
3. **Ship incrementally** — Every milestone produces something playable. No "engine work" milestones without a playable result.

---

## PROJECT STRUCTURE OVERVIEW

```
MILESTONE 0 — Project Foundation & Architecture         (Week 1–2)
MILESTONE 1 — Combat Prototype                          (Week 3–6)
MILESTONE 2 — Full Combat System                        (Week 7–10)
MILESTONE 3 — Adventure Map Prototype                   (Week 11–14)
MILESTONE 4 — Hero & Progression Systems                (Week 15–18)
MILESTONE 5 — Town & Resource Systems                   (Week 19–23)
MILESTONE 6 — Roguelike Loop                            (Week 24–28)
MILESTONE 7 — Content Pass (Factions, Spells, Units)    (Week 29–34)
MILESTONE 8 — Polish, Audio, UI                         (Week 35–40)
MILESTONE 9 — Balancing & Release Candidate             (Week 41–44)
```

---

---

# MILESTONE 0 — Project Foundation & Architecture
**Goal:** Empty project runs, folder structure established, core data patterns decided.  
**Playable result:** Nothing yet — this is scaffolding only.

## 0.1 Godot Project Setup
- [ ] Create Godot 4.x project, configure 2D rendering pipeline
- [ ] Set base resolution: `1920×1080`, stretch mode: `canvas_items`
- [ ] Establish folder structure:
  ```
  /scenes
    /combat
    /adventure_map
    /ui
    /menus
  /scripts
    /combat
    /adventure_map
    /systems
    /data
    /utils
  /resources
    /units
    /heroes
    /spells
    /artifacts
    /factions
    /maps
  /assets
    /sprites
    /audio
    /fonts
    /tilemaps
  /autoloads
  ```
- [ ] Set up version control (Git), add `.gitignore` for Godot

## 0.2 Autoload (Global) Singletons
Define the global systems that persist across all scenes:
- [ ] `GameState` — current run state (hero, resources, day, map seed)
- [ ] `EventBus` — global Signal bus for decoupled communication
- [ ] `DataManager` — loads and caches all `.tres` resource files
- [ ] `SceneManager` — handles scene transitions with optional loading screen
- [ ] `SaveManager` — handles save/load (roguelike: single save slot with run state)
- [ ] `AudioManager` — plays music/SFX with pooling

## 0.3 Core Data Schemas (Resources)
Define all `.tres` resource classes before writing any game logic:

```gdscript
# UnitData.gd (extends Resource)
@export var unit_name: String
@export var faction: String
@export var tier: int               # 1–7
@export var attack: int
@export var defense: int
@export var min_damage: int
@export var max_damage: int
@export var hp: int
@export var speed: int              # determines turn order
@export var movement: int           # hex movement range in combat
@export var is_ranged: bool
@export var is_flying: bool
@export var is_large: bool          # occupies 2 hexes
@export var abilities: Array[String]
@export var sprite: Texture2D

# HeroData.gd (extends Resource)
@export var hero_name: String
@export var faction: String
@export var hero_type: String       # "might" or "magic"
@export var attack: int
@export var defense: int
@export var spell_power: int
@export var knowledge: int
@export var secondary_skills: Dictionary   # skill_name: level (1–3)
@export var specialty: String
@export var spellbook: Array[String]
@export var portrait: Texture2D

# SpellData.gd (extends Resource)
@export var spell_name: String
@export var school: String          # "fire" "air" "water" "earth"
@export var level: int              # 1–5
@export var mana_cost: int
@export var effect_type: String     # "damage" "buff" "debuff" "summon" etc.
@export var base_value: float
@export var power_scaling: float    # value added per Spell Power point
@export var duration: int           # rounds (-1 = permanent until end of combat)
@export var target_type: String     # "single" "aoe" "all_enemies" "all_allies"

# ArtifactData.gd (extends Resource)
@export var artifact_name: String
@export var tier: String            # "treasure" "minor" "major" "relic"
@export var slot: String            # "head" "torso" "hand" "feet" "ring" "neck"
@export var stat_bonuses: Dictionary
@export var special_ability: String
@export var description: String
@export var icon: Texture2D
```

## 0.4 State Machine Base Class
Write a reusable `StateMachine.gd` that all game state machines (combat, adventure map, UI) extend. This prevents spaghetti logic later.

```gdscript
# StateMachine.gd (autoload or base class)
class_name StateMachine extends Node
var current_state: State
func transition_to(new_state: State) -> void: ...
func update(delta: float) -> void: ...
```

---

---

# MILESTONE 1 — Combat Prototype
**Goal:** Two armies fight on a hex grid. You can click to move and attack. Winner is determined.  
**Playable result:** A standalone combat scene. Hardcoded armies, no hero, no spells yet.

## 1.1 Hex Grid System
This is the most critical technical foundation. Get it right.

- [ ] Decide coordinate system: **Cube coordinates** internally (q, r, s), convert to pixel for rendering
- [ ] Implement `HexGrid.gd`:
  - `hex_to_pixel(hex: Vector3i) -> Vector2` 
  - `pixel_to_hex(pos: Vector2) -> Vector3i`
  - `hex_distance(a, b) -> int`
  - `get_neighbors(hex) -> Array[Vector3i]`
  - `get_hexes_in_range(origin, range) -> Array[Vector3i]`
  - `find_path(start, end, blocked) -> Array[Vector3i]`  ← A* or BFS
- [ ] Create `CombatTileMap` scene:
  - 11 columns × 17 rows hex grid
  - Visual tile states: normal, highlighted (movement range), targeted, occupied
- [ ] Implement obstacle placement (random static obstacles per battle)
- [ ] Click-to-select hex, hover highlight

## 1.2 Unit Stack Entity
- [ ] Create `UnitStack.gd` scene:
  - Properties: `unit_data: UnitData`, `stack_count: int`, `current_hp: int`
  - Computed: `total_hp = unit_data.hp × stack_count`  
  - Visual: sprite + stack count number label
  - Hex position tracking
- [ ] Place unit stacks on grid (attacker left, defender right, 6 slots per side)
- [ ] Visual: highlight selected stack, show movement range on select

## 1.3 Combat Turn Manager
- [ ] `CombatTurnManager.gd`:
  - Build turn queue from all unit stacks sorted by Speed (descending)
  - On equal speed: attacker side goes first
  - Track "current acting stack"
  - Advance queue after each action
  - Detect round end (all stacks acted); rebuild queue for next round
- [ ] Visual turn order display (horizontal strip of unit icons showing upcoming order)

## 1.4 Unit Actions — Move & Attack
- [ ] **Move action:**
  - On stack select: calculate reachable hexes (BFS up to Speed range, blocked by other units)
  - Highlight reachable hexes in blue
  - Click hex → move stack there (animate movement along path)
  - Deduct movement from remaining actions
- [ ] **Melee Attack:**
  - After moving adjacent to enemy: highlight attackable enemies in red
  - Click enemy → resolve attack
  - Attacker deals damage → enemy loses HP → update stack count
  - Enemy retaliates once (unless no-retaliation ability)
  - If stack_count reaches 0: remove stack from grid, mark hex empty
- [ ] **Wait action:** defer stack to end of round queue
- [ ] **Defend action:** stack gains +defense modifier until next turn

## 1.5 Damage Resolution
Implement the formula from the research doc:
```gdscript
func calculate_damage(attacker: UnitStack, defender: UnitStack) -> int:
    var base = randi_range(attacker.unit_data.min_damage, 
                           attacker.unit_data.max_damage) * attacker.stack_count
    var atk = attacker.unit_data.attack
    var def = defender.unit_data.defense
    var modifier = 1.0
    if atk > def:
        modifier = 1.0 + 0.05 * min(atk - def, 60)   # +5% per point, cap at +300%
    elif def > atk:
        modifier = 1.0 - 0.025 * min(def - atk, 28)  # -2.5% per point, cap at -70%
    return int(base * modifier)
```
- [ ] Apply damage, recalculate stack count: `new_count = ceil(remaining_hp / unit_data.hp)`
- [ ] Show floating damage numbers on hit

## 1.6 Combat End Condition
- [ ] Detect when all stacks of one side are eliminated
- [ ] Show "Victory" / "Defeat" overlay
- [ ] "Return to Map" button (goes nowhere yet — just resets scene)

---

---

# MILESTONE 2 — Full Combat System
**Goal:** Combat feels like HoMM3. Ranged units, flying, spells, morale, hero, siege basics.  
**Playable result:** Full combat with hero, spellcasting, all unit types, siege mode toggle.

## 2.1 Ranged Combat
- [ ] Ranged units can attack any enemy without moving
- [ ] Highlight all enemies red when ranged unit is selected (no movement required)
- [ ] **Ammo system:** ranged units have limited shots (Ammo Cart removes limit later)
- [ ] **Range penalty:** if enemy unit is adjacent to ranged unit, damage is halved
- [ ] **Obstacle penalty:** if line-of-sight blocked by obstacles, damage halved (don't stack with range penalty)
- [ ] Visual: projectile animation from attacker to defender

## 2.2 Flying Units
- [ ] Flying units ignore all obstacles and other units when pathfinding
- [ ] Reachable hexes = all hexes within Speed range regardless of obstacles
- [ ] Can still be blocked from landing on occupied hexes
- [ ] Mark flying units with a visual indicator (subtle shadow / wing icon)

## 2.3 Large (2-Hex) Units
- [ ] Large units occupy a "head" hex and a "tail" hex
- [ ] Both hexes are blocked for movement
- [ ] Attacker can target either hex; damage applies to the stack
- [ ] Pathfinding accounts for 2-hex footprint

## 2.4 Hero Integration
- [ ] `CombatHero.gd` — hero sits off-grid (portrait + stats panel on side of battlefield)
- [ ] Hero stats passively apply to all friendly stacks:
  - Attack stat adds flat bonus to all friendly melee/ranged damage
  - Defense stat reduces all incoming damage to friendlies
- [ ] **Hero action:** once per round, hero may cast one spell OR use a war machine
- [ ] Hero "dies" when all friendly stacks are wiped → combat lost
- [ ] Add placeholder hero with hardcoded stats for now

## 2.5 Spell System
- [ ] `SpellSystem.gd`:
  - Hero has mana pool (Knowledge × 10)
  - During hero's action phase: show spell list UI
  - Select spell → prompt for target (depends on target_type)
  - Apply spell effect, deduct mana cost
- [ ] **Implement first 8 spells (2 per school):**
  - Fire: `Fireball` (AoE damage), `Curse` (reduces damage dealt)
  - Air: `Haste` (increases Speed), `Lightning Bolt` (single target damage)
  - Water: `Slow` (decreases Speed), `Cure` (heals friendly stack)
  - Earth: `Shield` (reduces damage taken), `Stone Skin` (+defense buff)
- [ ] **Buff/Debuff tracking:** each stack has `active_effects: Array[Effect]`
  - Effect has: `type`, `value`, `duration` (rounds remaining)
  - Effects are decremented at start of that stack's turn
- [ ] Visual: spell animation, affected unit glows during effect duration
- [ ] Status icons on affected stacks (small icon showing active buffs/debuffs)

## 2.6 Morale & Luck
- [ ] `MoraleSystem.gd`:
  - Calculate morale value per stack based on: faction mix, Leadership skill, artifacts
  - Same-faction armies: neutral (0); mixed factions: -1 penalty per extra faction
  - On stack's turn: roll for morale proc
  - Positive morale (1+): 8.33%/16.67%/25% chance of extra turn (basic/adv/expert Leadership)
  - Negative morale: 8.33%/16.67%/25% chance of losing turn
  - Undead: always neutral morale (immune to morale)
- [ ] `LuckSystem.gd`:
  - Luck value per-hero (0–3), applies to all friendly stacks
  - On damage roll: 12.5% chance per luck point of dealing double damage
  - Roll luck before applying damage formula

## 2.7 Special Unit Abilities
Implement a flag-based ability system. Each UnitData has `abilities: Array[String]`.
- [ ] `no_retaliation` — skip retaliation after being attacked
- [ ] `double_attack` — attacks twice in one action (second hit no retaliation)
- [ ] `life_drain` — attacker heals HP equal to damage dealt (capped at lost HP)
- [ ] `immune_fire / immune_air / immune_water / immune_earth` — immune to that school
- [ ] `immune_all_spells` — immune to all magic (Black Dragon)
- [ ] `petrify` — chance to petrify target on attack (skips next turn)
- [ ] `death_stare` — small % chance to instantly kill entire stack count

## 2.8 War Machines
- [ ] **Ballista:** acts as a separate "unit" on the grid (right side of battlefield)
  - Attacks once per round if hero has Artillery skill, otherwise every other round
  - Cannot move, can be destroyed by enemies
- [ ] **Ammo Cart:** removes ammo limit for all friendly ranged units
- [ ] **First Aid Tent:** heals one friendly stack per round (hero with First Aid skill directs it)

## 2.9 Siege Combat Mode
- [ ] Toggle: `CombatScene` can be initialized in `siege_mode: bool`
- [ ] In siege mode: add Wall tiles in predefined positions (center column)
  - Gate hex (can be opened/destroyed)
  - Two wall sections left and right of gate (each has HP)
  - Two corner towers (auto-attack attacker stacks every round)
- [ ] `WallManager.gd`: walls have HP, reduce by catapult or special unit hits
- [ ] Defenders behind intact walls cannot be melee-attacked
- [ ] **Catapult:** auto-fires at random wall section each round; player can target with Artillery skill
- [ ] **Moat:** hexes in front of gate slow attacker movement (costs extra movement points)

## 2.10 Combat AI (Basic)
- [ ] Enemy stacks use simple AI:
  1. If ranged: stay put, shoot nearest enemy
  2. If melee flier: fly to and attack highest-value (highest HP) target
  3. If melee walker: move toward nearest enemy, attack if adjacent
  4. Hero AI: cast highest-damage spell on stack with most units
- [ ] AI acts with a short delay so player can follow what's happening

---

---

# MILESTONE 3 — Adventure Map Prototype
**Goal:** Hero walks around a tile map, picks up resources, triggers combat.  
**Playable result:** Simple 30×30 map with mines, chests, neutral creatures. Combat integrates.

## 3.1 Adventure Map TileMap
- [ ] Create `AdventureMap.gd` scene using Godot TileMap node
- [ ] Tile types: Grass, Dirt, Road, Water, Mountain (impassable), Forest (slows)
- [ ] **Movement cost per tile type:**
  - Road: 0.5× cost
  - Grass/Dirt: 1× cost
  - Forest/Rough: 1.5× cost  
  - Water: impassable (without ship)
  - Mountain/Rock: impassable
- [ ] Tile atlas setup: one tileset with all terrain variants
- [ ] **Fog of War:**
  - Each tile has 3 states: `UNSEEN` (black), `EXPLORED` (dimmed), `VISIBLE` (clear)
  - Visibility radius around hero (default 5 tiles, expanded by Scouting skill)
  - When hero moves: reveal tiles in radius, mark visited tiles as EXPLORED

## 3.2 Hero on Adventure Map
- [ ] `AdventureHero.gd`:
  - Position on map (tile coordinates)
  - Movement points per day (default 1500; terrain costs subtract from pool)
  - Each day: movement pool resets on "End Turn"
- [ ] Click-to-move: click a tile → calculate path (A*), animate hero walking along path
- [ ] Path preview: show path line when hovering over destination
- [ ] Stop movement if movement points run out mid-path
- [ ] **End Turn button:** advances day counter, resets movement, triggers "new day" events

## 3.3 Map Objects — First Pass
Implement these object types as `MapObject` scenes placed on the map:

- [ ] **Gold Mine:** shows owner flag; when hero walks onto it, flag changes to player color → generates +1000 gold/day
- [ ] **Resource Pile:** one-time pickup, adds resources to player inventory
- [ ] **Treasure Chest:** interact → popup: "Take 1000 gold" or "Take 500 XP"
- [ ] **Neutral Creature Stack:** enemy unit stack sitting on map tile; walking into it triggers combat
- [ ] **Town:** entering town opens Town UI (stub for now)
- [ ] **Garrison:** blocks path; must fight to pass

## 3.4 Combat Integration
- [ ] When hero walks into a neutral creature stack on map: `SceneManager` transitions to `CombatScene`
  - Pass hero data + enemy stack data to combat scene
  - On combat end: return to adventure map
  - Victory: neutral stack removed from map, XP awarded to hero
  - Defeat: hero loses army (stacks wiped), hero "retreats" to last town
- [ ] When hero walks into enemy hero: same transition, but both sides have heroes

## 3.5 Day/Week/Month System
- [ ] `TimeManager.gd` (autoload):
  - Track Day (1–7), Week (1–4), Month (n)
  - On End Turn: increment day; broadcast `EventBus.day_changed`
  - On Day 7→1: new week begins; broadcast `EventBus.week_changed`
    - Refill all creature dwellings on week change
    - Apply Week event (if any) — e.g. "Week of the Goblin" (double goblin growth)
  - Display Day/Week/Month in HUD

## 3.6 Basic HUD
- [ ] Top bar: Gold + all 6 rare resources displayed with icons
- [ ] Top right: Day / Week / Month counter
- [ ] Bottom bar: selected hero name, movement points remaining, End Turn button
- [ ] Mini-map (simple color-coded rectangle map, updates as fog lifts)

---

---

# MILESTONE 4 — Hero & Progression Systems
**Goal:** Hero gains XP, levels up, picks skills. Secondary skills affect combat noticeably.  
**Playable result:** Full hero sheet, level-up screen with choices, skills working in combat.

## 4.1 Experience & Level-Up
- [ ] `HeroProgression.gd`:
  - XP table: `xp_for_level[n] = 1000 × (n-1)^2` (approximate HoMM3 curve)
  - On combat victory: award XP based on enemy creature tiers and stack sizes
  - On XP threshold reached: trigger level-up
- [ ] **Level-Up UI Screen** (full-screen modal):
  - Show current stats
  - Display +1 to one primary stat (show which stat is gained, weighted by hero type)
  - Show 3 secondary skill choices (roguelike: 3 instead of 2)
  - Each choice card shows: skill name, current level → new level, description of effect
  - Player clicks one choice to confirm
- [ ] After level-up: apply stat/skill changes to hero data

## 4.2 Secondary Skill Implementation
Implement all 28 secondary skills. Group by implementation complexity:

**Tier A — Implement First (high impact, simple logic):**
- [ ] `Logistics` — multiply hero movement points by 1.1/1.2/1.3
- [ ] `Offence` — multiply all friendly damage by 1.1/1.2/1.3 in combat
- [ ] `Armorer` — multiply all friendly damage received by 0.95/0.90/0.85
- [ ] `Wisdom` — allow learning spells of level 3 / 4 / 5 from Mage Guild
- [ ] `Fire/Air/Water/Earth Magic` — spells of that school deal 25%/50%/75% more damage / duration
- [ ] `Leadership` — +1/+2/+3 morale to all friendly stacks
- [ ] `Luck` — +1/+2/+3 luck to all friendly stacks
- [ ] `Necromancy` — after battle: raise 10%/20%/30% of killed enemies as Skeletons

**Tier B — Implement Second:**
- [ ] `Archery` — ranged units deal 25%/50%/50% more damage (basic/advanced/expert)
- [ ] `Tactics` — pre-combat: move units within 3/5/unlimited hexes before battle starts
- [ ] `Scouting` — increase vision radius by +1/+2/+3 tiles
- [ ] `Pathfinding` — reduce rough terrain movement penalty by 25%/50%/75%
- [ ] `Mysticism` — regenerate 1/2/3 mana per day
- [ ] `Sorcery` — all spell damage increased by 5%/10%/15%
- [ ] `Resistance` — 5%/10%/20% chance to resist enemy spells
- [ ] `Intelligence` — gain mana equal to 25%/50%/100% of defeated enemy hero's max mana

**Tier C — Implement Later:**
- [ ] `Artillery` — control Ballista (basic), double Ballista shots (advanced/expert)
- [ ] `First Aid` — control Tent, improve healing amount
- [ ] `Navigation` — sea movement +50%/+100%/+150%
- [ ] `Estates` — +125/+250/+500 gold per day
- [ ] `Eagle Eye` — 10%/20%/30% chance to learn enemy-cast spell
- [ ] `Scholar` — share spells with allied heroes when meeting on map
- [ ] `Learning` — gain 5%/10%/15% more XP from combat

## 4.3 Hero Specialty System
- [ ] Each hero has one specialty loaded from their `HeroData` resource
- [ ] Specialty types:
  - `unit_specialist(unit_name)` — that unit type gets +1 Attack AND +1 Defense per hero level
  - `spell_specialist(spell_name)` — that spell always cast at Expert level regardless of school mastery
  - `skill_specialist(skill_name)` — that secondary skill's effect is doubled
  - `resource_specialist(resource)` — +X of that resource per day (passive)
- [ ] Specialties visible on Hero Sheet UI

## 4.4 Hero Sheet UI
- [ ] Full-screen "Hero Screen" (H key or click hero portrait):
  - Left: Hero portrait, name, class, level, XP bar
  - Center: Paper-doll with equipped artifact slots (head, neck, torso, hand×2, ring×2, feet)
  - Right: Primary stats (Attack, Defense, Spell Power, Knowledge) with breakdown tooltip
  - Bottom left: Secondary skills grid (8 slots, showing skill icon + level stars)
  - Bottom right: Spellbook (list of known spells with icons and mana cost)
  - Army: 7-slot army bar showing unit stacks (count, HP bar)

## 4.5 Army Management
- [ ] Hero carries up to 7 unit stacks (7 slots)
- [ ] Stacks of same unit type can be merged (click drag onto same type)
- [ ] Stacks can be split (shift+click to split stack)
- [ ] Units can be transferred between two heroes meeting on map
- [ ] Units can be garrisoned in / retrieved from towns

---

---

# MILESTONE 5 — Town & Resource Systems
**Goal:** Towns build buildings, grow creatures, provide spells. Resources are earned and spent.  
**Playable result:** Full resource loop. Enter town, build things, recruit units, leave and fight.

## 5.1 Resource Manager
- [ ] `ResourceManager.gd` (autoload):
  - Dictionary: `resources = { "gold": 0, "wood": 0, "ore": 0, "mercury": 0, "sulfur": 0, "crystal": 0, "gems": 0 }`
  - `add_resource(type, amount)`, `spend_resource(cost_dict) -> bool`
  - `get_daily_income() -> Dictionary` — sums all mine outputs + town income
  - On new day: call `add_resource` for each income source
- [ ] HUD resource bar updates reactively via signals

## 5.2 Mine System
- [ ] `Mine.gd` map object:
  - `resource_type`, `daily_output` (gold: 1000, others: 1/day)
  - `owner`: null / player / enemy
  - On hero interaction: change owner to hero's faction
  - On new day: if owned by player, `ResourceManager.add_resource()`
  - Visual: mine building sprite + colored flag showing owner

## 5.3 Town Scene
- [ ] `TownScene.gd` — entered when hero visits town on map
- [ ] Town belongs to a faction; uses that faction's building tree
- [ ] **Town Overview screen:**
  - Town illustration (background art for this faction)
  - Building slots: shows existing buildings, greyed-out unbuilt buildings
  - "Build" button on affordable/unlocked buildings
  - Resource costs shown with affordability color-coding (green = can afford, red = can't)
  - One build per day limit (greyed out after building)

## 5.4 Building Tree
- [ ] `BuildingTree.gd` — per faction, defines:
  - All buildings with name, cost, prerequisites, effect
  - `can_build(building_id) -> bool` — checks prerequisites + resources + one-per-day
  - `build(building_id)` — spends resources, marks built, triggers effect
- [ ] **Universal buildings (all factions):**
  - `Village Hall → Town Hall → City Hall → Capitol` (+250/+500/+1000/+2000 gold/day)
  - `Tavern` — hire heroes (up to 2 heroes for hire at any time)
  - `Fort → Citadel → Castle` — improves town garrison HP and siege walls
  - `Mage Guild Level 1–5` — unlocks spell learning (tier = available spell level)
  - `Marketplace` — resource trading at decreasing exchange rates
  - `Blacksmith` — purchase war machines

## 5.5 Creature Dwellings & Recruitment
- [ ] Each faction has 7 creature dwellings (one per tier), each with an optional upgrade building
- [ ] On week start: each built dwelling adds X creatures to the "available pool"
  - Growth amount varies by unit tier (tier 1: ~12/week, tier 7: ~1/week)
- [ ] **Recruitment UI:**
  - Shows all available creatures per tier
  - Slider or +/- buttons to select how many to buy
  - Shows cost (gold + resource if applicable)
  - "Recruit All" button
  - Recruited units added to hero's army or town garrison

## 5.6 Mage Guild & Spell Learning
- [ ] When Mage Guild is built in town: a random set of spells is assigned to it
  - Level 1 guild: 3 level-1 spells + 1 level-2 spell
  - Level 2: adds more; higher guilds unlock rarer spells
  - Spells are random per run (roguelike variation)
- [ ] Hero visits Mage Guild: learns all spells they can access (limited by Wisdom skill level)
  - No Wisdom: can only learn level 1–2 spells
  - Basic Wisdom: up to level 3
  - Advanced: up to level 4
  - Expert: all 5 levels
- [ ] Learned spells added to hero's spellbook permanently (for this run)

## 5.7 Tavern (Hero Hiring)
- [ ] Town's Tavern offers 2 heroes for hire (random from faction's hero pool)
- [ ] Cost: 2500 gold
- [ ] Hired hero starts with basic stats (level 1), no army
- [ ] Player can have multiple heroes on map simultaneously
- [ ] Secondary heroes: used for resource flagging, transporting units, backup combat

## 5.8 Town Garrison
- [ ] Each town has a 7-slot garrison (units left behind to defend)
- [ ] When enemy hero attacks town: garrison + town structures defend
- [ ] If no garrison: town falls without combat (just changes ownership)
- [ ] Units can be swapped between hero army and garrison when hero visits town

---

---

# MILESTONE 6 — Roguelike Loop
**Goal:** The game is now a complete roguelike. New run, explore, fight, win/die, repeat.  
**Playable result:** Start screen, full run from start to win/death, run summary, meta-progression.

## 6.1 Run Initialization
- [ ] **Main Menu:**
  - New Run → Faction/Class select → Difficulty select → Start
  - Continue (if mid-run save exists)
  - Meta-upgrades screen (unlocked between runs)
- [ ] **Faction Select screen:** shows 3 starting factions (unlock more via meta)
  - Each faction card: name, flavor text, starting units, hero class, unique mechanic preview
- [ ] On run start:
  - Generate procedural map (see 6.2)
  - Assign starting hero (faction-appropriate, level 1)
  - Give starting resources and 1-week-worth of starting army
  - Set win condition for this run

## 6.2 Procedural Map Generation
- [ ] `MapGenerator.gd`:
  - Input: seed (random or manual), map size (S/M/L), difficulty
  - **Zone-based generation:**
    1. Divide map into zones (start zone, mid zones, boss zone)
    2. Place player start town in start zone
    3. Scatter mines, chests, creature stacks with increasing difficulty by zone
    4. Place neutral towns (capturable)
    5. Place boss encounter in final zone
    6. Connect zones with paths; add obstacles to create chokepoints
  - Guarantee: player always has at least 2 capturable mines in start zone
  - Difficulty scales creature stack sizes and guard strength
- [ ] Each run: different seed → different map layout, mine positions, creature placements

## 6.3 Run Win/Loss Conditions
- [ ] **Win conditions (one per run, shown at start):**
  - Defeat the Boss Hero (specific powerful enemy hero in boss zone)
  - Capture all towns on map
  - Survive N weeks and accumulate X gold
  - Find and equip the Legendary Artifact (hidden in guarded location)
- [ ] **Loss conditions:**
  - Main hero is defeated with no towns to retreat to
  - Time limit reached (configurable per run)
- [ ] On win: `RunSummaryScreen` showing stats, unlocked rewards
- [ ] On loss: `RunOverScreen` with cause of death, stats, continue to meta screen

## 6.4 Roguelike Loot — Artifact System
- [ ] `ArtifactManager.gd`:
  - Pool of artifacts randomized per run (not all artifacts available every run)
  - Artifacts appear: in creature banks, as chest rewards, from boss drops, in Artifact Merchant shops
- [ ] **Artifact Merchant** (adventure map object):
  - Sells 3 random artifacts per visit (refreshes weekly)
  - Costs gold + sometimes rare resources
- [ ] **Equipping artifacts:** open Hero Screen → drag artifact to correct slot
  - Slot restriction enforced (head artifact → head slot only)
  - Some artifacts: "misc" slot (no restriction)
- [ ] **Combination artifacts:** if hero has all component artifacts → auto-combine into relic tier

## 6.5 Roguelike Events
- [ ] **Random weekly events** (shown at week start, one per week):
  - Combat modifiers: "All Fire spells deal +50% damage this week"
  - Economic: "All mines produce double this week"
  - Army: "Week of the [Creature] — this creature available at double growth in all dwellings"
  - Curse: "Week of Plague — all creature growths halved"
- [ ] **Encounter events** (triggered by stepping on special tiles):
  - "A wandering merchant offers you..." → choice of 3 items at discount
  - "A hermit teaches you..." → learn a random spell
  - "An ambush!" → surprise combat with disadvantaged starting positions
  - "Ancient vault discovered" → solve a puzzle or pay resources for a reward

## 6.6 Meta-Progression (Between Runs)
- [ ] `MetaProgression.gd` (persistent save, separate from run save):
  - Track: total runs, wins, best scores, unlocked content
  - **Meta currency:** "Renown" earned per run based on performance
- [ ] **Unlock tree (spend Renown):**
  - Unlock additional factions (start with 2, unlock 3 more)
  - Unlock additional starting heroes per faction
  - Permanent small bonuses: "+50 starting gold", "+1 starting unit tier 2"
  - Unlock harder difficulty tiers
  - Unlock new artifact types to appear in runs
  - Unlock new map events

## 6.7 Difficulty Scaling
- [ ] 4 difficulty levels: Squire / Knight / Hero / Legend
- [ ] Per difficulty:
  - Starting resources multiplier
  - Enemy AI aggressiveness
  - Neutral creature stack size multiplier
  - Number of enemy heroes on map
  - Time limit (Legend: strict time limit)

---

---

# MILESTONE 7 — Content Pass
**Goal:** Populate the game with full content: all factions, full spell roster, enough units.  
**Playable result:** 3 fully playable factions, 40+ spells, 30+ unit types.

## 7.1 Implement 3 Core Factions
Start with these 3 — they represent distinct playstyles and cover all key mechanics.

### Castle (Starter Faction — Human/Order)
- [ ] Units: Pikeman, Archer/Marksman, Griffin, Swordsman/Crusader, Monk/Zealot, Cavalier/Champion, Angel/Archangel
- [ ] Key abilities: Marksman double-shot; Archangel resurrect; Griffin unlimited retaliation
- [ ] Hero class: Knight (Might) / Cleric (Magic)
- [ ] Starting spell school: Earth + Water
- [ ] Unique building: Brotherhood of the Sword (+1 Morale to visiting heroes)
- [ ] Faction feel: balanced, high morale, consistent, good ranged + elite top-end

### Necropolis (Advanced Faction — Undead)
- [ ] Units: Skeleton/Skeleton Warrior, Zombie/Walking Dead, Wight/Wraith, Vampire/Vampire Lord, Lich/Power Lich, Black Knight/Dread Knight, Bone Dragon/Ghost Dragon
- [ ] Key abilities: Vampire Lord (life drain + no retaliation); Lich splash damage; Undead = immune to morale/mind spells; Necromancy skill
- [ ] Hero class: Death Knight (Might) / Necromancer (Magic)
- [ ] Starting spell school: Earth + Fire
- [ ] Unique building: Necromancy Amplifier (boosts Necromancy %)
- [ ] Faction feel: snowballs through Necromancy, weak start, dominant mid-late

### Stronghold (Aggression Faction — Orcs/Barbarians)
- [ ] Units: Goblin/Hobgoblin, Wolf Rider/Wolf Raider, Orc/Orc Chieftain, Ogre/Ogre Mage, Roc/Thunderbird, Cyclops/Cyclops King, Behemoth/Ancient Behemoth
- [ ] Key abilities: Cyclops wall destroyer; Behemoth reduces defense; Wolf Rider double attack; No penalty for mixed army (all are "barbarian")
- [ ] Hero class: Barbarian (Might)
- [ ] Unique mechanic: Barbarians can't use magic guilds above level 2 (offset by pure melee power)
- [ ] Faction feel: aggressive early game, cheap units, raw damage, weak on spells

## 7.2 Full Spell Roster (40 spells minimum)
Implement remaining spells by school:

**Fire Magic (8 spells):**
- [ ] Bloodlust (+Attack to one stack), Curse (-damage to enemy stack)
- [ ] Fireball (AoE ground target), Inferno (large AoE)
- [ ] Fire Wall (creates terrain hazard line), Misfortune (-Luck)
- [ ] Armageddon (damages all units — hero specialty pairing), Frenzy (berserk one stack)

**Air Magic (8 spells):**
- [ ] Haste (+Speed one stack), Disrupting Ray (-Defense permanently)
- [ ] Lightning Bolt (single target), Chain Lightning (bounces between enemies)
- [ ] Forgetfulness (ranged units forget to shoot), Air Shield (-ranged damage taken)
- [ ] Dimension Door (hero teleports on map — adventure map spell), Fly (hero moves as flying on map)

**Water Magic (8 spells):**
- [ ] Cure (heals + removes negative effects), Weakness (-Attack to enemy)
- [ ] Slow (reduces Speed), Ice Bolt (single target + freeze chance)
- [ ] Blizzard (AoE terrain hazard, multiple rounds), Dispel (remove buffs/debuffs)
- [ ] Prayer (+Attack/Defense/Speed to all friendlies), Clone (duplicate friendly stack for 1 combat)

**Earth Magic (8 spells):**
- [ ] Stone Skin (+Defense), Shield (-ranged damage)
- [ ] Magic Arrow (pure damage, unresistible), Implosion (extreme single target damage)
- [ ] Quicksand (terrain traps in random hexes), Land Mine (hidden terrain hazard)
- [ ] Resurrection (revive friendly dead stack), Animate Dead (revive undead stack)
- [ ] Town Portal (return to any friendly town — adventure map spell), Earthquake (damages walls in siege)

## 7.3 Artifact Pool (50 minimum)
- [ ] 20 Treasure tier: minor stat bonuses (+1 Attack, +2 Defense, +50 gold/day, etc.)
- [ ] 15 Minor tier: meaningful single bonuses (+2 Spell Power, +3 Speed to Cavalry, etc.)
- [ ] 10 Major tier: powerful effects (double mana regen, +25% ranged damage)
- [ ] 5 Relic tier: game-changing (e.g. "Spellbinder's Hat" — all spells cost 0 mana for 3 rounds/day)

## 7.4 Map Object Pass
Implement remaining adventure map objects:
- [ ] Stat booster sites (one-time permanent: +1 Attack, +1 Defense, +1 Spell Power, +1 Knowledge)
- [ ] Skill boosters (Witch Hut: random secondary skill; Scholar Hut: choose from 3 skills)
- [ ] Mana restore sites (Magic Spring, Mystical Garden)
- [ ] Creature Bank encounters (Dragon Utopia, Crypt, Cyclopean Stockpile) — guarded, high reward
- [ ] Obelisk (partially reveals treasure map for Grail mechanic — optional)
- [ ] Monolith portal pairs (instant travel across map)
- [ ] Stables (+movement to visiting hero for 7 days)

---

---

# MILESTONE 8 — UI, Audio & Visual Polish
**Goal:** The game looks and sounds like a finished product.  
**Playable result:** All screens complete, all SFX present, music plays, animations smooth.

## 8.1 UI Polish
- [ ] Consistent UI theme: dark fantasy style, custom fonts (serif for headers, clean for body)
- [ ] All tooltips: hover any stat/skill/spell/artifact → detailed popup explaining it
- [ ] Combat log panel: scrollable text log of all combat events ("Skeleton takes 14 damage, 3 die")
- [ ] Animated unit sprites (idle, attack, hit, death animations — 4 frames minimum)
- [ ] Spell animations: particles/effects for each spell type
- [ ] Transition animations between scenes (fade to black, etc.)
- [ ] Confirm dialogs for irreversible actions (retreat, disband units)

## 8.2 Combat Visual Polish
- [ ] Hit flash on damaged units
- [ ] Death animation + fade-out on unit elimination
- [ ] Projectile animation for ranged attacks
- [ ] Morale proc: golden flash + extra turn indicator
- [ ] Luck proc: visual effect on double-damage hit
- [ ] Spell cast animation on hero portrait
- [ ] Hex highlight states: movement blue, attack red, spell purple, selected yellow

## 8.3 Adventure Map Visual Polish
- [ ] Animated hero sprite walking between tiles
- [ ] Mine flagging animation (flag raises on capture)
- [ ] Day/Night visual cycle (subtle color temperature shift)
- [ ] Fog of war smooth reveal (fade animation, not instant pop)
- [ ] Water tiles animated (gentle wave shader)
- [ ] Wind effect on forest tiles (optional shader)

## 8.4 Audio
- [ ] **Music tracks needed:**
  - Main menu theme
  - Adventure map (1 per faction town type, 3 initially)
  - Combat music (tense/urgent)
  - Victory fanfare (short)
  - Defeat theme (short)
  - Town screen music (calm, faction-flavored)
- [ ] **SFX:**
  - Sword hits (melee)
  - Arrow/projectile sound
  - Spell cast sounds (fire crackle, lightning, ice, earth rumble)
  - Footstep for adventure map movement
  - Building construction sound
  - Gold pickup
  - Level-up fanfare
  - Unit death sounds
  - Button clicks / UI interactions

## 8.5 Screen & Flow Completeness
- [ ] Main Menu (New Run / Continue / Meta-Upgrades / Quit)
- [ ] Faction Select screen
- [ ] Difficulty Select screen
- [ ] Adventure Map (complete HUD, mini-map, end turn)
- [ ] Town Screen (all tabs: Build, Recruit, Mage Guild, Tavern, Garrison)
- [ ] Hero Screen (stats, skills, spellbook, equipment, army)
- [ ] Combat Screen (battlefield, turn order bar, spell UI, combat log)
- [ ] Level-Up Screen
- [ ] Artifact Found Screen
- [ ] Event/Choice Screen
- [ ] Run Victory Screen
- [ ] Run Over / Defeat Screen
- [ ] Meta-Progression Screen
- [ ] Pause Menu (Settings, Save & Quit, Abandon Run)

---

---

# MILESTONE 9 — Balancing, Bug Fix & Release Candidate
**Goal:** The game is fair, fun, and bug-free enough to ship an Early Access / Demo version.

## 9.1 Balance Pass
- [ ] Unit stat audit: compare each unit's cost vs combat value by tier
- [ ] Spell balance: ensure no spell is auto-skip or auto-pick in every situation
- [ ] Secondary skill balance: every skill should have at least one build where it's optimal
- [ ] Economy balance: gold income vs creature cost should allow 1 meaningful army upgrade/week
- [ ] Difficulty curve: playtest each difficulty, adjust multipliers
- [ ] Roguelike run length: target 90–150 min per full run on Normal

## 9.2 QA Checklist
- [ ] All combat edge cases: large units near walls, flying into walls, ranged in melee, 0-speed units
- [ ] Level-up at max secondary skills (8 expert skills) — only primary stat offered
- [ ] Resource edge cases: negative gold prevention, spending more than available blocked
- [ ] Town captured mid-week: creature pool behavior
- [ ] Save/load integrity test: save mid-combat, mid-adventure, after level-up
- [ ] Meta-save persists across runs correctly

## 9.3 Performance
- [ ] Adventure map: test with 200+ map objects, ensure no frame drops
- [ ] Combat: test with 14 large stacks simultaneously
- [ ] TileMap: confirm draw call efficiency (use atlases, not individual sprites)
- [ ] Target: stable 60 FPS on mid-range hardware

## 9.4 Accessibility
- [ ] Colorblind mode: replace pure color coding with shapes/icons as secondary indicator
- [ ] Text size option (small/medium/large)
- [ ] All tooltips readable without prior knowledge of the game
- [ ] Key rebinding for all combat actions

---

---

# TECHNICAL ARCHITECTURE REFERENCE

## Scene Tree Structure

```
Main (Node)
├── Autoloads/
│   ├── GameState
│   ├── EventBus
│   ├── DataManager
│   ├── SceneManager
│   ├── TimeManager
│   ├── ResourceManager
│   ├── AudioManager
│   └── SaveManager
├── AdventureMapScene (Node2D)
│   ├── TileMap (terrain)
│   ├── ObjectLayer (mines, chests, etc.)
│   ├── HeroLayer (hero sprites)
│   ├── FogOfWar (CanvasLayer)
│   └── HUD (CanvasLayer)
├── CombatScene (Node2D)
│   ├── HexGrid (TileMap)
│   ├── UnitLayer (Node2D — all UnitStack nodes)
│   ├── EffectsLayer (particles, animations)
│   ├── HeroPanel_Left (Control)
│   ├── HeroPanel_Right (Control)
│   ├── TurnOrderBar (Control)
│   ├── CombatLog (Control)
│   └── SpellUI (Control)
└── UI Scenes (loaded by SceneManager as needed)
    ├── TownScene
    ├── HeroScreen
    ├── LevelUpScreen
    ├── MetaScreen
    └── ...
```

## Key Signal Contracts (EventBus)

```gdscript
# Time
signal day_changed(new_day: int)
signal week_changed(new_week: int, week_name: String)

# Combat
signal combat_started(attacker_data, defender_data)
signal combat_ended(result: String, surviving_units: Array)
signal unit_damaged(unit: UnitStack, damage: int, killed_count: int)
signal unit_died(unit: UnitStack)
signal spell_cast(hero, spell: SpellData, targets: Array)

# Hero
signal hero_leveled_up(hero, new_level: int)
signal hero_skill_learned(hero, skill_name: String, new_level: int)
signal artifact_equipped(hero, artifact: ArtifactData, slot: String)

# Economy
signal resource_changed(type: String, new_amount: int, delta: int)
signal mine_captured(mine, new_owner: String)

# Map
signal hero_moved(hero, new_tile: Vector2i)
signal town_captured(town, new_owner: String)
signal map_object_interacted(object, hero)
```

## Save Structure
```json
{
  "run": {
    "seed": 123456,
    "day": 14,
    "hero": { "...hero data..." },
    "resources": { "gold": 5000, "...": 0 },
    "map_state": { "mines_owned": [], "objects_collected": [], "explored_tiles": [] },
    "towns": [{ "...town state..." }]
  },
  "meta": {
    "renown": 450,
    "unlocked_factions": ["castle", "necropolis"],
    "permanent_upgrades": { "starting_gold_bonus": 100 },
    "total_runs": 12,
    "total_wins": 3
  }
}
```

---

*Design Document v1.0 — HoMM3 Roguelike Clone — Godot 4.x*  
*Created for project planning. Update this document as design decisions evolve.*
