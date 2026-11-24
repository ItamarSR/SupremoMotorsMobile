extends Node
class_name WeatherSystem
# Ciclo de dia e noite + clima dinamico (limpo, nublado, chuva).
# Chuva reduz a aderencia (Game.grip_env). Atualiza luz, ceu, neblina, janelas e postes.

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var world: WorldBuilder
var rain: CPUParticles3D
var state := "limpo"
var day_length := 720.0
var _state_timer := 150.0
var _was_night := false

func setup(p_sun: DirectionalLight3D, p_env: Environment, p_sky: ProceduralSkyMaterial, p_world: WorldBuilder, p_rain: CPUParticles3D) -> void:
  sun = p_sun
  env = p_env
  sky_mat = p_sky
  world = p_world
  rain = p_rain
  day_length = float(Data.world.get("dia_duracao_s", 720))
  _apply_weather()
  _apply_time()

func is_night() -> bool:
  return Game.time_of_day < 5.5 or Game.time_of_day > 18.5

func clock_text() -> String:
  var h := int(Game.time_of_day)
  var m := int((Game.time_of_day - float(h)) * 60.0)
  return "%02d:%02d" % [h, m]

func _process(delta: float) -> void:
  Game.time_of_day = fposmod(Game.time_of_day + delta * 24.0 / day_length, 24.0)
  _apply_time()
  _state_timer -= delta
  if _state_timer <= 0.0:
    _roll_weather()

func _roll_weather() -> void:
  _state_timer = randf_range(150.0, 300.0)
  var r := randf()
  var next := "limpo" if r < 0.5 else ("nublado" if r < 0.8 else "chuva")
  if next != state:
    state = next
    _apply_weather()
    Bus.say("Clima: %s" % state, "info")

func _apply_weather() -> void:
  rain.emitting = state == "chuva"
  match state:
    "chuva":
      Game.grip_env = 0.78
    "nublado":
      Game.grip_env = 0.95
    _:
      Game.grip_env = 1.0

func _apply_time() -> void:
  var t: float = Game.time_of_day
  var elev: float = sin((t - 6.0) / 24.0 * TAU)
  var day: float = clampf(elev * 2.0 + 0.25, 0.0, 1.0)
  var warm: float = clampf(1.0 - absf(elev) * 3.0, 0.0, 1.0)
  var overcast: float = 0.0 if state == "limpo" else (0.45 if state == "nublado" else 0.7)
  sun.rotation_degrees = Vector3(-(t - 6.0) * 15.0, 35.0, 0.0)
  sun.light_energy = clampf(elev * 1.5, 0.0, 1.3) * (1.0 - overcast * 0.6)
  sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.55, 0.25), warm)
  var top := Color(0.01, 0.02, 0.08).lerp(Color(0.25, 0.45, 0.85), day)
  var hor := Color(0.04, 0.07, 0.18).lerp(Color(0.65, 0.78, 0.92), day)
  hor = hor.lerp(Color(1.0, 0.55, 0.3), warm * 0.5)
  var grey := Color(0.5, 0.52, 0.56) * (0.25 + 0.75 * day)
  top = top.lerp(grey, overcast)
  hor = hor.lerp(grey, overcast)
  sky_mat.sky_top_color = top
  sky_mat.sky_horizon_color = hor
  sky_mat.ground_horizon_color = hor
  sky_mat.ground_bottom_color = top * 0.4
  env.ambient_light_energy = lerpf(0.35, 1.0, day)
  env.fog_light_color = hor
  env.fog_density = 0.0012 + overcast * 0.003
  var night_amount: float = 1.0 - day
  for m in world.window_mats:
    (m as StandardMaterial3D).emission_energy_multiplier = night_amount * 1.8
  for m in world.lamp_mats:
    (m as StandardMaterial3D).emission_energy_multiplier = night_amount * 4.0
  var night := is_night()
  if night != _was_night:
    _was_night = night
    Bus.night_changed.emit(night)
