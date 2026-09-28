extends SceneTree

## Evade presentation stays on the opponent when the punch texture swaps.
## godot --headless --path . -s res://evade_attack_visual_smoke_test.gd

const RootType = preload("res://scripts/combat_visual_root.gd")
const OppType = preload("res://scripts/opponent_visual.gd")
const EvadeType = preload("res://scripts/player_evade.gd")
const AttackType = preload("res://scripts/opponent_attack_state.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_direction(failures, EvadeType.Direction.LEFT, "LEFT", "EVADE")
	_check_direction(failures, EvadeType.Direction.RIGHT, "RIGHT", "EVADE")
	_check_direction(failures, EvadeType.Direction.DOWN, "DOWN", "EVADE")
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
	if direction == EvadeType.Direction.LEFT and active.x <= idle.x + 100.0:
		failures.append("LEFT punch did not move aside with the evade")
	if direction == EvadeType.Direction.RIGHT and active.x >= idle.x - 100.0:
		failures.append("RIGHT punch did not move aside with the evade")
	if direction == EvadeType.Direction.DOWN and active.y >= idle.y - 200.0:
		failures.append("DOWN punch did not rise above the eye line")
	evade.window_active = false
	opponent._on_attack_state_changed(AttackType.AttackState.IDLE, null)
	root.free()


func _check_unchanged_parallax_exports(failures: Array[String]) -> void:
	var root := RootType.new()
	if not is_equal_approx(root.parallax_opponent_x, 130.0):
		failures.append("opponent horizontal parallax changed")
	if not is_equal_approx(root.parallax_opponent_down_y, 40.0):
		failures.append("opponent down parallax changed")
	if not is_equal_approx(root.evade_passby_offset_x, 130.0):
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
