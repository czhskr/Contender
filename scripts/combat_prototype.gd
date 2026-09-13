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
const ATTACK_STATE_NAMES := [
	"IDLE",
	"STARTUP",
	"ACTIVE",
	"RECOVERY",
]
const PLAYER_STATE_NAMES := [
	"IDLE",
	"ATTACKING",
	"SLIP LEFT",
	"SLIP RIGHT",
	"DUCK",
	"GUARD",
]

@onready var combat_input: Node = $PlayerCombatInput
@onready var attack_state: Node = $PlayerAttackState
@onready var stamina: Node = $PlayerStamina
@onready var player_state: Node = $PlayerActionState
@onready var stamina_bar: ProgressBar = \
	$DebugHUD/Panel/Margin/Content/PlayerStaminaBar
@onready var stamina_value: Label = \
	$DebugHUD/Panel/Margin/Content/StaminaValue
@onready var target_value: Label = $DebugHUD/Panel/Margin/Content/TargetRow/TargetValue
@onready var guard_value: Label = $DebugHUD/Panel/Margin/Content/GuardRow/GuardValue
@onready var attack_state_value: Label = \
	$DebugHUD/Panel/Margin/Content/AttackStateRow/AttackStateValue
@onready var current_attack_value: Label = \
	$DebugHUD/Panel/Margin/Content/CurrentAttackRow/CurrentAttackValue
@onready var player_state_value: Label = \
	$DebugHUD/Panel/Margin/Content/PlayerStateRow/PlayerStateValue
@onready var last_input_value: Label = \
	$DebugHUD/Panel/Margin/Content/LastInputRow/LastInputValue


func _ready() -> void:
	combat_input.attack_requested.connect(_on_attack_requested)
	combat_input.defense_requested.connect(_on_defense_requested)
	combat_input.guard_changed.connect(_on_guard_changed)
	combat_input.target_changed.connect(_on_target_changed)
	attack_state.state_changed.connect(_on_attack_state_changed)
	stamina.stamina_changed.connect(_on_stamina_changed)
	player_state.state_changed.connect(_on_player_state_changed)

	_on_target_changed(combat_input.current_target)
	_on_guard_changed(combat_input.is_guarding)
	_on_attack_state_changed(attack_state.current_state, attack_state.current_attack)
	_on_stamina_changed(stamina.current_stamina, stamina.max_stamina)
	_on_player_state_changed(player_state.current_state)


func _on_attack_requested(
	attack: int,
	target: int
) -> void:
	if not player_state.can_attack():
		last_input_value.text = "Blocked: %s (player: %s)" % [
			ATTACK_NAMES[attack],
			PLAYER_STATE_NAMES[player_state.current_state],
		]
		return

	var attack_data = attack_state.get_attack_data(attack)
	if attack_data == null:
		last_input_value.text = "Missing attack data: %s" % ATTACK_NAMES[attack]
		return

	if not stamina.can_afford(attack_data.stamina_cost):
		last_input_value.text = "Insufficient stamina: %s (%.1f / %.1f)" % [
			ATTACK_NAMES[attack],
			stamina.current_stamina,
			attack_data.stamina_cost,
		]
		return

	if attack_state.try_start_attack(attack):
		stamina.spend_for_attack(attack_data.stamina_cost)
		last_input_value.text = "Accepted: %s -> %s" % [
			ATTACK_NAMES[attack],
			TARGET_NAMES[target],
		]


func _on_defense_requested(defense: int) -> void:
	if player_state.try_start_evasion(defense):
		last_input_value.text = "Accepted: %s" % DEFENSE_NAMES[defense]
	else:
		last_input_value.text = "Blocked: %s (player: %s)" % [
			DEFENSE_NAMES[defense],
			PLAYER_STATE_NAMES[player_state.current_state],
		]


func _on_guard_changed(is_guarding: bool) -> void:
	player_state.set_guard_held(is_guarding)
	_update_guard_debug()
	last_input_value.text = "High guard input: %s" % (
		"PRESSED" if is_guarding else "RELEASED"
	)


func _on_target_changed(target: int) -> void:
	target_value.text = TARGET_NAMES[target]
	last_input_value.text = "Target -> %s" % target_value.text


func _on_attack_state_changed(state: int, attack: int) -> void:
	attack_state_value.text = ATTACK_STATE_NAMES[state]
	current_attack_value.text = "None" if attack == -1 else ATTACK_NAMES[attack]


func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	stamina_bar.max_value = max_stamina
	stamina_bar.value = current_stamina
	stamina_value.text = "%.1f / %.1f" % [current_stamina, max_stamina]


func _on_player_state_changed(state: int) -> void:
	player_state_value.text = PLAYER_STATE_NAMES[state]
	_update_guard_debug()


func _update_guard_debug() -> void:
	if player_state.is_guarding():
		guard_value.text = "ON"
	elif combat_input.is_guarding:
		guard_value.text = "HELD (waiting)"
	else:
		guard_value.text = "OFF"
