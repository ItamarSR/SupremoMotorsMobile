extends RefCounted
class_name VehicleStats
# Calcula os atributos finais de um veiculo a partir da definicao (data/vehicles.json)
# e das pecas instaladas (data/tuning.json). Funcao pura: facil de testar.

static func compute(def: Dictionary, parts: Array) -> Dictionary:
  var s: Dictionary = {
    "power_mult": 1.0, "weight_add": 0.0, "grip_mult": 1.0, "brake_mult": 1.0,
    "fuel_mult": 1.0, "reliability": float(def.get("confiabilidade", 0.9)),
    "value_mult": 1.0, "ride_mm": 0.0, "turbo": false,
    "exhaust_mm": float(def.get("escape_mm", 50)), "downforce": 0.0, "final_mult": 1.0,
    "alarm": false, "tracker": false, "pops": false, "neon": false, "spoiler": false,
    "rim_color": ""
  }
  for pid in parts:
    var item: Dictionary = Data.tuning_item(str(pid))
    if item.is_empty():
      continue
    var e: Dictionary = item.get("efeitos", {})
    s["power_mult"] = float(s["power_mult"]) * (1.0 + float(e.get("potencia_pct", 0.0)) / 100.0)
    s["weight_add"] = float(s["weight_add"]) + float(e.get("peso_kg", 0.0))
    s["grip_mult"] = float(s["grip_mult"]) * (1.0 + float(e.get("aderencia_pct", 0.0)) / 100.0)
    s["brake_mult"] = float(s["brake_mult"]) * (1.0 + float(e.get("freio_pct", 0.0)) / 100.0)
    s["fuel_mult"] = float(s["fuel_mult"]) * (1.0 + float(e.get("consumo_pct", 0.0)) / 100.0)
    s["reliability"] = float(s["reliability"]) + float(e.get("confiabilidade", 0.0))
    s["value_mult"] = float(s["value_mult"]) + float(e.get("valor_pct", 0.0)) / 100.0
    s["ride_mm"] = float(s["ride_mm"]) + float(e.get("altura_mm", 0.0))
    s["downforce"] = float(s["downforce"]) + float(e.get("downforce", 0.0))
    s["final_mult"] = float(s["final_mult"]) * (1.0 + float(e.get("relacao_final_pct", 0.0)) / 100.0)
    if e.get("turbo", false):
      s["turbo"] = true
    if e.get("pops", false):
      s["pops"] = true
    if e.get("alarme", false):
      s["alarm"] = true
    if e.get("rastreador", false):
      s["tracker"] = true
    if e.has("escape_mm"):
      s["exhaust_mm"] = maxf(float(s["exhaust_mm"]), float(e["escape_mm"]))
    var visual: String = str(item.get("visual", ""))
    if visual == "spoiler":
      s["spoiler"] = true
    elif visual == "neon":
      s["neon"] = true
    elif visual == "rodas":
      s["rim_color"] = str(item.get("cor", ""))
  s["reliability"] = clampf(float(s["reliability"]), 0.3, 1.0)
  s["ride_mm"] = maxf(float(s["ride_mm"]), -90.0)
  s["hp"] = float(def.get("potencia_cv", 60)) * float(s["power_mult"])
  s["torque_nm"] = float(def.get("torque_nm", 100)) * float(s["power_mult"])
  s["mass"] = maxf(120.0, float(def.get("massa_kg", 1000)) + float(s["weight_add"]))
  s["value"] = int(float(def.get("preco", 0)) * float(s["value_mult"]))
  return s

## Valor de mercado de uma peca instalada (usado pela oficina para descartar slots).
static func slot_of(item_id: String) -> String:
  return str(Data.tuning_item(item_id).get("slot", ""))
