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
signal round_voided
signal knockdown_confirmed
signal fighter_stood(downed_side: DownedSide, at_count: int)
signal hud_text_changed(text: String)


enum MatchState {
	FIGHTING,
	PLAYER_DOWN,
	OPPONENT_DOWN,
	FINAL_KO,
	TRADE_RESOLUTION,
	DOUBLE_DOWN,
	RESUME_DELAY,
}

enum DownedSide {
	NONE,
	PLAYER,
	OPPONENT,
	BOTH,
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
## Stand-up pause before both fighters may act again. Not a count tick.
@export_range(0.0, 5.0, 0.05, "or_greater") var resume_delay_seconds := 2.0

@export_group("Knockdown Meter")
## Successful stand-up restores this fraction of the meter's maximum.
@export_range(0.0, 1.0, 0.05) var recovery_meter_ratio := 0.5

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
var _resume_time_remaining := 0.0
var _begin_requested := false
var _waiting_for_begin := false
## When false, RoundManager (break / round end / finished) owns combat freeze.
var _combat_control_enabled := true
var _candidate_live := false
var _candidate_is_player := false
var _candidate_token := -1
var _pending_kind := 0
var _pending_side := DownedSide.NONE
var _waiting_for_finisher := false
var _player_will_recover := false
var _opponent_will_recover := false
var _player_stand_count := -1
var _opponent_stand_count := -1
var _player_stood := false
var _opponent_stood := false
var _scripted_player_recovery: Dictionary = {}
var _scripted_opponent_recovery: Dictionary = {}
var _finisher: Node = null


func _ready() -> void:
	if player_recovery_settings == null:
		player_recovery_settings = RecoverySettingsType.new()
	if opponent_recovery_settings == null:
		opponent_recovery_settings = RecoverySettingsType.new()
	_finisher = get_node_or_null("../FinisherImpactFreeze")
	if _finisher != null and _finisher.has_signal("finisher_finished"):
		if not _finisher.finisher_finished.is_connected(_on_finisher_finished):
			_finisher.finisher_finished.connect(_on_finisher_finished)
	set_process(false)
	hud_text_changed.emit("FIGHTING")


func _process(delta: float) -> void:
	if match_state == MatchState.RESUME_DELAY:
		_discard_resume_inputs()
		if _waiting_for_begin:
			return
		_resume_time_remaining = maxf(_resume_time_remaining - delta, 0.0)
		if not _begin_requested and _resume_time_remaining <= _begin_presentation_length():
			_begin_requested = true
			if _play_begin():
				_waiting_for_begin = true
				return
		if _resume_time_remaining > 0.0:
			return
		_discard_resume_inputs()
		_resume_fighting()
		hud_text_changed.emit("FIGHTING")
		return
	if match_state not in [MatchState.PLAYER_DOWN, MatchState.OPPONENT_DOWN, MatchState.DOUBLE_DOWN]:
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


func new_actions_locked() -> bool:
	return match_state != MatchState.FIGHTING


func allows_attack_resolution(is_player_attack: bool, token: int) -> bool:
	if match_state == MatchState.FIGHTING:
		return true
	if match_state == MatchState.TRADE_RESOLUTION and _candidate_live:
		return is_player_attack == _candidate_is_player and token == _candidate_token
	return false


func queue_recovery_result(side: DownedSide, success: bool, stand_up_count: int) -> void:
	var payload := {
		"success": success,
		"stand_up_count": stand_up_count if success else -1,
		"chance": 1.0,
		"roll": 0.0,
		"stamina": 0.0,
	}
	if side == DownedSide.PLAYER:
		_scripted_player_recovery = payload
	elif side == DownedSide.OPPONENT:
		_scripted_opponent_recovery = payload


func notify_threshold(side: DownedSide) -> void:
	if not _combat_control_enabled:
		return
	if side == DownedSide.NONE or side == DownedSide.BOTH:
		return
	if match_state == MatchState.TRADE_RESOLUTION:
		return
	if match_state != MatchState.FIGHTING:
		return
	_open_trade(side)


func notify_attack_resolved(is_player_attack: bool, token: int) -> void:
	if match_state != MatchState.TRADE_RESOLUTION or not _candidate_live:
		return
	if is_player_attack != _candidate_is_player or token != _candidate_token:
		return
	_commit_trade(true)


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
	if side == DownedSide.PLAYER and player_knockdown_meter != null:
		player_knockdown_meter.set_meter(0.0)
	elif side == DownedSide.OPPONENT and opponent_knockdown_meter != null:
		opponent_knockdown_meter.set_meter(0.0)
	_begin_knockdown(side)


func _open_trade(first_side: DownedSide) -> void:
	match_state = MatchState.TRADE_RESOLUTION
	_candidate_live = false
	_candidate_token = -1
	var candidate_is_player := first_side == DownedSide.PLAYER
	var attack_state: Node = player_attack_state if candidate_is_player else opponent_attack_state
	var resolver: Node = offense_resolver if candidate_is_player else defense_resolver
	var active := false
	var token := -1
	if attack_state != null:
		token = int(attack_state.get_action_token())
		active = int(attack_state.get("current_state")) == AttackStateType.AttackState.ACTIVE
	var unresolved := true
	if resolver != null and resolver.has_method("has_resolved_token"):
		unresolved = not resolver.has_resolved_token(token)
	var label := "Player" if first_side == DownedSide.PLAYER else "Opponent"
	if active and unresolved and token >= 0:
		_candidate_live = true
		_candidate_is_player = candidate_is_player
		_candidate_token = token
		var owner := "Player" if candidate_is_player else "Opponent"
		if print_events:
			print("[TRADE]")
			print("first_threshold=%s" % label)
			print("candidate=%sAttackToken#%d" % [owner, token])
			print("phase=ACTIVE")
		_cancel_non_candidate_attacks()
		return
	if print_events:
		print("[TRADE]")
		print("first_threshold=%s" % label)
		print("candidate=NONE")
	_cancel_non_candidate_attacks()
	_commit_trade(false)


func _cancel_non_candidate_attacks() -> void:
	if player_attack_state != null:
		if not (_candidate_live and _candidate_is_player):
			if player_attack_state.current_state != AttackStateType.AttackState.IDLE:
				player_attack_state.cancel_attack()
	if opponent_attack_state != null:
		if not (_candidate_live and not _candidate_is_player):
			if int(opponent_attack_state.current_state) != AttackStateType.AttackState.IDLE:
				opponent_attack_state.cancel_attack()


func _commit_trade(from_candidate: bool) -> void:
	if match_state != MatchState.TRADE_RESOLUTION:
		return
	_candidate_live = false
	var player_down := player_knockdown_meter != null and player_knockdown_meter.is_knockdown_threshold()
	var opponent_down := opponent_knockdown_meter != null and opponent_knockdown_meter.is_knockdown_threshold()
	var player_now := 0.0 if player_knockdown_meter == null else player_knockdown_meter.current_meter
	var opponent_now := 0.0 if opponent_knockdown_meter == null else opponent_knockdown_meter.current_meter
	if player_down and opponent_down:
		_pending_kind = 2
		_pending_side = DownedSide.BOTH
		if print_events:
			if from_candidate:
				print("[TRADE]")
				print("candidate_resolved")
				print("player_kd=%.0f" % player_now)
				print("opponent_kd=%.0f" % opponent_now)
			print("result=DOUBLE_KNOCKDOWN")
	elif player_down:
		_pending_kind = 1
		_pending_side = DownedSide.PLAYER
		if print_events:
			print("result=SINGLE_KNOCKDOWN")
	elif opponent_down:
		_pending_kind = 1
		_pending_side = DownedSide.OPPONENT
		if print_events:
			print("result=SINGLE_KNOCKDOWN")
	else:
		match_state = MatchState.FIGHTING
		return
	knockdown_confirmed.emit()
	_present_pending()


func _present_pending() -> void:
	_set_meter_updates_enabled(false)
	var finisher := _finisher
	if finisher != null and finisher.has_method("try_begin_finisher") and not _waiting_for_finisher:
		var side := int(_pending_side if _pending_kind == 1 else DownedSide.PLAYER)
		if bool(finisher.get("is_pending")):
			_waiting_for_finisher = true
			return
		if finisher.try_begin_finisher(side):
			_waiting_for_finisher = true
			return
	_apply_pending_knockdown()


func _on_finisher_finished(_side: int) -> void:
	if not _waiting_for_finisher:
		return
	_waiting_for_finisher = false
	_apply_pending_knockdown()


func _apply_pending_knockdown() -> void:
	var kind := _pending_kind
	var side := _pending_side
	_pending_kind = 0
	_pending_side = DownedSide.NONE
	if kind == 2:
		_begin_double_knockdown()
	elif kind == 1:
		_begin_knockdown(side)


func _begin_knockdown(side: DownedSide) -> void:
	if match_state not in [MatchState.FIGHTING, MatchState.TRADE_RESOLUTION]:
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


func _begin_double_knockdown() -> void:
	if match_state not in [MatchState.FIGHTING, MatchState.TRADE_RESOLUTION]:
		return
	if not _combat_control_enabled:
		return
	downed_side = DownedSide.BOTH
	current_count = 0
	will_recover = false
	stand_up_count = -1
	_player_stood = false
	_opponent_stood = false
	player_knockdown_count += 1
	opponent_knockdown_count += 1
	var player_result := _take_recovery(DownedSide.PLAYER, player_stamina.current_stamina)
	var opponent_result := _take_recovery(DownedSide.OPPONENT, opponent_stamina.current_stamina)
	_player_will_recover = bool(player_result["success"])
	_opponent_will_recover = bool(opponent_result["success"])
	_player_stand_count = int(player_result["stand_up_count"])
	_opponent_stand_count = int(opponent_result["stand_up_count"])
	_log_recovery(DownedSide.PLAYER, player_result)
	_log_recovery(DownedSide.OPPONENT, opponent_result)
	match_state = MatchState.DOUBLE_DOWN
	_freeze_combat()
	if print_events:
		print("[DOUBLE_KD]")
		print("Player recovery=%s stand_count=%d" % [
			"SUCCESS" if _player_will_recover else "FAIL",
			_player_stand_count,
		])
		print("Opponent recovery=%s stand_count=%d" % [
			"SUCCESS" if _opponent_will_recover else "FAIL",
			_opponent_stand_count,
		])
	match_state_changed.emit(match_state)
	hud_text_changed.emit("DOUBLE DOWN")
	_count_time_remaining = count_interval
	set_process(true)


func _take_recovery(side: DownedSide, stamina_now: float) -> Dictionary:
	var scripted: Dictionary = _scripted_player_recovery if side == DownedSide.PLAYER else _scripted_opponent_recovery
	if not scripted.is_empty():
		var copy := scripted.duplicate()
		copy["stamina"] = stamina_now
		if side == DownedSide.PLAYER:
			_scripted_player_recovery = {}
		else:
			_scripted_opponent_recovery = {}
		return copy
	var settings := player_recovery_settings if side == DownedSide.PLAYER else opponent_recovery_settings
	return settings.resolve_recovery(stamina_now)


func _decide_recovery() -> void:
	var stamina := _downed_stamina()
	var result := _take_recovery(downed_side, stamina.current_stamina)
	will_recover = bool(result["success"])
	stand_up_count = int(result["stand_up_count"])
	_log_recovery(downed_side, result)

	recovery_decided.emit(
		downed_side,
		will_recover,
		stand_up_count,
		float(result["stamina"]),
		float(result["chance"]) if result.has("chance") else 0.0,
		float(result["roll"]) if result.has("roll") else 0.0
	)


func _log_recovery(side: DownedSide, result: Dictionary) -> void:
	if not print_events or not result.has("chance"):
		return
	var settings: RecoverySettingsType = player_recovery_settings if side == DownedSide.PLAYER else opponent_recovery_settings
	var stamina_now := float(result["stamina"])
	var ratio := stamina_now / maxf(settings.reference_stamina, 0.001)
	var curved: float = settings._stamina_curve(stamina_now, settings.recovery_chance_exponent)
	var base_chance := lerpf(settings.min_recovery_chance, settings.max_recovery_chance, curved)
	var final_chance := float(result["chance"])
	var bonus := final_chance - base_chance
	var roll := float(result["roll"])
	var success := bool(result["success"])
	print("[RECOVERY] fighter=%s kd=%d stamina=%.1f ratio=%.3f base_chance=%.3f bonus=%.3f final_chance=%.3f roll=%.3f comparison=roll<final_chance result=%s stand_count=%s" % [
		"PLAYER" if side == DownedSide.PLAYER else "OPPONENT",
		player_knockdown_count if side == DownedSide.PLAYER else opponent_knockdown_count,
		stamina_now,
		ratio,
		base_chance,
		bonus,
		final_chance,
		roll,
		"SUCCESS" if success else "FAIL",
		str(int(result["stand_up_count"])) if success else "-",
	])


func _advance_count() -> void:
	current_count += 1
	count_changed.emit(current_count, downed_side)
	hud_text_changed.emit("COUNT: %d" % current_count)
	if print_events:
		print("Count: %d" % current_count)

	if match_state == MatchState.DOUBLE_DOWN:
		_advance_double_count()
		return

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
	var restored_meter := _recovery_meter_value()
	_set_downed_meter(restored_meter)

	var recovered_side := downed_side
	if print_events:
		var label := "Player" if recovered_side == DownedSide.PLAYER else "Opponent"
		print("%s recovered at %d | KD Meter -> %.0f" % [label, at_count, restored_meter])

	_begin_resume_delay()
	recovered.emit(recovered_side, at_count)


func _advance_double_count() -> void:
	if _player_will_recover and not _player_stood and current_count >= _player_stand_count:
		_stand_one(DownedSide.PLAYER, current_count)
	if _opponent_will_recover and not _opponent_stood and current_count >= _opponent_stand_count:
		_stand_one(DownedSide.OPPONENT, current_count)
	if _player_stood and _opponent_stood:
		if print_events:
			print("Both recovered")
		var stood_count := current_count
		_begin_resume_delay()
		recovered.emit(DownedSide.BOTH, stood_count)
		return
	if current_count >= 10:
		_finish_double_at_ten()
		return
	_count_time_remaining = count_interval


func _stand_one(side: DownedSide, at_count: int) -> void:
	var settings := player_recovery_settings if side == DownedSide.PLAYER else opponent_recovery_settings
	var stamina: Node = player_stamina if side == DownedSide.PLAYER else opponent_stamina
	var meter := player_knockdown_meter if side == DownedSide.PLAYER else opponent_knockdown_meter
	stamina.restore_stamina(settings.recovery_stamina_amount)
	if meter != null:
		meter.set_meter(meter.max_meter * recovery_meter_ratio)
	if side == DownedSide.PLAYER:
		_player_stood = true
	else:
		_opponent_stood = true
	var label := "Player" if side == DownedSide.PLAYER else "Opponent"
	var waiting := not (_player_stood and _opponent_stood)
	if print_events:
		if waiting:
			print("%s recovered - WAITING" % label)
		else:
			print("%s recovered" % label)
	fighter_stood.emit(side, at_count)


func _finish_double_at_ten() -> void:
	set_process(false)
	if _player_stood and not _opponent_stood:
		downed_side = DownedSide.OPPONENT
		winner = Winner.PLAYER
		match_state = MatchState.FINAL_KO
		_freeze_combat()
		if print_events:
			print("Opponent KO")
			print("Winner: Player")
		hud_text_changed.emit("KO\nWinner: Player")
		match_state_changed.emit(match_state)
		match_finished.emit(winner)
		return
	if _opponent_stood and not _player_stood:
		downed_side = DownedSide.PLAYER
		winner = Winner.OPPONENT
		match_state = MatchState.FINAL_KO
		_freeze_combat()
		if print_events:
			print("Player KO")
			print("Winner: Opponent")
		hud_text_changed.emit("KO\nWinner: Opponent")
		match_state_changed.emit(match_state)
		match_finished.emit(winner)
		return
	downed_side = DownedSide.BOTH
	winner = Winner.NONE
	match_state = MatchState.FINAL_KO
	_freeze_combat()
	if print_events:
		print("DOUBLE KO")
	hud_text_changed.emit("DOUBLE KO")
	match_state_changed.emit(match_state)
	round_voided.emit()


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


func reset_for_next_round() -> void:
	set_process(false)
	current_count = 0
	downed_side = DownedSide.NONE
	will_recover = false
	stand_up_count = -1
	winner = Winner.NONE
	_candidate_live = false
	_candidate_token = -1
	_pending_kind = 0
	_pending_side = DownedSide.NONE
	_waiting_for_finisher = false
	_player_stood = false
	_opponent_stood = false
	_player_will_recover = false
	_opponent_will_recover = false
	_resume_time_remaining = 0.0
	_begin_requested = false
	_waiting_for_begin = false
	match_state = MatchState.FIGHTING
	_combat_control_enabled = true
	if player_stamina != null:
		player_stamina.set_regeneration_enabled(true)
	if opponent_stamina != null:
		opponent_stamina.set_regeneration_enabled(true)
	_set_meter_updates_enabled(true)
	if opponent_attack_state != null:
		opponent_attack_state.set_combat_enabled(true)
	hud_text_changed.emit("FIGHTING")
	match_state_changed.emit(match_state)


func _begin_resume_delay() -> void:
	match_state = MatchState.RESUME_DELAY
	_resume_time_remaining = resume_delay_seconds
	_begin_requested = false
	_waiting_for_begin = false
	_discard_resume_inputs()
	set_process(true)
	if print_events:
		print("Resume delay %.2fs" % resume_delay_seconds)
	match_state_changed.emit(match_state)


func _begin_presentation_length() -> float:
	var banner := _announcement()
	if banner != null and banner.has_method("light_pass_length"):
		return float(banner.light_pass_length())
	return 0.72


func _announcement() -> Node:
	var hud := get_node_or_null("../CombatHUD")
	if hud != null:
		var named := hud.get_node_or_null("CombatAnnouncement")
		if named != null:
			return named
	if is_inside_tree():
		return get_tree().get_first_node_in_group("combat_announcement")
	return null


func _play_begin() -> bool:
	var banner := _announcement()
	if banner == null or not banner.has_method("play_begin"):
		return false
	if banner.has_signal("pass_finished") and not banner.pass_finished.is_connected(_on_announcement_pass_finished):
		banner.pass_finished.connect(_on_announcement_pass_finished)
	banner.play_begin()
	return true


func _on_announcement_pass_finished(text: String) -> void:
	if text != "BEGIN" or match_state != MatchState.RESUME_DELAY or not _waiting_for_begin:
		return
	_waiting_for_begin = false
	_discard_resume_inputs()
	_resume_fighting()
	hud_text_changed.emit("FIGHTING")


func _resume_fighting() -> void:
	set_process(false)
	current_count = 0
	downed_side = DownedSide.NONE
	will_recover = false
	stand_up_count = -1
	_resume_time_remaining = 0.0
	_begin_requested = false
	_waiting_for_begin = false
	_candidate_live = false
	_pending_kind = 0
	_waiting_for_finisher = false
	_player_stood = false
	_opponent_stood = false
	match_state = MatchState.FIGHTING
	if _combat_control_enabled:
		player_stamina.set_regeneration_enabled(true)
		opponent_stamina.set_regeneration_enabled(true)
		opponent_attack_state.set_combat_enabled(true)
		_set_meter_updates_enabled(true)
	match_state_changed.emit(match_state)
	var rounds := get_node_or_null("../RoundManager")
	if rounds != null and rounds.has_method("resume_after_knockdown"):
		rounds.resume_after_knockdown()
	if print_events:
		print("FIGHTING RESUME")


func _discard_resume_inputs() -> void:
	var buffer = get_node_or_null("../PlayerActionBuffer")
	if buffer != null and buffer.has_method("clear"):
		buffer.clear()
	var combat_input = get_node_or_null("../PlayerCombatInput")
	if combat_input != null and combat_input.has_method("clear_held_evade"):
		combat_input.clear_held_evade()
	if combat_input != null and "is_guarding" in combat_input:
		combat_input.is_guarding = false
	if player_action_state != null and player_action_state.is_guarding():
		player_action_state.set_guard_held(false)
	var ai = get_node_or_null("../OpponentAI")
	if ai != null and ai.has_method("clear_pending_combat_decisions"):
		ai.clear_pending_combat_decisions()
	if opponent_attack_state != null:
		opponent_attack_state.set_combat_enabled(false)


func _freeze_combat() -> void:
	player_attack_state.cancel_attack()
	player_action_state.force_reset_to_idle()
	if opponent_action_state != null:
		opponent_action_state.force_reset_to_idle()
	opponent_attack_state.cancel_and_disable()
	var ai = get_node_or_null("../OpponentAI")
	if ai != null and ai.has_method("clear_pending_combat_decisions"):
		ai.clear_pending_combat_decisions()
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


func _recovery_meter_value() -> float:
	var meter := (
		player_knockdown_meter
		if downed_side == DownedSide.PLAYER
		else opponent_knockdown_meter
	)
	if meter == null:
		return preload("res://scripts/knockdown_meter.gd").new().max_meter * recovery_meter_ratio
	return meter.max_meter * recovery_meter_ratio


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
