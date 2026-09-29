extends SceneTree

const AiType = preload("res://scripts/opponent_ai.gd")
const AttackType = preload("res://scripts/opponent_attack_state.gd")
const ActionType = preload("res://scripts/opponent_action_state.gd")
const StunType = preload("res://scripts/hit_stun.gd")
const DataType = preload("res://scripts/opponent_attack_data.gd")
const StaminaType = preload("res://scripts/opponent_stamina.gd")
const KDType = preload("res://scripts/knockdown_manager.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_mix(failures)
	_check_link(failures, 2, 0.0, 1.0)
	_check_link(failures, 3, 0.0, 0.0)
	_check_same_follow(failures)
	_check_same_hand(failures)
	_check_stamina(failures)
	_check_hit_stun(failures)
	_check_knockdown(failures)
	_check_retaliation(failures)
	if failures.is_empty():
		print("SMOKE PASS: opponent combo")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_mix(failures: Array[String]) -> void:
	var ai := AiType.new()
	ai.pattern_single_chance = 0.30
	ai.pattern_quick_chance = 0.30
	ai.pattern_burst_chance = 0.20
	seed(7)
	var counts := [0, 0, 0, 0]
	for _i in 200:
		counts[ai._choose_pattern()] += 1
	if counts[0] < 30 or counts[1] < 30 or counts[2] < 15 or counts[3] < 15:
		failures.append("pattern mix %s" % str(counts))


func _make(stamina_now: float, single: float, two: float) -> AiType:
	var ai := AiType.new()
	ai.pattern_single_chance = single
	ai.pattern_quick_chance = two
	ai.pattern_burst_chance = 0.0 if single + two > 0.0 else 1.0
	ai.followup_opposite_chance = 1.0
	ai.opponent_action_state = ActionType.new()
	ai.opponent_attack_state = AttackType.new()
	ai.opponent_hit_stun = StunType.new()
	ai.opponent_attack_state.hit_stun = ai.opponent_hit_stun
	ai.opponent_action_state.hit_stun = ai.opponent_hit_stun
	var stamina := StaminaType.new()
	stamina.current_stamina = stamina_now
	stamina.max_stamina = 100.0
	ai.opponent_stamina = stamina
	ai.opponent_attack_state.opponent_stamina = stamina
	var left := DataType.new()
	left.attack_type = DataType.AttackType.LEFT_STRAIGHT
	left.startup_time = 0.10
	left.active_time = 0.08
	left.recovery_time = 0.20
	left.stamina_cost = 4.0
	var right := DataType.new()
	right.attack_type = DataType.AttackType.RIGHT_STRAIGHT
	right.startup_time = 0.14
	right.active_time = 0.09
	right.recovery_time = 0.20
	right.stamina_cost = 5.0
	ai.opponent_attack_state.attacks = [left, right]
	ai.opponent_attack_state.combat_enabled = true
	ai.opponent_attack_state._ready_gate = true
	ai.opponent_attack_state.initial_ready_delay = 0.0
	ai.opponent_attack_state._time_remaining = 0.0
	ai.difficulty = preload("res://scripts/opponent_difficulty_settings.gd").new()
	ai.difficulty.aggression = 1.0
	ai.difficulty.low_stamina_wait_chance = 0.0
	ai._proactive_timer = 100.0
	ai._offense_cooldown = 0.0
	ai.attack_to_attack_cancel = 0.50
	return ai


func _drive(ai: AiType, seconds: float) -> Array[int]:
	var started: Array[int] = []
	var tokens: Array[int] = []
	var times: Array[float] = []
	var time := 0.0
	while time < seconds:
		ai.opponent_attack_state.hand_reuse.debug_now = time
		var before := ai.opponent_attack_state.get_action_token()
		ai._process(0.01)
		ai.opponent_attack_state._process(0.01)
		var token := ai.opponent_attack_state.get_action_token()
		if token != before and ai.opponent_attack_state.current_attack != null:
			started.append(ai.opponent_attack_state.current_attack.attack_type)
			tokens.append(token)
			times.append(time)
		time += 0.01
	ai.set_meta("tokens", tokens)
	ai.set_meta("times", times)
	return started


func _check_link(failures: Array[String], length: int, single: float, two: float) -> void:
	var ai := _make(100.0, single, two)
	var started := _drive(ai, 2.0)
	if started.size() < length:
		failures.append("combo %d started only %s" % [length, str(started)])
		return
	var tokens: Array = ai.get_meta("tokens")
	var seen := {}
	for token in tokens:
		if seen.has(token):
			failures.append("attack token reused")
		seen[token] = true
	for index in range(1, length):
		if started[index] == started[index - 1]:
			failures.append("follow-up repeated the same hand %s" % str(started))
			return
	if ai.opponent_stamina.current_stamina < 0.0:
		failures.append("stamina went negative")


func _check_same_follow(failures: Array[String]) -> void:
	var ai := _make(100.0, 0.0, 1.0)
	ai.followup_opposite_chance = 0.0
	var started := _drive(ai, 2.5)
	if started.size() < 2 or started[0] != started[1]:
		failures.append("same-hand follow-up did not stay on the chosen hand %s" % str(started))
		return
	var times: Array = ai.get_meta("times")
	if float(times[1]) - float(times[0]) < 0.45:
		failures.append("same-hand follow-up broke the 0.45 reuse")


func _check_retaliation(failures: Array[String]) -> void:
	var ai := _make(100.0, 1.0, 0.0)
	ai._offense_cooldown = 100.0
	ai._on_player_attack_resolved(0, 0.0, 0.0, false, 1)
	if not ai._retaliation_pending or not is_equal_approx(ai._retaliation_chance, 0.45):
		failures.append("block should arm a 45 percent retaliation")
	ai._on_player_attack_resolved(0, 0.0, 0.0, false, 2)
	if ai.debug_retaliation_armed != 2 or not is_equal_approx(ai._retaliation_chance, 0.60):
		failures.append("evade should refresh retaliation to 60 percent without stacking")
	ai.retaliation_evade_chance = 1.0
	ai._retaliation_chance = 1.0
	ai.difficulty.aggression = 0.0
	ai._offense_cooldown = 0.0
	var before := ai.opponent_attack_state.get_action_token()
	ai._process(0.02)
	if ai.opponent_attack_state.get_action_token() == before:
		failures.append("a saved retaliation should start an attack once the fighter can act")
	if ai._retaliation_pending:
		failures.append("the retaliation decision should be consumed")


func _check_same_hand(failures: Array[String]) -> void:
	var ai := _make(100.0, 1.0, 0.0)
	ai._offense_cooldown = 100.0
	ai.opponent_attack_state.hand_reuse.debug_now = 0.0
	if not ai.opponent_attack_state.try_execute_attack(DataType.AttackType.LEFT_STRAIGHT):
		failures.append("left start failed")
		return
	ai.opponent_attack_state.hand_reuse.debug_now = 0.44
	ai.opponent_attack_state._time_remaining = 0.0
	ai.opponent_attack_state.current_state = AttackType.AttackState.IDLE
	ai.opponent_attack_state.current_attack = null
	ai.opponent_attack_state._ready_gate = true
	if ai.opponent_attack_state.try_execute_attack(DataType.AttackType.LEFT_STRAIGHT):
		failures.append("same hand started before 0.45")
	ai.opponent_attack_state.hand_reuse.debug_now = 0.46
	if not ai.opponent_attack_state.try_execute_attack(DataType.AttackType.LEFT_STRAIGHT):
		failures.append("same hand should start after 0.45 and full recovery")


func _check_stamina(failures: Array[String]) -> void:
	var ai := _make(4.0, 0.0, 1.0)
	if not ai._start_new_attack():
		failures.append("one affordable punch should still start a combo")
		return
	_drive(ai, 1.5)
	if ai.debug_stamina_cancels < 1:
		failures.append("low stamina should cancel the follow-up")
	if ai.opponent_stamina.current_stamina < 0.0:
		failures.append("stamina went negative on a blocked follow-up")


func _check_hit_stun(failures: Array[String]) -> void:
	var ai := _make(100.0, 0.0, 0.0)
	_drive(ai, 0.05)
	if ai._combo_left <= 0:
		failures.append("3-hit intent did not arm a follow-up")
		return
	ai.opponent_hit_stun.apply_hit_stun()
	ai._process(0.01)
	if not ai._follow_up_pending or ai._combo_left <= 0:
		failures.append("a normal hit must not cancel the combo")


func _check_knockdown(failures: Array[String]) -> void:
	var ai := _make(100.0, 0.0, 0.0)
	_drive(ai, 0.05)
	ai.knockdown_manager = KDType.new()
	ai.knockdown_manager.match_state = KDType.MatchState.OPPONENT_DOWN
	ai._process(0.01)
	if ai._follow_up_pending:
		failures.append("knockdown should cancel the unstarted follow-up")
