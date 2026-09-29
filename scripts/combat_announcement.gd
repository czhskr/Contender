extends CanvasLayer

## Center combat announcements. Presentation only; it does not advance combat.

signal presentation_started(text: String)
signal pass_finished(text: String)

const UI_FONT: FontFile = preload("res://assets/fonts/esamanru Medium.ttf")
const VIEW := Vector2(1152, 648)
const ENTER := 0.16
const EXIT := 0.16
const SLAB_HOLD := 0.40
const BANNER_SIZE := Vector2(720, 96)

var current_text := ""
var phase := ""
var ring_bell_for_fight := true

var _token := 0
var _count_token := 0
var _banner: Control
var _banner_label: Label
var _count: Label
var _tween: Tween
var _count_tween: Tween


func _ready() -> void:
	layer = 6
	add_to_group("combat_announcement")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = UI_FONT
	root.theme = theme
	add_child(root)
	_banner = _Banner.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.size = BANNER_SIZE
	_banner.visible = false
	root.add_child(_banner)
	_banner_label = Label.new()
	_banner_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_label)
	_count = Label.new()
	_count.set_anchors_preset(Control.PRESET_CENTER)
	_count.offset_left = -160.0
	_count.offset_right = 160.0
	_count.offset_top = -118.0
	_count.offset_bottom = -18.0
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 84)
	_count.add_theme_color_override("font_color", Color(0.97, 0.96, 0.93))
	_count.add_theme_constant_override("outline_size", 8)
	_count.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.05, 0.9))
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.visible = false
	root.add_child(_count)


func reset() -> void:
	_token += 1
	_count_token += 1
	_kill()
	current_text = ""
	phase = ""
	if _banner != null:
		_banner.visible = false
	if _count != null:
		_count.visible = false


func play_round(round_number: int) -> void:
	play_pass("ROUND %d" % round_number, false, 0.40, 58)


func play_fight(ring_bell: bool = true) -> void:
	ring_bell_for_fight = ring_bell
	play_pass("FIGHT", true, SLAB_HOLD, 80)


func play_begin() -> void:
	play_pass("BEGIN", true, SLAB_HOLD, 80)


func light_pass_length() -> float:
	return ENTER + SLAB_HOLD + EXIT


func play_knockout() -> void:
	play_pass("KNOCKOUT", false, 0.60, 78)


func play_decision() -> void:
	play_pass("DECISION", true, 0.50, 70)


func play_pass(text: String, light_slab: bool, hold: float, font_size: int) -> void:
	_token += 1
	var token := _token
	_count_token += 1
	if _count != null:
		_count.visible = false
	if _count_tween != null and _count_tween.is_valid():
		_count_tween.kill()
	current_text = text
	phase = "enter"
	_banner.visible = true
	_banner.light_slab = light_slab
	_banner.queue_redraw()
	_banner_label.text = text
	_banner_label.add_theme_font_size_override("font_size", font_size)
	_banner_label.add_theme_color_override("font_color", Color(0.08, 0.07, 0.09) if light_slab else Color(0.97, 0.96, 0.93))
	var view := _view()
	var center := Vector2((view.x - BANNER_SIZE.x) * 0.5, view.y * 0.5 - 70.0)
	var right := Vector2(view.x + 40.0, center.y)
	var left := Vector2(-BANNER_SIZE.x - 40.0, center.y)
	_banner.position = right
	_banner.modulate.a = 1.0
	presentation_started.emit(text)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_banner, "position", center, ENTER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		if token == _token:
			phase = "hold"
	)
	_tween.tween_interval(hold)
	_tween.tween_callback(func() -> void:
		if token == _token:
			phase = "exit"
	)
	_tween.tween_property(_banner, "position", left, EXIT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.finished.connect(func() -> void:
		if token != _token:
			return
		_banner.visible = false
		if current_text == text:
			current_text = ""
			phase = ""
		pass_finished.emit(text)
	)


func show_count(count: int) -> void:
	_token += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _banner != null:
		_banner.visible = false
	_count_token += 1
	var token := _count_token
	current_text = str(count)
	phase = "count"
	_count.text = str(count)
	_count.visible = true
	_count.modulate.a = 1.0
	_count.pivot_offset = _count.size * 0.5
	_count.scale = Vector2(0.90, 0.90)
	if _count_tween != null and _count_tween.is_valid():
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.tween_property(_count, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_count_tween.tween_property(_count, "scale", Vector2.ONE, 0.08)
	_count_tween.tween_interval(0.54)
	_count_tween.tween_property(_count, "modulate:a", 0.0, 0.20)
	_count_tween.finished.connect(func() -> void:
		if token != _count_token:
			return
		_count.visible = false
		if current_text == str(count):
			current_text = ""
			phase = ""
	)


func _view() -> Vector2:
	var rect := get_viewport().get_visible_rect().size
	if rect.x < 2.0:
		return VIEW
	return rect


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _count_tween != null and _count_tween.is_valid():
		_count_tween.kill()


class _Banner:
	extends Control

	var light_slab := false

	func _draw() -> void:
		var color := Color(0.95, 0.93, 0.88) if light_slab else Color(0.07, 0.06, 0.08, 0.94)
		draw_colored_polygon(PackedVector2Array([
			Vector2(34.0, 0.0),
			Vector2(size.x, 0.0),
			Vector2(size.x - 34.0, size.y),
			Vector2(0.0, size.y),
		]), color)
