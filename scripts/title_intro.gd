extends Node

## First-launch title presentation. One logo moves from center to its layout pose.

signal finished

const BLACK_HOLD := 0.20
const LOGO_REVEAL := 0.26
const FADE_DELAY := 0.34
const FADE_TIME := 0.55
const MOVE_DELAY := 1.80
const MOVE_TIME := 0.52
const MENU_DELAY := 2.66
const MENU_STAGGER := 0.08
const MENU_SLIDE := 0.18
const INTRO_SCALE := 1.45

var running := false

var _token := 0
var _tween: Tween
var _host: Control
var _logo: TextureRect
var _menu: Control
var _overlay: ColorRect
var _slabs: Array[Control] = []
var _pointer: Control
var _final_position := Vector2.ZERO
var _final_size := Vector2.ZERO
var _rest: Array[Vector2] = []


func play(host: Control, logo: TextureRect, menu: Control, slabs: Array[Control], pointer: Control) -> void:
	_bind(host, logo, menu, slabs, pointer)
	_token += 1
	var token := _token
	_kill()
	running = true
	_remember_layout()
	_hide_menu()
	_overlay.color = Color(0, 0, 0, 1)
	_overlay.visible = true
	var view := _view_size()
	var intro_size := _final_size * INTRO_SCALE
	var start_size := intro_size * 0.94
	_logo.modulate.a = 0.0
	_logo.size = start_size
	_logo.position = view * 0.5 - start_size * 0.5
	_tween = create_tween()
	_tween.tween_property(_logo, "modulate:a", 1.0, LOGO_REVEAL).set_delay(BLACK_HOLD)
	_tween.parallel().tween_property(_logo, "size", intro_size, LOGO_REVEAL).set_delay(BLACK_HOLD).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_logo, "position", view * 0.5 - intro_size * 0.5, LOGO_REVEAL).set_delay(BLACK_HOLD).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_overlay, "color:a", 0.0, FADE_TIME).set_delay(FADE_DELAY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_logo, "position", _final_position, MOVE_TIME).set_delay(MOVE_DELAY).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_logo, "size", _final_size, MOVE_TIME).set_delay(MOVE_DELAY).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	for index in _slabs.size():
		var slab := _slabs[index]
		var rest: Vector2 = _rest[index]
		_tween.parallel().tween_property(slab, "position", rest, MENU_SLIDE).set_delay(MENU_DELAY + MENU_STAGGER * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_property(slab, "modulate:a", 1.0, MENU_SLIDE).set_delay(MENU_DELAY + MENU_STAGGER * index)
	if _pointer != null:
		_tween.parallel().tween_property(_pointer, "modulate:a", 1.0, MENU_SLIDE).set_delay(MENU_DELAY)
	_tween.finished.connect(func() -> void:
		if token != _token:
			return
		_settle()
		finished.emit()
	)


func show_immediately(host: Control = null, logo: TextureRect = null, menu: Control = null, slabs: Array[Control] = [], pointer: Control = null) -> void:
	if host != null:
		_bind(host, logo, menu, slabs, pointer)
		_remember_layout()
	_token += 1
	_kill()
	_settle()


func final_position() -> Vector2:
	return _final_position


func final_size() -> Vector2:
	return _final_size


func _bind(host: Control, logo: TextureRect, menu: Control, slabs: Array[Control], pointer: Control) -> void:
	_host = host
	_logo = logo
	_menu = menu
	_slabs = slabs
	_pointer = pointer
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = ColorRect.new()
		_overlay.name = "IntroBlack"
		_overlay.color = Color(0, 0, 0, 1)
		_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_overlay.position = Vector2.ZERO
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(_overlay)
		_overlay.size = host.size
	var logo_index := logo.get_index()
	if _overlay.get_index() > logo_index:
		host.move_child(_overlay, logo_index)


func _remember_layout() -> void:
	_final_position = _logo.position
	_final_size = _logo.size
	_rest.clear()
	for slab in _slabs:
		_rest.append(slab.position)


func _hide_menu() -> void:
	for index in _slabs.size():
		var slab := _slabs[index]
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slab.modulate.a = 0.0
		slab.position = _rest[index] + Vector2(-18.0, 8.0)
	if _pointer != null:
		_pointer.modulate.a = 0.0


func _settle() -> void:
	running = false
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.color = Color(0, 0, 0, 0)
	if _logo != null and is_instance_valid(_logo) and _final_size != Vector2.ZERO:
		_logo.position = _final_position
		_logo.size = _final_size
		_logo.modulate.a = 1.0
	for index in _slabs.size():
		var slab := _slabs[index]
		if not is_instance_valid(slab):
			continue
		if index < _rest.size():
			slab.position = _rest[index]
		slab.modulate.a = 1.0
		slab.mouse_filter = Control.MOUSE_FILTER_STOP
	if _pointer != null and is_instance_valid(_pointer):
		_pointer.modulate.a = 1.0


func _view_size() -> Vector2:
	var view := _logo.get_viewport().get_visible_rect().size
	if view.x < 2.0 or view.y < 2.0:
		return Vector2(1152, 648)
	return view


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
