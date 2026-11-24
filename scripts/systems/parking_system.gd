extends Node
class_name ParkingSystem
# Estado persistente de veiculos estacionados + multa, guincho e furto.
#   parked = {pos, rot, engine_on, locked, since, legal, protected, fined}
# Tempo medido em Game.play_time (nao avanca com o jogo fechado).
# Furto: so veiculos DESTRANCADOS fora de lotes protegidos (garagem/oficina).
# NAO ha animacao de guincho nem NPC ladrao visivel: o evento e simulado por probabilidade.

var world: WorldBuilder
var container: Node3D
var cars: Dictionary = {}      # uid -> SupremoCar (instancias no mundo)
var _theft_timer := 0.0

func setup(p_world: WorldBuilder, p_container: Node3D) -> void:
  world = p_world
  container = p_container

func cfg() -> Dictionary:
  return Data.economy.get("estacionamento", {})

## Cria o dicionario de estado de estacionamento para um carro na posicao atual.
func make_state(car: SupremoCar, locked: bool) -> Dictionary:
  var info: Dictionary = world.zone_info(car.global_position)
  var pos := car.global_position
  return {
    "pos": [pos.x, pos.y, pos.z], "rot": car.global_rotation.y, "engine_on": false,
    "locked": locked, "since": Game.play_time, "legal": bool(info.get("legal", false)),
    "protected": bool(info.get("protegido", false)), "fined": false
  }

func spawn_parked(v: Dictionary, pos: Vector3, rot: float, locked: bool = false) -> SupremoCar:
  var car := SupremoCar.make(v, true)
  car.position = pos
  car.rotation.y = rot
  container.add_child(car)
  car.park()
  cars[str(v["uid"])] = car
  v["parked"] = make_state(car, locked)
  return car

func spawn_from_state(v: Dictionary) -> SupremoCar:
  var s: Dictionary = v["parked"]
  var p: Array = s["pos"]
  var car := SupremoCar.make(v, true)
  car.position = Vector3(float(p[0]), float(p[1]) + 0.2, float(p[2]))
  car.rotation.y = float(s.get("rot", 0.0))
  container.add_child(car)
  car.park()
  car.engine_on = bool(s.get("engine_on", false))
  cars[str(v["uid"])] = car
  return car

func remove_instance(uid: String) -> void:
  var c: Variant = cars.get(uid)
  if c != null and is_instance_valid(c):
    (c as Node).queue_free()
  cars.erase(uid)

func _physics_process(delta: float) -> void:
  var rules: Dictionary = cfg()
  var fine_after: float = float(rules.get("multa_apos_s", 25))
  var tow_after: float = float(rules.get("guincho_apos_s", 70))
  for v in Game.vehicles.duplicate():
    if v["status"] != "ativo" or v["parked"].is_empty():
      continue
    var s: Dictionary = v["parked"]
    if bool(s.get("legal", true)):
      continue
    var elapsed: float = Game.play_time - float(s.get("since", Game.play_time))
    if not bool(s.get("fined", false)) and elapsed > fine_after:
      s["fined"] = true
      var inf: Dictionary = Data.police.get("infracoes", {}).get("estacionamento_proibido", {})
      Game.add_fine("estacionamento_proibido", "%s (%s)" % [inf.get("nome", "Estacionamento proibido"), Data.vehicle_def(str(v["model"])).get("modelo", "")], int(inf.get("multa", 130)))
      Bus.say("MULTA de estacionamento irregular! Em breve o guincho vem.", "fine")
    if elapsed > tow_after:
      _tow(v)
  _theft_timer += delta
  if _theft_timer >= float(rules.get("furto_intervalo_s", 30)):
    _theft_timer = 0.0
    for v in Game.vehicles.duplicate():
      if v["status"] == "ativo" and not v["parked"].is_empty():
        _try_theft(v, rules)

func _tow(v: Dictionary) -> void:
  var uid := str(v["uid"])
  remove_instance(uid)
  v["status"] = "patio"
  v["parked"] = {}
  Bus.say("GUINCHO levou seu %s para o Patio Municipal." % Data.vehicle_def(str(v["model"])).get("modelo", "veiculo"), "warn")
  Bus.vehicle_removed.emit(uid, "guincho")

func _try_theft(v: Dictionary, rules: Dictionary) -> void:
  var s: Dictionary = v["parked"]
  if bool(s.get("locked", false)) or bool(s.get("protected", false)):
    return
  var chance: float = float(rules.get("furto_chance_base", 0.25))
  if bool(s.get("engine_on", false)):
    chance *= float(rules.get("furto_motor_ligado_mult", 1.6))
  var stats: Dictionary = VehicleStats.compute(Data.vehicle_def(str(v["model"])), v["tuning"])
  if bool(stats["alarm"]):
    chance *= float(rules.get("furto_alarme_mult", 0.4))
  if randf() >= chance:
    return
  var uid := str(v["uid"])
  var model_name: String = str(Data.vehicle_def(str(v["model"])).get("modelo", "veiculo"))
  v["status"] = "roubado"
  v["stolen_pos"] = s.get("pos", [])
  v["parked"] = {}
  remove_instance(uid)
  var extra := " Rastreador ativo: consulte a Delegacia." if bool(stats["tracker"]) else ""
  Bus.say("FURTO! Seu %s foi roubado.%s" % [model_name, extra], "warn")
  Bus.vehicle_removed.emit(uid, "furto")

## Recuperacao de veiculo roubado (Delegacia). Retorna mensagem de resultado.
func recover_stolen(v: Dictionary) -> String:
  var stats: Dictionary = VehicleStats.compute(Data.vehicle_def(str(v["model"])), v["tuning"])
  if bool(stats["tracker"]):
    var fee: int = int(cfg().get("recuperacao_rastreador_taxa", 400))
    if not Game.spend(fee, "Recuperacao via rastreador"):
      return "Saldo insuficiente (R$ %d)." % fee
    v["status"] = "patio"
    return "Veiculo localizado pelo rastreador e levado ao Patio Municipal."
  if bool(v.get("insured", false)):
    var pay: int = int(float(Game.vehicle_value(v)) * float(Data.economy.get("seguro", {}).get("cobertura_pct", 0.7)))
    Game.add_money(pay, "Indenizacao do seguro")
    v["status"] = "perdido"
    return "Sem rastreador: o seguro pagou R$ %d e o caso foi encerrado." % pay
  return "Sem rastreador nem seguro: nao ha como recuperar este veiculo."
