## UnitData.gd
## Static, immutable data for one unit type (e.g. "Skeleton Warrior", "Archangel").
## One .tres file per unit — set all fields in the Inspector.
## NEVER mutate at runtime. Per-stack runtime state lives in UnitStack.gd (Milestone 1).
extends Resource

# ── IDENTITY ──────────────────────────────────────────────────────────────────
@export var id:        String = ""
@export var unit_name: String = ""
@export var faction:   String = ""
@export var tier:      int    = 1

@export var is_upgrade:      bool   = false
@export var base_unit_id:    String = ""
@export var upgrade_unit_id: String = ""

# ── COMBAT STATS ──────────────────────────────────────────────────────────────
@export var attack:     int = 1
@export var defense:    int = 1
@export var min_damage: int = 1
@export var max_damage: int = 1
@export var hp:         int = 1
@export var speed:      int = 1
@export var movement:   int = 1

# ── RANGED ────────────────────────────────────────────────────────────────────
@export var is_ranged: bool = false
@export var ammo:      int  = 0

# ── MOVEMENT TYPE ─────────────────────────────────────────────────────────────
@export var is_flying: bool = false
@export var is_large:  bool = false

# ── ECONOMY ───────────────────────────────────────────────────────────────────
@export var cost_gold:    int = 0
@export var cost_wood:    int = 0
@export var cost_ore:     int = 0
@export var cost_mercury: int = 0
@export var cost_sulfur:  int = 0
@export var cost_crystal: int = 0
@export var cost_gems:    int = 0
@export var weekly_growth: int = 1

# ── ABILITIES ─────────────────────────────────────────────────────────────────
## Recognised tags: "no_retaliation" "double_attack" "life_drain"
## "immune_fire" "immune_air" "immune_water" "immune_earth" "immune_all_spells"
## "petrify" "death_stare" "unlimited_retaliation" "morale_immune"
@export var abilities: Array[String] = []

# ── VISUALS ───────────────────────────────────────────────────────────────────
@export var sprite_idle:   Texture2D = null
@export var sprite_attack: Texture2D = null
@export var sprite_hit:    Texture2D = null
@export var sprite_dead:   Texture2D = null
@export var portrait:      Texture2D = null

func has_ability(tag: String) -> bool:
	return tag in abilities

func get_cost_dict() -> Dictionary:
	return {
		"gold": cost_gold, "wood": cost_wood, "ore": cost_ore,
		"mercury": cost_mercury, "sulfur": cost_sulfur,
		"crystal": cost_crystal, "gems": cost_gems,
	}

func average_damage() -> float:
	return (min_damage + max_damage) / 2.0
