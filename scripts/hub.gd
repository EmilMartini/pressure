class_name Hub
extends Node2D
## The Hollow (World and progression GDD, section 9): a few connected rooms the player
## walks through between runs, with people in them. The Fire (the Keeper: talents), the
## Stair (the Gatewarden: the Gate and past runs, and the Gate arch itself), the Library
## (the Archivist once recruited: the Journal and the full ledger), the Forge (the Armory
## and the Workshop, until their NPCs arrive) and the Chapel (the trophy wall and the
## Mirror). Talking opens a line keyed to the save (Dialogue) and the NPC's services.
## A fresh save shows only the Keeper, the Gatewarden and the Gate; the stations without
## an NPC yet show from the first finished run on. Esc / Start opens a small menu. Late
## pads join on Start like in a run.
##
## `-- --menu-shot` saves hub, journal, mastery, names, classes and options captures.
## `-- --hub-walk --instance=N` is the bot: it walks the rooms and uses every station on
## show (`--keep-save` keeps that instance's save, `--hub-shot` saves captures).
## `-- --hub-descend --autotest --one-floor --secs=N --instance=N` is the exported-exe smoke
## test (tools/exe_smoke.sh): the Gate's loadout screen opens and Descend is clicked with the
## mouse (`--descend-key`: Enter), the
## bot plays N seconds, the run hands back to the Hollow, and the Hollow quits (after
## `--descend-runs=K` such runs, default 1).

const WALL := 60.0
const DOOR := 140.0
const RANGE := 64.0
const NPC_RANGE := 84.0
const HINT_SECS := 7.0
const LIT := Color(1.0, 0.82, 0.35)
const FIRE := Vector2(-80, -150)

## Room inner rects; rooms sit two walls apart, so each builds its own walls.
const ROOMS := {
    "hall": { "name": "THE FIRE", "rect": Rect2(-450, -300, 900, 600), "theme": "sanctum" },
    "chapel": { "name": "THE CHAPEL", "rect": Rect2(-350, -840, 700, 420), "theme": "sanctum" },
    "library": { "name": "THE LIBRARY", "rect": Rect2(-1210, -260, 640, 520), "theme": "crypt" },
    "forge": { "name": "THE FORGE", "rect": Rect2(570, -260, 640, 520), "theme": "forge" },
    "stair": { "name": "THE STAIR", "rect": Rect2(-350, 420, 700, 420), "theme": "ruins" },
}
## Doorways: the middle of the gap where the two rooms' walls meet.
const DOORS := [
    { "a": "hall", "b": "chapel", "at": Vector2(0, -360) },
    { "a": "hall", "b": "library", "at": Vector2(-510, 0) },
    { "a": "hall", "b": "forge", "at": Vector2(510, 0) },
    { "a": "hall", "b": "stair", "at": Vector2(0, 360) },
]

const STATIONS := [
    { "id": "keeper", "npc": "keeper", "sub": "talents", "pos": Vector2(-170, -120), "verb": "talk", "style": "npc", "room": "hall" },
    { "id": "gatewarden", "npc": "gatewarden", "sub": "the Gate, past runs", "pos": Vector2(-170, 690), "verb": "talk", "style": "npc", "room": "stair" },
    { "id": "gate", "name": "THE GATE", "sub": "start a run", "pos": Vector2(0, 776), "tile": Vector2i(4, 10), "tint": Color(0.55, 1.0, 1.0), "verb": "descend", "style": "gate", "room": "stair" },
    { "id": "archivist", "npc": "archivist", "sub": "journal, ledger", "pos": Vector2(-880, -50), "verb": "talk", "style": "npc", "room": "library" },
    { "id": "wellkeeper", "npc": "wellkeeper", "sub": "relics", "pos": Vector2(230, -90), "verb": "trade", "style": "npc", "room": "hall" },
    { "id": "cartographer", "npc": "cartographer", "sub": "the world map", "pos": Vector2(-720, 150), "verb": "talk", "style": "npc", "room": "library" },
    { "id": "armory", "name": "ARMORY", "sub": "guns and gear", "pos": Vector2(760, -40), "tile": Vector2i(42, 9), "icon": "item/weapon/ranged/crossbow_2.png", "tint": Color(1.0, 0.6, 0.3), "verb": "browse", "style": "plinth", "room": "forge" },
    { "id": "workshop", "name": "WORKSHOP", "sub": "options", "pos": Vector2(1020, -40), "tile": Vector2i(41, 5), "icon": "gui/spells/earth/maxwells_silver_hammer.png", "tint": Color(0.85, 0.8, 0.7), "verb": "tinker", "style": "plinth", "room": "forge" },
    { "id": "mirror", "name": "MIRROR", "sub": "names", "pos": Vector2(250, -520), "tile": Vector2i(31, 0), "icon": "item/misc/mirror.png", "tint": Color(0.6, 0.85, 1.0), "verb": "look", "style": "plinth", "room": "chapel" },
    { "id": "trophies", "name": "", "sub": "", "pos": Vector2(-60, -580), "tile": Vector2i(9, 11), "tint": LIT, "verb": "all achievements", "style": "wall", "room": "chapel" },
]

const EXPLAINER := [
    "A run is five floors. Each floor ends in a boss.",
    "Dying keeps your achievements, unlocks and Embers.",
    "Runs pay Embers for rooms, elites and new reactions; the Keeper trades them for swappable talents.",
    "Your loadout at the Gate (Kit, Mark, Relic, Vow) only changes how a run starts.",
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
var _walk := false
## Smoke-test passes through the Hollow (--hub-descend): 0 = open the Gate and Descend,
## then back from each run (--descend-runs=N, default 1), quitting after the last.
static var _descend_pass := 0

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
var _ledger_title: Label
var _ledger_body: VBoxContainer
var _ledger_back: Button
var _explainer_center: CenterContainer
var _explainer_ok: Button
var _esc_center: CenterContainer
var _esc_first: Button
var _consent_center: CenterContainer
var _consent_allow: Button
var _talk_root: Control
var _talk_panel: PanelContainer
var _talk_name: Label
var _talk_text: Label
var _talk_buttons: HBoxContainer
var _talking := ""
var _class_select: LoadoutScreen = null
var _relic_center: CenterContainer
var _relic_body: VBoxContainer
var _relic_back: Button
var _map_center: CenterContainer
var _map_back: Button
var _map_list: Label
const WELL_POS := Vector2(330, -60)
var _cv: CanvasItem = null     # where _text and prompts draw (the Crisp proxy)
var ambience: Ambience = null


func _ready() -> void:
    randomize()
    var args := OS.get_cmdline_user_args()
    # Exported release builds cannot pick a scene on the command line, so the hub (the
    # start scene) hands bot and capture runs straight to the run scene.
    var descend_probe := args.has("--hub-descend")
    for flag in ["--autotest", "--start-shot", "--obstacle-test", "--layouts-shot"]:
        if args.has(flag) and not descend_probe:
            get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
            return
    _shot = args.has("--menu-shot")
    _walk = args.has("--hub-walk")
    var theme_shot := args.has("--themes-shot")
    if _walk or descend_probe:
        # The hub bot: its own save, Shrine and play-data files per --instance, fresh
        # unless --keep-save (after a --recruit-probe run on the same instance).
        var tag := Main._instance_tag()
        Progress.save_path = "user://save_autotest%s.json" % tag
        Mastery.save_path = "user://mastery_autotest%s.json" % tag
        Telemetry.use_file("user://telemetry/runs%s.jsonl" % (tag if tag != "" else "_bot"))
        if args.has("--keep-save"):
            Progress.load_save()
            Mastery.load_save()
        else:
            Progress.reset()
            Mastery.reset()
    elif _shot or theme_shot:
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
    camera.position_smoothing_enabled = true
    camera.position_smoothing_speed = 6.0
    var bounds := _bounds().grow(WALL)
    camera.limit_left = int(bounds.position.x)
    camera.limit_top = int(bounds.position.y)
    camera.limit_right = int(bounds.end.x)
    camera.limit_bottom = int(bounds.end.y)
    add_child(camera)
    camera.make_current()
    add_child(PostFx.new())
    _build_rooms()
    Crisp.attach(self, _draw_texts)
    MenuPad.strip_joypad_from_ui_actions()
    _build_ui()
    var pads := Input.get_connected_joypads()
    _spawn_player(0 if pads.has(0) else -1, true)
    camera.position = players[0].position
    camera.reset_smoothing()
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
    elif _walk:
        _hub_walk()
    elif descend_probe:
        _descend_probe()
    elif not Settings.flag("seen_explainer"):
        _open(_explainer_center, _explainer_ok)
    elif Telemetry.consent() == "ask":
        _open(_consent_center, _consent_allow)


# --- Rooms -------------------------------------------------------------------


static func _bounds() -> Rect2:
    var out := Rect2()
    var first := true
    for id in ROOMS:
        var r: Rect2 = ROOMS[id]["rect"]
        out = r if first else out.merge(r)
        first = false
    return out


## Which room a point is in (doorways count as the nearer room), "" outside them all.
static func room_at(pos: Vector2) -> String:
    var best := ""
    var best_d := INF
    for id in ROOMS:
        var r: Rect2 = ROOMS[id]["rect"]
        if r.has_point(pos):
            return String(id)
        var d := r.get_center().distance_to(pos)
        if d < best_d:
            best_d = d
            best = String(id)
    return best


## Whether a station is in the Hollow yet. The Keeper, the Gatewarden and the Gate are
## always there; the Archivist once recruited; stations whose NPC is not built yet from
## the first run on, so a fresh save starts with the Shrine and the Gate only.
func _shown(s: Dictionary) -> bool:
    match String(s["id"]):
        "keeper", "gatewarden", "gate":
            return true
        "archivist":
            return Progress.npc_home("archivist")
        "wellkeeper":
            return Progress.npc_home("wellkeeper")
        "cartographer":
            return Progress.npc_home("cartographer")
    return _settled()


func _settled() -> bool:
    return Progress.stat("runs_started") > 0 or not Progress.history.is_empty()


func _station(id: String) -> Dictionary:
    for s in STATIONS:
        if s["id"] == id:
            return s
    return {}


func _build_rooms() -> void:
    Themes.current = "sanctum"
    var body := StaticBody2D.new()
    body.collision_layer = Player.LAYER_WALLS
    body.collision_mask = 0
    add_child(body)
    var seed_n := 4242
    for id in ROOMS:
        var room: Dictionary = ROOMS[id]
        var r: Rect2 = room["rect"]
        var fill := Themes.floor_fill(r, camera.zoom.x, seed_n, Color.WHITE, String(room["theme"]))
        fill.z_index = -2
        add_child(fill)
        seed_n += 17
        _room_walls(body, String(id), r, String(room["theme"]))
    for d in DOORS:
        var at: Vector2 = d["at"]
        var ra: Rect2 = ROOMS[d["a"]]["rect"]
        var vertical: bool = at.y < ra.position.y or at.y > ra.end.y
        var hall := Rect2(at - Vector2(DOOR / 2.0, WALL), Vector2(DOOR, 2.0 * WALL)) if vertical else Rect2(at - Vector2(WALL, DOOR / 2.0), Vector2(2.0 * WALL, DOOR))
        var fill := Themes.floor_fill(hall, camera.zoom.x, seed_n, Color(0.8, 0.8, 0.8), String(ROOMS[d["a"]]["theme"]))
        fill.z_index = -2
        add_child(fill)
    # Bodies for plinths and people on show, so players walk around them.
    for s in STATIONS:
        if not _shown(s) or not String(s["style"]) in ["plinth", "npc"]:
            continue
        var shape := CollisionShape2D.new()
        var rs := RectangleShape2D.new()
        rs.size = Vector2(36, 18) if s["style"] == "plinth" else Vector2(30, 14)
        shape.shape = rs
        shape.position = Vector2(s["pos"]) + (Vector2(0, 4) if s["style"] == "plinth" else Vector2(0, -6))
        body.add_child(shape)
    ambience = Ambience.new(null, "sanctum", _bounds())
    for id in ROOMS:
        var r: Rect2 = ROOMS[id]["rect"]
        for f in [0.2, 0.8]:
            ambience.add_light(Vector2(r.position.x + r.size.x * f, r.position.y - 30.0), "torch")
    ambience.add_light(FIRE, "brazier")
    # Art pass (art_pass.gd): light, grade and the Gatewarden's gatehouse.
    ArtPass.dress_hub(self, ambience, ROOMS["stair"]["rect"], _station("gate")["pos"], FIRE, Player.LAYER_WALLS)
    add_child(ambience)


## The four walls of a room, cut where a doorway leads out.
func _room_walls(body: StaticBody2D, id: String, r: Rect2, theme: String) -> void:
    var gaps := { "top": [], "bottom": [], "left": [], "right": [] }
    for d in DOORS:
        if d["a"] != id and d["b"] != id:
            continue
        var at: Vector2 = d["at"]
        if at.y < r.position.y:
            gaps["top"].append(at.x)
        elif at.y > r.end.y:
            gaps["bottom"].append(at.x)
        elif at.x < r.position.x:
            gaps["left"].append(at.y)
        else:
            gaps["right"].append(at.y)
    var x0 := r.position.x - WALL
    var x1 := r.end.x + WALL
    for side in ["top", "bottom"]:
        var y := r.position.y - WALL if side == "top" else r.end.y
        for span in _spans(x0, x1, gaps[side]):
            _wall(body, Rect2(span.x, y, span.y - span.x, WALL), theme)
    for side in ["left", "right"]:
        var x := r.position.x - WALL if side == "left" else r.end.x
        for span in _spans(r.position.y, r.end.y, gaps[side]):
            _wall(body, Rect2(x, span.x, WALL, span.y - span.x), theme)


## [from, to] minus a DOOR-wide gap around each centre, as Vector2(start, end) spans.
static func _spans(from: float, to: float, centres: Array) -> Array:
    var out: Array = []
    var at := from
    var sorted := centres.duplicate()
    sorted.sort()
    for c in sorted:
        var g0 := float(c) - DOOR / 2.0
        if g0 > at:
            out.append(Vector2(at, g0))
        at = float(c) + DOOR / 2.0
    if to > at:
        out.append(Vector2(at, to))
    return out


func _wall(body: StaticBody2D, rect: Rect2, theme: String) -> void:
    var shape := CollisionShape2D.new()
    var r := RectangleShape2D.new()
    r.size = rect.size
    shape.shape = r
    shape.position = rect.get_center()
    body.add_child(shape)
    var bricks := Themes.wall_fill(rect, camera.zoom.x, Color.WHITE, theme)
    bricks.z_index = -1
    add_child(bricks)


# --- Players -----------------------------------------------------------------


func _spawn_player(device: int, keyboard: bool) -> Player:
    var p := Player.new(players.size(), PlayerInput.new(device, keyboard))
    p.position = Vector2(-40.0 + 40.0 * float(players.size()), 40.0)
    p.set_meta("mark_id", String(Loadout.current()["mark"]))   # the Mark's accent in the Hollow too
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
    _follow_camera()
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
            if not _shown(s):
                continue
            var d := p.global_position.distance_to(Vector2(s["pos"]))
            if d <= _range_of(s) and d < best_d:
                best_d = d
                best = String(s["id"])
        if best != "":
            _use_station(best)
            return


## The camera follows the players' middle; the room limits keep it off the void.
func _follow_camera() -> void:
    if players.is_empty() or camera == null:
        return
    var mid := Vector2.ZERO
    for p in players:
        mid += p.global_position
    camera.position = mid / float(players.size())


func _range_of(s: Dictionary) -> float:
    match String(s["style"]):
        "wall":
            return 110.0
        "gate":
            return 80.0
        "npc":
            return NPC_RANGE
    return RANGE


func _update_highlights() -> void:
    _highlight.clear()
    for s in STATIONS:
        if not _shown(s):
            continue
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
        "keeper", "gatewarden", "archivist", "cartographer":
            _talk(id)
        "gate":
            _show_class_select()
        "wellkeeper":
            # Silent (GDD section 9): no line, straight to her trade.
            _fill_relics()
            _open(_relic_center, _relic_first())
        "armory":
            _open_journal("armory")
        "trophies":
            _open_journal("trophies")
        "mirror":
            _open(_names_center, _name_edits[0])
        "workshop":
            _open(_options_center, null)


## Each station opens its own part of the Journal (Journal.set_view).
func _open_journal(which: String) -> void:
    _open(_journal_center, null)
    match which:
        "armory":
            _journal.set_view("ARMORY", [1, 2])
            _journal.set_tab(1)
        "trophies":
            _journal.set_view("TROPHIES", [0])
            _journal.set_tab(0)
        "archivist":
            _journal.set_view("JOURNAL", [3, 4, 5, 6])
            _journal.set_tab(3)
        _:
            _journal.set_view("JOURNAL", [])


# --- Talking -----------------------------------------------------------------


## What each NPC offers after their line: [button label, action].
func _services(npc: String) -> Array:
    match npc:
        "keeper":
            return [["Talents", func():
                _open(_mastery_center, null)
                _mastery.set_tab(_mastery.tab)]]
        "gatewarden":
            return [["Descend", func():
                _close_overlay()
                _show_class_select()],
                ["Past runs", func():
                _fill_ledger(Progress.npc_home("archivist"))
                _open(_ledger_center, _ledger_back)]]
        "cartographer":
            return [["World map", func(): _open_map()]]
        "archivist":
            return [["Journal", func(): _open_journal("archivist")],
                ["Ledger", func():
                _fill_ledger(true)
                _open(_ledger_center, _ledger_back)]]
    return []


func _talk(npc: String) -> void:
    _talking = npc
    var line := Dialogue.say(npc, Dialogue.context({ "where": "hub" }))
    Telemetry.hub_event("talk", { "npc": npc, "line": String(line.get("id", "")) })
    _talk_name.text = Npc.display_name(npc)
    _talk_name.add_theme_color_override("font_color", Npc.color(npc))
    _talk_text.text = String(line.get("text", "..."))
    for c in _talk_buttons.get_children():
        _talk_buttons.remove_child(c)
        c.queue_free()
    var first: Button = null
    for sv in _services(npc):
        var b := UiTheme.button(String(sv[0]), sv[1])
        _talk_buttons.add_child(b)
        if first == null:
            first = b
    var leave := UiTheme.button("Leave", _close_overlay)
    _talk_buttons.add_child(leave)
    # The box goes along the bottom, or along the top when the speaker stands in the lower
    # half of the screen (the Stair: the camera stops at the room's edge), so it never
    # covers them.
    var at := get_viewport().get_canvas_transform() * Vector2(_station(npc).get("pos", Vector2.ZERO))
    _place_talk(at.y > get_viewport_rect().size.y * 0.5)
    _open(_talk_root, first if first != null else leave)


func _talk_button(label: String) -> Button:
    for c in _talk_buttons.get_children():
        if c is Button and (c as Button).text == label:
            return c
    return null


func _place_talk(top: bool) -> void:
    _talk_panel.set_anchors_preset(Control.PRESET_CENTER_TOP if top else Control.PRESET_CENTER_BOTTOM)
    _talk_panel.offset_left = -540
    _talk_panel.offset_right = 540
    _talk_panel.offset_top = 28.0 if top else -230.0
    _talk_panel.offset_bottom = 230.0 if top else -28.0
    _talk_panel.grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN


# --- Overlays ----------------------------------------------------------------


func _open(c: Control, focus: Control) -> void:
    if _overlay != null and _overlay != c:
        _overlay.visible = false
    _overlay = c
    _dim.visible = c != _talk_root
    c.visible = true
    # A button still held from opening (A on the plinth) must be released first.
    for k in ["accept", "cancel", "left", "right"]:
        _pad._was[k] = true
    for p in players:
        p.set_physics_process(false)
        p.input.force_move = Vector2.ZERO
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
    if after_explainer and Telemetry.consent() == "ask" and not _shot and not _walk:
        _open(_consent_center, _consent_allow)


func _show_class_select() -> void:
    if _class_select != null:
        return
    _dim.visible = false
    for p in players:
        p.set_physics_process(false)
    _class_select = LoadoutScreen.new(_on_class_picked, _close_class_select)
    _ui.add_child(_class_select)


func _close_class_select() -> void:
    if _class_select != null:
        _class_select.queue_free()
        _class_select = null
    _closed_frame = Engine.get_process_frames()
    _cooldown = 0.25
    for p in players:
        p.set_physics_process(true)


## The exe smoke test (--hub-descend): Descend through the real loadout screen, and quit
## once the run has handed back to the Hollow.
func _descend_probe() -> void:
    _descend_pass += 1
    var runs := 1
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--descend-runs="):
            runs = maxi(1, int(a.substr(15)))
    await get_tree().create_timer(1.5).timeout
    if _descend_pass > runs:
        print("[HUB-DESCEND] back in the Hollow; quitting")
        get_tree().quit()
        return
    _show_class_select()
    await get_tree().create_timer(1.0).timeout
    if OS.get_cmdline_user_args().has("--descend-key"):
        # The keyboard route: Enter through Input, like a player.
        print("[HUB-DESCEND] pressing Descend (Enter)")
        for down in [true, false]:
            var k := InputEventKey.new()
            k.physical_keycode = KEY_ENTER
            k.keycode = KEY_ENTER
            k.pressed = down
            Input.parse_input_event(k)
        return
    # The mouse route (default): a real left click on the Descend button, through Input and
    # the GUI, which runs the scene change inside the click's own dispatch.
    var at := Vector2.ZERO
    for hit in _class_select._hits:
        if int(hit[1]) == 4:
            at = _class_select.get_screen_transform() * (hit[0] as Rect2).get_center()
    print("[HUB-DESCEND] pressing Descend (mouse click at %s)" % at)
    # Pushed in the viewport's own coordinates (headless has no pointer over a window): a
    # move onto the button, then press and release.
    var mm := InputEventMouseMotion.new()
    mm.position = at
    mm.global_position = at
    get_viewport().push_input(mm, true)
    await get_tree().process_frame
    for down in [true, false]:
        var mb := InputEventMouseButton.new()
        mb.button_index = MOUSE_BUTTON_LEFT
        mb.pressed = down
        mb.position = at
        mb.global_position = at
        if is_inside_tree():
            get_viewport().push_input(mb, true)
    await get_tree().create_timer(2.0).timeout
    if is_inside_tree():
        print("[HUB-DESCEND] FAIL: the click did not Descend")
        get_tree().quit(1)


func _on_class_picked(lo: Dictionary) -> void:
    Progress.loadout = lo
    Progress.save()
    # Deferred: Descend runs inside the click's (or key's) own input dispatch, and swapping
    # the scene there tore the Hollow out from under the GUI; the release exe crashed
    # (0xc0000005) on a mouse click. Never change scene synchronously from input.
    get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


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
    _hint = UiTheme.label("Walk   WASD / left stick      talk, use   E / A      menu   Esc / Start", 22, UiTheme.BONE)
    _hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _hint.offset_left = -500
    _hint.offset_right = 500
    _hint.offset_top = 24
    _ui.add_child(_hint)

    _pad.on_cancel = func():
        if _overlay in [_esc_center, _explainer_center, _journal_center, _mastery_center, _names_center, _ledger_center, _talk_root]:
            _close_overlay()
    _pad.on_tab = func(step: int):
        if _overlay == _journal_center:
            _journal.step_tab(step)
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
    _build_talk()


## The talk box: along the bottom, so the speaker stays in view above it. The name in
## the NPC's colour, the line, then their services and Leave (focus starts on the first).
func _build_talk() -> void:
    _talk_root = Control.new()
    _talk_root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _talk_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _talk_root.visible = false
    _ui.add_child(_talk_root)
    var panel := PanelContainer.new()
    _talk_panel = panel
    _place_talk(false)
    _talk_root.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 10)
    panel.add_child(col)
    _talk_name = UiTheme.label("", 30)
    _talk_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    col.add_child(_talk_name)
    _talk_text = UiTheme.label("", 28, UiTheme.BONE)
    _talk_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _talk_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _talk_text.custom_minimum_size = Vector2(1040, 0)
    col.add_child(_talk_text)
    _talk_buttons = HBoxContainer.new()
    _talk_buttons.add_theme_constant_override("separation", 16)
    col.add_child(_talk_buttons)


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
    _ledger_title = UiTheme.label("THE LEDGER", 40)
    col.add_child(_ledger_title)
    _ledger_body = VBoxContainer.new()
    _ledger_body.add_theme_constant_override("separation", 4)
    col.add_child(_ledger_body)
    _ledger_back = UiTheme.button("Back", _close_overlay)
    col.add_child(_ledger_back)
    # The Wellkeeper's trade: items saved in a Well, bought back as Relics with Embers.
    _relic_center = _center()
    var rpanel := PanelContainer.new()
    rpanel.custom_minimum_size = Vector2(780, 0)
    _relic_center.add_child(rpanel)
    var rcol := VBoxContainer.new()
    rcol.add_theme_constant_override("separation", 8)
    rpanel.add_child(rcol)
    var rtitle := UiTheme.label(Npc.display_name("wellkeeper"), 40)
    rtitle.add_theme_color_override("font_color", Npc.color("wellkeeper"))
    rcol.add_child(rtitle)
    _relic_body = VBoxContainer.new()
    _relic_body.add_theme_constant_override("separation", 6)
    rcol.add_child(_relic_body)
    _relic_back = UiTheme.button("Leave", _close_overlay)
    rcol.add_child(_relic_back)
    # The Cartographer's world map (WorldMap): the Descent and the shortcuts opened.
    _map_center = _center()
    var mpanel := PanelContainer.new()
    _map_center.add_child(mpanel)
    var mcol := VBoxContainer.new()
    mcol.add_theme_constant_override("separation", 8)
    mpanel.add_child(mcol)
    var mtitle := UiTheme.label("THE DESCENT", 40)
    mtitle.add_theme_color_override("font_color", Npc.color("cartographer"))
    mcol.add_child(mtitle)
    mcol.add_child(WorldMap.new())
    _map_list = UiTheme.label("", 20, UiTheme.BONE)
    _map_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _map_list.custom_minimum_size = Vector2(900, 0)
    mcol.add_child(_map_list)
    _map_back = UiTheme.button("Back", _close_overlay)
    mcol.add_child(_map_back)


## The Wellkeeper's stall: what waits in the Well (a button each, priced by rarity), what
## is already yours, and the Embers in hand. Placeholder wording (section 9 review).
func _fill_relics() -> void:
    for c in _relic_body.get_children():
        _relic_body.remove_child(c)
        c.queue_free()
    _relic_body.add_child(UiTheme.label("Embers: %d" % Mastery.embers, 22, LIT))
    if Progress.well_saved.is_empty():
        _relic_body.add_child(UiTheme.label("Nothing waits in the Well.", 22, UiTheme.DIM))
    for id in Progress.well_saved:
        var item_id := String(id)
        var it: Dictionary = Items.get_item(item_id)
        var price := Loadout.relic_price(item_id)
        var label := "%s  (%s)    %d Embers" % [String(it.get("name", item_id)), Items.rarity_name(it), price]
        var b := UiTheme.button(label, func(): _buy_relic(item_id))
        b.icon = Items.icon(it)
        b.custom_minimum_size = Vector2(700, 56)
        b.add_theme_color_override("font_color", Items.rarity_text_color(it))
        b.disabled = Mastery.embers < price
        _relic_body.add_child(b)
    if not Progress.relics.is_empty():
        var names: Array = []
        for id in Progress.relics:
            names.append(String(Items.get_item(String(id)).get("name", id)))
        var own := UiTheme.label("Your Relics: %s. Choose one at the Gate." % ", ".join(names), 20, UiTheme.BONE)
        own.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        own.custom_minimum_size = Vector2(700, 0)
        _relic_body.add_child(own)


## The map, with the opened shortcuts named under it. Placeholder wording.
func _open_map() -> void:
    var names: Array = []
    for id in Shortcuts.opened():
        names.append(Shortcuts.display_name(String(id)))
    _map_list.text = ("Shortcuts open: %s." % ", ".join(names)) if not names.is_empty() else "No shortcuts open yet."
    _open(_map_center, _map_back)
    if _walk:
        print("[HUB-MAP] shortcuts open %d: %s" % [names.size(), ", ".join(names)])


func _relic_first() -> Control:
    for c in _relic_body.get_children():
        if c is Button and not (c as Button).disabled:
            return c
    return _relic_back


func _buy_relic(item_id: String) -> void:
    if Progress.buy_relic(item_id):
        Sfx.play("buy")
        Telemetry.hub_event("relic", { "item": item_id })
        if _walk:
            print("[HUB-RELIC] bought %s, Embers left %d" % [item_id, Mastery.embers])
    else:
        Sfx.play("error")
    _fill_relics()
    _relic_first().grab_focus.call_deferred()


## The run history. Bare (the Gatewarden's count, before the Archivist moves in): the
## last runs and the tally of deaths. Full (the Archivist's ledger): totals as well.
func _fill_ledger(full: bool = true) -> void:
    for c in _ledger_body.get_children():
        c.queue_free()
    _ledger_title.text = "THE LEDGER" if full else "PAST RUNS"
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
        if String(h.get("region", "")) != "" and not won:
            line += " in %s" % Regions.display_name(String(h["region"]))
        if h.has("embers"):
            line += "    +%d Embers" % int(h["embers"])
        if not unlocks.is_empty():
            line += "    +%d unlock%s" % [unlocks.size(), "" if unlocks.size() == 1 else "s"]
        _ledger_body.add_child(_left(UiTheme.label(line, 22, Color(0.55, 1.0, 0.7) if won else UiTheme.BONE)))
    if not full:
        _ledger_body.add_child(_left(UiTheme.label("  Runs %d    cleared %d    deaths %d" % [Progress.stat("runs_started"), Progress.stat("runs_won"), Progress.deaths()], 22, UiTheme.DIM)))
        return
    _ledger_body.add_child(_left(UiTheme.label("Totals", 26, UiTheme.BONE)))
    var totals := [
        "  Runs %d    cleared %d    floors %d    bosses %d" % [Progress.stat("runs_started"), Progress.stat("runs_won"), Progress.stat("floors"), Progress.stat("bosses")],
        "  Kills %d    elites %d    reactions %d" % [Progress.stat("kills"), Progress.stat("elites"), Progress.stat("reactions")],
        "  Achievements %d / %d    guns %d / %d" % [Progress.achievements_count(), Progress.ACHIEVEMENTS.size(), Guns.ids().size(), Guns.all_ids().size()],
        "  Embers: %d to spend with the Keeper, %d earned in all" % [Mastery.embers, Mastery.earned],
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
    col.add_child(UiTheme.label("THE HOLLOW", 40))
    _esc_first = UiTheme.button("Resume", _close_overlay)
    col.add_child(_esc_first)
    col.add_child(UiTheme.button("Options", func(): _open(_options_center, null)))
    col.add_child(UiTheme.button("How it works", func(): _open(_explainer_center, _explainer_ok)))
    col.add_child(UiTheme.button("Replay tutorial", func():
        Settings.set_value("tutorial_done", false)
        get_tree().change_scene_to_file.call_deferred("res://scenes/tutorial.tscn")))
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
    for id in ROOMS:
        var r: Rect2 = ROOMS[id]["rect"]
        draw_rect(r.grow(-10.0), Color(0, 0, 0, 0.35), false, 20.0)
    _draw_library()
    _draw_forge()
    _draw_fire()
    if _shown(_station("wellkeeper")):
        Pedestal.draw_well(self, WELL_POS, _time, _highlight.has("wellkeeper"), not Progress.well_saved.is_empty())
    if _shown(_station("trophies")):
        _draw_trophy_wall()
    for s in STATIONS:
        if not _shown(s):
            continue
        match String(s["style"]):
            "plinth":
                _draw_plinth(s)
            "gate":
                _draw_gate(s)
            "wall":
                _draw_wall_marker(s)
            "npc":
                Npc.draw(self, String(s["npc"]), Vector2(s["pos"]), _time, _highlight.has(String(s["id"])))


## Station names, prompts, room names, the trophy count and goals: drawn on the Crisp
## layer so they stay sharp above the post-process pixel grid.
func _draw_texts(cv: CanvasItem) -> void:
    _cv = cv
    for id in ROOMS:
        var r: Rect2 = ROOMS[id]["rect"]
        if id == "chapel" and _shown(_station("trophies")):
            continue   # the goals sit under the plaque
        _text(Vector2(r.get_center().x, r.position.y + 34.0), String(ROOMS[id]["name"]), 22, Color(UiTheme.DIM, 0.8), 400.0)
    if _shown(_station("trophies")):
        var top: float = ROOMS["chapel"]["rect"].position.y
        var n: int = Progress.ACHIEVEMENTS.size()
        var y := top + 14.0
        _text(Vector2(0, y + 10.0), "TROPHIES   %d / %d" % [Progress.achievements_count(), n], 24, LIT, 400.0)
        var goals := goal_rows(3)
        if goals.is_empty():
            _text(Vector2(0, y + 36.0), "Every achievement earned.", 20, UiTheme.BONE, 400.0)
        for i in goals.size():
            draw_goal(cv, Vector2(-280, y + 18.0 + float(i) * 46.0), goals[i], 560.0)
    if not Progress.npc_home("archivist"):
        _text(Vector2(-985, -80), "an empty desk", 20, Color(UiTheme.DIM, 0.7))
    for s in STATIONS:
        if not _shown(s):
            continue
        var p: Vector2 = s["pos"]
        match String(s["style"]):
            "plinth":
                _draw_label_and_prompt(s, p, -76.0)
            "gate":
                _draw_label_and_prompt(s, p, -50.0)
            "npc":
                _draw_npc_label(s, p)
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


## An NPC's name over their head (always, so the room reads at a glance), what they do
## under their feet, and the prompt when someone is close.
func _draw_npc_label(s: Dictionary, base: Vector2) -> void:
    var id := String(s["id"])
    var npc := String(s["npc"])
    var hl := _highlight.has(id)
    var head := base + Vector2(0, -16.0 * Npc.SCALE - 22.0)
    _text(head, Npc.display_name(npc), 24, Npc.color(npc).lerp(Color.WHITE, 0.35 if hl else 0.0), 320.0)
    _text(base + Vector2(0, 26), String(s["sub"]), 20, UiTheme.BONE if hl else UiTheme.DIM, 320.0)
    if hl:
        var pr: Array = _highlight[id]
        var bob := sin(_time * 5.0) * 2.0
        Prompts.draw(_cv if _cv != null else self, head + Vector2(-24, -34.0 + bob), String(pr[0]), String(pr[1]), 24.0)
        _text(head + Vector2(26, -26.0 + bob), String(s["verb"]), 20, Color(0.6, 1.0, 1.0), 80.0)


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


## The Gate: a dark arch cut into the Stair's bottom wall, steps going down, a cold glow.
func _draw_gate(s: Dictionary) -> void:
    var p: Vector2 = s["pos"]
    var bottom: float = ROOMS["stair"]["rect"].end.y
    var c: Color = s["tint"]
    var arch := Rect2(Vector2(-70, bottom - 4.0), Vector2(140, WALL + 4.0))
    draw_rect(arch.grow(6.0), Color(0.25, 0.2, 0.22))
    draw_rect(arch, Color(0.01, 0.01, 0.02))
    for i in 4:
        draw_rect(Rect2(Vector2(-60 + i * 6, bottom + 8.0 + i * 12.0), Vector2(120 - i * 12, 6)), Color(0.18, 0.2, 0.24, 1.0 - 0.2 * i))
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := 220.0 + sin(_time * 1.6) * 16.0
    draw_texture_rect(glow, Rect2(Vector2(-g / 2.0, bottom - g / 2.0), Vector2(g, g)), false, Color(c, 0.18 + (0.12 if _highlight.has("gate") else 0.0)))
    draw_arc(p, 34.0, 0.0, TAU, 40, Color(c, 0.35 + 0.15 * sin(_time * 3.0)), 2.0)
    draw_texture_rect(Art.tile(s["tile"]), Rect2(p + Vector2(-16, -16), Vector2(32, 32)), false, Color(c, 0.85))


## The fire in the middle of the Hollow: a ring of stones, logs, and flames that flicker.
func _draw_fire() -> void:
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := 300.0 + sin(_time * 3.1) * 14.0 + sin(_time * 7.3) * 6.0
    draw_texture_rect(glow, Rect2(FIRE - Vector2(g, g) / 2.0, Vector2(g, g)), false, Color(1.0, 0.55, 0.2, 0.30))
    for i in 10:
        var a := TAU * float(i) / 10.0
        draw_circle(FIRE + Vector2(cos(a) * 30.0, sin(a) * 14.0 + 6.0), 7.0, Color(0.32, 0.29, 0.30))
        draw_circle(FIRE + Vector2(cos(a) * 30.0, sin(a) * 14.0 + 4.0), 5.0, Color(0.46, 0.42, 0.42))
    draw_line(FIRE + Vector2(-22, 8), FIRE + Vector2(20, -2), Color(0.30, 0.18, 0.10), 7.0)
    draw_line(FIRE + Vector2(-18, -2), FIRE + Vector2(22, 8), Color(0.36, 0.22, 0.12), 7.0)
    var cols := [Color(0.85, 0.22, 0.08), Color(1.0, 0.55, 0.12), Color(1.0, 0.88, 0.45)]
    for k in 3:
        var h := (46.0 - 13.0 * float(k)) * (1.0 + 0.12 * sin(_time * 9.0 + float(k) * 2.0))
        var w := 20.0 - 5.0 * float(k)
        var sway := sin(_time * 5.0 + float(k)) * 4.0
        draw_colored_polygon(PackedVector2Array([FIRE + Vector2(-w, 2), FIRE + Vector2(w, 2), FIRE + Vector2(sway * 0.5 + w * 0.4, -h * 0.55), FIRE + Vector2(sway, -h), FIRE + Vector2(sway * 0.5 - w * 0.4, -h * 0.55)]), cols[k])


## The Library: shelves along the top wall, a reading desk where the Archivist works.
func _draw_library() -> void:
    var r: Rect2 = ROOMS["library"]["rect"]
    var spine := [Color(0.45, 0.16, 0.12), Color(0.22, 0.30, 0.20), Color(0.50, 0.40, 0.22), Color(0.20, 0.22, 0.36), Color(0.36, 0.30, 0.28)]
    for sx in [r.position.x + 40.0, r.end.x - 260.0]:
        var shelf := Rect2(sx, r.position.y + 6.0, 220.0, 70.0)
        draw_rect(shelf, Color(0.20, 0.13, 0.08))
        for row in 2:
            var y := shelf.position.y + 6.0 + float(row) * 32.0
            var x := shelf.position.x + 6.0
            var k := int(sx) + row * 7
            while x < shelf.end.x - 10.0:
                var w := 6.0 + float(posmod(k * 13, 5))
                draw_rect(Rect2(x, y + float(posmod(k, 3)), w, 26.0 - float(posmod(k, 3))), spine[posmod(k, spine.size())])
                x += w + 1.0
                k += 1
            draw_rect(Rect2(shelf.position.x, y + 26.0, shelf.size.x, 4.0), Color(0.30, 0.20, 0.12))
    var desk := Rect2(-1045, -150, 110, 44)
    draw_rect(desk.grow(2.0), Color(0.08, 0.05, 0.04))
    draw_rect(desk, Color(0.34, 0.22, 0.13))
    draw_rect(Rect2(desk.position, Vector2(desk.size.x, 6.0)), Color(0.46, 0.31, 0.18))
    draw_rect(Rect2(desk.position + Vector2(18, 8), Vector2(30, 22)), Color(0.86, 0.80, 0.66))
    draw_rect(Rect2(desk.position + Vector2(52, 10), Vector2(26, 20)), Color(0.80, 0.74, 0.60))
    var flame := desk.position + Vector2(100, -4)
    draw_rect(Rect2(flame + Vector2(-3, 0), Vector2(6, 14)), Color(0.9, 0.86, 0.75))
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := 90.0 + sin(_time * 6.0) * 6.0
    draw_texture_rect(glow, Rect2(flame - Vector2(g, g) / 2.0, Vector2(g, g)), false, Color(1.0, 0.8, 0.4, 0.25))
    draw_circle(flame + Vector2(0, -3), 3.0, Color(1.0, 0.85, 0.4))


## The Forge: a cold hearth on the top wall and an anvil; the Smith is not home yet.
func _draw_forge() -> void:
    var r: Rect2 = ROOMS["forge"]["rect"]
    var hearth := Rect2(r.get_center().x - 70.0, r.position.y + 4.0, 140.0, 70.0)
    draw_rect(hearth.grow(4.0), Color(0.22, 0.18, 0.18))
    draw_rect(hearth, Color(0.05, 0.03, 0.03))
    var glow: Texture2D = Art.PARTICLES["light"]
    draw_texture_rect(glow, Rect2(hearth.get_center() - Vector2(70, 50), Vector2(140, 100)), false, Color(0.9, 0.3, 0.1, 0.12 + 0.03 * sin(_time * 1.3)))
    var anvil := Vector2(r.get_center().x, r.end.y - 110.0)
    draw_colored_polygon(PackedVector2Array([anvil + Vector2(-30, -14), anvil + Vector2(34, -14), anvil + Vector2(22, -4), anvil + Vector2(-20, -4)]), Color(0.34, 0.34, 0.38))
    draw_rect(Rect2(anvil + Vector2(-10, -4), Vector2(20, 14)), Color(0.24, 0.24, 0.28))
    draw_rect(Rect2(anvil + Vector2(-18, 10), Vector2(36, 6)), Color(0.20, 0.20, 0.24))


## The Trophy Wall: a plaque on the Chapel's top wall with one tile per achievement, the
## count, and the next three goals with bars written on the floor under it.
func _draw_trophy_wall() -> void:
    var n: int = Progress.ACHIEVEMENTS.size()
    var cols := maxi(1, ceili(float(n) / 2.0))
    var cell := minf(20.0, 600.0 / float(cols))
    var w := cell * float(cols)
    var top: float = ROOMS["chapel"]["rect"].position.y - WALL + 6.0
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


# --- Test hooks --------------------------------------------------------------


func _capture(path: String, wait: float) -> void:
    await get_tree().create_timer(wait).timeout
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png(path)


## `-- --menu-shot`: the hub (as menu.png), each journal tab, mastery, names, options,
## the Gate's loadout screen (classes.png, and loadout_mark.png with a Mark and a Vow
## picked); then quit.
func _menu_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    players[0].global_position = Vector2(-170, -40)
    await _capture("res://autotest/menu.png", 0.8)
    _open(_journal_center, null)
    _journal.set_view("JOURNAL", [])
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
    _class_select.cycle("mark", 1)
    _class_select.cycle("vow", 1)
    _class_select.select_row(1)
    await _capture("res://autotest/loadout_mark.png", 0.4)
    get_tree().quit()


## `-- --themes-shot` ends here (after Main's theme rooms): the sanctum with its ambience
## running for 2 s, saved as res://autotest/theme_sanctum.png, then quit.
func _theme_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    players[0].global_position = Vector2(0, 120)
    await _capture("res://autotest/theme_sanctum.png", 2.0)
    print("[THEME SHOT] sanctum  ambience=%d px" % (ambience.live() if ambience != null else 0))
    get_tree().quit()


## Where a player stands to use a station: in front of it (below), or above the Gate.
func _stand_point(s: Dictionary) -> Vector2:
    var p: Vector2 = s["pos"]
    match String(s["style"]):
        "gate":
            return p + Vector2(0, -46)
        "wall":
            return p + Vector2(0, 50)
    return p + Vector2(0, 48)


## Waypoints from room `a` to room `b` through the doorways (breadth-first), each door as
## a point inside the room, the doorway, and a point inside the next room.
func _route(a: String, b: String) -> Array:
    var prev := { a: "" }
    var queue := [a]
    while not queue.is_empty():
        var cur: String = queue.pop_front()
        if cur == b:
            break
        for d in DOORS:
            var n := ""
            if d["a"] == cur:
                n = String(d["b"])
            elif d["b"] == cur:
                n = String(d["a"])
            if n == "" or prev.has(n):
                continue
            prev[n] = cur
            queue.append(n)
    var chain: Array = [b]
    while String(prev.get(chain[0], "")) != "":
        chain.push_front(prev[chain[0]])
    var pts: Array = [Rect2(ROOMS[a]["rect"]).get_center()]
    for i in range(chain.size() - 1):
        var from: Rect2 = ROOMS[chain[i]]["rect"]
        var to: Rect2 = ROOMS[chain[i + 1]]["rect"]
        for d in DOORS:
            if (d["a"] == chain[i] and d["b"] == chain[i + 1]) or (d["b"] == chain[i] and d["a"] == chain[i + 1]):
                var at: Vector2 = d["at"]
                var dir := to.get_center() - from.get_center()
                dir = Vector2(signf(dir.x), 0) if absf(dir.x) > absf(dir.y) else Vector2(0, signf(dir.y))
                pts.append(at - dir * (WALL + 50.0))
                pts.append(at)
                pts.append(at + dir * (WALL + 50.0))
        pts.append(to.get_center())
    return pts


func _walk_to(target: Vector2) -> bool:
    var p := players[0]
    var pts := _route(room_at(p.global_position), room_at(target))
    pts.append(target)
    for wp in pts:
        var t := 0.0
        while p.global_position.distance_to(wp) > 10.0:
            p.input.force_move = (Vector2(wp) - p.global_position).normalized()
            await get_tree().physics_frame
            t += get_physics_process_delta_time()
            if t > 8.0:
                p.input.force_move = Vector2.ZERO
                print("[HUB-WALK] stuck at (%.0f, %.0f) going to (%.0f, %.0f)" % [p.global_position.x, p.global_position.y, wp.x, wp.y])
                return false
    p.input.force_move = Vector2.ZERO
    return true


## `-- --hub-walk`: walk to every station on show and use it like a player (the interact
## press, then the NPC's service button), checking what opens. Logs [HUB] (what is on
## show), [HUB-TALK] (each line), [HUB-STEP] per station and [HUB-WALK] PASS / FAIL.
## `--hub-shot` (needs a window) saves autotest/hub_<station>.png and _talk captures.
func _hub_walk() -> void:
    var shots := OS.get_cmdline_user_args().has("--hub-shot")
    if shots:
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    await get_tree().create_timer(0.5).timeout
    var on_show: Array = []
    for s in STATIONS:
        if _shown(s):
            on_show.append(s["id"])
    print("[HUB] runs=%d archivist=%s on show: %s" % [Progress.stat("runs_started"), Progress.npc_state("archivist"), ", ".join(on_show)])
    var fresh := Progress.stat("runs_started") == 0
    if fresh:
        var expect := ["keeper", "gatewarden", "gate"]
        print("[HUB-FRESH] %s (expected %s)" % ["PASS" if on_show == expect else "FAIL", ", ".join(expect)])
    # station, service button, what should open
    var plan: Array = [["keeper", "Talents", _mastery_center], ["gatewarden", "Past runs", _ledger_center], ["gate", "", null]]
    if Progress.npc_home("archivist"):
        plan.append(["archivist", "Journal", _journal_center])
        plan.append(["archivist", "Ledger", _ledger_center])
    if Progress.npc_home("wellkeeper"):
        plan.append(["wellkeeper", "", _relic_center])
    if Progress.npc_home("cartographer"):
        plan.append(["cartographer", "World map", _map_center])
    if _settled():
        plan.append_array([["armory", "", _journal_center], ["workshop", "", _options_center], ["mirror", "", _names_center], ["trophies", "", _journal_center]])
    plan.append(["gatewarden", "Descend", null])
    var ok := not fresh or on_show == ["keeper", "gatewarden", "gate"]
    var p := players[0]
    for step in plan:
        var id := String(step[0])
        var s := _station(id)
        if not await _walk_to(_stand_point(s)):
            ok = false
            print("[HUB-STEP] %s FAIL (could not walk there)" % id)
            continue
        await get_tree().create_timer(0.4).timeout
        if shots:
            await _capture("res://autotest/hub_%s.png" % id, 0.2)
        p.input._edges["interact"] = true
        await get_tree().create_timer(0.2).timeout
        var opened := "nothing"
        var good := false
        if s["style"] == "npc":
            if _overlay == _talk_root:
                print("[HUB-TALK] %s: \"%s\"" % [id, _talk_text.text])
                if shots:
                    await _capture("res://autotest/hub_%s_talk.png" % id, 0.2)
                var b := _talk_button(String(step[1]))
                if b != null:
                    b.pressed.emit()
                    await get_tree().create_timer(0.2).timeout
                    if shots and step[2] != null:
                        await _capture("res://autotest/hub_%s_open.png" % id, 0.2)
            if step[2] == null:
                good = _class_select != null
                opened = "loadout" if good else str(_overlay)
            else:
                good = _overlay == step[2]
                opened = _overlay_name()
        elif s["style"] == "gate":
            good = _class_select != null and _loadout_check()
            opened = "loadout" if _class_select != null else _overlay_name()
        else:
            good = _overlay == step[2]
            opened = _overlay_name()
        if _overlay == _journal_center:
            var tabs: Array = []
            for i in (_journal.allowed if not _journal.allowed.is_empty() else range(Journal.TABS.size())):
                tabs.append(Journal.TABS[i])
            opened += " (%s)" % ", ".join(tabs)
        if _overlay == _relic_center:
            var first := _relic_first()
            if first != _relic_back:
                (first as Button).pressed.emit()
                await get_tree().create_timer(0.2).timeout
            opened += " (waiting %d, relics %d)" % [Progress.well_saved.size(), Progress.relics.size()]
        print("[HUB-STEP] %s -> %s %s" % [id + ("/" + String(step[1]) if String(step[1]) != "" else ""), opened, "PASS" if good else "FAIL"])
        ok = ok and good
        if _class_select != null:
            _close_class_select()
        _close_overlay()
        await get_tree().create_timer(0.4).timeout
    print("[HUB-WALK] %s" % ("PASS" if ok else "FAIL"))
    get_tree().quit()


## The Gate's loadout screen, driven like a player: every Mark and Kit is cycled through
## (locked ones must block Descend), a Relic is taken when one is owned, and the Vows are
## cycled. Prints [HUB-LOADOUT]. True when the screen behaves.
func _loadout_check() -> bool:
    var ls := _class_select
    var ok := true
    var open_marks: Array = []
    for i in Loadout.marks().size():
        if Loadout.mark_unlocked(ls.option("mark")):
            open_marks.append(ls.option("mark"))
        elif ls.blocked_slot() != "mark":
            ok = false
        ls.cycle("mark", 1)
    var open_kits := 0
    for i in Loadout.KITS.size():
        if Loadout.kit_unlocked(ls.option("kit")):
            open_kits += 1
        ls.cycle("kit", 1)
    var vows: Array = []
    for i in Loadout.VOWS.size():
        vows.append(ls.option("vow"))
        ls.cycle("vow", 1)
    var relic := ""
    if not Progress.relics.is_empty():
        ls.cycle("relic", 1)
        relic = ls.option("relic")
        ok = ok and relic == String(Progress.relics[0])
    ok = ok and ls.blocked_slot() == ""
    print("[HUB-LOADOUT] marks open %d / %d (%s), kits open %d / %d, relic %s, vows %s, current %s %s" % [
        open_marks.size(), Loadout.marks().size(), ",".join(open_marks), open_kits, Loadout.KITS.size(),
        relic if relic != "" else "-", ",".join(vows), ls.current(), "PASS" if ok else "FAIL"])
    return ok


func _overlay_name() -> String:
    if _overlay == null:
        return "nothing"
    for pair in [[_relic_center, "relics"], [_map_center, "map"], [_mastery_center, "talents"], [_ledger_center, "ledger: " + (_ledger_title.text if _ledger_title != null else "")], [_journal_center, "journal"], [_options_center, "options"], [_names_center, "names"], [_talk_root, "talk"], [_esc_center, "menu"]]:
        if _overlay == pair[0]:
            return String(pair[1])
    return "?"


func _players_count() -> int:
    var n := 0
    for c in get_children():
        if c is Player:
            n += 1
    return maxi(1, n)
