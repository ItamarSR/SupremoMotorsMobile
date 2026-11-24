extends Node
class_name PoliceSystem
# Fiscalizacao: infracoes -> suspeita -> abordagem -> perseguicao -> bloqueio -> apreensao.
# A intensidade depende da gravidade, da regiao, do historico (multas pendentes e
# escolhas como 'infrator') e do tempo de fuga. Regras em data/police.json.
# Viaturas sao SupremoCar controlados pela IA simples de perseguicao (car.gd).

signal seized(reason: String)

var world: WorldBuilder
var traffic: TrafficSystem
var container: Node3D
var player_getter: Callable
var enabled := true
var suspicion := 0.0
var state := "livre"                 # livre | abordagem | perseguicao
var responders: Array = []
var blockers: Array = []

var _cooldown := 0.0
var _stop_timer := 0.0
var _order_timer := 0.0
var _caught_timer := 0.0
var _escape_timer := 0.0
var _block_done := false
var _spawn_timer := 0.0
var _inside: Dictionary = {}

func setup(p_world: WorldBuilder, p_traffic: TrafficSystem, p_container: Node3D, p_getter: Callable) -> void:
  world = p_world
  traffic = p_traffic
  container = p_container
  player_getter = p_getter

func level() -> String:
  var resp := "nenhuma"
  for n in Data.police.get("niveis", []):
    if suspicion >= float(n["min"]):
      resp = str(n["resposta"])
  return resp

func stars() -> int:
  return clampi(int(ceil(suspicion / 25.0)), 0, 4)

## Registra uma infracao: soma suspeita (ponderada) e, se imediata, gera multa.
func register(inf_id: String, immediate_fine: bool = true) -> void:
  var inf: Dictionary = Data.police.get("infracoes", {}).get(inf_id, {})
  if inf.is_empty():
    return
  var p: SupremoCar = player_getter.call()
  var region := "residencial"
  if p != null and is_instance_valid(p):
    region = str(world.zone_info(p.global_position).get("regiao", "residencial"))
  var rmult: float = float(Data.police.get("regioes", {}).get(region, 1.0))
  var hist: float = 1.0 + float(Data.police.get("historico_mult_por_flag", 0.1)) * float(Game.flags.get("infrator", 0)) \
    + 0.05 * float(mini(Game.unpaid_fines().size(), 6))
  suspicion = minf(100.0, suspicion + float(inf.get("suspeita", 0)) * rmult * hist)
  if immediate_fine:
    var f: Dictionary = Game.add_fine(inf_id, str(inf["nome"]), int(inf["multa"]))
    Bus.say("MULTA: %s - R$ %d" % [f["nome"], f["valor"]], "fine")

func _physics_process(delta: float) -> void:
  if not enabled:
    return
  var p: SupremoCar = player_getter.call()
  if p == null or not is_instance_valid(p):
    return
  _cooldown = maxf(0.0, _cooldown - delta)
  var info: Dictionary = world.zone_info(p.global_position)
  if p.freeze or info.get("lote", "") == "garagem":
    # estacionado ou dentro da garagem particular: a pressao diminui rapido
    suspicion = maxf(0.0, suspicion - 6.0 * delta)
    if state != "livre" and suspicion < 20.0:
      _end_response("Voce saiu de vista. A policia desistiu.")
    return
  _check_infractions(p, info)
  match state:
    "livre":
      suspicion = maxf(0.0, suspicion - float(Data.police.get("decaimento_suspeita_por_s", 0.8)) * delta)
      if suspicion >= 30.0:
        _begin_response(p)
    "abordagem":
      _tick_abordagem(p, delta)
    "perseguicao":
      _tick_perseguicao(p, delta)

func _check_infractions(p: SupremoCar, info: Dictionary) -> void:
  var limit: float = float(info.get("limite", 40))
  var tol: float = float(Data.police.get("tolerancia_kmh", 10))
  if _cooldown <= 0.0 and p.speed_kmh > limit + tol and (bool(info.get("rua", false)) or info.get("lote", "") != ""):
    var excess: float = p.speed_kmh - limit
    var danger: float = float(Data.police.get("direcao_perigosa_acima_kmh", 45))
    register("direcao_perigosa" if excess > danger else "excesso_velocidade")
    _cooldown = float(Data.police.get("cooldown_infracao_s", 8))
  # avanco de sinal vermelho
  for rx in WorldBuilder.ROADS:
    for rz in WorldBuilder.ROADS:
      var key := "%d_%d" % [int(rx), int(rz)]
      var inside: bool = absf(p.global_position.x - rx) < 6.0 and absf(p.global_position.z - rz) < 6.0
      if inside and not _inside.get(key, false):
        var v := p.linear_velocity
        var axis := "ns" if absf(v.z) >= absf(v.x) else "ew"
        if p.speed_kmh > 12.0 and traffic.light_state(axis) == "vermelho":
          register("avanco_sinal")
      _inside[key] = inside

func _begin_response(p: SupremoCar) -> void:
  state = "abordagem"
  _stop_timer = 0.0
  _order_timer = 0.0
  _escape_timer = 0.0
  var r := _spawn_police(p)
  if r != null:
    Bus.say("POLICIA: encoste e pare o veiculo!", "police")

func _end_response(msg: String = "") -> void:
  for c in responders:
    if is_instance_valid(c):
      c.queue_free()
  for c in blockers:
    if is_instance_valid(c):
      c.queue_free()
  responders.clear()
  blockers.clear()
  state = "livre"
  _stop_timer = 0.0
  _order_timer = 0.0
  _caught_timer = 0.0
  _escape_timer = 0.0
  _block_done = false
  if msg != "":
    Bus.say(msg, "police")

func _closest(p: SupremoCar) -> float:
  var best := 1.0e9
  for c in responders:
    if is_instance_valid(c):
      best = minf(best, (c as SupremoCar).global_position.distance_to(p.global_position))
  return best

func _drive_responders(p: SupremoCar) -> void:
  for c in responders:
    if not is_instance_valid(c):
      continue
    var car: SupremoCar = c
    car.ai_target = p.global_position
    car.ai_ignore = p
    car.ai_max_kmh = clampf(p.speed_kmh * 1.12 + 18.0, 25.0, 125.0)

func _tick_abordagem(p: SupremoCar, delta: float) -> void:
  responders = responders.filter(func(c): return is_instance_valid(c))
  if responders.is_empty():
    state = "livre"
    return
  _drive_responders(p)
  var near := _closest(p)
  if near < 35.0:
    _order_timer += delta
  if p.speed_kmh < 6.0 and near < 25.0:
    _stop_timer += delta
  else:
    _stop_timer = maxf(0.0, _stop_timer - delta)
  if _stop_timer >= float(Data.police.get("tempo_parada_abordagem_s", 3.0)):
    _complete_stop()
  elif _order_timer > float(Data.police.get("tempo_ordem_parar_s", 7.0)) and p.speed_kmh > 25.0:
    register("fuga_fiscalizacao")
    suspicion = maxf(suspicion, 60.0)
    state = "perseguicao"
    Bus.say("FUGA! Perseguicao policial iniciada.", "police")
  elif suspicion >= 60.0:
    state = "perseguicao"
    Bus.say("Perseguicao policial iniciada!", "police")
  elif near > float(Data.police.get("distancia_fuga_m", 220)):
    _escape_timer += delta
    if _escape_timer > 15.0:
      suspicion *= 0.4
      _end_response("Voce despistou a viatura.")

func _complete_stop() -> void:
  var pending: int = Game.unpaid_fines().size()
  if Game.is_irregular():
    register("veiculo_irregular")
    _seize("Veiculo irregular: multas em atraso (%d)." % pending)
    return
  suspicion = 0.0
  if pending > 0:
    _end_response("Abordagem concluida. Voce tem %d multa(s) pendente(s). Pague na Delegacia." % pending)
  else:
    _end_response("Abordagem concluida. Documentos em dia. Siga viagem.")

func _tick_perseguicao(p: SupremoCar, delta: float) -> void:
  responders = responders.filter(func(c): return is_instance_valid(c))
  _drive_responders(p)
  _spawn_timer -= delta
  var wanted: int = 3 if suspicion >= 90.0 else 2
  if responders.size() < wanted and _spawn_timer <= 0.0:
    _spawn_timer = 6.0
    _spawn_police(p)
  if suspicion >= 90.0 and not _block_done:
    _spawn_blockade(p)
  var near := _closest(p)
  if near < 9.0 and p.speed_kmh < 10.0:
    _caught_timer += delta
  else:
    _caught_timer = maxf(0.0, _caught_timer - delta)
  if _caught_timer >= 2.5:
    _seize("Apreendido em perseguicao.")
    return
  if near > 100.0:
    suspicion = maxf(0.0, suspicion - float(Data.police.get("decaimento_fuga_por_s", 3.0)) * delta)
    if suspicion < 20.0:
      _end_response("Voce despistou a policia.")
  elif responders.is_empty():
    state = "livre"

func _seize(reason: String) -> void:
  Game.add_fine("apreensao", "Apreensao do veiculo", int(Data.police.get("taxa_apreensao", 600)))
  Bus.say("VEICULO APREENDIDO: %s" % reason, "police")
  suspicion = 0.0
  _end_response()
  seized.emit(reason)

func _spawn_police(p: SupremoCar) -> SupremoCar:
  var minimum: float = float(Data.police.get("distancia_spawn_min_m", 90))
  var maximum: float = float(Data.police.get("distancia_spawn_max_m", 170))
  var best := Vector3.ZERO
  var found := false
  for attempt in range(25):
    var rx: float = WorldBuilder.ROADS[randi() % 4]
    var rz: float = WorldBuilder.ROADS[randi() % 4]
    var pos := Vector3(rx + 3.5, 1.0, rz)
    var d := pos.distance_to(p.global_position)
    if d >= minimum and d <= maximum:
      best = pos
      found = true
      break
  if not found:
    return null
  var v := {"uid": "", "model": "viatura", "color": "#f2f2f2", "tuning": [], "plate": "PM%04d" % (randi() % 10000), "fuel_l": 50.0}
  var car := SupremoCar.make(v)
  car.position = best
  var dir := p.global_position - best
  car.rotation.y = atan2(-dir.x, -dir.z)
  car.ai_enabled = true
  car.ai_ignore = p
  container.add_child(car)
  responders.append(car)
  return car

func _spawn_blockade(p: SupremoCar) -> void:
  _block_done = true
  var v := p.linear_velocity
  v.y = 0.0
  var dir := v.normalized() if v.length() > 3.0 else (-p.global_transform.basis.z)
  var ahead := p.global_position + dir * 130.0
  ahead.x = clampf(ahead.x, -190.0, 190.0)
  ahead.z = clampf(ahead.z, -190.0, 190.0)
  var along_x := absf(dir.x) > absf(dir.z)
  var snap_vals: Array = []
  for r in WorldBuilder.ROADS:
    snap_vals.append(float(r))
  var best := float(snap_vals[0])
  var ref: float = ahead.z if along_x else ahead.x
  for s in snap_vals:
    if absf(float(s) - ref) < absf(best - ref):
      best = float(s)
  for off in [-3.2, 3.2]:
    var pos := Vector3(ahead.x, 1.0, best + off) if along_x else Vector3(best + off, 1.0, ahead.z)
    var vd := {"uid": "", "model": "viatura", "color": "#f2f2f2", "tuning": [], "plate": "PM%04d" % (randi() % 10000), "fuel_l": 50.0}
    var car := SupremoCar.make(vd)
    car.position = pos
    car.rotation.y = (PI * 0.5) if along_x else 0.0
    container.add_child(car)
    car.park()
    blockers.append(car)
  Bus.say("BLOQUEIO POLICIAL a frente!", "police")
