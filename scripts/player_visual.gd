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
signal slip_requested(direction: int) ## -1 left, +1 right, 0 ended

enum Priority {
	IDLE = 0,
	DEFENSE = 1,
	ATTACK = 2,
	KNOCKDOWN = 3,
}

@export var attack_state: AttackStateType
@export var action_state: ActionStateType
@export var knockdown_manager: KnockdownManagerType

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

@export_group("Slip POV")
@export_range(0.0, 200.0, 1.0, "or_greater") var slip_pov_x := 42.0
@export_range(0.0, 200.0, 1.0, "or_greater") var slip_pov_y := 14.0
@export_range(0.01, 1.0, 0.01, "or_greater") var slip_pov_tween_seconds := 0.10

@export_group("Runtime Offsets (read-only during play)")
var breathing_offset := Vector2.ZERO
var pov_offset := Vector2.ZERO
## DOWN: shift full-frame POV downward (no rotation).
@export var knockdown_drop_distance := 50.0

@export_group("Debug")
@export var show_visual_debug := false

var current_visual_state := "IDLE"

var _anchor: Node2D
var _sprite: Sprite2D
var _debug_label: Label
var _priority := Priority.IDLE
var _action_effect_offset := Vector2.ZERO
var _knockdown_offset := Vector2.ZERO
var _knocked_down := false
var _warned_resolution := false

var _breathing_tween: Tween
var _pov_tween: Tween
var _breathing_active := false


func _ready() -> void:
	if player_display_scale <= 0.0:
		player_display_scale = DisplayLayout.compute_player_full_frame_scale()
	_build_nodes()
	_show_idle()
	if attack_state != null:
		attack_state.state_changed.connect(_on_attack_state_changed)
	if action_state != null:
		action_state.state_changed.connect(_on_action_state_changed)
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_match_state_changed)
		knockdown_manager.recovered.connect(_on_recovered)


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
	if attack_state != null and attack_state.current_state != AttackStateType.AttackState.IDLE:
		if state == ActionStateType.PlayerState.SLIP_LEFT:
			_begin_slip_pov(-1)
		elif state == ActionStateType.PlayerState.SLIP_RIGHT:
			_begin_slip_pov(1)
		elif state == ActionStateType.PlayerState.IDLE:
			_end_slip_pov()
		return

	match state:
		ActionStateType.PlayerState.IDLE:
			_end_slip_pov()
			_show_idle()
		ActionStateType.PlayerState.GUARD:
			_stop_breathing()
			_end_slip_pov()
			_show_guard()
		ActionStateType.PlayerState.SLIP_LEFT:
			_stop_breathing()
			_begin_slip_pov(-1)
			_set_visual_state("SLIP_LEFT")
		ActionStateType.PlayerState.SLIP_RIGHT:
			_stop_breathing()
			_begin_slip_pov(1)
			_set_visual_state("SLIP_RIGHT")
		ActionStateType.PlayerState.ATTACKING:
			_stop_breathing()


func _on_match_state_changed(state: int) -> void:
	if state == KnockdownManagerType.MatchState.PLAYER_DOWN:
		_knocked_down = true
		_stop_breathing()
		_reset_pov_immediate()
		_set_priority(Priority.KNOCKDOWN)
		_knockdown_offset = Vector2(0.0, knockdown_drop_distance)
		_show_pose("KNOCKDOWN", texture_idle)
	elif state == KnockdownManagerType.MatchState.FINAL_KO:
		if knockdown_manager.downed_side == KnockdownManagerType.DownedSide.PLAYER:
			_knocked_down = true
			_stop_breathing()
			_reset_pov_immediate()
			_set_priority(Priority.KNOCKDOWN)
			_knockdown_offset = Vector2(0.0, knockdown_drop_distance)
			_show_pose("KO", texture_idle)
	elif state == KnockdownManagerType.MatchState.FIGHTING:
		if not _knocked_down and _priority == Priority.KNOCKDOWN:
			_knockdown_offset = Vector2.ZERO
			_action_effect_offset = Vector2.ZERO
			_show_idle()


func _on_recovered(downed_side: int, _at_count: int) -> void:
	if downed_side != KnockdownManagerType.DownedSide.PLAYER:
		return
	_knocked_down = false
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
	## base + breathing + action + POV + knockdown (shake lives on CombatVisualRoot).
	_anchor.rotation_degrees = 0.0
	_anchor.position = (
		asset_base_position
		+ breathing_offset
		+ _action_effect_offset
		+ pov_offset
		+ _knockdown_offset
	)
	if _sprite != null:
		_sprite.centered = false
		_sprite.offset = Vector2.ZERO
		_sprite.scale = Vector2(player_display_scale, player_display_scale)
		_sprite.rotation_degrees = 0.0


func _start_breathing() -> void:
	if _knocked_down or _priority != Priority.IDLE:
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


func _begin_slip_pov(direction: int) -> void:
	## Absolute target — never accumulate. direction -1 left / +1 right.
	_stop_breathing()
	slip_requested.emit(direction)
	var target := Vector2(slip_pov_x * float(direction), slip_pov_y)
	_tween_pov_to(target)


func _end_slip_pov() -> void:
	slip_requested.emit(0)
	_tween_pov_to(Vector2.ZERO)


func _tween_pov_to(target: Vector2) -> void:
	if _pov_tween != null and _pov_tween.is_valid():
		_pov_tween.kill()
	_pov_tween = null
	var from := pov_offset
	if from.is_equal_approx(target):
		pov_offset = target
		_apply_composed_transform()
		return
	_pov_tween = create_tween()
	_pov_tween.set_ease(Tween.EASE_IN_OUT)
	_pov_tween.set_trans(Tween.TRANS_SINE)
	_pov_tween.tween_method(
		func(v: Vector2) -> void:
			pov_offset = v
			_apply_composed_transform(),
		from,
		target,
		maxf(slip_pov_tween_seconds, 0.01)
	)


func _reset_pov_immediate() -> void:
	if _pov_tween != null and _pov_tween.is_valid():
		_pov_tween.kill()
	_pov_tween = null
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
