extends Node
class_name TrafficSystem
# Semaforos sincronizados nos 16 cruzamentos + carros NPC que seguem a malha viaria,
# trafegam pela direita, param no vermelho e freiam diante de obstaculos.
# NAO ha pedestres nesta versao.

const CYCLE := 28.0
const LANE := 3.5
const NPC_MODELS := ["gol_gl_1988", "uno_mille_1996", "fusca_1974", "opala_ss_1976"]
const NPC_COLORS := ["#f1f1ee", "#c9ced6", "#101216", "#b8211f", "#1e5fd8", "#e8c01a"]

var world: WorldBuilder
var container: Node3D
var npcs: Array = []
var light_mats: Array = []
var _t := 0.0

func setup(p_world: WorldBuilder, p_container: Node3D, npc_count: int = 8) -> void:
  world = p_world
  container = p_container
  _build_lights()
  for i in range(npc_count):
    _spawn_npc()

func light_state(axis: String) -> String:
  var t: float = fposmod(_t, CYCLE)
  if axis == "ns":
    if t < 12.0:
      return "verde"
    return "amarelo" if t < 14.0 else "vermelho"
  if t < 14.0:
    return "vermelho"
  return "verde" if t < 26.0 else "amarelo"

func _color_for(state: String) -> Color:
  match state:
    "verde":
      return Color(0.1, 1.0, 0.3)
    "amarelo":
      return Color(1.0, 0.8, 0.1)
    _:
      return Color(1.0, 0.1, 0.1)

func _build_lights() -> void:
  var holder := Node3D.new()
  holder.name = "Semaforos"
  holder.add_to_group("decoration")
  container.add_child(holder)
  var pole := StandardMaterial3D.new()
  pole.albedo_color = Color(0.15, 0.15, 0.17)
  for rx in WorldBuilder.ROADS:
    for rz in WorldBuilder.ROADS:
      for def in [["ns", Vector3(8.5, 0, -8.5)], ["ew", Vector3(-8.5, 0, 8.5)]]:
        var base := Vector3(rx, 0.0, rz) + (def[1] as Vector3)
        var mp := MeshInstance3D.new()
        var cm := CylinderMesh.new()
        cm.top_radius = 0.1
        cm.bottom_radius = 0.1
        cm.height = 5.0
        mp.mesh = cm
        mp.material_override = pole
        mp.position = base + Vector3(0, 2.5, 0)
        holder.add_child(mp)
        var lamp := MeshInstance3D.new()
        var sm := SphereMesh.new()
        sm.radius = 0.38
        sm.height = 0.76
        lamp.mesh = sm
        var lm := StandardMaterial3D.new()
        lm.emission_enabled = true
        lm.emission_energy_multiplier = 2.5
        lamp.material_override = lm
        lamp.position = base + Vector3(0, 5.2, 0)
        holder.add_child(lamp)
        light_mats.append({"mat": lm, "axis": def[0]})
  _refresh_lights()

func _refresh_lights() -> void:
  for e in light_mats:
    var c := _color_for(light_state(str(e["axis"])))
    var m: StandardMaterial3D = e["mat"]
    m.albedo_color = c
    m.emission = c

func _node_pos(i: int, j: int) -> Vector3:
  return Vector3(WorldBuilder.ROADS[i], 0.0, WorldBuilder.ROADS[j])

func _spawn_npc() -> void:
  var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
  for attempt in range(20):
    var i := randi() % 4
    var j := randi() % 4
    var d: Vector2i = dirs[randi() % 4]
    var pi := i - d.x
    var pj := j - d.y
    if pi < 0 or pi > 3 or pj < 0 or pj > 3:
      continue
    var v := {
      "uid": "", "model": NPC_MODELS[randi() % NPC_MODELS.size()], "color": NPC_COLORS[randi() % NPC_COLORS.size()],
      "tuning": [], "plate": Game.gen_plate(), "fuel_l": 40.0
    }
    var car := SupremoCar.make(v)
    var right := Vector3(-float(d.y), 0.0, float(d.x))
    var tgt := _node_pos(i, j) + right * LANE
    var start := tgt - Vector3(float(d.x), 0.0, float(d.y)) * 55.0
    car.position = Vector3(start.x, 1.0, start.z)
    car.rotation.y = atan2(-float(d.x), -float(d.y))
    car.ai_enabled = true
    car.ai_max_kmh = randf_range(30.0, 42.0)
    car.ai_target = tgt
    container.add_child(car)
    npcs.append({"car": car, "i": i, "j": j, "dx": d.x, "dz": d.y})
    return

func _process(delta: float) -> void:
  _t += delta
  _refresh_lights()

func _physics_process(_delta: float) -> void:
  for n in npcs:
    var car: SupremoCar = n["car"]
    if not is_instance_valid(car):
      continue
    var dx: int = n["dx"]
    var dz: int = n["dz"]
    var right := Vector3(-float(dz), 0.0, float(dx))
    var tgt := _node_pos(n["i"], n["j"]) + right * LANE
    car.ai_target = tgt
    var flat := Vector3(car.global_position.x - tgt.x, 0.0, car.global_position.z - tgt.z)
    var dist := flat.length()
    var axis := "ew" if dx != 0 else "ns"
    car.ai_hold = dist > 7.0 and dist < 18.0 and light_state(axis) != "verde"
    if dist < 9.0:
      _choose_next(n)

func _choose_next(n: Dictionary) -> void:
  var d := Vector2i(n["dx"], n["dz"])
  var options := [d, Vector2i(-d.y, d.x), Vector2i(d.y, -d.x)]
  var weights := [0.6, 0.2, 0.2]
  var valid: Array = []
  var wsum := 0.0
  for k in range(3):
    var o: Vector2i = options[k]
    var ni: int = int(n["i"]) + o.x
    var nj: int = int(n["j"]) + o.y
    if ni >= 0 and ni <= 3 and nj >= 0 and nj <= 3:
      valid.append([o, float(weights[k])])
      wsum += float(weights[k])
  var chosen := Vector2i(-d.x, -d.y)
  if not valid.is_empty():
    var r := randf() * wsum
    for e in valid:
      r -= float(e[1])
      if r <= 0.0:
        chosen = e[0]
        break
  n["dx"] = chosen.x
  n["dz"] = chosen.y
  n["i"] = int(n["i"]) + chosen.x
  n["j"] = int(n["j"]) + chosen.y
