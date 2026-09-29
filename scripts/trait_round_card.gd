extends CanvasLayer

## Player-facing trait reveal. Gameplay stays paused until 계속하기.

signal fight_pressed

const Catalog = preload("res://scripts/trait_catalog.gd")
const CursorPolicy = preload("res://scripts/cursor_policy.gd")
const UI_FONT: FontFile = preload("res://assets/fonts/esamanru Medium.ttf")

const VIEW := Vector2(1152, 648)
const SLAB_SIZE := Vector2(340, 66)
const SLANT := 22.0
const CREAM := Color(0.95, 0.93, 0.88, 1.0)
const INK := Color(0.08, 0.07, 0.09, 1.0)
const PAPER := Color(0.97, 0.96, 0.93, 1.0)

var _round: Label
var _player_name: Label
var _player_benefit: Label
var _player_drawback: Label
var _opponent_name: Label
var _opponent_benefit: Label
var _opponent_drawback: Label
var _continue: Control
var _continue_hovered := false


func _ready() -> void:
	layer = 30
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.physical_keycode == KEY_ENTER:
		_confirm()
		get_viewport().set_input_as_handled()


func show_round(round_number: int, player_traits: Array, opponent_traits: Array, _player_wins: int, _opponent_wins: int) -> void:
	_round.text = "ROUND %d" % round_number
	_fill(_player_name, _player_benefit, _player_drawback, player_traits)
	_fill(_opponent_name, _opponent_benefit, _opponent_drawback, opponent_traits)
	_continue_hovered = false
	visible = true
	CursorPolicy.show_pointer()


func _confirm() -> void:
	if not visible:
		return
	visible = false
	CursorPolicy.hide_pointer()
	fight_pressed.emit()


func _fill(name_label: Label, benefit: Label, drawback: Label, traits: Array) -> void:
	if traits.is_empty() or traits[0] == null:
		name_label.text = ""
		benefit.text = ""
		drawback.text = ""
		return
	var entry = traits[0]
	name_label.text = Catalog.reveal_name(entry)
	benefit.text = Catalog.reveal_benefit(entry)
	drawback.text = Catalog.reveal_drawback(entry)


func _build() -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	var board := Control.new()
	board.name = "Board"
	board.position = Vector2.ZERO
	board.size = VIEW
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.theme = theme
	add_child(board)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	board.add_child(dim)
	_round = _label(Vector2(0, 108), Vector2(VIEW.x, 36), 22, PAPER)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(_round)
	_add_side(board, "OPPONENT", Vector2(64, 176))
	_add_side(board, "PLAYER", Vector2(788, 176))
	_continue = _Continue.new()
	_continue.position = Vector2(436, 392)
	_continue.size = Vector2(280, 58)
	_continue.hovered.connect(func() -> void:
		if _continue_hovered:
			return
		_continue_hovered = true
		var audio = get_tree().root.get_node_or_null("AudioDirector")
		if audio != null and audio.has_method("play_ui_hover"):
			audio.play_ui_hover()
	)
	_continue.activated.connect(_confirm)
	board.add_child(_continue)


func _add_side(board: Control, caption: String, origin: Vector2) -> void:
	var plate := _Slab.new()
	plate.position = origin
	plate.size = Vector2(300, 156)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(plate)
	var who := _label(origin + Vector2(28, 16), Vector2(244, 22), 13, Color(0.78, 0.76, 0.72))
	who.text = caption
	board.add_child(who)
	var name_label := _label(origin + Vector2(28, 42), Vector2(244, 40), 24, PAPER)
	var benefit := _label(origin + Vector2(28, 90), Vector2(244, 24), 15, CREAM)
	var drawback := _label(origin + Vector2(28, 114), Vector2(244, 24), 15, CREAM)
	board.add_child(name_label)
	board.add_child(benefit)
	board.add_child(drawback)
	if caption == "PLAYER":
		_player_name = name_label
		_player_benefit = benefit
		_player_drawback = drawback
	else:
		_opponent_name = name_label
		_opponent_benefit = benefit
		_opponent_drawback = drawback


func _label(at: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


class _Slab:
	extends Control

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(22.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 22.0, size.y),
			Vector2(0.0, size.y),
		]), Color(0.07, 0.06, 0.08, 0.92))


class _Continue:
	extends Control

	signal hovered
	signal activated

	var _label: Label


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			hovered.emit()
		)
		_label = Label.new()
		_label.text = "계속하기"
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 26)
		_label.add_theme_color_override("font_color", Color(0.08, 0.07, 0.09))
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			activated.emit()
			accept_event()


	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(22.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 22.0, size.y),
			Vector2(0.0, size.y),
		]), Color(0.95, 0.93, 0.88, 1.0))
