extends CanvasLayer

## Shows both fighters' traits before the round clock starts.

signal fight_pressed

var _title: Label
var _body: RichTextLabel
var _button: Button


func _ready() -> void:
	layer = 3
	visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48
	panel.offset_top = 36
	panel.offset_right = -48
	panel.offset_bottom = -36
	add_child(panel)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_body)
	_button = Button.new()
	_button.text = "FIGHT"
	_button.pressed.connect(func() -> void:
		visible = false
		fight_pressed.emit()
	)
	panel.add_child(_button)


func show_round(round_number: int, player_traits: Array, opponent_traits: Array, player_wins: int, opponent_wins: int) -> void:
	_title.text = "ROUND %d" % round_number
	_body.text = ""
	_body.append_text("[b]PLAYER[/b]\n")
	_append_traits(player_traits)
	_body.append_text("\n[b]OPPONENT[/b]\n")
	_append_traits(opponent_traits)
	_body.append_text("\n[b]SCORE[/b]  PLAYER %d : %d OPPONENT\n" % [player_wins, opponent_wins])
	visible = true


func _append_traits(traits: Array) -> void:
	for entry in traits:
		_body.append_text("%s\n%s\n%s\n" % [
			entry.display_name,
			entry.positive_effect,
			entry.tradeoff_description,
		])
