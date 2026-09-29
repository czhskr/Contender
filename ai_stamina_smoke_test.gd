extends SceneTree

const Ai := preload("res://scripts/opponent_ai.gd")
const Settings := preload("res://scripts/match_settings.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_curve()
	_check_monotonic()
	_check_patterns()
	_check_difficulties()
	_check_defense_untouched()
	if failures.is_empty():
		print("AI STAMINA SMOKE PASS")
	else:
		for failure in failures:
			print("FAIL ", failure)
		print("AI STAMINA SMOKE FAIL")
		quit(1)
		return
	quit(0)


func _make(stamina_now: float) -> OpponentAI:
	var ai := Ai.new()
	var stamina := OpponentStamina.new()
	stamina.max_stamina = 100.0
	stamina.current_stamina = stamina_now
	ai.opponent_stamina = stamina
	ai.difficulty = OpponentDifficultySettings.new()
	return ai


func _check_curve() -> void:
	var high := _make(100.0)
	var seventy := _make(75.0)
	var mid := _make(50.0)
	var low := _make(20.0)
	var floor_case := _make(10.0)
	if high.stamina_offense_modifier() < 0.98:
		failures.append("stamina 100 offense should stay on the baseline")
	if seventy.stamina_offense_modifier() < 0.98:
		failures.append("stamina 75 should stay close to the baseline")
	if mid.stamina_offense_modifier() >= high.stamina_offense_modifier():
		failures.append("stamina 50 should conserve")
	if mid.stamina_interval_modifier() <= 1.05:
		failures.append("stamina 50 interval should lengthen")
	if low.stamina_offense_modifier() >= 0.40:
		failures.append("stamina 20 should conserve strongly")
	if floor_case.proactive_attack_chance() <= 0.0:
		failures.append("stamina 10 must still be able to attack")
	if floor_case.stamina_offense_modifier() >= low.stamina_offense_modifier():
		failures.append("stamina 10 should be more conservative than 20")


func _check_monotonic() -> void:
	var previous := 2.0
	for value in [100.0, 75.0, 50.0, 35.0, 20.0, 10.0]:
		var ai := _make(value)
		var offense := ai.stamina_offense_modifier()
		if offense > previous + 0.001:
			failures.append("offense modifier rose as stamina fell at %s" % value)
		previous = offense
		print(
			"stamina=%s offense=%.3f interval=%.3f chance=%.3f"
			% [value, offense, ai.stamina_interval_modifier(), ai.proactive_attack_chance()]
		)


func _check_patterns() -> void:
	var rates_single: Array[float] = []
	for value in [100.0, 75.0, 50.0, 35.0, 20.0, 10.0]:
		var ai := _make(value)
		var counts := [0, 0, 0, 0]
		seed(4040 + int(value))
		for _i in 500:
			counts[ai._choose_pattern()] += 1
		var single := float(counts[0]) / 500.0
		var burst := float(counts[2]) / 500.0
		rates_single.append(single)
		print(
			"pattern stamina=%s single=%.2f quick=%.2f burst=%.2f delayed=%.2f"
			% [
				value,
				single,
				float(counts[1]) / 500.0,
				burst,
				float(counts[3]) / 500.0,
			]
		)
		if value >= 75.0 and single < 0.20:
			failures.append("high stamina should keep single probes")
		if value <= 20.0 and single < 0.45:
			failures.append("low stamina should prefer short patterns")
		if value <= 20.0 and counts[1] + counts[2] + counts[3] == 0:
			failures.append("low stamina must not erase multi-punch patterns")
	if rates_single[2] < rates_single[0] + 0.06:
		failures.append("stamina 50 did not move toward short patterns")
	if rates_single[4] < rates_single[2] + 0.04:
		failures.append("stamina 20 did not shorten patterns further")
	if rates_single[5] + 0.02 < rates_single[4]:
		failures.append("stamina 10 shortened less than stamina 20")


func _check_difficulties() -> void:
	for difficulty in [Settings.Difficulty.EASY, Settings.Difficulty.NORMAL, Settings.Difficulty.HARD]:
		Settings.difficulty = difficulty
		var full := _make(100.0)
		var tired := _make(20.0)
		if tired.proactive_attack_chance() >= full.proactive_attack_chance():
			failures.append("difficulty %s low stamina was not more conservative" % difficulty)
		if full.stamina_offense_modifier() < 0.98:
			failures.append("difficulty %s high stamina changed the baseline" % difficulty)


func _check_defense_untouched() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/opponent_ai.gd")
	if source.find("stamina_offense_modifier()") < 0:
		failures.append("stamina offense modifier missing")
	var defense := source.get_slice("func _choose_defense", 1).get_slice("func ", 0)
	if defense.find("stamina_offense") >= 0:
		failures.append("defense selection uses the stamina offense modifier")
	var pressure := source.get_slice("func _offer_pressure_defense", 1).get_slice("func ", 0)
	if pressure.find("stamina_offense") >= 0:
		failures.append("pressure defense uses the stamina offense modifier")
	var retaliation := source.get_slice("func _take_retaliation_decision", 1).get_slice("func ", 0)
	if retaliation.find("stamina_offense") >= 0:
		failures.append("retaliation uses the stamina offense modifier")
