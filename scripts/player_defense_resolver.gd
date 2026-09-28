class_name PlayerDefenseResolver
extends Node

## Resolves opponent attacks vs player defense. Applies Knockdown Meter damage.

const ActionStateType = preload("res://scripts/player_action_state.gd")
const AttackDataType = preload("res://scripts/opponent_attack_data.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")

signal attack_resolved(
	result: DefenseResult,
	knockdown_damage: float,
	player_meter: float,
	was_knockdown: bool
)
signal player_knockdown(attack_type: int)

enum DefenseResult {
	HIT,
	BLOCK,
	EVADE,
}

const RESULT_NAMES := ["HIT", "BLOCK", "EVADE"]
const ATTACK_NAMES := [
	"Left Straight",
	"Right Straight",
	"Left Hook",
	"Right Hook",
]

@export var player_action_state: ActionStateType
@export var player_evade: Node
@export var player_knockdown_meter: KnockdownMeterType
@export var opponent_attack_state: Node

@export_group("Guard Knockdown Damage")
@export_range(0.0, 1.0, 0.05) var guard_knockdown_damage_multiplier := 0.25

@export_group("Hit Resolve")
@export var hit_resolve_coordinator: Node

@export_group("Debug")
@export var print_hit_results := true

## False while knockdown/round freeze owns combat.
var meter_updates_enabled := true


func _ready() -> void:
	assert(
		player_action_state != null,
		"PlayerDefenseResolver requires a player action state."
	)
	assert(player_knockdown_meter != null, "PlayerDefenseResolver requires KD meter.")
	if opponent_attack_state != null and opponent_attack_state.has_signal("attack_active"):
		opponent_attack_state.attack_active.connect(_on_opponent_attack_active)


func _on_opponent_attack_active(attack_data: AttackDataType) -> void:
	if hit_resolve_coordinator != null and hit_resolve_coordinator.has_method("queue_opponent_active"):
		hit_resolve_coordinator.queue_opponent_active(attack_data)
	else:
		resolve_attack(attack_data)


func resolve_attack(attack_data: AttackDataType) -> void:
	var result := DefenseResult.HIT
	var raw_kd: float = attack_data.knockdown_damage

	if _does_evasion_avoid_attack(attack_data):
		result = DefenseResult.EVADE
		raw_kd = 0.0
	elif player_action_state.is_guarding():
		result = DefenseResult.BLOCK
		raw_kd *= guard_knockdown_damage_multiplier

	var applied := 0.0
	var was_knockdown := false
	if meter_updates_enabled and raw_kd > 0.0:
		applied = player_knockdown_meter.apply_knockdown_damage(raw_kd)
		if player_knockdown_meter.is_full():
			was_knockdown = true
			player_knockdown.emit(attack_data.attack_type)

	attack_resolved.emit(
		result,
		applied,
		player_knockdown_meter.current_meter,
		was_knockdown
	)

	if print_hit_results:
		print(
			"Opponent %s -> %s | KD Damage: %.1f | Player KD: %.0f/%.0f"
			% [
				ATTACK_NAMES[attack_data.attack_type],
				RESULT_NAMES[result],
				applied,
				player_knockdown_meter.current_meter,
				player_knockdown_meter.max_meter,
			]
		)
		if was_knockdown:
			print("Player Knockdown (KD Meter full)")


func _does_evasion_avoid_attack(_attack_data: AttackDataType) -> bool:
	## Continuous Evade: gameplay window only (PlayerEvade), not exclusive slip states.
	if player_evade != null and player_evade.has_method("is_window_active"):
		return player_evade.is_window_active()
	return false
