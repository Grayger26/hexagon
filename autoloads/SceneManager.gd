## SceneManager.gd
## Handles every scene transition with a black fade.
## Preserves AdventureMap during combat so the map state (obstacles,
## player position, fog, enemy sprites) persists across battles.
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

var _current_scene:     Node       = null
var _current_scene_type: int        = -1   ## Scene enum value, -1 = none
var _transitioning:     bool       = false
var _pending_scene:     Scene      = Scene.MAIN_MENU
var _pending_data:      Dictionary = {}

## Preserved (hidden) scene that will be restored on return.
## e.g. AdventureMap is hidden during combat and restored when combat ends.
var _preserved_scene:     Node = null
var _preserved_scene_type: int  = -1

## Rules for scene preservation: when transitioning TO a scene type,
## preserve (hide) the current scene of the mapped type instead of freeing it.
## Key = destination scene, Value = current scene type to preserve.
const _PRESERVE_RULES: Dictionary = {
	Scene.COMBAT: Scene.ADVENTURE_MAP,
}

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
	if is_instance_valid(fade_rect):
		await _fade(1.0)
	_swap_scene()
	if is_instance_valid(fade_rect):
		await _fade(0.0)
	_transitioning = false

func _on_transition_requested(scene_path: String, data: Dictionary) -> void:
	for key: Variant in SCENE_PATHS:
		if SCENE_PATHS[key] as String == scene_path:
			go_to(key as Scene, data)
			return
	push_error("[SceneManager] Unknown scene path: %s" % scene_path)



# ── PRIVATE ──────────────────────────────────────────────────────────────


func _swap_scene() -> void:
	var path: String = SCENE_PATHS.get(_pending_scene, "") as String
	if path.is_empty():
		push_error("[SceneManager] No path registered for scene %d" % _pending_scene)
		return

	# ── Restore a preserved scene? ────────────────────────────────────────
	# If we hid AdventureMap during combat and are now returning to it,
	# restore the hidden instance instead of creating a fresh one.
	if _preserved_scene != null and _pending_scene == _preserved_scene_type:
		if _current_scene:
			_current_scene.queue_free()
		_current_scene = _preserved_scene
		_current_scene_type = _preserved_scene_type
		_preserved_scene = null
		_preserved_scene_type = -1
		# Re-add to tree and show it.
		get_tree().root.add_child(_current_scene)
		get_tree().current_scene = _current_scene
		_current_scene.visible = true
		print("[SceneManager] Restored preserved scene type=%d" % _current_scene_type)
		# Notify the restored scene it's back.
		if _current_scene.has_method("_on_scene_entered"):
			_current_scene._on_scene_entered(_pending_data)
		return

	# ── Discard stale preserved scene (we're transitioning somewhere else) ─
	if _preserved_scene != null:
		print("[SceneManager] Discarding stale preserved scene type=%d" % _preserved_scene_type)
		_preserved_scene.queue_free()
		_preserved_scene = null
		_preserved_scene_type = -1

	# ── Free or preserve the current scene ────────────────────────────────
	if _current_scene:
		var preserve_target: int = _PRESERVE_RULES.get(_pending_scene, -1) as int
		if preserve_target != -1 and _current_scene_type == preserve_target:
			# Preserve: hide instead of free so the scene's state survives.
			_current_scene.visible = false
			get_tree().root.remove_child(_current_scene)
			_preserved_scene = _current_scene
			_preserved_scene_type = _current_scene_type
			_current_scene = null
			_current_scene_type = -1
			print("[SceneManager] Preserved scene type=%d for later restoration" % preserve_target)
		else:
			_current_scene.queue_free()
			_current_scene = null
			_current_scene_type = -1
	elif get_tree().current_scene != null:
		# First transition: free the initial scene (MainMenu) which was
		# created by Godot's project settings, not by SceneManager.
		print("[SceneManager] Freeing initial scene: %s" % get_tree().current_scene.name)
		get_tree().current_scene.queue_free()

	# ── Create the new scene ──────────────────────────────────────────────
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("[SceneManager] Failed to load: %s" % path)
		return
	_current_scene = packed.instantiate()
	_current_scene_type = _pending_scene as int
	get_tree().root.add_child(_current_scene)
	get_tree().current_scene = _current_scene
	print("[SceneManager] Created scene type=%d: %s" % [_current_scene_type, path])
	if _current_scene.has_method("_on_scene_entered"):
		_current_scene._on_scene_entered(_pending_data)


func _fade(target_alpha: float) -> void:
	if fade_rect == null:
		return
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", target_alpha, FADE_DURATION)
	await tween.finished
