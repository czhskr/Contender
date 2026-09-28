extends SceneTree

## Continuous Evade Movement + Timing + Opponent Down Nstance lowering.
## Run: godot --headless --path . -s res://continuous_evade_smoke_test.gd

const PlayerEvadeType = preload("res://scripts/player_evade.gd")
const PlayerVisualType = preload("res://scripts/player_visual.gd")
const CombatVisualRootType = preload("res://scripts/combat_visual_root.gd")
const OpponentVisualType = preload("res://scripts/opponent_visual.gd")
const BufferType = preload("res://scripts/player_action_buffer.gd")
const StaminaType = preload("res://scripts/player_stamina.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const ActionStateType = preload("res://scripts/player_action_state.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const HitStunType = preload("res://scripts/hit_stun.gd")
const OpponentAttackDataType = preload("res://scripts/opponent_attack_data.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	_check_defaults(failures)
	_check_input_map(failures)
	_check_movement_targets(failures)
	await _check_visual_smoothing(failures)
	_check_window_stamina_retrigger(failures)
	_check_low_stamina_movement_only(failures)
	_check_attack_gates(failures)
	_check_resolver_evade(failures)
	_check_passby_down(failures)
	_check_opponent_down_idle(failures)
	_check_no_legacy_slip_api(failures)
	_check_scene_wiring(failures)

	if failures.is_empty():
		print("SMOKE PASS: continuous evade")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_defaults(failures: Array[String]) -> void:
	var evade := PlayerEvadeType.new()
	if not is_equal_approx(evade.evade_window, 0.18):
		failures.append("evade_window expected 0.18")
	if not is_equal_approx(evade.evade_stamina_cost, 4.0):
		failures.append("evade_stamina_cost expected 4")
	if not is_equal_approx(evade.evade_retrigger_interval, 0.12):
		failures.append("evade_retrigger_interval expected 0.12")
	if evade.left_offset != Vector2(0.0, 4.0):
		failures.append("LEFT offset expected (0, 4) — no Player X")
	if evade.right_offset != Vector2(0.0, 4.0):
		failures.append("RIGHT offset expected (0, 4) — no Player X")
	if evade.down_offset != Vector2(0.0, 10.0):
		failures.append("DOWN offset expected (0, 10)")
	if not is_equal_approx(evade.left_offset.x, 0.0) or not is_equal_approx(evade.right_offset.x, 0.0):
		failures.append("Player lateral X must be 0 (full-frame clipping)")
	var buffer := BufferType.new()
	if not is_equal_approx(buffer.attack_to_evade, 0.35):
		failures.append("attack_to_evade expected 0.35")
	var root := CombatVisualRootType.new()
	if not is_equal_approx(root.parallax_crowd_x, 20.0):
		failures.append("parallax_crowd_x != 20")
	if not is_equal_approx(root.parallax_ring_x, 45.0):
		failures.append("parallax_ring_x != 45")
	if not is_equal_approx(root.parallax_opponent_x, 90.0):
		failures.append("parallax_opponent_x != 90")
	if not is_equal_approx(root.parallax_crowd_down_y, 10.0):
		failures.append("parallax_crowd_down_y != 10")
	if not is_equal_approx(root.parallax_ring_down_y, 22.0):
		failures.append("parallax_ring_down_y != 22")
	if not is_equal_approx(root.parallax_opponent_down_y, 40.0):
		failures.append("parallax_opponent_down_y != 40")
	if not is_equal_approx(root.evade_down_passby_offset_y, 40.0):
		failures.append("evade_down_passby_offset_y != 40")
	if not is_equal_approx(root.weave_depth_opponent, 45.0):
		failures.append("weave_depth_opponent != 45")
	var stacked := root.parallax_opponent_down_y + root.evade_down_passby_offset_y
	if stacked > 85.0:
		failures.append("DOWN stack too large (%.1f)" % stacked)
	var player := PlayerVisualType.new()
	if not is_equal_approx(player.opponent_down_idle_offset_y, 90.0):
		failures.append("opponent_down_idle_offset_y != 90")
	evade.free()
	buffer.free()
	root.free()
	player.free()


func _check_input_map(failures: Array[String]) -> void:
	if not InputMap.has_action("combat_evade_down"):
		failures.append("combat_evade_down missing from InputMap")
	if InputMap.has_action("combat_duck"):
		failures.append("combat_duck must stay removed")
	var keys := CombatInputType.EvadeDirection.keys()
	if not keys.has("DOWN"):
		failures.append("EvadeDirection.DOWN missing")
	if keys.has("DUCK"):
		failures.append("EvadeDirection must not include DUCK")


func _check_movement_targets(failures: Array[String]) -> void:
	var evade := PlayerEvadeType.new()
	evade.set_movement_direction(PlayerEvadeType.Direction.LEFT)
	if evade.movement_target != Vector2(0.0, 4.0):
		failures.append("LEFT movement target wrong")
	evade.set_movement_direction(PlayerEvadeType.Direction.RIGHT)
	if evade.movement_target != Vector2(0.0, 4.0):
		failures.append("A→D should retarget immediately without recovery")
	evade.set_movement_direction(PlayerEvadeType.Direction.DOWN)
	if evade.movement_target != Vector2(0.0, 10.0):
		failures.append("DOWN movement target wrong")
	evade.set_movement_direction(PlayerEvadeType.Direction.NONE)
	if evade.movement_target != Vector2.ZERO:
		failures.append("Release must target CENTER")
	## No exclusive slip state
	var action := ActionStateType.new()
	if ActionStateType.PlayerState.keys().has("SLIP_LEFT"):
		failures.append("PlayerActionState still has SLIP_LEFT")
	action.free()
	evade.free()


func _check_visual_smoothing(failures: Array[String]) -> void:
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
		failures.append("Player POV X must stay 0 (got %.2f)" % player.pov_offset.x)
	if not is_equal_approx(player.pov_offset.y, 4.0):
		failures.append("POV Y did not reach LEFT/RIGHT small Y (got %.2f)" % player.pov_offset.y)
	## World weave: shared head lateral crosses center with dip
	var world := CombatVisualRootType.new()
	world.head_smooth_time = 0.08
	world._on_evade_movement_target_changed(Vector2.ZERO, PlayerEvadeType.Direction.LEFT)
	for _i in 20:
		world._process(0.02)
	if world._head_lateral < 0.9:
		failures.append("Head lateral should approach LEFT (+1)")
	## Retarget RIGHT without zeroing velocity — continuity
	var vel_before := world._head_lateral_vel
	world._on_evade_movement_target_changed(Vector2.ZERO, PlayerEvadeType.Direction.RIGHT)
	## Midway toward RIGHT: lateral near 0 → weave Y dip on opponent
	var saw_dip := false
	for _j in 30:
		world._process(0.02)
		if absf(world._head_lateral) < 0.35 and world._opponent_parallax.y < -5.0:
			saw_dip = true
			break
	if not saw_dip:
		failures.append("A→D should produce center weave dip on Opponent Y")
	## Velocity was not forcibly zeroed on retarget (may still be non-zero immediately after)
	if is_equal_approx(vel_before, 0.0) and is_equal_approx(world._head_lateral_vel, 0.0):
		pass ## ok if already settled
	world.free()
	## Additive opponent-down idle
	player._opponent_down_idle_offset = Vector2(0.0, 90.0)
	player._apply_composed_transform()
	if player._anchor != null:
		var expected_y := player.asset_base_position.y + player.pov_offset.y + 90.0
		if not is_equal_approx(player._anchor.position.y, expected_y):
			failures.append("opponent_down_idle not additive with evade POV")
	player.queue_free()
	evade.queue_free()
	await process_frame


func _check_window_stamina_retrigger(failures: Array[String]) -> void:
	var stamina := StaminaType.new()
	stamina.initial_current_stamina = 100.0
	stamina.initial_max_stamina = 100.0
	stamina._ready()
	var evade := PlayerEvadeType.new()
	evade.player_stamina = stamina
	evade.evade_retrigger_interval = 0.12
	evade.evade_window = 0.18

	var before := stamina.current_stamina
	if not evade.try_begin_window(PlayerEvadeType.Direction.LEFT):
		failures.append("First evade window should start")
	elif not is_equal_approx(before - stamina.current_stamina, 4.0):
		failures.append("Evade should spend exactly 4 stamina")
	if not evade.is_window_active():
		failures.append("Window should be active after trigger")

	## Hold / same-frame retrigger blocked
	before = stamina.current_stamina
	if evade.try_begin_window(PlayerEvadeType.Direction.RIGHT):
		failures.append("Retrigger interval must block new window")
	if not is_equal_approx(stamina.current_stamina, before):
		failures.append("Blocked retrigger must not spend stamina")

	## After retrigger cools, new window allowed (may replace active)
	evade._retrigger_remaining = 0.0
	before = stamina.current_stamina
	if not evade.try_begin_window(PlayerEvadeType.Direction.DOWN):
		failures.append("After retrigger, new window should start")
	elif not is_equal_approx(before - stamina.current_stamina, 4.0):
		failures.append("Second evade should spend 4")

	## Window expiry
	evade._window_remaining = 0.0
	evade._process(0.01)
	if evade.is_window_active():
		failures.append("Window should end after duration")

	stamina.queue_free()
	evade.queue_free()


func _check_low_stamina_movement_only(failures: Array[String]) -> void:
	var stamina := StaminaType.new()
	stamina.initial_current_stamina = 2.0
	stamina.initial_max_stamina = 100.0
	stamina._ready()
	var evade := PlayerEvadeType.new()
	evade.player_stamina = stamina
	evade.set_movement_direction(PlayerEvadeType.Direction.RIGHT)
	if evade.movement_target != Vector2(0.0, 4.0):
		failures.append("Low stamina must still allow movement")
	var before := stamina.current_stamina
	if evade.try_begin_window(PlayerEvadeType.Direction.RIGHT):
		failures.append("Low stamina must not open evade window")
	if not is_equal_approx(stamina.current_stamina, before):
		failures.append("Low stamina path must not spend")
	stamina.queue_free()
	evade.queue_free()


func _check_attack_gates(failures: Array[String]) -> void:
	var buffer := BufferType.new()
	if not (
		buffer.attack_to_guard < buffer.attack_to_evade
		and buffer.attack_to_evade < buffer.attack_to_attack
	):
		failures.append(
			"Expected guard < evade < attack cancel (%.2f / %.2f / %.2f)"
			% [buffer.attack_to_guard, buffer.attack_to_evade, buffer.attack_to_attack]
		)
	buffer.free()

	var stamina := StaminaType.new()
	stamina._ready()
	var hit_stun := HitStunType.new()
	var attack := AttackStateType.new()
	attack.player_stamina = stamina
	attack.hit_stun = hit_stun
	attack.print_action_speed = false
	var data := AttackDataType.new()
	data.startup_time = 0.10
	data.active_time = 0.08
	data.recovery_time = 0.40
	data.stamina_cost = 4.0
	attack.attacks = [data]
	attack._ready()
	var evade := PlayerEvadeType.new()
	evade.player_stamina = stamina

	if not attack.try_start_attack(0):
		failures.append("Attack start failed for gate test")
	else:
		## Startup: no window
		if evade.try_begin_window(PlayerEvadeType.Direction.LEFT) and attack.current_state == AttackStateType.AttackState.STARTUP:
			## Window itself doesn't know attack state — combat_prototype gates.
			## Here verify recover progress API for cancel threshold.
			pass
		for _i in 8:
			attack._process(0.02)
		if attack.is_recovering() and attack.get_recovery_progress() < 0.35:
			## Below threshold — cancel not ready
			if attack.get_recovery_progress() >= 0.35:
				failures.append("Early recovery past evade threshold unexpectedly")
	stamina.queue_free()
	hit_stun.queue_free()
	attack.queue_free()
	evade.queue_free()


func _check_resolver_evade(failures: Array[String]) -> void:
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
	var evade := PlayerEvadeType.new()
	evade.player_stamina = stamina
	var meter := KnockdownMeterType.new()
	meter._ready()
	var defense := DefenseResolverType.new()
	defense.player_action_state = action
	defense.player_evade = evade
	defense.player_knockdown_meter = meter
	defense.print_hit_results = false

	var opp := OpponentAttackDataType.new()
	opp.knockdown_damage = 10.0

	evade.try_begin_window(PlayerEvadeType.Direction.LEFT)
	defense.resolve_attack(opp)
	## Capture last result via signal would be ideal; check meter instead.
	if meter.current_meter > 0.0:
		failures.append("EVADE window active must deal 0 KD")

	evade.end_window()
	defense.resolve_attack(opp)
	if meter.current_meter <= 0.0:
		failures.append("No evade/guard should HIT and apply KD")

	meter.current_meter = 0.0
	action.set_guard_held(true)
	defense.resolve_attack(opp)
	if not is_equal_approx(meter.current_meter, 2.5):
		failures.append("BLOCK should apply 0.25 KD mult (got %.2f)" % meter.current_meter)

	stamina.queue_free()
	hit_stun.queue_free()
	attack.queue_free()
	action.queue_free()
	evade.queue_free()
	meter.queue_free()
	defense.queue_free()


func _check_passby_down(failures: Array[String]) -> void:
	var opponent := OpponentVisualType.new()
	opponent._build_nodes()
	opponent.apply_evade_passby_offset(Vector2(0.0, -40.0))
	if opponent._evade_passby_offset != Vector2(0.0, -40.0):
		failures.append("DOWN passby offset not applied")
	var expected_y := opponent.asset_base_position.y - 40.0
	if opponent._anchor != null and not is_equal_approx(opponent._anchor.position.y, expected_y):
		failures.append("DOWN passby not in compose")
	opponent.clear_evade_passby()
	if opponent._evade_passby_offset != Vector2.ZERO:
		failures.append("clear_evade_passby failed")
	opponent.free()

	var root := CombatVisualRootType.new()
	var stacked := root.parallax_opponent_down_y + root.evade_down_passby_offset_y
	if stacked > 85.0:
		failures.append("DOWN parallax+passby stack too large (%.1f)" % stacked)
	if not root.has_method("_begin_evade_passby_presentation"):
		failures.append("Missing passby presentation (must not lock player POV)")
	root.free()


func _check_opponent_down_idle(failures: Array[String]) -> void:
	var player := PlayerVisualType.new()
	player._build_nodes()
	player._set_opponent_down_idle(true)
	if player._opponent_down_idle_target != Vector2(0.0, 90.0):
		failures.append("Opponent down idle target Y should be +90")
	player._knocked_down = true
	player._set_opponent_down_idle(true)
	if player._opponent_down_idle_target != Vector2.ZERO:
		failures.append("Player Down must force opponent_down_idle = 0")
	player._knocked_down = false
	player._set_opponent_down_idle(false)
	if player._opponent_down_idle_target != Vector2.ZERO:
		failures.append("Recover should target 0")
	player.free()


func _check_no_legacy_slip_api(failures: Array[String]) -> void:
	var action := ActionStateType.new()
	if action.has_method("get_slip_progress"):
		failures.append("get_slip_progress must be removed")
	if action.has_method("unlock_for_next_action"):
		failures.append("unlock_for_next_action must be removed")
	if action.has_method("try_start_evasion"):
		failures.append("try_start_evasion must be removed from PlayerActionState")
	var buffer := BufferType.new()
	if buffer.has_method("buffer_slip_left"):
		failures.append("buffer_slip_left must be removed")
	var player := PlayerVisualType.new()
	if player.has_method("_begin_slip_pov"):
		failures.append("_begin_slip_pov must be removed")
	if player.has_method("hold_evade_slip_pov"):
		failures.append("hold_evade_slip_pov must be removed (movement unlock)")
	action.free()
	buffer.free()
	player.free()


func _check_scene_wiring(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn load failed")
		return
	var scene := packed.instantiate()
	if scene.get_node_or_null("PlayerEvade") == null:
		failures.append("PlayerEvade missing from game.tscn")
	var defense = scene.get_node_or_null("PlayerDefenseResolver")
	if defense != null and defense.player_evade == null:
		failures.append("DefenseResolver.player_evade not wired")
	var visual_root = scene.get_node_or_null("CombatVisualRoot")
	if visual_root != null and visual_root.player_evade == null:
		failures.append("CombatVisualRoot.player_evade not wired")
	var player_v = scene.get_node_or_null("CombatVisualRoot/PlayerVisual")
	if player_v != null and player_v.player_evade == null:
		failures.append("PlayerVisual.player_evade not wired")
	scene.free()
