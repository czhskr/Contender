extends Node

## Presentation audio. Gameplay state stays the source of truth.

const Settings = preload("res://scripts/match_settings.gd")
const Offense = preload("res://scripts/player_offense_resolver.gd")
const Defense = preload("res://scripts/player_defense_resolver.gd")
const Rounds = preload("res://scripts/round_manager.gd")
const Knockdown = preload("res://scripts/knockdown_manager.gd")

const TITLE_BGM := "res://assets/audio/bgm/bgm_title.mp3"
const RESULT_BGM := "res://assets/audio/bgm/bgm_result.mp3"
const CROWD_LOOP := "res://assets/audio/ambience/ambience_crowd_loop.mp3"
const CROWD_INTRO := "res://assets/audio/ambience/ambience_crowd_round_intro.mp3"
const CROWD_CHEER := "res://assets/audio/ambience/ambience_crowd_cheer.mp3"
const CROWD_COUNT := "res://assets/audio/ambience/ambience_crowd_count.mp3"
const HIT_01 := "res://assets/audio/sfx/sfx_hit_01.mp3"
const HIT_02 := "res://assets/audio/sfx/sfx_hit_02.mp3"
const BLOCK := "res://assets/audio/sfx/sfx_block.mp3"
const KNOCKDOWN_SFX := "res://assets/audio/sfx/sfx_knockdown.mp3"
const BELL := "res://assets/audio/sfx/sfx_round_bell.mp3"
const UI_HOVER := "res://assets/audio/sfx/sfx_ui_button.mp3"
const VOICE_FIGHT := "res://assets/audio/voice/voice_fight.mp3"
const VOICE_BEGIN := "res://assets/audio/voice/voice_begin.mp3"
const VOICE_KO := "res://assets/audio/voice/voice_ko.mp3"

const SFX_POOL_SIZE := 4
const FULL_COUNT_SECONDS := 12.0

var bgm_id := ""
var voice_path := ""
var count_voice_path := ""
var last_sfx_path := ""
var crowd_count_length := 0.0
var crowd_count_loops := false
var sfx_plays := 0
var knockdown_plays := 0
var count_voice_plays := 0
var fight_plays := 0
var begin_plays := 0
var ko_plays := 0
var title_plays := 0
var carry_final_cheer := false
var cheer_plays := 0
var hover_plays := 0
var bell_plays := 0
var knockdown_sfx_length := 0.0

var _bgm: AudioStreamPlayer
var _crowd_loop: AudioStreamPlayer
var _crowd_intro: AudioStreamPlayer
var _crowd_cheer: AudioStreamPlayer
var _crowd_count: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _count_voice: AudioStreamPlayer
var _knock: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _streams := {}
var _bound := {}
var _cheer_after_knockdown := false
var _applied_bgm := -1.0
var _applied_sfx := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_bgm = _player("Bgm", "BGM")
	_crowd_loop = _player("CrowdLoop", "BGM")
	_crowd_intro = _player("CrowdIntro", "BGM")
	_crowd_cheer = _player("CrowdCheer", "BGM")
	_crowd_count = _player("CrowdCount", "BGM")
	_voice = _player("Voice", "Voice")
	_count_voice = _player("CountVoice", "Voice")
	_knock = _player("Knockdown", "SFX")
	_ui = _player("UiHover", "SFX")
	_crowd_cheer.finished.connect(_on_cheer_finished)
	for index in SFX_POOL_SIZE:
		_sfx.append(_player("Sfx%d" % index, "SFX"))
	get_tree().node_added.connect(_consider)
	_scan(get_tree().root)
	apply_volumes()


func _process(_delta: float) -> void:
	if not is_equal_approx(_applied_bgm, Settings.bgm_volume) or not is_equal_approx(_applied_sfx, Settings.sfx_volume):
		apply_volumes()


func apply_volumes() -> void:
	_apply_bus("BGM", Settings.bgm_volume)
	_apply_bus("SFX", Settings.sfx_volume)
	_apply_bus("Voice", Settings.sfx_volume)
	_applied_bgm = Settings.bgm_volume
	_applied_sfx = Settings.sfx_volume


func play_ui_hover() -> void:
	hover_plays += 1
	_play_one_shot(_ui, UI_HOVER, "SFX")


func play_resume_count(count: int) -> void:
	_on_count(count, 0)


func suspend_gameplay_audio() -> void:
	for player in _gameplay_one_shots():
		if player.playing:
			player.stream_paused = true


func resume_gameplay_audio() -> void:
	for player in _gameplay_one_shots():
		player.stream_paused = false


func _gameplay_one_shots() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = [
		_voice, _count_voice, _knock, _crowd_intro, _crowd_count, _crowd_cheer,
	]
	for player in _sfx:
		players.append(player)
	return players


func choose_hit_path() -> String:
	if randi() % 2 == 0:
		return HIT_01
	return HIT_02


func abandon_match_audio() -> void:
	carry_final_cheer = false
	resume_gameplay_audio()
	stop_match_audio()


func stop_match_audio() -> void:
	_cheer_after_knockdown = false
	var keep_final_cheer := carry_final_cheer and _crowd_cheer.playing
	_crowd_loop.stop()
	_crowd_intro.stop()
	if not keep_final_cheer:
		carry_final_cheer = false
		_crowd_cheer.stop()
	_crowd_count.stop()
	_voice.stop()
	_count_voice.stop()
	_knock.stop()
	for player in _sfx:
		player.stop()


func _ensure_buses() -> void:
	for bus_name in ["BGM", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _apply_bus(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	if linear <= 0.0:
		AudioServer.set_bus_mute(index, true)
		return
	AudioServer.set_bus_mute(index, false)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0001, 1.0)))


func _player(node_name: String, bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	add_child(player)
	return player


func _scan(node: Node) -> void:
	_consider(node)
	for child in node.get_children():
		_scan(child)


func _consider(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _bound.has(id):
		return
	var script_path := ""
	var attached = node.get_script()
	if attached != null:
		script_path = str(attached.resource_path)
	var bound := true
	match script_path:
		"res://scripts/title_menu.gd":
			node.tree_exiting.connect(_on_title_exiting)
			_play_title_bgm()
		"res://scripts/round_manager.gd":
			node.round_state_changed.connect(_on_round_state)
			node.tree_exiting.connect(_on_match_node_exiting)
		"res://scripts/knockdown_manager.gd":
			node.match_state_changed.connect(_on_match_state)
			node.knockdown_confirmed.connect(_on_knockdown_confirmed)
			node.count_changed.connect(_on_count)
			node.recovered.connect(_on_recovered)
			node.match_finished.connect(_on_match_finished)
			node.round_voided.connect(_on_round_voided)
		"res://scripts/player_offense_resolver.gd":
			node.attack_hit.connect(_on_player_attack)
		"res://scripts/player_defense_resolver.gd":
			node.attack_resolved.connect(_on_opponent_attack)
		"res://scripts/combat_announcement.gd":
			node.presentation_started.connect(_on_presentation.bind(node))
		"res://scripts/result_screen.gd":
			node.tree_exiting.connect(_on_result_exiting)
			_enter_result()
		_:
			bound = false
	if bound:
		_bound[id] = true


func _play_title_bgm() -> void:
	title_plays += 1
	_play_bgm(TITLE_BGM, "title")


func _on_title_exiting() -> void:
	if bgm_id == "title":
		_bgm.stop()
		bgm_id = ""


func _on_round_state(state: int) -> void:
	if state == Rounds.RoundState.TRAIT_PREVIEW or state == Rounds.RoundState.ROUND_INTRO or state == Rounds.RoundState.FIGHTING:
		_start_crowd_loop()
	if state == Rounds.RoundState.ROUND_INTRO:
		_play_one_shot(_crowd_intro, CROWD_INTRO, "BGM")


func _on_match_state(state: int) -> void:
	if (
		state == Knockdown.MatchState.PLAYER_DOWN
		or state == Knockdown.MatchState.OPPONENT_DOWN
		or state == Knockdown.MatchState.DOUBLE_DOWN
	):
		_start_crowd_count()
		_play_crowd_cheer(false)


func _on_knockdown_confirmed() -> void:
	_play_knockdown_sfx()


func _on_count(count: int, _side: int) -> void:
	if count < 1 or count > 10:
		return
	var path := "res://assets/audio/voice/voice_count_%02d.mp3" % count
	count_voice_plays += 1
	count_voice_path = path
	_play_one_shot(_count_voice, path, "Voice")


func _on_recovered(_side: int, _at_count: int) -> void:
	_stop_crowd_count()
	_play_crowd_cheer(false)


func _on_match_finished(_winner: int) -> void:
	ko_plays += 1
	_cheer_after_knockdown = false
	_stop_crowd_count()
	_play_voice(VOICE_KO)
	_play_crowd_cheer(true)


func _on_round_voided() -> void:
	_cheer_after_knockdown = false
	_stop_crowd_count()


func _on_player_attack(_attack: int, _damage: float, _meter: float, _was_knockdown: bool, result: int) -> void:
	_on_resolve(result, true)


func _on_opponent_attack(result: int, _damage: float, _meter: float, _was_knockdown: bool) -> void:
	_on_resolve(result, false)


func _on_resolve(result: int, player_attack: bool) -> void:
	var hit: int = Offense.ResolveResult.HIT if player_attack else Defense.DefenseResult.HIT
	var block: int = Offense.ResolveResult.BLOCK if player_attack else Defense.DefenseResult.BLOCK
	if result == hit:
		_play_sfx(choose_hit_path())
	elif result == block:
		_play_sfx(BLOCK)


func _on_presentation(text: String, banner: Node) -> void:
	if text == "FIGHT":
		fight_plays += 1
		_play_voice(VOICE_FIGHT)
		if bool(banner.get("ring_bell_for_fight")):
			bell_plays += 1
			_play_sfx(BELL)
	elif text == "BEGIN":
		begin_plays += 1
		_play_voice(VOICE_BEGIN)


func _on_cheer_finished() -> void:
	carry_final_cheer = false


func _on_match_node_exiting() -> void:
	stop_match_audio()


func _enter_result() -> void:
	stop_match_audio()
	_play_bgm(RESULT_BGM, "result")


func _on_result_exiting() -> void:
	carry_final_cheer = false
	_crowd_cheer.stop()
	if bgm_id == "result":
		_bgm.stop()
		bgm_id = ""


func _play_bgm(path: String, id: String) -> void:
	_play_one_shot(_bgm, path, "BGM")
	bgm_id = id


func _play_voice(path: String) -> void:
	voice_path = path
	_play_one_shot(_voice, path, "Voice")


func _play_knockdown_sfx() -> void:
	knockdown_plays += 1
	_play_one_shot(_knock, KNOCKDOWN_SFX, "SFX")
	if _knock.stream != null:
		knockdown_sfx_length = _knock.stream.get_length()


func _play_crowd_cheer(final_match: bool) -> void:
	cheer_plays += 1
	if final_match:
		carry_final_cheer = true
	_play_one_shot(_crowd_cheer, CROWD_CHEER, "BGM")


func _play_sfx(path: String) -> void:
	sfx_plays += 1
	last_sfx_path = path
	var player := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	_play_one_shot(player, path, "SFX")


func _start_crowd_loop() -> void:
	if _crowd_loop.playing:
		return
	var stream := _prepared(CROWD_LOOP, true)
	_crowd_loop.bus = "BGM"
	_crowd_loop.stream = stream
	_crowd_loop.play()


func _start_crowd_count() -> void:
	if _crowd_count.playing:
		return
	var stream := _prepared(CROWD_COUNT, false)
	crowd_count_length = stream.get_length()
	crowd_count_loops = crowd_count_length <= 0.0 or crowd_count_length < FULL_COUNT_SECONDS
	stream.loop = crowd_count_loops
	_crowd_count.bus = "BGM"
	_crowd_count.stream = stream
	_crowd_count.play()


func _stop_crowd_count() -> void:
	_crowd_count.stop()


func _play_one_shot(player: AudioStreamPlayer, path: String, bus_name: String) -> void:
	player.bus = bus_name
	player.stream = _prepared(path, false)
	player.play()


func _prepared(path: String, looping: bool) -> AudioStreamMP3:
	if not _streams.has(path):
		_streams[path] = load(path)
	var stream := _streams[path] as AudioStreamMP3
	stream.loop = looping
	return stream
