class_name FinisherImpactFreeze
extends Node

## Presentation: freeze combat on a true Knockdown finisher HIT (no Engine.time_scale).
## KnockdownManager / Count still begin only after this finishes.

signal finisher_started(downed_side: int)
signal finisher_finished(downed_side: int)

@export_group("Finisher Impact Freeze")
## Wall-clock seconds (Time.get_ticks_msec). Not scaled gameplay time.
@export_range(0.05, 10.0, 0.05, "or_greater") var finisher_freeze_duration := 2.0

@export_group("Wired Nodes")
@export var impact_effect: Node
@export var combat_visual_root: Node

@export_group("Debug")
@export var print_events := false

## True from accept until finished (blocks combat / duplicate finishers).
var is_pending := false
var is_active := false

var _downed_side := 0
var _token := 0
var _end_msec := 0


func _ready() -> void:
	set_process(false)
	if impact_effect == null:
		impact_effect = get_node_or_null("FinisherImpactEffect")
	if combat_visual_root == null:
		var parent := get_parent()
		if parent != null:
			combat_visual_root = parent.get_node_or_null("CombatVisualRoot")


func is_blocking_combat() -> bool:
	return is_pending


func try_begin_finisher(downed_side: int) -> bool:
	## Returns true if this call owns the finisher (caller waits for finisher_finished).
	if is_pending:
		if print_events:
			print("FinisherImpactFreeze: ignore duplicate (already pending)")
		return false
	if downed_side == 0:
		return false

	is_pending = true
	is_active = true
	_downed_side = downed_side
	_token += 1
	_end_msec = Time.get_ticks_msec() + maxi(int(round(finisher_freeze_duration * 1000.0)), 1)
	set_process(true)

	if combat_visual_root != null and combat_visual_root.has_method("set_finisher_freeze"):
		combat_visual_root.set_finisher_freeze(true)
	if impact_effect != null and impact_effect.has_method("play_finisher"):
		impact_effect.play_finisher(finisher_freeze_duration)

	if print_events:
		print(
			"FinisherImpactFreeze START | side=%d | freeze=%.2fs"
			% [downed_side, finisher_freeze_duration]
		)

	finisher_started.emit(downed_side)
	return true


func cancel_and_restore() -> void:
	_token += 1
	is_active = false
	is_pending = false
	set_process(false)
	_stop_presentation()


func _process(_delta: float) -> void:
	if not is_active:
		set_process(false)
		return
	if Time.get_ticks_msec() >= _end_msec:
		var token := _token
		set_process(false)
		_finish(token)


func _finish(token: int) -> void:
	if token != _token:
		return
	is_active = false
	_stop_presentation()
	var side := _downed_side
	is_pending = false
	if print_events:
		print("FinisherImpactFreeze END | side=%d" % side)
	finisher_finished.emit(side)


func _stop_presentation() -> void:
	if impact_effect != null and impact_effect.has_method("stop_immediate"):
		impact_effect.stop_immediate()
	if combat_visual_root != null and combat_visual_root.has_method("set_finisher_freeze"):
		combat_visual_root.set_finisher_freeze(false)


func _exit_tree() -> void:
	_token += 1
	is_active = false
	is_pending = false
	set_process(false)
	_stop_presentation()
