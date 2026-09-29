extends SceneTree

## Normal HIT never gameplay-stuns either fighter.
## Run: godot --headless --path . -s res://tests/combat/hit_stun_smoke_test.gd

const HitStunType = preload("res://scripts/hit_stun.gd")
const AttackType = preload("res://scripts/player_attack_state.gd")
const DataType = preload("res://scripts/attack_data.gd")
const StaminaType = preload("res://scripts/player_stamina.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var stun := HitStunType.new()
	stun.apply_hit_stun()
	if stun.is_hit_stunned() or stun.can_apply_new_stun():
		failures.append("Normal HIT must not gameplay-stun")
	var attack := AttackType.new()
	var stamina := StaminaType.new()
	stamina.current_stamina = 100.0
	stamina.max_stamina = 100.0
	attack.player_stamina = stamina
	attack.hit_stun = stun
	var data := DataType.new()
	data.attack_type = 0
	data.startup_time = 0.10
	data.active_time = 0.08
	data.recovery_time = 0.11
	data.stamina_cost = 4.0
	attack.attacks = [data]
	attack.hand_reuse.debug_now = 0.0
	if not attack.try_start_attack(0):
		failures.append("Player attack did not start")
	else:
		stun.apply_hit_stun()
		attack._process(0.10)
		if attack.current_state != AttackType.AttackState.ACTIVE:
			failures.append("A hit during startup must not stop the attack")
	if failures.is_empty():
		print("SMOKE PASS: hit stun")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)
