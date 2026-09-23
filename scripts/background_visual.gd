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
	var scale_factor := _compute_scale(tex_size)
	sprite.scale = Vector2(scale_factor, scale_factor)

	var baseline_y := viewport_size.y - bottom_safe_margin
	var base := Vector2(viewport_size.x * 0.5, baseline_y)
	if sprite == _crowd:
		_crowd_base = base
	else:
		_ring_base = base
	sprite.position = base


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
