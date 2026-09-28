extends SceneTree

## Stamina is attack-only. Low stamina raises KD taken, not action time.
## Run: godot --headless --path . -s res://combat_rework_smoke_test.gd

const StaminaType = preload("res://scripts/player_stamina.gd")
const EvadeType = preload("res://scripts/player_evade.gd")
const ActionType = preload("res://scripts/player_action_state.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const AttackDataType = preload("res://scripts/attack_data.gd")
const VulnType = preload("res://scripts/knockdown_vulnerability.gd")
const VignetteType = preload("res://scripts/fatigue_vignette.gd")
const OpponentVisualType = preload("res://scripts/opponent_visual.gd")
const OffenseType = preload("res://scripts/player_offense_resolver.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")
const OppActionType = preload("res://scripts/opponent_action_state.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_attack_costs_and_recovery(failures)
	_check_evade_and_guard_free(failures)
	await _check_attack_timing_ignores_stamina(failures)
	_check_vulnerability(failures)
	await _check_block_and_evade_vulnerability(failures)
	_check_exhausted(failures)
	_check_vignette_curve(failures)
	await _check_ghost(failures)

	if failures.is_empty():
		print("SMOKE PASS: combat rework")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_attack_costs_and_recovery(failures: Array[String]) -> void:
	var expected := {
		"res://data/attacks/left_straight.tres": [4.0, 0.11],
		"res://data/attacks/right_straight.tres": [5.0, 0.14],
		"res://data/attacks/left_hook.tres": [7.0, 0.18],
		"res://data/attacks/right_hook.tres": [8.0, 0.21],
	}
	var buffer_script = load("res://scripts/player_action_buffer.gd")
	var buffer = buffer_script.new()
	if not is_equal_approx(buffer.attack_to_attack, 0.50):
		failures.append("attack_to_attack changed")
	buffer.free()
	for path in expected.keys():
		var data = load(path)
		var pair: Array = expected[path]
		if not is_equal_approx(data.stamina_cost, pair[0]):
			failures.append("%s cost changed" % path)
		if not is_equal_approx(data.recovery_time, pair[1]):
			failures.append("%s recovery expected %.2f got %.2f" % [path, pair[1], data.recovery_time])
		var earliest: float = data.startup_time + data.active_time + data.recovery_time * 0.50
		if earliest <= 0.0:
			failures.append("earliest combo timing invalid")


func _check_evade_and_guard_free(failures: Array[String]) -> void:
	var stamina := StaminaType.new()
	stamina.initial_current_stamina = 0.0
	stamina.initial_max_stamina = 100.0
	stamina._ready()
	var evade := EvadeType.new()
	if evade.try_begin_window(EvadeType.Direction.LEFT) == false:
		failures.append("Stamina 0 must still open Evade")
	if not is_equal_approx(stamina.current_stamina, 0.0):
		failures.append("Evade spent stamina")
	var attack := AttackStateType.new()
	var action := ActionType.new()
	root.add_child(attack)
	action.attack_state = attack
	root.add_child(action)
	action.set_guard_held(true)
	if not action.is_guarding():
		failures.append("Guard must work with no stamina spend")
	if not is_equal_approx(stamina.current_stamina, 0.0):
		failures.append("Guard spent stamina")
	stamina.current_stamina = 3.0
	if stamina.can_afford(4.0):
		failures.append("Cost 4 must be unaffordable at stamina 3")
	action.queue_free()
	attack.queue_free()
	stamina.queue_free()
	evade.free()


func _check_attack_timing_ignores_stamina(failures: Array[String]) -> void:
	var fast := _scaled_recovery_at(100.0)
	var slow := _scaled_recovery_at(10.0)
	if not is_equal_approx(fast, slow):
		failures.append("Low stamina still changes recovery timing")
	if not is_equal_approx(fast, 0.11):
		failures.append("Left straight recovery not 0.11")
	await process_frame


func _scaled_recovery_at(stamina_value: float) -> float:
	var stamina := StaminaType.new()
	stamina.initial_current_stamina = stamina_value
	stamina.initial_max_stamina = 100.0
	stamina._ready()
	var attack := AttackStateType.new()
	attack.player_stamina = stamina
	attack.print_action_speed = false
	var data := AttackDataType.new()
	data.attack_type = 0
	data.startup_time = 0.10
	data.active_time = 0.08
	data.recovery_time = 0.11
	data.stamina_cost = 4.0
	attack.attacks = [data]
	root.add_child(attack)
	attack.try_start_attack(0)
	var recovery := attack.get_scaled_recovery()
	attack.queue_free()
	stamina.free()
	return recovery


func _check_vulnerability(failures: Array[String]) -> void:
	var vuln := VulnType.new()
	var samples := {
		100.0: 1.0,
		75.0: 1.03,
		50.0: 1.10,
		25.0: 1.25,
		10.0: 1.40,
		0.0: 1.50,
	}
	for stamina_value in samples.keys():
		var got := vuln.multiplier_for(stamina_value, 100.0)
		var want: float = samples[stamina_value]
		if absf(got - want) > 0.02:
			failures.append("Vulnerability at %.0f expected %.2f got %.2f" % [stamina_value, want, got])


func _check_block_and_evade_vulnerability(failures: Array[String]) -> void:
	var stamina := preload("res://scripts/opponent_stamina.gd").new()
	stamina.initial_current_stamina = 0.0
	stamina.initial_max_stamina = 100.0
	stamina._ready()
	var action := OppActionType.new()
	var player_attack := AttackStateType.new()
	var data := AttackDataType.new()
	data.attack_type = 0
	data.knockdown_damage = 10.0
	player_attack.attacks = [data]
	var meter := MeterType.new()
	var offense := OffenseType.new()
	offense.player_attack_state = player_attack
	offense.opponent_action_state = action
	offense.opponent_knockdown_meter = meter
	offense.opponent_stamina = stamina
	offense.knockdown_vulnerability = VulnType.new()
	offense.print_hit_results = false
	offense.meter_updates_enabled = true
	root.add_child(meter)
	root.add_child(offense)
	await process_frame
	action.current_state = OppActionType.OpponentState.GUARD
	offense.resolve_hit_now(0)
	## 10 * 0.25 * 1.50 = 3.75
	if absf(meter.current_meter - 3.75) > 0.15:
		failures.append("BLOCK at 0 stamina expected ~3.75 KD, got %.2f" % meter.current_meter)
	meter.set_meter(0.0)
	action.current_state = OppActionType.OpponentState.SLIP_LEFT
	action.current_evasion_phase = OppActionType.EvasionPhase.EVADING
	offense.resolve_hit_now(0)
	if not is_equal_approx(meter.current_meter, 0.0):
		failures.append("EVADE must stay KD 0")
	offense.queue_free()
	meter.queue_free()
	stamina.free()
	await process_frame


func _check_exhausted(failures: Array[String]) -> void:
	var stamina := StaminaType.new()
	stamina.initial_current_stamina = 4.0
	stamina.initial_max_stamina = 100.0
	stamina._ready()
	stamina.spend_for_attack(4.0)
	if not stamina.is_exhausted:
		failures.append("Stamina 0 should enter Exhausted")
	stamina.current_stamina = 24.0
	stamina._evaluate_exhausted()
	if not stamina.is_exhausted:
		failures.append("Stamina 24 should stay Exhausted")
	stamina.current_stamina = 25.0
	stamina._evaluate_exhausted()
	if stamina.is_exhausted:
		failures.append("Stamina 25 should leave Exhausted")
	stamina.free()


func _check_vignette_curve(failures: Array[String]) -> void:
	var vignette := VignetteType.new()
	var high := vignette.vignette_intensity_for(100.0, 100.0)
	var mid := vignette.vignette_intensity_for(50.0, 100.0)
	var low := vignette.vignette_intensity_for(0.0, 100.0)
	if high > 0.01:
		failures.append("Full stamina vignette should be ~0")
	if mid <= high or low <= mid:
		failures.append("Vignette should rise as stamina falls")
	if not is_equal_approx(low, 1.0):
		failures.append("Zero stamina vignette intensity should be 1")
	vignette.free()


func _check_ghost(failures: Array[String]) -> void:
	var visual := OpponentVisualType.new()
	root.add_child(visual)
	await process_frame
	if visual._sprite.modulate.a < 0.99:
		failures.append("Main opponent must stay opaque")
	visual.set_exhausted_ghost(true)
	visual._process(1.0)
	var ghost_a: Sprite2D = visual.get_node_or_null("Anchor/GhostA")
	var ghost_b: Sprite2D = visual.get_node_or_null("Anchor/GhostB")
	if ghost_a == null or ghost_b == null or not ghost_a.visible or not ghost_b.visible:
		failures.append("Exhausted should show two ghosts")
	elif ghost_a.modulate.a > 0.4 or ghost_b.modulate.a > 0.4:
		failures.append("Ghosts must stay faint")
	elif ghost_a.texture != visual._sprite.texture:
		failures.append("Ghost must copy the live pose texture")
	visual.set_exhausted_ghost(false)
	visual._process(1.0)
	if ghost_a != null and ghost_a.visible:
		failures.append("Recovered stamina should hide ghosts")
	var hud_parent_is_canvas := visual.get_parent() != null
	if not hud_parent_is_canvas:
		failures.append("visual missing")
	visual.queue_free()
	await process_frame
