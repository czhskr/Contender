extends SceneTree

## Title menu selection state.
## godot --headless --path . -s res://tests/ui/title_menu_smoke_test.gd

const MenuType = preload("res://scripts/title_menu.gd")
const MatchSettings = preload("res://scripts/match_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	if not ResourceLoader.exists(MenuType.BACKGROUND_PATH):
		failures.append("title background missing")
	if not ResourceLoader.exists(MenuType.LOGO_PATH):
		failures.append("title logo missing")
	var background: Texture2D = load(MenuType.BACKGROUND_PATH)
	var logo: Texture2D = load(MenuType.LOGO_PATH)
	if background == null or logo == null:
		failures.append("title images failed to load")
	elif not is_equal_approx(float(background.get_width()) / float(background.get_height()), 1152.0 / 648.0):
		failures.append("title background aspect is not 16:9")
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	if menu.menu_items.size() != 3 or menu.menu_items[0] != "시작" or menu.menu_items[1] != "튜토리얼" or menu.menu_items[2] != "설정":
		failures.append("menu is not 시작, 튜토리얼, 설정")
	if "QUIT" in menu.menu_items:
		failures.append("QUIT must not exist")
	if menu.selected_index != 0:
		failures.append("시작 is not the default selection")
	menu._move_selection(1)
	if menu.selected_index != 1:
		failures.append("down did not reach TUTORIAL")
	menu._move_selection(1)
	if menu.selected_index != 2:
		failures.append("down did not reach OPTIONS")
	menu._move_selection(1)
	if menu.selected_index != 0:
		failures.append("down did not wrap to 시작")
	menu._move_selection(-1)
	if menu.selected_index != 2:
		failures.append("up did not wrap to OPTIONS")
	var start := menu._slabs[0] as Control
	var tutorial := menu._slabs[1] as Control
	var options := menu._slabs[2] as Control
	if tutorial.position.x <= start.position.x or options.position.x <= tutorial.position.x:
		failures.append("menu cascade is missing")
	if menu._context == null or menu._context.is_open():
		failures.append("context panel should start closed")
	menu._select_index(1)
	if menu._context.is_open():
		failures.append("hover/selection opened a panel")
	menu._select_index(0)
	menu._activate_selected()
	if not menu._context.is_open() or menu._context.current_kind() != 0:
		failures.append("시작 did not open the mode panel")
	var held := menu.selected_index
	menu._move_selection(1)
	if menu.selected_index != held:
		failures.append("panel and menu moved together")
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = KEY_DOWN
	menu._context.handle_key(down)
	if menu._context.inner_index() != 1:
		failures.append("START panel did not move to TRAIT")
	menu._select_index(2)
	menu._activate_selected()
	if menu._context.current_kind() != 2:
		failures.append("click did not replace the open panel")
	var right := InputEventKey.new()
	right.pressed = true
	right.keycode = KEY_LEFT
	menu._context.handle_key(right)
	if MatchSettings.bgm_volume >= 1.0:
		failures.append("OPTIONS slider did not decrease")
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.NORMAL:
		failures.append("screen shake should start at NORMAL")
	var down_shake := InputEventKey.new()
	down_shake.pressed = true
	down_shake.keycode = KEY_DOWN
	menu._context.handle_key(down_shake)
	menu._context.handle_key(down_shake)
	menu._context.handle_key(down_shake)
	if menu._context.inner_index() != 3:
		failures.append("SCREEN SHAKE row was not selected")
	var step_right := InputEventKey.new()
	step_right.pressed = true
	step_right.keycode = KEY_RIGHT
	menu._context.handle_key(step_right)
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.STRONG:
		failures.append("NORMAL did not step to STRONG")
	menu._context.handle_key(step_right)
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.STRONG:
		failures.append("STRONG wrapped past the end")
	var step_left := InputEventKey.new()
	step_left.pressed = true
	step_left.keycode = KEY_LEFT
	menu._context.handle_key(step_left)
	menu._context.handle_key(step_left)
	menu._context.handle_key(step_left)
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.OFF:
		failures.append("OFF did not stay clamped")
	menu._context.handle_key(step_right)
	if MatchSettings.screen_shake != MatchSettings.ScreenShake.NORMAL:
		failures.append("OFF did not return to NORMAL")
	if not is_equal_approx(MatchSettings.screen_shake_multiplier(), 1.0):
		failures.append("NORMAL is not the current combat shake")
	var visual = preload("res://scripts/combat_visual_root.gd").new()
	root.add_child(visual)
	MatchSettings.screen_shake = MatchSettings.ScreenShake.OFF
	visual._play_shake(visual.player_hit_shake_strength, visual.player_hit_shake_duration)
	if visual._shake_tween != null:
		failures.append("OFF still played a screen shake")
	MatchSettings.screen_shake = MatchSettings.ScreenShake.STRONG
	if not is_equal_approx(visual.player_hit_shake_strength * MatchSettings.screen_shake_multiplier(), 18.0):
		failures.append("STRONG is not 1.5 times the player hit shake")
	if not is_equal_approx(visual.player_hit_shake_duration, 0.15):
		failures.append("shake duration changed")
	MatchSettings.screen_shake = MatchSettings.ScreenShake.NORMAL
	visual.free()
	menu._context.open_kind(1)
	await create_timer(0.2).timeout
	var tutorial_text := ""
	var labels: Array[Node] = []
	_collect_labels(menu._context, labels)
	for child in labels:
		if (child as Label).text.find("아래 회피") >= 0:
			tutorial_text = (child as Label).text
	if tutorial_text == "" or tutorial_text.find("DUCK") >= 0 or tutorial_text.find("QUIT") >= 0:
		failures.append("tutorial controls do not match the live input")
	var backing_count := 0
	for child in menu._context.get_children():
		if str(child.name) == "Backing":
			backing_count += 1
	if backing_count != 1:
		failures.append("stale panel content remained")
	menu._context.close()
	if menu._context.is_open() or menu.selected_index != 2:
		failures.append("close did not return to the menu selection")
	var match_scene := menu._build_match(1)
	var mode_node = match_scene.get_node_or_null("GameMode")
	if mode_node == null or int(mode_node.mode) != 1:
		failures.append("match scene did not receive the selected GameMode")
	match_scene.free()
	await create_timer(0.16).timeout
	if menu._pointer.position.y + menu._pointer.size.y < options.position.y:
		failures.append("pointer did not follow OPTIONS")
	if failures.is_empty():
		print("SMOKE PASS: title menu")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _collect_labels(node: Node, labels: Array[Node]) -> void:
	if node is Label:
		labels.append(node)
	for child in node.get_children():
		_collect_labels(child, labels)
