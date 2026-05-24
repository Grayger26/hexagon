## DataManager.gd
## Loads every .tres data resource at startup and stores them in typed dictionaries.
## Systems never load resources themselves — they call DataManager.get_unit("skeleton")
## etc.  This gives us one central place to add/rename content.
##
## Folder conventions:
##   res://resources/units/      ← UnitData .tres files
##   res://resources/heroes/     ← HeroData .tres files
##   res://resources/spells/     ← SpellData .tres files
##   res://resources/artifacts/  ← ArtifactData .tres files
##   res://resources/factions/   ← FactionData .tres files
extends Node


# ─────────────────────────────────────────────
#  CACHES  (key = resource "id" field, lowercase snake_case)
# ─────────────────────────────────────────────
var units:     Dictionary = {}   # id -> UnitData
var heroes:    Dictionary = {}   # id -> HeroData
var spells:    Dictionary = {}   # id -> SpellData
var artifacts: Dictionary = {}   # id -> ArtifactData
var factions:  Dictionary = {}   # id -> FactionData

var _loaded: bool = false


func _ready() -> void:
	_load_all()


# ─────────────────────────────────────────────
#  LOAD
# ─────────────────────────────────────────────

func _load_all() -> void:
	_load_folder("res://resources/units/",     units)
	_load_folder("res://resources/heroes/",    heroes)
	_load_folder("res://resources/spells/",    spells)
	_load_folder("res://resources/artifacts/", artifacts)
	_load_folder("res://resources/factions/",  factions)
	_loaded = true
	print("[DataManager] Loaded — units:%d  heroes:%d  spells:%d  artifacts:%d  factions:%d"
		% [units.size(), heroes.size(), spells.size(), artifacts.size(), factions.size()])


func _load_folder(path: String, cache: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[DataManager] Folder not found: %s" % path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path := path + file_name
			var res := load(full_path)
			if res == null:
				push_error("[DataManager] Failed to load: %s" % full_path)
			elif not "id" in res:
				push_warning("[DataManager] Resource has no 'id' field: %s" % full_path)
			else:
				cache[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()


# ─────────────────────────────────────────────
#  GETTERS  (all return null on miss + push error)
# ─────────────────────────────────────────────

func get_unit(id: String) -> Resource:
	return _get(units, id, "UnitData")

func get_hero(id: String) -> Resource:
	return _get(heroes, id, "HeroData")

func get_spell(id: String) -> Resource:
	return _get(spells, id, "SpellData")

func get_artifact(id: String) -> Resource:
	return _get(artifacts, id, "ArtifactData")

func get_faction(id: String) -> Resource:
	return _get(factions, id, "FactionData")


func _get(cache: Dictionary, id: String, type_name: String) -> Resource:
	if cache.has(id):
		return cache[id]
	push_error("[DataManager] %s not found: '%s'" % [type_name, id])
	return null


# ─────────────────────────────────────────────
#  QUERY HELPERS
# ─────────────────────────────────────────────

## Returns all units belonging to a faction, sorted by tier.
func get_units_for_faction(faction_id: String) -> Array:
	var result: Array = []
	for unit in units.values():
		if unit.faction == faction_id:
			result.append(unit)
	result.sort_custom(func(a, b): return a.tier < b.tier)
	return result


## Returns all spells of a given school.
func get_spells_by_school(school: String) -> Array:
	var result: Array = []
	for spell in spells.values():
		if spell.school == school:
			result.append(spell)
	return result


## Returns all spells up to a given level.
func get_spells_up_to_level(max_level: int) -> Array:
	var result: Array = []
	for spell in spells.values():
		if spell.level <= max_level:
			result.append(spell)
	return result


## Returns all artifacts of a given tier.
func get_artifacts_by_tier(tier: String) -> Array:
	var result: Array = []
	for artifact in artifacts.values():
		if artifact.tier == tier:
			result.append(artifact)
	return result


## Returns a random subset of artifacts (for roguelike pool generation).
func get_random_artifact_pool(count: int, rng: RandomNumberGenerator) -> Array:
	var all: Array = artifacts.values().duplicate()
	all.shuffle()   # uses global RNG; fine for non-seeded calls
	# Use rng if provided for deterministic seeded runs
	if rng != null:
		for i in range(all.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = all[i]
			all[i] = all[j]
			all[j] = tmp
	return all.slice(0, min(count, all.size()))
