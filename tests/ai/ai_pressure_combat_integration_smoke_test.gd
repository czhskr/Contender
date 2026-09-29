extends SceneTree

## Full player punch → hit stun → pressure defense → resolver path.
## Run: godot --headless --path . -s res://tests/ai/ai_pressure_combat_integration_smoke_test.gd

const AttackStateType = preload("res://scripts/player_attack_state.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const OffenseType = preload("res://scripts/player_offense_resolver.gd")
const ActionType = preload("res://scripts/opponent_action_state.gd")
const AIType = preload("res://scripts/opponent_ai.gd")
const StunType = preload("res://scripts/hit_stun.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")
const RoundType = preload("res://scripts/round_manager.gd")
const KDType = preload("res://scripts/knockdown_manager.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	await _check_same_hand(failures)
	await _check_opposite_hand(failures)
	_check_same_timestamp_orders(failures)
	await _check_scene_same_hand(failures)
	if failures.is_empty():
		print("SMOKE PASS: pressure combat integration")
		quit(0)
		return
	print("SMOKE FAIL:")
	for failure in failures:
		print(" - %s" % failure)
	quit(1)


func _build():
	var attack := AttackStateType.new()
	attack.print_action_speed = false
	var left := AttackDataType.new()
	left.attack_type = 0
	left.startup_time = 0.10
	left.active_time = 0.08
	left.recovery_time = 0.11
	left.knockdown_damage = 8.0
	left.stamina_cost = 4.0
	var right := AttackDataType.new()
	right.attack_type = 1
	right.startup_time = 0.10
	right.active_time = 0.08
	right.recovery_time = 0.11
	right.knockdown_damage = 10.0
	right.stamina_cost = 5.0
	attack.attacks = [left, right]
	var action := ActionType.new()
	var stun := StunType.new()
	action.hit_stun = stun
	var meter := MeterType.new()
	var offense := OffenseType.new()
	offense.player_attack_state = attack
	offense.opponent_action_state = action
	offense.opponent_knockdown_meter = meter
	offense.print_hit_results = true
	var ai := AIType.new()
	ai.player_attack_state = attack
	ai.opponent_action_state = action
	ai.opponent_hit_stun = stun
	ai.knockdown_manager = KDType.new()
	ai.round_manager = RoundType.new()
	ai.round_manager.round_state = RoundType.RoundState.FIGHTING
	ai.difficulty = preload("res://scripts/opponent_difficulty_settings.gd").new()
	ai.print_ai_decisions = true
	ai._proactive_timer = 10.0
	ai._offense_cooldown = 5.0
	var results: Array[String] = []
	attack.state_changed.connect(func(state: int, _attack_index: int) -> void:
		if state == AttackStateType.AttackState.ACTIVE:
			ai.resolve_pending_defense_now()
	)
	root.add_child(attack)
	root.add_child(action)
	root.add_child(stun)
	root.add_child(meter)
	root.add_child(offense)
	root.add_child(ai)
	await process_frame
	offense.attack_hit.connect(func(attack_index: int, _d: float, _m: float, _k: bool, result: int) -> void:
		ai._on_player_attack_resolved(attack_index, _d, _m, _k, result)
		results.append(OffenseType.RESULT_NAMES[result])
		print("[RESOLVE] result=%s" % OffenseType.RESULT_NAMES[result])
		if result == OffenseType.ResolveResult.HIT:
			stun.apply_hit_stun()
	)
	return {
		"attack": attack,
		"action": action,
		"stun": stun,
		"ai": ai,
		"offense": offense,
		"results": results,
	}


func _pump(bundle: Dictionary, seconds: float) -> void:
	var attack: AttackStateType = bundle["attack"]
	var action: ActionType = bundle["action"]
	var stun: StunType = bundle["stun"]
	var ai: AIType = bundle["ai"]
	var steps := int(seconds / 0.01)
	for _i in steps:
		attack.hand_reuse.debug_now = ai._combat_time
		stun._process(0.01)
		ai._process(0.01)
		attack._process(0.01)
		action._process(0.01)


func _check_same_hand(failures: Array[String]) -> void:
	print("J-J INTEGRATION")
	var bundle: Dictionary = await _build()
	var attack: AttackStateType = bundle["attack"]
	var ai: AIType = bundle["ai"]
	ai.debug_forced_rolls = [0.0, 0.0]
	for punch in 10:
		attack.hand_reuse.debug_now = ai._combat_time
		if not attack.can_start_attack() or not attack.is_hand_ready(0):
			_pump(bundle, 0.05)
			continue
		if not attack.try_start_attack(0):
			failures.append("Same-hand punch %d did not start" % punch)
			break
		_pump(bundle, 0.50)
		if bundle["stun"].is_hit_stunned():
			_pump(bundle, 0.40)
	var results: Array = bundle["results"]
	print("J-J RESULTS %s" % str(results))
	if results.is_empty():
		failures.append("J sequence produced no hits")
	var defended := false
	for result in results:
		if result == "BLOCK" or result == "EVADE":
			defended = true
	if not defended:
		failures.append("Repeated J never reached BLOCK or EVADE")
	for node in [bundle["attack"], bundle["action"], bundle["stun"], bundle["ai"], bundle["offense"]]:
		node.queue_free()


func _check_opposite_hand(failures: Array[String]) -> void:
	print("J-K INTEGRATION")
	var bundle: Dictionary = await _build()
	var attack: AttackStateType = bundle["attack"]
	var ai: AIType = bundle["ai"]
	ai.debug_forced_rolls = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var hands := [0, 1, 0, 1, 0, 1]
	for hand in hands:
		attack.hand_reuse.debug_now = ai._combat_time
		if attack.current_state != AttackStateType.AttackState.IDLE:
			_pump(bundle, 0.05)
		if not attack.try_start_attack(hand):
			_pump(bundle, 0.20)
			attack.hand_reuse.debug_now = ai._combat_time
			if not attack.try_start_attack(hand):
				continue
		_pump(bundle, 0.25)
	var results: Array = bundle["results"]
	print("J-K RESULTS %s" % str(results))
	if results.is_empty() or results[0] != "HIT":
		failures.append("First alternating punch should be a clean HIT")
	var defended := false
	for result in results:
		if result == "BLOCK" or result == "EVADE":
			defended = true
	if not defended:
		failures.append("J-K chain never reached BLOCK or EVADE")
	for node in [bundle["attack"], bundle["action"], bundle["stun"], bundle["ai"], bundle["offense"]]:
		node.queue_free()


func _check_same_timestamp_orders(failures: Array[String]) -> void:
	if not _recovery_after_order(true):
		failures.append("Stun end before startup did not schedule pressure recovery")
	if not _recovery_after_order(false):
		failures.append("Startup before stun end did not keep a deferred recovery")


func _recovery_after_order(stun_end_first: bool) -> bool:
	var attack := AttackStateType.new()
	attack.print_action_speed = false
	var data := AttackDataType.new()
	data.attack_type = 0
	data.startup_time = 0.10
	data.active_time = 0.08
	data.recovery_time = 0.11
	data.knockdown_damage = 8.0
	attack.attacks = [data]
	var action := ActionType.new()
	var stun := StunType.new()
	action.hit_stun = stun
	var ai := AIType.new()
	ai.player_attack_state = attack
	ai.opponent_action_state = action
	ai.opponent_hit_stun = stun
	ai.difficulty = preload("res://scripts/opponent_difficulty_settings.gd").new()
	ai.knockdown_manager = KDType.new()
	ai.round_manager = RoundType.new()
	ai.round_manager.round_state = RoundType.RoundState.FIGHTING
	ai._pressure_hit_count = 1
	ai._pressure_until = 10.0
	ai._combat_time = 0.45
	ai.debug_forced_rolls = [0.0, 0.0]
	ai._on_player_attack_resolved(0, 8.0, 0.0, false, 0)
	attack.current_state = AttackStateType.AttackState.STARTUP
	ai._on_player_attack_state_changed(AttackStateType.AttackState.STARTUP, 0)
	var scheduled := ai._reaction_pending or action.is_guarding()
	ai.free()
	action.free()
	stun.free()
	attack.free()
	return scheduled


func _check_scene_same_hand(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	for _i in 8:
		await process_frame
	var ai: AIType = scene.get_node("OpponentAI")
	var attack: AttackStateType = scene.get_node("PlayerAttackState")
	var stun: StunType = scene.get_node("OpponentHitStun")
	var action: ActionType = scene.get_node("OpponentActionState")
	var offense: OffenseType = scene.get_node("PlayerOffenseResolver")
	print("HIT CONNECTIONS %s" % offense.attack_hit.get_connections().size())
	ai.print_ai_decisions = false
	ai._offense_cooldown = 0.0
	seed(11)
	var results: Array[String] = []
	var result_count := 0
	var defense_window := -1
	var max_defense_window := 0
	offense.attack_hit.connect(func(_a: int, _d: float, _m: float, _k: bool, result: int) -> void:
		results.append(OffenseType.RESULT_NAMES[result])
	)
	var coordinator = scene.get_node("HitResolveCoordinator")
	var opponent_attack = scene.get_node("OpponentAttackState")
	var player_stun = scene.get_node("PlayerHitStun")
	var opponent_attacks := 0
	var opponent_time := 0.0
	var saw_startup := false
	var hands := [0, 1]
	for punch in 30:
		var hand: int = hands[punch % 2]
		attack.hand_reuse.debug_now = ai._combat_time
		if attack.current_state == AttackStateType.AttackState.IDLE and attack.is_hand_ready(hand):
			attack.try_start_attack(hand)
		for _s in 40:
			attack.hand_reuse.debug_now = ai._combat_time
			opponent_time += 0.01
			opponent_attack.hand_reuse.debug_now = opponent_time
			stun._process(0.01)
			player_stun._process(0.01)
			attack._process(0.01)
			ai._process(0.01)
			action._process(0.01)
			coordinator._flush()
			opponent_attack._process(0.01)
			while result_count < results.size():
				var newest: String = results[result_count]
				if defense_window >= 0:
					defense_window += 1
					max_defense_window = maxi(max_defense_window, defense_window)
				elif newest == "BLOCK" or newest == "EVADE":
					defense_window = 1
					max_defense_window = maxi(max_defense_window, 1)
				result_count += 1
			var starting := int(opponent_attack.current_state) == 1
			if starting and not saw_startup:
				opponent_attacks += 1
				defense_window = -1
			saw_startup = starting
	var defended := 0
	var hit_streak := 0
	var max_hit_streak := 0
	var hit_count := 0
	var block_count := 0
	var evade_count := 0
	for result in results:
		if result == "HIT":
			hit_count += 1
			hit_streak += 1
			max_hit_streak = maxi(max_hit_streak, hit_streak)
		else:
			hit_streak = 0
			if result == "BLOCK":
				block_count += 1
				defended += 1
			elif result == "EVADE":
				evade_count += 1
				defended += 1
	var gap_sum := 0.0
	for gap in ai.debug_defense_to_attack:
		gap_sum += gap
	var gap_avg := 0.0 if ai.debug_defense_to_attack.is_empty() else gap_sum / ai.debug_defense_to_attack.size()
	var gap_max := 0.0
	for gap in ai.debug_defense_to_attack:
		gap_max = maxf(gap_max, gap)
	print("SCENE JK hit=%d block=%d evade=%d opponent_attacks=%d block_armed=%d evade_armed=%d decisions=%d attack_starts=%d failed=%d initiative_started=%d consumed=%d expired=%d defense_to_attack_avg=%.2f max=%.2f silent_results=%d max_hit_streak=%d" % [hit_count, block_count, evade_count, opponent_attacks, ai.debug_retaliation_block_armed, ai.debug_retaliation_evade_armed, ai.debug_retaliation_attempted, ai.debug_retaliation_started, ai.debug_retaliation_failed, ai.debug_initiative_started, ai.debug_initiative_consumed, ai.debug_initiative_expired, gap_avg, gap_max, max_defense_window, max_hit_streak])
	for line in ai.debug_retaliation_trace:
		print(line)
	if defended < 1 and hit_count >= 10:
		failures.append("J/K spam produced no blocks or evades")
	if defended >= 3 and max_defense_window >= 10:
		failures.append("Defenses did not create an opponent attack for %d player results" % max_defense_window)
	var split_at := results.size()
	seed(11)
	var jk_started := 0
	for punch in 30:
		var hand: int = hands[punch % 2]
		attack.hand_reuse.debug_now = ai._combat_time
		if attack.current_state == AttackStateType.AttackState.IDLE and attack.is_hand_ready(hand):
			if attack.try_start_attack(hand):
				jk_started += 1
		for _s in 30:
			attack.hand_reuse.debug_now = ai._combat_time
			opponent_time += 0.01
			opponent_attack.hand_reuse.debug_now = opponent_time
			stun._process(0.01)
			player_stun._process(0.01)
			attack._process(0.01)
			ai._process(0.01)
			action._process(0.01)
			coordinator._flush()
			opponent_attack._process(0.01)
	print("SCENE JK started=%d player_state=%s stunned=%s" % [jk_started, attack.current_state, scene.get_node("PlayerHitStun").is_hit_stunned() if scene.get_node_or_null("PlayerHitStun") != null else false])
	var jk_results: Array = results.slice(split_at)
	var jk_hit := 0
	var jk_block := 0
	var jk_evade := 0
	for result in jk_results:
		if result == "HIT":
			jk_hit += 1
		elif result == "BLOCK":
			jk_block += 1
		elif result == "EVADE":
			jk_evade += 1
	print("SCENE JK hits=%d blocks=%d evades=%d %s" % [jk_hit, jk_block, jk_evade, str(jk_results)])
	scene.queue_free()

