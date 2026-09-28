extends SceneTree

## Traits, KD 300, and best-of-three round wins.
## Run: godot --headless --path . -s res://trait_match_smoke_test.gd

const Catalog = preload("res://scripts/trait_catalog.gd")
const ManagerType = preload("res://scripts/trait_manager.gd")
const MathType = preload("res://scripts/trait_math.gd")
const TraitType = preload("res://scripts/fighter_trait.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")
const ScorerType = preload("res://scripts/round_scorer.gd")
const StatsType = preload("res://scripts/combat_side_stats.gd")
const RoundType = preload("res://scripts/round_manager.gd")
const EvadeType = preload("res://scripts/player_evade.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_pair_rules(failures)
	_check_effects(failures)
	_check_meter_and_match(failures)
	if failures.is_empty():
		print("SMOKE PASS: trait match")
		quit(0)
		return
	print("SMOKE FAIL:")
	for failure in failures:
		print(" - %s" % failure)
	quit(1)


func _trait(id: int) -> Resource:
	for entry in Catalog.all_traits():
		if entry.id == id:
			return entry
	return null


func _check_pair_rules(failures: Array[String]) -> void:
	var manager := ManagerType.new()
	root.add_child(manager)
	manager.set_seed(7)
	var seen := {}
	for round_index in 3:
		manager.reroll_round()
		if manager.player_traits.size() != 1 or manager.opponent_traits.size() != 1:
			failures.append("Each fighter needs exactly 1 trait")
		seen[round_index] = manager.player_traits[0].id
	var shared := false
	for _try in 40:
		manager.reroll_round()
		if manager.player_traits[0].id == manager.opponent_traits[0].id:
			shared = true
			break
	if not shared:
		failures.append("Both fighters should be able to draw the same trait")
	manager.queue_free()


func _check_effects(failures: Array[String]) -> void:
	var iron := _trait(TraitType.Id.IRON_GUARD)
	var heavy := _trait(TraitType.Id.HEAVY_HANDS)
	var glass := _trait(TraitType.Id.GLASS_CANNON)
	var endure := _trait(TraitType.Id.ENDURANCE)
	var chin := _trait(TraitType.Id.TOUGH_CHIN)
	var efficient := _trait(TraitType.Id.EFFICIENT_STRIKER)
	var hooks := _trait(TraitType.Id.POWER_HOOKS)
	var straight := _trait(TraitType.Id.SHARP_STRAIGHT)
	var last := _trait(TraitType.Id.LAST_STAND)
	var feet := _trait(TraitType.Id.QUICK_FEET)
	var reflex := _trait(TraitType.Id.REFLEX)
	var pressure := _trait(TraitType.Id.PRESSURE_FIGHTER)
	if not is_equal_approx(MathType.taken_kd(10.0, [iron], 100.0, true, 1.0), 0.0):
		failures.append("Iron Guard block should be 0")
	if not is_equal_approx(MathType.taken_kd(10.0, [iron], 100.0, false, 1.0), 20.0):
		failures.append("Iron Guard clean hit should be x2")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 1, [heavy], 100.0), 20.0):
		failures.append("Heavy Hands outgoing x2")
	if not is_equal_approx(MathType.attack_cost(5.0, [heavy]), 10.0):
		failures.append("Heavy Hands cost x2")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 1, [glass], 100.0), 20.0):
		failures.append("Glass Cannon outgoing x2")
	if not is_equal_approx(MathType.taken_kd(20.0, [glass], 100.0, false, 1.0), 40.0):
		failures.append("Glass Cannon incoming x2")
	if not is_equal_approx(MathType.regen_multiplier([endure]), 2.0):
		failures.append("Endurance regen x2")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 1, [endure], 100.0), 5.0):
		failures.append("Endurance damage x0.5")
	if not is_equal_approx(MathType.taken_kd(10.0, [chin], 100.0, false, 1.0), 5.0):
		failures.append("Tough Chin incoming x0.5")
	if not is_equal_approx(MathType.attack_cost(8.0, [chin]), 12.0):
		failures.append("Tough Chin cost x1.5")
	if not is_equal_approx(MathType.attack_cost(8.0, [efficient]), 4.0):
		failures.append("Efficient cost x0.5")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 2, [hooks], 100.0), 20.0):
		failures.append("Power Hooks hook x2")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 0, [hooks], 100.0), 5.0):
		failures.append("Power Hooks straight x0.5")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 0, [straight], 100.0), 20.0):
		failures.append("Sharp Straight straight x2")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 2, [straight], 100.0), 5.0):
		failures.append("Sharp Straight hook x0.5")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 1, [last], 25.0), 20.0):
		failures.append("Last Stand should double outgoing at 25")
	if not is_equal_approx(MathType.outgoing_kd(10.0, 1, [last], 26.0), 10.0):
		failures.append("Last Stand should be idle above 25")
	if not is_equal_approx(feet.evade_window, 1.5) or not is_equal_approx(feet.slip_duration, 1.5):
		failures.append("Quick Feet window/slip x1.5")
	if not is_equal_approx(MathType.taken_kd(10.0, [feet], 100.0, true, 1.0), 5.0):
		failures.append("Quick Feet block should be x2 after the 0.25 guard cut")
	if not is_equal_approx(reflex.evade_retrigger, 0.5) or not is_equal_approx(reflex.reaction_time, 0.5):
		failures.append("Reflex timing x0.5")
	if not is_equal_approx(MathType.attack_cost(4.0, [reflex]), 6.0):
		failures.append("Reflex cost x1.5")
	if not is_equal_approx(pressure.attack_link_threshold, 0.5):
		failures.append("Pressure should halve the attack-link threshold")
	if not is_equal_approx(MathType.regen_multiplier([pressure]), 0.5):
		failures.append("Pressure regen x0.5")
	if not is_equal_approx(MathType.outgoing_kd(15.0, 2, [heavy, hooks], 100.0), 37.5):
		failures.append("Heavy Hands + Power Hooks should cap at x2.5")
	var evade := EvadeType.new()
	if not is_equal_approx(evade.evade_window, 0.18):
		failures.append("Base evade window was mutated")
	evade.free()


func _check_meter_and_match(failures: Array[String]) -> void:
	var meter := MeterType.new()
	if not is_equal_approx(meter.max_meter, 300.0):
		failures.append("KD max should be 300")
	meter.current_meter = 299.0
	meter.apply_knockdown_damage(1.0)
	if not meter.is_full():
		failures.append("300 should knock down")
	var rounds := RoundType.new()
	if not is_equal_approx(rounds.round_duration, 60.0) or rounds.wins_to_finish != 2:
		failures.append("Match should be 60s rounds, first to 2")
	rounds.player_round_wins = 2
	rounds.opponent_round_wins = 0
	if not rounds._someone_clinched():
		failures.append("2-0 should clinch")
	rounds.player_round_wins = 1
	rounds.opponent_round_wins = 1
	if rounds._someone_clinched():
		failures.append("1-1 should continue")
	var player := StatsType.new()
	var opponent := StatsType.new()
	player.attacks_landed = 1
	var scorer := ScorerType.new()
	if scorer.decide_round_winner(player, opponent, 1) != 1:
		failures.append("Tie-break should prefer landed punches")
	player.attacks_landed = 0
	opponent.attacks_landed = 0
	if scorer.decide_round_winner(player, opponent, 2) != 2:
		failures.append("Fully tied even round should pick opponent deterministically")
	meter.free()
	rounds.free()
	scorer.free()
