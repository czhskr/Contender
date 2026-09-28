class_name OpponentAttackState
extends Node

## Executes opponent attacks. Selection is owned by OpponentAI.

const AttackDataType = preload("res://scripts/opponent_attack_data.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const HandReuseType = preload("res://scripts/hand_reuse.gd")

signal state_changed(state: AttackState, attack_data: AttackDataType)
signal attack_active(attack_data: AttackDataType)
signal attack_started(attack_data: AttackDataType)

enum AttackState {
	IDLE,
	STARTUP,
	ACTIVE,
	RECOVERY,
}

const ATTACK_NAMES := [
	"Left Straight",
	"Right Straight",
	"Left Hook",
	"Right Hook",
]
const SIDE_NAMES := ["Left", "Right"]

@export var attacks: Array[AttackDataType] = []
@export var opponent_stamina: OpponentStaminaType
@export var hit_stun: Node
@export var same_hand_reuse_interval := HandReuseType.DEFAULT_INTERVAL
@export_group("Timing")
## Match-start gate only. Post-recovery pacing is owned by OpponentAI.
@export_range(0.0, 30.0, 0.05, "or_greater") var initial_ready_delay := 1.0
## Extra IDLE gate after Recovery. Keep at 0. Combo timing comes from recovery cancel and hand reuse.
@export_range(0.0, 30.0, 0.05, "or_greater") var attack_cooldown := 0.0
@export_group("Debug")
@export var print_attack_start := false
@export var print_action_speed := false

var current_state := AttackState.IDLE
var current_attack: AttackDataType
var combat_enabled := true

var _time_remaining := 0.0
var _phase_duration := 0.0
var _action_token := 0
var _action_speed_snapshot := 1.0
var _scaled_startup := 0.0
var _scaled_recovery := 0.0
var _ready_gate := true
var hand_reuse: HandReuseType = HandReuseType.new()


func get_action_speed_snapshot() -> float:
	return _action_speed_snapshot


func get_scaled_startup() -> float:
	return _scaled_startup


func get_scaled_recovery() -> float:
	return _scaled_recovery


func get_active_duration() -> float:
	if current_attack == null:
		return 0.0
	return current_attack.active_time


func _ready() -> void:
	if attacks.is_empty():
		push_error("OpponentAttackState requires at least one attack.")
		set_process(false)
		return
	if opponent_stamina == null:
		push_error("OpponentAttackState requires opponent stamina.")
		set_process(false)
		return

	_time_remaining = initial_ready_delay
	_ready_gate = true


func _process(delta: float) -> void:
	if not combat_enabled:
		return

	_time_remaining -= delta
	var token := _action_token

	while _time_remaining <= 0.0 and current_state != AttackState.IDLE:
		if token != _action_token:
			return
		var overflow := -_time_remaining
		match current_state:
			AttackState.STARTUP:
				_enter_state(AttackState.ACTIVE, current_attack.active_time)
				attack_active.emit(current_attack)
			AttackState.ACTIVE:
				_enter_state(AttackState.RECOVERY, _scaled_recovery)
			AttackState.RECOVERY:
				current_attack = null
				_action_speed_snapshot = 1.0
				_enter_state(AttackState.IDLE, attack_cooldown)
				_ready_gate = true
		_time_remaining -= overflow
		token = _action_token

	if current_state == AttackState.IDLE and _time_remaining < 0.0:
		_time_remaining = 0.0


func is_recovering() -> bool:
	return current_state == AttackState.RECOVERY


func get_recovery_progress() -> float:
	if current_state != AttackState.RECOVERY:
		return 0.0
	if _phase_duration <= 0.0:
		return 1.0
	return clampf(1.0 - (_time_remaining / _phase_duration), 0.0, 1.0)


func get_action_token() -> int:
	return _action_token


## Early exit from Startup/Active/Recovery so AI can chain via cancel window.
func force_end_for_cancel() -> void:
	if current_state == AttackState.IDLE:
		return
	_action_token += 1
	current_attack = null
	_action_speed_snapshot = 1.0
	_scaled_startup = 0.0
	_scaled_recovery = 0.0
	_phase_duration = 0.0
	_ready_gate = true
	_enter_state(AttackState.IDLE, 0.0)


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	if enabled and current_state == AttackState.IDLE:
		_time_remaining = attack_cooldown
		_ready_gate = true


func cancel_and_disable() -> void:
	combat_enabled = false
	_action_token += 1
	current_attack = null
	_action_speed_snapshot = 1.0
	_ready_gate = false
	_phase_duration = 0.0
	_enter_state(AttackState.IDLE, 0.0)


## Cancel current punch without toggling combat_enabled (Hit Stun cancel).
func cancel_attack() -> void:
	if current_state == AttackState.IDLE:
		return
	_action_token += 1
	current_attack = null
	_action_speed_snapshot = 1.0
	_scaled_startup = 0.0
	_scaled_recovery = 0.0
	_phase_duration = 0.0
	_ready_gate = true
	_enter_state(AttackState.IDLE, attack_cooldown)


func is_hand_ready(attack_type: int) -> bool:
	hand_reuse.interval = same_hand_reuse_interval
	return hand_reuse.is_ready(attack_type)


func is_ready_for_command() -> bool:
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	return (
		combat_enabled
		and current_state == AttackState.IDLE
		and _time_remaining <= 0.0
		and _ready_gate
	)


func get_attack_data(attack_type: int) -> AttackDataType:
	for attack in attacks:
		if attack.attack_type == attack_type:
			return attack
	return null


func get_affordable_attacks() -> Array[AttackDataType]:
	var result: Array[AttackDataType] = []
	for attack in attacks:
		if opponent_stamina.can_afford(_effective_cost(attack.stamina_cost)):
			result.append(attack)
	return result


## AI entry point. Snapshot speed BEFORE stamina cost.
func try_execute_attack(attack_type: int) -> bool:
	if _new_actions_locked():
		return false
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	if not is_ready_for_command():
		return false

	var attack := get_attack_data(attack_type)
	if attack == null:
		return false
	if not opponent_stamina.can_afford(_effective_cost(attack.stamina_cost)):
		return false
	if not is_hand_ready(attack_type):
		return false

	_action_speed_snapshot = 1.0
	_scaled_startup = attack.startup_time
	_scaled_recovery = attack.recovery_time

	if not opponent_stamina.spend_for_attack(_effective_cost(attack.stamina_cost)):
		_action_speed_snapshot = 1.0
		return false

	current_attack = attack
	_ready_gate = false
	_action_token += 1
	hand_reuse.note_started(attack_type)
	_enter_state(AttackState.STARTUP, _scaled_startup)
	attack_started.emit(attack)

	if print_attack_start:
		print(
			"Opponent %s | Cost: %.0f | Stamina: %.0f"
			% [
				ATTACK_NAMES[attack.attack_type],
				attack.stamina_cost,
				opponent_stamina.current_stamina,
			]
		)
	if print_action_speed:
		print(
			"Opponent %s | Startup: %.2f | Recovery: %.2f"
			% [
				ATTACK_NAMES[attack.attack_type],
				_scaled_startup,
				_scaled_recovery,
			]
		)
	return true


func _effective_cost(base_cost: float) -> float:
	if not is_inside_tree():
		return base_cost
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager == null:
		return base_cost
	return preload("res://scripts/trait_math.gd").attack_cost(base_cost, manager.opponent_traits)


func _enter_state(next_state: AttackState, duration: float) -> void:
	current_state = next_state
	_phase_duration = maxf(duration, 0.0)
	_time_remaining = _phase_duration
	state_changed.emit(current_state, current_attack)


func _new_actions_locked() -> bool:
	if not is_inside_tree():
		return false
	var knockdown := get_node_or_null("../KnockdownManager")
	return knockdown != null and knockdown.has_method("new_actions_locked") and knockdown.new_actions_locked()
