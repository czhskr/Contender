class_name KnockdownMeter
extends Node

## Remaining knockdown durability. Starts full and falls as damage lands.
## Reaching 0 triggers Knockdown. It is not remaining HP and it is not Final KO.

signal meter_changed(current_meter: float, max_meter: float)
signal meter_filled()

@export_range(1.0, 1000.0, 1.0, "or_greater") var max_meter := 300.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_meter := 300.0

var current_meter := 0.0


func _ready() -> void:
	current_meter = clampf(initial_meter, 0.0, max_meter)
	meter_changed.emit(current_meter, max_meter)


func get_meter() -> float:
	return current_meter


func is_knockdown_threshold() -> bool:
	return current_meter <= 0.0


func apply_knockdown_damage(amount: float) -> float:
	var before := current_meter
	current_meter = clampf(current_meter - maxf(amount, 0.0), 0.0, max_meter)
	var applied := before - current_meter
	if applied > 0.0:
		meter_changed.emit(current_meter, max_meter)
	if before > 0.0 and current_meter <= 0.0:
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
	set_meter(max_meter)
