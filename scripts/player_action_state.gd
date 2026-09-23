class_name PlayerActionState
extends Node

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")
const PlayerStaminaType = preload("res://scripts/player_stamina.gd")
const ActionSpeedSettingsType = preload("res://scripts/action_speed_settings.gd")

signal state_changed(state: PlayerState)
signal evasion_phase_changed(evasion: PlayerState, phase: EvasionPhase)

enum PlayerState {
	IDLE,
	ATTACKING,
	SLIP_LEFT,
	SLIP_RIGHT,
	GUARD,
}

enum EvasionPhase {
	NONE,
	EVADING,
	## Post-window lockout only (not a successful evade window).
	RECOVERY,
}

const STATE_NAMES := [
	"Idle",
	"Attacking",
	"Slip Left",
	"Slip Right",
	"Guard",
]
const EVASION_PHASE_NAMES := [
	"None",
	"Evading",
	"Recovery",
]

@export var attack_state: AttackStateType
@export var player_stamina: PlayerStaminaType
@export var action_speed_settings: ActionSpeedSettingsType
@export var hit_stun: Node

@export_group("Evasion Timing")
## Valid evade window (not lengthened by fatigue).
@export_range(0.0, 10.0, 0.01, "or_greater") var slip_duration := 0.18

@export_group("Debug")
@export var print_state_changes := true
@export var print_action_speed := false

var current_state := PlayerState.IDLE
var current_evasion_phase := EvasionPhase.NONE

var _guard_held := false
var _phase_time_remaining := 0.0
var _evade_window_remaining := 0.0
var _post_evade_lock_remaining := 0.0


func _ready() -> void:
	assert(attack_state != null, "PlayerActionState requires an attack state.")
	if action_speed_settings == null:
		action_speed_settings = ActionSpeedSettingsType.new()
	attack_state.state_changed.connect(_on_attack_state_changed)
	set_process(false)

	if print_state_changes:
		print("[PlayerState] %s" % STATE_NAMES[current_state])


func _process(delta: float) -> void:
	_phase_time_remaining -= delta

	if current_evasion_phase == EvasionPhase.EVADING:
		_evade_window_remaining -= delta
		if _evade_window_remaining <= 0.0:
			if _post_evade_lock_remaining > 0.0:
				## Evade window closed; remaining time is locked but not evade-valid.
				_enter_evasion_phase(EvasionPhase.RECOVERY, _post_evade_lock_remaining)
			else:
				_finish_evasion()
		return

	if current_evasion_phase == EvasionPhase.RECOVERY and _phase_time_remaining <= 0.0:
		_finish_evasion()


func can_attack() -> bool:
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	return current_state == PlayerState.IDLE


func try_start_evasion(evasion: int) -> bool:
	if hit_stun != null and hit_stun.is_hit_stunned():
		return false
	if current_state != PlayerState.IDLE:
		return false

	var next_state := _defense_to_player_state(evasion)
	if next_state == PlayerState.IDLE:
		return false

	var base_window := slip_duration
	var stamina_now := (
		player_stamina.current_stamina if player_stamina != null else 100.0
	)
	var action_speed := action_speed_settings.calculate_action_speed(stamina_now)
	var total_lock := action_speed_settings.scale_duration(base_window, action_speed)
	## Evade-valid window stays at base; fatigue only extends post-window lockout.
	_evade_window_remaining = base_window
	_post_evade_lock_remaining = maxf(total_lock - base_window, 0.0)

	_enter_state(next_state)
	_enter_evasion_phase(EvasionPhase.EVADING, base_window)
	set_process(true)

	if print_action_speed:
		print(
			"Player %s | Stamina: %.0f | Action Speed: %.2f | Evade Window: %.2f | Lock: %.2f"
			% [
				STATE_NAMES[next_state],
				stamina_now,
				action_speed,
				base_window,
				total_lock,
			]
		)
	return true


func set_guard_held(is_held: bool) -> void:
	if hit_stun != null and hit_stun.is_hit_stunned():
		if not is_held:
			_guard_held = false
		return

	_guard_held = is_held

	if is_held and current_state == PlayerState.IDLE:
		_enter_state(PlayerState.GUARD)
	elif not is_held and current_state == PlayerState.GUARD:
		_enter_state(PlayerState.IDLE)


func is_evading() -> bool:
	return current_state in [
		PlayerState.SLIP_LEFT,
		PlayerState.SLIP_RIGHT,
	]


func is_evasion_active() -> bool:
	## Only the fixed base window counts for HIT/BLOCK/EVADE resolution.
	return is_evading() and current_evasion_phase == EvasionPhase.EVADING


func get_current_evasion() -> PlayerState:
	return current_state if is_evading() else PlayerState.IDLE


func is_guarding() -> bool:
	return current_state == PlayerState.GUARD


func force_reset_to_idle() -> void:
	_guard_held = false
	current_evasion_phase = EvasionPhase.NONE
	_phase_time_remaining = 0.0
	_evade_window_remaining = 0.0
	_post_evade_lock_remaining = 0.0
	set_process(false)
	if current_state != PlayerState.IDLE:
		_enter_state(PlayerState.IDLE)


func _on_attack_state_changed(state: int, _attack: int) -> void:
	if state == AttackStateType.AttackState.IDLE:
		if current_state == PlayerState.ATTACKING:
			_finish_locked_action()
	elif current_state == PlayerState.IDLE:
		_enter_state(PlayerState.ATTACKING)


func _finish_evasion() -> void:
	current_evasion_phase = EvasionPhase.NONE
	_evade_window_remaining = 0.0
	_post_evade_lock_remaining = 0.0
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
		_:
			return PlayerState.IDLE
