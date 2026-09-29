extends SceneTree

## Combat HUD layout and bindings.
## godot --headless --path . -s res://tests/ui/combat_hud_smoke_test.gd

const HudType = preload("res://scripts/combat_hud.gd")
const ModeType = preload("res://scripts/game_mode.gd")
const ManagerType = preload("res://scripts/trait_manager.gd")
const Catalog = preload("res://scripts/trait_catalog.gd")
const TraitType = preload("res://scripts/fighter_trait.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_layout(failures)
	_check_scene(failures)
	if failures.is_empty():
		print("SMOKE PASS: combat hud")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_layout(failures: Array[String]) -> void:
	var hud: HudType = HudType.new()
	root.add_child(hud)
	hud._build()
	hud.apply_stamina(true, 73.4, 100.0)
	hud.apply_stamina(false, 91.2, 100.0)
	hud.apply_kd(true, 152.6, 300.0)
	hud.apply_kd(false, 40.2, 300.0)
	if _has_meter_caption(hud._opponent_panel) or _has_meter_caption(hud._player_panel):
		failures.append("KD or STAMINA captions are still in the fighter HUD")
	var kd_block := hud._player_panel.get_child(0) as Control
	var kd_height: float = kd_block.get_combined_minimum_size().y
	if absf(kd_height - HudType.KD_BAR_HEIGHT) > 1.0:
		failures.append("kd block is taller than the bar (%s)" % kd_height)
	if absf(hud.player_stamina_bar.get_parent().get_combined_minimum_size().y - HudType.STAMINA_BAR_HEIGHT) > 1.0:
		failures.append("stamina block is taller than the bar")
	if hud.player_stamina_value.visible or hud.opponent_stamina_value.visible:
		failures.append("stamina numbers are visible")
	if hud.player_kd_value.visible or hud.opponent_kd_value.visible:
		failures.append("kd numbers are visible")
	if hud.player_stamina_value.text != "73 / 100":
		failures.append("player stamina text %s" % hud.player_stamina_value.text)
	if hud.opponent_stamina_value.text != "91 / 100":
		failures.append("opponent stamina text")
	if hud.player_kd_value.text != "153 / 300":
		failures.append("player kd text %s" % hud.player_kd_value.text)
	if hud.opponent_kd_value.text != "40 / 300":
		failures.append("opponent kd text")
	if hud.player_kd_bar.custom_minimum_size.x != HudType.BAR_LENGTH:
		failures.append("player kd length")
	if hud.opponent_kd_bar.custom_minimum_size.x != hud.player_stamina_bar.custom_minimum_size.x:
		failures.append("bar lengths differ")
	if hud.player_kd_bar.custom_minimum_size.y <= hud.player_stamina_bar.custom_minimum_size.y:
		failures.append("kd is not thicker than stamina")
	if not _fill_is(hud.player_stamina_bar, HudType.STAMINA_COLOR):
		failures.append("player stamina is not green")
	if not _fill_is(hud.opponent_stamina_bar, HudType.STAMINA_COLOR):
		failures.append("opponent stamina is not green")
	if not _fill_is(hud.player_kd_bar, HudType.KD_COLOR):
		failures.append("player kd is not red")
	if not _fill_is(hud.opponent_kd_bar, HudType.KD_COLOR):
		failures.append("opponent kd is not red")
	_check_fill_direction(failures, hud)
	hud.apply_match(0, 0, 1, 60.0)
	if hud.match_label.text != "ROUND 1" or hud.timer_label.text != "01:00":
		failures.append("opening match text")
	if _filled_count(hud.opponent_win_pips) != 0 or _filled_count(hud.player_win_pips) != 0:
		failures.append("opening wins are not empty")
	var info := hud._match_cluster.get_node("MatchRow/MatchInfo")
	var separator := info.get_node("Separator") as Control
	if separator == null or separator.custom_minimum_size.x < 3.0:
		failures.append("round and timer are not separated")
	if hud._match_cluster.get_node("MatchRow/OpponentWins") != hud.opponent_win_pips[0].get_parent():
		failures.append("left indicators are not the opponent")
	hud.apply_match(0, 1, 2, 55.0)
	if _filled_count(hud.opponent_win_pips) != 1 or _filled_count(hud.player_win_pips) != 0:
		failures.append("opponent win did not fill the left side")
	hud.apply_match(1, 0, 2, 40.0)
	if _filled_count(hud.player_win_pips) != 1 or _filled_count(hud.opponent_win_pips) != 0:
		failures.append("player win did not fill the right side")
	hud.apply_match(1, 1, 3, 60.0)
	if _filled_count(hud.opponent_win_pips) != 1 or _filled_count(hud.player_win_pips) != 1:
		failures.append("split round wins")
	hud.apply_match(1, 1, 3, 20.0)
	if _filled_count(hud.opponent_win_pips) != 1 or hud.match_label.text != "ROUND 3" or hud.timer_label.text != "00:20":
		failures.append("same score changed the indicators")
	hud.apply_match(2, 1, 3, 0.0)
	if _filled_count(hud.player_win_pips) != 2:
		failures.append("two player wins did not fill both dots")
	hud.apply_match(1, 2, 3, 52.0)
	if hud.match_label.text != "ROUND 3" or hud.timer_label.text != "00:52":
		failures.append("match text %s %s" % [hud.match_label.text, hud.timer_label.text])
	if hud.player_win_pips.size() != 2 or hud.opponent_win_pips.size() != 2:
		failures.append("round win indicators are not two per side")
	if not hud.player_win_pips[0].get_meta("filled") or hud.player_win_pips[1].get_meta("filled"):
		failures.append("player win dots")
	if not hud.opponent_win_pips[0].get_meta("filled") or not hud.opponent_win_pips[1].get_meta("filled"):
		failures.append("opponent win dots")
	var normal_height := hud._opponent_panel.get_combined_minimum_size().y
	hud.apply_traits(false, "TOUGH CHIN", "SHARP STRAIGHT")
	if hud.player_trait.visible or hud.opponent_trait.visible:
		failures.append("NORMAL still shows trait names")
	if absf(hud._opponent_panel.get_combined_minimum_size().y - normal_height) > 1.0:
		failures.append("NORMAL leaves a trait gap")
	hud.apply_traits(true, "TOUGH CHIN", "SHARP STRAIGHT")
	if hud.player_trait.text != "TOUGH CHIN" or hud.opponent_trait.text != "SHARP STRAIGHT":
		failures.append("TRAIT names missing")
	if not hud.player_trait.visible or not hud.opponent_trait.visible:
		failures.append("TRAIT names hidden")
	if hud._opponent_panel.get_combined_minimum_size().y <= normal_height + 8.0:
		failures.append("TRAIT name does not take a line")
	if hud._opponent_panel.anchor_left > 0.01 or hud._opponent_panel.anchor_top > 0.01:
		failures.append("opponent HUD is not top-left")
	if hud._opponent_panel.offset_left < 20.0 or hud._opponent_panel.offset_top < 12.0:
		failures.append("opponent HUD is outside the safe margin")
	if hud._player_panel.anchor_right < 0.99 or hud._player_panel.anchor_bottom < 0.99:
		failures.append("player HUD is not bottom-right")
	if hud._player_panel.offset_right > -20.0 or hud._player_panel.offset_bottom > -12.0:
		failures.append("player HUD is outside the safe margin")
	if hud._match_cluster.anchor_left < 0.49 or absf(hud._match_cluster.offset_left + hud._match_cluster.offset_right) > 1.0:
		failures.append("match HUD is not centered")
	if hud._match_cluster.offset_top < 18.0 or hud._match_cluster.offset_top > 24.0:
		failures.append("match HUD top margin")
	var match_width := hud._match_cluster.offset_right - hud._match_cluster.offset_left
	if match_width < 240.0 or match_width > 380.0:
		failures.append("match HUD width %s" % match_width)
	var theme_font: Font = (hud.get_child(0) as Control).theme.default_font
	if theme_font == null or theme_font.resource_path != "res://assets/fonts/esamanru Medium.ttf":
		failures.append("CombatHUD theme font is not the project TTF")
	for label in [hud.player_name, hud.opponent_name, hud.player_trait, hud.match_label, hud.timer_label, hud.center_label]:
		if label.get_theme_font("font") != theme_font:
			failures.append("%s does not use the shared HUD font" % label.name)
	if hud.center_label.visible:
		failures.append("center presentation should start empty")
	hud.show_center("FIGHT!")
	if hud.center_label.text != "FIGHT!":
		failures.append("center presentation")
	hud.free()


func _check_scene(failures: Array[String]) -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	var scene := packed.instantiate()
	var debug := scene.get_node_or_null("DebugHUD")
	if debug == null or debug.visible:
		failures.append("DebugHUD should stay in the scene and start hidden")
	if scene.get_node_or_null("DebugHUD/Panel/Margin/Content/PlayerStaminaBar") == null:
		failures.append("hidden debug stamina bar was removed")
	if scene.get_node_or_null("CombatVisualRoot/DebugHUD") != null:
		failures.append("DebugHUD must stay outside CombatVisualRoot")
	var hud := scene.get_node_or_null("CombatHUD")
	if hud == null:
		failures.append("CombatHUD missing")
	else:
		scene.get_node("RoundManager").auto_start = false
		root.add_child(scene)
		hud._build()
		hud._refresh_all()
		if hud.player_stamina_value.text != "100 / 100":
			failures.append("scene player stamina %s" % hud.player_stamina_value.text)
		if hud.player_kd_value.text != "300 / 300" or hud.opponent_kd_value.text != "300 / 300":
			failures.append("scene kd did not start full")
		if hud.player_trait.visible or hud.opponent_trait.visible:
			failures.append("NORMAL scene shows trait names")
		if hud.center_label.visible:
			failures.append("center banner is visible before the round call")
		var mode: ModeType = scene.get_node("GameMode")
		mode.mode = ModeType.Mode.TRAIT
		var traits: ManagerType = ManagerType.new()
		traits.name = "TraitManager"
		traits.player_traits = [_one(TraitType.Id.TOUGH_CHIN)]
		traits.opponent_traits = [_one(TraitType.Id.SHARP_STRAIGHT)]
		scene.add_child(traits)
		hud._refresh_traits()
		if hud.player_trait.text != "강한 맷집" or hud.opponent_trait.text != "날카로운 스트레이트":
			failures.append("scene trait refresh failed")
		if not hud.player_trait.visible or not hud.opponent_trait.visible:
			failures.append("TRAIT mode hid the current trait name")
		if hud.player_trait.text.find("x") >= 0 or hud.player_trait.text.find("+") >= 0:
			failures.append("combat trait label shows a modifier")
		traits.clear_traits()
		hud._refresh_traits()
		if hud.player_trait.visible or hud.player_trait.text != "":
			failures.append("cleared traits left a stale name")
	scene.free()


func _check_fill_direction(failures: Array[String], hud: HudType) -> void:
	if not _drains_outward(hud.opponent_kd_bar, hud.opponent_kd_chunk, false):
		failures.append("opponent kd does not drain from the center side")
	if not _drains_outward(hud.opponent_stamina_bar, hud.opponent_stamina_chunk, false):
		failures.append("opponent stamina does not drain from the center side")
	if not _drains_outward(hud.player_kd_bar, hud.player_kd_chunk, true):
		failures.append("player kd does not drain from the center side")
	if not _drains_outward(hud.player_stamina_bar, hud.player_stamina_chunk, true):
		failures.append("player stamina does not drain from the center side")
	hud.apply_stamina(true, 100.0, 100.0, true)
	hud.apply_stamina(true, 70.0, 100.0)
	hud._process(0.02)
	hud.apply_stamina(true, 80.0, 100.0)
	hud._process(0.0)
	if not _right_anchored(hud.player_stamina_heal, hud.player_stamina_bar):
		failures.append("player stamina highlight does not grow from the right")
	if hud._meter_display[0] > hud._meter_chunk[0] + 0.001:
		failures.append("player stamina chunk fell below the main bar")
	hud.apply_stamina(false, 100.0, 100.0, true)
	hud.apply_stamina(false, 70.0, 100.0)
	hud._process(0.05)
	hud.apply_stamina(false, 80.0, 100.0)
	hud._process(0.0)
	if hud.opponent_stamina_heal.position.x > 1.0:
		failures.append("opponent stamina highlight left the left edge")
	hud.apply_kd(true, 300.0, 300.0, true)
	hud.apply_kd(true, 290.0, 300.0)
	hud.apply_kd(true, 275.0, 300.0)
	hud._process(0.01)
	if not _drains_outward(hud.player_kd_bar, hud.player_kd_chunk, true):
		failures.append("rapid player damage changed the fill direction")
	if hud.player_kd_impact.scale.x < 0.9:
		failures.append("player impact was mirrored")
	if hud.player_kd_flash.color.a < 0.2:
		failures.append("player kd flash missing")
	if hud._meter_target[2] > hud._meter_display[2] + 0.001 or hud._meter_display[2] > hud._meter_chunk[2] + 0.001:
		failures.append("player kd chunk order broke")
	hud.apply_kd(true, 0.0, 300.0, true)
	hud.apply_kd(true, 150.0, 300.0)
	var elapsed := 0.0
	while elapsed < 0.45:
		hud._process(0.05)
		elapsed += 0.05
	if absf(hud.player_kd_bar.value - 150.0) > 2.0:
		failures.append("player recovery display is not half")
	if not _right_anchored(hud.player_kd_heal, hud.player_kd_bar):
		failures.append("player recovery glow is not anchored to the right")
	hud.apply_kd(true, 300.0, 300.0, true)
	hud.apply_kd(false, 300.0, 300.0, true)
	hud.apply_stamina(true, 100.0, 100.0, true)
	hud.apply_stamina(false, 100.0, 100.0, true)
	if not _drains_outward(hud.player_kd_bar, hud.player_kd_chunk, true) or not _drains_outward(hud.opponent_kd_bar, hud.opponent_kd_chunk, false):
		failures.append("reset changed a fill direction")
	if absf(hud.player_kd_bar.value - 300.0) > 0.01 or absf(hud.opponent_kd_bar.value - 300.0) > 0.01:
		failures.append("reset did not fill both KD bars")


func _drains_outward(bar: ProgressBar, chunk: ProgressBar, from_right: bool) -> bool:
	var mode := ProgressBar.FILL_END_TO_BEGIN if from_right else ProgressBar.FILL_BEGIN_TO_END
	return bar.fill_mode == mode and chunk.fill_mode == mode


func _right_anchored(highlight: ColorRect, bar: ProgressBar) -> bool:
	if highlight.size.x < 1.0:
		return false
	return absf(highlight.position.x + highlight.size.x - bar.size.x) <= 1.5


func _filled_count(pips: Array[Panel]) -> int:
	var count := 0
	for pip in pips:
		if bool(pip.get_meta("filled")):
			count += 1
	return count


func _has_meter_caption(node: Node) -> bool:
	if node is Label and node.visible and ((node as Label).text == "KD" or (node as Label).text == "STAMINA"):
		return true
	for child in node.get_children():
		if _has_meter_caption(child):
			return true
	return false


func _fill_is(bar: ProgressBar, expected: Color) -> bool:
	var fill: StyleBox = bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		return (fill as StyleBoxFlat).bg_color.is_equal_approx(expected)
	return false


func _one(id: int) -> Resource:
	for entry in Catalog.all_traits():
		if entry.id == id:
			return entry
	return null
