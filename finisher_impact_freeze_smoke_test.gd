extends SceneTree

## Knockdown Finisher Impact Freeze regression.
## Run: godot --headless --path . -s res://finisher_impact_freeze_smoke_test.gd

const FinisherType = preload("res://scripts/finisher_impact_freeze.gd")
const EffectType = preload("res://scripts/finisher_impact_effect.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const OpponentAttackDataType = preload("res://scripts/opponent_attack_data.gd")
const OpponentActionStateType = preload("res://scripts/opponent_action_state.gd")
const PlayerActionStateType = preload("res://scripts/player_action_state.gd")
const PlayerAttackStateType = preload("res://scripts/player_attack_state.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")
const PlayerStaminaType = preload("res://scripts/player_stamina.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const HitStunType = preload("res://scripts/hit_stun.gd")
const RoundManagerType = preload("res://scripts/round_manager.gd")
const RecoveryType = preload("res://scripts/recovery_chance_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	Engine.time_scale = 1.0

	_check_defaults(failures)
	_check_effect_flash_only(failures)
	_check_player_attacker_pose_releases_on_freeze_exit(failures)
	_check_opponent_attacker_idle_via_cancel_and_disable(failures)
	_check_scene_wiring(failures)
	_check_block_evade_no_finisher(failures)
	_check_normal_hit_no_finisher(failures)
	await _check_freeze_duration_no_time_scale(failures)
	await _check_duplicate_ignored(failures)
	_check_cancel_clears_effect(failures)
	await _check_player_finisher_then_knockdown(failures)
	await _check_opponent_finisher_then_knockdown(failures)
	_check_debug_force_bypasses(failures)
	_check_count_interval_unchanged(failures)
	_check_recovery_break_values(failures)
	_check_round_pause_api(failures)
	_check_no_legacy_slow_motion(failures)

	Engine.time_scale = 1.0

	if failures.is_empty():
		print("SMOKE PASS: finisher impact freeze")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _wait_real_ms(ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _check_defaults(failures: Array[String]) -> void:
	var finisher := FinisherType.new()
	## Legacy slow-mo export must not exist.
	if "finisher_time_scale" in finisher or "finisher_real_duration" in finisher:
		failures.append("legacy time_scale / real_duration exports must be removed")
	if not is_equal_approx(finisher.finisher_freeze_duration, 2.0):
		failures.append("finisher_freeze_duration expected 2.0 (script default)")
	if finisher.is_pending or finisher.is_active:
		failures.append("finisher should start idle")
	finisher.free()

	var fx := EffectType.new()
	if not is_equal_approx(fx.flash_peak_alpha, 0.82):
		failures.append("flash_peak_alpha expected 0.82")
	if not is_equal_approx(fx.flash_duration, 0.12):
		failures.append("flash_duration expected 0.12")
	if "overlay_alpha" in fx:
		failures.append("dark overlay_alpha must be removed (was causing gray screen)")
	fx.free()


func _check_effect_flash_only(failures: Array[String]) -> void:
	## White flash must clear fully; no lingering dark overlay.
	var fx := EffectType.new()
	root.add_child(fx)
	await process_frame
	fx.flash_duration = 0.12
	fx.play_finisher(2.0)
	if not fx.visible:
		failures.append("flash effect should be visible at start")
	## Let a few frames update flash alpha.
	await _wait_real_ms(50)
	var flash_node: ColorRect = fx.get_node_or_null("ImpactFlash")
	if flash_node == null:
		failures.append("ImpactFlash ColorRect missing")
	elif flash_node.color.r < 0.99 or flash_node.color.g < 0.99 or flash_node.color.b < 0.99:
		failures.append("flash must be white RGB (not gray tint)")
	## After flash window — original scene (effect layer hidden)
	await _wait_real_ms(120)
	if fx.visible:
		failures.append("flash layer must hide after ~0.12s (no gray hold overlay)")
	if flash_node != null and flash_node.color.a > 0.01:
		failures.append("flash alpha must be 0 after flash ends")
	fx.free()


func _check_player_attacker_pose_releases_on_freeze_exit(failures: Array[String]) -> void:
	## CASE A: Player attack pose frozen → freeze exit must return to Idle stance.
	const PlayerVisualType = preload("res://scripts/player_visual.gd")
	var pv: Node = PlayerVisualType.new()
	root.add_child(pv)
	await process_frame
	pv._set_priority(PlayerVisualType.Priority.ATTACK)
	pv._show_attack(0)
	if pv.current_visual_state != "LEFT_STRAIGHT":
		failures.append("precondition: player should show LEFT_STRAIGHT")
	pv.set_finisher_freeze(true)
	## Simulate AttackState IDLE that was ignored during freeze.
	pv._on_attack_state_changed(PlayerAttackStateType.AttackState.IDLE, -1)
	if pv.current_visual_state != "LEFT_STRAIGHT":
		failures.append("during freeze player attack pose must stay locked")
	pv.set_finisher_freeze(false)
	if pv.current_visual_state != "IDLE":
		failures.append(
			"CASE A: Player must return to IDLE stance on freeze exit (got %s)"
			% pv.current_visual_state
		)
	pv.free()


func _check_opponent_attacker_idle_via_cancel_and_disable(failures: Array[String]) -> void:
	## CASE B regression: Opponent cancel_and_disable re-emits IDLE → stance (unchanged path).
	const OpponentVisualType = preload("res://scripts/opponent_visual.gd")
	var ov: Node = OpponentVisualType.new()
	var oas := OpponentAttackStateType.new()
	var left := OpponentAttackDataType.new()
	left.attack_type = OpponentAttackDataType.AttackType.LEFT_STRAIGHT
	var alist: Array[OpponentAttackDataType] = []
	alist.append(left)
	oas.attacks = alist
	oas.opponent_stamina = OpponentStaminaType.new()
	ov.opponent_attack_state = oas
	root.add_child(oas.opponent_stamina)
	root.add_child(oas)
	root.add_child(ov)
	await process_frame
	ov._begin_attack_pose(OpponentAttackDataType.AttackType.LEFT_STRAIGHT)
	ov.set_finisher_freeze(true)
	ov._on_attack_state_changed(OpponentAttackStateType.AttackState.IDLE, null)
	if ov.current_visual_state == "IDLE":
		failures.append("during freeze opponent attack pose must stay locked")
	ov.set_finisher_freeze(false)
	## Mirror KnockdownManager._freeze_combat for PLAYER_DOWN attacker cleanup.
	oas.cancel_and_disable()
	if ov.current_visual_state != "IDLE":
		failures.append(
			"CASE B: Opponent must return to IDLE via cancel_and_disable (got %s)"
			% ov.current_visual_state
		)
	ov.free()
	oas.free()


func _check_scene_wiring(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn missing")
		return
	var scene: Node = packed.instantiate()
	var round_mgr: Node = scene.get_node_or_null("RoundManager")
	if round_mgr != null:
		round_mgr.set("auto_start", false)
	root.add_child(scene)
	var finisher: Node = scene.get_node_or_null("FinisherImpactFreeze")
	if finisher == null:
		failures.append("FinisherImpactFreeze node missing in game.tscn")
	elif not (finisher is FinisherType):
		failures.append("FinisherImpactFreeze wrong script")
	else:
		if not is_equal_approx(finisher.finisher_freeze_duration, 2.0):
			failures.append(
				"scene runtime finisher_freeze_duration != 2.0 (got %.3f)"
				% finisher.finisher_freeze_duration
			)
		var fx: Node = finisher.get_node_or_null("FinisherImpactEffect")
		if fx == null or not (fx is EffectType):
			failures.append("FinisherImpactEffect child missing")
	if scene.get_node_or_null("FinisherSlowMotion") != null:
		failures.append("legacy FinisherSlowMotion node must be removed")
	var ai: Node = scene.get_node_or_null("OpponentAI")
	if ai != null and ai.get("finisher_impact_freeze") != finisher:
		failures.append("OpponentAI.finisher_impact_freeze not wired")
	if round_mgr == null or not round_mgr.has_method("pause_for_finisher"):
		failures.append("RoundManager.pause_for_finisher missing")
	scene.free()
	Engine.time_scale = 1.0


func _check_block_evade_no_finisher(failures: Array[String]) -> void:
	var meter := KnockdownMeterType.new()
	meter.set_meter(90.0)
	meter.apply_knockdown_damage(0.0)
	if meter.is_knockdown_threshold():
		failures.append("EVADE should not empty the meter")
	meter.apply_knockdown_damage(8.0 * 0.25)
	if meter.is_knockdown_threshold():
		failures.append("BLOCK from 90 should not knock down")
	meter.free()


func _check_normal_hit_no_finisher(failures: Array[String]) -> void:
	var meter := KnockdownMeterType.new()
	meter.set_meter(50.0)
	meter.apply_knockdown_damage(8.0)
	if meter.is_knockdown_threshold():
		failures.append("normal HIT should not knock down from 50")
	meter.free()


func _check_freeze_duration_no_time_scale(failures: Array[String]) -> void:
	## Short override — production default is 2.0s.
	var holder := Node.new()
	root.add_child(holder)
	var fx := EffectType.new()
	holder.add_child(fx)
	var finisher := FinisherType.new()
	finisher.impact_effect = fx
	finisher.finisher_freeze_duration = 0.12
	holder.add_child(finisher)

	var finished_count := [0]
	finisher.finisher_finished.connect(func(_s): finished_count[0] += 1)

	var t0 := Time.get_ticks_msec()
	if not finisher.try_begin_finisher(KnockdownManagerType.DownedSide.OPPONENT):
		failures.append("try_begin_finisher should accept first call")
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("time_scale must stay 1.0 during freeze (got %.3f)" % Engine.time_scale)
	if not finisher.is_blocking_combat():
		failures.append("finisher should block combat while pending")
	if not fx.visible:
		failures.append("impact effect should be visible during freeze")

	await _wait_real_ms(200)

	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	if finished_count[0] != 1:
		failures.append("finisher_finished expected once, got %d" % finished_count[0])
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("time_scale must remain 1.0 after freeze")
	if elapsed < 0.10 or elapsed > 0.35:
		failures.append("freeze wall-clock out of range: %.3f" % elapsed)
	if finisher.is_pending or finisher.is_active:
		failures.append("finisher should be idle after finish")
	if fx.visible:
		failures.append("impact effect should hide after freeze")

	holder.free()
	Engine.time_scale = 1.0


func _check_duplicate_ignored(failures: Array[String]) -> void:
	var finisher := FinisherType.new()
	finisher.finisher_freeze_duration = 0.12
	root.add_child(finisher)
	var finished_count := [0]
	finisher.finisher_finished.connect(func(_s): finished_count[0] += 1)

	if not finisher.try_begin_finisher(KnockdownManagerType.DownedSide.PLAYER):
		failures.append("first finisher should start")
	if finisher.try_begin_finisher(KnockdownManagerType.DownedSide.PLAYER):
		failures.append("duplicate finisher must be ignored")
	if finisher.try_begin_finisher(KnockdownManagerType.DownedSide.OPPONENT):
		failures.append("second side finisher while pending must be ignored")
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("duplicate path must not alter time_scale")

	await _wait_real_ms(200)
	if finished_count[0] != 1:
		failures.append("duplicate path should still finish exactly once")

	finisher.free()
	Engine.time_scale = 1.0


func _check_cancel_clears_effect(failures: Array[String]) -> void:
	var holder := Node.new()
	root.add_child(holder)
	var fx := EffectType.new()
	holder.add_child(fx)
	var finisher := FinisherType.new()
	finisher.impact_effect = fx
	finisher.finisher_freeze_duration = 1.0
	holder.add_child(finisher)

	finisher.try_begin_finisher(KnockdownManagerType.DownedSide.OPPONENT)
	if not fx.visible:
		failures.append("cancel test: effect should be visible")
	finisher.cancel_and_restore()
	if finisher.is_pending:
		failures.append("cancel should clear pending")
	if fx.visible:
		failures.append("cancel should hide effect")
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("cancel must leave time_scale at 1.0")

	finisher.try_begin_finisher(KnockdownManagerType.DownedSide.PLAYER)
	holder.free()
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("_exit_tree must leave time_scale at 1.0")
	Engine.time_scale = 1.0


func _check_player_finisher_then_knockdown(failures: Array[String]) -> void:
	var ctx := _make_knockdown_harness()
	root.add_child(ctx.root)
	var finisher: FinisherType = ctx.finisher
	finisher.finisher_freeze_duration = 0.08
	var begin_count := [0]
	var down_while_pending := [false]

	ctx.knockdown.match_state_changed.connect(
		func(state: int) -> void:
			if state == KnockdownManagerType.MatchState.OPPONENT_DOWN:
				begin_count[0] += 1
				if finisher.is_pending:
					down_while_pending[0] = true
	)

	ctx.opp_meter.set_meter(8.0)
	var start_ok := [false]
	ctx.offense.opponent_knockdown.connect(
		func(_a: int) -> void:
			start_ok[0] = finisher.try_begin_finisher(KnockdownManagerType.DownedSide.OPPONENT)
	)
	finisher.finisher_finished.connect(
		func(side: int) -> void:
			if side == KnockdownManagerType.DownedSide.OPPONENT:
				ctx.knockdown.begin_opponent_knockdown()
	)

	ctx.offense.print_hit_results = false
	ctx.offense.resolve_hit_now(0)

	if not start_ok[0] and not finisher.is_pending:
		failures.append("player finisher should start on KD fill HIT")
	if finisher.is_pending and not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("time_scale must stay 1.0 during player finisher")

	await _wait_real_ms(160)

	if begin_count[0] != 1:
		failures.append("opponent knockdown begin expected once, got %d" % begin_count[0])
	if down_while_pending[0]:
		failures.append("Knockdown must start only after freeze ends")
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("scale 1.0 after player finisher→knockdown")

	ctx.knockdown.begin_opponent_knockdown()
	if begin_count[0] != 1:
		failures.append("duplicate begin_opponent_knockdown should not re-enter DOWN")

	ctx.root.free()
	Engine.time_scale = 1.0


func _check_opponent_finisher_then_knockdown(failures: Array[String]) -> void:
	var ctx := _make_knockdown_harness()
	root.add_child(ctx.root)
	var finisher: FinisherType = ctx.finisher
	finisher.finisher_freeze_duration = 0.08
	var begin_count := [0]
	ctx.knockdown.match_state_changed.connect(
		func(state: int) -> void:
			if state == KnockdownManagerType.MatchState.PLAYER_DOWN:
				begin_count[0] += 1
	)

	ctx.player_meter.set_meter(95.0)
	if not finisher.try_begin_finisher(KnockdownManagerType.DownedSide.PLAYER):
		failures.append("opponent-side finisher should start")
	finisher.finisher_finished.connect(
		func(side: int) -> void:
			if side == KnockdownManagerType.DownedSide.PLAYER:
				ctx.knockdown.begin_player_knockdown()
	)

	await _wait_real_ms(160)
	if begin_count[0] != 1:
		failures.append("player knockdown begin expected once, got %d" % begin_count[0])
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("time_scale must stay 1.0 for opponent finisher path")

	ctx.root.free()
	Engine.time_scale = 1.0


func _check_debug_force_bypasses(failures: Array[String]) -> void:
	var ctx := _make_knockdown_harness()
	root.add_child(ctx.root)
	var finisher: FinisherType = ctx.finisher
	var finisher_starts := [0]
	finisher.finisher_started.connect(func(_s): finisher_starts[0] += 1)

	ctx.knockdown.force_knockdown(KnockdownManagerType.DownedSide.OPPONENT)
	if finisher_starts[0] != 0:
		failures.append("debug force knockdown must not start finisher")
	if ctx.knockdown.match_state != KnockdownManagerType.MatchState.OPPONENT_DOWN:
		failures.append("force knockdown should enter OPPONENT_DOWN immediately")
	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("force knockdown must leave time_scale at 1.0")

	ctx.root.free()


func _check_count_interval_unchanged(failures: Array[String]) -> void:
	var km := KnockdownManagerType.new()
	if not is_equal_approx(km.count_interval, 1.0):
		failures.append("count_interval must remain 1.0")
	km.free()


func _check_recovery_break_values(failures: Array[String]) -> void:
	var player_rec: RecoveryType = load("res://data/ko/player_recovery_chance.tres")
	var opp_rec: RecoveryType = load("res://data/ko/opponent_recovery_chance.tres")
	if player_rec == null or not is_equal_approx(player_rec.recovery_stamina_amount, 15.0):
		failures.append("player recovery stamina +15 missing")
	if opp_rec == null or not is_equal_approx(opp_rec.recovery_stamina_amount, 15.0):
		failures.append("opponent recovery stamina +15 missing")
	var km := KnockdownManagerType.new()
	if not is_equal_approx(km.recovery_meter_ratio, 0.5):
		failures.append("recovery meter ratio must stay 0.5")
	km.free()
	var rm := RoundManagerType.new()
	if not is_equal_approx(rm.round_duration, 60.0):
		failures.append("round duration must stay 60")
	if rm.round_stamina_recovery != 0.0 or rm.round_knockdown_meter_recovery != 0.0:
		failures.append("round carry-over recovery should be removed")
	rm.free()


func _check_round_pause_api(failures: Array[String]) -> void:
	var rm := RoundManagerType.new()
	rm.auto_start = false
	rm.round_state = RoundManagerType.RoundState.FIGHTING
	rm.timer_paused = false
	rm.pause_for_finisher()
	if not rm.timer_paused:
		failures.append("pause_for_finisher should set timer_paused")
	if rm.can_accept_combat_input():
		failures.append("paused round should reject combat input")
	rm.free()


func _check_no_legacy_slow_motion(failures: Array[String]) -> void:
	if ResourceLoader.exists("res://scripts/finisher_slow_motion.gd"):
		failures.append("legacy finisher_slow_motion.gd must be deleted")
	if ResourceLoader.exists("res://finisher_slow_motion_smoke_test.gd"):
		failures.append("legacy finisher_slow_motion_smoke_test.gd must be deleted")


func _make_knockdown_harness() -> Dictionary:
	var holder := Node.new()
	var finisher := FinisherType.new()
	var knockdown := KnockdownManagerType.new()
	var player_meter := KnockdownMeterType.new()
	var opp_meter := KnockdownMeterType.new()
	var player_stamina := PlayerStaminaType.new()
	var opp_stamina := OpponentStaminaType.new()
	var player_attack := PlayerAttackStateType.new()
	var player_action := PlayerActionStateType.new()
	var opp_attack := OpponentAttackStateType.new()
	var opp_action := OpponentActionStateType.new()
	var player_hit := HitStunType.new()
	var opp_hit := HitStunType.new()
	var offense := OffenseResolverType.new()
	var defense := DefenseResolverType.new()

	var left := AttackDataType.new()
	left.attack_type = 0
	left.knockdown_damage = 8.0
	left.stamina_cost = 4.0
	var attack_list: Array[AttackDataType] = []
	attack_list.append(left)
	player_attack.attacks = attack_list

	var opp_left := OpponentAttackDataType.new()
	opp_left.attack_type = OpponentAttackDataType.AttackType.LEFT_STRAIGHT
	opp_left.knockdown_damage = 8.0
	var opp_list: Array[OpponentAttackDataType] = []
	opp_list.append(opp_left)
	opp_attack.attacks = opp_list

	player_attack.player_stamina = player_stamina
	player_attack.hit_stun = player_hit
	player_action.attack_state = player_attack
	player_action.player_stamina = player_stamina
	player_action.hit_stun = player_hit
	opp_attack.opponent_stamina = opp_stamina
	opp_attack.hit_stun = opp_hit
	opp_action.attack_state = opp_attack
	opp_action.opponent_stamina = opp_stamina
	opp_action.hit_stun = opp_hit

	offense.player_attack_state = player_attack
	offense.opponent_action_state = opp_action
	offense.opponent_knockdown_meter = opp_meter
	offense.print_hit_results = false
	defense.player_action_state = player_action
	defense.player_knockdown_meter = player_meter
	defense.opponent_attack_state = opp_attack
	defense.print_hit_results = false

	knockdown.player_attack_state = player_attack
	knockdown.player_action_state = player_action
	knockdown.opponent_attack_state = opp_attack
	knockdown.opponent_action_state = opp_action
	knockdown.player_stamina = player_stamina
	knockdown.opponent_stamina = opp_stamina
	knockdown.player_knockdown_meter = player_meter
	knockdown.opponent_knockdown_meter = opp_meter
	knockdown.defense_resolver = defense
	knockdown.offense_resolver = offense
	knockdown.player_hit_stun = player_hit
	knockdown.opponent_hit_stun = opp_hit
	knockdown.player_recovery_settings = load("res://data/ko/player_recovery_chance.tres")
	knockdown.opponent_recovery_settings = load("res://data/ko/opponent_recovery_chance.tres")
	knockdown.enable_debug_force_knockdown = true
	knockdown.print_events = false

	holder.add_child(finisher)
	holder.add_child(player_meter)
	holder.add_child(opp_meter)
	holder.add_child(player_stamina)
	holder.add_child(opp_stamina)
	holder.add_child(player_hit)
	holder.add_child(opp_hit)
	holder.add_child(player_attack)
	holder.add_child(player_action)
	holder.add_child(opp_attack)
	holder.add_child(opp_action)
	holder.add_child(offense)
	holder.add_child(defense)
	holder.add_child(knockdown)
	knockdown.set_combat_control_enabled(true)

	return {
		"root": holder,
		"finisher": finisher,
		"knockdown": knockdown,
		"player_meter": player_meter,
		"opp_meter": opp_meter,
		"offense": offense,
		"defense": defense,
		"player_attack": player_attack,
	}
