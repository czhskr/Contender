class_name HandReuse
extends RefCounted

## Per-hand reuse clock. Time is measured from each attack's start.
## LEFT and RIGHT do not share a timer. This is not a global attack cooldown.

const DEFAULT_INTERVAL := 0.45

var interval := DEFAULT_INTERVAL
## Tests set this to a virtual clock. Negative means wall time.
var debug_now := -1.0
var _left_ready_at := -1.0
var _right_ready_at := -1.0


func now() -> float:
	if debug_now >= 0.0:
		return debug_now
	return Time.get_ticks_msec() / 1000.0


func note_started(attack_type: int) -> void:
	var ready_at := now() + interval
	if AttackData.hand_of(attack_type) == AttackData.Hand.LEFT:
		_left_ready_at = ready_at
	else:
		_right_ready_at = ready_at


func is_ready(attack_type: int) -> bool:
	var ready_at := _right_ready_at
	if AttackData.hand_of(attack_type) == AttackData.Hand.LEFT:
		ready_at = _left_ready_at
	if ready_at < 0.0:
		return true
	return now() >= ready_at - 0.000001
