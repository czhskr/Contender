extends SceneTree

## Smooth drain follows the latest gameplay value. Numbers stay immediate.
## godot --headless --path . -s res://tests/combat/smooth_drain_smoke_test.gd

const HudType = preload("res://scripts/combat_hud.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var hud: HudType = HudType.new()
	root.add_child(hud)
	hud._build()
	hud.apply_stamina(true, 100.0, 100.0, true)
	hud.apply_stamina(false, 100.0, 100.0, true)
	hud.apply_kd(true, 300.0, 300.0, true)
	hud.apply_kd(false, 300.0, 300.0, true)
	hud.apply_stamina(true, 70.0, 100.0)
	hud.apply_kd(true, 250.0, 300.0)
	if hud.player_stamina_value.text != "70 / 100" or hud.player_kd_value.text != "250 / 300":
		failures.append("numbers must show the actual value immediately")
	if hud.player_stamina_bar.value <= 70.0 or hud.player_kd_bar.value <= 250.0:
		failures.append("bars should still be draining from the previous value")
	_pump(hud, 0.32)
	if absf(hud.player_stamina_bar.value - 70.0) > 1.0:
		failures.append("player stamina did not settle, bar %.2f" % hud.player_stamina_bar.value)
	if absf(hud.player_kd_bar.value - 250.0) > 1.0:
		failures.append("player kd did not settle, bar %.2f" % hud.player_kd_bar.value)
	hud.apply_stamina(false, 80.0, 100.0)
	hud.apply_kd(false, 200.0, 300.0)
	_pump(hud, 0.32)
	if absf(hud.opponent_stamina_bar.value - 80.0) > 1.0 or absf(hud.opponent_kd_bar.value - 200.0) > 1.0:
		failures.append("opponent bars did not settle")
	hud.apply_kd(true, 290.0, 300.0, true)
	hud.apply_kd(true, 275.0, 300.0)
	hud.apply_kd(true, 260.0, 300.0)
	if hud.player_kd_value.text != "260 / 300":
		failures.append("rapid kd text should be the latest actual")
	var previous: float = hud.player_kd_bar.value
	for _step in 12:
		hud._process(1.0 / 60.0)
		if hud.player_kd_bar.value < 260.0 - 0.01:
			failures.append("kd bar overshot the target")
			break
		if hud.player_kd_bar.value > previous + 0.01:
			failures.append("kd bar moved away from the newer lower target")
			break
		previous = hud.player_kd_bar.value
	hud.apply_stamina(true, 40.0, 100.0, true)
	hud.apply_stamina(true, 52.0, 100.0)
	hud.apply_stamina(true, 65.0, 100.0)
	if hud.player_stamina_bar.value > 65.0 + 0.01:
		failures.append("stamina bar overshot")
	_pump(hud, 0.32)
	if absf(hud.player_stamina_bar.value - 65.0) > 1.0:
		failures.append("stamina regen did not settle")
	hud.apply_kd(true, 20.0, 300.0, true)
	hud.apply_kd(true, 0.0, 300.0)
	if hud.player_kd_value.text != "0 / 300":
		failures.append("knockdown number must be 0 immediately")
	_pump(hud, 0.32)
	if hud.player_kd_bar.value > 0.5:
		failures.append("knockdown bar did not drain to 0")
	hud.apply_kd(true, 42.0, 300.0, true)
	hud.apply_kd(true, 300.0, 300.0, true)
	if absf(hud.player_kd_bar.value - 300.0) > 0.01:
		failures.append("round reset should snap the bar to 300")
	if failures.is_empty():
		print("SMOKE PASS: smooth drain")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _pump(hud: HudType, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(1.0 / 60.0, left)
		hud._process(step)
		left -= step
