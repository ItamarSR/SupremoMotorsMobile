extends Node
class_name EconomySystem
# Banco, emprestimo, seguro, compra/venda e despesas recorrentes (seguro e IPVA).
# Contra inflacao infinita: ha varios ralos (multas, combustivel, guincho, IPVA,
# seguro, juros) e a venda de veiculos paga so uma fracao do valor (venda_pct).
# Nao implementado: transferencias entre jogadores e financiamento parcelado.

var _timer := 0.0
var _cycles := 0

func _process(delta: float) -> void:
  _timer += delta
  var interval: float = float(Data.economy.get("despesas", {}).get("intervalo_s", 240))
  if _timer >= interval:
    _timer = 0.0
    _cycles += 1
    _charge()

func _charge() -> void:
  var cfg: Dictionary = Data.economy.get("despesas", {})
  var prem_pct: float = float(Data.economy.get("seguro", {}).get("premio_pct_valor", 0.02))
  for v in Game.vehicles:
    if v["status"] != "ativo" and v["status"] != "patio":
      continue
    var model_name: String = str(Data.vehicle_def(str(v["model"])).get("modelo", ""))
    if bool(v.get("insured", false)):
      var premium: int = int(float(Game.vehicle_value(v)) * prem_pct)
      if Game.spend(premium, "Seguro - %s" % model_name):
        Bus.say("Despesa: seguro %s R$ %d" % [model_name, premium], "info")
      else:
        v["insured"] = false
        Bus.say("Seguro de %s cancelado por falta de pagamento." % model_name, "warn")
  if _cycles % int(cfg.get("ipva_a_cada_ciclos", 3)) == 0:
    for v in Game.vehicles:
      if v["status"] != "ativo":
        continue
      var model_name: String = str(Data.vehicle_def(str(v["model"])).get("modelo", ""))
      var tax: int = int(float(Game.vehicle_value(v)) * float(cfg.get("ipva_pct", 0.01)))
      if Game.spend(tax, "IPVA - %s" % model_name):
        Bus.say("Despesa: IPVA %s R$ %d" % [model_name, tax], "info")
      else:
        Game.add_fine("ipva_atrasado", "IPVA em atraso - %s" % model_name, tax + 50)
        Bus.say("IPVA em atraso: virou multa pendente!", "warn")

# ------------------------------------------------------------------ banco
func take_loan(amount: int) -> String:
  var maxv: int = int(Data.economy.get("emprestimo_max", 5000))
  if Game.loan > 0:
    return "Voce ja tem um emprestimo em aberto (R$ %d)." % Game.loan
  if amount <= 0 or amount > maxv:
    return "Valor invalido (maximo R$ %d)." % maxv
  var owed: int = int(float(amount) * (1.0 + float(Data.economy.get("juros_emprestimo", 0.15))))
  Game.loan = owed
  Game.add_money(amount, "Emprestimo (deve R$ %d)" % owed)
  return "Emprestimo de R$ %d aprovado. Valor a pagar: R$ %d." % [amount, owed]

func repay_loan() -> String:
  if Game.loan <= 0:
    return "Voce nao tem emprestimo."
  var pay: int = mini(Game.loan, Game.money)
  if pay <= 0 or not Game.spend(pay, "Pagamento de emprestimo"):
    return "Saldo insuficiente."
  Game.loan -= pay
  return "Pago R$ %d. Restante: R$ %d." % [pay, Game.loan]

# ------------------------------------------------------------------ veiculos
func buy_vehicle(model_id: String) -> Dictionary:
  var def: Dictionary = Data.vehicle_def(model_id)
  if def.is_empty() or not Game.spend(int(def["preco"]), "Compra: %s" % def.get("modelo", model_id)):
    return {}
  var v: Dictionary = Game.make_vehicle(model_id)
  Game.vehicles.append(v)
  return v

func sell_price(v: Dictionary) -> int:
  return int(float(Game.vehicle_value(v)) * float(Data.economy.get("venda_pct", 0.6)))

func sell_vehicle(uid: String) -> int:
  var v: Dictionary = Game.get_vehicle(uid)
  if v.is_empty():
    return 0
  var price: int = sell_price(v)
  Game.add_money(price, "Venda: %s" % Data.vehicle_def(str(v["model"])).get("modelo", ""))
  v["status"] = "vendido"
  v["parked"] = {}
  return price

func insurance_cost(v: Dictionary) -> int:
  return int(float(Game.vehicle_value(v)) * float(Data.economy.get("seguro", {}).get("adesao_pct_valor", 0.03)))

func buy_insurance(v: Dictionary) -> bool:
  if bool(v.get("insured", false)):
    return false
  if not Game.spend(insurance_cost(v), "Adesao de seguro"):
    return false
  v["insured"] = true
  return true

# ------------------------------------------------------------------ manutencao
func repair_cost(v: Dictionary) -> int:
  var def: Dictionary = Data.vehicle_def(str(v["model"]))
  return int((1.0 - float(v["condition"])) * float(def["preco"]) * float(Data.economy.get("reparo_pct_preco", 0.15)))

func repair(v: Dictionary) -> bool:
  var cost := repair_cost(v)
  if cost <= 0 or not Game.spend(cost, "Reparo"):
    return false
  v["condition"] = 1.0
  v["history"].append({"t": int(Game.play_time), "tipo": "reparo", "km": float(v["odometer_km"])})
  return true

func change_oil(v: Dictionary) -> bool:
  if not Game.spend(int(Data.economy.get("troca_oleo", 150)), "Troca de oleo"):
    return false
  v["oil_km_left"] = float(Data.economy.get("oleo_intervalo_km", 5000))
  v["history"].append({"t": int(Game.play_time), "tipo": "troca_oleo", "km": float(v["odometer_km"])})
  return true

# ------------------------------------------------------------------ tuning
func install_part(v: Dictionary, item_id: String) -> String:
  var item: Dictionary = Data.tuning_item(item_id)
  if item.is_empty():
    return "Peca inexistente."
  var parts: Array = v["tuning"]
  if item_id in parts:
    return "Ja instalada."
  if not Game.spend(int(item["preco"]), "Tuning: %s" % item["nome"]):
    return "Saldo insuficiente."
  var slot := str(item["slot"])
  for existing in parts.duplicate():
    if VehicleStats.slot_of(str(existing)) == slot:
      parts.erase(existing)
  parts.append(item_id)
  return "Instalado: %s" % item["nome"]

func paint(v: Dictionary, paint_id: String) -> String:
  for p in Data.paints:
    if str(p["id"]) == paint_id:
      if not Game.spend(int(p["preco"]), "Pintura: %s" % p["nome"]):
        return "Saldo insuficiente."
      v["color"] = str(p["cor"])
      return "Pintura aplicada: %s" % p["nome"]
  return "Cor inexistente."
