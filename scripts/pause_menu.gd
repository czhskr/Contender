extends CanvasLayer

## Combat pause. The resume countdown runs only after a real fighting pause.

const PageTransition = preload("res://scripts/page_transition.gd")
const Rounds = preload("res://scripts/round_manager.gd")
const Knockdown = preload("res://scripts/knockdown_manager.gd")
const Settings = preload("res://scripts/match_settings.gd")
const CursorPolicy = preload("res://scripts/cursor_policy.gd")

const VIEW := Vector2(1152, 648)
const SLAB_SIZE := Vector2(340, 66)
const GAP := 16.0
const SLANT := 22.0
const SLAB_DARK := Color(0.07, 0.06, 0.08, 0.94)
const SLAB_LIGHT := Color(0.95, 0.93, 0.88, 1.0)
const TEXT_LIGHT := Color(0.97, 0.96, 0.93, 1.0)
const TEXT_DARK := Color(0.08, 0.07, 0.09, 1.0)
const COUNT_STEP := 1.0

const MAIN: PackedStringArray = ["재개", "옵션", "나가기"]

var open := false
var options_open := false
var counting := false
var waiting_fight := false
var from_fighting := false
var selected := 0
var option_index := 0

var _overlay: ColorRect
var _main: Control
var _options: Control
var _buttons: Array[Control] = []
var _option_rows: Array[Control] = []
var _step := 0
var _step_left := 0.0
var _saved_announcement_mode := Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if _is_escape(key):
		_on_escape()
		get_viewport().set_input_as_handled()
		return
	if not open or counting or waiting_fight:
		return
	if options_open:
		_option_key(key)
	elif _is_up(key):
		_select_main(selected - 1)
	elif _is_down(key):
		_select_main(selected + 1)
	elif _is_accept(key):
		_activate_main()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not counting:
		return
	_step_left -= delta
	if _step_left > 0.0:
		return
	if _step > 1:
		_step -= 1
		_show_step()
		return
	_begin_fight_banner()


func _on_escape() -> void:
	if counting or waiting_fight:
		return
	if options_open:
		_close_options()
		return
	if open:
		_resume()
		return
	if _can_pause():
		_open()


func _can_pause() -> bool:
	if get_tree().paused or PageTransition.is_running():
		return false
	var rounds = _rounds()
	var knockdown = _knockdown()
	if rounds == null or knockdown == null:
		return false
	if rounds.round_state == Rounds.RoundState.IDLE or rounds.round_state == Rounds.RoundState.MATCH_FINISHED or rounds.round_state == Rounds.RoundState.DECISION_REQUIRED:
		return false
	if knockdown.match_state == Knockdown.MatchState.FINAL_KO:
		return false
	var parent := get_parent()
	if parent != null and parent.get("_result_payload") != null:
		return false
	var finisher = _finisher()
	if finisher != null and finisher.has_method("is_blocking_combat") and finisher.is_blocking_combat():
		return false
	return true


func _is_actual_fighting() -> bool:
	var rounds = _rounds()
	var knockdown = _knockdown()
	if rounds == null or knockdown == null:
		return false
	if rounds.round_state != Rounds.RoundState.FIGHTING or rounds.timer_paused:
		return false
	if knockdown.match_state != Knockdown.MatchState.FIGHTING:
		return false
	var finisher = _finisher()
	if finisher != null and finisher.has_method("is_blocking_combat") and finisher.is_blocking_combat():
		return false
	return true


func _open() -> void:
	from_fighting = _is_actual_fighting()
	open = true
	options_open = false
	selected = 0
	visible = true
	_overlay.visible = true
	_main.visible = true
	_options.visible = false
	_select_main(0, false)
	get_tree().paused = true
	var audio = _audio()
	if audio != null:
		audio.suspend_gameplay_audio()
	CursorPolicy.show_pointer()


func _resume() -> void:
	var fighting := from_fighting
	_hide_menu()
	var audio = _audio()
	if audio != null:
		audio.resume_gameplay_audio()
	if not fighting:
		CursorPolicy.hide_pointer()
		get_tree().paused = false
		return
	CursorPolicy.hide_pointer()
	_arm_countdown()


func _arm_countdown() -> void:
	var banner = _banner()
	if banner != null:
		_saved_announcement_mode = banner.process_mode
		banner.process_mode = Node.PROCESS_MODE_ALWAYS
	counting = true
	waiting_fight = false
	_step = 3
	_show_step()


func _show_step() -> void:
	_step_left = COUNT_STEP
	var banner = _banner()
	if banner != null and banner.has_method("show_count"):
		banner.show_count(_step)
	var audio = _audio()
	if audio != null:
		audio.play_resume_count(_step)


func _begin_fight_banner() -> void:
	counting = false
	waiting_fight = true
	var banner = _banner()
	if banner == null or not banner.has_method("play_fight"):
		_finish_resume()
		return
	if banner.has_signal("pass_finished") and not banner.pass_finished.is_connected(_on_fight_finished):
		banner.pass_finished.connect(_on_fight_finished)
	banner.play_fight(false)


func _on_fight_finished(text: String) -> void:
	if text != "FIGHT" or not waiting_fight:
		return
	_finish_resume()


func _finish_resume() -> void:
	waiting_fight = false
	counting = false
	var banner = _banner()
	if banner != null:
		banner.process_mode = _saved_announcement_mode
	visible = false
	get_tree().paused = false


func _activate_main() -> void:
	if selected == 0:
		_resume()
	elif selected == 1:
		_open_options()
	else:
		_exit_match()


func _open_options() -> void:
	options_open = true
	option_index = 0
	_main.visible = false
	_options.visible = true
	_select_option(0, false)


func _close_options() -> void:
	options_open = false
	_options.visible = false
	_main.visible = true
	_select_main(selected, false)


func _exit_match() -> void:
	open = false
	options_open = false
	counting = false
	waiting_fight = false
	visible = false
	var audio = _audio()
	if audio != null and audio.has_method("abandon_match_audio"):
		audio.abandon_match_audio()
	var host := get_parent()
	if host != null:
		host.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	PageTransition.request(0, func(_mode: int) -> Node:
		return load("res://scenes/title.tscn").instantiate()
	)


func _select_main(index: int, sound: bool = true) -> void:
	var next := posmod(index, MAIN.size())
	var changed := next != selected
	selected = next
	for button in _buttons:
		button.set_selected(button.item_index == selected)
		button.punch_if(changed and button.item_index == selected)
	if changed and sound:
		_ui_hover()


func _select_option(index: int, sound: bool = true) -> void:
	var next := posmod(index, _option_rows.size())
	var changed := next != option_index
	option_index = next
	for row in _option_rows:
		row.set_selected(row.item_index == option_index)
	if changed and sound:
		_ui_hover()
	_refresh_options()


func _option_key(key: InputEventKey) -> void:
	if _is_up(key):
		_select_option(option_index - 1)
	elif _is_down(key):
		_select_option(option_index + 1)
	elif _is_left(key):
		_nudge_option(-1)
	elif _is_right(key):
		_nudge_option(1)
	elif _is_accept(key) and option_index == _option_rows.size() - 1:
		_close_options()


func _nudge_option(direction: int) -> void:
	if option_index == 0:
		Settings.bgm_volume = clampf(Settings.bgm_volume + direction * 0.05, 0.0, 1.0)
	elif option_index == 1:
		Settings.sfx_volume = clampf(Settings.sfx_volume + direction * 0.05, 0.0, 1.0)
	elif option_index == 2:
		Settings.step_screen_shake(direction)
	_refresh_options()


func _refresh_options() -> void:
	if _option_rows.size() < 4:
		return
	_option_rows[0].set_value("BGM  %d%%" % int(round(Settings.bgm_volume * 100.0)))
	_option_rows[1].set_value("SFX  %d%%" % int(round(Settings.sfx_volume * 100.0)))
	var shake := "보통"
	if Settings.screen_shake == Settings.ScreenShake.OFF:
		shake = "끄기"
	elif Settings.screen_shake == Settings.ScreenShake.STRONG:
		shake = "강함"
	_option_rows[2].set_value("화면 흔들림  %s" % shake)
	_option_rows[3].set_value("닫기")


func _hide_menu() -> void:
	open = false
	options_open = false
	_overlay.visible = false
	_main.visible = false
	_options.visible = false


func _build() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "Dim"
	_overlay.color = Color(0, 0, 0, 0.62)
	_overlay.position = Vector2.ZERO
	_overlay.size = VIEW
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_main = Control.new()
	_main.name = "Main"
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main)
	var total := SLAB_SIZE.y * MAIN.size() + GAP * (MAIN.size() - 1)
	var origin := Vector2((VIEW.x - SLAB_SIZE.x) * 0.5, (VIEW.y - total) * 0.5)
	for index in MAIN.size():
		var button := PauseButton.new()
		button.item_index = index
		button.text = MAIN[index]
		button.position = origin + Vector2(0, index * (SLAB_SIZE.y + GAP))
		button.size = SLAB_SIZE
		button.hovered.connect(_select_main)
		button.activated.connect(func(item: int) -> void:
			_select_main(item, false)
			_activate_main()
		)
		_main.add_child(button)
		_buttons.append(button)
	_options = Control.new()
	_options.name = "Options"
	_options.visible = false
	_options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_options)
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.05, 0.07, 0.78)
	panel.position = Vector2(336, 70)
	panel.size = Vector2(480, 508)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options.add_child(panel)
	var heading := Label.new()
	heading.text = "설정"
	heading.position = Vector2(360, 88)
	heading.size = Vector2(432, 40)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", TEXT_LIGHT)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options.add_child(heading)
	for index in 4:
		var row := PauseButton.new()
		row.item_index = index
		row.text = ""
		row.position = Vector2(376, 146 + index * 78)
		row.size = Vector2(400, 66)
		row.hovered.connect(_select_option)
		row.activated.connect(func(item: int) -> void:
			_select_option(item, false)
			if item == 4:
				_close_options()
		)
		_options.add_child(row)
		_option_rows.append(row)
	_refresh_options()


func _ui_hover() -> void:
	var audio = _audio()
	if audio != null:
		audio.play_ui_hover()


func _audio():
	if get_tree() == null:
		return null
	return get_tree().root.get_node_or_null("AudioDirector")


func _rounds():
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("RoundManager")


func _knockdown():
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("KnockdownManager")


func _finisher():
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("FinisherImpactFreeze")


func _banner():
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("CombatHUD/CombatAnnouncement")


func _is_escape(key: InputEventKey) -> bool:
	return key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE


func _is_accept(key: InputEventKey) -> bool:
	return key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE or key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_SPACE


func _is_up(key: InputEventKey) -> bool:
	return key.keycode == KEY_UP or key.keycode == KEY_W or key.physical_keycode == KEY_UP or key.physical_keycode == KEY_W


func _is_down(key: InputEventKey) -> bool:
	return key.keycode == KEY_DOWN or key.keycode == KEY_S or key.physical_keycode == KEY_DOWN or key.physical_keycode == KEY_S


func _is_left(key: InputEventKey) -> bool:
	return key.keycode == KEY_LEFT or key.keycode == KEY_A or key.physical_keycode == KEY_LEFT or key.physical_keycode == KEY_A


func _is_right(key: InputEventKey) -> bool:
	return key.keycode == KEY_RIGHT or key.keycode == KEY_D or key.physical_keycode == KEY_RIGHT or key.physical_keycode == KEY_D


class PauseButton:
	extends Control

	signal hovered(index: int)
	signal activated(index: int)

	var item_index := 0
	var text := ""
	var selected := false
	var _label: Label


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			hovered.emit(item_index)
		)
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 26)
		add_child(_label)
		_paint()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(item_index)
			accept_event()


	func set_selected(on: bool) -> void:
		selected = on
		queue_redraw()


	func set_value(next: String) -> void:
		text = next
		if _label != null:
			_label.text = next


	func punch_if(on: bool) -> void:
		if not on or not is_inside_tree():
			return
		pivot_offset = size * 0.5
		scale = Vector2.ONE
		var motion := create_tween()
		motion.tween_property(self, "scale", Vector2(1.015, 1.015), 0.06)
		motion.tween_property(self, "scale", Vector2.ONE, 0.07)


	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(22.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 22.0, size.y),
			Vector2(0.0, size.y),
		]), Color(0.95, 0.93, 0.88, 1.0) if selected else Color(0.07, 0.06, 0.08, 0.94))
		_paint()


	func _paint() -> void:
		if _label == null:
			return
		_label.text = text
		_label.add_theme_color_override("font_color", Color(0.08, 0.07, 0.09, 1.0) if selected else Color(0.97, 0.96, 0.93, 1.0))
