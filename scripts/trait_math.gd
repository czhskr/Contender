class_name TraitMath
extends RefCounted

const LAST_STAND_STAMINA := 25.0
const MIN_ATTACK_COST := 0.1
const OFFENSIVE_TRAIT_CAP := 2.5
const TRAIT_CONTRIBUTION_CAP := 3.0
static var recent_kd_lines: Array[String] = []


static func product(traits: Array, field: String) -> float:
	var value := 1.0
	for entry in traits:
		value *= float(entry.get(field))
	return value


static func has_flag(traits: Array, field: String) -> bool:
	for entry in traits:
		if bool(entry.get(field)):
			return true
	return false


static func attack_cost(base_cost: float, traits: Array) -> float:
	var scaled := base_cost * product(traits, "attack_cost")
	return maxf(MIN_ATTACK_COST, snappedf(scaled, 0.1))


static func outgoing_kd(base_damage: float, attack_type: int, traits: Array, attacker_stamina: float) -> float:
	return base_damage * offensive_multiplier(attack_type, traits, attacker_stamina)


static func offensive_multiplier(attack_type: int, traits: Array, attacker_stamina: float) -> float:
	var raw := product(traits, "outgoing_kd")
	if attack_type <= 1:
		raw *= product(traits, "straight_outgoing_kd")
	else:
		raw *= product(traits, "hook_outgoing_kd")
	if has_flag(traits, "last_stand") and attacker_stamina <= LAST_STAND_STAMINA:
		raw *= 2.0
	return minf(raw, OFFENSIVE_TRAIT_CAP)


static func defensive_multiplier(traits: Array, defender_stamina: float) -> float:
	var raw := product(traits, "incoming_kd")
	if has_flag(traits, "last_stand") and defender_stamina <= LAST_STAND_STAMINA:
		raw *= 2.0
	return raw


static func compose_kd(
	base_damage: float,
	attack_type: int,
	attacker_traits: Array,
	attacker_stamina: float,
	defender_traits: Array,
	defender_stamina: float,
	blocked: bool,
	vulnerability: float,
	counter_hit: bool = false
) -> Dictionary:
	var offensive := offensive_multiplier(attack_type, attacker_traits, attacker_stamina)
	var defensive := defensive_multiplier(defender_traits, defender_stamina)
	var trait_component := minf(offensive * defensive, TRAIT_CONTRIBUTION_CAP)
	var block_multiplier := 1.0
	var block_source := ""
	var counter_multiplier := 1.0
	var final_damage := base_damage * trait_component
	if blocked:
		if has_flag(defender_traits, "iron_guard"):
			block_multiplier = 0.0
			block_source = "Iron Guard"
			final_damage = 0.0
		else:
			block_multiplier = 0.25 * product(defender_traits, "block_incoming_kd")
			block_source = "Guard"
			final_damage *= block_multiplier
			final_damage *= vulnerability
	else:
		final_damage *= vulnerability
		if counter_hit:
			counter_multiplier = 1.5
			final_damage *= counter_multiplier
	return {
		"base": base_damage,
		"offensive_trait": offensive,
		"defender_received_trait": defensive,
		"trait_component": trait_component,
		"stamina_vulnerability": vulnerability,
		"block": block_multiplier,
		"block_source": block_source,
		"counter": counter_multiplier,
		"final": maxf(final_damage, 0.0),
	}


static func taken_kd(
	outgoing: float,
	defender_traits: Array,
	defender_stamina: float,
	blocked: bool,
	vulnerability: float,
	counter_hit: bool = false
) -> float:
	if outgoing <= 0.0:
		return 0.0
	var damage := outgoing * product(defender_traits, "incoming_kd")
	if has_flag(defender_traits, "last_stand") and defender_stamina <= LAST_STAND_STAMINA:
		damage *= 2.0
	if blocked:
		if has_flag(defender_traits, "iron_guard"):
			return 0.0
		damage *= 0.25
		damage *= product(defender_traits, "block_incoming_kd")
	damage *= vulnerability
	if counter_hit and not blocked:
		damage *= 1.5
	return maxf(damage, 0.0)


static func regen_multiplier(traits: Array) -> float:
	return maxf(product(traits, "stamina_regen"), 0.0)


static func pace_multiplier(traits: Array) -> float:
	return maxf(product(traits, "offense_pace"), 0.05)
