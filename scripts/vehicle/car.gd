extends RigidBody3D
class_name SupremoCar
# Veiculo (carro ou moto) dirigido por dados (data/vehicles.json + pecas de tuning).
# Fisica: suspensao por raycast, pneus com limite de aderencia combinado, motor com
# curva de torque, cambio automatico, marcha a re, consumo, desgaste e dano por colisao.
# E uma aproximacao de JOGO (nao simulacao validada de engenharia). A moto usa
# estabilizacao arcade (torque de endireitamento), nao dinamica real de duas rodas.

const GRAV := 9.81

var uid := ""
var def: Dictionary = {}
var stats: Dictionary = {}
var vdata: Dictionary = {}        # referencia ao dicionario do veiculo em Game.vehicles
var is_moto := false
var is_player := false
var drive := "traseira"
var wheel_pts: Array = []
var wheel_r := 0.3
var ratios: Array = [3.5, 2.0, 1.4, 1.0, 0.8]
var final_drive := 3.6
var redline := 6500.0
var idle_rpm := 900.0
var peak_rpm := 3500.0
var cylinders := 4
var tank_l := 40.0
var cda := 0.7
var spring := 20000.0
var damper := 2600.0
const DRIVE_EFF := 0.84

# entradas
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := false
# estado
var rpm := 900.0
var gear := 1
var reverse := false
var speed_kmh := 0.0
var engine_load := 0.0
var grounded_wheels := 0
var fuel_l := 30.0
var odometer_km := 0.0
var engine_on := true
var limiter := false
# IA
var ai_enabled := false
var ai_target := Vector3.ZERO
var ai_max_kmh := 40.0
var ai_hold := false
var ai_ignore: Node = null
var audio: EngineAudio = null

var _visual: Dictionary = {}
var _steer_angle := 0.0
var _gear_cooldown := 0.0
var _dead_timer := 0.0
var _flip_timer := 0.0
var _flash := 0.0
var _prev_vel := Vector3.ZERO
var _dmg_cd := 1.5
var _stuck_timer := 0.0
var _reverse_timer := 0.0
var _lean := 0.0
var _out_of_fuel_told := false

func setup(v: Dictionary, with_lights: bool = false) -> void:
  vdata = v
  uid = str(v.get("uid", ""))
  def = Data.vehicle_def(str(v.get("model", "")))
  stats = VehicleStats.compute(def, v.get("tuning", []))
  is_moto = str(def.get("tipo", "carro")) == "moto"
  drive = str(def.get("tracao", "traseira"))
  mass = float(stats["mass"])
  wheel_r = float(def.get("raio_roda_m", 0.3))
  ratios = def.get("marchas", [3.5, 2.0, 1.4, 1.0, 0.8])
  final_drive = float(def.get("diferencial", 3.6))
  redline = float(def.get("rpm_max", 6500))
  idle_rpm = float(def.get("rpm_marcha_lenta", 900))
  peak_rpm = float(def.get("rpm_torque_pico", 3500))
  cylinders = int(def.get("cilindros", 4))
  tank_l = float(def.get("tanque_l", 40))
  cda = float(def.get("cda", 0.7))
  fuel_l = float(v.get("fuel_l", tank_l * 0.6))
  odometer_km = float(v.get("odometer_km", 0.0))
  rpm = idle_rpm

  continuous_cd = true
  can_sleep = false
  linear_damp = 0.02
  angular_damp = 0.12
  var h0: float = VehicleBuilder.ground_offset(def)
  center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
  var cg: float = float(def.get("cg_altura_m", 0.5)) + float(stats.get("ride_mm", 0.0)) / 1000.0
  center_of_mass = Vector3(0.0, -h0 + cg, 0.0)

  var built: Dictionary = VehicleBuilder.build(def, str(v.get("color", "#cccccc")), stats, str(v.get("plate", "")), with_lights)
  _visual = built
  add_child(built["root"])
  wheel_pts = built["wheel_points"]
  var n: int = wheel_pts.size()
  spring = mass * GRAV / (float(n) * VehicleBuilder.SAG)
  damper = spring * 0.13

  var dims: Dictionary = def.get("dimensoes", {})
  var L: float = float(dims.get("comp", 4.0))
  var W: float = float(dims.get("larg", 1.7))
  var H: float = float(dims.get("alt", 1.4))
  var shape := BoxShape3D.new()
  var col := CollisionShape3D.new()
  if is_moto:
    shape.size = Vector3(0.5, 0.9, L * 0.85)
    col.position = Vector3(0, -h0 + 0.3 + 0.45, 0)
  else:
    shape.size = Vector3(W * 0.98, H * 0.6, L * 0.98)
    col.position = Vector3(0, -h0 + 0.18 + H * 0.3, 0)
  col.shape = shape
  add_child(col)

static func make(v: Dictionary, with_lights: bool = false) -> SupremoCar:
  var c := SupremoCar.new()
  c.setup(v, with_lights)
  return c

func set_headlights(on: bool) -> void:
  for sp in _visual.get("spots", []):
    sp.visible = on

func condition() -> float:
  return float(vdata.get("condition", 1.0))

func _torque_at(r: float) -> float:
  var span: float = redline * 0.62
  var curve: float = clampf(1.0 - pow((r - peak_rpm) / span, 2.0), 0.45, 1.0)
  return float(stats["torque_nm"]) * curve * lerpf(0.6, 1.0, condition())

func _is_front(i: int) -> bool:
  return i == 0 if is_moto else i < 2

func _drive_share(i: int) -> float:
  if is_moto:
    return 1.0 if i == 1 else 0.0
  match drive:
    "dianteira":
      return 0.5 if i < 2 else 0.0
    "integral":
      return 0.25
    _:
      return 0.5 if i >= 2 else 0.0

func park() -> void:
  throttle = 0.0
  brake = 0.0
  steer = 0.0
  handbrake = false
  linear_velocity = Vector3.ZERO
  angular_velocity = Vector3.ZERO
  freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
  freeze = true
  engine_on = false
  rpm = 0.0

func unpark() -> void:
  freeze = false
  engine_on = true
  rpm = idle_rpm
  _dmg_cd = 1.0
  _prev_vel = Vector3.ZERO

func recover() -> void:
  var yaw: float = global_rotation.y
  global_rotation = Vector3(0.0, yaw, 0.0)
  global_position += Vector3.UP * 1.2
  linear_velocity = Vector3.ZERO
  angular_velocity = Vector3.ZERO
  _flip_timer = 0.0
  _dmg_cd = 1.0

func _physics_process(delta: float) -> void:
  if freeze:
    return
  var basis_up: Vector3 = global_transform.basis.y.normalized()
  var forward: Vector3 = -global_transform.basis.z.normalized()
  var right_axis: Vector3 = global_transform.basis.x.normalized()
  var forward_speed: float = linear_velocity.dot(forward)
  var spd: float = linear_velocity.length()
  speed_kmh = spd * 3.6
  if ai_enabled:
    _run_ai(delta, forward, forward_speed)

  # ---- estado do motor
  _dead_timer = maxf(0.0, _dead_timer - delta)
  var can_drive: bool = engine_on and fuel_l > 0.0 and _dead_timer <= 0.0
  if is_player and fuel_l <= 0.0 and engine_on and not _out_of_fuel_told:
    _out_of_fuel_told = true
    Bus.say("Sem combustivel! Va ao Posto Estrada BR.", "warn")
  if fuel_l > 0.5:
    _out_of_fuel_told = false
  var thr: float = throttle if can_drive else 0.0
  reverse = brake > 0.0 and thr == 0.0 and forward_speed < 0.6
  var max_steer: float = 0.34 if is_moto else 0.52
  _steer_angle = move_toward(_steer_angle, steer * max_steer / (1.0 + speed_kmh / 95.0), delta * 2.2)
  _gear_cooldown = maxf(0.0, _gear_cooldown - delta)
  var fd: float = final_drive * float(stats["final_mult"])
  var wheel_rpm: float = absf(forward_speed) / (TAU * wheel_r) * 60.0
  var gear_ratio: float = float(ratios[gear - 1])
  var calc_rpm: float = wheel_rpm * gear_ratio * fd
  if can_drive:
    rpm = clampf(maxf(idle_rpm + thr * (peak_rpm - idle_rpm) * 0.35, calc_rpm), idle_rpm, redline)
  else:
    rpm = move_toward(rpm, 0.0 if not engine_on else calc_rpm, 2500.0 * delta)
  if _gear_cooldown <= 0.0 and can_drive:
    if rpm > redline * 0.93 and gear < ratios.size() and thr > 0.3:
      gear += 1
      _gear_cooldown = 0.4
    elif calc_rpm < peak_rpm * 0.55 and gear > 1:
      gear -= 1
      _gear_cooldown = 0.4
  engine_load = clampf(thr * (0.4 + rpm / (redline * 1.5)), 0.0, 1.0)
  limiter = can_drive and rpm >= redline * 0.995 and thr > 0.5
  var tq: float = _torque_at(rpm)
  var engine_force := 0.0
  if can_drive and not limiter and not reverse:
    engine_force = thr * tq * gear_ratio * fd * DRIVE_EFF / wheel_r
  elif can_drive and reverse:
    engine_force = -brake * tq * 3.0 * fd * DRIVE_EFF / wheel_r * 0.5

  # ---- suspensao + pneus
  var space := get_world_3d().direct_space_state
  grounded_wheels = 0
  var n: int = wheel_pts.size()
  var lat_k: float = mass * 4.2 * (4.0 / float(n))
  var brake_total: float = mass * 11.0 * float(stats["brake_mult"])
  var mu_base: float = 1.12 * float(stats["grip_mult"]) * Game.grip_env
  var wheels: Array = _visual["wheels"]
  for i in range(n):
    var local_point: Vector3 = wheel_pts[i]
    var origin: Vector3 = global_transform * local_point
    var cast_end: Vector3 = origin - basis_up * (VehicleBuilder.REST_LEN + wheel_r + 0.05)
    var query := PhysicsRayQueryParameters3D.create(origin, cast_end)
    query.exclude = [get_rid()]
    var hit: Dictionary = space.intersect_ray(query)
    var wn: Dictionary = wheels[i]
    var steer_node: Node3D = wn["steer"]
    var spin_node: Node3D = wn["spin"]
    if hit.is_empty():
      steer_node.position = local_point + Vector3.DOWN * VehicleBuilder.REST_LEN
      spin_node.rotation.x -= forward_speed / wheel_r * delta
      continue
    grounded_wheels += 1
    var hit_point: Vector3 = hit["position"]
    var normal: Vector3 = hit["normal"]
    var distance: float = origin.distance_to(hit_point)
    var compression: float = clampf(VehicleBuilder.REST_LEN - (distance - wheel_r), 0.0, VehicleBuilder.REST_LEN)
    steer_node.position = local_point + Vector3.DOWN * (VehicleBuilder.REST_LEN - compression)
    var front: bool = _is_front(i)
    steer_node.rotation.y = _steer_angle if front else 0.0
    spin_node.rotation.x -= forward_speed / wheel_r * delta
    var lever: Vector3 = origin - global_position
    var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(lever)
    var susp_vel: float = point_velocity.dot(basis_up)
    var spring_force: float = maxf(0.0, compression * spring - susp_vel * damper)
    apply_force((basis_up + normal).normalized() * spring_force, lever)
    var wheel_fwd: Vector3 = forward.rotated(basis_up, _steer_angle if front else 0.0)
    wheel_fwd = (wheel_fwd - normal * wheel_fwd.dot(normal)).normalized()
    var wheel_right: Vector3 = wheel_fwd.cross(normal).normalized()
    var long_speed: float = point_velocity.dot(wheel_fwd)
    var lat_speed: float = point_velocity.dot(wheel_right)
    var rear_hb: bool = handbrake and not front
    var mu: float = mu_base * (0.25 if rear_hb else 1.0)
    var grip_limit: float = spring_force * mu
    var lateral: float = clampf(-lat_speed * lat_k, -grip_limit, grip_limit)
    var longitudinal: float = engine_force * _drive_share(i)
    if reverse:
      pass
    elif brake > 0.0 or rear_hb:
      var strength: float = brake_total * brake / float(n) + (mass * 5.0 / float(n) if rear_hb else 0.0)
      longitudinal -= signf(long_speed) * minf(absf(long_speed) * mass * 1.5, strength)
    elif thr <= 0.0 and can_drive:
      var eb: float = mass * (0.9 + rpm / redline * 1.5) / float(n)
      longitudinal -= signf(long_speed) * minf(absf(long_speed) * mass * 0.6, eb)
    var combined := Vector2(longitudinal, lateral)
    if combined.length() > grip_limit and grip_limit > 0.0:
      combined = combined.normalized() * grip_limit
    apply_force(wheel_fwd * combined.x + wheel_right * combined.y, lever)

  # ---- resistencias
  if spd > 0.1:
    var vdir: Vector3 = linear_velocity.normalized()
    apply_central_force(-vdir * (0.6 * cda * spd * spd))
    if grounded_wheels > 0:
      apply_central_force(-vdir * mass * GRAV * 0.012)
  var df: float = float(stats["downforce"])
  if df > 0.0:
    apply_central_force(-basis_up * df * spd * spd)
  if is_moto:
    var tilt: Vector3 = basis_up.cross(Vector3.UP)
    apply_torque(tilt * mass * 38.0)
    var ang_rp: Vector3 = forward * angular_velocity.dot(forward) + right_axis * angular_velocity.dot(right_axis)
    apply_torque(-ang_rp * mass * 2.5)

  # ---- consumo, desgaste, falhas
  var km: float = spd * delta / 1000.0
  odometer_km += km
  if engine_on and fuel_l > 0.0:
    var burn: float = (0.0006 + engine_load * float(stats["hp"]) * 0.000006) * float(stats["fuel_mult"])
    fuel_l = maxf(0.0, fuel_l - burn * delta)
  var rel: float = float(stats["reliability"])
  if not vdata.is_empty():
    vdata["odometer_km"] = odometer_km
    vdata["fuel_l"] = fuel_l
    if vdata.has("oil_km_left"):
      vdata["oil_km_left"] = float(vdata["oil_km_left"]) - km
      if float(vdata["oil_km_left"]) <= 0.0:
        rel -= 0.1
  if limiter and randf() < (1.0 - rel) * 0.25 * delta:
    _dead_timer = 4.0
    if not vdata.is_empty():
      vdata["condition"] = maxf(0.0, condition() - 0.05)
    if is_player:
      Bus.say("Falha mecanica! O motor apagou (confiabilidade baixa).", "warn")

  # ---- dano por colisao (variacao brusca de velocidade)
  _dmg_cd = maxf(0.0, _dmg_cd - delta)
  var dv: float = (linear_velocity - _prev_vel).length()
  _prev_vel = linear_velocity
  if dv > 5.5 and _dmg_cd <= 0.0 and not vdata.is_empty():
    vdata["condition"] = maxf(0.0, condition() - (dv - 5.5) * 0.012)
    _dmg_cd = 0.5
    if is_player:
      Bus.say("Colisao! Danos na lataria e na mecanica.", "warn")

  # ---- recuperacao de capotamento
  if global_transform.basis.y.y < 0.25 and spd < 6.0:
    _flip_timer += delta
  else:
    _flip_timer = 0.0
  if _flip_timer > 2.5:
    recover()

func _run_ai(delta: float, forward: Vector3, forward_speed: float) -> void:
  var to: Vector3 = ai_target - global_position
  to.y = 0.0
  var dist: float = to.length()
  var fwd: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
  var dir: Vector3 = to.normalized() if dist > 0.01 else fwd
  var ang: float = fwd.signed_angle_to(dir, Vector3.UP)
  var desired: float = ai_max_kmh / 3.6
  if absf(ang) > 0.6:
    desired *= 0.5
  if ai_hold:
    desired = 0.0
  var dims: Dictionary = def.get("dimensoes", {})
  var L: float = float(dims.get("comp", 4.0))
  var from_p: Vector3 = global_position + fwd * (L * 0.5 + 0.3)
  var q := PhysicsRayQueryParameters3D.create(from_p, from_p + fwd * 12.0)
  q.exclude = [get_rid()]
  var h: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
  if not h.is_empty() and h["collider"] != ai_ignore and h["collider"] is RigidBody3D:
    var hd: float = from_p.distance_to(h["position"])
    desired = 0.0 if hd < 9.0 else desired * 0.6
  steer = clampf(ang * 1.8, -1.0, 1.0)
  throttle = clampf((desired - forward_speed) * 0.5, 0.0, 1.0)
  brake = clampf((forward_speed - desired) * 0.4, 0.0, 1.0) if forward_speed > desired + 1.0 else 0.0
  handbrake = false
  # destravar: re por 1,5 s quando preso
  if _reverse_timer > 0.0:
    _reverse_timer -= delta
    throttle = 0.0
    brake = 1.0
    steer = -steer
    return
  if throttle > 0.4 and absf(forward_speed) < 1.0 and not ai_hold:
    _stuck_timer += delta
    if _stuck_timer > 3.0:
      _stuck_timer = 0.0
      _reverse_timer = 1.5
  else:
    _stuck_timer = 0.0

func _process(delta: float) -> void:
  if _visual.is_empty():
    return
  for m in _visual["tail_mats"]:
    (m as StandardMaterial3D).emission_energy_multiplier = 1.0 + (3.0 if brake > 0.1 else 0.0)
  var bar: Array = _visual["bar"]
  if bar.size() == 2:
    _flash += delta
    var on: bool = int(_flash * 6.0) % 2 == 0
    (bar[0] as MeshInstance3D).visible = on
    (bar[1] as MeshInstance3D).visible = not on
  if is_moto:
    var target_lean: float = clampf(-_steer_angle * minf(speed_kmh / 40.0, 1.5) * 1.6, -0.6, 0.6)
    _lean = lerpf(_lean, target_lean, clampf(delta * 6.0, 0.0, 1.0))
    (_visual["body_root"] as Node3D).rotation.z = _lean
  if audio != null:
    var eng_rpm: float = rpm
    var thr: float = throttle
    if freeze:
      eng_rpm = idle_rpm if engine_on else 0.0
      thr = 0.0
    audio.set_state(eng_rpm, thr, engine_load, cylinders, float(stats["exhaust_mm"]), bool(stats["turbo"]), bool(stats["pops"]), limiter, engine_on and fuel_l > 0.0 and _dead_timer <= 0.0)
