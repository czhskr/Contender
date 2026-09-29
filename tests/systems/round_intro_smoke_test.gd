extends SceneTree

## Round intro holds the clock until the open finishes.
## godot --headless --path . -s res://tests/systems/round_intro_smoke_test.gd

const GameScene = preload("res://scenes/game.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var scene := GameScene.instantiate()
	var rounds = scene.get_node("RoundManager")
	rounds.auto_start = false
	rounds.force_round_intro = true
	root.add_child(scene)
	rounds.start_match()
	await process_frame
	if rounds.round_state != rounds.RoundState.ROUND_INTRO:
		failures.append("round did not open with an intro")
	if not is_equal_approx(rounds.time_remaining, 60.0):
		failures.append("timer moved before the intro")
	if rounds.can_accept_combat_input():
		failures.append("combat input was live during the intro")
	var stamina: float = scene.get_node("PlayerStamina").current_stamina
	var opp: float = scene.get_node("OpponentStamina").current_stamina
	await create_timer(0.20).timeout
	if not is_equal_approx(rounds.time_remaining, 60.0):
		failures.append("timer ran during the arena hold")
	if not is_equal_approx(scene.get_node("PlayerStamina").current_stamina, stamina):
		failures.append("player stamina changed during the intro")
	if not is_equal_approx(scene.get_node("OpponentStamina").current_stamina, opp):
		failures.append("opponent stamina changed during the intro")
	var attack = scene.get_node("OpponentAttackState")
	if attack.current_state != attack.AttackState.IDLE:
		failures.append("opponent attacked during the intro")
	await create_timer(0.40).timeout
	var banner := scene.get_node("CombatHUD/CombatAnnouncement")
	if banner.current_text != "ROUND 1":
		failures.append("ROUND 1 was not on screen, saw %s" % banner.current_text)
	if banner.phase != "hold" and banner.phase != "enter":
		failures.append("ROUND was not traveling or holding")
	await create_timer(0.90).timeout
	if banner.current_text != "FIGHT":
		failures.append("FIGHT was not on screen, saw %s" % banner.current_text)
	if rounds.round_state == rounds.RoundState.FIGHTING:
		failures.append("fighting started before the intro finished")
	if not is_equal_approx(rounds.time_remaining, 60.0):
		failures.append("timer started before FIGHT finished")
	await create_timer(1.60).timeout
	if rounds.round_state != rounds.RoundState.FIGHTING:
		failures.append("intro did not reach fighting")
	if not rounds.can_accept_combat_input():
		failures.append("input stayed locked after the intro")
	if rounds.time_remaining > 59.7:
		failures.append("timer did not start with the round")
	if banner._banner_label.get_theme_font_size("font_size") < 70:
		failures.append("FIGHT type is too small")
	banner.show_count(9)
	if banner._count.get_theme_font_size("font_size") < 76:
		failures.append("count type is too small")
	if banner._count.offset_top > -40.0:
		failures.append("count sits on the fighter's face")
	scene.free()
	if failures.is_empty():
		print("SMOKE PASS: round intro")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)
