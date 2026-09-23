class_name HitStun
extends Node

## Short full-action lock after a real HIT. Does not decide combat outcomes.

signal hit_stun_started(duration: float)
signal hit_stun_ended()
signal hit_stun_changed(is_stunned: bool, time_remaining: float)

@export_range(0.0, 5.0, 0.01, "or_greater") var hit_stun_duration := 0.35

@export_group("Debug")
@export var print_events := false

var _time_remaining := 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if _time_remaining <= 0.0:
		return
	_time_remaining = maxf(_time_remaining - delta, 0.0)
	hit_stun_changed.emit(true, _time_remaining)
	if _time_remaining <= 0.0:
		_end_stun()


func is_hit_stunned() -> bool:
	return _time_remaining > 0.0


func get_time_remaining() -> float:
	return _time_remaining


## Refresh from full duration (re-hit during stun restarts the timer).
func apply_hit_stun(duration: float = -1.0) -> void:
	var use_duration := hit_stun_duration if duration < 0.0 else duration
	if use_duration <= 0.0:
		clear_hit_stun()
		return
	var was_active := is_hit_stunned()
	_time_remaining = use_duration
	set_process(true)
	if not was_active:
		hit_stun_started.emit(use_duration)
	hit_stun_changed.emit(true, _time_remaining)
	if print_events:
		print(
			"[HitStun:%s] apply %.2fs%s"
			% [name, use_duration, " (refresh)" if was_active else ""]
		)


func clear_hit_stun() -> void:
	if not is_hit_stunned() and _time_remaining <= 0.0:
		set_process(false)
		return
	_time_remaining = 0.0
	set_process(false)
	hit_stun_ended.emit()
	hit_stun_changed.emit(false, 0.0)
	if print_events:
		print("[HitStun:%s] clear" % name)


func _end_stun() -> void:
	set_process(false)
	hit_stun_ended.emit()
	hit_stun_changed.emit(false, 0.0)
	if print_events:
		print("[HitStun:%s] ended" % name)
