extends SceneTree

const VisualType = preload("res://scripts/opponent_visual.gd")
const AttackType = preload("res://scripts/opponent_attack_state.gd")
const VulnType = preload("res://scripts/knockdown_vulnerability.gd")
const TraitMath = preload("res://scripts/trait_math.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_flicker(failures)
	_print_baseline()
	if failures.is_empty():
		print("SMOKE PASS: visual flicker and kd baseline")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_flicker(failures: Array[String]) -> void:
	var visual := VisualType.new()
	var attack := AttackType.new()
	visual.opponent_attack_state = attack
	attack.current_state = AttackType.AttackState.STARTUP
	if not visual._attack_visual_owns_pose():
		failures.append("Startup must keep the attack visual")
	attack.current_state = AttackType.AttackState.ACTIVE
	if not visual._attack_visual_owns_pose():
		failures.append("Active must keep the attack visual")
	attack.current_state = AttackType.AttackState.IDLE
	visual._attack_pose_holding = false
	visual._priority = VisualType.Priority.IDLE
	if visual._attack_visual_owns_pose():
		failures.append("Idle should allow the hit texture")
	visual._priority = VisualType.Priority.DEFENSE
	if visual._attack_visual_owns_pose():
		failures.append("Guard or slip should allow the hit texture")
	visual._priority = VisualType.Priority.ATTACK
	if not visual._attack_visual_owns_pose():
		failures.append("An attack presentation must block the hit texture")


func _print_baseline() -> void:
	var vuln := VulnType.new()
	print("BASELINE right straight KD")
	for stamina_value in [100.0, 75.0, 50.0, 25.0, 10.0, 0.0]:
		var scale := vuln.multiplier_for(stamina_value, 100.0)
		var normal := TraitMath.taken_kd(10.0, [], 100.0, false, scale, false)
		var counter := TraitMath.taken_kd(10.0, [], 100.0, false, scale, true)
		var blocked := TraitMath.taken_kd(10.0, [], 100.0, true, scale, true)
		print("stamina %.0f vuln=%.2f normal=%.2f counter=%.2f block=%.2f" % [stamina_value, scale, normal, counter, blocked])
