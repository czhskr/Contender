class_name ActionSpeedSettings
extends Resource

## Continuous low-stamina action speed curve (absolute Current Stamina).
## Shared formula for player/opponent; use separate .tres for balance.

@export_group("Fatigue Curve")
@export_range(1.0, 1000.0, 0.1, "or_greater") var reference_stamina := 100.0
@export_range(0.1, 10.0, 0.05, "or_greater") var fatigue_exponent := 2.5
@export_range(0.05, 1.0, 0.01) var minimum_action_speed := 0.60


## Returns action speed multiplier in [minimum_action_speed, 1.0].
func calculate_action_speed(current_stamina: float) -> float:
	var fatigue := clampf(
		1.0 - current_stamina / maxf(reference_stamina, 0.001),
		0.0,
		1.0
	)
	var curved := pow(fatigue, fatigue_exponent)
	return clampf(
		lerpf(1.0, minimum_action_speed, curved),
		minimum_action_speed,
		1.0
	)


func scale_duration(base_duration: float, action_speed: float) -> float:
	var speed := maxf(action_speed, 0.001)
	return base_duration / speed
