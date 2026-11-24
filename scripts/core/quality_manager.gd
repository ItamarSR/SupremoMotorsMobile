extends Node
class_name SupremoQualityManager

signal quality_changed(profile: String)

const PROFILES := ["LOW", "MEDIUM", "HIGH"]
var profile := "MEDIUM"
var automatic := true
var _samples: Array[float] = []
var _elapsed := 0.0
var _last_change := 0.0
var _world: Node3D
var _sun: DirectionalLight3D

func setup(world: Node3D, sun: DirectionalLight3D) -> void:
 _world = world
 _sun = sun
 apply_profile("MEDIUM")

func apply_profile(name: String) -> void:
 if not name in PROFILES:
  return
 profile = name
 if is_instance_valid(_sun):
  _sun.shadow_enabled = profile == "HIGH"
 if is_instance_valid(_world):
  # Grupo "decoration": arvores, postes, faixas e semaforos. No modo LOW some parte deles.
  var idx := 0
  for node in get_tree().get_nodes_in_group("decoration"):
   if node is Node3D:
    node.visible = profile != "LOW" or idx % 2 == 0
    idx += 1
 quality_changed.emit(profile)

func set_manual(name: String) -> void:
 automatic = false
 apply_profile(name)

func set_automatic() -> void:
 automatic = true
 _samples.clear()
 _elapsed = 0.0
 _last_change = 0.0

func _process(delta: float) -> void:
 if not automatic:
  return
 _elapsed += delta
 _last_change += delta
 if delta <= 0.0 or delta > 0.25:
  return
 _samples.append(1.0 / delta)
 if _samples.size() > 120:
  _samples.pop_front()
 if _elapsed < 8.0 or _last_change < 20.0 or _samples.size() < 60:
  return
 _elapsed = 0.0
 var total := 0.0
 for value in _samples:
  total += value
 var average := total / float(_samples.size())
 # Hysteresis reduces oscillation. This is runtime FPS adaptation, not GPU detection.
 if average < 26.0 and profile != "LOW":
  apply_profile("LOW" if profile == "MEDIUM" else "MEDIUM")
  _last_change = 0.0
 elif average > 53.0 and profile != "HIGH":
  apply_profile("HIGH" if profile == "MEDIUM" else "MEDIUM")
  _last_change = 0.0
 _samples.clear()
