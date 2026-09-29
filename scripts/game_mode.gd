class_name GameMode
extends Node

## Match-wide mode. Round changes do not change this.
## Title / menu code should set `mode` before the match starts.

enum Mode {
	NORMAL,
	TRAIT,
}

@export var mode: Mode = Mode.NORMAL


func _ready() -> void:
	add_to_group("game_mode")


func is_trait_mode() -> bool:
	return mode == Mode.TRAIT


func mode_label() -> String:
	return "TRAIT" if is_trait_mode() else "NORMAL"


static func find(tree: SceneTree) -> GameMode:
	if tree == null:
		return null
	return tree.get_first_node_in_group("game_mode") as GameMode
