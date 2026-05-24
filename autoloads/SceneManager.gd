## SceneManager.gd
## Handles every scene transition in the game.
## Usage:
##   SceneManager.go_to(SceneManager.Scene.COMBAT, { "attacker": ..., "defender": ... })
##
## A black fade covers the transition so there's never a white flash or pop.
## The optional `data` dict is forwarded to the incoming scene's _on_scene_entered(data)
## method if it exists — scenes don't need to read from a global temp variable.
extends Node


# ─────────────────────────────────────────────
#  SCENE REGISTRY
## Add every scene path here. Using an enum keeps call sites typo-safe.
# ─────────────────────────────────────────────
enum Scene {
	MAIN_MENU,
	FACTION_SELECT,
	DIFFICULTY_SELECT,
	ADVENTURE_MAP,
	COMBAT,
	TOWN,
	HERO_SCREEN,
	LEVEL_UP,
	ARTIFACT_FOUND,
	EVENT_CHOICE,
	RUN_VICTORY,
	RUN_OVER,
	META_SCREEN,
	PAUSE_MENU,
	LOADING,
}

const SCENE_PATHS: Dictionary = {
	Scene.MAIN_MENU:        "res://scenes/menus/MainMenu.tscn",
	Scene.FACTION_SELECT:   "res://scenes/menus/FactionSelect.tscn",
	Scene.DIFFICULTY_SELECT:"res://scenes/menus/DifficultySelect.tscn",
	Scene.ADVENTURE_MAP:    "res://scenes/adventure_map/AdventureMap.tscn",
	Scene.COMBAT:           "res://scenes/combat/CombatScene.tscn",
	Scene.TOWN:             "res://scenes/ui/TownScene.tscn",
	Scene.HERO_SCREEN:      "res://scenes/ui/HeroScreen.tscn",
	Scene.LEVEL_UP:         "res://scenes/ui/LevelUpScreen.tscn",
	Scene.ARTIFACT_FOUND:   "res://scenes/ui/ArtifactFoundScreen.tscn",
	Scene.EVENT_CHOICE:     "res://scenes/ui/EventChoiceScreen.tscn",
	Scene.RUN_VICTORY:      "res://scenes/menus/RunVictory.tscn",
	Scene.RUN_OVER:         "res://scenes/menus/RunOver.tscn",
	Scene.META_SCREEN:      "res://scenes/menus/MetaScreen.tscn",
	Scene.PAUSE_MENU:       "res://scenes/menus/PauseMenu.tscn",
	Scene.LOADING:          "res://scenes/menus/LoadingScreen.tscn",
}

# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _current_scene: Node   = null
var _transitioning:  bool  = false
var _pending_scene:  Scene = Scene.MAIN_MENU
var _pending_data:   Dictionary = {}

## Fade overlay — injected from project root on startup.
## Must be a CanvasLayer > ColorRect covering the full viewport.
var _fade: ColorRect = null

const FADE_DURATION: float = 0.25


func _ready() -> void:
	# Listen for EventBus requests so any script can trigger a transition
	# without importing SceneManager directly.
	EventBus.scene_transition_requested.connect(_on_transition_requested)


# ─────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────

## Primary transition call.
## data is forwarded to the incoming scene's _on_scene_entered(data) if it exists.
func go_to(scene: Scene, data: Dictionary = {}) -> void:
	if _transitioning:
		push_warning("[SceneManager] Transition requested while already transitioning — queued.")
		_pending_scene = scene
		_pending_data  = data
		return
	_transitioning = true
	_pending_scene = scene
	_pending_data  = data
	await _fade_out()
	_swap_scene()
	await _fade_in()
	_transitioning = false


## Register the fade overlay node (called from the root scene _ready).
func register_fade(fade_node: ColorRect) -> void:
	_fade = fade_node


# ─────────────────────────────────────────────
#  INTERNAL
# ─────────────────────────────────────────────

func _on_transition_requested(scene_path: String, data: Dictionary) -> void:
	# Find the Scene enum matching the path
	for key in SCENE_PATHS:
		if SCENE_PATHS[key] == scene_path:
			go_to(key, data)
			return
	push_error("[SceneManager] Unknown scene path: %s" % scene_path)


func _swap_scene() -> void:
	var path: String = SCENE_PATHS.get(_pending_scene, "")
	if path == "":
		push_error("[SceneManager] No path for scene enum %d" % _pending_scene)
		return

	# Remove old scene
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null

	# Load and add new scene
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("[SceneManager] Failed to load scene: %s" % path)
		return

	_current_scene = packed.instantiate()
	get_tree().root.add_child(_current_scene)
	get_tree().current_scene = _current_scene

	# Forward data if the scene expects it
	if _current_scene.has_method("_on_scene_entered"):
		_current_scene._on_scene_entered(_pending_data)


func _fade_out() -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_DURATION)
	await tween.finished


func _fade_in() -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished
