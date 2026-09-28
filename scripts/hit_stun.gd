class_name HitStun
extends Node

## Normal HIT does not gameplay-stun either fighter.
## The node stays so existing scene paths remain valid.

signal hit_stun_started(duration: float)
signal hit_stun_ended()
signal hit_stun_changed(is_stunned: bool, time_remaining: float)


func _process(_delta: float) -> void:
	pass


func is_hit_stunned() -> bool:
	return false


func get_time_remaining() -> float:
	return 0.0


func can_apply_new_stun() -> bool:
	return false


func apply_hit_stun(_duration: float = -1.0) -> void:
	pass


func clear_hit_stun() -> void:
	pass
