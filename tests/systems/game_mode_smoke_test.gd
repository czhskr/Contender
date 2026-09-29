extends SceneTree

## Game modes and trait eligibility.
## godot --headless --path . -s res://tests/systems/game_mode_smoke_test.gd

const ModeType = preload("res://scripts/game_mode.gd")
const ManagerType = preload("res://scripts/trait_manager.gd")
const Catalog = preload("res://scripts/trait_catalog.gd")
const MathType = preload("res://scripts/trait_math.gd")
const TraitType = preload("res://scripts/fighter_trait.gd")
const RoundType = preload("res://scripts/round_manager.gd")
const KDType = preload("res://scripts/knockdown_manager.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_baseline(failures)
	_check_eligibility(failures)
	await _check_normal_flow(failures)
	await _check_trait_flow(failures)
	_check_stress(failures)
	if failures.is_empty():
		print("SMOKE PASS: game mode")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_baseline(failures: Array[String]) -> void:
	var hit: float = _right_straight([], false, false)
	var counter: float = _right_straight([], false, true)
	var block: float = _right_straight([], true, false)
	if not is_equal_approx(hit, 10.0):
		failures.append("NORMAL right straight expected 10, got %.2f" % hit)
	if not is_equal_approx(counter, 15.0):
		failures.append("NORMAL counter expected 15, got %.2f" % counter)
	if not is_equal_approx(block, 2.5):
		failures.append("NORMAL block expected 2.5, got %.2f" % block)
	var heavy: Array = [_trait(TraitType.Id.HEAVY_HANDS)]
	if is_equal_approx(_right_straight(heavy, false, false), 10.0):
		failures.append("trait modifier did not change damage")


func _right_straight(traits: Array, blocked: bool, counter: bool) -> float:
	var result: Dictionary = MathType.compose_kd(10.0, 1, traits, 100.0, [], 100.0, blocked, 1.0, counter)
	return float(result["final"])


func _check_eligibility(failures: Array[String]) -> void:
	var player_pool: Array = Catalog.eligible_traits(Catalog.player_capabilities())
	var opponent_pool: Array = Catalog.eligible_traits(Catalog.opponent_capabilities())
	if player_pool.size() != 12:
		failures.append("player pool expected 12, got %d" % player_pool.size())
	if opponent_pool.size() != 10:
		failures.append("opponent pool expected 10, got %d" % opponent_pool.size())
	if not _pool_has(player_pool, TraitType.Id.POWER_HOOKS):
		failures.append("player should be eligible for Power Hooks")
	if _pool_has(opponent_pool, TraitType.Id.POWER_HOOKS):
		failures.append("opponent must not be eligible for Power Hooks")
	if not _pool_has(player_pool, TraitType.Id.SHARP_STRAIGHT):
		failures.append("player should be eligible for Sharp Straight")
	if _pool_has(opponent_pool, TraitType.Id.SHARP_STRAIGHT):
		failures.append("opponent must not be eligible for Sharp Straight")
	var hooks = _trait(TraitType.Id.POWER_HOOKS)
	var sharp = _trait(TraitType.Id.SHARP_STRAIGHT)
	if Catalog.exclusion_reason(hooks, Catalog.opponent_capabilities()) != "requires_hook_attack":
		failures.append("Power Hooks exclusion reason")
	if Catalog.exclusion_reason(sharp, Catalog.opponent_capabilities()) != "requires_hook_attack":
		failures.append("Sharp Straight exclusion reason")
	if Catalog.exclusion_reason(hooks, Catalog.player_capabilities()) != "":
		failures.append("Power Hooks should not be excluded for the player")
	if Catalog.exclusion_reason(sharp, Catalog.player_capabilities()) != "":
		failures.append("Sharp Straight should not be excluded for the player")


func _check_stress(failures: Array[String]) -> void:
	var manager := ManagerType.new()
	manager.print_pools = false
	manager.set_seed(3)
	root.add_child(manager)
	var player_hooks := 0
	var opponent_hooks := 0
	var player_sharp := 0
	var opponent_sharp := 0
	var shared := 0
	var seen_player := {}
	var seen_opponent := {}
	for _i in 1000:
		manager.reroll_round()
		var player_id: int = manager.player_traits[0].id
		var opponent_id: int = manager.opponent_traits[0].id
		seen_player[player_id] = true
		seen_opponent[opponent_id] = true
		if player_id == TraitType.Id.POWER_HOOKS:
			player_hooks += 1
		if opponent_id == TraitType.Id.POWER_HOOKS:
			opponent_hooks += 1
		if player_id == TraitType.Id.SHARP_STRAIGHT:
			player_sharp += 1
		if opponent_id == TraitType.Id.SHARP_STRAIGHT:
			opponent_sharp += 1
		if player_id == opponent_id:
			shared += 1
		if not Catalog.is_trait_eligible(manager.opponent_traits[0], Catalog.opponent_capabilities()):
			failures.append("opponent received an ineligible trait")
			break
	if opponent_hooks != 0:
		failures.append("Power Hooks selected for opponent %d times" % opponent_hooks)
	if opponent_sharp != 0:
		failures.append("Sharp Straight selected for opponent %d times" % opponent_sharp)
	if player_hooks == 0:
		failures.append("Power Hooks never selected for player")
	if player_sharp == 0:
		failures.append("Sharp Straight never selected for player")
	if shared == 0:
		failures.append("same trait was never shared")
	if seen_player.size() != 12 or seen_opponent.size() != 10:
		failures.append("stress coverage player %d opponent %d" % [seen_player.size(), seen_opponent.size()])
	manager.free()


func _check_normal_flow(failures: Array[String]) -> void:
	var built: Dictionary = _match(ModeType.Mode.NORMAL)
	var rounds: RoundType = built["rounds"]
	var manager: ManagerType = built["traits"]
	rounds.start_match()
	if manager.player_traits.size() != 0 or manager.opponent_traits.size() != 0:
		failures.append("NORMAL started with traits")
	if rounds.round_state != RoundType.RoundState.FIGHTING:
		failures.append("NORMAL should enter fighting without a trait card")
	if built["holder"].get_node_or_null("TraitRoundCard") != null:
		failures.append("NORMAL showed a trait card")
	rounds._begin_round_entry(2)
	if manager.player_traits.size() != 0 or manager.roll_count != 0:
		failures.append("NORMAL round change rolled traits")
	rounds.current_round = 2
	rounds.player_round_wins = 1
	rounds._on_round_voided()
	if manager.player_traits.size() != 0 or manager.opponent_traits.size() != 0:
		failures.append("NORMAL rematch rolled traits")
	if rounds.player_round_wins != 1 or rounds.current_round != 2:
		failures.append("NORMAL rematch changed score or round")
	built["holder"].free()


func _check_trait_flow(failures: Array[String]) -> void:
	var built: Dictionary = _match(ModeType.Mode.TRAIT)
	var rounds: RoundType = built["rounds"]
	var manager: ManagerType = built["traits"]
	manager.print_pools = false
	rounds.start_match()
	if manager.player_traits.size() != 1 or manager.opponent_traits.size() != 1:
		failures.append("TRAIT should draw one trait each")
	var card = built["holder"].get_node_or_null("TraitRoundCard")
	if card == null or not card.visible:
		failures.append("TRAIT should show the trait card")
	else:
		var catalog = preload("res://scripts/trait_catalog.gd")
		if card._opponent_name.position.x >= card._player_name.position.x:
			failures.append("opponent trait card is not on the left")
		if card._opponent_name.text != catalog.reveal_name(manager.opponent_traits[0]):
			failures.append("left card does not show the opponent trait")
		if card._player_name.text != catalog.reveal_name(manager.player_traits[0]):
			failures.append("right card does not show the player trait")
	var first_player: int = manager.player_traits[0].id
	await process_frame
	if rounds.round_state != RoundType.RoundState.FIGHTING:
		failures.append("TRAIT headless confirm should start the round")
	if card.visible:
		failures.append("trait card stayed visible after the round started")
	var before: int = manager.roll_count
	rounds.current_round = 2
	rounds.player_round_wins = 1
	rounds._on_round_voided()
	if manager.roll_count <= before:
		failures.append("TRAIT rematch did not reroll")
	if manager.player_traits.size() != 1 or manager.opponent_traits.size() != 1:
		failures.append("TRAIT rematch lost the one-trait draw")
	if rounds.player_round_wins != 1:
		failures.append("TRAIT rematch changed the score")
	if first_player < 0:
		failures.append("trait id")
	built["holder"].free()


func _match(mode_value: int) -> Dictionary:
	var holder := Node.new()
	var mode := ModeType.new()
	mode.name = "GameMode"
	mode.mode = mode_value
	var knockdown := KDType.new()
	knockdown.name = "KnockdownManager"
	knockdown.print_events = false
	var traits := ManagerType.new()
	traits.name = "TraitManager"
	traits.print_pools = false
	var rounds := RoundType.new()
	rounds.name = "RoundManager"
	rounds.auto_start = false
	rounds.print_events = false
	rounds.knockdown_manager = knockdown
	holder.add_child(mode)
	holder.add_child(knockdown)
	holder.add_child(traits)
	holder.add_child(rounds)
	root.add_child(holder)
	return {"holder": holder, "rounds": rounds, "traits": traits}


func _pool_has(pool: Array, id: int) -> bool:
	for entry in pool:
		if entry.id == id:
			return true
	return false


func _trait(id: int) -> Resource:
	for entry in Catalog.all_traits():
		if entry.id == id:
			return entry
	return null
