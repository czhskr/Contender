class_name FatigueVignette
extends CanvasLayer

## Edge-only fatigue read. HUD stays on a higher CanvasLayer.
## Intensity follows Player Stamina. Ghosting is a separate Exhausted flag.

@export var player_stamina: Node
@export var opponent_visual: Node

@export_range(0.05, 1.0, 0.01) var inner_radius := 0.42
@export_range(0.05, 1.5, 0.01) var edge_softness := 0.7
@export_range(0.0, 1.0, 0.01) var max_edge_alpha := 0.62
@export_range(0.5, 4.0, 0.05) var fatigue_exponent := 2.0

var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = 1
	setup()


func setup() -> void:
	_build()


func bind(stamina: Node, opponent: Node) -> void:
	player_stamina = stamina
	opponent_visual = opponent
	if is_inside_tree():
		_ready()


func vignette_intensity_for(current_stamina: float, max_stamina: float) -> float:
	var fatigue := clampf(1.0 - current_stamina / maxf(max_stamina, 0.001), 0.0, 1.0)
	return pow(fatigue, fatigue_exponent)


func _build() -> void:
	if _rect != null:
		return
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.5) = 0.42;
uniform float edge_softness : hint_range(0.01, 1.5) = 0.7;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.62;
void fragment() {
	float dist = length((UV - vec2(0.5)) * vec2(1.777, 1.0));
	float edge = smoothstep(inner_radius, inner_radius + edge_softness, dist);
	COLOR = vec4(0.0, 0.0, 0.0, edge * intensity * max_alpha);
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect = ColorRect.new()
	_rect.name = "Vignette"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(1, 1, 1, 1)
	_rect.material = _material
	add_child(_rect)
	_material.set_shader_parameter("inner_radius", inner_radius)
	_material.set_shader_parameter("edge_softness", edge_softness)
	_material.set_shader_parameter("max_alpha", max_edge_alpha)
	_material.set_shader_parameter("intensity", 0.0)
	if player_stamina != null and not player_stamina.stamina_changed.is_connected(_on_stamina_changed):
		player_stamina.stamina_changed.connect(_on_stamina_changed)
		_on_stamina_changed(player_stamina.current_stamina, player_stamina.max_stamina)
	if player_stamina != null and player_stamina.has_signal("exhausted_changed"):
		if not player_stamina.exhausted_changed.is_connected(_on_exhausted_changed):
			player_stamina.exhausted_changed.connect(_on_exhausted_changed)
		if "is_exhausted" in player_stamina:
			_on_exhausted_changed(player_stamina.is_exhausted)


func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(
		"intensity",
		vignette_intensity_for(current_stamina, max_stamina)
	)


func _on_exhausted_changed(active: bool) -> void:
	if opponent_visual != null and opponent_visual.has_method("set_exhausted_ghost"):
		opponent_visual.set_exhausted_ghost(active)
