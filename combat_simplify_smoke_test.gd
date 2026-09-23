extends SceneTree

## Regression: no Head/Body, Straight-only AI, no Just/Counter/Duck/Random KO.
## Run: godot --headless --path . -s res://combat_simplify_smoke_test.gd

const AttackDataType = preload("res://scripts/opponent_attack_data.gd")
const CombatSideStatsType = preload("res://scripts/combat_side_stats.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const OpponentAIType = preload("res://scripts/opponent_ai.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	_check_no_target_api(failures)
	_check_ai_active_attacks(failures)
	_check_difficulty_resources(failures)
	_check_stats_shape(failures)
	_check_guard_defaults(failures)
	_check_no_duck(failures)
	_check_scene_load(failures)

	if failures.is_empty():
		print("SMOKE PASS: combat simplify (KD Meter / no Just-Counter-Duck)")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_no_target_api(failures: Array[String]) -> void:
	var input := CombatInputType.new()
	if input.has_signal("target_changed"):
		failures.append("target_changed signal still present")
	if input.get("current_target") != null:
		failures.append("current_target still present")
	var preserved_hook: int = AttackDataType.AttackType.LEFT_HOOK
	if preserved_hook != 2:
		failures.append("LEFT_HOOK enum value unexpected")
	input.queue_free()


func _check_ai_active_attacks(failures: Array[String]) -> void:
	var active: Array = OpponentAIType.ACTIVE_ATTACK_TYPES
	if AttackDataType.AttackType.LEFT_HOOK in active:
		failures.append("AI ACTIVE_ATTACK_TYPES includes LEFT_HOOK")
	if AttackDataType.AttackType.RIGHT_HOOK in active:
		failures.append("AI ACTIVE_ATTACK_TYPES includes RIGHT_HOOK")
	if AttackDataType.AttackType.LEFT_STRAIGHT not in active:
		failures.append("AI missing LEFT_STRAIGHT")
	if AttackDataType.AttackType.RIGHT_STRAIGHT not in active:
		failures.append("AI missing RIGHT_STRAIGHT")


func _check_difficulty_resources(failures: Array[String]) -> void:
	for path in [
		"res://data/difficulty/easy.tres",
		"res://data/difficulty/normal.tres",
		"res://data/difficulty/hard.tres",
	]:
		var settings = load(path)
		if settings == null:
			failures.append("Missing difficulty: %s" % path)
			continue
		if settings.get("head_target_weight") != null:
			failures.append("%s still has head_target_weight" % path)
		if settings.get("counter_chance") != null:
			failures.append("%s still has counter_chance" % path)


func _check_stats_shape(failures: Array[String]) -> void:
	var stats := CombatSideStatsType.new()
	if stats.get("head_hits") != null or stats.get("body_hits") != null:
		failures.append("head/body hits still on stats")
	if stats.get("just_attacks") != null:
		failures.append("just_attacks still on stats")
	var _kd = stats.knockdown_damage_dealt


func _check_guard_defaults(failures: Array[String]) -> void:
	var offense := OffenseResolverType.new()
	var defense := DefenseResolverType.new()
	if not is_equal_approx(offense.guard_knockdown_damage_multiplier, 0.25):
		failures.append("offense guard KD mult != 0.25")
	if not is_equal_approx(defense.guard_knockdown_damage_multiplier, 0.25):
		failures.append("defense guard KD mult != 0.25")
	offense.queue_free()
	defense.queue_free()


func _check_no_duck(failures: Array[String]) -> void:
	if &"combat_duck" in InputMap.get_actions():
		failures.append("combat_duck still registered")
	var input := CombatInputType.new()
	## DefenseType should not expose DUCK
	var has_duck := false
	for key in CombatInputType.DefenseType.keys():
		if str(key) == "DUCK":
			has_duck = true
	if has_duck:
		failures.append("DefenseType.DUCK still exists")
	input.queue_free()


func _check_scene_load(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn failed to load")
		return
	var scene := packed.instantiate()
	if scene == null:
		failures.append("game.tscn failed to instantiate")
		return
	if scene.get_node_or_null("DebugHUD/Panel/Margin/Content/TargetRow") != null:
		failures.append("TargetRow still present")
	if scene.get_node_or_null("PlayerCounterWindow") != null:
		failures.append("PlayerCounterWindow still present")
	scene.free()
