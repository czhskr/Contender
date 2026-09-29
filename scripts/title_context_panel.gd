extends Control

## Right-side title panels. One panel is visible, and only after activate.

signal match_requested(mode: int)

const GameModeType = preload("res://scripts/game_mode.gd")
const MatchSettings = preload("res://scripts/match_settings.gd")
const PageTransition = preload("res://scripts/page_transition.gd")

const PANEL_ORIGIN := Vector2(620, 186)
const PANEL_SIZE := Vector2(460, 360)
const OPTIONS_PANEL_SIZE := Vector2(460, 408)
const SLANT := 22.0
const STAGGER := 0.05
const SLIDE_TIME := 0.12
const EXIT_TIME := 0.12
const HOVER_TIME := 0.10
const BACKING := Color(0.05, 0.05, 0.07, 0.62)
const SECTION_BACKING := Color(0.04, 0.035, 0.05, 0.78)
const TEXT := Color(0.96, 0.95, 0.92, 1.0)
const DIM := Color(0.86, 0.84, 0.80, 0.96)
const TUTORIAL_KEY_X := 24.0
const TUTORIAL_ACTION_X := 132.0
const TIP_BAR_POS := Vector2(-580, 374)
const TIP_BAR_SIZE := Vector2(1072, 64)
const TIP_SHIFT := 16.0
const TIP_MOVE := 0.15

const TIPS_DEFAULT: PackedStringArray = [
	"TIP: 가드로 공격을 막으면 스태미나가 감소합니다.",
	"TIP: 가드로 공격을 막아 스태미나가 모두 소진되면 가드가 해제됩니다.",
	"TIP: 스태미나가 부족하면 공격할 수 없지만, 회피는 계속 사용할 수 있습니다.",
	"TIP: 공격하는 도중 상대의 펀치를 맞으면 더 큰 피해를 받습니다.",
	"TIP: 스태미나가 적을수록 상대의 공격에 더 큰 피해를 받습니다.",
	"TIP: 양손을 번갈아 공격하면 같은 손을 연속으로 사용하는 것보다 빠르게 공격할 수 있습니다.",
	"TIP: 회피는 상대의 공격 타이밍에 맞춰 사용해야 합니다.",
	"TIP: 다운에서 다시 일어나도 받은 피해가 완전히 회복되지는 않습니다.",
	"TIP: 특성 모드에서는 매 라운드 두 선수에게 새로운 특성이 적용됩니다.",
]

enum Kind { START, TUTORIAL, OPTIONS }

var _open := false
var _kind := Kind.START
var _inner_index := 0
var _keyboard_focus_visible := false
var _token := 0
var _tween: Tween
var _rows: Array[Control] = []
var tips: PackedStringArray = TIPS_DEFAULT.duplicate()
var _tip_index := 0
var _tip_token := 0
var _tip_label: Label
var _page_label: Label
var _tip_left: Control
var _tip_right: Control
var _tip_rest := Vector2.ZERO
var _tip_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = PANEL_ORIGIN
	size = PANEL_SIZE
	visible = false


func is_open() -> bool:
	return _open


func current_kind() -> int:
	return _kind


func inner_index() -> int:
	return _inner_index


func open_kind(kind: int) -> void:
	if PageTransition.is_running():
		return
	if _open and _kind == kind:
		close()
		return
	_token += 1
	var token := _token
	_kind = kind
	_inner_index = 0
	_keyboard_focus_visible = false
	_open = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if visible and get_child_count() > 0:
		_play_exit(token, func() -> void:
			if token != _token:
				return
			_rebuild()
		)
		return
	visible = true
	_rebuild()


func close() -> void:
	if not _open and not visible:
		return
	_token += 1
	var token := _token
	_open = false
	_set_rows_interactive(false)
	if get_child_count() == 0:
		visible = false
		return
	_play_exit(token, func() -> void:
		if token != _token:
			return
		_clear_content()
		visible = false
	)


func handle_key(key: InputEventKey) -> void:
	if not _open or PageTransition.is_running():
		return
	if _kind == Kind.TUTORIAL:
		if _is_horizontal(key, -1):
			_step_tip(-1)
		elif _is_horizontal(key, 1):
			_step_tip(1)
		return
	if _is_vertical(key, -1):
		_keyboard_focus_visible = true
		_focus_row(posmod(_inner_index - 1, _row_count()))
	elif _is_vertical(key, 1):
		_keyboard_focus_visible = true
		_focus_row(posmod(_inner_index + 1, _row_count()))
	elif _kind == Kind.OPTIONS and _is_horizontal(key, -1):
		_keyboard_focus_visible = true
		_nudge_option(-0.05)
	elif _kind == Kind.OPTIONS and _is_horizontal(key, 1):
		_keyboard_focus_visible = true
		_nudge_option(0.05)
	elif _kind == Kind.START and _is_accept(key):
		_confirm_mode()


func _row_count() -> int:
	if _kind == Kind.START:
		return 2
	if _kind == Kind.OPTIONS:
		return 4
	return 3


func _focus_row(index: int) -> void:
	if not _open or index == _inner_index:
		_refresh_rows()
		return
	_inner_index = index
	_refresh_rows()
	_ui_hover()


func _ui_hover() -> void:
	if get_tree() == null:
		return
	var audio = get_tree().root.get_node_or_null("AudioDirector")
	if audio != null and audio.has_method("play_ui_hover"):
		audio.play_ui_hover()


func _rebuild() -> void:
	_clear_content()
	var token := _token
	visible = true
	var panel_size := OPTIONS_PANEL_SIZE if _kind == Kind.OPTIONS else PANEL_SIZE
	size = panel_size
	var backing := PanelBacking.new()
	backing.name = "Backing"
	backing.position = Vector2.ZERO
	backing.size = panel_size
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)
	_rows.clear()
	if _kind == Kind.START:
		var title := _label(_title_text(), 26, TEXT)
		title.position = Vector2(36, 18)
		add_child(title)
		_add_mode_row(0, "일반", "기본 규칙으로 플레이합니다", Vector2(40, 88))
		_add_mode_row(1, "특성", "매 라운드 양 선수에게 특성이 적용됩니다", Vector2(40, 196))
	elif _kind == Kind.TUTORIAL:
		_add_tutorial()
	else:
		var title := _label(_title_text(), 26, TEXT)
		title.position = Vector2(36, 18)
		add_child(title)
		_add_option_row(0, "BGM", Vector2(40, 70))
		_add_option_row(1, "SFX", Vector2(40, 146))
		_add_choice_row(2, false, Vector2(40, 222))
		_add_choice_row(3, true, Vector2(40, 298))
	_refresh_rows()
	_play_entrance(token)


func _add_mode_row(index: int, title_text: String, detail: String, at: Vector2) -> void:
	var row := ModeRow.new()
	row.name = title_text
	row.index = index
	row.title_text = title_text
	row.detail = detail
	row.position = at
	row.size = Vector2(380, 78)
	row.pressed.connect(_on_mode_pressed)
	add_child(row)
	_rows.append(row)


func _add_option_row(index: int, title_text: String, at: Vector2) -> void:
	var row := OptionRow.new()
	row.index = index
	row.title_text = title_text
	row.position = at
	row.size = Vector2(380, 64)
	row.changed.connect(_on_option_changed)
	row.capture_started.connect(_on_slider_capture)
	add_child(row)
	_rows.append(row)


func _add_choice_row(nav_index: int, screen_shake: bool, at: Vector2) -> void:
	var row := ShakeRow.new()
	row.nav_index = nav_index
	row.screen_shake = screen_shake
	row.position = at
	row.size = Vector2(380, 64)
	row.stepped.connect(_on_choice_stepped)
	add_child(row)
	_rows.append(row)


func _on_choice_stepped(nav_index: int, delta: int) -> void:
	if not _open:
		return
	_inner_index = nav_index
	if nav_index == 2:
		MatchSettings.step_difficulty(delta)
	else:
		MatchSettings.step_screen_shake(delta)
	_refresh_rows()


func _add_tutorial() -> void:
	var title_plate := _add_section_plate("TitlePlate", Vector2(28, 8), Vector2(240, 52))
	var controls := _label("조작법", 26, TEXT)
	controls.position = Vector2(24, 10)
	title_plate.add_child(controls)
	var attack := _add_section_plate("AttackPlate", Vector2(28, 68), Vector2(404, 148))
	var attack_title := _label("공격", 18, TEXT)
	attack_title.position = Vector2(22, 8)
	attack.add_child(attack_title)
	_add_control_line(attack, "J", "왼쪽 스트레이트", 38)
	_add_control_line(attack, "K", "오른쪽 스트레이트", 64)
	_add_control_line(attack, "SHIFT + J", "왼쪽 훅", 90)
	_add_control_line(attack, "SHIFT + K", "오른쪽 훅", 116)
	var defense := _add_section_plate("DefensePlate", Vector2(28, 224), Vector2(404, 124))
	var defense_title := _label("방어", 18, TEXT)
	defense_title.position = Vector2(22, 8)
	defense.add_child(defense_title)
	_add_control_line(defense, "A / D", "좌 / 우 회피", 40)
	_add_control_line(defense, "S", "아래 회피", 66)
	_add_control_line(defense, "SPACE", "하이 가드", 92)
	_tip_index = 0
	_add_tip_bar()


func _add_tip_bar() -> void:
	var bar := TipBar.new()
	bar.name = "TipBar"
	bar.position = TIP_BAR_POS
	bar.size = TIP_BAR_SIZE
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var left := ShakeArrow.new()
	left.direction = -1
	left.position = Vector2(18, 12)
	left.size = Vector2(40, 40)
	left.step_requested.connect(_step_tip)
	bar.add_child(left)
	var right := ShakeArrow.new()
	right.direction = 1
	right.position = Vector2(TIP_BAR_SIZE.x - 58, 12)
	right.size = Vector2(40, 40)
	right.step_requested.connect(_step_tip)
	bar.add_child(right)
	var page := _label("", 16, TEXT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.position = Vector2(TIP_BAR_SIZE.x - 148, 20)
	page.size = Vector2(72, 28)
	page.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(page)
	var line := _label("", 16, TEXT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = Vector2(78, 18)
	line.size = Vector2(TIP_BAR_SIZE.x - 260, 28)
	line.clip_text = true
	bar.add_child(line)
	_tip_label = line
	_page_label = page
	_tip_left = left
	_tip_right = right
	_tip_rest = line.position
	_present_tip()


func _step_tip(delta: int) -> void:
	if _kind != Kind.TUTORIAL or not _open or tips.is_empty() or _tip_label == null:
		return
	_ui_hover()
	_tip_token += 1
	var token := _tip_token
	var label := _tip_label
	var rest := _tip_rest
	var outgoing := rest + Vector2(-TIP_SHIFT if delta > 0 else TIP_SHIFT, 0)
	var incoming := rest + Vector2(TIP_SHIFT if delta > 0 else -TIP_SHIFT, 0)
	if _tip_tween != null and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_property(label, "position", outgoing, TIP_MOVE * 0.4)
	_tip_tween.parallel().tween_property(label, "modulate:a", 0.0, TIP_MOVE * 0.4)
	_tip_tween.tween_callback(func() -> void:
		if token != _tip_token or label != _tip_label:
			return
		_tip_index = posmod(_tip_index + delta, tips.size())
		label.text = tips[_tip_index]
		_refresh_tip_page()
		label.position = incoming
		label.modulate.a = 0.0
	)
	_tip_tween.tween_property(label, "position", rest, TIP_MOVE * 0.6)
	_tip_tween.parallel().tween_property(label, "modulate:a", 1.0, TIP_MOVE * 0.6)


func _present_tip() -> void:
	if _tip_label == null or tips.is_empty():
		return
	_tip_index = posmod(_tip_index, tips.size())
	_tip_label.text = tips[_tip_index]
	_tip_label.position = _tip_rest
	_tip_label.modulate.a = 1.0
	_refresh_tip_page()


func _refresh_tip_page() -> void:
	if _page_label == null or tips.is_empty():
		return
	_page_label.text = "%d/%d" % [_tip_index + 1, tips.size()]


func _add_section_plate(node_name: String, at: Vector2, plate_size: Vector2) -> Control:
	var plate := SectionPlate.new()
	plate.name = node_name
	plate.position = at
	plate.size = plate_size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	return plate


func _add_control_line(parent: Control, key_text: String, action_text: String, y: float) -> void:
	var key := _label(key_text, 16, TEXT)
	key.set_meta("column", "key")
	key.position = Vector2(22, y)
	parent.add_child(key)
	var action := _label(action_text, 16, DIM)
	action.set_meta("column", "action")
	action.position = Vector2(22 + TUTORIAL_ACTION_X, y)
	parent.add_child(action)


func _title_text() -> String:
	if _kind == Kind.START:
		return "게임 모드"
	if _kind == Kind.TUTORIAL:
		return "조작법"
	return "설정"


func _refresh_rows() -> void:
	var mouse_pointing := false
	for row in _rows:
		if is_instance_valid(row) and row.has_method("is_pointing") and row.is_pointing():
			mouse_pointing = true
	for row in _rows:
		if not is_instance_valid(row):
			continue
		if row is ModeRow:
			var mode := row as ModeRow
			mode.selected = mode.index == _inner_index
			mode.keyboard_lit = _keyboard_focus_visible and not mouse_pointing and mode.selected
			row.queue_redraw()
		elif row is OptionRow:
			var option := row as OptionRow
			option.selected = option.index == _inner_index
			option.keyboard_lit = _keyboard_focus_visible and not mouse_pointing and option.selected
			option.value = _option_value(option.index)
			row.queue_redraw()
		elif row is ShakeRow:
			var shake := row as ShakeRow
			shake.selected = _inner_index == shake.nav_index
			shake.keyboard_lit = _keyboard_focus_visible and not mouse_pointing and shake.selected
			shake.sync()


func _sync_row_highlight() -> void:
	_refresh_rows()


func _option_value(index: int) -> float:
	if index == 0:
		return MatchSettings.bgm_volume
	return MatchSettings.sfx_volume


func _set_option(index: int, value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if index == 0:
		MatchSettings.bgm_volume = next
	elif index == 1:
		MatchSettings.sfx_volume = next
	_refresh_rows()


func _nudge_option(delta: float) -> void:
	if _inner_index == 2:
		MatchSettings.step_difficulty(-1 if delta < 0.0 else 1)
		_refresh_rows()
		return
	if _inner_index == 3:
		MatchSettings.step_screen_shake(-1 if delta < 0.0 else 1)
		_refresh_rows()
		return
	_set_option(_inner_index, _option_value(_inner_index) + delta)


func _on_mode_pressed(index: int) -> void:
	if not _open or PageTransition.is_running():
		return
	_inner_index = index
	_confirm_mode()


func _confirm_mode() -> void:
	if not _open or _kind != Kind.START or PageTransition.is_running():
		return
	_refresh_rows()
	if _inner_index >= 0 and _inner_index < _rows.size() and _rows[_inner_index] is ModeRow:
		(_rows[_inner_index] as ModeRow).confirm_punch()
	match_requested.emit(GameModeType.Mode.NORMAL if _inner_index == 0 else GameModeType.Mode.TRAIT)


func _on_option_changed(index: int, value: float) -> void:
	if not _open:
		return
	_inner_index = index
	_set_option(index, value)


func _on_slider_capture(index: int) -> void:
	for row in _rows:
		if row is OptionRow and (row as OptionRow).index != index:
			(row as OptionRow).end_drag()


func _set_rows_interactive(enabled: bool) -> void:
	for row in _rows:
		if not is_instance_valid(row):
			continue
		if row is OptionRow:
			if not enabled:
				(row as OptionRow).end_drag()
		if row.has_method("set_input_enabled"):
			row.set_input_enabled(enabled)


func _play_entrance(token: int) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var order := 0
	for child in get_children():
		var control := child as Control
		if control == null:
			continue
		var rest := control.position
		control.position = rest + Vector2(22.0, 8.0)
		control.modulate.a = 0.0
		var delay := STAGGER * order
		_tween.parallel().tween_property(control, "position", rest, SLIDE_TIME).set_delay(delay)
		_tween.parallel().tween_property(control, "modulate:a", 1.0, SLIDE_TIME).set_delay(delay)
		order += 1
	_tween.finished.connect(func() -> void:
		if token != _token:
			return
	)


func _play_exit(token: int, done: Callable) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_set_rows_interactive(false)
	_tween = create_tween()
	var found := false
	for child in get_children():
		var control := child as Control
		if control == null:
			continue
		found = true
		var rest := control.position
		_tween.parallel().tween_property(control, "position", rest + Vector2(28.0, 6.0), EXIT_TIME)
		_tween.parallel().tween_property(control, "modulate:a", 0.0, EXIT_TIME)
	if not found:
		done.call()
		return
	_tween.finished.connect(func() -> void:
		if token != _token:
			return
		done.call()
	)


func _clear_content() -> void:
	_tip_token += 1
	if _tip_tween != null and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = null
	_tip_label = null
	_page_label = null
	_tip_left = null
	_tip_right = null
	for child in get_children():
		child.free()
	_rows.clear()


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _is_vertical(key: InputEventKey, step: int) -> bool:
	var up := key.keycode == KEY_UP or key.keycode == KEY_W or key.physical_keycode == KEY_UP or key.physical_keycode == KEY_W
	var down := key.keycode == KEY_DOWN or key.keycode == KEY_S or key.physical_keycode == KEY_DOWN or key.physical_keycode == KEY_S
	return up if step < 0 else down


func _is_horizontal(key: InputEventKey, step: int) -> bool:
	var left := key.keycode == KEY_LEFT or key.keycode == KEY_A or key.physical_keycode == KEY_LEFT or key.physical_keycode == KEY_A
	var right := key.keycode == KEY_RIGHT or key.keycode == KEY_D or key.physical_keycode == KEY_RIGHT or key.physical_keycode == KEY_D
	return left if step < 0 else right


func _is_accept(key: InputEventKey) -> bool:
	return key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE or key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_SPACE


class PanelBacking:
	extends Control

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(28.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 28.0, size.y),
			Vector2(0.0, size.y),
		]), BACKING)


class SectionPlate:
	extends Control

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(16.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 16.0, size.y),
			Vector2(0.0, size.y),
		]), SECTION_BACKING)


class TipBar:
	extends Control

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(22.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 22.0, size.y),
			Vector2(0.0, size.y),
		]), Color(0.05, 0.05, 0.07, 0.78))


class ModeRow:
	extends Control

	signal pressed(index: int)

	var index := 0
	var title_text := ""
	var detail := ""
	var selected := false
	var keyboard_lit := false
	var hover_mix := 0.0
	var _pointer_inside := false
	var _title: Label
	var _detail: Label
	var _hover_tween: Tween


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: set_hovered(true))
		mouse_exited.connect(func() -> void: set_hovered(false))
		_title = Label.new()
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title.position = Vector2(28, 8)
		_title.add_theme_font_size_override("font_size", 22)
		_title.text = title_text
		add_child(_title)
		_detail = Label.new()
		_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail.position = Vector2(28, 40)
		_detail.add_theme_font_size_override("font_size", 14)
		_detail.size = Vector2(324, 28)
		_detail.clip_text = true
		_detail.text = detail
		add_child(_detail)
		_paint()


	func set_input_enabled(enabled: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


	func set_hovered(hovered: bool) -> void:
		var entered := hovered and not _pointer_inside
		_pointer_inside = hovered
		_tween_hover(1.0 if hovered else 0.0)
		_notify_highlight()
		if entered:
			var panel = get_parent()
			if panel != null and panel.has_method("_ui_hover"):
				panel._ui_hover()


	func is_pointing() -> bool:
		return _pointer_inside


	func _notify_highlight() -> void:
		var panel := get_parent()
		if panel != null and panel.has_method("_sync_row_highlight"):
			panel._sync_row_highlight()


	func _tween_hover(target: float) -> void:
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		if not is_inside_tree():
			hover_mix = target
			queue_redraw()
			return
		_hover_tween = create_tween()
		_hover_tween.tween_method(_set_hover_mix, hover_mix, target, HOVER_TIME)


	func _set_hover_mix(next: float) -> void:
		hover_mix = next
		queue_redraw()


	func _process(_delta: float) -> void:
		if _hover_tween != null and _hover_tween.is_valid():
			queue_redraw()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(index)
			accept_event()


	func _light_amount() -> float:
		if _pointer_inside:
			return hover_mix
		if keyboard_lit:
			return 1.0
		return 0.0


	func _draw() -> void:
		var dark := Color(0.07, 0.06, 0.08, 0.9)
		var light := Color(0.95, 0.93, 0.88, 1.0)
		var color := dark.lerp(light, _light_amount())
		draw_colored_polygon(PackedVector2Array([
			Vector2(18.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 18.0, size.y),
			Vector2(0.0, size.y),
		]), color)
		_paint()


	func confirm_punch() -> void:
		if not is_inside_tree():
			return
		pivot_offset = size * 0.5
		scale = Vector2.ONE
		modulate = Color(1.22, 1.18, 1.12)
		var motion := create_tween()
		motion.tween_property(self, "scale", Vector2(1.035, 1.035), 0.05)
		motion.parallel().tween_property(self, "modulate", Color.WHITE, 0.05)
		motion.tween_property(self, "scale", Vector2.ONE, 0.05)


	func _paint() -> void:
		var amount := _light_amount()
		var ink := Color(0.97, 0.96, 0.93).lerp(Color(0.08, 0.07, 0.09), amount)
		var sub := Color(0.78, 0.76, 0.72).lerp(Color(0.28, 0.26, 0.24), amount)
		if _title != null:
			_title.add_theme_color_override("font_color", ink)
		if _detail != null:
			_detail.add_theme_color_override("font_color", sub)


class OptionRow:
	extends Control

	signal changed(index: int, value: float)
	signal capture_started(index: int)

	const TRACK_LEFT := 22.0
	const TRACK_END_PAD := 22.0
	const TRACK_Y := 46.0
	const HIT_PAD_Y := 14.0
	const HIT_PAD_X := 10.0

	var index := 0
	var title_text := ""
	var value := 1.0
	var selected := false
	var keyboard_lit := false
	var hover_mix := 0.0
	var _title: Label
	var _amount: Label
	var _dragging := false
	var _pointer_inside := false
	var _hovering := false
	var _hover_tween: Tween


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process_input(false)
		mouse_entered.connect(func() -> void:
			_pointer_inside = true
			set_hovered(true)
		)
		mouse_exited.connect(func() -> void:
			_pointer_inside = false
			if not _dragging:
				set_hovered(false)
		)
		_title = Label.new()
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title.position = Vector2(24, 8)
		_title.add_theme_font_size_override("font_size", 18)
		_title.text = title_text
		add_child(_title)
		_amount = Label.new()
		_amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_amount.position = Vector2(286, 8)
		_amount.size = Vector2(70, 24)
		_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_amount.add_theme_font_size_override("font_size", 18)
		add_child(_amount)
		_paint()


	func track_left() -> float:
		return TRACK_LEFT


	func track_right() -> float:
		return size.x - TRACK_END_PAD


	func track_hit_rect() -> Rect2:
		var top := TRACK_Y - HIT_PAD_Y
		return Rect2(
			track_left() - HIT_PAD_X,
			top,
			(track_right() - track_left()) + HIT_PAD_X * 2.0,
			HIT_PAD_Y * 2.0
		)


	func value_from_x(local_x: float) -> float:
		var span := maxf(track_right() - track_left(), 1.0)
		return clampf((local_x - track_left()) / span, 0.0, 1.0)


	func is_dragging() -> bool:
		return _dragging


	func set_input_enabled(enabled: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		if not enabled:
			end_drag()


	func begin_drag(local_x: float) -> void:
		_dragging = true
		set_process_input(true)
		set_hovered(true)
		capture_started.emit(index)
		_emit_at(local_x)


	func drag_to(local_x: float) -> void:
		if not _dragging:
			return
		_emit_at(local_x)


	func end_drag() -> void:
		if not _dragging:
			return
		_dragging = false
		set_process_input(false)
		if not _pointer_inside:
			set_hovered(false)
		queue_redraw()


	func note_pointer_exit() -> void:
		_pointer_inside = false
		if not _dragging:
			set_hovered(false)


	func set_hovered(hovered: bool) -> void:
		var entered := hovered and not _hovering
		_hovering = hovered
		_tween_hover(1.0 if hovered else 0.0)
		if entered:
			var panel = get_parent()
			if panel != null and panel.has_method("_ui_hover"):
				panel._ui_hover()
		_notify_highlight()


	func is_pointing() -> bool:
		return _hovering or _dragging


	func _notify_highlight() -> void:
		var panel := get_parent()
		if panel != null and panel.has_method("_sync_row_highlight"):
			panel._sync_row_highlight()


	func _tween_hover(target: float) -> void:
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		if not is_inside_tree():
			hover_mix = target
			queue_redraw()
			return
		_hover_tween = create_tween()
		_hover_tween.tween_method(_set_hover_mix, hover_mix, target, HOVER_TIME)


	func _set_hover_mix(next: float) -> void:
		hover_mix = next
		queue_redraw()


	func _process(_delta: float) -> void:
		if _dragging or (_hover_tween != null and _hover_tween.is_valid()):
			queue_redraw()


	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
			return
		if not track_hit_rect().has_point(button.position):
			return
		begin_drag(button.position.x)
		accept_event()


	func _input(event: InputEvent) -> void:
		if not _dragging:
			return
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
				end_drag()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			_emit_at(get_local_mouse_position().x)
			get_viewport().set_input_as_handled()


	func _emit_at(local_x: float) -> void:
		changed.emit(index, value_from_x(local_x))


	func _light_amount() -> float:
		if is_pointing():
			return hover_mix
		if keyboard_lit:
			return 1.0
		return 0.0


	func _draw() -> void:
		var dark := Color(0.07, 0.06, 0.08, 0.9)
		var light := Color(0.95, 0.93, 0.88, 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(16.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 16.0, size.y),
			Vector2(0.0, size.y),
		]), dark.lerp(light, _light_amount()))
		_draw_track()
		_paint()


	func _draw_track() -> void:
		var left := track_left()
		var right := track_right()
		var y := TRACK_Y
		var lit := _light_amount() > 0.45
		var empty := Color(0.18, 0.16, 0.18, 1.0) if lit else Color(0.55, 0.52, 0.48, 0.95)
		var fill := Color(0.07, 0.06, 0.08, 1.0) if lit else Color(0.95, 0.93, 0.88, 1.0)
		if _dragging:
			fill = Color(0.02, 0.02, 0.03) if lit else Color(1.0, 0.98, 0.94)
		_draw_slanted(left, right, y - 4.0, y + 5.0, 5.0, empty)
		var tip := lerpf(left, right, value)
		if tip > left + 0.5:
			_draw_slanted(left, tip, y - 4.0, y + 5.0, 5.0, fill)
		var cap := Color(0.08, 0.07, 0.09) if lit else Color(0.97, 0.96, 0.93)
		draw_line(Vector2(left, y - 7.0), Vector2(left, y + 8.0), cap, 2.0)
		draw_line(Vector2(right, y - 7.0), Vector2(right, y + 8.0), cap, 2.0)
		_draw_handle(tip, y, fill, lit)


	func _draw_handle(center_x: float, center_y: float, fill: Color, ink_dark: bool) -> void:
		var half_w := 5.0
		var half_h := 9.0
		if _dragging:
			half_h = 11.0
		var shear := 4.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(center_x - half_w + shear, center_y - half_h),
			Vector2(center_x + half_w + shear, center_y - half_h),
			Vector2(center_x + half_w, center_y + half_h),
			Vector2(center_x - half_w, center_y + half_h),
		]), Color(0.02, 0.02, 0.025, 0.9) if not ink_dark else Color(0.97, 0.96, 0.93, 0.95))
		draw_colored_polygon(PackedVector2Array([
			Vector2(center_x - half_w + shear + 1.5, center_y - half_h + 1.5),
			Vector2(center_x + half_w + shear - 1.5, center_y - half_h + 1.5),
			Vector2(center_x + half_w - 1.5, center_y + half_h - 1.5),
			Vector2(center_x - half_w + 1.5, center_y + half_h - 1.5),
		]), fill)


	func _draw_slanted(left: float, right: float, top: float, bottom: float, shear: float, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(left + shear, top),
			Vector2(right + shear, top),
			Vector2(right, bottom),
			Vector2(left, bottom),
		]), color)


	func _paint() -> void:
		var ink := Color(0.97, 0.96, 0.93).lerp(Color(0.08, 0.07, 0.09), _light_amount())
		if _title != null:
			_title.add_theme_color_override("font_color", ink)
		if _amount != null:
			_amount.text = "%d%%" % int(round(value * 100.0))
			_amount.add_theme_color_override("font_color", ink)


class ShakeRow:
	extends Control

	signal stepped(nav_index: int, delta: int)

	const ARROW_SIZE := Vector2(40, 40)
	const VALUE_ORIGIN := Vector2(214, 12)
	const VALUE_SIZE := Vector2(100, 40)

	var selected := false
	var keyboard_lit := false
	var nav_index := 3
	var screen_shake := true
	var hover_mix := 0.0
	var _pointer_inside := false
	var _arrow_hover := 0
	var _hovering := false
	var _hover_tween: Tween
	var _title: Label
	var _value: Label
	var _left: ShakeArrow
	var _right: ShakeArrow


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_pointer_inside = true
			set_hovered(true)
		)
		mouse_exited.connect(func() -> void:
			_pointer_inside = false
			set_hovered(_arrow_hover > 0)
		)
		_title = Label.new()
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title.position = Vector2(24, 18)
		_title.add_theme_font_size_override("font_size", 18)
		_title.text = "화면 흔들림" if screen_shake else "난이도"
		add_child(_title)
		_left = _make_arrow(-1, Vector2(168, 12))
		_value = Label.new()
		_value.name = "ShakeValue"
		_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_value.position = VALUE_ORIGIN
		_value.size = VALUE_SIZE
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_value.add_theme_font_size_override("font_size", 16)
		add_child(_value)
		_right = _make_arrow(1, Vector2(320, 12))
		_paint()


	func value_center() -> Vector2:
		return _value.position + _value.size * 0.5


	func sync() -> void:
		queue_redraw()
		_paint()


	func left_arrow() -> ShakeArrow:
		return _left


	func right_arrow() -> ShakeArrow:
		return _right


	func set_input_enabled(enabled: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		_left.set_input_enabled(enabled)
		_right.set_input_enabled(enabled)


	func _make_arrow(direction: int, at: Vector2) -> ShakeArrow:
		var arrow := ShakeArrow.new()
		arrow.direction = direction
		arrow.position = at
		arrow.size = ARROW_SIZE
		arrow.custom_minimum_size = ARROW_SIZE
		arrow.step_requested.connect(_on_arrow)
		arrow.hover_changed.connect(_on_arrow_hover)
		add_child(arrow)
		return arrow


	func _on_arrow_hover(on: bool) -> void:
		_arrow_hover = maxi(0, _arrow_hover + (1 if on else -1))
		set_hovered(_pointer_inside or _arrow_hover > 0)


	func set_hovered(hovered: bool) -> void:
		var entered := hovered and not _hovering
		_hovering = hovered
		var target := 1.0 if hovered else 0.0
		if entered:
			var panel = get_parent()
			if panel != null and panel.has_method("_ui_hover"):
				panel._ui_hover()
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		if not is_inside_tree():
			hover_mix = target
			queue_redraw()
		else:
			_hover_tween = create_tween()
			_hover_tween.tween_method(_set_hover_mix, hover_mix, target, HOVER_TIME)
		_notify_highlight()


	func is_pointing() -> bool:
		return _hovering or _arrow_hover > 0


	func _notify_highlight() -> void:
		var panel := get_parent()
		if panel != null and panel.has_method("_sync_row_highlight"):
			panel._sync_row_highlight()


	func _set_hover_mix(next: float) -> void:
		hover_mix = next
		queue_redraw()
		_paint()


	func _light_amount() -> float:
		if is_pointing():
			return maxf(hover_mix, 1.0 if _arrow_hover > 0 else hover_mix)
		if keyboard_lit:
			return 1.0
		return 0.0


	func _on_arrow(direction: int) -> void:
		stepped.emit(nav_index, direction)


	func _draw() -> void:
		var dark := Color(0.07, 0.06, 0.08, 0.9)
		var light := Color(0.95, 0.93, 0.88, 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(16.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 16.0, size.y),
			Vector2(0.0, size.y),
		]), dark.lerp(light, _light_amount()))
		_paint()


	func _paint() -> void:
		var level: int = MatchSettings.screen_shake if screen_shake else MatchSettings.difficulty
		var ink := Color(0.97, 0.96, 0.93).lerp(Color(0.08, 0.07, 0.09), _light_amount())
		if _title != null:
			_title.text = "화면 흔들림" if screen_shake else "난이도"
			_title.add_theme_color_override("font_color", ink)
		if _value != null:
			_value.text = _choice_text()
			_value.add_theme_color_override("font_color", ink)
		var lit := _light_amount() > 0.45
		var floor: int = MatchSettings.ScreenShake.OFF if screen_shake else MatchSettings.Difficulty.EASY
		var ceiling: int = MatchSettings.ScreenShake.STRONG if screen_shake else MatchSettings.Difficulty.HARD
		if _left != null:
			_left.enabled = level > floor
			_left.on_light_row = lit
			_left.queue_redraw()
		if _right != null:
			_right.enabled = level < ceiling
			_right.on_light_row = lit
			_right.queue_redraw()


	func _choice_text() -> String:
		if screen_shake:
			return _shake_text()
		return MatchSettings.difficulty_label()


	func _shake_text() -> String:
		match MatchSettings.screen_shake:
			MatchSettings.ScreenShake.OFF:
				return "끄기"
			MatchSettings.ScreenShake.STRONG:
				return "강함"
			_:
				return "보통"


class ShakeArrow:
	extends Control

	signal step_requested(direction: int)
	signal hover_changed(on: bool)

	var direction := -1
	var enabled := true
	var on_light_row := false
	var hover_mix := 0.0
	var _hover_tween: Tween
	var _hovered := false


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			if enabled:
				set_hovered(true)
		)
		mouse_exited.connect(func() -> void: set_hovered(false))


	func set_input_enabled(next: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if next else Control.MOUSE_FILTER_IGNORE


	func set_hovered(hovered: bool) -> void:
		if not enabled:
			hovered = false
		var entered := hovered and not _hovered
		_hovered = hovered
		if entered:
			var host = get_parent()
			while host != null and not host.has_method("_ui_hover"):
				host = host.get_parent()
			if host != null:
				host._ui_hover()
		hover_changed.emit(hovered)
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		if not is_inside_tree():
			hover_mix = 1.0 if hovered else 0.0
			queue_redraw()
			return
		_hover_tween = create_tween()
		_hover_tween.tween_method(_set_hover_mix, hover_mix, 1.0 if hovered else 0.0, HOVER_TIME)


	func _set_hover_mix(next: float) -> void:
		hover_mix = next
		queue_redraw()


	func _process(_delta: float) -> void:
		if _hover_tween != null and _hover_tween.is_valid():
			queue_redraw()


	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
			return
		accept_event()
		if not enabled:
			return
		_punch()
		step_requested.emit(direction)


	func _punch() -> void:
		if not is_inside_tree():
			return
		pivot_offset = size * 0.5
		var motion := create_tween()
		motion.tween_property(self, "scale", Vector2(0.92, 0.92), 0.04)
		motion.tween_property(self, "scale", Vector2.ONE, 0.05)


	func _draw() -> void:
		var fill := Color(0.22, 0.20, 0.22, 1.0)
		var glyph := Color(0.97, 0.96, 0.93)
		if on_light_row:
			fill = Color(0.16, 0.14, 0.15, 1.0)
			glyph = Color(0.97, 0.96, 0.93)
		if not enabled:
			fill = Color(0.45, 0.42, 0.40, 0.45) if on_light_row else Color(0.10, 0.09, 0.10, 0.85)
			glyph = Color(0.55, 0.52, 0.50, 0.7)
			hover_mix = 0.0
		elif hover_mix > 0.0:
			var hot := Color(0.95, 0.93, 0.88) if not on_light_row else Color(0.06, 0.05, 0.06)
			fill = fill.lerp(hot, hover_mix)
			glyph = Color(0.08, 0.07, 0.09) if not on_light_row else Color(0.97, 0.96, 0.93)
		draw_colored_polygon(PackedVector2Array([
			Vector2(8.0, 2.0),
			Vector2(size.x - 2.0, 2.0),
			Vector2(size.x - 8.0, size.y - 2.0),
			Vector2(2.0, size.y - 2.0),
		]), fill)
		var mid := size * 0.5
		var tip := Vector2(14.0 if direction < 0 else size.x - 14.0, mid.y)
		var tail_x := size.x - 14.0 if direction < 0 else 14.0
		draw_colored_polygon(PackedVector2Array([
			tip,
			Vector2(tail_x, mid.y - 7.0),
			Vector2(tail_x, mid.y + 7.0),
		]), glyph)
