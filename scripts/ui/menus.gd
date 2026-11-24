extends Node
class_name Menus
# Menus de jogo (oficina, banco, concessionaria, delegacia, patio, posto, garagem, celular).
# Cada menu monta uma lista de entradas e chama ui.show_menu; acoes reabrem o menu.
# Toda a logica de dinheiro/estado fica em EconomySystem/ParkingSystem/MissionSystem.

var ui: GameUI
var ctx    # no principal (main.gd): player, player_v, economy, parking, mission, police, world, weather...

func setup(p_ui: GameUI, p_ctx) -> void:
  ui = p_ui
  ctx = p_ctx

func _brl(n: int) -> String:
  return "R$ %d" % n

func _model_name(v: Dictionary) -> String:
  var d: Dictionary = Data.vehicle_def(str(v["model"]))
  return "%s %s (%s)" % [d.get("fabricante", ""), d.get("modelo", "?"), str(v.get("plate", ""))]

func _head(text: String) -> Dictionary:
  return {"t": text, "h": true}

func _info_money() -> String:
  return "Saldo: %s   |   Reputacao: %d   |   Divida: %s" % [_brl(Game.money), Game.reputation, _brl(Game.loan)]

func open_for_poi(poi: Dictionary) -> void:
  match str(poi["tipo"]):
    "oficina": open_oficina()
    "banco": open_banco()
    "concessionaria": open_concessionaria()
    "delegacia": open_delegacia()
    "patio": open_patio()
    "posto": open_posto()
    "estacionamento", "garagem": open_garagem()

# ------------------------------------------------------------------ oficina
func _editable() -> bool:
  return ctx.player_v.get("uid", "") != "" and Game.get_vehicle(str(ctx.player_v["uid"])).size() > 0

func _effects_text(e: Dictionary) -> String:
  var parts: Array = []
  var names := {"potencia_pct": "pot %+d%%", "aderencia_pct": "aderencia %+d%%", "freio_pct": "freio %+d%%", "peso_kg": "peso %+d kg",
    "consumo_pct": "consumo %+d%%", "altura_mm": "altura %+d mm", "escape_mm": "escape %d mm", "relacao_final_pct": "relacao final %+d%%"}
  for k in names:
    if e.has(k):
      parts.append(str(names[k]) % int(e[k]))
  if e.has("confiabilidade"):
    parts.append("confiab. %+.0f%%" % (float(e["confiabilidade"]) * 100.0))
  if e.get("turbo", false): parts.append("turbo")
  if e.get("pops", false): parts.append("estouros")
  if e.get("alarme", false): parts.append("alarme")
  if e.get("rastreador", false): parts.append("rastreador")
  if e.has("downforce"): parts.append("downforce")
  if e.has("valor_pct"): parts.append("valor +%d%%" % int(e["valor_pct"]))
  return ", ".join(parts)

func open_oficina(category: String = "") -> void:
  if not _editable():
    ui.show_menu("Oficina do Zeca", "Veiculo emprestado nao pode ser modificado.", [])
    return
  var v: Dictionary = ctx.player_v
  var entries: Array = []
  var sub := "%s\n%s" % [_model_name(v), _info_money()]
  if category == "":
    for cat in Data.tuning_categories:
      entries.append({"t": "%s  >" % cat["nome"], "cb": func(): open_oficina(str(cat["id"]))})
    entries.append({"t": "Pintura  >", "cb": func(): open_oficina("_pintura")})
    entries.append({"t": "Manutencao e reparos  >", "cb": func(): open_oficina("_manutencao")})
    entries.append({"t": "Diagnostico mecanico", "cb": func(): open_diagnostico()})
    ui.show_menu("Oficina do Zeca - Tuning", sub, entries)
    return
  entries.append({"t": "< voltar", "cb": func(): open_oficina("")})
  if category == "_pintura":
    for p in Data.paints:
      entries.append({"t": "%s - %s" % [p["nome"], _brl(int(p["preco"]))], "off": Game.money < int(p["preco"]), "cb": func():
        Bus.say(ctx.economy.paint(v, str(p["id"])))
        ctx.rebuild_player()
        open_oficina("_pintura")})
    ui.show_menu("Pintura", sub, entries)
    return
  if category == "_manutencao":
    var rc: int = ctx.economy.repair_cost(v)
    entries.append(_head("Condicao: %d%%   |   Oleo: %d km restantes   |   Odometro: %.1f km" % [int(float(v["condition"]) * 100.0), int(v["oil_km_left"]), float(v["odometer_km"])]))
    entries.append({"t": "Reparar lataria e mecanica - %s" % _brl(rc), "off": rc <= 0 or Game.money < rc, "cb": func():
      if ctx.economy.repair(v):
        Bus.say("Veiculo reparado.")
      open_oficina("_manutencao")})
    var oil: int = int(Data.economy.get("troca_oleo", 150))
    entries.append({"t": "Trocar oleo - %s" % _brl(oil), "off": Game.money < oil, "cb": func():
      if ctx.economy.change_oil(v):
        Bus.say("Oleo trocado.")
      open_oficina("_manutencao")})
    ui.show_menu("Manutencao", sub, entries)
    return
  var title := "Tuning"
  for cat in Data.tuning_categories:
    if str(cat["id"]) != category:
      continue
    title = str(cat["nome"])
    for item in cat["itens"]:
      var installed: bool = str(item["id"]) in v["tuning"]
      var label := "%s - %s%s\n    %s" % [item["nome"], _brl(int(item["preco"])), "  [INSTALADO]" if installed else "", _effects_text(item.get("efeitos", {}))]
      entries.append({"t": label, "off": installed or Game.money < int(item["preco"]), "cb": func():
        Bus.say(ctx.economy.install_part(v, str(item["id"])))
        ctx.rebuild_player()
        open_oficina(category)})
  ui.show_menu("Oficina - %s" % title, sub, entries)

func open_diagnostico() -> void:
  var v: Dictionary = ctx.player_v
  var car: SupremoCar = ctx.player
  var s: Dictionary = car.stats
  var d: Dictionary = car.def
  var lines: Array = [
    _head("%s" % _model_name(v)),
    _head("Potencia: %d cv   |   Torque: %d Nm   |   Massa: %d kg" % [int(s["hp"]), int(s["torque_nm"]), int(s["mass"])]),
    _head("Tracao: %s   |   Cambio: automatico (prototipo)   |   Cilindros: %s" % [d.get("tracao", "?"), str(d.get("cilindros", "?"))]),
    _head("Aderencia x%.2f   |   Freios x%.2f   |   Consumo x%.2f" % [float(s["grip_mult"]), float(s["brake_mult"]), float(s["fuel_mult"])]),
    _head("Confiabilidade: %d%%   |   Condicao: %d%%   |   Oleo: %d km" % [int(float(s["reliability"]) * 100.0), int(float(v.get("condition", 1.0)) * 100.0), int(v.get("oil_km_left", 0))]),
    _head("Combustivel: %.1f / %.0f L   |   Odometro: %.1f km" % [car.fuel_l, car.tank_l, car.odometer_km]),
    _head("Valor de mercado: %s   |   Seguro: %s" % [_brl(Game.vehicle_value(v)), "ativo" if v.get("insured", false) else "nao"])
  ]
  ui.show_menu("Diagnostico mecanico", "Dados reais do veiculo em uso.", lines)

# ------------------------------------------------------------------ banco
func open_banco() -> void:
  var entries: Array = []
  var fines_total: int = Game.unpaid_total()
  entries.append({"t": "Extrato bancario", "cb": func(): open_extrato("banco")})
  entries.append({"t": "Pagar multas pendentes (%s)" % _brl(fines_total), "off": fines_total <= 0 or Game.money < fines_total, "cb": func():
    if Game.pay_all_fines():
      Bus.say("Multas pagas. Veiculos regularizados.")
    open_banco()})
  if Game.loan > 0:
    entries.append({"t": "Quitar emprestimo (deve %s)" % _brl(Game.loan), "off": Game.money <= 0, "cb": func():
      Bus.say(ctx.economy.repay_loan())
      open_banco()})
  else:
    for amount in [1000, 3000, 5000]:
      entries.append({"t": "Emprestimo de %s (juros %d%%)" % [_brl(amount), int(float(Data.economy.get("juros_emprestimo", 0.15)) * 100.0)], "cb": func():
        Bus.say(ctx.economy.take_loan(amount))
        open_banco()})
  var v: Dictionary = ctx.player_v
  if Game.get_vehicle(str(v["uid"])).size() > 0 and not bool(v.get("insured", false)):
    var cost: int = ctx.economy.insurance_cost(v)
    entries.append({"t": "Contratar seguro do veiculo atual - adesao %s (mensalidade recorrente)" % _brl(cost), "off": Game.money < cost, "cb": func():
      if ctx.economy.buy_insurance(v):
        Bus.say("Seguro contratado.")
      open_banco()})
  ui.show_menu("Banco da Vila", _info_money(), entries)

func _back_to(where: String) -> void:
  if where == "banco":
    open_banco()
  else:
    open_celular()

func open_extrato(back: String = "banco") -> void:
  var entries: Array = [{"t": "< voltar", "cb": func(): _back_to(back)}]
  var rows: Array = Game.statement.duplicate()
  rows.reverse()
  for r in rows.slice(0, 20):
    entries.append(_head("%s%s   %s" % ["+" if int(r["v"]) >= 0 else "", _brl(int(r["v"])), str(r["m"])]))
  if rows.is_empty():
    entries.append(_head("Sem movimentacoes ainda."))
  ui.show_menu("Extrato bancario", _info_money(), entries)

# ------------------------------------------------------------------ concessionaria
func open_concessionaria() -> void:
  var entries: Array = []
  for def in Data.shop_vehicles():
    var price: int = int(def["preco"])
    var label := "%s %s %d  -  %s\n    %d cv | %d kg | %s | %s" % [def["fabricante"], def["modelo"], int(def["ano"]), _brl(price), int(def["potencia_cv"]), int(def["massa_kg"]), def["categoria"], def["tracao"]]
    entries.append({"t": label, "off": Game.money < price, "cb": func():
      var nv: Dictionary = ctx.economy.buy_vehicle(str(def["id"]))
      if not nv.is_empty():
        ctx.place_new_vehicle(nv)
        Bus.say("Compra realizada! O veiculo esta no estacionamento da concessionaria.")
      open_concessionaria()})
  entries.append({"t": "Vender um veiculo da garagem  >", "cb": func(): open_venda()})
  ui.show_menu("Concessionaria Supremo", _info_money(), entries)

func open_venda() -> void:
  var entries: Array = [{"t": "< voltar", "cb": func(): open_concessionaria()}]
  var count: int = Game.owned_active().size()
  for v in Game.owned_active():
    var price: int = ctx.economy.sell_price(v)
    var in_use: bool = str(v["uid"]) == Game.active_uid
    entries.append({"t": "%s - receber %s%s" % [_model_name(v), _brl(price), "  (em uso)" if in_use else ""],
      "off": count <= 1 or in_use, "cb": func():
        var uid := str(v["uid"])
        ctx.parking.remove_instance(uid)
        Bus.say("Vendido por %s." % _brl(ctx.economy.sell_vehicle(uid)))
        open_venda()})
  entries.append(_head("A venda paga %d%% do valor de mercado (ralo economico). Nao da para vender o veiculo em uso nem o ultimo." % int(float(Data.economy.get("venda_pct", 0.6)) * 100.0)))
  ui.show_menu("Vender veiculo", _info_money(), entries)

# ------------------------------------------------------------------ delegacia / patio
func open_delegacia() -> void:
  var entries: Array = []
  var unpaid: Array = Game.unpaid_fines()
  entries.append(_head("Multas pendentes: %d (%s)%s" % [unpaid.size(), _brl(Game.unpaid_total()), "  - VEICULO IRREGULAR" if Game.is_irregular() else ""]))
  for f in unpaid:
    entries.append(_head("  - %s: %s" % [f["nome"], _brl(int(f["valor"]))]))
  entries.append({"t": "Pagar todas as multas e regularizar - %s" % _brl(Game.unpaid_total()), "off": Game.unpaid_total() <= 0 or Game.money < Game.unpaid_total(), "cb": func():
    if Game.pay_all_fines():
      Bus.say("Multas pagas. Documentacao regularizada.")
    open_delegacia()})
  entries.append(_head("Veiculos furtados:"))
  var any_stolen := false
  for v in Game.vehicles:
    if v["status"] == "roubado":
      any_stolen = true
      entries.append({"t": "Registrar ocorrencia / recuperar: %s" % _model_name(v), "cb": func():
        Bus.say(ctx.parking.recover_stolen(v))
        open_delegacia()})
  if not any_stolen:
    entries.append(_head("  nenhum"))
  ui.show_menu("Delegacia Distrital", "%s\nSuspeita atual: %d%% (%s)" % [_info_money(), int(ctx.police.suspicion), ctx.police.level()], entries)

func open_patio() -> void:
  var entries: Array = []
  var fee: int = int(Data.economy.get("taxa_guincho", 350))
  var any := false
  for v in Game.vehicles:
    if v["status"] == "patio":
      any = true
      var total: int = fee + Game.unpaid_total()
      entries.append({"t": "Retirar %s - taxa %s + multas %s = %s" % [_model_name(v), _brl(fee), _brl(Game.unpaid_total()), _brl(total)],
        "off": Game.money < total, "cb": func():
          if Game.spend(fee, "Taxa de patio/guincho") and (Game.unpaid_total() == 0 or Game.pay_all_fines()):
            ctx.release_from_patio(v)
            Bus.say("Veiculo liberado do patio.")
          open_patio()})
  if not any:
    entries.append(_head("Nenhum veiculo seu no patio."))
  else:
    entries.append(_head("Sem dinheiro? Faca um emprestimo no Banco da Vila."))
  ui.show_menu("Patio Municipal", _info_money(), entries)

# ------------------------------------------------------------------ posto
func open_posto() -> void:
  var car: SupremoCar = ctx.player
  var price: float = float(Data.economy.get("preco_combustivel_l", 6.2))
  var missing: float = maxf(0.0, car.tank_l - car.fuel_l)
  var entries: Array = []
  entries.append({"t": "Completar o tanque (%.1f L) - %s" % [missing, _brl(int(ceil(missing * price)))], "off": missing < 0.5, "cb": func():
    Bus.say(ctx.refuel(missing))
    open_posto()})
  entries.append({"t": "Abastecer 10 L - %s" % _brl(int(10.0 * price)), "off": missing < 0.5, "cb": func():
    Bus.say(ctx.refuel(minf(10.0, missing)))
    open_posto()})
  ui.show_menu("Posto Estrada BR", "Combustivel: %.1f / %.0f L  |  R$ %.2f/L\n%s" % [car.fuel_l, car.tank_l, price, _info_money()], entries)

# ------------------------------------------------------------------ garagem
func open_garagem() -> void:
  var entries: Array = []
  for v in Game.vehicles:
    var st: String = str(v["status"])
    if st == "vendido" or st == "perdido":
      continue
    var d: Dictionary = Data.vehicle_def(str(v["model"]))
    var s: Dictionary = VehicleStats.compute(d, v["tuning"])
    var where := ""
    match st:
      "ativo":
        where = "EM USO" if str(v["uid"]) == Game.active_uid else ("estacionado" + (" (trancado)" if bool(v["parked"].get("locked", false)) else " (destrancado)" if not v["parked"].is_empty() else ""))
      "patio": where = "no PATIO (retire la)"
      "roubado": where = "FURTADO"
    var txt := "%s - %s\n    %d cv | %d Nm | %d kg | cond. %d%% | valor %s" % [_model_name(v), where, int(s["hp"]), int(s["torque_nm"]), int(s["mass"]), int(float(v["condition"]) * 100.0), _brl(Game.vehicle_value(v))]
    var can_take: bool = st == "ativo" and str(v["uid"]) != Game.active_uid
    entries.append({"t": txt, "off": not can_take, "cb": func():
      ctx.switch_to(str(v["uid"]))
      ui.close_menu()})
  ui.show_menu("Garagem", "Compare o desempenho e escolha qual veiculo conduzir.\n" + _info_money(), entries)

# ------------------------------------------------------------------ celular
func open_celular() -> void:
  var entries: Array = []
  entries.append({"t": "Missoes", "cb": func(): open_missoes()})
  entries.append({"t": "Multas (%d pendentes - %s)" % [Game.unpaid_fines().size(), _brl(Game.unpaid_total())], "cb": func(): open_multas()})
  entries.append({"t": "Banco / extrato", "cb": func(): open_extrato("celular")})
  entries.append({"t": "Garagem e comparacao de desempenho", "cb": func(): open_garagem()})
  entries.append({"t": "Painel de diagnostico", "cb": func(): open_diagnostico()})
  entries.append({"t": "Calendario de eventos", "cb": func(): open_eventos()})
  entries.append({"t": "Salvar jogo", "cb": func():
    ctx.save()
    open_celular()})
  ui.show_menu("Celular", "%s\nHora: %s   |   Clima: %s" % [_info_money(), ctx.weather.clock_text(), ctx.weather.state], entries)

func open_multas() -> void:
  var entries: Array = [{"t": "< voltar", "cb": func(): open_celular()}]
  var rows: Array = Game.fines.duplicate()
  rows.reverse()
  for f in rows.slice(0, 20):
    entries.append(_head("%s %s - %s" % ["[paga]" if f["paga"] else "[PENDENTE]", f["nome"], _brl(int(f["valor"]))]))
  if rows.is_empty():
    entries.append(_head("Nenhuma multa registrada."))
  ui.show_menu("Registro de multas", "Pague no Banco ou na Delegacia. Com %d ou mais pendentes o veiculo fica irregular." % int(Data.police.get("limite_multas_irregular", 3)), entries)

func open_eventos() -> void:
  var entries: Array = [{"t": "< voltar", "cb": func(): open_celular()}]
  entries.append(_head("Gerenciador de eventos (corrida, arrancada, drift, time attack, encontros...) AINDA NAO IMPLEMENTADO nesta versao."))
  entries.append(_head("Previsto no Capitulo 2 em diante; os tipos ja estao em Dados/eventos e no Server/events."))
  ui.show_menu("Calendario de eventos", "Voce pode explorar o mundo livremente.", entries)

func open_missoes() -> void:
  var entries: Array = [{"t": "< voltar", "cb": func(): open_celular()}]
  var active: Dictionary = ctx.mission.active()
  if not active.is_empty():
    entries.append(_head("EM ANDAMENTO: %s\n%s" % [active["titulo"], ctx.mission.step_text()]))
    entries.append({"t": "Abandonar missao", "cb": func():
      ctx.mission.abandon()
      open_missoes()})
  else:
    for m in ctx.mission.available():
      var reward: Dictionary = m.get("recompensa", {})
      entries.append({"t": "%s - %s\n    %s" % [m["titulo"], _brl(int(reward.get("dinheiro", 0))), m["descricao"]], "cb": func(): _mission_dialog(m)})
    if ctx.mission.available().is_empty():
      entries.append(_head("Nenhuma missao disponivel. Complete as anteriores."))
  entries.append(_head("Campanha:"))
  for c in Data.chapters:
    entries.append(_head("  Capitulo %d - %s [%s]" % [int(c["id"]), c["titulo"], "jogavel (prototipo)" if c["status"] == "prototipo" else "bloqueado - nao implementado"]))
  ui.show_menu("Missoes", "Reputacao: %d" % Game.reputation, entries)

func _mission_dialog(m: Dictionary) -> void:
  var entries: Array = []
  entries.append({"t": "Aceitar", "cb": func(): _accept_mission(str(m["id"]))})
  entries.append({"t": "Agora nao", "cb": func(): open_missoes()})
  ui.show_menu(str(m["titulo"]), str(m.get("dialogo_inicio", m["descricao"])), entries)

func _accept_mission(id: String) -> void:
  ctx.mission.start(id)
  ui.close_menu()

func open_choice(choice: Dictionary, _mission_id: String) -> void:
  var entries: Array = []
  for o in choice.get("opcoes", []):
    entries.append({"t": str(o["texto"]), "cb": func():
      ctx.mission.apply_choice(o)
      ui.close_menu()})
  ui.show_menu("Escolha", str(choice.get("texto", "")), entries)
