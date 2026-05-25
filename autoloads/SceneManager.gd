## SceneManager.gd
## Handles every scene transition with a black fade.
## Usage:  SceneManager.go_to(SceneManager.Scene.COMBAT, { "data": ... })
extends Node


enum Scene {
	MAIN_MENU, FACTION_SELECT, DIFFICULTY_SELECT,
	ADVENTURE_MAP, COMBAT, TOWN, HERO_SCREEN, LEVEL_UP,
	ARTIFACT_FOUND, EVENT_CHOICE, RUN_VICTORY, RUN_OVER,
	META_SCREEN, PAUSE_MENU,
}

const SCENE_PATHS: Dictionary = {
	Scene.MAIN_MENU:         "res://scenes/menus/MainMenu.tscn",
	Scene.FACTION_SELECT:    "res://scenes/menus/FactionSelect.tscn",
	Scene.DIFFICULTY_SELECT: "res://scenes/menus/DifficultySelect.tscn",
	Scene.ADVENTURE_MAP:     "res://scenes/adventure_map/AdventureMap.tscn",
	Scene.COMBAT:            "res://scenes/combat/CombatScene.tscn",
	Scene.TOWN:              "res://scenes/ui/TownScene.tscn",
	Scene.HERO_SCREEN:       "res://scenes/ui/HeroScreen.tscn",
	Scene.LEVEL_UP:          "res://scenes/ui/LevelUpScreen.tscn",
	Scene.ARTIFACT_FOUND:    "res://scenes/ui/ArtifactFoundScreen.tscn",
	Scene.EVENT_CHOICE:      "res://scenes/ui/EventChoiceScreen.tscn",
	Scene.RUN_VICTORY:       "res://scenes/menus/RunVictory.tscn",
	Scene.RUN_OVER:          "res://scenes/menus/RunOver.tscn",
	Scene.META_SCREEN:       "res://scenes/menus/MetaScreen.tscn",
	Scene.PAUSE_MENU:        "res://scenes/menus/PauseMenu.tscn",
}

const FADE_DURATION: float = 0.25

var _current_scene: Node       = null
var _transitioning:  bool      = false
var _pending_scene:  Scene     = Scene.MAIN_MENU
var _pending_data:   Dictionary = {}

## Assign from the first scene's _ready():  SceneManager.fade_rect = $FadeRect
var fade_rect: ColorRect = null


func _ready() -> void:
	EventBus.scene_transition_requested.connect(_on_transition_requested)


func go_to(scene: Scene, data: Dictionary = {}) -> void:
	if _transitioning:
		push_warning("[SceneManager] Already transitioning — request ignored.")
		return
	_transitioning = true
	_pending_scene = scene
	_pending_data  = data
	await _fade(1.0)
	_swap_scene()
	await _fade(0.0)
	_transitioning = false


func _on_transition_requested(scene_path: String, data: Dictionary) -> void:
	for key: Variant in SCENE_PATHS:
		if SCENE_PATHS[key] as String == scene_path:
			go_to(key as Scene, data)
			return
	push_error("[SceneManager] Unknown scene path: %s" % scene_path)


func _swap_scene() -> void:
	var path: String = SCENE_PATHS.get(_pending_scene, "") as String
	if path.is_empty():
		push_error("[SceneManager] No path registered for scene %d" % _pending_scene)
		return
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("[SceneManager] Failed to load: %s" % path)
		return
	_current_scene = packed.instantiate()
	get_tree().root.add_child(_current_scene)
	get_tree().current_scene = _current_scene
	if _current_scene.has_method("_on_scene_entered"):
		_current_scene._on_scene_entered(_pending_data)


func _fade(target_alpha: float) -> void:
	if fade_rect == null:
		return
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", target_alpha, FADE_DURATION)
	await tween.finished
