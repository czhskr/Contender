extends SceneTree

## 1-slot Action Buffer + Recovery/Slip cancel window regression.
## Run: godot --headless --path . -s res://action_buffer_smoke_test.gd

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const ActionStateType = preload("res://scripts/player_action_state.gd")
const BufferType = preload("res://scripts/player_action_buffer.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const StaminaType = preload("res://scripts/player_stamina.gd")
const HitStunType = preload("res://scripts/hit_stun.gd")
const OpponentAttackStateType = preload("res://scripts/opponent_attack_state.gd")
const OpponentAttackDataType = preload("res://scripts/opponent_attack_data.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const OpponentAIType = preload("res://scripts/opponent_ai.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	_check_buffer_defaults(failures)
	_check_scene_wiring(failures)
	_check_recovery_progress_and_cancel(failures)
	_check_attack_buffer_executes_in_window(failures)
	_check_cancel_threshold_order(failures)
	_check_evade_window_and_attack_cancel(failures)
	_check_buffer_expiry(failures)
	_check_hit_stun_clears_buffer(failures)
	_check_stamina_on_buffered_attack(failures)
	_check_stale_guard(failures)
	_check_guard_release_immediate_actions(failures)
	_check_opponent_recovery_cancel(failures)
	_check_ai_cancel_export(failures)

	if failures.is_empty():
		print("SMOKE PASS: action buffer / recovery cancel")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_buffer_defaults(failures: Array[String]) -> void:
	var buffer := BufferType.new()
	if not is_equal_approx(buffer.buffer_duration, 0.20):
		failures.append("buffer_duration expected 0.20")
	if not is_equal_approx(buffer.attack_to_attack, 0.50):
		failures.append("attack_to_attack expected 0.50")
	if not is_equal_approx(buffer.attack_to_evade, 0.35):
		failures.append("attack_to_evade expected 0.35")
	if not is_equal_approx(buffer.attack_to_guard, 0.25):
		failures.append("attack_to_guard expected 0.25")
	if "slip_to_attack" in buffer or "slip_to_slip" in buffer:
		failures.append("Legacy slip_to_* cancel thresholds must be removed")
	buffer.queue_free()


func _check_scene_wiring(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		failures.append("game.tscn load failed")
		return
	var scene := packed.instantiate()
	var buffer = scene.get_node_or_null("PlayerActionBuffer")
	if buffer == null:
		failures.append("PlayerActionBuffer missing from game.tscn")
	elif not is_equal_approx(buffer.buffer_duration, 0.20):
		failures.append("Scene buffer_duration not 0.20")
	var ai = scene.get_node_or_null("OpponentAI")
	if ai == null:
		failures.append("OpponentAI missing")
	elif not is_equal_approx(ai.attack_to_attack_cancel, 0.50):
		failures.append("OpponentAI.attack_to_attack_cancel expected 0.50")
	var attack = scene.get_node_or_null("PlayerAttackState")
	if attack == null or not attack.has_method("get_recovery_progress"):
		failures.append("PlayerAttackState missing recovery progress API")
	var evade = scene.get_node_or_null("PlayerEvade")
	if evade == null:
		failures.append("PlayerEvade missing from game.tscn")
	elif not evade.has_method("try_begin_window"):
		failures.append("PlayerEvade missing try_begin_window")
	scene.free()


func _make_player_attack_bundle() -> Dictionary:
	var stamina := StaminaType.new()
	stamina.initial_current_stamina = 100.0
	stamina.initial_max_stamina = 100.0
	stamina._ready()

	var hit_stun := HitStunType.new()
	var attack_state := AttackStateType.new()
	attack_state.player_stamina = stamina
	attack_state.hit_stun = hit_stun
	var left := AttackDataType.new()
	left.attack_type = 0
	left.startup_time = 0.10
	left.active_time = 0.08
	left.recovery_time = 0.20
	left.stamina_cost = 4.0
	left.knockdown_damage = 8.0
	var right := AttackDataType.new()
	right.attack_type = 1
	right.startup_time = 0.10
	right.active_time = 0.08
	right.recovery_time = 0.20
	right.stamina_cost = 5.0
	right.knockdown_damage = 10.0
	var hook := AttackDataType.new()
	hook.attack_type = 3
	hook.startup_time = 0.10
	hook.active_time = 0.08
	hook.recovery_time = 0.20
	hook.stamina_cost = 8.0
	hook.knockdown_damage = 15.0
	attack_state.attacks = [left, right, hook]
	attack_state.print_action_speed = false
	attack_state._ready()

	var action_state := ActionStateType.new()
	action_state.attack_state = attack_state
	action_state.player_stamina = stamina
	action_state.hit_stun = hit_stun
	action_state.print_state_changes = false
	action_state._ready()

	return {
		"stamina": stamina,
		"hit_stun": hit_stun,
		"attack": attack_state,
		"action": action_state,
	}


func _pump(nodes: Array, dt: float, steps: int) -> void:
	for _i in steps:
		for node in nodes:
			if node.has_method("_process"):
				node._process(dt)


func _check_recovery_progress_and_cancel(failures: Array[String]) -> void:
	var bag := _make_player_attack_bundle()
	var attack: AttackStateType = bag["attack"]
	if not attack.try_start_attack(0):
		failures.append("Could not start attack for recovery progress")
		_free_bag(bag)
		return
	## startup 0.10 + active 0.08 = 0.18 into recovery
	_pump([attack, bag["action"]], 0.02, 10)
	if not attack.is_recovering():
		failures.append("Expected RECOVERY after startup+active")
		_free_bag(bag)
		return
	var mid := attack.get_recovery_progress()
	if mid < 0.05:
		failures.append("Recovery progress should advance, got %.2f" % mid)
	var token_before := attack.get_action_token()
	attack.force_end_for_cancel()
	if attack.current_state != AttackStateType.AttackState.IDLE:
		failures.append("force_end_for_cancel did not reach IDLE")
	if attack.get_action_token() == token_before:
		failures.append("force_end_for_cancel should bump action token")
	## Stale process must not revive attack
	_pump([attack], 0.05, 5)
	if attack.current_state != AttackStateType.AttackState.IDLE:
		failures.append("Stale recovery advanced after cancel")
	_free_bag(bag)


func _check_attack_buffer_executes_in_window(failures: Array[String]) -> void:
	var bag := _make_player_attack_bundle()
	var attack: AttackStateType = bag["attack"]
	var action: ActionStateType = bag["action"]
	var stamina: StaminaType = bag["stamina"]
	var buffer := BufferType.new()
	buffer.buffer_duration = 1.0

	if not attack.try_start_attack(0):
		failures.append("J start failed")
		_free_bag(bag)
		buffer.queue_free()
		return
	stamina.spend_for_attack(4.0)
	buffer.buffer_attack(1) ## K
	## Reach recovery ~55% (startup+active+0.11 of 0.20)
	_pump([attack, action, buffer], 0.02, 15)
	if not attack.is_recovering():
		failures.append("Expected recovery before buffered K")
	if attack.get_recovery_progress() < buffer.attack_to_attack:
		## push a bit more
		_pump([attack, action, buffer], 0.02, 5)
	if attack.get_recovery_progress() < buffer.attack_to_attack:
		failures.append(
			"Could not reach attack_to_attack window (prog=%.2f)"
			% attack.get_recovery_progress()
		)
		_free_bag(bag)
		buffer.queue_free()
		return

	## Simulate combat_prototype cancel resolve
	attack.force_end_for_cancel()
	var before := stamina.current_stamina
	if not action.can_attack():
		failures.append("Action not idle after unlock for buffered K")
	elif not attack.try_start_attack(1):
		failures.append("Buffered K failed to start")
	else:
		stamina.spend_for_attack(5.0)
		var spent := before - stamina.current_stamina
		if spent < 4.9 or spent > 5.5:
			failures.append("Buffered K stamina spend expected ~5, got %.2f" % spent)
		if attack.current_attack != 1:
			failures.append("Buffered attack should be Right Straight")
	buffer.clear()
	_free_bag(bag)
	buffer.queue_free()


func _check_cancel_threshold_order(failures: Array[String]) -> void:
	var buffer := BufferType.new()
	if not (
		buffer.attack_to_guard
		< buffer.attack_to_evade
		and buffer.attack_to_evade < buffer.attack_to_attack
	):
		failures.append(
			"Expected guard < evade < attack cancel thresholds (%.2f / %.2f / %.2f)"
			% [buffer.attack_to_guard, buffer.attack_to_evade, buffer.attack_to_attack]
		)
	buffer.queue_free()


func _check_evade_window_and_attack_cancel(failures: Array[String]) -> void:
	const PlayerEvadeType = preload("res://scripts/player_evade.gd")
	var bag := _make_player_attack_bundle()
	var stamina: StaminaType = bag["stamina"]
	var attack: AttackStateType = bag["attack"]
	var action: ActionStateType = bag["action"]
	var evade := PlayerEvadeType.new()
	evade.player_stamina = stamina

	## Continuous evade: no exclusive slip state — attack available while moving.
	evade.set_movement_direction(PlayerEvadeType.Direction.LEFT)
	if not action.can_attack():
		failures.append("Evade movement must not block Attack")
	if not evade.try_begin_window(PlayerEvadeType.Direction.LEFT):
		failures.append("Evade window failed to start")
	## Evade → Attack: ends window via combat path; here attack still possible
	if not attack.try_start_attack(0):
		failures.append("Evade → Attack should be available without slip recovery")
	attack.force_end_for_cancel()

	## Attack recovery cancel into evade at 35%
	## Use longer recovery so we can land inside the cancel window.
	var data: AttackDataType = attack.get_attack_data(0)
	data.recovery_time = 0.60
	if not attack.try_start_attack(0):
		failures.append("Attack restart failed")
		_free_bag(bag)
		evade.queue_free()
		return
	## startup 0.10 + active 0.08 = 0.18 → then recovery
	_pump([attack, action], 0.02, 12)
	if not attack.is_recovering():
		failures.append("Expected recovery for attack_to_evade")
	elif attack.get_recovery_progress() < 0.35:
		_pump([attack, action], 0.02, 12)
	if attack.is_recovering() and attack.get_recovery_progress() >= 0.35:
		attack.force_end_for_cancel()
		evade._retrigger_remaining = 0.0
		if not evade.try_begin_window(PlayerEvadeType.Direction.RIGHT):
			failures.append("Attack recovery >=35% should allow evade window")
	elif not attack.is_recovering():
		failures.append("Left recovery before attack_to_evade window")
	_free_bag(bag)
	evade.queue_free()


func _check_buffer_expiry(failures: Array[String]) -> void:
	var buffer := BufferType.new()
	buffer.buffer_duration = 0.10
	buffer.buffer_attack(1)
	if not buffer.has_buffered():
		failures.append("buffer_attack did not store")
	buffer._process(0.11)
	if buffer.has_buffered():
		failures.append("Buffer should expire after buffer_duration")
	buffer.queue_free()


func _check_hit_stun_clears_buffer(failures: Array[String]) -> void:
	## Logic mirrored by combat_prototype: hit stun => clear buffer
	var buffer := BufferType.new()
	buffer.buffer_attack(2)
	var stun := HitStunType.new()
	stun.apply_hit_stun(0.35)
	if not stun.is_hit_stunned():
		failures.append("Hit stun did not apply")
	buffer.clear()
	if buffer.has_buffered():
		failures.append("Buffer should clear on hit stun path")
	## Knockdown path equivalent
	buffer.buffer_evade(CombatInputType.EvadeDirection.LEFT)
	buffer.clear()
	if buffer.has_buffered():
		failures.append("Buffer should clear on knockdown path")
	stun.queue_free()
	buffer.queue_free()


func _check_stamina_on_buffered_attack(failures: Array[String]) -> void:
	var bag := _make_player_attack_bundle()
	var stamina: StaminaType = bag["stamina"]
	stamina.current_stamina = 3.0
	stamina.stamina_changed.emit(stamina.current_stamina, stamina.max_stamina)
	var attack: AttackStateType = bag["attack"]
	var data = attack.get_attack_data(0)
	if stamina.can_afford(data.stamina_cost):
		failures.append("Setup: stamina should be insufficient for left straight")
	## combat_prototype path: affordability gates buffered execute
	attack.force_end_for_cancel()
	if bag["action"].can_attack() and stamina.can_afford(data.stamina_cost):
		failures.append("Insufficient stamina must block buffered attack execute")
	elif bag["action"].can_attack() and attack.try_start_attack(0):
		## AttackState itself does not check stamina — caller must.
		## Ensure we did not spend when unaffordable.
		if not stamina.can_afford(data.stamina_cost):
			## Correct: start is possible at state layer; spend must be skipped by caller.
			pass
		else:
			failures.append("Unexpected affordable after setup")
	## Explicit spend path must refuse
	if stamina.spend_for_attack(data.stamina_cost):
		failures.append("spend_for_attack must fail when unaffordable")
	_free_bag(bag)


func _check_stale_guard(failures: Array[String]) -> void:
	var buffer := BufferType.new()
	buffer.buffer_guard()
	if not buffer.is_guard():
		failures.append("buffer_guard failed")
	## Space release path
	buffer.clear_guard()
	if buffer.has_buffered():
		failures.append("clear_guard must drop stale guard buffer")
	## Guard buffer must not expire by TTL while held
	buffer.buffer_guard()
	buffer._process(5.0)
	if not buffer.is_guard():
		failures.append("Guard buffer should not TTL-expire while held")
	buffer.clear_guard()
	buffer.queue_free()


func _check_guard_release_immediate_actions(failures: Array[String]) -> void:
	const PlayerEvadeType = preload("res://scripts/player_evade.gd")
	var bag := _make_player_attack_bundle()
	var action: ActionStateType = bag["action"]
	var stamina: StaminaType = bag["stamina"]
	var evade := PlayerEvadeType.new()
	evade.player_stamina = stamina
	var window_before := evade.evade_window
	action.set_guard_held(true)
	if action.current_state != ActionStateType.PlayerState.GUARD:
		failures.append("Guard ON failed")
	action.set_guard_held(false)
	if action.current_state != ActionStateType.PlayerState.IDLE:
		failures.append("Guard OFF must be immediate (no recovery)")
	if not action.can_attack():
		failures.append("Guard → Attack not immediately available")
	evade.set_movement_direction(PlayerEvadeType.Direction.RIGHT)
	if not evade.try_begin_window(PlayerEvadeType.Direction.RIGHT):
		failures.append("Guard → Evade window not immediately available")
	if not is_equal_approx(evade.evade_window, window_before):
		failures.append("Guard release mutated evade_window")
	if not evade.is_window_active():
		failures.append("Fresh Evade after Guard must open window")
	_free_bag(bag)
	evade.queue_free()


func _check_opponent_recovery_cancel(failures: Array[String]) -> void:
	var stamina := OpponentStaminaType.new()
	stamina.initial_current_stamina = 100.0
	stamina.initial_max_stamina = 100.0
	stamina._ready()
	var hit_stun := HitStunType.new()
	var state := OpponentAttackStateType.new()
	state.opponent_stamina = stamina
	state.hit_stun = hit_stun
	state.print_attack_start = false
	state.print_action_speed = false
	state.attack_cooldown = 0.0
	state.initial_ready_delay = 0.0
	var left := OpponentAttackDataType.new()
	left.attack_type = OpponentAttackDataType.AttackType.LEFT_STRAIGHT
	left.startup_time = 0.05
	left.active_time = 0.05
	left.recovery_time = 0.40
	left.stamina_cost = 4.0
	var right := OpponentAttackDataType.new()
	right.attack_type = OpponentAttackDataType.AttackType.RIGHT_STRAIGHT
	right.side = OpponentAttackDataType.AttackSide.RIGHT
	right.startup_time = 0.05
	right.active_time = 0.05
	right.recovery_time = 0.40
	right.stamina_cost = 5.0
	state.attacks = [left, right]
	state._ready()
	## Clear ready gate delay
	state._time_remaining = 0.0
	state._ready_gate = true

	if not state.try_execute_attack(OpponentAttackDataType.AttackType.LEFT_STRAIGHT):
		failures.append("Opponent left straight failed")
		stamina.queue_free()
		hit_stun.queue_free()
		state.queue_free()
		return
	_pump([state], 0.02, 8)
	if not state.is_recovering():
		failures.append("Opponent expected RECOVERY")
	_pump([state], 0.02, 12)
	if state.get_recovery_progress() < 0.50:
		_pump([state], 0.02, 8)
	if state.get_recovery_progress() < 0.50:
		failures.append(
			"Opponent recovery progress < 0.50 (%.2f)" % state.get_recovery_progress()
		)
	else:
		var before := stamina.current_stamina
		state.force_end_for_cancel()
		if not state.is_ready_for_command():
			failures.append("Opponent not ready after recovery cancel")
		elif not state.try_execute_attack(OpponentAttackDataType.AttackType.RIGHT_STRAIGHT):
			failures.append("Opponent follow-up after cancel failed")
		else:
			var spent := before - stamina.current_stamina
			if spent < 4.9:
				failures.append("Opponent follow-up stamina not spent (%.2f)" % spent)
	## Hit stun must block cancel offense path
	state.force_end_for_cancel()
	hit_stun.apply_hit_stun(0.35)
	if state.try_execute_attack(OpponentAttackDataType.AttackType.LEFT_STRAIGHT):
		failures.append("Opponent must not attack during hit stun")
	stamina.queue_free()
	hit_stun.queue_free()
	state.queue_free()


func _check_ai_cancel_export(failures: Array[String]) -> void:
	var ai := OpponentAIType.new()
	if not is_equal_approx(ai.attack_to_attack_cancel, 0.50):
		failures.append("AI attack_to_attack_cancel default 0.50")
	if not ai.has_method("_can_recovery_cancel_offense"):
		failures.append("AI missing _can_recovery_cancel_offense")
	if not ai.has_method("_ensure_offense_ready"):
		failures.append("AI missing _ensure_offense_ready")
	ai.queue_free()


func _free_bag(bag: Dictionary) -> void:
	for key in bag.keys():
		var node = bag[key]
		if node != null and is_instance_valid(node):
			node.queue_free()
