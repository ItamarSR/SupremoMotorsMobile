extends Node
# Testes automatizados de logica (dados, tuning, economia, save, missoes).
# Rodar:  godot --headless --path . res://tests/test_runner.tscn
# Codigo de saida 0 = tudo certo, 1 = ha falhas. Usa user://test_save.json (nao toca seu save).

var _ok := 0
var _fail := 0

func _ready() -> void:
  await get_tree().process_frame
  _test_data()
  _test_stats()
  _test_economy()
  _test_fines()
  _test_save()
  _test_missions()
  _test_plate()
  print("TESTES: %d ok, %d falhas" % [_ok, _fail])
  get_tree().quit(1 if _fail > 0 else 0)

func check(cond: bool, msg: String) -> void:
  if cond:
    _ok += 1
  else:
    _fail += 1
    printerr("FALHOU: " + msg)

func _fresh() -> void:
  Game.new_game()
  Game.money = 100000

func _test_data() -> void:
  check(Data.vehicles.size() >= 6, "ao menos 6 veiculos carregados")
  check(Data.vehicles.has("gol_gl_1988") and Data.vehicles.has("cg_160"), "carro e moto presentes")
  check(Data.tuning_index.size() > 10, "catalogo de tuning carregado")
  check(not Data.police.is_empty() and not Data.economy.is_empty() and not Data.world.is_empty(), "json de policia/economia/mundo")
  var last := -1.0
  var sorted_ok := true
  for n in Data.police.get("niveis", []):
    if float(n["min"]) < last:
      sorted_ok = false
    last = float(n["min"])
  check(sorted_ok, "niveis de suspeita em ordem crescente")
  for id in Data.vehicles:
    var d: Dictionary = Data.vehicles[id]
    check(float(d["torque_nm"]) > 0.0 and (d["marchas"] as Array).size() >= 4, "veiculo %s com torque e marchas" % id)

func _test_stats() -> void:
  var def: Dictionary = Data.vehicle_def("gol_gl_1988")
  var base: Dictionary = VehicleStats.compute(def, [])
  check(is_equal_approx(float(base["hp"]), 66.0), "potencia base do Gol = 66 cv")
  var tuned: Dictionary = VehicleStats.compute(def, ["ecu_stage1"])
  check(float(tuned["hp"]) > float(base["hp"]), "ECU aumenta potencia")
  var turbo: Dictionary = VehicleStats.compute(def, ["turbo_pequeno", "escape_inox_70", "spoiler_gt"])
  check(bool(turbo["turbo"]) and float(turbo["exhaust_mm"]) >= 70.0 and bool(turbo["spoiler"]), "turbo/escape/aerofolio refletidos")
  check(float(turbo["mass"]) > float(base["mass"]), "pecas aumentam a massa")
  check(float(turbo["reliability"]) < float(base["reliability"]), "turbo reduz confiabilidade")
  check(int(turbo["value"]) > int(base["value"]), "tuning valoriza o veiculo")

func _test_economy() -> void:
  _fresh()
  var eco := EconomySystem.new()
  var v: Dictionary = Game.vehicles[0]
  check(eco.install_part(v, "turbo_pequeno").begins_with("Instalado"), "instala turbo pequeno")
  eco.install_part(v, "turbo_grande")
  check(("turbo_grande" in v["tuning"]) and not ("turbo_pequeno" in v["tuning"]), "slot de turbo e exclusivo")
  var before: int = Game.money
  var msg := eco.take_loan(1000)
  check(Game.money == before + 1000 and Game.loan == 1150, "emprestimo de 1000 gera divida de 1150: " + msg)
  check(eco.take_loan(1000).begins_with("Voce ja tem"), "segundo emprestimo e recusado")
  eco.repay_loan()
  check(Game.loan == 0, "emprestimo quitado")
  var nv: Dictionary = eco.buy_vehicle("uno_mille_1996")
  check(not nv.is_empty() and Game.vehicles.size() == 2, "compra de veiculo")
  check(eco.sell_price(nv) < int(Data.vehicle_def("uno_mille_1996")["preco"]), "venda paga menos que o preco novo")
  Game.money = 10
  check(eco.buy_vehicle("skyline_r34").is_empty(), "compra sem saldo e recusada")
  eco.free()

func _test_fines() -> void:
  _fresh()
  for i in range(3):
    Game.add_fine("excesso_velocidade", "teste", 100)
  check(Game.is_irregular(), "3 multas pendentes tornam o veiculo irregular")
  check(Game.pay_all_fines() and Game.unpaid_total() == 0 and not Game.is_irregular(), "pagar multas regulariza")

func _test_save() -> void:
  _fresh()
  Game.save_path = "user://test_save.json"
  Game.money = 1234
  Game.reputation = 7
  Game.flags["infrator"] = 1
  check(Game.save_game(), "salva jogo")
  Game.money = 0
  Game.reputation = 0
  Game.flags = {}
  check(Game.load_game() and Game.money == 1234 and Game.reputation == 7 and int(Game.flags.get("infrator", 0)) == 1, "carrega o que salvou")
  check(Game.vehicles.size() == 1 and Game.active_uid == Game.vehicles[0]["uid"], "veiculo e veiculo ativo persistem")
  Game.from_dict({"version": 99})
  check(not Game.from_dict({"version": 99}), "save de versao futura e recusado")
  DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
  Game.save_path = Game.DEFAULT_SAVE_PATH

func _test_missions() -> void:
  var ids: Array = []
  for m in Data.missions:
    ids.append(str(m["id"]))
  var poi_ids: Array = []
  for p in Data.world.get("pois", []):
    poi_ids.append(str(p["id"]))
  for m in Data.missions:
    for s in m["passos"]:
      if s.has("poi"):
        check(str(s["poi"]) in poi_ids, "missao %s referencia POI existente (%s)" % [m["id"], s["poi"]])
    for req in m.get("requer", {}).get("concluidas", []):
      check(str(req) in ids, "missao %s requer missao existente" % m["id"])

func _test_plate() -> void:
  var re := RegEx.new()
  re.compile("^[A-Z]{3}[0-9][A-Z][0-9]{2}$")
  for i in range(20):
    check(re.search(Game.gen_plate()) != null, "placa no formato Mercosul")
