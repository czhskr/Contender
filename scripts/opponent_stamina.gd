class_name OpponentStamina
extends Node

signal stamina_changed(current_stamina: float, max_stamina: float)

@export_group("Initial Values")
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_current_stamina := 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var initial_max_stamina := 100.0

@export_group("Regeneration")
@export_range(0.0, 10.0, 0.05, "or_greater") var regeneration_delay := 0.65
@export_range(0.0, 1000.0, 0.1, "or_greater") var regeneration_per_second := 8.0

var current_stamina := 0.0
var max_stamina := 0.0
var regeneration_enabled := true

var _time_since_regen_block := INF


func _ready() -> void:
	max_stamina = initial_max_stamina
	current_stamina = clampf(initial_current_stamina, 0.0, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)


func _process(delta: float) -> void:
	_time_since_regen_block += delta

	if not regeneration_enabled:
		return

	if (
		_time_since_regen_block >= regeneration_delay
		and current_stamina < max_stamina
	):
		current_stamina = minf(
			current_stamina + regeneration_per_second * _regen_scale() * delta,
			max_stamina
		)
		stamina_changed.emit(current_stamina, max_stamina)


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
	return restored


## Spend attack cost and restart natural regen delay. No refund on miss/block/evade.
func spend_for_attack(stamina_cost: float) -> bool:
	if not can_afford(stamina_cost):
		return false

	_time_since_regen_block = 0.0
	current_stamina -= stamina_cost
	stamina_changed.emit(current_stamina, max_stamina)
	return true


## Successful block cost. Uses the attack's base cost, clamps at 0, and restarts regen.
func apply_block_stamina_damage(amount: float) -> float:
	var damage := maxf(amount, 0.0)
	if damage <= 0.0:
		return 0.0
	_time_since_regen_block = 0.0
	var before := current_stamina
	current_stamina = maxf(current_stamina - damage, 0.0)
	var applied := before - current_stamina
	stamina_changed.emit(current_stamina, max_stamina)
	return applied


func reset_to_max() -> void:
	current_stamina = max_stamina
	stamina_changed.emit(current_stamina, max_stamina)


func _regen_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager == null:
		return 1.0
	return preload("res://scripts/trait_math.gd").regen_multiplier(manager.traits_for_player(false))

