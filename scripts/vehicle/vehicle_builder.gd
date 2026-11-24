extends RefCounted
class_name VehicleBuilder
# Gera a parte VISUAL dos veiculos por codigo (placeholders procedurais estilizados:
# hatch, fusca, cupe e moto). NAO sao modelos 3D reais; para modelos reais troque
# build() por um loader de glTF mantendo o mesmo dicionario de retorno.

const MOUNT_Y := -0.10      # altura (local) de onde sai o raycast da suspensao
const REST_LEN := 0.30      # curso total da suspensao
const SAG := 0.10           # compressao em repouso

static func ground_offset(def: Dictionary) -> float:
  # Distancia da origem do corpo ate o chao em repouso.
  var r: float = float(def.get("raio_roda_m", 0.3))
  return -MOUNT_Y + (REST_LEN - SAG) + r

static func mat(color: Color, rough: float = 0.45, metal: float = 0.1) -> StandardMaterial3D:
  var m := StandardMaterial3D.new()
  m.albedo_color = color
  m.roughness = rough
  m.metallic = metal
  return m

static func glow_mat(color: Color, energy: float) -> StandardMaterial3D:
  var m := StandardMaterial3D.new()
  m.albedo_color = color
  m.emission_enabled = true
  m.emission = color
  m.emission_energy_multiplier = energy
  return m

static func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
  var mi := MeshInstance3D.new()
  var b := BoxMesh.new()
  b.size = size
  mi.mesh = b
  mi.position = pos
  mi.material_override = material
  parent.add_child(mi)
  return mi

static func _ellipsoid(parent: Node3D, scale_v: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
  var mi := MeshInstance3D.new()
  var s := SphereMesh.new()
  s.radius = 1.0
  s.height = 2.0
  s.radial_segments = 20
  s.rings = 10
  mi.mesh = s
  mi.scale = scale_v
  mi.position = pos
  mi.material_override = material
  parent.add_child(mi)
  return mi

## Retorna {root, body_root, wheels[{steer,spin}], body_mats[], tail_mats[], spots[], bar[], wheel_points[], h0}
static func build(def: Dictionary, color_hex: String, stats: Dictionary, plate: String, with_lights: bool) -> Dictionary:
  var root := Node3D.new()
  var body_root := Node3D.new()
  root.add_child(body_root)
  var r: float = float(def.get("raio_roda_m", 0.3))
  var dims: Dictionary = def.get("dimensoes", {})
  var L: float = float(dims.get("comp", 4.0))
  var W: float = float(dims.get("larg", 1.7))
  var H: float = float(dims.get("alt", 1.4))
  var wb: float = float(dims.get("entre_eixos", 2.4))
  var track: float = float(dims.get("bitola", 1.4))
  var h0 := ground_offset(def)
  var style: String = str(def.get("estilo", "hatch"))
  var paint := mat(Color.from_string(color_hex, Color(0.7, 0.7, 0.7)), 0.28, 0.45)
  var glass := mat(Color(0.05, 0.08, 0.12), 0.1, 0.0)
  var dark := mat(Color(0.04, 0.04, 0.05), 0.7, 0.0)
  var chrome := mat(Color(0.75, 0.78, 0.82), 0.2, 0.9)
  var head_mat := glow_mat(Color(1.0, 0.96, 0.8), 1.6)
  var tail_mat := glow_mat(Color(0.8, 0.02, 0.02), 1.0)
  var result := {
    "root": root, "body_root": body_root, "wheels": [], "body_mats": [paint],
    "tail_mats": [tail_mat], "spots": [], "bar": [], "wheel_points": [], "h0": h0
  }
  # Rebaixamento visual (suspensao): desloca apenas a carroceria.
  body_root.position.y = float(stats.get("ride_mm", 0.0)) / 1000.0

  var is_moto := style == "moto"
  if is_moto:
    _build_moto(body_root, def, paint, dark, chrome, head_mat, tail_mat, h0)
  elif style == "fusca":
    var gy := func(y: float) -> float: return y - h0
    _ellipsoid(body_root, Vector3(W * 0.5, H * 0.26, L * 0.49), Vector3(0, gy.call(0.20 + H * 0.28), 0), paint)
    _ellipsoid(body_root, Vector3(W * 0.43, H * 0.24, L * 0.26), Vector3(0, gy.call(0.20 + H * 0.58), L * 0.04), glass)
    _ellipsoid(body_root, Vector3(W * 0.44, H * 0.09, L * 0.27), Vector3(0, gy.call(0.20 + H * 0.78), L * 0.04), paint)
    _box(body_root, Vector3(W * 1.02, 0.06, 0.12), Vector3(0, gy.call(0.33), -L * 0.5 + 0.05), chrome)
    _box(body_root, Vector3(W * 1.02, 0.06, 0.12), Vector3(0, gy.call(0.33), L * 0.5 - 0.05), chrome)
    for sx in [-1.0, 1.0]:
      var hl := MeshInstance3D.new()
      var sm := SphereMesh.new()
      sm.radius = 0.1
      sm.height = 0.2
      hl.mesh = sm
      hl.position = Vector3(sx * W * 0.3, gy.call(0.20 + H * 0.42), -L * 0.46)
      hl.material_override = head_mat
      body_root.add_child(hl)
    _box(body_root, Vector3(0.22, 0.12, 0.06), Vector3(-W * 0.34, gy.call(0.20 + H * 0.38), L * 0.47), tail_mat)
    _box(body_root, Vector3(0.22, 0.12, 0.06), Vector3(W * 0.34, gy.call(0.20 + H * 0.38), L * 0.47), tail_mat)
  else:
    # hatch / coupe: caixa baixa + cabine envidracada + teto na cor da carroceria
    var coupe := style == "coupe"
    var low_h := H * (0.46 if coupe else 0.40)
    var cab_h := H * (0.34 if coupe else 0.36)
    var cab_len := L * (0.40 if coupe else 0.52)
    var cab_shift := L * (0.10 if coupe else 0.04)
    var y_low := -h0 + 0.20 + low_h * 0.5
    var y_cab := -h0 + 0.20 + low_h + cab_h * 0.5
    var used_model := _add_model(body_root, str(def.get("id", "")), style, bool(def.get("policia", false)), L, W, H, h0, paint)
    if not used_model:
      _box(body_root, Vector3(W, low_h, L), Vector3(0, y_low, 0), paint)
      _box(body_root, Vector3(W * 0.88, cab_h, cab_len), Vector3(0, y_cab, cab_shift), glass)
      _box(body_root, Vector3(W * 0.90, 0.05, cab_len * 1.02), Vector3(0, y_cab + cab_h * 0.5, cab_shift), paint)
      _box(body_root, Vector3(W * 1.02, H * 0.12, 0.2), Vector3(0, y_low - low_h * 0.25, -L * 0.5), dark)
      _box(body_root, Vector3(W * 1.02, H * 0.12, 0.2), Vector3(0, y_low - low_h * 0.25, L * 0.5), dark)
      _box(body_root, Vector3(W * 0.5, H * 0.09, 0.05), Vector3(0, y_low + low_h * 0.1, -L * 0.5 - 0.01), dark)
      for sx in [-1.0, 1.0]:
        _box(body_root, Vector3(W * 0.2, H * 0.09, 0.07), Vector3(sx * W * 0.36, y_low + low_h * 0.15, -L * 0.5), head_mat)
        _box(body_root, Vector3(W * 0.2, H * 0.09, 0.07), Vector3(sx * W * 0.36, y_low + low_h * 0.15, L * 0.5), tail_mat)
    # aerofolio (tuning)
    if bool(stats.get("spoiler", false)):
      var y_sp := y_cab + cab_h * 0.5 + (0.02 if coupe else 0.0)
      if coupe:
        y_sp = y_low + low_h * 0.5 + 0.12
      _box(body_root, Vector3(W * 0.92, 0.04, 0.26), Vector3(0, y_sp + 0.16, L * 0.47), dark)
      _box(body_root, Vector3(0.05, 0.16, 0.2), Vector3(-W * 0.3, y_sp + 0.08, L * 0.47), dark)
      _box(body_root, Vector3(0.05, 0.16, 0.2), Vector3(W * 0.3, y_sp + 0.08, L * 0.47), dark)
    # viatura: barra de luzes e faixa
    if bool(def.get("policia", false)):
      var red := glow_mat(Color(1, 0.05, 0.05), 2.5)
      var blue := glow_mat(Color(0.1, 0.25, 1.0), 2.5)
      var bar_y := y_cab + cab_h * 0.5 + 0.1
      var br := _box(body_root, Vector3(0.45, 0.1, 0.22), Vector3(-0.3, bar_y, cab_shift), red)
      var bb := _box(body_root, Vector3(0.45, 0.1, 0.22), Vector3(0.3, bar_y, cab_shift), blue)
      result["bar"] = [br, bb]
      if not used_model:
        _box(body_root, Vector3(W * 1.005, 0.14, L * 0.6), Vector3(0, y_low, 0.0), mat(Color(0.05, 0.12, 0.45), 0.4, 0.2))
        for sx in [-1.0, 1.0]:
          var lab := Label3D.new()
          lab.text = "POLICIA"
          lab.font_size = 36
          lab.pixel_size = 0.004
          lab.modulate = Color(1, 1, 1)
          lab.position = Vector3(sx * (W * 0.5 + 0.01), y_low, 0.0)
          lab.rotation_degrees = Vector3(0, 90.0 * sx, 0)
          body_root.add_child(lab)
    # neon
    if bool(stats.get("neon", false)):
      _box(body_root, Vector3(W * 0.8, 0.02, L * 0.8), Vector3(0, -h0 + 0.12, 0), glow_mat(Color(0.1, 0.4, 1.0), 3.0))
      var nl := OmniLight3D.new()
      nl.light_color = Color(0.1, 0.4, 1.0)
      nl.light_energy = 1.4
      nl.omni_range = 4.5
      nl.position = Vector3(0, -h0 + 0.2, 0)
      body_root.add_child(nl)
    # placa (Mercosul ficticia): fundo branco + texto
    var plate_y := -h0 + 0.20 + low_h * 0.28
    _box(body_root, Vector3(0.42, 0.14, 0.01), Vector3(0, plate_y, L * 0.5 + 0.11), mat(Color(0.95, 0.95, 0.95), 0.6, 0.0))
    var pl := Label3D.new()
    pl.text = plate
    pl.font_size = 40
    pl.pixel_size = 0.0028
    pl.modulate = Color(0.05, 0.1, 0.4)
    pl.position = Vector3(0, plate_y, L * 0.5 + 0.12)
    body_root.add_child(pl)

  # faróis (SpotLight) so no veiculo do jogador (custo de iluminacao em celular)
  if with_lights:
    for sx in [-1.0, 1.0]:
      var sp := SpotLight3D.new()
      sp.spot_range = 32.0
      sp.spot_angle = 38.0
      sp.light_energy = 2.2
      sp.light_color = Color(1.0, 0.95, 0.82)
      sp.position = Vector3(sx * (0.0 if is_moto else W * 0.34), -h0 + 0.62, -L * 0.5)
      sp.visible = false
      body_root.add_child(sp)
      result["spots"].append(sp)

  # Rodas e pontos de suspensao
  var rim_hex: String = str(stats.get("rim_color", ""))
  var rim_color := Color.from_string(rim_hex, Color(0.75, 0.78, 0.82)) if rim_hex != "" else Color(0.75, 0.78, 0.82)
  var tire := mat(Color(0.05, 0.05, 0.055), 0.9, 0.0)
  var rim := mat(rim_color, 0.25, 0.9)
  var pts: Array = []
  if is_moto:
    pts = [Vector3(0, MOUNT_Y, -wb * 0.5), Vector3(0, MOUNT_Y, wb * 0.5)]
  else:
    pts = [Vector3(-track * 0.5, MOUNT_Y, -wb * 0.5), Vector3(track * 0.5, MOUNT_Y, -wb * 0.5),
      Vector3(-track * 0.5, MOUNT_Y, wb * 0.5), Vector3(track * 0.5, MOUNT_Y, wb * 0.5)]
  var tire_w := 0.12 if is_moto else 0.22
  for p in pts:
    var steer_node := Node3D.new()
    var spin_node := Node3D.new()
    steer_node.add_child(spin_node)
    var t := MeshInstance3D.new()
    var tc := CylinderMesh.new()
    tc.top_radius = r
    tc.bottom_radius = r
    tc.height = tire_w
    t.mesh = tc
    t.rotation.z = PI * 0.5
    t.material_override = tire
    spin_node.add_child(t)
    var rm := MeshInstance3D.new()
    var rc := CylinderMesh.new()
    rc.top_radius = r * 0.62
    rc.bottom_radius = r * 0.62
    rc.height = tire_w + 0.02
    rm.mesh = rc
    rm.rotation.z = PI * 0.5
    rm.material_override = rim
    spin_node.add_child(rm)
    steer_node.position = p + Vector3.DOWN * (REST_LEN - SAG)
    root.add_child(steer_node)
    result["wheels"].append({"steer": steer_node, "spin": spin_node})
  result["wheel_points"] = pts
  return result

## Modelos CC0 (Kenney Car Kit) usados como carroceria. Fusca e moto seguem procedurais.
const MODEL_DIR := "res://assets/models/"
const MODEL_BY_ID := {
  "gol_gl_1988": "hatchback-sports", "uno_mille_1996": "hatchback-sports",
  "opala_ss_1976": "sedan", "skyline_r34": "sedan-sports", "strada_2020": "delivery"
}
const MODEL_YAW_DEG := 180.0   # se o carro aparecer de re, troque para 0.0

static func _add_model(body_root: Node3D, id: String, style: String, police: bool, L: float, W: float, H: float, h0: float, paint: StandardMaterial3D) -> bool:
  var name: String = "police" if police else str(MODEL_BY_ID.get(id, "hatchback-sports" if style == "hatch" else "sedan-sports"))
  var path := MODEL_DIR + name + ".glb"
  if not ResourceLoader.exists(path):
    return false
  var ps = load(path)
  if not (ps is PackedScene):
    return false
  var inst: Node3D = (ps as PackedScene).instantiate()
  var holder := Node3D.new()
  holder.add_child(inst)
  # esconde as rodas do modelo (o jogo usa rodas proprias, com suspensao)
  _hide_wheels(inst)
  var box := _collect_aabb(inst, Transform3D.IDENTITY, AABB(), false)
  if box.size.length() < 0.01:
    holder.free()
    return false
  var length: float = maxf(box.size.x, box.size.z)
  var s: float = L / length
  holder.scale = Vector3.ONE * s
  holder.rotation_degrees.y = MODEL_YAW_DEG
  # centraliza no plano e apoia a base na altura do chao do corpo
  var c := box.get_center()
  inst.position = Vector3(-c.x, -box.position.y, -c.z)
  holder.position = Vector3(0, -h0 + 0.17, 0)
  _tint(inst, paint)
  body_root.add_child(holder)
  return true

static func _hide_wheels(n: Node) -> void:
  for ch in n.get_children():
    if str(ch.name).to_lower().contains("wheel") and ch is Node3D:
      (ch as Node3D).visible = false
    else:
      _hide_wheels(ch)

static func _collect_aabb(n: Node, xf: Transform3D, acc: AABB, has: bool) -> AABB:
  var t := xf
  if n is Node3D:
    t = xf * (n as Node3D).transform
    if not (n as Node3D).visible:
      return acc
  var got := has
  var out := acc
  if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
    var b: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
    out = b if not got else out.merge(b)
    got = true
  for ch in n.get_children():
    var sub := _collect_aabb(ch, t, out, got)
    if sub.size.length() > 0.0:
      out = sub
      got = true
  return out

static func _tint(n: Node, paint: StandardMaterial3D) -> void:
  if n is MeshInstance3D:
    var mi := n as MeshInstance3D
    if mi.mesh != null:
      for i in range(mi.mesh.get_surface_count()):
        var m = mi.mesh.surface_get_material(i)
        if m is StandardMaterial3D:
          var d := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
          d.albedo_color = paint.albedo_color.lerp(Color.WHITE, 0.25)
          mi.set_surface_override_material(i, d)
  for ch in n.get_children():
    _tint(ch, paint)

static func _build_moto(body_root: Node3D, def: Dictionary, paint: Material, dark: Material, chrome: Material, head_mat: Material, tail_mat: Material, h0: float) -> void:
  var dims: Dictionary = def.get("dimensoes", {})
  var L: float = float(dims.get("comp", 2.0))
  var wb: float = float(dims.get("entre_eixos", 1.36))
  var y0 := -h0 + 0.3
  # tanque
  var tank := MeshInstance3D.new()
  var cap := CapsuleMesh.new()
  cap.radius = 0.17
  cap.height = 0.62
  tank.mesh = cap
  tank.rotation.x = PI * 0.5
  tank.position = Vector3(0, y0 + 0.62, -wb * 0.12)
  tank.material_override = paint
  body_root.add_child(tank)
  _box(body_root, Vector3(0.22, 0.30, 0.55), Vector3(0, y0 + 0.28, 0.0), dark)                       # motor
  _box(body_root, Vector3(0.24, 0.08, 0.62), Vector3(0, y0 + 0.62, wb * 0.2), mat(Color(0.05, 0.05, 0.06), 0.8, 0.0))  # banco
  _box(body_root, Vector3(0.26, 0.04, 0.4), Vector3(0, y0 + 0.5, wb * 0.5 + 0.1), paint)             # paralama traseiro
  _box(body_root, Vector3(0.05, 0.62, 0.05), Vector3(0, y0 + 0.4, -wb * 0.5 + 0.05), chrome)         # garfo
  _box(body_root, Vector3(0.7, 0.04, 0.04), Vector3(0, y0 + 0.78, -wb * 0.5 + 0.18), dark)           # guidao
  var hl := MeshInstance3D.new()
  var sm := SphereMesh.new()
  sm.radius = 0.1
  sm.height = 0.2
  hl.mesh = sm
  hl.position = Vector3(0, y0 + 0.66, -wb * 0.5 - 0.05)
  hl.material_override = head_mat
  body_root.add_child(hl)
  _box(body_root, Vector3(0.14, 0.06, 0.05), Vector3(0, y0 + 0.5, wb * 0.5 + 0.32), tail_mat)
  # escapamento
  var ex := MeshInstance3D.new()
  var ec := CylinderMesh.new()
  ec.top_radius = 0.045
  ec.bottom_radius = 0.045
  ec.height = 0.7
  ex.mesh = ec
  ex.rotation.x = PI * 0.5
  ex.position = Vector3(0.16, y0 + 0.18, wb * 0.3)
  ex.material_override = chrome
  body_root.add_child(ex)
  # piloto (silhueta)
  var torso := MeshInstance3D.new()
  var tc := CapsuleMesh.new()
  tc.radius = 0.15
  tc.height = 0.62
  torso.mesh = tc
  torso.position = Vector3(0, y0 + 1.0, wb * 0.12)
  torso.rotation.x = deg_to_rad(-22.0)
  torso.material_override = mat(Color(0.1, 0.12, 0.2), 0.8, 0.0)
  body_root.add_child(torso)
  var head := MeshInstance3D.new()
  var hs := SphereMesh.new()
  hs.radius = 0.13
  hs.height = 0.26
  head.mesh = hs
  head.position = Vector3(0, y0 + 1.42, -wb * 0.02)
  head.material_override = mat(Color(0.9, 0.9, 0.92), 0.3, 0.2)
  body_root.add_child(head)
  _box(body_root, Vector3(0.13, 0.5, 0.15), Vector3(0.17, y0 + 0.62, -wb * 0.02), mat(Color(0.1, 0.12, 0.2), 0.8, 0.0))
  _box(body_root, Vector3(0.13, 0.5, 0.15), Vector3(-0.17, y0 + 0.62, -wb * 0.02), mat(Color(0.1, 0.12, 0.2), 0.8, 0.0))
