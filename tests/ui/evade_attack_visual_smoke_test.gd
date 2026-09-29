extends SceneTree

## Evade presentation stays on the opponent when the punch texture swaps.
## godot --headless --path . -s res://tests/ui/evade_attack_visual_smoke_test.gd

const RootType = preload("res://scripts/combat_visual_root.gd")
const OppType = preload("res://scripts/opponent_visual.gd")
const EvadeType = preload("res://scripts/player_evade.gd")
const AttackType = preload("res://scripts/opponent_attack_state.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_direction(failures, EvadeType.Direction.LEFT, "LEFT", "EVADE")
	_check_direction(failures, EvadeType.Direction.RIGHT, "RIGHT", "EVADE")
	_check_direction(failures, EvadeType.Direction.DOWN, "DOWN", "EVADE")
	_check_down_continuity(failures)
	_check_down_pose_matrix(failures)
	_check_unchanged_parallax_exports(failures)
	_check_hit_does_not_cover_attack(failures)
	_check_knockdown_still_clears_punch(failures)
	if failures.is_empty():
		print("SMOKE PASS: evade attack visual")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_direction(failures: Array[String], direction: int, label: String, result: String) -> void:
	var built: Dictionary = _build()
	var root: RootType = built["root"]
	var opponent: OppType = built["opponent"]
	var evade: EvadeType = built["evade"]
	evade.window_active = true
	evade.window_direction = direction
	evade.last_window_direction = direction
	evade.movement_direction = direction
	root._set_parallax_targets_for_direction(direction)
	root._apply_parallax_offsets()
	opponent._stop_breathing()
	var idle: Vector2 = opponent._anchor.position
	var parallax: Vector2 = opponent.parallax_offset
	opponent._on_attack_state_changed(AttackType.AttackState.STARTUP, null)
	var startup: Vector2 = opponent._anchor.position
	opponent._begin_attack_pose(0)
	var active: Vector2 = opponent._anchor.position
	opponent._on_attack_state_changed(AttackType.AttackState.RECOVERY, null)
	var recovery: Vector2 = opponent._anchor.position
	var preserved := (
		startup.distance_to(idle) < 0.5
		and active.distance_to(opponent.asset_base_position) > 1.0
		and recovery.distance_to(active) < 0.5
		and opponent.parallax_offset.distance_to(parallax) < 0.5
	)
	print("[EVADE_VISUAL]")
	print("direction=%s" % label)
	print("gameplay_result=%s" % result)
	print("idle_offset=%s" % idle)
	print("startup_offset=%s" % startup)
	print("active_offset=%s" % active)
	print("offset_preserved=%s" % ("true" if preserved else "false"))
	if not preserved:
		failures.append("%s offset was not preserved across the punch texture" % label)
	if direction == EvadeType.Direction.LEFT and active.x <= idle.x + 30.0:
		failures.append("LEFT punch did not move aside with the evade")
	if direction == EvadeType.Direction.RIGHT and active.x >= idle.x - 30.0:
		failures.append("RIGHT punch did not move aside with the evade")
	if direction == EvadeType.Direction.DOWN and absf(active.y - idle.y) > 1.0:
		failures.append("DOWN active moved the body from %.1f to %.1f" % [idle.y, active.y])
	evade.window_active = false
	opponent._on_attack_state_changed(AttackType.AttackState.IDLE, null)
	root.free()


func _check_down_continuity(failures: Array[String]) -> void:
	var built: Dictionary = _build()
	var root: RootType = built["root"]
	var opponent: OppType = built["opponent"]
	var evade: EvadeType = built["evade"]
	evade.window_active = true
	evade.window_direction = EvadeType.Direction.DOWN
	evade.last_window_direction = EvadeType.Direction.DOWN
	root._set_parallax_targets_for_direction(EvadeType.Direction.DOWN)
	root._apply_parallax_offsets()
	opponent._stop_breathing()
	_log_down("evade_start", opponent)
	opponent._on_attack_state_changed(AttackType.AttackState.STARTUP, null)
	var startup_y: float = opponent._anchor.position.y
	_log_down("startup", opponent)
	opponent._begin_attack_pose(0)
	var enter_y: float = opponent._anchor.position.y
	_log_down("active_enter", opponent)
	if absf(enter_y - startup_y) > 1.0:
		failures.append("DOWN active enter moved the body by %.1f" % absf(enter_y - startup_y))
	var previous := enter_y
	var largest := 0.0
	for _step in 8:
		opponent._process(1.0 / 60.0)
		var delta_y: float = absf(opponent._anchor.position.y - previous)
		largest = maxf(largest, delta_y)
		previous = opponent._anchor.position.y
	_log_down("active_middle", opponent)
	if largest > 20.0:
		failures.append("DOWN miss step was %.1fpx in one frame" % largest)
	var risen: float = startup_y - opponent._anchor.position.y
	var cap: float = root.max_opponent_upward_lift()
	var total_up: float = opponent.asset_base_position.y - opponent._anchor.position.y
	if total_up > cap + 0.5:
		failures.append("DOWN lift %.1f exceeded the framed %.1f and opens a bottom gap" % [total_up, cap])
	if absf(risen) > 1.0:
		failures.append("DOWN body rose %.1f during the punch" % risen)
	evade.window_active = false
	var before_release: float = opponent._anchor.position.y
	opponent._process(1.0 / 60.0)
	if absf(opponent._anchor.position.y - before_release) > 20.0:
		failures.append("DOWN window end snapped")
	for _step in 10:
		opponent._process(1.0 / 60.0)
	_log_down("window_end", opponent)
	if absf(opponent._attack_miss_clearance.y) > 1.0:
		failures.append("DOWN miss did not ease back after the window")
	opponent._on_attack_state_changed(AttackType.AttackState.RECOVERY, null)
	_log_down("recovery", opponent)
	var recovery_y: float = opponent._anchor.position.y
	opponent._show_idle()
	var idle_jump: float = absf(opponent._anchor.position.y - recovery_y)
	if idle_jump > 50.0:
		failures.append("DOWN idle return jumped %.1f" % idle_jump)
	_log_down("idle", opponent)
	root.free()


func _check_down_pose_matrix(failures: Array[String]) -> void:
	_pose_case(failures, "A_idle_while_down", "idle")
	_pose_case(failures, "B_startup_while_down", "startup")
	_pose_case(failures, "C_active_while_down", "active")
	_pose_case(failures, "D_recovery_while_down", "recovery")
	_pose_case(failures, "E_hit_while_attacking", "hit")
	_pose_case(failures, "F_guard_while_down", "guard")
	_pose_case(failures, "G_slip_while_down", "slip")


func _pose_case(failures: Array[String], label: String, pose: String) -> void:
	var built: Dictionary = _build()
	var root: RootType = built["root"]
	var opponent: OppType = built["opponent"]
	var evade: EvadeType = built["evade"]
	evade.window_active = true
	evade.window_direction = EvadeType.Direction.DOWN
	root._set_parallax_targets_for_direction(EvadeType.Direction.DOWN)
	root._apply_parallax_offsets()
	opponent._stop_breathing()
	if pose == "hit":
		opponent._begin_attack_pose(0)
	var base_y: float = opponent.asset_base_position.y
	var before_parallax: float = opponent.parallax_offset.y
	var before: float = opponent._anchor.position.y
	if pose == "idle":
		opponent._show_idle()
	elif pose == "startup":
		opponent._on_attack_state_changed(AttackType.AttackState.STARTUP, null)
	elif pose == "active":
		opponent._begin_attack_pose(0)
	elif pose == "recovery":
		opponent._begin_attack_pose(0)
		opponent._on_attack_state_changed(AttackType.AttackState.RECOVERY, null)
	elif pose == "hit":
		opponent._on_player_attack_hit(0, 8.0, 10.0, false, 0)
	elif pose == "guard":
		opponent._begin_defense_pose("GUARD", opponent.texture_high_guard, 0.25)
	elif pose == "slip":
		opponent._begin_defense_pose("SLIP_LEFT", opponent.texture_slip_left, 0.32)
	for _step in 4:
		opponent._process(1.0 / 60.0)
	var after: float = opponent._anchor.position.y
	if not is_equal_approx(opponent.asset_base_position.y, base_y):
		failures.append("%s changed base position" % label)
	if not is_equal_approx(opponent.parallax_offset.y, before_parallax):
		failures.append("%s reset the duck parallax" % label)
	if absf(after - before) > 1.0:
		failures.append("%s jumped %.1f on pose change" % [label, after - before])
	var lift: float = base_y - after
	if lift > root.max_opponent_upward_lift() + 0.5:
		failures.append("%s lift %.1f opens a bottom gap" % [label, lift])
	root.free()


func _log_down(phase: String, opponent: OppType) -> void:
	print("[EVADE_VISUAL]")
	print("direction=DOWN")
	print("phase=%s" % phase)
	print("hud=absent")
	print("base_y=%.1f" % opponent.asset_base_position.y)
	print("evade_y=%.1f" % opponent.parallax_offset.y)
	print("pass_by_y=%.1f" % opponent._evade_passby_offset.y)
	print("attack_miss_y=%.1f" % opponent._attack_miss_clearance.y)
	print("final_y=%.1f" % opponent._anchor.position.y)


func _check_unchanged_parallax_exports(failures: Array[String]) -> void:
	var root := RootType.new()
	if not is_equal_approx(root.parallax_opponent_x, 280.0):
		failures.append("opponent horizontal parallax changed")
	if not is_equal_approx(root.parallax_opponent_down_y, 40.0):
		failures.append("opponent down parallax changed")
	if not is_equal_approx(root.evade_passby_offset_x, 40.0):
		failures.append("horizontal pass-by changed")
	if not is_equal_approx(root.evade_down_passby_offset_y, 40.0):
		failures.append("down pass-by changed")
	root.free()


func _check_hit_does_not_cover_attack(failures: Array[String]) -> void:
	var built: Dictionary = _build()
	var opponent: OppType = built["opponent"]
	opponent._begin_attack_pose(0)
	var pose: String = opponent.current_visual_state
	opponent._on_player_attack_hit(0, 8.0, 10.0, false, 0)
	if opponent.current_visual_state != pose:
		failures.append("HIT covered the attack texture")
	built["root"].free()


func _check_knockdown_still_clears_punch(failures: Array[String]) -> void:
	var built: Dictionary = _build()
	var opponent: OppType = built["opponent"]
	opponent._attack_pose_holding = true
	opponent._priority = 2
	opponent._return_to_stance()
	if opponent._attack_pose_holding or opponent.current_visual_state != "IDLE":
		failures.append("knockdown stance reset failed")
	built["root"].free()


func _build() -> Dictionary:
	var root := RootType.new()
	var opponent := OppType.new()
	var evade := EvadeType.new()
	root.opponent_visual = opponent
	root.player_evade = evade
	root.add_child(opponent)
	root.add_child(evade)
	get_root().add_child(root)
	opponent._build_nodes()
	opponent._stop_breathing()
	return {"root": root, "opponent": opponent, "evade": evade}
