class_name PlayerActionBuffer
extends Node

## 1-slot action buffer + attack recovery cancel thresholds.
## Continuous Evade is not buffered (movement is free; window is press-time).

signal buffer_changed(kind: int, attack: int)

enum Kind {
	NONE = 0,
	ATTACK = 1,
	GUARD = 2,
	EVADE = 3,
}

@export_group("Buffer")
@export_range(0.0, 2.0, 0.01, "or_greater") var buffer_duration := 0.20

@export_group("Attack Recovery Cancel")
@export_range(0.0, 1.0, 0.01) var attack_to_attack := 0.50
@export_range(0.0, 1.0, 0.01) var attack_to_evade := 0.35
@export_range(0.0, 1.0, 0.01) var attack_to_guard := 0.25

var kind := Kind.NONE
var attack_index := -1
var evade_direction := 0

## Attack TTL. Guard uses < 0 (no expiry; cleared on Space release).
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
	if kind == Kind.NONE and attack_index < 0 and evade_direction == 0:
		return
	kind = Kind.NONE
	attack_index = -1
	evade_direction = 0
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
	evade_direction = 0
	_ttl = buffer_duration
	buffer_changed.emit(kind, attack_index)


func buffer_evade(direction: int) -> void:
	kind = Kind.EVADE
	attack_index = -1
	evade_direction = direction
	_ttl = buffer_duration
	buffer_changed.emit(kind, attack_index)


func buffer_guard() -> void:
	kind = Kind.GUARD
	attack_index = -1
	evade_direction = 0
	_ttl = -1.0
	buffer_changed.emit(kind, attack_index)


func is_attack() -> bool:
	return kind == Kind.ATTACK


func is_evade() -> bool:
	return kind == Kind.EVADE


func is_guard() -> bool:
	return kind == Kind.GUARD


func get_ttl() -> float:
	return _ttl
