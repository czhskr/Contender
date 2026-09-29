class_name TraitManager
extends Node

## Rolls one trait per fighter at the start of each round.
## Effects are queried live. Base resources are never overwritten.

const Catalog = preload("res://scripts/trait_catalog.gd")
const GameModeType = preload("res://scripts/game_mode.gd")

signal traits_changed

var player_traits: Array = []
var opponent_traits: Array = []
var rng := RandomNumberGenerator.new()
var roll_count := 0
var print_pools := true


func _ready() -> void:
	add_to_group("trait_manager")
	rng.randomize()


func set_seed(seed_value: int) -> void:
	rng.seed = seed_value


func reroll_round() -> void:
	if _mode_disables_traits():
		clear_traits()
		return
	roll_count += 1
	var player_caps = Catalog.player_capabilities()
	var opponent_caps = Catalog.opponent_capabilities()
	if print_pools:
		_print_pools(player_caps, opponent_caps)
	player_traits = [_roll_one(player_caps)]
	opponent_traits = [_roll_one(opponent_caps)]
	traits_changed.emit()


func clear_traits() -> void:
	player_traits = []
	opponent_traits = []
	traits_changed.emit()


func traits_for_player(is_player: bool) -> Array:
	return player_traits if is_player else opponent_traits


static func find(tree: SceneTree) -> TraitManager:
	if tree == null:
		return null
	return tree.get_first_node_in_group("trait_manager") as TraitManager


func _roll_one(caps):
	var pool: Array = Catalog.eligible_traits(caps)
	if pool.is_empty():
		return null
	var index := rng.randi_range(0, pool.size() - 1)
	return pool[index]


func _mode_disables_traits() -> bool:
	if not is_inside_tree():
		return false
	var mode = GameModeType.find(get_tree())
	return mode != null and not mode.is_trait_mode()


func _print_pools(player_caps, opponent_caps) -> void:
	print("[TRAIT_POOL]")
	print("Player eligible=%s" % _names(Catalog.eligible_traits(player_caps)))
	print("Opponent eligible=%s" % _names(Catalog.eligible_traits(opponent_caps)))
	_print_excluded("Player", player_caps)
	_print_excluded("Opponent", opponent_caps)


func _print_excluded(label: String, caps) -> void:
	var lines: Array[String] = []
	for entry in Catalog.all_traits():
		var reason := Catalog.exclusion_reason(entry, caps)
		if reason != "":
			lines.append("- %s: %s" % [Catalog.english_name(entry), reason])
	if lines.is_empty():
		return
	print("%s excluded:" % label)
	for line in lines:
		print(line)


func _names(pool: Array) -> String:
	var names: PackedStringArray = []
	for entry in pool:
		names.append(Catalog.english_name(entry))
	return ", ".join(names)
