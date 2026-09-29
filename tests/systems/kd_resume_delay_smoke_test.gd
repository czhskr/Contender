extends SceneTree

## Stand-up waits 2 seconds, then BEGIN, then both fighters resume.
## godot --headless --path . -s res://tests/systems/kd_resume_delay_smoke_test.gd

const KD = preload("res://scripts/knockdown_manager.gd")
const Meter = preload("res://scripts/knockdown_meter.gd")
const AttackData = preload("res://scripts/attack_data.gd")
const OppAttackData = preload("res://scripts/opponent_attack_data.gd")
const PlayerAttack = preload("res://scripts/player_attack_state.gd")
const OppAttack = preload("res://scripts/opponent_attack_state.gd")
const PlayerAction = preload("res://scripts/player_action_state.gd")
const OppAction = preload("res://scripts/opponent_action_state.gd")
const PlayerStamina = preload("res://scripts/player_stamina.gd")
const OppStamina = preload("res://scripts/opponent_stamina.gd")
const RoundManager = preload("res://scripts/round_manager.gd")
const Buffer = preload("res://scripts/player_action_buffer.gd")
const Evade = preload("res://scripts/player_evade.gd")
const InputNode = preload("res://scripts/player_combat_input.gd")
const AI = preload("res://scripts/opponent_ai.gd")
const RoundIntro = preload("res://scripts/round_intro.gd")
const Recovery = preload("res://scripts/recovery_chance_settings.gd")
const Difficulty = preload("res://scripts/opponent_difficulty_settings.gd")
const Announcement = preload("res://scripts/combat_announcement.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_unchanged_rules(failures)
	await _check_banners(failures)
	await _check_single_success(failures)
	_check_single_fail(failures)
	await _check_double_success(failures)
	_check_one_sided(failures)
	_check_double_ko(failures)
	if failures.is_empty():
		print("SMOKE PASS: knockdown resume delay")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_unchanged_rules(failures: Array[String]) -> void:
	var settings := Recovery.new()
	if not is_equal_approx(settings.recovery_stamina_amount, 15.0):
		failures.append("recovery stamina amount changed")
	var chance := float(settings.calculate_recovery_chance(100.0))
	if not is_equal_approx(chance, settings.max_recovery_chance):
		failures.append("full stamina recovery is not the curve maximum")
	if settings.calculate_stand_up_count(100.0) < 3:
		failures.append("full stamina can still stand before count 3")
	var difficulty := Difficulty.new()
	if not is_equal_approx(difficulty.reaction_delay, 0.234):
		failures.append("difficulty reaction baseline changed")
	if not is_equal_approx(RoundIntro.TOTAL, 2.75):
		failures.append("round intro length changed")
	var kd := KD.new()
	if not is_equal_approx(kd.resume_delay_seconds, 2.0) or not is_equal_approx(kd.count_interval, 1.0):
		failures.append("resume delay was mixed into the count interval")
	if not is_equal_approx(kd.recovery_meter_ratio, 0.5):
		failures.append("recovery meter ratio changed")


func _check_banners(failures: Array[String]) -> void:
	var banner := Announcement.new()
	root.add_child(banner)
	banner.play_round(2)
	if banner.current_text != "ROUND 2":
		failures.append("ROUND announcement changed")
	banner.play_fight()
	if banner.current_text != "FIGHT" or not banner._banner.light_slab:
		failures.append("FIGHT announcement changed")
	banner.play_knockout()
	if banner.current_text != "KNOCKOUT":
		failures.append("KNOCKOUT announcement changed")
	banner.play_decision()
	if banner.current_text != "DECISION":
		failures.append("DECISION announcement changed")
	banner.show_count(4)
	if not banner._count.visible or banner.current_text != "4":
		failures.append("count announcement did not replace the slab")
	banner.play_begin()
	if banner.current_text != "BEGIN" or banner._count.visible or not banner._banner.light_slab:
		failures.append("BEGIN did not reuse the FIGHT slab")
	if not is_equal_approx(banner.light_pass_length(), 0.72):
		failures.append("BEGIN timing does not match FIGHT")
	await create_timer(0.95).timeout
	if banner.current_text == "4" or banner._count.visible or banner.current_text == "FIGHT" or banner.current_text == "DECISION":
		failures.append("a stale announcement returned after BEGIN")
	banner.free()


func _check_single_success(failures: Array[String]) -> void:
	var ctx := _arm()
	ctx.player_stamina.current_stamina = 40.0
	ctx.kd.queue_recovery_result(KD.DownedSide.PLAYER, true, 1)
	ctx.kd.begin_player_knockdown()
	if ctx.round.timer_paused != true:
		failures.append("count did not pause the round timer")
	ctx.kd._process(1.0)
	if ctx.kd.match_state != KD.MatchState.RESUME_DELAY:
		failures.append("stand-up went straight to fighting")
	if ctx.kd.is_fighting() or ctx.kd.can_accept_combat_input():
		failures.append("resume delay still accepts combat")
	if not is_equal_approx(ctx.player_meter.current_meter, 150.0):
		failures.append("recovery KD is not 150")
	if not is_equal_approx(ctx.player_stamina.current_stamina, 55.0):
		failures.append("recovery stamina is not +15")
	if ctx.player_attack.try_start_attack(0):
		failures.append("player attack started during resume delay")
	ctx.player_action.set_guard_held(true)
	if ctx.player_action.is_guarding():
		failures.append("guard started during resume delay")
	if ctx.evade.try_begin_window(1):
		failures.append("evade started during resume delay")
	ctx.buffer.buffer_attack(0)
	ctx.input.is_guarding = true
	ctx.ai._reaction_pending = true
	ctx.ai._offense_cooldown = 0.0
	ctx.kd._process(0.4)
	if ctx.buffer.has_buffered() or ctx.input.is_guarding:
		failures.append("stale input survived the resume delay")
	if ctx.ai._reaction_pending or ctx.opp_attack.combat_enabled:
		failures.append("AI pending action survived the resume delay")
	if ctx.opp_attack.try_execute_attack(0):
		failures.append("opponent attack started during resume delay")
	if not ctx.round.timer_paused or not is_equal_approx(ctx.round.time_remaining, 60.0):
		failures.append("round timer ran during resume delay")
	ctx.round._process(0.5)
	if not is_equal_approx(ctx.round.time_remaining, 60.0):
		failures.append("paused timer still counted down")
	ctx.kd._process(0.8)
	if ctx.banner.current_text == "BEGIN" or ctx.kd.match_state != KD.MatchState.RESUME_DELAY:
		failures.append("BEGIN started before the quiet part of the delay")
	if not is_equal_approx(ctx.kd._resume_time_remaining, 0.8):
		failures.append("resume delay is not 2.0 seconds")
	ctx.banner.show_count(7)
	ctx.kd._process(0.08)
	if ctx.banner.current_text != "BEGIN" or ctx.banner._count.visible:
		failures.append("BEGIN did not replace the count")
	if ctx.kd.is_fighting() or ctx.kd.can_accept_combat_input() or ctx.opp_attack.combat_enabled:
		failures.append("fighting started before BEGIN finished")
	if ctx.player_stamina.regeneration_enabled or not ctx.round.timer_paused:
		failures.append("regen or the round timer resumed during BEGIN")
	if ctx.player_attack.try_start_attack(0) or ctx.evade.try_begin_window(1):
		failures.append("player input worked during BEGIN")
	ctx.buffer.buffer_attack(0)
	ctx.input.is_guarding = true
	ctx.ai._reaction_pending = true
	await create_timer(0.55).timeout
	if ctx.kd.match_state != KD.MatchState.RESUME_DELAY or ctx.buffer.has_buffered() or ctx.input.is_guarding:
		failures.append("BEGIN ended early or stale input survived")
	if ctx.ai._reaction_pending:
		failures.append("opponent pending action survived BEGIN")
	await create_timer(0.30).timeout
	if ctx.kd.match_state != KD.MatchState.FIGHTING or not ctx.kd.can_accept_combat_input():
		failures.append("fighting did not resume when BEGIN finished")
	if ctx.begins[0] != 1:
		failures.append("single recovery did not show BEGIN once")
	if ctx.player_attack.current_state != 0:
		failures.append("held input became an attack when BEGIN finished")
	if not ctx.opp_attack.combat_enabled or not ctx.player_stamina.regeneration_enabled or not ctx.opp_stamina.regeneration_enabled:
		failures.append("one side resumed before the other")
	if ctx.round.timer_paused:
		failures.append("round timer stayed paused after fighting resumed")
	var before: float = ctx.round.time_remaining
	ctx.round._process(0.25)
	if not is_equal_approx(ctx.round.time_remaining, before - 0.25):
		failures.append("round timer did not resume")
	if not ctx.player_attack.try_start_attack(0):
		failures.append("player attack did not work after resume")
	if not ctx.opp_attack.try_execute_attack(0):
		failures.append("opponent attack did not work after resume")
	ctx.root.free()


func _check_single_fail(failures: Array[String]) -> void:
	var ctx := _arm()
	var states: Array[int] = []
	ctx.kd.match_state_changed.connect(func(state: int) -> void:
		states.append(state)
	)
	ctx.kd.queue_recovery_result(KD.DownedSide.OPPONENT, false, 3)
	ctx.kd.begin_opponent_knockdown()
	for _i in 10:
		ctx.kd._process(1.0)
	if states.has(KD.MatchState.RESUME_DELAY):
		failures.append("failed recovery still played resume delay")
	if ctx.begins[0] != 0:
		failures.append("failed recovery played BEGIN")
	if not states.has(KD.MatchState.FINAL_KO):
		failures.append("count 10 did not reach final KO")
	ctx.root.free()


func _check_double_success(failures: Array[String]) -> void:
	var ctx := _arm()
	ctx.player_stamina.current_stamina = 40.0
	ctx.opp_stamina.current_stamina = 40.0
	ctx.kd.queue_recovery_result(KD.DownedSide.PLAYER, true, 1)
	ctx.kd.queue_recovery_result(KD.DownedSide.OPPONENT, true, 2)
	ctx.kd._begin_double_knockdown()
	ctx.kd._process(1.0)
	if ctx.kd.match_state != KD.MatchState.DOUBLE_DOWN or ctx.kd.can_accept_combat_input():
		failures.append("the first fighter to stand became active")
	ctx.kd._process(1.0)
	if ctx.kd.match_state != KD.MatchState.RESUME_DELAY:
		failures.append("both standing did not share one resume delay")
	if ctx.kd.can_accept_combat_input() or ctx.opp_attack.combat_enabled:
		failures.append("one side could act before the shared delay ended")
	if not is_equal_approx(ctx.player_meter.current_meter, 150.0) or not is_equal_approx(ctx.opp_meter.current_meter, 150.0):
		failures.append("double recovery meter is not 150")
	ctx.kd._process(1.2)
	if ctx.banner.current_text == "BEGIN":
		failures.append("shared BEGIN started during the quiet delay")
	ctx.kd._process(0.08)
	if ctx.banner.current_text != "BEGIN" or ctx.kd.is_fighting():
		failures.append("shared recovery did not show one BEGIN while still delayed")
	await create_timer(0.90).timeout
	if ctx.begins[0] != 1:
		failures.append("double recovery played BEGIN %d times" % ctx.begins[0])
	if ctx.kd.match_state != KD.MatchState.FIGHTING or not ctx.opp_attack.combat_enabled or not ctx.kd.can_accept_combat_input():
		failures.append("both fighters did not resume when BEGIN finished")
	ctx.root.free()


func _check_one_sided(failures: Array[String]) -> void:
	var ctx := _arm()
	var states: Array[int] = []
	ctx.kd.match_state_changed.connect(func(state: int) -> void:
		states.append(state)
	)
	ctx.kd.queue_recovery_result(KD.DownedSide.PLAYER, true, 2)
	ctx.kd.queue_recovery_result(KD.DownedSide.OPPONENT, false, 1)
	ctx.kd._begin_double_knockdown()
	ctx.kd._process(1.0)
	ctx.kd._process(1.0)
	if ctx.kd.is_fighting() or ctx.kd.can_accept_combat_input():
		failures.append("the standing fighter became active while the other was counted out")
	for _i in 8:
		ctx.kd._process(1.0)
	if states.has(KD.MatchState.RESUME_DELAY):
		failures.append("one-sided recovery played a shared resume delay")
	if ctx.begins[0] != 0:
		failures.append("one-sided recovery played BEGIN")
	if not states.has(KD.MatchState.FINAL_KO):
		failures.append("one-sided recovery did not finish as a KO")
	ctx.root.free()


func _check_double_ko(failures: Array[String]) -> void:
	var ctx := _arm()
	var voided := [false]
	var delayed := [false]
	ctx.kd.round_voided.connect(func() -> void:
		voided[0] = true
	)
	ctx.kd.match_state_changed.connect(func(state: int) -> void:
		if state == KD.MatchState.RESUME_DELAY:
			delayed[0] = true
	)
	ctx.kd.queue_recovery_result(KD.DownedSide.PLAYER, false, 1)
	ctx.kd.queue_recovery_result(KD.DownedSide.OPPONENT, false, 1)
	ctx.kd._begin_double_knockdown()
	for _i in 10:
		ctx.kd._process(1.0)
	if delayed[0]:
		failures.append("double KO played a resume delay")
	if ctx.begins[0] != 0:
		failures.append("double KO played BEGIN")
	if not voided[0]:
		failures.append("double KO did not void the round")
	ctx.root.free()


func _arm() -> Dictionary:
	var fight := Node.new()
	var kd := KD.new()
	kd.name = "KnockdownManager"
	kd.print_events = false
	kd.enable_debug_force_knockdown = false
	var player_meter := Meter.new()
	var opp_meter := Meter.new()
	var player_stamina := PlayerStamina.new()
	var opp_stamina := OppStamina.new()
	var player_attack := PlayerAttack.new()
	player_attack.print_action_speed = false
	var opp_attack := OppAttack.new()
	var player_action := PlayerAction.new()
	player_action.print_state_changes = false
	player_action.attack_state = player_attack
	var opp_action := OppAction.new()
	opp_action.attack_state = opp_attack
	var left := AttackData.new()
	left.attack_type = 0
	left.startup_time = 0.1
	left.active_time = 0.08
	left.recovery_time = 0.11
	left.stamina_cost = 4.0
	left.knockdown_damage = 8.0
	var attacks: Array[AttackData] = []
	attacks.append(left)
	player_attack.attacks = attacks
	player_attack.player_stamina = player_stamina
	var opp_left := OppAttackData.new()
	opp_left.attack_type = 0
	opp_left.startup_time = 0.1
	opp_left.active_time = 0.08
	opp_left.recovery_time = 0.11
	opp_left.stamina_cost = 4.0
	opp_left.knockdown_damage = 8.0
	var opp_attacks: Array[OppAttackData] = []
	opp_attacks.append(opp_left)
	opp_attack.attacks = opp_attacks
	opp_attack.opponent_stamina = opp_stamina
	kd.player_attack_state = player_attack
	kd.player_action_state = player_action
	kd.opponent_attack_state = opp_attack
	kd.opponent_action_state = opp_action
	kd.player_stamina = player_stamina
	kd.opponent_stamina = opp_stamina
	kd.player_knockdown_meter = player_meter
	kd.opponent_knockdown_meter = opp_meter
	kd.player_recovery_settings = load("res://data/ko/player_recovery_chance.tres")
	kd.opponent_recovery_settings = load("res://data/ko/opponent_recovery_chance.tres")
	var buffer := Buffer.new()
	buffer.name = "PlayerActionBuffer"
	var combat_input := InputNode.new()
	combat_input.name = "PlayerCombatInput"
	var evade := Evade.new()
	evade.name = "PlayerEvade"
	evade.player_stamina = player_stamina
	var ai := AI.new()
	ai.name = "OpponentAI"
	ai.print_ai_decisions = false
	ai.player_attack_state = player_attack
	ai.opponent_attack_state = opp_attack
	ai.opponent_action_state = opp_action
	ai.opponent_stamina = opp_stamina
	ai.knockdown_manager = kd
	var rounds := RoundManager.new()
	rounds.name = "RoundManager"
	rounds.auto_start = false
	rounds.print_events = false
	rounds.knockdown_manager = kd
	rounds.player_attack_state = player_attack
	rounds.player_action_state = player_action
	rounds.opponent_attack_state = opp_attack
	rounds.opponent_action_state = opp_action
	rounds.player_stamina = player_stamina
	rounds.opponent_stamina = opp_stamina
	var banner := Announcement.new()
	banner.name = "CombatAnnouncement"
	var begins: Array = [0]
	banner.pass_finished.connect(func(text: String) -> void:
		if text == "BEGIN":
			begins[0] = int(begins[0]) + 1
	)
	for node in [player_meter, opp_meter, player_stamina, opp_stamina, player_attack, opp_attack, player_action, opp_action, buffer, combat_input, evade, ai, kd, rounds, banner]:
		fight.add_child(node)
	root.add_child(fight)
	rounds.set_process(false)
	rounds.round_state = RoundManager.RoundState.FIGHTING
	rounds.current_round = 1
	rounds.time_remaining = 60.0
	rounds.timer_paused = false
	kd.set_combat_control_enabled(true)
	return {
		"root": fight,
		"kd": kd,
		"round": rounds,
		"player_meter": player_meter,
		"opp_meter": opp_meter,
		"player_stamina": player_stamina,
		"opp_stamina": opp_stamina,
		"player_attack": player_attack,
		"opp_attack": opp_attack,
		"player_action": player_action,
		"buffer": buffer,
		"input": combat_input,
		"evade": evade,
		"ai": ai,
		"banner": banner,
		"begins": begins,
	}
