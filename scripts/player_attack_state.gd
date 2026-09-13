class_name PlayerAttackState
extends Node

const AttackDataType = preload("res://scripts/attack_data.gd")

signal state_changed(state: AttackState, attack: int)
signal attack_rejected(requested_attack: int, current_attack: int)

enum AttackState {
	IDLE,
	STARTUP,
	ACTIVE,
	RECOVERY,
}

@export var attacks: Array[AttackDataType] = []

var current_state := AttackState.IDLE
var current_attack := -1

var _current_data: AttackDataType
var _time_remaining := 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_time_remaining -= delta

	while _time_remaining <= 0.0 and current_state != AttackState.IDLE:
		var overflow := -_time_remaining
		_advance_state()
		_time_remaining -= overflow


func try_start_attack(attack: int) -> bool:
	if not can_start_attack():
		attack_rejected.emit(attack, current_attack)
		return false

	var attack_data := get_attack_data(attack)
	if attack_data == null:
		push_error("Attack data is missing for attack type %d." % attack)
		return false

	_current_data = attack_data
	current_attack = attack
	set_process(true)
	_enter_state(AttackState.STARTUP, _current_data.startup_time)
	return true


func can_start_attack() -> bool:
	return current_state == AttackState.IDLE


func _advance_state() -> void:
	match current_state:
		AttackState.STARTUP:
			_enter_state(AttackState.ACTIVE, _current_data.active_time)
		AttackState.ACTIVE:
			_enter_state(AttackState.RECOVERY, _current_data.recovery_time)
		AttackState.RECOVERY:
			current_attack = -1
			_current_data = null
			set_process(false)
			_enter_state(AttackState.IDLE, 0.0)


func _enter_state(next_state: AttackState, duration: float) -> void:
	current_state = next_state
	_time_remaining = duration
	state_changed.emit(current_state, current_attack)


func get_attack_data(attack: int) -> AttackDataType:
	for attack_data in attacks:
		if attack_data.attack_type == attack:
			return attack_data

	return null
