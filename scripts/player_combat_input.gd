class_name PlayerCombatInput
extends Node

signal attack_requested(attack: AttackType)
signal defense_requested(defense: DefenseType)
signal guard_changed(is_guarding: bool)

enum AttackType {
	LEFT_STRAIGHT,
	RIGHT_STRAIGHT,
	LEFT_HOOK,
	RIGHT_HOOK,
}

enum DefenseType {
	SLIP_LEFT,
	SLIP_RIGHT,
}

const LEFT_STRAIGHT := &"combat_left_straight"
const RIGHT_STRAIGHT := &"combat_right_straight"
const LEFT_HOOK := &"combat_left_hook"
const RIGHT_HOOK := &"combat_right_hook"
const SLIP_LEFT := &"combat_slip_left"
const SLIP_RIGHT := &"combat_slip_right"
const HIGH_GUARD := &"combat_high_guard"

var is_guarding := false


func _unhandled_input(event: InputEvent) -> void:
	## Guard release first so same-frame Attack/Slip after Space-up is not blocked.
	if event.is_action_released(HIGH_GUARD):
		_set_guarding(false)
		return

	if event.is_action_pressed(HIGH_GUARD):
		_set_guarding(true)
		return

	if event.is_action_pressed(LEFT_HOOK, false, true):
		_request_attack(AttackType.LEFT_HOOK)
	elif event.is_action_pressed(RIGHT_HOOK, false, true):
		_request_attack(AttackType.RIGHT_HOOK)
	elif event.is_action_pressed(LEFT_STRAIGHT, false, true):
		_request_attack(AttackType.LEFT_STRAIGHT)
	elif event.is_action_pressed(RIGHT_STRAIGHT, false, true):
		_request_attack(AttackType.RIGHT_STRAIGHT)
	elif event.is_action_pressed(SLIP_LEFT, false, true):
		defense_requested.emit(DefenseType.SLIP_LEFT)
		_consume_event()
	elif event.is_action_pressed(SLIP_RIGHT, false, true):
		defense_requested.emit(DefenseType.SLIP_RIGHT)
		_consume_event()


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
