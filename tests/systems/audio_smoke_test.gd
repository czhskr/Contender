extends SceneTree

## Audio follows existing gameplay signals. It does not retune combat.
## Run: godot --headless --path . -s res://tests/systems/audio_smoke_test.gd

const Settings = preload("res://scripts/match_settings.gd")
const Knockdown = preload("res://scripts/knockdown_manager.gd")
const Rounds = preload("res://scripts/round_manager.gd")
const Offense = preload("res://scripts/player_offense_resolver.gd")
const Defense = preload("res://scripts/player_defense_resolver.gd")
const AttackState = preload("res://scripts/player_attack_state.gd")
const ActionState = preload("res://scripts/player_action_state.gd")
const Meter = preload("res://scripts/knockdown_meter.gd")
const Announcement = preload("res://scripts/combat_announcement.gd")
const RoundIntro = preload("res://scripts/round_intro.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var audio = root.get_node("AudioDirector")
	_check_assets(failures)
	_check_timing_unchanged(failures)
	await _check_title(audio, failures)
	await _check_volumes(audio, failures)
	await _check_combat(audio, failures)
	await _check_result(audio, failures)
	await _check_result_hold(failures)
	Settings.bgm_volume = 1.0
	Settings.sfx_volume = 1.0
	audio.apply_volumes()

	if failures.is_empty():
		print("SMOKE PASS: audio")
		print(
			"CROWD_COUNT_LENGTH %.3f LOOP %s KNOCKDOWN_SFX_LENGTH %.3f"
			% [audio.crowd_count_length, audio.crowd_count_loops, audio.knockdown_sfx_length]
		)
		quit(0)
	else:
		print("SMOKE FAIL:")
		for failure in failures:
			print(" - %s" % failure)
		quit(1)


func _check_assets(failures: Array[String]) -> void:
	var paths: Array[String] = [
		"res://assets/audio/ambience/ambience_crowd_cheer.mp3",
		"res://assets/audio/ambience/ambience_crowd_count.mp3",
		"res://assets/audio/ambience/ambience_crowd_loop.mp3",
		"res://assets/audio/ambience/ambience_crowd_round_intro.mp3",
		"res://assets/audio/bgm/bgm_result.mp3",
		"res://assets/audio/bgm/bgm_title.mp3",
		"res://assets/audio/sfx/sfx_block.mp3",
		"res://assets/audio/sfx/sfx_hit_01.mp3",
		"res://assets/audio/sfx/sfx_hit_02.mp3",
		"res://assets/audio/sfx/sfx_knockdown.mp3",
		"res://assets/audio/sfx/sfx_ui_button.mp3",
		"res://assets/audio/voice/voice_begin.mp3",
		"res://assets/audio/voice/voice_fight.mp3",
		"res://assets/audio/voice/voice_ko.mp3",
	]
	for count in range(1, 11):
		paths.append("res://assets/audio/voice/voice_count_%02d.mp3" % count)
	for path in paths:
		if not FileAccess.file_exists(path):
			failures.append("missing %s" % path)
	if AudioServer.get_bus_index("BGM") < 0 or AudioServer.get_bus_index("SFX") < 0 or AudioServer.get_bus_index("Voice") < 0:
		failures.append("audio buses missing")


func _check_timing_unchanged(failures: Array[String]) -> void:
	var knockdown = Knockdown.new()
	var intro = RoundIntro.new()
	var banner = Announcement.new()
	if not is_equal_approx(knockdown.count_interval, 1.0):
		failures.append("count interval changed")
	if not is_equal_approx(knockdown.resume_delay_seconds, 2.0):
		failures.append("resume delay changed")
	if not is_equal_approx(intro.TOTAL, 2.75) or not is_equal_approx(intro.FIGHT_AT, 1.35):
		failures.append("round intro timing changed")
	if not is_equal_approx(banner.light_pass_length(), 0.72):
		failures.append("BEGIN length changed")
	var finisher = load("res://scripts/finisher_impact_freeze.gd").new()
	if not is_equal_approx(finisher.finisher_freeze_duration, 2.0):
		failures.append("finisher freeze changed")
	var combat = load("res://scripts/combat_prototype.gd")
	if not is_equal_approx(combat.RESULT_PRESENTATION_SECONDS, 3.0):
		failures.append("result presentation is not 5 seconds")


func _check_title(audio, failures: Array[String]) -> void:
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	if not audio._bgm.playing or audio.bgm_id != "title" or audio.title_plays != 1:
		failures.append("title BGM did not start when the title scene entered")
	var started: int = audio.title_plays
	title.play_intro()
	await process_frame
	if not title.is_intro_running() or not audio._bgm.playing or audio.title_plays != started:
		failures.append("title BGM did not stay through the logo intro")
	var stream = audio._bgm.stream as AudioStreamMP3
	if stream == null or stream.loop:
		failures.append("title BGM loops")
	title.queue_free()
	await process_frame
	if audio._bgm.playing:
		failures.append("title BGM stayed after leaving title")


func _check_volumes(audio, failures: Array[String]) -> void:
	Settings.bgm_volume = 0.0
	Settings.sfx_volume = 1.0
	await process_frame
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("BGM")):
		failures.append("BGM 0 did not mute")
	if AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")):
		failures.append("SFX muted with only BGM at 0")
	Settings.sfx_volume = 0.0
	await process_frame
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) or not AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")):
		failures.append("SFX 0 did not mute SFX and Voice")
	Settings.bgm_volume = 0.5
	Settings.sfx_volume = 0.25
	await process_frame
	var bgm_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM"))
	var sfx_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	var voice_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice"))
	if AudioServer.is_bus_mute(AudioServer.get_bus_index("BGM")) or not is_equal_approx(bgm_db, linear_to_db(0.5)):
		failures.append("BGM slider did not reach the BGM bus")
	if not is_equal_approx(sfx_db, linear_to_db(0.25)) or not is_equal_approx(voice_db, sfx_db):
		failures.append("SFX slider did not drive SFX and Voice")
	Settings.bgm_volume = 1.0
	Settings.sfx_volume = 1.0
	await process_frame
	if not is_equal_approx(Settings.bgm_volume, 1.0) or not is_equal_approx(Settings.sfx_volume, 1.0):
		failures.append("volume setting was not kept")


func _check_combat(audio, failures: Array[String]) -> void:
	var host := Knockdown.new()
	var rounds := Rounds.new()
	rounds.auto_start = false
	rounds.knockdown_manager = host
	rounds.print_events = false
	var attack := AttackState.new()
	var action := ActionState.new()
	action.attack_state = attack
	var meter := Meter.new()
	var offense := Offense.new()
	offense.player_attack_state = attack
	offense.opponent_knockdown_meter = meter
	offense.print_hit_results = false
	var defense := Defense.new()
	defense.player_action_state = action
	defense.player_knockdown_meter = meter
	defense.print_hit_results = false
	var banner := Announcement.new()
	root.add_child(host)
	root.add_child(rounds)
	root.add_child(attack)
	root.add_child(action)
	root.add_child(meter)
	root.add_child(offense)
	root.add_child(defense)
	root.add_child(banner)
	await process_frame

	var knockdown := Knockdown.new()
	knockdown.print_events = false
	root.add_child(knockdown)
	rounds.round_state_changed.emit(Rounds.RoundState.ROUND_INTRO)
	await process_frame
	if not audio._crowd_loop.playing:
		failures.append("crowd loop did not start")
	var loop_stream = audio._crowd_loop.stream as AudioStreamMP3
	if loop_stream == null or not loop_stream.loop:
		failures.append("crowd loop is not looping")
	if not audio._crowd_intro.playing:
		failures.append("round intro crowd did not play")
	var intro_stream = audio._crowd_intro.stream as AudioStreamMP3
	if intro_stream != null and intro_stream.loop:
		failures.append("round intro crowd loops")

	var fights_before: int = audio.fight_plays
	banner.play_fight()
	if audio.fight_plays != fights_before + 1 or audio.voice_path != audio.VOICE_FIGHT:
		failures.append("FIGHT did not play voice_fight once")
	if audio.last_sfx_path != audio.BELL:
		failures.append("FIGHT did not play the round bell")

	seed(1)
	var seen := {}
	for _i in 40:
		seen[audio.choose_hit_path()] = true
	if not seen.has(audio.HIT_01) or not seen.has(audio.HIT_02):
		failures.append("hit pool did not choose both clips")
	var sfx_before: int = audio.sfx_plays
	var first_slot: int = audio._sfx_next
	offense.attack_hit.emit(0, 8.0, 8.0, false, Offense.ResolveResult.HIT)
	offense.attack_hit.emit(1, 10.0, 18.0, false, Offense.ResolveResult.HIT)
	if audio.sfx_plays != sfx_before + 2:
		failures.append("two HIT resolutions did not play two SFX")
	if not audio._sfx[first_slot].playing:
		failures.append("the second HIT cut the first HIT")
	var evade_before: int = audio.sfx_plays
	offense.attack_hit.emit(0, 0.0, 0.0, false, Offense.ResolveResult.EVADE)
	defense.attack_resolved.emit(Defense.DefenseResult.EVADE, 0.0, 0.0, false)
	if audio.sfx_plays != evade_before:
		failures.append("EVADE played a hit or block sound")
	defense.attack_resolved.emit(Defense.DefenseResult.BLOCK, 2.0, 2.0, false)
	offense.attack_hit.emit(0, 2.0, 2.0, false, Offense.ResolveResult.BLOCK)
	if audio.last_sfx_path != audio.BLOCK or audio.sfx_plays != evade_before + 2:
		failures.append("BLOCK did not play once per resolution")

	var kd_before: int = audio.knockdown_plays
	var counts_before: int = audio.count_voice_plays
	var hit_slot: int = audio._sfx_next
	offense.attack_hit.emit(0, 8.0, 300.0, true, Offense.ResolveResult.HIT)
	knockdown.knockdown_confirmed.emit()
	if audio.knockdown_plays != kd_before + 1 or not audio._knock.playing:
		failures.append("knockdown confirmation did not play knockdown SFX")
	if not audio._sfx[hit_slot].playing:
		failures.append("knockdown SFX cut the clean HIT")
	var cheers_before: int = audio.cheer_plays
	knockdown.match_state_changed.emit(Knockdown.MatchState.DOUBLE_DOWN)
	if audio.knockdown_plays != kd_before + 1:
		failures.append("down state played another knockdown SFX")
	if not audio._crowd_count.playing or not audio._crowd_loop.playing:
		failures.append("crowd count did not layer over the loop")
	if not audio._crowd_cheer.playing or audio.cheer_plays != cheers_before + 1:
		failures.append("count start did not play one crowd cheer")
	var cheers_at_count: int = audio.cheer_plays
	knockdown.count_changed.emit(1, Knockdown.DownedSide.BOTH)
	knockdown.count_changed.emit(7, Knockdown.DownedSide.BOTH)
	if audio.count_voice_plays != counts_before + 2:
		failures.append("count voice played more than once per count")
	if audio.count_voice_path != "res://assets/audio/voice/voice_count_07.mp3":
		failures.append("count 7 did not use voice_count_07")
	knockdown.count_changed.emit(10, Knockdown.DownedSide.BOTH)
	if not audio.count_voice_path.ends_with("voice_count_10.mp3"):
		failures.append("count 10 voice mismatch")
	audio._knock.finished.emit()
	if audio.cheer_plays != cheers_at_count:
		failures.append("knockdown SFX finished started another cheer")
	var cheer_stream = audio._crowd_cheer.stream as AudioStreamMP3
	if cheer_stream != null and cheer_stream.loop:
		failures.append("crowd cheer loops")
	knockdown.fighter_stood.emit(Knockdown.DownedSide.PLAYER, 4)
	if not audio._crowd_count.playing:
		failures.append("one fighter standing stopped the shared count")
	knockdown.recovered.emit(Knockdown.DownedSide.BOTH, 4)
	if audio._crowd_count.playing:
		failures.append("recovery left crowd count playing")
	if not audio._crowd_cheer.playing or audio.carry_final_cheer:
		failures.append("recovery cheer was marked as the final match cheer")
	var begins_before: int = audio.begin_plays
	banner.play_begin()
	if audio.begin_plays != begins_before + 1 or audio.voice_path != audio.VOICE_BEGIN:
		failures.append("BEGIN did not play voice_begin once")

	knockdown.match_state_changed.emit(Knockdown.MatchState.PLAYER_DOWN)
	var ko_before: int = audio.ko_plays
	knockdown.match_finished.emit(Knockdown.Winner.OPPONENT)
	if audio._crowd_count.playing:
		failures.append("final KO left crowd count playing")
	if audio.ko_plays != ko_before + 1 or audio.voice_path != audio.VOICE_KO or not audio._crowd_cheer.playing or not audio.carry_final_cheer:
		failures.append("final KO did not play voice_ko and the final crowd cheer")
	audio.stop_match_audio()
	if not audio._crowd_cheer.playing or not audio.carry_final_cheer:
		failures.append("match cleanup cut the final crowd cheer")
	if audio._crowd_loop.playing or audio._crowd_count.playing or audio._voice.playing or audio._knock.playing:
		failures.append("match cleanup left stale combat audio")

	knockdown.match_state_changed.emit(Knockdown.MatchState.DOUBLE_DOWN)
	var void_ko: int = audio.ko_plays
	var void_counts: int = audio.count_voice_plays
	knockdown.count_changed.emit(10, Knockdown.DownedSide.BOTH)
	knockdown.round_voided.emit()
	if audio.ko_plays != void_ko:
		failures.append("double KO played voice_ko")
	if audio.count_voice_plays != void_counts + 1:
		failures.append("double KO duplicated the count voice")
	if audio._crowd_count.playing:
		failures.append("double KO left crowd count playing")
	if audio._crowd_loop.playing:
		failures.append("double KO restarted the crowd loop after cleanup")

	rounds.queue_free()
	await process_frame
	if audio._crowd_loop.playing or audio._crowd_count.playing or audio._crowd_intro.playing:
		failures.append("leaving the match left crowd audio playing")
	banner.queue_free()
	offense.queue_free()
	defense.queue_free()
	action.queue_free()
	attack.queue_free()
	meter.queue_free()
	knockdown.queue_free()
	host.queue_free()
	await process_frame


func _check_result(audio, failures: Array[String]) -> void:
	audio._start_crowd_loop()
	var cheer_before: bool = audio._crowd_cheer.playing
	var result = load("res://scenes/result.tscn").instantiate()
	root.add_child(result)
	await process_frame
	if audio.bgm_id != "result" or not audio._bgm.playing:
		failures.append("result BGM did not start")
	var stream = audio._bgm.stream as AudioStreamMP3
	if stream == null or stream.loop:
		failures.append("result BGM loops")
	if cheer_before and not audio._crowd_cheer.playing:
		failures.append("result cut the final crowd cheer")
	if cheer_before and not audio._bgm.playing:
		failures.append("final cheer did not overlap result BGM")
	if audio._crowd_loop.playing or audio._crowd_count.playing or audio._voice.playing:
		failures.append("match audio leaked into the result")
	var kept_bgm := Settings.bgm_volume
	var kept_sfx := Settings.sfx_volume
	result.queue_free()
	await process_frame
	if audio._bgm.playing:
		failures.append("result BGM stayed after leaving the result")
	if audio._crowd_cheer.playing:
		failures.append("leaving the result kept the final crowd cheer")
	if not is_equal_approx(Settings.bgm_volume, kept_bgm) or not is_equal_approx(Settings.sfx_volume, kept_sfx):
		failures.append("scene change cleared the volume settings")


func _check_result_hold(failures: Array[String]) -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	game.get_node("RoundManager").auto_start = false
	root.add_child(game)
	await process_frame
	var banner = game.get_node("CombatHUD/CombatAnnouncement")
	banner.play_knockout()
	var result = MatchResultData.new()
	result.result_type = MatchResultData.ResultType.KO
	var started := Time.get_ticks_msec()
	game._queue_result_scene(result)
	await create_timer(2.6).timeout
	if game._result_sent:
		failures.append("KO result opened before 3 seconds")
	await create_timer(0.7).timeout
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	if not game._result_sent:
		failures.append("KO result did not open after the 3 second presentation")
	elif elapsed < 3.0 or elapsed > 3.8:
		failures.append("KO result opened at %.2f seconds" % elapsed)
	banner.play_decision()
	var decision = MatchResultData.new()
	decision.result_type = MatchResultData.ResultType.DECISION
	game._result_sent = false
	game._queue_result_scene(decision)
	if game._result_sent or not is_equal_approx(game.RESULT_PRESENTATION_SECONDS, 3.0):
		failures.append("decision does not use the same 5 second presentation")
	game.free()
