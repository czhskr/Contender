class_name RoundManager
extends Node

signal round_started(round_number: int)
signal round_ended(round_number: int)
signal break_started(completed_round: int, break_seconds: float)
signal break_ended(next_round: int)
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
@export_range(0.0, 1000.0, 0.5, "or_greater") var round_stamina_recovery := 25.0
@export_range(0.0, 100.0, 1.0) var round_knockdown_meter_recovery := 15.0

@export_group("Debug")
@export var auto_start := true
@export var print_events := true

var round_state := RoundState.IDLE
var current_round := 0
var time_remaining := 0.0
var break_time_remaining := 0.0
var timer_paused := false


func _ready() -> void:
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_knockdown_state_changed)
		knockdown_manager.recovered.connect(_on_knockdown_recovered)
		knockdown_manager.match_finished.connect(_on_knockdown_match_finished)

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
	timer_paused = false
	_start_round(1)


func _start_round(round_number: int) -> void:
	current_round = round_number
	time_remaining = round_duration
	break_time_remaining = 0.0
	timer_paused = false
	round_state = RoundState.FIGHTING

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
	_emit_hud()

	if current_round >= total_rounds:
		call_deferred("_enter_decision_required")
	else:
		call_deferred("_start_break")


func _start_break() -> void:
	round_state = RoundState.BREAK
	break_time_remaining = break_duration

	var player_restored: float = player_stamina.restore_stamina(round_stamina_recovery)
	var opponent_restored: float = opponent_stamina.restore_stamina(round_stamina_recovery)
	var player_kd_reduced := 0.0
	var opponent_kd_reduced := 0.0
	if player_knockdown_meter != null:
		player_kd_reduced = player_knockdown_meter.reduce_meter(round_knockdown_meter_recovery)
	if opponent_knockdown_meter != null:
		opponent_kd_reduced = opponent_knockdown_meter.reduce_meter(round_knockdown_meter_recovery)

	if print_events:
		print(
			"BREAK %.0fs | Stamina +%.0f (P +%.1f / O +%.1f) | KD -%.0f (P -%.1f / O -%.1f)"
			% [
				break_duration,
				round_stamina_recovery,
				player_restored,
				opponent_restored,
				round_knockdown_meter_recovery,
				player_kd_reduced,
				opponent_kd_reduced,
			]
		)

	round_state_changed.emit(round_state)
	break_started.emit(current_round, break_duration)
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
	]:
		timer_paused = true
		if print_events:
			print("Round timer paused (knockdown)")
		_emit_hud()


func _on_knockdown_recovered(_downed_side: int, _at_count: int) -> void:
	if round_state != RoundState.FIGHTING:
		return
	timer_paused = false
	if print_events:
		print("Round timer resumed (recovery)")
	_emit_hud()


func _on_knockdown_match_finished(winner: int) -> void:
	if round_state == RoundState.MATCH_FINISHED:
		return

	timer_paused = false
	time_remaining = 0.0
	break_time_remaining = 0.0
	round_state = RoundState.MATCH_FINISHED
	knockdown_manager.set_combat_control_enabled(false)
	_freeze_combat()

	if print_events:
		var winner_label := "Player" if winner == KnockdownManagerType.Winner.PLAYER else "Opponent"
		print("Match finished by KO | Winner: %s | Round system stopped" % winner_label)

	round_state_changed.emit(round_state)
	match_stopped_by_ko.emit(winner)
	_emit_hud()


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
