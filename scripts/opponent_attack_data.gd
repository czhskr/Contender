class_name OpponentAttackData
extends Resource

enum AttackType {
	LEFT_STRAIGHT,
	RIGHT_STRAIGHT,
	LEFT_HOOK,
	RIGHT_HOOK,
}

enum AttackSide {
	LEFT,
	RIGHT,
}

@export var attack_type := AttackType.LEFT_STRAIGHT
@export var side := AttackSide.LEFT
@export_range(0.0, 10.0, 0.01, "or_greater") var startup_time := 0.10
@export_range(0.0, 10.0, 0.01, "or_greater") var active_time := 0.08
@export_range(0.0, 10.0, 0.01, "or_greater") var recovery_time := 0.11
## Cost paid by the opponent when starting this attack.
@export_range(0.0, 1000.0, 0.1, "or_greater") var stamina_cost := 4.0
## Applied to the player Knockdown Meter on HIT (BLOCK uses guard multiplier).
@export_range(0.0, 1000.0, 0.1, "or_greater") var knockdown_damage := 8.0
