class_name OpponentActionState
extends Node

## Lightweight opponent defense/evade state driven by OpponentAI.

const ActionSpeedSettingsType = preload("res://scripts/action_speed_settings.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")

signal state_changed(state: OpponentState)
signal evasion_phase_changed(state: OpponentState, phase: EvasionPhase)

enum OpponentState {
	IDLE,
	ATTACKING,
	SLIP_LEFT,
	SLIP_RIGHT,
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
	"Guard",
]

@export var attack_state: OpponentAttackStateType
@export var opponent_stamina: OpponentStaminaType
@export var action_speed_settings: ActionSpeedSettingsType
@export var hit_stun: Node

@export_group("Evasion Timing")
@export_range(0.0, 10.0, 0.01, "or_greater") var slip_duration := 0.22

@export_group("Debug")
@export var print_state_changes := false

var current_state := OpponentState.IDLE
var current_evasion_phase := EvasionPhase.NONE

var _guard_held := false
var _phase_time_remaining := 0.0
var _evade_window_remaining := 0.0
var _post_evade_lock_remaining := 0.0


func _ready() -> void:
	if action_speed_settings == null:
		action_speed_settings = ActionSpeedSettingsType.new()
	if attack_state != null:
		attack_state.state_changed.connect(_on_attack_state_changed)
	set_process(false)


func _process(delta: float) -> void:
	_phase_time_remaining -= delta

	if current_evasion_phase == EvasionPhase.EVADING:
		_evade_window_remaining -= delta
		if _evade_window_remaining <= 0.0:
			if _post_evade_lock_remaining > 0.0:
				_enter_evasion_phase(EvasionPhase.RECOVERY, _post_evade_lock_remaining)
			else:
				_finish_evasion()
		return

	if current_evasion_phase == EvasionPhase.RECOVERY and _phase_time_remaining <= 0.0:
		_finish_evasion()


func can_defend() -> bool:
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	return current_state == OpponentState.IDLE


func try_start_evasion(evasion: OpponentState) -> bool:
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	if not can_defend():
		return false
	if evasion not in [OpponentState.SLIP_LEFT, OpponentState.SLIP_RIGHT]:
		return false

	var base_window := slip_duration
	var stamina_now := (
		opponent_stamina.current_stamina if opponent_stamina != null else 100.0
	)
	var action_speed := action_speed_settings.calculate_action_speed(stamina_now)
	var total_lock := action_speed_settings.scale_duration(base_window, action_speed)
	_evade_window_remaining = base_window
	_post_evade_lock_remaining = maxf(total_lock - base_window, 0.0)

	_guard_held = false
	_enter_state(evasion)
	_enter_evasion_phase(EvasionPhase.EVADING, base_window)
	set_process(true)
	return true


func set_guard_held(is_held: bool) -> void:
	## Hold-only. No post-lock after release (AI decision cadence is separate).
	if hit_stun != null and hit_stun.is_hit_stunned():
		if not is_held:
			_guard_held = false
		return
	_guard_held = is_held
	if is_held and current_state == OpponentState.IDLE:
		_enter_state(OpponentState.GUARD)
	elif not is_held and current_state == OpponentState.GUARD:
		_enter_state(OpponentState.IDLE)


func is_evading() -> bool:
	return current_state in [
		OpponentState.SLIP_LEFT,
		OpponentState.SLIP_RIGHT,
	]


func is_evasion_active() -> bool:
	return is_evading() and current_evasion_phase == EvasionPhase.EVADING


func get_current_evasion() -> OpponentState:
	return current_state if is_evading() else OpponentState.IDLE


func is_guarding() -> bool:
	return current_state == OpponentState.GUARD


func force_reset_to_idle() -> void:
	_guard_held = false
	current_evasion_phase = EvasionPhase.NONE
	_phase_time_remaining = 0.0
	_evade_window_remaining = 0.0
	_post_evade_lock_remaining = 0.0
	set_process(false)
	if current_state != OpponentState.IDLE:
		_enter_state(OpponentState.IDLE)


func _on_attack_state_changed(state: int, _attack_data) -> void:
	if state == OpponentAttackStateType.AttackState.IDLE:
		if current_state == OpponentState.ATTACKING:
			_enter_state(OpponentState.GUARD if _guard_held else OpponentState.IDLE)
	elif current_state == OpponentState.IDLE:
		_enter_state(OpponentState.ATTACKING)


func _finish_evasion() -> void:
	current_evasion_phase = EvasionPhase.NONE
	_evade_window_remaining = 0.0
	_post_evade_lock_remaining = 0.0
	set_process(false)
	evasion_phase_changed.emit(current_state, current_evasion_phase)
	_enter_state(OpponentState.GUARD if _guard_held else OpponentState.IDLE)


func _enter_state(next_state: OpponentState) -> void:
	if current_state == next_state:
		return
	current_state = next_state
	state_changed.emit(current_state)
	if print_state_changes:
		print("[OpponentState] %s" % STATE_NAMES[current_state])


func _enter_evasion_phase(next_phase: EvasionPhase, duration: float) -> void:
	current_evasion_phase = next_phase
	_phase_time_remaining = duration
	evasion_phase_changed.emit(current_state, current_evasion_phase)
