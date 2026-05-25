## AudioManager.gd
## Central audio system. Music cross-fades; SFX uses a fixed pool of players.
## Usage:
##   AudioManager.play_music("adventure_castle")
##   AudioManager.play_sfx("sword_hit")
extends Node


const MUSIC_PATHS: Dictionary = {
	"main_menu":           "res://assets/audio/music/main_menu.ogg",
	"adventure_castle":    "res://assets/audio/music/adventure_castle.ogg",
	"adventure_necro":     "res://assets/audio/music/adventure_necro.ogg",
	"adventure_stronghold":"res://assets/audio/music/adventure_stronghold.ogg",
	"combat":              "res://assets/audio/music/combat.ogg",
	"town_castle":         "res://assets/audio/music/town_castle.ogg",
	"town_necro":          "res://assets/audio/music/town_necro.ogg",
	"town_stronghold":     "res://assets/audio/music/town_stronghold.ogg",
	"victory":             "res://assets/audio/music/victory.ogg",
	"defeat":              "res://assets/audio/music/defeat.ogg",
}

const SFX_PATHS: Dictionary = {
	"sword_hit":      "res://assets/audio/sfx/sword_hit.wav",
	"arrow_shoot":    "res://assets/audio/sfx/arrow_shoot.wav",
	"spell_fire":     "res://assets/audio/sfx/spell_fire.wav",
	"spell_ice":      "res://assets/audio/sfx/spell_ice.wav",
	"spell_lightning":"res://assets/audio/sfx/spell_lightning.wav",
	"spell_earth":    "res://assets/audio/sfx/spell_earth.wav",
	"unit_death":     "res://assets/audio/sfx/unit_death.wav",
	"level_up":       "res://assets/audio/sfx/level_up.wav",
	"morale_positive":"res://assets/audio/sfx/morale_positive.wav",
	"morale_negative":"res://assets/audio/sfx/morale_negative.wav",
	"luck_proc":      "res://assets/audio/sfx/luck_proc.wav",
	"footstep":       "res://assets/audio/sfx/footstep.wav",
	"gold_pickup":    "res://assets/audio/sfx/gold_pickup.wav",
	"mine_capture":   "res://assets/audio/sfx/mine_capture.wav",
	"button_click":   "res://assets/audio/sfx/button_click.wav",
	"button_hover":   "res://assets/audio/sfx/button_hover.wav",
	"build_complete": "res://assets/audio/sfx/build_complete.wav",
	"artifact_equip": "res://assets/audio/sfx/artifact_equip.wav",
	"hero_recruit":   "res://assets/audio/sfx/hero_recruit.wav",
}

const SFX_POOL_SIZE: int = 12
const FADE_TIME:     float = 1.5

var music_volume:  float = 1.0
var sfx_volume:    float = 1.0
var music_enabled: bool  = true
var sfx_enabled:   bool  = true

var _player_a:    AudioStreamPlayer
var _player_b:    AudioStreamPlayer
var _active:      AudioStreamPlayer
var _sfx_pool:    Array[AudioStreamPlayer] = []
var _pool_idx:    int = 0
var _current_key: String = ""
var _stream_cache: Dictionary = {}


func _ready() -> void:
	_player_a = _make_music_player()
	_player_b = _make_music_player()
	_active   = _player_a
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	# Deferred so SaveManager._ready() has run before we read from it.
	call_deferred("_load_settings")


# ── MUSIC ─────────────────────────────────────────────────────────────────────

func play_music(key: String, crossfade: bool = true) -> void:
	if key == _current_key or not music_enabled:
		return
	if not MUSIC_PATHS.has(key):
		push_warning("[AudioManager] Unknown music key: %s" % key)
		return
	_current_key = key
	var stream: AudioStream = _load_audio(MUSIC_PATHS[key])
	if stream == null:
		return
	var incoming: AudioStreamPlayer = _player_b if _active == _player_a else _player_a
	incoming.stream    = stream
	incoming.volume_db = linear_to_db(0.0)
	incoming.play()
	if crossfade and _active.playing:
		var t := create_tween().set_parallel(true)
		t.tween_property(_active,  "volume_db", linear_to_db(0.0),         FADE_TIME)
		t.tween_property(incoming, "volume_db", linear_to_db(music_volume), FADE_TIME)
		await t.finished
		_active.stop()
	else:
		_active.stop()
		incoming.volume_db = linear_to_db(music_volume)
	_active = incoming


func stop_music(fade: bool = true) -> void:
	if fade:
		var t := create_tween()
		t.tween_property(_active, "volume_db", linear_to_db(0.0), FADE_TIME)
		await t.finished
	_active.stop()
	_current_key = ""


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_active.volume_db = linear_to_db(music_volume)
	_save_settings()


# ── SFX ───────────────────────────────────────────────────────────────────────

func play_sfx(key: String, pitch_var: float = 0.05) -> void:
	if not sfx_enabled:
		return
	if not SFX_PATHS.has(key):
		push_warning("[AudioManager] Unknown SFX key: %s" % key)
		return
	var stream: AudioStream = _load_audio(SFX_PATHS[key])
	if stream == null:
		return
	var p: AudioStreamPlayer = _sfx_pool[_pool_idx]
	_pool_idx     = (_pool_idx + 1) % SFX_POOL_SIZE
	p.stream      = stream
	p.volume_db   = linear_to_db(sfx_volume)
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_save_settings()


# ── HELPERS ───────────────────────────────────────────────────────────────────

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = linear_to_db(0.0)
	add_child(p)
	return p


func _load_audio(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		push_warning("[AudioManager] File not found: %s" % path)
		return null
	var s: AudioStream = load(path)
	_stream_cache[path] = s
	return s


func _load_settings() -> void:
	var m: Dictionary = SaveManager.get_meta_data()
	music_volume  = m.get("audio_music_vol", 1.0)  as float
	sfx_volume    = m.get("audio_sfx_vol",   1.0)  as float
	music_enabled = m.get("audio_music_on",  true) as bool
	sfx_enabled   = m.get("audio_sfx_on",    true) as bool


func _save_settings() -> void:
	SaveManager.set_meta_value("audio_music_vol", music_volume)
	SaveManager.set_meta_value("audio_sfx_vol",   sfx_volume)
