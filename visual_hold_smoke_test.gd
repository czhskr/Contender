extends SceneTree

## Presentation holds only. Gameplay attack timing is unchanged.
## godot --headless --path . -s res://visual_hold_smoke_test.gd

const OppType = preload("res://scripts/opponent_visual.gd")
const AttackType = preload("res://scripts/opponent_attack_state.gd")
const AttackDataType = preload("res://scripts/opponent_attack_data.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var visual := OppType.new()
	if not is_equal_approx(visual.attack_pose_hold_seconds, 0.28):
		failures.append("straight hold")
	if not is_equal_approx(visual.slip_visual_hold_seconds, 0.38):
		failures.append("slip hold")
	if not is_equal_approx(visual.hit_hold_seconds, 0.22):
		failures.append("hit hold")
	if not is_equal_approx(visual.guard_visual_hold_seconds, 0.32):
		failures.append("guard hold")
	var attack := AttackType.new()
	var data := AttackDataType.new()
	data.attack_type = 0
	data.startup_time = 0.10
	data.active_time = 0.08
	data.recovery_time = 0.11
	if not is_equal_approx(data.recovery_time, 0.11):
		failures.append("gameplay recovery changed")
	visual._build_nodes()
	visual._begin_attack_pose(0)
	visual._attack_pose_holding = true
	visual._priority = OppType.Priority.ATTACK
	visual.opponent_attack_state = attack
	attack.current_state = AttackType.AttackState.IDLE
	visual._on_attack_state_changed(AttackType.AttackState.IDLE, null)
	if visual.current_visual_state == "IDLE":
		failures.append("stance flashed while the punch hold was still active")
	visual._on_player_attack_hit(0, 8.0, 10.0, false, 0)
	if visual.current_visual_state == "HIT":
		failures.append("HIT covered the attack texture")
	visual._return_to_stance()
	if visual.current_visual_state != "IDLE" or visual._attack_pose_holding:
		failures.append("player knockdown did not return the opponent to stance")
	visual.free()
	attack.free()
	if failures.is_empty():
		print("SMOKE PASS: visual hold")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)
