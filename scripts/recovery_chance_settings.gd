class_name RecoveryChanceSettings
extends Resource

## Decides get-up once at knockdown time (not per count).

@export_group("Recovery Chance")
@export_range(1.0, 1000.0, 0.1, "or_greater") var reference_stamina := 100.0
@export_range(0.1, 5.0, 0.05, "or_greater") var recovery_chance_exponent := 1.25
@export_range(0.0, 1.0, 0.01) var max_recovery_chance := 0.85
@export_range(0.0, 1.0, 0.01) var min_recovery_chance := 0.05

@export_group("Stand-Up Count")
## Higher stamina maps toward earlier counts; lower stamina toward later.
@export_range(1, 9, 1) var earliest_stand_up_count := 1
@export_range(1, 9, 1) var latest_stand_up_count := 9
@export_range(0.1, 5.0, 0.05, "or_greater") var stand_up_count_exponent := 1.25

@export_group("Stand-Up Stamina")
@export_range(0.0, 1000.0, 0.1, "or_greater") var recovery_stamina_amount := 15.0


func calculate_recovery_chance(current_stamina: float) -> float:
	var curved := _stamina_curve(current_stamina, recovery_chance_exponent)
	return clampf(
		lerpf(min_recovery_chance, max_recovery_chance, curved),
		0.0,
		1.0
	)


func calculate_stand_up_count(current_stamina: float) -> int:
	var earliest := mini(earliest_stand_up_count, latest_stand_up_count)
	var latest := maxi(earliest_stand_up_count, latest_stand_up_count)
	var curved := _stamina_curve(current_stamina, stand_up_count_exponent)
	## High stamina → early stand-up; low stamina → late stand-up.
	var count := roundi(lerpf(float(latest), float(earliest), curved))
	return clampi(count, earliest, latest)


## One-shot roll at knockdown. Does not roll again during the count.
func resolve_recovery(current_stamina: float) -> Dictionary:
	var chance := calculate_recovery_chance(current_stamina)
	var roll := randf()
	var success := roll < chance
	var stand_up_count := -1
	if success:
		stand_up_count = calculate_stand_up_count(current_stamina)
	return {
		"success": success,
		"stand_up_count": stand_up_count,
		"chance": chance,
		"roll": roll,
		"stamina": current_stamina,
	}


func _stamina_curve(current_stamina: float, exponent: float) -> float:
	var ratio := clampf(
		current_stamina / maxf(reference_stamina, 0.001),
		0.0,
		1.0
	)
	return pow(ratio, exponent)
