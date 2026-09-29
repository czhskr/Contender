class_name FighterTrait
extends Resource

## One strong Round modifier. Effects are multipliers, never permanent base edits.

enum Id {
	IRON_GUARD,
	HEAVY_HANDS,
	GLASS_CANNON,
	ENDURANCE,
	TOUGH_CHIN,
	EFFICIENT_STRIKER,
	POWER_HOOKS,
	SHARP_STRAIGHT,
	LAST_STAND,
	QUICK_FEET,
	REFLEX,
	PRESSURE_FIGHTER,
}

@export var id: Id = Id.IRON_GUARD
@export var display_name := ""
@export var description := ""
@export var positive_effect := ""
@export var tradeoff_description := ""
## Empty means this trait can sit next to any other trait.
@export var exclusive_group := ""

@export var outgoing_kd := 1.0
@export var incoming_kd := 1.0
@export var hook_outgoing_kd := 1.0
@export var straight_outgoing_kd := 1.0
@export var attack_cost := 1.0
@export var stamina_regen := 1.0
@export var block_incoming_kd := 1.0
@export var iron_guard := false
@export var last_stand := false
@export var evade_window := 1.0
@export var evade_retrigger := 1.0
@export var slip_duration := 1.0
@export var reaction_time := 1.0
## Multiplies the attack-to-attack cancel threshold. 0.5 halves the recovery wait.
@export var attack_link_threshold := 1.0
## Multiplies opponent attack interval and follow-up delay.
@export var offense_pace := 1.0
## Eligibility. A fighter without this attack cannot be offered the trait.
@export var requires_straight_attack := false
@export var requires_hook_attack := false
