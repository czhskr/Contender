extends SceneTree

## New-round visuals must drop a previous knockdown pose, and KD max is 200.
## Run: godot --headless --path . -s res://round_visual_reset_smoke_test.gd

const OpponentVisualType = preload("res://scripts/opponent_visual.gd")
const PlayerVisualType = preload("res://scripts/player_visual.gd")
const KnockdownType = preload("res://scripts/knockdown_manager.gd")
const MeterType = preload("res://scripts/knockdown_meter.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	await _check_visual_reset(failures)
	_check_kd_max(failures)
	if failures.is_empty():
		print("SMOKE PASS: round visual reset / KD 200")
		quit(0)
		return
	print("SMOKE FAIL:")
	for failure in failures:
		print(" - %s" % failure)
	quit(1)


func _check_visual_reset(failures: Array[String]) -> void:
	var visual := OpponentVisualType.new()
	var kd := KnockdownType.new()
	visual.knockdown_manager = kd
	root.add_child(visual)
	await process_frame
	var poses := ["HIT", "LEFT_STRAIGHT", "HIGH_GUARD", "SLIP_LEFT"]
	for pose in poses:
		visual._show_pose(pose, visual.texture_hit if pose == "HIT" else visual.texture_left_straight)
		visual.reset_for_new_round()
		if not _is_nstance(visual):
			failures.append("%s pose survived a new round" % pose)
	visual._on_match_state_changed(KnockdownType.MatchState.OPPONENT_DOWN)
	visual.reset_for_new_round()
	if not _is_nstance(visual) or visual._knockdown_offset != Vector2.ZERO:
		failures.append("Knockdown pose survived round 1 to 2")
	kd.downed_side = KnockdownType.DownedSide.OPPONENT
	visual._on_match_state_changed(KnockdownType.MatchState.FINAL_KO)
	if not visual._locked_final_ko:
		failures.append("Final KO should lock the pose until the next round")
	visual.reset_for_new_round()
	if visual._locked_final_ko or not _is_nstance(visual) or visual._knockdown_offset != Vector2.ZERO:
		failures.append("Final KO pose survived round 2 to 3")
	visual._begin_attack_pose(0)
	visual.reset_for_new_round()
	await create_timer(0.25).timeout
	if not _is_nstance(visual):
		failures.append("A delayed attack-pose callback overwrote the new round")
	visual.queue_free()
	kd.free()


func _is_nstance(visual) -> bool:
	return (
		visual.current_visual_state == "IDLE"
		and visual._sprite != null
		and visual._sprite.texture != null
		and visual._sprite.texture.resource_path.ends_with("o.Nstance.png")
	)


func _check_kd_max(failures: Array[String]) -> void:
	var meter := MeterType.new()
	if not is_equal_approx(meter.max_meter, 300.0):
		failures.append("KD max should be 300")
	meter.set_meter(299.0)
	meter.apply_knockdown_damage(0.5)
	if meter.is_full():
		failures.append("299.5 must not knock down")
	meter.apply_knockdown_damage(0.5)
	if not meter.is_full():
		failures.append("300 must knock down")
	var kd := KnockdownType.new()
	kd.opponent_knockdown_meter = meter
	kd.downed_side = KnockdownType.DownedSide.OPPONENT
	if not is_equal_approx(kd._recovery_meter_value(), meter.max_meter * 0.5):
		failures.append("Recover KD must be half of the live maximum")
	if not is_equal_approx(kd._recovery_meter_value(), 150.0):
		failures.append("Recover KD at max 300 should be 150")
	meter.free()
	kd.free()
