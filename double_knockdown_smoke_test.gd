extends SceneTree

## Double Knockdown resolution. Run:
## godot --headless --path . -s res://double_knockdown_smoke_test.gd

const KD = preload("res://scripts/knockdown_manager.gd")
const Offense = preload("res://scripts/player_offense_resolver.gd")
const Defense = preload("res://scripts/player_defense_resolver.gd")
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
const OppVisual = preload("res://scripts/opponent_visual.gd")
const PlayerVisual = preload("res://scripts/player_visual.gd")
const Finisher = preload("res://scripts/finisher_impact_freeze.gd")


class TraitStub extends Node:
	var rolls := 0
	var player_traits: Array = []
	var opponent_traits: Array = []

	func reroll_round() -> void:
		rolls += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_stamina_unchanged(failures)
	_check_only_one_side(failures, false)
	_check_only_one_side(failures, true)
	_check_phase_excluded(failures, OppAttack.AttackState.STARTUP, "startup")
	_check_phase_excluded(failures, OppAttack.AttackState.RECOVERY, "recovery")
	_check_active_trade(failures, true)
	_check_active_trade(failures, false)
	_check_registered_token_only(failures)
	_check_both_recover(failures)
	_check_one_sided_recovery(failures, true)
	_check_one_sided_recovery(failures, false)
	_check_double_ko_rematch(failures)
	_check_single_regression(failures)
	_check_stale_visual(failures)
	_check_one_finisher(failures)
	if failures.is_empty():
		print("SMOKE PASS: double knockdown")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_stamina_unchanged(failures: Array[String]) -> void:
	var player := PlayerStamina.new()
	var opponent := OppStamina.new()
	if not is_equal_approx(player.regeneration_delay, 0.65) or not is_equal_approx(opponent.regeneration_delay, 0.65):
		failures.append("regen delay must stay 0.65 on both")
	if not is_equal_approx(player.regeneration_per_second, 12.0) or not is_equal_approx(opponent.regeneration_per_second, 8.0):
		failures.append("regen rate changed")
	player.free()
	opponent.free()


func _check_only_one_side(failures: Array[String], player_down: bool) -> void:
	var ctx := _make(false)
	root.add_child(ctx.root)
	ctx.player_meter.set_meter(8.0 if player_down else 300.0)
	ctx.opp_meter.set_meter(300.0 if player_down else 8.0)
	ctx.kd.queue_recovery_result(KD.DownedSide.PLAYER if player_down else KD.DownedSide.OPPONENT, true, 4)
	if player_down:
		ctx.opp_attack.current_state = OppAttack.AttackState.IDLE
		ctx.defense.resolve_attack(ctx.opp_data)
	else:
		ctx.player_attack.current_state = PlayerAttack.AttackState.ACTIVE
		ctx.offense.resolve_hit_now(0)
	var expected: int = KD.MatchState.PLAYER_DOWN if player_down else KD.MatchState.OPPONENT_DOWN
	if ctx.kd.match_state != expected:
		failures.append("single side state got %d" % ctx.kd.match_state)
	ctx.root.free()


func _check_phase_excluded(failures: Array[String], phase: int, label: String) -> void:
	var ctx := _make(false)
	root.add_child(ctx.root)
	ctx.opp_meter.set_meter(8.0)
	ctx.opp_attack.current_state = phase
	ctx.player_attack.current_state = PlayerAttack.AttackState.ACTIVE
	ctx.kd.queue_recovery_result(KD.DownedSide.OPPONENT, true, 3)
	ctx.offense.resolve_hit_now(0)
	if ctx.kd.match_state != KD.MatchState.OPPONENT_DOWN:
		failures.append("%s should be single opponent knockdown, state %d" % [label, ctx.kd.match_state])
	if ctx.opp_attack.current_state != OppAttack.AttackState.IDLE:
		failures.append("%s attack should be cancelled" % label)
	ctx.root.free()


func _check_active_trade(failures: Array[String], player_first: bool) -> void:
	var ctx := _make(false)
	root.add_child(ctx.root)
	ctx.player_meter.set_meter(8.0)
	ctx.opp_meter.set_meter(8.0)
	ctx.player_attack.current_state = PlayerAttack.AttackState.ACTIVE
	ctx.opp_attack.current_state = OppAttack.AttackState.ACTIVE
	var before_player: int = ctx.player_attack.get_action_token()
	var before_opp: int = ctx.opp_attack.get_action_token()
	if player_first:
		ctx.offense.resolve_hit_now(0)
		ctx.defense.resolve_attack(ctx.opp_data)
	else:
		ctx.defense.resolve_attack(ctx.opp_data)
		ctx.offense.resolve_hit_now(0)
	if ctx.kd.match_state != KD.MatchState.DOUBLE_DOWN:
		failures.append("order %s expected DOUBLE_DOWN got %d" % ["player-first" if player_first else "opponent-first", ctx.kd.match_state])
	if ctx.player_meter.current_meter > 0.0 or ctx.opp_meter.current_meter > 0.0:
		failures.append("both meters should reach 0")
	if ctx.player_attack.get_action_token() != before_player and ctx.player_attack.current_state != PlayerAttack.AttackState.IDLE:
		failures.append("player attack should end after double confirm")
	if ctx.opp_attack.current_state != OppAttack.AttackState.IDLE:
		failures.append("opponent attack should end after double confirm")
	if before_opp < 0:
		failures.append("token baseline")
	ctx.root.free()


func _check_registered_token_only(failures: Array[String]) -> void:
	var ctx := _make(false)
	root.add_child(ctx.root)
	ctx.opp_meter.set_meter(8.0)
	ctx.player_meter.set_meter(300.0)
	ctx.player_attack.current_state = PlayerAttack.AttackState.ACTIVE
	ctx.opp_attack.current_state = OppAttack.AttackState.ACTIVE
	ctx.offense.resolve_hit_now(0)
	if ctx.kd.match_state != KD.MatchState.TRADE_RESOLUTION:
		failures.append("active unresolved opponent should keep trade open, state %d" % ctx.kd.match_state)
	var player_token: int = ctx.player_attack.get_action_token()
	var opp_token: int = ctx.opp_attack.get_action_token()
	if ctx.player_attack.try_start_attack(0):
		failures.append("new player attack after threshold")
	if ctx.opp_attack.try_execute_attack(0):
		failures.append("new opponent attack after threshold")
	if ctx.player_attack.get_action_token() != player_token or ctx.opp_attack.get_action_token() != opp_token:
		failures.append("threshold created a new attack token")
	ctx.opp_attack._action_token = 99
	var before: float = ctx.player_meter.current_meter
	ctx.defense.resolve_attack(ctx.opp_data)
	if ctx.player_meter.current_meter != before:
		failures.append("unregistered token applied damage")
	ctx.opp_attack._action_token = opp_token
	ctx.defense._resolved_token = -1
	ctx.defense.resolve_attack(ctx.opp_data)
	if ctx.kd.match_state != KD.MatchState.OPPONENT_DOWN:
		failures.append("registered token should confirm single knockdown, state %d" % ctx.kd.match_state)
	ctx.root.free()


func _check_both_recover(failures: Array[String]) -> void:
	var ctx := _arm_double(4, true, 7, true)
	_pump(ctx.kd, 4)
	if ctx.kd.match_state != KD.MatchState.DOUBLE_DOWN:
		failures.append("player should wait after count 4")
	if ctx.kd.can_accept_combat_input():
		failures.append("input must stay locked while the other fighter is down")
	if ctx.player_meter.current_meter != 150.0:
		failures.append("standing player meter should be 150")
	_pump(ctx.kd, 3)
	if ctx.kd.match_state != KD.MatchState.RESUME_DELAY:
		failures.append("both recover should wait before fighting")
	if ctx.kd.can_accept_combat_input():
		failures.append("input must stay locked during the shared resume delay")
	ctx.kd._process(ctx.kd.resume_delay_seconds)
	if ctx.kd.match_state != KD.MatchState.FIGHTING:
		failures.append("both recover should resume fighting")
	if ctx.opp_meter.current_meter != 150.0:
		failures.append("standing opponent meter should be 150")
	if not ctx.player_stamina.regeneration_enabled or not ctx.opp_stamina.regeneration_enabled:
		failures.append("regen should resume with fighting")
	ctx.root.free()


func _check_one_sided_recovery(failures: Array[String], player_recovers: bool) -> void:
	var ctx := _arm_double(5, player_recovers, 6, not player_recovers)
	_pump(ctx.kd, 10)
	if ctx.kd.match_state != KD.MatchState.FINAL_KO:
		failures.append("count 10 should finish the round")
	var winner: int = KD.Winner.PLAYER if player_recovers else KD.Winner.OPPONENT
	if ctx.kd.winner != winner:
		failures.append("winner mismatch %d" % ctx.kd.winner)
	ctx.root.free()


func _check_double_ko_rematch(failures: Array[String]) -> void:
	var ctx := _arm_double(1, false, 1, false)
	var round := RoundManager.new()
	round.name = "RoundManager"
	round.auto_start = false
	round.print_events = false
	round.knockdown_manager = ctx.kd
	ctx.root.add_child(round)
	var traits := TraitStub.new()
	traits.name = "TraitManager"
	ctx.root.add_child(traits)
	round.current_round = 2
	round.player_round_wins = 1
	round.opponent_round_wins = 0
	round.round_state = RoundManager.RoundState.FIGHTING
	ctx.kd.set_combat_control_enabled(true)
	_pump(ctx.kd, 10)
	if ctx.kd.winner != KD.Winner.NONE:
		failures.append("double KO must not pick a winner")
	if round.player_round_wins != 1 or round.opponent_round_wins != 0:
		failures.append("double KO changed the score")
	if round.current_round != 2:
		failures.append("double KO advanced the round")
	if traits.rolls != 1:
		failures.append("rematch should reroll traits once, got %d" % traits.rolls)
	if round.round_state != RoundManager.RoundState.TRAIT_PREVIEW:
		failures.append("rematch should open the same round preview")
	ctx.root.free()


func _check_single_regression(failures: Array[String]) -> void:
	var ctx := _make(false)
	root.add_child(ctx.root)
	ctx.opp_stamina.current_stamina = 40.0
	ctx.opp_meter.set_meter(8.0)
	ctx.player_attack.current_state = PlayerAttack.AttackState.ACTIVE
	ctx.kd.queue_recovery_result(KD.DownedSide.OPPONENT, true, 2)
	ctx.offense.resolve_hit_now(0)
	if ctx.kd.match_state != KD.MatchState.OPPONENT_DOWN:
		failures.append("single regression did not go down")
	_pump(ctx.kd, 2)
	if ctx.kd.match_state != KD.MatchState.RESUME_DELAY:
		failures.append("single recovery should wait before fighting")
	ctx.kd._process(ctx.kd.resume_delay_seconds)
	if ctx.kd.match_state != KD.MatchState.FIGHTING:
		failures.append("single recovery did not resume")
	if ctx.opp_meter.current_meter != 150.0:
		failures.append("single recovery meter")
	if not is_equal_approx(ctx.opp_stamina.current_stamina, 55.0):
		failures.append("single recovery stamina +15")
	ctx.root.free()


func _check_stale_visual(failures: Array[String]) -> void:
	var ctx := _make(false)
	root.add_child(ctx.root)
	var visual := OppVisual.new()
	visual.knockdown_manager = ctx.kd
	ctx.root.add_child(visual)
	visual._build_nodes()
	visual._attack_pose_holding = true
	visual._priority = 2
	ctx.kd.match_state = KD.MatchState.DOUBLE_DOWN
	visual._on_match_state_changed(KD.MatchState.DOUBLE_DOWN)
	if visual._attack_pose_holding:
		failures.append("double knockdown left the attack hold")
	visual._release_attack_pose_to_stance()
	visual._begin_attack_pose(0)
	if visual._priority < 4:
		failures.append("stale attack callback restored a punch over down")
	var player_visual := PlayerVisual.new()
	player_visual.knockdown_manager = ctx.kd
	ctx.root.add_child(player_visual)
	player_visual._build_nodes()
	player_visual._on_match_state_changed(KD.MatchState.DOUBLE_DOWN)
	if not player_visual._knocked_down:
		failures.append("player down presentation missing on double knockdown")
	ctx.root.free()


func _check_one_finisher(failures: Array[String]) -> void:
	var ctx := _make(true)
	root.add_child(ctx.root)
	ctx.finisher.finisher_freeze_duration = 30.0
	var starts := [0]
	ctx.finisher.finisher_started.connect(func(_s): starts[0] += 1)
	ctx.player_meter.set_meter(8.0)
	ctx.opp_meter.set_meter(8.0)
	ctx.player_attack.current_state = PlayerAttack.AttackState.ACTIVE
	ctx.opp_attack.current_state = OppAttack.AttackState.ACTIVE
	ctx.offense.resolve_hit_now(0)
	ctx.defense.resolve_attack(ctx.opp_data)
	if starts[0] != 1:
		failures.append("double knockdown started %d finishers" % starts[0])
	if ctx.kd.match_state == KD.MatchState.DOUBLE_DOWN:
		failures.append("count started before the shared freeze")
	ctx.kd._on_finisher_finished(KD.DownedSide.PLAYER)
	if ctx.kd.match_state != KD.MatchState.DOUBLE_DOWN:
		failures.append("shared freeze should release into double down")
	ctx.root.free()


func _arm_double(player_count: int, player_ok: bool, opp_count: int, opp_ok: bool) -> Dictionary:
	var ctx := _make(false)
	root.add_child(ctx.root)
	ctx.player_stamina.current_stamina = 40.0
	ctx.opp_stamina.current_stamina = 40.0
	ctx.player_meter.set_meter(8.0)
	ctx.opp_meter.set_meter(8.0)
	ctx.player_attack.current_state = PlayerAttack.AttackState.ACTIVE
	ctx.opp_attack.current_state = OppAttack.AttackState.ACTIVE
	ctx.kd.queue_recovery_result(KD.DownedSide.PLAYER, player_ok, player_count)
	ctx.kd.queue_recovery_result(KD.DownedSide.OPPONENT, opp_ok, opp_count)
	ctx.offense.resolve_hit_now(0)
	ctx.defense.resolve_attack(ctx.opp_data)
	return ctx


func _pump(kd: KD, steps: int) -> void:
	for _i in steps:
		kd._process(1.0)


func _make(with_finisher: bool) -> Dictionary:
	var holder := Node.new()
	holder.name = "Fight"
	var player_meter := Meter.new()
	var opp_meter := Meter.new()
	var player_stamina := PlayerStamina.new()
	var opp_stamina := OppStamina.new()
	var player_attack := PlayerAttack.new()
	var opp_attack := OppAttack.new()
	var player_action := PlayerAction.new()
	var opp_action := OppAction.new()
	var offense := Offense.new()
	var defense := Defense.new()
	var kd := KD.new()
	kd.name = "KnockdownManager"
	var left := AttackData.new()
	left.attack_type = 0
	left.knockdown_damage = 8.0
	left.stamina_cost = 4.0
	var attacks: Array[AttackData] = []
	attacks.append(left)
	player_attack.attacks = attacks
	player_attack.player_stamina = player_stamina
	var opp_left := OppAttackData.new()
	opp_left.attack_type = 0
	opp_left.knockdown_damage = 8.0
	opp_left.stamina_cost = 4.0
	var opp_list: Array[OppAttackData] = []
	opp_list.append(opp_left)
	opp_attack.attacks = opp_list
	opp_attack.opponent_stamina = opp_stamina
	offense.player_attack_state = player_attack
	offense.opponent_action_state = opp_action
	offense.opponent_knockdown_meter = opp_meter
	offense.opponent_stamina = opp_stamina
	offense.print_hit_results = false
	defense.player_action_state = player_action
	defense.player_knockdown_meter = player_meter
	defense.player_stamina = player_stamina
	defense.opponent_attack_state = opp_attack
	defense.print_hit_results = false
	kd.player_attack_state = player_attack
	kd.player_action_state = player_action
	player_action.attack_state = player_attack
	opp_action.attack_state = opp_attack
	kd.opponent_attack_state = opp_attack
	kd.opponent_action_state = opp_action
	kd.player_stamina = player_stamina
	kd.opponent_stamina = opp_stamina
	kd.player_knockdown_meter = player_meter
	kd.opponent_knockdown_meter = opp_meter
	kd.offense_resolver = offense
	kd.defense_resolver = defense
	kd.player_recovery_settings = load("res://data/ko/player_recovery_chance.tres")
	kd.opponent_recovery_settings = load("res://data/ko/opponent_recovery_chance.tres")
	kd.print_events = false
	kd.enable_debug_force_knockdown = false
	var finisher: Node = null
	if with_finisher:
		finisher = Finisher.new()
		finisher.name = "FinisherImpactFreeze"
		holder.add_child(finisher)
	for node in [player_meter, opp_meter, player_stamina, opp_stamina, player_attack, opp_attack, player_action, opp_action, offense, defense, kd]:
		holder.add_child(node)
	kd.set_combat_control_enabled(true)
	return {
		"root": holder,
		"kd": kd,
		"offense": offense,
		"defense": defense,
		"player_meter": player_meter,
		"opp_meter": opp_meter,
		"player_attack": player_attack,
		"opp_attack": opp_attack,
		"player_stamina": player_stamina,
		"opp_stamina": opp_stamina,
		"opp_data": opp_left,
		"finisher": finisher,
	}
