extends SceneTree

## KD bar shake, flash, and punch stay on KD damage only.
## godot --headless --path . -s res://kd_impact_smoke_test.gd

const HudType = preload("res://scripts/combat_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var hud: HudType = HudType.new()
	root.add_child(hud)
	hud._build()
	_arm(hud, 300.0, 300.0, 100.0, 100.0)
	_hit(failures, hud, true, 300.0, 290.0, "player")
	_arm(hud, 300.0, 300.0, 100.0, 100.0)
	_hit(failures, hud, false, 300.0, 290.0, "opponent")
	_check_stamina(failures, hud)
	_check_same_value(failures, hud)
	_check_recovery(failures, hud)
	_check_reset(failures, hud)
	_check_rapid(failures, hud)
	_check_zero(failures, hud)
	if failures.is_empty():
		print("SMOKE PASS: kd impact")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _arm(hud: HudType, player_kd: float, opponent_kd: float, player_stamina: float, opponent_stamina: float) -> void:
	hud.apply_kd(true, player_kd, 300.0, true)
	hud.apply_kd(false, opponent_kd, 300.0, true)
	hud.apply_stamina(true, player_stamina, 100.0, true)
	hud.apply_stamina(false, opponent_stamina, 100.0, true)


func _hit(failures: Array[String], hud: HudType, is_player: bool, before: float, after: float, label: String) -> void:
	hud.apply_kd(is_player, before, 300.0, true)
	hud.apply_kd(is_player, after, 300.0)
	hud._process(0.01)
	var body := hud.player_kd_impact if is_player else hud.opponent_kd_impact
	var flash := hud.player_kd_flash if is_player else hud.opponent_kd_flash
	var other := hud.opponent_kd_impact if is_player else hud.player_kd_impact
	if absf(body.position.x) < 1.0:
		failures.append("%s shake did not move" % label)
	if absf(body.position.x) > HudType.SHAKE_AMPLITUDE + 0.01:
		failures.append("%s shake exceeded amplitude" % label)
	if flash.color.a < 0.2:
		failures.append("%s flash did not peak" % label)
	if body.scale.x <= 1.0 or body.scale.x > HudType.PUNCH_PEAK + 0.001:
		failures.append("%s punch scale %s" % [label, body.scale])
	if other.position != Vector2.ZERO or other.scale != Vector2.ONE:
		failures.append("%s impact leaked to the other KD bar" % label)
	if hud.player_stamina_bar.scale != Vector2.ONE or hud.opponent_stamina_bar.scale != Vector2.ONE:
		failures.append("%s impact scaled stamina" % label)
	_settle(hud)
	if body.position != Vector2.ZERO:
		failures.append("%s shake did not return to base" % label)
	if body.scale != Vector2.ONE:
		failures.append("%s punch did not return to 1" % label)
	if flash.color.a > 0.001:
		failures.append("%s flash did not turn off" % label)
	if not _fill_is(hud.player_kd_bar, HudType.KD_COLOR) or not _fill_is(hud.opponent_kd_bar, HudType.KD_COLOR):
		failures.append("%s flash changed the base KD color" % label)


func _check_stamina(failures: Array[String], hud: HudType) -> void:
	_arm(hud, 300.0, 300.0, 100.0, 100.0)
	hud.apply_stamina(true, 90.0, 100.0)
	hud.apply_stamina(false, 90.0, 100.0)
	hud._process(0.01)
	if hud._shake_time[0] >= 0.0 or hud._shake_time[1] >= 0.0:
		failures.append("stamina damage started a KD shake")
	if hud._flash_time[0] >= 0.0 or hud._punch_time[0] >= 0.0:
		failures.append("stamina damage started a KD flash or punch")
	if hud.player_kd_flash.color.a > 0.001 or hud.opponent_kd_flash.color.a > 0.001:
		failures.append("stamina damage flashed a KD bar")


func _check_same_value(failures: Array[String], hud: HudType) -> void:
	_arm(hud, 300.0, 300.0, 100.0, 100.0)
	hud.apply_kd(false, 300.0, 300.0)
	hud._process(0.01)
	if hud._shake_time[1] >= 0.0 or hud._flash_time[1] >= 0.0 or hud._punch_time[1] >= 0.0:
		failures.append("equal KD value started impact")


func _check_recovery(failures: Array[String], hud: HudType) -> void:
	_arm(hud, 0.0, 0.0, 100.0, 100.0)
	hud.apply_kd(true, 150.0, 300.0)
	hud.apply_kd(false, 150.0, 300.0)
	hud._process(0.01)
	if hud._shake_time[0] >= 0.0 or hud._flash_time[0] >= 0.0 or hud._punch_time[0] >= 0.0:
		failures.append("recovery started damage impact")
	if hud.player_kd_impact.scale != Vector2.ONE:
		failures.append("recovery punched the KD bar")


func _check_reset(failures: Array[String], hud: HudType) -> void:
	_arm(hud, 300.0, 300.0, 100.0, 100.0)
	hud.apply_kd(true, 290.0, 300.0)
	hud._process(0.01)
	if hud.player_kd_flash.color.a <= 0.0:
		failures.append("reset setup did not flash")
	hud.apply_kd(true, 300.0, 300.0, true)
	if hud.player_kd_impact.position != Vector2.ZERO:
		failures.append("reset left a shake offset")
	if hud.player_kd_impact.scale != Vector2.ONE:
		failures.append("reset left a punch scale")
	if hud.player_kd_flash.color.a > 0.001:
		failures.append("reset left the flash on")
	if hud._shake_time[0] >= 0.0 or hud._flash_time[0] >= 0.0 or hud._punch_time[0] >= 0.0:
		failures.append("reset left impact timers running")


func _check_rapid(failures: Array[String], hud: HudType) -> void:
	_arm(hud, 300.0, 300.0, 100.0, 100.0)
	var values := [290.0, 275.0, 260.0]
	var peak_flash := 0.0
	for value in values:
		hud.apply_kd(false, value, 300.0)
		hud._process(0.0)
		peak_flash = maxf(peak_flash, hud.opponent_kd_flash.color.a)
		if hud.opponent_kd_impact.scale.x > HudType.PUNCH_PEAK + 0.001:
			failures.append("rapid punch accumulated to %s" % hud.opponent_kd_impact.scale.x)
		if absf(hud.opponent_kd_impact.position.x) > HudType.SHAKE_AMPLITUDE + 0.01:
			failures.append("rapid shake drifted past amplitude")
		hud._process(0.08)
	if peak_flash < HudType.FLASH_PEAK - 0.01:
		failures.append("rapid flash did not refresh to peak")
	if hud.opponent_kd_flash.color.a > HudType.FLASH_PEAK + 0.001:
		failures.append("rapid flash stacked above peak")
	_settle(hud)
	if hud.opponent_kd_impact.position != Vector2.ZERO:
		failures.append("rapid shake ended away from base")
	if hud.opponent_kd_impact.scale != Vector2.ONE:
		failures.append("rapid punch ended away from 1")
	if hud.opponent_kd_flash.color.a > 0.001:
		failures.append("rapid flash stayed on")
	if hud._meter_target[3] > hud._meter_display[3] or hud._meter_display[3] > hud._meter_chunk[3] + 0.001:
		failures.append("rapid impact broke actual <= main <= chunk")


func _check_zero(failures: Array[String], hud: HudType) -> void:
	_arm(hud, 20.0, 300.0, 100.0, 100.0)
	hud.apply_kd(true, 0.0, 300.0)
	hud._process(0.0)
	if hud.player_kd_flash.color.a < HudType.FLASH_PEAK - 0.01:
		failures.append("KD 0 did not flash")
	if hud.player_kd_impact.scale.x < HudType.PUNCH_PEAK - 0.01:
		failures.append("KD 0 did not punch")


func _settle(hud: HudType) -> void:
	var elapsed := 0.0
	while elapsed < 0.4:
		hud._process(0.05)
		elapsed += 0.05


func _fill_is(bar: ProgressBar, expected: Color) -> bool:
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if fill == null:
		return false
	return fill.bg_color.is_equal_approx(expected)
