class_name PlayerStamina
extends Node

signal stamina_changed(current_stamina: float, max_stamina: float)
signal exhausted_changed(is_exhausted: bool)

@export_group("Initial Values")
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_current_stamina := 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_max_stamina := 100.0

@export_group("Regeneration")
@export_range(0.0, 10.0, 0.05, "or_greater") var regeneration_delay := 0.65
@export_range(0.0, 1000.0, 0.1, "or_greater") var regeneration_per_second := 12.0

@export_group("Repeated Attack Fatigue")
@export_range(0.0, 10.0, 0.05, "or_greater") var repeated_attack_window := 1.5
@export_range(1, 100, 1, "or_greater") var attacks_before_max_loss := 3
@export_range(0.0, 100.0, 0.05, "or_greater") var max_stamina_loss_per_attack := 0.25

@export_group("Exhausted")
## Stay exhausted until stamina climbs back to this value.
@export_range(0.0, 1000.0, 0.5, "or_greater") var exhausted_recovery_threshold := 25.0

var current_stamina := 0.0
var max_stamina := 0.0
var regeneration_enabled := true
var is_exhausted := false

var _time_since_last_attack := INF
var _time_since_regen_block := INF
var _consecutive_attack_count := 0


func _ready() -> void:
	max_stamina = initial_max_stamina
	current_stamina = clampf(initial_current_stamina, 0.0, max_stamina)
	_evaluate_exhausted()
	stamina_changed.emit(current_stamina, max_stamina)


func _process(delta: float) -> void:
	_time_since_last_attack += delta
	_time_since_regen_block += delta

	if _time_since_last_attack > repeated_attack_window:
		_consecutive_attack_count = 0

	if not regeneration_enabled:
		return

	if (
		_time_since_regen_block >= regeneration_delay
		and current_stamina < max_stamina
	):
		current_stamina = minf(
			current_stamina + regeneration_per_second * _regen_scale(true) * delta,
			max_stamina
		)
		stamina_changed.emit(current_stamina, max_stamina)
		_evaluate_exhausted()


func can_afford(stamina_cost: float) -> bool:
	return current_stamina >= stamina_cost


func set_regeneration_enabled(enabled: bool) -> void:
	regeneration_enabled = enabled


func restore_stamina(amount: float) -> float:
	var before := current_stamina
	current_stamina = minf(current_stamina + maxf(amount, 0.0), max_stamina)
	var restored := current_stamina - before
	if restored > 0.0:
		stamina_changed.emit(current_stamina, max_stamina)
		_evaluate_exhausted()
	return restored


func spend_for_attack(stamina_cost: float) -> bool:
	if not can_afford(stamina_cost):
		return false

	if _time_since_last_attack <= repeated_attack_window:
		_consecutive_attack_count += 1
	else:
		_consecutive_attack_count = 1

	_time_since_last_attack = 0.0
	_time_since_regen_block = 0.0
	current_stamina -= stamina_cost

	if _consecutive_attack_count > attacks_before_max_loss:
		max_stamina = maxf(
			max_stamina - max_stamina_loss_per_attack,
			0.0
		)
		current_stamina = minf(current_stamina, max_stamina)

	stamina_changed.emit(current_stamina, max_stamina)
	_evaluate_exhausted()
	return true


func reset_to_max() -> void:
	current_stamina = max_stamina
	_evaluate_exhausted()
	stamina_changed.emit(current_stamina, max_stamina)


func _evaluate_exhausted() -> void:
	var next := is_exhausted
	if current_stamina <= 0.0:
		next = true
	elif current_stamina >= exhausted_recovery_threshold:
		next = false
	if next == is_exhausted:
		return
	is_exhausted = next
	exhausted_changed.emit(is_exhausted)


func _regen_scale(is_player: bool) -> float:
	if not is_inside_tree():
		return 1.0
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager == null:
		return 1.0
	return preload("res://scripts/trait_math.gd").regen_multiplier(manager.traits_for_player(is_player))

