extends Node
class_name EngineAudio
# Audio de motor SINTETIZADO em tempo real (AudioStreamGenerator), controlado por
# parametros fisicos: RPM, carga, cilindros, diametro do escape, turbo, estouros e
# corte de giro. Nao usa arquivos de audio. NAO e MetaSounds (isso e da Unreal);
# e um sintetizador simples em GDScript, a ser substituido por amostras/FMOD depois.

const MIX_RATE := 22050.0

var enabled := true
var rpm := 900.0
var throttle := 0.0
var load_amount := 0.0
var cylinders := 4
var exhaust_mm := 50.0
var has_turbo := false
var has_pops := false
var limiter := false
var running := true

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _turbo_phase := 0.0
var _lp := 0.0
var _boost := 0.0
var _last_throttle := 0.0
var _blow := 0.0
var _pop := 0.0
var _lim_phase := 0.0

func _ready() -> void:
  _player = AudioStreamPlayer.new()
  var gen := AudioStreamGenerator.new()
  gen.mix_rate = MIX_RATE
  gen.buffer_length = 0.12
  _player.stream = gen
  _player.volume_db = -7.0
  add_child(_player)
  _player.play()
  _playback = _player.get_stream_playback()

func set_state(p_rpm: float, p_throttle: float, p_load: float, p_cyl: int, p_exhaust: float, p_turbo: bool, p_pops: bool, p_limiter: bool, p_running: bool) -> void:
  rpm = p_rpm
  throttle = p_throttle
  load_amount = p_load
  cylinders = maxi(1, p_cyl)
  exhaust_mm = p_exhaust
  has_turbo = p_turbo
  has_pops = p_pops
  limiter = p_limiter
  running = p_running

func _process(delta: float) -> void:
  if not enabled or _playback == null:
    return
  # Eventos discretos: alivio do turbo e estouros de escapamento.
  if has_turbo and _last_throttle > 0.6 and throttle < 0.2 and _boost > 0.4:
    _blow = 0.45
  if (has_turbo or has_pops) and throttle < 0.05 and rpm > 3500.0 and running and randf() < 0.9 * delta * (2.0 if has_pops else 0.4):
    _pop = 0.06
  _last_throttle = throttle
  var boost_target := 0.0
  if has_turbo and running:
    boost_target = clampf(throttle * clampf((rpm - 2000.0) / 3500.0, 0.0, 1.0), 0.0, 1.0)
  _boost = lerpf(_boost, boost_target, clampf(delta * 3.0, 0.0, 1.0))
  _blow = maxf(0.0, _blow - delta)
  _pop = maxf(0.0, _pop - delta)

  var frames: int = _playback.get_frames_available()
  if frames <= 0:
    return
  var fire_hz := maxf(rpm, 1.0) / 60.0 * float(cylinders) * 0.5     # motor 4 tempos
  var pipe := clampf((exhaust_mm - 35.0) / 45.0, 0.0, 1.0)        # 0 = fino, 1 = grosso
  var cutoff := clampf(0.07 + rpm / 22000.0 + pipe * 0.16, 0.04, 0.85)
  var vol := (0.16 + 0.34 * load_amount + 0.18 * pipe) if running else 0.0
  var turbo_hz := 1500.0 + rpm * 0.9
  var step := fire_hz / MIX_RATE
  var turbo_step := turbo_hz / MIX_RATE
  for i in range(frames):
    _phase += step
    if _phase >= 1.0:
      _phase -= 1.0
    var a := _phase * TAU
    var w := sin(a) + 0.55 * sin(2.0 * a + 0.7) + 0.32 * sin(3.0 * a + 1.9) + 0.18 * sin(5.0 * a + 0.3)
    w = tanh(w * (0.9 + load_amount * 1.8))
    var n := randf() * 2.0 - 1.0
    var s := w + n * (0.04 + 0.22 * load_amount * throttle)
    _lp += cutoff * (s - _lp)
    var out := _lp * vol
    if has_turbo and _boost > 0.01:
      _turbo_phase += turbo_step
      if _turbo_phase >= 1.0:
        _turbo_phase -= 1.0
      out += sin(_turbo_phase * TAU) * _boost * 0.045
    if _blow > 0.0:
      out += n * 0.16 * (_blow / 0.45)
    if _pop > 0.0:
      out += n * 0.5 * (_pop / 0.06)
    if limiter:
      _lim_phase += 18.0 / MIX_RATE
      if _lim_phase >= 1.0:
        _lim_phase -= 1.0
      if _lim_phase < 0.5:
        out *= 0.15
    out = clampf(out, -0.95, 0.95)
    _playback.push_frame(Vector2(out, out))
