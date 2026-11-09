class_name Main
extends Node2D
## Run orchestrator: players, floors, the current room, scrap, camera, HUD,
## couch co-op joins, and the self-test bot.

const MAX_PLAYERS := 4
const FLOORS := Regions.DEPTHS   # one region per depth (Regions)
const CAMERA_PAD := 90.0

var players: Array[Player] = []
var fx: Fx
var hud: Hud
var danger: DangerFx   # hit flashes and the low-health edge (danger_fx.gd)
var camera: PixelCamera
var pause_menu: PauseMenu
var levelup: LevelUpScreen
var gun_pick: GunPickScreen
var _pending_levelups: Array = []
var _shake := 0.0

## The depth of the region the party is in (1 to FLOORS): drives difficulty, prices and
## floor size. The region itself (`region_id`, see Regions) sets the theme, boss and layouts.
var floor_number := 0
var region_id := ""
var route: Array = []          # region ids this run has entered, top first
var _planned_route: Array = [] # bots: --route=a,b,c, or the random way down to --start-floor
var _door_choice := ""          # the region behind the stairs door the party took (Room "stairs")
## This floor's shortcut gate (Shortcuts.plan), {} if none.
var gate: Dictionary = {}
var _floor_t0 := 0.0            # _clock at floor start ([TRAVEL] lines)
var _boss_room_at := -1.0       # _clock when the party first entered this floor's boss room
var _rush := false              # bots: --rush walks straight for the boss room
var _open_gates := false        # bots: --open-gates walks through a shortcut gate from its far side
var _gate_entry := Vector2i.ZERO  # the side a gate brings the party in by (enter_room)
var _bot_doors := {}            # bots: depth -> the door picked for it
var rooms: Dictionary = {}          # Vector2i -> RoomData
var current: Room = null
var current_pos := Vector2i.ZERO
var scrap := 0
var rooms_cleared := 0
var floor_rooms_cleared := 0   # difficulty creeps within a floor, resets at the stairs
var _paused_secs := 0.0
var _perf_probe := OS.get_cmdline_user_args().has("--perf")
var _perf_t := 2.0
var _perf_lines := OS.get_cmdline_user_args().has("--perf-lines")
var _bot_idle_fights := false
var _probe: BalanceProbe = null   # --dps-probe (scripts/balance_probe.gd)
var _probe_started := false
var bot_paused := false   # a capture (PayoutShot) drives the player instead of the bot
var _hitstop_left := 0.0
var _ticker: Node
var _flash_rect: ColorRect
var _flash_life := 0.0
var _flash_fade := 0.0
var total_kills := 0
var game_over := false
var victory := false
var show_help := false   # F1 toggles the control strip; prompts live on the things themselves
var message := ""
var _message_time := 0.0
var _joined_devices: Dictionary = {}
var _transitioning := false
var _room_entered_ms := 0
var _room_entered_t := 0.0   # game time of the last room entry (bots: survives --fixed-fps fast-forward)

# Self-test: `godot --path . -- --autotest` plays by itself, saves screenshots to
# res://autotest/ and prints progress. Used to verify builds without a human.
var autotest := false
## The Torn Bestiary Page this run: "" (none yet), "dropped", "carried" or "given".
var page_state := ""
var _recruit_probe := false
## Items dropped in a Well this run (Loadout): saved for the Wellkeeper when the run ends.
var well_items: Array = []
var _well_probe := false
var well_screen: WellScreen
## Balance probe `--old-balance`: the late-floor tuning of 2026-11-05 off (uncapped Leech,
## formula bosses without the rally, old floor damage), for like-for-like bot comparisons.
static var old_balance := false
var _clock := 0.0
var _bot_idle := 0.0
var _bot_obstacle_time := 0.0
var _bot_skip: Dictionary = {}
var _bot_tried: Dictionary = {}   # item and gun ids already taken once this run
var _shots_taken: Dictionary = {}
var _reaction_counts: Dictionary = {}
var _fusion_counts: Dictionary = {}   # fusion / cataclysm name -> times fired this run


func _ready() -> void:
    randomize()
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--seed="):
            seed(int(a.substr(7)))   # a fixed run for before/after captures (clarity_shot.gd)

    fx = Fx.new()
    fx.main = self
    add_child(fx)

    camera = PixelCamera.new()
    camera.follow_speed = 7.0
    camera.zoom = Vector2(1.3, 1.3)
    add_child(camera)
    camera.make_current()

    RenderingServer.set_default_clear_color(Art.CLEAR)

    add_child(PostFx.new())
    danger = DangerFx.new(self)
    add_child(danger)   # layer 3 like the HUD, added first: draws under it
    var layer := CanvasLayer.new()
    layer.layer = 3   # over the PostFx (1) and the Crisp world-text layer (2)
    add_child(layer)
    hud = Hud.new()
    hud.main = self
    layer.add_child(hud)
    pause_menu = PauseMenu.new(self)
    add_child(pause_menu)
    levelup = LevelUpScreen.new(self)
    add_child(levelup)
    gun_pick = GunPickScreen.new(self)
    add_child(gun_pick)
    well_screen = WellScreen.new()
    add_child(well_screen)

    var args := OS.get_cmdline_user_args()
    autotest = args.has("--autotest")
    _recruit_probe = autotest and args.has("--recruit-probe")
    _well_probe = autotest and args.has("--well-probe")
    _rush = autotest and args.has("--rush")
    _open_gates = autotest and args.has("--open-gates")
    Enemy.spawn_log = autotest   # [SPAWN-MOVED] / [SPAWN-CLOSE] lines (Enemy.EMERGE_SECS)
    old_balance = autotest and args.has("--old-balance")
    Regions.activate("")
    Regions.reset_stats()
    Regions.exposed_enabled = not (autotest and args.has("--no-exposed"))
    if autotest:
        # Fresh, separate save so the bot never touches the real one. `--veteran` unlocks
        # every gun and class first, to measure a player whose pool is wide open.
        Progress.save_path = "user://save_autotest%s.json" % _instance_tag()
        # Bots never write the player's own records: a separate file per instance (or
        # runs_bot.jsonl without --instance), loaded fresh so no human runs are copied in.
        Telemetry.use_file("user://telemetry/runs%s.jsonl" % (_instance_tag() if _instance_tag() != "" else "_bot"))
        if args.has("--keep-save"):
            Progress.load_save()   # this instance's save from its last run (shortcut persistence)
        else:
            Progress.reset()
        if args.has("--shortcuts=all"):
            for sid in Shortcuts.DEFS.keys():
                Progress.open_shortcut(String(sid))
        # The bot never uses the player's real Shrine: a throwaway file, empty unless
        # --mastery=N or --mastery=full buys ranks on it. Runs still pay Embers into it,
        # so the [EMBERS] line measures income.
        Mastery.save_path = "user://mastery_autotest%s.json" % _instance_tag()
        Mastery.reset()
        var probe_side := "a"
        for a in args:
            if a.begins_with("--mastery-side="):
                probe_side = "b" if a.substr(15) == "b" else "a"
        for a in args:
            if a.begins_with("--mastery="):
                # Balance probe. "full": every rank of both sides of every talent and the
                # whole survival track, side A active (B with --mastery-side=b). "N":
                # spend N Embers cheapest-first on the survival track and active sides.
                var spec := a.substr(10)
                var left := 0
                if spec == "full":
                    Mastery.debug_max_all(probe_side)
                else:
                    left = Mastery.debug_spend_greedy(int(spec), probe_side)
                var power: Dictionary = Mastery.current_power()
                var talents: Array = []
                for t in Mastery.active_summary():
                    talents.append("%s:%s%d" % [t["slot"], t["side"], int(t["rank"])])
                print("[MASTERY] %s: spent %d, left %d, survival %d, talents %s, power dmg-eq +%.1f%% hp-eq +%.0f" % [
                    spec, Mastery.spent(), left, Mastery.survival, " ".join(talents), float(power["dmg"]) * 100.0, float(power["hp"])])
        if args.has("--veteran"):
            for gid in Guns.all_ids():
                Progress.unlocks["gun:" + gid] = true
            for m in Loadout.marks():
                Progress.unlocks["mark:" + str(m["id"])] = true
            for k in Loadout.KITS:
                if String(k) != "":
                    Progress.unlocks["kit:" + String(k)] = true
            print("[VETERAN] pool: %d guns" % Guns.ids().size())
        # The bot plays the Unmarked with a bare Kit unless told otherwise. `--class=<old
        # class>` is that class's Kit and Mark (`-- --autotest --class=pyromancer`);
        # `--kit=<gun>`, `--mark=<id>`, `--relic=<item>` and `--vow=<id>` set one slot.
        var build := _bot_build()
        Progress.loadout = Loadout.from_class(String(build.get("class", "vagrant")))
        for a in args:
            if a.begins_with("--class="):
                Progress.loadout = Loadout.from_class(a.substr(8))
        for a in args:
            for slot in ["kit", "mark", "relic", "vow"]:
                if a.begins_with("--%s=" % slot):
                    Progress.loadout[slot] = a.substr(slot.length() + 3)
        # The bot's throwaway save opens what it asks for (Mark and Kit unlocks feed no pool).
        Progress.unlocks["mark:" + String(Progress.loadout.get("mark", "vagrant"))] = true
        if String(Progress.loadout.get("kit", "")) != "":
            Progress.unlocks["kit:" + String(Progress.loadout["kit"])] = true
        if Progress.loadout.get("relic", "") != "" and not Progress.relics.has(Progress.loadout["relic"]):
            Progress.relics.append(Progress.loadout["relic"])   # the bot owns the Relic it asks for
        print("[GATE-LOADOUT] kit=%s mark=%s relic=%s vow=%s  instance=%s" % [Progress.loadout.get("kit", ""), Progress.loadout.get("mark", ""),
            Progress.loadout.get("relic", ""), Progress.loadout.get("vow", ""), _instance_tag().trim_prefix("_")])
    var pads := Input.get_connected_joypads()
    _spawn_player(0 if pads.has(0) else -1, true)
    Input.joy_connection_changed.connect(_on_joy_connection_changed)

    Elements.reaction_fired.connect(_count_reaction)
    Elements.fusion_fired.connect(_on_fusion)
    Progress.unlocked.connect(_on_unlocked)
    if args.has("--obstacle-test") or args.has("--start-shot") or args.has("--layouts-shot") or args.has("--themes-shot"):
        # Test hooks never touch the real save.
        Progress.save_path = "user://save_autotest.json"
        Progress.reset()
    if autotest:
        _setup_autotest()
        if GunProbe.wanted():
            add_child(GunProbe.new(self))   # per-gun dps probe (scripts/gun_probe.gd)

    Settings.apply()
    if autotest and OS.get_cmdline_user_args().has("--uncapped"):
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # perf probe: measure past the refresh rate
    show_help = Settings.flag("controls_hint")
    Progress.start_run()
    Telemetry.run_start(self)
    Music.play("run")
    Items.new_run()
    start_floor(_bot_start_floor() if autotest else 1)
    if OS.get_cmdline_user_args().has("--obstacle-test"):
        _obstacle_test()
    if OS.get_cmdline_user_args().has("--layouts-shot"):
        _layouts_shot()
    if OS.get_cmdline_user_args().has("--themes-shot"):
        _themes_shot()
    if OS.get_cmdline_user_args().has("--start-shot"):
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
        await get_tree().create_timer(0.8).timeout
        await _screenshot("res://autotest/start.png")
        Art.debug_icon_sheet("res://autotest/icons.png")
        FigureGen.debug_sheet("res://autotest/figures.png")
        # Stand next to the first pedestal to show the prompt, once per device kind.
        if current != null and not current.pedestals.is_empty():
            var ped: Pedestal = current.pedestals[0]
            players[0].global_position = ped.global_position + Vector2(0, 30)
            players[0].input.lock_kind = true
            players[0].input.last_kind = "kb"
            await get_tree().create_timer(0.3).timeout
            await _screenshot("res://autotest/prompt_kb.png")
            players[0].input.last_kind = "pad"
            await get_tree().create_timer(0.3).timeout
            await _screenshot("res://autotest/prompt_pad.png")
            players[0].input.last_kind = "kb"
            players[0].input.lock_kind = false
        # Interact edge test: one simulated press must equip exactly once, even when
        # several rendered frames pass before the next physics tick.
        if current != null and not current.pedestals.is_empty():
            var p0 := players[0]
            p0.equip("bone_ring")
            p0.input._edges["interact"] = true
            var ped0: Pedestal = current.pedestals[0]
            p0.global_position = ped0.global_position
            current._handle_interact()
            current._handle_interact()
            print("[INTERACT TEST] guns=%d edges_left=%s" % [p0.guns.size(), str(p0.input._edges)])
        # The level-up picker.
        players[0].level = 2
        levelup.open(players[0])
        await get_tree().create_timer(0.6).timeout
        await _screenshot("res://autotest/levelup.png")
        get_tree().paused = false
        levelup.visible = false
        # Special rooms, for checking their dressing.
        for t in [RoomData.Type.SHOP, RoomData.Type.TREASURE, RoomData.Type.CHALLENGE, RoomData.Type.HIDDEN]:
            for pos in rooms.keys():
                if rooms[pos].type == t:
                    enter_room(pos, Vector2i.ZERO)
                    players[0].global_position = Vector2(0, 120)
                    await get_tree().create_timer(0.5).timeout
                    await _screenshot("res://autotest/room_%s.png" % rooms[pos].type_name().to_lower().replace(" ", "_"))
                    break
        get_tree().quit()


## Debug capture: `godot --path . -- --layouts-shot` (fresh test save) builds every room
## layout once in a cleared arena and every puzzle kind once (plus a secret wall and a
## secret alcove), saves res://autotest/layout_<name>.png and secret_<kind>.png, then quits.
func _layouts_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    await get_tree().create_timer(0.5).timeout
    var shots: Array = []
    for lname in RoomLayouts.ALL:
        shots.append({ "file": "layout_" + String(lname), "layout": lname, "size": maxi(1, RoomLayouts.min_size(lname)) })
    for k in Secrets.ORDER:
        shots.append({ "file": "secret_" + String(k), "layout": "open", "secret": k, "size": 1 })
    shots.append({ "file": "secret_wall", "layout": "open", "size": 1, "wall": true })
    shots.append({ "file": "secret_alcove", "layout": "open", "size": 1, "alcove": true })
    var centre := Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2)
    for shot in shots:
        rooms = _shot_rooms(centre, shot)
        enter_room(centre, Vector2i.ZERO)
        for pl in players:
            pl.global_position = Vector2.ZERO
        # Fit the whole room and its walls in the frame.
        var vp := get_viewport().get_visible_rect().size
        var span := current.rect.size + Vector2.ONE * (2.0 * Room.WALL + 80.0)
        var z := minf(vp.x / span.x, vp.y / span.y)
        camera.zoom = Vector2(z, z)
        camera.limit_left = -100000
        camera.limit_top = -100000
        camera.limit_right = 100000
        camera.limit_bottom = 100000
        camera.target = Vector2.ZERO
        camera.snap_now()
        await get_tree().create_timer(0.7).timeout
        await _screenshot("res://autotest/%s.png" % shot["file"])
        print("[LAYOUT SHOT] %s  layout=%s size=%s secret=%s alcove=%s blockers=%s" % [shot["file"], current.layout_name, current.room_size, current.data.secret, current.data.alcove, current.has_blockers])
    get_tree().quit()


## Review capture: `godot --path . -- --themes-shot` (fresh test save) builds one cleared
## arena per floor theme (Themes.ORDER) at the run's zoom, with a layout that shows the
## theme's water, walls or chasms, lets its ambience run for 2 s, saves
## res://autotest/theme_<name>.png, then opens the hub, which saves theme_sanctum.png and
## quits (see Hub).
func _themes_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    await get_tree().create_timer(0.5).timeout
    var layouts := { "crypt": "four_pillars", "ruins": "flooded", "frozen": "frozen", "forge": "broken", "void": "rift" }
    var centre := Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2)
    for i in Themes.ORDER.size():
        var tname := String(Themes.ORDER[i])
        floor_number = i + 1
        region_id = Regions.for_theme(tname)
        rooms = _shot_rooms(centre, { "layout": String(layouts.get(tname, "open")), "size": 1 })
        enter_room(centre, Vector2i.ZERO)
        for pl in players:
            pl.global_position = Vector2(0, 60)
        camera.target = Vector2.ZERO
        camera.snap_now()
        await get_tree().create_timer(2.0).timeout
        await _screenshot("res://autotest/theme_%s.png" % tname)
        print("[THEME SHOT] %s  layout=%s  ambience=%d px" % [tname, current.layout_name, current.ambience.live() if current.ambience != null else 0])
    get_tree().change_scene_to_file("res://scenes/hub.tscn")


## A cleared arena at `centre` with a plain door on every side (one a secret wall, for the
## "wall" shot), shaped as `shot` asks.
func _shot_rooms(centre: Vector2i, shot: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var r := RoomData.new()
    r.pos = centre
    r.type = RoomData.Type.ARENA
    r.cleared = true
    r.size_class = int(shot.get("size", 1))
    r.layout = String(shot.get("layout", "open"))
    r.layout_seed = 1234567
    r.secret = String(shot.get("secret", ""))
    r.alcove = bool(shot.get("alcove", false))
    out[centre] = r
    for d in FloorGen.DIRS:
        var n := RoomData.new()
        n.pos = centre + d
        n.type = RoomData.Type.ARENA
        n.doors[-d] = { "to": centre, "obstacle": "" }
        out[centre + d] = n
        r.doors[d] = { "to": centre + d, "obstacle": "" }
    if bool(shot.get("wall", false)):
        r.doors[Vector2i.RIGHT] = { "to": centre + Vector2i.RIGHT, "obstacle": "secret", "secret": "roots" }
        (out[centre + Vector2i.RIGHT] as RoomData).type = RoomData.Type.HIDDEN
    return out


## Headless check that projectiles hit obstacles: `godot --headless --path . -- --obstacle-test`
func _obstacle_test() -> void:
    var ob := Obstacle.new("pool", Vector2(60, 150), Vector2.RIGHT)
    ob.position = Vector2(300, 0)
    current.add_child(ob)
    var e := Enemy.new()
    e.configure("grunt", 1)
    e.position = Vector2(300, 300)
    current.enemies.add_child(e)
    for y in [0.0, 300.0]:
        var p := Projectile.new()
        p.velocity = Vector2(600, 0)
        p.element = Element.Kind.ICE
        p.damage = 1.0
        p.potency = 1.0
        p.lifetime = 1.0
        p.position = Vector2(100, y)
        p.body_entered.connect(func(b): print("  projectile at y=%d entered %s" % [y, b.get_class() if not b is Obstacle else "Obstacle"]))
        add_child(p)
    await get_tree().create_timer(1.2).timeout
    print("[OBSTACLE TEST] obstacle alive=%s  enemy states=%s" % [is_instance_valid(ob), e.states if is_instance_valid(e) else "dead"])
    get_tree().quit()


func _on_unlocked(unlock_id: String, achievement_name: String) -> void:
    if unlock_id == "":
        hud.toast("Achievement: %s" % achievement_name)
        Sfx.play("unlock")
        return
    var what := Progress.unlock_label(unlock_id)
    hud.toast("%s: unlocked %s" % [achievement_name, what])
    Sfx.play("unlock")


func _end_run(won: bool) -> void:
    # Embers first, so telemetry and the history line can carry the payout. The bot pays
    # into its throwaway Shrine file (see _ready).
    var award: Dictionary = Mastery.award(floor_number, won, String(Loadout.current()["mark"]))
    var gained := int(award.get("total", 0))
    Telemetry.run_end(self, won, award)
    Progress.keep_well_items(well_items)
    if autotest and not well_items.is_empty():
        print("[WELL] saved for the Wellkeeper: %s" % ", ".join(well_items))
    var killer := "" if won else Lessons.killer_key(region_id, current != null and current.data.type == RoomData.Type.BOSS)
    Progress.end_run(won, floor_number, total_kills, gained, region_id, killer)
    if autotest and killer != "":
        print("[LESSON] killer=%s deaths=%d new=%s unlocks=%s" % [killer, int(Progress.lessons.get(killer, 0)), Progress.run_lesson != "", ",".join(Progress.run_unlocks)])
    if gained > 0:
        announce("+%d Embers" % gained)
    if autotest:
        print("[EMBERS] +%d (%s)  bank %d" % [gained, Mastery.award_text(award), Mastery.embers])
    Music.play("ambient", 2.5)
    if not autotest:
        get_tree().create_timer(1.6).timeout.connect(pause_menu.show_menu)


func shake(amount: float) -> void:
    _shake = maxf(_shake, amount * Settings.shake_mult())


## The show grows over a run: tame on the first floor, the full display on the last.
## Only presentation reads this (particle counts, flashes, ripples), never gameplay.
var spectacle_override := -1.0


func spectacle_value() -> float:
    if spectacle_override >= 0.0:
        return spectacle_override
    var guns := 0
    for p in players:
        guns = maxi(guns, p.guns.size())
    return clampf(0.35 + 0.14 * float(floor_number - 1) + 0.03 * float(floor_rooms_cleared) + 0.004 * float(difficulty()) + 0.05 * float(maxi(0, guns - 1)), 0.35, 1.3)


func _update_spectacle() -> void:
    if fx != null and fx.has_method("set_spectacle"):
        fx.set_spectacle(spectacle_value())


## Hit-stop: freeze the world for a beat on a big moment (unscaled, HUD keeps drawing).
func hitstop(secs: float, scale: float = 0.05) -> void:
    if secs <= 0.0 or not Settings.flag("hit_stop") or get_tree().paused:
        return
    if _ticker == null:
        _ticker = FeedbackTicker.new()
        _ticker.main = self
        _ticker.process_mode = Node.PROCESS_MODE_ALWAYS
        add_child(_ticker)
    _hitstop_left = maxf(_hitstop_left, secs)
    Engine.time_scale = scale


## Bot, probe and capture runs: any user argument after `--` (or `--autotest` anywhere).
## Every autoload checks this in its own _ready, before its first load, so such a run never
## reads or writes the player's settings.json, save.json, mastery.json or runs.jsonl.
static func bot_run() -> bool:
    return not OS.get_cmdline_user_args().is_empty() or OS.get_cmdline_args().has("--autotest")


## Parallel bot runs: `--instance=N` gives each its own save, mastery and telemetry files
## (and `--audio-driver Dummy` on the command line keeps them silent).
static func _instance_tag() -> String:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--instance="):
            return "_" + a.substr(11)
    return ""


## Hit-stop and flash run on real time in a node that keeps processing while the tree is
## paused: a menu that opens mid hit-stop (the boss dies, a level-up pops) must never be
## left in slow motion, which made its grace timer crawl and blocked every pick.
class FeedbackTicker extends Node:
    var main: Main
    func _process(delta: float) -> void:
        main._tick_feedback(delta / maxf(Engine.time_scale, 0.001))


func _tick_feedback(real_delta: float) -> void:
    if _hitstop_left > 0.0:
        _hitstop_left -= real_delta
        if _hitstop_left <= 0.0 or get_tree().paused:
            _hitstop_left = 0.0
            Engine.time_scale = 1.0
    elif Engine.time_scale != 1.0 and get_tree().paused:
        Engine.time_scale = 1.0
    if _flash_rect != null and _flash_rect.color.a > 0.0:
        _flash_rect.color.a = maxf(0.0, _flash_rect.color.a - _flash_fade * real_delta)


## A full-screen tinted flash that fades out; strength is the starting alpha. With the
## "Screen flashes" option off it is a third as strong and fades twice as slowly.
func flash(color: Color, strength: float = 0.5, life: float = 0.25) -> void:
    if not Settings.flag("flashes"):
        strength *= 0.3
        life *= 2.0
    if _ticker == null:
        _ticker = FeedbackTicker.new()
        _ticker.main = self
        _ticker.process_mode = Node.PROCESS_MODE_ALWAYS
        add_child(_ticker)
    if _flash_rect == null:
        var layer := CanvasLayer.new()
        layer.layer = 90
        layer.process_mode = Node.PROCESS_MODE_ALWAYS
        add_child(layer)
        _flash_rect = ColorRect.new()
        _flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
        _flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _flash_rect.color = Color(color, 0.0)
        layer.add_child(_flash_rect)
    _flash_rect.color = Color(color, clampf(maxf(strength, _flash_rect.color.a), 0.0, 0.85))
    _flash_life = life
    _flash_fade = _flash_rect.color.a / maxf(life, 0.01)


func is_device_joined(device: int) -> bool:
    return _joined_devices.has(device)


# --- Floors and rooms --------------------------------------------------------


func start_floor(n: int) -> void:
    if autotest and floor_number > 0:
        print("[HAZARD] region=%s gas_lit=%d zapped=%d" % [region_id, Materials.stat_gas_lit, Materials.stat_zapped])
        Materials.stat_gas_lit = 0
        Materials.stat_zapped = 0
    if autotest and OS.get_cmdline_user_args().has("--one-floor") and floor_number > 0 and n > floor_number:
        # Balance probe: one floor per instance, so late floors can be measured in parallel.
        print("[FLOOR] %d (%s) reached at t=%.0f hp=%.0f/%.0f level=%d: --one-floor stops here" % [n, _next_region(n), _clock, players[0].hp, players[0].max_hp, players[0].level])
        Telemetry.floor_start(self)
        _print_stats("END")
        get_tree().quit()
        return
    floor_number = n
    region_id = _next_region(n)
    _door_choice = ""
    route.append(region_id)
    Regions.activate(region_id)
    Music.set_floor(n)
    floor_rooms_cleared = 0
    _arena_dps = []
    if autotest and not players.is_empty():
        print("[FLOOR] %d region=%s at t=%.0f kills=%d scrap=%d hp=%.0f level=%d guns=%d items=%d" % [
            n, region_id, _clock, total_kills, scrap, players[0].hp, players[0].level, players[0].guns.size(), players[0].equipment.size()])
    Telemetry.floor_start(self)
    rooms = FloorGen.generate(region_id, party_luck(), players)
    _place_archivist()
    _place_well()
    gate = Shortcuts.plan(rooms, region_id)
    if autotest and region_id == String(Shortcuts.DEFS[Shortcuts.SLUICE]["region"]):
        print("[SLUICE] floor=%d region=%s drained=%s" % [floor_number, region_id, str(Shortcuts.drained(region_id))])
    _floor_t0 = _clock
    _boss_room_at = -1.0
    _scout_reveal()
    for p in players:
        p.pressure = 0.0
        if not p.alive:
            p.alive = true
            p.add_to_group("players")
        p.hp = maxf(p.hp, p.max_hp * (0.6 if n <= 2 else 0.4))   # deeper stairs patch you up less
    enter_room(Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2), Vector2i.ZERO)
    announce(Regions.display_name(region_id))
    if autotest and OS.get_cmdline_user_args().has("--boss-only"):
        # Boss probe: straight into the floor's boss room. `--boss-dps=N` stands in for the
        # arena output a real floor would have measured (it sizes the boss from depth 2).
        for a in OS.get_cmdline_user_args():
            if a.begins_with("--boss-dps="):
                _arena_dps = [float(a.substr(11))]
        for rp in rooms.keys():
            if (rooms[rp] as RoomData).type == RoomData.Type.BOSS:
                rooms[rp].visited = true
                enter_room(rp, Vector2i.ZERO)
                break


## The region the party enters at depth `n`: the door it took, else the planned route if
## there is one, the top region at depth 1, else a random built region one edge down.
func _next_region(n: int) -> String:
    if _door_choice != "" and n > 1:
        return _door_choice
    if _planned_route.size() >= n:
        return String(_planned_route[n - 1])
    if n <= 1 or region_id == "":
        return Regions.FIRST
    var next := Regions.pick_next(region_id)
    return next if next != "" else region_id


## Shrine Scout talents: Cartographer shows the shop (1), treasure (2) and boss (3) rooms on
## the map from the start of a floor; Dowser shows hidden rooms (1) and rooms holding a
## puzzle or an alcove (2).
func _scout_reveal() -> void:
    var reveal := int(Mastery.bonus("reveal_rooms"))
    var dowse := int(Mastery.bonus("reveal_secrets"))
    if reveal <= 0 and dowse <= 0:
        return
    for r in rooms.values():
        var rd: RoomData = r
        match rd.type:
            RoomData.Type.SHOP:
                rd.discovered = rd.discovered or reveal >= 1
            RoomData.Type.TREASURE:
                rd.discovered = rd.discovered or reveal >= 2
            RoomData.Type.BOSS:
                rd.discovered = rd.discovered or reveal >= 3
            RoomData.Type.HIDDEN:
                rd.discovered = rd.discovered or dowse >= 1
        if dowse >= 2 and (rd.secret != "" or rd.alcove):
            rd.discovered = true


## Load the room at `pos`. `moved` is the direction the party travelled to get there,
## or ZERO when dropped in (floor start).
func enter_room(pos: Vector2i, moved: Vector2i) -> void:
    _transitioning = false
    _room_entered_ms = Time.get_ticks_msec()
    _room_entered_t = _clock
    if autotest and rooms.has(pos):
        var vis: Array = []
        for rp in rooms.keys():
            if rooms[rp].visited:
                vis.append(rp)
        print("[BOT] enter %s (%s) moved=%s visited=%s doors=%s" % [pos, rooms[pos].type_name(), moved, str(vis), str(rooms[pos].doors)])
    Sfx.stop_all()
    if current != null:
        # Spoils nobody chose are salvaged (and said so), never lost silently.
        current.salvage_spoils("left")
        if autotest and current.cleared_at >= 0.0 and current.data.type == RoomData.Type.ARENA:
            print("[DWELL] floor=%d secs=%.1f peds_left=%d" % [floor_number, _clock - current.cleared_at, current._floor_pedestals()])
        Telemetry.room_exit(current)
        current.collect_all_scrap()
        remove_child(current)
        current.queue_free()
    for c in get_children():
        if c is Projectile:
            c.queue_free()

    current_pos = pos
    if _boss_room_at < 0.0 and rooms.has(pos) and rooms[pos].type == RoomData.Type.BOSS:
        _boss_room_at = _clock
        if autotest:
            print("[TRAVEL] floor=%d region=%s boss_room_after=%.1f gate=%s" % [floor_number, region_id, _clock - _floor_t0, "open" if not gate.is_empty() and Shortcuts.is_open(String(gate["id"])) else ("closed" if not gate.is_empty() else "none")])
    Elements.room_reset()
    if autotest and not players.is_empty():
        _arena_snap = [_clock, players[0].hp, players[0].hurt_total, players[0].healed_total, players[0].healed_leech, players[0].healed_regen]
    current = Room.new(rooms[pos], self)
    add_child(current)
    _update_spectacle()
    move_child(current, 0)
    current.door_entered.connect(_on_door_entered)
    if autotest and _perf_probe:
        print("[ROOM] %s layout=%s size=%s" % [pos, current.layout_name, current.room_size])

    # Through a gate the party comes in by the gate's own wall, not the opposite one.
    var side := _gate_entry if _gate_entry != Vector2i.ZERO else -moved
    _gate_entry = Vector2i.ZERO
    var base := Vector2.ZERO if moved == Vector2i.ZERO else current.entry_position(side)
    var across := Vector2(side).orthogonal() if moved != Vector2i.ZERO else Vector2.RIGHT
    for i in players.size():
        players[i].global_position = base + across * (float(i) - float(players.size() - 1) / 2.0) * 40.0
        players[i].invuln = maxf(players[i].invuln, 0.8)   # a breath after a door, never a cheap hit
        players[i].velocity = Vector2.ZERO

    var r := current.rect.grow(Room.WALL + CAMERA_PAD)
    camera.limit_left = int(r.position.x)
    camera.limit_top = int(r.position.y)
    camera.limit_right = int(r.end.x)
    camera.limit_bottom = int(r.end.y)
    camera.target = _party_center()
    camera.snap_now()


func _on_door_entered(dir: Vector2i) -> void:
    if _transitioning:
        return
    if Time.get_ticks_msec() - _room_entered_ms < 350:
        if autotest:
            print("[DOOR] ignored a door event %d ms after entering the room" % (Time.get_ticks_msec() - _room_entered_ms))
        return
    _transitioning = true
    call_deferred("enter_room", door_target(dir), dir)


## The room behind this room's door on side `dir`. A shortcut gate (Shortcuts) leads to a
## room that is not next door; walking through one from the far side opens it for good.
func door_target(dir: Vector2i) -> Vector2i:
    var door: Dictionary = rooms[current_pos].doors.get(dir, {})
    var to: Vector2i = door.get("to", current_pos + dir)
    if door.has("gate") and rooms.has(to):
        _gate_entry = door.get("back", -dir)
        var back: Dictionary = rooms[to].doors.get(_gate_entry, {})
        if String(back.get("obstacle", "")) == Shortcuts.OBSTACLE:
            back["obstacle"] = ""
            var id := String(door["gate"])
            if Progress.open_shortcut(id):
                announce("Shortcut opened: %s" % Shortcuts.display_name(id))
                Sfx.play("confirm")
                Telemetry.event("shortcut_opened", { "id": id, "floor": floor_number })
                if autotest:
                    print("[SHORTCUT] opened %s at t=%.0f" % [id, _clock])
        elif autotest:
            print("[SHORTCUT] through %s at t=%.0f" % [String(door["gate"]), _clock])
    return to


## Bots: health at room entry, then lost and healed since ([ARENA] lines at clear and death).
var _arena_snap: Array = []


func _print_arena(tag: String) -> void:
    if not autotest or players.is_empty() or _arena_snap.size() < 6 or current == null:
        return
    var p: Player = players[0]
    print("[ARENA] %s floor=%d room=%s secs=%.0f level=%d max=%.0f hp_in=%.0f hp_out=%.0f lost=%.0f healed=%.0f (leech %.0f regen %.0f) low=%.2f leech=%.0f regen=%.1f armor=%.0f guns=%d guards=%d" % [
        tag, floor_number, current.data.type_name(), _clock - float(_arena_snap[0]), p.level, p.max_hp,
        float(_arena_snap[1]), p.hp, p.hurt_total - float(_arena_snap[2]), p.healed_total - float(_arena_snap[3]), p.healed_leech - float(_arena_snap[4]), p.healed_regen - float(_arena_snap[5]), current.low_hp,
        p.stat("lifesteal"), p.stat("regen"), p.stat("armor"), p.guns.size(), p.burst_guards])


func on_room_cleared(_room: Room) -> void:
    _print_arena("clear")
    rooms_cleared += 1
    Progress.add("rooms")
    floor_rooms_cleared += 1
    _update_spectacle()
    announce("Room cleared")


## Down the stairs; `to` is the region behind the door taken ("" at the bottom).
func next_floor(to: String = "") -> void:
    # Shortcuts never skip bosses (design section 8): the way down only exists once this
    # floor's boss room is cleared.
    var boss_done := false
    for rp in rooms.keys():
        if (rooms[rp] as RoomData).type == RoomData.Type.BOSS:
            boss_done = (rooms[rp] as RoomData).cleared
    if autotest:
        print("[BOSS-CHECK] %s floor=%d region=%s gate=%s" % ["PASS" if boss_done else "FAIL", floor_number, region_id, "open" if not gate.is_empty() and Shortcuts.is_open(String(gate["id"])) else "-"])
    assert(boss_done, "left a floor with its boss room not cleared")
    _door_choice = to
    Progress.add("floors")
    if floor_number >= FLOORS or Regions.next_options(region_id).is_empty():
        victory = true
        announce("You cleared the dungeon!")
        _end_run(true)
    else:
        call_deferred("start_floor", floor_number + 1)


## Enemy scaling input. Mostly a floor number: within a floor it only creeps up every
## second room, so a floor feels like one difficulty band and the jump is the stairs.
func difficulty() -> int:
    return 2 + (floor_number - 1) * 4 + mini(floor_rooms_cleared, 6) / 2


## Damage per second the party dealt in each arena cleared on this floor (Room measures it
## with Enemy.dealt_total); sizes the boss from floor 2.
var _arena_dps: Array = []


func note_arena_dps(dps: float) -> void:
    _arena_dps.append(dps)


## Mean output of the floor's last three arenas, 0 when none was fought.
func floor_arena_dps() -> float:
    var recent: Array = _arena_dps.slice(-3)
    if recent.is_empty():
        return 0.0
    var sum := 0.0
    for v in recent:
        sum += float(v)
    return sum / float(recent.size())


## Best luck in the party: rarer offers for everyone, the way scrap gain works.
func party_luck() -> float:
    var best := 0.0
    for p in players:
        best = maxf(best, p.stat("luck"))
    return best


func add_scrap(v: int) -> void:
    var gain := 0.0
    for p in players:
        gain = maxf(gain, p.stat("scrap_gain"))
    var got := ceili(float(v) * (1.0 + gain))
    scrap += got
    Telemetry.scrap_earned(got)


func announce(text: String) -> void:
    message = text
    _message_time = 3.0


func party_elements() -> Array:
    var kinds := []
    for p in players:
        for k in p.element_kinds():
            if not kinds.has(k):
                kinds.append(k)
    return kinds


func nearest_alive_player(pos: Vector2) -> Player:
    var best: Player = null
    var best_d := INF
    for p in players:
        if not p.alive:
            continue
        var d := p.global_position.distance_squared_to(pos)
        if d < best_d:
            best_d = d
            best = p
    return best


func _party_center() -> Vector2:
    var sum := Vector2.ZERO
    var n := 0
    for p in players:
        if p.alive:
            sum += p.global_position
            n += 1
    if n == 0:
        for p in players:
            sum += p.global_position
        n = players.size()
    return sum / float(maxi(1, n))


# --- Players ---------------------------------------------------------------


func _spawn_player(device: int, keyboard: bool) -> Player:
    var p := Player.new(players.size(), PlayerInput.new(device, keyboard))
    p.position = _party_center() + Vector2(randf_range(-40, 40), randf_range(-40, 40))
    add_child(p)
    players.append(p)
    p.died.connect(_on_player_died)
    p.leveled_up.connect(_on_leveled_up)
    if danger != null:
        p.hurt.connect(danger.on_hurt)
    # Player 1 wears the loadout picked at the Gate; later joiners a random unlocked Mark
    # with its own Kit, no Relic or Vow.
    var lo := Loadout.current()
    if players.size() > 1:
        var mark_id := String(Loadout.unlocked_marks().pick_random())
        lo = Loadout.from_class(mark_id)
        if not Loadout.kit_unlocked(String(lo["kit"])):
            lo["kit"] = Loadout.BARE_KIT
    Loadout.apply(p, lo)
    # A Kit brings its gun. A bare Kit starts naked: the entrance offers a pick of two
    # (the room does that for unarmed players on entry); late joiners get a random one.
    if current != null and String(lo["kit"]) == Loadout.BARE_KIT:
        if current.data.type == RoomData.Type.START and floor_number == 1:
            current.add_gun_choice()
        else:
            var pool: Array = Guns.ids()
            if not pool.is_empty():
                p.add_gun(pool.pick_random())
    if device >= 0:
        _joined_devices[device] = true
    if autotest:
        print("[LOADOUT-STATS] %s" % _loadout_stats(p))
    return p


## One line of a fresh player's numbers, for before/after checks of starts (Phase 2:
## every old class must play as its Mark with the same numbers).
func _loadout_stats(p: Player) -> String:
    var gun_ids: Array = []
    for g in p.guns:
        gun_ids.append(g.data.id)
    var items: Array = p.equipment.values()
    items.sort()
    var keys := ["speed", "armor", "crit", "luck", "regen", "lifesteal", "scrap_gain", "state_duration"]
    for ek in Element.NAMES.values():
        var e := String(ek).to_lower()
        keys.append("potency_" + e)
        keys.append("dmg_" + e)
    var parts: Array = []
    for k in keys:
        var v := p.stat(String(k))
        if not is_zero_approx(v):
            parts.append("%s=%.3f" % [k, v])
    return "hp=%.0f carry=%d guns=%s items=%s %s" % [p.max_hp, p.weight_capacity, ",".join(gun_ids), ",".join(items), " ".join(parts)]


func _on_joy_connection_changed(device: int, connected: bool) -> void:
    if device == 0 and connected and not players.is_empty() and players[0].input.device < 0:
        players[0].input.device = 0
        _joined_devices[0] = true
        players[0].say("Controller connected")


func _handle_joins() -> void:
    if players.size() >= MAX_PLAYERS:
        return
    for d in Input.get_connected_joypads():
        if _joined_devices.has(d):
            continue
        if Input.is_joy_button_pressed(d, JOY_BUTTON_START):
            var p := _spawn_player(d, false)
            p.say("Joined!")


var _back_was_down: Dictionary = {}


## The pad's Back / Select button opens that player's character sheet.
func _handle_sheet_buttons() -> void:
    if pause_menu.visible:
        return
    for d in Input.get_connected_joypads():
        if not _joined_devices.has(d):
            continue
        var down := Input.is_joy_button_pressed(d, JOY_BUTTON_BACK)
        if down and not _back_was_down.get(d, false):
            for p in players:
                if p.input.device == d:
                    pause_menu.show_sheet(p, true)
                    break
        _back_was_down[d] = down


## Level-ups wait for a quiet moment: the picker opens once the room is clear.
func _on_leveled_up(p: Player) -> void:
    if _probe != null:
        return   # the dps probe measures a fixed build
    if autotest:
        print("[LEVEL] %d floor=%d t=%.0f rooms=%d xp_total=%.0f" % [p.level, floor_number, _clock, rooms_cleared, p.xp_total])
        # Picks one of three like a player would: the rarest card, then what kills or keeps
        # you alive over vent and fusion niche picks.
        var opts: Array = LevelUps.roll(p, 3)
        if not opts.is_empty():
            var best := 0
            for i in opts.size():
                if _bot_pick_score(opts[i]) > _bot_pick_score(opts[best]):
                    best = i
            Telemetry.levelup(opts, best, int(p.level))
            p.apply_upgrade(opts[best])
        return
    _pending_levelups.append(p)


func _bot_pick_score(opt: Dictionary) -> float:
    var cat_bonus := { "OFFENCE": 3.0, "DEFENCE": 3.0, "REACTIONS": 2.5, "ELEMENT": 2.0, "FUSIONS": 1.5, "TRADE-OFF": 1.0, "VENT": 0.0 }
    return 10.0 * float(opt.get("rarity", 0)) + float(cat_bonus.get(String(opt.get("cat", "")), 0.0)) + randf()


func _serve_levelups() -> void:
    if _pending_levelups.is_empty() or pause_menu.visible or levelup.is_open():
        return
    if current != null and current.active:
        return
    var p: Player = _pending_levelups.pop_front()
    if is_instance_valid(p) and p.alive:
        levelup.open(p)


func _on_player_died(_p: Player) -> void:
    for p in players:
        if p.alive:
            return
    game_over = true
    if autotest:
        print("[DEATH] floor=%d region=%s room=%s diff=%d t=%.0f kills=%d level=%d" % [floor_number, region_id, current.data.type_name() if current else "-", difficulty(), _clock, total_kills, players[0].level])
        _print_arena("death")
    _end_run(false)


# --- Frame -----------------------------------------------------------------


func _process(delta: float) -> void:
    if autotest:
        _autotest_tick(delta)
    _handle_joins()
    _handle_sheet_buttons()
    _serve_levelups()
    camera.target = _party_center()
    camera.shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
    _shake = move_toward(_shake, 0.0, 28.0 * delta)
    _message_time = maxf(0.0, _message_time - delta)
    if _message_time <= 0.0:
        message = ""


func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    var key: InputEventKey = event
    match key.physical_keycode:
        KEY_R:
            _restart()
        KEY_F1:
            show_help = not show_help
        KEY_C:
            if not players.is_empty() and not pause_menu.visible:
                pause_menu.show_sheet(players[0], true)
        KEY_F9:
            Progress.reset()
            announce("Save wiped: next run starts from nothing")
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
            var ids: Array = Guns.all_ids()
            var n: int = key.physical_keycode - KEY_1
            if key.physical_keycode == KEY_0:
                n = 9
            if n < ids.size() and not players.is_empty():
                players[0].add_gun(ids[n])


# --- The Archivist (World and progression GDD, phase 1) ----------------------


## The Archivist sits chained in a side room of the Ossuary (the first region's treasure
## room, else its shop) until someone brings him the Torn Bestiary Page. Missed, never
## lost: he is there every run until recruited.
func _place_archivist() -> void:
    if region_id != Regions.FIRST or Progress.npc_home("archivist"):
        return
    for want in [RoomData.Type.TREASURE, RoomData.Type.SHOP]:
        for pos in rooms:
            var r: RoomData = rooms[pos]
            if r.type == want:
                r.stock.append({ "kind": "archivist", "id": "archivist", "price": 0, "taken": false,
                    "pos": Vector2(-300, -110), "page": page_state == "carried" })
                if autotest:
                    print("[RECRUIT] archivist chained in the %s at %s" % [RoomData.TYPE_NAMES.get(want, "?"), pos])
                return


## The first elite killed in a run (Archivist not yet home) drops the Torn Bestiary Page.
func drop_page(room: Room, pos: Vector2) -> void:
    if page_state != "" or Progress.npc_home("archivist"):
        return
    page_state = "dropped"
    room.data.stock.append({ "kind": "page", "id": "bestiary_page", "price": 0, "taken": false, "pos": pos })
    room._build_pedestals()
    Telemetry.event("page_dropped", { "floor": floor_number })
    if autotest:
        print("[RECRUIT] page dropped by an elite on floor %d at t=%.0f" % [floor_number, _clock])


func take_page(o: Dictionary, pl: Player) -> void:
    o["taken"] = true
    page_state = "carried"
    pl.say("Torn Bestiary Page")
    Sfx.play("buy")
    for pos in rooms:
        for so in (rooms[pos] as RoomData).stock:
            if so["kind"] == "archivist":
                so["page"] = true
    if autotest:
        print("[RECRUIT] page taken at t=%.0f" % _clock)


## Talking to the chained Archivist: a line keyed to the save; with the page, giving it
## frees him and he moves into the Hollow (the page leaves the run).
func talk_archivist(o: Dictionary, pl: Player) -> void:
    var giving: bool = page_state == "carried" and not o.get("freed", false)
    var line := Dialogue.say("archivist", Dialogue.context({ "where": "ossuary", "page": giving }))
    o["say"] = String(line.get("text", ""))
    o["say_age"] = 0.0
    if giving:
        page_state = "given"
        o["page"] = false
        o["freed"] = true
        Progress.set_npc_state("archivist", "recruited")
        Telemetry.event("npc_recruited", { "npc": "archivist", "floor": floor_number })
        hud.toast("Archivist freed: the Journal is in the Hollow's library")
        Sfx.play("unlock")
        if autotest:
            print("[RECRUIT] archivist recruited at t=%.0f: \"%s\"" % [_clock, o["say"]])
            if _recruit_probe:
                _print_stats("END")
                get_tree().quit()
    else:
        if Progress.npc_state("archivist") == "":
            Progress.set_npc_state("archivist", "met")
        Sfx.play("ui_open")
        if autotest:
            print("[RECRUIT] archivist says: \"%s\"" % o["say"])


# --- The Well (World and progression GDD, section 11) ------------------------


## Leaving the run any other way (Return to hub, Restart, Quit) keeps the Well's items
## too; after `_end_run` this finds nothing new.
func _exit_tree() -> void:
    Progress.keep_well_items(well_items)


## Each region's start room has a Well: once per region one worn item can go down it.
## However the run ends, the item waits for the Wellkeeper, who sells it back as a Relic.
func _place_well() -> void:
    for pos in rooms:
        var r: RoomData = rooms[pos]
        if r.type == RoomData.Type.START:
            r.stock.append({ "kind": "well", "id": "well", "price": 0, "taken": false, "pos": Vector2(-250, -140) })
            return


## Worn items a player could drop in a Well (gear, not gun mods).
func well_choices(pl: Player) -> Array:
    var out: Array = []
    for key in pl.equipment.keys():
        var id := String(pl.equipment[key])
        if not Items.get_item(id).is_empty() and not out.has(id):
            out.append(id)
    return out


func use_well(o: Dictionary, pl: Player, room: Room) -> void:
    var choices := well_choices(pl)
    if choices.is_empty():
        pl.say("Nothing worn to give the well")
        Sfx.play("error")
        return
    if autotest:
        _drop_in_well(o, pl, room, String(choices[0]))
        return
    well_screen.pick(pl, choices, func(id: String) -> void:
        if id != "" and not o.get("taken", false) and is_instance_valid(pl):
            _drop_in_well(o, pl, room, id))


func _drop_in_well(o: Dictionary, pl: Player, room: Room, id: String) -> void:
    if not pl.unequip_item(id):
        return
    o["taken"] = true
    well_items.append(id)
    Telemetry.event("well_drop", { "item": id, "floor": floor_number, "region": region_id })
    hud.toast("%s went down the well. The Wellkeeper keeps it." % String(Items.get_item(id).get("name", id)))
    Sfx.play("unlock")
    if is_instance_valid(room):
        room._build_pedestals()
    if autotest:
        print("[WELL] dropped %s on floor %d (%s) at t=%.0f" % [id, floor_number, region_id, _clock])


## Leave the run for the hub (pause menu, run-over screen).
func return_to_hub() -> void:
    get_tree().paused = false
    Engine.time_scale = 1.0
    get_tree().change_scene_to_file("res://scenes/hub.tscn")


func _restart() -> void:
    get_tree().reload_current_scene()


## Dark edges over the whole screen; sits under the HUD.
func _make_vignette() -> TextureRect:
    var grad := Gradient.new()
    grad.set_color(0, Color(0, 0, 0, 0.0))
    grad.set_color(1, Color(0, 0, 0, 0.78))
    grad.set_offset(0, 0.35)
    var tex := GradientTexture2D.new()
    tex.gradient = grad
    tex.fill = GradientTexture2D.FILL_RADIAL
    tex.fill_from = Vector2(0.5, 0.5)
    tex.fill_to = Vector2(1.05, 0.5)
    tex.width = 256
    tex.height = 256
    var rect := TextureRect.new()
    rect.texture = tex
    rect.stretch_mode = TextureRect.STRETCH_SCALE
    rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return rect


# --- Self-test bot ---------------------------------------------------------


func _count_reaction(reaction_name: String, _pos: Vector2, _col: Color) -> void:
    _reaction_counts[reaction_name] = _reaction_counts.get(reaction_name, 0) + 1
    Progress.add_reaction(reaction_name)


## A fusion or cataclysm fired (Elements.fusion_fired, before its actions run): the show,
## the counts. A first-ever discovery says so in its in-world name label ("NEW"), not with a
## HUD toast: the first minutes of a fusion build discover several a minute.
func _on_fusion(fusion_name: String, tier: int, pos: Vector2, radius: float, entry: Dictionary) -> void:
    _fusion_counts[fusion_name] = int(_fusion_counts.get(fusion_name, 0)) + 1
    Telemetry.fusion(fusion_name, tier)
    var first := Progress.add_fusion(fusion_name, tier)
    FusionFx.play(self, fusion_name, tier, pos, radius, entry, first)


## --fusion-probe loadouts: four w1 guns of four elements each (wet, fire, oil, shock, blood
## and gale are the w1 elements).
const FUSION_LOADOUTS := [
    ["water_pistol", "flare_pistol", "spark_needler", "zephyr_rang"],   # wet fire shock gale
    ["slick_wand", "flare_pistol", "spark_needler", "zephyr_rang"],     # oil fire shock gale
    ["water_pistol", "flare_pistol", "spark_needler", "vein_pistol"],   # wet fire shock blood
    ["slick_wand", "flare_pistol", "vein_pistol", "zephyr_rang"],       # oil fire blood gale
    # The Pyre Lord's chain (water, shock, ice; he brings the fire). Only by --fusion-probe=4,
    # the --instance rotation keeps to the first four.
    ["water_pistol", "spark_needler", "rime_chakram", "flare_pistol"],
]


## --build=<id> profiles for late-floor probes. "storm" replays the human run 4487a37a46b6c384
## (Stormcaller, won all five floors): each floor entry is the build at the START of that
## floor, i.e. what the player carried when the previous floor ended: guns as id@tier, gear,
## mods as item@gun, and the level-up picks made on the previous floor (LevelUps.options()
## ids, "<boon>_<rarity>"). The picks are the human's 44 old picks translated to the boon
## catalog at the new pace (one level a wave: 4, 6, 4 and 5 picks before floors 2 to 5, from
## the run's XP under Player.xp_to_next), keeping what the human favoured (damage, crit,
## regen and Leech, health, vent; its element duration picks became Smoulder, the nearest
## reaction boon) and nothing it never saw (element and fusion boons). XP gain, luck,
## projectile speed and scrap picks are gone from the catalog. With --start-floor=N the bot
## begins on floor N with
## every earlier floor's picks applied. "mid" is a mediocre build at the same levels: four
## tier-one guns of four elements, starter gear, bot-random level-ups and no healing items.
const BOT_BUILDS := {
    "storm": {
        "class": "stormcaller",
        2: { "guns": ["blowtorch@2", "blood_lance@1", "frost_caster@1", "spark_needler@2", "venom_spitter@1"],
            "gear": ["charm_shock", "hobnail_boots", "charm_stone", "vampiric_loop"],
            "mods": ["coating_void@frost_caster"],
            "picks": ["damage_0", "crit_0", "armor_1", "vent_charge_1"] },
        3: { "guns": ["blowtorch@2", "blood_lance@2", "frost_caster@1", "spark_needler@2", "venom_spitter@1", "gravel_shotgun@1"],
            "gear": ["vial_fire", "hobnail_boots", "charm_stone", "band_of_lingering", "ring_fire", "overpressure", "gloves_stone", "leech_mail"],
            "mods": ["coating_shock@blowtorch", "coating_stone@blood_lance", "coating_void@frost_caster", "oiled_bolt@venom_spitter"],
            "picks": ["regen_1", "lifesteal_2", "attack_speed_1", "damage_1", "dot_1", "crit_1"] },
        4: { "guns": ["blowtorch@2", "blood_lance@2", "frost_caster@1", "spark_needler@2", "venom_spitter@1", "gravel_shotgun@1"],
            "gear": ["vial_fire", "hobnail_boots", "charm_stone", "signet_of_overload", "ring_fire", "overpressure", "gloves_stone", "leech_mail"],
            "mods": ["coating_shock@blowtorch", "coating_stone@blood_lance", "coating_ice@blood_lance", "coating_void@frost_caster", "oiled_bolt@venom_spitter"],
            "picks": ["damage_2", "max_hp_1", "dot_0", "potency_1"] },
        5: { "guns": ["blowtorch@2", "blood_lance@2", "frost_caster@1", "spark_needler@2", "venom_spitter@1", "gravel_shotgun@1"],
            "gear": ["vial_acid", "hobnail_boots", "charm_stone", "signet_of_overload", "ring_fire", "overpressure", "gloves_stone", "leech_mail", "seer_circlet"],
            "mods": ["coating_shock@blowtorch", "coating_stone@blood_lance", "coating_ice@blood_lance", "coating_void@frost_caster", "oiled_bolt@venom_spitter"],
            "picks": ["dodge_0", "vent_1", "damage_1", "max_hp_1", "attack_speed_1"] },
    },
    "mid": {
        "class": "stormcaller",
        2: { "guns": ["spark_needler@1", "blowtorch@1", "frost_caster@1", "venom_spitter@1"], "gear": ["hobnail_boots"], "mods": [], "random_levels": 4 },
        3: { "guns": ["spark_needler@1", "blowtorch@1", "frost_caster@1", "venom_spitter@1", "blood_lance@1"], "gear": ["hobnail_boots"], "mods": [], "random_levels": 6 },
        4: { "guns": ["spark_needler@2", "blowtorch@1", "frost_caster@1", "venom_spitter@1", "blood_lance@1"], "gear": ["hobnail_boots", "ring_fire"], "mods": [], "random_levels": 4 },
        5: { "guns": ["spark_needler@2", "blowtorch@1", "frost_caster@1", "venom_spitter@1", "blood_lance@1", "gravel_shotgun@1"], "gear": ["hobnail_boots", "ring_fire"], "mods": [], "random_levels": 5 },
    },
}


func _bot_build() -> Dictionary:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--build="):
            return BOT_BUILDS.get(a.substr(8), {})
    return {}


func _bot_start_floor() -> int:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--start-floor="):
            return clampi(int(a.substr(14)), 1, FLOORS)
    return 1


## Bots: `--route=ossuary_gate,rust_ruins,...` fixes the regions in order (checked against
## the graph); otherwise a bot starting deeper (--start-floor) takes a random way down.
func _plan_bot_route() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--route="):
            _planned_route = Regions.parse_route(a.substr(8))
            if _planned_route.is_empty():
                push_error("--route: not a way down the region graph: %s" % a.substr(8))
    var start := _bot_start_floor()
    if _planned_route.size() < start:
        _planned_route = Regions.random_route(start)
    var bad := Regions.validate()
    print("[ROUTE] %s  graph %s" % [" > ".join(_planned_route), "valid" if bad.is_empty() else "INVALID: " + "; ".join(bad)])


## Fit the bot out as the --build profile stood at the start of floor `n`: guns and tiers,
## gear, mods, and every level-up the profile made before that floor.
func _apply_bot_build(build: Dictionary, n: int) -> void:
    if n < 2 or not build.has(n):
        return
    var p := players[0]
    var entry: Dictionary = build[n]
    p.weight_capacity_base = 40
    p.recalc_stats()
    for g in p.guns.duplicate():
        p.drop_gun(g)
    for spec in entry["guns"]:
        var parts: PackedStringArray = String(spec).split("@")
        if p.add_gun(parts[0], false):
            p.guns[p.guns.size() - 1].tier = int(parts[1]) if parts.size() > 1 else 1
    for slot in p.equipment.keys():
        p.equipment.erase(slot)
    for id in entry["gear"]:
        p.equip(id)
    for spec in entry["mods"]:
        var parts: PackedStringArray = String(spec).split("@")
        for g in p.guns:
            if g.data.id == parts[1] and g.mods.size() < g.tier:
                p.equip_mod_on(g, parts[0])
                break
    var by_id := {}
    for opt in LevelUps.options():
        by_id[opt["id"]] = opt
    for f in range(2, n + 1):
        var e: Dictionary = build.get(f, {})
        var no_picks := OS.get_cmdline_user_args().has("--no-picks")
        for pick in ([] if no_picks else e.get("picks", [])):
            if by_id.has(pick):
                p.apply_upgrade(by_id[pick])
                p.level += 1
        for i in (0 if no_picks else int(e.get("random_levels", 0))):
            var opts: Array = LevelUps.roll(p, 1)
            if not opts.is_empty():
                p.apply_upgrade(opts[0])
            p.level += 1
    p.xp = 0.0
    p.hp = p.max_hp
    scrap = 60
    var guns: Array = []
    for g in p.guns:
        guns.append("%s@%d%s" % [g.data.id, g.tier, ("+" + "+".join(g.mods)) if not g.mods.is_empty() else ""])
    print("[BUILD] floor %d: level %d, max hp %.0f, lifesteal %.0f, regen %.1f, armor %.0f, guns %s, gear %s" % [
        n, p.level, p.max_hp, p.stat("lifesteal"), p.stat("regen"), p.stat("armor"), ", ".join(guns), str(p.equipment.values())])


func _setup_autotest() -> void:
    Materials.hash_log = OS.get_cmdline_user_args().has("--grid-hash")
    BossBody.log_enabled = not _perf_quiet()
    _bot_idle_fights = OS.get_cmdline_user_args().has("--idle")
    _bot_kite = OS.get_cmdline_user_args().has("--kite")
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--aim="):
            Player.aim_mode_override = a.substr(6)
    # The bot aims itself in fights (holds fire at its pick): needed in manual mode.
    _bot_aim = OS.get_cmdline_user_args().has("--bot-aim") or Player.aim_mode_override == "manual"
    if OS.get_cmdline_user_args().has("--dps-probe"):
        _probe = BalanceProbe.new(self)
        add_child(_probe)
    if PayoutShot.wanted():
        add_child(PayoutShot.new(self))   # level-up cards and wave-end spoils (payout_shot.gd)
    if HurtShot.wanted():
        add_child(HurtShot.new(self))   # hit flash, low health, hazards, death recap (hurt_shot.gd)
    _plan_bot_route()
    _apply_bot_build(_bot_build(), _bot_start_floor())
    if GearShot.wanted():
        add_child(GearShot.new(self))   # worn-gear sheets and fight close-ups (gear_shot.gd)
    if ClarityShot.wanted():
        add_child(ClarityShot.new(self))   # before/after readability shots and numbers (clarity_shot.gd)
    # Default: a real naked start, so the run measures the progression loop. `--arsenal`
    # hands over every gun to stress every element and effect at once.
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--loadout="):
            # Balance probe: start with exactly these guns, e.g. --loadout=water_pistol,flare_pistol
            # With --build the loadout replaces the profile's guns (gear and levels stay),
            # and `id@tier` sets a tier, so element builds compare on the same footing.
            var p0 := players[0]
            p0.weight_capacity_base = 40
            p0.recalc_stats()
            if not _bot_build().is_empty():
                for g in p0.guns.duplicate():
                    p0.drop_gun(g)
            for spec in a.substr(10).split(","):
                var parts: PackedStringArray = String(spec).split("@")
                if p0.add_gun(parts[0], parts.size() == 1) and parts.size() > 1:
                    p0.guns[p0.guns.size() - 1].tier = int(parts[1])
            print("[LOADOUT] %s" % a.substr(10))
        if a == "--fusion-probe" or a.begins_with("--fusion-probe="):
            # Tier-ladder probe: four light guns of four elements, so compounds, fusions and
            # cataclysms actually happen. The loadout rotates with --instance (or pick one
            # with --fusion-probe=K); each is four w1 guns, the same weight and dps as four
            # copies of one, so single-element runs compare like for like.
            var k := int(a.substr(15)) if a.begins_with("--fusion-probe=") else posmod(int(_instance_tag().trim_prefix("_")), 4)
            var lo: Array = FUSION_LOADOUTS[posmod(k, FUSION_LOADOUTS.size())]
            var p1 := players[0]
            p1.weight_capacity_base = 40
            p1.recalc_stats()
            for gid in lo:
                p1.add_gun(gid)
            print("[LOADOUT] fusion-probe %d: %s" % [posmod(k, FUSION_LOADOUTS.size()), ",".join(lo)])
            var bad := Fusions.validate()
            print("[FUSION-TABLES] %s" % ("valid" if bad.is_empty() else "%d errors: %s" % [bad.size(), "; ".join(bad.slice(0, 5))]))
    if OS.get_cmdline_user_args().has("--arsenal"):
        var p := players[0]
        p.weight_capacity_base = 80
        p.recalc_stats()
        for id in Guns.all_ids():
            var owned := false
            for g in p.guns:
                if g.data.id == id:
                    owned = true
            if not owned:
                p.add_gun(id)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))


func _autotest_tick(delta: float) -> void:
    _clock += delta
    if _perf_probe:
        # Every 2 s a sample line, but only with --perf-lines: printing costs a hitch, so a
        # plain --perf run prints its frame-time summary once, at the end (Perf.summary).
        _perf_t -= get_process_delta_time() / maxf(Engine.time_scale, 0.001)
        if _perf_t <= 0.0 and _perf_lines:
            _perf_t = 2.0
            print("[PERF] t=%.0f fps=%d process_ms=%.2f physics_ms=%.2f draw_calls=%d objects=%d primitives=%d nodes=%d enemies=%d projectiles=%d pixels=%d" % [
                _clock, Engine.get_frames_per_second(),
                Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
                Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
                Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
                Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
                Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
                Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
                get_tree().get_nodes_in_group("enemies").size(),
                Projectile.live,
                fx.live_pixels() if fx != null and fx.has_method("live_pixels") else -1])
    if current == null or players.is_empty():
        return
    if bot_paused:
        return
    if _probe != null:
        if not _probe_started:
            _probe_started = true
            _probe.start()
        _probe.tick(delta)
        return
    # Watchdog: nothing in a bot run may hold the tree paused. Report what did and go on.
    if get_tree().paused:
        _paused_secs += delta
        if _paused_secs > 4.0:
            var open: Array = []
            for c in get_children():
                if c is CanvasLayer or c is Control:
                    if c.get("visible") == true:
                        open.append(c.name)
            print("[WATCHDOG] tree paused %.0f s at t=%.0f; visible overlays: %s" % [_paused_secs, _clock, str(open)])
            if levelup != null and levelup.has_method("is_open") and levelup.is_open():
                print("[WATCHDOG] level-up screen open")
            if gun_pick != null and gun_pick.is_open():
                print("[WATCHDOG] gun picker open")
            get_tree().paused = false
            _paused_secs = 0.0
    else:
        _paused_secs = 0.0
    var p := players[0]
    var t := p.nearest_enemy(900.0)
    var circle := Vector2.RIGHT.rotated(_clock * 0.6)
    if t != null:
        var to_enemy := (t.global_position - p.global_position).normalized()
        # Low on health: run, don't orbit. Otherwise circle at range like a player kiting.
        var flee := p.hp < p.max_hp * 0.5
        p.input.force_move = (-to_enemy * (1.0 if flee else 0.8) + circle * (0.25 if flee else 0.6)).normalized()
        if _bot_kite:
            p.input.force_move = _bot_kite_dir(p)
        if _bot_idle_fights:
            # Balance probe: stand still in the middle of every fight, as a lazy player would.
            p.input.force_move = -p.global_position.normalized() if p.global_position.length() > 40.0 else Vector2.ZERO
        var inner := current.rect.grow(-120.0)
        if not inner.has_point(p.global_position) and not _bot_kite:
            p.input.force_move = (inner.get_center() - p.global_position).normalized()
        if _bot_aim:
            _bot_aim_at(p, t)
        _bot_idle = 0.0
    else:
        _bot_idle += delta
        _bot_navigate(p)
    if fmod(_clock, 6.0) < delta:
        p.vent()
    if fmod(_clock, 9.0) < delta and p.has_method("use_active"):
        p.use_active()
    if fmod(_clock, 10.0) < delta:
        if not _perf_quiet():
            _print_stats("TICK")
        var peds: Array = []
        for ped in current.pedestals:
            if is_instance_valid(ped):
                peds.append("%s@%s" % [ped.offer.get("id", ped.kind()), ped.position.round()])
        print("    room active=%s wave_left=%.0f enemies=%d paused=%s pos=%s move=%s fire=%s idle=%.1f peds=%s" % [
            current.active, current.wave_time_left, current.enemies.get_child_count(), get_tree().paused,
            p.global_position.round(), p.input.force_move, p.level, _bot_idle, str(peds)])
    if _clock >= 30.0 and not _shots_taken.has("pause"):
        _shots_taken["pause"] = true
        pause_menu.show_for_test()
    if _clock >= 45.0 and not _shots_taken.has("sheet"):
        _shots_taken["sheet"] = true
        # Gear for the sheet screenshot only with --gear: it biased the shock reactions.
        if OS.get_cmdline_user_args().has("--gear"):
            for id in ["conductors_mail", "ring_shock", "vial_shock", "lucky_cog", "quick_hands"]:
                p.equip(id)
        pause_menu.show_for_test("res://autotest/sheet.png", p)
    for shot_time in [15.0, 60.0, 120.0, 180.0, 240.0]:
        if _clock >= shot_time and not _shots_taken.has(shot_time):
            _shots_taken[shot_time] = true
            _screenshot("res://autotest/t%03d.png" % int(shot_time))
    var limit := 70.0 if OS.get_cmdline_user_args().has("--short") else 300.0
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--secs="):
            limit = float(a.substr(7))
    if _clock >= limit or game_over or victory:
        if not game_over and not victory:
            var would: Dictionary = Mastery.preview(floor_number, false, String(Loadout.current()["mark"]))
            print("[EMBERS] time cap: a death here would pay +%d (%s)" % [int(would["total"]), Mastery.award_text(would)])
        _print_stats("END")
        get_tree().quit()


## `--kite`: a player-like dodge instead of orbiting the nearest enemy. Every enemy and
## enemy shot within reach pushes (closer pushes harder), the bot slides sideways along
## that push the way a player circles a crowd, and the room's edge pulls it back in
## gradually, so it is not steered into the pack it is fleeing.
var _bot_kite := false
var _bot_aim := false   # --bot-aim (and --aim=manual): the bot holds fire at its own pick
var _bot_kite_side := 1.0
var _bot_kite_flip := 0.0


## --bot-aim: hold fire toward the nearest enemy, or on a boss with parts toward the part its
## chain needs next: intact armour first (to tear it), else the visible part that takes the
## most (the bare core), as a player who knows the fight would.
func _bot_aim_at(p: Player, t: Node2D) -> void:
    var at := t.global_position
    var body: BossBody = t.get("body")
    if body != null and body.has_parts():
        var best := -1.0
        for i in body.parts.size():
            if not body.visible(i):
                continue
            var score := float(body.parts[i].get("taken", 1.0)) + (10.0 if body.parts[i].get("armour", false) else 0.0)
            if score > best:
                best = score
                at = body.part_world(i)
    var to := at - p.global_position
    p.input.force_fire = true
    p.input.force_aim = to.normalized() if to.length() > 1.0 else Vector2.RIGHT


func _bot_kite_dir(p: Player) -> Vector2:
    var pos := p.global_position
    var push := Vector2.ZERO
    var crowd := 0
    for e in current.enemies.get_children():
        if not is_instance_valid(e) or not e is Enemy:
            continue
        var d: Vector2 = pos - (e as Enemy).global_position
        var l := d.length()
        if l < 340.0 and l > 0.5:
            push += d / l * pow((340.0 - l) / 340.0, 2.0) * (2.5 if (e as Enemy).is_elite else 1.0)
            crowd += 1
    for sh in get_tree().get_nodes_in_group("enemy_projectiles"):
        if not is_instance_valid(sh) or not sh is Node2D:
            continue
        var d2: Vector2 = pos - (sh as Node2D).global_position
        var l2 := d2.length()
        if l2 < 160.0 and l2 > 0.5:
            push += d2 / l2 * (160.0 - l2) / 160.0 * 1.5
    var away := push.normalized() if push.length() > 0.01 else Vector2.ZERO
    _bot_kite_flip -= get_process_delta_time()
    if _bot_kite_flip <= 0.0:
        _bot_kite_flip = randf_range(2.5, 5.0)
        _bot_kite_side = -_bot_kite_side
    var dir := away * 0.75 + away.orthogonal() * _bot_kite_side * 0.65
    if crowd == 0:
        dir = Vector2.ZERO
    # The edge: pull toward the middle as the bot nears a wall, harder the closer it is.
    var inner := current.rect.grow(-90.0)
    var center_pull := Vector2.ZERO
    if not inner.has_point(pos):
        var clamped := Vector2(clampf(pos.x, inner.position.x, inner.end.x), clampf(pos.y, inner.position.y, inner.end.y))
        center_pull = (clamped - pos) / 60.0 + (inner.get_center() - pos).normalized() * 0.4
    dir += center_pull
    if dir.length() < 0.05:
        return Vector2.ZERO
    return current.path_dir(pos, pos + dir.normalized() * 80.0)


func _bot_navigate(p: Player) -> void:
    var room := current
    p.input.force_fire = false
    p.input.force_aim = Vector2.ZERO
    # Just through a door: step into the room first, so kiting or a door's own trigger
    # cannot bounce the bot straight back out.
    if _clock - _room_entered_t < 1.2:
        p.input.force_move = room.path_dir(p.global_position, Vector2.ZERO) if p.global_position.length() > 80.0 else Vector2.ZERO
        return
    # Pedestals worth using.
    for ped in room.pedestals:
        if not is_instance_valid(ped) or ped.empty():
            continue
        var o: Dictionary = ped.offer
        if _bot_wants(o, p):
            if _bot_idle > 15.0 and o["kind"] in ["gun", "item"]:
                # A layout can wall a pedestal off from the bot's straight path: give it up.
                _bot_tried[o["id"]] = true
                _bot_idle = 0.0
                continue
            var d := ped.global_position - p.global_position
            if d.length() < 30.0:
                if o["kind"] in ["gun", "item"]:
                    _bot_tried[o["id"]] = true
                room.activate(ped, p)
                _bot_idle = 0.0
            else:
                p.input.force_move = room.path_dir(p.global_position, ped.global_position)
            return
    # Obstacles the bot can clear with what it carries. Secret walls it never looks for:
    # a hidden room is only used once someone opened it.
    for dir in room.data.doors.keys():
        var ob: String = room.data.doors[dir]["obstacle"]
        if ob == "" or not Obstacle.KINDS.has(ob) or Obstacle.KINDS[ob].get("locked", false) or _bot_skip.has([current_pos, dir]):
            continue
        _bot_obstacle_time += get_process_delta_time()
        if _bot_obstacle_time > 25.0:
            _print_stats("Gave up on %s obstacle" % ob)
            _bot_skip[[current_pos, dir]] = true
            _bot_obstacle_time = 0.0
            continue
        var spec: Dictionary = Obstacle.KINDS[ob]
        var want_kind: int = spec["element"]
        if spec["reaction"] == "Steam":
            want_kind = Element.Kind.WET if fmod(_clock, 1.6) < 0.8 else Element.Kind.FIRE
        var gun: Gun = null
        for g in p.guns:
            if g.data.element == want_kind:
                gun = g
        if gun == null:
            continue
        # Auto-fire never targets obstacles: walk up and hold the trigger at the door.
        var target := room.door_world_position(dir)
        var to := target - p.global_position
        p.input.force_move = room.path_dir(p.global_position, target) if to.length() > 130.0 else Vector2.ZERO
        p.input.force_fire = to.length() <= 260.0
        p.input.force_aim = to.normalized()
        return
    _bot_obstacle_time = 0.0
    if not room.data.cleared:
        p.input.force_move = room.path_dir(p.global_position, Vector2.ZERO) if p.global_position.length() > 60.0 else Vector2.ZERO
        return
    var dir := _bot_next_dir()
    if dir == Vector2i.ZERO:
        p.input.force_move = Vector2.ZERO
        return
    if _bot_idle > 12.0:
        _print_stats("STUCK, teleporting")
        _bot_idle = 0.0
        enter_room(door_target(dir), dir)
        return
    p.input.force_move = room.path_dir(p.global_position, room.door_world_position(dir))


## Whether the bot would use an offer right now (same rule for walking to it and for
## choosing a shop to walk back to, so it never ping-pongs between rooms).
func _bot_wants(o: Dictionary, p: Player) -> bool:
    if o.get("taken", false):
        return false
    match o["kind"]:
        "sigil":
            return true
        "page":
            return _recruit_probe
        "well":
            return _well_probe and not well_choices(p).is_empty()
        "archivist":
            return _recruit_probe and page_state == "carried"
        "sluice":
            return _open_gates
        "stairs":
            # Like a player: see the whole floor (shop, treasure) before going down, then
            # take the door the route plans (or a random one).
            return _bot_next_dir() == Vector2i.ZERO and (String(o["id"]) == "" or String(o["id"]) == _bot_door())
        "gun":
            return o["price"] <= scrap and p.can_carry(Guns.make(o["id"])) and not _bot_tried.has(o["id"])
        "item":
            # Replacing gear drops the old piece back on the floor; never chase it twice.
            if o["price"] > scrap or _bot_tried.has(o["id"]):
                return false
            if not _bot_build().is_empty():
                # A --build profile keeps its kit: only free slots and free mod slots fill.
                var slot: String = String(Items.get_item(o["id"]).get("slot", ""))
                if slot == "mod":
                    return p.mod_target() != null
                if slot in ["ring", "trinket"]:
                    return not (p.equipment.has(slot + "1") and p.equipment.has(slot + "2"))
                return not p.equipment.has(slot)
            return true
        "carry":
            return o["price"] <= scrap and scrap > 120
        "gunsmith":
            if o["price"] > scrap or (scrap <= 120 and o["price"] > 0):
                return false
            for g in p.guns:
                if g.tier < Gun.MAX_TIER:
                    return true
            return false
        "reroll":
            return o["price"] <= scrap and scrap > 200 and o.get("amount", 0) < 3
        "repair":
            return o["price"] <= scrap and p.hp < p.max_hp * 0.6
    return false


## The stairs door a bot takes out of this region: the next region of its --route while
## that lasts, else one of the doors on offer picked at random (once per depth).
func _bot_door() -> String:
    var depth := floor_number + 1
    if _planned_route.size() >= depth:
        return String(_planned_route[depth - 1])
    if not _bot_doors.has(depth):
        var ids: Array = []
        if current != null:
            for o in current.data.stock:
                if o["kind"] == "stairs" and String(o["id"]) != "":
                    ids.append(String(o["id"]))
        if ids.is_empty():
            return ""
        _bot_doors[depth] = String(ids.pick_random())
        print("[ROUTE-DOOR] depth %d: %s of %s" % [depth, _bot_doors[depth], ids])
    return String(_bot_doors[depth])


## Where to go next: a shop when scrap burns a hole in the pocket, else the nearest
## unvisited room, leaving the boss room for last the way a player reads the minimap.
const NO_STEP := Vector2i(99, 99)   # BFS sentinel: a real step can be (-1, 0)


func _bot_next_dir() -> Vector2i:
    var goal := NO_STEP
    if _open_gates and not gate.is_empty() and current_pos == gate["ante"] and not Shortcuts.is_open(String(gate["id"])):
        # --open-gates: from the antechamber, through the gate to open it from the far side.
        return Vector2i(gate["back"])
    if _rush:
        # --rush: straight for the boss door the way a player who knows the way walks.
        if rooms[current_pos].type == RoomData.Type.BOSS:
            return Vector2i.ZERO
        goal = _bot_bfs(func(r: RoomData) -> bool: return r.type == RoomData.Type.BOSS)
        if goal != NO_STEP:
            return goal
    if _recruit_probe and page_state == "carried":
        goal = _bot_bfs(func(r: RoomData) -> bool:
            for o in r.stock:
                if o["kind"] == "archivist" and not o.get("freed", false):
                    return true
            return false)
        if goal != NO_STEP:
            return goal
    if scrap > 150:
        goal = _bot_bfs(func(r: RoomData) -> bool:
            if r.type != RoomData.Type.SHOP:
                return false
            for o in r.stock:
                if o["kind"] != "stairs" and _bot_wants(o, players[0]):
                    return true
            return false)
    if goal == NO_STEP:
        goal = _bot_bfs(func(r: RoomData) -> bool: return not r.visited and r.type != RoomData.Type.BOSS)
    if goal == NO_STEP:
        goal = _bot_bfs(func(r: RoomData) -> bool: return not r.visited)
    if goal == NO_STEP:
        # Everything seen (a shop trip can come after the boss): back to the stairs.
        goal = _bot_bfs(func(r: RoomData) -> bool:
            for o in r.stock:
                if o["kind"] == "stairs" and not o.get("taken", false):
                    return true
            return false)
    if goal == NO_STEP:
        return Vector2i.ZERO
    return goal


## Breadth-first search through passable doors; returns the first step toward the
## nearest room (other than the current one) that satisfies `pred`, or NO_STEP.
func _bot_bfs(pred: Callable) -> Vector2i:
    var start := current_pos
    var prev: Dictionary = { start: start }
    var via: Dictionary = {}
    var queue: Array = [start]
    while not queue.is_empty():
        var cur: Vector2i = queue.pop_front()
        var r: RoomData = rooms[cur]
        if cur != start and pred.call(r):
            var step := cur
            while prev[step] != start:
                step = prev[step]
            return via[step]   # the door taken out of this room (a gate is not next door)
        for d in r.doors.keys():
            if r.doors[d]["obstacle"] != "":
                continue
            var n: Vector2i = r.doors[d]["to"]
            if prev.has(n):
                continue
            prev[n] = cur
            if cur == start:
                via[n] = d
            queue.append(n)
    return NO_STEP


func _screenshot(path: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png(path)


## A --perf run (without --perf-lines) keeps the fight's chatty logs ([TICK], [BOSS-CHAIN],
## [STAGGER]) quiet: a print through the bot's log pipe costs a 15 ms hitch on Windows, and
## real players never print them.
func _perf_quiet() -> bool:
    return _perf_probe and not _perf_lines


func _print_stats(label: String) -> void:
    if label == "END":
        if _perf_probe:
            print(Perf.summary())
        print("[HAZARD] region=%s gas_lit=%d zapped=%d" % [region_id, Materials.stat_gas_lit, Materials.stat_zapped])
    var p := players[0]
    var visited := 0
    for r in rooms.values():
        if r.visited:
            visited += 1
    print("[%s] t=%.0f wall=%.0f fps=%d floor=%d region=%s room=%s visited=%d/%d cleared=%d kills=%d scrap=%d hp=%.0f weight=%d/%d clouds=%d" % [
        label, _clock, Time.get_ticks_msec() / 1000.0, Engine.get_frames_per_second(), floor_number, region_id,
        current.data.type_name() if current else "-", visited, rooms.size(),
        rooms_cleared, total_kills, scrap, p.hp, p.total_weight(), p.weight_capacity,
        get_tree().get_nodes_in_group("clouds").size()])
    print("    resist: exposed=%d dmg resisted=%.0f weak=%.0f exposed=%.0f plain=%.0f (exposed %s)" % [
        Regions.stat_exposed, Regions.stat_dmg["resisted"], Regions.stat_dmg["weak"], Regions.stat_dmg["exposed"], Regions.stat_dmg["plain"],
        "on" if Regions.exposed_enabled else "off"])
    print("    reactions: %s" % str(_reaction_counts))
    print("    fusions: %s" % str(_fusion_counts))
    print("    unlocked this run: %s  (achievements %d/%d)" % [str(Progress.run_unlocks), Progress.achievements_count(), Progress.ACHIEVEMENTS.size()])
    if label == "END":
        _print_fusion_summary()


## [FUSION]: fusions and cataclysms this run by tier, damage share by tier (DoTs count for
## the tier that set them), the top names by count and by share of fusion damage.
## [FUSION-CHECK]: the termination proof (no context above tier 4, at most the room budget of
## fusions in one frame, no product made at or below its own tier), PASS or FAIL.
func _print_fusion_summary() -> void:
    var s: Dictionary = Telemetry.fusion_summary()
    var fus: Dictionary = s["fusions"]
    var cat: Dictionary = s["cataclysms"]
    var td: Array = s["tier_dmg"]
    var fd: Dictionary = s["fusion_dmg"]
    var total := 0.0
    for v in td:
        total += float(v)
    var n3 := 0
    var n4 := 0
    for k in fus:
        n3 += int(fus[k])
    for k in cat:
        n4 += int(cat[k])
    var fdt := 0.0
    for k in fd:
        fdt += float(fd[k])
    var names: Array = fd.keys()
    names.sort_custom(func(x, y): return float(fd[x]) > float(fd[y]))
    var top_dmg: Array = []
    for nm in names.slice(0, 6):
        top_dmg.append("%s %.0f%%" % [nm, 100.0 * float(fd[nm]) / maxf(fdt, 1.0)])
    var all_counts: Dictionary = fus.duplicate()
    all_counts.merge(cat)
    var by_count: Array = all_counts.keys()
    by_count.sort_custom(func(x, y): return int(all_counts[x]) > int(all_counts[y]))
    var top_n: Array = []
    for nm in by_count.slice(0, 6):
        top_n.append("%s:%d" % [nm, int(all_counts[nm])])
    var shares: Array = []
    for t in 5:
        shares.append("t%d=%.1f%%" % [t, 100.0 * float(td[t]) / maxf(total, 1.0)])
    print("[FUSION] enabled=%s t3=%d (%d kinds) t4=%d (%d kinds) fields=%d compounds enemy=%d patch=%d budget_denied=%d gap_denied=%d dmg %s total=%.0f fusion_dmg=%.0f" % [
        Elements.fusions_enabled, n3, fus.size(), n4, cat.size(), int(Elements.dbg["fields"]), int(Elements.dbg["compounds_enemy"]),
        int(Elements.dbg["compounds_patch"]), int(Elements.dbg["denied_budget"]), int(Elements.dbg["denied_gap"]), " ".join(shares), total, fdt])
    print("    top by count: %s" % ", ".join(top_n))
    print("    top by fusion damage: %s" % ", ".join(top_dmg))
    print("    discovered this run: %d fusions, %d cataclysms" % [Progress.run_fusion_discoveries.size(), Progress.run_cataclysm_discoveries.size()])
    print("    [FUSION-JSON] %s" % JSON.stringify({ "counts": all_counts, "dmg": fd, "tier_dmg": td }))
    var d: Dictionary = Elements.dbg
    var ok := int(d["max_ctx"]) <= Fusions.MAX_TIER and int(d["violations"]) == 0 and int(d["max_frame"]) <= Fusions.MAX_FUSIONS_PER_SEC + 1
    print("[FUSION-CHECK] %s max_ctx=%d max_fusions_in_frame=%d max_depth=%d violations=%d" % [
        "PASS" if ok else "FAIL", int(d["max_ctx"]), int(d["max_frame"]), int(d["max_depth"]), int(d["violations"])])
    if not ok:
        push_error("fusion termination check failed: %s" % str(d))
    # Brotato's rule: nothing finishes emerging within Enemy.SPAWN_ASSERT of a player.
    print("[SPAWN-CHECK] %s landed=%d moved=%d close=%d" % [
        "PASS" if Enemy.spawn_close == 0 else "FAIL", Enemy.spawn_landed, Enemy.spawn_moved, Enemy.spawn_close])
