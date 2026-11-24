extends Node
class_name MissionSystem
# Missoes data-driven (data/missions.json): passos por POI, por coordenada ou por condicao,
# limite de tempo, falha por multa, recompensas, dialogos, escolhas e flags persistentes.
# Estado em Game.mission = {ativa, passo, concluidas}. Apenas o Capitulo 1 existe.

var world: WorldBuilder
var player_getter: Callable
var _time_left := 0.0
var _fines_at_start := 0

func setup(p_world: WorldBuilder, p_getter: Callable) -> void:
  world = p_world
  player_getter = p_getter
  if Game.mission.get("ativa", "") != "":
    var m := mission_def(str(Game.mission["ativa"]))
    _time_left = float(m.get("tempo_limite_s", 0))
    _fines_at_start = Game.fines.size()

func mission_def(id: String) -> Dictionary:
  for m in Data.missions:
    if str(m["id"]) == id:
      return m
  return {}

func active() -> Dictionary:
  return mission_def(str(Game.mission.get("ativa", "")))

func is_done(id: String) -> bool:
  return id in Game.mission.get("concluidas", [])

func available() -> Array:
  var out: Array = []
  for m in Data.missions:
    if is_done(str(m["id"])):
      continue
    var ok := true
    for req in m.get("requer", {}).get("concluidas", []):
      if not is_done(str(req)):
        ok = false
    if int(m.get("requer", {}).get("reputacao", 0)) > Game.reputation:
      ok = false
    if ok:
      out.append(m)
  return out

func start(id: String) -> bool:
  if Game.mission.get("ativa", "") != "":
    return false
  var m := mission_def(id)
  if m.is_empty():
    return false
  Game.mission["ativa"] = id
  Game.mission["passo"] = 0
  _time_left = float(m.get("tempo_limite_s", 0))
  _fines_at_start = Game.fines.size()
  Bus.mission_changed.emit()
  Bus.say("Missao iniciada: %s" % m["titulo"], "mission")
  return true

func abandon() -> void:
  if Game.mission.get("ativa", "") == "":
    return
  Game.mission["ativa"] = ""
  Game.mission["passo"] = 0
  Bus.mission_changed.emit()
  Bus.say("Missao abandonada.", "mission")

func current_step() -> Dictionary:
  var m := active()
  if m.is_empty():
    return {}
  var steps: Array = m["passos"]
  var i: int = int(Game.mission.get("passo", 0))
  return steps[i] if i < steps.size() else {}

func step_text() -> String:
  var s := current_step()
  return str(s.get("texto", "")) if not s.is_empty() else ""

func time_left() -> float:
  return _time_left

## Posicao do objetivo atual (ou Vector3.INF se nao houver ponto no mapa).
func target_position() -> Vector3:
  var s := current_step()
  if s.is_empty():
    return Vector3.INF
  if s.has("poi"):
    var p: Dictionary = world.pois.get(str(s["poi"]), {})
    return p["pos"] if not p.is_empty() else Vector3.INF
  if s.has("pos"):
    var a: Array = s["pos"]
    return Vector3(float(a[0]), 0.0, float(a[1]))
  return Vector3.INF

func _physics_process(delta: float) -> void:
  var m := active()
  if m.is_empty():
    return
  if float(m.get("tempo_limite_s", 0)) > 0.0:
    _time_left -= delta
    if _time_left <= 0.0:
      _fail("Tempo esgotado.")
      return
  if bool(m.get("falha_se_multa", false)) and Game.fines.size() > _fines_at_start:
    _fail("Voce tomou uma multa.")
    return
  var s := current_step()
  if s.is_empty():
    return
  if str(s.get("tipo", "")) == "possuir_veiculos":
    if Game.owned_active().size() >= int(s.get("qtd", 2)):
      _advance()
    return
  var p: SupremoCar = player_getter.call()
  if p == null or not is_instance_valid(p):
    return
  var target := target_position()
  if target == Vector3.INF:
    return
  var d := Vector2(p.global_position.x - target.x, p.global_position.z - target.z).length()
  if d < float(s.get("raio", 14)):
    _advance()

func _advance() -> void:
  Game.mission["passo"] = int(Game.mission.get("passo", 0)) + 1
  var m := active()
  if int(Game.mission["passo"]) >= (m["passos"] as Array).size():
    _complete(m)
  else:
    Bus.say("Objetivo: %s" % step_text(), "mission")
    Bus.mission_changed.emit()

func _complete(m: Dictionary) -> void:
  var reward: Dictionary = m.get("recompensa", {})
  if int(reward.get("dinheiro", 0)) > 0:
    Game.add_money(int(reward["dinheiro"]), "Missao: %s" % m["titulo"])
  Game.reputation += int(reward.get("reputacao", 0))
  var done: Array = Game.mission["concluidas"]
  done.append(str(m["id"]))
  Game.mission["ativa"] = ""
  Game.mission["passo"] = 0
  Bus.say("MISSAO CONCLUIDA: %s (+R$ %d, +%d rep)" % [m["titulo"], int(reward.get("dinheiro", 0)), int(reward.get("reputacao", 0))], "mission")
  Bus.mission_changed.emit()
  if m.has("escolha"):
    Bus.choice_requested.emit(m["escolha"], str(m["id"]))

func apply_choice(option: Dictionary) -> void:
  var e: Dictionary = option.get("efeitos", {})
  if int(e.get("dinheiro", 0)) > 0:
    Game.add_money(int(e["dinheiro"]), "Escolha de missao")
  Game.reputation += int(e.get("reputacao", 0))
  if e.has("flag"):
    Game.flags[str(e["flag"])] = int(Game.flags.get(str(e["flag"]), 0)) + 1
    Bus.say("Consequencia permanente: voce agora e conhecido como '%s' (a policia vai te marcar mais)." % e["flag"], "warn")

func _fail(reason: String) -> void:
  var m := active()
  Game.mission["ativa"] = ""
  Game.mission["passo"] = 0
  Bus.say("MISSAO FALHOU: %s (%s)" % [m.get("titulo", ""), reason], "warn")
  Bus.mission_changed.emit()
