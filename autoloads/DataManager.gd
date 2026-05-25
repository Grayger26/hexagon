## DataManager.gd
## Loads every .tres data resource at startup and caches them.
## All other systems call DataManager.get_unit("id") etc. — never load() directly.
##
## Resource files live in:
##   res://resources/units/      ← UnitData .tres
##   res://resources/heroes/     ← HeroData .tres
##   res://resources/spells/     ← SpellData .tres
##   res://resources/artifacts/  ← ArtifactData .tres
##   res://resources/factions/   ← FactionData .tres
extends Node


var units:     Dictionary = {}
var heroes:    Dictionary = {}
var spells:    Dictionary = {}
var artifacts: Dictionary = {}
var factions:  Dictionary = {}


func _ready() -> void:
	_load_folder("res://resources/units/",      units)
	_load_folder("res://resources/heroes/",     heroes)
	_load_folder("res://resources/spells/",     spells)
	_load_folder("res://resources/artifacts/",  artifacts)
	_load_folder("res://resources/factions/",   factions)
	print("[DataManager] Loaded — units:%d  heroes:%d  spells:%d  artifacts:%d  factions:%d"
		% [units.size(), heroes.size(), spells.size(), artifacts.size(), factions.size()])


# ── LOAD ──────────────────────────────────────────────────────────────────────

func _load_folder(path: String, cache: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[DataManager] Folder not found or empty: %s" % path)
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
				push_warning("[DataManager] Resource missing 'id' field: %s" % full_path)
			else:
				cache[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()


# ── GETTERS ───────────────────────────────────────────────────────────────────

func get_unit(id: String) -> Resource:
	return _get_from_cache(units, id, "UnitData")

func get_hero(id: String) -> Resource:
	return _get_from_cache(heroes, id, "HeroData")

func get_spell(id: String) -> Resource:
	return _get_from_cache(spells, id, "SpellData")

func get_artifact(id: String) -> Resource:
	return _get_from_cache(artifacts, id, "ArtifactData")

func get_faction(id: String) -> Resource:
	return _get_from_cache(factions, id, "FactionData")

func _get_from_cache(cache: Dictionary, id: String, type_name: String) -> Resource:
	if cache.has(id):
		return cache[id]
	push_error("[DataManager] %s not found: '%s'" % [type_name, id])
	return null


# ── QUERY HELPERS ─────────────────────────────────────────────────────────────

func get_units_for_faction(faction_id: String) -> Array:
	var result: Array = []
	for unit in units.values():
		if unit.faction == faction_id:
			result.append(unit)
	result.sort_custom(func(a, b): return a.tier < b.tier)
	return result


func get_spells_by_school(school: String) -> Array:
	return units.values().filter(func(s): return s.school == school)


func get_spells_up_to_level(max_level: int) -> Array:
	var result: Array = []
	for spell in spells.values():
		if spell.level <= max_level:
			result.append(spell)
	return result


func get_artifacts_by_tier(tier: String) -> Array:
	var result: Array = []
	for artifact in artifacts.values():
		if artifact.tier == tier:
			result.append(artifact)
	return result


func get_random_artifact_pool(count: int, rng: RandomNumberGenerator = null) -> Array:
	var all: Array = artifacts.values().duplicate()
	if rng != null:
		# Fisher-Yates with seeded rng for deterministic runs
		for i in range(all.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = all[i]; all[i] = all[j]; all[j] = tmp
	else:
		all.shuffle()
	return all.slice(0, min(count, all.size()))
