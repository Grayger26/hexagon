## GameState.gd
## Single source of truth for the active run.
## Holds no logic — just owns the data. Systems read from here and write through
## their own managers (ResourceManager, TimeManager, etc.) which then update
## the relevant fields here and emit EventBus signals.
extends Node


# ─────────────────────────────────────────────
#  RUN STATE
# ─────────────────────────────────────────────
enum RunPhase { NONE, ADVENTURE, COMBAT, TOWN, LEVEL_UP, GAME_OVER }

var run_active:    bool       = false
var run_phase:     RunPhase   = RunPhase.NONE
var run_seed:      int        = 0
var difficulty:    String     = "knight"   # squire / knight / hero / legend
var faction:       String     = ""

# ─────────────────────────────────────────────
#  TIME
# ─────────────────────────────────────────────
var day:   int = 1   # 1–7
var week:  int = 1   # 1–4
var month: int = 1

# ─────────────────────────────────────────────
#  RESOURCES
# ─────────────────────────────────────────────
var resources: Dictionary = {
	"gold":    0,
	"wood":    0,
	"ore":     0,
	"mercury": 0,
	"sulfur":  0,
	"crystal": 0,
	"gems":    0,
}

# ─────────────────────────────────────────────
#  HERO  (active player hero)
# ─────────────────────────────────────────────
## Holds a HeroState instance (see scripts/data/HeroState.gd).
## Null when no run is active.
var player_hero: Resource = null

# ─────────────────────────────────────────────
#  MAP STATE  (populated by MapGenerator)
# ─────────────────────────────────────────────
var map_seed:          int            = 0
var map_size:          Vector2i       = Vector2i(64, 64)
var explored_tiles:    Array[Vector2i] = []
var mines_owned:       Dictionary     = {}   # mine_id -> owner string
var objects_collected: Array[String]  = []   # object_ids already picked up
var towns:             Dictionary     = {}   # town_id -> TownState
var neutral_stacks:    Dictionary     = {}   # stack_id -> NeutralStackData

# ─────────────────────────────────────────────
#  SECONDARY HEROES  (hired helpers)
# ─────────────────────────────────────────────
var secondary_heroes: Array[Resource] = []

# ─────────────────────────────────────────────
#  WIN / LOSS CONDITIONS  (set on run start)
# ─────────────────────────────────────────────
var win_condition:  Dictionary = {}   # { "type": "defeat_boss", "target_id": "boss_01" }
var loss_condition: Dictionary = {}   # { "type": "hero_death" }

# ─────────────────────────────────────────────
#  RUN STATISTICS  (for end screen)
# ─────────────────────────────────────────────
var stats: Dictionary = {
	"days_survived":    0,
	"battles_won":      0,
	"battles_lost":     0,
	"gold_earned":      0,
	"creatures_killed": 0,
	"spells_cast":      0,
	"artifacts_found":  0,
}


# ─────────────────────────────────────────────
#  PUBLIC HELPERS
# ─────────────────────────────────────────────

## Called by SceneManager when a fresh run begins.
func init_run(p_faction: String, p_difficulty: String, p_seed: int) -> void:
	run_active  = true
	run_phase   = RunPhase.ADVENTURE
	faction     = p_faction
	difficulty  = p_difficulty
	run_seed    = p_seed
	map_seed    = p_seed

	day   = 1
	week  = 1
	month = 1

	resources      = { "gold": 0, "wood": 0, "ore": 0, "mercury": 0,
	                   "sulfur": 0, "crystal": 0, "gems": 0 }
	explored_tiles    = []
	mines_owned       = {}
	objects_collected = []
	towns             = {}
	neutral_stacks    = {}
	secondary_heroes  = []
	stats = { "days_survived": 0, "battles_won": 0, "battles_lost": 0,
	          "gold_earned": 0, "creatures_killed": 0,
	          "spells_cast": 0, "artifacts_found": 0 }

	player_hero = null   # set by HeroFactory after init


## Called by SaveManager on load.
func load_from_dict(data: Dictionary) -> void:
	run_active  = true
	run_phase   = RunPhase.ADVENTURE
	faction     = data.get("faction",    "castle")
	difficulty  = data.get("difficulty", "knight")
	run_seed    = data.get("seed",       0)
	day         = data.get("day",        1)
	week        = data.get("week",       1)
	month       = data.get("month",      1)
	resources   = data.get("resources",  resources.duplicate())
	stats       = data.get("stats",      stats.duplicate())
	# Hero + map state are restored by their own managers after this call.


## Returns a snapshot dict for SaveManager.
func to_dict() -> Dictionary:
	return {
		"faction":    faction,
		"difficulty": difficulty,
		"seed":       run_seed,
		"day":        day,
		"week":       week,
		"month":      month,
		"resources":  resources.duplicate(),
		"stats":      stats.duplicate(),
		# hero / map / towns serialised separately
	}


func increment_stat(key: String, amount: int = 1) -> void:
	if stats.has(key):
		stats[key] += amount
