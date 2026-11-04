class_name Main
extends Node2D
## Run orchestrator: players, floors, the current room, scrap, camera, HUD,
## couch co-op joins, and the self-test bot.

const MAX_PLAYERS := 4
const FLOORS := 3
const CAMERA_PAD := 90.0

var players: Array[Player] = []
var fx: Fx
var hud: Hud
var camera: Camera2D
var pause_menu: PauseMenu
var _shake := 0.0
var _help_timer := 20.0

var floor_number := 0
var rooms: Dictionary = {}          # Vector2i -> RoomData
var current: Room = null
var current_pos := Vector2i.ZERO
var scrap := 0
var rooms_cleared := 0
var total_kills := 0
var game_over := false
var victory := false
var show_help := true
var message := ""
var _message_time := 0.0
var _joined_devices: Dictionary = {}
var _transitioning := false

# Self-test: `godot --path . -- --autotest` plays by itself, saves screenshots to
# res://autotest/ and prints progress. Used to verify builds without a human.
var autotest := false
var _clock := 0.0
var _bot_idle := 0.0
var _bot_obstacle_time := 0.0
var _bot_skip: Dictionary = {}
var _shots_taken: Dictionary = {}
var _reaction_counts: Dictionary = {}


func _ready() -> void:
    randomize()

    fx = Fx.new()
    fx.main = self
    add_child(fx)

    camera = Camera2D.new()
    camera.position_smoothing_enabled = true
    camera.position_smoothing_speed = 7.0
    add_child(camera)
    camera.make_current()

    RenderingServer.set_default_clear_color(Art.CLEAR)

    var layer := CanvasLayer.new()
    add_child(layer)
    layer.add_child(_make_vignette())
    hud = Hud.new()
    hud.main = self
    layer.add_child(hud)
    pause_menu = PauseMenu.new(self)
    add_child(pause_menu)

    var pads := Input.get_connected_joypads()
    _spawn_player(0 if pads.has(0) else -1, true)
    Input.joy_connection_changed.connect(_on_joy_connection_changed)

    Elements.reaction_fired.connect(_count_reaction)
    Progress.unlocked.connect(_on_unlocked)
    var args := OS.get_cmdline_user_args()
    autotest = args.has("--autotest")
    if args.has("--obstacle-test") or args.has("--start-shot"):
        # Test hooks never touch the real save.
        Progress.save_path = "user://save_autotest.json"
        Progress.reset()
    if autotest:
        _setup_autotest()

    Progress.start_run()
    start_floor(1)
    if OS.get_cmdline_user_args().has("--obstacle-test"):
        _obstacle_test()
    if OS.get_cmdline_user_args().has("--start-shot"):
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
        await get_tree().create_timer(0.8).timeout
        await _screenshot("res://autotest/start.png")
        get_tree().quit()


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
    hud.toast("%s: unlocked %s" % [achievement_name, Progress.unlock_label(unlock_id)])
    Sfx.play("unlock")


func _end_run(won: bool) -> void:
    Progress.end_run(won, floor_number, total_kills)
    if not autotest:
        get_tree().create_timer(1.6).timeout.connect(pause_menu.show_menu)


func shake(amount: float) -> void:
    _shake = maxf(_shake, amount)


func is_device_joined(device: int) -> bool:
    return _joined_devices.has(device)


# --- Floors and rooms --------------------------------------------------------


func start_floor(n: int) -> void:
    floor_number = n
    rooms = FloorGen.generate(n)
    for p in players:
        p.pressure = 0.0
        if not p.alive:
            p.alive = true
            p.add_to_group("players")
        p.hp = maxf(p.hp, p.max_hp * 0.6)
    enter_room(Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2), Vector2i.ZERO)
    announce("Floor %d" % n)


## Load the room at `pos`. `moved` is the direction the party travelled to get there,
## or ZERO when dropped in (floor start).
func enter_room(pos: Vector2i, moved: Vector2i) -> void:
    _transitioning = false
    Sfx.stop_all()
    if current != null:
        current.collect_all_scrap()
        remove_child(current)
        current.queue_free()
    for c in get_children():
        if c is Projectile:
            c.queue_free()

    current_pos = pos
    current = Room.new(rooms[pos], self)
    add_child(current)
    move_child(current, 0)
    current.door_entered.connect(_on_door_entered)

    var base := Vector2.ZERO if moved == Vector2i.ZERO else current.entry_position(-moved)
    var across := Vector2(moved).orthogonal() if moved != Vector2i.ZERO else Vector2.RIGHT
    for i in players.size():
        players[i].global_position = base + across * (float(i) - float(players.size() - 1) / 2.0) * 40.0
        players[i].velocity = Vector2.ZERO

    var r := current.rect.grow(Room.WALL + CAMERA_PAD)
    camera.limit_left = int(r.position.x)
    camera.limit_top = int(r.position.y)
    camera.limit_right = int(r.end.x)
    camera.limit_bottom = int(r.end.y)
    camera.position = _party_center()
    camera.reset_smoothing()


func _on_door_entered(dir: Vector2i) -> void:
    if _transitioning:
        return
    _transitioning = true
    call_deferred("enter_room", current_pos + dir, dir)


func on_room_cleared(_room: Room) -> void:
    rooms_cleared += 1
    announce("Room cleared")


func next_floor() -> void:
    Progress.add("floors")
    if floor_number >= FLOORS:
        victory = true
        announce("You cleared the dungeon!")
        _end_run(true)
    else:
        call_deferred("start_floor", floor_number + 1)


## Enemy scaling input: grows with floors and with every room the party clears.
## Starts at 2 so the first arena already bites.
func difficulty() -> int:
    return 2 + (floor_number - 1) * 3 + rooms_cleared


func add_scrap(v: int) -> void:
    var gain := 0.0
    for p in players:
        gain = maxf(gain, p.stat("scrap_gain"))
    scrap += ceili(float(v) * (1.0 + gain))


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
    # Naked start: no guns. The entrance offers a pick of two; late joiners get a random one.
    if current != null:
        if current.data.type == RoomData.Type.START and floor_number == 1:
            current.add_gun_choice()
        else:
            var pool: Array = Guns.ids()
            if not pool.is_empty():
                p.add_gun(pool.pick_random())
    if device >= 0:
        _joined_devices[device] = true
    return p


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


func _on_player_died(_p: Player) -> void:
    for p in players:
        if p.alive:
            return
    game_over = true
    _end_run(false)


# --- Frame -----------------------------------------------------------------


func _process(delta: float) -> void:
    if autotest:
        _autotest_tick(delta)
    _handle_joins()
    camera.position = _party_center()
    camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
    _shake = move_toward(_shake, 0.0, 28.0 * delta)
    _message_time = maxf(0.0, _message_time - delta)
    if _message_time <= 0.0:
        message = ""
    if show_help and _help_timer > 0.0:
        _help_timer -= delta
        if _help_timer <= 0.0:
            show_help = false


func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    var key: InputEventKey = event
    match key.physical_keycode:
        KEY_R:
            _restart()
        KEY_F1:
            show_help = not show_help
            _help_timer = 0.0
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


func _setup_autotest() -> void:
    # Fresh, separate save so the bot exercises unlocks without touching the real one.
    Progress.save_path = "user://save_autotest.json"
    Progress.reset()
    var p := players[0]
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
    if current == null or players.is_empty():
        return
    var p := players[0]
    var t := p.nearest_enemy(900.0)
    var circle := Vector2.RIGHT.rotated(_clock * 0.6)
    p.input.force_fire = t != null
    if t != null:
        var to_enemy := (t.global_position - p.global_position).normalized()
        p.input.force_aim = to_enemy
        p.input.force_move = (-to_enemy * 0.8 + circle * 0.6).normalized()
        var inner := current.rect.grow(-120.0)
        if not inner.has_point(p.global_position):
            p.input.force_move = (inner.get_center() - p.global_position).normalized()
        _bot_idle = 0.0
    else:
        p.input.force_aim = Vector2.ZERO
        _bot_idle += delta
        _bot_navigate(p)
    if fmod(_clock, 6.0) < delta:
        p.vent()
    if _clock >= 12.0 and p.auto_aim:
        p.auto_aim = false
    if _clock >= 30.0 and not _shots_taken.has("pause"):
        _shots_taken["pause"] = true
        pause_menu.show_for_test()
    for shot_time in [15.0, 60.0, 120.0, 180.0, 240.0]:
        if _clock >= shot_time and not _shots_taken.has(shot_time):
            _shots_taken[shot_time] = true
            _screenshot("res://autotest/t%03d.png" % int(shot_time))
    var limit := 70.0 if OS.get_cmdline_user_args().has("--short") else 300.0
    if _clock >= limit or game_over or victory:
        _print_stats("END")
        get_tree().quit()


func _bot_navigate(p: Player) -> void:
    var room := current
    # Pedestals worth using.
    for ped in room.pedestals:
        if not is_instance_valid(ped):
            continue
        var o: Dictionary = ped.offer
        var want := false
        match o["kind"]:
            "sigil", "stairs":
                want = true
            "gun":
                want = o["price"] <= scrap and p.can_carry(Guns.make(o["id"]))
            "carry", "repair", "item":
                want = o["price"] <= scrap
        if want:
            var d := ped.global_position - p.global_position
            if d.length() < 30.0:
                room.activate(ped, p)
                _bot_idle = 0.0
            else:
                p.input.force_move = d.normalized()
            return
    # Obstacles the bot can clear with what it carries.
    for dir in room.data.doors.keys():
        var ob: String = room.data.doors[dir]["obstacle"]
        if ob == "" or _bot_skip.has([current_pos, dir]):
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
        p.primary = gun
        var target := room.door_world_position(dir)
        var to := target - p.global_position
        p.input.force_aim = to.normalized()
        p.input.force_fire = true
        p.input.force_move = to.normalized() if to.length() > 130.0 else Vector2.ZERO
        return
    _bot_obstacle_time = 0.0
    if not room.data.cleared:
        p.input.force_move = -p.global_position.normalized() if p.global_position.length() > 60.0 else Vector2.ZERO
        return
    var dir := _bot_next_dir()
    if dir == Vector2i.ZERO:
        p.input.force_move = Vector2.ZERO
        return
    if _bot_idle > 12.0:
        _print_stats("STUCK, teleporting")
        _bot_idle = 0.0
        enter_room(current_pos + dir, dir)
        return
    p.input.force_move = (room.door_world_position(dir) - p.global_position).normalized()


## Breadth-first search through passable doors to the nearest unvisited room.
func _bot_next_dir() -> Vector2i:
    var start := current_pos
    var prev: Dictionary = { start: start }
    var queue: Array = [start]
    var goal := Vector2i(-1, -1)
    while not queue.is_empty():
        var cur: Vector2i = queue.pop_front()
        var r: RoomData = rooms[cur]
        if cur != start and not r.visited:
            goal = cur
            break
        for d in r.doors.keys():
            if r.doors[d]["obstacle"] != "":
                continue
            var n: Vector2i = r.doors[d]["to"]
            if prev.has(n):
                continue
            prev[n] = cur
            queue.append(n)
    if goal.x < 0:
        return Vector2i.ZERO
    var step := goal
    while prev[step] != start:
        step = prev[step]
    return step - start


func _screenshot(path: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png(path)


func _print_stats(label: String) -> void:
    var p := players[0]
    var visited := 0
    for r in rooms.values():
        if r.visited:
            visited += 1
    print("[%s] t=%.0f floor=%d room=%s visited=%d/%d cleared=%d kills=%d scrap=%d hp=%.0f weight=%d/%d" % [
        label, _clock, floor_number, current.data.type_name() if current else "-", visited, rooms.size(),
        rooms_cleared, total_kills, scrap, p.hp, p.total_weight(), p.weight_capacity])
    print("    reactions: %s" % str(_reaction_counts))
    print("    unlocked this run: %s  (achievements %d/%d)" % [str(Progress.run_unlocks), Progress.achievements_count(), Progress.ACHIEVEMENTS.size()])
