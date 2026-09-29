class_name MatchResultData
extends RefCounted

const RoundScoreScript = preload("res://scripts/round_score.gd")
const CombatSideStatsScript = preload("res://scripts/combat_side_stats.gd")
const RoundStatsSnapshotScript = preload("res://scripts/round_stats_snapshot.gd")

enum Winner {
	NONE,
	PLAYER,
	OPPONENT,
}

enum ResultType {
	NONE,
	KO,
	DECISION,
	DRAW,
}

var winner := Winner.NONE
var result_type := ResultType.NONE
var player_total_score := 0
var opponent_total_score := 0
var round_scores: Array = []
var cumulative_player = CombatSideStatsScript.new()
var cumulative_opponent = CombatSideStatsScript.new()
var round_stats: Array = []
var ended_in_round := 0
var player_round_wins := 0
var opponent_round_wins := 0

static var current: MatchResultData = null
static var resume_mode := 0


static func publish(result: MatchResultData, mode: int) -> void:
	current = result
	resume_mode = mode


func get_round_score(round_number: int):
	for score in round_scores:
		if score.round_number == round_number:
			return score
	return null


func get_round_stats(round_number: int):
	for snap in round_stats:
		if snap.round_number == round_number:
			return snap
	return null
