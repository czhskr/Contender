extends SceneTree

## Gray damage chunk trails only losses, then catches the main bar.
## godot --headless --path . -s res://tests/combat/damage_chunk_smoke_test.gd

const HudType = preload("res://scripts/combat_hud.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var hud: HudType = HudType.new()
	root.add_child(hud)
	hud._build()
	_drop(hud, true, 300.0, 250.0, true)
	if hud.player_kd_value.text != "250 / 300":
		failures.append("kd number should be actual immediately")
	if hud.player_kd_chunk.value < hud.player_kd_bar.value - 0.01:
		failures.append("kd chunk started under the main bar")
	if hud.player_kd_chunk.value < 299.0:
		failures.append("kd chunk did not keep the pre-damage level")
	_pump(hud, 0.10)
	if hud.player_kd_chunk.value < hud.player_kd_bar.value - 0.01:
		failures.append("kd chunk fell through the main bar during hold")
	if hud.player_kd_chunk.value < 290.0:
		failures.append("kd chunk moved before the hold ended")
	_pump(hud, 0.55)
	if absf(hud.player_kd_bar.value - 250.0) > 1.0 or absf(hud.player_kd_chunk.value - 250.0) > 1.0:
		failures.append("kd bar and chunk did not meet at 250")
	_drop(hud, false, 100.0, 80.0, false)
	if hud.opponent_stamina_chunk.value < 99.0:
		failures.append("stamina chunk missing")
	_pump(hud, 0.70)
	if absf(hud.opponent_stamina_bar.value - 80.0) > 1.0 or absf(hud.opponent_stamina_chunk.value - 80.0) > 1.0:
		failures.append("stamina chunk did not catch up")
	hud.apply_kd(true, 300.0, 300.0, true)
	hud.apply_kd(true, 280.0, 300.0)
	hud.apply_kd(true, 250.0, 300.0)
	if absf(hud.player_kd_chunk.value - 300.0) > 1.0:
		failures.append("rapid kd should keep one high chunk, got %.1f" % hud.player_kd_chunk.value)
	if hud.player_kd_value.text != "250 / 300":
		failures.append("rapid kd number")
	hud.apply_stamina(true, 100.0, 100.0, true)
	hud.apply_stamina(true, 96.0, 100.0)
	hud.apply_stamina(true, 91.0, 100.0)
	hud.apply_stamina(true, 84.0, 100.0)
	if hud.player_stamina_chunk.value < 99.0:
		failures.append("rapid stamina chunk was not merged")
	hud.apply_stamina(true, 70.0, 100.0, true)
	hud.apply_stamina(true, 60.0, 100.0)
	_pump(hud, 0.05)
	var held: float = hud.player_stamina_chunk.value
	hud.apply_stamina(true, 65.0, 100.0)
	if hud.player_stamina_chunk.value > held + 0.01:
		failures.append("regen created a new damage chunk")
	_pump(hud, 0.20)
	if hud.player_stamina_chunk.value + 0.05 < hud.player_stamina_bar.value:
		failures.append("chunk fell below the regenerating stamina bar")
	hud.apply_kd(true, 20.0, 300.0, true)
	hud.apply_kd(true, 0.0, 300.0)
	if hud.player_kd_value.text != "0 / 300":
		failures.append("knockdown number")
	_pump(hud, 0.20)
	hud.apply_kd(true, 150.0, 300.0)
	var before_recover: float = hud.player_kd_chunk.value
	_pump(hud, 0.05)
	if hud.player_kd_chunk.value > before_recover + 1.0 and hud.player_kd_bar.value < hud.player_kd_chunk.value - 5.0:
		failures.append("recovery grew a damage chunk ahead of the bar")
	hud.apply_kd(true, 42.0, 300.0, true)
	hud.apply_kd(true, 40.0, 300.0)
	hud.apply_kd(true, 300.0, 300.0, true)
	if absf(hud.player_kd_bar.value - 300.0) > 0.01 or absf(hud.player_kd_chunk.value - 300.0) > 0.01:
		failures.append("round reset left a chunk")
	if failures.is_empty():
		print("SMOKE PASS: damage chunk")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _drop(hud: HudType, kd: bool, start: float, after: float, player_side: bool) -> void:
	var maximum := 300.0 if kd else 100.0
	if kd:
		hud.apply_kd(player_side, start, maximum, true)
		hud.apply_kd(player_side, after, maximum)
	else:
		hud.apply_stamina(player_side, start, maximum, true)
		hud.apply_stamina(player_side, after, maximum)


func _pump(hud: HudType, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(1.0 / 60.0, left)
		hud._process(step)
		left -= step
