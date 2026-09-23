class_name PlayerOffenseResolver
extends Node

## Resolves player attack hits vs opponent defense. Applies Knockdown Meter damage.

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")
const OpponentActionStateType = preload("res://scripts/opponent_action_state.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")

signal attack_hit(
	attack: int,
	knockdown_damage: float,
	opponent_meter: float,
	was_knockdown: bool,
	result: int
)
signal opponent_knockdown(attack: int)

enum ResolveResult {
	HIT,
	BLOCK,
	EVADE,
}

const ATTACK_NAMES := [
	"Left Straight",
	"Right Straight",
	"Left Hook",
	"Right Hook",
]
const RESULT_NAMES := ["HIT", "BLOCK", "EVADE"]

@export var player_attack_state: AttackStateType
@export var opponent_action_state: OpponentActionStateType
@export var opponent_knockdown_meter: KnockdownMeterType

@export_group("Guard Knockdown Damage")
@export_range(0.0, 1.0, 0.05) var guard_knockdown_damage_multiplier := 0.25

@export_group("Hit Resolve")
@export var hit_resolve_coordinator: Node

@export_group("Debug")
@export var print_hit_results := true

## False while knockdown/round freeze owns combat.
var meter_updates_enabled := true
var _resolved_for_current_attack := false


func _ready() -> void:
	assert(player_attack_state != null)
	assert(opponent_knockdown_meter != null)
	player_attack_state.state_changed.connect(_on_player_attack_state_changed)


func _on_player_attack_state_changed(state: int, attack: int) -> void:
	if state == AttackStateType.AttackState.STARTUP:
		_resolved_for_current_attack = false
		return
	if state != AttackStateType.AttackState.ACTIVE:
		return
	if _resolved_for_current_attack:
		return
	_resolved_for_current_attack = true
	if (
		hit_resolve_coordinator != null
		and hit_resolve_coordinator.has_method("queue_player_active")
	):
		hit_resolve_coordinator.queue_player_active(attack)
	else:
		_resolve_hit(attack)


func resolve_hit_now(attack: int) -> void:
	_resolve_hit(attack)


func _resolve_hit(attack: int) -> void:
	var attack_data = player_attack_state.get_attack_data(attack)
	if attack_data == null:
		push_error("Attack data is missing for attack type %d." % attack)
		return

	var result := ResolveResult.HIT
	var raw_kd: float = attack_data.knockdown_damage

	if _does_opponent_evade(attack):
		result = ResolveResult.EVADE
		raw_kd = 0.0
	elif opponent_action_state != null and opponent_action_state.is_guarding():
		result = ResolveResult.BLOCK
		raw_kd *= guard_knockdown_damage_multiplier

	var applied := 0.0
	var was_knockdown := false
	if meter_updates_enabled and raw_kd > 0.0:
		applied = opponent_knockdown_meter.apply_knockdown_damage(raw_kd)
		if opponent_knockdown_meter.is_full():
			was_knockdown = true
			opponent_knockdown.emit(attack)

	attack_hit.emit(
		attack,
		applied,
		opponent_knockdown_meter.current_meter,
		was_knockdown,
		result
	)

	if print_hit_results:
		print(
			"Player %s -> %s | KD Damage: %.1f | Opp KD: %.0f/%.0f"
			% [
				ATTACK_NAMES[attack],
				RESULT_NAMES[result],
				applied,
				opponent_knockdown_meter.current_meter,
				opponent_knockdown_meter.max_meter,
			]
		)
		if was_knockdown:
			print("Opponent Knockdown (KD Meter full)")


func _does_opponent_evade(attack: int) -> bool:
	if opponent_action_state == null or not opponent_action_state.is_evasion_active():
		return false
	var evasion := opponent_action_state.get_current_evasion()
	## Slip Left / Slip Right avoid Straights and Hooks.
	return evasion in [
		OpponentActionStateType.OpponentState.SLIP_LEFT,
		OpponentActionStateType.OpponentState.SLIP_RIGHT,
	]
