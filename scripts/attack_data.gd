class_name AttackData
extends Resource

@export_enum(
	"Left Straight",
	"Right Straight",
	"Left Hook",
	"Right Hook"
) var attack_type: int
@export_range(0.0, 10.0, 0.01, "or_greater") var startup_time := 0.10
@export_range(0.0, 10.0, 0.01, "or_greater") var active_time := 0.08
@export_range(0.0, 10.0, 0.01, "or_greater") var recovery_time := 0.18
