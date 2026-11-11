class_name MomentPrompt
extends CanvasLayer
## "This moment" (Vision gap analysis 6.1): F8, or hold the pad's Back button, marks what
## just happened. The game pauses under a small card at the top: four tags (Fun, Boring,
## Unfair, Confusing) and, from the keyboard, an optional one-line note. Picking a tag
## records a `moment` telemetry event (Telemetry.moment: room, floor, time, health, build,
## nearest enemies, recent hits) and saves a small screenshot of the frame before the card
## opened to user://moments/ (headless runs skip it). Esc, B or F8 again cancels.
##
## Keyboard: 1 to 4 pick a tag, Tab types a note (Enter goes back to the tags), the mouse
## clicks. Pad: d-pad or shoulders move, A picks, B cancels.
## Bots: `--moment-probe` opens it after the first room clear and picks Unfair with a note
## (main.gd `_moment_probe`), printing `[MOMENT]` and `[MOMENT-CHECK] PASS/FAIL`.

const TAGS := ["fun", "boring", "unfair", "confusing"]
const NAMES := ["Fun", "Boring", "Unfair", "Confusing"]
const COLORS := [Color(0.55, 0.95, 0.55), Color(0.70, 0.70, 0.75), Color(1.0, 0.45, 0.35), Color(0.95, 0.80, 0.35)]
## Hold Back this long on a pad (a tap still opens the character sheet).
const HOLD_SECS := 0.45
const SHOT_WIDTH := 480
const NOTE_MAX := 140

var main: Main
var _card: PanelContainer
var _buttons: Array[Button] = []
var _note: LineEdit
var _note_row: Control
var _hint: Label
var _saved: Label
var _saved_t := 0.0
var _image: Image = null
var _pad := MenuPad.new()
var _open := false
var _by_pad := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var closed_ms := -100000   # the pause menu ignores Esc this soon after a close
var last_event: Dictionary = {}


func _init(p_main: Main) -> void:
    main = p_main
    layer = 55   # over the HUD and the pause menu's layer (50); only opens while unpaused
    process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.theme = UiTheme.make()
    add_child(root)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.22)   # light: the moment itself stays readable underneath
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(dim)
    _card = PanelContainer.new()
    _card.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _card.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _card.position.y = 64
    root.add_child(_card)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 8)
    _card.add_child(v)
    var title := UiTheme.body("This moment was...", 18)
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(title)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(row)
    for i in TAGS.size():
        var b := UiTheme.button(NAMES[i], _choose.bind(i))
        b.custom_minimum_size = Vector2(132, 44)
        b.add_theme_font_size_override("font_size", 26)
        b.add_theme_color_override("font_color", COLORS[i])
        b.set_meta("pixel", true)
        row.add_child(b)
        _buttons.append(b)
    _note_row = HBoxContainer.new()
    v.add_child(_note_row)
    _note = LineEdit.new()
    _note.placeholder_text = "Note (optional): Tab to type, Enter when done"
    _note.max_length = NOTE_MAX
    _note.focus_mode = Control.FOCUS_CLICK   # pads skip it; Tab or a click reaches it
    _note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _note.custom_minimum_size = Vector2(0, 34)
    if Art.FONT_BODY != null:
        _note.add_theme_font_override("font", Art.FONT_BODY)
    _note.add_theme_font_size_override("font_size", 16)
    _note.text_submitted.connect(func(_t: String): _note.release_focus())
    _note_row.add_child(_note)
    _hint = UiTheme.body("", 15, UiTheme.DIM)
    _hint.autowrap_mode = TextServer.AUTOWRAP_OFF
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    v.add_child(_hint)
    # "Saved" flash after a pick, at the same spot, while play resumes.
    _saved = UiTheme.body("", 18)
    _saved.autowrap_mode = TextServer.AUTOWRAP_OFF
    _saved.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _saved.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _saved.position.y = 72
    _saved.visible = false
    add_child(_saved)
    _pad.on_cancel = cancel
    _pad.on_tab = _step_focus
    _card.visible = false
    dim.visible = false
    _card.set_meta("dim", dim)
    visible = true


func is_open() -> bool:
    return _open


## Open the card (F8 or a held Back). Only mid-run and while nothing else has the game
## paused (pause menu, level-up, gun pick, run over).
func open(by_pad: bool) -> bool:
    if _open or get_tree().paused or not Telemetry.recording() or main.game_over or main.victory:
        return false
    _by_pad = by_pad
    _image = _capture()
    _open = true
    _note.text = ""
    _note_row.visible = not by_pad
    for i in _buttons.size():
        _buttons[i].text = NAMES[i] if by_pad else "%d %s" % [i + 1, NAMES[i]]
    _hint.text = "A pick   B cancel   (game paused)" if by_pad else "1-4 or click to pick   Esc cancel   (game paused)"
    _card.visible = true
    (_card.get_meta("dim") as CanvasItem).visible = true
    _saved.visible = false
    get_tree().paused = true
    _mouse_mode = Input.mouse_mode
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    # A pad: focus the first tag, and swallow the buttons already held so nothing fires
    # on the opening frame.
    _pad = MenuPad.new()
    _pad.on_cancel = cancel
    _pad.on_tab = _step_focus
    _pad.set("_was", { "accept": _any_pad(JOY_BUTTON_A), "cancel": _any_pad(JOY_BUTTON_B) })
    if by_pad:
        _buttons[0].grab_focus()
    else:
        var f := get_viewport().gui_get_focus_owner()
        if f != null:
            f.release_focus()
    Sfx.play("ui_open")
    return true


func cancel() -> void:
    if not _open:
        return
    Sfx.play("ui_back")
    _close()


## Pick tag `i` from code (the bot probe) or a button.
func choose(i: int, note: String = "") -> void:
    if note != "":
        _note.text = note
    _choose(i)


func _choose(i: int) -> void:
    if not _open or i < 0 or i >= TAGS.size():
        return
    var note := _note.text.strip_edges().replace("\n", " ").left(NOTE_MAX)
    var shot := _save_shot()
    last_event = Telemetry.moment(main, TAGS[i], note, shot)
    Sfx.play("ui_confirm")
    _close()
    _saved.text = "Moment saved: %s" % NAMES[i]
    _saved.add_theme_color_override("font_color", COLORS[i])
    _saved.visible = true
    _saved.modulate.a = 1.0
    _saved_t = 1.4
    if main.autotest:
        print("[MOMENT] tag=%s floor=%s room=%s t=%s hp=%s/%s fighting=%s enemies=%s nearest=%s note=\"%s\" shot=%s" % [
            last_event.get("tag", "?"), last_event.get("floor", "?"), last_event.get("room", "?"), last_event.get("t", "?"),
            last_event.get("hp", "?"), last_event.get("max_hp", "?"), last_event.get("fighting", "?"), last_event.get("enemies_alive", "?"),
            JSON.stringify(last_event.get("nearest", [])), last_event.get("note", ""), last_event.get("shot", "-")])


func _close() -> void:
    _open = false
    _card.visible = false
    (_card.get_meta("dim") as CanvasItem).visible = false
    if _note.has_focus():
        _note.release_focus()
    for b in _buttons:
        if b.has_focus():
            b.release_focus()
    _image = null
    Input.mouse_mode = _mouse_mode
    closed_ms = Time.get_ticks_msec()
    get_tree().paused = false


func _process(delta: float) -> void:
    if _saved.visible:
        _saved_t -= delta
        _saved.modulate.a = clampf(_saved_t / 0.4, 0.0, 1.0)
        if _saved_t <= 0.0:
            _saved.visible = false
    if _open:
        _pad.poll(get_viewport(), delta)


func _input(event: InputEvent) -> void:
    if not _open or not event is InputEventKey or not event.pressed or event.echo:
        return
    var key := (event as InputEventKey).physical_keycode
    var typing := _note.has_focus()
    match key:
        KEY_ESCAPE, KEY_F8:
            get_viewport().set_input_as_handled()
            cancel()
        KEY_TAB:
            get_viewport().set_input_as_handled()
            if typing:
                _note.release_focus()
            else:
                _note.grab_focus()
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4:
            if typing:
                return
            get_viewport().set_input_as_handled()
            _choose((key - KEY_KP_1) if key >= KEY_KP_1 else (key - KEY_1))


func _step_focus(step: int) -> void:
    var f := get_viewport().gui_get_focus_owner()
    var i := _buttons.find(f)
    i = wrapi(i + step, 0, _buttons.size()) if i >= 0 else 0
    _buttons[i].grab_focus()
    Sfx.play("ui_move")


func _any_pad(button: JoyButton) -> bool:
    for d in Input.get_connected_joypads():
        if Input.is_joy_button_pressed(d, button):
            return true
    return false


## The last drawn frame, before the card shows, scaled down. Null when headless.
func _capture() -> Image:
    if DisplayServer.get_name() == "headless":
        return null
    var tex := get_viewport().get_texture()
    if tex == null:
        return null
    var img := tex.get_image()
    if img == null or img.is_empty():
        return null
    var h := int(round(float(img.get_height()) * float(SHOT_WIDTH) / float(maxi(1, img.get_width()))))
    img.resize(SHOT_WIDTH, maxi(1, h), Image.INTERPOLATE_BILINEAR)
    return img


## Saves the captured frame as user://moments/<run>_<t>.png (moments_<n>/ for bot
## instances). Returns the path, or "" when there was nothing to save.
func _save_shot() -> String:
    if _image == null:
        return ""
    var tag := Main._instance_tag() if Main.bot_run() else ""
    var dir := "user://moments%s" % tag
    DirAccess.make_dir_recursive_absolute(dir)
    var stamp := Time.get_datetime_string_from_system(false).replace(":", "").replace("-", "").replace("T", "_")
    var path := "%s/%s_%s.png" % [dir, Telemetry.run_id(), stamp]
    if _image.save_png(path) != OK:
        return ""
    return path
