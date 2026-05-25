## HeroData.gd
## Static archetype data for one hero. One .tres per hero.
## Per-run mutable state lives in HeroState.gd.
extends Resource

# ── IDENTITY ──────────────────────────────────────────────────────────────────
@export var id:         String = ""
@export var hero_name:  String = ""
@export var faction:    String = ""
@export var hero_type:  String = "might"   ## "might" | "magic"
@export var hero_class: String = ""        ## display e.g. "Knight"

# ── STARTING PRIMARY STATS ────────────────────────────────────────────────────
@export var start_attack:      int = 1
@export var start_defense:     int = 1
@export var start_spell_power: int = 1
@export var start_knowledge:   int = 1

# ── LEVEL-UP STAT WEIGHTS (must sum to ~1.0) ──────────────────────────────────
@export var weight_attack:      float = 0.25
@export var weight_defense:     float = 0.25
@export var weight_spell_power: float = 0.25
@export var weight_knowledge:   float = 0.25

# ── STARTING SECONDARY SKILLS ─────────────────────────────────────────────────
## Dict: skill_id -> starting level (1=Basic 2=Advanced 3=Expert)
@export var starting_skills: Dictionary = {}

# ── STARTING SPELLS ───────────────────────────────────────────────────────────
@export var starting_spells: Array[String] = []

# ── SPECIALTY ─────────────────────────────────────────────────────────────────
## specialty_type: "unit_specialist"|"spell_specialist"|"skill_specialist"|
##                 "resource_bonus"|"none"
@export var specialty_type:        String = "none"
@export var specialty_value:       String = ""
@export var specialty_amount:      int    = 0
@export var specialty_description: String = ""

# ── SKILL BIAS ────────────────────────────────────────────────────────────────
## skill_id -> weight multiplier (default 1.0). Higher = more likely on level-up.
@export var skill_bias: Dictionary = {}

# ── VISUALS ───────────────────────────────────────────────────────────────────
@export var portrait_small: Texture2D = null
@export var portrait_large: Texture2D = null
@export var map_sprite:     Texture2D = null

## Returns a primary stat name chosen by weighted random, used on level-up.
func roll_primary_stat_gain(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var cum  := 0.0
	var weights := {
		"attack":      weight_attack,
		"defense":     weight_defense,
		"spell_power": weight_spell_power,
		"knowledge":   weight_knowledge,
	}
	for stat in weights:
		cum += weights[stat]
		if roll <= cum:
			return stat
	return "attack"
