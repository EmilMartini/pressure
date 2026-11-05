class_name OptionsMenu
extends PanelContainer
## Options card: one row per setting, a label and a value. Left / right (arrows, d-pad,
## shoulders) change the focused row, Enter / A / a click steps it, sliders are 10-step
## bars you can also click. B / Esc or Back closes. Used by the hub's Workshop and the
## pause menu; the owner must not poll its own MenuPad while this is visible.

const ROWS := [
    { "key": "master_volume", "label": "Master volume", "type": "slider" },
    { "key": "music_volume", "label": "Music volume", "type": "slider" },
    { "key": "sfx_volume", "label": "Sound volume", "type": "slider" },
    { "key": "fullscreen", "label": "Fullscreen", "type": "bool" },
    { "key": "vsync", "label": "VSync", "type": "bool" },
    { "key": "screen_shake", "label": "Screen shake", "type": "slider" },
    { "key": "hit_stop", "label": "Hit-stop", "type": "bool" },
    { "key": "damage_numbers", "label": "Damage numbers", "type": "bool" },
    { "key": "post_fx", "label": "Post-processing", "type": "bool" },
    { "key": "crt", "label": "CRT effect", "type": "bool" },
    { "key": "crt_intensity", "label": "CRT intensity", "type": "slider" },
    { "key": "bloom", "label": "Bloom", "type": "bool" },
    { "key": "controls_hint", "label": "Controls strip in runs", "type": "bool" },
    { "key": "pause_on_disconnect", "label": "Pause when a pad drops", "type": "bool" },
]
const STEPS := 10
const ROW_H := 40.0
const BAR_W := 230.0

var on_close: Callable
var _rows: Array[Button] = []
var _values: Array[Control] = []
var _back: Button
var _pad := MenuPad.new()
var _held_lr: Dictionary = {}


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = Vector2(720, 0)
    process_mode = Node.PROCESS_MODE_ALWAYS
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    add_child(v)
    v.add_child(UiTheme.label("OPTIONS", 40))
    v.add_child(UiTheme.label("Up / down pick     left / right change     B / Esc back", 20, UiTheme.DIM))
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(680, 440)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    v.add_child(scroll)
    var list := VBoxContainer.new()
    list.add_theme_constant_override("separation", 2)
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(list)
    for i in ROWS.size():
        var row := _make_row(i)
        list.add_child(row)
        _rows.append(row)
    _back = UiTheme.button("Back", _close)
    v.add_child(_back)
    _pad.on_cancel = _close
    _pad.on_tab = func(step: int): _step_focused(step)
    visibility_changed.connect(func():
        if visible:
            for k in ["accept", "cancel", "left", "right"]:
                _pad._was[k] = true
            _refresh()
            if not _rows.is_empty():
                _rows[0].grab_focus.call_deferred())


func _make_row(i: int) -> Button:
    var spec: Dictionary = ROWS[i]
    var b := Button.new()
    b.text = String(spec["label"])
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    b.custom_minimum_size = Vector2(660, ROW_H)
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.add_theme_font_size_override("font_size", 24)
    b.pressed.connect(func(): _step(i, 1, true))
    var val := Control.new()
    val.mouse_filter = Control.MOUSE_FILTER_STOP if spec["type"] == "slider" else Control.MOUSE_FILTER_IGNORE
    val.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
    val.offset_left = -BAR_W - 24.0
    val.offset_right = -18.0
    val.draw.connect(func(): _draw_value(val, i))
    val.gui_input.connect(func(ev: InputEvent): _on_value_input(ev, val, i))
    b.add_child(val)
    _values.append(val)
    return b


func _process(delta: float) -> void:
    if not is_visible_in_tree():
        return
    _pad.poll(get_viewport(), delta)
    # Pad stick left / right also changes the value (MenuPad only reads the d-pad there).
    var ax := 0.0
    for d in Input.get_connected_joypads():
        var a := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
        if absf(a) > absf(ax):
            ax = a
    var dir := 0
    if ax < -0.6:
        dir = -1
    elif ax > 0.6:
        dir = 1
    var was: int = _held_lr.get("dir", 0)
    var t: float = _held_lr.get("t", 0.0)
    if dir != 0 and dir != was:
        _step_focused(dir)
        t = 0.0
    elif dir != 0:
        t += delta
        if t > 0.4:
            t -= 0.12
            _step_focused(dir)
    _held_lr["dir"] = dir
    _held_lr["t"] = t


func _input(event: InputEvent) -> void:
    if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:
        return
    var k := event as InputEventKey
    match k.physical_keycode:
        KEY_LEFT, KEY_A:
            if _focused_row() >= 0:
                _step_focused(-1)
                get_viewport().set_input_as_handled()
        KEY_RIGHT, KEY_D:
            if _focused_row() >= 0:
                _step_focused(1)
                get_viewport().set_input_as_handled()
        KEY_ESCAPE:
            if not k.echo:
                get_viewport().set_input_as_handled()
                _close()


func _focused_row() -> int:
    var f := get_viewport().gui_get_focus_owner()
    for i in _rows.size():
        if _rows[i] == f:
            return i
    return -1


func _step_focused(dir: int) -> void:
    var i := _focused_row()
    if i >= 0:
        _step(i, dir, false)


## Change row `i` by one step. `wrap` (a press) cycles a slider past full back to zero.
func _step(i: int, dir: int, wrap: bool) -> void:
    var spec: Dictionary = ROWS[i]
    var key := String(spec["key"])
    if spec["type"] == "bool":
        Settings.set_value(key, not Settings.flag(key))
    else:
        var n := roundi(Settings.number(key) * STEPS) + dir
        if wrap and n > STEPS:
            n = 0
        Settings.set_value(key, float(clampi(n, 0, STEPS)) / float(STEPS))
    Sfx.play("ui_move")
    _refresh()


func _on_value_input(ev: InputEvent, val: Control, i: int) -> void:
    if not ev is InputEventMouseButton or not ev.pressed or (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
        return
    var x := (ev as InputEventMouseButton).position.x
    var n := clampi(ceili(x / (val.size.x - 50.0) * STEPS), 0, STEPS)
    Settings.set_value(String(ROWS[i]["key"]), float(n) / float(STEPS))
    _rows[i].grab_focus()
    Sfx.play("ui_move")
    _refresh()
    val.accept_event()


func _draw_value(val: Control, i: int) -> void:
    var spec: Dictionary = ROWS[i]
    var key := String(spec["key"])
    var h := val.size.y
    var font: Font = Art.FONT
    if spec["type"] == "bool":
        var on := Settings.flag(key)
        val.draw_string(font, Vector2(0, h * 0.5 + 8.0), "ON" if on else "OFF", HORIZONTAL_ALIGNMENT_RIGHT, val.size.x, 24, Color(0.55, 1.0, 0.7) if on else UiTheme.DIM)
        return
    var n := roundi(Settings.number(key) * STEPS)
    var w := val.size.x - 50.0
    var cell := w / float(STEPS)
    for s in STEPS:
        var r := Rect2(Vector2(float(s) * cell + 1.0, h * 0.5 - 8.0), Vector2(cell - 3.0, 16.0))
        val.draw_rect(r, UiTheme.FOCUS if s < n else Color(0.22, 0.19, 0.21))
    val.draw_string(font, Vector2(w, h * 0.5 + 8.0), "%d" % (n * 10), HORIZONTAL_ALIGNMENT_RIGHT, 48.0, 22, UiTheme.BONE)


func _refresh() -> void:
    for i in _values.size():
        _values[i].queue_redraw()
        var dim: bool = ROWS[i]["key"] == "crt_intensity" and not Settings.flag("crt")
        _rows[i].modulate = Color(1, 1, 1, 0.5) if dim else Color.WHITE


func _close() -> void:
    if not visible:
        return
    Sfx.play("ui_back")
    if on_close.is_valid():
        on_close.call()
