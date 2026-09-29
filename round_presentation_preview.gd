extends SceneTree

const GameScene = preload("res://scenes/game.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1152, 648))
	var scene := GameScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.78).timeout
	await _shot("res://round_intro_round_preview.png")
	await create_timer(0.90).timeout
	await _shot("res://round_intro_fight_preview.png")
	await create_timer(1.20).timeout
	scene.get_node("CombatHUD/CombatAnnouncement").show_count(9)
	await process_frame
	await process_frame
	await _shot("res://round_count_preview.png")
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(path))
