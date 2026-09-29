class_name OpponentVisual
extends Node2D

## Opponent presentation.
## One shared display_scale for all poses; PNG-internal alignment preserved.
## Runtime effects compose separately from asset_base_position.

const TextureResolver = preload("res://scripts/visual_texture_resolver.gd")
const DisplayLayout = preload("res://scripts/visual_display_layout.gd")
const AttackStateType = preload("res://scripts/opponent_attack_state.gd")
const ActionStateType = preload("res://scripts/opponent_action_state.gd")
const OffenseResolverType = preload("res://scripts/player_offense_resolver.gd")
const DefenseResolverType = preload("res://scripts/player_defense_resolver.gd")
const KnockdownManagerType = preload("res://scripts/knockdown_manager.gd")
const AttackDataType = preload("res://scripts/opponent_attack_data.gd")

signal visual_state_changed(state_name: String)

enum Priority {
	IDLE = 0,
	DEFENSE = 1,
	ATTACK = 2,
	HIT = 3,
	KNOCKDOWN = 4,
}

@export var opponent_attack_state: AttackStateType
@export var opponent_action_state: ActionStateType
@export var offense_resolver: OffenseResolverType
@export var defense_resolver: DefenseResolverType
@export var knockdown_manager: KnockdownManagerType

@export_group("Display")
## Shared by every Opponent pose. Contain fit (height-limited): 648/1024 ≈ 0.6328.
@export var opponent_display_scale := DisplayLayout.DEFAULT_OPPONENT_DISPLAY_SCALE
## Top-left of scaled canvas. X stays centered. Y is set so max DOWN lift
## puts the canvas bottom on the viewport bottom (CombatVisualRoot).
@export var asset_base_position := Vector2(90, 85)

@export_group("Textures")
@export var texture_idle := "res://assets/opponent/o.Nstance.png"
@export var texture_left_straight := "res://assets/opponent/o.L_straight.png"
@export var texture_right_straight := "res://assets/opponent/o.R_straight.png"
@export var texture_slip_left := "res://assets/opponent/o.L_slip.png"
@export var texture_slip_right := "res://assets/opponent/o.R_slip.png"
@export var texture_high_guard := "res://assets/opponent/o.highguard.png"
@export var texture_hit := "res://assets/opponent/o.hit.png"

@export_group("Exhausted Ghost")
@export_range(0.0, 1.0, 0.01) var ghost_a_alpha := 0.22
@export_range(0.0, 1.0, 0.01) var ghost_b_alpha := 0.16
@export var ghost_a_drift := Vector2(12, 4)
@export var ghost_b_drift := Vector2(10, 5)
@export_range(0.1, 8.0, 0.05, "or_greater") var ghost_fade_seconds := 0.25
@export_range(0.0, 64.0, 0.5, "or_greater") var breathing_amplitude := 6.0
@export_range(0.2, 6.0, 0.05, "or_greater") var breathing_cycle_seconds := 1.6

@export_group("Runtime Offsets")
var breathing_offset := Vector2.ZERO
## Driven by CombatVisualRoot world parallax (additive; never replaces base).
var parallax_offset := Vector2.ZERO
## DOWN: shift opponent downward (no rotation). Uses o.hit.png.
@export var knockdown_drop_distance := 70.0
@export var print_visual_trace := false
@export var print_opponent_transform := false
@export var hit_hold_seconds := 0.22
## Visual-only punch pose length. Independent of AttackState Recovery timing.
@export_range(0.0, 2.0, 0.01, "or_greater") var attack_pose_hold_seconds := 0.28
@export_range(0.0, 2.0, 0.01, "or_greater") var slip_visual_hold_seconds := 0.38
@export_range(0.0, 2.0, 0.01, "or_greater") var guard_visual_hold_seconds := 0.32
## Set by CombatVisualRoot on EVADE (additive; cleared when pose ends).
var _evade_passby_offset := Vector2.ZERO
var _attack_miss_clearance := Vector2.ZERO
var _logged_final_y := 0.0

@export_group("Knockdown Impact Shake")
## Visual-only vertical jolt on OpponentSprite (not screen / HUD shake).
@export_range(0.0, 64.0, 0.5, "or_greater") var knockdown_impact_shake_y := 10.0
@export_range(1, 8, 1) var knockdown_impact_shake_count := 3
@export_range(0.01, 1.0, 0.01, "or_greater") var knockdown_impact_shake_duration := 0.18

@export_group("Debug")
@export var show_visual_debug := false

var current_visual_state := "IDLE"

var _anchor: Node2D
var _sprite: Sprite2D
var _ghost_a: Sprite2D
var _ghost_b: Sprite2D
var _ghost_weight := 0.0
var _ghost_target := 0.0
var _debug_label: Label
var _priority := Priority.IDLE
var _action_effect_offset := Vector2.ZERO
var _knockdown_offset := Vector2.ZERO
var _knockdown_impact_offset := Vector2.ZERO
var _locked_final_ko := false
var _hit_release_token := 0
## Invalidates in-flight attack pose timers (new ACTIVE / HIT / KNOCKDOWN).
var _attack_pose_token := 0
var _attack_pose_holding := false
var _defense_pose_token := 0
var _defense_hold_alive := false
var _knockdown_impact_token := 0
var _finisher_freeze := false
var _finisher_sealed := false
var _sealed_texture: Texture2D

var _breathing_tween: Tween
var _knockdown_impact_tween: Tween
var _breathing_active := false


func _ready() -> void:
	if opponent_display_scale <= 0.0:
		opponent_display_scale = DisplayLayout.compute_opponent_contain_scale()
	_build_nodes()
	_show_idle()
	if opponent_attack_state != null:
		opponent_attack_state.state_changed.connect(_on_attack_state_changed)
	if opponent_action_state != null:
		opponent_action_state.state_changed.connect(_on_action_state_changed)
	if offense_resolver != null:
		offense_resolver.attack_hit.connect(_on_player_attack_hit)
	if defense_resolver != null:
		defense_resolver.attack_resolved.connect(_on_opponent_attack_resolved)
	if knockdown_manager != null:
		knockdown_manager.match_state_changed.connect(_on_match_state_changed)
		knockdown_manager.recovered.connect(_on_recovered)
		if knockdown_manager.has_signal("fighter_stood"):
			knockdown_manager.fighter_stood.connect(_on_recovered)


func _build_nodes() -> void:
	_anchor = Node2D.new()
	_anchor.name = "Anchor"
	add_child(_anchor)

	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = false
	_sprite.offset = Vector2.ZERO
	_sprite.scale = Vector2(opponent_display_scale, opponent_display_scale)
	_anchor.add_child(_sprite)
	_ghost_a = _make_ghost("GhostA")
	_ghost_b = _make_ghost("GhostB")

	_debug_label = Label.new()
	_debug_label.name = "OpponentVisualDebug"
	_debug_label.position = Vector2(16, 590)
	_debug_label.visible = show_visual_debug
	add_child(_debug_label)

	_apply_composed_transform()
	set_process(true)


func _make_ghost(node_name: String) -> Sprite2D:
	var ghost := Sprite2D.new()
	ghost.name = node_name
	ghost.centered = false
	ghost.z_index = -1
	ghost.visible = false
	ghost.modulate = Color(1, 1, 1, 0)
	_anchor.add_child(ghost)
	return ghost


## Visual only. Does not affect hit resolution.
func set_exhausted_ghost(active: bool) -> void:
	_ghost_target = 1.0 if active else 0.0


func _process(delta: float) -> void:
	_tick_attack_miss(delta)
	var step := delta / maxf(ghost_fade_seconds, 0.01)
	_ghost_weight = move_toward(_ghost_weight, _ghost_target, step)
	if _ghost_a == null or _ghost_b == null:
		return
	var show := _ghost_weight > 0.001
	_ghost_a.visible = show
	_ghost_b.visible = show
	if not show:
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	_ghost_a.position = Vector2(
		sin(t * 0.7) * ghost_a_drift.x,
		cos(t * 0.5) * ghost_a_drift.y
	)
	_ghost_b.position = Vector2(
		sin(t * 0.7 + PI) * ghost_b_drift.x,
		sin(t * 0.45) * ghost_b_drift.y
	)
	_ghost_a.modulate.a = ghost_a_alpha * _ghost_weight
	_ghost_b.modulate.a = ghost_b_alpha * _ghost_weight


func set_parallax_offset(offset: Vector2) -> void:
	var started_down := parallax_offset.y > -1.0 and offset.y <= -1.0
	var ended_down := parallax_offset.y <= -1.0 and offset.y > -1.0
	parallax_offset = offset
	_apply_composed_transform()
	if started_down:
		log_opponent_transform("DOWN_EVADE_START")
	elif ended_down:
		log_opponent_transform("DOWN_EVADE_END")


func _on_attack_state_changed(state: int, attack_data) -> void:
	if _player_is_down():
		_return_to_stance()
		return
	if _priority >= Priority.KNOCKDOWN:
		return
	if _finisher_freeze:
		return
	match state:
		AttackStateType.AttackState.STARTUP:
			_cancel_attack_pose_hold()
			_stop_breathing()
			if _priority == Priority.ATTACK:
				_release_attack_pose_to_stance()
			log_opponent_transform("ATTACK_STARTUP")
		AttackStateType.AttackState.ACTIVE:
			if attack_data == null:
				return
			_begin_attack_pose(attack_data.attack_type)
			log_opponent_transform("ATTACK_ACTIVE")
		AttackStateType.AttackState.RECOVERY:
			log_opponent_transform("ATTACK_RECOVERY")
		AttackStateType.AttackState.IDLE:
			if _attack_pose_holding:
				return
			_cancel_attack_pose_hold()
			if _priority <= Priority.ATTACK:
				_show_idle()


func _on_action_state_changed(state: int) -> void:
	if _priority >= Priority.HIT:
		return
	if _finisher_freeze:
		return
	if (
		opponent_attack_state != null
		and opponent_attack_state.current_state != AttackStateType.AttackState.IDLE
		and (_attack_pose_holding or _priority == Priority.ATTACK)
	):
		return

	match state:
		ActionStateType.OpponentState.IDLE:
			if _defense_hold_alive and _priority == Priority.DEFENSE:
				return
			if _priority <= Priority.DEFENSE:
				_show_idle()
		ActionStateType.OpponentState.GUARD:
			_stop_breathing()
			_begin_defense_pose("HIGH_GUARD", texture_high_guard, guard_visual_hold_seconds)
		ActionStateType.OpponentState.SLIP_LEFT:
			_stop_breathing()
			_begin_defense_pose("SLIP_LEFT", texture_slip_left, slip_visual_hold_seconds)
		ActionStateType.OpponentState.SLIP_RIGHT:
			_stop_breathing()
			_begin_defense_pose("SLIP_RIGHT", texture_slip_right, slip_visual_hold_seconds)
		ActionStateType.OpponentState.ATTACKING:
			_stop_breathing()


func _on_player_attack_hit(
	_attack: int,
	_knockdown_damage: float,
	_opponent_meter: float,
	was_knockdown: bool,
	result: int
) -> void:
	## Finisher HIT: show hit pose during freeze. DOWN/drop waits for match_state OPPONENT_DOWN.
	if result != OffenseResolverType.ResolveResult.HIT:
		return
	if _priority >= Priority.KNOCKDOWN:
		return
	if not was_knockdown and _attack_visual_owns_pose():
		_visual_trace("HIT_SKIPPED_DURING_ATTACK")
		return

	_cancel_defense_hold()
	_cancel_attack_pose_hold()
	_stop_breathing()
	_set_priority(Priority.HIT)
	_action_effect_offset = Vector2.ZERO
	_show_pose("HIT", texture_hit)
	_hit_release_token += 1
	if was_knockdown or _finisher_freeze:
		## Hold hit pose until KnockdownManager promotes priority; do not auto-release to idle.
		return
	var token := _hit_release_token
	get_tree().create_timer(hit_hold_seconds).timeout.connect(
		func() -> void:
			if token == _hit_release_token and not _finisher_freeze:
				_release_hit_if_allowed()
	)


func _on_opponent_attack_resolved(
	_result: int,
	_knockdown_damage: float,
	_player_meter: float,
	_was_knockdown: bool
) -> void:
	## EVADE presentation is orchestrated by CombatVisualRoot (pass-by + slip hold).
	pass


## Visual-only: shift Straight further along evade-away axis so glove clears face center.
func apply_evade_passby(world_dir: float, amount: float) -> void:
	apply_evade_passby_offset(Vector2(amount * world_dir, 0.0))


func apply_evade_passby_offset(offset: Vector2) -> void:
	if _finisher_freeze:
		return
	_evade_passby_offset = offset
	_refresh_action_offset()


func clear_evade_passby() -> void:
	_evade_passby_offset = Vector2.ZERO
	_refresh_action_offset()


func _on_match_state_changed(state: int) -> void:
	if state == KnockdownManagerType.MatchState.OPPONENT_DOWN or state == KnockdownManagerType.MatchState.DOUBLE_DOWN:
		_cancel_defense_hold()
		_cancel_attack_pose_hold()
		_stop_breathing()
		clear_evade_passby()
		_set_priority(Priority.KNOCKDOWN)
		_action_effect_offset = Vector2.ZERO
		_knockdown_offset = Vector2(0.0, knockdown_drop_distance)
		_show_pose("KNOCKDOWN", texture_hit)
		_play_knockdown_impact_shake()
	elif state == KnockdownManagerType.MatchState.FINAL_KO:
		if knockdown_manager.downed_side == KnockdownManagerType.DownedSide.OPPONENT or knockdown_manager.downed_side == KnockdownManagerType.DownedSide.BOTH:
			_locked_final_ko = true
			_cancel_defense_hold()
			_cancel_attack_pose_hold()
			_stop_breathing()
			clear_evade_passby()
			_set_priority(Priority.KNOCKDOWN)
			_action_effect_offset = Vector2.ZERO
			_knockdown_offset = Vector2(0.0, knockdown_drop_distance)
			## Entry shake already played on OPPONENT_DOWN — do not repeat during count/KO.
			_show_pose("KO", texture_hit)
		else:
			_return_to_stance()
	elif state == KnockdownManagerType.MatchState.PLAYER_DOWN:
		_return_to_stance()
	elif state == KnockdownManagerType.MatchState.FIGHTING:
		_locked_final_ko = false
		if _priority == Priority.KNOCKDOWN or _knockdown_offset != Vector2.ZERO:
			_clear_knockdown_impact()
			_knockdown_offset = Vector2.ZERO
			_action_effect_offset = Vector2.ZERO
			_show_idle()


func _on_recovered(downed_side: int, _at_count: int) -> void:
	if downed_side != KnockdownManagerType.DownedSide.OPPONENT:
		return
	if _locked_final_ko:
		return
	_clear_knockdown_impact()
	_knockdown_offset = Vector2.ZERO
	_action_effect_offset = Vector2.ZERO
	_show_idle()


func _player_is_down() -> bool:
	if knockdown_manager == null:
		return false
	return knockdown_manager.match_state == KnockdownManagerType.MatchState.PLAYER_DOWN or knockdown_manager.match_state == KnockdownManagerType.MatchState.DOUBLE_DOWN or (
		knockdown_manager.match_state == KnockdownManagerType.MatchState.FINAL_KO
		and knockdown_manager.downed_side in [
			KnockdownManagerType.DownedSide.PLAYER,
			KnockdownManagerType.DownedSide.BOTH,
		]
	)


func _return_to_stance() -> void:
	_cancel_defense_hold()
	_cancel_attack_pose_hold()
	_hit_release_token += 1
	_snap_attack_miss()
	_stop_breathing()
	clear_evade_passby()
	_knockdown_offset = Vector2.ZERO
	_show_idle()


func _attack_visual_owns_pose() -> bool:
	if _attack_pose_holding or _priority == Priority.ATTACK:
		return true
	if opponent_attack_state == null:
		return false
	var state: int = opponent_attack_state.current_state
	return state == AttackStateType.AttackState.STARTUP or state == AttackStateType.AttackState.ACTIVE


func _visual_trace(event: String) -> void:
	if not print_visual_trace:
		return
	print(
		"[VISUAL] %s priority=%d pose_token=%d hit_token=%d t=%.3f"
		% [event, _priority, _attack_pose_token, _hit_release_token, Time.get_ticks_msec() / 1000.0]
	)


func _begin_defense_pose(pose_name: String, texture_path: String, hold: float) -> void:
	_defense_pose_token += 1
	var token := _defense_pose_token
	_defense_hold_alive = true
	_set_priority(Priority.DEFENSE)
	_refresh_action_offset()
	_show_pose(pose_name, texture_path)
	if not is_inside_tree():
		return
	get_tree().create_timer(maxf(hold, 0.0)).timeout.connect(
		func() -> void:
			if token != _defense_pose_token or _finisher_freeze:
				return
			_defense_hold_alive = false
			if _priority != Priority.DEFENSE or _locked_final_ko:
				return
			var action_state := opponent_action_state.current_state if opponent_action_state != null else -1
			if action_state == ActionStateType.OpponentState.GUARD or action_state == ActionStateType.OpponentState.SLIP_LEFT or action_state == ActionStateType.OpponentState.SLIP_RIGHT:
				return
			_show_idle()
			print("[VISUAL_HOLD] %s held=%.2f" % [pose_name, hold])
	)


func _cancel_defense_hold() -> void:
	_defense_pose_token += 1
	_defense_hold_alive = false


func _release_hit_if_allowed() -> void:
	if _finisher_freeze:
		return
	if _priority == Priority.HIT and not _locked_final_ko:
		_show_idle()


func _begin_attack_pose(attack_type: int) -> void:
	if _priority >= Priority.KNOCKDOWN or _locked_final_ko or _player_is_down():
		return
	_hit_release_token += 1
	_cancel_defense_hold()
	_cancel_attack_pose_hold()
	_stop_breathing()
	_set_priority(Priority.ATTACK)
	_attack_pose_holding = true
	_show_attack(attack_type)
	_attack_pose_token += 1
	var token := _attack_pose_token
	var hold := maxf(attack_pose_hold_seconds, 0.0)
	if hold <= 0.0 or not is_inside_tree():
		if hold <= 0.0:
			_release_attack_pose_to_stance()
		return
	get_tree().create_timer(hold).timeout.connect(
		func() -> void:
			if token == _attack_pose_token and not _finisher_freeze:
				_release_attack_pose_to_stance()
	)


func _cancel_attack_pose_hold() -> void:
	_attack_pose_token += 1
	_attack_pose_holding = false


func _release_attack_pose_to_stance() -> void:
	## Combat may still be in RECOVERY; visual returns to stance without unlocking attacks.
	if _finisher_freeze:
		return
	if _priority > Priority.ATTACK:
		_attack_pose_holding = false
		return
	_attack_pose_holding = false
	if _locked_final_ko:
		return
	_show_idle()


## Finisher Impact Freeze: lock current attack/HIT pose; stop breathing.
func set_finisher_freeze(active: bool) -> void:
	_finisher_freeze = active
	if active:
		_stop_breathing()
		_finisher_sealed = false
		_attack_pose_token += 1
		_hit_release_token += 1
		_attack_pose_holding = _priority == Priority.ATTACK or _attack_pose_holding
		call_deferred("_seal_finisher_pose")
		return
	_finisher_sealed = false
	## Freeze ended. The next attack cancel may return to stance.
	_attack_pose_holding = false


func _arm_attack_evade_offset() -> void:
	var root := get_parent()
	if root == null or not root.has_method("attack_texture_evade_offsets"):
		_refresh_action_offset()
		return
	var parts: Dictionary = root.attack_texture_evade_offsets()
	var passby: Vector2 = parts["passby"]
	if _evade_passby_offset == Vector2.ZERO and passby != Vector2.ZERO:
		_evade_passby_offset = passby
	_refresh_action_offset()


func _tick_attack_miss(delta: float) -> void:
	var root := get_parent()
	if root == null or not root.has_method("down_attack_miss_motion"):
		return
	var showing := _attack_pose_holding and not _finisher_freeze and _priority < Priority.KNOCKDOWN
	var motion: Dictionary = root.down_attack_miss_motion(showing)
	var target: Vector2 = motion["target"]
	var speed: float = motion["speed"]
	if target.y < 0.0 and root.has_method("max_opponent_upward_lift"):
		var used := -minf(parallax_offset.y + _evade_passby_offset.y, 0.0)
		var room := maxf(float(root.max_opponent_upward_lift()) - used, 0.0)
		target.y = -minf(-target.y, room)
	if _attack_miss_clearance.distance_to(target) <= 0.01:
		return
	_attack_miss_clearance = _attack_miss_clearance.move_toward(target, speed * delta)
	_refresh_action_offset()


func _snap_attack_miss() -> void:
	_attack_miss_clearance = Vector2.ZERO
	_refresh_action_offset()


func _refresh_action_offset() -> void:
	var next := _evade_passby_offset + _attack_miss_clearance
	if next == _action_effect_offset and _anchor != null:
		_apply_composed_transform()
		return
	_action_effect_offset = next
	_apply_composed_transform()


func _show_attack(attack_type: int) -> void:
	## Keep the evade world offset. Add the miss on top of it; do not snap to base.
	_arm_attack_evade_offset()
	match attack_type:
		AttackDataType.AttackType.LEFT_STRAIGHT:
			_show_pose("LEFT_STRAIGHT", texture_left_straight)
		AttackDataType.AttackType.RIGHT_STRAIGHT:
			_show_pose("RIGHT_STRAIGHT", texture_right_straight)
		AttackDataType.AttackType.LEFT_HOOK:
			_show_pose("LEFT_STRAIGHT", texture_left_straight)
		AttackDataType.AttackType.RIGHT_HOOK:
			_show_pose("RIGHT_STRAIGHT", texture_right_straight)
		_:
			_show_pose("IDLE", texture_idle)


func reset_for_new_round() -> void:
	_locked_final_ko = false
	_finisher_freeze = false
	_attack_pose_token += 1
	_hit_release_token += 1
	_cancel_defense_hold()
	_attack_pose_holding = false
	_clear_knockdown_impact()
	_knockdown_offset = Vector2.ZERO
	_evade_passby_offset = Vector2.ZERO
	_snap_attack_miss()
	_action_effect_offset = Vector2.ZERO
	parallax_offset = Vector2.ZERO
	_show_idle()


func _show_idle() -> void:
	if _locked_final_ko:
		return
	_set_priority(Priority.IDLE)
	_refresh_action_offset()
	_show_pose("IDLE", texture_idle)
	_start_breathing()


func _seal_finisher_pose() -> void:
	if not _finisher_freeze or _sprite == null:
		return
	_finisher_sealed = true
	_sealed_texture = _sprite.texture


func _show_pose(state_name: String, texture_path: String) -> void:
	if _finisher_freeze and _finisher_sealed:
		return
	var texture := TextureResolver.try_load(texture_path)
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.offset = Vector2.ZERO
	## Same scale for every pose — never per-pose rescale.
	_sprite.scale = Vector2(opponent_display_scale, opponent_display_scale)
	_sprite.visible = texture != null
	_sync_ghost_pose()
	if texture == null:
		push_warning("OpponentVisual missing texture: %s" % texture_path)
	_apply_composed_transform()
	_set_visual_state(state_name)
	log_opponent_transform("POSE_CHANGE")


func apply_composed_transform() -> void:
	_apply_composed_transform()


func log_opponent_transform(event: String) -> void:
	if not print_opponent_transform or _anchor == null:
		return
	var final_y := _anchor.position.y
	print("[OPP_TRANSFORM]")
	print("event=%s" % event)
	print("pose=%s" % current_visual_state)
	print("base_y=%.1f" % asset_base_position.y)
	print("evade_y=%.1f" % parallax_offset.y)
	print("pass_by_y=%.1f" % _evade_passby_offset.y)
	print("attack_miss_y=%.1f" % _attack_miss_clearance.y)
	print("local_pose_y=0.0")
	print("final_y=%.1f" % final_y)
	print("previous_final_y=%.1f" % _logged_final_y)
	print("position_delta=%.1f" % (final_y - _logged_final_y))
	_logged_final_y = final_y


func _apply_composed_transform() -> void:
	if _anchor == null:
		return
	## final = base + breathing + action + parallax + knockdown drop + impact shake
	_anchor.rotation_degrees = 0.0
	_anchor.position = (
		asset_base_position
		+ breathing_offset
		+ _action_effect_offset
		+ parallax_offset
		+ _knockdown_offset
		+ _knockdown_impact_offset
	)
	if _sprite != null:
		_sprite.scale = Vector2(opponent_display_scale, opponent_display_scale)
		_sprite.rotation_degrees = 0.0


func _play_knockdown_impact_shake() -> void:
	## One-shot on knockdown entry only. Count loop must not re-trigger this.
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
			Vector2.ZERO,
			captured,
			step_dur * 0.45
		)
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
	if _locked_final_ko or _finisher_freeze or _priority != Priority.IDLE:
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
	breathing_offset = Vector2(value.x, maxf(value.y, 0.0))
	_apply_composed_transform()


func _sync_ghost_pose() -> void:
	if _sprite == null:
		return
	_sprite.modulate = Color(1, 1, 1, 1)
	for ghost in [_ghost_a, _ghost_b]:
		if ghost == null:
			continue
		ghost.texture = _sprite.texture
		ghost.centered = false
		ghost.offset = Vector2.ZERO
		ghost.scale = _sprite.scale


func _set_priority(priority: Priority) -> void:
	_priority = priority


func _set_visual_state(state_name: String) -> void:
	current_visual_state = state_name
	if _debug_label != null:
		_debug_label.visible = show_visual_debug
		_debug_label.text = "OPPONENT VISUAL: %s" % state_name
	visual_state_changed.emit(state_name)
