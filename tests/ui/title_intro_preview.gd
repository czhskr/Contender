extends SceneTree

## Title intro frames.

const MenuType = preload("res://scripts/title_menu.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1152, 648))
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await _shot("res://title_intro_black_preview.png")
	await create_timer(0.36).timeout
	await _shot("res://title_intro_logo_preview.png")
	await create_timer(0.28).timeout
	await _shot("res://title_intro_fade_preview.png")
	await create_timer(0.22).timeout
	await _shot("res://title_intro_move_preview.png")
	await create_timer(0.55).timeout
	await _shot("res://title_intro_final_preview.png")
	menu._activate_selected()
	await create_timer(0.30).timeout
	if menu._context._rows.size() > 1:
		menu._context._rows[1].set_hovered(true)
	await create_timer(0.16).timeout
	await _shot("res://title_hover_preview.png")
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(path))
