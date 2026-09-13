extends Node

const ATTACK_NAMES := [
	"Left straight",
	"Right straight",
	"Left hook",
	"Right hook",
]
const DEFENSE_NAMES := [
	"Slip left",
	"Slip right",
	"Duck",
]
const TARGET_NAMES := [
	"HEAD",
	"BODY",
]

@onready var combat_input: Node = $PlayerCombatInput
@onready var target_value: Label = $DebugHUD/Panel/Margin/Content/TargetRow/TargetValue
@onready var guard_value: Label = $DebugHUD/Panel/Margin/Content/GuardRow/GuardValue
@onready var last_input_value: Label = \
	$DebugHUD/Panel/Margin/Content/LastInputRow/LastInputValue


func _ready() -> void:
	combat_input.attack_requested.connect(_on_attack_requested)
	combat_input.defense_requested.connect(_on_defense_requested)
	combat_input.guard_changed.connect(_on_guard_changed)
	combat_input.target_changed.connect(_on_target_changed)

	_on_target_changed(combat_input.current_target)
	_on_guard_changed(combat_input.is_guarding)


func _on_attack_requested(
	attack: int,
	target: int
) -> void:
	last_input_value.text = "%s -> %s" % [
		ATTACK_NAMES[attack],
		TARGET_NAMES[target],
	]


func _on_defense_requested(defense: int) -> void:
	last_input_value.text = DEFENSE_NAMES[defense]


func _on_guard_changed(is_guarding: bool) -> void:
	guard_value.text = "ON (holding)" if is_guarding else "OFF"
	last_input_value.text = "High guard %s" % guard_value.text


func _on_target_changed(target: int) -> void:
	target_value.text = TARGET_NAMES[target]
	last_input_value.text = "Target -> %s" % target_value.text
