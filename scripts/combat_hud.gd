extends CanvasLayer

## Screen-space combat HUD. Reads stamina, KD, round, score, and traits.
## It does not change combat rules.

const STAMINA_COLOR := Color(0.40, 0.72, 0.34, 1.0)
const KD_COLOR := Color(0.80, 0.22, 0.20, 1.0)
const TRACK_COLOR := Color(0.04, 0.04, 0.05, 0.82)
const TEXT_COLOR := Color(0.96, 0.96, 0.94, 1.0)
const TEXT_DIM := Color(0.78, 0.76, 0.72, 0.92)
const PIP_EMPTY := Color(0.62, 0.62, 0.64, 0.92)
const PIP_FILLED := Color(0.96, 0.94, 0.88, 1.0)
const MATCH_BACKING := Color(0.04, 0.035, 0.05, 0.78)
const MATCH_MARGIN_TOP := 20.0
const PIP_SIZE := 10.0

const MARGIN_X := 32.0
const MARGIN_TOP := 20.0
const MARGIN_BOTTOM := 22.0
const BAR_LENGTH := 330.0
const KD_BAR_HEIGHT := 18.0
const STAMINA_BAR_HEIGHT := 10.0
const UI_FONT: FontFile = preload("res://assets/fonts/esamanru Medium.ttf")
## About 95% of a step settles in this time. Exp decay, no overshoot.
const DRAIN_SETTLE_SECONDS := 0.20
const DRAIN_TAU := 0.065
const CHUNK_COLOR := Color(0.55, 0.55, 0.55, 1.0)
const CHUNK_HOLD_SECONDS := 0.15
## Slower than the main bar so the gray loss stays visible, then catches up.
const CHUNK_TAU := 0.09
const SHAKE_AMPLITUDE := 4.0
const SHAKE_DURATION := 0.12
const FLASH_PEAK := 0.55
const FLASH_DURATION := 0.08
const PUNCH_PEAK := 1.05
const PUNCH_DURATION := 0.12
const REGEN_HIGHLIGHT := 0.16
const REGEN_LINGER := 0.22
const REGEN_FADE := 0.18
const HEAL_PEAK := 0.28
const HEAL_DURATION := 0.30

var player_stamina_bar: ProgressBar
var player_stamina_value: Label
var player_kd_bar: ProgressBar
var player_kd_value: Label
var player_name: Label
var player_trait: Label
var opponent_stamina_bar: ProgressBar
var player_stamina_chunk: ProgressBar
var opponent_stamina_chunk: ProgressBar
var player_kd_chunk: ProgressBar
var opponent_kd_chunk: ProgressBar
var player_kd_impact: Control
var opponent_kd_impact: Control
var player_kd_flash: ColorRect
var opponent_kd_flash: ColorRect
var player_stamina_heal: ColorRect
var opponent_stamina_heal: ColorRect
var player_kd_heal: ColorRect
var opponent_kd_heal: ColorRect
var _regen_on: Array[bool] = [false, false]
var _regen_hold: Array[float] = [0.0, 0.0]
var _regen_fade: Array[float] = [0.0, 0.0]
var _regen_starts: Array[int] = [0, 0]
var _kd_heal_time: Array[float] = [-1.0, -1.0]
var _kd_hosts: Array[Control] = []
var _shake_time: Array[float] = [-1.0, -1.0]
var _flash_time: Array[float] = [-1.0, -1.0]
var _punch_time: Array[float] = [-1.0, -1.0]
var opponent_stamina_value: Label
var opponent_kd_bar: ProgressBar
var opponent_kd_value: Label
var opponent_name: Label
var opponent_trait: Label
var match_label: Label
var timer_label: Label
var player_win_pips: Array[Panel] = []
var opponent_win_pips: Array[Panel] = []
var center_label: Label
var _match_cluster: Control
var _opponent_panel: Control
var _player_panel: Control
var _center_token := 0
var _built := false
var _meter_target: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _meter_display: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _meter_chunk: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _chunk_hold: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _meter_bars: Array[ProgressBar] = []
var _chunk_bars: Array[ProgressBar] = []


func _ready() -> void:
	layer = 2
	_build()
	_bind()
	_refresh_all(true)
	set_process(true)


func _process(delta: float) -> void:
	for index in _meter_bars.size():
		var target: float = _meter_target[index]
		var display: float = _move_toward_value(_meter_display[index], target, delta, DRAIN_TAU)
		_meter_display[index] = display
		_meter_bars[index].value = display
		_meter_chunk[index] = _advance_chunk(index, display, target, delta)
		if index < _chunk_bars.size():
			_chunk_bars[index].value = _meter_chunk[index]
	_present_kd_impacts(delta)
	_present_heals(delta)


func _move_toward_value(current: float, target: float, delta: float, tau: float) -> float:
	if is_equal_approx(current, target):
		return target
	var blend := 1.0 - exp(-delta / tau)
	var next := current + (target - current) * blend
	if target >= current:
		next = minf(next, target)
	else:
		next = maxf(next, target)
	if absf(next - target) < 0.05:
		return target
	return next


func _advance_chunk(index: int, display: float, target: float, delta: float) -> float:
	var chunk := _meter_chunk[index]
	if _chunk_hold[index] > 0.0:
		_chunk_hold[index] = maxf(_chunk_hold[index] - delta, 0.0)
	elif target + 0.001 >= chunk:
		chunk = display
	else:
		chunk = _move_toward_value(chunk, target, delta, CHUNK_TAU)
	chunk = maxf(chunk, display)
	return clampf(chunk, 0.0, _meter_bars[index].max_value)


func apply_stamina(is_player: bool, current: float, maximum: float, immediate: bool = false) -> void:
	_set_meter(0 if is_player else 1, player_stamina_bar if is_player else opponent_stamina_bar, player_stamina_value if is_player else opponent_stamina_value, current, maximum, immediate)


func apply_kd(is_player: bool, current: float, maximum: float, immediate: bool = false) -> void:
	_set_meter(2 if is_player else 3, player_kd_bar if is_player else opponent_kd_bar, player_kd_value if is_player else opponent_kd_value, current, maximum, immediate)


func apply_match(player_score: int, opponent_score: int, round_number: int, seconds_left: float) -> void:
	match_label.text = "ROUND %d" % round_number if round_number > 0 else "ROUND -"
	var minutes := int(seconds_left) / 60
	var secs := int(seconds_left) % 60
	timer_label.text = "%02d:%02d" % [minutes, secs]
	_paint_pips(opponent_win_pips, opponent_score)
	_paint_pips(player_win_pips, player_score)
	_fit_match()


func apply_traits(show_names: bool, player_trait_name: String, opponent_trait_name: String) -> void:
	_set_trait(player_trait, show_names, player_trait_name)
	_set_trait(opponent_trait, show_names, opponent_trait_name)
	_fit_panels()


func show_center(text: String) -> void:
	center_label.text = text
	center_label.visible = text != ""


func _build() -> void:
	if _built:
		return
	_built = true
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = UI_FONT
	root.theme = theme
	add_child(root)

	_opponent_panel = _fighter_column("OpponentPanel")
	root.add_child(_opponent_panel)
	opponent_name = _label("OPPONENT", 17, TEXT_COLOR, 4)
	opponent_trait = _label("", 12, TEXT_DIM, 3)
	opponent_trait.visible = false
	var opp_kd := _meter_block(false, false)
	var opp_stamina := _meter_block(true, false)
	_bind_meter(opp_stamina, opp_kd, false)
	_opponent_panel.add_child(opponent_name)
	_opponent_panel.add_child(opponent_trait)
	_opponent_panel.add_child(opp_kd["row"])
	_opponent_panel.add_child(opp_stamina["row"])

	_player_panel = _fighter_column("PlayerPanel")
	root.add_child(_player_panel)
	var player_kd := _meter_block(false, true)
	var player_stamina := _meter_block(true, true)
	_bind_meter(player_stamina, player_kd, true)
	player_name = _label("PLAYER", 17, TEXT_COLOR, 4)
	player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	player_trait = _label("", 12, TEXT_DIM, 3)
	player_trait.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	player_trait.visible = false
	_player_panel.add_child(player_kd["row"])
	_player_panel.add_child(player_stamina["row"])
	_player_panel.add_child(player_name)
	_player_panel.add_child(player_trait)

	_match_cluster = _match_cluster_node()
	root.add_child(_match_cluster)

	center_label = _label("", 40)
	center_label.name = "CenterPresentation"
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.offset_left = -220.0
	center_label.offset_right = 220.0
	center_label.offset_top = -36.0
	center_label.offset_bottom = 36.0
	center_label.add_theme_constant_override("outline_size", 6)
	center_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	center_label.visible = false
	root.add_child(center_label)
	var announcement := preload("res://scripts/combat_announcement.gd").new()
	announcement.name = "CombatAnnouncement"
	add_child(announcement)
	_meter_bars = [
		player_stamina_bar,
		opponent_stamina_bar,
		player_kd_bar,
		opponent_kd_bar,
	]
	_chunk_bars = [
		player_stamina_chunk,
		opponent_stamina_chunk,
		player_kd_chunk,
		opponent_kd_chunk,
	]
	_kd_hosts = [player_kd_impact, opponent_kd_impact]
	_fit_panels()
	_fit_match()


func _bind() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var stamina := parent.get_node_or_null("PlayerStamina")
	var opp_stamina := parent.get_node_or_null("OpponentStamina")
	var player_kd := parent.get_node_or_null("PlayerKnockdownMeter")
	var opp_kd := parent.get_node_or_null("OpponentKnockdownMeter")
	if stamina != null and stamina.has_signal("stamina_changed"):
		stamina.stamina_changed.connect(func(current: float, maximum: float) -> void:
			apply_stamina(true, current, maximum)
		)
	if opp_stamina != null and opp_stamina.has_signal("stamina_changed"):
		opp_stamina.stamina_changed.connect(func(current: float, maximum: float) -> void:
			apply_stamina(false, current, maximum)
		)
	if player_kd != null and player_kd.has_signal("meter_changed"):
		player_kd.meter_changed.connect(func(current: float, maximum: float) -> void:
			apply_kd(true, current, maximum)
		)
	if opp_kd != null and opp_kd.has_signal("meter_changed"):
		opp_kd.meter_changed.connect(func(current: float, maximum: float) -> void:
			apply_kd(false, current, maximum)
		)
	var rounds := parent.get_node_or_null("RoundManager")
	if rounds != null:
		if rounds.has_signal("time_changed"):
			rounds.time_changed.connect(func(_seconds: float) -> void:
				_refresh_match()
			)
		if rounds.has_signal("hud_text_changed"):
			rounds.hud_text_changed.connect(func(_text: String) -> void:
				_refresh_match()
			)
		if rounds.has_signal("round_started"):
			rounds.round_started.connect(_on_round_started)
		if rounds.has_signal("decision_required"):
			rounds.decision_required.connect(func() -> void:
				_announce("play_decision")
			)
		if rounds.has_signal("round_ended"):
			rounds.round_ended.connect(func(_n: int) -> void:
				pass
			)
	var knockdown := parent.get_node_or_null("KnockdownManager")
	if knockdown != null and knockdown.has_signal("count_changed"):
		knockdown.count_changed.connect(func(count: int, _side: int) -> void:
			_announce_count(count)
		)
	if knockdown != null and knockdown.has_signal("hud_text_changed"):
		knockdown.hud_text_changed.connect(_on_knockdown_text)
	var traits := parent.get_node_or_null("TraitManager")
	if traits != null and traits.has_signal("traits_changed"):
		traits.traits_changed.connect(_refresh_traits)
	_refresh_all(true)


func _refresh_all(immediate: bool = false) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var stamina := parent.get_node_or_null("PlayerStamina")
	var opp_stamina := parent.get_node_or_null("OpponentStamina")
	var player_kd := parent.get_node_or_null("PlayerKnockdownMeter")
	var opp_kd := parent.get_node_or_null("OpponentKnockdownMeter")
	if stamina != null:
		apply_stamina(true, float(stamina.current_stamina), float(stamina.max_stamina), immediate)
	if opp_stamina != null:
		apply_stamina(false, float(opp_stamina.current_stamina), float(opp_stamina.max_stamina), immediate)
	if player_kd != null:
		apply_kd(true, float(player_kd.current_meter), float(player_kd.max_meter), immediate)
	if opp_kd != null:
		apply_kd(false, float(opp_kd.current_meter), float(opp_kd.max_meter), immediate)
	_refresh_match()
	_refresh_traits()


func _refresh_match() -> void:
	var rounds := get_parent().get_node_or_null("RoundManager") if get_parent() != null else null
	if rounds == null:
		return
	apply_match(
		int(rounds.player_round_wins),
		int(rounds.opponent_round_wins),
		int(rounds.current_round),
		float(rounds.time_remaining)
	)


func _refresh_traits() -> void:
	var parent := get_parent()
	var mode := parent.get_node_or_null("GameMode") if parent != null else null
	var show_names := false
	if mode != null and mode.has_method("is_trait_mode"):
		show_names = bool(mode.is_trait_mode())
	var traits := parent.get_node_or_null("TraitManager") if parent != null else null
	var catalog = preload("res://scripts/trait_catalog.gd")
	var player_text := ""
	var opponent_text := ""
	if show_names and traits != null and not traits.player_traits.is_empty() and traits.player_traits[0] != null:
		player_text = catalog.reveal_name(traits.player_traits[0])
	if show_names and traits != null and not traits.opponent_traits.is_empty() and traits.opponent_traits[0] != null:
		opponent_text = catalog.reveal_name(traits.opponent_traits[0])
	apply_traits(show_names and player_text != "", player_text, opponent_text)


func _on_round_started(_round_number: int) -> void:
	_refresh_all(true)
	_refresh_traits()
	_refresh_match()


func _announce(method: String) -> void:
	var banner := get_node_or_null("CombatAnnouncement")
	if banner != null and banner.has_method(method):
		banner.call(method)


func _announce_count(count: int) -> void:
	var banner := get_node_or_null("CombatAnnouncement")
	if banner != null:
		banner.show_count(count)


func _on_knockdown_text(text: String) -> void:
	if text.begins_with("KO") or text == "DOUBLE KO":
		_announce("play_knockout")
	elif text == "FIGHTING":
		pass


func _trait_name(entries: Array) -> String:
	if entries.is_empty() or entries[0] == null:
		return ""
	var catalog = preload("res://scripts/trait_catalog.gd")
	return catalog.english_name(entries[0]).to_upper()


func _set_trait(label: Label, show_names: bool, trait_name: String) -> void:
	label.visible = show_names and trait_name != ""
	label.text = trait_name if show_names else ""


func _set_meter(index: int, bar: ProgressBar, label: Label, current: float, maximum: float, immediate: bool) -> void:
	var capped := maxf(maximum, 1.0)
	var actual := clampf(current, 0.0, capped)
	bar.max_value = capped
	if index < _chunk_bars.size() and _chunk_bars[index] != null:
		_chunk_bars[index].max_value = capped
	label.text = "%d / %d" % [roundi(actual), roundi(maximum)]
	var previous_target := _meter_target[index]
	_meter_target[index] = actual
	if immediate or _meter_bars.is_empty():
		_meter_display[index] = actual
		_meter_chunk[index] = actual
		_chunk_hold[index] = 0.0
		bar.value = actual
		if index < _chunk_bars.size() and _chunk_bars[index] != null:
			_chunk_bars[index].value = actual
		if index >= 2:
			_clear_kd_impact(index - 2)
			_clear_kd_heal(index - 2)
		else:
			_clear_regen(index)
		return
	if actual < previous_target - 0.001:
		_meter_chunk[index] = maxf(_meter_chunk[index], _meter_display[index])
		_chunk_hold[index] = CHUNK_HOLD_SECONDS
		if index >= 2:
			_trigger_kd_impact(index - 2)
		else:
			_end_regen(index)
	elif actual > previous_target + 0.001:
		if index >= 2:
			_trigger_kd_heal(index - 2)
		else:
			_note_stamina_increase(index, actual, capped)
	bar.value = _meter_display[index]


func _fit_panels() -> void:
	_place_top_left(_opponent_panel)
	_place_bottom_right(_player_panel)


func _place_top_left(panel: Control) -> void:
	var size := panel.get_combined_minimum_size()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = MARGIN_X
	panel.offset_top = MARGIN_TOP
	panel.offset_right = MARGIN_X + size.x
	panel.offset_bottom = MARGIN_TOP + size.y


func _place_bottom_right(panel: Control) -> void:
	var size := panel.get_combined_minimum_size()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_right = -MARGIN_X
	panel.offset_bottom = -MARGIN_BOTTOM
	panel.offset_left = -MARGIN_X - size.x
	panel.offset_top = -MARGIN_BOTTOM - size.y


func _fit_match() -> void:
	if _match_cluster == null:
		return
	var size := _match_cluster.get_combined_minimum_size()
	_match_cluster.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_match_cluster.offset_left = -size.x * 0.5
	_match_cluster.offset_right = size.x * 0.5
	_match_cluster.offset_top = MATCH_MARGIN_TOP
	_match_cluster.offset_bottom = MATCH_MARGIN_TOP + size.y


func _fighter_column(node_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	return box


func _bind_meter(stamina: Dictionary, kd: Dictionary, is_player: bool) -> void:
	if is_player:
		player_stamina_bar = stamina["bar"]
		player_stamina_chunk = stamina["chunk"]
		player_stamina_value = stamina["value"]
		player_stamina_heal = stamina["heal"]
		player_kd_bar = kd["bar"]
		player_kd_chunk = kd["chunk"]
		player_kd_value = kd["value"]
		player_kd_impact = kd["impact"]
		player_kd_flash = kd["flash"]
		player_kd_heal = kd["heal"]
	else:
		opponent_stamina_bar = stamina["bar"]
		opponent_stamina_chunk = stamina["chunk"]
		opponent_stamina_value = stamina["value"]
		opponent_stamina_heal = stamina["heal"]
		opponent_kd_bar = kd["bar"]
		opponent_kd_chunk = kd["chunk"]
		opponent_kd_value = kd["value"]
		opponent_kd_impact = kd["impact"]
		opponent_kd_flash = kd["flash"]
		opponent_kd_heal = kd["heal"]


func _match_cluster_node() -> PanelContainer:
	var cluster := PanelContainer.new()
	cluster.name = "MatchHUD"
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = MATCH_BACKING
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.95, 0.93, 0.88, 0.28)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 2
	style.corner_radius_bottom_left = 10
	cluster.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.name = "MatchRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	cluster.add_child(row)
	opponent_win_pips = _pip_row(row, "OpponentWins")
	var info := HBoxContainer.new()
	info.name = "MatchInfo"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	match_label = _label("ROUND -", 19, TEXT_COLOR, 5)
	match_label.name = "Round"
	info.add_child(match_label)
	var separator := Panel.new()
	separator.name = "Separator"
	separator.custom_minimum_size = Vector2(4, 4)
	separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := StyleBoxFlat.new()
	dot.bg_color = PIP_FILLED
	dot.corner_radius_top_left = 2
	dot.corner_radius_top_right = 2
	dot.corner_radius_bottom_right = 2
	dot.corner_radius_bottom_left = 2
	separator.add_theme_stylebox_override("panel", dot)
	info.add_child(separator)
	timer_label = _label("00:00", 21, TEXT_COLOR, 5)
	timer_label.name = "Timer"
	info.add_child(timer_label)
	player_win_pips = _pip_row(row, "PlayerWins")
	return cluster


func _pip_row(parent: HBoxContainer, row_name: String) -> Array[Panel]:
	var box := HBoxContainer.new()
	box.name = row_name
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 7)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(box)
	var pips: Array[Panel] = []
	for index in 2:
		var pip := Panel.new()
		pip.name = "Win%d" % [index + 1]
		pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pip)
		pips.append(pip)
	_paint_pips(pips, 0)
	return pips


func _paint_pips(pips: Array[Panel], wins: int) -> void:
	for index in pips.size():
		var filled := index < wins
		var style := StyleBoxFlat.new()
		var radius := int(PIP_SIZE * 0.5)
		style.corner_radius_top_left = radius
		style.corner_radius_top_right = radius
		style.corner_radius_bottom_right = radius
		style.corner_radius_bottom_left = radius
		style.set_border_width_all(1 if filled else 0)
		if filled:
			style.bg_color = PIP_FILLED
			style.border_color = Color(0.08, 0.08, 0.09, 0.85)
		else:
			style.bg_color = PIP_EMPTY
			style.border_color = PIP_EMPTY
		pips[index].add_theme_stylebox_override("panel", style)
		pips[index].set_meta("filled", filled)


func _label(text: String, font_size: int, color: Color = TEXT_COLOR, outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	return label


func _meter_block(stamina: bool, from_right: bool) -> Dictionary:
	var block := Control.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var height := STAMINA_BAR_HEIGHT if stamina else KD_BAR_HEIGHT
	var fill_from := ProgressBar.FILL_END_TO_BEGIN if from_right else ProgressBar.FILL_BEGIN_TO_END
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(BAR_LENGTH, height)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chunk := ProgressBar.new()
	chunk.set_anchors_preset(Control.PRESET_FULL_RECT)
	chunk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chunk.show_percentage = false
	chunk.max_value = 100.0 if stamina else 300.0
	chunk.value = chunk.max_value if stamina else 0.0
	chunk.custom_minimum_size = Vector2(BAR_LENGTH, height)
	chunk.fill_mode = fill_from
	_style_bar(chunk, CHUNK_COLOR)
	var bar := ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.max_value = chunk.max_value
	bar.value = chunk.value
	bar.custom_minimum_size = Vector2(BAR_LENGTH, height)
	bar.fill_mode = fill_from
	_style_bar(bar, STAMINA_COLOR if stamina else KD_COLOR)
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(0, 0, 0, 0)
	bar.add_theme_stylebox_override("background", clear)
	stack.add_child(chunk)
	stack.add_child(bar)
	var heal := ColorRect.new()
	heal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heal.color = Color(1, 1, 1, 0)
	stack.add_child(heal)
	var value := _label("0 / 0", 11, TEXT_DIM)
	value.visible = false
	var impact: Control = null
	var flash: ColorRect = null
	if stamina:
		stack.set_anchors_preset(Control.PRESET_FULL_RECT)
		block.add_child(stack)
	else:
		flash = ColorRect.new()
		flash.color = Color(1, 1, 1, 0)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(flash)
		var host := Control.new()
		host.custom_minimum_size = Vector2(BAR_LENGTH, height)
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		impact = Control.new()
		impact.name = "KdImpact"
		impact.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.set_anchors_preset(Control.PRESET_FULL_RECT)
		impact.add_child(stack)
		host.add_child(impact)
		block.add_child(host)
	block.custom_minimum_size = Vector2(BAR_LENGTH, height)
	block.add_child(value)
	return {
		"row": block,
		"bar": bar,
		"chunk": chunk,
		"value": value,
		"impact": impact,
		"flash": flash,
		"heal": heal,
	}


func _trigger_kd_impact(slot: int) -> void:
	_shake_time[slot] = 0.0
	_flash_time[slot] = 0.0
	_punch_time[slot] = 0.0


func _clear_kd_impact(slot: int) -> void:
	_shake_time[slot] = -1.0
	_flash_time[slot] = -1.0
	_punch_time[slot] = -1.0
	_apply_kd_impact(slot)


func _present_kd_impacts(delta: float) -> void:
	for slot in 2:
		if _shake_time[slot] >= 0.0:
			_shake_time[slot] += delta
			if _shake_time[slot] >= SHAKE_DURATION:
				_shake_time[slot] = -1.0
		if _flash_time[slot] >= 0.0:
			_flash_time[slot] += delta
			if _flash_time[slot] >= FLASH_DURATION:
				_flash_time[slot] = -1.0
		if _punch_time[slot] >= 0.0:
			_punch_time[slot] += delta
			if _punch_time[slot] >= PUNCH_DURATION:
				_punch_time[slot] = -1.0
		_apply_kd_impact(slot)


func _apply_kd_impact(slot: int) -> void:
	if slot >= _kd_hosts.size() or _kd_hosts[slot] == null:
		return
	var body := _kd_hosts[slot]
	var parent := body.get_parent() as Control
	if parent != null and parent.size.x > 1.0:
		body.size = parent.size
	body.pivot_offset = body.size * 0.5
	var offset := Vector2.ZERO
	if _shake_time[slot] >= 0.0:
		var amount := clampf(_shake_time[slot] / SHAKE_DURATION, 0.0, 1.0)
		var envelope := 1.0 - amount
		offset.x = sin(amount * TAU * 3.0) * SHAKE_AMPLITUDE * envelope
		offset.y = sin(amount * TAU * 2.0) * 0.6 * envelope
	body.position = offset
	var punch := 1.0
	if _punch_time[slot] >= 0.0:
		var amount := clampf(_punch_time[slot] / PUNCH_DURATION, 0.0, 1.0)
		punch = lerpf(PUNCH_PEAK, 1.0, amount)
	body.scale = Vector2(punch, punch)
	var flash := player_kd_flash if slot == 0 else opponent_kd_flash
	var alpha := 0.0
	if flash != null and _flash_time[slot] >= 0.0:
		var amount := clampf(_flash_time[slot] / FLASH_DURATION, 0.0, 1.0)
		alpha = FLASH_PEAK * (1.0 - amount)
	if flash != null:
		flash.color = Color(1, 1, 1, alpha)


func _note_stamina_increase(index: int, actual: float, maximum: float) -> void:
	if actual >= maximum - 0.001:
		if _regen_on[index]:
			_end_regen(index)
		return
	if not _regen_on[index]:
		_regen_on[index] = true
		_regen_starts[index] += 1
	_regen_hold[index] = REGEN_LINGER
	_regen_fade[index] = 0.0


func _end_regen(index: int) -> void:
	if not _regen_on[index] and _regen_fade[index] <= 0.0:
		return
	_regen_on[index] = false
	_regen_hold[index] = 0.0
	_regen_fade[index] = REGEN_FADE


func _clear_regen(index: int) -> void:
	_regen_on[index] = false
	_regen_hold[index] = 0.0
	_regen_fade[index] = 0.0
	_paint_regen(index, 0.0)


func _trigger_kd_heal(slot: int) -> void:
	_kd_heal_time[slot] = 0.0


func _clear_kd_heal(slot: int) -> void:
	_kd_heal_time[slot] = -1.0
	_paint_kd_heal(slot, 0.0)


func _present_heals(delta: float) -> void:
	for slot in 2:
		var alpha := 0.0
		if _regen_on[slot]:
			_regen_hold[slot] = maxf(_regen_hold[slot] - delta, 0.0)
			if _regen_hold[slot] <= 0.0:
				_end_regen(slot)
			else:
				alpha = REGEN_HIGHLIGHT
		if not _regen_on[slot] and _regen_fade[slot] > 0.0:
			_regen_fade[slot] = maxf(_regen_fade[slot] - delta, 0.0)
			alpha = REGEN_HIGHLIGHT * (_regen_fade[slot] / REGEN_FADE)
		_paint_regen(slot, alpha)
		var glow := 0.0
		if _kd_heal_time[slot] >= 0.0:
			_kd_heal_time[slot] += delta
			if _kd_heal_time[slot] >= HEAL_DURATION:
				_kd_heal_time[slot] = -1.0
			else:
				var amount := clampf(_kd_heal_time[slot] / HEAL_DURATION, 0.0, 1.0)
				var falloff := 1.0 - amount
				glow = HEAL_PEAK * falloff * falloff
		_paint_kd_heal(slot, glow)


func _paint_regen(slot: int, alpha: float) -> void:
	var rect := player_stamina_heal if slot == 0 else opponent_stamina_heal
	var bar := player_stamina_bar if slot == 0 else opponent_stamina_bar
	_paint_fill_highlight(rect, bar, alpha)


func _paint_kd_heal(slot: int, alpha: float) -> void:
	var rect := player_kd_heal if slot == 0 else opponent_kd_heal
	var bar := player_kd_bar if slot == 0 else opponent_kd_bar
	_paint_fill_highlight(rect, bar, alpha)


func _paint_fill_highlight(rect: ColorRect, bar: ProgressBar, alpha: float) -> void:
	if rect == null or bar == null:
		return
	var ratio := 0.0
	if bar.max_value > 0.0:
		ratio = clampf(bar.value / bar.max_value, 0.0, 1.0)
	var width := bar.size.x * ratio
	var origin_x := bar.size.x - width if bar.fill_mode == ProgressBar.FILL_END_TO_BEGIN else 0.0
	rect.position = Vector2(origin_x, 0.0)
	rect.size = Vector2(width, bar.size.y)
	rect.color = Color(1, 1, 1, alpha)


func _style_bar(bar: ProgressBar, fill_color: Color) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_COLOR
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
