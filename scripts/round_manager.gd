class_name RoundManager
extends Node

signal round_started(round_number: int)
signal round_ended(round_number: int)
signal break_started(completed_round: int, break_seconds: float)
signal break_ended(next_round: int)
signal trait_preview_started(round_number: int)
signal series_finished(winner: int)
signal decision_required
signal match_stopped_by_ko(winner: int)
signal time_changed(seconds_remaining: float)
signal round_state_changed(state: RoundState)
signal hud_text_changed(text: String)

enum RoundState {
	IDLE,
	FIGHTING,
	ROUND_END,
	BREAK,
	DECISION_REQUIRED,
	MATCH_FINISHED,
	TRAIT_PREVIEW,
}

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const ActionStateType = preload("res://scripts/player_action_state.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")
const OpponentActionStateType = preload("res://scripts/opponent_action_state.gd")
const PlayerStaminaType = preload("res://scripts/player_stamina.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")

@export var knockdown_manager: KnockdownManagerType
@export var player_attack_state: AttackStateType
@export var player_action_state: ActionStateType
@export var opponent_attack_state: OpponentAttackStateType
@export var opponent_action_state: OpponentActionStateType
@export var player_stamina: PlayerStaminaType
@export var opponent_stamina: OpponentStaminaType
@export var player_knockdown_meter: KnockdownMeterType
@export var opponent_knockdown_meter: KnockdownMeterType
@export var defense_resolver: DefenseResolverType
@export var offense_resolver: OffenseResolverType
@export var player_hit_stun: Node
@export var opponent_hit_stun: Node
@export var player_evade: Node
@export var combat_input: Node
@export var combat_visual_root: Node2D

@export_group("Round Settings")
@export_range(1, 15, 1, "or_greater") var total_rounds := 3
@export_range(1.0, 600.0, 0.5, "or_greater") var round_duration := 60.0
@export_range(0.0, 120.0, 0.5, "or_greater") var break_duration := 10.0
@export_range(0.0, 1000.0, 0.5, "or_greater") var round_stamina_recovery := 0.0
@export_range(0.0, 100.0, 1.0) var round_knockdown_meter_recovery := 0.0
@export var wins_to_finish := 2

var player_round_wins := 0
var opponent_round_wins := 0
var _round_awarded := false
var _preview_round := 1

@export_group("Debug")
@export var auto_start := true
@export var print_events := true

var round_state := RoundState.IDLE
var current_round := 0
var time_remaining := 0.0
var break_time_remaining := 0.0
var timer_paused := false


func _ready() -> void:
	if player_evade == null:
		player_evade = get_node_or_null("../PlayerEvade")
	if combat_input == null:
		combat_input = get_node_or_null("../PlayerCombatInput")
	if combat_visual_root == null:
		combat_visual_root = get_node_or_null("../CombatVisualRoot")
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_knockdown_state_changed)
		knockdown_manager.recovered.connect(_on_knockdown_recovered)
		knockdown_manager.match_finished.connect(_on_knockdown_match_finished)
		if knockdown_manager.has_signal("round_voided"):
			knockdown_manager.round_voided.connect(_on_round_voided)

	_freeze_combat()
	knockdown_manager.set_combat_control_enabled(false)
	_emit_hud()

	if auto_start:
		call_deferred("start_match")


func _process(delta: float) -> void:
	match round_state:
		RoundState.FIGHTING:
			if timer_paused:
				return
			time_remaining = maxf(time_remaining - delta, 0.0)
			time_changed.emit(time_remaining)
			_emit_hud()
			if time_remaining <= 0.0:
				_end_round()
		RoundState.BREAK:
			break_time_remaining = maxf(break_time_remaining - delta, 0.0)
			_emit_hud()
			if break_time_remaining <= 0.0:
				_finish_break()
		_:
			pass


func can_accept_combat_input() -> bool:
	return round_state == RoundState.FIGHTING and not timer_paused


## Presentation freeze before KnockdownManager starts Count (finisher slow-mo).
func pause_for_finisher() -> void:
	if round_state != RoundState.FIGHTING:
		return
	timer_paused = true
	if print_events:
		print("Round timer paused (finisher)")
	_emit_hud()


func is_match_active() -> bool:
	return round_state in [
		RoundState.FIGHTING,
		RoundState.ROUND_END,
		RoundState.BREAK,
	]


func start_match() -> void:
	if round_state not in [RoundState.IDLE, RoundState.DECISION_REQUIRED]:
		return
	current_round = 0
	player_round_wins = 0
	opponent_round_wins = 0
	timer_paused = true
	_open_trait_preview(1)
	if DisplayServer.get_name() == "headless":
		call_deferred("confirm_round_start")


func _start_round(round_number: int) -> void:
	current_round = round_number
	time_remaining = round_duration
	break_time_remaining = 0.0
	timer_paused = false
	round_state = RoundState.FIGHTING
	_round_awarded = false

	_resume_combat()
	knockdown_manager.set_combat_control_enabled(true)

	if print_events:
		print("ROUND %d / %d START" % [current_round, total_rounds])

	round_state_changed.emit(round_state)
	round_started.emit(current_round)
	time_changed.emit(time_remaining)
	_emit_hud()


func _end_round() -> void:
	if round_state != RoundState.FIGHTING:
		return

	time_remaining = 0.0
	timer_paused = false
	round_state = RoundState.ROUND_END

	knockdown_manager.set_combat_control_enabled(false)
	_freeze_combat()

	if print_events:
		print("ROUND %d END" % current_round)

	round_state_changed.emit(round_state)
	round_ended.emit(current_round)
	_award_decision_round()
	_emit_hud()

	if _someone_clinched() or current_round >= total_rounds:
		call_deferred("_finish_series_from_rounds", false)
	else:
		call_deferred("_open_trait_preview", current_round + 1)


func _start_break() -> void:
	round_state = RoundState.BREAK
	break_time_remaining = 0.0
	if print_events:
		print("BREAK | score %d-%d" % [player_round_wins, opponent_round_wins])
	round_state_changed.emit(round_state)
	break_started.emit(current_round, break_time_remaining)
	_emit_hud()


func _finish_break() -> void:
	if round_state != RoundState.BREAK:
		return

	var next_round := current_round + 1
	if print_events:
		print("BREAK END → ROUND %d" % next_round)

	break_ended.emit(next_round)
	_start_round(next_round)


func _enter_decision_required() -> void:
	round_state = RoundState.DECISION_REQUIRED
	knockdown_manager.set_combat_control_enabled(false)
	_freeze_combat()

	if print_events:
		print("DECISION REQUIRED (no KO after Round %d)" % current_round)

	round_state_changed.emit(round_state)
	decision_required.emit()
	_emit_hud()


func _on_knockdown_state_changed(state: int) -> void:
	if round_state != RoundState.FIGHTING:
		return

	if state in [
		KnockdownManagerType.MatchState.PLAYER_DOWN,
		KnockdownManagerType.MatchState.OPPONENT_DOWN,
		KnockdownManagerType.MatchState.DOUBLE_DOWN,
	]:
		timer_paused = true
		if print_events:
			print("Round timer paused (knockdown)")
		_emit_hud()


func _on_knockdown_recovered(_downed_side: int, _at_count: int) -> void:
	if round_state != RoundState.FIGHTING:
		return
	if knockdown_manager != null and knockdown_manager.match_state != KnockdownManagerType.MatchState.FIGHTING:
		return
	timer_paused = false
	if print_events:
		print("Round timer resumed (recovery)")
	_emit_hud()


func _on_round_voided() -> void:
	if round_state == RoundState.MATCH_FINISHED:
		return
	var score_player := player_round_wins
	var score_opponent := opponent_round_wins
	print("ROUND %d VOID" % current_round)
	print("Score remains %d-%d" % [score_player, score_opponent])
	print("ROUND %d REMATCH" % current_round)
	_open_trait_preview(current_round)


func _on_knockdown_match_finished(winner: int) -> void:
	if round_state == RoundState.MATCH_FINISHED or _round_awarded:
		return
	var round_winner := 2 if winner == KnockdownManagerType.Winner.OPPONENT else 1
	_award_round(round_winner)
	if _someone_clinched():
		_finish_series_from_rounds(true)
	else:
		_open_trait_preview(current_round + 1)


func _award_decision_round() -> void:
	var stats = _combat_stats()
	var scorer = _round_scorer()
	if stats == null or scorer == null or not stats.round_stats.has(current_round):
		_award_round(1)
		return
	var snap = stats.round_stats[current_round]
	_award_round(scorer.decide_round_winner(snap.player, snap.opponent, current_round))


func _award_round(round_winner: int) -> void:
	if _round_awarded:
		return
	_round_awarded = true
	if round_winner == 1:
		player_round_wins += 1
	else:
		opponent_round_wins += 1
	if print_events:
		print("ROUND %d WIN | Score %d-%d" % [current_round, player_round_wins, opponent_round_wins])


func _someone_clinched() -> bool:
	return player_round_wins >= wins_to_finish or opponent_round_wins >= wins_to_finish


func _finish_series_from_rounds(by_ko: bool) -> void:
	if round_state == RoundState.MATCH_FINISHED:
		return
	round_state = RoundState.MATCH_FINISHED
	timer_paused = true
	var winner := KnockdownManagerType.Winner.PLAYER
	if opponent_round_wins > player_round_wins:
		winner = KnockdownManagerType.Winner.OPPONENT
	round_state_changed.emit(round_state)
	series_finished.emit(1 if winner == KnockdownManagerType.Winner.PLAYER else 2)
	if by_ko:
		match_stopped_by_ko.emit(winner)
	else:
		decision_required.emit()
	_emit_hud()


func confirm_round_start() -> void:
	if round_state != RoundState.TRAIT_PREVIEW:
		return
	_reset_fighters_for_round()
	if knockdown_manager != null and knockdown_manager.has_method("reset_for_next_round"):
		knockdown_manager.reset_for_next_round()
	if combat_visual_root != null and combat_visual_root.has_method("reset_for_new_round"):
		combat_visual_root.reset_for_new_round()
	_start_round(_preview_round)


func _open_trait_preview(round_number: int) -> void:
	_preview_round = round_number
	_round_awarded = false
	round_state = RoundState.TRAIT_PREVIEW
	timer_paused = true
	var traits = _trait_manager()
	if traits != null:
		traits.reroll_round()
	_freeze_combat()
	if knockdown_manager != null:
		knockdown_manager.set_combat_control_enabled(false)
	round_state_changed.emit(round_state)
	trait_preview_started.emit(round_number)
	_emit_hud()
	_show_trait_card(round_number)


func _reset_fighters_for_round() -> void:
	if player_stamina != null and player_stamina.has_method("reset_to_max"):
		player_stamina.reset_to_max()
	if opponent_stamina != null and opponent_stamina.has_method("reset_to_max"):
		opponent_stamina.reset_to_max()
	if player_knockdown_meter != null:
		player_knockdown_meter.set_meter(0.0)
	if opponent_knockdown_meter != null:
		opponent_knockdown_meter.set_meter(0.0)
	_clear_continuous_evade()
	if player_hit_stun != null:
		player_hit_stun.clear_hit_stun()
	if opponent_hit_stun != null:
		opponent_hit_stun.clear_hit_stun()
	var ai = get_node_or_null("../OpponentAI")
	if ai != null and ai.has_method("clear_pending_combat_decisions"):
		ai.clear_pending_combat_decisions()
		if ai.has_method("clear_follow_up"):
			ai.clear_follow_up()


func _show_trait_card(round_number: int) -> void:
	var card = get_node_or_null("../TraitRoundCard")
	if card == null:
		card = preload("res://scripts/trait_round_card.gd").new()
		card.name = "TraitRoundCard"
		get_parent().add_child(card)
		if not card.fight_pressed.is_connected(confirm_round_start):
			card.fight_pressed.connect(confirm_round_start)
	var traits = _trait_manager()
	var player_traits: Array = traits.player_traits if traits != null else []
	var opponent_traits: Array = traits.opponent_traits if traits != null else []
	card.show_round(round_number, player_traits, opponent_traits, player_round_wins, opponent_round_wins)
	_print_round_traits(player_traits, opponent_traits)


func _trait_manager():
	var node = get_node_or_null("../TraitManager")
	if node == null and get_parent() != null:
		node = preload("res://scripts/trait_manager.gd").new()
		node.name = "TraitManager"
		get_parent().add_child(node)
	return node


func _print_round_traits(player_traits: Array, opponent_traits: Array) -> void:
	print("[TRAITS]")
	print("Player:")
	_print_trait_list(player_traits)
	print("Opponent:")
	_print_trait_list(opponent_traits)


func _print_trait_list(traits: Array) -> void:
	if traits.is_empty():
		print("- none")
		return
	for entry in traits:
		print("- %s" % entry.display_name)
		print("  dealt_kd ×%.2f straight ×%.2f hook ×%.2f" % [entry.outgoing_kd, entry.straight_outgoing_kd, entry.hook_outgoing_kd])
		print("  taken_kd ×%.2f block_taken ×%.2f attack_cost ×%.2f" % [entry.incoming_kd, entry.block_incoming_kd, entry.attack_cost])
		if entry.iron_guard:
			print("  block_kd = 0 (Iron Guard)")
		if entry.last_stand:
			print("  last_stand ×2 at stamina <= 25")


func _combat_stats():
	return get_node_or_null("../CombatStats")


func _round_scorer():
	return get_node_or_null("../RoundScorer")


func _freeze_combat() -> void:
	if player_attack_state != null:
		player_attack_state.cancel_attack()
	if player_action_state != null:
		player_action_state.force_reset_to_idle()
	if opponent_action_state != null:
		opponent_action_state.force_reset_to_idle()
	if opponent_attack_state != null:
		opponent_attack_state.cancel_and_disable()
	if player_stamina != null:
		player_stamina.set_regeneration_enabled(false)
	if opponent_stamina != null:
		opponent_stamina.set_regeneration_enabled(false)
	if player_hit_stun != null:
		player_hit_stun.clear_hit_stun()
	if opponent_hit_stun != null:
		opponent_hit_stun.clear_hit_stun()
	_set_meter_updates_enabled(false)
	_clear_continuous_evade()


## Round End / Break / decision / match freeze. No stamina spend.
func _clear_continuous_evade() -> void:
	if combat_input != null and combat_input.has_method("clear_held_evade"):
		combat_input.clear_held_evade()
	if player_evade != null and player_evade.has_method("clear_all"):
		player_evade.clear_all()
	if combat_visual_root != null and combat_visual_root.has_method("clear_continuous_evade_presentation"):
		combat_visual_root.clear_continuous_evade_presentation()


func _resume_combat() -> void:
	if player_stamina != null:
		player_stamina.set_regeneration_enabled(true)
	if opponent_stamina != null:
		opponent_stamina.set_regeneration_enabled(true)
	if opponent_attack_state != null:
		opponent_attack_state.set_combat_enabled(true)
	_set_meter_updates_enabled(true)


func _set_meter_updates_enabled(enabled: bool) -> void:
	if defense_resolver != null:
		defense_resolver.meter_updates_enabled = enabled
	if offense_resolver != null:
		offense_resolver.meter_updates_enabled = enabled


func _emit_hud() -> void:
	var text := ""
	match round_state:
		RoundState.IDLE:
			text = "ROUND -- / %d" % total_rounds
		RoundState.FIGHTING:
			var pause_mark := " [DOWN]" if timer_paused else ""
			text = "ROUND %d / %d\n%s%s" % [
				current_round,
				total_rounds,
				_format_clock(time_remaining),
				pause_mark,
			]
		RoundState.ROUND_END:
			text = "ROUND %d / %d\nROUND END" % [current_round, total_rounds]
		RoundState.BREAK:
			text = "ROUND %d / %d\nBREAK %.0f" % [
				current_round,
				total_rounds,
				ceilf(break_time_remaining),
			]
		RoundState.DECISION_REQUIRED:
			text = "ROUND %d / %d\nDECISION" % [current_round, total_rounds]
		RoundState.MATCH_FINISHED:
			text = "ROUND %d / %d\nMATCH OVER" % [current_round, total_rounds]
	hud_text_changed.emit(text)


func _format_clock(seconds: float) -> String:
	var total := maxi(ceili(seconds), 0)
	var mins := int(floor(float(total) / 60.0))
	var secs := total - mins * 60
	return "%02d:%02d" % [mins, secs]
