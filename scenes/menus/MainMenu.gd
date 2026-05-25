## MainMenu.gd
## First scene the player sees. Wires up SceneManager fade rect here since
## this is the entry point — it runs before any other scene is loaded.
extends Control


func _ready() -> void:
	# Register the fade rect with SceneManager so transitions work from here on.
	SceneManager.fade_rect = $FadeRect
	# Fade in on arrival
	$FadeRect.modulate.a = 1.0
	var t := create_tween()
	t.tween_property($FadeRect, "modulate:a", 0.0, 0.4)

	$VBox/BtnNewRun.pressed.connect(_on_new_run)
	$VBox/BtnContinue.pressed.connect(_on_continue)
	$VBox/BtnMeta.pressed.connect(_on_meta)
	$VBox/BtnQuit.pressed.connect(_on_quit)

	# Grey out Continue if no save exists
	$VBox/BtnContinue.disabled = not SaveManager.has_run_save()


func _on_new_run() -> void:
	AudioManager.play_sfx("button_click")
	SceneManager.go_to(SceneManager.Scene.FACTION_SELECT)


func _on_continue() -> void:
	AudioManager.play_sfx("button_click")
	if SaveManager.load_run():
		SceneManager.go_to(SceneManager.Scene.ADVENTURE_MAP)


func _on_meta() -> void:
	AudioManager.play_sfx("button_click")
	SceneManager.go_to(SceneManager.Scene.META_SCREEN)


func _on_quit() -> void:
	get_tree().quit()
