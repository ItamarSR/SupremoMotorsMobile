extends Control
class_name Minimap
# Minimapa (norte para cima girando com o carro) + GPS: seta/linha ate o objetivo da missao.

const SCALE := 0.55

var world: WorldBuilder
var player: SupremoCar
var police: Array = []
var target := Vector3.INF

func _ready() -> void:
  clip_contents = true
  custom_minimum_size = Vector2(190, 190)
  size = Vector2(190, 190)

func _to_map(world_pos: Vector3, heading_phi: float) -> Vector2:
  var d := Vector2(world_pos.x - player.global_position.x, world_pos.z - player.global_position.z)
  return size * 0.5 + d.rotated(heading_phi) * SCALE

func _draw() -> void:
  draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.1, 0.78), true)
  draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.6, 1.0, 0.9), false, 2.0)
  if player == null or not is_instance_valid(player) or world == null:
    return
  var yaw: float = player.global_rotation.y
  var f := Vector2(-sin(yaw), -cos(yaw))
  var phi: float = -PI * 0.5 - atan2(f.y, f.x)
  var road_col := Color(0.4, 0.45, 0.55, 0.9)
  for r in WorldBuilder.ROADS:
    draw_line(_to_map(Vector3(r, 0, -205), phi), _to_map(Vector3(r, 0, 245), phi), road_col, 5.0 * SCALE * 2.0)
    draw_line(_to_map(Vector3(-205, 0, r), phi), _to_map(Vector3(205, 0, r), phi), road_col, 5.0 * SCALE * 2.0)
  draw_line(_to_map(Vector3(-285, 0, WorldBuilder.HIGHWAY_Z), phi), _to_map(Vector3(285, 0, WorldBuilder.HIGHWAY_Z), phi), Color(0.6, 0.65, 0.4, 0.9), 6.0)
  for id in world.pois:
    var p: Dictionary = world.pois[id]
    var pt := _to_map(p["pos"], phi)
    draw_circle(pt, 4.0, Color(1.0, 0.8, 0.2))
  for c in police:
    if is_instance_valid(c):
      draw_circle(_to_map((c as Node3D).global_position, phi), 4.5, Color(1.0, 0.1, 0.1))
  if target != Vector3.INF:
    var tp := _to_map(target, phi)
    var center := size * 0.5
    var clamped := Vector2(clampf(tp.x, 8.0, size.x - 8.0), clampf(tp.y, 8.0, size.y - 8.0))
    draw_line(center, clamped, Color(0.2, 1.0, 0.5, 0.9), 2.0)
    draw_circle(clamped, 6.0, Color(0.2, 1.0, 0.5))
    var dist := Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length()
    draw_string(ThemeDB.fallback_font, Vector2(6, size.y - 6), "GPS %d m" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 1.0, 0.6))
  var c0 := size * 0.5
  draw_colored_polygon(PackedVector2Array([c0 + Vector2(0, -9), c0 + Vector2(6, 7), c0 + Vector2(-6, 7)]), Color(0.3, 0.8, 1.0))

func _process(_delta: float) -> void:
  queue_redraw()
