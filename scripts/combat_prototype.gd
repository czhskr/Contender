extends Node

const ATTACK_NAMES := [
	"Left straight",
	"Right straight",
	"Left hook",
	"Right hook",
]
const EVADE_NAMES := [
	"NONE",
	"Evade Left",
	"Evade Down",
	"Evade Right",
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
	"GUARD",
]
const DEFENSE_RESULT_NAMES := ["HIT", "BLOCK", "EVADE"]

@onready var combat_input: Node = $PlayerCombatInput
@onready var attack_state: Node = $PlayerAttackState
@onready var stamina: Node = $PlayerStamina
@onready var player_state: Node = $PlayerActionState
@onready var player_evade: Node = $PlayerEvade
@onready var action_buffer: Node = $PlayerActionBuffer
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
@onready var finisher_impact_freeze: Node = $FinisherImpactFreeze
@onready var combat_visual_root: Node = $CombatVisualRoot
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
	_ensure_fatigue_vignette()
	combat_input.attack_requested.connect(_on_attack_requested)
	combat_input.evade_pressed.connect(_on_evade_pressed)
	combat_input.evade_hold_changed.connect(_on_evade_hold_changed)
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
	if opponent_ai != null and opponent_ai.has_method("_on_player_attack_resolved"):
		if not offense_resolver.attack_hit.is_connected(opponent_ai._on_player_attack_resolved):
			offense_resolver.attack_hit.connect(opponent_ai._on_player_attack_resolved)
	knockdown_manager.hud_text_changed.connect(_on_match_hud_text_changed)
	knockdown_manager.match_finished.connect(_on_match_finished)
	knockdown_manager.match_state_changed.connect(_on_match_state_for_evade)
	round_manager.hud_text_changed.connect(_on_round_hud_text_changed)
	round_manager.decision_required.connect(_on_decision_required)
	match_decision.hud_text_changed.connect(_on_score_hud_text_changed)
	match_decision.match_result_ready.connect(_on_match_result_ready)
	if player_hit_stun != null and player_hit_stun.has_signal("hit_stun_started"):
		player_hit_stun.hit_stun_started.connect(_on_player_hit_stun_started)
	if finisher_impact_freeze != null:
		finisher_impact_freeze.finisher_started.connect(_on_finisher_started)
		finisher_impact_freeze.finisher_finished.connect(_on_finisher_finished)

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


func _ensure_fatigue_vignette() -> void:
	var vignette := get_node_or_null("FatigueVignette")
	var created := vignette == null
	if created:
		vignette = preload("res://scripts/fatigue_vignette.gd").new()
		vignette.name = "FatigueVignette"
	vignette.player_stamina = stamina
	vignette.opponent_visual = get_node_or_null("CombatVisualRoot/OpponentVisual")
	if created:
		add_child(vignette)
		var hud := get_node_or_null("DebugHUD")
		if hud != null:
			move_child(vignette, hud.get_index())
	elif vignette.has_method("setup"):
		vignette.setup()


func _process(_delta: float) -> void:
	if not _can_accept_combat_input():
		_clear_action_buffer()
		return
	if player_hit_stun != null and player_hit_stun.is_hit_stunned():
		_clear_action_buffer()
		return
	_try_apply_held_evade_movement()
	_try_resolve_buffered_actions()


func _can_accept_combat_input() -> bool:
	if finisher_impact_freeze != null and finisher_impact_freeze.is_blocking_combat():
		return false
	return (
		knockdown_manager.can_accept_combat_input()
		and round_manager.can_accept_combat_input()
	)


func _clear_action_buffer() -> void:
	if action_buffer != null and action_buffer.has_method("clear"):
		action_buffer.clear()


func _on_player_hit_stun_started(_duration: float) -> void:
	_clear_action_buffer()
	_clear_evade_all()


func _on_attack_requested(attack: int) -> void:
	if not _can_accept_combat_input():
		last_input_value.text = "Blocked: match not fighting"
		_clear_action_buffer()
		return

	if player_hit_stun != null and player_hit_stun.is_hit_stunned():
		last_input_value.text = "Blocked: hit stun"
		_clear_action_buffer()
		return

	_sync_guard_release_if_needed()

	if _try_execute_player_attack(attack):
		return

	if _can_buffer_combat_action() or (
		attack_state.current_state == attack_state.AttackState.IDLE
		and not attack_state.is_hand_ready(attack)
	):
		action_buffer.buffer_attack(attack)
		last_input_value.text = "Buffered: %s" % ATTACK_NAMES[attack]
		return

	last_input_value.text = "Blocked: %s (player: %s)" % [
		ATTACK_NAMES[attack],
		PLAYER_STATE_NAMES[player_state.current_state],
	]


## Continuous movement target (always allowed when fighting; no stamina).
func _on_evade_hold_changed(direction: int) -> void:
	if player_evade == null:
		return
	if not _can_accept_combat_input() or (
		player_hit_stun != null and player_hit_stun.is_hit_stunned()
	):
		player_evade.center_movement()
		return
	if not _can_apply_evade_movement():
		return
	player_evade.set_movement_direction(direction)


## Explicit A/S/D press: try gameplay evade window (+ optional attack recovery cancel).
func _on_evade_pressed(direction: int) -> void:
	if not _can_accept_combat_input():
		last_input_value.text = "Blocked: match not fighting"
		return
	if player_hit_stun != null and player_hit_stun.is_hit_stunned():
		last_input_value.text = "Blocked: hit stun"
		return

	_sync_guard_release_if_needed()

	## Movement updates from hold_changed; ensure target matches this press.
	if _can_apply_evade_movement():
		player_evade.set_movement_direction(direction)

	if _try_begin_evade_window(direction):
		return

	## Buffer evade only during attack recovery (cancel window).
	if attack_state.is_recovering() and _can_buffer_combat_action():
		action_buffer.buffer_evade(direction)
		last_input_value.text = "Buffered: %s" % EVADE_NAMES[direction]
		return

	last_input_value.text = "Move %s (no evade window)" % EVADE_NAMES[direction]


## Startup/Active: no movement. Recovery: only after attack_to_evade progress.
func _can_apply_evade_movement() -> bool:
	if attack_state.current_state in [
		attack_state.AttackState.STARTUP,
		attack_state.AttackState.ACTIVE,
	]:
		return false
	if attack_state.is_recovering():
		return attack_state.get_recovery_progress() >= action_buffer.attack_to_evade
	return true


func _try_apply_held_evade_movement() -> void:
	if player_evade == null or combat_input == null:
		return
	if not _can_apply_evade_movement():
		return
	var held: int = combat_input.held_evade_direction
	if held == combat_input.EvadeDirection.NONE:
		return
	if player_evade.movement_direction != held:
		player_evade.set_movement_direction(held)


func _try_begin_evade_window(direction: int) -> bool:
	if direction == combat_input.EvadeDirection.NONE:
		return false
	## Startup / Active: never open gameplay evade.
	if attack_state.current_state in [
		attack_state.AttackState.STARTUP,
		attack_state.AttackState.ACTIVE,
	]:
		return false
	## Recovery: need attack_to_evade progress.
	if attack_state.is_recovering():
		if attack_state.get_recovery_progress() < action_buffer.attack_to_evade:
			return false
		attack_state.force_end_for_cancel()

	if player_evade.try_begin_window(direction):
		_clear_action_buffer()
		last_input_value.text = "Evade window: %s" % EVADE_NAMES[direction]
		return true
	return false


func _clear_evade_all() -> void:
	if player_evade != null:
		player_evade.clear_all()
	if combat_input != null and combat_input.has_method("clear_held_evade"):
		combat_input.clear_held_evade()


func _on_match_state_for_evade(state: int) -> void:
	if state != knockdown_manager.MatchState.FIGHTING:
		_clear_evade_all()


func _sync_guard_release_if_needed() -> void:
	## Guard has no recovery: once Space is up, leave GUARD immediately.
	if combat_input != null and combat_input.is_guarding:
		return
	if player_state != null and player_state.is_guarding():
		player_state.set_guard_held(false)
		_update_guard_debug()


func _on_guard_changed(is_guarding: bool) -> void:
	if not is_guarding:
		if action_buffer != null and action_buffer.has_method("clear_guard"):
			action_buffer.clear_guard()

	if not _can_accept_combat_input():
		return

	if player_hit_stun != null and player_hit_stun.is_hit_stunned():
		player_state.set_guard_held(false)
		_update_guard_debug()
		return

	if is_guarding and not player_state.can_attack() and _can_buffer_combat_action():
		player_state.set_guard_held(true)
		action_buffer.buffer_guard()
		_update_guard_debug()
		last_input_value.text = "High guard input: PRESSED (buffered)"
		return

	player_state.set_guard_held(is_guarding)
	if is_guarding:
		_clear_action_buffer()
	elif combat_input.held_evade_direction != combat_input.EvadeDirection.NONE:
		## Guard released while A/S/D held — resume continuous movement.
		_on_evade_hold_changed(combat_input.held_evade_direction)
	_update_guard_debug()
	last_input_value.text = "High guard input: %s" % (
		"PRESSED" if is_guarding else "RELEASED"
	)


func _trait_attack_cost(base_cost: float) -> float:
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager == null:
		return base_cost
	return preload("res://scripts/trait_math.gd").attack_cost(base_cost, manager.player_traits)


func _attack_link_threshold() -> float:
	var threshold: float = action_buffer.attack_to_attack
	var manager = preload("res://scripts/trait_manager.gd").find(get_tree())
	if manager != null:
		threshold *= preload("res://scripts/trait_math.gd").product(manager.player_traits, "attack_link_threshold")
	return clampf(threshold, 0.0, 1.0)


func _can_buffer_combat_action() -> bool:
	return attack_state.current_state != attack_state.AttackState.IDLE


func _try_execute_player_attack(attack: int) -> bool:
	if not player_state.can_attack():
		return false

	var attack_data = attack_state.get_attack_data(attack)
	if attack_data == null:
		last_input_value.text = "Missing attack data: %s" % ATTACK_NAMES[attack]
		return false

	var cost: float = _trait_attack_cost(attack_data.stamina_cost)
	if not stamina.can_afford(cost):
		last_input_value.text = "Insufficient stamina: %s (%.1f / %.1f)" % [
			ATTACK_NAMES[attack],
			stamina.current_stamina,
			cost,
		]
		return false

	if attack_state.try_start_attack(attack):
		if player_evade != null:
			player_evade.end_window()
			player_evade.center_movement()
		stamina.spend_for_attack(cost)
		_clear_action_buffer()
		last_input_value.text = "Accepted: %s" % ATTACK_NAMES[attack]
		return true
	return false


func _try_resolve_buffered_actions() -> void:
	if action_buffer != null and action_buffer.has_buffered():
		match action_buffer.kind:
			action_buffer.Kind.ATTACK:
				var attack: int = action_buffer.attack_index
				if attack_state.current_state == attack_state.AttackState.IDLE:
					if not attack_state.is_hand_ready(attack):
						return
					if not _try_execute_player_attack(attack):
						_clear_action_buffer()
					return
				if not _can_cancel_into_attack(attack):
					return
				_unlock_current_action_for_cancel()
				if not _try_execute_player_attack(attack):
					_clear_action_buffer()
			action_buffer.Kind.EVADE:
				if not _can_cancel_into_evade():
					return
				var direction: int = action_buffer.evade_direction
				_unlock_current_action_for_cancel()
				player_evade.set_movement_direction(direction)
				if _try_begin_evade_window(direction):
					_clear_action_buffer()
				else:
					_clear_action_buffer()
					last_input_value.text = "Move %s (no evade window)" % EVADE_NAMES[direction]
			action_buffer.Kind.GUARD:
				if not combat_input.is_guarding:
					action_buffer.clear_guard()
					return
				if not _can_cancel_into_guard():
					return
				_unlock_current_action_for_cancel()
				player_state.set_guard_held(true)
				_clear_action_buffer()
				_update_guard_debug()
				last_input_value.text = "Cancel -> High Guard"
			_:
				pass
		return

	if combat_input.is_guarding and _can_cancel_into_guard():
		_unlock_current_action_for_cancel()
		player_state.set_guard_held(true)
		_update_guard_debug()
		last_input_value.text = "Cancel -> High Guard"


func _unlock_current_action_for_cancel() -> void:
	if attack_state.current_state != attack_state.AttackState.IDLE:
		attack_state.force_end_for_cancel()


func _can_cancel_into_attack(next_attack: int) -> bool:
	if not attack_state.is_recovering():
		return false
	return AttackData.can_recovery_cancel(
		attack_state.get_recovery_progress(),
		_attack_link_threshold(),
		attack_state.current_attack,
		next_attack
	)


func _can_cancel_into_evade() -> bool:
	if attack_state.is_recovering():
		return attack_state.get_recovery_progress() >= action_buffer.attack_to_evade
	return false


func _can_cancel_into_guard() -> bool:
	if attack_state.is_recovering():
		return attack_state.get_recovery_progress() >= action_buffer.attack_to_guard
	return false


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


func _on_player_knockdown(attack_type: int) -> void:
	last_input_value.text = "PLAYER DOWN! KD Meter full | %s" % ATTACK_NAMES[attack_type]


func _on_finisher_started(downed_side: int) -> void:
	_clear_action_buffer()
	if round_manager != null and round_manager.has_method("pause_for_finisher"):
		round_manager.pause_for_finisher()
	if defense_resolver != null:
		defense_resolver.meter_updates_enabled = false
	if offense_resolver != null:
		offense_resolver.meter_updates_enabled = false
	if opponent_ai != null and opponent_ai.has_method("clear_pending_combat_decisions"):
		opponent_ai.clear_pending_combat_decisions()
	last_input_value.text = (
		"FINISHER FREEZE → Opponent"
		if downed_side == knockdown_manager.DownedSide.OPPONENT
		else "FINISHER FREEZE → Player"
	)


func _on_finisher_finished(downed_side: int) -> void:
	## KnockdownManager starts Count after this freeze. Clear a leftover player attack pose.
	if downed_side == knockdown_manager.DownedSide.OPPONENT or downed_side == knockdown_manager.DownedSide.PLAYER:
		if attack_state != null:
			attack_state.cancel_attack()
		if player_state != null:
			player_state.force_reset_to_idle()
		_clear_action_buffer()


func _on_match_hud_text_changed(text: String) -> void:
	match_status_value.text = text


func _on_round_hud_text_changed(text: String) -> void:
	round_status_value.text = text


func _on_score_hud_text_changed(text: String) -> void:
	score_status_value.text = text


func _on_match_finished(winner: int) -> void:
	if finisher_impact_freeze != null and finisher_impact_freeze.has_method("cancel_and_restore"):
		finisher_impact_freeze.cancel_and_restore()
	var winner_name := "Player" if winner == knockdown_manager.Winner.PLAYER else "Opponent"
	last_input_value.text = "FINAL KO | Winner: %s" % winner_name


func _on_decision_required() -> void:
	last_input_value.text = "DECISION REQUIRED (scoring...)"


func _on_match_result_ready(result) -> void:
	if finisher_impact_freeze != null and finisher_impact_freeze.has_method("cancel_and_restore"):
		finisher_impact_freeze.cancel_and_restore()
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
	if not was_knockdown:
		return
	_clear_action_buffer()
	_clear_evade_all()
	if attack_state != null:
		attack_state.cancel_attack()
	if player_state != null:
		player_state.force_reset_to_idle()


func _apply_opponent_hit_reaction(was_knockdown: bool) -> void:
	if not was_knockdown:
		return
	if opponent_attack_state != null:
		opponent_attack_state.cancel_attack()
	if opponent_action_state != null:
		opponent_action_state.force_reset_to_idle()
	if opponent_ai != null and opponent_ai.has_method("clear_pending_combat_decisions"):
		opponent_ai.clear_pending_combat_decisions(false)


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
