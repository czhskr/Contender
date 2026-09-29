class_name PlayerDefenseResolver
extends Node

## Resolves opponent attacks vs player defense. Applies Knockdown Meter damage.

const ActionStateType = preload("res://scripts/player_action_state.gd")
const AttackDataType = preload("res://scripts/opponent_attack_data.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")
const VulnerabilityType = preload("res://scripts/knockdown_vulnerability.gd")
const PlayerStaminaType = preload("res://scripts/player_stamina.gd")

signal attack_resolved(
	result: DefenseResult,
	knockdown_damage: float,
	player_meter: float,
	was_knockdown: bool
)
signal player_knockdown(attack_type: int)
signal block_guard_broken

enum DefenseResult {
	HIT,
	BLOCK,
	EVADE,
}

const RESULT_NAMES := ["HIT", "BLOCK", "EVADE"]
const BLOCK_STAMINA_COST_SCALE := 2.0
const ATTACK_NAMES := [
	"Left Straight",
	"Right Straight",
	"Left Hook",
	"Right Hook",
]

@export var player_action_state: ActionStateType
@export var player_evade: Node
@export var player_knockdown_meter: KnockdownMeterType
@export var player_stamina: PlayerStaminaType
@export var knockdown_vulnerability: VulnerabilityType
@export var opponent_attack_state: Node

@export_group("Guard Knockdown Damage")
@export_range(0.0, 1.0, 0.05) var guard_knockdown_damage_multiplier := 0.25

@export_group("Hit Resolve")
@export var hit_resolve_coordinator: Node

@export_group("Debug")
@export var print_hit_results := true

## False while knockdown/round freeze owns combat.
var meter_updates_enabled := true
var _resolved_token := -1


func _ready() -> void:
	assert(
		player_action_state != null,
		"PlayerDefenseResolver requires a player action state."
	)
	assert(player_knockdown_meter != null, "PlayerDefenseResolver requires KD meter.")
	if player_stamina == null:
		player_stamina = get_node_or_null("../PlayerStamina")
	if knockdown_vulnerability == null:
		knockdown_vulnerability = VulnerabilityType.new()
	if opponent_attack_state != null and opponent_attack_state.has_signal("attack_active"):
		opponent_attack_state.attack_active.connect(_on_opponent_attack_active)


func _on_opponent_attack_active(attack_data: AttackDataType) -> void:
	if hit_resolve_coordinator != null and hit_resolve_coordinator.has_method("queue_opponent_active"):
		hit_resolve_coordinator.queue_opponent_active(attack_data)
	else:
		resolve_attack(attack_data)


func resolve_attack(attack_data: AttackDataType) -> void:
	var token := -1
	if opponent_attack_state != null and opponent_attack_state.current_state != 0:
		token = opponent_attack_state.get_action_token()
		if token == _resolved_token:
			return
		if not _resolution_allowed(false, token):
			return
		_resolved_token = token
	var result := DefenseResult.HIT
	var raw_kd: float = attack_data.knockdown_damage

	if _does_evasion_avoid_attack(attack_data):
		result = DefenseResult.EVADE
		raw_kd = 0.0
	else:
		var blocked := player_action_state.is_guarding()
		if blocked:
			result = DefenseResult.BLOCK
		raw_kd = _final_taken(attack_data.attack_type, raw_kd, blocked)

	if result == DefenseResult.BLOCK and player_stamina != null:
		player_stamina.apply_block_stamina_damage(attack_data.stamina_cost * BLOCK_STAMINA_COST_SCALE)
		if player_stamina.current_stamina <= 0.0 and player_action_state != null:
			player_action_state.set_guard_held(false)
			block_guard_broken.emit()

	var applied := 0.0
	var was_knockdown := false
	if meter_updates_enabled and raw_kd > 0.0:
		applied = player_knockdown_meter.apply_knockdown_damage(raw_kd)
		if player_knockdown_meter.is_knockdown_threshold():
			was_knockdown = true
			_notify_threshold(true)
			player_knockdown.emit(attack_data.attack_type)

	attack_resolved.emit(
		result,
		applied,
		player_knockdown_meter.current_meter,
		was_knockdown
	)
	_notify_resolved(false, token)

	if print_hit_results:
		print(
			"Opponent %s -> %s | KD Damage: %.1f | Player KD: %.0f/%.0f"
			% [
				ATTACK_NAMES[attack_data.attack_type],
				RESULT_NAMES[result] if not _attack_phase_is_open(get_node_or_null("../PlayerAttackState")) or result != DefenseResult.HIT else "COUNTER HIT",
				applied,
				player_knockdown_meter.current_meter,
				player_knockdown_meter.max_meter,
			]
		)
		if was_knockdown:
			print("Player Knockdown (KD Meter full)")
			for line in TraitMath.recent_kd_lines:
				print("  last %s" % line)


func has_resolved_token(token: int) -> bool:
	return token >= 0 and token == _resolved_token


func _resolution_allowed(is_player_attack: bool, token: int) -> bool:
	var manager := get_node_or_null("../KnockdownManager")
	if manager == null or not manager.has_method("allows_attack_resolution"):
		return true
	return manager.allows_attack_resolution(is_player_attack, token)


func _notify_threshold(player_down: bool) -> void:
	var manager := get_node_or_null("../KnockdownManager")
	if manager == null or not manager.has_method("notify_threshold"):
		return
	var KnockdownType = preload("res://scripts/knockdown_manager.gd")
	var side: int = KnockdownType.DownedSide.PLAYER if player_down else KnockdownType.DownedSide.OPPONENT
	manager.notify_threshold(side)


func _notify_resolved(is_player_attack: bool, token: int) -> void:
	var manager := get_node_or_null("../KnockdownManager")
	if manager != null and manager.has_method("notify_attack_resolved"):
		manager.notify_attack_resolved(is_player_attack, token)


func _final_taken(attack_type: int, base_damage: float, blocked: bool) -> float:
	var TraitMathScript = preload("res://scripts/trait_math.gd")
	var manager = null
	if is_inside_tree():
		manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	var attacker_traits: Array = []
	var defender_traits: Array = []
	if manager != null:
		attacker_traits = manager.traits_for_player(false)
		defender_traits = manager.traits_for_player(true)
	var attacker_node := get_node_or_null("../OpponentStamina")
	var defender_node: Node = player_stamina
	var attacker_stamina: float = 100.0
	var defender_stamina: float = 100.0
	if attacker_node != null:
		attacker_stamina = float(attacker_node.get("current_stamina"))
	if defender_node != null:
		defender_stamina = float(defender_node.get("current_stamina"))
	var vulnerability := 1.0
	if knockdown_vulnerability != null and defender_node != null:
		vulnerability = knockdown_vulnerability.multiplier_for(
			float(defender_node.get("current_stamina")),
			float(defender_node.get("max_stamina"))
		)
	var counter_hit := false
	if not blocked:
		counter_hit = _attack_phase_is_open(get_node_or_null("../PlayerAttackState"))
	var breakdown: Dictionary = TraitMathScript.compose_kd(
		base_damage,
		attack_type,
		attacker_traits,
		attacker_stamina,
		defender_traits,
		defender_stamina,
		blocked,
		vulnerability,
		counter_hit
	)
	if print_hit_results:
		_print_breakdown(ATTACK_NAMES[attack_type], blocked, counter_hit, breakdown)
	return float(breakdown["final"])


func _print_breakdown(attack_name: String, blocked: bool, counter_hit: bool, breakdown: Dictionary) -> void:
	var result_name := "HIT"
	if blocked:
		result_name = "BLOCK"
	elif counter_hit:
		result_name = "COUNTER_HIT"
	var line := "[KD_BREAKDOWN] attacker=Opponent attack=%s result=%s base=%.2f offensive_trait=%.2f defender_received_trait=%.2f trait_component=%.2f stamina_vulnerability=%.2f block=%.2f block_source=%s counter=%.2f final=%.2f" % [
		attack_name,
		result_name,
		breakdown["base"],
		breakdown["offensive_trait"],
		breakdown["defender_received_trait"],
		breakdown["trait_component"],
		breakdown["stamina_vulnerability"],
		breakdown["block"],
		breakdown["block_source"],
		breakdown["counter"],
		breakdown["final"],
	]
	print(line)
	TraitMath.recent_kd_lines.append(line)
	if TraitMath.recent_kd_lines.size() > 5:
		TraitMath.recent_kd_lines.pop_front()


func _attack_phase_is_open(attack_state: Node) -> bool:
	if attack_state == null:
		return false
	var state := int(attack_state.get("current_state"))
	return state == 1 or state == 2


func _does_evasion_avoid_attack(_attack_data: AttackDataType) -> bool:
	## Continuous Evade: gameplay window only (PlayerEvade), not exclusive slip states.
	if player_evade != null and player_evade.has_method("is_window_active"):
		return player_evade.is_window_active()
	return false
