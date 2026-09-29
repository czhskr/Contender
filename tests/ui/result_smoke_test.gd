extends SceneTree

## Result presentation reads a published match result and does not score it.
## godot --headless --path . -s res://tests/ui/result_smoke_test.gd

const ResultScript = preload("res://scripts/match_result_data.gd")
const ScoreScript = preload("res://scripts/round_score.gd")
const ScreenScript = preload("res://scripts/result_screen.gd")
const Settings = preload("res://scripts/match_settings.gd")
const Transition = preload("res://scripts/page_transition.gd")
const Announcement = preload("res://scripts/combat_announcement.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_check_display(failures, ResultScript.Winner.PLAYER, ResultScript.ResultType.KO, "VICTORY", "KNOCKOUT", false)
	_check_display(failures, ResultScript.Winner.OPPONENT, ResultScript.ResultType.KO, "DEFEAT", "KNOCKOUT", false)
	_check_display(failures, ResultScript.Winner.PLAYER, ResultScript.ResultType.DECISION, "VICTORY", "DECISION", true)
	_check_display(failures, ResultScript.Winner.OPPONENT, ResultScript.ResultType.DECISION, "DEFEAT", "DECISION", true)
	_check_display(failures, ResultScript.Winner.NONE, ResultScript.ResultType.DRAW, "DRAW", "DRAW", false)
	var source := FileAccess.get_file_as_string("res://scripts/result_screen.gd")
	if source.find("round_scorer") >= 0 or source.find("KnockdownManager") >= 0 or source.find("CombatStats") >= 0:
		failures.append("result screen reaches into combat")
	var combat := FileAccess.get_file_as_string("res://scripts/combat_prototype.gd")
	if combat.find("round_voided") >= 0 or combat.find("_on_result_banner_finished") < 0:
		failures.append("result opens without waiting for the announcement, or on a double KO")
	var screen := _open(_make(ResultScript.Winner.PLAYER, ResultScript.ResultType.DECISION, true))
	var down := InputEventKey.new()
	down.pressed = true
	down.keycode = KEY_DOWN
	screen._unhandled_input(down)
	if screen.selected_index != 1 or not screen._buttons[1].selected or screen._buttons[0].selected:
		failures.append("keyboard did not move to the title button")
	screen._buttons[0].mouse_entered.emit()
	if screen.selected_index != 0 or Transition.is_running():
		failures.append("hover activated a button")
	var banner := Announcement.new()
	root.add_child(banner)
	var opened := [false]
	banner.pass_finished.connect(func(text: String) -> void:
		if text == "KNOCKOUT":
			opened[0] = true
	)
	banner.play_knockout()
	if opened[0]:
		failures.append("result would open before KNOCKOUT finishes")
	await create_timer(0.50).timeout
	if opened[0]:
		failures.append("KNOCKOUT was cut short")
	await create_timer(0.55).timeout
	if not opened[0]:
		failures.append("KNOCKOUT did not finish")
	banner.play_decision()
	if banner.current_text != "DECISION":
		failures.append("DECISION announcement changed")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var mode_before: int = Settings.difficulty
	Settings.difficulty = Settings.Difficulty.HARD
	screen._buttons[0]._gui_input(click)
	var built: Node = screen._build_rematch(ResultScript.resume_mode)
	var mode_node: Node = built.get_node_or_null("GameMode")
	if mode_node == null or int(mode_node.mode) != ResultScript.resume_mode:
		failures.append("retry did not keep the game mode")
	if Settings.difficulty != Settings.Difficulty.HARD:
		failures.append("retry reset the difficulty")
	Settings.difficulty = mode_before
	built.free()
	var title: Node = screen._build_title(0)
	root.add_child(title)
	if title == null or title.get_node_or_null("Logo") == null:
		failures.append("title return did not build the title scene")
	title.free()
	if failures.is_empty():
		print("SMOKE PASS: result scene")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_display(failures: Array[String], winner: int, result_type: int, headline: String, method: String, with_scores: bool) -> void:
	var screen := _open(_make(winner, result_type, with_scores))
	if screen._headline.text != headline or screen._method.text != method:
		failures.append("%s / %s was shown as %s / %s" % [headline, method, screen._headline.text, screen._method.text])
	var lines := screen.get_node("ResultPanel/RoundScores")
	var found_round := false
	for child in lines.get_children():
		if child is Label and (child as Label).text.begins_with("ROUND"):
			found_round = true
			if not with_scores:
				failures.append("KO invented a round score")
	if with_scores and not found_round:
		failures.append("decision round scores were missing")
	if with_scores:
		var text := ""
		for child in lines.get_children():
			if child is Label:
				text += (child as Label).text + "\n"
		if text.find("ROUND 1          10 - 9") < 0 or text.find("ROUND 2          8 - 10") < 0:
			failures.append("decision scores were not the published cards")
	screen.free()


func _open(result) -> Control:
	ResultScript.publish(result, 1)
	var screen: Control = ScreenScript.new()
	screen.name = "Result"
	root.add_child(screen)
	return screen


func _make(winner: int, result_type: int, with_scores: bool):
	var result := ResultScript.new()
	result.winner = winner
	result.result_type = result_type
	result.player_round_wins = 2 if winner == ResultScript.Winner.PLAYER else 0
	result.opponent_round_wins = 2 if winner == ResultScript.Winner.OPPONENT else 0
	if winner == ResultScript.Winner.NONE:
		result.player_round_wins = 1
		result.opponent_round_wins = 1
	if with_scores:
		result.round_scores = [_score(1, 10, 9), _score(2, 8, 10), _score(3, 10, 9)]
	return result


func _score(round_number: int, player_score: int, opponent_score: int):
	var score := ScoreScript.new()
	score.round_number = round_number
	score.player_score = player_score
	score.opponent_score = opponent_score
	return score
