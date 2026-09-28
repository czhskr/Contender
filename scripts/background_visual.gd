class_name BackgroundVisual
extends Node2D

## Crowd (far) + Ring (near). Ring transparency reveals crowd.
## Parallax offsets are additive and composed on top of layout bases.

const TextureResolver = preload("res://scripts/visual_texture_resolver.gd")

@export var viewport_size := Vector2(1152, 648)
@export var crowd_texture_path := "res://assets/background/bg_crowd.png"
@export var ring_texture_path := "res://assets/background/bg_ring.png"

@export_group("Layout")
## Distance from viewport bottom to the image bottom edge.
@export var bottom_safe_margin := 0.0
## If true, scale layers to cover the viewport (may crop). Else fit width.
@export var cover_viewport := true

@export_group("Parallax Overscan")
## One-sided bleed in pixels. Defaults match max Crowd/Ring motion plus a small safety.
## CombatVisualRoot.set_motion_bleed overwrites these from the live parallax exports.
@export var crowd_bleed := Vector2(24, 24)
@export var ring_bleed := Vector2(49, 48)

@export_group("Parallax Offsets")
## Additive offsets driven by CombatVisualRoot during Player Slip.
@export var crowd_parallax_offset := Vector2.ZERO
@export var ring_parallax_offset := Vector2.ZERO

var _crowd: Sprite2D
var _ring: Sprite2D
var _crowd_base := Vector2.ZERO
var _ring_base := Vector2.ZERO


func _ready() -> void:
	_crowd = _make_layer("CrowdLayer")
	_ring = _make_layer("RingLayer")
	_setup_layer(_crowd, crowd_texture_path)
	_setup_layer(_ring, ring_texture_path)
	_apply_composed_positions()


func set_crowd_parallax(offset: Vector2) -> void:
	crowd_parallax_offset = offset
	_apply_composed_positions()


func set_ring_parallax(offset: Vector2) -> void:
	ring_parallax_offset = offset
	_apply_composed_positions()


func _make_layer(node_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.centered = true
	sprite.z_as_relative = true
	add_child(sprite)
	return sprite


func _setup_layer(sprite: Sprite2D, path: String) -> void:
	var texture := TextureResolver.try_load(path)
	if texture == null:
		push_warning("BackgroundVisual missing texture: %s" % path)
		sprite.visible = false
		return

	sprite.texture = texture
	sprite.visible = true
	## Bottom-center of the texture sits on the baseline.
	sprite.offset = Vector2(0.0, -float(texture.get_height()) * 0.5)

	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var bleed := crowd_bleed if sprite == _crowd else ring_bleed
	_layout_sprite(sprite, tex_size, bleed)

	if sprite == _crowd:
		_crowd_base = sprite.position
	else:
		_ring_base = sprite.position


func set_motion_bleed(crowd: Vector2, ring: Vector2) -> void:
	crowd_bleed = Vector2(maxf(crowd.x, 0.0), maxf(crowd.y, 0.0))
	ring_bleed = Vector2(maxf(ring.x, 0.0), maxf(ring.y, 0.0))
	if _crowd != null and _crowd.texture != null:
		_layout_sprite(
			_crowd,
			Vector2(_crowd.texture.get_width(), _crowd.texture.get_height()),
			crowd_bleed
		)
		_crowd_base = _crowd.position
	if _ring != null and _ring.texture != null:
		_layout_sprite(
			_ring,
			Vector2(_ring.texture.get_width(), _ring.texture.get_height()),
			ring_bleed
		)
		_ring_base = _ring.position
	_apply_composed_positions()


func _layout_sprite(sprite: Sprite2D, tex_size: Vector2, bleed: Vector2) -> void:
	## Cover scale, then the minimum extra uniform scale that keeps bleed off-screen.
	## Scale stays around the previous visual center (bottom anchor shifts down).
	var cover := _compute_scale(tex_size)
	var covered := tex_size * cover
	var need_w := viewport_size.x + bleed.x * 2.0
	var need_h := viewport_size.y + bleed.y * 2.0
	var factor := 1.0
	if covered.x > 0.0 and covered.y > 0.0:
		factor = maxf(need_w / covered.x, need_h / covered.y)
	factor = maxf(factor, 1.0)
	var scale_factor := cover * factor
	sprite.scale = Vector2(scale_factor, scale_factor)

	var old_h := tex_size.y * cover
	var new_h := tex_size.y * scale_factor
	var baseline_y := viewport_size.y - bottom_safe_margin + (new_h - old_h) * 0.5
	sprite.position = Vector2(viewport_size.x * 0.5, baseline_y)


func layer_covers_viewport(sprite: Sprite2D, parallax: Vector2) -> bool:
	if sprite == null or sprite.texture == null:
		return false
	var rect := _world_rect(sprite, parallax)
	return (
		rect.position.x <= 0.5
		and rect.position.y <= 0.5
		and rect.end.x >= viewport_size.x - 0.5
		and rect.end.y >= viewport_size.y - 0.5
	)


func layer_visual_center(sprite: Sprite2D) -> Vector2:
	return _world_rect(sprite, Vector2.ZERO).get_center()


func cover_visual_center(tex_size: Vector2) -> Vector2:
	var cover := _compute_scale(tex_size)
	var covered := tex_size * cover
	return Vector2(viewport_size.x * 0.5, viewport_size.y - bottom_safe_margin - covered.y * 0.5)


func _world_rect(sprite: Sprite2D, parallax: Vector2) -> Rect2:
	var local := sprite.get_rect()
	var origin := sprite.position + parallax
	## Node scale is applied to the local rect about the sprite origin.
	var pos := origin + local.position * sprite.scale
	var size := local.size * sprite.scale
	return Rect2(pos, size)


func _compute_scale(tex_size: Vector2) -> float:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return 1.0
	var scale_x := viewport_size.x / tex_size.x
	var scale_y := viewport_size.y / tex_size.y
	if cover_viewport:
		return maxf(scale_x, scale_y)
	return scale_x


func _apply_composed_positions() -> void:
	if _crowd != null:
		_crowd.position = _crowd_base + crowd_parallax_offset
	if _ring != null:
		_ring.position = _ring_base + ring_parallax_offset
