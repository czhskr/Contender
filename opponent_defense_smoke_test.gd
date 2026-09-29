extends SceneTree

## Opponent discrete defense: reaction, Guard/Slip, and hit results.
## Run: godot --headless --path . -s res://opponent_defense_smoke_test.gd

const AIType = preload("res://scripts/opponent_ai.gd")
const ActionType = preload("res://scripts/opponent_action_state.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const OffenseType = preload("res://scripts/player_offense_resolver.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")
const VisualType = preload("res://scripts/opponent_visual.gd")
const RoundType = preload("res://scripts/round_manager.gd")
const DifficultyType = preload("res://scripts/opponent_difficulty_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_difficulty_unchanged(failures)
	await _check_reaction_and_decisions(failures)
	await _check_resolver(failures)
	await _check_visual_and_clear(failures)

	if failures.is_empty():
		print("SMOKE PASS: opponent defense")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_difficulty_unchanged(failures: Array[String]) -> void:
	var normal := DifficultyType.new()
	if not is_equal_approx(normal.reaction_delay, 0.234):
		failures.append("Normal reaction_delay changed")
	if not is_equal_approx(normal.mistake_chance, 0.20):
		failures.append("Normal mistake_chance changed")
	if not is_equal_approx(normal.aggression, 0.62):
		failures.append("AI baseline aggression must stay 0.62")
	if FileAccess.file_exists("res://data/difficulty/easy.tres") or FileAccess.file_exists("res://data/difficulty/hard.tres"):
		failures.append("Easy/Hard difficulty resources should be removed")


func _check_reaction_and_decisions(failures: Array[String]) -> void:
	var action := ActionType.new()
	var player_attack := AttackStateType.new()
	var ai := AIType.new()
	root.add_child(action)
	root.add_child(ai)
	await process_frame
	ai.opponent_action_state = action
	ai.player_attack_state = player_attack
	ai.print_ai_decisions = false

	player_attack.current_state = AttackStateType.AttackState.STARTUP
	ai._on_player_attack_state_changed(AttackStateType.AttackState.STARTUP, 0)
	if not ai._reaction_pending:
		failures.append("Player startup did not schedule a reaction")
	if ai._reaction_timer < 0.154 or ai._reaction_timer > 0.314:
		failures.append("Normal reaction timer left the 0.234±0.08 band")

	player_attack.current_state = AttackStateType.AttackState.ACTIVE
	ai.debug_forced_rolls = [0.0, 0.9, 0.0, 0.0]
	ai.resolve_pending_defense_now()
	if action.current_state != ActionType.OpponentState.SLIP_LEFT:
		failures.append("Forced slip-left decision did not enter Slip Left")
	if not action.is_evasion_active():
		failures.append("Slip Left is not an active evade window")

	action.force_reset_to_idle()
	player_attack.current_state = AttackStateType.AttackState.STARTUP
	ai.debug_forced_rolls = [0.5]
	ai._on_player_attack_state_changed(AttackStateType.AttackState.STARTUP, 2)
	if ai._reaction_attack != 2:
		failures.append("Player Hook was not detected")
	player_attack.current_state = AttackStateType.AttackState.ACTIVE
	ai.debug_forced_rolls = [0.0, 0.9, 0.99, 0.0]
	ai.resolve_pending_defense_now()
	if action.current_state != ActionType.OpponentState.GUARD:
		failures.append("Forced guard decision did not enter Guard")

	action.force_reset_to_idle()
	player_attack.current_state = AttackStateType.AttackState.ACTIVE
	ai._reaction_pending = true
	ai._reaction_attack = 1
	ai.debug_forced_rolls = [0.0, 0.0, 0.0]
	ai.resolve_pending_defense_now()
	if action.current_state != ActionType.OpponentState.IDLE:
		failures.append("Mistake NONE should leave the opponent idle")

	action.force_reset_to_idle()
	ai._reaction_pending = true
	ai.debug_forced_rolls = [0.99]
	ai.resolve_pending_defense_now()
	if action.current_state != ActionType.OpponentState.IDLE:
		failures.append("Failed reaction roll should stay idle (HIT path)")

	action.current_state = ActionType.OpponentState.ATTACKING
	ai._reaction_pending = true
	ai._reaction_attack = 3
	ai.debug_forced_rolls = [0.0, 0.9, 0.0, 0.0]
	ai.resolve_pending_defense_now()
	if action.current_state != ActionType.OpponentState.ATTACKING:
		failures.append("Committed attack was cancelled into a defense")

	action.queue_free()
	ai.queue_free()
	await process_frame


func _check_resolver(failures: Array[String]) -> void:
	var action := ActionType.new()
	var player_attack := AttackStateType.new()
	var meter := MeterType.new()
	var offense := OffenseType.new()
	var straight := AttackDataType.new()
	straight.attack_type = 0
	straight.knockdown_damage = 10.0
	var hook := AttackDataType.new()
	hook.attack_type = 2
	hook.knockdown_damage = 13.0
	var right := AttackDataType.new()
	right.attack_type = 1
	right.knockdown_damage = 10.0
	player_attack.attacks = [straight, right, hook]
	root.add_child(meter)
	root.add_child(offense)
	await process_frame
	offense.player_attack_state = player_attack
	offense.opponent_action_state = action
	offense.opponent_knockdown_meter = meter
	offense.meter_updates_enabled = true
	offense.print_hit_results = false

	action.current_state = ActionType.OpponentState.GUARD
	offense._resolved_for_current_attack = false
	offense.resolve_hit_now(0)
	if not is_equal_approx(meter.current_meter, 297.5):
		failures.append("Guard BLOCK should apply KD x0.25")

	meter.set_meter(0.0)
	action.current_state = ActionType.OpponentState.SLIP_RIGHT
	action.current_evasion_phase = ActionType.EvasionPhase.EVADING
	offense.resolve_hit_now(2)
	if not is_equal_approx(meter.current_meter, 0.0):
		failures.append("Slip Right should EVADE a Player Hook")

	action.current_state = ActionType.OpponentState.SLIP_LEFT
	action.current_evasion_phase = ActionType.EvasionPhase.EVADING
	offense.resolve_hit_now(1)
	if not is_equal_approx(meter.current_meter, 0.0):
		failures.append("Slip Left should EVADE a Straight")

	action.current_state = ActionType.OpponentState.IDLE
	action.current_evasion_phase = ActionType.EvasionPhase.NONE
	offense.resolve_hit_now(0)
	if not is_equal_approx(meter.current_meter, 10.0):
		failures.append("No defense should be a full HIT")

	offense.queue_free()
	meter.queue_free()
	await process_frame


func _check_visual_and_clear(failures: Array[String]) -> void:
	var action := ActionType.new()
	var visual := VisualType.new()
	visual.opponent_action_state = action
	root.add_child(action)
	root.add_child(visual)
	await process_frame

	action.try_start_evasion(ActionType.OpponentState.SLIP_LEFT)
	if visual.current_visual_state != "SLIP_LEFT":
		failures.append("Slip Left visual was not o.L_slip pose")
	action.force_reset_to_idle()
	action.try_start_evasion(ActionType.OpponentState.SLIP_RIGHT)
	if visual.current_visual_state != "SLIP_RIGHT":
		failures.append("Slip Right visual was not o.R_slip pose")
	action._process(1.0)
	if action.current_state != ActionType.OpponentState.IDLE:
		failures.append("Slip did not return to idle")
	if visual.current_visual_state != "IDLE":
		failures.append("Slip did not return to Nstance")

	action.set_guard_held(true)
	if visual.current_visual_state != "HIGH_GUARD":
		failures.append("Guard visual was not high guard pose")
	action.set_guard_held(false)
	if visual.current_visual_state != "IDLE":
		failures.append("Guard release did not return to Nstance")

	action.set_guard_held(true)
	var rounds := RoundType.new()
	rounds.opponent_action_state = action
	rounds._freeze_combat()
	if action.current_state != ActionType.OpponentState.IDLE:
		failures.append("Round freeze did not clear defense")

	action.set_guard_held(true)
	action.force_reset_to_idle()
	if action.current_state != ActionType.OpponentState.IDLE:
		failures.append("Knockdown reset did not clear defense")

	visual.queue_free()
	action.queue_free()
	await process_frame
