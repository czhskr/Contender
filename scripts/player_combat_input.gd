class_name PlayerCombatInput
extends Node

signal attack_requested(attack: AttackType)
signal evade_pressed(direction: int) ## Explicit press (not OS key-repeat).
signal evade_hold_changed(direction: int) ## Held movement direction (NONE when released).
signal guard_changed(is_guarding: bool)

enum AttackType {
	LEFT_STRAIGHT,
	RIGHT_STRAIGHT,
	LEFT_HOOK,
	RIGHT_HOOK,
}

## Continuous Evade directions (replaces DefenseType SLIP_*).
enum EvadeDirection {
	NONE = 0,
	LEFT = 1,
	DOWN = 2,
	RIGHT = 3,
}

const LEFT_STRAIGHT := &"combat_left_straight"
const RIGHT_STRAIGHT := &"combat_right_straight"
const LEFT_HOOK := &"combat_left_hook"
const RIGHT_HOOK := &"combat_right_hook"
const EVADE_LEFT := &"combat_slip_left"
const EVADE_RIGHT := &"combat_slip_right"
const EVADE_DOWN := &"combat_evade_down"
const HIGH_GUARD := &"combat_high_guard"

var is_guarding := false
## Most recent held evade direction (stack of held keys).
var held_evade_direction := EvadeDirection.NONE

var _held_stack: Array[int] = []


func _unhandled_input(event: InputEvent) -> void:
	## Guard release first so same-frame Attack/Evade after Space-up is not blocked.
	if event.is_action_released(HIGH_GUARD):
		_set_guarding(false)
		return

	if event.is_action_pressed(HIGH_GUARD):
		_set_guarding(true)
		return

	if event.is_action_pressed(LEFT_HOOK, false, true):
		_request_attack(AttackType.LEFT_HOOK)
		return
	if event.is_action_pressed(RIGHT_HOOK, false, true):
		_request_attack(AttackType.RIGHT_HOOK)
		return
	if event.is_action_pressed(LEFT_STRAIGHT, false, true):
		_request_attack(AttackType.LEFT_STRAIGHT)
		return
	if event.is_action_pressed(RIGHT_STRAIGHT, false, true):
		_request_attack(AttackType.RIGHT_STRAIGHT)
		return

	## Evade: ignore OS key-repeat (echo).
	if event is InputEventKey and event.echo:
		return

	if event.is_action_pressed(EVADE_LEFT, false, true):
		_on_evade_pressed(EvadeDirection.LEFT)
		return
	if event.is_action_pressed(EVADE_DOWN, false, true):
		_on_evade_pressed(EvadeDirection.DOWN)
		return
	if event.is_action_pressed(EVADE_RIGHT, false, true):
		_on_evade_pressed(EvadeDirection.RIGHT)
		return

	if event.is_action_released(EVADE_LEFT):
		_on_evade_released(EvadeDirection.LEFT)
		return
	if event.is_action_released(EVADE_DOWN):
		_on_evade_released(EvadeDirection.DOWN)
		return
	if event.is_action_released(EVADE_RIGHT):
		_on_evade_released(EvadeDirection.RIGHT)
		return


func _on_evade_pressed(direction: int) -> void:
	## Push to stack (last pressed wins while multiple held).
	_held_stack.erase(direction)
	_held_stack.push_back(direction)
	_emit_hold()
	evade_pressed.emit(direction)
	_consume_event()


func _on_evade_released(direction: int) -> void:
	_held_stack.erase(direction)
	_emit_hold()
	_consume_event()


func _emit_hold() -> void:
	var next := EvadeDirection.NONE
	if not _held_stack.is_empty():
		next = _held_stack[_held_stack.size() - 1]
	if next == held_evade_direction:
		return
	held_evade_direction = next
	evade_hold_changed.emit(held_evade_direction)


func clear_held_evade() -> void:
	_held_stack.clear()
	if held_evade_direction != EvadeDirection.NONE:
		held_evade_direction = EvadeDirection.NONE
		evade_hold_changed.emit(held_evade_direction)


func _request_attack(attack: AttackType) -> void:
	attack_requested.emit(attack)
	_consume_event()


func _set_guarding(value: bool) -> void:
	if is_guarding == value:
		return
	is_guarding = value
	guard_changed.emit(is_guarding)
	_consume_event()


func _consume_event() -> void:
	get_viewport().set_input_as_handled()
