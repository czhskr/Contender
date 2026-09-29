extends SceneTree

## Context panel hover, sliders, shake arrows, tutorial columns, and panel toggle.
## godot --headless --path . -s res://tests/ui/context_panel_smoke_test.gd

const MenuType = preload("res://scripts/title_menu.gd")
const PanelType = preload("res://scripts/title_context_panel.gd")
const MatchSettings = preload("res://scripts/match_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	await _check_mode_hover(menu, failures)
	await _check_sliders(menu, failures)
	await _check_shake(menu, failures)
	await _check_tutorial(menu, failures)
	await _check_toggle(menu, failures)
	if failures.is_empty():
		print("SMOKE PASS: context panel")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_mode_hover(menu: MenuType, failures: Array[String]) -> void:
	menu._select_index(0)
	menu._activate_selected()
	var mode_row = menu._context._rows[0]
	var trait_row = menu._context._rows[1]
	if mode_row._light_amount() > 0.05 or trait_row._light_amount() > 0.05:
		failures.append("game mode rows start highlighted")
	mode_row.set_hovered(true)
	await create_timer(0.2).timeout
	if mode_row._light_amount() < 0.9 or trait_row._light_amount() > 0.05:
		failures.append("only 일반 should light on hover")
	if not mode_row.selected:
		failures.append("hover replaced the keyboard index")
	mode_row.set_hovered(false)
	trait_row.set_hovered(true)
	await create_timer(0.2).timeout
	if trait_row._light_amount() < 0.9 or mode_row._light_amount() > 0.05:
		failures.append("only 특성 should light on hover")
	trait_row.set_hovered(false)
	await create_timer(0.2).timeout
	if mode_row._light_amount() > 0.05 or trait_row._light_amount() > 0.05:
		failures.append("rows stayed lit after the pointer left")
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = KEY_DOWN
	menu._context.handle_key(down)
	if mode_row._light_amount() > 0.05 or trait_row._light_amount() < 0.9:
		failures.append("keyboard focus did not light only 특성")
	mode_row.set_hovered(true)
	await create_timer(0.2).timeout
	if mode_row._light_amount() < 0.9 or trait_row._light_amount() > 0.05:
		failures.append("mouse hover did not override keyboard focus")
	mode_row.set_hovered(false)
	await create_timer(0.05).timeout
	if trait_row._light_amount() < 0.9 or mode_row._light_amount() > 0.05:
		failures.append("keyboard focus did not return after hover")


func _check_sliders(menu: MenuType, failures: Array[String]) -> void:
	menu._select_index(2)
	menu._activate_selected()
	await create_timer(PanelType.EXIT_TIME + 0.08).timeout
	var bgm = menu._context._rows[0]
	var sfx = menu._context._rows[1]
	var difficulty_row = menu._context._rows[2]
	var shake = menu._context._rows[3]
	if bgm._light_amount() > 0.05 or sfx._light_amount() > 0.05 or difficulty_row._light_amount() > 0.05 or shake._light_amount() > 0.05:
		failures.append("option rows start highlighted by their stored values")
	bgm.set_hovered(true)
	await create_timer(0.2).timeout
	if bgm._light_amount() < 0.9 or sfx._light_amount() > 0.05 or difficulty_row._light_amount() > 0.05 or shake._light_amount() > 0.05:
		failures.append("only BGM should light on hover")
	bgm.set_hovered(false)
	sfx.set_hovered(true)
	await create_timer(0.2).timeout
	if sfx._light_amount() < 0.9 or bgm._light_amount() > 0.05 or difficulty_row._light_amount() > 0.05 or shake._light_amount() > 0.05:
		failures.append("only SFX should light on hover")
	sfx.set_hovered(false)
	shake.set_hovered(true)
	await create_timer(0.2).timeout
	if shake._light_amount() < 0.9 or bgm._light_amount() > 0.05 or sfx._light_amount() > 0.05 or difficulty_row._light_amount() > 0.05:
		failures.append("only screen shake should light on hover")
	shake.set_hovered(false)
	if not is_equal_approx(bgm.value_from_x(bgm.track_left()), 0.0):
		failures.append("slider left end is not 0%")
	if not is_equal_approx(bgm.value_from_x(bgm.track_right()), 1.0):
		failures.append("slider right end is not 100%")
	var above := Vector2(bgm.track_left(), 4.0)
	var on_track := Vector2((bgm.track_left() + bgm.track_right()) * 0.5, bgm.TRACK_Y)
	if bgm.track_hit_rect().has_point(above) or not bgm.track_hit_rect().has_point(on_track):
		failures.append("slider hit area does not cover the track")
	if bgm.track_hit_rect().size.y < 28.0:
		failures.append("slider hit area is thinner than 28px")
	bgm.begin_drag(bgm.track_left())
	if not is_equal_approx(MatchSettings.bgm_volume, 0.0) or not bgm.is_dragging():
		failures.append("BGM track click did not go to 0%")
	bgm.drag_to(bgm.track_right() + 80.0)
	if not is_equal_approx(MatchSettings.bgm_volume, 1.0) or not bgm.is_dragging():
		failures.append("BGM drag did not clamp at 100%")
	bgm.note_pointer_exit()
	if not bgm.is_dragging():
		failures.append("BGM drag released when the pointer left")
	bgm.drag_to(-40.0)
	if not is_equal_approx(MatchSettings.bgm_volume, 0.0):
		failures.append("BGM drag did not clamp at 0%")
	sfx.begin_drag(sfx.track_right())
	if bgm.is_dragging():
		failures.append("two sliders stayed captured")
	if not is_equal_approx(MatchSettings.sfx_volume, 1.0):
		failures.append("SFX track click did not go to 100%")
	sfx.drag_to(sfx.track_left() - 30.0)
	if not is_equal_approx(MatchSettings.sfx_volume, 0.0) or not sfx.is_dragging():
		failures.append("SFX drag did not clamp at 0%")
	sfx.end_drag()
	MatchSettings.bgm_volume = 1.0
	MatchSettings.sfx_volume = 1.0


func _check_shake(menu: MenuType, failures: Array[String]) -> void:
	MatchSettings.screen_shake = MatchSettings.ScreenShake.NORMAL
	menu._context._refresh_rows()
	var shake = menu._context._rows[3]
	var center: Vector2 = shake.value_center()
	MatchSettings.screen_shake = MatchSettings.ScreenShake.OFF
	menu._context._refresh_rows()
	if shake.value_center() != center:
		failures.append("OFF moved the shake value center")
	if shake.left_arrow().enabled or not shake.right_arrow().enabled:
		failures.append("OFF did not disable only the left arrow")
	var before: int = MatchSettings.screen_shake
	_click_arrow(shake.left_arrow())
	if MatchSettings.screen_shake != before:
		failures.append("disabled left arrow changed the shake value")
	_click_arrow(shake.right_arrow())
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.NORMAL:
		failures.append("right arrow did not step to NORMAL")
	MatchSettings.screen_shake = MatchSettings.ScreenShake.STRONG
	menu._context._refresh_rows()
	if shake.value_center() != center:
		failures.append("STRONG moved the shake value center")
	if shake.right_arrow().enabled or not shake.left_arrow().enabled:
		failures.append("STRONG did not disable only the right arrow")
	shake.left_arrow().set_hovered(true)
	await create_timer(0.2).timeout
	if shake.left_arrow().hover_mix < 0.9 or shake.right_arrow().hover_mix > 0.05:
		failures.append("arrow hover was not limited to the pointed arrow")
	var right := InputEventKey.new()
	right.pressed = true
	right.keycode = KEY_RIGHT
	menu._context._inner_index = 3
	menu._context.handle_key(right)
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.STRONG:
		failures.append("keyboard did not keep STRONG clamped")
	var left := InputEventKey.new()
	left.pressed = true
	left.keycode = KEY_LEFT
	menu._context.handle_key(left)
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.NORMAL:
		failures.append("keyboard Left did not step back to NORMAL")
	if shake.left_arrow().size.x < 36.0 or shake.left_arrow().size.y < 36.0:
		failures.append("arrow hit target is below 36px")
	MatchSettings.screen_shake = MatchSettings.ScreenShake.NORMAL


func _check_tutorial(menu: MenuType, failures: Array[String]) -> void:
	menu._context.open_kind(1)
	await create_timer(PanelType.EXIT_TIME + 0.08).timeout
	var action_x := -1.0
	var saw_evade := false
	var saw_duck := false
	for child in _all_labels(menu._context):
		if child is Label and str(child.get_meta("column", "")) == "action":
			var label := child as Label
			if action_x < 0.0:
				action_x = label.position.x
			elif not is_equal_approx(label.position.x, action_x):
				failures.append("tutorial action column is not aligned")
			if label.text == "아래 회피":
				saw_evade = true
			if label.text.find("DUCK") >= 0 or label.text.find("오리") >= 0:
				saw_duck = true
	if not saw_evade or saw_duck:
		failures.append("tutorial does not say 아래 회피")
	var plate = menu._context.get_node_or_null("AttackPlate")
	if plate == null:
		failures.append("tutorial section backing is missing")
	else:
		var alpha: float = PanelType.SECTION_BACKING.a
		if alpha < 0.70 or alpha > 0.82:
			failures.append("tutorial backing alpha is outside 0.70-0.82")


func _all_labels(node: Node) -> Array:
	var labels: Array = []
	_gather_labels(node, labels)
	return labels


func _gather_labels(node: Node, labels: Array) -> void:
	if node is Label:
		labels.append(node)
	for child in node.get_children():
		_gather_labels(child, labels)


func _check_toggle(menu: MenuType, failures: Array[String]) -> void:
	menu._select_index(0)
	menu._activate_selected()
	await create_timer(PanelType.EXIT_TIME + 0.05).timeout
	if menu._context.current_kind() != 0 or not menu._context.is_open():
		failures.append("START did not open")
	menu._activate_selected()
	if menu._context.is_open():
		failures.append("START did not toggle closed")
	menu._select_index(1)
	menu._activate_selected()
	await create_timer(0.05).timeout
	menu._activate_selected()
	if menu._context.is_open():
		failures.append("TUTORIAL did not toggle closed")
	menu._select_index(2)
	menu._activate_selected()
	await create_timer(0.05).timeout
	menu._activate_selected()
	if menu._context.is_open():
		failures.append("OPTIONS did not toggle closed")
	menu._activate_selected()
	await create_timer(0.05).timeout
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	menu._unhandled_input(escape)
	if menu._context.is_open():
		failures.append("ESC did not close the panel")
	menu._select_index(2)
	menu._activate_selected()
	await create_timer(0.02).timeout
	menu._select_index(0)
	menu._activate_selected()
	menu._select_index(1)
	menu._activate_selected()
	menu._select_index(2)
	menu._activate_selected()
	await create_timer(0.55).timeout
	if not menu._context.is_open() or menu._context.current_kind() != 2:
		failures.append("fast switching did not settle on OPTIONS")
	var names: PackedStringArray = []
	for child in menu._context.get_children():
		names.append(str(child.name))
	if names.has("일반") or names.has("특성"):
		failures.append("fast switching restored a stale mode row")
	var backing := 0
	for child in menu._context.get_children():
		if str(child.name) == "Backing":
			backing += 1
	if backing != 1:
		failures.append("fast switching left stale panel content")


func _click_arrow(arrow: Control) -> void:
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = arrow.size * 0.5
	arrow._gui_input(event)
