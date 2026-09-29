extends SceneTree

const PlayerStaminaType = preload("res://scripts/player_stamina.gd")
const OpponentStaminaType = preload("res://scripts/opponent_stamina.gd")
const VisualType = preload("res://scripts/opponent_visual.gd")
const AttackType = preload("res://scripts/opponent_attack_state.gd")
const KDType = preload("res://scripts/knockdown_manager.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_check_regen(failures, PlayerStaminaType.new(), "Player")
	_check_regen(failures, OpponentStaminaType.new(), "Opponent")
	_check_player_down_visual(failures)
	if failures.is_empty():
		print("SMOKE PASS: stamina regen and knockdown stance")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_regen(failures: Array[String], stamina, fighter: String) -> void:
	if not is_equal_approx(stamina.regeneration_delay, 0.65):
		failures.append("%s regen delay should be 0.65" % fighter)
	var rate: float = stamina.regeneration_per_second
	stamina.current_stamina = 100.0
	stamina.max_stamina = 100.0
	stamina.regeneration_enabled = true
	stamina._time_since_regen_block = 0.0
	if stamina.has_method("spend_for_attack"):
		stamina.spend_for_attack(4.0)
	var spent: float = stamina.current_stamina
	stamina._process(0.64)
	if not is_equal_approx(stamina.current_stamina, spent):
		failures.append("%s regen started during the delay" % fighter)
	stamina._process(0.02)
	if stamina.current_stamina <= spent:
		failures.append("%s regen did not start after the delay" % fighter)
	print("[STAMINA_REGEN] fighter=%s delay=%.3f rate=%.1f" % [fighter, stamina.regeneration_delay, rate])
	stamina.spend_for_attack(4.0) if stamina.has_method("spend_for_attack") else null
	var after_second: float = stamina.current_stamina
	stamina._process(0.64)
	if not is_equal_approx(stamina.current_stamina, after_second):
		failures.append("%s second attack did not reset regen delay" % fighter)
	if not is_equal_approx(stamina.regeneration_per_second, rate):
		failures.append("%s regen rate changed" % fighter)


func _check_player_down_visual(failures: Array[String]) -> void:
	var visual := VisualType.new()
	var attack := AttackType.new()
	var knockdown := KDType.new()
	root.add_child(visual)
	visual._build_nodes()
	visual.opponent_attack_state = attack
	visual.knockdown_manager = knockdown
	visual._attack_pose_holding = true
	visual._priority = VisualType.Priority.ATTACK
	visual._on_match_state_changed(KDType.MatchState.PLAYER_DOWN)
	if visual._attack_pose_holding:
		failures.append("Player knockdown left the attack visual hold on")
	if visual.current_visual_state != "IDLE":
		failures.append("Player knockdown should return the opponent to stance")
	var token := visual._attack_pose_token
	visual._release_attack_pose_to_stance()
	if visual._attack_pose_token != token:
		failures.append("A stale attack callback changed the visual token")
	if visual.current_visual_state != "IDLE":
		failures.append("A stale attack callback restored a punch texture")
	knockdown.match_state = KDType.MatchState.PLAYER_DOWN
	visual._on_attack_state_changed(AttackType.AttackState.ACTIVE, null)
	if visual.current_visual_state != "IDLE":
		failures.append("Count allowed a new opponent attack texture")
	visual.queue_free()
