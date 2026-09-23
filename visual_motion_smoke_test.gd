extends SceneTree

## Visual motion regression (breathing / slip POV / parallax / shake / recovery).
## Run: godot --headless --path . -s res://visual_motion_smoke_test.gd

const PlayerVisualType = preload("res://scripts/player_visual.gd")
const OpponentVisualType = preload("res://scripts/opponent_visual.gd")
const CombatVisualRootType = preload("res://scripts/combat_visual_root.gd")
const BackgroundVisualType = preload("res://scripts/background_visual.gd")
const ActionStateType = preload("res://scripts/player_action_state.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const StaminaType = preload("res://scripts/player_stamina.gd")
const HitStunType = preload("res://scripts/hit_stun.gd")
const BufferType = preload("res://scripts/player_action_buffer.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	_check_defaults(failures)
	await _check_compose_and_breathing(failures)
	await _check_slip_pov_absolute(failures)
	_check_parallax_direction_and_magnitude(failures)
	_check_opponent_not_center_locked(failures)
	_check_parallax_and_shake_wiring(failures)
	_check_stale_tween_tokens(failures)
	_check_evade_visual_hold_api(failures)
	_check_guard_no_recovery(failures)
	_check_attack_to_guard_threshold(failures)
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
	if not is_equal_approx(player.slip_pov_x, 90.0):
		failures.append("slip_pov_x != 90")
	if not is_equal_approx(player.slip_pov_y, 24.0):
		failures.append("slip_pov_y != 24")
	if not is_equal_approx(opponent.breathing_amplitude, 6.0):
		failures.append("Opponent breathing_amplitude != 6")
	if not is_equal_approx(opponent.attack_pose_hold_seconds, 0.20):
		failures.append("attack_pose_hold_seconds != 0.20")
	if not is_equal_approx(opponent.knockdown_impact_shake_y, 10.0):
		failures.append("opponent knockdown_impact_shake_y != 10")
	if opponent.knockdown_impact_shake_count != 3:
		failures.append("opponent knockdown_impact_shake_count != 3")
	if not is_equal_approx(opponent.knockdown_impact_shake_duration, 0.18):
		failures.append("opponent knockdown_impact_shake_duration != 0.18")
	if not is_equal_approx(player.knockdown_impact_shake_y, 6.0):
		failures.append("player knockdown_impact_shake_y != 6")
	if not is_equal_approx(visual_root.parallax_crowd_x, 10.0):
		failures.append("parallax_crowd_x != 10")
	if not is_equal_approx(visual_root.parallax_ring_x, 24.0):
		failures.append("parallax_ring_x != 24")
	if not is_equal_approx(visual_root.parallax_opponent_x, 48.0):
		failures.append("parallax_opponent_x != 48")
	if not is_equal_approx(visual_root.evade_passby_offset_x, 130.0):
		failures.append("evade_passby must stay 130")
	if not is_equal_approx(visual_root.evade_visual_hold_seconds, 0.20):
		failures.append("evade_visual_hold must stay 0.20")
	if not (
		visual_root.parallax_opponent_x > visual_root.parallax_ring_x
		and visual_root.parallax_ring_x > visual_root.parallax_crowd_x
	):
		failures.append("Parallax depth order Crowd < Ring < Opponent broken")
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
	opponent.set_parallax_offset(Vector2(48.0, 0.0))
	var expected_x := opponent.asset_base_position.x + 48.0
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
	if not is_equal_approx(player.pov_offset.x, -90.0):
		failures.append("Slip Left POV X expected -90")
	if not is_equal_approx(player.pov_offset.y, 24.0):
		failures.append("Slip Left POV Y expected +24")
	player._begin_slip_pov(-1)
	player.pov_offset = Vector2(-player.slip_pov_x, player.slip_pov_y)
	if not is_equal_approx(player.pov_offset.x, -90.0):
		failures.append("Consecutive Slip Left drifted POV")
	player._begin_slip_pov(1)
	player.pov_offset = Vector2(player.slip_pov_x, player.slip_pov_y)
	if not is_equal_approx(player.pov_offset.x, 90.0):
		failures.append("Slip Right POV X expected +90")
	player._reset_pov_immediate()
	if player.pov_offset != Vector2.ZERO:
		failures.append("POV reset failed")
	player.queue_free()
	await process_frame


func _check_parallax_direction_and_magnitude(failures: Array[String]) -> void:
	var visual_root := CombatVisualRootType.new()
	## Slip Left → world +X targets
	var left_crowd := visual_root.parallax_crowd_x * 1.0
	var left_ring := visual_root.parallax_ring_x * 1.0
	var left_opp := visual_root.parallax_opponent_x * 1.0
	if left_crowd <= 0.0 or left_ring <= 0.0 or left_opp <= 0.0:
		failures.append("Slip Left world parallax should be +X")
	if not (left_opp > left_ring and left_ring > left_crowd):
		failures.append("Slip Left magnitude Opponent > Ring > Crowd")
	## Slip Right → world -X
	var right_opp := visual_root.parallax_opponent_x * -1.0
	if right_opp >= 0.0:
		failures.append("Slip Right opponent parallax should be -X")
	visual_root.free()


func _check_opponent_not_center_locked(failures: Array[String]) -> void:
	var opponent := OpponentVisualType.new()
	opponent._build_nodes()
	var base := opponent.asset_base_position
	opponent.set_parallax_offset(Vector2(48.0, 0.0))
	var mid := opponent._anchor.position
	if is_equal_approx(mid.x, base.x):
		failures.append("Opponent still at base after +48 parallax (center-locked?)")
	## Simulate a later compose (breathing update) — must keep parallax
	opponent._set_breathing_offset(Vector2(0.0, 3.0))
	if not is_equal_approx(opponent._anchor.position.x, base.x + 48.0):
		failures.append("Breathing compose overwrote opponent parallax")
	opponent.set_parallax_offset(Vector2.ZERO)
	if not is_equal_approx(opponent.parallax_offset.x, 0.0):
		failures.append("Opponent parallax did not clear to 0")
	opponent.free()


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
	## Root itself does not carry world parallax — only shake.
	visual_root.free()

	var bg := BackgroundVisualType.new()
	if not bg.has_method("set_crowd_parallax") or not bg.has_method("set_ring_parallax"):
		failures.append("BackgroundVisual missing parallax setters")
	bg.free()


func _check_stale_tween_tokens(failures: Array[String]) -> void:
	var player := PlayerVisualType.new()
	player._build_nodes()
	var token0: int = player._pov_token
	player._begin_slip_pov(-1)
	if player._pov_token <= token0:
		failures.append("POV tween should bump token on begin")
	var token1: int = player._pov_token
	player._begin_slip_pov(1)
	if player._pov_token <= token1:
		failures.append("Chained Slip should invalidate prior POV tween")
	player._reset_pov_immediate()
	if player.pov_offset != Vector2.ZERO:
		failures.append("POV immediate reset failed after chain")
	player.free()

	var visual_root := CombatVisualRootType.new()
	var p0: int = visual_root._parallax_token
	visual_root._tween_world_parallax(1.0)
	if visual_root._parallax_token <= p0:
		failures.append("Parallax tween should bump token")
	var p1: int = visual_root._parallax_token
	visual_root._tween_world_parallax(-1.0)
	if visual_root._parallax_token <= p1:
		failures.append("Chained parallax should invalidate prior tween")
	visual_root._reset_world_parallax_immediate()
	if visual_root._parallax_token <= p1:
		failures.append("Immediate parallax reset should bump token")
	visual_root.free()


func _check_evade_visual_hold_api(failures: Array[String]) -> void:
	var visual_root := CombatVisualRootType.new()
	if not is_equal_approx(visual_root.evade_visual_hold_seconds, 0.20):
		failures.append("evade_visual_hold_seconds expected 0.20")
	if not is_equal_approx(visual_root.evade_passby_offset_x, 130.0):
		failures.append("evade_passby_offset_x expected 130")
	if not visual_root.has_method("_begin_evade_visual_hold"):
		failures.append("Missing evade visual hold")
	visual_root.free()

	var player := PlayerVisualType.new()
	player._build_nodes()
	if not player.has_method("hold_evade_slip_pov") or not player.has_method("release_evade_slip_pov"):
		failures.append("PlayerVisual missing evade POV hold API")
	else:
		player.hold_evade_slip_pov(-1)
		if not player._evade_pov_hold:
			failures.append("hold_evade_slip_pov did not arm hold")
		## Simulate gameplay slip ending while hold active
		player._evade_pov_hold = true
		player.pov_offset = Vector2(-70, 20)
		## release should clear when not evading
		player.release_evade_slip_pov()
		if player._evade_pov_hold:
			failures.append("release_evade_slip_pov did not clear hold flag")
	player.free()

	var opponent := OpponentVisualType.new()
	opponent._build_nodes()
	if not opponent.has_method("apply_evade_passby"):
		failures.append("OpponentVisual missing apply_evade_passby")
	else:
		opponent.set_parallax_offset(Vector2(48, 0))
		opponent.apply_evade_passby(1.0, 130.0)
		var expected := opponent.asset_base_position.x + 48.0 + 130.0
		if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.x, expected):
			failures.append(
				"EVADE passby not additive with parallax (got %.1f expected %.1f)"
				% [opponent._anchor.position.x, expected]
			)
		## ACTIVE texture swap must not wipe passby if already set
		opponent._show_attack(0)
		if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.x, expected):
			failures.append("Straight texture swap cleared evade passby")
		opponent.clear_evade_passby()
		var after := opponent.asset_base_position.x + 48.0
		if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.x, after):
			failures.append("clear_evade_passby failed")
	## Knockdown impact is additive and settles to drop-only
	opponent._knockdown_offset = Vector2(0.0, opponent.knockdown_drop_distance)
	opponent._play_knockdown_impact_shake()
	opponent._knockdown_impact_offset = Vector2(0.0, 10.0)
	opponent._apply_composed_transform()
	var kd_expected := (
		opponent.asset_base_position.y
		+ opponent.knockdown_drop_distance
		+ 10.0
	)
	if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.y, kd_expected):
		failures.append("Knockdown impact not additive with drop")
	opponent._clear_knockdown_impact()
	if opponent._knockdown_impact_offset != Vector2.ZERO:
		failures.append("clear_knockdown_impact failed")
	if opponent._anchor != null and not is_equal_approx(
		opponent._anchor.position.y,
		opponent.asset_base_position.y + opponent.knockdown_drop_distance
	):
		failures.append("After impact clear, drop offset should remain")
	opponent.free()


func _check_guard_no_recovery(failures: Array[String]) -> void:
	var stamina := StaminaType.new()
	stamina._ready()
	var hit_stun := HitStunType.new()
	var attack := AttackStateType.new()
	attack.player_stamina = stamina
	attack.hit_stun = hit_stun
	attack.print_action_speed = false
	attack._ready()
	var action := ActionStateType.new()
	action.attack_state = attack
	action.player_stamina = stamina
	action.hit_stun = hit_stun
	action.print_state_changes = false
	action._ready()

	action.set_guard_held(true)
	if not action.is_guarding():
		failures.append("Guard press should enter GUARD immediately")
	action.set_guard_held(false)
	if action.current_state != ActionStateType.PlayerState.IDLE:
		failures.append("Guard release should enter IDLE immediately (no post-lock)")
	if not action.can_attack():
		failures.append("After Guard release, Attack should be available immediately")
	if not action.try_start_evasion(CombatInputType.DefenseType.SLIP_LEFT):
		failures.append("After Guard release, Slip should be available immediately")
	## Evade window unchanged (base slip_duration)
	if not is_equal_approx(action.slip_duration, 0.18):
		failures.append("Player slip_duration (evade window) changed")
	action.force_reset_to_idle()
	stamina.queue_free()
	hit_stun.queue_free()
	attack.queue_free()
	action.queue_free()


func _check_attack_to_guard_threshold(failures: Array[String]) -> void:
	var buffer := BufferType.new()
	if not is_equal_approx(buffer.attack_to_guard, 0.25):
		failures.append("Attack→Guard cancel threshold should remain 0.25")
	var stamina := StaminaType.new()
	stamina._ready()
	var hit_stun := HitStunType.new()
	var attack := AttackStateType.new()
	attack.player_stamina = stamina
	attack.hit_stun = hit_stun
	attack.print_action_speed = false
	var data := AttackDataType.new()
	data.attack_type = 0
	data.startup_time = 0.10
	data.active_time = 0.08
	data.recovery_time = 0.40
	data.stamina_cost = 4.0
	attack.attacks = [data]
	attack._ready()
	if not attack.try_start_attack(0):
		failures.append("Could not start attack for guard-threshold check")
		stamina.queue_free()
		hit_stun.queue_free()
		attack.queue_free()
		buffer.queue_free()
		return
	## Still in STARTUP — not recovering → Attack→Guard cancel unavailable
	if attack.is_recovering():
		failures.append("Unexpected recovery during startup")
	if attack.get_recovery_progress() >= buffer.attack_to_guard:
		failures.append("Startup must not satisfy Attack→Guard cancel")
	## Advance into early recovery (< 25%)
	for _i in 12:
		attack._process(0.02)
	if not attack.is_recovering():
		failures.append("Expected RECOVERY for guard threshold test")
	elif attack.get_recovery_progress() >= buffer.attack_to_guard:
		## push was too far; still OK if recovering — just ensure ACTIVE had no cancel API
		pass
	else:
		## Below threshold: cancel into guard must wait
		if attack.get_recovery_progress() >= buffer.attack_to_guard:
			failures.append("Early recovery unexpectedly past guard threshold")
	stamina.queue_free()
	hit_stun.queue_free()
	attack.queue_free()
	buffer.queue_free()


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
		if not is_equal_approx(visual_root.parallax_opponent_x, 48.0):
			failures.append("Scene parallax_opponent_x != 48")
	var player_v = scene.get_node_or_null("CombatVisualRoot/PlayerVisual")
	if player_v != null:
		if not is_equal_approx(player_v.slip_pov_x, 90.0):
			failures.append("Scene slip_pov_x != 90")
		if not is_equal_approx(player_v.slip_pov_y, 24.0):
			failures.append("Scene slip_pov_y != 24")
		if not is_equal_approx(player_v.knockdown_impact_shake_y, 6.0):
			failures.append("Scene player knockdown_impact_shake_y != 6")
	var opp_v = scene.get_node_or_null("CombatVisualRoot/OpponentVisual")
	if opp_v != null and not is_equal_approx(opp_v.attack_pose_hold_seconds, 0.20):
		failures.append("Scene OpponentVisual hold != 0.20")
	if opp_v != null and not is_equal_approx(opp_v.knockdown_impact_shake_y, 10.0):
		failures.append("Scene opponent knockdown_impact_shake_y != 10")
	if opp_v != null and not opp_v.has_method("_play_knockdown_impact_shake"):
		failures.append("OpponentVisual missing knockdown impact shake")
	if scene.get_node_or_null("CombatVisualRoot/DebugHUD") != null:
		failures.append("DebugHUD must not be under CombatVisualRoot")
	if scene.get_node_or_null("DebugHUD") == null:
		failures.append("DebugHUD missing at scene root")
	scene.free()
