class_name MatchDecision
extends Node

## Finalizes round scores and decision / KO match results for Result Scene.

signal round_scored(score)
signal match_result_ready(result)
signal hud_text_changed(text: String)

const CombatStatsType = preload("res://scripts/combat_stats.gd")
const RoundScorerType = preload("res://scripts/round_scorer.gd")
const RoundManagerType = preload("res://scripts/round_manager.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")
const MatchResultDataScript = preload("res://scripts/match_result_data.gd")

@export var combat_stats: CombatStatsType
@export var round_scorer: RoundScorerType
@export var round_manager: RoundManagerType

@export_group("Debug")
@export var print_events := true

var round_scores: Array = []
var latest_result = null
var _decision_resolved := false
var _ko_resolved := false


func _ready() -> void:
	if combat_stats != null:
		combat_stats.round_stats_finalized.connect(_on_round_stats_finalized)
	if round_manager != null:
		round_manager.decision_required.connect(_on_decision_required)
		round_manager.match_stopped_by_ko.connect(_on_match_stopped_by_ko)


func get_round_score(round_number: int):
	for score in round_scores:
		if score.round_number == round_number:
			return score
	return null


func _on_round_stats_finalized(snapshot) -> void:
	if _ko_resolved:
		return

	var score = round_scorer.score_round(
		snapshot.round_number,
		snapshot.player,
		snapshot.opponent
	)
	round_scores.append(score)
	round_scored.emit(score)

	if print_events:
		_print_round_result(snapshot, score)

	hud_text_changed.emit(
		"R%d %d-%d" % [score.round_number, score.player_score, score.opponent_score]
	)


func _on_decision_required() -> void:
	if _ko_resolved or _decision_resolved:
		return
	_decision_resolved = true

	var result = _build_base_result()
	result.result_type = MatchResultDataScript.ResultType.DECISION

	var player_total := 0
	var opponent_total := 0
	for score in round_scores:
		player_total += score.player_score
		opponent_total += score.opponent_score

	result.player_total_score = player_total
	result.opponent_total_score = opponent_total

	if round_manager != null and round_manager.player_round_wins != round_manager.opponent_round_wins:
		if round_manager.player_round_wins > round_manager.opponent_round_wins:
			result.winner = MatchResultDataScript.Winner.PLAYER
		else:
			result.winner = MatchResultDataScript.Winner.OPPONENT
	elif player_total > opponent_total:
		result.winner = MatchResultDataScript.Winner.PLAYER
	elif opponent_total > player_total:
		result.winner = MatchResultDataScript.Winner.OPPONENT
	else:
		result.winner = MatchResultDataScript.Winner.PLAYER

	latest_result = result
	if print_events:
		_print_final(result)
	match_result_ready.emit(result)
	hud_text_changed.emit(_result_hud_text(result))


func _on_match_stopped_by_ko(winner: int) -> void:
	if _ko_resolved or _decision_resolved:
		return
	_ko_resolved = true

	var result = _build_base_result()
	result.result_type = MatchResultDataScript.ResultType.KO
	if winner == KnockdownManagerType.Winner.PLAYER:
		result.winner = MatchResultDataScript.Winner.PLAYER
	else:
		result.winner = MatchResultDataScript.Winner.OPPONENT

	## Completed rounds may already be scored; unfinished round is omitted.
	var player_total := 0
	var opponent_total := 0
	for score in round_scores:
		player_total += score.player_score
		opponent_total += score.opponent_score
	result.player_total_score = player_total
	result.opponent_total_score = opponent_total

	if round_manager != null:
		result.ended_in_round = round_manager.current_round

	latest_result = result
	if print_events:
		var winner_label := (
			"PLAYER" if result.winner == MatchResultDataScript.Winner.PLAYER else "OPPONENT"
		)
		print("RESULT: %s KO WIN (decision skipped)" % winner_label)
	match_result_ready.emit(result)
	hud_text_changed.emit(_result_hud_text(result))


func _build_base_result():
	var result = MatchResultDataScript.new()
	result.round_scores = round_scores.duplicate()
	if combat_stats != null:
		result.cumulative_player = combat_stats.cumulative_player.duplicate_stats()
		result.cumulative_opponent = combat_stats.cumulative_opponent.duplicate_stats()
		result.round_stats = combat_stats.get_all_round_snapshots()
		result.ended_in_round = combat_stats.current_round
	return result


func _print_round_result(snapshot, score) -> void:
	var p = snapshot.player
	var o = snapshot.opponent
	print("ROUND %d RESULT" % snapshot.round_number)
	print(
		"Player: Landed %d | KD dmg %.0f | KD %d"
		% [p.attacks_landed, p.knockdown_damage_dealt, p.knockdowns]
	)
	print(
		"Opponent: Landed %d | KD dmg %.0f | KD %d"
		% [o.attacks_landed, o.knockdown_damage_dealt, o.knockdowns]
	)
	print(
		"Score: Player %d - %d Opponent"
		% [score.player_score, score.opponent_score]
	)


func _print_final(result) -> void:
	print(
		"FINAL SCORE: %d - %d"
		% [result.player_total_score, result.opponent_total_score]
	)
	print("RESULT: %s" % _result_label(result))


func _result_label(result) -> String:
	match result.result_type:
		MatchResultDataScript.ResultType.KO:
			if result.winner == MatchResultDataScript.Winner.PLAYER:
				return "PLAYER KO WIN"
			return "OPPONENT KO WIN"
		MatchResultDataScript.ResultType.DRAW:
			return "DRAW"
		MatchResultDataScript.ResultType.DECISION:
			if result.winner == MatchResultDataScript.Winner.PLAYER:
				return "PLAYER DECISION WIN"
			return "OPPONENT DECISION WIN"
		_:
			return "NONE"


func _result_hud_text(result) -> String:
	if result.result_type == MatchResultDataScript.ResultType.KO:
		return _result_label(result)
	return "%s\n%d - %d" % [
		_result_label(result),
		result.player_total_score,
		result.opponent_total_score,
	]
