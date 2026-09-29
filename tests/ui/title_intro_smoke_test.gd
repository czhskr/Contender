extends SceneTree

## Title logo intro and Korean title copy.
## godot --headless --path . -s res://tests/ui/title_intro_smoke_test.gd

const MenuType = preload("res://scripts/title_menu.gd")
const TransitionType = preload("res://scripts/page_transition.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	var final_position: Vector2 = menu._logo.position
	var final_size: Vector2 = menu._logo.size
	var aspect := final_size.x / final_size.y
	menu.play_intro()
	if not menu.is_intro_running():
		failures.append("intro did not start")
	var overlay := menu.get_node("IntroBlack") as ColorRect
	if overlay.color.a < 0.99:
		failures.append("first intro frame is not black")
	if menu._logo.modulate.a > 0.01:
		failures.append("logo is visible during the black hold")
	menu._activate_selected()
	if menu._context.is_open() or TransitionType.is_running():
		failures.append("intro allowed a panel or page wipe")
	await create_timer(0.52).timeout
	if not is_equal_approx(menu._logo.size.x / menu._logo.size.y, aspect):
		failures.append("large logo changed the aspect ratio")
	if menu._logo.size.x < final_size.x * 1.3:
		failures.append("large logo is not clearly bigger than the final logo")
	if menu.get_node("Background") == null:
		failures.append("background is missing")
	if overlay.color.a >= 0.98:
		failures.append("background fade did not start")
	await create_timer(2.55).timeout
	if menu.is_intro_running():
		failures.append("intro ran longer than 3.2 seconds")
	if menu._logo.position.distance_to(final_position) > 0.5 or menu._logo.size.distance_to(final_size) > 0.5:
		failures.append("logo did not land on its layout transform")
	if menu.selected_index != 0 or menu._context.is_open():
		failures.append("intro did not finish on 시작 with the panel closed")
	if menu._slabs[0].mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("menu input stayed locked after the intro")
	menu._activate_selected()
	if not menu._context.is_open() or menu._context.current_kind() != 0:
		failures.append("시작 did not open after the intro")
	_check_copy(menu, failures)
	if failures.is_empty():
		print("SMOKE PASS: title intro")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_copy(menu: MenuType, failures: Array[String]) -> void:
	menu._context.open_kind(1)
	await create_timer(0.2).timeout
	var texts: PackedStringArray = []
	_gather(menu._context, texts)
	for expected in ["조작법", "공격", "방어", "왼쪽 스트레이트", "오른쪽 스트레이트", "왼쪽 훅", "오른쪽 훅", "좌 / 우 회피", "아래 회피", "하이 가드", "J", "SHIFT + J", "A / D", "S", "SPACE"]:
		if not texts.has(expected):
			failures.append("missing tutorial text %s" % expected)
	var plate := menu._context.get_node("AttackPlate") as Control
	for child in plate.get_children():
		if child is Label:
			var label := child as Label
			var font := label.get_theme_default_font()
			var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			if label.position.x + width > plate.size.x - 16.0:
				failures.append("tutorial text clips: %s" % label.text)
	menu.show_title_immediately()
	menu._select_index(2)
	menu._activate_selected()
	await create_timer(0.2).timeout
	texts.clear()
	_gather(menu._context, texts)
	for expected in ["설정", "BGM", "SFX", "화면 흔들림", "보통"]:
		if not texts.has(expected):
			failures.append("missing options text %s" % expected)


func _gather(node: Node, texts: PackedStringArray) -> void:
	if node is Label:
		texts.append((node as Label).text)
	for child in node.get_children():
		_gather(child, texts)
