extends Node
# Banco de dados do jogo (autoload "Data"): carrega e valida os JSON de res://data
# e pacotes de conteudo extras (veiculos) de user://content e res://content.

const REQUIRED_VEHICLE_KEYS := ["id", "modelo", "massa_kg", "potencia_cv", "torque_nm", "rpm_max", "marchas", "diferencial", "tracao", "dimensoes", "preco"]
const CONTENT_DIRS := ["res://content", "user://content"]

var vehicles: Dictionary = {}
var tuning_categories: Array = []
var paints: Array = []
var tuning_index: Dictionary = {}
var police: Dictionary = {}
var economy: Dictionary = {}
var missions: Array = []
var chapters: Array = []
var world: Dictionary = {}

func _ready() -> void:
  reload()

func reload() -> void:
  vehicles.clear()
  tuning_index.clear()
  _add_vehicles(_read("res://data/vehicles.json"), "res://data/vehicles.json")
  for dir_path in CONTENT_DIRS:
    _load_content_pack(dir_path)
  var t: Dictionary = _read("res://data/tuning.json")
  tuning_categories = t.get("categorias", [])
  paints = t.get("pinturas", [])
  for cat in tuning_categories:
    for item in cat.get("itens", []):
      item["categoria"] = cat.get("id", "")
      tuning_index[str(item.get("id", ""))] = item
  police = _read("res://data/police.json")
  economy = _read("res://data/economy.json")
  world = _read("res://data/world.json")
  var m: Dictionary = _read("res://data/missions.json")
  missions = m.get("missoes", [])
  chapters = m.get("capitulos", [])

func _read(path: String) -> Dictionary:
  if not FileAccess.file_exists(path):
    push_error("Arquivo de dados ausente: %s" % path)
    return {}
  var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
  if typeof(parsed) != TYPE_DICTIONARY:
    push_error("JSON invalido: %s" % path)
    return {}
  return parsed

func _load_content_pack(dir_path: String) -> void:
  var dir := DirAccess.open(dir_path)
  if dir == null:
    return
  for f in dir.get_files():
    if f.ends_with(".json"):
      var full: String = dir_path.path_join(f)
      _add_vehicles(_read(full), full)

func _add_vehicles(src: Dictionary, origin: String) -> void:
  for d in src.get("veiculos", []):
    if _valid_vehicle(d, origin):
      vehicles[str(d["id"])] = d

func _valid_vehicle(d: Dictionary, origin: String) -> bool:
  for k in REQUIRED_VEHICLE_KEYS:
    if not d.has(k):
      push_error("Veiculo invalido em %s: falta a chave '%s'" % [origin, k])
      return false
  return true

func vehicle_def(id: String) -> Dictionary:
  return vehicles.get(id, {})

func tuning_item(id: String) -> Dictionary:
  return tuning_index.get(id, {})

func shop_vehicles() -> Array:
  var out: Array = []
  for id in vehicles:
    if vehicles[id].get("loja", true):
      out.append(vehicles[id])
  out.sort_custom(func(a, b): return float(a["preco"]) < float(b["preco"]))
  return out
