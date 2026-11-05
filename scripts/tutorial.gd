extends Main
## First-time tutorial: one entrance room, played the first time the game starts (the
## hub sends you here while Settings "tutorial_done" is false). A list of steps, each with
## a big instruction and the device-correct prompt; each waits for its condition, chimes,
## and moves on. Esc / Start skips. Walking through the final door marks it done and
## goes to the hub. Reuses the run machinery (Room, Pedestal, Player, Hud, Fx) by
## extending Main with its own _ready and _process; nothing here touches the run save
## beyond what picking up gear normally counts.

const CIRCLE := Vector2(-320, 150)
const CIRCLE_R := 46.0
const DOOR_DIR := Vector2i.UP
const NEXT_DELAY := 0.8
const DUMMY_HP := 100000.0
const REACTION_SHOW := 2.2

## text: the instruction. sub: the line under it. action: the prompt shown ("move",
## "interact", "vent", "sheet", "close", "active", or "").
const STEPS := [
    { "id": "move", "text": "Walk to the marked circle", "sub": "", "action": "move" },
    { "id": "gun", "text": "Take the Water Pistol", "sub": "Stand at the plinth and press the button.", "action": "interact" },
    { "id": "aim", "text": "Your guns aim and fire on their own", "sub": "Stay in range of the dummies. Water makes them Wet.", "action": "move" },
    { "id": "react", "text": "Take the Flare Pistol", "sub": "Water + fire = Steam. Every pair of elements reacts.", "action": "interact" },
    { "id": "vent", "text": "Vent your pressure", "sub": "Firing heats or chills the gauge under your health. Venting blasts it out as a nova.", "action": "vent" },
    { "id": "gear", "text": "Equip the Rusted Helm", "sub": "Gear fills slots: head, chest, hands, feet, two rings, two trinkets, an active.", "action": "interact" },
    { "id": "active", "text": "Take the Smelling Salts", "sub": "An active item does something when you use it.", "action": "interact" },
    { "id": "door", "text": "The door is open: walk through to the hub", "sub": "Every run is five floors, each ends in a boss.\nDying keeps your unlocks and Embers. The hub is where you spend them.", "action": "move" },
]

var step := -1
var _sub := 0
var _step_t := 0.0
var _wait := -1.0
var _dummies: Array = []
var _reacted := false
var _vented := false
var _salts_charges := -1
var _reaction_text := ""
var _reaction_col := Color.WHITE
var _reaction_time := 0.0
var _finishing := false
var _start_down: Dictionary = {}
var _back_down: Dictionary = {}
var _ui: Control
var _sheet_ui: Control
var _sheet_tut: CharacterSheet
var _sheet_pad := MenuPad.new()
var _sheet_opened_frame := -1


func _ready() -> void:
    randomize()
    get_tree().paused = false
    Engine.time_scale = 1.0
    fx = Fx.new()
    fx.main = self
    add_child(fx)
    spectacle_override = 0.6
    camera = PixelCamera.new()
    camera.follow_speed = 7.0
    camera.zoom = Vector2(1.3, 1.3)
    add_child(camera)
    camera.make_current()
    RenderingServer.set_default_clear_color(Art.CLEAR)
    add_child(PostFx.new())
    var layer := CanvasLayer.new()
    layer.layer = 3   # over the PostFx (1) and the Crisp world-text layer (2)
    add_child(layer)
    hud = Hud.new()
    hud.main = self
    layer.add_child(hud)
    _build_ui()

    Progress.chosen_class = "vagrant"
    Items.new_run()
    var pads := Input.get_connected_joypads()
    _spawn_player(0 if pads.has(0) else -1, true)
    Input.joy_connection_changed.connect(_on_joy_connection_changed)
    Elements.reaction_fired.connect(_on_reaction)

    floor_number = 1
    var data := RoomData.new()
    data.pos = Vector2i.ZERO
    data.type = RoomData.Type.START
    data.doors = { DOOR_DIR: { "to": DOOR_DIR, "obstacle": "" } }
    # A spent placeholder keeps the stock non-empty, so the room does not offer its own
    # two-gun pick to the unarmed player.
    var spent := FloorGen.offer("stairs", "", 0)
    spent["taken"] = true
    data.stock = [spent]
    var beyond := RoomData.new()
    beyond.pos = DOOR_DIR
    beyond.type = RoomData.Type.ARENA
    rooms = { Vector2i.ZERO: data, DOOR_DIR: beyond }
    enter_room(Vector2i.ZERO, Vector2i.ZERO)
    if current.doors.has(DOOR_DIR):
        current.doors[DOOR_DIR].set_state(Door.State.LOCKED)
    for p in players:
        p.global_position = Vector2(0, 160)
    Settings.apply()
    Music.duck(false)
    Music.play("hub")
    if Music.current != "hub":
        Music.play("menu")
    _enter_step(0)


# --- Steps -------------------------------------------------------------------


func _enter_step(i: int) -> void:
    step = i
    Telemetry.tutorial_step(i, String(STEPS[i]["id"]))
    _sub = 0
    _step_t = 0.0
    _wait = -1.0
    match String(STEPS[i]["id"]):
        "gun":
            _add_offer(FloorGen.offer("gun", "water_pistol", 0), Vector2(-320, -60))
        "aim":
            for at in [Vector2(250, -130), Vector2(360, 0), Vector2(250, 130)]:
                _spawn_dummy(at)
        "react":
            _reacted = false
            _add_offer(FloorGen.offer("gun", "flare_pistol", 0), Vector2(-60, -190))
        "vent":
            _vented = false
        "gear":
            _add_offer(Items.offer("rusted_helm", 0), Vector2(-320, -60))
        "active":
            _add_offer(Items.offer("smelling_salts", 0), Vector2(-60, -190))
        "door":
            if current.doors.has(DOOR_DIR):
                current.doors[DOOR_DIR].set_state(Door.State.OPEN)
            _room_entered_ms = Time.get_ticks_msec()


## Put an offer on its own plinth at a fixed spot in the room.
func _add_offer(o: Dictionary, at: Vector2) -> void:
    o["pos"] = at
    current.data.stock.append(o)
    current._build_pedestals()


## A target that stands still, does not hurt, and does not die.
func _spawn_dummy(at: Vector2) -> void:
    var e := Enemy.new()
    e.configure("grunt", 1)
    e.speed = 0.0
    e.contact_damage = 0.0
    e.scrap_value = 0
    e.position = at
    current.enemies.add_child(e)
    e.max_hp = DUMMY_HP
    e.hp = DUMMY_HP
    _dummies.append(e)


## Whether the current step's condition holds (sub-steps advance in place).
func _check_step() -> bool:
    var p := players[0]
    match String(STEPS[step]["id"]):
        "move":
            return p.global_position.distance_to(CIRCLE) <= CIRCLE_R
        "gun":
            return not p.guns.is_empty()
        "aim":
            if _step_t < 4.0:
                return false
            for e in _dummies:
                if is_instance_valid(e) and e.hp < e.max_hp:
                    return true
            return _step_t > 10.0
        "react":
            if _sub == 0 and p.guns.size() >= 2:
                _sub = 1
                _reacted = false
            return _sub == 1 and (_reacted or _step_t > 30.0)
        "vent":
            # Keep the gauge charged until the vent happens, so there is something to vent.
            for pl in players:
                if absf(pl.pressure) < Player.VENT_MIN + 10.0:
                    pl.pressure = 60.0
            return _vented
        "gear":
            if _sub == 0 and p.equipment.values().has("rusted_helm"):
                _sub = 1
                Sfx.play("ui_confirm")
            elif _sub == 1 and _sheet_open():
                _sub = 2
            return _sub == 2 and not _sheet_open()
        "active":
            if _sub == 0 and p.equipment.get("active", "") == "smelling_salts":
                _sub = 1
                if p.active_charges <= 0:
                    p.active_charges = 1
                _salts_charges = p.active_charges
                Sfx.play("ui_confirm")
            return _sub == 1 and p.active_charges < _salts_charges
    return false


## The instruction for the current step and sub-step: [text, sub, action].
func _instruction() -> Array:
    var s: Dictionary = STEPS[step]
    var text := String(s["text"])
    var sub := String(s["sub"])
    var action := String(s["action"])
    match String(s["id"]):
        "react":
            if _sub == 1:
                text = "Wet targets meet fire: watch for the reaction"
                action = ""
        "gear":
            if _sub == 1:
                text = "Open your character sheet"
                sub = "It shows your guns, gear and stats."
                action = "sheet"
            elif _sub == 2:
                text = "Now close it again"
                sub = ""
                action = "close"
        "active":
            if _sub == 1:
                text = "Use your active item"
                sub = "Smelling Salts heal you. Active items recharge as you clear rooms."
                action = "active"
    return [text, sub, action]


func _finish(skipped: bool = false) -> void:
    if _finishing:
        return
    _finishing = true
    Telemetry.tutorial_end(step, skipped)
    Settings.set_value("tutorial_done", true)
    Engine.time_scale = 1.0
    get_tree().paused = false
    Sfx.play("ui_confirm")
    get_tree().change_scene_to_file.call_deferred("res://scenes/hub.tscn")


# --- Overrides of the run ----------------------------------------------------


func _on_door_entered(dir: Vector2i) -> void:
    if dir == DOOR_DIR and step >= 0 and String(STEPS[step]["id"]) == "door":
        _finish()


## Nobody dies in the tutorial: a downed player stands straight back up.
func _on_player_died(p: Player) -> void:
    p.alive = true
    p.hp = p.max_hp
    p.add_to_group("players")


func next_floor() -> void:
    pass


func difficulty() -> int:
    return 1


func _on_reaction(reaction_name: String, _pos: Vector2, col: Color) -> void:
    match reaction_name:
        "Fire Nova", "Frost Nova":
            _vented = true
            return
        "ELITE", "Shield broken!", "Shield restored!", "Shield cracked", "Path opened!":
            return
    if step >= 0 and String(STEPS[step]["id"]) == "react" and _sub == 1:
        _reacted = true
    _reaction_text = reaction_name
    _reaction_col = col
    _reaction_time = REACTION_SHOW


func _process(delta: float) -> void:
    var real_delta := delta / maxf(Engine.time_scale, 0.001)
    if _hitstop_left > 0.0:
        _hitstop_left -= real_delta
        if _hitstop_left <= 0.0:
            Engine.time_scale = 1.0
    if _flash_rect != null and _flash_rect.color.a > 0.0:
        _flash_rect.color.a = maxf(0.0, _flash_rect.color.a - _flash_fade * real_delta)
    _handle_joins()
    camera.target = _party_center()
    camera.shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
    _shake = move_toward(_shake, 0.0, 28.0 * delta)
    _message_time = maxf(0.0, _message_time - delta)
    if _message_time <= 0.0:
        message = ""
    _reaction_time = maxf(0.0, _reaction_time - delta)
    for p in players:
        if p.hp < p.max_hp * 0.5:
            p.heal(p.max_hp * 0.5 * delta)
    _ui.queue_redraw()
    queue_redraw()
    if _finishing or players.is_empty():
        return
    if _sheet_open():
        _sheet_pad.poll(get_viewport(), delta)
    if _skip_pressed():
        _finish(true)
        return
    _poll_sheet_button()
    if step < 0:
        return
    _step_t += delta
    if _wait >= 0.0:
        _wait -= delta
        if _wait < 0.0 and step + 1 < STEPS.size():
            _enter_step(step + 1)
        return
    if _check_step():
        Sfx.play("unlock")
        if step + 1 < STEPS.size():
            _wait = NEXT_DELAY


func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if (event as InputEventKey).physical_keycode == KEY_C and not _finishing:
        if _sheet_open():
            _close_sheet()
        else:
            _open_sheet()
        get_viewport().set_input_as_handled()


## Esc or Start on a joined pad skips, unless the character sheet is up (then it closes it).
func _skip_pressed() -> bool:
    var hit := false
    for d in Input.get_connected_joypads():
        var down := Input.is_joy_button_pressed(d, JOY_BUTTON_START)
        if down and not _start_down.get(d, false) and is_device_joined(d):
            hit = true
        _start_down[d] = down
    if Input.is_action_just_pressed("ui_cancel"):
        hit = true
    if hit and _sheet_open():
        if Engine.get_process_frames() != _sheet_opened_frame:
            _close_sheet()
        return false
    return hit


func _poll_sheet_button() -> void:
    for d in Input.get_connected_joypads():
        var down := Input.is_joy_button_pressed(d, JOY_BUTTON_BACK)
        if down and not _back_down.get(d, false) and is_device_joined(d):
            if _sheet_open():
                _close_sheet()
            else:
                _open_sheet()
        _back_down[d] = down


# --- Character sheet ---------------------------------------------------------


func _sheet_open() -> bool:
    return _sheet_ui != null and _sheet_ui.visible


func _open_sheet() -> void:
    if _sheet_open() or players.is_empty():
        return
    _sheet_ui.visible = true
    _sheet_tut.visible = true
    _sheet_tut.show_player(players[0])
    _sheet_opened_frame = Engine.get_process_frames()
    for k in ["accept", "cancel", "left", "right"]:
        _sheet_pad._was[k] = true
    for p in players:
        p.set_physics_process(false)
    Sfx.play("ui_open")
    Music.duck(true)


func _close_sheet() -> void:
    if not _sheet_open():
        return
    _sheet_ui.visible = false
    for p in players:
        p.set_physics_process(true)
    var f := get_viewport().gui_get_focus_owner()
    if f != null:
        f.release_focus()
    Sfx.play("ui_back")
    Music.duck(false)


# --- Drawing -----------------------------------------------------------------


func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 3
    add_child(layer)
    _ui = Control.new()
    _ui.set_anchors_preset(Control.PRESET_FULL_RECT)
    _ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ui.draw.connect(_draw_ui)
    layer.add_child(_ui)
    var sheet_layer := CanvasLayer.new()
    sheet_layer.layer = 50
    add_child(sheet_layer)
    _sheet_ui = Control.new()
    _sheet_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
    _sheet_ui.theme = UiTheme.make()
    _sheet_ui.visible = false
    sheet_layer.add_child(_sheet_ui)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.6)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _sheet_ui.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    _sheet_ui.add_child(center)
    _sheet_tut = CharacterSheet.new(_close_sheet)
    center.add_child(_sheet_tut)
    MenuPad.strip_joypad_from_ui_actions()
    _sheet_pad.on_cancel = _close_sheet


## The prompt label for an action on player 1's current device.
func _prompt_label(action: String, kind: String) -> String:
    match action:
        "move":
            return "LS" if kind == "pad" else "WASD"
        "close":
            return "B" if kind == "pad" else "Esc"
    return players[0].input.prompt(action)


func _draw_ui() -> void:
    if step < 0 or players.is_empty():
        return
    var vp := _ui.get_viewport_rect().size
    var font: Font = Art.FONT
    var ins := _instruction()
    var text := String(ins[0])
    var sub := String(ins[1])
    var action := String(ins[2])
    var kind := players[0].input.last_kind
    var sub_lines: PackedStringArray = sub.split("\n") if sub != "" else PackedStringArray()
    var box_h := 64.0 + 26.0 * float(sub_lines.size())
    var box := Rect2(Vector2(vp.x / 2.0 - 470.0, 64.0), Vector2(940.0, box_h))
    _ui.draw_rect(box, Color(0.04, 0.035, 0.05, 0.86))
    _ui.draw_rect(box, Color(0.35, 0.3, 0.3), false, 2.0)
    var done := _wait >= 0.0
    var col := Color(0.55, 1.0, 0.7) if done else UiTheme.BONE
    var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
    var px := 0.0
    if action != "" and not done:
        var label := _prompt_label(action, kind)
        px = maxf(28.0, 14.0 * float(label.length()) + 14.0) + 14.0
        Prompts.draw(_ui, Vector2(vp.x / 2.0 - (tw + px) / 2.0 + px / 2.0 - 7.0, box.position.y + 30.0), label, kind, 28.0)
    var tx := vp.x / 2.0 - (tw + px) / 2.0 + px
    _ui.draw_string(font, Vector2(tx, box.position.y + 40.0), text + ("   done" if done else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
    for i in sub_lines.size():
        _ui.draw_string(font, Vector2(box.position.x, box.position.y + 70.0 + 26.0 * float(i)), sub_lines[i], HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 22, UiTheme.DIM.lightened(0.25))
    _ui.draw_string(font, Vector2(box.position.x, box.end.y + 24.0), "step %d / %d      Esc / Start  skip tutorial" % [step + 1, STEPS.size()], HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 20, UiTheme.DIM)
    if _reaction_time > 0.0:
        var a := clampf(_reaction_time / 0.5, 0.0, 1.0)
        var pop := 1.0 + 0.3 * clampf((_reaction_time - (REACTION_SHOW - 0.15)) / 0.15, 0.0, 1.0)
        _ui.draw_string(font, Vector2(0, box.end.y + 76.0), _reaction_text.to_upper() + "!", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(40.0 * pop), Color(_reaction_col.lightened(0.3), a))


func _draw() -> void:
    # The marked circle for the first step, drawn on the room floor.
    if step != 0:
        return
    var t := Time.get_ticks_msec() / 1000.0
    var c := Color(0.55, 1.0, 1.0)
    draw_circle(CIRCLE, CIRCLE_R, Color(c, 0.08))
    draw_arc(CIRCLE, CIRCLE_R, 0.0, TAU, 48, Color(c, 0.5 + 0.2 * sin(t * 4.0)), 3.0)
    draw_arc(CIRCLE, CIRCLE_R - 12.0, t, t + PI, 24, Color(c, 0.35), 2.0)
