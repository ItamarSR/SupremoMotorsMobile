extends Node
# Barramento de eventos desacoplado (autoload "Bus").
# Sistemas emitem/ouvem sinais aqui em vez de se referenciarem diretamente.

signal notify(text: String, kind: String)
signal money_changed(amount: int)
signal fine_added(fine: Dictionary)
signal mission_changed
signal choice_requested(choice: Dictionary, mission_id: String)
signal vehicle_changed
signal night_changed(is_night: bool)
signal vehicle_removed(uid: String, reason: String)

func say(text: String, kind: String = "info") -> void:
  notify.emit(text, kind)
