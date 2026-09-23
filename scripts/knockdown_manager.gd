class_name KnockdownManager
extends Node

signal match_state_changed(state: MatchState)
signal count_changed(count: int, downed_side: DownedSide)
signal recovery_decided(
	downed_side: DownedSide,
	success: bool,
	stand_up_count: int,
	stamina: float,
	chance: float,
	roll: float
)
signal recovered(downed_side: DownedSide, at_count: int)
signal match_finished(winner: Winner)
signal hud_text_changed(text: String)


enum MatchState {
	FIGHTING,
	PLAYER_DOWN,
	OPPONENT_DOWN,
	FINAL_KO,
}

enum DownedSide {
	NONE,
	PLAYER,
	OPPONENT,
}

enum Winner {
	NONE,
	PLAYER,
	OPPONENT,
}

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const ActionStateType = preload("res://scripts/player_action_state.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")
const OpponentActionStateType = preload("res://scripts/opponent_action_state.gd")
const PlayerStaminaType = preload("res://scripts/player_stamina.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")
const RecoverySettingsType = preload("res://scripts/recovery_chance_settings.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")

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
@export var player_recovery_settings: RecoverySettingsType
@export var opponent_recovery_settings: RecoverySettingsType
@export var player_hit_stun: Node
@export var opponent_hit_stun: Node

@export_group("Count")
@export_range(0.05, 5.0, 0.05, "or_greater") var count_interval := 1.0

@export_group("Knockdown Meter")
## Fixed KD Meter value after a successful recovery.
@export_range(0.0, 100.0, 1.0) var recovery_knockdown_meter := 50.0

@export_group("Debug")
@export var enable_debug_force_knockdown := true
@export var print_events := true

var match_state := MatchState.FIGHTING
var current_count := 0
var downed_side := DownedSide.NONE
var player_knockdown_count := 0
var opponent_knockdown_count := 0
var winner := Winner.NONE

## Set once when knockdown begins. Count only advances the timer.
var will_recover := false
var stand_up_count := -1

var _count_time_remaining := 0.0
## When false, RoundManager (break / round end / finished) owns combat freeze.
var _combat_control_enabled := true


func _ready() -> void:
	if player_recovery_settings == null:
		player_recovery_settings = RecoverySettingsType.new()
	if opponent_recovery_settings == null:
		opponent_recovery_settings = RecoverySettingsType.new()
	set_process(false)
	hud_text_changed.emit("FIGHTING")


func _process(delta: float) -> void:
	if match_state not in [MatchState.PLAYER_DOWN, MatchState.OPPONENT_DOWN]:
		return

	_count_time_remaining -= delta
	if _count_time_remaining > 0.0:
		return

	_advance_count()


func _unhandled_input(event: InputEvent) -> void:
	if not enable_debug_force_knockdown:
		return
	if event.is_action_pressed(&"debug_force_player_knockdown"):
		force_knockdown(DownedSide.PLAYER)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_force_opponent_knockdown"):
		force_knockdown(DownedSide.OPPONENT)
		get_viewport().set_input_as_handled()


func is_fighting() -> bool:
	return match_state == MatchState.FIGHTING


func can_accept_combat_input() -> bool:
	return match_state == MatchState.FIGHTING


func set_combat_control_enabled(enabled: bool) -> void:
	_combat_control_enabled = enabled


func begin_player_knockdown() -> void:
	_begin_knockdown(DownedSide.PLAYER)


func begin_opponent_knockdown() -> void:
	_begin_knockdown(DownedSide.OPPONENT)


func force_knockdown(side: DownedSide) -> void:
	if match_state != MatchState.FIGHTING:
		return
	if not _combat_control_enabled:
		return
	_begin_knockdown(side)


func _begin_knockdown(side: DownedSide) -> void:
	if match_state != MatchState.FIGHTING:
		return
	if not _combat_control_enabled:
		return
	if side == DownedSide.NONE:
		return

	downed_side = side
	current_count = 0
	will_recover = false
	stand_up_count = -1

	if side == DownedSide.PLAYER:
		player_knockdown_count += 1
		match_state = MatchState.PLAYER_DOWN
	else:
		opponent_knockdown_count += 1
		match_state = MatchState.OPPONENT_DOWN

	_freeze_combat()
	_decide_recovery()
	match_state_changed.emit(match_state)
	hud_text_changed.emit("DOWN")
	_count_time_remaining = count_interval
	set_process(true)


func _decide_recovery() -> void:
	var settings := _active_recovery_settings()
	var stamina := _downed_stamina()
	var result: Dictionary = settings.resolve_recovery(stamina.current_stamina)
	will_recover = bool(result["success"])
	stand_up_count = int(result["stand_up_count"])

	var side_label := "Player" if downed_side == DownedSide.PLAYER else "Opponent"
	var stamina_now: float = float(result["stamina"])
	var chance: float = float(result["chance"])
	var roll: float = float(result["roll"])

	if print_events:
		print("%s Knockdown | Stamina: %.0f (#%d)" % [
			side_label,
			stamina_now,
			player_knockdown_count if downed_side == DownedSide.PLAYER else opponent_knockdown_count,
		])
		if will_recover:
			print(
				"Recovery Roll: SUCCESS (%.0f%% vs %.0f%%) | Stand-up Count: %d"
				% [roll * 100.0, chance * 100.0, stand_up_count]
			)
		else:
			print(
				"Recovery Roll: FAILED (%.0f%% vs %.0f%%) | Final KO if count reaches 10"
				% [roll * 100.0, chance * 100.0]
			)

	recovery_decided.emit(
		downed_side,
		will_recover,
		stand_up_count,
		stamina_now,
		chance,
		roll
	)


func _advance_count() -> void:
	current_count += 1
	count_changed.emit(current_count, downed_side)
	hud_text_changed.emit("COUNT: %d" % current_count)
	if print_events:
		print("Count: %d" % current_count)

	if will_recover and current_count >= stand_up_count:
		_recover(current_count)
		return

	if current_count >= 10:
		_finish_final_ko()
		return

	_count_time_remaining = count_interval


func _recover(at_count: int) -> void:
	var settings := _active_recovery_settings()
	var stamina := _downed_stamina()
	stamina.restore_stamina(settings.recovery_stamina_amount)
	_set_downed_meter(recovery_knockdown_meter)

	var recovered_side := downed_side
	if print_events:
		var label := "Player" if recovered_side == DownedSide.PLAYER else "Opponent"
		print("%s recovered at %d | KD Meter -> %.0f" % [label, at_count, recovery_knockdown_meter])

	recovered.emit(recovered_side, at_count)
	_resume_fighting()
	hud_text_changed.emit("FIGHTING")


func _finish_final_ko() -> void:
	set_process(false)
	match_state = MatchState.FINAL_KO
	if downed_side == DownedSide.PLAYER:
		winner = Winner.OPPONENT
	else:
		winner = Winner.PLAYER

	_freeze_combat()
	player_stamina.set_regeneration_enabled(false)
	opponent_stamina.set_regeneration_enabled(false)

	var downed_label := "Player" if downed_side == DownedSide.PLAYER else "Opponent"
	var winner_label := "Player" if winner == Winner.PLAYER else "Opponent"
	if print_events:
		print("%s KO" % downed_label)
		print("Winner: %s" % winner_label)

	hud_text_changed.emit("KO\nWinner: %s" % winner_label)
	match_state_changed.emit(match_state)
	match_finished.emit(winner)


func _resume_fighting() -> void:
	set_process(false)
	current_count = 0
	downed_side = DownedSide.NONE
	will_recover = false
	stand_up_count = -1
	match_state = MatchState.FIGHTING
	if _combat_control_enabled:
		player_stamina.set_regeneration_enabled(true)
		opponent_stamina.set_regeneration_enabled(true)
		opponent_attack_state.set_combat_enabled(true)
		_set_meter_updates_enabled(true)
	match_state_changed.emit(match_state)


func _freeze_combat() -> void:
	player_attack_state.cancel_attack()
	player_action_state.force_reset_to_idle()
	if opponent_action_state != null:
		opponent_action_state.force_reset_to_idle()
	opponent_attack_state.cancel_and_disable()
	player_stamina.set_regeneration_enabled(false)
	opponent_stamina.set_regeneration_enabled(false)
	_set_meter_updates_enabled(false)
	if player_hit_stun != null:
		player_hit_stun.clear_hit_stun()
	if opponent_hit_stun != null:
		opponent_hit_stun.clear_hit_stun()


func _set_meter_updates_enabled(enabled: bool) -> void:
	if defense_resolver != null:
		defense_resolver.meter_updates_enabled = enabled
	if offense_resolver != null:
		offense_resolver.meter_updates_enabled = enabled


func _set_downed_meter(value: float) -> void:
	var meter := (
		player_knockdown_meter
		if downed_side == DownedSide.PLAYER
		else opponent_knockdown_meter
	)
	if meter != null:
		meter.set_meter(value)


func _active_recovery_settings() -> RecoverySettingsType:
	if downed_side == DownedSide.PLAYER:
		return player_recovery_settings
	return opponent_recovery_settings


func _downed_stamina() -> Node:
	if downed_side == DownedSide.PLAYER:
		return player_stamina
	return opponent_stamina
