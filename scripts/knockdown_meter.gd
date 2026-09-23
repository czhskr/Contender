class_name KnockdownMeter
extends Node

## Accumulates knockdown damage from hits. Reaches 100 → Knockdown (not Final KO).

signal meter_changed(current_meter: float, max_meter: float)
signal meter_filled()

@export_range(1.0, 1000.0, 1.0, "or_greater") var max_meter := 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_meter := 0.0

var current_meter := 0.0


func _ready() -> void:
	current_meter = clampf(initial_meter, 0.0, max_meter)
	meter_changed.emit(current_meter, max_meter)


func get_meter() -> float:
	return current_meter


func is_full() -> bool:
	return current_meter >= max_meter


func apply_knockdown_damage(amount: float) -> float:
	var before := current_meter
	current_meter = clampf(current_meter + maxf(amount, 0.0), 0.0, max_meter)
	var applied := current_meter - before
	if applied > 0.0 or amount > 0.0:
		meter_changed.emit(current_meter, max_meter)
	if before < max_meter and current_meter >= max_meter:
		meter_filled.emit()
	return applied


func set_meter(value: float) -> void:
	current_meter = clampf(value, 0.0, max_meter)
	meter_changed.emit(current_meter, max_meter)


func reduce_meter(amount: float) -> float:
	var before := current_meter
	current_meter = clampf(current_meter - maxf(amount, 0.0), 0.0, max_meter)
	var reduced := before - current_meter
	if reduced > 0.0:
		meter_changed.emit(current_meter, max_meter)
	return reduced


func reset_meter() -> void:
	set_meter(0.0)
