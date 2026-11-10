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
    { "key": "fps_cap", "label": "Frame cap", "type": "pick", "options": ["60", "uncapped"],
        "names": ["60 FPS", "UNCAPPED"] },
    { "key": "screen_shake", "label": "Screen shake", "type": "slider" },
    { "key": "hit_stop", "label": "Hit-stop", "type": "bool" },
    { "key": "flashes", "label": "Screen flashes", "type": "bool" },
    { "key": "fight_text", "label": "Fight text", "type": "pick", "options": ["quiet", "reactions", "everything"],
        "names": ["QUIET", "REACTIONS", "EVERYTHING"] },
    { "key": "damage_numbers", "label": "Damage numbers", "type": "bool" },
    { "key": "own_fx", "label": "Your effects", "type": "slider" },
    { "key": "post_fx", "label": "Post-processing", "type": "bool" },
    { "key": "pixel_size", "label": "Pixel size", "type": "choice", "options": [2, 3, 4] },
    { "key": "palette", "label": "Palette and dither", "type": "bool" },
    { "key": "crt", "label": "CRT effect", "type": "bool" },
    { "key": "crt_intensity", "label": "CRT intensity", "type": "slider" },
    { "key": "bloom", "label": "Bloom", "type": "bool" },
    { "key": "lighting", "label": "Lighting", "type": "bool" },
    { "key": "aim_mode", "label": "Aiming", "type": "pick", "options": ["auto", "assisted", "manual"],
        "names": ["AUTO", "ASSISTED", "MANUAL"] },
    { "key": "vent_mode", "label": "Vent", "type": "pick", "options": ["auto", "button"],
        "names": ["AUTOMATIC", "BUTTON"] },

    { "key": "manual_fire", "label": "Manual fire", "type": "pick", "options": ["hold", "toggle"],
        "names": ["HOLD", "TOGGLE"] },
    { "key": "controls_hint", "label": "Controls strip in runs", "type": "bool" },
    { "key": "pause_on_disconnect", "label": "Pause when a pad drops", "type": "bool" },
    { "key": "vibration", "label": "Controller vibration", "type": "slider" },
    { "key": "vibration_paused", "label": "Vibrate while paused", "type": "bool" },
    { "key": "telemetry", "label": "Share play data", "type": "consent" },
    { "key": "", "label": "Export play data", "type": "action" },
    { "key": "", "label": "Wipe save", "type": "wipe" },
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
var _action_note := ""   # result line of the last action row (export path)
var _wipe_armed_t := 0.0  # seconds left to confirm a wipe with a second press
var _wipe_done := false


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
    b.clip_text = true
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
    _process_wipe(delta)
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


## Wiping mid-run would leave the run writing stats into an empty save: hub only.
func _in_run() -> bool:
    var scene := get_tree().current_scene
    return scene != null and scene is Main


func _process_wipe(delta: float) -> void:
    if _wipe_armed_t > 0.0:
        var i := _focused_row()
        if i < 0 or ROWS[i]["type"] != "wipe":
            _wipe_armed_t = 0.0   # moving off the row disarms it
        else:
            _wipe_armed_t = maxf(0.0, _wipe_armed_t - delta)
        _refresh()


## Change row `i` by one step. `wrap` (a press) cycles a slider past full back to zero.
func _step(i: int, dir: int, wrap: bool) -> void:
    var spec: Dictionary = ROWS[i]
    var key := String(spec["key"])
    if spec["type"] == "wipe":
        if not wrap:
            return
        if _in_run():
            Sfx.play("deny")
            return
        if _wipe_armed_t <= 0.0:
            # First press arms it; a second press within four seconds wipes.
            _wipe_armed_t = 4.0
            _wipe_done = false
            Sfx.play("error")
        else:
            _wipe_armed_t = 0.0
            Progress.reset()
            Mastery.reset()
            _wipe_done = true
            Sfx.play("ui_back")
        _refresh()
        return
    if spec["type"] == "action":
        if not wrap:
            return
        _action_note = Telemetry.export_file()
        _rows[i].text = "%s: %s" % [spec["label"], _action_note]
    elif spec["type"] == "consent":
        Settings.set_value(key, "off" if Telemetry.consent() == "on" else "on")
    elif spec["type"] == "bool":
        Settings.set_value(key, not Settings.flag(key))
    elif spec["type"] == "pick":
        var opts: Array = spec["options"]
        var at := maxi(0, opts.find(String(Settings.get_value(key))))
        at = (at + dir + opts.size()) % opts.size() if wrap else clampi(at + dir, 0, opts.size() - 1)
        Settings.set_value(key, opts[at])
    elif spec["type"] == "choice":
        var opts: Array = spec["options"]
        var at := opts.find(roundi(Settings.number(key)))
        at = (at + dir + opts.size()) % opts.size() if wrap else clampi(at + dir, 0, opts.size() - 1)
        Settings.set_value(key, opts[at])
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
    if ROWS[i]["type"] != "slider":
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
    if spec["type"] == "wipe":
        var txt := "UNLOCKS, TROPHIES, TALENTS, EMBERS"
        var col := UiTheme.DIM
        if _in_run():
            txt = "ONLY IN THE HUB"
        elif _wipe_done:
            txt = "SAVE WIPED"
            col = Color(0.55, 1.0, 0.7)
        elif _wipe_armed_t > 0.0:
            txt = "PRESS AGAIN TO WIPE  %d" % ceili(_wipe_armed_t)
            col = Color(1.0, 0.35, 0.3)
        val.draw_string(font, Vector2(0, h * 0.5 + 8.0), txt, HORIZONTAL_ALIGNMENT_RIGHT, val.size.x, 22, col)
        return
    if spec["type"] == "action":
        if _action_note == "":
            val.draw_string(font, Vector2(0, h * 0.5 + 8.0), "SAVE", HORIZONTAL_ALIGNMENT_RIGHT, val.size.x, 24, UiTheme.BONE)
        return
    if spec["type"] == "consent":
        var shared: bool = Telemetry.consent() == "on"
        val.draw_string(font, Vector2(0, h * 0.5 + 8.0), "ON" if shared else "OFF", HORIZONTAL_ALIGNMENT_RIGHT, val.size.x, 24, Color(0.55, 1.0, 0.7) if shared else UiTheme.DIM)
        return
    if spec["type"] == "pick":
        var opts: Array = spec["options"]
        var at := maxi(0, opts.find(String(Settings.get_value(key))))
        val.draw_string(font, Vector2(0, h * 0.5 + 8.0), "<  %s  >" % String(spec["names"][at]), HORIZONTAL_ALIGNMENT_RIGHT, val.size.x, 24, UiTheme.FOCUS)
        return
    if spec["type"] == "choice":
        var cur := roundi(Settings.number(key))
        var opts: Array = spec["options"]
        var x := val.size.x
        for k in range(opts.size() - 1, -1, -1):
            var o := int(opts[k])
            var on_k := o == cur
            val.draw_string(font, Vector2(x - 40.0, h * 0.5 + 8.0), "%dx" % o, HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 24, UiTheme.FOCUS if on_k else UiTheme.DIM)
            x -= 52.0
        return
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
        var key := String(ROWS[i]["key"])
        var dim: bool = (key == "crt_intensity" and not Settings.flag("crt")) or (key == "manual_fire" and String(Settings.get_value("aim_mode")) != "manual") or ((key == "pixel_size" or key == "palette") and not Settings.flag("post_fx"))
        _rows[i].modulate = Color(1, 1, 1, 0.5) if dim else Color.WHITE


func _close() -> void:
    if not visible:
        return
    Sfx.play("ui_back")
    if on_close.is_valid():
        on_close.call()
