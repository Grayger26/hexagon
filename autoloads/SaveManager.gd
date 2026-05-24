## SaveManager.gd
## Handles all persistence:
##   - Run save  (single slot, overwritten on each End Turn — roguelike style)
##   - Meta save (permanent, accumulates between runs)
##
## Format: JSON, stored in user://  so it works cross-platform.
## Encryption is not needed for a single-player game, but the pattern is
## set up so you can add it later by swapping FileAccess for a crypto wrapper.
extends Node


const RUN_SAVE_PATH:  String = "user://run_save.json"
const META_SAVE_PATH: String = "user://meta_save.json"

# Emitted so the UI can show a "Saving..." indicator.
signal save_started()
signal save_completed(success: bool)
signal load_completed(success: bool)


# ─────────────────────────────────────────────
#  RUN SAVE
# ─────────────────────────────────────────────

func save_run() -> bool:
	save_started.emit()

	var data: Dictionary = {
		"version":   1,
		"timestamp": Time.get_unix_time_from_system(),
		"game_state": GameState.to_dict(),
		# Hero and map state are handled by their own serialisers
		"hero":  _serialise_hero(),
		"map":   _serialise_map(),
		"towns": _serialise_towns(),
	}

	var success := _write_json(RUN_SAVE_PATH, data)
	save_completed.emit(success)
	return success


func load_run() -> bool:
	var data := _read_json(RUN_SAVE_PATH)
	if data.is_empty():
		load_completed.emit(false)
		return false

	GameState.load_from_dict(data.get("game_state", {}))
	_deserialise_hero(data.get("hero", {}))
	_deserialise_map(data.get("map", {}))
	_deserialise_towns(data.get("towns", {}))

	load_completed.emit(true)
	return true


func has_run_save() -> bool:
	return FileAccess.file_exists(RUN_SAVE_PATH)


func delete_run_save() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)


# ─────────────────────────────────────────────
#  META SAVE
# ─────────────────────────────────────────────

## Default meta structure — used when no file exists yet.
const META_DEFAULTS: Dictionary = {
	"version":              1,
	"renown":               0,
	"total_runs":           0,
	"total_wins":           0,
	"unlocked_factions":    ["castle"],
	"permanent_upgrades":   {},
	"best_run_days":        9999,
	"achievements":         [],
}

var _meta_cache: Dictionary = {}


func _ready() -> void:
	_meta_cache = load_meta()


func load_meta() -> Dictionary:
	var data := _read_json(META_SAVE_PATH)
	if data.is_empty():
		return META_DEFAULTS.duplicate(true)
	# Merge with defaults so new keys added in future versions don't break old saves
	var merged := META_DEFAULTS.duplicate(true)
	merged.merge(data, true)
	return merged


func save_meta() -> bool:
	return _write_json(META_SAVE_PATH, _meta_cache)


## Helper used by MetaProgressionManager — returns cached meta.
func get_meta() -> Dictionary:
	return _meta_cache


func set_meta_value(key: String, value) -> void:
	_meta_cache[key] = value
	save_meta()


func add_meta_renown(amount: int) -> void:
	_meta_cache["renown"] = _meta_cache.get("renown", 0) + amount
	EventBus.meta_renown_gained.emit(amount, _meta_cache["renown"])
	save_meta()


func unlock_faction(faction_id: String) -> void:
	var unlocked: Array = _meta_cache.get("unlocked_factions", [])
	if faction_id not in unlocked:
		unlocked.append(faction_id)
		_meta_cache["unlocked_factions"] = unlocked
		save_meta()


# ─────────────────────────────────────────────
#  SERIALISE / DESERIALISE HELPERS
## Placeholder implementations — filled in as systems are built.
# ─────────────────────────────────────────────

func _serialise_hero() -> Dictionary:
	if GameState.player_hero == null:
		return {}
	return GameState.player_hero.to_dict() if GameState.player_hero.has_method("to_dict") else {}


func _deserialise_hero(data: Dictionary) -> void:
	if data.is_empty():
		return
	# HeroFactory.restore_from_dict(data) will be called here in Milestone 4
	pass


func _serialise_map() -> Dictionary:
	return {
		"explored_tiles":    GameState.explored_tiles.map(func(v): return [v.x, v.y]),
		"mines_owned":       GameState.mines_owned.duplicate(),
		"objects_collected": GameState.objects_collected.duplicate(),
	}


func _deserialise_map(data: Dictionary) -> void:
	if data.is_empty():
		return
	GameState.explored_tiles = []
	for arr in data.get("explored_tiles", []):
		GameState.explored_tiles.append(Vector2i(arr[0], arr[1]))
	GameState.mines_owned       = data.get("mines_owned",       {})
	GameState.objects_collected = data.get("objects_collected", [])


func _serialise_towns() -> Dictionary:
	var result: Dictionary = {}
	for id in GameState.towns:
		var town = GameState.towns[id]
		result[id] = town.to_dict() if town.has_method("to_dict") else {}
	return result


func _deserialise_towns(data: Dictionary) -> void:
	GameState.towns = {}
	# TownFactory.restore_all(data) will be called here in Milestone 5
	pass


# ─────────────────────────────────────────────
#  FILE I/O
# ─────────────────────────────────────────────

func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Cannot write to %s: %s" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Cannot read %s: %s" % [path, FileAccess.get_open_error()])
		return {}
	var text   := file.get_as_text()
	file.close()
	var parsed := JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[SaveManager] Invalid JSON in %s" % path)
		return {}
	return parsed
