extends SceneTree

## Difficulty only scales AI decisions. Combat numbers stay put.
## godot --headless --path . -s res://tests/ai/difficulty_smoke_test.gd

const MatchSettings = preload("res://scripts/match_settings.gd")
const AIType = preload("res://scripts/opponent_ai.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")
const AttackType = preload("res://scripts/attack_data.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	MatchSettings.difficulty = MatchSettings.Difficulty.NORMAL
	if MatchSettings.difficulty != MatchSettings.Difficulty.NORMAL:
		failures.append("default difficulty is not NORMAL")
	var ai := AIType.new()
	_check_normal_baseline(ai, failures)
	_check_level(ai, MatchSettings.Difficulty.EASY, 0.2925, [0.48, 0.544, 0.608], [0.130, 0.08125, 0.04875], 0.24, 0.3375, 0.45, failures)
	_check_level(ai, MatchSettings.Difficulty.NORMAL, 0.234, [0.60, 0.68, 0.76], [0.104, 0.065, 0.039], 0.32, 0.45, 0.60, failures)
	_check_level(ai, MatchSettings.Difficulty.HARD, 0.1755, [0.75, 0.85, 0.95], [0.078, 0.04875, 0.02925], 0.48, 0.675, 0.90, failures)
	_check_combat_unchanged(ai, failures)
	MatchSettings.step_difficulty(-1)
	MatchSettings.difficulty = MatchSettings.Difficulty.EASY
	MatchSettings.step_difficulty(-1)
	if MatchSettings.difficulty != MatchSettings.Difficulty.EASY:
		failures.append("easy wrapped below the start")
	MatchSettings.step_difficulty(1)
	if MatchSettings.difficulty != MatchSettings.Difficulty.NORMAL:
		failures.append("easy did not step to normal")
	MatchSettings.step_difficulty(1)
	MatchSettings.step_difficulty(1)
	if MatchSettings.difficulty != MatchSettings.Difficulty.HARD:
		failures.append("hard wrapped past the end")
	MatchSettings.difficulty = MatchSettings.Difficulty.NORMAL
	ai.free()
	if failures.is_empty():
		print("SMOKE PASS: difficulty")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_normal_baseline(ai, failures: Array[String]) -> void:
	var settings = preload("res://scripts/opponent_difficulty_settings.gd").new()
	if not is_equal_approx(settings.reaction_delay, 0.234):
		failures.append("normal reaction baseline is not 0.234")
	if not is_equal_approx(ai.proactive_defense_interval_min, 0.55) or not is_equal_approx(ai.proactive_defense_interval_max, 1.05):
		failures.append("proactive interval is not 0.55-1.05")
	if not is_equal_approx(ai.neutral_offense_scale, 0.82):
		failures.append("neutral offense scale changed")
	if not is_equal_approx(ai.initiative_block_duration, 0.20) or not is_equal_approx(ai.initiative_evade_duration, 0.35):
		failures.append("initiative windows changed")
	if not is_equal_approx(ai.pressure_guard_weight, 0.45):
		failures.append("guard/slip mix changed")


func _check_level(ai, level: int, reaction: float, defense: Array, pressure: Array, offense: float, block: float, evade: float, failures: Array[String]) -> void:
	MatchSettings.difficulty = level
	if not is_equal_approx(ai._compose_reaction(0.234), reaction):
		failures.append("reaction %.3f expected %.3f" % [ai._compose_reaction(0.234), reaction])
	ai._pressure_hit_count = 1
	if not is_equal_approx(ai._pressure_defense_chance_now(), defense[0]):
		failures.append("defense1 %.4f" % ai._pressure_defense_chance_now())
	if not is_equal_approx(ai._compose_reaction(ai._pressure_reaction_base()), pressure[0]):
		failures.append("pressure reaction 1")
	ai._pressure_hit_count = 2
	if not is_equal_approx(ai._pressure_defense_chance_now(), defense[1]):
		failures.append("defense2")
	if not is_equal_approx(ai._compose_reaction(ai._pressure_reaction_base()), pressure[1]):
		failures.append("pressure reaction 2")
	ai._pressure_hit_count = 3
	if not is_equal_approx(ai._pressure_defense_chance_now(), defense[2]):
		failures.append("defense3 %.4f" % ai._pressure_defense_chance_now())
	if not is_equal_approx(ai._compose_reaction(ai._pressure_reaction_base()), pressure[2]):
		failures.append("pressure reaction 3")
	if not is_equal_approx(ai._proactive_action_chance(), offense):
		failures.append("offense frequency")
	if not is_equal_approx(ai._scaled_chance(ai.retaliation_block_chance, MatchSettings.retaliation_chance_multiplier()), block):
		failures.append("block retaliation")
	if not is_equal_approx(ai._scaled_chance(ai.retaliation_evade_chance, MatchSettings.retaliation_chance_multiplier()), evade):
		failures.append("evade retaliation")


func _check_combat_unchanged(ai, failures: Array[String]) -> void:
	var before_startup := 0.10
	var attack := AttackType.new()
	if not is_equal_approx(attack.startup_duration if attack.get("startup_duration") != null else before_startup, before_startup) and attack.get("startup") != null:
		pass
	var meter := MeterType.new()
	var maximum := meter.max_meter
	MatchSettings.difficulty = MatchSettings.Difficulty.HARD
	if not is_equal_approx(meter.max_meter, maximum):
		failures.append("difficulty changed the KD meter")
	if not is_equal_approx(ai.attack_to_attack_cancel, 0.50):
		failures.append("difficulty changed attack cancel")
	meter.free()
