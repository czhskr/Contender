extends SceneTree

## Player and opponent recovery use one formula. The curve is not retuned here.
## Run: godot --headless --path . -s res://recovery_symmetry_smoke_test.gd

const Recovery = preload("res://scripts/recovery_chance_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var player: Recovery = load("res://data/ko/player_recovery_chance.tres")
	var opponent: Recovery = load("res://data/ko/opponent_recovery_chance.tres")
	_check_resources(player, opponent, failures)
	_check_scene(failures)
	_check_curve(player, opponent, failures)
	_check_samples(player, opponent, failures)
	if failures.is_empty():
		print("SMOKE PASS: recovery symmetry")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_resources(player: Recovery, opponent: Recovery, failures: Array[String]) -> void:
	var fields: Array[String] = [
		"reference_stamina",
		"recovery_chance_exponent",
		"max_recovery_chance",
		"min_recovery_chance",
		"earliest_stand_up_count",
		"latest_stand_up_count",
		"stand_up_count_exponent",
		"recovery_stamina_amount",
	]
	for field in fields:
		if not is_equal_approx(float(player.get(field)), float(opponent.get(field))):
			failures.append("%s differs: player %s opponent %s" % [field, player.get(field), opponent.get(field)])


func _check_scene(failures: Array[String]) -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	var manager = game.get_node("KnockdownManager")
	var player_path: String = manager.player_recovery_settings.resource_path
	var opponent_path: String = manager.opponent_recovery_settings.resource_path
	if player_path != "res://data/ko/player_recovery_chance.tres":
		failures.append("player recovery resource is %s" % player_path)
	if opponent_path != "res://data/ko/opponent_recovery_chance.tres":
		failures.append("opponent recovery resource is %s" % opponent_path)
	game.free()


func _check_curve(player: Recovery, opponent: Recovery, failures: Array[String]) -> void:
	var targets := {
		0.0: {"chance": 0.10, "count": 9},
		10.0: {"chance": 0.12, "count": 9},
		25.0: {"chance": 0.18, "count": 8},
		50.0: {"chance": 0.30, "count": 6},
		75.0: {"chance": 0.45, "count": 4},
		100.0: {"chance": 0.60, "count": 3},
	}
	for stamina in [0.0, 10.0, 25.0, 50.0, 75.0, 100.0]:
		var player_chance := player.calculate_recovery_chance(stamina)
		var opponent_chance := opponent.calculate_recovery_chance(stamina)
		if not is_equal_approx(player_chance, opponent_chance):
			failures.append("chance differs at stamina %.0f" % stamina)
		var player_count := player.calculate_stand_up_count(stamina)
		var opponent_count := opponent.calculate_stand_up_count(stamina)
		if player_count != opponent_count:
			failures.append("stand count differs at stamina %.0f" % stamina)
		if player_count < 3 or player_count > 9:
			failures.append("stand count %d is outside 3-9" % player_count)
		var target: Dictionary = targets[stamina]
		if absf(player_chance - float(target["chance"])) > 0.02:
			failures.append("stamina %.0f chance %.3f is far from %.2f" % [stamina, player_chance, target["chance"]])
		if absi(player_count - int(target["count"])) > 1:
			failures.append("stamina %.0f stand %d is far from %d" % [stamina, player_count, target["count"]])
		print("CHANCE stamina=%.0f final=%.3f stand=%d" % [stamina, player_chance, player_count])
	var first := player.calculate_recovery_chance(40.0)
	var second := player.calculate_recovery_chance(40.0)
	var third := player.calculate_recovery_chance(40.0)
	if not is_equal_approx(first, second) or not is_equal_approx(second, third):
		failures.append("knockdown count changed the chance formula")


func _check_samples(player: Recovery, opponent: Recovery, failures: Array[String]) -> void:
	var samples := 400
	for stamina in [0.0, 10.0, 25.0, 50.0, 75.0, 100.0]:
		var expected := player.calculate_recovery_chance(stamina)
		var player_success := 0
		var opponent_success := 0
		for index in samples:
			seed(index + int(stamina) * 1000)
			if bool(player.resolve_recovery(stamina)["success"]):
				player_success += 1
			seed(index + int(stamina) * 1000)
			var opponent_roll: Dictionary = opponent.resolve_recovery(stamina)
			if bool(opponent_roll["success"]):
				opponent_success += 1
			seed(index + int(stamina) * 1000)
			var again: Dictionary = player.resolve_recovery(stamina)
			if int(again["stand_up_count"]) != int(opponent_roll["stand_up_count"]):
				failures.append("stand count diverged at stamina %.0f sample %d" % [stamina, index])
				return
		var player_rate := float(player_success) / float(samples)
		var opponent_rate := float(opponent_success) / float(samples)
		print(
			"SAMPLE stamina=%.0f expected=%.3f player=%.3f opponent=%.3f n=%d"
			% [stamina, expected, player_rate, opponent_rate, samples]
		)
		if player_success != opponent_success:
			failures.append("paired sample diverged at stamina %.0f" % stamina)
		if absf(player_rate - expected) > 0.08:
			failures.append("player sample %.3f is far from %.3f at stamina %.0f" % [player_rate, expected, stamina])
