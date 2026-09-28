class_name TraitManager
extends Node

## Rolls one trait per fighter at the start of each round.
## Effects are queried live. Base resources are never overwritten.

const Catalog = preload("res://scripts/trait_catalog.gd")

signal traits_changed

var player_traits: Array = []
var opponent_traits: Array = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("trait_manager")
	rng.randomize()


func set_seed(seed_value: int) -> void:
	rng.seed = seed_value


func reroll_round() -> void:
	player_traits = [_roll_one()]
	opponent_traits = [_roll_one()]
	traits_changed.emit()


func traits_for_player(is_player: bool) -> Array:
	return player_traits if is_player else opponent_traits


static func find(tree: SceneTree) -> TraitManager:
	if tree == null:
		return null
	return tree.get_first_node_in_group("trait_manager") as TraitManager


func _roll_one():
	var pool: Array = Catalog.all_traits()
	var index := rng.randi_range(0, pool.size() - 1)
	return pool[index]
