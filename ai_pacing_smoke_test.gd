extends SceneTree

## Opponent AI pacing / opposite-hand follow-up regression (KD Meter era).
## Run: godot --headless --path . -s res://ai_pacing_smoke_test.gd

const OpponentAIType = preload("res://scripts/opponent_ai.gd")
const AttackDataType = preload("res://scripts/opponent_attack_data.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	_check_attack_cooldown_zero(failures)
	_check_difficulty(failures)
	_check_follow_up_opposite(failures)
	_check_scene(failures)

	if failures.is_empty():
		print("SMOKE PASS: AI pacing / follow-up")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_attack_cooldown_zero(failures: Array[String]) -> void:
	var state_script = load("res://scripts/opponent_attack_state.gd")
	var node = state_script.new()
	if not is_equal_approx(node.attack_cooldown, 0.0):
		failures.append(
			"OpponentAttackState.attack_cooldown expected 0, got %.2f" % node.attack_cooldown
		)
	node.queue_free()


func _check_difficulty(failures: Array[String]) -> void:
	var expected := {
		"res://data/difficulty/easy.tres": {
			"min": 0.35, "max": 0.7, "fu": 0.25, "fu_min": 0.12, "fu_max": 0.25
		},
		"res://data/difficulty/normal.tres": {
			"min": 0.1, "max": 0.3, "fu": 0.6, "fu_min": 0.05, "fu_max": 0.12
		},
		"res://data/difficulty/hard.tres": {
			"min": 0.03, "max": 0.15, "fu": 0.8, "fu_min": 0.02, "fu_max": 0.08
		},
	}
	for path in expected.keys():
		var settings = load(path)
		if settings == null:
			failures.append("Missing %s" % path)
			continue
		var e: Dictionary = expected[path]
		if not is_equal_approx(settings.attack_interval_min, e["min"]):
			failures.append("%s interval_min" % path)
		if not is_equal_approx(settings.attack_interval_max, e["max"]):
			failures.append("%s interval_max" % path)
		if not is_equal_approx(settings.follow_up_chance, e["fu"]):
			failures.append("%s follow_up_chance" % path)
		if not is_equal_approx(settings.follow_up_delay_min, e["fu_min"]):
			failures.append("%s follow_up_delay_min" % path)
		if not is_equal_approx(settings.follow_up_delay_max, e["fu_max"]):
			failures.append("%s follow_up_delay_max" % path)


func _check_follow_up_opposite(failures: Array[String]) -> void:
	var ai := OpponentAIType.new()
	if not ai.has_method("_pick_follow_up_attack"):
		failures.append("Missing _pick_follow_up_attack")
	if AttackDataType.AttackType.LEFT_HOOK in OpponentAIType.ACTIVE_ATTACK_TYPES:
		failures.append("Hook re-enabled in ACTIVE_ATTACK_TYPES")
	ai.queue_free()


func _check_scene(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn load failed")
		return
	var scene := packed.instantiate()
	var opp_attack = scene.get_node_or_null("OpponentAttackState")
	if opp_attack != null and opp_attack.attack_cooldown > 0.05:
		failures.append(
			"Scene attack_cooldown still high: %.2f" % opp_attack.attack_cooldown
		)
	var player_stun = scene.get_node_or_null("PlayerHitStun")
	if player_stun != null and not is_equal_approx(player_stun.hit_stun_duration, 0.35):
		failures.append("Hit Stun not 0.35")
	scene.free()
