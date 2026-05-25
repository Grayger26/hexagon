## GameState.gd
## Single source of truth for the active run.
## Holds data only — logic lives in dedicated manager scripts.
extends Node


enum RunPhase { NONE, ADVENTURE, COMBAT, TOWN, LEVEL_UP, GAME_OVER }

var run_active: bool     = false
var run_phase:  RunPhase = RunPhase.NONE
var run_seed:   int      = 0
var difficulty: String   = "knight"
var faction:    String   = ""

var day:   int = 1
var week:  int = 1
var month: int = 1

var resources: Dictionary = {
	"gold": 0, "wood": 0, "ore": 0, "mercury": 0,
	"sulfur": 0, "crystal": 0, "gems": 0,
}

var player_hero: Resource = null

var map_size:          Vector2i        = Vector2i(64, 64)
var explored_tiles:    Array[Vector2i] = []
var mines_owned:       Dictionary      = {}
var objects_collected: Array[String]   = []
var towns:             Dictionary      = {}
var neutral_stacks:    Dictionary      = {}

var secondary_heroes: Array[Resource] = []

var win_condition:  Dictionary = {}
var loss_condition: Dictionary = {}

var stats: Dictionary = {
	"days_survived": 0, "battles_won": 0, "battles_lost": 0,
	"gold_earned": 0, "creatures_killed": 0,
	"spells_cast": 0, "artifacts_found": 0,
}


func init_run(p_faction: String, p_difficulty: String, p_seed: int) -> void:
	run_active = true
	run_phase  = RunPhase.ADVENTURE
	faction    = p_faction
	difficulty = p_difficulty
	run_seed   = p_seed
	day = 1; week = 1; month = 1
	resources = {
		"gold": 0, "wood": 0, "ore": 0, "mercury": 0,
		"sulfur": 0, "crystal": 0, "gems": 0,
	}
	explored_tiles    = []
	mines_owned       = {}
	objects_collected = []
	towns             = {}
	neutral_stacks    = {}
	secondary_heroes  = []
	stats = {
		"days_survived": 0, "battles_won": 0, "battles_lost": 0,
		"gold_earned": 0, "creatures_killed": 0,
		"spells_cast": 0, "artifacts_found": 0,
	}
	player_hero = null


func load_from_dict(data: Dictionary) -> void:
	run_active = true
	run_phase  = RunPhase.ADVENTURE
	# Explicit casts on every Dictionary.get() to avoid Variant inference warnings.
	faction    = data.get("faction",    "castle")   as String
	difficulty = data.get("difficulty", "knight")   as String
	run_seed   = data.get("seed",       0)          as int
	day        = data.get("day",        1)          as int
	week       = data.get("week",       1)          as int
	month      = data.get("month",      1)          as int
	resources  = data.get("resources",  resources.duplicate()) as Dictionary
	stats      = data.get("stats",      stats.duplicate())     as Dictionary


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
	}


func increment_stat(key: String, amount: int = 1) -> void:
	if stats.has(key):
		stats[key] = (stats[key] as int) + amount
