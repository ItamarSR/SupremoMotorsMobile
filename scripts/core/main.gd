extends Node3D
# Raiz de composicao: monta mundo, sistemas e UI e liga tudo por sinais/callables.
# Regras de jogo ficam em scripts/systems; dados em res://data; estado em Game.

const MENU_POIS := ["oficina", "banco", "concessionaria", "delegacia", "patio", "posto", "estacionamento", "garagem"]
const GARAGE_SLOTS := [0.0, -9.0, 9.0, -18.0, 18.0]
const AUTOSAVE_S := 60.0

var world: WorldBuilder
var weather: WeatherSystem
var traffic: TrafficSystem
var police: PoliceSystem
var parking: ParkingSystem
var economy: EconomySystem
var mission: MissionSystem
var menus: Menus
var ui: GameUI
var quality: SupremoQualityManager
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var rain: CPUParticles3D

var player: SupremoCar = null
var player_v: Dictionary = {}
var audio: EngineAudio = null

var _dynamic: Node3D
var _beacon: MeshInstance3D
var _autosave := 0.0
var _lights_on := false

func _ready() -> void:
  randomize()
  if not Game.load_game():
    Game.new_game()
  _build_environment()

  world = WorldBuilder.new()
  world.name = "Mundo"
  add_child(world)
  world.build()

  _dynamic = Node3D.new()
  _dynamic.name = "Veiculos"
  add_child(_dynamic)

  camera = Camera3D.new()
  camera.current = true
  camera.fov = 72.0
  camera.far = 900.0
  camera.position = Vector3(0, 4.0, 9.0)
  add_child(camera)
  _build_rain()

  parking = ParkingSystem.new()
  parking.name = "Estacionamento"
  add_child(parking)
  parking.setup(world, _dynamic)

  economy = EconomySystem.new()
  economy.name = "Economia"
  add_child(economy)

  traffic = TrafficSystem.new()
  traffic.name = "Transito"
  add_child(traffic)
  traffic.setup(world, _dynamic, 8)

  police = PoliceSystem.new()
  police.name = "Policia"
  add_child(police)
  police.setup(world, traffic, _dynamic, Callable(self, "get_player"))
  police.seized.connect(_on_seized)

  mission = MissionSystem.new()
  mission.name = "Missoes"
  add_child(mission)
  mission.setup(world, Callable(self, "get_player"))

  weather = WeatherSystem.new()
  weather.name = "Clima"
  add_child(weather)
  var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
  weather.setup(sun, env, sky_mat, world, rain)

  quality = SupremoQualityManager.new()
  add_child(quality)
  quality.setup(self, sun)

  var layer := CanvasLayer.new()
  add_child(layer)
  ui = GameUI.new()
  layer.add_child(ui)
  ui.driving_input.connect(_on_drive)
  ui.action.connect(_on_action)
  menus = Menus.new()
  add_child(menus)
  menus.setup(ui, self)
  ui.minimap.world = world

  Bus.vehicle_removed.connect(_on_vehicle_removed)
  Bus.night_changed.connect(_on_night)
  Bus.choice_requested.connect(func(c, id): menus.open_choice(c, id))

  _build_beacon()
  _restore_vehicles()
  _lights_on = weather.is_night()
  if player != null:
    player.set_headlights(_lights_on)
  Bus.say("Bem-vindo a Vila Supremo! Abra o CELULAR [C] para ver as missoes.", "info")

# ---------------------------------------------------------------- ambiente
func _build_environment() -> void:
  sun = DirectionalLight3D.new()
  sun.light_energy = 1.2
  sun.shadow_enabled = false
  sun.directional_shadow_max_distance = 120.0
  add_child(sun)
  env = Environment.new()
  env.background_mode = Environment.BG_SKY
  var sky := Sky.new()
  sky.sky_material = ProceduralSkyMaterial.new()
  env.sky = sky
  env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
  env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
  env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
  env.fog_enabled = true
  env.fog_density = 0.0015
  var we := WorldEnvironment.new()
  we.environment = env
  add_child(we)

func _build_rain() -> void:
  rain = CPUParticles3D.new()
  rain.amount = 700
  rain.lifetime = 1.1
  rain.emitting = false
  rain.local_coords = false
  rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
  rain.emission_box_extents = Vector3(22, 0.2, 22)
  rain.direction = Vector3(0, -1, 0)
  rain.spread = 2.0
  rain.gravity = Vector3(0, -25, 0)
  rain.initial_velocity_min = 18.0
  rain.initial_velocity_max = 24.0
  var bm := BoxMesh.new()
  bm.size = Vector3(0.02, 0.6, 0.02)
  var m := StandardMaterial3D.new()
  m.albedo_color = Color(0.7, 0.8, 1.0, 0.5)
  m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  bm.material = m
  rain.mesh = bm
  rain.position = Vector3(0, 14, 0)
  camera.add_child(rain)

func _build_beacon() -> void:
  _beacon = MeshInstance3D.new()
  var c := CylinderMesh.new()
  c.top_radius = 0.6
  c.bottom_radius = 0.6
  c.height = 45.0
  _beacon.mesh = c
  var m := StandardMaterial3D.new()
  m.albedo_color = Color(0.2, 1.0, 0.5, 0.35)
  m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  m.emission_enabled = true
  m.emission = Color(0.2, 1.0, 0.5)
  _beacon.material_override = m
  _beacon.visible = false
  add_child(_beacon)

# ---------------------------------------------------------------- veiculos
func get_player() -> SupremoCar:
  if player != null and is_instance_valid(player):
    return player
  return null

func _garage_pos(slot: int) -> Vector3:
  return world.poi_front("garagem_jogador", float(GARAGE_SLOTS[slot % GARAGE_SLOTS.size()]))

func _restore_vehicles() -> void:
  var slot := 1
  for v in Game.vehicles:
    if v["status"] != "ativo" or str(v["uid"]) == Game.active_uid:
      continue
    if v["parked"].is_empty():
      parking.spawn_parked(v, _garage_pos(slot), PI, true)
      slot += 1
    else:
      parking.spawn_from_state(v)
  var active: Dictionary = Game.get_vehicle(Game.active_uid)
  if active.is_empty() or active["status"] != "ativo":
    _ensure_active()
    return
  var pos := _garage_pos(0)
  var rot := PI
  var lp: Array = active.get("last_pos", [])
  if lp.size() >= 4:
    pos = Vector3(float(lp[0]), float(lp[1]) + 0.3, float(lp[2]))
    rot = float(lp[3])
  var car := SupremoCar.make(active, true)
  car.position = pos
  car.rotation.y = rot
  _dynamic.add_child(car)
  if not active["parked"].is_empty():
    car.park()
    car.engine_on = bool(active["parked"].get("engine_on", false))
  _set_player(car, active)

func _set_player(car: SupremoCar, v: Dictionary) -> void:
  player = car
  player_v = v
  car.is_player = true
  if audio != null and is_instance_valid(audio):
    audio.queue_free()
  audio = EngineAudio.new()
  car.add_child(audio)
  car.audio = audio
  car.set_headlights(_lights_on)
  Game.active_uid = str(v["uid"])
  ui.minimap.player = car
  Bus.vehicle_changed.emit()

func _take_control(inst: SupremoCar, v: Dictionary) -> void:
  parking.cars.erase(str(v["uid"]))
  inst.unpark()
  v["parked"] = {}
  _set_player(inst, v)

func _park_current_auto() -> void:
  var cur := get_player()
  if cur == null:
    return
  if str(player_v.get("uid", "")) == "emprestado":
    cur.queue_free()
    player = null
    return
  if not cur.freeze:
    cur.park()
    player_v["parked"] = parking.make_state(cur, false)
  parking.cars[str(player_v["uid"])] = cur
  cur.is_player = false
  cur.audio = null
  if audio != null and is_instance_valid(audio):
    audio.queue_free()
    audio = null
  cur.set_headlights(false)

func switch_to(uid: String) -> void:
  var target: Dictionary = Game.get_vehicle(uid)
  if target.is_empty() or target["status"] != "ativo" or uid == Game.active_uid:
    return
  _park_current_auto()
  var inst: SupremoCar = parking.cars.get(uid)
  if inst == null or not is_instance_valid(inst):
    if target["parked"].is_empty():
      inst = parking.spawn_parked(target, _garage_pos(1), PI, true)
    else:
      inst = parking.spawn_from_state(target)
  _take_control(inst, target)
  Bus.say("Voce assumiu o %s." % Data.vehicle_def(str(target["model"])).get("modelo", "veiculo"))

func _ensure_active() -> void:
  player = null
  for v in Game.owned_active():
    var inst: SupremoCar = parking.cars.get(str(v["uid"]))
    if inst == null or not is_instance_valid(inst):
      if v["parked"].is_empty():
        inst = parking.spawn_parked(v, _garage_pos(1), PI, true)
      else:
        inst = parking.spawn_from_state(v)
    _take_control(inst, v)
    return
  # sem veiculo proprio: carro emprestado no patio
  var loaner := {
    "uid": "emprestado", "model": "uno_mille_1996", "color": "#8d9aa8", "plate": "EMP0R01",
    "odometer_km": 0.0, "fuel_l": 25.0, "condition": 1.0, "oil_km_left": 3000.0, "tuning": [],
    "insured": false, "status": "ativo", "parked": {}, "last_pos": [], "history": [], "owner": "Patio"
  }
  var car := SupremoCar.make(loaner, true)
  car.position = world.poi_front("patio", 0.0)
  car.rotation.y = 0.0
  _dynamic.add_child(car)
  _set_player(car, loaner)
  Bus.say("Voce recebeu um veiculo emprestado. Regularize e retire o seu no Patio.", "warn")

func place_new_vehicle(v: Dictionary) -> void:
  var off: float = [-12.0, -4.0, 4.0, 12.0][randi() % 4]
  parking.spawn_parked(v, world.poi_front("concessionaria", off), 0.0, false)

func release_from_patio(v: Dictionary) -> void:
  v["status"] = "ativo"
  var inst: SupremoCar = parking.spawn_parked(v, world.poi_front("patio", [-9.0, 0.0, 9.0][randi() % 3]), 0.0, false)
  if str(Game.active_uid) == "emprestado":
    var cur := get_player()
    if cur != null:
      cur.queue_free()
    player = null
    _take_control(inst, v)

func rebuild_player() -> void:
  var old := get_player()
  if old == null or str(player_v.get("uid", "")) == "emprestado":
    return
  var xf := old.global_transform
  var frozen := old.freeze
  var engine := old.engine_on
  var car := SupremoCar.make(player_v, true)
  car.transform = xf
  car.position.y += 0.15
  _dynamic.add_child(car)
  if frozen:
    car.park()
    car.engine_on = engine
    parking.cars[str(player_v["uid"])] = car
  old.queue_free()
  _set_player(car, player_v)

func refuel(liters: float) -> String:
  var cur := get_player()
  if cur == null:
    return "Sem veiculo."
  var cost: int = int(ceil(liters * float(Data.economy.get("preco_combustivel_l", 6.2))))
  if not Game.spend(cost, "Combustivel"):
    return "Saldo insuficiente."
  cur.fuel_l = minf(cur.tank_l, cur.fuel_l + liters)
  player_v["fuel_l"] = cur.fuel_l
  return "Abastecido %.1f L por R$ %d." % [liters, cost]

# ---------------------------------------------------------------- eventos
func _on_vehicle_removed(uid: String, _reason: String) -> void:
  if uid == Game.active_uid:
    player = null
    call_deferred("_ensure_active")

func _on_seized(_reason: String) -> void:
  var v: Dictionary = Game.get_vehicle(Game.active_uid)
  var cur := get_player()
  if cur != null:
    cur.queue_free()
  player = null
  if not v.is_empty():
    v["status"] = "patio"
    v["parked"] = {}
    parking.cars.erase(str(v["uid"]))
  call_deferred("_ensure_active")

func _on_night(is_night: bool) -> void:
  _lights_on = is_night
  var cur := get_player()
  if cur != null:
    cur.set_headlights(is_night)

func _on_drive(gas: float, stop: float, steering: float, park_brake: bool) -> void:
  var cur := get_player()
  if cur == null or cur.freeze:
    return
  cur.throttle = gas
  cur.brake = stop
  cur.steer = steering
  cur.handbrake = park_brake

func _on_action(act: String) -> void:
  var cur := get_player()
  if cur == null:
    return
  match act:
    "interact":
      var poi := world.nearest_poi(cur.global_position, 16.0)
      if not poi.is_empty() and str(poi["tipo"]) in MENU_POIS:
        menus.open_for_poi(poi)
    "phone":
      menus.open_celular()
    "park":
      _toggle_park(cur)
    "lock":
      if cur.freeze and not player_v["parked"].is_empty():
        var locked: bool = not bool(player_v["parked"].get("locked", false))
        player_v["parked"]["locked"] = locked
        Bus.say("Veiculo trancado." if locked else "Veiculo destrancado.")
      else:
        Bus.say("Estacione o veiculo [P] para trancar.", "warn")
    "engine":
      if cur.freeze:
        cur.engine_on = not cur.engine_on
        player_v["parked"]["engine_on"] = cur.engine_on
        Bus.say("Motor ligado (risco maior de furto)." if cur.engine_on else "Motor desligado.")
      else:
        Bus.say("Estacione o veiculo [P] para desligar o motor.", "warn")
    "lights":
      _lights_on = not _lights_on
      cur.set_headlights(_lights_on)
    "save":
      save()
    "quality":
      _cycle_quality()
    "reset":
      cur.recover()

func _toggle_park(cur: SupremoCar) -> void:
  if cur.freeze:
    cur.unpark()
    player_v["parked"] = {}
    parking.cars.erase(str(player_v["uid"]))
    Bus.say("Motor ligado. Boa viagem!")
    return
  if cur.speed_kmh > 5.0:
    Bus.say("Pare o veiculo para estacionar.", "warn")
    return
  var st: Dictionary = parking.make_state(cur, false)
  cur.park()
  player_v["parked"] = st
  parking.cars[str(player_v["uid"])] = cur
  if bool(st["legal"]):
    Bus.say("Estacionado em vaga regular." + (" Garagem protegida." if bool(st["protected"]) else " Tranque o carro [L] para evitar furto."))
  else:
    Bus.say("ATENCAO: estacionamento irregular! Risco de multa e guincho. Use estacionamento ou garagem.", "warn")

func _cycle_quality() -> void:
  if quality.automatic:
    quality.set_manual("LOW")
  elif quality.profile == "LOW":
    quality.set_manual("MEDIUM")
  elif quality.profile == "MEDIUM":
    quality.set_manual("HIGH")
  else:
    quality.set_automatic()

# ---------------------------------------------------------------- salvar
func _sync_state() -> void:
  var cur := get_player()
  if cur != null and str(player_v.get("uid", "")) != "emprestado" and not player_v.is_empty():
    var p := cur.global_position
    player_v["last_pos"] = [p.x, p.y, p.z, cur.global_rotation.y]
    player_v["fuel_l"] = cur.fuel_l
    player_v["odometer_km"] = cur.odometer_km

func save(quiet: bool = false) -> void:
  _sync_state()
  var ok := Game.save_game()
  if not quiet:
    Bus.say("Jogo salvo." if ok else "Falha ao salvar o jogo.", "info" if ok else "warn")

func _notification(what: int) -> void:
  if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
    if world != null:
      save(true)

# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
  var cur := get_player()
  if cur == null:
    return
  var back := 8.3 if not cur.is_moto else 5.5
  var target := cur.global_position + cur.global_transform.basis.z * back + Vector3.UP * (3.4 if not cur.is_moto else 2.4)
  camera.global_position = camera.global_position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
  camera.look_at(cur.global_position + Vector3.UP * 0.65)
  _update_hud(cur)
  _autosave += delta
  if _autosave >= AUTOSAVE_S:
    _autosave = 0.0
    save(true)

func _update_hud(cur: SupremoCar) -> void:
  var gear_text := "R" if cur.reverse else str(cur.gear)
  var line1 := "%03d km/h | %04d RPM | M%s" % [roundi(cur.speed_kmh), roundi(cur.rpm), gear_text]
  if cur.freeze:
    line1 = "ESTACIONADO%s" % (" (motor ligado)" if cur.engine_on else "")
  var loaner := " [EMPRESTADO]" if str(player_v.get("uid", "")) == "emprestado" else ""
  var cond: int = int(float(player_v.get("condition", 1.0)) * 100.0)
  var stars := "*".repeat(police.stars())
  var line2 := "Comb %.0f/%.0f L | Cond %d%% | %s %s | %s%s" % [cur.fuel_l, cur.tank_l, cond, weather.clock_text(), weather.state, str(cur.def.get("modelo", "")), loaner]
  var line3 := "R$ %d | Rep %d | Multas %d (R$ %d) | Procurado: %s" % [Game.money, Game.reputation, Game.unpaid_fines().size(), Game.unpaid_total(), stars if stars != "" else "-"]
  var poi := world.nearest_poi(cur.global_position, 16.0)
  var prompt := ""
  if not ui.panel_open and not poi.is_empty() and str(poi["tipo"]) in MENU_POIS:
    prompt = str(poi["nome"])
  var m_text := ""
  var m := mission.active()
  if not m.is_empty():
    var tl := mission.time_left()
    m_text = "MISSAO: %s - %s" % [m["titulo"], mission.step_text()]
    if tl > 0.0:
      m_text += "  (%d:%02d)" % [int(tl) / 60, int(tl) % 60]
  var lock_label := "TRANCAR [L]"
  if cur.freeze and not player_v.get("parked", {}).is_empty() and bool(player_v["parked"].get("locked", false)):
    lock_label = "DESTRANCAR [L]"
  ui.update_hud({"text": "%s\n%s\n%s" % [line1, line2, line3], "mission": m_text, "prompt": prompt, "lock_label": lock_label})
  ui.minimap.police = police.responders
  var tp := mission.target_position()
  ui.minimap.target = tp
  _beacon.visible = tp != Vector3.INF
  if _beacon.visible:
    _beacon.global_position = tp + Vector3(0, 22.0, 0)
