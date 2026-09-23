class_name CombatVisualRoot
extends Node2D

## Fight visuals root. HUD stays outside — only this subtree shakes / parallaxes.

const ActionStateType = preload("res://scripts/player_action_state.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")

@export var viewport_size := Vector2(1152, 648)

@export_group("Wired Nodes")
@export var background_visual: Node2D
@export var opponent_visual: Node2D
@export var player_visual: Node2D
@export var player_action_state: ActionStateType
@export var offense_resolver: OffenseResolverType
@export var defense_resolver: DefenseResolverType
@export var knockdown_manager: KnockdownManagerType

@export_group("World Parallax (Slip)")
## Closer layers move more. Slip Left → world +X; Slip Right → world -X.
@export_range(0.0, 200.0, 1.0, "or_greater") var parallax_crowd_x := 6.0
@export_range(0.0, 200.0, 1.0, "or_greater") var parallax_ring_x := 14.0
@export_range(0.0, 200.0, 1.0, "or_greater") var parallax_opponent_x := 24.0
@export_range(0.01, 1.0, 0.01, "or_greater") var parallax_tween_seconds := 0.10

@export_group("Hit Shake")
@export_range(0.0, 64.0, 0.5, "or_greater") var opponent_hit_shake_strength := 3.0
@export_range(0.01, 1.0, 0.01, "or_greater") var opponent_hit_shake_duration := 0.10
@export_range(0.0, 64.0, 0.5, "or_greater") var player_hit_shake_strength := 7.0
@export_range(0.01, 1.0, 0.01, "or_greater") var player_hit_shake_duration := 0.15

var base_position := Vector2.ZERO
var shake_offset := Vector2.ZERO

var _parallax_tween: Tween
var _shake_tween: Tween
var _shake_token := 0


func _ready() -> void:
	base_position = position
	_resolve_wired_nodes()
	_apply_composed_position()

	if player_action_state != null:
		player_action_state.state_changed.connect(_on_player_action_state_changed)
	if offense_resolver != null:
		offense_resolver.attack_hit.connect(_on_player_attack_hit)
	if defense_resolver != null:
		defense_resolver.attack_resolved.connect(_on_opponent_attack_resolved)
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_match_state_changed)


func _resolve_wired_nodes() -> void:
	if background_visual == null:
		background_visual = get_node_or_null("BackgroundVisual")
	if opponent_visual == null:
		opponent_visual = get_node_or_null("OpponentVisual")
	if player_visual == null:
		player_visual = get_node_or_null("PlayerVisual")


func set_shake_offset(offset: Vector2) -> void:
	shake_offset = offset
	_apply_composed_position()


func _apply_composed_position() -> void:
	position = base_position + shake_offset


func _on_player_action_state_changed(state: int) -> void:
	match state:
		ActionStateType.PlayerState.SLIP_LEFT:
			_tween_world_parallax(1.0)
		ActionStateType.PlayerState.SLIP_RIGHT:
			_tween_world_parallax(-1.0)
		_:
			_tween_world_parallax(0.0)


func _tween_world_parallax(direction: float) -> void:
	## direction: +1 Slip Left (world +X), -1 Slip Right (world -X), 0 = home.
	if _parallax_tween != null and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = null

	var crowd_target := Vector2(parallax_crowd_x * direction, 0.0)
	var ring_target := Vector2(parallax_ring_x * direction, 0.0)
	var opp_target := Vector2(parallax_opponent_x * direction, 0.0)

	var crowd_from := Vector2.ZERO
	var ring_from := Vector2.ZERO
	var opp_from := Vector2.ZERO
	if background_visual != null:
		crowd_from = background_visual.crowd_parallax_offset
		ring_from = background_visual.ring_parallax_offset
	if opponent_visual != null and "parallax_offset" in opponent_visual:
		opp_from = opponent_visual.parallax_offset

	_parallax_tween = create_tween()
	_parallax_tween.set_parallel(true)
	_parallax_tween.set_ease(Tween.EASE_IN_OUT)
	_parallax_tween.set_trans(Tween.TRANS_SINE)
	var dur := maxf(parallax_tween_seconds, 0.01)

	if background_visual != null:
		_parallax_tween.tween_method(
			func(v: Vector2) -> void:
				if background_visual != null and background_visual.has_method("set_crowd_parallax"):
					background_visual.set_crowd_parallax(v),
			crowd_from,
			crowd_target,
			dur
		)
		_parallax_tween.tween_method(
			func(v: Vector2) -> void:
				if background_visual != null and background_visual.has_method("set_ring_parallax"):
					background_visual.set_ring_parallax(v),
			ring_from,
			ring_target,
			dur
		)
	if opponent_visual != null and opponent_visual.has_method("set_parallax_offset"):
		_parallax_tween.tween_method(
			func(v: Vector2) -> void:
				if opponent_visual != null and opponent_visual.has_method("set_parallax_offset"):
					opponent_visual.set_parallax_offset(v),
			opp_from,
			opp_target,
			dur
		)


func _reset_world_parallax_immediate() -> void:
	if _parallax_tween != null and _parallax_tween.is_valid():
		_parallax_tween.kill()
	_parallax_tween = null
	if background_visual != null:
		if background_visual.has_method("set_crowd_parallax"):
			background_visual.set_crowd_parallax(Vector2.ZERO)
		if background_visual.has_method("set_ring_parallax"):
			background_visual.set_ring_parallax(Vector2.ZERO)
	if opponent_visual != null and opponent_visual.has_method("set_parallax_offset"):
		opponent_visual.set_parallax_offset(Vector2.ZERO)


func _on_player_attack_hit(
	_attack: int,
	_knockdown_damage: float,
	_opponent_meter: float,
	was_knockdown: bool,
	result: int
) -> void:
	if was_knockdown:
		_clear_shake()
		return
	if result != OffenseResolverType.ResolveResult.HIT:
		return
	_play_shake(opponent_hit_shake_strength, opponent_hit_shake_duration)


func _on_opponent_attack_resolved(
	result: int,
	_knockdown_damage: float,
	_player_meter: float,
	was_knockdown: bool
) -> void:
	if was_knockdown:
		_clear_shake()
		return
	if result != DefenseResolverType.DefenseResult.HIT:
		return
	_play_shake(player_hit_shake_strength, player_hit_shake_duration)


func _on_match_state_changed(state: int) -> void:
	if (
		state == KnockdownManagerType.MatchState.PLAYER_DOWN
		or state == KnockdownManagerType.MatchState.OPPONENT_DOWN
		or state == KnockdownManagerType.MatchState.FINAL_KO
	):
		_clear_shake()
		_reset_world_parallax_immediate()
	elif state == KnockdownManagerType.MatchState.FIGHTING:
		_clear_shake()
		_reset_world_parallax_immediate()


func _play_shake(strength: float, duration: float) -> void:
	## Replace any in-flight shake so offsets never accumulate.
	_shake_token += 1
	var token := _shake_token
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	set_shake_offset(Vector2.ZERO)

	if strength <= 0.0 or duration <= 0.0:
		return

	_shake_tween = create_tween()
	var steps := 5
	var step_dur := maxf(duration / float(steps), 0.01)
	for i in range(steps):
		var mag := strength * (1.0 - float(i) / float(steps))
		var peak := Vector2(
			randf_range(-mag, mag),
			randf_range(-mag * 0.6, mag * 0.6)
		)
		var captured_peak := peak
		_shake_tween.tween_method(
			func(v: Vector2) -> void:
				if token == _shake_token:
					set_shake_offset(v),
			Vector2.ZERO,
			captured_peak,
			step_dur * 0.45
		)
		_shake_tween.tween_method(
			func(v: Vector2) -> void:
				if token == _shake_token:
					set_shake_offset(v),
			captured_peak,
			Vector2.ZERO,
			step_dur * 0.55
		)
	_shake_tween.finished.connect(
		func() -> void:
			if token == _shake_token:
				set_shake_offset(Vector2.ZERO)
	)


func _clear_shake() -> void:
	_shake_token += 1
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	set_shake_offset(Vector2.ZERO)
