class_name RoundScorer
extends Node

## MVP 10-Point Must scorer. Weights are tunable in the Inspector.

const RoundScoreScript = preload("res://scripts/round_score.gd")

@export_group("Effective Offense Weights")
@export_range(0.0, 100.0, 0.1, "or_greater") var landed_weight := 1.0
@export_range(0.0, 100.0, 0.01, "or_greater") var damage_weight := 0.05

@export_group("Round Score Rules")
@export_range(0.0, 1000.0, 0.1, "or_greater") var draw_threshold := 1.5
@export_range(0, 10, 1) var minimum_round_score := 7
@export_range(0, 5, 1) var knockdown_score_step := 1


func calculate_effective_offense(stats) -> float:
	return (
		float(stats.attacks_landed) * landed_weight
		+ stats.knockdown_damage_dealt * damage_weight
	)


func score_round(round_number: int, player_stats, opponent_stats):
	var result = RoundScoreScript.new()
	result.round_number = round_number
	result.player_effective = calculate_effective_offense(player_stats)
	result.opponent_effective = calculate_effective_offense(opponent_stats)

	var net_kd: int = player_stats.knockdowns - opponent_stats.knockdowns
	var offense_diff: float = result.player_effective - result.opponent_effective

	if net_kd == 0 and absf(offense_diff) <= draw_threshold:
		result.player_score = 10
		result.opponent_score = 10
		result.is_draw = true
		return result

	var player_wins := false
	if net_kd != 0:
		player_wins = net_kd > 0
	else:
		player_wins = offense_diff > 0

	var kd_margin := absi(net_kd)
	var loser_score := maxi(
		minimum_round_score,
		9 - kd_margin * knockdown_score_step
	)

	if player_wins:
		result.player_score = 10
		result.opponent_score = loser_score
	else:
		result.player_score = loser_score
		result.opponent_score = 10

	result.is_draw = false
	return result


## Best-of-three rounds cannot end drawn. Judge card may still be 10-10.
func decide_round_winner(player_stats, opponent_stats, round_number: int) -> int:
	var score = score_round(1, player_stats, opponent_stats)
	if not score.is_draw:
		if score.player_score > score.opponent_score:
			return 1
		return 2
	var checks: Array = [
		player_stats.knockdowns - opponent_stats.knockdowns,
		player_stats.knockdown_damage_dealt - opponent_stats.knockdown_damage_dealt,
		player_stats.attacks_landed - opponent_stats.attacks_landed,
		(player_stats.attacks_evaded + player_stats.blocked_hits)
			- (opponent_stats.attacks_evaded + opponent_stats.blocked_hits),
		player_stats.attacks_thrown - opponent_stats.attacks_thrown,
	]
	for diff in checks:
		if diff > 0.0:
			return 1
		if diff < 0.0:
			return 2
	return 1 if round_number % 2 == 1 else 2
