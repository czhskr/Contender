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
	"GUARD",
]
const DEFENSE_RESULT_NAMES := ["HIT", "BLOCK", "EVADE"]

@onready var combat_input: Node = $PlayerCombatInput
@onready var attack_state: Node = $PlayerAttackState
@onready var stamina: Node = $PlayerStamina
@onready var player_state: Node = $PlayerActionState
@onready var opponent_stamina: Node = $OpponentStamina
@onready var player_knockdown_meter: Node = $PlayerKnockdownMeter
@onready var opponent_knockdown_meter: Node = $OpponentKnockdownMeter
@onready var defense_resolver: Node = $PlayerDefenseResolver
@onready var opponent_attack_state: Node = $OpponentAttackState
@onready var offense_resolver: Node = $PlayerOffenseResolver
@onready var knockdown_manager: Node = $KnockdownManager
@onready var round_manager: Node = $RoundManager
@onready var match_decision: Node = $MatchDecision
@onready var player_hit_stun: Node = $PlayerHitStun
@onready var opponent_hit_stun: Node = $OpponentHitStun
@onready var opponent_action_state: Node = $OpponentActionState
@onready var opponent_ai: Node = $OpponentAI
@onready var stamina_bar: ProgressBar = \
	$DebugHUD/Panel/Margin/Content/PlayerStaminaBar
@onready var stamina_value: Label = \
	$DebugHUD/Panel/Margin/Content/StaminaValue
@onready var player_kd_bar: ProgressBar = \
	$DebugHUD/Panel/Margin/Content/PlayerKnockdownMeterBar
@onready var player_kd_value: Label = \
	$DebugHUD/Panel/Margin/Content/PlayerKnockdownMeterValue
@onready var opponent_stamina_bar: ProgressBar = \
	$DebugHUD/Panel/Margin/Content/OpponentStaminaBar
@onready var opponent_stamina_value: Label = \
	$DebugHUD/Panel/Margin/Content/OpponentStaminaValue
@onready var opponent_kd_bar: ProgressBar = \
	$DebugHUD/Panel/Margin/Content/OpponentKnockdownMeterBar
@onready var opponent_kd_value: Label = \
	$DebugHUD/Panel/Margin/Content/OpponentKnockdownMeterValue
@onready var guard_value: Label = $DebugHUD/Panel/Margin/Content/GuardRow/GuardValue
@onready var attack_state_value: Label = \
	$DebugHUD/Panel/Margin/Content/AttackStateRow/AttackStateValue
@onready var current_attack_value: Label = \
	$DebugHUD/Panel/Margin/Content/CurrentAttackRow/CurrentAttackValue
@onready var player_state_value: Label = \
	$DebugHUD/Panel/Margin/Content/PlayerStateRow/PlayerStateValue
@onready var match_status_value: Label = \
	$DebugHUD/Panel/Margin/Content/MatchStatusRow/MatchStatusValue
@onready var round_status_value: Label = \
	$DebugHUD/Panel/Margin/Content/RoundStatusRow/RoundStatusValue
@onready var score_status_value: Label = \
	$DebugHUD/Panel/Margin/Content/ScoreStatusRow/ScoreStatusValue
@onready var last_input_value: Label = \
	$DebugHUD/Panel/Margin/Content/LastInputRow/LastInputValue


func _ready() -> void:
	combat_input.attack_requested.connect(_on_attack_requested)
	combat_input.defense_requested.connect(_on_defense_requested)
	combat_input.guard_changed.connect(_on_guard_changed)
	attack_state.state_changed.connect(_on_attack_state_changed)
	stamina.stamina_changed.connect(_on_stamina_changed)
	player_state.state_changed.connect(_on_player_state_changed)
	opponent_stamina.stamina_changed.connect(_on_opponent_stamina_changed)
	player_knockdown_meter.meter_changed.connect(_on_player_kd_changed)
	opponent_knockdown_meter.meter_changed.connect(_on_opponent_kd_changed)
	offense_resolver.opponent_knockdown.connect(_on_opponent_knockdown)
	defense_resolver.player_knockdown.connect(_on_player_knockdown)
	defense_resolver.attack_resolved.connect(_on_opponent_attack_resolved)
	offense_resolver.attack_hit.connect(_on_player_attack_hit)
	knockdown_manager.hud_text_changed.connect(_on_match_hud_text_changed)
	knockdown_manager.match_finished.connect(_on_match_finished)
	round_manager.hud_text_changed.connect(_on_round_hud_text_changed)
	round_manager.decision_required.connect(_on_decision_required)
	match_decision.hud_text_changed.connect(_on_score_hud_text_changed)
	match_decision.match_result_ready.connect(_on_match_result_ready)

	_on_guard_changed(combat_input.is_guarding)
	_on_attack_state_changed(attack_state.current_state, attack_state.current_attack)
	_on_stamina_changed(stamina.current_stamina, stamina.max_stamina)
	_on_player_state_changed(player_state.current_state)
	_on_opponent_stamina_changed(
		opponent_stamina.current_stamina,
		opponent_stamina.max_stamina
	)
	_on_player_kd_changed(
		player_knockdown_meter.current_meter,
		player_knockdown_meter.max_meter
	)
	_on_opponent_kd_changed(
		opponent_knockdown_meter.current_meter,
		opponent_knockdown_meter.max_meter
	)
	_on_match_hud_text_changed("FIGHTING")
	_on_score_hud_text_changed("--")


func _can_accept_combat_input() -> bool:
	return (
		knockdown_manager.can_accept_combat_input()
		and round_manager.can_accept_combat_input()
	)


func _on_attack_requested(attack: int) -> void:
	if not _can_accept_combat_input():
		last_input_value.text = "Blocked: match not fighting"
		return

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
		last_input_value.text = "Accepted: %s" % ATTACK_NAMES[attack]


func _on_defense_requested(defense: int) -> void:
	if not _can_accept_combat_input():
		last_input_value.text = "Blocked: match not fighting"
		return

	if player_state.try_start_evasion(defense):
		last_input_value.text = "Accepted: %s" % DEFENSE_NAMES[defense]
	else:
		last_input_value.text = "Blocked: %s (player: %s)" % [
			DEFENSE_NAMES[defense],
			PLAYER_STATE_NAMES[player_state.current_state],
		]


func _on_guard_changed(is_guarding: bool) -> void:
	if not _can_accept_combat_input():
		return

	player_state.set_guard_held(is_guarding)
	_update_guard_debug()
	last_input_value.text = "High guard input: %s" % (
		"PRESSED" if is_guarding else "RELEASED"
	)


func _on_attack_state_changed(state: int, attack: int) -> void:
	attack_state_value.text = ATTACK_STATE_NAMES[state]
	current_attack_value.text = "None" if attack == -1 else ATTACK_NAMES[attack]


func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	stamina_bar.max_value = max_stamina
	stamina_bar.value = current_stamina
	stamina_value.text = "%.1f / %.1f" % [current_stamina, max_stamina]


func _on_opponent_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	opponent_stamina_bar.max_value = max_stamina
	opponent_stamina_bar.value = current_stamina
	opponent_stamina_value.text = "%.1f / %.1f" % [current_stamina, max_stamina]


func _on_player_kd_changed(current_meter: float, max_meter: float) -> void:
	player_kd_bar.max_value = max_meter
	player_kd_bar.value = current_meter
	player_kd_value.text = "KD %.0f / %.0f" % [current_meter, max_meter]


func _on_opponent_kd_changed(current_meter: float, max_meter: float) -> void:
	opponent_kd_bar.max_value = max_meter
	opponent_kd_bar.value = current_meter
	opponent_kd_value.text = "KD %.0f / %.0f" % [current_meter, max_meter]


func _on_opponent_knockdown(attack: int) -> void:
	last_input_value.text = "OPP DOWN! KD Meter full | %s" % ATTACK_NAMES[attack]
	knockdown_manager.begin_opponent_knockdown()


func _on_player_knockdown(attack_type: int) -> void:
	last_input_value.text = "PLAYER DOWN! KD Meter full | %s" % ATTACK_NAMES[attack_type]
	knockdown_manager.begin_player_knockdown()


func _on_match_hud_text_changed(text: String) -> void:
	match_status_value.text = text


func _on_round_hud_text_changed(text: String) -> void:
	round_status_value.text = text


func _on_score_hud_text_changed(text: String) -> void:
	score_status_value.text = text


func _on_match_finished(winner: int) -> void:
	var winner_name := "Player" if winner == knockdown_manager.Winner.PLAYER else "Opponent"
	last_input_value.text = "FINAL KO | Winner: %s" % winner_name


func _on_decision_required() -> void:
	last_input_value.text = "DECISION REQUIRED (scoring...)"


func _on_match_result_ready(result) -> void:
	var ResultType = preload("res://scripts/match_result_data.gd").ResultType
	var Winner = preload("res://scripts/match_result_data.gd").Winner
	match result.result_type:
		ResultType.KO:
			last_input_value.text = (
				"KO WIN: Player"
				if result.winner == Winner.PLAYER
				else "KO WIN: Opponent"
			)
		ResultType.DRAW:
			last_input_value.text = "DRAW %d - %d" % [
				result.player_total_score,
				result.opponent_total_score,
			]
		ResultType.DECISION:
			last_input_value.text = "%s %d - %d" % [
				(
					"PLAYER DECISION"
					if result.winner == Winner.PLAYER
					else "OPPONENT DECISION"
				),
				result.player_total_score,
				result.opponent_total_score,
			]
		_:
			last_input_value.text = "Match result"


func _on_opponent_attack_resolved(
	result: int,
	knockdown_damage: float,
	player_meter: float,
	was_knockdown: bool
) -> void:
	if result == defense_resolver.DefenseResult.HIT:
		_apply_player_hit_reaction(was_knockdown)

	if was_knockdown:
		return

	last_input_value.text = "%s | KD +%.1f | Player KD %.0f" % [
		DEFENSE_RESULT_NAMES[result],
		knockdown_damage,
		player_meter,
	]


func _on_player_attack_hit(
	attack: int,
	knockdown_damage: float,
	opponent_meter: float,
	was_knockdown: bool,
	result: int
) -> void:
	if result == offense_resolver.ResolveResult.HIT:
		_apply_opponent_hit_reaction(was_knockdown)

	if was_knockdown:
		return

	if result != offense_resolver.ResolveResult.HIT:
		last_input_value.text = "Player %s | %s" % [
			ATTACK_NAMES[attack],
			DEFENSE_RESULT_NAMES[result],
		]
		return

	last_input_value.text = "HIT | KD +%.1f | Opp KD %.0f" % [
		knockdown_damage,
		opponent_meter,
	]


func _apply_player_hit_reaction(was_knockdown: bool) -> void:
	if attack_state != null:
		attack_state.cancel_attack()
	if player_state != null:
		player_state.force_reset_to_idle()
	if was_knockdown:
		if player_hit_stun != null:
			player_hit_stun.clear_hit_stun()
		return
	if player_hit_stun != null:
		player_hit_stun.apply_hit_stun()


func _apply_opponent_hit_reaction(was_knockdown: bool) -> void:
	if opponent_attack_state != null:
		opponent_attack_state.cancel_attack()
	if opponent_action_state != null:
		opponent_action_state.force_reset_to_idle()
	if opponent_ai != null and opponent_ai.has_method("clear_pending_combat_decisions"):
		opponent_ai.clear_pending_combat_decisions()
	if was_knockdown:
		if opponent_hit_stun != null:
			opponent_hit_stun.clear_hit_stun()
		return
	if opponent_hit_stun != null:
		opponent_hit_stun.apply_hit_stun()


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
