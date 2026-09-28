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
@export_range(0.0, 100.0, 0.1, "or_greater") var evade_stamina_cost := 4.0
@export_range(0.0, 2.0, 0.01, "or_greater") var evade_retrigger_interval := 0.12

@export_group("Movement Targets (POV — X locked; full-frame clipping)")
## Full-frame Player PNG fills the viewport: any X translation clips.
## Evade feel comes from World/Opponent parallax only.
@export var left_offset := Vector2(0.0, 4.0)
@export var right_offset := Vector2(0.0, 4.0)
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


## Explicit press attempt: may open a gameplay window (stamina + retrigger).
## Movement must already be updated by the caller.
## Returns true if a new gameplay window started.
## Active window is NOT extended when retrigger blocks; when retrigger is ready,
## a fresh window replaces the previous one (no infinite extension via same press).
func try_begin_window(direction: int) -> bool:
	if direction == Direction.NONE:
		return false
	if _retrigger_remaining > 0.0:
		if print_events:
			print("Evade window blocked: retrigger %.2fs" % _retrigger_remaining)
		return false
	if player_stamina == null or not player_stamina.can_afford(evade_stamina_cost):
		if print_events:
			print("Evade window blocked: stamina")
		return false

	if not player_stamina.spend_for_action(evade_stamina_cost):
		return false

	## Replace any active window with a fresh timing window.
	window_active = true
	window_direction = direction
	last_window_direction = direction
	_window_remaining = evade_window
	_retrigger_remaining = evade_retrigger_interval
	evade_window_changed.emit(true, window_direction)
	if print_events:
		print("Evade window START | dir=%d | cost=%.0f" % [direction, evade_stamina_cost])
	return true

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
	if window_active:
		_end_window()
	window_active = false
	_window_remaining = 0.0
	window_direction = Direction.NONE
	_retrigger_remaining = 0.0
	set_movement_direction(Direction.NONE)


func center_movement() -> void:
	set_movement_direction(Direction.NONE)
