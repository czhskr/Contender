extends SceneTree

## Visual motion regression (breathing / slip POV / parallax / shake / recovery).
## Run: godot --headless --path . -s res://visual_motion_smoke_test.gd

const PlayerVisualType = preload("res://scripts/player_visual.gd")
const OpponentVisualType = preload("res://scripts/opponent_visual.gd")
const CombatVisualRootType = preload("res://scripts/combat_visual_root.gd")
const BackgroundVisualType = preload("res://scripts/background_visual.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	_check_defaults(failures)
	await _check_compose_and_breathing(failures)
	await _check_slip_pov_absolute(failures)
	_check_parallax_and_shake_wiring(failures)
	_check_opponent_recovery(failures)
	_check_no_player_health(failures)
	_check_scene(failures)

	if failures.is_empty():
		print("SMOKE PASS: visual motion")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_defaults(failures: Array[String]) -> void:
	var player := PlayerVisualType.new()
	var opponent := OpponentVisualType.new()
	var visual_root := CombatVisualRootType.new()
	if not is_equal_approx(player.breathing_amplitude, 6.0):
		failures.append("Player breathing_amplitude != 6")
	if not is_equal_approx(player.breathing_cycle_seconds, 1.6):
		failures.append("Player breathing_cycle_seconds != 1.6")
	if not is_equal_approx(player.slip_pov_x, 42.0):
		failures.append("slip_pov_x != 42")
	if not is_equal_approx(player.slip_pov_y, 14.0):
		failures.append("slip_pov_y != 14")
	if not is_equal_approx(opponent.breathing_amplitude, 6.0):
		failures.append("Opponent breathing_amplitude != 6")
	if not is_equal_approx(opponent.attack_pose_hold_seconds, 0.20):
		failures.append("attack_pose_hold_seconds != 0.20")
	if not is_equal_approx(visual_root.parallax_crowd_x, 6.0):
		failures.append("parallax_crowd_x != 6")
	if not is_equal_approx(visual_root.parallax_ring_x, 14.0):
		failures.append("parallax_ring_x != 14")
	if not is_equal_approx(visual_root.parallax_opponent_x, 24.0):
		failures.append("parallax_opponent_x != 24")
	if not is_equal_approx(visual_root.opponent_hit_shake_strength, 3.0):
		failures.append("opponent_hit_shake_strength != 3")
	if not is_equal_approx(visual_root.player_hit_shake_strength, 7.0):
		failures.append("player_hit_shake_strength != 7")
	player.free()
	opponent.free()
	visual_root.free()


func _check_compose_and_breathing(failures: Array[String]) -> void:
	var player := PlayerVisualType.new()
	root.add_child(player)
	await process_frame
	if not player._breathing_active:
		failures.append("Idle should start breathing")
	var base_y := player.asset_base_position.y
	player._set_breathing_offset(Vector2(0.0, 6.0))
	if player.breathing_offset.y < 0.0:
		failures.append("Breathing must not go above base (-Y)")
	if player._anchor != null and player._anchor.position.y < base_y:
		failures.append("Composed Y must never be above base")
	player._stop_breathing()
	if player.breathing_offset != Vector2.ZERO:
		failures.append("Stop breathing should zero offset")
	if player.asset_base_position != Vector2.ZERO:
		failures.append("Breathing mutated asset_base_position")
	player.queue_free()
	await process_frame

	var opponent := OpponentVisualType.new()
	root.add_child(opponent)
	await process_frame
	if not opponent._breathing_active:
		failures.append("Opponent Idle should start breathing")
	opponent.set_parallax_offset(Vector2(24.0, 0.0))
	var expected_x := opponent.asset_base_position.x + 24.0
	if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.x, expected_x):
		failures.append("Opponent parallax not additive")
	opponent.set_parallax_offset(Vector2.ZERO)
	if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.x, opponent.asset_base_position.x):
		failures.append("Opponent parallax did not return to base")
	opponent.queue_free()
	await process_frame


func _check_slip_pov_absolute(failures: Array[String]) -> void:
	var player := PlayerVisualType.new()
	root.add_child(player)
	await process_frame
	player.slip_pov_tween_seconds = 0.01
	player._begin_slip_pov(-1)
	player.pov_offset = Vector2(-player.slip_pov_x, player.slip_pov_y)
	player._apply_composed_transform()
	if not is_equal_approx(player.pov_offset.x, -42.0):
		failures.append("Slip Left POV X expected -42")
	player._begin_slip_pov(-1)
	player.pov_offset = Vector2(-player.slip_pov_x, player.slip_pov_y)
	if not is_equal_approx(player.pov_offset.x, -42.0):
		failures.append("Consecutive Slip Left drifted POV")
	player._begin_slip_pov(1)
	player.pov_offset = Vector2(player.slip_pov_x, player.slip_pov_y)
	if not is_equal_approx(player.pov_offset.x, 42.0):
		failures.append("Slip Right POV X expected +42")
	player._reset_pov_immediate()
	if player.pov_offset != Vector2.ZERO:
		failures.append("POV reset failed")
	player.queue_free()
	await process_frame


func _check_parallax_and_shake_wiring(failures: Array[String]) -> void:
	var visual_root := CombatVisualRootType.new()
	if not visual_root.has_method("_tween_world_parallax"):
		failures.append("CombatVisualRoot missing parallax tween")
	if not visual_root.has_method("_play_shake"):
		failures.append("CombatVisualRoot missing shake")
	if not visual_root.has_method("_clear_shake"):
		failures.append("CombatVisualRoot missing clear shake")
	visual_root.base_position = Vector2(10, 20)
	visual_root.set_shake_offset(Vector2(3, -2))
	if visual_root.position != Vector2(13, 18):
		failures.append("Shake compose on CombatVisualRoot failed")
	visual_root.set_shake_offset(Vector2.ZERO)
	if visual_root.position != visual_root.base_position:
		failures.append("Shake did not return to base")
	visual_root.free()

	var bg := BackgroundVisualType.new()
	if not bg.has_method("set_crowd_parallax") or not bg.has_method("set_ring_parallax"):
		failures.append("BackgroundVisual missing parallax setters")
	bg.free()


func _check_opponent_recovery(failures: Array[String]) -> void:
	var left = load("res://data/opponent_attacks/left_straight.tres")
	var right = load("res://data/opponent_attacks/right_straight.tres")
	if left == null or not is_equal_approx(left.recovery_time, 0.50):
		failures.append(
			"Opp L Straight recovery expected 0.50, got %s"
			% str(left.recovery_time if left else null)
		)
	if right == null or not is_equal_approx(right.recovery_time, 0.55):
		failures.append(
			"Opp R Straight recovery expected 0.55, got %s"
			% str(right.recovery_time if right else null)
		)
	if left != null and not is_equal_approx(left.startup_time, 0.8):
		failures.append("Opp L Straight startup changed")
	if left != null and not is_equal_approx(left.active_time, 0.1):
		failures.append("Opp L Straight active changed")
	if right != null and not is_equal_approx(right.startup_time, 0.9):
		failures.append("Opp R Straight startup changed")


func _check_no_player_health(failures: Array[String]) -> void:
	if FileAccess.file_exists("res://scripts/player_health.gd"):
		failures.append("player_health.gd still exists")
	if FileAccess.file_exists("res://scripts/player_health.gd.uid"):
		failures.append("player_health.gd.uid still exists")


func _check_scene(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn failed to load")
		return
	var scene := packed.instantiate()
	var visual_root = scene.get_node_or_null("CombatVisualRoot")
	if visual_root == null:
		failures.append("CombatVisualRoot missing")
	else:
		if visual_root.player_action_state == null:
			failures.append("CombatVisualRoot.player_action_state not wired")
		if visual_root.offense_resolver == null:
			failures.append("CombatVisualRoot.offense_resolver not wired")
		if visual_root.defense_resolver == null:
			failures.append("CombatVisualRoot.defense_resolver not wired")
		if visual_root.background_visual == null:
			failures.append("CombatVisualRoot.background_visual not wired")
		if visual_root.opponent_visual == null:
			failures.append("CombatVisualRoot.opponent_visual not wired")
	var opp_v = scene.get_node_or_null("CombatVisualRoot/OpponentVisual")
	if opp_v != null and not is_equal_approx(opp_v.attack_pose_hold_seconds, 0.20):
		failures.append("Scene OpponentVisual hold != 0.20")
	if scene.get_node_or_null("CombatVisualRoot/DebugHUD") != null:
		failures.append("DebugHUD must not be under CombatVisualRoot")
	if scene.get_node_or_null("DebugHUD") == null:
		failures.append("DebugHUD missing at scene root")
	scene.free()
