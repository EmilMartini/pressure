class_name Hub
extends Node2D
## The hub (Enter the Gungeon's Breach): one dark room the player walks around between
## runs. Stations are plinths with a prompt: the Gate starts a run (class picker, then
## main.tscn), the Armory opens the Journal, the Shrine the talent board, the Mirror the
## names, the Workshop the options, the Ledger the run history, and the Trophy Wall along
## the top shows every achievement plus the next three goals. Esc / Start opens a small
## menu. Late pads join on Start like in a run.
##
## `-- --menu-shot` saves hub, journal, mastery, names, classes and options captures.

const INNER := Vector2(1100, 600)
const WALL := 60.0
const RANGE := 64.0
const HINT_SECS := 7.0
const LIT := Color(1.0, 0.82, 0.35)

const STATIONS := [
    { "id": "gate", "name": "THE GATE", "sub": "start a run", "pos": Vector2(0, 236), "tile": Vector2i(4, 10), "tint": Color(0.55, 1.0, 1.0), "verb": "descend", "style": "gate" },
    { "id": "armory", "name": "ARMORY", "sub": "guns and gear", "pos": Vector2(-420, -100), "tile": Vector2i(42, 9), "icon": "item/weapon/ranged/crossbow_2.png", "tint": Color(1.0, 0.6, 0.3), "verb": "browse", "style": "plinth" },
    { "id": "shrine", "name": "SHRINE", "sub": "talents", "pos": Vector2(-420, 150), "tile": Vector2i(28, 12), "icon": "gui/invocations/kiku_necronomicon.png", "tint": Color(0.8, 0.5, 1.0), "verb": "kneel", "style": "plinth" },
    { "id": "mirror", "name": "MIRROR", "sub": "names", "pos": Vector2(420, -100), "tile": Vector2i(31, 0), "icon": "item/misc/mirror.png", "tint": Color(0.6, 0.85, 1.0), "verb": "look", "style": "plinth" },
    { "id": "workshop", "name": "WORKSHOP", "sub": "options", "pos": Vector2(420, 150), "tile": Vector2i(41, 5), "icon": "gui/spells/earth/maxwells_silver_hammer.png", "tint": Color(0.85, 0.8, 0.7), "verb": "tinker", "style": "plinth" },
    { "id": "ledger", "name": "LEDGER", "sub": "run history", "pos": Vector2(-230, 210), "tile": Vector2i(44, 6), "icon": "item/book/parchment_new.png", "tint": Color(0.95, 0.8, 0.5), "verb": "read", "style": "plinth" },
    { "id": "trophies", "name": "", "sub": "", "pos": Vector2(0, -80), "tile": Vector2i(9, 11), "tint": LIT, "verb": "all achievements", "style": "wall" },
]

const EXPLAINER := [
    "A run is five floors. Each floor ends in a boss.",
    "Dying keeps your achievements, unlocks and Embers.",
    "Runs pay Embers for rooms, elites and new reactions; the Shrine trades them for swappable talents.",
    "Classes only change how a run starts.",
]

var players: Array[Player] = []
var camera: Camera2D
var _time := 0.0
var _highlight: Dictionary = {}       # station id -> [prompt key, prompt kind] when someone is near
var _joined: Dictionary = {}          # pad device -> true
var _start_was: Dictionary = {}
var _pad := MenuPad.new()
var _cooldown := 0.0
var _closed_frame := -1
var _shot := false

var _ui: Control
var _dim: ColorRect
var _hint: Label
var _overlay: Control = null
var _journal: Journal
var _journal_center: CenterContainer
var _mastery: MasteryScreen
var _mastery_center: CenterContainer
var _names_center: CenterContainer
var _name_edits: Array = []
var _options: OptionsMenu
var _options_center: CenterContainer
var _ledger_center: CenterContainer
var _ledger_body: VBoxContainer
var _ledger_back: Button
var _explainer_center: CenterContainer
var _explainer_ok: Button
var _esc_center: CenterContainer
var _esc_first: Button
var _consent_center: CenterContainer
var _consent_allow: Button
var _class_select: ClassSelect = null
var _cv: CanvasItem = null     # where _text and prompts draw (the Crisp proxy)
var ambience: Ambience = null


func _ready() -> void:
    randomize()
    var args := OS.get_cmdline_user_args()
    # Exported release builds cannot pick a scene on the command line, so the hub (the
    # start scene) hands bot and capture runs straight to the run scene.
    for flag in ["--autotest", "--start-shot", "--obstacle-test", "--layouts-shot"]:
        if args.has(flag):
            get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
            return
    _shot = args.has("--menu-shot")
    var theme_shot := args.has("--themes-shot")
    if _shot or theme_shot:
        Progress.save_path = "user://save_autotest.json"
        Progress.load_save()
    elif not Settings.flag("tutorial_done"):
        get_tree().change_scene_to_file.call_deferred("res://scenes/tutorial.tscn")
        return
    get_tree().paused = false
    Engine.time_scale = 1.0
    RenderingServer.set_default_clear_color(Art.CLEAR)
    camera = Camera2D.new()
    camera.zoom = Vector2.ONE
    add_child(camera)
    camera.make_current()
    add_child(PostFx.new())
    _build_room()
    Crisp.attach(self, _draw_texts)
    MenuPad.strip_joypad_from_ui_actions()
    _build_ui()
    var pads := Input.get_connected_joypads()
    _spawn_player(0 if pads.has(0) else -1, true)
    Input.joy_connection_changed.connect(_on_joy_connection_changed)
    Settings.apply()
    Music.duck(false)
    Music.play("hub")
    if Music.current != "hub":
        Music.play("menu")
    if theme_shot:
        _theme_shot()
    elif _shot:
        _menu_shot()
    elif not Settings.flag("seen_explainer"):
        _open(_explainer_center, _explainer_ok)
    elif Telemetry.consent() == "ask":
        _open(_consent_center, _consent_allow)


# --- Room --------------------------------------------------------------------


## The sanctum (Themes "sanctum"): ornate mosaic floor, carved relief walls, torches on
## the top wall and warm dust (Ambience).
func _build_room() -> void:
    var half := INNER / 2.0
    Themes.current = "sanctum"
    var floor_fill := Themes.floor_fill(Rect2(-half, INNER), camera.zoom.x, 4242, Color.WHITE, "sanctum")
    floor_fill.z_index = -2
    add_child(floor_fill)
    var body := StaticBody2D.new()
    body.collision_layer = Player.LAYER_WALLS
    body.collision_mask = 0
    add_child(body)
    _wall(body, Vector2(0, -half.y - WALL / 2.0), Vector2(INNER.x + 2.0 * WALL, WALL))
    _wall(body, Vector2(0, half.y + WALL / 2.0), Vector2(INNER.x + 2.0 * WALL, WALL))
    _wall(body, Vector2(-half.x - WALL / 2.0, 0), Vector2(WALL, INNER.y))
    _wall(body, Vector2(half.x + WALL / 2.0, 0), Vector2(WALL, INNER.y))
    # Plinth bodies, so players walk around stations instead of through them.
    for s in STATIONS:
        if s["style"] != "plinth":
            continue
        var shape := CollisionShape2D.new()
        var r := RectangleShape2D.new()
        r.size = Vector2(36, 18)
        shape.shape = r
        shape.position = Vector2(s["pos"]) + Vector2(0, 4)
        body.add_child(shape)
    ambience = Ambience.new(null, "sanctum", Rect2(-half, INNER))
    var tx := Themes.texel(camera.zoom.x)
    for x in [-480.0, -180.0, 180.0, 480.0]:
        ambience.add_light(Vector2(x, -half.y - 30.0), "torch")
    # Gold statues and an altar in the top wall between the torches.
    var decor: Array = Themes.def("sanctum")["decor"]
    var at := 0
    for x in [-330.0, 330.0]:
        var spr := Sprite2D.new()
        spr.texture = Themes.tex(String(decor[at % decor.size()]))
        spr.scale = Vector2(tx, tx)
        spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        spr.position = (Vector2(x, -half.y - 32.0) / tx).round() * tx
        spr.modulate = Themes.def("sanctum")["decor_tint"]
        spr.z_index = -1
        add_child(spr)
        at += 2
    add_child(ambience)


func _wall(body: StaticBody2D, center: Vector2, wall_size: Vector2) -> void:
    var shape := CollisionShape2D.new()
    var r := RectangleShape2D.new()
    r.size = wall_size
    shape.shape = r
    shape.position = center
    body.add_child(shape)
    var bricks := Themes.wall_fill(Rect2(center - wall_size / 2.0, wall_size), camera.zoom.x, Color.WHITE, "sanctum")
    bricks.z_index = -1
    add_child(bricks)


# --- Players -----------------------------------------------------------------


func _spawn_player(device: int, keyboard: bool) -> Player:
    var p := Player.new(players.size(), PlayerInput.new(device, keyboard))
    p.position = Vector2(-40.0 + 40.0 * float(players.size()), 40.0)
    add_child(p)
    players.append(p)
    if device >= 0:
        _joined[device] = true
    return p


func _on_joy_connection_changed(device: int, connected: bool) -> void:
    if device == 0 and connected and not players.is_empty() and players[0].input.device < 0:
        players[0].input.device = 0
        _joined[0] = true


func _handle_pads() -> bool:
    var start := false
    for d in Input.get_connected_joypads():
        var down := Input.is_joy_button_pressed(d, JOY_BUTTON_START)
        var edge: bool = down and not _start_was.get(d, false)
        _start_was[d] = down
        if not edge:
            continue
        if _joined.has(d):
            start = true
        elif players.size() < Main.MAX_PLAYERS and _overlay == null:
            var p := _spawn_player(d, false)
            p.say("Joined!")
            Sfx.play("ui_confirm")
    return start


# --- Frame -------------------------------------------------------------------


func _process(delta: float) -> void:
    _time += delta
    _cooldown = maxf(0.0, _cooldown - delta)
    queue_redraw()
    if _hint != null:
        _hint.modulate.a = clampf((HINT_SECS - _time) / 1.5, 0.0, 1.0) if _overlay == null else 0.0
    var start := _handle_pads()
    var cancel := Input.is_action_just_pressed("ui_cancel") and Engine.get_process_frames() != _closed_frame
    if _class_select != null:
        return   # the class picker polls pads and handles Esc itself
    if _overlay != null:
        if _overlay != _options_center:
            _pad.poll(get_viewport(), delta)
        if _overlay == _esc_center and start:
            _close_overlay()
        elif cancel and _overlay != _options_center:
            _close_overlay()
        return
    if (start or cancel) and _cooldown <= 0.0:
        _open(_esc_center, _esc_first)
        return
    _update_highlights()
    for p in players:
        if not p.input.take_pressed("interact") or _cooldown > 0.0:
            continue
        var best := ""
        var best_d := INF
        for s in STATIONS:
            var d := p.global_position.distance_to(Vector2(s["pos"]))
            if d <= _range_of(s) and d < best_d:
                best_d = d
                best = String(s["id"])
        if best != "":
            _use_station(best)
            return


func _range_of(s: Dictionary) -> float:
    match String(s["style"]):
        "wall":
            return 110.0
        "gate":
            return 80.0
    return RANGE


func _update_highlights() -> void:
    _highlight.clear()
    for s in STATIONS:
        var best: Player = null
        var best_d := INF
        for p in players:
            var d := p.global_position.distance_to(Vector2(s["pos"]))
            if d < best_d:
                best_d = d
                best = p
        if best != null and best_d <= _range_of(s):
            _highlight[s["id"]] = [best.input.prompt("interact"), best.input.last_kind]


func _use_station(id: String) -> void:
    Sfx.play("ui_open")
    Telemetry.hub_event("station", { "id": id, "players": _players_count() })
    match id:
        "gate":
            _show_class_select()
        "armory":
            _open(_journal_center, null)
            _journal.set_tab(1)
        "trophies":
            _open(_journal_center, null)
            _journal.set_tab(0)
        "shrine":
            _open(_mastery_center, null)
            _mastery.set_tab(_mastery.tab)
        "mirror":
            _open(_names_center, _name_edits[0])
        "workshop":
            _open(_options_center, null)
        "ledger":
            _fill_ledger()
            _open(_ledger_center, _ledger_back)


# --- Overlays ----------------------------------------------------------------


func _open(c: Control, focus: Control) -> void:
    if _overlay != null and _overlay != c:
        _overlay.visible = false
    _overlay = c
    _dim.visible = true
    c.visible = true
    # A button still held from opening (A on the plinth) must be released first.
    for k in ["accept", "cancel", "left", "right"]:
        _pad._was[k] = true
    for p in players:
        p.set_physics_process(false)
    if focus != null:
        focus.grab_focus.call_deferred()


func _close_overlay() -> void:
    if _overlay == null:
        return
    var after_explainer := _overlay == _explainer_center
    if after_explainer:
        Settings.set_value("seen_explainer", true)
    _overlay.visible = false
    _overlay = null
    _dim.visible = false
    _closed_frame = Engine.get_process_frames()
    _cooldown = 0.25
    for p in players:
        p.set_physics_process(true)
    var f := get_viewport().gui_get_focus_owner()
    if f != null:
        f.release_focus()
    Sfx.play("ui_back")
    if after_explainer and Telemetry.consent() == "ask" and not _shot:
        _open(_consent_center, _consent_allow)


func _show_class_select() -> void:
    if _class_select != null:
        return
    _dim.visible = false
    for p in players:
        p.set_physics_process(false)
    _class_select = ClassSelect.new(_on_class_picked, _close_class_select)
    _ui.add_child(_class_select)


func _close_class_select() -> void:
    if _class_select != null:
        _class_select.queue_free()
        _class_select = null
    _closed_frame = Engine.get_process_frames()
    _cooldown = 0.25
    for p in players:
        p.set_physics_process(true)


func _on_class_picked(id: String) -> void:
    Progress.chosen_class = id
    get_tree().change_scene_to_file("res://scenes/main.tscn")


func _center() -> CenterContainer:
    var c := CenterContainer.new()
    c.set_anchors_preset(Control.PRESET_FULL_RECT)
    c.visible = false
    _ui.add_child(c)
    return c


func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 10
    add_child(layer)
    _ui = Control.new()
    _ui.set_anchors_preset(Control.PRESET_FULL_RECT)
    _ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ui.theme = UiTheme.make()
    layer.add_child(_ui)
    _dim = ColorRect.new()
    _dim.color = Color(0, 0, 0, 0.6)
    _dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _dim.visible = false
    _ui.add_child(_dim)
    _hint = UiTheme.label("Walk to a station   WASD / left stick      use it   E / A      menu   Esc / Start", 22, UiTheme.BONE)
    _hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _hint.offset_left = -500
    _hint.offset_right = 500
    _hint.offset_top = 300   # under the trophy wall text, above the centre marker
    _ui.add_child(_hint)

    _pad.on_cancel = func():
        if _overlay == _esc_center or _overlay == _explainer_center or _overlay == _journal_center \
                or _overlay == _mastery_center or _overlay == _names_center or _overlay == _ledger_center:
            _close_overlay()
    _pad.on_tab = func(step: int):
        if _overlay == _journal_center:
            _journal.set_tab(_journal.tab + step)
        elif _overlay == _mastery_center:
            _mastery.set_tab(_mastery.tab + step)

    _journal_center = _center()
    _journal = Journal.new(_close_overlay)
    _journal_center.add_child(_journal)
    _mastery_center = _center()
    _mastery = MasteryScreen.new(_close_overlay)
    _mastery_center.add_child(_mastery)
    _options_center = _center()
    _options = OptionsMenu.new(_close_overlay)
    _options_center.add_child(_options)
    _build_names()
    _build_ledger()
    _build_explainer()
    _build_consent()
    _build_esc_menu()


func _build_names() -> void:
    _names_center = _center()
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(560, 0)
    _names_center.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 10)
    panel.add_child(col)
    col.add_child(UiTheme.label("THE MIRROR", 40))
    col.add_child(UiTheme.label("Type a name for each player; keyboard only", 20, UiTheme.DIM))
    for i in 4:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        col.add_child(row)
        var tag := UiTheme.label("P%d" % (i + 1), 24, Player.PLAYER_COLORS[i % Player.PLAYER_COLORS.size()])
        tag.custom_minimum_size = Vector2(60, 0)
        row.add_child(tag)
        var edit := LineEdit.new()
        edit.placeholder_text = "Player %d" % (i + 1)
        edit.text = Progress.names[i]
        edit.max_length = 12
        edit.custom_minimum_size = Vector2(380, 44)
        edit.add_theme_font_override("font", Art.FONT)
        edit.add_theme_font_size_override("font_size", 24)
        edit.add_theme_color_override("font_color", UiTheme.BONE)
        edit.text_changed.connect(func(t: String): Progress.set_player_name(i, t))
        row.add_child(edit)
        _name_edits.append(edit)
    col.add_child(UiTheme.button("Back", _close_overlay))


func _build_ledger() -> void:
    _ledger_center = _center()
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(780, 0)
    _ledger_center.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 8)
    panel.add_child(col)
    col.add_child(UiTheme.label("THE LEDGER", 40))
    _ledger_body = VBoxContainer.new()
    _ledger_body.add_theme_constant_override("separation", 4)
    col.add_child(_ledger_body)
    _ledger_back = UiTheme.button("Back", _close_overlay)
    col.add_child(_ledger_back)


func _fill_ledger() -> void:
    for c in _ledger_body.get_children():
        c.queue_free()
    _ledger_body.add_child(_left(UiTheme.label("Last runs", 26, UiTheme.BONE)))
    var hist: Array = Progress.history
    if hist.is_empty():
        _ledger_body.add_child(_left(UiTheme.label("  No runs yet. The Gate is waiting.", 22, UiTheme.DIM)))
    var shown := 0
    for i in range(hist.size() - 1, -1, -1):
        if shown >= 5:
            break
        shown += 1
        var h: Dictionary = hist[i]
        var won := bool(h.get("won", false))
        var unlocks: Array = h.get("unlocks", [])
        var line := "  Run %d    floor %d    %d kills    %s" % [i + 1, int(h.get("floor", 0)), int(h.get("kills", 0)), "CLEARED" if won else "fell"]
        if h.has("embers"):
            line += "    +%d Embers" % int(h["embers"])
        if not unlocks.is_empty():
            line += "    +%d unlock%s" % [unlocks.size(), "" if unlocks.size() == 1 else "s"]
        _ledger_body.add_child(_left(UiTheme.label(line, 22, Color(0.55, 1.0, 0.7) if won else UiTheme.BONE)))
    _ledger_body.add_child(_left(UiTheme.label("Totals", 26, UiTheme.BONE)))
    var totals := [
        "  Runs %d    cleared %d    floors %d    bosses %d" % [Progress.stat("runs_started"), Progress.stat("runs_won"), Progress.stat("floors"), Progress.stat("bosses")],
        "  Kills %d    elites %d    reactions %d" % [Progress.stat("kills"), Progress.stat("elites"), Progress.stat("reactions")],
        "  Achievements %d / %d    guns %d / %d" % [Progress.achievements_count(), Progress.ACHIEVEMENTS.size(), Guns.ids().size(), Guns.all_ids().size()],
        "  Embers: %d to spend at the Shrine, %d earned in all" % [Mastery.embers, Mastery.earned],
        "  Shrine: %d / %d talent ranks, Last Breath %d / %d" % [Mastery.ranks_bought(), Mastery.ranks_total(), Mastery.survival, Mastery.survival_max()],
        "  Embers by source: %s" % Mastery.earned_text(),
        "  Play data: %d runs kept on this device, sharing %s (Workshop options)" % [Telemetry.stored_count(), "on" if Telemetry.consent() == "on" else "off"],
    ]
    for t in totals:
        var l := _left(UiTheme.label(t, 22, UiTheme.DIM))
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        l.custom_minimum_size = Vector2(740, 0)
        _ledger_body.add_child(l)


func _left(l: Label) -> Label:
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    return l


func _build_explainer() -> void:
    _explainer_center = _center()
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(820, 0)
    _explainer_center.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 12)
    panel.add_child(col)
    col.add_child(UiTheme.label("HOW IT WORKS", 40, LIT))
    for line in EXPLAINER:
        var l := UiTheme.label(line, 24, UiTheme.BONE)
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        l.custom_minimum_size = Vector2(760, 0)
        col.add_child(l)
    _explainer_ok = UiTheme.button("Got it", _close_overlay)
    col.add_child(_explainer_ok)


## One-time card after the explainer: may anonymous play data be shared?
func _build_consent() -> void:
    _consent_center = _center()
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(820, 0)
    _consent_center.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 12)
    panel.add_child(col)
    col.add_child(UiTheme.label("SHARE PLAY DATA?", 40, LIT))
    for line in [
        "Help balance the game: anonymous play data from your runs (floors, deaths, purchases, level-up picks, guns used, frame rate).",
        "No names, no addresses, no text you type. A random id stands in for this device.",
        "It is kept on this device either way; change it any time under Options: Share play data.",
    ]:
        var l := UiTheme.label(line, 24, UiTheme.BONE)
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        l.custom_minimum_size = Vector2(760, 0)
        col.add_child(l)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    col.add_child(row)
    _consent_allow = UiTheme.button("Allow", func():
        Settings.set_value("telemetry", "on")
        _close_overlay())
    row.add_child(_consent_allow)
    row.add_child(UiTheme.button("No thanks", func():
        Settings.set_value("telemetry", "off")
        _close_overlay()))


func _build_esc_menu() -> void:
    _esc_center = _center()
    var panel := PanelContainer.new()
    _esc_center.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 10)
    panel.add_child(col)
    col.add_child(UiTheme.label("THE HUB", 40))
    _esc_first = UiTheme.button("Resume", _close_overlay)
    col.add_child(_esc_first)
    col.add_child(UiTheme.button("Options", func(): _open(_options_center, null)))
    col.add_child(UiTheme.button("How it works", func(): _open(_explainer_center, _explainer_ok)))
    col.add_child(UiTheme.button("Replay tutorial", func():
        Settings.set_value("tutorial_done", false)
        get_tree().change_scene_to_file("res://scenes/tutorial.tscn")))
    col.add_child(UiTheme.button("Quit", func(): get_tree().quit()))


# --- Progress helpers (also used by the run-over screen) ---------------------


## The next `count` open achievements: name, desc, progress, goal, reward (labels).
static func goal_rows(count: int) -> Array:
    var out: Array = []
    for g in Progress.next_goals(count):
        var row: Dictionary = g.duplicate()
        var rewards: Array = []
        for a in Progress.ACHIEVEMENTS:
            if a["name"] == g["name"]:
                for r in a["rewards"]:
                    rewards.append(Progress.unlock_label(r))
                break
        row["reward"] = ", ".join(rewards)
        out.append(row)
    return out


## A progress bar row for a goal, as a Control: name and reward above, bar and count below.
static func goal_bar(g: Dictionary, width: float) -> Control:
    var c := Control.new()
    c.custom_minimum_size = Vector2(width, 52)
    c.draw.connect(func(): draw_goal(c, Vector2.ZERO, g, width))
    return c


## Draw one goal row at `at` on any canvas item: title line, then a bar with the count.
static func draw_goal(ci: CanvasItem, at: Vector2, g: Dictionary, width: float) -> void:
    var font: Font = Art.FONT
    var goal := maxi(1, int(g.get("goal", 1)))
    var prog := clampi(int(g.get("progress", 0)), 0, goal)
    var title := "%s: %s" % [g.get("name", "?"), g.get("desc", "")]
    ci.draw_string(font, at + Vector2(0, 20), title, HORIZONTAL_ALIGNMENT_LEFT, width * 0.62, 22, UiTheme.BONE)
    var reward := String(g.get("reward", ""))
    if reward != "":
        ci.draw_string(font, at + Vector2(width * 0.62, 20), "unlocks " + reward, HORIZONTAL_ALIGNMENT_RIGHT, width * 0.38, 20, LIT)
    var bar := Rect2(at + Vector2(0, 30), Vector2(width - 90.0, 12))
    ci.draw_rect(bar, Color(0.16, 0.14, 0.16))
    ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(prog) / float(goal), bar.size.y)), UiTheme.FOCUS)
    ci.draw_rect(bar, Color(0.4, 0.35, 0.35), false, 1.0)
    ci.draw_string(font, at + Vector2(width - 84.0, 44), "%d / %d" % [prog, goal], HORIZONTAL_ALIGNMENT_RIGHT, 84.0, 20, UiTheme.DIM)


# --- Drawing -----------------------------------------------------------------


func _draw() -> void:
    var half := INNER / 2.0
    var rect := Rect2(-half, INNER)
    draw_rect(rect.grow(-10.0), Color(0, 0, 0, 0.35), false, 20.0)
    _draw_trophy_wall()
    for s in STATIONS:
        match String(s["style"]):
            "plinth":
                _draw_plinth(s)
            "gate":
                _draw_gate(s)
            "wall":
                _draw_wall_marker(s)


## Station names, prompts, the trophy count and goals: drawn on the Crisp layer so they
## stay sharp above the post-process pixel grid.
func _draw_texts(cv: CanvasItem) -> void:
    _cv = cv
    var half := INNER / 2.0
    var n: int = Progress.ACHIEVEMENTS.size()
    var y := -half.y + 14.0
    _text(Vector2(0, y + 10.0), "TROPHIES   %d / %d" % [Progress.achievements_count(), n], 24, LIT, 400.0)
    var goals := goal_rows(3)
    if goals.is_empty():
        _text(Vector2(0, y + 36.0), "Every achievement earned.", 20, UiTheme.BONE, 400.0)
    for i in goals.size():
        draw_goal(cv, Vector2(-280, y + 18.0 + float(i) * 46.0), goals[i], 560.0)
    for s in STATIONS:
        var p: Vector2 = s["pos"]
        match String(s["style"]):
            "plinth":
                _draw_label_and_prompt(s, p, -76.0)
            "gate":
                _draw_label_and_prompt(s, p, -50.0)
            "wall":
                if _highlight.has(String(s["id"])):
                    var pr: Array = _highlight[s["id"]]
                    Prompts.draw(cv, p + Vector2(0, -2.0 + sin(_time * 5.0) * 2.0), String(pr[0]), String(pr[1]), 24.0)
                    _text(p + Vector2(0, 40), String(s["verb"]), 20, Color(0.6, 1.0, 1.0))
    _cv = null


func _text(at: Vector2, text: String, px: int, col: Color, width: float = 260.0) -> void:
    var cv: CanvasItem = _cv if _cv != null else self
    var font: Font = Art.FONT
    cv.draw_string(font, at + Vector2(-width / 2.0 + 1.0, 1.0), text, HORIZONTAL_ALIGNMENT_CENTER, width, px, Color(0, 0, 0, 0.8))
    cv.draw_string(font, at + Vector2(-width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_CENTER, width, px, col)


func _draw_label_and_prompt(s: Dictionary, base: Vector2, top: float) -> void:
    var id := String(s["id"])
    var hl := _highlight.has(id)
    if String(s["name"]) != "":
        _text(base + Vector2(0, top), String(s["name"]), 26, Color(s["tint"]).lerp(Color.WHITE, 0.4 if hl else 0.0))
    if String(s["sub"]) != "":
        _text(base + Vector2(0, 46), String(s["sub"]), 20, UiTheme.DIM if not hl else UiTheme.BONE)
    if hl:
        var pr: Array = _highlight[id]
        Prompts.draw(_cv if _cv != null else self, base + Vector2(0, top - 34.0 + sin(_time * 5.0) * 2.0), String(pr[0]), String(pr[1]), 24.0)
        _text(base + Vector2(0, 68), String(s["verb"]), 20, Color(0.6, 1.0, 1.0))


func _draw_plinth(s: Dictionary) -> void:
    var p: Vector2 = s["pos"]
    var c: Color = s["tint"]
    var hl := _highlight.has(String(s["id"]))
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := 110.0 + sin(_time * 2.2 + p.x) * 8.0
    draw_texture_rect(glow, Rect2(p + Vector2(-g / 2.0, -g / 2.0 - 36.0), Vector2(g, g)), false, Color(c, 0.16 + (0.12 if hl else 0.0)))
    draw_circle(p + Vector2(0, 18), 26.0, Color(0, 0, 0, 0.45))
    draw_colored_polygon(PackedVector2Array([p + Vector2(-16, -8), p + Vector2(16, -8), p + Vector2(20, 14), p + Vector2(-20, 14)]), Color(0.30, 0.27, 0.29))
    draw_rect(Rect2(p + Vector2(-20, 10), Vector2(40, 6)), Color(0.22, 0.2, 0.22))
    draw_rect(Rect2(p + Vector2(-18, -12), Vector2(36, 6)), Color(0.42, 0.38, 0.40))
    draw_rect(Rect2(p + Vector2(-18, -12), Vector2(36, 2)), Color(0.58, 0.54, 0.55))
    draw_line(p + Vector2(-10, -4), p + Vector2(-10, 8), Color(0.2, 0.18, 0.2), 1.0)
    draw_line(p + Vector2(10, -4), p + Vector2(10, 8), Color(0.2, 0.18, 0.2), 1.0)
    draw_circle(p + Vector2(0, -14), 10.0, Color(0, 0, 0, 0.35))
    if hl:
        draw_rect(Rect2(p + Vector2(-18, -12), Vector2(36, 6)), Color(c, 0.6))
    var bob := sin(_time * 2.2 + p.x * 0.01) * 3.0
    var icon_rect := Rect2(p + Vector2(-20, -58 + bob), Vector2(40, 40))
    if s.has("icon"):
        # A 32 px Dungeon Crawl tile at 1x, untinted: the glow carries the station colour.
        Art.draw_icon(self, Art.icon(String(s["icon"]), s["tile"]), icon_rect)
    else:
        draw_texture_rect(Art.tile(s["tile"]), icon_rect, false, c)


## The Gate: a dark arch cut into the bottom wall, stairs going down, a cold glow.
func _draw_gate(s: Dictionary) -> void:
    var p: Vector2 = s["pos"]
    var half := INNER / 2.0
    var c: Color = s["tint"]
    var arch := Rect2(Vector2(-70, half.y - 4.0), Vector2(140, WALL + 4.0))
    draw_rect(arch.grow(6.0), Color(0.25, 0.2, 0.22))
    draw_rect(arch, Color(0.01, 0.01, 0.02))
    for i in 4:
        draw_rect(Rect2(Vector2(-60 + i * 6, half.y + 8.0 + i * 12.0), Vector2(120 - i * 12, 6)), Color(0.18, 0.2, 0.24, 1.0 - 0.2 * i))
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := 220.0 + sin(_time * 1.6) * 16.0
    draw_texture_rect(glow, Rect2(Vector2(-g / 2.0, half.y - g / 2.0), Vector2(g, g)), false, Color(c, 0.18 + (0.12 if _highlight.has("gate") else 0.0)))
    draw_arc(p, 34.0, 0.0, TAU, 40, Color(c, 0.35 + 0.15 * sin(_time * 3.0)), 2.0)
    draw_texture_rect(Art.tile(s["tile"]), Rect2(p + Vector2(-16, -16), Vector2(32, 32)), false, Color(c, 0.85))


## The Trophy Wall: a plaque on the top wall with one tile per achievement, the count,
## and the next three goals with bars written on the floor under it.
func _draw_trophy_wall() -> void:
    var half := INNER / 2.0
    var n: int = Progress.ACHIEVEMENTS.size()
    var cols := maxi(1, ceili(float(n) / 2.0))
    var cell := minf(20.0, 600.0 / float(cols))
    var w := cell * float(cols)
    var top := -half.y - WALL + 6.0
    var plaque := Rect2(Vector2(-w / 2.0 - 10.0, top - 2.0), Vector2(w + 20.0, cell * 2.0 + 10.0))
    draw_rect(plaque.grow(3.0), Color(0.35, 0.28, 0.2))
    draw_rect(plaque, Color(0.06, 0.05, 0.06))
    for i in n:
        var a: Dictionary = Progress.ACHIEVEMENTS[i]
        var done: bool = Progress.achievements_done.has(a["id"])
        var at := Vector2(-w / 2.0 + float(i % cols) * cell, top + 3.0 + float(i / cols) * cell)
        var r := Rect2(at + Vector2(1, 1), Vector2(cell - 2.0, cell - 2.0))
        var tex := Progress.achievement_icon(a)
        if done:
            draw_rect(r, Color(LIT, 0.18))
            Art.draw_icon(self, tex, r)
        else:
            Art.draw_icon(self, tex, r, Color(0.22, 0.2, 0.22))


func _draw_wall_marker(s: Dictionary) -> void:
    var p: Vector2 = s["pos"]
    var hl := _highlight.has(String(s["id"]))
    draw_arc(p, 30.0, 0.0, TAU, 32, Color(LIT, 0.25 + (0.3 if hl else 0.0)), 2.0)
    draw_arc(p, 20.0, _time, _time + PI * 1.4, 16, Color(LIT, 0.3), 2.0)


# --- Test hook ---------------------------------------------------------------


func _capture(path: String, wait: float) -> void:
    await get_tree().create_timer(wait).timeout
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png(path)


## `-- --menu-shot`: the hub (as menu.png), each journal tab, mastery, names, classes,
## options; then quit.
func _menu_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    players[0].global_position = Vector2(-420, -40)
    await _capture("res://autotest/menu.png", 0.8)
    _open(_journal_center, null)
    for i in Journal.TABS.size():
        _journal.set_tab(i)
        await _capture("res://autotest/journal_%d.png" % i, 0.3)
    _close_overlay()
    _open(_mastery_center, null)
    await _capture("res://autotest/mastery.png", 0.4)
    _close_overlay()
    _open(_names_center, _name_edits[0])
    await _capture("res://autotest/names.png", 0.3)
    _close_overlay()
    _open(_options_center, null)
    await _capture("res://autotest/options.png", 0.3)
    _close_overlay()
    _show_class_select()
    await _capture("res://autotest/classes.png", 0.4)
    get_tree().quit()


## `-- --themes-shot` ends here (after Main's theme rooms): the sanctum with its ambience
## running for 2 s, saved as res://autotest/theme_sanctum.png, then quit.
func _theme_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    players[0].global_position = Vector2(0, 120)
    await _capture("res://autotest/theme_sanctum.png", 2.0)
    print("[THEME SHOT] sanctum  ambience=%d px" % (ambience.live() if ambience != null else 0))
    get_tree().quit()


func _players_count() -> int:
    var n := 0
    for c in get_children():
        if c is Player:
            n += 1
    return maxi(1, n)
