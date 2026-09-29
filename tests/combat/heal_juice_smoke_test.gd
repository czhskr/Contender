extends SceneTree

## Stamina regen highlight and KD recovery glow.
## godot --headless --path . -s res://tests/combat/heal_juice_smoke_test.gd

const HudType = preload("res://scripts/combat_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var hud: HudType = HudType.new()
	root.add_child(hud)
	hud._build()
	for is_player in [true, false]:
		var side := "player" if is_player else "opponent"
		_check_stamina(failures, hud, is_player, side)
		_check_kd(failures, hud, is_player, side)
	if failures.is_empty():
		print("SMOKE PASS: heal juice")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_stamina(failures: Array[String], hud: HudType, is_player: bool, side: String) -> void:
	var slot := 0 if is_player else 1
	hud.apply_stamina(is_player, 100.0, 100.0, true)
	hud.apply_stamina(is_player, 80.0, 100.0)
	var hold_before: float = hud._chunk_hold[slot]
	if hold_before <= 0.0:
		failures.append("%s stamina damage did not start a chunk" % side)
	hud._process(0.05)
	var hold_mid: float = hud._chunk_hold[slot]
	hud.apply_stamina(is_player, 81.0, 100.0)
	hud._process(0.0)
	if not hud._regen_on[slot]:
		failures.append("%s regen highlight did not turn on" % side)
	if hud._regen_starts[slot] != 1:
		failures.append("%s regen started %d times" % [side, hud._regen_starts[slot]])
	var highlight := _regen_alpha(hud, is_player)
	if highlight < HudType.REGEN_HIGHLIGHT - 0.001:
		failures.append("%s regen highlight is dim" % side)
	if hud._chunk_hold[slot] > hold_mid + 0.001:
		failures.append("%s regen refreshed the damage chunk" % side)
	if hud._meter_display[slot] > hud._meter_chunk[slot] + 0.001:
		failures.append("%s regen left the chunk below the main bar" % side)
	for value in [82.0, 83.0, 84.0]:
		hud.apply_stamina(is_player, value, 100.0)
		hud._process(0.016)
	if hud._regen_starts[slot] != 1:
		failures.append("%s regen restarted on later frames" % side)
	if absf(_regen_alpha(hud, is_player) - HudType.REGEN_HIGHLIGHT) > 0.001:
		failures.append("%s sustained regen left the steady highlight" % side)
	hud.apply_stamina(is_player, 100.0, 100.0)
	if hud._regen_on[slot]:
		failures.append("%s stamina stayed highlighted at max" % side)
	_pump(hud, 0.25)
	if _regen_alpha(hud, is_player) > 0.001:
		failures.append("%s max highlight did not fade out" % side)
	hud.apply_stamina(is_player, 70.0, 100.0, true)
	hud.apply_stamina(is_player, 71.0, 100.0)
	hud._process(0.0)
	if not hud._regen_on[slot]:
		failures.append("%s second regen did not turn on" % side)
	hud.apply_stamina(is_player, 100.0, 100.0, true)
	if hud._regen_on[slot] or _regen_alpha(hud, is_player) > 0.001:
		failures.append("%s round reset started a stamina heal" % side)
	if not _fill_is(hud.player_stamina_bar if is_player else hud.opponent_stamina_bar, HudType.STAMINA_COLOR):
		failures.append("%s stamina base color changed" % side)


func _check_kd(failures: Array[String], hud: HudType, is_player: bool, side: String) -> void:
	var slot := 0 if is_player else 1
	hud.apply_kd(is_player, 20.0, 300.0, true)
	hud.apply_kd(is_player, 0.0, 300.0)
	hud._process(0.04)
	var flash_at: float = hud._flash_time[slot]
	var shake_at: float = hud._shake_time[slot]
	var punch_at: float = hud._punch_time[slot]
	if flash_at < 0.0:
		failures.append("%s KD damage did not flash" % side)
	var body := hud.player_kd_impact if is_player else hud.opponent_kd_impact
	hud.apply_kd(is_player, 150.0, 300.0)
	if absf(hud._flash_time[slot] - flash_at) > 0.0001:
		failures.append("%s recovery reset the damage flash" % side)
	if absf(hud._shake_time[slot] - shake_at) > 0.0001 or absf(hud._punch_time[slot] - punch_at) > 0.0001:
		failures.append("%s recovery retriggered shake or punch" % side)
	hud._process(0.0)
	var glow := _heal_alpha(hud, is_player)
	if glow < HudType.HEAL_PEAK - 0.01:
		failures.append("%s recovery glow did not start" % side)
	if glow >= HudType.FLASH_PEAK - 0.01:
		failures.append("%s recovery glow is as strong as damage flash" % side)
	if body.scale.x > 1.0 and absf(hud._punch_time[slot] - punch_at) > 0.0001:
		failures.append("%s recovery punched the KD bar" % side)
	_pump(hud, 0.4)
	if _heal_alpha(hud, is_player) > 0.001:
		failures.append("%s recovery glow did not end" % side)
	if body.scale != Vector2.ONE or body.position != Vector2.ZERO:
		failures.append("%s KD did not settle after recovery" % side)
	if absf(hud._meter_target[slot + 2] - hud._meter_display[slot + 2]) > 1.0:
		failures.append("%s recovery did not settle the main bar" % side)
	if hud._meter_display[slot + 2] > hud._meter_chunk[slot + 2] + 0.05:
		failures.append("%s recovery left the chunk below the main bar" % side)
	hud.apply_kd(is_player, 0.0, 300.0, true)
	hud.apply_kd(is_player, 0.0, 300.0)
	hud._process(0.0)
	if hud._kd_heal_time[slot] >= 0.0 or _heal_alpha(hud, is_player) > 0.001:
		failures.append("%s failed recovery showed a glow" % side)
	hud.apply_kd(is_player, 150.0, 300.0)
	hud._process(0.0)
	hud.apply_kd(is_player, 300.0, 300.0, true)
	if hud._kd_heal_time[slot] >= 0.0 or _heal_alpha(hud, is_player) > 0.001:
		failures.append("%s round reset kept a recovery glow" % side)
	if hud._flash_time[slot] >= 0.0 or body.scale != Vector2.ONE:
		failures.append("%s round reset kept damage impact" % side)
	if not _fill_is(hud.player_kd_bar if is_player else hud.opponent_kd_bar, HudType.KD_COLOR):
		failures.append("%s KD base color changed" % side)


func _regen_alpha(hud: HudType, is_player: bool) -> float:
	var rect := hud.player_stamina_heal if is_player else hud.opponent_stamina_heal
	return rect.color.a


func _heal_alpha(hud: HudType, is_player: bool) -> float:
	var rect := hud.player_kd_heal if is_player else hud.opponent_kd_heal
	return rect.color.a


func _pump(hud: HudType, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		hud._process(0.05)
		elapsed += 0.05


func _fill_is(bar: ProgressBar, expected: Color) -> bool:
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if fill == null:
		return false
	return fill.bg_color.is_equal_approx(expected)
