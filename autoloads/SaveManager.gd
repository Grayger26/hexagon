## SaveManager.gd
## Run saves (single slot, overwritten each End Turn) and
## meta saves (permanent, survives between runs).
extends Node


const RUN_SAVE_PATH:  String = "user://run_save.json"
const META_SAVE_PATH: String = "user://meta_save.json"

signal save_started()
signal save_completed(success: bool)
signal load_completed(success: bool)

const META_DEFAULTS: Dictionary = {
	"version":            1,
	"renown":             0,
	"total_runs":         0,
	"total_wins":         0,
	"unlocked_factions":  ["castle"],
	"permanent_upgrades": {},
	"best_run_days":      9999,
	"achievements":       [],
	"audio_music_vol":    1.0,
	"audio_sfx_vol":      1.0,
	"audio_music_on":     true,
	"audio_sfx_on":       true,
}

var _meta_cache: Dictionary = {}


func _ready() -> void:
	_meta_cache = load_meta()


# ── RUN SAVE ──────────────────────────────────────────────────────────────────

func save_run() -> bool:
	save_started.emit()
	var data: Dictionary = {
		"version":    1,
		"timestamp":  Time.get_unix_time_from_system(),
		"game_state": GameState.to_dict(),
		"hero":        _serialise_hero(),
		"map":         _serialise_map(),
		"towns":       _serialise_towns(),
	}
	var ok: bool = _write_json(RUN_SAVE_PATH, data)
	save_completed.emit(ok)
	return ok


func load_run() -> bool:
	var data: Dictionary = _read_json(RUN_SAVE_PATH)
	if data.is_empty():
		load_completed.emit(false)
		return false
	GameState.load_from_dict(data.get("game_state", {}) as Dictionary)
	_deserialise_hero( data.get("hero",  {}) as Dictionary)
	_deserialise_map(  data.get("map",   {}) as Dictionary)
	_deserialise_towns(data.get("towns", {}) as Dictionary)
	load_completed.emit(true)
	return true


func has_run_save() -> bool:
	return FileAccess.file_exists(RUN_SAVE_PATH)


func delete_run_save() -> void:
	if has_run_save():
		DirAccess.remove_absolute(RUN_SAVE_PATH)


# ── META SAVE ─────────────────────────────────────────────────────────────────

func load_meta() -> Dictionary:
	var data: Dictionary = _read_json(META_SAVE_PATH)
	if data.is_empty():
		return META_DEFAULTS.duplicate(true)
	var merged: Dictionary = META_DEFAULTS.duplicate(true)
	merged.merge(data, true)
	return merged


func save_meta() -> bool:
	return _write_json(META_SAVE_PATH, _meta_cache)


## NOTE: not named get_meta() — that conflicts with Godot's built-in Object.get_meta().
func get_meta_data() -> Dictionary:
	return _meta_cache


func set_meta_value(key: String, value: Variant) -> void:
	_meta_cache[key] = value
	save_meta()


func add_meta_renown(amount: int) -> void:
	var current: int = _meta_cache.get("renown", 0) as int
	_meta_cache["renown"] = current + amount
	EventBus.meta_renown_gained.emit(amount, _meta_cache["renown"] as int)
	save_meta()


func unlock_faction(faction_id: String) -> void:
	var unlocked: Array = _meta_cache.get("unlocked_factions", []) as Array
	if faction_id not in unlocked:
		unlocked.append(faction_id)
		_meta_cache["unlocked_factions"] = unlocked
		save_meta()


# ── SERIALISE STUBS ───────────────────────────────────────────────────────────

func _serialise_hero() -> Dictionary:
	if GameState.player_hero == null:
		return {}
	return GameState.player_hero.to_dict() if GameState.player_hero.has_method("to_dict") else {}

func _deserialise_hero(_data: Dictionary) -> void:
	pass   # HeroFactory.restore_from_dict(data) — Milestone 4

func _serialise_map() -> Dictionary:
	return {
		"explored_tiles":    GameState.explored_tiles.map(func(v: Vector2i) -> Array: return [v.x, v.y]),
		"mines_owned":       GameState.mines_owned.duplicate(),
		"objects_collected": GameState.objects_collected.duplicate(),
	}

func _deserialise_map(data: Dictionary) -> void:
	if data.is_empty():
		return
	GameState.explored_tiles = []
	for arr: Variant in data.get("explored_tiles", []) as Array:
		var pair: Array = arr as Array
		GameState.explored_tiles.append(Vector2i(pair[0] as int, pair[1] as int))
	GameState.mines_owned       = data.get("mines_owned",       {}) as Dictionary
	GameState.objects_collected = data.get("objects_collected", []) as Array[String]

func _serialise_towns() -> Dictionary:
	var result: Dictionary = {}
	for id: String in GameState.towns:
		var t: Variant = GameState.towns[id]
		result[id] = t.to_dict() if (t as Object).has_method("to_dict") else {}
	return result

func _deserialise_towns(_data: Dictionary) -> void:
	GameState.towns = {}   # TownFactory.restore_all(data) — Milestone 5


# ── FILE I/O ──────────────────────────────────────────────────────────────────

func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Cannot write %s — error %d" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Cannot read %s — error %d" % [path, FileAccess.get_open_error()])
		return {}
	var text: String   = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[SaveManager] Invalid JSON in %s" % path)
		return {}
	return parsed as Dictionary
