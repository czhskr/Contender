class_name OpponentAI
extends Node

## Decides attack/defense. Execution stays on OpponentAttackState.
## Hooks remain in AttackData/enum but are excluded from AI candidates.
##
## After Recovery the next decision is immediate. A new punch may open a
## 1/2/3-hit opposite-hand combo. Follow-ups still use recovery cancel,
## same-hand reuse, and stamina. Choosing not to attack can still wait.

const MatchSettings = preload("res://scripts/match_settings.gd")
const DifficultyType = preload("res://scripts/opponent_difficulty_settings.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")
const OpponentActionStateType = preload("res://scripts/opponent_action_state.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const AttackDataType = preload("res://scripts/opponent_attack_data.gd")
const AttackHand = preload("res://scripts/attack_data.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")
const RoundManagerType = preload("res://scripts/round_manager.gd")

const ACTIVE_ATTACK_TYPES := [
	AttackDataType.AttackType.LEFT_STRAIGHT,
	AttackDataType.AttackType.RIGHT_STRAIGHT,
]

const READY_POLL := 0.02

signal difficulty_changed(settings: DifficultyType)

@export var difficulty: DifficultyType
@export var player_attack_state: AttackStateType
@export var opponent_attack_state: OpponentAttackStateType
@export var opponent_action_state: OpponentActionStateType
@export var opponent_stamina: OpponentStaminaType
@export var knockdown_manager: KnockdownManagerType
@export var round_manager: RoundManagerType
@export var opponent_hit_stun: Node
@export var finisher_impact_freeze: Node

@export_group("Recovery Cancel")
## Attack → Attack cancel progress on Recovery (same principle as player).
@export_range(0.0, 1.0, 0.01) var attack_to_attack_cancel := 0.50

@export_group("Pressure Defense")
@export_range(0.0, 3.0, 0.01) var pressure_memory_duration := 0.60
@export_range(0.0, 1.0, 0.01) var pressure_defense_chance := 0.60
@export_range(0.0, 1.0, 0.01) var pressure_defense_chance_hit_2 := 0.68
@export_range(0.0, 1.0, 0.01) var pressure_defense_chance_hit_3_plus := 0.76
@export_range(0.0, 1.0, 0.01) var pressure_guard_weight := 0.45
@export_range(0.0, 1.0, 0.01) var pressure_reaction_delay := 0.104
@export_range(0.0, 1.0, 0.01) var pressure_reaction_hit_2 := 0.065
@export_range(0.01, 1.0, 0.01) var pressure_reaction_hit_3_plus := 0.039

@export_group("Proactive Defense")
@export_range(0.1, 6.0, 0.01) var proactive_defense_interval_min := 0.55
@export_range(0.1, 6.0, 0.01) var proactive_defense_interval_max := 1.05
@export_range(0.0, 1.0, 0.01) var proactive_guard_chance := 0.32
@export_range(0.0, 1.0, 0.01) var proactive_guard_weight := 0.65
@export_range(0.0, 2.0, 0.01) var proactive_guard_hold_min := 0.55
@export_range(0.0, 2.0, 0.01) var proactive_guard_hold_max := 0.90
@export_range(0.0, 2.0, 0.01) var pressure_guard_duration := 0.45

@export_group("Debug")
@export_range(0.0, 1.0, 0.01) var pattern_single_chance := 0.30
@export_range(0.0, 1.0, 0.01) var pattern_quick_chance := 0.30
@export_range(0.0, 1.0, 0.01) var pattern_burst_chance := 0.20
@export_range(0.0, 1.0, 0.01) var followup_opposite_chance := 0.70
@export_range(0.0, 1.0, 0.01) var retaliation_block_chance := 0.45
@export_range(0.0, 1.0, 0.01) var retaliation_evade_chance := 0.60
@export_range(0.0, 2.0, 0.01) var initiative_block_duration := 0.20
@export_range(0.0, 2.0, 0.01) var initiative_evade_duration := 0.35
@export_range(0.5, 1.0, 0.01) var neutral_offense_scale := 0.82
@export var print_ai_decisions := false
@export var print_stamina_decisions := true

var _offense_cooldown := 0.0
var _reaction_pending := false
var _reaction_timer := 0.0
var _reaction_attack := -1
var _logged_stamina_wait := false
var _follow_up_pending := false
var _follow_up_used := false
var _combo_left := 0
var _combo_sequence := ""
var _follow_type := -1
var _follow_delay_until := -1.0
var _attack_pattern := 0
var debug_pattern_counts: Array[int] = [0, 0, 0, 0]
var _follow_reason := ""
var _retaliation_pending := false
var _retaliation_chance := 0.0
var _initiative_remaining := -1.0
var _initiative_source := ""
var _held_defense_attack := -2
var _releasing_defense := false
var _last_defer_reason := ""
var _last_defense_success_time := -1.0
var debug_combo_counts: Array[int] = [0, 0, 0, 0]
var debug_stamina_cancels := 0
var debug_retaliation_armed := 0
var debug_retaliation_block_armed := 0
var debug_retaliation_evade_armed := 0
var debug_retaliation_attempted := 0
var debug_retaliation_started := 0
var debug_retaliation_failed := 0
var debug_initiative_started := 0
var debug_initiative_consumed := 0
var debug_initiative_expired := 0
var debug_defense_to_attack: Array[float] = []
var debug_retaliation_trace: PackedStringArray = []
var _needs_post_recovery_pacing := false
var _last_attack_type := -1
var _combat_time := 0.0
var _pressure_until := -1.0
var _pressure_hit_count := 0
var _pressure_stun_id := 0
var _recovery_defense_used_stun := -1
var _pressure_recovery_armed := false
var _deferred_pressure_recovery := false
var _was_hit_stunned := false
var _pressure_reaction := false
var _guard_hold_remaining := -1.0
var _proactive_timer := 1.0
var player_stamina: Node = null


func _ready() -> void:
	if difficulty == null:
		difficulty = DifficultyType.new()
		difficulty.display_name = "Normal"
	if player_attack_state != null:
		player_attack_state.state_changed.connect(_on_player_attack_state_changed)
	var offense = null
	var parent := get_parent()
	if parent != null:
		offense = parent.get_node_or_null("PlayerOffenseResolver")
		player_stamina = parent.get_node_or_null("PlayerStamina")
	if offense != null and offense.has_signal("attack_hit"):
		if not offense.attack_hit.is_connected(_on_player_attack_resolved):
			offense.attack_hit.connect(_on_player_attack_resolved)
	_roll_offense_cooldown(true)
	_roll_proactive_timer()


func set_difficulty(settings: DifficultyType) -> void:
	if settings == null:
		return
	difficulty = settings
	_roll_offense_cooldown(true)
	difficulty_changed.emit(difficulty)
	if print_ai_decisions:
		print("AI Difficulty -> %s" % difficulty.display_name)


func get_difficulty() -> DifficultyType:
	return difficulty


func _process(delta: float) -> void:
	if _match_is_live():
		_combat_time += delta
	else:
		_pressure_hit_count = 0
	if _pressure_hit_count > 0 and not _is_under_pressure():
		_pressure_hit_count = 0
		_deferred_pressure_recovery = false
		_set_armed(false, "MEMORY_EXPIRED")
	var stunned := _is_hit_stunned()
	if stunned and not _was_hit_stunned:
		_guard_hold_remaining = -1.0
		_pressure_stun_id += 1
	if _was_hit_stunned and not stunned:
		_on_hit_stun_ended()
	_was_hit_stunned = stunned
	if not _can_think():
		if knockdown_manager != null and not knockdown_manager.is_fighting():
			_cancel_combo("KNOCKDOWN")
		elif round_manager != null and not round_manager.can_accept_combat_input():
			_cancel_combo("ROUND_END")
		elif finisher_impact_freeze != null and finisher_impact_freeze.has_method("is_blocking_combat") and finisher_impact_freeze.is_blocking_combat():
			_cancel_combo("FREEZE")
		_clear_pending_reaction()
		return

	_tick_guard_hold(delta)
	if _held_defense_attack >= -1 and _player_is_active_phase():
		_release_held_defense()
	if _is_initiative_active() and _retaliation_pending and not _player_is_active_phase():
		var taken := _take_retaliation_decision()
		if taken == 1:
			_consume_initiative()
			_held_defense_attack = -2
			return
		if taken == 2:
			_consume_initiative()
			_release_held_defense()
		else:
			_note_defer(_defer_reason())
	_expire_initiative(delta)
	if _reaction_pending:
		_reaction_timer -= delta
		if _reaction_timer <= 0.0:
			_resolve_scheduled_reaction()
		_offense_cooldown = maxf(_offense_cooldown - delta, 0.0)
		return

	if not (_retaliation_pending and not _follow_up_pending and not _pressure_recovery_armed):
		_tick_proactive_defense(delta)
	if _retaliation_pending and not _follow_up_pending and not _pressure_recovery_armed:
		_offense_cooldown = 0.0
	_offense_cooldown = maxf(_offense_cooldown - delta, 0.0)
	if _offense_cooldown <= 0.0 and not _pressure_recovery_armed:
		_try_offense()


func _can_think() -> bool:
	if finisher_impact_freeze != null and finisher_impact_freeze.has_method("is_blocking_combat"):
		if finisher_impact_freeze.is_blocking_combat():
			return false
	if knockdown_manager != null and not knockdown_manager.is_fighting():
		return false
	if round_manager != null and not round_manager.can_accept_combat_input():
		return false
	if opponent_attack_state != null and not opponent_attack_state.combat_enabled:
		return false
	return true


func _on_player_attack_state_changed(state: int, attack: int) -> void:
	if print_ai_decisions and player_attack_state != null:
		print(
			"[PLAYER_ATTACK] token=%d hand=%s type=%d phase=%s time=%.3f"
			% [
				player_attack_state.get_action_token(),
				"LEFT" if attack == 0 or attack == 2 else "RIGHT",
				attack,
				_player_phase_name(),
				_combat_time,
			]
		)
	if state != AttackStateType.AttackState.STARTUP:
		return
	if _defer_new_defense_for_initiative(attack):
		return
	_pressure_log(
		"startup token=%d hit_count=%d armed=%s pressure=%.3f stun=%s remain=%.3f can_defend=%s pending=%s used_stun=%d stun_id=%d"
		% [
			player_attack_state.get_action_token() if player_attack_state != null else -1,
			_pressure_hit_count,
			_pressure_recovery_armed,
			maxf(_pressure_until - _combat_time, 0.0),
			_is_hit_stunned(),
			_stun_remaining(),
			opponent_action_state.can_defend() if opponent_action_state != null else false,
			_pressure_reaction,
			_recovery_defense_used_stun,
			_pressure_stun_id,
		]
	)
	if _pressure_recovery_armed and _is_under_pressure():
		if opponent_action_state == null or not opponent_action_state.can_defend():
			_mark_pressure()
			return
		_set_armed(false, "NEXT_STARTUP_CONSUMED")
		_deferred_pressure_recovery = false
		_try_schedule_pressure_recovery()
		_mark_pressure()
		return
	if (
		_pressure_hit_count > 0
		and _is_under_pressure()
		and _recovery_defense_used_stun != _pressure_stun_id
	):
		if _is_hit_stunned():
			_deferred_pressure_recovery = true
			_pressure_log("DEFER reason=STUN_STILL_ACTIVE remain=%.3f" % _stun_remaining())
			_mark_pressure()
			return
		_recovery_defense_used_stun = _pressure_stun_id
		_try_schedule_pressure_recovery()
		_mark_pressure()
		return
	if _pressure_reaction and _reaction_pending:
		_mark_pressure()
		return
	if _can_think():
		_schedule_defense_reaction(attack)
	_mark_pressure()


func _schedule_defense_reaction(attack: int) -> void:
	_reaction_pending = true
	_reaction_attack = attack
	var variance := difficulty.reaction_delay_variance
	var base_delay := difficulty.reaction_delay
	if _is_under_pressure():
		base_delay = _pressure_reaction_base()
	var delay := _compose_reaction(base_delay)
	if not _is_under_pressure():
		delay = maxf(delay + _unit_roll_range(-variance, variance), 0.01)
	_reaction_timer = delay
	if print_ai_decisions:
		print(
			"[AI DEFENSE] detected player attack=%d | reaction=%.2f"
			% [attack, _reaction_timer]
		)


## Called when the player's punch reaches ACTIVE, before hit resolution.
## If the configured delay has not elapsed yet, the punch forces the decision
## so Guard/Slip can still be up for BLOCK/EVADE. Difficulty rolls are unchanged.
func resolve_pending_defense_now() -> void:
	if not _reaction_pending:
		return
	_reaction_timer = 0.0
	_resolve_scheduled_reaction()


func _resolve_scheduled_reaction() -> void:
	_reaction_pending = false
	if not _can_think():
		return
	if player_attack_state.current_state not in [
		AttackStateType.AttackState.STARTUP,
		AttackStateType.AttackState.ACTIVE,
	]:
		if print_ai_decisions:
			print("[AI DEFENSE] cancelled | player attack ended")
		return
	if not opponent_action_state.can_defend():
		if print_ai_decisions:
			print("[AI DEFENSE] skipped | not IDLE (attack commitment)")
		_pressure_reaction = false
		return

	if _pressure_reaction:
		_pressure_reaction = false
		var pressure_choice := _choose_pressure_defense()
		_apply_defense(pressure_choice, false)
		return

	var reaction_chance := difficulty.defensive_reaction_chance
	if _is_under_pressure():
		reaction_chance = _pressure_defense_chance_now()
	if _unit_roll() > reaction_chance:
		if print_ai_decisions:
			print("[AI DEFENSE] decision=NONE (no reaction)")
		return

	var is_mistake := _unit_roll() < difficulty.mistake_chance
	var choice := _choose_defense(_reaction_attack, is_mistake)
	_apply_defense(choice, is_mistake)


func _choose_defense(_player_attack: int, is_mistake: bool) -> String:
	if is_mistake:
		var roll := _unit_roll()
		if roll < 0.34:
			return "NONE"
		if roll < 0.67:
			return "GUARD"
		return "SLIP_LEFT" if _unit_roll() < 0.5 else "SLIP_RIGHT"

	var evade_roll := _unit_roll()
	if evade_roll < difficulty.evade_chance:
		return "SLIP_LEFT" if _unit_roll() < 0.5 else "SLIP_RIGHT"
	if _unit_roll() < difficulty.guard_chance:
		return "GUARD"
	return "NONE"


func _apply_defense(choice: String, is_mistake: bool) -> void:
	match choice:
		"SLIP_LEFT":
			opponent_action_state.try_start_evasion(
				OpponentActionStateType.OpponentState.SLIP_LEFT
			)
			_pressure_log("SLIP_EXECUTED SLIP_LEFT")
		"SLIP_RIGHT":
			opponent_action_state.try_start_evasion(
				OpponentActionStateType.OpponentState.SLIP_RIGHT
			)
			_pressure_log("SLIP_EXECUTED SLIP_RIGHT")
		"GUARD":
			_begin_guard_hold(pressure_guard_duration)
			_pressure_log("GUARD_EXECUTED")
		_:
			pass

	if print_ai_decisions:
		if is_mistake:
			print("[AI DEFENSE] mistake=true | decision=%s" % choice)
		else:
			print("[AI DEFENSE] mistake=false | decision=%s" % choice)


func _try_offense() -> void:
	if opponent_attack_state == null:
		_offense_cooldown = READY_POLL
		return
	if opponent_action_state != null:
		var action := opponent_action_state.current_state
		if action != OpponentActionStateType.OpponentState.IDLE:
			if action != OpponentActionStateType.OpponentState.ATTACKING:
				_offense_cooldown = READY_POLL
				return

	if _follow_up_pending:
		_execute_follow_up()
		return

	if _retaliation_pending and not _is_initiative_active():
		var taken := _take_retaliation_decision()
		if taken == 0:
			_offense_cooldown = READY_POLL
			_note_defer(_defer_reason())
			return
		if taken == 1:
			return

	if randf() > _proactive_attack_chance():
		_log_stamina_decision("WAIT", "")
		_roll_offense_cooldown(false)
		return

	if not _start_new_attack():
		_log_stamina_decision("WAIT", "")
		if print_ai_decisions and not _logged_stamina_wait:
			print("AI waiting for stamina recovery")
			_logged_stamina_wait = true
		_roll_offense_cooldown(false)


## Idle, or opposite-hand recovery past the cancel threshold.
func _commit_recovery_for(next_attack_type: int) -> bool:
	if opponent_hit_stun != null and opponent_hit_stun.is_hit_stunned():
		return false
	if opponent_attack_state.is_ready_for_command():
		return true
	if not _can_recovery_cancel_offense(next_attack_type):
		return false
	opponent_attack_state.force_end_for_cancel()
	return opponent_attack_state.is_ready_for_command()


func _can_recovery_cancel_offense(next_attack_type: int) -> bool:
	if opponent_attack_state == null or not opponent_attack_state.is_recovering():
		return false
	var current = opponent_attack_state.current_attack
	var current_type := -1
	if current != null:
		current_type = current.attack_type
	return AttackHand.can_recovery_cancel(
		opponent_attack_state.get_recovery_progress(),
		_opposite_cancel_threshold(),
		current_type,
		next_attack_type
	)


func _opposite_cancel_threshold() -> float:
	var threshold := attack_to_attack_cancel
	if not is_inside_tree():
		return threshold
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager != null:
		threshold *= preload("res://scripts/trait_math.gd").product(
			manager.opponent_traits, "attack_link_threshold"
		)
	return clampf(threshold, 0.0, 1.0)


func _start_new_attack() -> bool:
	var attack: AttackDataType = _pick_opening_attack()
	if attack == null:
		return false
	if not _commit_recovery_for(attack.attack_type):
		_offense_cooldown = READY_POLL
		return false
	if not opponent_attack_state.try_execute_attack(attack.attack_type):
		_offense_cooldown = READY_POLL
		return false
	_last_attack_type = attack.attack_type
	_logged_stamina_wait = false
	_follow_up_used = false
	_begin_combo(attack.attack_type)
	if print_ai_decisions:
		print("[AI_ATTACK] %s START stamina=%.1f" % [OpponentAttackStateType.ATTACK_NAMES[attack.attack_type], _stamina_now()])
	return true


func _pick_opening_attack() -> AttackDataType:
	var candidates: Array[AttackDataType] = []
	for attack in opponent_attack_state.get_affordable_attacks():
		if attack.attack_type in ACTIVE_ATTACK_TYPES:
			candidates.append(attack)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func _execute_follow_up() -> void:
	if _follow_delay_until >= 0.0 and _combat_time < _follow_delay_until:
		_offense_cooldown = READY_POLL
		return
	if _follow_type < 0:
		_choose_follow_hand()
	var attack := opponent_attack_state.get_attack_data(_follow_type)
	var affordable := (
		attack != null
		and attack.attack_type in ACTIVE_ATTACK_TYPES
		and opponent_stamina != null
		and opponent_stamina.can_afford(attack.stamina_cost)
	)
	if not affordable:
		if _follow_up_can_leave():
			_cancel_combo("NO_STAMINA")
		_offense_cooldown = READY_POLL
		return
	if not opponent_attack_state.is_hand_ready(_follow_type):
		_offense_cooldown = READY_POLL
		return
	if not _commit_recovery_for(_follow_type):
		_offense_cooldown = READY_POLL
		return
	if opponent_attack_state.try_execute_attack(_follow_type):
		_last_attack_type = _follow_type
		_combo_left = maxi(_combo_left - 1, 0)
		_follow_up_pending = false
		_follow_up_used = true
		_offense_cooldown = READY_POLL
		_combo_sequence = _append_hand(_combo_sequence, _follow_type)
		if print_ai_decisions:
			print("[AI_COMBO] followup=%s reason=%s" % [OpponentAttackStateType.ATTACK_NAMES[_follow_type], _follow_reason])
			print("[AI_ATTACK] %s START stamina=%.1f" % [OpponentAttackStateType.ATTACK_NAMES[_follow_type], _stamina_now()])
		_follow_type = -1
		if _combo_left > 0:
			_follow_up_pending = true
			_choose_follow_hand()
	else:
		_offense_cooldown = READY_POLL


func _follow_up_can_leave() -> bool:
	if opponent_attack_state.is_ready_for_command():
		return opponent_attack_state.is_hand_ready(_follow_type)
	return _can_recovery_cancel_offense(_follow_type) and opponent_attack_state.is_hand_ready(_follow_type)


func _choose_follow_hand() -> void:
	var want_same := randf() >= followup_opposite_chance
	if want_same:
		_follow_type = _last_attack_type
		_follow_reason = "SAME_HAND"
	else:
		_follow_type = _opposite_type(_last_attack_type)
		_follow_reason = "OPPOSITE_HAND"


func _append_hand(sequence: String, attack_type: int) -> String:
	var letter := "L" if attack_type == AttackDataType.AttackType.LEFT_STRAIGHT or attack_type == AttackDataType.AttackType.LEFT_HOOK else "R"
	if sequence.is_empty():
		return letter
	return sequence + "-" + letter


func _begin_combo(first_type: int) -> void:
	_attack_pattern = _choose_pattern()
	debug_pattern_counts[_attack_pattern] += 1
	var length := 1
	if _attack_pattern == 1 or _attack_pattern == 3:
		length = 2
	elif _attack_pattern == 2:
		length = 3
	_combo_left = length - 1
	_combo_sequence = _append_hand("", first_type)
	debug_combo_counts[length] += 1
	_follow_type = -1
	_follow_delay_until = -1.0
	if _attack_pattern == 3:
		_follow_delay_until = _combat_time + randf_range(0.15, 0.30)
	_follow_up_pending = _combo_left > 0
	_needs_post_recovery_pacing = false
	_offense_cooldown = READY_POLL
	if _follow_up_pending:
		_choose_follow_hand()
	if print_ai_decisions:
		print("[AI_PATTERN] %s intent=%d" % [_pattern_name(_attack_pattern), length])
	_log_stamina_decision("ATTACK", _pattern_name(_attack_pattern))


func _choose_pattern() -> int:
	var weights := _pattern_weights()
	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return 0
	var roll := randf() * total
	var cursor := 0.0
	for index in weights.size():
		cursor += weights[index]
		if roll <= cursor:
			return index
	return weights.size() - 1


func stamina_ratio() -> float:
	if opponent_stamina == null:
		return 1.0
	var maximum := float(opponent_stamina.max_stamina)
	if maximum <= 0.0:
		maximum = 100.0
	return clampf(float(opponent_stamina.current_stamina) / maximum, 0.0, 1.0)


## 1 at high stamina. Falls smoothly below 70% so the fighter starts leaving recovery time.
func stamina_offense_modifier() -> float:
	var ratio := stamina_ratio()
	if ratio >= 0.70:
		return 1.0
	var t := ratio / 0.70
	return lerpf(0.08, 1.0, pow(t, 1.35))


## 1 at high stamina. Stretches the existing attack interval when stamina is low.
func stamina_interval_modifier() -> float:
	var ratio := stamina_ratio()
	if ratio >= 0.70:
		return 1.0
	var t := ratio / 0.70
	return lerpf(2.4, 1.0, pow(t, 1.05))


func proactive_attack_chance() -> float:
	var base := difficulty.aggression * neutral_offense_scale
	return clampf(base * stamina_offense_modifier(), 0.0, 1.0)


func _proactive_attack_chance() -> float:
	return proactive_attack_chance()


func _pattern_weights() -> Array[float]:
	var conserve := clampf(1.0 - stamina_offense_modifier(), 0.0, 1.0)
	var delayed := maxf(0.0, 1.0 - pattern_single_chance - pattern_quick_chance - pattern_burst_chance)
	var weights: Array[float] = [
		pattern_single_chance * (1.0 + 1.35 * conserve),
		pattern_quick_chance * (1.0 - 0.62 * conserve),
		pattern_burst_chance * (1.0 - 0.82 * conserve),
		delayed * (1.0 - 0.62 * conserve),
	]
	var costs: Array[float] = [4.5, 9.0, 13.5, 9.0]
	var stamina_now := maxf(_stamina_now(), 0.0)
	for index in weights.size():
		if weights[index] <= 0.0:
			continue
		weights[index] *= clampf(stamina_now / costs[index], 0.15, 1.0)
	return weights


func _pattern_name(pattern: int) -> String:
	match pattern:
		0:
			return "SINGLE_PROBE"
		1:
			return "QUICK_DOUBLE"
		2:
			return "THREE_PUNCH_BURST"
		_:
			return "DELAYED_DOUBLE"


func _opposite_type(attack_type: int) -> int:
	match attack_type:
		AttackDataType.AttackType.LEFT_STRAIGHT:
			return AttackDataType.AttackType.RIGHT_STRAIGHT
		AttackDataType.AttackType.RIGHT_STRAIGHT:
			return AttackDataType.AttackType.LEFT_STRAIGHT
		_:
			return -1


func _planned_sequence(first_type: int, length: int) -> String:
	var parts: PackedStringArray = []
	var attack_type := first_type
	for _i in length:
		parts.append("L" if attack_type == AttackDataType.AttackType.LEFT_STRAIGHT else "R")
		attack_type = _opposite_type(attack_type)
		if attack_type < 0:
			break
	return "-".join(parts)


func _cancel_combo(reason: String) -> void:
	if _combo_left <= 0 and not _follow_up_pending:
		return
	_combo_left = 0
	_follow_up_pending = false
	_follow_type = -1
	_follow_delay_until = -1.0
	if reason == "NO_STAMINA":
		debug_stamina_cancels += 1
	if print_ai_decisions:
		print("[AI_COMBO] CANCEL reason=%s" % reason)


func _stamina_now() -> float:
	if opponent_stamina == null:
		return -1.0
	return float(opponent_stamina.current_stamina)


func _pick_follow_up_attack(previous_type: int) -> AttackDataType:
	var opposite := -1
	match previous_type:
		AttackDataType.AttackType.LEFT_STRAIGHT:
			opposite = AttackDataType.AttackType.RIGHT_STRAIGHT
		AttackDataType.AttackType.RIGHT_STRAIGHT:
			opposite = AttackDataType.AttackType.LEFT_STRAIGHT
		_:
			opposite = -1

	if opposite >= 0:
		var preferred := opponent_attack_state.get_attack_data(opposite)
		if (
			preferred != null
			and preferred.attack_type in ACTIVE_ATTACK_TYPES
			and opponent_stamina.can_afford(preferred.stamina_cost)
		):
			return preferred

	return _pick_attack(true)


func _pick_attack(prefer_fast: bool) -> AttackDataType:
	var affordable := opponent_attack_state.get_affordable_attacks()
	var candidates: Array[AttackDataType] = []
	for attack in affordable:
		if attack.attack_type in ACTIVE_ATTACK_TYPES:
			candidates.append(attack)
	if candidates.is_empty():
		return null

	var weights: Array[float] = []
	var total := 0.0
	for attack in candidates:
		var weight := difficulty.straight_weight
		if prefer_fast:
			weight *= 1.25
		if opponent_stamina.current_stamina < difficulty.low_stamina_threshold:
			weight *= 1.0 / maxf(attack.stamina_cost, 1.0)
		weights.append(weight)
		total += weight

	if total <= 0.0:
		return candidates[0]

	var roll := randf() * total
	var cumulative := 0.0
	for i in candidates.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return candidates[i]
	return candidates.back()


## Test seam. Production leaves this empty and uses randf.
var debug_forced_rolls: Array[float] = []


func _trait_product(is_player: bool, field: String) -> float:
	if not is_inside_tree():
		return 1.0
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager == null:
		return 1.0
	return preload("res://scripts/trait_math.gd").product(manager.traits_for_player(is_player), field)


func _unit_roll() -> float:
	if not debug_forced_rolls.is_empty():
		return clampf(debug_forced_rolls.pop_front(), 0.0, 1.0)
	return randf()


func _unit_roll_range(min_value: float, max_value: float) -> float:
	return lerpf(min_value, max_value, _unit_roll())


func _roll_offense_cooldown(initial: bool) -> void:
	var pace := _trait_product(false, "offense_pace") * stamina_interval_modifier()
	var minimum := difficulty.attack_interval_min * pace
	var maximum := maxf(difficulty.attack_interval_max * pace, minimum)
	_offense_cooldown = randf_range(minimum, maximum)
	if initial:
		_offense_cooldown = minf(_offense_cooldown, maximum)


func _log_stamina_decision(decision: String, pattern: String) -> void:
	if not print_stamina_decisions:
		return
	print(
		"[AI_STAMINA] stamina=%.1f ratio=%.2f offense_modifier=%.2f interval_modifier=%.2f pattern=%s decision=%s"
		% [
			_stamina_now(),
			stamina_ratio(),
			stamina_offense_modifier(),
			stamina_interval_modifier(),
			pattern if pattern != "" else "-",
			decision,
		]
	)


func _is_hit_stunned() -> bool:
	return opponent_hit_stun != null and opponent_hit_stun.is_hit_stunned()


func _match_is_live() -> bool:
	if knockdown_manager != null and not knockdown_manager.is_fighting():
		return false
	if round_manager != null and not round_manager.can_accept_combat_input():
		return false
	return true


func _pressure_log(message: String) -> void:
	if print_ai_decisions:
		print("[PRESSURE] %s" % message)


func _player_is_attacking() -> bool:
	if player_attack_state == null:
		return false
	return player_attack_state.current_state in [
		AttackStateType.AttackState.STARTUP,
		AttackStateType.AttackState.ACTIVE,
		AttackStateType.AttackState.RECOVERY,
	]


func _player_phase_name() -> String:
	if player_attack_state == null:
		return "NONE"
	match player_attack_state.current_state:
		AttackStateType.AttackState.STARTUP:
			return "STARTUP"
		AttackStateType.AttackState.ACTIVE:
			return "ACTIVE"
		AttackStateType.AttackState.RECOVERY:
			return "RECOVERY"
		_:
			return "IDLE"


func _set_armed(next: bool, reason: String) -> void:
	if _pressure_recovery_armed == next:
		return
	_pressure_log("ARMED %s -> %s reason=%s" % [_pressure_recovery_armed, next, reason])
	_pressure_recovery_armed = next


func _stun_remaining() -> float:
	if opponent_hit_stun == null or not opponent_hit_stun.has_method("get_time_remaining"):
		return 0.0
	return float(opponent_hit_stun.get_time_remaining())


func _mark_pressure() -> void:
	_pressure_until = _combat_time + pressure_memory_duration


func _is_under_pressure() -> bool:
	return _combat_time < _pressure_until


func _on_player_attack_resolved(
	_attack: int,
	_damage: float,
	_meter: float,
	_was_knockdown: bool,
	result: int
) -> void:
	if result == 0:
		if not _is_under_pressure():
			_pressure_hit_count = 0
		_pressure_hit_count += 1
		_mark_pressure()
		_offer_pressure_defense()
	elif result == 1:
		_mark_pressure()
		_arm_retaliation(_scaled_chance(retaliation_block_chance, MatchSettings.retaliation_chance_multiplier()), "BLOCK")
	elif result == 2:
		_arm_retaliation(_scaled_chance(retaliation_evade_chance, MatchSettings.retaliation_chance_multiplier()), "EVADE")


func _arm_retaliation(chance: float, source: String) -> void:
	_retaliation_pending = true
	_retaliation_chance = chance
	debug_retaliation_armed += 1
	if source == "BLOCK":
		debug_retaliation_block_armed += 1
		_initiative_remaining = initiative_block_duration
	else:
		debug_retaliation_evade_armed += 1
		_initiative_remaining = initiative_evade_duration
	_initiative_source = source
	debug_initiative_started += 1
	_last_defense_success_time = _combat_time
	_last_defer_reason = ""
	_retaliation_log("ARM source=%s" % source)


func _is_initiative_active() -> bool:
	return _initiative_remaining > 0.0


func _initiative_is_frozen() -> bool:
	if _is_hit_stunned():
		return true
	if opponent_action_state != null:
		var action := opponent_action_state.current_state
		if action == OpponentActionStateType.OpponentState.GUARD:
			return true
		if action == OpponentActionStateType.OpponentState.SLIP_LEFT or action == OpponentActionStateType.OpponentState.SLIP_RIGHT:
			return true
	if opponent_attack_state != null and opponent_attack_state.current_state in [
		preload("res://scripts/opponent_attack_state.gd").AttackState.STARTUP,
		preload("res://scripts/opponent_attack_state.gd").AttackState.ACTIVE,
	]:
		return true
	return false


func _expire_initiative(delta: float) -> void:
	if _initiative_remaining <= 0.0 or _initiative_is_frozen():
		return
	_initiative_remaining = maxf(_initiative_remaining - delta, 0.0)
	if _initiative_remaining > 0.0:
		return
	_initiative_remaining = -1.0
	_initiative_source = ""
	debug_initiative_expired += 1
	_retaliation_log("EXPIRED")
	_release_held_defense()


func _defer_new_defense_for_initiative(attack: int) -> bool:
	if _releasing_defense or not _is_initiative_active() or not _retaliation_pending:
		return false
	if _player_is_active_phase():
		return false
	_held_defense_attack = attack
	_note_defer(_defer_reason())
	_mark_pressure()
	return true


func _player_is_active_phase() -> bool:
	return (
		player_attack_state != null
		and player_attack_state.current_state == AttackStateType.AttackState.ACTIVE
	)


func _consume_initiative() -> void:
	if _initiative_remaining <= 0.0 and _initiative_source.is_empty():
		return
	_initiative_remaining = -1.0
	_initiative_source = ""
	debug_initiative_consumed += 1


func _release_held_defense() -> void:
	var attack := _held_defense_attack
	_held_defense_attack = -2
	if attack < -1 or player_attack_state == null:
		return
	if not _player_is_attacking():
		return
	_releasing_defense = true
	if (
		_pressure_hit_count > 0
		and _is_under_pressure()
		and _recovery_defense_used_stun != _pressure_stun_id
		and not _is_hit_stunned()
	):
		_recovery_defense_used_stun = _pressure_stun_id
		_try_schedule_pressure_recovery()
	elif _can_think():
		_schedule_defense_reaction(attack)
	_releasing_defense = false


## 0 = not ready, 1 = attack started, 2 = decision used without an attack.
func _take_retaliation_decision() -> int:
	if not _retaliation_pending:
		return 0
	if opponent_attack_state == null or not opponent_attack_state.is_ready_for_command():
		return 0
	if opponent_action_state != null:
		var action := opponent_action_state.current_state
		if action != OpponentActionStateType.OpponentState.IDLE and action != OpponentActionStateType.OpponentState.ATTACKING:
			return 0
	_retaliation_pending = false
	debug_retaliation_attempted += 1
	var chance := _retaliation_chance
	_retaliation_chance = 0.0
	var roll := randf()
	var success := roll < chance
	_retaliation_log("DECISION roll=%.2f chance=%.2f success=%s" % [roll, chance, success])
	if success and _start_new_attack():
		debug_retaliation_started += 1
		if _last_defense_success_time >= 0.0:
			debug_defense_to_attack.append(_combat_time - _last_defense_success_time)
			_last_defense_success_time = -1.0
		_retaliation_log("ATTACK_START")
		return 1
	if not success:
		debug_retaliation_failed += 1
	return 2


func _defer_reason() -> String:
	if _is_hit_stunned():
		return "HIT_STUN"
	if finisher_impact_freeze != null and finisher_impact_freeze.has_method("is_blocking_combat") and finisher_impact_freeze.is_blocking_combat():
		return "FREEZE"
	if knockdown_manager != null and not knockdown_manager.is_fighting():
		return "DOWN"
	if opponent_attack_state != null and opponent_attack_state.current_state in [
		preload("res://scripts/opponent_attack_state.gd").AttackState.STARTUP,
		preload("res://scripts/opponent_attack_state.gd").AttackState.ACTIVE,
	]:
		return "COMMITTED_ATTACK"
	if opponent_action_state != null:
		var action := opponent_action_state.current_state
		if action == OpponentActionStateType.OpponentState.GUARD:
			return "GUARD_ACTIVE"
		if action == OpponentActionStateType.OpponentState.SLIP_LEFT or action == OpponentActionStateType.OpponentState.SLIP_RIGHT:
			return "SLIP_ACTIVE"
	if _pressure_recovery_armed or _pressure_reaction:
		return "PENDING_PRESSURE_DEFENSE"
	if _reaction_pending:
		return "PENDING_REACTIVE_DEFENSE"
	if _player_phase_name() == "STARTUP":
		return "PLAYER_STARTUP"
	if opponent_attack_state != null and not opponent_attack_state.is_ready_for_command():
		return "NOT_READY"
	return "NOT_ACTIONABLE"


func _opponent_state_name() -> String:
	if _is_hit_stunned():
		return "HIT_STUN"
	if opponent_attack_state != null and opponent_attack_state.current_state != 0:
		return "ATTACK"
	if opponent_action_state == null:
		return "IDLE"
	return OpponentActionStateType.STATE_NAMES[opponent_action_state.current_state]


func _note_defer(reason: String) -> void:
	if reason == _last_defer_reason:
		return
	_last_defer_reason = reason
	if reason == "NOT_READY" and opponent_attack_state != null:
		_retaliation_log("DEFER reason=%s remain=%.2f gate=%s combat=%s" % [reason, opponent_attack_state._time_remaining, opponent_attack_state._ready_gate, opponent_attack_state.combat_enabled])
		return
	_retaliation_log("DEFER reason=%s" % reason)


func _retaliation_log(message: String) -> void:
	var line := "[RETALIATION] %s time=%.2f player_phase=%s opponent_state=%s" % [
		message,
		_combat_time,
		_player_phase_name(),
		_opponent_state_name(),
	]
	if debug_retaliation_trace.size() < 16:
		debug_retaliation_trace.append(line)
	print(line)


func _offer_pressure_defense() -> void:
	if not _match_is_live() or _pressure_hit_count <= 0 or not _is_under_pressure():
		return
	_set_armed(true, "CLEAN_HIT")


func _on_hit_stun_ended() -> void:
	if not _match_is_live():
		_deferred_pressure_recovery = false
		_pressure_log("SKIP reason=DOWN")
		return
	if _pressure_hit_count <= 0 or not _is_under_pressure():
		_deferred_pressure_recovery = false
		_pressure_log("SKIP reason=MEMORY_EXPIRED")
		return
	if _recovery_defense_used_stun == _pressure_stun_id and not _deferred_pressure_recovery:
		_pressure_log("SKIP reason=ALREADY_USED stun=%d" % _pressure_stun_id)
		return
	_recovery_defense_used_stun = _pressure_stun_id
	var deferred := _deferred_pressure_recovery
	_deferred_pressure_recovery = false
	_pressure_log(
		"STUN_END stun=%d hit_count=%d phase=%s deferred=%s"
		% [_pressure_stun_id, _pressure_hit_count, _player_phase_name(), deferred]
	)
	if deferred or _player_is_attacking():
		_set_armed(false, "STUN_END_IMMEDIATE")
		_try_schedule_pressure_recovery()
		return
	_set_armed(true, "STUN_END_IDLE")


func _try_schedule_pressure_recovery() -> void:
	if _defer_new_defense_for_initiative(_reaction_attack):
		return
	if opponent_action_state == null or not opponent_action_state.can_defend():
		_pressure_log("SKIP reason=COMMITTED_ATTACK")
		return
	var chance := _pressure_defense_chance_now()
	_pressure_log("RECOVERY_CHECK hit_count=%d phase=%s can_defend=true" % [_pressure_hit_count, _player_phase_name()])
	if _unit_roll() > chance:
		_pressure_log("ROLL %.2f FAIL" % chance)
		return
	_pressure_log("ROLL %.2f SUCCESS" % chance)
	_reaction_pending = true
	_pressure_reaction = true
	_reaction_timer = _compose_reaction(_pressure_reaction_base())
	var kind := "PENDING"
	_pressure_log("%s delay=%.2f" % [kind, _reaction_timer])


func _pressure_defense_chance_now() -> float:
	var base := pressure_defense_chance
	if _pressure_hit_count >= 3:
		base = pressure_defense_chance_hit_3_plus
	elif _pressure_hit_count >= 2:
		base = pressure_defense_chance_hit_2
	return _scaled_chance(base, MatchSettings.defense_chance_multiplier())


func _pressure_reaction_base() -> float:
	if _pressure_hit_count >= 3:
		return pressure_reaction_hit_3_plus
	if _pressure_hit_count >= 2:
		return pressure_reaction_hit_2
	return pressure_reaction_delay


func _compose_reaction(base_delay: float) -> float:
	var stamina_mod := _player_stamina_reaction_multiplier()
	var trait_mod := _trait_product(false, "reaction_time")
	var ratio := 1.0
	if player_stamina != null:
		var maximum := float(player_stamina.get("max_stamina"))
		if maximum > 0.0:
			ratio = clampf(float(player_stamina.get("current_stamina")) / maximum, 0.0, 1.0)
	var final_delay := maxf(base_delay * stamina_mod * trait_mod * MatchSettings.reaction_time_multiplier(), 0.01)
	if print_ai_decisions:
		print(
			"[AI_REACTION] base=%.3f player_stamina=%.2f stamina_mod=%.2f trait_mod=%.2f final=%.3f"
			% [base_delay, ratio, stamina_mod, trait_mod, final_delay]
		)
	return final_delay


func _player_stamina_reaction_multiplier() -> float:
	var knots: Array[Vector2] = [
		Vector2(0.0, 0.40),
		Vector2(0.25, 0.55),
		Vector2(0.50, 0.75),
		Vector2(0.75, 0.90),
		Vector2(1.0, 1.0),
	]
	var ratio := 1.0
	if player_stamina != null:
		var maximum := float(player_stamina.get("max_stamina"))
		if maximum > 0.0:
			ratio = clampf(float(player_stamina.get("current_stamina")) / maximum, 0.0, 1.0)
	for index in knots.size() - 1:
		var low: Vector2 = knots[index]
		var high: Vector2 = knots[index + 1]
		if ratio <= high.x or index == knots.size() - 2:
			var span := high.x - low.x
			var weight := 0.0 if span <= 0.0 else (ratio - low.x) / span
			return lerpf(low.y, high.y, clampf(weight, 0.0, 1.0))
	return 1.0


func _scaled_pressure_reaction() -> float:
	return _compose_reaction(_pressure_reaction_base())


func _choose_pressure_defense() -> String:
	if _unit_roll() < pressure_guard_weight:
		_pressure_log("GUARD_PENDING")
		return "GUARD"
	var slip := "SLIP_LEFT" if _unit_roll() < 0.5 else "SLIP_RIGHT"
	_pressure_log("SLIP_PENDING")
	return slip


func _begin_guard_hold(duration: float) -> void:
	if opponent_stamina != null and opponent_stamina.current_stamina <= 0.0:
		return
	opponent_action_state.set_guard_held(true)
	_guard_hold_remaining = duration


func _tick_guard_hold(delta: float) -> void:
	if _guard_hold_remaining < 0.0:
		return
	_guard_hold_remaining -= delta
	if _guard_hold_remaining <= 0.0:
		_guard_hold_remaining = -1.0
		if opponent_action_state != null and opponent_action_state.is_guarding():
			opponent_action_state.set_guard_held(false)


func _scaled_chance(base: float, multiplier: float) -> float:
	return MatchSettings.scale_chance(base, multiplier)


func _proactive_action_chance() -> float:
	return _scaled_chance(proactive_guard_chance, MatchSettings.offense_frequency_multiplier())


func _roll_proactive_timer() -> void:
	var minimum := proactive_defense_interval_min
	var maximum := maxf(proactive_defense_interval_max, minimum)
	_proactive_timer = randf_range(minimum, maximum)


func _tick_proactive_defense(delta: float) -> void:
	_proactive_timer -= delta
	if _proactive_timer > 0.0:
		return
	if not _proactive_decision_ready():
		## Busy actions already have their own duration. Do not restart the full interval.
		_proactive_timer = READY_POLL
		return
	_roll_proactive_timer()
	_consider_proactive_defense()


func _proactive_decision_ready() -> bool:
	if opponent_action_state == null or not opponent_action_state.can_defend():
		return false
	if opponent_attack_state != null and not opponent_attack_state.is_ready_for_command():
		return false
	return true


func _consider_proactive_defense() -> void:
	if opponent_action_state == null or not opponent_action_state.can_defend():
		return
	if opponent_attack_state != null and not opponent_attack_state.is_ready_for_command():
		return
	if _unit_roll() > _proactive_action_chance():
		return
	if _unit_roll() < proactive_guard_weight:
		var hold := _unit_roll_range(proactive_guard_hold_min, proactive_guard_hold_max)
		_begin_guard_hold(hold)
		if print_ai_decisions:
			print("[AI] PROACTIVE_GUARD duration=%.2f" % hold)
		return
	var slip := "SLIP_LEFT" if _unit_roll() < 0.5 else "SLIP_RIGHT"
	_apply_defense(slip, false)
	if print_ai_decisions:
		print("[AI] PROACTIVE_%s" % slip)


func _clear_pending_reaction() -> void:
	_reaction_pending = false
	_reaction_timer = 0.0
	_pressure_reaction = false


func clear_pending_combat_decisions(drop_retaliation: bool = true) -> void:
	_clear_pending_reaction()
	_follow_up_pending = false
	_follow_up_used = false
	_follow_type = -1
	_follow_delay_until = -1.0
	_combo_left = 0
	if drop_retaliation:
		if _retaliation_pending or _initiative_remaining > 0.0:
			_retaliation_log("CLEAR reason=RESET")
		_retaliation_pending = false
		_retaliation_chance = 0.0
		_initiative_remaining = -1.0
		_initiative_source = ""
		_held_defense_attack = -2
		_last_defer_reason = ""
	_needs_post_recovery_pacing = false
	_pressure_until = -1.0
	_pressure_hit_count = 0
	_pressure_stun_id = 0
	_recovery_defense_used_stun = -1
	_pressure_recovery_armed = false
	_deferred_pressure_recovery = false
	_guard_hold_remaining = -1.0
	if opponent_action_state != null and opponent_action_state.is_guarding():
		opponent_action_state.set_guard_held(false)
	_roll_proactive_timer()
	_roll_offense_cooldown(false)
