class_name AttackData
extends Resource

enum Hand {
	LEFT,
	RIGHT,
}


## 0/2 are left punches. 1/3 are right punches. Shared with opponent attack ints.
static func hand_of(attack_type: int) -> Hand:
	if attack_type == 0 or attack_type == 2:
		return Hand.LEFT
	return Hand.RIGHT


static func is_same_hand(current_type: int, next_type: int) -> bool:
	return hand_of(current_type) == hand_of(next_type)


## Opposite hand may leave recovery early. Same hand must finish recovery.
static func can_recovery_cancel(
	progress: float,
	threshold: float,
	current_type: int,
	next_type: int
) -> bool:
	if is_same_hand(current_type, next_type):
		return false
	return progress >= threshold


@export_enum(
	"Left Straight",
	"Right Straight",
	"Left Hook",
	"Right Hook"
) var attack_type: int
@export_range(0.0, 10.0, 0.01, "or_greater") var startup_time := 0.10
@export_range(0.0, 10.0, 0.01, "or_greater") var active_time := 0.08
@export_range(0.0, 10.0, 0.01, "or_greater") var recovery_time := 0.11
@export_range(0.0, 1000.0, 0.1, "or_greater") var stamina_cost := 4.0
## Applied to the target Knockdown Meter on HIT (BLOCK uses guard multiplier).
@export_range(0.0, 1000.0, 0.1, "or_greater") var knockdown_damage := 8.0
