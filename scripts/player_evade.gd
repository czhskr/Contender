class_name PlayerEvade
extends Node

## Continuous Evade Movement (visual) + independent Evade Timing Window (gameplay).
## Movement has no recovery. Window costs stamina and uses retrigger interval.

signal movement_target_changed(target: Vector2, direction: int)
signal evade_window_changed(active: bool, direction: int)

enum Direction {
	NONE = 0,
	LEFT = 1,
	DOWN = 2,
	RIGHT = 3,
}

const PlayerStaminaType = preload("res://scripts/player_stamina.gd")

@export var player_stamina: PlayerStaminaType

@export_group("Gameplay Timing")
@export_range(0.0, 2.0, 0.01, "or_greater") var evade_window := 0.18
@export_range(0.0, 2.0, 0.01, "or_greater") var evade_retrigger_interval := 0.12

@export_group("Movement Targets (POV — X locked; full-frame clipping)")
## Full-frame Player PNG fills the viewport: any X translation clips.
## Evade feel comes from World/Opponent parallax only.
@export var left_offset := Vector2(0.0, 10.0)
@export var right_offset := Vector2(0.0, 10.0)
@export var down_offset := Vector2(0.0, 10.0)

@export_group("Debug")
@export var print_events := false

## Held movement direction (visual).
var movement_direction := Direction.NONE
var movement_target := Vector2.ZERO

## Gameplay window.
var window_active := false
var window_direction := Direction.NONE
var _window_remaining := 0.0
var _retrigger_remaining := 0.0

## Last direction that successfully opened a window (for pass-by presentation).
var last_window_direction := Direction.NONE
## After a HIT, this lateral direction stays off until that key is released.
var _movement_release_lock := Direction.NONE


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _retrigger_remaining > 0.0:
		_retrigger_remaining = maxf(_retrigger_remaining - delta, 0.0)
	if window_active:
		_window_remaining -= delta
		if _window_remaining <= 0.0:
			_end_window()


func set_movement_direction(direction: int) -> void:
	if direction != Direction.NONE and direction == _movement_release_lock:
		return
	if direction == movement_direction:
		return
	movement_direction = direction
	movement_target = offset_for_direction(direction)
	movement_target_changed.emit(movement_target, movement_direction)


func offset_for_direction(direction: int) -> Vector2:
	match direction:
		Direction.LEFT:
			return left_offset
		Direction.RIGHT:
			return right_offset
		Direction.DOWN:
			return down_offset
		_:
			return Vector2.ZERO


## Explicit press: opens the gameplay window. Does not spend Stamina.
func try_begin_window(direction: int) -> bool:
	if direction == Direction.NONE:
		return false
	if _combat_actions_locked():
		return false
	if _retrigger_remaining > 0.0:
		if print_events:
			print("Evade window blocked: retrigger %.2fs" % _retrigger_remaining)
		return false

	window_active = true
	window_direction = direction
	last_window_direction = direction
	_window_remaining = _scaled_player_value(evade_window, "evade_window")
	_retrigger_remaining = _scaled_player_value(evade_retrigger_interval, "evade_retrigger")
	evade_window_changed.emit(true, window_direction)
	if print_events:
		print("Evade window START | dir=%d" % direction)
	return true


func _scaled_player_value(base_value: float, field: String) -> float:
	if not is_inside_tree():
		return base_value
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager == null:
		return base_value
	return base_value * preload("res://scripts/trait_math.gd").product(manager.player_traits, field)

func is_window_active() -> bool:
	return window_active


func end_window() -> void:
	if window_active:
		_end_window()


func _end_window() -> void:
	window_active = false
	_window_remaining = 0.0
	var dir := window_direction
	window_direction = Direction.NONE
	evade_window_changed.emit(false, dir)
	if print_events:
		print("Evade window END")


## HIT / Knockdown / Round / Match — clear movement + window.
func clear_all() -> void:
	_movement_release_lock = Direction.NONE
	if window_active:
		_end_window()
	window_active = false
	_window_remaining = 0.0
	window_direction = Direction.NONE
	_retrigger_remaining = 0.0
	set_movement_direction(Direction.NONE)


func center_movement() -> void:
	set_movement_direction(Direction.NONE)


## HIT breaks LEFT/RIGHT movement only. The same key must be released before it can return.
func break_lateral_movement_until_release() -> void:
	var direction := movement_direction
	if direction != Direction.LEFT and direction != Direction.RIGHT:
		return
	if window_active and window_direction == direction:
		end_window()
	_movement_release_lock = direction
	set_movement_direction(Direction.NONE)


func notify_direction_released(direction: int) -> void:
	if _movement_release_lock == direction:
		_movement_release_lock = Direction.NONE


func _combat_actions_locked() -> bool:
	if not is_inside_tree():
		return false
	var knockdown = get_node_or_null("../KnockdownManager")
	return knockdown != null and knockdown.has_method("new_actions_locked") and knockdown.new_actions_locked()
