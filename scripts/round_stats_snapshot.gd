class_name RoundStatsSnapshot
extends RefCounted

const CombatSideStatsScript = preload("res://scripts/combat_side_stats.gd")

var round_number := 0
var player = CombatSideStatsScript.new()
var opponent = CombatSideStatsScript.new()


func duplicate_snapshot():
	var copy = new()
	copy.round_number = round_number
	copy.player = player.duplicate_stats()
	copy.opponent = opponent.duplicate_stats()
	return copy
