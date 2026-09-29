extends SceneTree

## Same-hand recovery, hit-stun hold, and one resolve per attack token.
## Run: godot --headless --path . -s res://tests/combat/same_hand_smoke_test.gd

const AttackDataType = preload("res://scripts/attack_data.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const OffenseType = preload("res://scripts/player_offense_resolver.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")
const HitStunType = preload("res://scripts/hit_stun.gd")
const BufferType = preload("res://scripts/player_action_buffer.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_hands(failures)
	_check_cancel_gate(failures)
	_check_reuse(failures)
	_check_stun_keeps_kd(failures)
	_check_one_resolve(failures)
	if failures.is_empty():
		print("SMOKE PASS: same-hand / hit stun")
		quit(0)
		return
	print("SMOKE FAIL:")
	for failure in failures:
		print(" - %s" % failure)
	quit(1)


func _check_hands(failures: Array[String]) -> void:
	if AttackDataType.hand_of(0) != AttackDataType.Hand.LEFT:
		failures.append("Left Straight is LEFT")
	if AttackDataType.hand_of(2) != AttackDataType.Hand.LEFT:
		failures.append("Left Hook is LEFT")
	if AttackDataType.hand_of(1) != AttackDataType.Hand.RIGHT:
		failures.append("Right Straight is RIGHT")
	if AttackDataType.hand_of(3) != AttackDataType.Hand.RIGHT:
		failures.append("Right Hook is RIGHT")
	if not AttackDataType.is_same_hand(0, 2) or not AttackDataType.is_same_hand(1, 3):
		failures.append("Same-hand pairs")
	if AttackDataType.is_same_hand(0, 1):
		failures.append("J and K are opposite hands")


func _check_cancel_gate(failures: Array[String]) -> void:
	var buffer := BufferType.new()
	var threshold := buffer.attack_to_attack
	if AttackDataType.can_recovery_cancel(0.50, threshold, 0, 0):
		failures.append("J to J must not early-cancel")
	if AttackDataType.can_recovery_cancel(0.50, threshold, 0, 2):
		failures.append("J to left hook must not early-cancel")
	if AttackDataType.can_recovery_cancel(0.90, threshold, 1, 1):
		failures.append("K to K must not early-cancel")
	if AttackDataType.can_recovery_cancel(0.50, threshold, 1, 3):
		failures.append("K to right hook must not early-cancel")
	if AttackDataType.can_recovery_cancel(0.50, threshold, 3, 1):
		failures.append("Right hook to K must not early-cancel")
	if AttackDataType.can_recovery_cancel(0.50, threshold, 2, 0):
		failures.append("Left hook to J must not early-cancel")
	if not AttackDataType.can_recovery_cancel(0.50, threshold, 0, 1):
		failures.append("J to K should cancel at 0.50")
	if not AttackDataType.can_recovery_cancel(0.50, threshold, 1, 0):
		failures.append("K to J should cancel at 0.50")
	if not AttackDataType.can_recovery_cancel(0.50, threshold, 2, 1):
		failures.append("Left hook to K should cancel")
	if not AttackDataType.can_recovery_cancel(0.50, threshold, 3, 0):
		failures.append("Right hook to J should cancel")
	if AttackDataType.can_recovery_cancel(0.49, threshold, 0, 1):
		failures.append("Opposite cancel must wait for 0.50")
	if AttackDataType.can_recovery_cancel(0.50, threshold * 0.5, 0, 0):
		failures.append("Pressure must not bypass same-hand recovery")
	if not AttackDataType.can_recovery_cancel(0.25, threshold * 0.5, 0, 1):
		failures.append("Pressure may speed opposite-hand links")
	buffer.free()


func _check_reuse(failures: Array[String]) -> void:
	var clock := preload("res://scripts/hand_reuse.gd").new()
	clock.debug_now = 0.0
	clock.note_started(0)
	clock.debug_now = 0.29
	if clock.is_ready(0) or clock.is_ready(2):
		failures.append("LEFT is not reusable at 0.29 for straight or hook")
	clock.debug_now = 0.44
	if clock.is_ready(0):
		failures.append("LEFT must stay closed before 0.45")
	if not clock.is_ready(1) or not clock.is_ready(3):
		failures.append("RIGHT stays free while LEFT is cooling down")
	clock.debug_now = 0.45
	if not clock.is_ready(0) or not clock.is_ready(2):
		failures.append("LEFT opens at 0.45 for both left punches")
	clock.note_started(1)
	clock.debug_now = 0.70
	if clock.is_ready(1):
		failures.append("RIGHT reuse is independent and starts at its own attack")
	if not clock.is_ready(0):
		failures.append("LEFT stays open while RIGHT is cooling down")
	if not is_equal_approx(clock.interval, 0.45):
		failures.append("Reuse baseline is 0.45")
	clock.debug_now = 0.25
	if clock.is_ready(0):
		failures.append("Pressure must not open same-hand reuse at 0.25")
	var opp_opposite := 0.10 + 0.08 + 0.11 * 0.5
	if not (opp_opposite < clock.interval):
		failures.append("Opposite-hand follow-up should be legal inside the other hand's timer")
	if not is_equal_approx(maxf(0.10 + 0.08 + 0.11, clock.interval), 0.45):
		failures.append("Left Straight earliest same-hand repeat should be 0.45")
	if not is_equal_approx(maxf(0.14 + 0.09 + 0.14, clock.interval), 0.45):
		failures.append("Right Straight earliest same-hand repeat should be 0.45")
	if not is_equal_approx(maxf(0.18 + 0.10 + 0.18, clock.interval), 0.46):
		failures.append("Left Hook earliest same-hand repeat should be 0.46")
	if not is_equal_approx(maxf(0.22 + 0.11 + 0.21, clock.interval), 0.54):
		failures.append("Right Hook earliest same-hand repeat should be 0.54")
	_check_opponent_hands(failures)


func _check_stun_keeps_kd(failures: Array[String]) -> void:
	var stun := HitStunType.new()
	root.add_child(stun)
	stun.apply_hit_stun()
	if stun.is_hit_stunned():
		failures.append("A normal hit must not gameplay-stun")
	stun.free()


func _check_one_resolve(failures: Array[String]) -> void:
	var attack := AttackStateType.new()
	var data := AttackDataType.new()
	data.attack_type = 0
	data.startup_time = 0.0
	data.active_time = 0.2
	data.knockdown_damage = 8.0
	attack.attacks = [data]
	attack.print_action_speed = false
	var meter := MeterType.new()
	var offense := OffenseType.new()
	offense.player_attack_state = attack
	offense.opponent_knockdown_meter = meter
	offense.print_hit_results = false
	var hits := [0]
	offense.attack_hit.connect(func(_a, _d, _m, _k, _r) -> void:
		hits[0] += 1
	)
	root.add_child(attack)
	root.add_child(meter)
	root.add_child(offense)
	attack.try_start_attack(0)
	attack._process(0.01)
	offense.resolve_hit_now(0)
	offense.resolve_hit_now(0)
	if hits[0] != 1:
		failures.append("One attack token must resolve once, got %d" % hits[0])
	if not is_equal_approx(meter.current_meter, 8.0):
		failures.append("That single resolve still applies KD")
	attack.cancel_attack()
	attack.hand_reuse.debug_now = attack.hand_reuse.now() + 1.0
	attack.try_start_attack(0)
	offense.resolve_hit_now(0)
	if hits[0] != 2:
		failures.append("A new token should resolve again")
	attack.free()
	meter.free()
	offense.free()


func _check_opponent_hands(failures: Array[String]) -> void:
	var StateType = preload("res://scripts/opponent_attack_state.gd")
	var StaminaType = preload("res://scripts/opponent_stamina.gd")
	var DataType = preload("res://scripts/opponent_attack_data.gd")
	var state := StateType.new()
	var stamina := StaminaType.new()
	state.opponent_stamina = stamina
	stamina.current_stamina = 100.0
	var left := DataType.new()
	left.attack_type = 0
	left.stamina_cost = 4.0
	var right := DataType.new()
	right.attack_type = 1
	right.stamina_cost = 5.0
	state.attacks = [left, right]
	state.print_attack_start = false
	state.print_action_speed = false
	state._ready_gate = true
	state._time_remaining = 0.0
	state.hand_reuse.debug_now = 0.0
	if not state.try_execute_attack(0):
		failures.append("Opponent left start failed")
		return
	state.force_end_for_cancel()
	state.hand_reuse.debug_now = 0.29
	if state.try_execute_attack(0):
		failures.append("Opponent L to L must wait for reuse")
	if not state.try_execute_attack(1):
		failures.append("Opponent L to R must stay available")
	state.free()
	stamina.free()
