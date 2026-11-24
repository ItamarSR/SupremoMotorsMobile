extends Node
# Estado persistente do jogador (autoload "Game") + salvamento versionado.
# Logica de dados apenas: nada de UI ou de nos de cena aqui.

const SAVE_VERSION := 3
const DEFAULT_SAVE_PATH := "user://save_v3.json"
const LEGACY_PATH := "user://garage_v2.json"

var save_path: String = DEFAULT_SAVE_PATH
var money: int = 3000
var reputation: int = 0
var loan: int = 0
var player_name: String = "Jogador"
var vehicles: Array = []        # dicionarios de veiculo (ver make_vehicle)
var active_uid: String = ""
var fines: Array = []
var flags: Dictionary = {}
var mission: Dictionary = {"ativa": "", "passo": 0, "concluidas": []}
var statement: Array = []
var play_time: float = 0.0
var time_of_day: float = 17.5
var _seq: int = 0
var grip_env: float = 1.0       # so em runtime (clima)

func _process(delta: float) -> void:
  play_time += delta

# ------------------------------------------------------------------ novo jogo
func new_game() -> void:
  money = int(Data.economy.get("dinheiro_inicial", 3000))
  reputation = 0
  loan = 0
  vehicles = []
  fines = []
  flags = {}
  mission = {"ativa": "", "passo": 0, "concluidas": []}
  statement = []
  play_time = 0.0
  time_of_day = float(Data.world.get("hora_inicial", 17.5))
  var first: Dictionary = make_vehicle("gol_gl_1988")
  vehicles.append(first)
  active_uid = first["uid"]

func _next_id() -> int:
  _seq += 1
  return _seq

func gen_plate() -> String:
  # Formato Mercosul ficticio: LLL N L NN
  var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  var s := ""
  for i in range(3):
    s += letters[randi() % letters.length()]
  s += str(randi() % 10) + letters[randi() % letters.length()] + str(randi() % 10) + str(randi() % 10)
  return s

func make_vehicle(model_id: String) -> Dictionary:
  var def: Dictionary = Data.vehicle_def(model_id)
  return {
    "uid": "veh_%d_%d" % [_next_id(), randi() % 100000],
    "model": model_id,
    "owner": player_name,
    "plate": gen_plate(),
    "color": str(def.get("cor", "#cccccc")),
    "odometer_km": 0.0,
    "fuel_l": float(def.get("tanque_l", 40)) * 0.6,
    "condition": 1.0,
    "oil_km_left": float(Data.economy.get("oleo_intervalo_km", 5000)),
    "tuning": [],
    "insured": false,
    "status": "ativo",          # ativo | patio | roubado | perdido
    "parked": {},               # estado persistente de estacionamento (ver ParkingSystem)
    "last_pos": [],
    "history": []               # historico de manutencao
  }

func get_vehicle(uid: String) -> Dictionary:
  for v in vehicles:
    if v["uid"] == uid:
      return v
  return {}

func owned_active() -> Array:
  var out: Array = []
  for v in vehicles:
    if v["status"] == "ativo":
      out.append(v)
  return out

# ------------------------------------------------------------------ dinheiro
func add_money(amount: int, reason: String) -> void:
  money += amount
  _log(amount, reason)
  Bus.money_changed.emit(money)

func spend(amount: int, reason: String) -> bool:
  if amount < 0 or money < amount:
    return false
  money -= amount
  _log(-amount, reason)
  Bus.money_changed.emit(money)
  return true

func _log(value: int, reason: String) -> void:
  statement.append({"t": int(play_time), "v": value, "m": reason})
  if statement.size() > 100:
    statement.pop_front()

# ------------------------------------------------------------------ multas
func add_fine(kind: String, label: String, value: int) -> Dictionary:
  var f := {"id": "m%d" % _next_id(), "tipo": kind, "nome": label, "valor": value, "t": int(play_time), "paga": false}
  fines.append(f)
  Bus.fine_added.emit(f)
  return f

func unpaid_fines() -> Array:
  var out: Array = []
  for f in fines:
    if not f["paga"]:
      out.append(f)
  return out

func unpaid_total() -> int:
  var total := 0
  for f in unpaid_fines():
    total += int(f["valor"])
  return total

func pay_all_fines() -> bool:
  var total: int = unpaid_total()
  if total <= 0:
    return true
  if not spend(total, "Pagamento de multas"):
    return false
  for f in fines:
    f["paga"] = true
  return true

func is_irregular() -> bool:
  return unpaid_fines().size() >= int(Data.police.get("limite_multas_irregular", 3))

func vehicle_value(v: Dictionary) -> int:
  var def: Dictionary = Data.vehicle_def(str(v["model"]))
  var stats: Dictionary = VehicleStats.compute(def, v["tuning"])
  var dep_max: float = float(Data.economy.get("depreciacao_max", 0.5))
  var dep_km: float = float(Data.economy.get("depreciacao_km", 300000))
  var dep: float = minf(float(v["odometer_km"]) / dep_km, dep_max)
  var cond: float = lerpf(0.6, 1.0, float(v["condition"]))
  return int(float(stats["value"]) * (1.0 - dep) * cond)

# ------------------------------------------------------------------ save/load
func to_dict() -> Dictionary:
  return {
    "version": SAVE_VERSION, "money": money, "reputation": reputation, "loan": loan,
    "player_name": player_name, "vehicles": vehicles, "active_uid": active_uid,
    "fines": fines, "flags": flags, "mission": mission, "statement": statement,
    "play_time": play_time, "time_of_day": time_of_day, "seq": _seq
  }

func save_game() -> bool:
  var f := FileAccess.open(save_path, FileAccess.WRITE)
  if f == null:
    push_warning("Nao foi possivel salvar: %s" % FileAccess.get_open_error())
    return false
  f.store_string(JSON.stringify(to_dict()))
  return true

func load_game() -> bool:
  if FileAccess.file_exists(save_path):
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
    if typeof(parsed) != TYPE_DICTIONARY:
      push_warning("Save corrompido; ignorando.")
      return false
    return from_dict(parsed)
  if save_path == DEFAULT_SAVE_PATH and FileAccess.file_exists(LEGACY_PATH):
    # Migracao v2 -> v3: so o dinheiro era relevante.
    var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
    new_game()
    if typeof(old) == TYPE_DICTIONARY:
      money = maxi(0, int(old.get("money", money)))
    return true
  return false

func from_dict(d: Dictionary) -> bool:
  var ver: int = int(d.get("version", 0))
  if ver > SAVE_VERSION or ver < 3:
    push_warning("Versao de save nao suportada: %d" % ver)
    return false
  money = maxi(0, int(d.get("money", 0)))
  reputation = int(d.get("reputation", 0))
  loan = maxi(0, int(d.get("loan", 0)))
  player_name = str(d.get("player_name", "Jogador"))
  vehicles = d.get("vehicles", [])
  active_uid = str(d.get("active_uid", ""))
  fines = d.get("fines", [])
  flags = d.get("flags", {})
  mission = d.get("mission", {"ativa": "", "passo": 0, "concluidas": []})
  statement = d.get("statement", [])
  play_time = float(d.get("play_time", 0.0))
  time_of_day = float(d.get("time_of_day", 17.5))
  _seq = int(d.get("seq", 0))
  # Remove veiculos cujo modelo nao existe mais (pacote de conteudo removido).
  var valid: Array = []
  for v in vehicles:
    if Data.vehicles.has(str(v.get("model", ""))):
      valid.append(v)
    else:
      push_warning("Veiculo com modelo desconhecido removido do save: %s" % str(v.get("model", "")))
  vehicles = valid
  return true
