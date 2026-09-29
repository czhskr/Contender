extends Node

## Timed round open before FIGHTING. Announcements do not start the clock.

signal completed(round_number: int)

const ARENA_HOLD := 0.45
const FIGHT_AT := 1.35
const TOTAL := 2.75

var running := false
var elapsed := 0.0

var _round_number := 1
var _showed_round := false
var _showed_fight := false


func start(round_number: int) -> void:
	_round_number = round_number
	elapsed = 0.0
	running = true
	_showed_round = false
	_showed_fight = false
	var banner = _banner()
	if banner != null and banner.has_method("reset"):
		banner.reset()


func cancel() -> void:
	running = false
	var banner = _banner()
	if banner != null and banner.has_method("reset"):
		banner.reset()


func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	if elapsed >= ARENA_HOLD and not _showed_round:
		_showed_round = true
		var banner = _banner()
		if banner != null:
			banner.play_round(_round_number)
	if elapsed >= FIGHT_AT and not _showed_fight:
		_showed_fight = true
		var banner = _banner()
		if banner != null:
			banner.play_fight()
	if elapsed >= TOTAL:
		running = false
		completed.emit(_round_number)


func _banner():
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("combat_announcement")
