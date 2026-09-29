extends SceneTree

## Screen shake is presentation only. Hit resolution and damage stay on the resolvers.
## Run: godot --headless --path . -s res://screen_shake_smoke_test.gd

const VisualType = preload("res://scripts/combat_visual_root.gd")
const SettingsType = preload("res://scripts/match_settings.gd")
const DefenseType = preload("res://scripts/player_defense_resolver.gd")
const OffenseType = preload("res://scripts/player_offense_resolver.gd")
const TraitMathType = preload("res://scripts/trait_math.gd")
const TraitType = preload("res://scripts/fighter_trait.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_balance_unchanged(failures)
	await _check_shake(failures)
	SettingsType.screen_shake = SettingsType.ScreenShake.NORMAL

	if failures.is_empty():
		print("SMOKE PASS: screen shake")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_balance_unchanged(failures: Array[String]) -> void:
	var paths: Array[String] = [
		"res://data/attacks/left_straight.tres",
		"res://data/attacks/right_straight.tres",
		"res://data/attacks/left_hook.tres",
		"res://data/attacks/right_hook.tres",
	]
	var expected_block: Array[float] = [8.0, 10.0, 14.0, 16.0]
	var defense := DefenseType.new()
	var offense := OffenseType.new()
	if not is_equal_approx(defense.guard_knockdown_damage_multiplier, 0.25):
		failures.append("player block KD multiplier changed")
	if not is_equal_approx(offense.guard_knockdown_damage_multiplier, 0.25):
		failures.append("opponent block KD multiplier changed")
	if not is_equal_approx(defense.BLOCK_STAMINA_COST_SCALE, 2.0):
		failures.append("player block stamina scale changed")
	if not is_equal_approx(offense.BLOCK_STAMINA_COST_SCALE, 2.0):
		failures.append("opponent block stamina scale changed")
	for index in paths.size():
		var attack = load(paths[index])
		var block_cost: float = float(attack.stamina_cost) * defense.BLOCK_STAMINA_COST_SCALE
		if not is_equal_approx(block_cost, expected_block[index]):
			failures.append("%s block stamina is %.1f" % [paths[index], block_cost])
	var iron_trait := TraitType.new()
	iron_trait.iron_guard = true
	var plain_trait := TraitType.new()
	var iron: float = TraitMathType.taken_kd(10.0, [iron_trait], 100.0, true, 1.0, false)
	if not is_equal_approx(iron, 0.0):
		failures.append("Iron Guard block KD is not 0")
	var guarded: float = TraitMathType.taken_kd(8.0, [plain_trait], 100.0, true, 1.0, false)
	if not is_equal_approx(guarded, 2.0):
		failures.append("block KD x0.25 changed")
	defense.free()
	offense.free()


func _check_shake(failures: Array[String]) -> void:
	var visual := VisualType.new()
	root.add_child(visual)
	await process_frame
	visual.base_position = Vector2(4.0, 8.0)
	visual.position = visual.base_position

	if not is_equal_approx(visual.player_hit_shake_strength, 12.0):
		failures.append("player HIT shake is not 12")
	if not is_equal_approx(visual.opponent_hit_shake_strength, 5.0):
		failures.append("opponent HIT shake is not 5")
	if not is_equal_approx(visual.player_hit_shake_duration, 0.15):
		failures.append("player shake duration changed")
	if not is_equal_approx(visual.opponent_hit_shake_duration, 0.10):
		failures.append("opponent shake duration changed")
	if not is_equal_approx(VisualType.BLOCK_SHAKE_SCALE, 0.65):
		failures.append("BLOCK scale is not 0.65 of HIT")
	var player_block: float = visual.player_hit_shake_strength * VisualType.BLOCK_SHAKE_SCALE
	var opponent_block: float = visual.opponent_hit_shake_strength * VisualType.BLOCK_SHAKE_SCALE
	if player_block >= visual.player_hit_shake_strength or opponent_block >= visual.opponent_hit_shake_strength:
		failures.append("BLOCK shake is not weaker than HIT")
	if not is_equal_approx(SettingsType.screen_shake_multiplier(), 1.0):
		failures.append("NORMAL multiplier is not 1")

	SettingsType.screen_shake = SettingsType.ScreenShake.OFF
	visual._on_opponent_attack_resolved(DefenseType.DefenseResult.HIT, 8.0, 8.0, false)
	visual._on_opponent_attack_resolved(DefenseType.DefenseResult.BLOCK, 2.0, 2.0, false)
	visual._on_player_attack_hit(0, 2.0, 2.0, false, OffenseType.ResolveResult.BLOCK)
	if visual._shake_tween != null or visual.shake_offset != Vector2.ZERO:
		failures.append("OFF still shook on HIT or BLOCK")
	if visual.position != visual.base_position:
		failures.append("OFF moved the visual root")

	SettingsType.screen_shake = SettingsType.ScreenShake.NORMAL
	var before_evade := visual._shake_token
	visual._on_opponent_attack_resolved(DefenseType.DefenseResult.EVADE, 0.0, 0.0, false)
	visual._on_player_attack_hit(0, 0.0, 0.0, false, OffenseType.ResolveResult.EVADE)
	if visual._shake_tween != null or visual._shake_token != before_evade:
		failures.append("EVADE started a screen shake")

	var block_token := visual._shake_token
	visual._on_opponent_attack_resolved(DefenseType.DefenseResult.BLOCK, 2.0, 2.0, false)
	if visual._shake_tween == null or visual._shake_token != block_token + 1:
		failures.append("player BLOCK did not shake once")
	visual._clear_shake()
	if visual.shake_offset != Vector2.ZERO or visual.position != visual.base_position:
		failures.append("player BLOCK shake drifted")

	var opponent_block_token := visual._shake_token
	visual._on_player_attack_hit(0, 2.0, 2.0, false, OffenseType.ResolveResult.BLOCK)
	if visual._shake_tween == null or visual._shake_token != opponent_block_token + 1:
		failures.append("opponent BLOCK did not shake once")
	visual._clear_shake()

	visual._on_opponent_attack_resolved(DefenseType.DefenseResult.HIT, 8.0, 8.0, false)
	if visual._shake_tween == null:
		failures.append("player HIT did not shake")
	await create_timer(0.22).timeout
	if visual.shake_offset != Vector2.ZERO or visual.position != visual.base_position:
		failures.append("player HIT shake did not return to base")

	visual._on_player_attack_hit(0, 8.0, 8.0, false, OffenseType.ResolveResult.HIT)
	await create_timer(0.18).timeout
	if visual.shake_offset != Vector2.ZERO or visual.position != visual.base_position:
		failures.append("opponent HIT shake did not return to base")

	SettingsType.screen_shake = SettingsType.ScreenShake.STRONG
	var strong_player: float = visual.player_hit_shake_strength * SettingsType.screen_shake_multiplier()
	var strong_block: float = player_block * SettingsType.screen_shake_multiplier()
	if not is_equal_approx(SettingsType.screen_shake_multiplier(), 1.5):
		failures.append("STRONG multiplier is not 1.5")
	if not is_equal_approx(strong_player, 18.0):
		failures.append("STRONG player HIT is not 18")
	if strong_player <= visual.player_hit_shake_strength:
		failures.append("STRONG is not above NORMAL")
	if strong_block >= strong_player:
		failures.append("STRONG BLOCK is not below STRONG HIT")
	if not is_equal_approx(visual.parallax_crowd_x, 80.0):
		failures.append("shake edit changed crowd parallax")
	if not is_equal_approx(visual.parallax_ring_x, 160.0):
		failures.append("shake edit changed ring parallax")
	if not is_equal_approx(visual.parallax_opponent_x, 280.0):
		failures.append("shake edit changed opponent parallax")
	visual.free()
