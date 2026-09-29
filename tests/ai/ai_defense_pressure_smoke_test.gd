extends SceneTree

## Pressure recovery after hit stun, plus idle proactive guard/slip.
## Run: godot --headless --path . -s res://tests/ai/ai_defense_pressure_smoke_test.gd

const AIType = preload("res://scripts/opponent_ai.gd")
const AttackType = preload("res://scripts/player_attack_state.gd")
const ActionType = preload("res://scripts/opponent_action_state.gd")
const OppAttackType = preload("res://scripts/opponent_attack_state.gd")
const StunType = preload("res://scripts/hit_stun.gd")
const RoundType = preload("res://scripts/round_manager.gd")
const KDType = preload("res://scripts/knockdown_manager.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_pressure(failures)
	_check_hit_scaling(failures)
	_check_combo_stats(failures)
	_check_proactive(failures)
	_check_cadence_defaults(failures)
	_simulate_idle_player(failures)
	if failures.is_empty():
		print("SMOKE PASS: AI pressure defense")
		quit(0)
		return
	print("SMOKE FAIL:")
	for failure in failures:
		print(" - %s" % failure)
	quit(1)


func _make_ai() -> AIType:
	var ai := AIType.new()
	ai.player_attack_state = AttackType.new()
	ai.opponent_action_state = ActionType.new()
	ai.opponent_attack_state = OppAttackType.new()
	ai.opponent_hit_stun = StunType.new()
	ai.opponent_action_state.hit_stun = ai.opponent_hit_stun
	ai.opponent_attack_state.hit_stun = ai.opponent_hit_stun
	ai.knockdown_manager = KDType.new()
	ai.round_manager = RoundType.new()
	ai.round_manager.round_state = RoundType.RoundState.FIGHTING
	ai.round_manager.timer_paused = false
	ai.opponent_attack_state.combat_enabled = true
	ai.opponent_attack_state._ready_gate = true
	ai.print_ai_decisions = false
	ai.difficulty = preload("res://scripts/opponent_difficulty_settings.gd").new()
	ai._proactive_timer = 10.0
	ai._offense_cooldown = 5.0
	return ai


func _check_pressure(failures: Array[String]) -> void:
	var ai := _make_ai()
	ai.opponent_hit_stun.apply_hit_stun()
	if ai.opponent_hit_stun.is_hit_stunned() or not ai.opponent_action_state.can_defend():
		failures.append("A normal hit must not stop defense")
	ai.debug_forced_rolls = [0.95]
	ai._on_player_attack_resolved(0, 8.0, 0.0, false, 0)
	if ai._reaction_pending:
		failures.append("A failed pressure roll must not force a defense")
	if not ai._pressure_recovery_armed:
		failures.append("A clean hit should keep a pressure defense opportunity")
	ai.player_attack_state.current_state = AttackType.AttackState.STARTUP
	ai.debug_forced_rolls = [0.95]
	ai._on_player_attack_state_changed(AttackType.AttackState.STARTUP, 0)
	if ai._reaction_pending:
		failures.append("A failed pressure roll must not force a defense")
	ai._set_armed(true, "TEST")
	ai.debug_forced_rolls = [0.1, 0.1]
	ai._on_player_attack_state_changed(AttackType.AttackState.STARTUP, 0)
	if not ai._pressure_reaction:
		failures.append("The next startup should queue pressure defense without hit stun")
	if ai._reaction_timer > 0.12:
		failures.append("Pressure reaction should stay near 0.104")
	for _step in 12:
		ai._process(0.01)
	if not ai.opponent_action_state.is_guarding():
		failures.append("Pressure defense should be able to choose Guard")
	ai.knockdown_manager.match_state = KDType.MatchState.OPPONENT_DOWN
	ai._process(0.01)
	if ai._reaction_pending:
		failures.append("Knockdown must not start pressure defense")
	ai.free()


func _check_hit_scaling(failures: Array[String]) -> void:
	var ai := _make_ai()
	ai._on_player_attack_resolved(0, 8.0, 0.0, false, 0)
	if ai._pressure_hit_count != 1 or not is_equal_approx(ai._pressure_defense_chance_now(), 0.60):
		failures.append("First clean hit should be 60 percent")
	if not is_equal_approx(ai._pressure_reaction_base(), 0.104):
		failures.append("First clean hit reaction should be 0.104")
	ai._on_player_attack_resolved(0, 8.0, 0.0, false, 0)
	if ai._pressure_hit_count != 2 or not is_equal_approx(ai._pressure_defense_chance_now(), 0.68):
		failures.append("Second clean hit should be 68 percent")
	if not is_equal_approx(ai._pressure_reaction_base(), 0.065):
		failures.append("Second clean hit reaction should be 0.065")
	ai._on_player_attack_resolved(1, 2.0, 0.0, false, 1)
	if ai._pressure_hit_count != 2:
		failures.append("A block must not increase the clean-hit count")
	ai._on_player_attack_resolved(0, 8.0, 0.0, false, 0)
	if ai._pressure_hit_count < 3 or not is_equal_approx(ai._pressure_defense_chance_now(), 0.76):
		failures.append("Third clean hit should be 76 percent")
	if not is_equal_approx(ai._pressure_reaction_base(), 0.039):
		failures.append("Third clean hit reaction should be 0.039")
	ai._pressure_until = ai._combat_time - 0.01
	ai._process(0.01)
	if ai._pressure_hit_count != 0:
		failures.append("Expired pressure should clear the hit count")
	ai._pressure_hit_count = 3
	ai._reaction_pending = true
	ai.clear_pending_combat_decisions()
	if ai._pressure_hit_count != 0 or ai._reaction_pending:
		failures.append("Round reset should clear pressure recovery")
	ai.free()


func _check_combo_stats(failures: Array[String]) -> void:
	var after_hit := [0, 0, 0, 0]
	for n in 100:
		seed(2000 + n)
		var hits := 0
		var escaped := 0
		while hits < 8:
			hits += 1
			var chance := 0.60
			if hits >= 3:
				chance = 0.76
			elif hits == 2:
				chance = 0.68
			if randf() <= chance:
				escaped = hits
				break
		if escaped >= 1 and escaped <= 3:
			after_hit[escaped - 1] += 1
		else:
			after_hit[3] += 1
	print(
		"PRESSURE 100 after1=%d after2=%d after3=%d four_plus=%d"
		% [after_hit[0], after_hit[1], after_hit[2], after_hit[3]]
	)
	if after_hit[0] + after_hit[1] + after_hit[2] < 90:
		failures.append("Most pressure sequences should escape by the third clean hit")
	if after_hit[3] > 15:
		failures.append("Too many sequences allowed 4 or more clean hits")


func _check_proactive(failures: Array[String]) -> void:
	var ai := _make_ai()
	ai.proactive_guard_chance = 1.0
	ai.proactive_guard_weight = 1.0
	ai.debug_forced_rolls = [0.0, 0.0, 0.5]
	ai._consider_proactive_defense()
	if not ai.opponent_action_state.is_guarding():
		failures.append("Proactive decision should be able to raise High Guard")
	if ai._guard_hold_remaining < 0.55 or ai._guard_hold_remaining > 0.90:
		failures.append("Proactive guard hold should stay inside 0.55-0.90")
	var held := ai._guard_hold_remaining
	ai._on_player_attack_resolved(0, 10.0, 0.0, false, 1)
	if not is_equal_approx(ai._guard_hold_remaining, held):
		failures.append("A block must not refresh the proactive guard timer")
	ai._process(0.20)
	if not ai.opponent_action_state.is_guarding():
		failures.append("Proactive guard must stay up for at least 0.55s")
	ai._guard_hold_remaining = 0.01
	ai._process(0.02)
	if ai.opponent_action_state.is_guarding():
		failures.append("Proactive guard should return to stance when the hold ends")
	ai.proactive_guard_weight = 0.0
	ai.debug_forced_rolls = [0.0, 1.0, 0.1]
	ai._consider_proactive_defense()
	if ai.opponent_action_state.current_state != ActionType.OpponentState.SLIP_LEFT:
		failures.append("Proactive slip should be able to choose left")
	ai.free()


func _check_cadence_defaults(failures: Array[String]) -> void:
	var ai := AIType.new()
	if not is_equal_approx(ai.proactive_defense_interval_min, 0.55):
		failures.append("proactive interval min should be 0.55")
	if not is_equal_approx(ai.proactive_defense_interval_max, 1.05):
		failures.append("proactive interval max should be 1.05")
	if not is_equal_approx(ai.proactive_guard_chance, 0.32):
		failures.append("proactive chance should stay 0.32")
	if not is_equal_approx(ai.proactive_guard_weight, 0.65):
		failures.append("proactive guard weight should stay 0.65")
	if not is_equal_approx(ai.pressure_memory_duration, 0.60):
		failures.append("pressure memory should stay 0.60")
	if not is_equal_approx(ai.pressure_defense_chance, 0.60):
		failures.append("pressure chance should stay 0.60")
	if not is_equal_approx(ai.pressure_reaction_delay, 0.104):
		failures.append("pressure reaction should stay 0.104")
	if not is_equal_approx(ai.pressure_guard_weight, 0.45):
		failures.append("pressure guard weight should stay 0.45")
	if not is_equal_approx(ai.proactive_guard_hold_min, 0.55):
		failures.append("proactive guard min should be 0.55")
	if not is_equal_approx(ai.proactive_guard_hold_max, 0.90):
		failures.append("proactive guard max should be 0.90")
	if not is_equal_approx(ai.pressure_guard_duration, 0.45):
		failures.append("Pressure guard duration should stay 0.45")
	if is_equal_approx(ai.pressure_guard_duration, ai.proactive_guard_hold_min):
		failures.append("Pressure guard duration must not share the proactive range")
	var difficulty := preload("res://scripts/opponent_difficulty_settings.gd").new()
	if not is_equal_approx(difficulty.reaction_delay, 0.234):
		failures.append("normal reaction should stay 0.234")
	if not is_equal_approx(ai._compose_reaction(0.16), 0.16):
		failures.append("Full stamina should leave normal reaction at 0.16")
	var stamina := preload("res://scripts/player_stamina.gd").new()
	stamina.max_stamina = 100.0
	ai.player_stamina = stamina
	var expected := {100.0: 0.160, 75.0: 0.144, 50.0: 0.120, 25.0: 0.088, 0.0: 0.064}
	for value in expected.keys():
		stamina.current_stamina = value
		var got := ai._compose_reaction(0.16)
		if not is_equal_approx(got, expected[value]):
			failures.append("Stamina %.0f normal reaction expected %.3f got %.3f" % [value, expected[value], got])
	stamina.free()
	if not is_equal_approx(difficulty.attack_interval_min, 0.10):
		failures.append("attack interval min should stay 0.10")
	if not is_equal_approx(difficulty.attack_interval_max, 0.30):
		failures.append("attack interval max should stay 0.30")
	ai.free()


func _simulate_idle_player(failures: Array[String]) -> void:
	seed(5)
	var result := _run_idle_timeline()
	var counts: Dictionary = result["counts"]
	var longest_idle: float = result["idle"]
	print("IDLE PLAYER TIMELINE")
	for entry in result["timeline"]:
		print(entry)
	print(
		"COUNTS attack=%d guard=%d slip=%d longest_idle=%.2f single=%d two=%d three=%d stamina_cancels=%d"
		% [
			counts["ATTACK"],
			counts["GUARD"],
			counts["SLIP"],
			longest_idle,
			result["single"],
			result["two"],
			result["three"],
			result["stamina_cancels"],
		]
	)
	if counts["ATTACK"] < 1 or int(counts["GUARD"]) + int(counts["SLIP"]) < 1:
		failures.append("20s idle player should mix attacks with a defense")
	if not result["same_hand_ok"]:
		failures.append("A same-hand punch started before 0.45s")
	if longest_idle > 2.0:
		failures.append("Idle gap was longer than 2.0s (%.2f)" % longest_idle)
	print("HANDS %s" % result["hands"])


func _run_idle_timeline() -> Dictionary:
	var ai := _make_ai()
	var stamina := preload("res://scripts/opponent_stamina.gd").new()
	var DataType := preload("res://scripts/opponent_attack_data.gd")
	stamina.current_stamina = 100.0
	stamina.max_stamina = 100.0
	ai.opponent_stamina = stamina
	ai.opponent_attack_state.opponent_stamina = stamina
	var left := DataType.new()
	left.attack_type = DataType.AttackType.LEFT_STRAIGHT
	left.startup_time = 0.8
	left.active_time = 0.1
	left.recovery_time = 0.5
	left.stamina_cost = 4.0
	var right := DataType.new()
	right.attack_type = DataType.AttackType.RIGHT_STRAIGHT
	right.startup_time = 0.9
	right.active_time = 0.1
	right.recovery_time = 0.55
	right.stamina_cost = 5.0
	ai.opponent_attack_state.attacks = [left, right]
	ai.opponent_attack_state.initial_ready_delay = 0.0
	ai.opponent_attack_state._time_remaining = 0.0
	ai._proactive_timer = 0.2
	ai._offense_cooldown = 0.0
	var timeline: PackedStringArray = []
	var counts := {"ATTACK": 0, "GUARD": 0, "SLIP": 0}
	var label := ""
	var idle_started := -1.0
	var longest_idle := 0.0
	var hands := ""
	var seen_token := ai.opponent_attack_state.get_action_token()
	var hand_ready_at := {-1: -1.0, 0: -1.0, 1: -1.0, 2: -1.0, 3: -1.0}
	var same_hand_ok := true
	var time := 0.0
	var step := 0.05
	while time < 20.0:
		ai.opponent_attack_state.hand_reuse.debug_now = time
		ai._process(step)
		ai.opponent_attack_state._process(step)
		ai.opponent_action_state._process(step)
		stamina._process(step)
		var token := ai.opponent_attack_state.get_action_token()
		if token != seen_token and ai.opponent_attack_state.current_attack != null:
			var kind: int = ai.opponent_attack_state.current_attack.attack_type
			var hand := kind % 2
			if float(hand_ready_at[hand]) >= 0.0 and time + 0.001 < float(hand_ready_at[hand]):
				same_hand_ok = false
			hand_ready_at[hand] = time + 0.45
			hands += "L" if hand == 0 else "R"
			seen_token = token
		var next := "IDLE"
		if ai.opponent_attack_state.current_state != OppAttackType.AttackState.IDLE:
			next = "ATTACK"
		elif ai.opponent_action_state.is_guarding():
			next = "GUARD"
		elif ai.opponent_action_state.current_state != ActionType.OpponentState.IDLE:
			next = "SLIP"
		if next != label:
			if label == "IDLE" and idle_started >= 0.0:
				longest_idle = maxf(longest_idle, time - idle_started)
			if next == "IDLE":
				idle_started = time
			label = next
			counts[next] = int(counts.get(next, 0)) + 1
			timeline.append("%.2f %s" % [time, next])
		time += step
	var single := ai.debug_combo_counts[1]
	var two := ai.debug_combo_counts[2]
	var three := ai.debug_combo_counts[3]
	var stamina_cancels := ai.debug_stamina_cancels
	ai.free()
	stamina.free()
	return {
		"counts": counts,
		"idle": longest_idle,
		"timeline": timeline,
		"single": single,
		"two": two,
		"three": three,
		"stamina_cancels": stamina_cancels,
		"hands": hands,
		"same_hand_ok": same_hand_ok,
	}

