extends SceneTree

## Hit Stun / AI / trade wiring regression (post KD Meter refactor).
## Run: godot --headless --path . -s res://balance_smoke_test.gd

const HitStunType = preload("res://scripts/hit_stun.gd")
const HitResolveCoordinatorType = preload("res://scripts/hit_resolve_coordinator.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const OpponentAIType = preload("res://scripts/opponent_ai.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	_check_hit_stun_default(failures)
	_check_difficulty_intervals(failures)
	_check_follow_up_fields(failures)
	_check_scene_wiring(failures)
	_check_simultaneous_trade_logic(failures)

	if failures.is_empty():
		print("SMOKE PASS: balance (hit stun / AI / trade)")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_hit_stun_default(failures: Array[String]) -> void:
	var stun := HitStunType.new()
	if not is_equal_approx(stun.hit_stun_duration, 0.35):
		failures.append(
			"HitStun default duration expected 0.35, got %.2f" % stun.hit_stun_duration
		)
	stun.queue_free()


func _check_difficulty_intervals(failures: Array[String]) -> void:
	var expected := {
		"res://data/difficulty/easy.tres": [0.35, 0.7, 0.25],
		"res://data/difficulty/normal.tres": [0.1, 0.3, 0.6],
		"res://data/difficulty/hard.tres": [0.03, 0.15, 0.8],
	}
	for path in expected.keys():
		var settings = load(path)
		if settings == null:
			failures.append("Missing difficulty: %s" % path)
			continue
		var vals: Array = expected[path]
		if not is_equal_approx(settings.attack_interval_min, vals[0]):
			failures.append("%s interval_min != %.2f" % [path, vals[0]])
		if not is_equal_approx(settings.attack_interval_max, vals[1]):
			failures.append("%s interval_max != %.2f" % [path, vals[1]])
		if not is_equal_approx(settings.follow_up_chance, vals[2]):
			failures.append("%s follow_up_chance != %.2f" % [path, vals[2]])


func _check_follow_up_fields(failures: Array[String]) -> void:
	var ai := OpponentAIType.new()
	if not ai.has_method("clear_pending_combat_decisions"):
		failures.append("OpponentAI missing clear_pending_combat_decisions")
	ai.queue_free()


func _check_scene_wiring(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn failed to load")
		return
	var scene := packed.instantiate()
	if scene == null:
		failures.append("game.tscn failed to instantiate")
		return

	var player_stun = scene.get_node_or_null("PlayerHitStun")
	var opp_stun = scene.get_node_or_null("OpponentHitStun")
	var coord = scene.get_node_or_null("HitResolveCoordinator")
	var offense = scene.get_node_or_null("PlayerOffenseResolver")
	var defense = scene.get_node_or_null("PlayerDefenseResolver")

	if player_stun == null or opp_stun == null:
		failures.append("HitStun nodes missing")
	elif (
		not is_equal_approx(player_stun.hit_stun_duration, 0.35)
		or not is_equal_approx(opp_stun.hit_stun_duration, 0.35)
	):
		failures.append("Scene HitStun duration not 0.35")

	if coord == null:
		failures.append("HitResolveCoordinator missing")
	if offense != null and offense.hit_resolve_coordinator == null:
		failures.append("OffenseResolver missing coordinator")
	if defense != null and defense.hit_resolve_coordinator == null:
		failures.append("DefenseResolver missing coordinator")
	if scene.get_node_or_null("PlayerKnockdownMeter") == null:
		failures.append("PlayerKnockdownMeter missing")

	scene.free()


func _check_simultaneous_trade_logic(failures: Array[String]) -> void:
	var coord := HitResolveCoordinatorType.new()
	if not coord.has_method("queue_player_active"):
		failures.append("Coordinator missing queue_player_active")
	if not coord.has_method("queue_opponent_active"):
		failures.append("Coordinator missing queue_opponent_active")
	if not OffenseResolverType.new().has_method("resolve_hit_now"):
		failures.append("OffenseResolver missing resolve_hit_now")
	coord.queue_free()
