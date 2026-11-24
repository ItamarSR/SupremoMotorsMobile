extends Control
class_name GameUI
# Interface: HUD, controles multitouch + teclado, minimapa, avisos e painel de menus.
# Nao contem regras de jogo: apenas emite sinais e exibe dados.

signal driving_input(throttle: float, brake: float, steering: float, handbrake: bool)
signal action(name: String)

var minimap: Minimap
var panel_open := false

var _touches: Dictionary = {}
var _areas: Dictionary = {}
var _buttons: Dictionary = {}
var _hud: Label
var _mission_label: Label
var _toast: Label
var _prompt: Label
var _panel: PanelContainer
var _panel_title: Label
var _panel_sub: Label
var _panel_list: VBoxContainer
var _toasts: Array = []

func _ready() -> void:
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  _hud = _make_label(Vector2(20, 12), 20)
  _mission_label = _make_label(Vector2(20, 168), 17)
  _mission_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
  _toast = _make_label(Vector2(330, 12), 18)
  _toast.size = Vector2(640, 100)
  _toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  _prompt = _make_label(Vector2(420, 400), 20)
  _prompt.size = Vector2(440, 30)
  _prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  _prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))

  minimap = Minimap.new()
  minimap.anchor_left = 1.0
  minimap.anchor_right = 1.0
  minimap.offset_left = -205
  minimap.offset_right = -15
  minimap.offset_top = 12
  minimap.offset_bottom = 202
  minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
  add_child(minimap)

  # direcao e pedais
  _create_button("left", "<", 24, -130, 115, 105, false, true)
  _create_button("right", ">", 150, -130, 115, 105, false, true)
  _create_button("brake", "FREIO / RE", -370, -130, 155, 105, true, true)
  _create_button("gas", "ACELERAR", -198, -150, 180, 125, true, true)
  _create_button("handbrake", "FREIO MAO", -370, -210, 155, 66, true, true)
  # acoes
  _create_button("interact", "INTERAGIR", -150, -330, 300, 70, false, true, true)
  _create_button("phone", "CELULAR [C]", 20, 110, 150, 46, false, false)
  _create_button("park", "ESTACIONAR [P]", 178, 110, 170, 46, false, false)
  _create_button("lock", "TRANCAR [L]", 356, 110, 140, 46, false, false)
  _create_button("engine", "MOTOR [M]", 504, 110, 130, 46, false, false)
  _create_button("lights", "FAROL [F]", 642, 110, 120, 46, false, false)
  _create_button("save", "SALVAR", 770, 110, 100, 46, false, false)
  _create_button("quality", "GRAFICOS", 878, 110, 120, 46, false, false)
  _create_button("reset", "REPOSICIONAR", 1006, 110, 150, 46, false, false)
  _buttons["interact"].visible = false
  resized.connect(_update_areas)
  _build_panel()
  _update_areas()
  Bus.notify.connect(_on_notify)

func _make_label(pos: Vector2, font_size: int) -> Label:
  var l := Label.new()
  l.position = pos
  l.add_theme_font_size_override("font_size", font_size)
  l.add_theme_color_override("font_color", Color.WHITE)
  l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
  l.add_theme_constant_override("outline_size", 6)
  l.mouse_filter = Control.MOUSE_FILTER_IGNORE
  add_child(l)
  return l

func _create_button(key: String, title: String, x: float, y: float, w: float, h: float, right: bool, bottom: bool, center: bool = false) -> void:
  var b := Button.new()
  b.text = title
  b.size = Vector2(w, h)
  b.position = Vector2(x, y)
  var ax := 0.5 if center else (1.0 if right else 0.0)
  b.anchor_left = ax
  b.anchor_right = ax
  b.anchor_top = 1.0 if bottom else 0.0
  b.anchor_bottom = 1.0 if bottom else 0.0
  b.add_theme_font_size_override("font_size", 16)
  b.focus_mode = Control.FOCUS_NONE
  b.mouse_filter = Control.MOUSE_FILTER_IGNORE
  add_child(b)
  _buttons[key] = b

func _update_areas() -> void:
  for key in _buttons:
    var b: Button = _buttons[key]
    _areas[key] = Rect2(b.position + Vector2(size.x * b.anchor_left, size.y * b.anchor_top), b.size)
  queue_redraw()

func _draw() -> void:
  for key in _areas:
    if not (_buttons[key] as Button).visible:
      continue
    var rect: Rect2 = _areas[key]
    draw_rect(rect, Color(0.04, 0.08, 0.13, 0.63), true)
    draw_rect(rect, Color(0.25, 0.7, 0.95, 0.7), false, 2.0)

# ------------------------------------------------------------------ entrada
func _input(event: InputEvent) -> void:
  if event is InputEventKey and event.pressed and not event.echo:
    if panel_open:
      if event.keycode == KEY_ESCAPE:
        close_menu()
      return
    match event.keycode:
      KEY_E: action.emit("interact")
      KEY_P: action.emit("park")
      KEY_L: action.emit("lock")
      KEY_M: action.emit("engine")
      KEY_C: action.emit("phone")
      KEY_F: action.emit("lights")
      KEY_R: action.emit("reset")
    return
  if panel_open:
    return
  if event is InputEventScreenTouch:
    if event.pressed:
      _touches[event.index] = _hit(event.position)
      _activate(_touches[event.index])
    else:
      _touches.erase(event.index)
  elif event is InputEventScreenDrag:
    _touches[event.index] = _hit(event.position)
  elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
    if event.pressed:
      _touches[-1] = _hit(event.position)
      _activate(_touches[-1])
    else:
      _touches.erase(-1)

func _hit(pos: Vector2) -> String:
  for key in _areas:
    if not (_buttons[key] as Button).visible:
      continue
    var rect: Rect2 = _areas[key]
    if rect.has_point(pos):
      return key
  return ""

func _activate(key: String) -> void:
  match key:
    "reset", "save", "quality", "phone", "park", "lock", "engine", "lights", "interact":
      action.emit(key)

func _is_held(key: String) -> bool:
  return _touches.values().has(key)

func _physics_process(_delta: float) -> void:
  if panel_open:
    driving_input.emit(0.0, 0.0, 0.0, false)
    return
  var gas := _is_held("gas") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
  var stop := _is_held("brake") or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
  var left := _is_held("left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
  var right := _is_held("right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
  var park := _is_held("handbrake") or Input.is_key_pressed(KEY_SPACE)
  driving_input.emit(float(gas), float(stop), float(left) - float(right), park)

# ------------------------------------------------------------------ exibicao
func update_hud(d: Dictionary) -> void:
  _hud.text = d.get("text", "")
  _mission_label.text = d.get("mission", "")
  var prompt: String = d.get("prompt", "")
  _prompt.text = ("[E] " + prompt) if prompt != "" else ""
  var btn: Button = _buttons["interact"]
  btn.visible = prompt != ""
  btn.text = prompt.to_upper() if prompt != "" else "INTERAGIR"
  (_buttons["lock"] as Button).text = d.get("lock_label", "TRANCAR [L]")
  queue_redraw()
  _tick_toasts()

func _on_notify(text: String, kind: String) -> void:
  var prefix := ""
  match kind:
    "fine": prefix = "[MULTA] "
    "police": prefix = "[POLICIA] "
    "warn": prefix = "[!] "
    "mission": prefix = "[MISSAO] "
  _toasts.append({"t": prefix + text, "life": 5.0})
  if _toasts.size() > 4:
    _toasts.pop_front()

func _tick_toasts() -> void:
  var delta := get_process_delta_time()
  var lines: Array = []
  for n in _toasts:
    n["life"] = float(n["life"]) - delta
  _toasts = _toasts.filter(func(n): return float(n["life"]) > 0.0)
  for n in _toasts:
    lines.append(str(n["t"]))
  _toast.text = "\n".join(lines)

# ------------------------------------------------------------------ painel de menus
func _build_panel() -> void:
  _panel = PanelContainer.new()
  _panel.visible = false
  _panel.custom_minimum_size = Vector2(780, 540)
  _panel.size = Vector2(780, 540)
  _panel.position = Vector2(250, 90)
  var sb := StyleBoxFlat.new()
  sb.bg_color = Color(0.03, 0.06, 0.12, 0.95)
  sb.border_color = Color(0.25, 0.65, 1.0)
  sb.set_border_width_all(2)
  sb.set_corner_radius_all(10)
  sb.set_content_margin_all(14)
  _panel.add_theme_stylebox_override("panel", sb)
  add_child(_panel)
  var vb := VBoxContainer.new()
  vb.add_theme_constant_override("separation", 8)
  _panel.add_child(vb)
  _panel_title = Label.new()
  _panel_title.add_theme_font_size_override("font_size", 28)
  _panel_title.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
  vb.add_child(_panel_title)
  _panel_sub = Label.new()
  _panel_sub.add_theme_font_size_override("font_size", 17)
  _panel_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  _panel_sub.custom_minimum_size = Vector2(740, 0)
  vb.add_child(_panel_sub)
  var scroll := ScrollContainer.new()
  scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  scroll.custom_minimum_size = Vector2(740, 330)
  vb.add_child(scroll)
  _panel_list = VBoxContainer.new()
  _panel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  _panel_list.add_theme_constant_override("separation", 6)
  scroll.add_child(_panel_list)
  var close := Button.new()
  close.text = "FECHAR [ESC]"
  close.custom_minimum_size = Vector2(0, 50)
  close.add_theme_font_size_override("font_size", 20)
  close.pressed.connect(close_menu)
  vb.add_child(close)

## entries: [{t: texto, cb: Callable (opcional), off: bool, h: bool (cabecalho)}]
func show_menu(title: String, subtitle: String, entries: Array) -> void:
  panel_open = true
  _touches.clear()
  _panel.visible = true
  _panel_title.text = title
  _panel_sub.text = subtitle
  for c in _panel_list.get_children():
    c.queue_free()
  for e in entries:
    if e.get("h", false):
      var l := Label.new()
      l.text = str(e["t"])
      l.add_theme_font_size_override("font_size", 19)
      l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
      l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      _panel_list.add_child(l)
    else:
      var b := Button.new()
      b.text = str(e["t"])
      b.custom_minimum_size = Vector2(0, 50)
      b.add_theme_font_size_override("font_size", 18)
      b.alignment = HORIZONTAL_ALIGNMENT_LEFT
      b.disabled = bool(e.get("off", false)) or not e.has("cb")
      if e.has("cb"):
        b.pressed.connect(e["cb"])
      _panel_list.add_child(b)

func close_menu() -> void:
  panel_open = false
  _panel.visible = false
  _touches.clear()
