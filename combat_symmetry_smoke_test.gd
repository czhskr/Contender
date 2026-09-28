extends SceneTree


func _initialize() -> void:
	var failures: Array[String] = []
	var player_left = load("res://data/attacks/left_straight.tres")
	var player_right = load("res://data/attacks/right_straight.tres")
	var opp_left = load("res://data/opponent_attacks/left_straight.tres")
	var opp_right = load("res://data/opponent_attacks/right_straight.tres")
	_same(failures, "LEFT startup", player_left.startup_time, opp_left.startup_time, 0.10)
	_same(failures, "LEFT active", player_left.active_time, opp_left.active_time, 0.08)
	_same(failures, "LEFT recovery", player_left.recovery_time, opp_left.recovery_time, 0.11)
	_same(failures, "RIGHT startup", player_right.startup_time, opp_right.startup_time, 0.14)
	_same(failures, "RIGHT active", player_right.active_time, opp_right.active_time, 0.09)
	_same(failures, "RIGHT recovery", player_right.recovery_time, opp_right.recovery_time, 0.14)
	if opp_left.startup_time > 0.5 or opp_right.startup_time > 0.5:
		failures.append("Opponent straight startup is still the slow value")
	if failures.is_empty():
		print("SMOKE PASS: combat symmetry")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _same(failures: Array[String], label: String, player_value: float, opponent_value: float, expected: float) -> void:
	if not is_equal_approx(player_value, expected) or not is_equal_approx(opponent_value, expected):
		failures.append("%s player=%.2f opponent=%.2f expected=%.2f" % [label, player_value, opponent_value, expected])
