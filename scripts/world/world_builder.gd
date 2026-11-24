extends Node3D
class_name WorldBuilder
# Gera por codigo o bairro "Vila Supremo": ruas em grade, quarteiroes com predios,
# casas, comercio, POIs (oficina, posto, banco, delegacia, patio, concessionaria...),
# morro com comunidade, rodovia com ponte estaiada e palmeiras. Tudo procedural
# (placeholders de cenario). Dados dos POIs vem de data/world.json.

const ROADS := [-120.0, -40.0, 40.0, 120.0]     # eixos das ruas (x e z)
const ROAD_W := 14.0
const BLOCK := 80.0
const HIGHWAY_Z := 230.0
const WORLD_HALF := 285.0
const LOT_TYPES := ["estacionamento", "garagem", "oficina", "concessionaria", "posto", "patio"]
const PROTECTED_TYPES := ["garagem", "oficina"]

var pois: Dictionary = {}                 # id -> {id,tipo,nome,center:Vector3,pos:Vector3}
var window_mats: Array = []
var lamp_mats: Array = []
var _rng := RandomNumberGenerator.new()
var _window_tex: ImageTexture
var _window_emit: ImageTexture
var _decor_roots: Array = []

func build() -> void:
  _rng.seed = 1989
  _make_window_textures()
  _build_ground_and_roads()
  _build_boundaries()
  var by_cell: Dictionary = {}
  for p in Data.world.get("pois", []):
    by_cell[Vector2i(int(p["ix"]), int(p["iz"]))] = p
    var center := Vector3(float(p["ix"]) * BLOCK, 0.0, float(p["iz"]) * BLOCK)
    pois[str(p["id"])] = {
      "id": str(p["id"]), "tipo": str(p["tipo"]), "nome": str(p["nome"]),
      "center": center, "pos": center + Vector3(0, 0, 28.0)
    }
  var decor := _decor("Arvores")
  var lamps := _decor("Postes")
  for ix in range(-2, 3):
    for iz in range(-2, 3):
      var center := Vector3(float(ix) * BLOCK, 0.0, float(iz) * BLOCK)
      var cell := Vector2i(ix, iz)
      _sidewalk(center)
      if by_cell.has(cell):
        _build_poi(by_cell[cell], center)
        _poi_marker(pois[str(by_cell[cell]["id"])])
      else:
        _build_generic_block(center)
      _lamps_and_trees(center, lamps, decor)
  _build_highway_and_bridge()

func _decor(label: String) -> Node3D:
  var n := Node3D.new()
  n.name = label
  n.add_to_group("decoration")
  add_child(n)
  return n

# ---------------------------------------------------------------- primitivos
func _mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
  var m := StandardMaterial3D.new()
  m.albedo_color = c
  m.roughness = rough
  m.metallic = metal
  return m

func _glow(c: Color, e: float) -> StandardMaterial3D:
  var m := StandardMaterial3D.new()
  m.albedo_color = c
  m.emission_enabled = true
  m.emission = c
  m.emission_energy_multiplier = e
  return m

func _box(parent: Node, size: Vector3, pos: Vector3, material: Material, collide: bool = false) -> Node3D:
  var mi := MeshInstance3D.new()
  var b := BoxMesh.new()
  b.size = size
  mi.mesh = b
  mi.material_override = material
  if collide:
    var body := StaticBody3D.new()
    body.position = pos
    var cs := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = size
    cs.shape = sh
    body.add_child(cs)
    body.add_child(mi)
    parent.add_child(body)
    return body
  mi.position = pos
  parent.add_child(mi)
  return mi

func _cyl(parent: Node, radius: float, height: float, pos: Vector3, material: Material, segments: int = 12) -> MeshInstance3D:
  var mi := MeshInstance3D.new()
  var c := CylinderMesh.new()
  c.top_radius = radius
  c.bottom_radius = radius
  c.height = height
  c.radial_segments = segments
  mi.mesh = c
  mi.position = pos
  mi.material_override = material
  parent.add_child(mi)
  return mi

func _label(parent: Node, text: String, pos: Vector3, size_px: int = 96, color: Color = Color(0.35, 0.7, 1.0), rot_y: float = 0.0) -> Label3D:
  var l := Label3D.new()
  l.text = text
  l.font_size = size_px
  l.pixel_size = 0.03
  l.modulate = color
  l.outline_size = 12
  l.outline_modulate = Color(0.02, 0.05, 0.15)
  l.double_sided = true
  l.position = pos
  l.rotation_degrees.y = rot_y
  parent.add_child(l)
  return l

func _make_window_textures() -> void:
  var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
  var emit := Image.create(128, 128, false, Image.FORMAT_RGBA8)
  img.fill(Color(0.16, 0.18, 0.22))
  emit.fill(Color(0, 0, 0))
  for cx in range(8):
    for cy in range(8):
      var r := Rect2i(cx * 16 + 3, cy * 16 + 3, 10, 10)
      if _rng.randf() < 0.38:
        img.fill_rect(r, Color(1.0, 0.88, 0.5))
        emit.fill_rect(r, Color(1.0, 0.85, 0.45))
      else:
        img.fill_rect(r, Color(0.08, 0.14, 0.22))
  _window_tex = ImageTexture.create_from_image(img)
  _window_emit = ImageTexture.create_from_image(emit)

func _building_mat(tint: Color, w: float, h: float) -> StandardMaterial3D:
  var m := StandardMaterial3D.new()
  m.albedo_color = tint
  m.albedo_texture = _window_tex
  m.emission_enabled = true
  m.emission_texture = _window_emit
  m.emission = Color(1, 1, 1)
  m.emission_energy_multiplier = 0.0
  m.uv1_scale = Vector3(maxf(w / 24.0, 1.0), maxf(h / 24.0, 1.0), 1.0)
  m.roughness = 0.9
  window_mats.append(m)
  return m

# ---------------------------------------------------------------- chao e ruas
func _build_ground_and_roads() -> void:
  var ground := StaticBody3D.new()
  ground.name = "Chao"
  ground.position = Vector3(0, -0.5, 20)
  add_child(ground)
  var gm := MeshInstance3D.new()
  var gb := BoxMesh.new()
  gb.size = Vector3(660, 1, 560)
  gm.mesh = gb
  gm.material_override = _mat(Color(0.16, 0.2, 0.17))
  ground.add_child(gm)
  var cs := CollisionShape3D.new()
  var sh := BoxShape3D.new()
  sh.size = gb.size
  cs.shape = sh
  ground.add_child(cs)

  var asphalt := _mat(Color(0.09, 0.09, 0.1), 0.95)
  var line_mat := _mat(Color(0.9, 0.85, 0.5), 0.8)
  var roads := Node3D.new()
  roads.name = "Ruas"
  add_child(roads)
  for r in ROADS:
    # vertical (eixo z)
    _box(roads, Vector3(ROAD_W, 0.04, 450.0), Vector3(r, 0.02, 20.0), asphalt)
    # horizontal (eixo x)
    _box(roads, Vector3(410.0, 0.04, ROAD_W), Vector3(0.0, 0.021, r), asphalt)
  var dashes := Node3D.new()
  dashes.name = "Faixas"
  dashes.add_to_group("decoration")
  add_child(dashes)
  for r in ROADS:
    for i in range(-25, 26):
      var t := float(i) * 8.0
      if not _near_road(t):
        _box(dashes, Vector3(0.22, 0.03, 3.2), Vector3(r, 0.045, t), line_mat)
        _box(dashes, Vector3(3.2, 0.03, 0.22), Vector3(t, 0.046, r), line_mat)

func _near_road(v: float) -> bool:
  for r in ROADS:
    if absf(v - r) < 9.0:
      return true
  return false

func _build_boundaries() -> void:
  var b := StaticBody3D.new()
  b.name = "Limites"
  add_child(b)
  var defs := [
    [Vector3(2, 20, 560), Vector3(WORLD_HALF + 20, 10, 20)],
    [Vector3(2, 20, 560), Vector3(-WORLD_HALF - 20, 10, 20)],
    [Vector3(660, 20, 2), Vector3(0, 10, 300)],
    [Vector3(660, 20, 2), Vector3(0, 10, -260)]
  ]
  for d in defs:
    var cs := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = d[0]
    cs.shape = sh
    cs.position = d[1]
    b.add_child(cs)

func _sidewalk(center: Vector3) -> void:
  _box(self, Vector3(66.0, 0.15, 66.0), center + Vector3(0, 0.075, 0), _mat(Color(0.42, 0.42, 0.44), 0.95), true)

# ---------------------------------------------------------------- postes e arvores
func _lamps_and_trees(center: Vector3, lamps: Node3D, trees: Node3D) -> void:
  var pole_mat := _mat(Color(0.2, 0.2, 0.22), 0.6, 0.5)
  for sx in [-1.0, 1.0]:
    for sz in [-1.0, 1.0]:
      var p := center + Vector3(sx * 32.0, 0.0, sz * 32.0)
      _cyl(lamps, 0.12, 7.0, p + Vector3(0, 3.5, 0), pole_mat, 6)
      var head := _glow(Color(1.0, 0.85, 0.5), 0.0)
      lamp_mats.append(head)
      var hm := MeshInstance3D.new()
      var sm := SphereMesh.new()
      sm.radius = 0.35
      sm.height = 0.7
      hm.mesh = sm
      hm.material_override = head
      hm.position = p + Vector3(0, 7.1, 0)
      lamps.add_child(hm)
  for i in range(3):
    var tx := center.x + _rng.randf_range(-28.0, 28.0)
    var tz := center.z + (31.0 if _rng.randf() < 0.5 else -31.0)
    if _rng.randf() < 0.6:
      _palm(trees, Vector3(tx, 0.15, tz))
    else:
      _tree(trees, Vector3(tx, 0.15, tz))

func _palm(parent: Node, p: Vector3) -> void:
  var h := _rng.randf_range(6.0, 9.0)
  _cyl(parent, 0.22, h, p + Vector3(0, h * 0.5, 0), _mat(Color(0.35, 0.25, 0.15)), 6)
  var leaf := _mat(Color(0.12, 0.45, 0.16))
  for i in range(6):
    var ang := float(i) / 6.0 * TAU
    var f := _box(parent, Vector3(0.5, 0.06, 3.2), p + Vector3(cos(ang) * 1.3, h + 0.1, sin(ang) * 1.3), leaf)
    f.rotation = Vector3(deg_to_rad(-20.0), -ang + PI * 0.5, 0)

func _tree(parent: Node, p: Vector3) -> void:
  var h := _rng.randf_range(3.0, 4.5)
  _cyl(parent, 0.25, h, p + Vector3(0, h * 0.5, 0), _mat(Color(0.3, 0.2, 0.12)), 6)
  var s := MeshInstance3D.new()
  var sm := SphereMesh.new()
  sm.radius = _rng.randf_range(2.0, 3.0)
  sm.height = sm.radius * 2.0
  s.mesh = sm
  s.material_override = _mat(Color(0.1, 0.4, 0.14))
  s.position = p + Vector3(0, h + 1.2, 0)
  parent.add_child(s)

# ---------------------------------------------------------------- quarteirao generico
func _build_generic_block(center: Vector3) -> void:
  var kind := _rng.randi() % 3
  var tints := [Color(0.75, 0.7, 0.62), Color(0.6, 0.66, 0.74), Color(0.78, 0.74, 0.7), Color(0.7, 0.55, 0.5), Color(0.55, 0.62, 0.58)]
  if kind == 0:
    # torre comercial
    var h := _rng.randf_range(22.0, 48.0)
    var w := _rng.randf_range(24.0, 36.0)
    var d := _rng.randf_range(24.0, 36.0)
    _box(self, Vector3(w, h, d), center + Vector3(0, h * 0.5 + 0.15, 0), _building_mat(tints[_rng.randi() % tints.size()], maxf(w, d), h), true)
  elif kind == 1:
    # comercio baixo com toldos coloridos
    var awn := [Color(0.9, 0.2, 0.2), Color(0.1, 0.5, 0.9), Color(0.95, 0.75, 0.1), Color(0.1, 0.6, 0.3)]
    for i in range(3):
      var w := 16.0
      var h := _rng.randf_range(8.0, 12.0)
      var x := -20.0 + float(i) * 20.0
      _box(self, Vector3(w, h, 24.0), center + Vector3(x, h * 0.5 + 0.15, -6.0), _building_mat(tints[_rng.randi() % tints.size()], w, h), true)
      _box(self, Vector3(w, 0.3, 3.0), center + Vector3(x, 3.6, 7.0), _mat(awn[_rng.randi() % awn.size()]))
  else:
    # casas coloridas
    var cols := [Color(0.9, 0.85, 0.5), Color(0.55, 0.8, 0.75), Color(0.9, 0.55, 0.45), Color(0.6, 0.65, 0.9), Color(0.95, 0.95, 0.9)]
    for i in range(2):
      for j in range(3):
        var x := -17.0 + float(j) * 17.0
        var z := -14.0 + float(i) * 28.0
        _box(self, Vector3(12.0, 5.0, 12.0), center + Vector3(x, 2.65, z), _mat(cols[_rng.randi() % cols.size()], 0.9), true)
        _box(self, Vector3(13.0, 0.4, 13.0), center + Vector3(x, 5.35, z), _mat(Color(0.55, 0.25, 0.18), 0.9))

# ---------------------------------------------------------------- POIs
func _build_poi(p: Dictionary, c: Vector3) -> void:
  var nome := str(p["nome"]).to_upper()
  match str(p["tipo"]):
    "estacionamento":
      _lot_floor(c, Color(0.14, 0.14, 0.16), true)
      _box(self, Vector3(5, 3, 5), c + Vector3(-26, 1.65, 26), _mat(Color(0.85, 0.85, 0.9)), true)
      _label(self, "ESTACIONAMENTO\nCENTRO", c + Vector3(0, 7.5, -30), 80)
      _label(self, "P", c + Vector3(-26, 5.5, 26), 140, Color(0.3, 0.7, 1.0))
    "garagem":
      _lot_floor(c, Color(0.18, 0.18, 0.2), false)
      _box(self, Vector3(34, 0.4, 16), c + Vector3(0, 6.2, -18), _mat(Color(0.3, 0.3, 0.34)))
      for sx in [-16.0, 16.0]:
        _box(self, Vector3(0.6, 6, 0.6), c + Vector3(sx, 3.2, -10), _mat(Color(0.25, 0.25, 0.28)), true)
        _box(self, Vector3(0.6, 6, 0.6), c + Vector3(sx, 3.2, -26), _mat(Color(0.25, 0.25, 0.28)), true)
      _box(self, Vector3(34, 6, 0.6), c + Vector3(0, 3.2, -26.5), _mat(Color(0.28, 0.28, 0.32)), true)
      _label(self, "GARAGEM\nPARTICULAR", c + Vector3(0, 8.5, -18), 80, Color(0.4, 0.9, 0.6))
    "oficina":
      _lot_floor(c, Color(0.2, 0.2, 0.22), false)
      var m := _mat(Color(0.18, 0.2, 0.26), 0.8)
      _box(self, Vector3(34, 9, 18), c + Vector3(0, 4.65, -18), m, true)
      _box(self, Vector3(12, 6, 0.4), c + Vector3(-8, 3.2, -8.7), _glow(Color(1.0, 0.55, 0.1), 0.8))
      _box(self, Vector3(12, 6, 0.4), c + Vector3(8, 3.2, -8.7), _glow(Color(1.0, 0.55, 0.1), 0.8))
      _label(self, "OFICINA DO ZECA", c + Vector3(0, 11.5, -8.6), 90, Color(1.0, 0.7, 0.2))
      for i in range(4):
        _cyl(self, 0.5, 0.5 + float(i % 2) * 0.5, c + Vector3(24 + 0.0, 0.5 + float(i) * 0.5, -6 + 0.0), _mat(Color(0.03, 0.03, 0.03)), 10)
    "posto":
      _lot_floor(c, Color(0.2, 0.2, 0.22), false)
      _box(self, Vector3(28, 0.8, 16), c + Vector3(-2, 6.4, 6), _mat(Color(0.92, 0.92, 0.9)), false)
      _box(self, Vector3(28.2, 0.5, 16.2), c + Vector3(-2, 5.9, 6), _glow(Color(0.1, 0.65, 0.25), 0.6))
      _box(self, Vector3(28.2, 0.3, 16.2), c + Vector3(-2, 6.9, 6), _glow(Color(1.0, 0.8, 0.1), 0.6))
      for sx in [-12.0, 8.0]:
        _box(self, Vector3(0.6, 6, 0.6), c + Vector3(sx, 3.2, 0), _mat(Color(0.8, 0.8, 0.8)), true)
        _box(self, Vector3(1.0, 1.4, 2.4), c + Vector3(sx + 2.0, 0.85, 6), _mat(Color(0.8, 0.1, 0.1)), true)
      _box(self, Vector3(14, 5, 8), c + Vector3(0, 2.65, -24), _mat(Color(0.9, 0.9, 0.85)), true)
      _label(self, "POSTO ESTRADA BR", c + Vector3(-2, 9.5, 6), 90, Color(0.2, 0.9, 0.3))
    "lavarapido":
      _lot_floor(c, Color(0.18, 0.2, 0.22), false)
      _box(self, Vector3(22, 6, 14), c + Vector3(0, 3.15, -16), _mat(Color(0.2, 0.55, 0.85)), true)
      _box(self, Vector3(8, 4.5, 0.4), c + Vector3(0, 2.4, -8.8), _glow(Color(0.2, 0.3, 0.9), 0.5))
      _label(self, "LAVA-RAPIDO BR", c + Vector3(0, 8.5, -8.6), 80, Color(0.5, 0.9, 1.0))
    "banco":
      var h := 26.0
      _box(self, Vector3(24, h, 22), c + Vector3(0, h * 0.5 + 0.15, -4), _building_mat(Color(0.45, 0.62, 0.8), 24.0, h), true)
      _box(self, Vector3(26, 1.0, 24), c + Vector3(0, 4.2, -4), _mat(Color(0.85, 0.85, 0.9)))
      _label(self, "BANCO DA VILA", c + Vector3(0, 6.5, 7.2), 90, Color(1.0, 0.9, 0.4))
    "concessionaria":
      _lot_floor(c, Color(0.2, 0.2, 0.23), false)
      _box(self, Vector3(34, 8, 14), c + Vector3(0, 4.15, -18), _mat(Color(0.1, 0.2, 0.35), 0.2, 0.3), true)
      _box(self, Vector3(30, 5.5, 0.3), c + Vector3(0, 3.2, -10.8), _glow(Color(0.5, 0.75, 1.0), 0.5))
      _label(self, "CONCESSIONARIA SUPREMO", c + Vector3(0, 10.0, -10.6), 80)
    "industria":
      for i in range(2):
        _box(self, Vector3(26, 10, 18), c + Vector3(-14 + float(i) * 28, 5.15, -10), _mat(Color(0.5, 0.5, 0.52), 0.9), true)
      _cyl(self, 1.8, 30.0, c + Vector3(22, 15.15, 18), _mat(Color(0.55, 0.3, 0.25)), 10)
      _label(self, "DISTRITO INDUSTRIAL", c + Vector3(0, 12.0, 4), 70, Color(0.9, 0.7, 0.3))
    "hospital":
      _box(self, Vector3(34, 18, 20), c + Vector3(0, 9.15, -8), _building_mat(Color(0.92, 0.94, 0.96), 34.0, 18.0), true)
      _box(self, Vector3(5, 1.4, 0.3), c + Vector3(0, 14, 2.2), _glow(Color(1, 0.1, 0.1), 1.5))
      _box(self, Vector3(1.4, 5, 0.3), c + Vector3(0, 14, 2.2), _glow(Color(1, 0.1, 0.1), 1.5))
      _label(self, "HOSPITAL MUNICIPAL", c + Vector3(0, 19.5, 2.3), 70, Color(0.4, 0.9, 1.0))
    "delegacia":
      _box(self, Vector3(34, 12, 18), c + Vector3(0, 6.15, -12), _mat(Color(0.82, 0.86, 0.95), 0.7), true)
      _box(self, Vector3(34.2, 1.4, 18.2), c + Vector3(0, 8.0, -12), _mat(Color(0.1, 0.2, 0.55)))
      _label(self, "DELEGACIA DISTRITAL", c + Vector3(0, 13.8, -2.6), 80, Color(0.5, 0.7, 1.0))
      _flag(c + Vector3(20, 0, 14))
    "patio":
      _lot_floor(c, Color(0.22, 0.2, 0.15), false)
      var fence := _mat(Color(0.7, 0.62, 0.2), 0.6, 0.3)
      for i in range(-5, 6):
        _box(self, Vector3(0.3, 3, 0.3), c + Vector3(float(i) * 5.5, 1.65, -30), fence)
        _box(self, Vector3(0.3, 3, 0.3), c + Vector3(-30, 1.65, float(i) * 5.5), fence)
        _box(self, Vector3(0.3, 3, 0.3), c + Vector3(30, 1.65, float(i) * 5.5), fence)
      _box(self, Vector3(60, 0.3, 0.2), c + Vector3(0, 2.8, -30), fence)
      _label(self, "PATIO MUNICIPAL", c + Vector3(0, 7.0, -30), 90, Color(1.0, 0.85, 0.2))
    "comunidade":
      _build_hill(c)
  _label(self, nome, c + Vector3(0, 0.6, 29.0), 36, Color(0.6, 0.85, 1.0, 0.85))

func _lot_floor(c: Vector3, col: Color, with_slots: bool) -> void:
  _box(self, Vector3(62, 0.05, 62), c + Vector3(0, 0.18, 0), _mat(col, 0.95))
  if with_slots:
    var lm := _mat(Color(0.95, 0.95, 0.95), 0.8)
    for i in range(-5, 6):
      _box(self, Vector3(0.18, 0.02, 5.0), c + Vector3(float(i) * 5.0, 0.22, 12.0), lm)
      _box(self, Vector3(0.18, 0.02, 5.0), c + Vector3(float(i) * 5.0, 0.22, -12.0), lm)

func _flag(p: Vector3) -> void:
  _cyl(self, 0.12, 12.0, p + Vector3(0, 6.0, 0), _mat(Color(0.8, 0.8, 0.8), 0.4, 0.8), 6)
  var fp := Vector3(2.2, 10.0, 0.0) + p
  _box(self, Vector3(4.0, 2.8, 0.05), fp, _mat(Color(0.0, 0.6, 0.25), 0.9))
  var dia := Node3D.new()
  dia.position = fp + Vector3(0, 0, 0.04)
  dia.scale = Vector3(1.0, 0.62, 1.0)
  add_child(dia)
  var dm := MeshInstance3D.new()
  var dc := CylinderMesh.new()
  dc.top_radius = 1.7
  dc.bottom_radius = 1.7
  dc.height = 0.05
  dc.radial_segments = 4
  dm.mesh = dc
  dm.rotation_degrees.x = 90.0
  dm.material_override = _mat(Color(1.0, 0.85, 0.0), 0.9)
  dia.add_child(dm)
  var cm := MeshInstance3D.new()
  var cc := CylinderMesh.new()
  cc.top_radius = 0.75
  cc.bottom_radius = 0.75
  cc.height = 0.05
  cm.mesh = cc
  cm.rotation_degrees.x = 90.0
  cm.position = fp + Vector3(0, 0, 0.09)
  cm.material_override = _mat(Color(0.05, 0.2, 0.6), 0.9)
  add_child(cm)

func _build_hill(c: Vector3) -> void:
  # morro em degraus com casinhas coloridas (comunidade) e estatua no topo
  var cols := [Color(0.9, 0.4, 0.3), Color(0.95, 0.8, 0.3), Color(0.3, 0.7, 0.8), Color(0.85, 0.85, 0.8), Color(0.55, 0.75, 0.4), Color(0.8, 0.5, 0.75)]
  for row in range(5):
    var y := 1.0 + float(row) * 4.2
    var width := 56.0 - float(row) * 7.0
    _box(self, Vector3(width, 4.0, 12.0), c + Vector3(0, y - 0.8, -4.0 - float(row) * 4.5), _mat(Color(0.28, 0.24, 0.2)), true)
    var count := int(width / 7.0)
    for i in range(count):
      var x := -width * 0.5 + 4.0 + float(i) * 7.0
      var hh := _rng.randf_range(3.0, 5.0)
      _box(self, Vector3(5.5, hh, 5.5), c + Vector3(x, y + 1.2 + hh * 0.5, -4.0 - float(row) * 4.5), _mat(cols[_rng.randi() % cols.size()], 0.9), true)
  var top := c + Vector3(0, 21.0, -26.0)
  var white := _mat(Color(0.95, 0.95, 0.95), 0.6)
  _box(self, Vector3(1.4, 7.0, 1.4), top + Vector3(0, 3.5, 0), white)
  _box(self, Vector3(9.0, 1.1, 1.0), top + Vector3(0, 5.8, 0), white)
  var head := MeshInstance3D.new()
  var hs := SphereMesh.new()
  hs.radius = 0.8
  hs.height = 1.6
  head.mesh = hs
  head.material_override = white
  head.position = top + Vector3(0, 7.6, 0)
  add_child(head)
  var spot := SpotLight3D.new()
  spot.spot_range = 24.0
  spot.light_energy = 2.0
  add_child(spot)
  spot.look_at_from_position(top + Vector3(0, 2.0, 14.0), top + Vector3(0, 5.0, 0), Vector3.UP)
  _label(self, "COMUNIDADE", c + Vector3(0, 6.0, 27.0), 70, Color(1.0, 0.8, 0.3))

func _poi_marker(poi: Dictionary) -> void:
  var colors := {
    "oficina": Color(1.0, 0.6, 0.1), "banco": Color(1.0, 0.9, 0.3), "concessionaria": Color(0.3, 0.7, 1.0),
    "delegacia": Color(0.4, 0.5, 1.0), "patio": Color(1.0, 0.85, 0.2), "posto": Color(0.3, 1.0, 0.4),
    "estacionamento": Color(0.6, 0.8, 1.0), "garagem": Color(0.4, 1.0, 0.7)
  }
  var t: String = poi["tipo"]
  if not colors.has(t):
    return
  var col: Color = colors[t]
  var pos: Vector3 = poi["pos"]
  var ring := _cyl(self, 4.0, 0.08, pos + Vector3(0, 0.3, 0), _marker_mat(col, 0.5), 24)
  ring.add_to_group("poi_marker")
  _cyl(self, 0.35, 14.0, pos + Vector3(0, 7.3, 0), _marker_mat(col, 0.28), 8)

func _marker_mat(c: Color, a: float) -> StandardMaterial3D:
  var m := StandardMaterial3D.new()
  m.albedo_color = Color(c.r, c.g, c.b, a)
  m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  m.emission_enabled = true
  m.emission = c
  return m

# ---------------------------------------------------------------- rodovia e ponte estaiada
func _build_highway_and_bridge() -> void:
  var asphalt := _mat(Color(0.08, 0.08, 0.09), 0.95)
  _box(self, Vector3(570, 0.04, 18), Vector3(0, 0.03, HIGHWAY_Z), asphalt)
  var line := _mat(Color(0.95, 0.9, 0.5))
  for i in range(-35, 36):
    _box(self, Vector3(3.0, 0.03, 0.25), Vector3(float(i) * 8.0, 0.06, HIGHWAY_Z), line)
  # ponte estaiada: mastro em X + cabos
  var concrete := _mat(Color(0.82, 0.84, 0.88), 0.5)
  var cable := _glow(Color(0.5, 0.75, 1.0), 0.6)
  var deck_y := 14.0
  _box(self, Vector3(120, 1.2, 20), Vector3(0, deck_y, HIGHWAY_Z), concrete, true)
  # rampas de acesso
  for sx in [-1.0, 1.0]:
    var ramp := _box(self, Vector3(60, 1.2, 20), Vector3(sx * 88.0, deck_y * 0.5, HIGHWAY_Z), concrete, true)
    ramp.rotation.z = -sx * deg_to_rad(13.0)
  for sx in [-1.0, 1.0]:
    var leg := _box(self, Vector3(3.0, 62.0, 3.0), Vector3(sx * 4.0, deck_y + 28.0, HIGHWAY_Z - 12.0), concrete)
    leg.rotation.z = -sx * deg_to_rad(8.0)
    var leg2 := _box(self, Vector3(3.0, 62.0, 3.0), Vector3(sx * 4.0, deck_y + 28.0, HIGHWAY_Z + 12.0), concrete)
    leg2.rotation.z = -sx * deg_to_rad(8.0)
  for i in range(1, 9):
    var x := float(i) * 7.0
    for sx in [-1.0, 1.0]:
      for sz in [-1.0, 1.0]:
        _cable(Vector3(sx * 4.0, deck_y + 54.0 - float(i) * 1.5, HIGHWAY_Z + sz * 12.0), Vector3(sx * x, deck_y + 0.6, HIGHWAY_Z + sz * 9.0), cable)
  _label(self, "SUPREMO BR", Vector3(0, deck_y + 40.0, HIGHWAY_Z - 14.0), 160, Color(0.4, 0.75, 1.0))

func _cable(a: Vector3, b: Vector3, material: Material) -> void:
  var mi := MeshInstance3D.new()
  var bm := BoxMesh.new()
  var length := a.distance_to(b)
  bm.size = Vector3(0.12, 0.12, length)
  mi.mesh = bm
  mi.material_override = material
  add_child(mi)
  mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)

# ---------------------------------------------------------------- consultas
func zone_info(pos: Vector3) -> Dictionary:
  var info := {"rua": false, "rodovia": false, "lote": "", "legal": false, "protegido": false, "regiao": "residencial", "limite": 40}
  if absf(pos.z - HIGHWAY_Z) < 9.0 and absf(pos.x) < 285.0:
    info["rua"] = true
    info["rodovia"] = true
    info["limite"] = int(Data.police.get("limites_kmh", {}).get("rodovia", 110))
  else:
    var on_road := false
    for r in ROADS:
      if absf(pos.x - r) < ROAD_W * 0.5 and pos.z > -205.0 and pos.z < 245.0:
        on_road = true
      if absf(pos.z - r) < ROAD_W * 0.5 and absf(pos.x) < 205.0:
        on_road = true
    info["rua"] = on_road
    if on_road:
      info["limite"] = int(Data.police.get("limites_kmh", {}).get("rua", 60))
  for id in pois:
    var p: Dictionary = pois[id]
    var c: Vector3 = p["center"]
    if absf(pos.x - c.x) < 31.0 and absf(pos.z - c.z) < 31.0 and not info["rua"]:
      var t: String = p["tipo"]
      if t in LOT_TYPES:
        info["lote"] = t
        info["legal"] = true
        info["protegido"] = t in PROTECTED_TYPES
        if t == "estacionamento":
          info["limite"] = int(Data.police.get("limites_kmh", {}).get("estacionamento", 20))
  if absf(pos.z) > 200.0:
    info["regiao"] = "rodovia"
  elif absf(pos.x) < 90.0 and absf(pos.z) < 90.0:
    info["regiao"] = "centro"
  elif pos.x < -40.0 and pos.z < -40.0:
    info["regiao"] = "industrial"
  return info

func nearest_poi(pos: Vector3, radius: float) -> Dictionary:
  var best: Dictionary = {}
  var best_d := radius
  for id in pois:
    var p: Dictionary = pois[id]
    var d := pos.distance_to(p["pos"])
    if d < best_d:
      best_d = d
      best = p
  return best

func poi_front(id: String, offset_x: float = 0.0) -> Vector3:
  var p: Dictionary = pois.get(id, {})
  if p.is_empty():
    return Vector3.ZERO
  var c: Vector3 = p["center"]
  return c + Vector3(offset_x, 1.0, 14.0)
