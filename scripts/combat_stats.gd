class_name CombatStats
extends Node

## Collects fight statistics by listening to combat signals. Does not resolve combat.

signal round_stats_finalized(snapshot)
signal stats_changed

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")
const RoundManagerType = preload("res://scripts/round_manager.gd")
const CombatSideStatsScript = preload("res://scripts/combat_side_stats.gd")
const RoundStatsSnapshotScript = preload("res://scripts/round_stats_snapshot.gd")

@export var player_attack_state: AttackStateType
@export var opponent_attack_state: OpponentAttackStateType
@export var defense_resolver: DefenseResolverType
@export var offense_resolver: OffenseResolverType
@export var knockdown_manager: KnockdownManagerType
@export var round_manager: RoundManagerType

@export_group("Debug")
@export var print_events := false

var current_round := 0
var recording := false

var current_player = CombatSideStatsScript.new()
var current_opponent = CombatSideStatsScript.new()
var cumulative_player = CombatSideStatsScript.new()
var cumulative_opponent = CombatSideStatsScript.new()

## Keyed by round number (1-based).
var round_stats: Dictionary = {}


func _ready() -> void:
	if player_attack_state != null:
		player_attack_state.state_changed.connect(_on_player_attack_state_changed)
	if opponent_attack_state != null:
		opponent_attack_state.state_changed.connect(_on_opponent_attack_state_changed)
	if offense_resolver != null:
		offense_resolver.attack_hit.connect(_on_player_attack_hit)
	if defense_resolver != null:
		defense_resolver.attack_resolved.connect(_on_opponent_attack_resolved)
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_knockdown_state_changed)
	if round_manager != null:
		round_manager.round_started.connect(_on_round_started)
		round_manager.round_ended.connect(_on_round_ended)


func get_round_snapshot(round_number: int):
	if not round_stats.has(round_number):
		return null
	return round_stats[round_number]


func get_all_round_snapshots() -> Array:
	var keys: Array = round_stats.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		result.append(round_stats[key])
	return result


func begin_round(round_number: int) -> void:
	current_round = round_number
	current_player = CombatSideStatsScript.new()
	current_opponent = CombatSideStatsScript.new()
	recording = true
	stats_changed.emit()


func finalize_current_round():
	if current_round <= 0:
		return null

	recording = false
	var snapshot = RoundStatsSnapshotScript.new()
	snapshot.round_number = current_round
	snapshot.player = current_player.duplicate_stats()
	snapshot.opponent = current_opponent.duplicate_stats()
	round_stats[current_round] = snapshot

	cumulative_player.add_other(snapshot.player)
	cumulative_opponent.add_other(snapshot.opponent)

	if print_events:
		print(
			"Round %d stats saved | P landed %d KD dmg %.0f KD %d | O landed %d KD dmg %.0f KD %d"
			% [
				current_round,
				snapshot.player.attacks_landed,
				snapshot.player.knockdown_damage_dealt,
				snapshot.player.knockdowns,
				snapshot.opponent.attacks_landed,
				snapshot.opponent.knockdown_damage_dealt,
				snapshot.opponent.knockdowns,
			]
		)

	round_stats_finalized.emit(snapshot)
	stats_changed.emit()
	return snapshot


func _on_round_started(round_number: int) -> void:
	begin_round(round_number)


func _on_round_ended(_round_number: int) -> void:
	finalize_current_round()


func _on_player_attack_state_changed(state: int, _attack: int) -> void:
	if not recording:
		return
	if state == AttackStateType.AttackState.ACTIVE:
		current_player.attacks_thrown += 1
		stats_changed.emit()


func _on_opponent_attack_state_changed(state: int, _attack_data) -> void:
	if not recording:
		return
	if state == OpponentAttackStateType.AttackState.ACTIVE:
		current_opponent.attacks_thrown += 1
		stats_changed.emit()


func _on_player_attack_hit(
	_attack: int,
	knockdown_damage: float,
	_opponent_meter: float,
	_was_knockdown: bool,
	result: int
) -> void:
	if not recording:
		return

	match result:
		OffenseResolverType.ResolveResult.BLOCK:
			current_player.blocked_hits += 1
			if knockdown_damage > 0.0:
				current_player.knockdown_damage_dealt += knockdown_damage
			stats_changed.emit()
			return
		OffenseResolverType.ResolveResult.EVADE:
			current_player.attacks_evaded += 1
			stats_changed.emit()
			return
		_:
			pass

	if knockdown_damage > 0.0:
		current_player.attacks_landed += 1
		current_player.knockdown_damage_dealt += knockdown_damage
		if _phase_is_open(opponent_attack_state):
			current_player.counter_hits_landed += 1
	stats_changed.emit()


func _on_opponent_attack_resolved(
	result: int,
	knockdown_damage: float,
	_player_meter: float,
	_was_knockdown: bool
) -> void:
	if not recording:
		return

	match result:
		DefenseResolverType.DefenseResult.HIT:
			if knockdown_damage > 0.0:
				current_opponent.attacks_landed += 1
				current_opponent.knockdown_damage_dealt += knockdown_damage
				if _phase_is_open(player_attack_state):
					current_opponent.counter_hits_landed += 1
		DefenseResolverType.DefenseResult.BLOCK:
			current_opponent.blocked_hits += 1
			if knockdown_damage > 0.0:
				current_opponent.knockdown_damage_dealt += knockdown_damage
		DefenseResolverType.DefenseResult.EVADE:
			current_opponent.attacks_evaded += 1

	stats_changed.emit()


func _phase_is_open(attack_state: Node) -> bool:
	if attack_state == null:
		return false
	var state := int(attack_state.current_state)
	return state == 1 or state == 2


func _on_knockdown_state_changed(state: int) -> void:
	if not recording:
		return

	if state == KnockdownManagerType.MatchState.PLAYER_DOWN or state == KnockdownManagerType.MatchState.DOUBLE_DOWN:
		current_opponent.knockdowns += 1
		stats_changed.emit()
	elif state == KnockdownManagerType.MatchState.OPPONENT_DOWN:
		current_player.knockdowns += 1
		stats_changed.emit()
	if state == KnockdownManagerType.MatchState.DOUBLE_DOWN:
		current_player.knockdowns += 1
		stats_changed.emit()
