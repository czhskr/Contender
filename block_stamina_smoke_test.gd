extends SceneTree

## Block stamina damage uses each attack's base stamina cost.
## godot --headless --path . -s res://block_stamina_smoke_test.gd

const PlayerStaminaType = preload("res://scripts/player_stamina.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const DefenseType = preload("res://scripts/player_defense_resolver.gd")
const OffenseType = preload("res://scripts/player_offense_resolver.gd")
const ActionType = preload("res://scripts/player_action_state.gd")
const OppActionType = preload("res://scripts/opponent_action_state.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const OppAttackType = preload("res://scripts/opponent_attack_data.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")
const EvadeType = preload("res://scripts/player_evade.gd")
const TraitType = preload("res://scripts/fighter_trait.gd")
const TraitMath = preload("res://scripts/trait_math.gd")
const ManagerType = preload("res://scripts/trait_manager.gd")
const HudType = preload("res://scripts/combat_hud.gd")

const COSTS := [4.0, 5.0, 7.0, 8.0]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_hold_is_free(failures)
	_check_block_costs(failures, true)
	_check_block_costs(failures, false)
	_check_hit_and_evade(failures)
	_check_clamp_and_guard(failures)
	_check_guard_break(failures)
	_check_regen(failures)
	_check_traits(failures)
	_check_hud(failures)
	if failures.is_empty():
		print("SMOKE PASS: block stamina")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_hold_is_free(failures: Array[String]) -> void:
	var stamina := _player_stamina(80.0)
	root.add_child(stamina)
	var action := _player_guard()
	stamina._time_since_regen_block = 10.0
	stamina._process(0.2)
	if not is_equal_approx(stamina.current_stamina, 80.0 + 0.2 * stamina.regeneration_per_second):
		failures.append("holding guard stopped stamina regen")
	if action.current_state != ActionType.PlayerState.GUARD:
		failures.append("guard did not stay held")
	action.free()
	stamina.free()


func _check_block_costs(failures: Array[String], defender_is_player: bool) -> void:
	var side := "player" if defender_is_player else "opponent"
	for attack in 4:
		var before := 100.0
		var after := _block(defender_is_player, attack, before)
		if not is_equal_approx(after, before - COSTS[attack] * 2.0):
			failures.append("%s block of attack %d left %.1f" % [side, attack, after])


func _check_hit_and_evade(failures: Array[String]) -> void:
	var hit := _player_block_setup()
	var stamina: PlayerStaminaType = hit["stamina"]
	var defense: DefenseType = hit["defense"]
	var action: ActionType = hit["action"]
	defense.resolve_attack(_opp_attack(1))
	if not is_equal_approx(stamina.current_stamina, 100.0):
		failures.append("clean HIT spent block stamina")
	var evade := EvadeType.new()
	defense.player_evade = evade
	evade.try_begin_window(EvadeType.Direction.LEFT)
	action.set_guard_held(true)
	defense.resolve_attack(_opp_attack(1))
	if not is_equal_approx(stamina.current_stamina, 100.0):
		failures.append("EVADE spent block stamina")
	evade.free()
	action.free()
	stamina.free()
	hit["meter"].free()
	defense.free()


func _check_clamp_and_guard(failures: Array[String]) -> void:
	var built := _player_block_setup()
	var stamina: PlayerStaminaType = built["stamina"]
	var action: ActionType = built["action"]
	var defense: DefenseType = built["defense"]
	stamina.current_stamina = 3.0
	action.set_guard_held(true)
	defense.resolve_attack(_opp_attack(1))
	if not is_equal_approx(stamina.current_stamina, 0.0):
		failures.append("block did not clamp stamina at 0")
	if action.is_guarding():
		failures.append("stamina 0 did not release the guard")
	defense.resolve_attack(_opp_attack(0))
	if not is_equal_approx(stamina.current_stamina, 0.0):
		failures.append("stamina went below 0")
	if action.is_guarding():
		failures.append("empty stamina started another guard by itself")
	action.free()
	stamina.free()
	built["meter"].free()
	defense.free()


func _check_guard_break(failures: Array[String]) -> void:
	var kept := _player_block_setup()
	var kept_stamina: PlayerStaminaType = kept["stamina"]
	var kept_action: ActionType = kept["action"]
	kept_stamina.current_stamina = 30.0
	kept_action.set_guard_held(true)
	kept["defense"].resolve_attack(_opp_attack(1))
	if not is_equal_approx(kept_stamina.current_stamina, 20.0) or not kept_action.is_guarding():
		failures.append("a block that leaves stamina should keep the guard")
	kept_action.free()
	kept_stamina.free()
	kept["meter"].free()
	kept["defense"].free()

	var broken := _player_block_setup()
	var stamina: PlayerStaminaType = broken["stamina"]
	var action: ActionType = broken["action"]
	var defense: DefenseType = broken["defense"]
	var broke := [false]
	defense.block_guard_broken.connect(func() -> void: broke[0] = true)
	stamina.current_stamina = 10.0
	action.set_guard_held(true)
	var attack := AttackStateType.new()
	attack.print_action_speed = false
	attack.current_state = attack.AttackState.ACTIVE
	defense.resolve_attack(_opp_attack(1))
	if not is_equal_approx(stamina.current_stamina, 0.0) or action.is_guarding() or not broke[0]:
		failures.append("block to zero did not break the guard")
	if attack.current_state != attack.AttackState.ACTIVE:
		failures.append("guard break cancelled the attack")
	var evade := EvadeType.new()
	for direction in [EvadeType.Direction.LEFT, EvadeType.Direction.RIGHT, EvadeType.Direction.DOWN]:
		evade.set_movement_direction(direction)
		if evade.movement_direction != direction:
			failures.append("guard break blocked evade direction %d" % direction)
	evade.free()
	var proto = preload("res://scripts/combat_prototype.gd").new()
	proto.stamina = stamina
	proto.player_state = action
	proto._on_block_guard_broken()
	if proto._can_raise_guard():
		failures.append("held space could raise guard at zero stamina")
	stamina.current_stamina = 10.0
	if proto._can_raise_guard():
		failures.append("recovered stamina raised guard while space stayed held")
	proto._guard_release_required = false
	if not proto._can_raise_guard():
		failures.append("guard stayed locked after space release")
	action.set_guard_held(true)
	if not action.is_guarding():
		failures.append("a new press did not raise guard after stamina recovered")
	var hit := _player_block_setup()
	hit["action"].set_guard_held(true)
	hit["defense"].resolve_attack(_opp_attack(1))
	# The setup starts at 100, so this is a clean block that stays up. Hit without guard:
	var clean_action: ActionType = ActionType.new()
	clean_action.print_state_changes = false
	hit["defense"].player_action_state = clean_action
	var before: float = hit["stamina"].current_stamina
	hit["defense"].resolve_attack(_opp_attack(1))
	if not is_equal_approx(hit["stamina"].current_stamina, before):
		failures.append("a clean HIT triggered block stamina")
	attack.free()
	action.free()
	stamina.free()
	broken["meter"].free()
	defense.free()
	clean_action.free()
	hit["action"].free()
	hit["stamina"].free()
	hit["meter"].free()
	hit["defense"].free()
	proto.free()

	var opp_stamina := _opponent_stamina(10.0)
	var guard := OppActionType.new()
	guard.print_state_changes = false
	guard.set_guard_held(true)
	var attacks := AttackStateType.new()
	attacks.attacks = [_player_attack(1)]
	var offense := OffenseType.new()
	offense.player_attack_state = attacks
	offense.opponent_action_state = guard
	offense.opponent_knockdown_meter = _meter()
	offense.opponent_stamina = opp_stamina
	offense.print_hit_results = false
	offense.resolve_hit_now(1)
	if not is_equal_approx(opp_stamina.current_stamina, 0.0) or guard.is_guarding():
		failures.append("opponent block to zero left the guard up")
	var ai = preload("res://scripts/opponent_ai.gd").new()
	ai.opponent_action_state = guard
	ai.opponent_stamina = opp_stamina
	ai._begin_guard_hold(0.5)
	if guard.is_guarding():
		failures.append("opponent started a guard at zero stamina")
	opp_stamina.current_stamina = 10.0
	ai._begin_guard_hold(0.5)
	if not guard.is_guarding():
		failures.append("opponent could not guard after stamina recovered")
	ai.free()
	attacks.free()
	guard.free()
	offense.opponent_knockdown_meter.free()
	opp_stamina.free()
	offense.free()


func _check_regen(failures: Array[String]) -> void:
	var stamina := _player_stamina(50.0)
	root.add_child(stamina)
	stamina._time_since_regen_block = 10.0
	stamina.apply_block_stamina_damage(5.0)
	if stamina._time_since_regen_block != 0.0:
		failures.append("block did not reset regen delay")
	stamina._process(0.64)
	if not is_equal_approx(stamina.current_stamina, 45.0):
		failures.append("stamina regenerated inside the block delay")
	stamina._process(0.02)
	if stamina.current_stamina <= 45.0:
		failures.append("stamina did not resume after the shared regen delay")
	stamina.free()


func _check_traits(failures: Array[String]) -> void:
	var heavy := TraitType.new()
	heavy.attack_cost = 2.0
	var efficient := TraitType.new()
	efficient.attack_cost = 0.5
	if not is_equal_approx(TraitMath.attack_cost(5.0, [heavy]), 10.0):
		failures.append("heavy hands fixture did not raise attack cost")
	if not is_equal_approx(TraitMath.attack_cost(5.0, [efficient]), 2.5):
		failures.append("efficient striker fixture did not lower attack cost")
	var built := _player_block_setup()
	var defense: DefenseType = built["defense"]
	var stamina: PlayerStaminaType = built["stamina"]
	built["action"].set_guard_held(true)
	defense.resolve_attack(_opp_attack(1))
	if not is_equal_approx(stamina.current_stamina, 90.0):
		failures.append("block used a trait-adjusted cost")
	var iron := TraitType.new()
	iron.iron_guard = true
	var manager := ManagerType.new()
	manager.print_pools = false
	root.add_child(manager)
	manager.player_traits = [iron]
	root.add_child(defense)
	stamina.current_stamina = 100.0
	var meter: MeterType = built["meter"]
	var kd_before := meter.current_meter
	defense.resolve_attack(_opp_attack(1))
	if not is_equal_approx(meter.current_meter, kd_before):
		failures.append("iron guard still took block KD")
	if not is_equal_approx(stamina.current_stamina, 90.0):
		failures.append("iron guard removed block stamina damage")
	stamina.current_stamina = 10.0
	built["action"].set_guard_held(true)
	defense.resolve_attack(_opp_attack(1))
	if not is_equal_approx(stamina.current_stamina, 0.0) or built["action"].is_guarding():
		failures.append("iron guard kept the guard at zero stamina")
	manager.free()
	built["action"].free()
	stamina.free()
	meter.free()
	defense.free()


func _check_hud(failures: Array[String]) -> void:
	var host := Node.new()
	root.add_child(host)
	var stamina := _player_stamina(100.0)
	stamina.name = "PlayerStamina"
	host.add_child(stamina)
	var hud: HudType = HudType.new()
	host.add_child(hud)
	stamina.apply_block_stamina_damage(5.0)
	if not is_equal_approx(hud._meter_target[0], 95.0):
		failures.append("HUD did not track block stamina")
	if hud._chunk_hold[0] <= 0.0:
		failures.append("block stamina did not show a damage chunk")
	if hud._shake_time[0] >= 0.0 or hud._flash_time[0] >= 0.0 or hud._punch_time[0] >= 0.0:
		failures.append("block stamina started a KD impact")
	hud.free()
	stamina.free()
	host.free()


func _block(defender_is_player: bool, attack: int, stamina_now: float) -> float:
	if defender_is_player:
		var built := _player_block_setup()
		var stamina: PlayerStaminaType = built["stamina"]
		stamina.current_stamina = stamina_now
		built["action"].set_guard_held(true)
		built["defense"].resolve_attack(_opp_attack(attack))
		var left := stamina.current_stamina
		built["action"].free()
		stamina.free()
		built["meter"].free()
		built["defense"].free()
		return left
	var opp_stamina := _opponent_stamina(stamina_now)
	var guard := OppActionType.new()
	guard.print_state_changes = false
	guard.set_guard_held(true)
	var attacks := AttackStateType.new()
	attacks.attacks = [_player_attack(attack)]
	var offense := OffenseType.new()
	offense.player_attack_state = attacks
	offense.opponent_action_state = guard
	offense.opponent_knockdown_meter = _meter()
	offense.opponent_stamina = opp_stamina
	offense.print_hit_results = false
	offense.resolve_hit_now(attack)
	var left := opp_stamina.current_stamina
	attacks.free()
	guard.free()
	offense.opponent_knockdown_meter.free()
	opp_stamina.free()
	offense.free()
	return left


func _player_block_setup() -> Dictionary:
	var stamina := _player_stamina(100.0)
	var action := ActionType.new()
	action.print_state_changes = false
	var defense := DefenseType.new()
	defense.player_action_state = action
	defense.player_stamina = stamina
	defense.player_knockdown_meter = _meter()
	defense.print_hit_results = false
	return {"stamina": stamina, "action": action, "defense": defense, "meter": defense.player_knockdown_meter}


func _player_guard() -> ActionType:
	var action := ActionType.new()
	action.print_state_changes = false
	action.set_guard_held(true)
	return action


func _player_stamina(current: float) -> PlayerStaminaType:
	var stamina := PlayerStaminaType.new()
	stamina.initial_current_stamina = current
	stamina._ready()
	return stamina


func _opponent_stamina(current: float) -> OpponentStaminaType:
	var stamina := OpponentStaminaType.new()
	stamina.initial_current_stamina = current
	stamina._ready()
	return stamina


func _meter() -> MeterType:
	var meter := MeterType.new()
	meter._ready()
	return meter


func _opp_attack(attack: int) -> Resource:
	var data := OppAttackType.new()
	data.attack_type = attack
	data.stamina_cost = COSTS[attack]
	data.knockdown_damage = 8.0
	return data


func _player_attack(attack: int) -> Resource:
	var data := AttackDataType.new()
	data.attack_type = attack
	data.stamina_cost = COSTS[attack]
	data.knockdown_damage = 8.0
	return data
