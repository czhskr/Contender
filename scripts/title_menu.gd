extends Control

## Static title menu. Selection is one index shared by keyboard and mouse.

const UI_FONT: FontFile = preload("res://assets/fonts/esamanru Medium.ttf")
const BACKGROUND_PATH := "res://assets/title/title_background.png"
const LOGO_PATH := "res://assets/title/contender_logo.png"

const MENU_ITEMS: PackedStringArray = ["시작", "튜토리얼", "설정"]
const SLAB_SIZE := Vector2(340, 66)
const CASCADE_X := 26.0
const BUTTON_GAP_Y := 16.0
const MENU_ORIGIN := Vector2(150, 292)
const SLANT := 22.0
const POINTER_SIZE := Vector2(16, 22)
const POINTER_GAP := 12.0

const SLAB_DARK := Color(0.07, 0.06, 0.08, 0.94)
const SLAB_LIGHT := Color(0.95, 0.93, 0.88, 1.0)
const TEXT_LIGHT := Color(0.97, 0.96, 0.93, 1.0)
const TEXT_DARK := Color(0.08, 0.07, 0.09, 1.0)

const GameScene := preload("res://scenes/game.tscn")
const GameModeType = preload("res://scripts/game_mode.gd")
const ContextType = preload("res://scripts/title_context_panel.gd")
const PageTransition = preload("res://scripts/page_transition.gd")
const IntroType = preload("res://scripts/title_intro.gd")
const CursorPolicy = preload("res://scripts/cursor_policy.gd")

var selected_index := 0
var menu_items: PackedStringArray = MENU_ITEMS

var _slabs: Array[Control] = []
var _pointer: Control
var _pointer_tween: Tween
var _snap_pointer := true
var _context: ContextType
var _logo: TextureRect
var _menu: Control
var _intro: IntroType


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_fit_viewport()
	_select_index(0)
	CursorPolicy.show_pointer()
	if DisplayServer.get_name() == "headless":
		_intro.show_immediately(self, _logo, _menu, _slabs, _pointer)
	else:
		_intro.play(self, _logo, _menu, _slabs, _pointer)


func _fit_viewport() -> void:
	var view := get_viewport().get_visible_rect().size
	if view.x < 2.0 or view.y < 2.0:
		view = Vector2(1152, 648)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = view
	var background := get_node_or_null("Background") as Control
	if background != null:
		background.set_anchors_preset(Control.PRESET_TOP_LEFT)
		background.position = Vector2.ZERO
		background.size = view


func is_intro_running() -> bool:
	return _intro != null and _intro.running


func play_intro() -> void:
	if _intro == null:
		return
	_intro.play(self, _logo, _menu, _slabs, _pointer)


func show_title_immediately() -> void:
	if _intro == null:
		return
	_intro.show_immediately(self, _logo, _menu, _slabs, _pointer)


func _unhandled_input(event: InputEvent) -> void:
	if is_intro_running():
		get_viewport().set_input_as_handled()
		return
	if PageTransition.is_running():
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if _is_escape(key) and _context != null and _context.is_open():
		_context.close()
		get_viewport().set_input_as_handled()
		return
	if _context != null and _context.is_open():
		_context.handle_key(key)
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_UP or key.keycode == KEY_W or key.physical_keycode == KEY_UP or key.physical_keycode == KEY_W:
		_move_selection(-1)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DOWN or key.keycode == KEY_S or key.physical_keycode == KEY_DOWN or key.physical_keycode == KEY_S:
		_move_selection(1)
		get_viewport().set_input_as_handled()
	elif _is_accept(key):
		_activate_selected()
		get_viewport().set_input_as_handled()


func _is_escape(key: InputEventKey) -> bool:
	return key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE


func _is_accept(key: InputEventKey) -> bool:
	return key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE or key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_SPACE


func _select_index(index: int) -> void:
	var previous := selected_index
	if menu_items.is_empty():
		selected_index = 0
	else:
		selected_index = posmod(index, menu_items.size())
	_update_visuals(previous != selected_index)
	if previous != selected_index:
		_ui_hover()


func _ui_hover() -> void:
	var audio = get_tree().root.get_node_or_null("AudioDirector")
	if audio != null and audio.has_method("play_ui_hover"):
		audio.play_ui_hover()


func _move_selection(step: int) -> void:
	if _context != null and _context.is_open():
		return
	_select_index(selected_index + step)


func _activate_selected() -> void:
	if _context == null or is_intro_running():
		return
	_context.open_kind(selected_index)


func _update_visuals(punch: bool = false) -> void:
	for index in _slabs.size():
		var slab := _slabs[index] as SlabButton
		if slab == null:
			continue
		slab.selected = index == selected_index
		slab.queue_redraw()
		if punch and index == selected_index:
			slab.punch()
	if _pointer == null or selected_index < 0 or selected_index >= _slabs.size():
		return
	var slab := _slabs[selected_index]
	var target := slab.position + Vector2(
		-POINTER_SIZE.x - POINTER_GAP,
		(slab.size.y - POINTER_SIZE.y) * 0.5
	)
	if _snap_pointer:
		_pointer.position = target
		_snap_pointer = false
		return
	if _pointer_tween != null and _pointer_tween.is_valid():
		_pointer_tween.kill()
	_pointer_tween = create_tween()
	_pointer_tween.tween_property(_pointer, "position", target, 0.10)


func _build() -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	self.theme = theme

	var background := TextureRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture = load(BACKGROUND_PATH)
	add_child(background)

	_logo = TextureRect.new()
	var logo := _logo
	logo.name = "Logo"
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture = load(LOGO_PATH)
	logo.position = Vector2(96, 36)
	logo.size = Vector2(520, 205)
	add_child(logo)

	_menu = Control.new()
	var menu := _menu
	menu.name = "Menu"
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.position = MENU_ORIGIN
	menu.size = Vector2(430, 250)
	add_child(menu)

	_pointer = Pointer.new()
	_pointer.name = "Pointer"
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.custom_minimum_size = POINTER_SIZE
	_pointer.size = POINTER_SIZE
	menu.add_child(_pointer)

	_slabs.clear()
	for index in menu_items.size():
		var slab := SlabButton.new()
		slab.name = menu_items[index]
		slab.item_index = index
		slab.item_text = menu_items[index]
		slab.position = Vector2(CASCADE_X * index, (SLAB_SIZE.y + BUTTON_GAP_Y) * index)
		slab.size = SLAB_SIZE
		slab.custom_minimum_size = SLAB_SIZE
		slab.hovered.connect(_select_index)
		slab.activated.connect(_on_slab_activated)
		menu.add_child(slab)
		_slabs.append(slab)
	_context = ContextType.new()
	_context.name = "ContextPanel"
	_context.match_requested.connect(_enter_match)
	add_child(_context)
	_intro = IntroType.new()
	_intro.name = "TitleIntro"
	add_child(_intro)


func _enter_match(mode: int) -> void:
	if is_intro_running():
		return
	PageTransition.request(mode, _build_match)


func _build_match(mode: int) -> Node:
	var scene := GameScene.instantiate()
	var mode_node := scene.get_node_or_null("GameMode")
	if mode_node != null:
		mode_node.mode = mode
	return scene


func _on_slab_activated(index: int) -> void:
	if is_intro_running():
		return
	_select_index(index)
	_activate_selected()


class SlabButton:
	extends Control

	signal hovered(index: int)
	signal activated(index: int)

	var item_index := 0
	var item_text := ""
	var selected := false
	var _label: Label


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			hovered.emit(item_index)
		)
		_label = Label.new()
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.offset_left = 28.0
		_label.offset_right = -28.0
		_label.add_theme_font_size_override("font_size", 28)
		_label.text = item_text
		add_child(_label)
		_apply_colors()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			activated.emit(item_index)
			accept_event()


	func _draw() -> void:
		draw_colored_polygon(_slab_points(), SLAB_LIGHT if selected else SLAB_DARK)
		_apply_colors()


	func punch() -> void:
		if not is_inside_tree():
			return
		pivot_offset = size * 0.5
		scale = Vector2.ONE
		var motion := create_tween()
		motion.tween_property(self, "scale", Vector2(1.015, 1.015), 0.06)
		motion.tween_property(self, "scale", Vector2.ONE, 0.07)


	func _apply_colors() -> void:
		if _label == null:
			return
		_label.add_theme_color_override("font_color", TEXT_DARK if selected else TEXT_LIGHT)


	func _slab_points() -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(SLANT, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - SLANT, size.y),
			Vector2(0.0, size.y),
		])


class Pointer:
	extends Control

	func _draw() -> void:
		var mid_y := size.y * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, 1.0),
			Vector2(0.0, size.y - 1.0),
			Vector2(size.x, mid_y),
		]), SLAB_LIGHT)
