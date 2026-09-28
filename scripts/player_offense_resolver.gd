class_name PlayerOffenseResolver
extends Node

## Resolves player attack hits vs opponent defense. Applies Knockdown Meter damage.

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")
const OpponentActionStateType = preload("res://scripts/opponent_action_state.gd")
const KnockdownMeterType = preload("res://scripts/knockdown_meter.gd")
const VulnerabilityType = preload("res://scripts/knockdown_vulnerability.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")

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
@export var opponent_stamina: OpponentStaminaType
@export var knockdown_vulnerability: VulnerabilityType

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
	assert(player_attack_state != null)
	assert(opponent_knockdown_meter != null)
	if opponent_stamina == null:
		opponent_stamina = get_node_or_null("../OpponentStamina")
	if knockdown_vulnerability == null:
		knockdown_vulnerability = VulnerabilityType.new()
	player_attack_state.state_changed.connect(_on_player_attack_state_changed)


func _on_player_attack_state_changed(state: int, attack: int) -> void:
	if state != AttackStateType.AttackState.ACTIVE:
		return
	if (
		player_attack_state != null
		and player_attack_state.get_action_token() == _resolved_token
	):
		return
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
	var token := -1
	if player_attack_state != null and player_attack_state.current_state != AttackStateType.AttackState.IDLE:
		token = player_attack_state.get_action_token()
		if token == _resolved_token:
			return
		if not _resolution_allowed(true, token):
			return
		_resolved_token = token
	var attack_data = player_attack_state.get_attack_data(attack)
	if attack_data == null:
		push_error("Attack data is missing for attack type %d." % attack)
		return

	var result := ResolveResult.HIT
	var raw_kd: float = attack_data.knockdown_damage

	if _does_opponent_evade(attack):
		result = ResolveResult.EVADE
		raw_kd = 0.0
	else:
		var blocked := opponent_action_state != null and opponent_action_state.is_guarding()
		if blocked:
			result = ResolveResult.BLOCK
		raw_kd = _final_kd(attack, raw_kd, true, blocked)

	var applied := 0.0
	var was_knockdown := false
	if meter_updates_enabled and raw_kd > 0.0:
		applied = opponent_knockdown_meter.apply_knockdown_damage(raw_kd)
		if opponent_knockdown_meter.is_full():
			was_knockdown = true
			_notify_threshold(false)
			opponent_knockdown.emit(attack)

	attack_hit.emit(
		attack,
		applied,
		opponent_knockdown_meter.current_meter,
		was_knockdown,
		result
	)
	_notify_resolved(true, token)

	if print_hit_results:
		print(
			"Player %s -> %s | KD Damage: %.1f | Opp KD: %.0f/%.0f"
			% [
				ATTACK_NAMES[attack],
				RESULT_NAMES[result] if not _attack_phase_is_open(get_node_or_null("../OpponentAttackState")) or result != ResolveResult.HIT else "COUNTER HIT",
				applied,
				opponent_knockdown_meter.current_meter,
				opponent_knockdown_meter.max_meter,
			]
		)
		if was_knockdown:
			print("Opponent Knockdown (KD Meter full)")
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


func _final_kd(attack_type: int, base_damage: float, attacker_is_player: bool, blocked: bool) -> float:
	var TraitMathScript = preload("res://scripts/trait_math.gd")
	var manager = null
	if is_inside_tree():
		manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	var attacker_traits: Array = []
	var defender_traits: Array = []
	if manager != null:
		attacker_traits = manager.traits_for_player(attacker_is_player)
		defender_traits = manager.traits_for_player(not attacker_is_player)
	var attacker_node := _side_stamina(attacker_is_player)
	var defender_node := _side_stamina(not attacker_is_player)
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
		counter_hit = _attack_phase_is_open(get_node_or_null("../OpponentAttackState"))
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
		_print_breakdown("Player", ATTACK_NAMES[attack_type], blocked, counter_hit, breakdown)
	return float(breakdown["final"])


func _print_breakdown(attacker_name: String, attack_name: String, blocked: bool, counter_hit: bool, breakdown: Dictionary) -> void:
	var result_name := "HIT"
	if blocked:
		result_name = "BLOCK"
	elif counter_hit:
		result_name = "COUNTER_HIT"
	var line := "[KD_BREAKDOWN] attacker=%s attack=%s result=%s base=%.2f offensive_trait=%.2f defender_received_trait=%.2f trait_component=%.2f stamina_vulnerability=%.2f block=%.2f block_source=%s counter=%.2f final=%.2f" % [
		attacker_name,
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


func _side_stamina(is_player: bool) -> Node:
	if is_player:
		return get_node_or_null("../PlayerStamina")
	return opponent_stamina


func _does_opponent_evade(attack: int) -> bool:
	if opponent_action_state == null or not opponent_action_state.is_evasion_active():
		return false
	var evasion := opponent_action_state.get_current_evasion()
	## Slip Left / Slip Right avoid Straights and Hooks.
	return evasion in [
		OpponentActionStateType.OpponentState.SLIP_LEFT,
		OpponentActionStateType.OpponentState.SLIP_RIGHT,
	]
