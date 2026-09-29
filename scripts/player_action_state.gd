class_name PlayerActionState
extends Node

## Player exclusive combat states: IDLE / ATTACKING / GUARD.
## Continuous Evade Movement + Timing live on PlayerEvade (not exclusive states).

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const PlayerStaminaType = preload("res://scripts/player_stamina.gd")

signal state_changed(state: PlayerState)

enum PlayerState {
	IDLE,
	ATTACKING,
	GUARD,
}

const STATE_NAMES := [
	"Idle",
	"Attacking",
	"Guard",
]

@export var attack_state: AttackStateType
@export var player_stamina: PlayerStaminaType
@export var hit_stun: Node

@export_group("Debug")
@export var print_state_changes := true

var current_state := PlayerState.IDLE
var _guard_held := false


func _ready() -> void:
	assert(attack_state != null, "PlayerActionState requires an attack state.")
	attack_state.state_changed.connect(_on_attack_state_changed)

	if print_state_changes:
		print("[PlayerState] %s" % STATE_NAMES[current_state])


func can_attack() -> bool:
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	return current_state == PlayerState.IDLE


func set_guard_held(is_held: bool) -> void:
	## High Guard is a pure hold: ON while held, OFF immediately on release.
	if hit_stun != null and hit_stun.is_hit_stunned():
		if not is_held:
			_guard_held = false
		return

	if is_held and _new_actions_locked():
		return

	_guard_held = is_held

	if is_held and current_state == PlayerState.IDLE:
		_enter_state(PlayerState.GUARD)
	elif not is_held and current_state == PlayerState.GUARD:
		_enter_state(PlayerState.IDLE)


func is_guarding() -> bool:
	return current_state == PlayerState.GUARD


func is_guard_held() -> bool:
	return _guard_held


## Compatibility: Continuous Evade is not an exclusive action state.
func is_evading() -> bool:
	return false


func force_reset_to_idle() -> void:
	_guard_held = false
	if current_state != PlayerState.IDLE:
		_enter_state(PlayerState.IDLE)


func _on_attack_state_changed(state: int, _attack: int) -> void:
	if state == AttackStateType.AttackState.IDLE:
		if current_state == PlayerState.ATTACKING:
			_finish_locked_action()
	elif current_state == PlayerState.IDLE:
		_enter_state(PlayerState.ATTACKING)


func _finish_locked_action() -> void:
	_enter_state(PlayerState.GUARD if _guard_held else PlayerState.IDLE)


func _enter_state(next_state: PlayerState) -> void:
	if current_state == next_state:
		return

	var previous_state := current_state
	current_state = next_state
	state_changed.emit(current_state)

	if print_state_changes:
		print(
			"[PlayerState] %s -> %s"
			% [STATE_NAMES[previous_state], STATE_NAMES[current_state]]
		)


func _new_actions_locked() -> bool:
	if not is_inside_tree():
		return false
	var knockdown = get_node_or_null("../KnockdownManager")
	return knockdown != null and knockdown.has_method("new_actions_locked") and knockdown.new_actions_locked()
