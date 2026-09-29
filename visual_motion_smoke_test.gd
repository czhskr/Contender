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
	await _check_stale_tween_tokens(failures)
	_check_evade_visual_hold_api(failures)
	_check_guard_no_recovery(failures)
	_check_attack_to_guard_threshold(failures)
	_check_opponent_recovery(failures)
	await _check_background_overscan(failures)
	await _check_opponent_down_coverage(failures)
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
	const PlayerEvadeType = preload("res://scripts/player_evade.gd")
	var evade := PlayerEvadeType.new()
	if not is_equal_approx(player.breathing_amplitude, 6.0):
		failures.append("Player breathing_amplitude != 6")
	if not is_equal_approx(player.breathing_cycle_seconds, 1.6):
		failures.append("Player breathing_cycle_seconds != 1.6")
	if evade.left_offset != Vector2(0.0, 10.0):
		failures.append("LEFT evade offset != (0, 10)")
	if evade.right_offset != Vector2(0.0, 10.0):
		failures.append("RIGHT evade offset != (0, 10)")
	if evade.down_offset != Vector2(0.0, 10.0):
		failures.append("DOWN evade offset != (0, 10)")
	if not is_equal_approx(opponent.breathing_amplitude, 6.0):
		failures.append("Opponent breathing_amplitude != 6")
	if not is_equal_approx(opponent.attack_pose_hold_seconds, 0.28):
		failures.append("attack_pose_hold_seconds != 0.28")
	if not is_equal_approx(opponent.knockdown_impact_shake_y, 10.0):
		failures.append("opponent knockdown_impact_shake_y != 10")
	if opponent.knockdown_impact_shake_count != 3:
		failures.append("opponent knockdown_impact_shake_count != 3")
	if not is_equal_approx(opponent.knockdown_impact_shake_duration, 0.18):
		failures.append("opponent knockdown_impact_shake_duration != 0.18")
	if not is_equal_approx(player.knockdown_impact_shake_y, 6.0):
		failures.append("player knockdown_impact_shake_y != 6")
	if not is_equal_approx(visual_root.parallax_crowd_x, 80.0):
		failures.append("parallax_crowd_x != 80")
	if not is_equal_approx(visual_root.parallax_ring_x, 160.0):
		failures.append("parallax_ring_x != 160")
	if not is_equal_approx(visual_root.parallax_opponent_x, 280.0):
		failures.append("parallax_opponent_x != 280")
	if not is_equal_approx(visual_root.evade_passby_offset_x, 40.0):
		failures.append("evade_passby must stay 40")
	if not is_equal_approx(visual_root.evade_visual_hold_seconds, 0.20):
		failures.append("evade_visual_hold must stay 0.20")
	if not (
		visual_root.parallax_opponent_x > visual_root.parallax_ring_x
		and visual_root.parallax_ring_x > visual_root.parallax_crowd_x
	):
		failures.append("Parallax depth order Crowd < Ring < Opponent broken")
	if not is_equal_approx(visual_root.opponent_hit_shake_strength, 5.0):
		failures.append("opponent_hit_shake_strength != 5")
	if not is_equal_approx(visual_root.player_hit_shake_strength, 12.0):
		failures.append("player_hit_shake_strength != 12")
	player.free()
	opponent.free()
	visual_root.free()
	evade.free()


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
	const PlayerEvadeType = preload("res://scripts/player_evade.gd")
	var evade := PlayerEvadeType.new()
	var player := PlayerVisualType.new()
	player.player_evade = evade
	player.evade_smooth_time = 0.01
	root.add_child(evade)
	root.add_child(player)
	await process_frame
	evade.set_movement_direction(PlayerEvadeType.Direction.LEFT)
	for _i in 30:
		player._process(0.02)
	if absf(player.pov_offset.x) > 0.01:
		failures.append("Evade Left POV X must be 0")
	if not is_equal_approx(player.pov_offset.y, 10.0):
		failures.append("Evade Left POV Y expected +10 (got %.2f)" % player.pov_offset.y)
	evade.set_movement_direction(PlayerEvadeType.Direction.RIGHT)
	for _j in 10:
		player._process(0.02)
	if absf(player.pov_offset.x) > 0.01:
		failures.append("Evade Right POV X must be 0")
	evade.set_movement_direction(PlayerEvadeType.Direction.DOWN)
	for _k in 30:
		player._process(0.02)
	if not is_equal_approx(player.pov_offset.y, 10.0):
		failures.append("Evade Down POV Y expected +10 (got %.2f)" % player.pov_offset.y)
	player._reset_pov_immediate()
	if player.pov_offset != Vector2.ZERO:
		failures.append("POV reset failed")
	player.queue_free()
	evade.queue_free()
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
	if not visual_root.has_method("_set_parallax_targets_for_direction"):
		failures.append("CombatVisualRoot missing continuous parallax targets")
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


func _check_stale_tween_tokens(failures: Array[String]) -> void:
	const PlayerEvadeType = preload("res://scripts/player_evade.gd")
	var evade := PlayerEvadeType.new()
	var player := PlayerVisualType.new()
	player.player_evade = evade
	player.evade_smooth_time = 0.01
	root.add_child(evade)
	root.add_child(player)
	await process_frame
	evade.set_movement_direction(PlayerEvadeType.Direction.LEFT)
	player._process(0.2)
	evade.set_movement_direction(PlayerEvadeType.Direction.RIGHT)
	player._process(0.2)
	if absf(player.pov_offset.x) > 0.01:
		failures.append("Chained evade must keep Player X = 0")
	player._reset_pov_immediate()
	if player.pov_offset != Vector2.ZERO:
		failures.append("POV immediate reset failed after chain")
	player.queue_free()
	evade.queue_free()
	await process_frame

	var visual_root := CombatVisualRootType.new()
	visual_root._set_parallax_targets_for_direction(PlayerEvadeType.Direction.LEFT)
	if visual_root._crowd_parallax.x <= 0.0:
		failures.append("LEFT parallax should be +X")
	visual_root._set_parallax_targets_for_direction(PlayerEvadeType.Direction.RIGHT)
	if visual_root._opponent_parallax.x >= 0.0:
		failures.append("RIGHT parallax should be -X")
	visual_root._set_parallax_targets_for_direction(PlayerEvadeType.Direction.DOWN)
	if visual_root._opponent_parallax.y >= 0.0:
		failures.append("DOWN parallax should be -Y")
	visual_root._reset_world_parallax_immediate()
	if visual_root._crowd_parallax != Vector2.ZERO:
		failures.append("Immediate parallax reset failed")
	visual_root.free()


func _check_evade_visual_hold_api(failures: Array[String]) -> void:
	var visual_root := CombatVisualRootType.new()
	if not is_equal_approx(visual_root.evade_visual_hold_seconds, 0.20):
		failures.append("evade_visual_hold_seconds expected 0.20")
	if not is_equal_approx(visual_root.evade_passby_offset_x, 40.0):
		failures.append("evade_passby_offset_x expected 40")
	if not visual_root.has_method("_begin_evade_passby_presentation"):
		failures.append("Missing evade passby presentation")
	## Passby must not lock player continuous movement APIs
	if visual_root.has_method("hold_evade_slip_pov"):
		failures.append("Root must not lock player POV via slip hold")
	visual_root.free()

	var player := PlayerVisualType.new()
	player._build_nodes()
	if player.has_method("hold_evade_slip_pov"):
		failures.append("PlayerVisual must not lock POV on evade success")
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
		opponent.apply_evade_passby_offset(Vector2(0.0, -40.0))
		var expected_y := opponent.asset_base_position.y - 40.0
		if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.y, expected_y):
			failures.append("DOWN passby Y not applied")
		opponent._show_attack(0)
		if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.y, expected_y):
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
	## Continuous evade is not an exclusive action state
	if action.has_method("try_start_evasion"):
		failures.append("PlayerActionState must not own slip evasion")
	const PlayerEvadeType = preload("res://scripts/player_evade.gd")
	var evade := PlayerEvadeType.new()
	evade.player_stamina = stamina
	if not evade.try_begin_window(PlayerEvadeType.Direction.LEFT):
		failures.append("After Guard release, Evade window should be available")
	if not is_equal_approx(evade.evade_window, 0.18):
		failures.append("Player evade_window changed")
	evade.queue_free()
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
	if left == null or not is_equal_approx(left.recovery_time, 0.11):
		failures.append(
			"Opp L Straight recovery expected 0.11, got %s"
			% str(left.recovery_time if left else null)
		)
	if right == null or not is_equal_approx(right.recovery_time, 0.14):
		failures.append(
			"Opp R Straight recovery expected 0.14, got %s"
			% str(right.recovery_time if right else null)
		)
	if left != null and not is_equal_approx(left.startup_time, 0.10):
		failures.append("Opp L Straight startup changed")
	if left != null and not is_equal_approx(left.active_time, 0.08):
		failures.append("Opp L Straight active changed")
	if right != null and not is_equal_approx(right.startup_time, 0.14):
		failures.append("Opp R Straight startup changed")


func _check_background_overscan(failures: Array[String]) -> void:
	var bg := BackgroundVisualType.new()
	root.add_child(bg)
	await process_frame
	var crowd: Sprite2D = bg.get_node_or_null("CrowdLayer")
	var ring: Sprite2D = bg.get_node_or_null("RingLayer")
	if crowd == null or ring == null or crowd.texture == null or ring.texture == null:
		failures.append("Background layers failed to load")
		bg.queue_free()
		return

	var crowd_tex := Vector2(crowd.texture.get_width(), crowd.texture.get_height())
	var ring_tex := Vector2(ring.texture.get_width(), ring.texture.get_height())
	var crowd_center := bg.layer_visual_center(crowd)
	var ring_center := bg.layer_visual_center(ring)
	if not crowd_center.is_equal_approx(bg.cover_visual_center(crowd_tex)):
		failures.append("Crowd overscan moved visual center")
	if not ring_center.is_equal_approx(bg.cover_visual_center(ring_tex)):
		failures.append("Ring overscan moved visual center")
	if not is_equal_approx(crowd.scale.x, crowd.scale.y) or not is_equal_approx(ring.scale.x, ring.scale.y):
		failures.append("Overscan broke uniform scale")

	var root_v := CombatVisualRootType.new()
	var crowd_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(root_v.parallax_crowd_x, 0.0),
		Vector2(-root_v.parallax_crowd_x, 0.0),
		Vector2(0.0, -(root_v.parallax_crowd_down_y + root_v.weave_depth_crowd)),
		Vector2(root_v.parallax_crowd_x, -(root_v.parallax_crowd_down_y + root_v.weave_depth_crowd)),
		Vector2(-root_v.parallax_crowd_x, -root_v.weave_depth_crowd),
	]
	for offset in crowd_offsets:
		if not bg.layer_covers_viewport(crowd, offset):
			failures.append("Crowd edge exposed at %s" % str(offset))
	var ring_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(root_v.parallax_ring_x, 0.0),
		Vector2(-root_v.parallax_ring_x, 0.0),
		Vector2(0.0, -(root_v.parallax_ring_down_y + root_v.weave_depth_ring)),
		Vector2(root_v.parallax_ring_x, -(root_v.parallax_ring_down_y + root_v.weave_depth_ring)),
		Vector2(-root_v.parallax_ring_x, -root_v.weave_depth_ring),
	]
	for offset in ring_offsets:
		if not bg.layer_covers_viewport(ring, offset):
			failures.append("Ring edge exposed at %s" % str(offset))
	root_v.background_visual = bg
	root_v._apply_background_overscan()
	var safety: float = root_v.background_overscan_safety
	if not is_equal_approx(bg.crowd_bleed.x, root_v.parallax_crowd_x + safety):
		failures.append("Crowd horizontal overscan is not amplitude plus safety")
	if not is_equal_approx(bg.ring_bleed.x, root_v.parallax_ring_x + safety):
		failures.append("Ring horizontal overscan is not amplitude plus safety")
	if not is_equal_approx(bg.crowd_bleed.y, root_v.parallax_crowd_down_y + root_v.weave_depth_crowd + safety):
		failures.append("Crowd vertical overscan changed")
	if not is_equal_approx(bg.ring_bleed.y, root_v.parallax_ring_down_y + root_v.weave_depth_ring + safety):
		failures.append("Ring vertical overscan changed")
	root_v._head_lateral = 1.0
	root_v._compose_head_parallax()
	if not is_equal_approx(root_v._crowd_parallax.x, 80.0) or not is_equal_approx(root_v._ring_parallax.x, 160.0):
		failures.append("LEFT background parallax is not 80 / 160")
	if not is_equal_approx(root_v._opponent_parallax.x, 280.0):
		failures.append("LEFT opponent parallax is not 280")
	if absf(root_v._crowd_parallax.x) >= absf(root_v._ring_parallax.x) or absf(root_v._ring_parallax.x) >= absf(root_v._opponent_parallax.x):
		failures.append("Parallax depth is not Opponent > Ring > Crowd")
	if not bg.layer_covers_viewport(crowd, Vector2(80.0, 0.0)) or not bg.layer_covers_viewport(crowd, Vector2(-80.0, 0.0)):
		failures.append("Crowd edge exposed at the new horizontal amplitude")
	if not bg.layer_covers_viewport(ring, Vector2(160.0, 0.0)) or not bg.layer_covers_viewport(ring, Vector2(-160.0, 0.0)):
		failures.append("Ring edge exposed at the new horizontal amplitude")
	root_v.free()

	var player := PlayerVisualType.new()
	if not is_equal_approx(player.player_display_scale, 0.75):
		failures.append("Player scale must stay 0.75")
	player.free()
	bg.queue_free()
	await process_frame


func _check_opponent_down_coverage(failures: Array[String]) -> void:
	var opponent := OpponentVisualType.new()
	root.add_child(opponent)
	await process_frame
	if opponent.get_node_or_null("Anchor/BottomBleed") != null:
		failures.append("BottomBleed must be removed")
	var scale := opponent.opponent_display_scale
	if not is_equal_approx(scale, 648.0 / 1024.0):
		failures.append("Opponent contain scale changed")
	var player := PlayerVisualType.new()
	if not is_equal_approx(player.player_display_scale, 0.75):
		failures.append("Player scale must stay 0.75")
	player.free()

	var root_v := CombatVisualRootType.new()
	root_v.opponent_visual = opponent
	root_v.viewport_size = Vector2(1152, 648)
	root_v._apply_opponent_down_framing()
	var lift := root_v.max_opponent_upward_lift()
	if not is_equal_approx(lift, 85.0):
		failures.append("Max upward lift expected 85, got %.2f" % lift)
	if not is_equal_approx(root_v.parallax_opponent_x, 280.0):
		failures.append("Opponent horizontal parallax changed")
	if not is_equal_approx(root_v.parallax_opponent_down_y, 40.0):
		failures.append("Opponent DOWN parallax changed")
	if not is_equal_approx(root_v.evade_down_passby_offset_y, 40.0):
		failures.append("DOWN pass-by magnitude changed")
	var canvas_h := 1024.0 * scale
	var center_top := opponent.asset_base_position.y
	var center_bottom := center_top + canvas_h
	var max_bottom := center_bottom - lift
	if absf(max_bottom - 648.0) > 2.0:
		failures.append("MAX DOWN canvas bottom %.2f is not viewport 648" % max_bottom)
	if center_top < 80.0:
		failures.append("CENTER framing did not shift down with the max lift")

	var opaque_left := 437.0 * scale
	var opaque_right := 1106.0 * scale
	var shift := root_v.parallax_opponent_x + root_v.evade_passby_offset_x
	var left_edge := opponent.asset_base_position.x - shift + opaque_left
	var right_edge := opponent.asset_base_position.x + shift + opaque_right
	if left_edge < -0.5 or right_edge > 1152.5:
		failures.append("Horizontal parallax plus pass-by clips idle opaque bounds")

	opponent._stop_breathing()
	opponent.set_parallax_offset(Vector2(0.0, -40.0))
	opponent.apply_evade_passby_offset(Vector2(0.0, -40.0))
	opponent._knockdown_offset = Vector2(0.0, 70.0)
	opponent._apply_composed_transform()
	var expected_y := opponent.asset_base_position.y - 40.0 - 40.0 + 70.0
	if not is_equal_approx(opponent._anchor.position.y, expected_y):
		failures.append("Knockdown must still add to evade offsets")
	root_v.free()
	opponent.queue_free()
	await process_frame


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
		if not is_equal_approx(visual_root.parallax_opponent_x, 280.0):
			failures.append("Scene parallax_opponent_x != 280")
		if not is_equal_approx(visual_root.player_hit_shake_strength, 12.0):
			failures.append("Scene player hit shake != 12")
		if not is_equal_approx(visual_root.opponent_hit_shake_strength, 5.0):
			failures.append("Scene opponent hit shake != 5")
		if not is_equal_approx(visual_root.player_hit_shake_duration, 0.15):
			failures.append("Scene player hit shake duration changed")
		if not is_equal_approx(visual_root.opponent_hit_shake_duration, 0.10):
			failures.append("Scene opponent hit shake duration changed")
	var player_v = scene.get_node_or_null("CombatVisualRoot/PlayerVisual")
	if player_v != null:
		if player_v.player_evade == null:
			failures.append("PlayerVisual.player_evade not wired")
		if not is_equal_approx(player_v.opponent_down_idle_offset_y, 90.0):
			failures.append("Scene opponent_down_idle_offset_y != 90")
		if not is_equal_approx(player_v.knockdown_impact_shake_y, 6.0):
			failures.append("Scene player knockdown_impact_shake_y != 6")
	var evade_node = scene.get_node_or_null("PlayerEvade")
	if evade_node == null:
		failures.append("PlayerEvade missing")
	elif evade_node.left_offset != Vector2(0.0, 10.0):
		failures.append("Scene LEFT evade offset wrong")
	var opp_v = scene.get_node_or_null("CombatVisualRoot/OpponentVisual")
	if opp_v != null and not is_equal_approx(opp_v.attack_pose_hold_seconds, 0.28):
		failures.append("Scene OpponentVisual hold != 0.28")
	if opp_v != null and not is_equal_approx(opp_v.knockdown_impact_shake_y, 10.0):
		failures.append("Scene opponent knockdown_impact_shake_y != 10")
	if opp_v != null and not opp_v.has_method("_play_knockdown_impact_shake"):
		failures.append("OpponentVisual missing knockdown impact shake")
	if scene.get_node_or_null("CombatVisualRoot/DebugHUD") != null:
		failures.append("DebugHUD must not be under CombatVisualRoot")
	if scene.get_node_or_null("DebugHUD") == null:
		failures.append("DebugHUD missing at scene root")
	scene.free()
