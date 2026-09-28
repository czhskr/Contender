class_name PlayerVisual
extends Node2D

## Full-frame POV Player art (authored 1536x864 @ 16:9).
## Uniform scale 0.75 maps the whole canvas onto the 1152x648 viewport.
## Pose changes swap texture only — transform stays fixed.
## Runtime effects compose additively on the Anchor.

const TextureResolver = preload("res://scripts/visual_texture_resolver.gd")
const DisplayLayout = preload("res://scripts/visual_display_layout.gd")
const AttackStateType = preload("res://scripts/player_attack_state.gd")
const ActionStateType = preload("res://scripts/player_action_state.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")
const CombatInputType = preload("res://scripts/player_combat_input.gd")

signal visual_state_changed(state_name: String)
## Emitted when continuous evade POV target changes (for world parallax).
signal evade_pov_target_changed(target: Vector2, direction: int)

enum Priority {
	IDLE = 0,
	DEFENSE = 1,
	ATTACK = 2,
	KNOCKDOWN = 3,
}

@export var attack_state: AttackStateType
@export var action_state: ActionStateType
@export var knockdown_manager: KnockdownManagerType
@export var player_evade: Node

@export_group("Display")
## Shared by every Player pose. 1152/1536 = 648/864 = 0.75.
@export var player_display_scale := DisplayLayout.DEFAULT_PLAYER_DISPLAY_SCALE
## Full-frame: source canvas (0,0) → viewport (0,0). No bottom-align / letterbox.
@export var asset_base_position := Vector2.ZERO

@export_group("Textures")
@export var texture_idle := "res://assets/player/p.Nstance.png"
@export var texture_left_straight := "res://assets/player/p.L_straight.png"
@export var texture_right_straight := "res://assets/player/p.R_straight.png"
@export var texture_left_hook := "res://assets/player/p.L_hook.png"
@export var texture_right_hook := "res://assets/player/p.R_hook.png"
@export var texture_high_guard := "res://assets/player/p.highguard.png"

@export_group("Idle Breathing")
@export_range(0.0, 64.0, 0.5, "or_greater") var breathing_amplitude := 6.0
@export_range(0.2, 6.0, 0.05, "or_greater") var breathing_cycle_seconds := 1.6

@export_group("Continuous Evade POV")
## Visual-only SmoothDamp time. Does not affect evade window.
@export_range(0.01, 1.0, 0.01, "or_greater") var evade_smooth_time := 0.10
## Legacy unused by world weave; kept for Inspector compatibility / tiny Y only.
@export_range(0.0, 120.0, 1.0, "or_greater") var weave_depth := 0.0

@export_group("Opponent Down Idle Lowering")
@export_range(0.0, 200.0, 1.0, "or_greater") var opponent_down_idle_offset_y := 90.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var opponent_down_idle_move_speed := 320.0

@export_group("Runtime Offsets (read-only during play)")
var breathing_offset := Vector2.ZERO
var pov_offset := Vector2.ZERO
## DOWN: shift full-frame POV downward (no rotation).
@export var knockdown_drop_distance := 50.0

@export_group("Knockdown Impact Shake")
## Visual-only vertical jolt on this POV overlay (not screen shake). Keep small.
@export_range(0.0, 64.0, 0.5, "or_greater") var knockdown_impact_shake_y := 6.0
@export_range(1, 8, 1) var knockdown_impact_shake_count := 3
@export_range(0.01, 1.0, 0.01, "or_greater") var knockdown_impact_shake_duration := 0.18

@export_group("Debug")
@export var show_visual_debug := false

var current_visual_state := "IDLE"

var _anchor: Node2D
var _sprite: Sprite2D
var _debug_label: Label
var _priority := Priority.IDLE
var _action_effect_offset := Vector2.ZERO
var _knockdown_offset := Vector2.ZERO
var _knockdown_impact_offset := Vector2.ZERO
var _opponent_down_idle_offset := Vector2.ZERO
var _opponent_down_idle_target := Vector2.ZERO
var _knocked_down := false
var _warned_resolution := false
var _evade_target := Vector2.ZERO
var _evade_direction := 0
var _pov_velocity := Vector2.ZERO

var _breathing_tween: Tween
var _knockdown_impact_tween: Tween
var _breathing_active := false
var _finisher_freeze := false
var _knockdown_impact_token := 0


func _ready() -> void:
	if player_display_scale <= 0.0:
		player_display_scale = DisplayLayout.compute_player_full_frame_scale()
	_build_nodes()
	_show_idle()
	set_process(true)
	if attack_state != null:
		attack_state.state_changed.connect(_on_attack_state_changed)
	if action_state != null:
		action_state.state_changed.connect(_on_action_state_changed)
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_match_state_changed)
		knockdown_manager.recovered.connect(_on_recovered)
		if knockdown_manager.has_signal("fighter_stood"):
			knockdown_manager.fighter_stood.connect(_on_fighter_stood)
	if player_evade != null and player_evade.has_signal("movement_target_changed"):
		player_evade.movement_target_changed.connect(_on_evade_movement_target_changed)


func _process(delta: float) -> void:
	if _finisher_freeze or _knocked_down:
		return
	var changed := false
	## Tiny Y-only SmoothDamp. X is always forced to 0 (full-frame safe).
	var target := Vector2(0.0, _evade_target.y)
	if not pov_offset.is_equal_approx(target) or absf(_pov_velocity.y) > 0.01:
		pov_offset = _smooth_damp_vec2(pov_offset, target, evade_smooth_time, delta)
		pov_offset.x = 0.0
		changed = true
	if not _opponent_down_idle_offset.is_equal_approx(_opponent_down_idle_target):
		_opponent_down_idle_offset = _opponent_down_idle_offset.move_toward(
			_opponent_down_idle_target,
			opponent_down_idle_move_speed * delta
		)
		changed = true
	if changed:
		_apply_composed_transform()


func _on_evade_movement_target_changed(target: Vector2, direction: int) -> void:
	## X locked — only Y from PlayerEvade targets is used.
	_evade_target = Vector2(0.0, target.y)
	_evade_direction = direction
	evade_pov_target_changed.emit(_evade_target, direction)
	if direction != CombatInputType.EvadeDirection.NONE:
		_stop_breathing()
	elif _priority == Priority.IDLE and not _knocked_down and not _finisher_freeze:
		_start_breathing()


func _smooth_damp_vec2(
	current: Vector2,
	target: Vector2,
	smooth_time: float,
	delta: float
) -> Vector2:
	## Critically-damped SmoothDamp. Velocity continuity across retargets.
	if absf(current.y - target.y) < 0.05 and absf(_pov_velocity.y) < 1.0:
		_pov_velocity.y = 0.0
		return Vector2(0.0, target.y)
	var st := maxf(smooth_time, 0.0001)
	var omega := 2.0 / st
	var x := omega * delta
	var exp := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change_y := current.y - target.y
	var temp_y := (_pov_velocity.y + omega * change_y) * delta
	_pov_velocity.y = (_pov_velocity.y - omega * temp_y) * exp
	var output_y := target.y + (change_y + temp_y) * exp
	## Prevent overshoot past target.
	if (target.y - current.y > 0.0) == (output_y > target.y):
		output_y = target.y
		_pov_velocity.y = 0.0
	return Vector2(0.0, output_y)


func _build_nodes() -> void:
	_anchor = Node2D.new()
	_anchor.name = "Anchor"
	add_child(_anchor)

	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	## Top-left of PNG canvas at local (0,0) → viewport (0,0) after base+effects.
	_sprite.centered = false
	_sprite.offset = Vector2.ZERO
	_sprite.scale = Vector2(player_display_scale, player_display_scale)
	_anchor.add_child(_sprite)

	_debug_label = Label.new()
	_debug_label.name = "PlayerVisualDebug"
	_debug_label.position = Vector2(16, 560)
	_debug_label.visible = show_visual_debug
	add_child(_debug_label)

	_apply_composed_transform()


func _on_attack_state_changed(state: int, attack: int) -> void:
	if _knocked_down:
		return
	if _finisher_freeze:
		## Keep the contact / attack pose frozen for the finisher beat.
		return
	match state:
		AttackStateType.AttackState.STARTUP:
			_stop_breathing()
			_set_priority(Priority.ATTACK)
			_show_attack(attack)
		AttackStateType.AttackState.ACTIVE:
			pass
		AttackStateType.AttackState.RECOVERY:
			pass
		AttackStateType.AttackState.IDLE:
			if _priority <= Priority.ATTACK:
				if action_state == null or action_state.current_state == ActionStateType.PlayerState.IDLE:
					_show_idle()
				elif action_state.current_state == ActionStateType.PlayerState.GUARD:
					_show_guard()


func _on_action_state_changed(state: int) -> void:
	if _knocked_down:
		return
	if _finisher_freeze:
		return
	if attack_state != null and attack_state.current_state != AttackStateType.AttackState.IDLE:
		return

	match state:
		ActionStateType.PlayerState.IDLE:
			_show_idle()
		ActionStateType.PlayerState.GUARD:
			_stop_breathing()
			_show_guard()
		ActionStateType.PlayerState.ATTACKING:
			_stop_breathing()


## Finisher Impact Freeze: lock current POV/attack pose; stop breathing/tweens.
func set_finisher_freeze(active: bool) -> void:
	var was_frozen := _finisher_freeze
	_finisher_freeze = active
	if active:
		_stop_breathing()
		_apply_composed_transform()
		return

	## Freeze exit (Player was attacker): release stale attack pose.
	if was_frozen and not _knocked_down and _priority == Priority.ATTACK:
		_show_idle()


func _on_match_state_changed(state: int) -> void:
	if state == KnockdownManagerType.MatchState.PLAYER_DOWN or state == KnockdownManagerType.MatchState.DOUBLE_DOWN:
		_knocked_down = true
		_opponent_is_down_clear()
		_stop_breathing()
		_reset_pov_immediate()
		_set_priority(Priority.KNOCKDOWN)
		_knockdown_offset = Vector2(0.0, knockdown_drop_distance)
		_show_pose("KNOCKDOWN", texture_idle)
		_play_knockdown_impact_shake()
	elif state == KnockdownManagerType.MatchState.OPPONENT_DOWN:
		## After finisher: Player should already be Nstance; apply lowering.
		if not _knocked_down and not _finisher_freeze:
			_set_opponent_down_idle(true)
	elif state == KnockdownManagerType.MatchState.FINAL_KO:
		if knockdown_manager.downed_side == KnockdownManagerType.DownedSide.PLAYER or knockdown_manager.downed_side == KnockdownManagerType.DownedSide.BOTH:
			_knocked_down = true
			_opponent_is_down_clear()
			_stop_breathing()
			_reset_pov_immediate()
			_set_priority(Priority.KNOCKDOWN)
			_knockdown_offset = Vector2(0.0, knockdown_drop_distance)
			_show_pose("KO", texture_idle)
		elif knockdown_manager.downed_side == KnockdownManagerType.DownedSide.OPPONENT:
			## Keep lowered Nstance on opponent Final KO.
			if not _knocked_down:
				_set_opponent_down_idle(true)
	elif state == KnockdownManagerType.MatchState.FIGHTING:
		_set_opponent_down_idle(false)
		if _knocked_down or _priority == Priority.KNOCKDOWN:
			_knocked_down = false
			_clear_knockdown_impact()
			_knockdown_offset = Vector2.ZERO
			_action_effect_offset = Vector2.ZERO
			_show_idle()


func _set_opponent_down_idle(active: bool) -> void:
	if _knocked_down:
		active = false
	_opponent_down_idle_target = (
		Vector2(0.0, opponent_down_idle_offset_y) if active else Vector2.ZERO
	)


func _opponent_is_down_clear() -> void:
	_opponent_down_idle_target = Vector2.ZERO
	_opponent_down_idle_offset = Vector2.ZERO


func _on_fighter_stood(downed_side: int, at_count: int) -> void:
	_on_recovered(downed_side, at_count)


func _on_recovered(downed_side: int, _at_count: int) -> void:
	if downed_side == KnockdownManagerType.DownedSide.OPPONENT:
		_set_opponent_down_idle(false)
		return
	if downed_side != KnockdownManagerType.DownedSide.PLAYER:
		return
	_knocked_down = false
	_clear_knockdown_impact()
	_knockdown_offset = Vector2.ZERO
	_action_effect_offset = Vector2.ZERO
	_reset_pov_immediate()
	_show_idle()


func _show_attack(attack: int) -> void:
	_stop_breathing()
	if not _knocked_down:
		_action_effect_offset = Vector2.ZERO
	match attack:
		CombatInputType.AttackType.LEFT_STRAIGHT:
			_show_pose("LEFT_STRAIGHT", texture_left_straight)
		CombatInputType.AttackType.RIGHT_STRAIGHT:
			_show_pose("RIGHT_STRAIGHT", texture_right_straight)
		CombatInputType.AttackType.LEFT_HOOK:
			_show_pose("LEFT_HOOK", texture_left_hook)
		CombatInputType.AttackType.RIGHT_HOOK:
			_show_pose("RIGHT_HOOK", texture_right_hook)
		_:
			_show_pose("IDLE", texture_idle)


func _show_guard() -> void:
	_stop_breathing()
	_set_priority(Priority.DEFENSE)
	if not _knocked_down:
		_action_effect_offset = Vector2.ZERO
	_show_pose("HIGH_GUARD", texture_high_guard)


func reset_for_new_round() -> void:
	_knocked_down = false
	_finisher_freeze = false
	_knockdown_impact_token += 1
	_clear_knockdown_impact()
	_knockdown_offset = Vector2.ZERO
	_action_effect_offset = Vector2.ZERO
	_set_opponent_down_idle(false)
	_opponent_down_idle_offset = Vector2.ZERO
	_reset_pov_immediate()
	_show_idle()


func _show_idle() -> void:
	_set_priority(Priority.IDLE)
	if not _knocked_down:
		_action_effect_offset = Vector2.ZERO
	_show_pose("IDLE", texture_idle)
	_start_breathing()


func _show_pose(state_name: String, texture_path: String) -> void:
	var texture := TextureResolver.try_load(texture_path)
	_sprite.texture = texture
	## Texture swap only — keep origin/scale identical for every pose.
	_sprite.centered = false
	_sprite.offset = Vector2.ZERO
	_sprite.scale = Vector2(player_display_scale, player_display_scale)
	_sprite.visible = texture != null
	if texture == null:
		push_warning("PlayerVisual missing texture: %s" % texture_path)
	else:
		_warn_if_unexpected_resolution(texture, texture_path)
	_apply_composed_transform()
	_set_visual_state(state_name)


func _warn_if_unexpected_resolution(texture: Texture2D, path: String) -> void:
	if _warned_resolution:
		return
	var expected := DisplayLayout.PLAYER_SOURCE_CANVAS_SIZE
	if (
		texture.get_width() != int(expected.x)
		or texture.get_height() != int(expected.y)
	):
		_warned_resolution = true
		push_warning(
			"PlayerVisual expected %dx%d (16:9 full-frame) but %s is %dx%d. Scale 0.75 assumes 1536x864."
			% [
				int(expected.x),
				int(expected.y),
				path,
				texture.get_width(),
				texture.get_height(),
			]
		)


func _apply_composed_transform() -> void:
	if _anchor == null:
		return
	## base + breathing + action + evade POV + opponent-down idle + knockdown + impact
	_anchor.rotation_degrees = 0.0
	_anchor.position = (
		asset_base_position
		+ breathing_offset
		+ _action_effect_offset
		+ pov_offset
		+ _opponent_down_idle_offset
		+ _knockdown_offset
		+ _knockdown_impact_offset
	)
	if _sprite != null:
		_sprite.centered = false
		_sprite.offset = Vector2.ZERO
		_sprite.scale = Vector2(player_display_scale, player_display_scale)
		_sprite.rotation_degrees = 0.0


func _play_knockdown_impact_shake() -> void:
	## One-shot vertical jolt on knockdown entry only (not during count).
	_knockdown_impact_token += 1
	var token := _knockdown_impact_token
	if _knockdown_impact_tween != null and _knockdown_impact_tween.is_valid():
		_knockdown_impact_tween.kill()
	_knockdown_impact_tween = null
	_knockdown_impact_offset = Vector2.ZERO
	_apply_composed_transform()

	if knockdown_impact_shake_y <= 0.0 or knockdown_impact_shake_duration <= 0.0:
		return
	var steps := maxi(knockdown_impact_shake_count, 1)
	var step_dur := maxf(knockdown_impact_shake_duration / float(steps), 0.01)
	_knockdown_impact_tween = create_tween()
	for i in range(steps):
		var mag := knockdown_impact_shake_y * (1.0 - float(i) / float(steps))
		var sign := 1.0 if (i % 2) == 0 else -1.0
		var peak := Vector2(0.0, mag * sign)
		var captured := peak
		_knockdown_impact_tween.tween_method(
			func(v: Vector2) -> void:
				if token != _knockdown_impact_token:
					return
				_knockdown_impact_offset = v
				_apply_composed_transform(),
			Vector2.ZERO if i == 0 else Vector2(0.0, 0.0),
			captured,
			step_dur * 0.45
		)
		## Return toward zero between peaks so drop offset remains the settle base.
		_knockdown_impact_tween.tween_method(
			func(v: Vector2) -> void:
				if token != _knockdown_impact_token:
					return
				_knockdown_impact_offset = v
				_apply_composed_transform(),
			captured,
			Vector2.ZERO,
			step_dur * 0.55
		)
	_knockdown_impact_tween.finished.connect(
		func() -> void:
			if token == _knockdown_impact_token:
				_knockdown_impact_offset = Vector2.ZERO
				_apply_composed_transform()
	)


func _clear_knockdown_impact() -> void:
	_knockdown_impact_token += 1
	if _knockdown_impact_tween != null and _knockdown_impact_tween.is_valid():
		_knockdown_impact_tween.kill()
	_knockdown_impact_tween = null
	if _knockdown_impact_offset != Vector2.ZERO:
		_knockdown_impact_offset = Vector2.ZERO
		_apply_composed_transform()


func _start_breathing() -> void:
	if _knocked_down or _finisher_freeze or _priority != Priority.IDLE:
		return
	if breathing_amplitude <= 0.0 or breathing_cycle_seconds <= 0.0:
		return
	if _breathing_active:
		return
	_stop_breathing()
	_breathing_active = true
	breathing_offset = Vector2.ZERO
	_apply_composed_transform()

	var half := breathing_cycle_seconds * 0.5
	var down := Vector2(0.0, breathing_amplitude)
	_breathing_tween = create_tween()
	_breathing_tween.set_loops()
	_breathing_tween.set_ease(Tween.EASE_IN_OUT)
	_breathing_tween.set_trans(Tween.TRANS_SINE)
	_breathing_tween.tween_method(_set_breathing_offset, Vector2.ZERO, down, half)
	_breathing_tween.tween_method(_set_breathing_offset, down, Vector2.ZERO, half)


func _stop_breathing() -> void:
	_breathing_active = false
	if _breathing_tween != null and _breathing_tween.is_valid():
		_breathing_tween.kill()
	_breathing_tween = null
	if breathing_offset != Vector2.ZERO:
		breathing_offset = Vector2.ZERO
		_apply_composed_transform()


func _set_breathing_offset(value: Vector2) -> void:
	## Never go above base (negative Y). Clamp for safety.
	breathing_offset = Vector2(value.x, maxf(value.y, 0.0))
	_apply_composed_transform()


func reset_evade_visual_immediate() -> void:
	_reset_pov_immediate()


func _reset_pov_immediate() -> void:
	_evade_target = Vector2.ZERO
	_evade_direction = CombatInputType.EvadeDirection.NONE
	_pov_velocity = Vector2.ZERO
	pov_offset = Vector2.ZERO
	_apply_composed_transform()


func _set_priority(priority: Priority) -> void:
	_priority = priority


func _set_visual_state(state_name: String) -> void:
	current_visual_state = state_name
	if _debug_label != null:
		_debug_label.visible = show_visual_debug
		_debug_label.text = "PLAYER VISUAL: %s" % state_name
	visual_state_changed.emit(state_name)
