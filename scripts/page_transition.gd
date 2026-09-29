extends CanvasLayer

## Title-to-match wipe. Lives on the scene-tree root, so replacing Title does not remove it.

const VIEW_FALLBACK := Vector2(1152, 648)
const CONFIRM_HOLD := 0.10
const WIPE_IN := 0.38
const SLAB_DELAY := 0.09
const WIPE_OUT := 0.32
const SHEAR := 320.0
const PAD_X := 760.0
const PAD_Y := 440.0

const ACCENT := Color(0.95, 0.93, 0.88, 1.0)
const DARK := Color(0.045, 0.04, 0.05, 1.0)

enum Phase { IDLE, CONFIRM, WIPE_IN, COVERED, WIPE_OUT }

static var _active = null

var phase := Phase.IDLE
var accept_count := 0
var handoff_count := 0

var _running := false
var _token := 0
var _elapsed := 0.0
var _handed := false
var _mode := 0
var _builder: Callable
var _game: Node
var _back: WipeSlab
var _front: WipeSlab
var _blocker: Control
var _view := VIEW_FALLBACK
var _body := Vector2.ZERO
var _start_x := 0.0
var _cover_x := 0.0
var _end_x := 0.0
var _origin_y := 0.0


static func is_running() -> bool:
	return _active != null and is_instance_valid(_active) and _active._running


static func request(mode: int, builder: Callable) -> bool:
	return _ensure()._request(mode, builder)


static func _ensure():
	if _active != null and is_instance_valid(_active):
		return _active
	var node = (load("res://scripts/page_transition.gd") as GDScript).new()
	node.name = "PageTransition"
	node.layer = 120
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(node)
	_active = node
	return node


func _ready() -> void:
	layer = 120
	_blocker = Control.new()
	_blocker.name = "InputBlock"
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blocker)
	_back = WipeSlab.new()
	_back.name = "BackSlab"
	_back.fill = DARK
	add_child(_back)
	_front = WipeSlab.new()
	_front.name = "FrontSlab"
	_front.fill = ACCENT
	add_child(_front)
	_hide_slabs()


func _process(delta: float) -> void:
	if not _running:
		return
	var token := _token
	_elapsed += delta
	var motion := _elapsed - CONFIRM_HOLD
	if motion < 0.0:
		phase = Phase.CONFIRM
		_place(0.0, 0.0)
		return
	var front_progress := _progress(motion, 0.0)
	var back_progress := _progress(motion, SLAB_DELAY)
	_place(front_progress, back_progress)
	if not _handed and back_progress >= 1.0:
		phase = Phase.COVERED
		_handoff(token)
		return
	if _handed and front_progress >= 2.0 and back_progress >= 2.0:
		_finish(token)
	elif _handed:
		phase = Phase.WIPE_OUT
	else:
		phase = Phase.WIPE_IN


func covers_viewport() -> bool:
	if _back == null or not _back.visible:
		return false
	return _slab_covers(_back) and _slab_covers(_front)


func back_covers_viewport() -> bool:
	return _back != null and _back.visible and _slab_covers(_back)


func _request(mode: int, builder: Callable) -> bool:
	if _running:
		return false
	_running = true
	_token += 1
	accept_count += 1
	_mode = mode
	_builder = builder
	_elapsed = 0.0
	_handed = false
	_game = null
	phase = Phase.CONFIRM
	_layout()
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_back.visible = true
	_front.visible = true
	_place(0.0, 0.0)
	return true


func _handoff(token: int) -> void:
	if token != _token or _handed:
		return
	_handed = true
	if not _builder.is_valid():
		_abort(token)
		return
	var scene: Node = _builder.call(_mode)
	if scene == null:
		_abort(token)
		return
	var rounds := scene.get_node_or_null("RoundManager")
	if rounds != null:
		rounds.auto_start = false
	var tree := get_tree()
	var outgoing := tree.current_scene
	tree.root.add_child(scene)
	tree.current_scene = scene
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	_game = scene
	handoff_count += 1
	if outgoing != null and outgoing != scene and is_instance_valid(outgoing):
		outgoing.queue_free()


func _finish(token: int) -> void:
	if token != _token or not _running:
		return
	_running = false
	phase = Phase.IDLE
	_hide_slabs()
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var game := _game
	_game = null
	_builder = Callable()
	if game == null or not is_instance_valid(game):
		return
	game.process_mode = Node.PROCESS_MODE_INHERIT
	var rounds := game.get_node_or_null("RoundManager")
	if rounds != null and rounds.round_state == rounds.RoundState.IDLE:
		rounds.start_match()


func _abort(token: int) -> void:
	if token != _token:
		return
	_running = false
	phase = Phase.IDLE
	_handed = false
	_hide_slabs()
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_builder = Callable()
	_game = null


func _hide_slabs() -> void:
	if _back != null:
		_back.visible = false
	if _front != null:
		_front.visible = false


func _place(front_progress: float, back_progress: float) -> void:
	_back.position = Vector2(_x_for(back_progress), _origin_y)
	_front.position = Vector2(_x_for(front_progress), _origin_y)
	_back.queue_redraw()
	_front.queue_redraw()


func _x_for(progress: float) -> float:
	if progress <= 1.0:
		return lerpf(_start_x, _cover_x, progress)
	return lerpf(_cover_x, _end_x, progress - 1.0)


func _progress(motion: float, delay: float) -> float:
	var t := motion - delay
	if t <= 0.0:
		return 0.0
	if t < WIPE_IN:
		return t / WIPE_IN
	return 1.0 + clampf((t - WIPE_IN) / WIPE_OUT, 0.0, 1.0)


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	if view.x < 2.0 or view.y < 2.0:
		view = VIEW_FALLBACK
	_view = view
	_body = Vector2(view.x + PAD_X, view.y + PAD_Y)
	_origin_y = -PAD_Y * 0.5
	var y_top := -_origin_y
	var y_bottom := view.y - _origin_y
	var left_top := SHEAR * (1.0 - y_top / _body.y)
	var left_bottom := SHEAR * (1.0 - y_bottom / _body.y)
	var max_left := maxf(left_top, left_bottom)
	var min_left := minf(left_top, left_bottom)
	var cover_low := view.x - (min_left + _body.x) + 48.0
	var cover_high := -max_left - 48.0
	_cover_x = (cover_low + cover_high) * 0.5
	_start_x = -(max_left + _body.x) - 120.0
	_end_x = view.x - min_left + 120.0
	_back.configure(_body, SHEAR)
	_front.configure(_body, SHEAR)


func _slab_covers(slab: WipeSlab) -> bool:
	var polygon := slab.world_points()
	var samples := PackedVector2Array([
		Vector2(2, 2),
		Vector2(_view.x - 2, 2),
		Vector2(2, _view.y - 2),
		Vector2(_view.x - 2, _view.y - 2),
		Vector2(_view.x * 0.5, 2),
		Vector2(_view.x * 0.5, _view.y - 2),
		Vector2(2, _view.y * 0.5),
		Vector2(_view.x - 2, _view.y * 0.5),
		_view * 0.5,
	])
	for point in samples:
		if not Geometry2D.is_point_in_polygon(point, polygon):
			return false
	return true


class WipeSlab:
	extends Control

	var fill := Color.WHITE
	var shear := 0.0
	var body := Vector2.ZERO


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false


	func configure(next_body: Vector2, next_shear: float) -> void:
		body = next_body
		shear = next_shear
		size = Vector2(body.x + shear, body.y)
		queue_redraw()


	func world_points() -> PackedVector2Array:
		var shifted := PackedVector2Array()
		for point in _points():
			shifted.append(position + point)
		return shifted


	func _draw() -> void:
		if body == Vector2.ZERO:
			return
		draw_colored_polygon(_points(), fill)


	func _points() -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(shear, 0.0),
			Vector2(shear + body.x, 0.0),
			Vector2(body.x, body.y),
			Vector2(0.0, body.y),
		])
