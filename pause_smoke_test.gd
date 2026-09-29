extends SceneTree

## Pause menu, resume countdown, and hover sound.
## Run: godot --headless --path . -s res://pause_smoke_test.gd

const PauseMenu = preload("res://scripts/pause_menu.gd")
const Rounds = preload("res://scripts/round_manager.gd")
const Knockdown = preload("res://scripts/knockdown_manager.gd")
const Announcement = preload("res://scripts/combat_announcement.gd")
const Settings = preload("res://scripts/match_settings.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var audio = root.get_node("AudioDirector")
	var host := Node.new()
	host.name = "Match"
	root.add_child(host)
	var knockdown := Knockdown.new()
	knockdown.name = "KnockdownManager"
	knockdown.print_events = false
	var rounds := Rounds.new()
	rounds.name = "RoundManager"
	rounds.auto_start = false
	rounds.print_events = false
	rounds.knockdown_manager = knockdown
	var hud := CanvasLayer.new()
	hud.name = "CombatHUD"
	var banner := Announcement.new()
	banner.name = "CombatAnnouncement"
	hud.add_child(banner)
	host.add_child(hud)
	host.add_child(knockdown)
	host.add_child(rounds)
	var pause: Node = PauseMenu.new()
	pause.name = "PauseMenu"
	host.add_child(pause)
	await process_frame

	_fighting(rounds, knockdown)
	rounds.time_remaining = 40.0
	var hovers_before: int = audio.hover_plays
	_key(pause, KEY_ESCAPE)
	if not pause.open or not paused:
		failures.append("ESC did not open a frozen pause menu")
	if pause._overlay == null or not pause._overlay.visible or pause._overlay.color.a < 0.4:
		failures.append("pause overlay is missing")
	if pause._buttons.size() != 3:
		failures.append("pause menu does not have three buttons")
	elif absf(pause._buttons[0].position.x - 406.0) > 1.0 or absf(pause._buttons[1].position.x - pause._buttons[0].position.x) > 0.1:
		failures.append("pause buttons are not centered as one column")
	await process_frame
	if not is_equal_approx(rounds.time_remaining, 40.0):
		failures.append("round timer advanced while paused")
	_key(pause, KEY_DOWN)
	_key(pause, KEY_DOWN)
	if pause.selected != 2 or audio.hover_plays != hovers_before + 2:
		failures.append("keyboard selection did not play one hover per move")
	var stuck: int = audio.hover_plays
	pause._select_main(pause.selected)
	if audio.hover_plays != stuck:
		failures.append("hover sound repeated on the same item")

	_key(pause, KEY_UP)
	_key(pause, KEY_ENTER)
	if not pause.options_open or pause._main.visible:
		failures.append("options did not replace the main buttons")
	Settings.bgm_volume = 0.4
	Settings.sfx_volume = 0.4
	pause.option_index = 0
	pause._nudge_option(1)
	await process_frame
	var bgm_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM"))
	if not is_equal_approx(Settings.bgm_volume, 0.45) or not is_equal_approx(bgm_db, linear_to_db(0.45)):
		failures.append("pause BGM slider did not update the bus")
	pause.option_index = 1
	pause._nudge_option(-1)
	await process_frame
	var voice_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice"))
	var sfx_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	if not is_equal_approx(Settings.sfx_volume, 0.35) or not is_equal_approx(voice_db, sfx_db):
		failures.append("pause SFX slider did not drive SFX and Voice")
	var difficulty_before: int = Settings.difficulty
	pause.option_index = 2
	pause._nudge_option(1)
	if Settings.difficulty != difficulty_before:
		failures.append("pause options changed the stored difficulty")
	var shake_before: int = Settings.screen_shake
	if pause._option_rows[2].text.find("화면 흔들림") < 0:
		failures.append("pause screen shake row is missing")
	pause._nudge_option(1)
	if Settings.screen_shake == shake_before and shake_before != Settings.ScreenShake.STRONG:
		failures.append("pause screen shake was not stored")
	Settings.screen_shake = shake_before
	Settings.bgm_volume = 1.0
	Settings.sfx_volume = 1.0
	for row in pause._option_rows:
		if row.text.find("난이도") >= 0:
			failures.append("pause options still show difficulty")
	pause.option_index = 3
	if pause._option_rows[3].text != "닫기":
		failures.append("options close button is missing")
	_key(pause, KEY_ESCAPE)
	if pause.options_open or not pause._main.visible:
		failures.append("ESC did not close options back to the pause menu")

	var counts_before: int = audio.count_voice_plays
	var bells_before: int = audio.bell_plays
	var fights_before: int = audio.fight_plays
	_key(pause, KEY_ESCAPE)
	if pause.open or not paused or not pause.counting:
		failures.append("fighting resume did not hold gameplay for the countdown")
	if not audio.count_voice_path.ends_with("voice_count_03.mp3"):
		failures.append("resume 3 did not use voice_count_03")
	pause._process(1.0)
	if not audio.count_voice_path.ends_with("voice_count_02.mp3"):
		failures.append("resume 2 did not use voice_count_02")
	pause._process(1.0)
	if not audio.count_voice_path.ends_with("voice_count_01.mp3"):
		failures.append("resume 1 did not use voice_count_01")
	pause._process(1.0)
	if paused == false or audio.fight_plays != fights_before + 1 or audio.bell_plays != bells_before:
		failures.append("resume FIGHT unpaused early or rang the round bell")
	if audio.count_voice_plays != counts_before + 3:
		failures.append("resume countdown did not play exactly three count voices")
	banner.pass_finished.emit("FIGHT")
	if paused:
		failures.append("gameplay stayed paused after FIGHT finished")
	rounds._process(0.25)
	if is_equal_approx(rounds.time_remaining, 40.0):
		failures.append("round timer did not continue after the fighting resume")

	_check_plain_resume(pause, rounds, knockdown, audio, failures)
	_key(pause, KEY_ESCAPE)
	pause.selected = 2
	pause._activate_main()
	if paused:
		failures.append("exit left the tree paused")
	if pause.open:
		failures.append("exit left the pause menu open")

	paused = false
	if failures.is_empty():
		print("SMOKE PASS: pause")
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_plain_resume(pause, rounds, knockdown, audio, failures: Array[String]) -> void:
	rounds.round_state = Rounds.RoundState.ROUND_INTRO
	rounds._intro.elapsed = 0.42
	rounds._intro.running = true
	var voices: int = audio.count_voice_plays
	var fights: int = audio.fight_plays
	_key(pause, KEY_ESCAPE)
	_key(pause, KEY_ESCAPE)
	if paused or pause.counting or audio.count_voice_plays != voices or audio.fight_plays != fights:
		failures.append("round intro resume added a countdown")
	if not is_equal_approx(rounds._intro.elapsed, 0.42):
		failures.append("round intro elapsed reset after pause")

	_fighting(rounds, knockdown)
	rounds.timer_paused = true
	knockdown.match_state = Knockdown.MatchState.PLAYER_DOWN
	knockdown._count_time_remaining = 0.55
	voices = audio.count_voice_plays
	_key(pause, KEY_ESCAPE)
	_key(pause, KEY_ESCAPE)
	if paused or audio.count_voice_plays != voices or audio.fight_plays != fights:
		failures.append("knockdown count resume added a countdown")
	if not is_equal_approx(knockdown._count_time_remaining, 0.55):
		failures.append("knockdown count timer reset after pause")

	knockdown.match_state = Knockdown.MatchState.RESUME_DELAY
	knockdown._resume_time_remaining = 0.35
	knockdown._waiting_for_begin = true
	var begins: int = audio.begin_plays
	_key(pause, KEY_ESCAPE)
	_key(pause, KEY_ESCAPE)
	if paused or audio.begin_plays != begins or audio.fight_plays != fights:
		failures.append("BEGIN resume restarted the announcement")
	if not is_equal_approx(knockdown._resume_time_remaining, 0.35):
		failures.append("resume delay restarted after pause")

	rounds.round_state = Rounds.RoundState.BREAK
	rounds.break_time_remaining = 6.5
	knockdown.match_state = Knockdown.MatchState.FIGHTING
	_key(pause, KEY_ESCAPE)
	_key(pause, KEY_ESCAPE)
	if paused or audio.fight_plays != fights:
		failures.append("break resume added a countdown")
	if not is_equal_approx(rounds.break_time_remaining, 6.5):
		failures.append("break timer reset after pause")

	knockdown.match_state = Knockdown.MatchState.FINAL_KO
	_key(pause, KEY_ESCAPE)
	if pause.open:
		failures.append("final KO opened the pause menu")


func _fighting(rounds, knockdown) -> void:
	rounds.round_state = Rounds.RoundState.FIGHTING
	rounds.timer_paused = false
	knockdown.match_state = Knockdown.MatchState.FIGHTING


func _key(pause, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = keycode
	pause._unhandled_input(key)
