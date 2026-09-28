class_name PlayerAttackState
extends Node

const AttackDataType = preload("res://scripts/attack_data.gd")
const PlayerStaminaType = preload("res://scripts/player_stamina.gd")
const HandReuseType = preload("res://scripts/hand_reuse.gd")

signal state_changed(state: AttackState, attack: int)
signal attack_rejected(requested_attack: int, current_attack: int)

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

@export var attacks: Array[AttackDataType] = []
@export var player_stamina: PlayerStaminaType
@export var hit_stun: Node
@export var same_hand_reuse_interval := HandReuseType.DEFAULT_INTERVAL

@export_group("Debug")
@export var print_action_speed := true

var current_state := AttackState.IDLE
var current_attack := -1

var _current_data: AttackDataType
var _time_remaining := 0.0
var _phase_duration := 0.0
## Bumped on every cancel / phase enter so stale overflow cannot revive a finished attack.
var _action_token := 0
## Snapshot at attack start (before stamina cost). Used for Startup/Recovery only.
var _action_speed_snapshot := 1.0
var _scaled_startup := 0.0
var _scaled_recovery := 0.0
var hand_reuse: HandReuseType = HandReuseType.new()


func get_action_speed_snapshot() -> float:
	return _action_speed_snapshot


func get_scaled_startup() -> float:
	return _scaled_startup


func get_scaled_recovery() -> float:
	return _scaled_recovery


func get_active_duration() -> float:
	if _current_data == null:
		return 0.0
	return _current_data.active_time


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_time_remaining -= delta

	while _time_remaining <= 0.0 and current_state != AttackState.IDLE:
		var overflow := -_time_remaining
		_advance_state()
		_time_remaining -= overflow


func try_start_attack(attack: int) -> bool:
	if _new_actions_locked():
		attack_rejected.emit(attack, current_attack)
		return false
	if not can_start_attack():
		attack_rejected.emit(attack, current_attack)
		return false
	if not is_hand_ready(attack):
		attack_rejected.emit(attack, current_attack)
		return false

	var attack_data := get_attack_data(attack)
	if attack_data == null:
		push_error("Attack data is missing for attack type %d." % attack)
		return false

	## Timing is attack-data only. Stamina does not slow Startup or Recovery.
	_action_speed_snapshot = 1.0
	_scaled_startup = attack_data.startup_time
	_scaled_recovery = attack_data.recovery_time

	_current_data = attack_data
	current_attack = attack
	_action_token += 1
	hand_reuse.note_started(attack)
	set_process(true)
	_enter_state(AttackState.STARTUP, _scaled_startup)

	if print_action_speed:
		print(
			"Player %s | Startup: %.2f | Recovery: %.2f"
			% [
				ATTACK_NAMES[attack],
				_scaled_startup,
				_scaled_recovery,
			]
		)
	return true


func is_hand_ready(attack: int) -> bool:
	hand_reuse.interval = same_hand_reuse_interval
	return hand_reuse.is_ready(attack)


func can_start_attack() -> bool:
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	return current_state == AttackState.IDLE


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


## Ends Startup/Active/Recovery cleanly so a buffered next action can start.
## Recovery itself is not deleted — this is an early exit at cancel time.
func force_end_for_cancel() -> void:
	cancel_attack()


func cancel_attack() -> void:
	if current_state == AttackState.IDLE:
		return

	_action_token += 1
	current_attack = -1
	_current_data = null
	_action_speed_snapshot = 1.0
	_scaled_startup = 0.0
	_scaled_recovery = 0.0
	_phase_duration = 0.0
	set_process(false)
	_enter_state(AttackState.IDLE, 0.0)


func _advance_state() -> void:
	var token := _action_token
	match current_state:
		AttackState.STARTUP:
			if token != _action_token or _current_data == null:
				return
			## Active hit window stays at base duration.
			_enter_state(AttackState.ACTIVE, _current_data.active_time)
		AttackState.ACTIVE:
			if token != _action_token:
				return
			_enter_state(AttackState.RECOVERY, _scaled_recovery)
		AttackState.RECOVERY:
			if token != _action_token:
				return
			current_attack = -1
			_current_data = null
			_action_speed_snapshot = 1.0
			set_process(false)
			_enter_state(AttackState.IDLE, 0.0)


func _enter_state(next_state: AttackState, duration: float) -> void:
	current_state = next_state
	_phase_duration = maxf(duration, 0.0)
	_time_remaining = _phase_duration
	state_changed.emit(current_state, current_attack)


func get_attack_data(attack: int) -> AttackDataType:
	for attack_data in attacks:
		if attack_data.attack_type == attack:
			return attack_data

	return null


func _new_actions_locked() -> bool:
	if not is_inside_tree():
		return false
	var knockdown := get_node_or_null("../KnockdownManager")
	return knockdown != null and knockdown.has_method("new_actions_locked") and knockdown.new_actions_locked()
