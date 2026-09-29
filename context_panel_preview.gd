extends SceneTree

## Title context panel screenshots.

const MenuType = preload("res://scripts/title_menu.gd")
const PanelType = preload("res://scripts/title_context_panel.gd")
const MatchSettings = preload("res://scripts/match_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1152, 648))
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	menu.show_title_immediately()
	current_scene = menu
	await process_frame
	await process_frame
	menu._activate_selected()
	await create_timer(0.28).timeout
	(menu._context._rows[1] as Control).set_hovered(true)
	await create_timer(0.14).timeout
	await _shot("res://context_start_hover_preview.png")
	menu._select_index(2)
	menu._activate_selected()
	await create_timer(PanelType.EXIT_TIME + 0.28).timeout
	var bgm = menu._context._rows[0]
	bgm.set_hovered(true)
	await create_timer(0.14).timeout
	await _shot("res://context_slider_hover_preview.png")
	bgm.begin_drag((bgm.track_left() + bgm.track_right()) * 0.62)
	await process_frame
	await _shot("res://context_slider_drag_preview.png")
	bgm.end_drag()
	var shake = menu._context._rows[2]
	shake.right_arrow().set_hovered(true)
	await create_timer(0.14).timeout
	await _shot("res://context_shake_hover_preview.png")
	menu._select_index(1)
	menu._activate_selected()
	await create_timer(PanelType.EXIT_TIME + 0.4).timeout
	await _shot("res://context_tutorial_preview.png")
	MatchSettings.bgm_volume = 1.0
	MatchSettings.sfx_volume = 1.0
	MatchSettings.screen_shake = MatchSettings.ScreenShake.NORMAL
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(path))
