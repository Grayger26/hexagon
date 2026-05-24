## AudioManager.gd
## Central audio system.
##  - Music: one stream at a time, cross-fade between tracks.
##  - SFX:   pooled AudioStreamPlayers so many sounds can overlap.
##
## Usage:
##   AudioManager.play_music("adventure_castle")
##   AudioManager.play_sfx("sword_hit")
##   AudioManager.set_music_volume(0.8)
extends Node


# ─────────────────────────────────────────────
#  AUDIO PATHS
## Add every track/sfx key here.  Paths are relative to res://assets/audio/
# ─────────────────────────────────────────────
const MUSIC_PATHS: Dictionary = {
	"main_menu":          "res://assets/audio/music/main_menu.ogg",
	"adventure_castle":   "res://assets/audio/music/adventure_castle.ogg",
	"adventure_necro":    "res://assets/audio/music/adventure_necro.ogg",
	"adventure_stronghold":"res://assets/audio/music/adventure_stronghold.ogg",
	"combat":             "res://assets/audio/music/combat.ogg",
	"town_castle":        "res://assets/audio/music/town_castle.ogg",
	"town_necro":         "res://assets/audio/music/town_necro.ogg",
	"town_stronghold":    "res://assets/audio/music/town_stronghold.ogg",
	"victory":            "res://assets/audio/music/victory.ogg",
	"defeat":             "res://assets/audio/music/defeat.ogg",
}

const SFX_PATHS: Dictionary = {
	# Combat
	"sword_hit":          "res://assets/audio/sfx/sword_hit.wav",
	"arrow_shoot":        "res://assets/audio/sfx/arrow_shoot.wav",
	"spell_fire":         "res://assets/audio/sfx/spell_fire.wav",
	"spell_ice":          "res://assets/audio/sfx/spell_ice.wav",
	"spell_lightning":    "res://assets/audio/sfx/spell_lightning.wav",
	"spell_earth":        "res://assets/audio/sfx/spell_earth.wav",
	"unit_death":         "res://assets/audio/sfx/unit_death.wav",
	"level_up":           "res://assets/audio/sfx/level_up.wav",
	"morale_positive":    "res://assets/audio/sfx/morale_positive.wav",
	"morale_negative":    "res://assets/audio/sfx/morale_negative.wav",
	"luck_proc":          "res://assets/audio/sfx/luck_proc.wav",
	# Adventure map
	"footstep":           "res://assets/audio/sfx/footstep.wav",
	"gold_pickup":        "res://assets/audio/sfx/gold_pickup.wav",
	"mine_capture":       "res://assets/audio/sfx/mine_capture.wav",
	# UI
	"button_click":       "res://assets/audio/sfx/button_click.wav",
	"button_hover":       "res://assets/audio/sfx/button_hover.wav",
	"build_complete":     "res://assets/audio/sfx/build_complete.wav",
	"artifact_equip":     "res://assets/audio/sfx/artifact_equip.wav",
	"hero_recruit":       "res://assets/audio/sfx/hero_recruit.wav",
}

# ─────────────────────────────────────────────
#  SETTINGS  (persisted via SaveManager meta)
# ─────────────────────────────────────────────
var music_volume: float = 1.0   # 0.0–1.0
var sfx_volume:   float = 1.0
var music_enabled: bool = true
var sfx_enabled:   bool = true

# ─────────────────────────────────────────────
#  NODES
# ─────────────────────────────────────────────
const SFX_POOL_SIZE: int = 12

var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer   # which one is currently audible
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0

var _current_music_key: String = ""
var _crossfade_tween: Tween = null


func _ready() -> void:
	# Music players (two for cross-fading)
	_music_player_a = _make_music_player()
	_music_player_b = _make_music_player()
	_active_music_player = _music_player_a

	# SFX pool
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	_load_settings()


# ─────────────────────────────────────────────
#  MUSIC
# ─────────────────────────────────────────────

func play_music(key: String, crossfade: bool = true) -> void:
	if key == _current_music_key:
		return
	if not music_enabled:
		return
	if not MUSIC_PATHS.has(key):
		push_warning("[AudioManager] Unknown music key: %s" % key)
		return

	_current_music_key = key
	var stream: AudioStream = _load_audio(MUSIC_PATHS[key])
	if stream == null:
		return

	var incoming := _music_player_b if _active_music_player == _music_player_a else _music_player_a
	incoming.stream = stream
	incoming.volume_db = linear_to_db(0.0)
	incoming.play()

	if crossfade and _active_music_player.playing:
		if _crossfade_tween:
			_crossfade_tween.kill()
		_crossfade_tween = create_tween().set_parallel(true)
		_crossfade_tween.tween_property(_active_music_player, "volume_db",
			linear_to_db(0.0), 1.5)
		_crossfade_tween.tween_property(incoming, "volume_db",
			linear_to_db(music_volume), 1.5)
		await _crossfade_tween.finished
		_active_music_player.stop()
	else:
		_active_music_player.stop()
		incoming.volume_db = linear_to_db(music_volume)

	_active_music_player = incoming


func stop_music(fade: bool = true) -> void:
	if fade:
		var tween := create_tween()
		tween.tween_property(_active_music_player, "volume_db", linear_to_db(0.0), 1.0)
		await tween.finished
	_active_music_player.stop()
	_current_music_key = ""


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_active_music_player.volume_db = linear_to_db(music_volume)
	_save_settings()


# ─────────────────────────────────────────────
#  SFX
# ─────────────────────────────────────────────

func play_sfx(key: String, pitch_variation: float = 0.0) -> void:
	if not sfx_enabled:
		return
	if not SFX_PATHS.has(key):
		push_warning("[AudioManager] Unknown SFX key: %s" % key)
		return
	var stream: AudioStream = _load_audio(SFX_PATHS[key])
	if stream == null:
		return
	var player := _sfx_pool[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume)
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_save_settings()


# ─────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = linear_to_db(0.0)
	add_child(p)
	return p


## Cache loaded streams so the same file isn't loaded from disk twice.
var _stream_cache: Dictionary = {}

func _load_audio(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not ResourceLoader.exists(path):
		push_warning("[AudioManager] Audio file not found: %s" % path)
		return null
	var stream: AudioStream = load(path)
	_stream_cache[path] = stream
	return stream


func _load_settings() -> void:
	var meta := SaveManager.get_meta()
	music_volume  = meta.get("audio_music_vol",  1.0)
	sfx_volume    = meta.get("audio_sfx_vol",    1.0)
	music_enabled = meta.get("audio_music_on",   true)
	sfx_enabled   = meta.get("audio_sfx_on",     true)


func _save_settings() -> void:
	SaveManager.set_meta_value("audio_music_vol", music_volume)
	SaveManager.set_meta_value("audio_sfx_vol",   sfx_volume)
	SaveManager.set_meta_value("audio_music_on",  music_enabled)
	SaveManager.set_meta_value("audio_sfx_on",    sfx_enabled)
