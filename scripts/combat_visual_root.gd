class_name CombatVisualRoot
extends Node2D

## Fight visuals root. HUD stays outside — only this subtree shakes / parallaxes.
## Continuous Evade: world parallax tracks PlayerEvade movement target (no slip recovery).

const ActionStateType = preload("res://scripts/player_action_state.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")
const PlayerEvadeType = preload("res://scripts/player_evade.gd")
const DisplayLayout = preload("res://scripts/visual_display_layout.gd")
const MatchSettings = preload("res://scripts/match_settings.gd")

@export var viewport_size := Vector2(1152, 648)

@export_group("Wired Nodes")
@export var background_visual: Node2D
@export var opponent_visual: Node2D
@export var player_visual: Node2D
@export var player_action_state: ActionStateType
@export var player_evade: PlayerEvadeType
@export var offense_resolver: OffenseResolverType
@export var defense_resolver: DefenseResolverType
@export var knockdown_manager: KnockdownManagerType

@export_group("World Parallax (Horizontal)")
## Closer layers move more. Evade Left → world +X; Evade Right → world -X.
## Stronger than legacy Slip (10/24/48) because Player X translation is locked at 0.
@export_range(0.0, 200.0, 1.0, "or_greater") var parallax_crowd_x := 80.0
@export_range(0.0, 400.0, 1.0, "or_greater") var parallax_ring_x := 160.0
@export_range(0.0, 400.0, 1.0, "or_greater") var parallax_opponent_x := 280.0

@export_group("World Parallax (Down)")
## Explicit S/DOWN look-down. Kept within pass-by stack budget.
@export_range(0.0, 200.0, 1.0, "or_greater") var parallax_crowd_down_y := 10.0
@export_range(0.0, 200.0, 1.0, "or_greater") var parallax_ring_down_y := 22.0
@export_range(0.0, 200.0, 1.0, "or_greater") var parallax_opponent_down_y := 40.0

@export_group("Parallax Motion")
## Shared head-motion SmoothDamp time (velocity continuous across retargets).
@export_range(0.01, 1.0, 0.01, "or_greater") var head_smooth_time := 0.12
## Position-based weave dip near lateral center (-Y = world rises). Depth by layer.
@export_range(0.0, 120.0, 1.0, "or_greater") var weave_depth_opponent := 45.0
@export_range(0.0, 120.0, 1.0, "or_greater") var weave_depth_ring := 22.0
@export_range(0.0, 120.0, 1.0, "or_greater") var weave_depth_crowd := 10.0
## Extra pixels beyond max parallax/weave so background edges stay off-screen.
@export_range(0.0, 64.0, 1.0, "or_greater") var background_overscan_safety := 4.0

@export_group("Hit Shake")
## Presentation only. Damage, stamina, and resolution stay on the resolvers.
## Opponent values fire when the player lands. Player values fire when the player is hit.
@export_range(0.0, 64.0, 0.5, "or_greater") var opponent_hit_shake_strength := 5.0
@export_range(0.01, 1.0, 0.01, "or_greater") var opponent_hit_shake_duration := 0.10
@export_range(0.0, 64.0, 0.5, "or_greater") var player_hit_shake_strength := 12.0
@export_range(0.01, 1.0, 0.01, "or_greater") var player_hit_shake_duration := 0.15
## High Guard BLOCK is the same camera shake, kept under a clean HIT.
const BLOCK_SHAKE_SCALE := 0.65

@export_group("Evade Visual (does not change gameplay evade window)")
## Opponent punch pass-by hold (does NOT lock Player continuous movement).
@export_range(0.0, 2.0, 0.01, "or_greater") var evade_visual_hold_seconds := 0.20
@export_range(0.0, 400.0, 1.0, "or_greater") var evade_passby_offset_x := 40.0
## Modest so DOWN continuous + pass-by does not clip Opponent top (stack ≤ ~80).
@export_range(0.0, 400.0, 1.0, "or_greater") var evade_down_passby_offset_y := 40.0
## Extra lift while a straight texture is showing during a live DOWN window.
## The glove center sits about 90px below the eye line after the existing
## duck parallax and the 40px pass-by. 51px more puts that center just above
## the eye line. It eases in and out; it is not applied in one frame.
@export_range(0.0, 400.0, 1.0, "or_greater") var attack_down_miss_clearance := 51.0
@export_range(0.02, 0.5, 0.01) var attack_down_miss_blend_seconds := 0.12
@export var print_evade_visual := false

var base_position := Vector2.ZERO
var shake_offset := Vector2.ZERO

var _shake_tween: Tween
var _shake_token := 0
var _evade_hold_token := 0
var _passby_active := false

## Composed layer offsets applied to BG / Opponent.
var _crowd_parallax := Vector2.ZERO
var _ring_parallax := Vector2.ZERO
var _opponent_parallax := Vector2.ZERO

## Shared continuous head-motion parameters (-1..+1 lateral, 0..1 down).
## LEFT = +1 (world +X), RIGHT = -1 (world -X). Velocity is NOT reset on retarget.
var _head_lateral := 0.0
var _head_lateral_vel := 0.0
var _head_lateral_target := 0.0
var _head_down := 0.0
var _head_down_vel := 0.0
var _head_down_target := 0.0
## 1 while LEFT/RIGHT dodge is the intent — enables center weave without resting at CENTER dip.
var _weave_blend := 0.0
var _weave_blend_vel := 0.0
var _weave_blend_target := 0.0
var _para_direction := 0

## Finisher Impact Freeze: lock combat motion; keep current pose/offsets.
var _finisher_freeze := false
var _freeze_clear_shake_msec := 0
var _freeze_shake_cleared := true


func _ready() -> void:
	base_position = position
	_resolve_wired_nodes()
	_apply_background_overscan()
	_apply_opponent_down_framing()
	_apply_composed_position()
	set_process(true)

	if player_evade != null and player_evade.has_signal("movement_target_changed"):
		player_evade.movement_target_changed.connect(_on_evade_movement_target_changed)
	elif player_visual != null and player_visual.has_signal("evade_pov_target_changed"):
		player_visual.evade_pov_target_changed.connect(_on_evade_movement_target_changed)

	if offense_resolver != null:
		offense_resolver.attack_hit.connect(_on_player_attack_hit)
	if defense_resolver != null:
		defense_resolver.attack_resolved.connect(_on_opponent_attack_resolved)
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_match_state_changed)


func _process(delta: float) -> void:
	if _finisher_freeze:
		if not _freeze_shake_cleared and Time.get_ticks_msec() >= _freeze_clear_shake_msec:
			_freeze_shake_cleared = true
			_clear_shake()
		return

	_head_lateral = _smooth_damp(
		_head_lateral, _head_lateral_target, 0, head_smooth_time, delta
	)
	_head_down = _smooth_damp(
		_head_down, _head_down_target, 1, head_smooth_time, delta
	)
	_weave_blend = _smooth_damp(
		_weave_blend, _weave_blend_target, 2, head_smooth_time, delta
	)
	_compose_head_parallax()
	_apply_parallax_offsets()


## Freeze combat visuals on finisher (breathing / tween motion). Overlay effects stay separate.
func set_finisher_freeze(active: bool) -> void:
	_finisher_freeze = active
	if active:
		_clear_passby_only()
		if player_visual != null and player_visual.has_method("set_finisher_freeze"):
			player_visual.set_finisher_freeze(true)
		if opponent_visual != null and opponent_visual.has_method("set_finisher_freeze"):
			opponent_visual.set_finisher_freeze(true)
		_freeze_clear_shake_msec = Time.get_ticks_msec() + 120
		_freeze_shake_cleared = false
	else:
		_freeze_shake_cleared = true
		if player_visual != null and player_visual.has_method("set_finisher_freeze"):
			player_visual.set_finisher_freeze(false)
		if opponent_visual != null and opponent_visual.has_method("set_finisher_freeze"):
			opponent_visual.set_finisher_freeze(false)


func _resolve_wired_nodes() -> void:
	if background_visual == null:
		background_visual = get_node_or_null("BackgroundVisual")
	if opponent_visual == null:
		opponent_visual = get_node_or_null("OpponentVisual")
	if player_visual == null:
		player_visual = get_node_or_null("PlayerVisual")
	if player_evade == null:
		player_evade = get_node_or_null("../PlayerEvade") as PlayerEvadeType


func set_shake_offset(offset: Vector2) -> void:
	shake_offset = offset
	_apply_composed_position()


func _apply_composed_position() -> void:
	position = base_position + shake_offset


func _on_evade_movement_target_changed(_target: Vector2, direction: int) -> void:
	if _finisher_freeze:
		return
	## Retarget shared head params — velocities intentionally NOT zeroed.
	_para_direction = direction
	match direction:
		PlayerEvadeType.Direction.LEFT:
			_head_lateral_target = 1.0
			_head_down_target = 1.0
			_weave_blend_target = 0.0
		PlayerEvadeType.Direction.RIGHT:
			_head_lateral_target = -1.0
			_head_down_target = 1.0
			_weave_blend_target = 0.0
		PlayerEvadeType.Direction.DOWN:
			_head_lateral_target = 0.0
			_head_down_target = 1.0
			_weave_blend_target = 0.0
		_:
			_head_lateral_target = 0.0
			_head_down_target = 0.0
			_weave_blend_target = 0.0


func _compose_head_parallax() -> void:
	## Lateral uses the same down channel as S, so settled height matches DOWN.
	## Weave stays off for held A/D. It must not add extra depth on top of down.
	var abs_lat := absf(_head_lateral)
	var weave_factor := (1.0 - abs_lat) * (1.0 - abs_lat) * _weave_blend
	weave_factor *= 1.0 - clampf(_head_down, 0.0, 1.0)

	var hx := _head_lateral
	var down := _head_down
	_crowd_parallax = Vector2(
		hx * parallax_crowd_x,
		-down * parallax_crowd_down_y - weave_factor * weave_depth_crowd
	)
	_ring_parallax = Vector2(
		hx * parallax_ring_x,
		-down * parallax_ring_down_y - weave_factor * weave_depth_ring
	)
	_opponent_parallax = Vector2(
		hx * parallax_opponent_x,
		-down * parallax_opponent_down_y - weave_factor * weave_depth_opponent
	)


## channel: 0=lateral, 1=down, 2=weave_blend
func _smooth_damp(
	current: float,
	target: float,
	channel: int,
	smooth_time: float,
	delta: float
) -> float:
	var velocity := 0.0
	match channel:
		0:
			velocity = _head_lateral_vel
		1:
			velocity = _head_down_vel
		_:
			velocity = _weave_blend_vel

	var st := maxf(smooth_time, 0.0001)
	var omega := 2.0 / st
	var x := omega * delta
	var exp := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (velocity + omega * change) * delta
	var new_vel := (velocity - omega * temp) * exp
	var output := target + (change + temp) * exp
	if (target - current > 0.0) == (output > target):
		output = target
		new_vel = 0.0

	match channel:
		0:
			_head_lateral_vel = new_vel
		1:
			_head_down_vel = new_vel
		_:
			_weave_blend_vel = new_vel
	return output


## Test helper — set absolute head targets without gameplay (smoke).
func _set_parallax_targets_for_direction(direction: int) -> void:
	_on_evade_movement_target_changed(Vector2.ZERO, direction)
	## Snap for unit tests that do not pump frames.
	_head_lateral = _head_lateral_target
	_head_down = _head_down_target
	_weave_blend = _weave_blend_target
	_head_lateral_vel = 0.0
	_head_down_vel = 0.0
	_weave_blend_vel = 0.0
	_compose_head_parallax()


func _apply_parallax_offsets() -> void:
	if background_visual != null:
		if background_visual.has_method("set_crowd_parallax"):
			background_visual.set_crowd_parallax(_crowd_parallax)
		if background_visual.has_method("set_ring_parallax"):
			background_visual.set_ring_parallax(_ring_parallax)
	if opponent_visual != null and opponent_visual.has_method("set_parallax_offset"):
		opponent_visual.set_parallax_offset(_opponent_parallax)


func reset_for_new_round() -> void:
	clear_continuous_evade_presentation()
	if opponent_visual != null and opponent_visual.has_method("reset_for_new_round"):
		opponent_visual.reset_for_new_round()
	if player_visual != null and player_visual.has_method("reset_for_new_round"):
		player_visual.reset_for_new_round()


func clear_continuous_evade_presentation() -> void:
	## Snap; do not leave a SmoothDamp tail into the next round.
	_clear_passby_only()
	_reset_world_parallax_immediate()
	if player_visual != null and player_visual.has_method("reset_evade_visual_immediate"):
		player_visual.reset_evade_visual_immediate()


## Max upward shift of the opponent canvas (negative Y).
## Settled DOWN is parallax 40 + pass-by 40 = 80.
## A LEFT/RIGHT→DOWN transition can still hold full weave (45) when pass-by (-40) starts,
## so the peak is max(DOWN, weave) + pass-by.
func max_opponent_upward_lift() -> float:
	return maxf(parallax_opponent_down_y, weave_depth_opponent) + evade_down_passby_offset_y


func _apply_opponent_down_framing() -> void:
	if opponent_visual == null:
		return
	var lift := max_opponent_upward_lift()
	var canvas_h := DisplayLayout.OPPONENT_SOURCE_CANVAS_SIZE.y * float(opponent_visual.opponent_display_scale)
	## base_y + canvas_h - lift == viewport bottom.
	var base_y := viewport_size.y - canvas_h + lift
	opponent_visual.asset_base_position.y = base_y
	if opponent_visual.has_method("apply_composed_transform"):
		opponent_visual.apply_composed_transform()


func _apply_background_overscan() -> void:
	if background_visual == null or not background_visual.has_method("set_motion_bleed"):
		return
	var safety := maxf(background_overscan_safety, 0.0)
	background_visual.set_motion_bleed(
		Vector2(
			parallax_crowd_x + safety,
			parallax_crowd_down_y + weave_depth_crowd + safety
		),
		Vector2(
			parallax_ring_x + safety,
			parallax_ring_down_y + weave_depth_ring + safety
		)
	)


func _reset_world_parallax_immediate() -> void:
	_head_lateral = 0.0
	_head_lateral_vel = 0.0
	_head_lateral_target = 0.0
	_head_down = 0.0
	_head_down_vel = 0.0
	_head_down_target = 0.0
	_weave_blend = 0.0
	_weave_blend_vel = 0.0
	_weave_blend_target = 0.0
	_para_direction = 0
	_crowd_parallax = Vector2.ZERO
	_ring_parallax = Vector2.ZERO
	_opponent_parallax = Vector2.ZERO
	_apply_parallax_offsets()


func _on_player_attack_hit(
	_attack: int,
	_knockdown_damage: float,
	_opponent_meter: float,
	was_knockdown: bool,
	result: int
) -> void:
	## Finisher: keep punch impact shake during freeze; DOWN visual waits for KnockdownManager.
	if result == OffenseResolverType.ResolveResult.BLOCK:
		_play_shake(opponent_hit_shake_strength * BLOCK_SHAKE_SCALE, opponent_hit_shake_duration)
		return
	if result != OffenseResolverType.ResolveResult.HIT:
		return
	_play_shake(opponent_hit_shake_strength, opponent_hit_shake_duration)
	if was_knockdown:
		return


func _on_opponent_attack_resolved(
	result: int,
	_knockdown_damage: float,
	_player_meter: float,
	was_knockdown: bool
) -> void:
	if result == DefenseResolverType.DefenseResult.EVADE:
		if was_knockdown:
			return
		_begin_evade_passby_presentation()
		return
	if result == DefenseResolverType.DefenseResult.BLOCK:
		_play_shake(player_hit_shake_strength * BLOCK_SHAKE_SCALE, player_hit_shake_duration)
		return
	if result != DefenseResolverType.DefenseResult.HIT:
		return
	_clear_passby_only()
	_play_shake(player_hit_shake_strength, player_hit_shake_duration)
	if was_knockdown:
		return


## Opponent punch pass-by only — never locks Player continuous POV movement.
func _begin_evade_passby_presentation() -> void:
	if _finisher_freeze:
		return
	var offset := _resolve_passby_offset()
	if offset == Vector2.ZERO:
		return

	_passby_active = true
	_evade_hold_token += 1
	var token := _evade_hold_token

	if opponent_visual != null and opponent_visual.has_method("apply_evade_passby_offset"):
		opponent_visual.apply_evade_passby_offset(offset)
	elif opponent_visual != null and opponent_visual.has_method("apply_evade_passby"):
		## Fallback for older signature (horizontal only).
		opponent_visual.apply_evade_passby(signf(offset.x), absf(offset.x))

	var hold := evade_visual_hold_seconds
	if opponent_visual != null and "attack_pose_hold_seconds" in opponent_visual:
		hold = maxf(hold, float(opponent_visual.attack_pose_hold_seconds))
	hold = maxf(hold, 0.01)
	get_tree().create_timer(hold).timeout.connect(
		func() -> void:
			if token == _evade_hold_token:
				_clear_passby_only()
	)


## Extra offset beyond world parallax while an attack texture is on screen.
## Pass-by matches the existing evade presentation. The down miss eases separately.
func down_attack_miss_motion(_attack_texture_visible: bool) -> Dictionary:
	## The straight and the body share one full-frame texture.
	## A separate miss on the body anchor is the vertical bounce, so the body
	## stays on the continuous duck parallax.
	return {
		"target": Vector2.ZERO,
		"speed": attack_down_miss_clearance / maxf(attack_down_miss_blend_seconds, 0.02),
	}


func attack_texture_evade_offsets() -> Dictionary:
	var direction := _active_evade_window_direction()
	var passby := Vector2.ZERO
	match direction:
		PlayerEvadeType.Direction.LEFT:
			passby = Vector2(evade_passby_offset_x, 0.0)
		PlayerEvadeType.Direction.RIGHT:
			passby = Vector2(-evade_passby_offset_x, 0.0)
		PlayerEvadeType.Direction.DOWN:
			## Vertical pass-by would lift the whole straight canvas, body included.
			passby = Vector2.ZERO
	return {"passby": passby, "clearance": Vector2.ZERO}


func _active_evade_window_direction() -> int:
	if player_evade == null or not player_evade.window_active:
		return PlayerEvadeType.Direction.NONE
	return player_evade.window_direction


func _resolve_passby_offset() -> Vector2:
	var dir := PlayerEvadeType.Direction.NONE
	if player_evade != null:
		dir = player_evade.last_window_direction
		if dir == PlayerEvadeType.Direction.NONE:
			dir = player_evade.window_direction
		if dir == PlayerEvadeType.Direction.NONE:
			dir = player_evade.movement_direction
	match dir:
		PlayerEvadeType.Direction.LEFT:
			return Vector2(evade_passby_offset_x, 0.0)
		PlayerEvadeType.Direction.RIGHT:
			return Vector2(-evade_passby_offset_x, 0.0)
		PlayerEvadeType.Direction.DOWN:
			return Vector2.ZERO
		_:
			return Vector2.ZERO


func _clear_passby_only() -> void:
	_evade_hold_token += 1
	_passby_active = false
	if opponent_visual != null and opponent_visual.has_method("clear_evade_passby"):
		opponent_visual.clear_evade_passby()


func _on_match_state_changed(state: int) -> void:
	if (
		state == KnockdownManagerType.MatchState.PLAYER_DOWN
		or state == KnockdownManagerType.MatchState.OPPONENT_DOWN
		or state == KnockdownManagerType.MatchState.DOUBLE_DOWN
		or state == KnockdownManagerType.MatchState.FINAL_KO
		or state == KnockdownManagerType.MatchState.FIGHTING
	):
		_clear_passby_only()
		_clear_shake()
		_reset_world_parallax_immediate()


func _play_shake(strength: float, duration: float) -> void:
	## During freeze hold (after brief impact window), do not keep shaking.
	var strength_scale := MatchSettings.screen_shake_multiplier()
	strength *= strength_scale
	if _finisher_freeze and _freeze_shake_cleared:
		return
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
