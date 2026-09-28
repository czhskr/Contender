extends SceneTree

## Knockdown Meter + Stamina separation smoke tests.
## Run: godot --headless --path . -s res://kd_meter_smoke_test.gd

const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const OpponentAttackDataType = preload("res://scripts/opponent_attack_data.gd")
const OpponentAIType = preload("res://scripts/opponent_ai.gd")
const CombatSideStatsType = preload("res://scripts/combat_side_stats.gd")
const RoundScorerType = preload("res://scripts/round_scorer.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	_check_meter(failures)
	_check_attack_data(failures)
	_check_hit_block_evade(failures)
	_check_no_legacy_systems(failures)
	_check_stats_scorer(failures)
	_check_scene(failures)

	if failures.is_empty():
		print("SMOKE PASS: KD Meter combat simplify")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_meter(failures: Array[String]) -> void:
	var meter := KnockdownMeterType.new()
	root.add_child(meter)
	if not is_equal_approx(meter.current_meter, 0.0):
		failures.append("Meter should start at 0")
	if not is_equal_approx(meter.max_meter, 300.0):
		failures.append("Meter max should be 300")
	meter.apply_knockdown_damage(292.0)
	if not is_equal_approx(meter.current_meter, 292.0):
		failures.append("Meter apply failed")
	meter.apply_knockdown_damage(8.0)
	if not meter.is_full():
		failures.append("Meter should be full at 300")
	meter.apply_knockdown_damage(50.0)
	if not is_equal_approx(meter.current_meter, 300.0):
		failures.append("Meter should clamp at 300")
	meter.set_meter(50.0)
	if not is_equal_approx(meter.current_meter, 50.0):
		failures.append("set_meter 50 failed")
	meter.reduce_meter(15.0)
	if not is_equal_approx(meter.current_meter, 35.0):
		failures.append("reduce_meter failed")
	meter.set_meter(5.0)
	meter.reduce_meter(15.0)
	if not is_equal_approx(meter.current_meter, 0.0):
		failures.append("Meter should clamp at 0")
	meter.queue_free()


func _check_attack_data(failures: Array[String]) -> void:
	var left = load("res://data/attacks/left_straight.tres")
	var right = load("res://data/attacks/right_straight.tres")
	var lh = load("res://data/attacks/left_hook.tres")
	var rh = load("res://data/attacks/right_hook.tres")
	if left == null or not is_equal_approx(left.knockdown_damage, 8.0):
		failures.append("Player L Straight KD dmg != 8")
	if right == null or not is_equal_approx(right.knockdown_damage, 10.0):
		failures.append("Player R Straight KD dmg != 10")
	if lh == null or not is_equal_approx(lh.knockdown_damage, 13.0):
		failures.append("Player L Hook KD dmg != 13")
	if rh == null or not is_equal_approx(rh.knockdown_damage, 15.0):
		failures.append("Player R Hook KD dmg != 15")
	if left != null and not is_equal_approx(left.stamina_cost, 4.0):
		failures.append("Player L Straight cost != 4")
	if right != null and not is_equal_approx(right.stamina_cost, 5.0):
		failures.append("Player R Straight cost != 5")
	if lh != null and not is_equal_approx(lh.stamina_cost, 7.0):
		failures.append("Player L Hook cost != 7")
	if rh != null and not is_equal_approx(rh.stamina_cost, 8.0):
		failures.append("Player R Hook cost != 8")
	var ol = load("res://data/opponent_attacks/left_straight.tres")
	var orr = load("res://data/opponent_attacks/right_straight.tres")
	if ol == null or not is_equal_approx(ol.knockdown_damage, 8.0):
		failures.append("Opp L Straight KD dmg != 8")
	if orr == null or not is_equal_approx(orr.knockdown_damage, 10.0):
		failures.append("Opp R Straight KD dmg != 10")
	if left != null and left.get("stamina_damage") != null:
		failures.append("Player attack still has stamina_damage property")


func _check_hit_block_evade(failures: Array[String]) -> void:
	## Resolver defaults + meter math for HIT / BLOCK / EVADE outcomes.
	var offense := OffenseResolverType.new()
	var defense := DefenseResolverType.new()
	if not is_equal_approx(offense.guard_knockdown_damage_multiplier, 0.25):
		failures.append("offense guard mult != 0.25")
	if not is_equal_approx(defense.guard_knockdown_damage_multiplier, 0.25):
		failures.append("defense guard mult != 0.25")
	offense.queue_free()
	defense.queue_free()

	var meter := KnockdownMeterType.new()
	root.add_child(meter)

	## HIT: full knockdown_damage
	var hit_applied: float = meter.apply_knockdown_damage(10.0)
	if not is_equal_approx(hit_applied, 10.0) or not is_equal_approx(meter.current_meter, 10.0):
		failures.append("HIT should apply full KD damage")

	## BLOCK: KD * 0.25
	var block_raw := 10.0 * 0.25
	meter.apply_knockdown_damage(block_raw)
	if not is_equal_approx(meter.current_meter, 12.5):
		failures.append("BLOCK should add KD * 0.25")

	## EVADE: no meter change
	var before_evade := meter.current_meter
	var evade_applied: float = meter.apply_knockdown_damage(0.0)
	if not is_equal_approx(evade_applied, 0.0) or not is_equal_approx(meter.current_meter, before_evade):
		failures.append("EVADE should not change KD meter")

	## 292 + 8 → full at the 300 maximum.
	meter.set_meter(292.0)
	var applied_to_full: float = meter.apply_knockdown_damage(8.0)
	if not meter.is_full() or not is_equal_approx(meter.current_meter, 300.0):
		failures.append("292 + 8 should fill meter to 300")
	if not is_equal_approx(applied_to_full, 8.0):
		failures.append("92 + 8 should apply exactly 8 KD")

	meter.queue_free()


func _check_no_legacy_systems(failures: Array[String]) -> void:
	if FileAccess.file_exists("res://scripts/ko_chance_settings.gd"):
		failures.append("ko_chance_settings.gd still exists")
	if FileAccess.file_exists("res://scripts/player_counter_window.gd"):
		failures.append("player_counter_window.gd still exists")
	if FileAccess.file_exists("res://data/ko/player_ko_chance.tres"):
		failures.append("player_ko_chance.tres still exists")
	var CombatInputType = load("res://scripts/player_combat_input.gd")
	var input = CombatInputType.new()
	if &"combat_duck" in InputMap.get_actions():
		failures.append("combat_duck still in InputMap")
	if &"combat_toggle_target" in InputMap.get_actions():
		failures.append("combat_toggle_target still in InputMap")
	if OpponentAttackDataType.AttackType.LEFT_HOOK in OpponentAIType.ACTIVE_ATTACK_TYPES:
		failures.append("AI Hooks re-enabled")
	var has_duck := false
	for key in CombatInputType.EvadeDirection.keys():
		if str(key) == "DUCK":
			has_duck = true
	if has_duck:
		failures.append("EvadeDirection.DUCK must not exist")
	input.queue_free()


func _check_stats_scorer(failures: Array[String]) -> void:
	var stats := CombatSideStatsType.new()
	if stats.get("just_attacks") != null:
		failures.append("just_attacks still on CombatSideStats")
	if stats.get("counter_hits") != null:
		failures.append("counter_hits still on CombatSideStats")
	var scorer := RoundScorerType.new()
	stats.attacks_landed = 2
	stats.knockdown_damage_dealt = 20.0
	var eff := scorer.calculate_effective_offense(stats)
	## 2 * 1.0 + 20 * 0.05 = 3.0
	if not is_equal_approx(eff, 3.0):
		failures.append("effective offense expected 3.0, got %.2f" % eff)
	scorer.queue_free()


func _check_scene(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn failed to load")
		return
	var scene := packed.instantiate()
	if scene.get_node_or_null("PlayerKnockdownMeter") == null:
		failures.append("PlayerKnockdownMeter missing")
	if scene.get_node_or_null("OpponentKnockdownMeter") == null:
		failures.append("OpponentKnockdownMeter missing")
	if scene.get_node_or_null("PlayerCounterWindow") != null:
		failures.append("PlayerCounterWindow still in scene")
	if scene.get_node_or_null("OpponentCounterWindow") != null:
		failures.append("OpponentCounterWindow still in scene")
	var hud = scene.get_node_or_null("DebugHUD/Panel/Margin/Content")
	if hud != null:
		if hud.get_node_or_null("PlayerKnockdownMeterBar") == null:
			failures.append("PlayerKnockdownMeterBar missing")
		if hud.get_node_or_null("OpponentKnockdownMeterBar") == null:
			failures.append("OpponentKnockdownMeterBar missing")
		if hud.get_node_or_null("CounterWindowRow") != null:
			failures.append("CounterWindowRow still in HUD")
		if hud.get_node_or_null("TargetRow") != null:
			failures.append("TargetRow still in HUD")
	var offense = scene.get_node_or_null("PlayerOffenseResolver")
	if offense != null and offense.opponent_knockdown_meter == null:
		failures.append("OffenseResolver missing opponent KD meter")
	var defense = scene.get_node_or_null("PlayerDefenseResolver")
	if defense != null and defense.player_knockdown_meter == null:
		failures.append("DefenseResolver missing player KD meter")
	var stun = scene.get_node_or_null("PlayerHitStun")
	if stun != null and stun.is_hit_stunned():
		failures.append("Normal HIT must not gameplay-stun")
	var kd_mgr = scene.get_node_or_null("KnockdownManager")
	if kd_mgr != null and not is_equal_approx(kd_mgr.recovery_meter_ratio, 0.5):
		failures.append("recovery_meter_ratio != 0.5")
	var round_mgr = scene.get_node_or_null("RoundManager")
	if round_mgr != null and not is_equal_approx(round_mgr.round_duration, 60.0):
		failures.append("round duration != 60")
	scene.free()
