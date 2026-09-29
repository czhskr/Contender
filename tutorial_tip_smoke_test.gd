extends SceneTree

## Tutorial tip bar: data list, page count, wrap, and panel ownership.
## godot --headless --path . -s res://tutorial_tip_smoke_test.gd

const MenuType = preload("res://scripts/title_menu.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var source := FileAccess.get_file_as_string("res://scripts/title_context_panel.gd")
	if source.find("1/8") >= 0 or source.find("1/9") >= 0 or source.find("tips.size()") < 0:
		failures.append("page count is hardcoded")
	var menu: MenuType = MenuType.new()
	root.add_child(menu)
	await process_frame
	var panel = menu._context
	if panel.tips.size() != 9:
		failures.append("initial tip count is not 9")
	if panel.tips[0] != "TIP: 가드로 공격을 막으면 스태미나가 감소합니다.":
		failures.append("first tip text is wrong")
	panel.open_kind(1)
	await process_frame
	if panel.current_kind() != 1 or panel.get_node_or_null("TipBar") == null:
		failures.append("tutorial open did not show the tip bar")
	if _text_of(panel, "조작법") == "" or _text_of(panel, "아래 회피") == "":
		failures.append("tutorial open did not show controls")
	if not is_equal_approx(panel.position.x, 620.0) or not is_equal_approx(panel.size.x, 460.0):
		failures.append("controls panel moved")
	var bar: Control = panel.get_node_or_null("TipBar")
	var bar_screen := bar.get_global_rect()
	if bar_screen.position.y < 540.0 or bar_screen.end.y > 648.0:
		failures.append("tip bar is not along the bottom")
	if bar_screen.position.x < 620.0 and bar_screen.end.y > 186.0 and bar_screen.position.y < 546.0:
		failures.append("tip bar overlaps the controls panel")
	if panel._tip_label.text != panel.tips[0]:
		failures.append("first tip is not shown")
	if panel._page_label.text != "1/%d" % panel.tips.size():
		failures.append("page is not 1 / tips.size()")
	if panel._tip_label.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		failures.append("tip text looks clickable")
	var total: int = panel.tips.size()
	await _step(panel, 1)
	if panel._tip_index != 1 or panel._tip_label.text != panel.tips[1]:
		failures.append("right did not advance")
	if panel._page_label.text != "2/%d" % total:
		failures.append("page did not become 2/N")
	await _step(panel, -1)
	if panel._tip_index != 0:
		failures.append("left did not go back")
	await _step(panel, -1)
	if panel._tip_index != total - 1 or panel._tip_label.text != panel.tips[total - 1]:
		failures.append("first tip did not wrap to the last")
	if panel._page_label.text != "%d/%d" % [total, total]:
		failures.append("wrapped page is not N/N")
	await _step(panel, 1)
	if panel._tip_index != 0:
		failures.append("last tip did not wrap to the first")
	var rest_x: float = panel._tip_rest.x
	panel._step_tip(1)
	await create_timer(0.04).timeout
	if panel._tip_label.position.x >= rest_x - 1.0:
		failures.append("right transition did not leave toward the left")
	await create_timer(0.2).timeout
	if absf(panel._tip_label.position.x - rest_x) > 1.0 or panel._tip_label.modulate.a < 0.95:
		failures.append("tip transition did not settle")
	if panel.TIP_MOVE < 0.12 or panel.TIP_MOVE > 0.18:
		failures.append("tip transition duration is outside 0.12-0.18")
	panel._tip_left.set_hovered(true)
	await create_timer(0.14).timeout
	if panel._tip_left.hover_mix < 0.9 or panel._tip_right.hover_mix > 0.05:
		failures.append("only the hovered arrow should light")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var before: int = panel._tip_index
	panel._tip_right._gui_input(click)
	await create_timer(0.22).timeout
	if panel._tip_index != posmod(before + 1, panel.tips.size()):
		failures.append("right arrow click did not advance")
	panel.tips.append("TIP: 추가 확인용 문장입니다.")
	panel._tip_index = 0
	panel._present_tip()
	if panel._page_label.text != "1/%d" % panel.tips.size() or panel.tips.size() != 10:
		failures.append("adding a tip did not raise N")
	var held := menu.selected_index
	var left := InputEventKey.new()
	left.pressed = true
	left.keycode = KEY_LEFT
	menu._unhandled_input(left)
	await create_timer(0.22).timeout
	if menu.selected_index != held:
		failures.append("tip keys moved the title menu")
	if panel._tip_index != panel.tips.size() - 1:
		failures.append("keyboard left did not wrap")
	panel.open_kind(0)
	await create_timer(0.28).timeout
	if panel.get_node_or_null("TipBar") != null or panel.current_kind() != 0:
		failures.append("START left the tip bar open")
	panel.open_kind(2)
	await create_timer(0.28).timeout
	if panel.get_node_or_null("TipBar") != null:
		failures.append("OPTIONS left the tip bar open")
	panel.open_kind(1)
	await create_timer(0.28).timeout
	if panel._tip_index != 0 or panel._tip_label == null or panel._tip_label.text != panel.tips[0]:
		failures.append("reopen did not start at tip 1")
	if panel._page_label.text != "1/%d" % panel.tips.size():
		failures.append("reopen page is not 1/N")
	panel.open_kind(1)
	await create_timer(0.28).timeout
	if panel.get_node_or_null("TipBar") != null or panel.is_open():
		failures.append("closing tutorial left the tip bar")
	if failures.is_empty():
		print("SMOKE PASS: tutorial tip bar")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _step(panel, delta: int) -> void:
	panel._step_tip(delta)
	await create_timer(0.22).timeout


func _text_of(node: Node, needle: String) -> String:
	if node is Label and (node as Label).text.find(needle) >= 0:
		return (node as Label).text
	for child in node.get_children():
		var found := _text_of(child, needle)
		if found != "":
			return found
	return ""
