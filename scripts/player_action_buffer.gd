class_name PlayerActionBuffer
extends Node

## 1-slot action buffer + cancel-window thresholds (Inspector-tunable).
## Does not spend stamina. Does not own combat rules — combat_prototype executes.

signal buffer_changed(kind: int, attack: int)

enum Kind {
	NONE = 0,
	ATTACK = 1,
	SLIP_LEFT = 2,
	SLIP_RIGHT = 3,
	GUARD = 4,
}

@export_group("Buffer")
## How long attack/slip inputs stay buffered before discard.
@export_range(0.0, 2.0, 0.01, "or_greater") var buffer_duration := 0.20

@export_group("Attack Recovery Cancel")
@export_range(0.0, 1.0, 0.01) var attack_to_attack := 0.50
@export_range(0.0, 1.0, 0.01) var attack_to_slip := 0.35
@export_range(0.0, 1.0, 0.01) var attack_to_guard := 0.25

@export_group("Slip Cancel")
@export_range(0.0, 1.0, 0.01) var slip_to_attack := 0.70
@export_range(0.0, 1.0, 0.01) var slip_to_slip := 0.70
@export_range(0.0, 1.0, 0.01) var slip_to_guard := 0.65

var kind := Kind.NONE
var attack_index := -1

## Attack/slip TTL. Guard uses < 0 (no expiry; cleared on Space release).
var _ttl := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if kind == Kind.NONE or kind == Kind.GUARD:
		return
	if _ttl < 0.0:
		return
	_ttl -= delta
	if _ttl <= 0.0:
		clear()


func clear() -> void:
	if kind == Kind.NONE and attack_index < 0:
		return
	kind = Kind.NONE
	attack_index = -1
	_ttl = 0.0
	buffer_changed.emit(kind, attack_index)


func clear_guard() -> void:
	if kind == Kind.GUARD:
		clear()


func has_buffered() -> bool:
	return kind != Kind.NONE


func buffer_attack(attack: int) -> void:
	kind = Kind.ATTACK
	attack_index = attack
	_ttl = buffer_duration
	buffer_changed.emit(kind, attack_index)


func buffer_slip_left() -> void:
	kind = Kind.SLIP_LEFT
	attack_index = -1
	_ttl = buffer_duration
	buffer_changed.emit(kind, attack_index)


func buffer_slip_right() -> void:
	kind = Kind.SLIP_RIGHT
	attack_index = -1
	_ttl = buffer_duration
	buffer_changed.emit(kind, attack_index)


func buffer_guard() -> void:
	## Hold-based: do not expire while Space remains held.
	kind = Kind.GUARD
	attack_index = -1
	_ttl = -1.0
	buffer_changed.emit(kind, attack_index)


func is_attack() -> bool:
	return kind == Kind.ATTACK


func is_slip() -> bool:
	return kind == Kind.SLIP_LEFT or kind == Kind.SLIP_RIGHT


func is_guard() -> bool:
	return kind == Kind.GUARD


func get_ttl() -> float:
	return _ttl
