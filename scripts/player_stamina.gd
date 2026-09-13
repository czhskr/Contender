class_name PlayerStamina
extends Node

signal stamina_changed(current_stamina: float, max_stamina: float)

@export_group("Initial Values")
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_current_stamina := 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_max_stamina := 100.0

@export_group("Regeneration")
@export_range(0.0, 10.0, 0.05, "or_greater") var regeneration_delay := 1.25
@export_range(0.0, 1000.0, 0.1, "or_greater") var regeneration_per_second := 12.0

@export_group("Repeated Attack Fatigue")
@export_range(0.0, 10.0, 0.05, "or_greater") var repeated_attack_window := 1.5
@export_range(1, 100, 1, "or_greater") var attacks_before_max_loss := 3
@export_range(0.0, 100.0, 0.05, "or_greater") var max_stamina_loss_per_attack := 0.25

var current_stamina := 0.0
var max_stamina := 0.0

var _time_since_last_attack := INF
var _consecutive_attack_count := 0


func _ready() -> void:
	max_stamina = initial_max_stamina
	current_stamina = clampf(initial_current_stamina, 0.0, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)


func _process(delta: float) -> void:
	_time_since_last_attack += delta

	if _time_since_last_attack > repeated_attack_window:
		_consecutive_attack_count = 0

	if (
		_time_since_last_attack >= regeneration_delay
		and current_stamina < max_stamina
	):
		current_stamina = minf(
			current_stamina + regeneration_per_second * delta,
			max_stamina
		)
		stamina_changed.emit(current_stamina, max_stamina)


func can_afford(stamina_cost: float) -> bool:
	return current_stamina >= stamina_cost


func spend_for_attack(stamina_cost: float) -> bool:
	if not can_afford(stamina_cost):
		return false

	if _time_since_last_attack <= repeated_attack_window:
		_consecutive_attack_count += 1
	else:
		_consecutive_attack_count = 1

	_time_since_last_attack = 0.0
	current_stamina -= stamina_cost

	if _consecutive_attack_count > attacks_before_max_loss:
		max_stamina = maxf(
			max_stamina - max_stamina_loss_per_attack,
			0.0
		)
		current_stamina = minf(current_stamina, max_stamina)

	stamina_changed.emit(current_stamina, max_stamina)
	return true
