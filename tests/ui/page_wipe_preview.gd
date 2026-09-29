extends SceneTree

## Saves three wipe frames. Not part of headless smoke.

const MenuType = preload("res://scripts/title_menu.gd")
const TransitionType = preload("res://scripts/page_transition.gd")


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
	var confirm := InputEventKey.new()
	confirm.pressed = true
	confirm.keycode = KEY_ENTER
	menu._context.handle_key(confirm)
	var transition = root.get_node("PageTransition")
	await _until(func() -> bool:
		var front := transition.get_node("FrontSlab") as Control
		var right := front.position.x + front.size.x
		return right > 520.0 and front.position.x < 0.0
	)
	await _shot("res://wipe_enter_preview.png")
	await _until(func() -> bool: return transition.phase == TransitionType.Phase.COVERED)
	await _shot("res://wipe_cover_preview.png")
	await _until(func() -> bool: return transition.phase == TransitionType.Phase.WIPE_OUT)
	for _i in 8:
		await process_frame
	await _shot("res://wipe_reveal_preview.png")
	quit(0)


func _until(done: Callable) -> void:
	for _i in 180:
		if done.call():
			return
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(path))
