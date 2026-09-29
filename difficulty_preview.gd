extends SceneTree

const MenuType = preload("res://scripts/title_menu.gd")
const MatchSettings = preload("res://scripts/match_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1152, 648))
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	menu.show_title_immediately()
	menu._select_index(2)
	menu._activate_selected()
	await create_timer(0.28).timeout
	MatchSettings.difficulty = MatchSettings.Difficulty.EASY
	menu._context._refresh_rows()
	await process_frame
	await _shot("res://difficulty_easy_preview.png")
	MatchSettings.difficulty = MatchSettings.Difficulty.NORMAL
	menu._context._refresh_rows()
	await process_frame
	await _shot("res://difficulty_normal_preview.png")
	MatchSettings.difficulty = MatchSettings.Difficulty.HARD
	menu._context._refresh_rows()
	await process_frame
	await _shot("res://difficulty_hard_preview.png")
	MatchSettings.difficulty = MatchSettings.Difficulty.NORMAL
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(path))
