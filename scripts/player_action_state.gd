class_name PlayerActionState
extends Node

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")

signal state_changed(state: PlayerState)
signal evasion_phase_changed(evasion: PlayerState, phase: EvasionPhase)

enum PlayerState {
	IDLE,
	ATTACKING,
	SLIP_LEFT,
	SLIP_RIGHT,
	DUCK,
	GUARD,
}

enum EvasionPhase {
	NONE,
	EVADING,
	RECOVERY,
}

const STATE_NAMES := [
	"Idle",
	"Attacking",
	"Slip Left",
	"Slip Right",
	"Duck",
	"Guard",
]
const EVASION_PHASE_NAMES := [
	"None",
	"Evading",
	"Recovery",
]

@export var attack_state: AttackStateType

@export_group("Evasion Timing")
@export_range(0.0, 10.0, 0.01, "or_greater") var slip_duration := 0.18
@export_range(0.0, 10.0, 0.01, "or_greater") var duck_duration := 0.24
@export_range(0.0, 10.0, 0.01, "or_greater") var evasion_recovery := 0.12

@export_group("Debug")
@export var print_state_changes := true

var current_state := PlayerState.IDLE
var current_evasion_phase := EvasionPhase.NONE

var _guard_held := false
var _phase_time_remaining := 0.0


func _ready() -> void:
	assert(attack_state != null, "PlayerActionState requires an attack state.")
	attack_state.state_changed.connect(_on_attack_state_changed)
	set_process(false)

	if print_state_changes:
		print("[PlayerState] %s" % STATE_NAMES[current_state])


func _process(delta: float) -> void:
	_phase_time_remaining -= delta

	while _phase_time_remaining <= 0.0 and is_evading():
		var overflow := -_phase_time_remaining

		if current_evasion_phase == EvasionPhase.EVADING:
			_enter_evasion_phase(EvasionPhase.RECOVERY, evasion_recovery)
			_phase_time_remaining -= overflow
		elif current_evasion_phase == EvasionPhase.RECOVERY:
			_finish_evasion()


func can_attack() -> bool:
	return current_state == PlayerState.IDLE


func try_start_evasion(evasion: int) -> bool:
	if current_state != PlayerState.IDLE:
		return false

	var next_state := _defense_to_player_state(evasion)
	if next_state == PlayerState.IDLE:
		return false

	var duration := duck_duration if next_state == PlayerState.DUCK else slip_duration
	_enter_state(next_state)
	_enter_evasion_phase(EvasionPhase.EVADING, duration)
	set_process(true)
	return true


func set_guard_held(is_held: bool) -> void:
	_guard_held = is_held

	if is_held and current_state == PlayerState.IDLE:
		_enter_state(PlayerState.GUARD)
	elif not is_held and current_state == PlayerState.GUARD:
		_enter_state(PlayerState.IDLE)


func is_evading() -> bool:
	return current_state in [
		PlayerState.SLIP_LEFT,
		PlayerState.SLIP_RIGHT,
		PlayerState.DUCK,
	]


func is_evasion_active() -> bool:
	return is_evading() and current_evasion_phase == EvasionPhase.EVADING


func get_current_evasion() -> PlayerState:
	return current_state if is_evading() else PlayerState.IDLE


func is_guarding() -> bool:
	return current_state == PlayerState.GUARD


func _on_attack_state_changed(state: int, _attack: int) -> void:
	if state == AttackStateType.AttackState.IDLE:
		if current_state == PlayerState.ATTACKING:
			_finish_locked_action()
	elif current_state == PlayerState.IDLE:
		_enter_state(PlayerState.ATTACKING)


func _finish_evasion() -> void:
	current_evasion_phase = EvasionPhase.NONE
	set_process(false)
	evasion_phase_changed.emit(current_state, current_evasion_phase)
	_finish_locked_action()


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


func _enter_evasion_phase(next_phase: EvasionPhase, duration: float) -> void:
	current_evasion_phase = next_phase
	_phase_time_remaining = duration
	evasion_phase_changed.emit(current_state, current_evasion_phase)

	if print_state_changes:
		print(
			"[PlayerState] %s phase: %s"
			% [STATE_NAMES[current_state], EVASION_PHASE_NAMES[current_evasion_phase]]
		)


func _defense_to_player_state(defense: int) -> PlayerState:
	match defense:
		CombatInputType.DefenseType.SLIP_LEFT:
			return PlayerState.SLIP_LEFT
		CombatInputType.DefenseType.SLIP_RIGHT:
			return PlayerState.SLIP_RIGHT
		CombatInputType.DefenseType.DUCK:
			return PlayerState.DUCK
		_:
			return PlayerState.IDLE
