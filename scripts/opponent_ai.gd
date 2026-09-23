class_name OpponentAI
extends Node

## Decides attack/defense. Execution stays on OpponentAttackState.
## Hooks remain in AttackData/enum but are excluded from AI candidates.
##
## Offense pacing (single timer after Recovery):
##   Attack → Startup/Active/Recovery → short attack_interval → next decision

const DifficultyType = preload("res://scripts/opponent_difficulty_settings.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")
const OpponentActionStateType = preload("res://scripts/opponent_action_state.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const AttackDataType = preload("res://scripts/opponent_attack_data.gd")
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

@export_group("Debug")
@export var print_ai_decisions := false

var _offense_cooldown := 0.0
var _reaction_pending := false
var _reaction_timer := 0.0
var _reaction_attack := -1
var _logged_stamina_wait := false
var _follow_up_pending := false
var _follow_up_used := false
var _needs_post_recovery_pacing := false
var _last_attack_type := -1


func _ready() -> void:
	if difficulty == null:
		difficulty = DifficultyType.new()
		difficulty.display_name = "Normal"
	if player_attack_state != null:
		player_attack_state.state_changed.connect(_on_player_attack_state_changed)
	_roll_offense_cooldown(true)


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
	if not _can_think():
		_clear_pending_reaction()
		return

	if _reaction_pending:
		_reaction_timer -= delta
		if _reaction_timer <= 0.0:
			_resolve_scheduled_reaction()

	_offense_cooldown = maxf(_offense_cooldown - delta, 0.0)
	if _offense_cooldown <= 0.0:
		_try_offense()


func _can_think() -> bool:
	if knockdown_manager != null and not knockdown_manager.is_fighting():
		return false
	if round_manager != null and not round_manager.can_accept_combat_input():
		return false
	if opponent_attack_state != null and not opponent_attack_state.combat_enabled:
		return false
	if opponent_hit_stun != null and opponent_hit_stun.is_hit_stunned():
		return false
	return true


func _on_player_attack_state_changed(state: int, attack: int) -> void:
	if not _can_think():
		return
	if state != AttackStateType.AttackState.STARTUP:
		return
	_schedule_defense_reaction(attack)


func _schedule_defense_reaction(attack: int) -> void:
	_reaction_pending = true
	_reaction_attack = attack
	var variance := difficulty.reaction_delay_variance
	var delay := difficulty.reaction_delay + randf_range(-variance, variance)
	_reaction_timer = maxf(delay, 0.05)
	if print_ai_decisions:
		print("AI Reaction scheduled | %.2fs" % _reaction_timer)


func _resolve_scheduled_reaction() -> void:
	_reaction_pending = false
	if not _can_think():
		return
	if player_attack_state.current_state not in [
		AttackStateType.AttackState.STARTUP,
		AttackStateType.AttackState.ACTIVE,
	]:
		if print_ai_decisions:
			print("AI Defense cancelled | player attack ended")
		return
	if not opponent_action_state.can_defend():
		return

	if randf() > difficulty.defensive_reaction_chance:
		if print_ai_decisions:
			print("AI Defense -> NONE (no reaction)")
		return

	var is_mistake := randf() < difficulty.mistake_chance
	var choice := _choose_defense(_reaction_attack, is_mistake)
	_apply_defense(choice, is_mistake)


func _choose_defense(_player_attack: int, is_mistake: bool) -> String:
	if is_mistake:
		var roll := randf()
		if roll < 0.34:
			return "NONE"
		if roll < 0.67:
			return "GUARD"
		return "SLIP_LEFT" if randf() < 0.5 else "SLIP_RIGHT"

	var evade_roll := randf()
	if evade_roll < difficulty.evade_chance:
		return "SLIP_LEFT" if randf() < 0.5 else "SLIP_RIGHT"
	if randf() < difficulty.guard_chance:
		return "GUARD"
	return "NONE"


func _apply_defense(choice: String, is_mistake: bool) -> void:
	match choice:
		"SLIP_LEFT":
			opponent_action_state.try_start_evasion(
				OpponentActionStateType.OpponentState.SLIP_LEFT
			)
		"SLIP_RIGHT":
			opponent_action_state.try_start_evasion(
				OpponentActionStateType.OpponentState.SLIP_RIGHT
			)
		"GUARD":
			opponent_action_state.set_guard_held(true)
			get_tree().create_timer(0.45).timeout.connect(
				func() -> void:
					if opponent_action_state != null:
						opponent_action_state.set_guard_held(false)
			)
		_:
			pass

	if print_ai_decisions:
		if is_mistake:
			print("AI Defense -> %s (MISTAKE)" % choice)
		else:
			print("AI Defense -> %s" % choice)


func _try_offense() -> void:
	if not opponent_attack_state.is_ready_for_command():
		_offense_cooldown = READY_POLL
		return
	if opponent_action_state != null:
		var action := opponent_action_state.current_state
		if action != OpponentActionStateType.OpponentState.IDLE:
			if action != OpponentActionStateType.OpponentState.ATTACKING:
				_offense_cooldown = READY_POLL
				return

	if _needs_post_recovery_pacing and not _follow_up_pending:
		_needs_post_recovery_pacing = false
		_roll_offense_cooldown(false)
		if print_ai_decisions:
			print("AI post-recovery pacing %.2fs" % _offense_cooldown)
		return

	if _follow_up_pending:
		_execute_follow_up()
		return

	if randf() > difficulty.aggression:
		_roll_offense_cooldown(false)
		return

	if opponent_stamina.current_stamina <= difficulty.low_stamina_threshold:
		if randf() < difficulty.low_stamina_wait_chance:
			if print_ai_decisions and not _logged_stamina_wait:
				print("AI waiting for stamina recovery")
				_logged_stamina_wait = true
			_roll_offense_cooldown(false)
			return

	var attack: AttackDataType = _pick_attack(false)
	if attack == null:
		if print_ai_decisions and not _logged_stamina_wait:
			print("AI waiting for stamina recovery")
			_logged_stamina_wait = true
		_roll_offense_cooldown(false)
		return

	_logged_stamina_wait = false
	if opponent_attack_state.try_execute_attack(attack.attack_type):
		_last_attack_type = attack.attack_type
		if print_ai_decisions:
			print(
				"AI Decision: ATTACK -> %s"
				% OpponentAttackStateType.ATTACK_NAMES[attack.attack_type]
			)
		_follow_up_used = false
		if _should_queue_follow_up():
			_queue_follow_up()
		else:
			_needs_post_recovery_pacing = true
			_offense_cooldown = READY_POLL
	else:
		_roll_offense_cooldown(false)


func _execute_follow_up() -> void:
	var attack: AttackDataType = _pick_follow_up_attack(_last_attack_type)
	if attack == null:
		if print_ai_decisions:
			print("AI follow-up cancelled (no affordable opposite/straight)")
		_follow_up_pending = false
		_needs_post_recovery_pacing = true
		_offense_cooldown = READY_POLL
		return

	if opponent_attack_state.try_execute_attack(attack.attack_type):
		_last_attack_type = attack.attack_type
		_follow_up_pending = false
		_follow_up_used = true
		_needs_post_recovery_pacing = true
		_offense_cooldown = READY_POLL
		if print_ai_decisions:
			print(
				"AI Decision: FOLLOW-UP -> %s"
				% OpponentAttackStateType.ATTACK_NAMES[attack.attack_type]
			)
	else:
		_follow_up_pending = false
		_needs_post_recovery_pacing = true
		_offense_cooldown = READY_POLL


func _should_queue_follow_up() -> bool:
	if _follow_up_used or _follow_up_pending:
		return false
	if difficulty == null:
		return false
	var chance := difficulty.follow_up_chance
	if chance <= 0.0:
		return false
	if opponent_stamina.current_stamina <= difficulty.low_stamina_threshold:
		chance *= 0.35
	return randf() < chance


func _queue_follow_up() -> void:
	_follow_up_pending = true
	_needs_post_recovery_pacing = false
	var minimum := difficulty.follow_up_delay_min
	var maximum := maxf(difficulty.follow_up_delay_max, minimum)
	_offense_cooldown = randf_range(minimum, maximum)
	if print_ai_decisions:
		print("AI follow-up armed (%.2fs)" % _offense_cooldown)


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


func _roll_offense_cooldown(initial: bool) -> void:
	var minimum := difficulty.attack_interval_min
	var maximum := maxf(difficulty.attack_interval_max, minimum)
	_offense_cooldown = randf_range(minimum, maximum)
	if initial:
		_offense_cooldown = minf(_offense_cooldown, maximum)


func _clear_pending_reaction() -> void:
	_reaction_pending = false
	_reaction_timer = 0.0


func clear_pending_combat_decisions() -> void:
	_clear_pending_reaction()
	_follow_up_pending = false
	_follow_up_used = false
	_needs_post_recovery_pacing = false
	_roll_offense_cooldown(false)
