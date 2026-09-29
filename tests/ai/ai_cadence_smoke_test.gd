extends SceneTree

const AiType = preload("res://scripts/opponent_ai.gd")
const AttackType = preload("res://scripts/opponent_attack_state.gd")
const ActionType = preload("res://scripts/opponent_action_state.gd")
const DataType = preload("res://scripts/opponent_attack_data.gd")
const StaminaType = preload("res://scripts/opponent_stamina.gd")
const RoundType = preload("res://scripts/round_manager.gd")
const KDType = preload("res://scripts/knockdown_manager.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var ai := _make()
	seed(3)
	var times: Array[float] = []
	var time := 0.0
	while time < 30.0:
		ai.opponent_attack_state.hand_reuse.debug_now = time
		var before := ai.opponent_attack_state.get_action_token()
		ai._process(0.01)
		ai.opponent_attack_state._process(0.01)
		ai.opponent_stamina._process(0.01)
		if ai.opponent_attack_state.get_action_token() != before and ai.opponent_attack_state.current_attack != null:
			times.append(time)
		time += 0.01
	var counts: Array[int] = ai.debug_pattern_counts
	print("PATTERNS single=%d quick=%d burst=%d delayed=%d attacks=%d" % [counts[0], counts[1], counts[2], counts[3], times.size()])
	var shown := 0
	for stamp in times:
		if shown >= 12:
			break
		print("ATTACK %.2f" % stamp)
		shown += 1
	_compare_neutral_scale(failures)
	var kinds := 0
	for count in counts:
		if count > 0:
			kinds += 1
	if kinds < 3:
		failures.append("Attack rhythm stayed on too few patterns")
	if times.size() < 8:
		failures.append("30s produced too few attacks")
	ai.free()
	var delayed := _make()
	delayed.pattern_single_chance = 0.0
	delayed.pattern_quick_chance = 0.0
	delayed.pattern_burst_chance = 0.0
	delayed.followup_opposite_chance = 1.0
	var delayed_times: Array[float] = []
	time = 0.0
	while time < 2.0 and delayed_times.size() < 2:
		delayed.opponent_attack_state.hand_reuse.debug_now = time
		var before_token := delayed.opponent_attack_state.get_action_token()
		delayed._process(0.01)
		delayed.opponent_attack_state._process(0.01)
		delayed.opponent_stamina._process(0.01)
		if delayed.opponent_attack_state.get_action_token() != before_token and delayed.opponent_attack_state.current_attack != null:
			delayed_times.append(time)
		time += 0.01
	if delayed_times.size() < 2 or delayed_times[1] - delayed_times[0] < 0.15:
		failures.append("Delayed double did not wait before the second punch")
	if failures.is_empty():
		print("SMOKE PASS: ai cadence")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _compare_neutral_scale(failures: Array[String]) -> void:
	var before_count := _count_sequences(1.0)
	var after_count := _count_sequences(0.82)
	print("NEUTRAL sequences before=%d after=%d" % [before_count, after_count])
	if float(after_count) > float(before_count) * 1.15:
		failures.append("Neutral offense scale increased sequences")


func _count_sequences(scale: float) -> int:
	var ai := _make()
	ai.neutral_offense_scale = scale
	ai.difficulty.aggression = 0.62
	seed(11)
	var time := 0.0
	while time < 30.0:
		ai.opponent_attack_state.hand_reuse.debug_now = time
		ai._process(0.01)
		ai.opponent_attack_state._process(0.01)
		ai.opponent_stamina._process(0.01)
		time += 0.01
	var total := 0
	for count in ai.debug_pattern_counts:
		total += count
	print("SCALE %.2f patterns=%s" % [scale, str(ai.debug_pattern_counts)])
	ai.free()
	return total


func _make() -> AiType:
	var ai := AiType.new()
	ai.opponent_action_state = ActionType.new()
	ai.opponent_attack_state = AttackType.new()
	var stamina := StaminaType.new()
	stamina.current_stamina = 100.0
	stamina.max_stamina = 100.0
	stamina.regeneration_enabled = true
	ai.opponent_stamina = stamina
	ai.opponent_attack_state.opponent_stamina = stamina
	var left := DataType.new()
	left.attack_type = DataType.AttackType.LEFT_STRAIGHT
	left.startup_time = 0.10
	left.active_time = 0.08
	left.recovery_time = 0.11
	left.stamina_cost = 4.0
	var right := DataType.new()
	right.attack_type = DataType.AttackType.RIGHT_STRAIGHT
	right.startup_time = 0.14
	right.active_time = 0.09
	right.recovery_time = 0.14
	right.stamina_cost = 5.0
	ai.opponent_attack_state.attacks = [left, right]
	ai.opponent_attack_state.combat_enabled = true
	ai.opponent_attack_state._ready_gate = true
	ai.opponent_attack_state._time_remaining = 0.0
	ai.difficulty = preload("res://scripts/opponent_difficulty_settings.gd").new()
	ai.difficulty.aggression = 1.0
	ai.difficulty.low_stamina_wait_chance = 0.0
	ai._proactive_timer = 100.0
	ai._offense_cooldown = 0.0
	ai.round_manager = RoundType.new()
	ai.round_manager.round_state = RoundType.RoundState.FIGHTING
	ai.knockdown_manager = KDType.new()
	return ai
