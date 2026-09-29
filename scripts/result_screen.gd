extends Control

## Match result presentation. It displays a published result and does not score the match.

const ResultScript = preload("res://scripts/match_result_data.gd")
const PageTransition = preload("res://scripts/page_transition.gd")
const UI_FONT: FontFile = preload("res://assets/fonts/esamanru Medium.ttf")
const BACKGROUND_PATH := "res://assets/title/title_background.png"
const GameScene := preload("res://scenes/game.tscn")
const TitleScene := preload("res://scenes/title.tscn")
const CursorPolicy = preload("res://scripts/cursor_policy.gd")

const VIEW := Vector2(1152, 648)
const SLAB_SIZE := Vector2(420, 66)
const SLANT := 22.0
const SLAB_DARK := Color(0.07, 0.06, 0.08, 0.94)
const SLAB_LIGHT := Color(0.95, 0.93, 0.88, 1.0)
const TEXT_LIGHT := Color(0.97, 0.96, 0.93, 1.0)
const TEXT_DARK := Color(0.08, 0.07, 0.09, 1.0)
const PANEL := Color(0.05, 0.05, 0.07, 0.72)

const BUTTONS: PackedStringArray = ["다시 하기", "타이틀로"]

var selected_index := 0

var _buttons: Array[Control] = []
var _headline: Label
var _method: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = VIEW
	var theme := Theme.new()
	theme.default_font = UI_FONT
	self.theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_show(ResultScript.current)
	_select(0)
	CursorPolicy.show_pointer()


func _unhandled_input(event: InputEvent) -> void:
	if PageTransition.is_running():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_UP or key.keycode == KEY_W or key.physical_keycode == KEY_UP or key.physical_keycode == KEY_W:
		_select(posmod(selected_index - 1, BUTTONS.size()))
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DOWN or key.keycode == KEY_S or key.physical_keycode == KEY_DOWN or key.physical_keycode == KEY_S:
		_select(posmod(selected_index + 1, BUTTONS.size()))
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE or key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_SPACE:
		_activate()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var background := TextureRect.new()
	background.name = "Background"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture = load(BACKGROUND_PATH)
	background.position = Vector2.ZERO
	background.size = VIEW
	add_child(background)
	var panel := _Panel.new()
	panel.name = "ResultPanel"
	panel.position = Vector2(276, 54)
	panel.size = Vector2(600, 356)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_headline = _label("Headline", 62, Vector2(0, 28), Vector2(600, 78))
	_method = _label("Method", 28, Vector2(0, 108), Vector2(600, 40))
	panel.add_child(_headline)
	panel.add_child(_method)
	var names := _label("Sides", 16, Vector2(70, 152), Vector2(460, 28))
	names.text = "PLAYER                         OPPONENT"
	names.add_theme_color_override("font_color", Color(0.86, 0.84, 0.80, 0.9))
	panel.add_child(names)
	var lines := Control.new()
	lines.name = "RoundScores"
	lines.position = Vector2(70, 188)
	lines.size = Vector2(460, 150)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lines)
	var menu := Control.new()
	menu.name = "Menu"
	menu.position = Vector2(366, 444)
	menu.size = Vector2(420, 150)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu)
	for index in BUTTONS.size():
		var button := _Button.new()
		button.text = BUTTONS[index]
		button.index = index
		button.position = Vector2(0, index * 78)
		button.size = SLAB_SIZE
		button.hovered.connect(_select)
		button.activated.connect(_on_pressed)
		menu.add_child(button)
		_buttons.append(button)


func _show(result) -> void:
	if result == null:
		_headline.text = "RESULT"
		_method.text = ""
		return
	_headline.text = _headline_for(result.winner)
	_method.text = _method_for(result.result_type)
	var lines := get_node("ResultPanel/RoundScores")
	var row := 0
	var wins := _label("MatchWins", 22, Vector2.ZERO, Vector2(460, 34))
	wins.text = "%d  -  %d" % [int(result.player_round_wins), int(result.opponent_round_wins)]
	wins.position = Vector2(0, row * 36)
	lines.add_child(wins)
	row += 1
	for score in result.round_scores:
		var line := _label("Round%d" % int(score.round_number), 22, Vector2(0, row * 36), Vector2(460, 34))
		line.text = "ROUND %d          %d - %d" % [score.round_number, score.player_score, score.opponent_score]
		lines.add_child(line)
		row += 1


func _headline_for(winner: int) -> String:
	if winner == ResultScript.Winner.PLAYER:
		return "VICTORY"
	if winner == ResultScript.Winner.OPPONENT:
		return "DEFEAT"
	if winner == ResultScript.Winner.NONE:
		return "DRAW"
	return "RESULT"


func _method_for(result_type: int) -> String:
	if result_type == ResultScript.ResultType.KO:
		return "KNOCKOUT"
	if result_type == ResultScript.ResultType.DECISION:
		return "DECISION"
	if result_type == ResultScript.ResultType.DRAW:
		return "DRAW"
	return ""


func _select(index: int) -> void:
	var changed := index != selected_index
	selected_index = index
	for button in _buttons:
		button.set_selected(button.index == index)
	if changed:
		_ui_hover()


func _ui_hover() -> void:
	var audio = get_tree().root.get_node_or_null("AudioDirector")
	if audio != null and audio.has_method("play_ui_hover"):
		audio.play_ui_hover()


func _on_pressed(index: int) -> void:
	_select(index)
	_activate()


func _activate() -> void:
	if PageTransition.is_running():
		return
	if selected_index == 0:
		PageTransition.request(ResultScript.resume_mode, _build_rematch)
	else:
		PageTransition.request(0, _build_title)


func _build_rematch(mode: int) -> Node:
	var scene := GameScene.instantiate()
	var mode_node := scene.get_node_or_null("GameMode")
	if mode_node != null:
		mode_node.mode = mode
	return scene


func _build_title(_mode: int) -> Node:
	return TitleScene.instantiate()


func _label(node_name: String, font_size: int, at: Vector2, label_size: Vector2) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_LIGHT)
	return label


class _Panel:
	extends Control

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(28.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 28.0, size.y),
			Vector2(0.0, size.y),
		]), PANEL)


class _Button:
	extends Control

	signal hovered(index: int)
	signal activated(index: int)

	var index := 0
	var text := ""
	var selected := false
	var _label: Label


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			hovered.emit(index)
		)
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.add_theme_font_size_override("font_size", 28)
		_label.text = text
		add_child(_label)
		_apply()


	func set_selected(next: bool) -> void:
		selected = next
		queue_redraw()
		_apply()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(index)
			accept_event()


	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(SLANT, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - SLANT, size.y),
			Vector2(0.0, size.y),
		]), SLAB_LIGHT if selected else SLAB_DARK)
		_apply()


	func _apply() -> void:
		if _label == null:
			return
		_label.add_theme_color_override("font_color", TEXT_DARK if selected else TEXT_LIGHT)
