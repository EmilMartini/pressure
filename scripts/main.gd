class_name Main
extends Node2D
## The arena: players, waves, elites, resistance drift, camera, HUD, couch co-op joins.
## Everything is built in code for now so the project reads as plain scripts.

const ARENA := Rect2(-1100, -700, 2200, 1400)
const WALL := 60.0
const INTERMISSION := 5.0
const START_DELAY := 3.0
const MAX_PLAYERS := 4
const STARTING_GUNS := ["water_pistol", "arc_rifle"]

var players: Array[Player] = []
var fx: Fx
var hud: Hud
var camera: Camera2D

var wave := 0
var wave_duration := 0.0
var wave_time_left := 0.0
var intermission := START_DELAY
var total_kills := 0
var game_over := false
var show_help := true

var _spawn_timer := 0.0
var _elite_timer := 0.0
var _enemies: Node2D
var _joined_devices: Dictionary = {}

# Self-test: `godot --path . -- --autotest` plays by itself, saves screenshots to
# res://autotest/ and prints reaction counts. Used to verify builds without a human.
var autotest := false
var _frame := 0
var _clock := 0.0
var _shots_taken: Dictionary = {}
var _reaction_counts: Dictionary = {}


func _ready() -> void:
    randomize()
    _build_walls()

    _enemies = Node2D.new()
    _enemies.name = "Enemies"
    add_child(_enemies)

    fx = Fx.new()
    add_child(fx)

    camera = Camera2D.new()
    camera.position_smoothing_enabled = true
    camera.position_smoothing_speed = 6.0
    camera.limit_left = int(ARENA.position.x)
    camera.limit_top = int(ARENA.position.y)
    camera.limit_right = int(ARENA.end.x)
    camera.limit_bottom = int(ARENA.end.y)
    add_child(camera)
    camera.make_current()

    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Hud.new()
    hud.main = self
    layer.add_child(hud)

    var pads := Input.get_connected_joypads()
    _spawn_player(0 if pads.has(0) else -1, true)
    Input.joy_connection_changed.connect(_on_joy_connection_changed)

    Elements.reaction_fired.connect(_count_reaction)
    autotest = OS.get_cmdline_user_args().has("--autotest")
    if autotest:
        _setup_autotest()


func _count_reaction(reaction_name: String, _pos: Vector2, _col: Color) -> void:
    _reaction_counts[reaction_name] = _reaction_counts.get(reaction_name, 0) + 1


func _setup_autotest() -> void:
    var p := players[0]
    p.input.force_fire = true
    for id in Guns.ids():
        var owned := false
        for g in p.guns:
            if g.data.id == id:
                owned = true
        if not owned:
            p.add_gun(id)
    intermission = 0.5
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))


func _autotest_tick(delta: float) -> void:
    var p := players[0]
    _clock += delta
    # Kite: back away from the nearest enemy while circling, aim at it for real hits.
    var t := p._nearest_enemy(900.0)
    var circle := Vector2.RIGHT.rotated(_clock * 0.6)
    if t != null:
        var to_enemy := (t.global_position - p.global_position).normalized()
        p.input.force_aim = to_enemy
        p.input.force_move = (-to_enemy * 0.8 + circle * 0.6).normalized()
    else:
        p.input.force_aim = Vector2.ZERO
        p.input.force_move = circle
    # Stay off the walls.
    var inner := ARENA.grow(-150.0)
    if not inner.has_point(p.global_position):
        p.input.force_move = (inner.get_center() - p.global_position).normalized()
    if fmod(_clock, 6.0) < delta:
        p.vent()
    if _clock >= 12.0 and p.auto_aim:
        p.auto_aim = false
        p.say("Manual aim")
    for shot_time in [10.0, 45.0, 75.0, 95.0]:
        if _clock >= shot_time and not _shots_taken.has(shot_time):
            _shots_taken[shot_time] = true
            _screenshot("res://autotest/t%03d.png" % int(shot_time))
    if _clock >= 110.0 or game_over:
        _print_stats("END")
        get_tree().quit()


func _screenshot(path: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png(path)


func _print_stats(label: String) -> void:
    var p := players[0]
    print("[%s] frame=%d wave=%d kills=%d enemies=%d hp=%.0f pressure=%.0f focus=%.2f weight=%d/%d" % [
        label, _frame, wave, total_kills, enemy_count(), p.hp, p.pressure, p.focus, p.total_weight(), p.weight_capacity])
    print("    reactions: %s" % str(_reaction_counts))


func enemy_count() -> int:
    return _enemies.get_child_count()


# --- Players ---------------------------------------------------------------


func _spawn_player(device: int, keyboard: bool) -> Player:
    var p := Player.new(players.size(), PlayerInput.new(device, keyboard))
    p.position = Vector2(randf_range(-60, 60), randf_range(-60, 60))
    add_child(p)
    players.append(p)
    p.died.connect(_on_player_died)
    for id in STARTING_GUNS:
        p.add_gun(id)
    if p.guns.size() > 1:
        p.primary = p.guns[1]
    p.say("Primary: %s" % p.primary.data.display_name)
    if device >= 0:
        _joined_devices[device] = true
    return p


func _on_joy_connection_changed(device: int, connected: bool) -> void:
    # Pad 0 belongs to player 1 alongside the keyboard, even if it shows up late.
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


func _alive_players() -> Array[Player]:
    var out: Array[Player] = []
    for p in players:
        if p.alive:
            out.append(p)
    return out


func _party_center() -> Vector2:
    var group := _alive_players()
    if group.is_empty():
        group = players
    var sum := Vector2.ZERO
    for p in group:
        sum += p.global_position
    return sum / float(maxi(1, group.size()))


func _party_elements() -> Array:
    var kinds := []
    for p in players:
        for k in p.element_kinds():
            if not kinds.has(k):
                kinds.append(k)
    return kinds


# --- Waves -----------------------------------------------------------------


func _process(delta: float) -> void:
    _frame += 1
    if autotest:
        _autotest_tick(delta)
    _handle_joins()
    camera.position = _party_center()

    if game_over:
        for p in players:
            if p.input.just_pressed("start"):
                _restart()
        return

    if intermission > 0.0:
        intermission -= delta
        if intermission <= 0.0:
            _start_wave()
        return

    wave_time_left -= delta
    _spawn_timer -= delta
    _elite_timer -= delta
    if _spawn_timer <= 0.0:
        _spawn_timer = maxf(0.3, 1.2 - 0.08 * float(wave))
        _spawn_group()
    if _elite_timer <= 0.0 and wave >= 2:
        _elite_timer = maxf(12.0, 28.0 - float(wave))
        _spawn_elite()
    if wave_time_left <= 0.0:
        _end_wave()


func _start_wave() -> void:
    wave += 1
    wave_duration = 20.0 + 5.0 * float(wave)
    wave_time_left = wave_duration
    _spawn_timer = 0.0
    _elite_timer = 8.0
    for p in players:
        if not p.alive:
            p.alive = true
            p.hp = p.max_hp * 0.5
            p.add_to_group("players")
            p.say("Back up!")


func _end_wave() -> void:
    if autotest:
        _print_stats("WAVE %d END" % wave)
    for e in _enemies.get_children():
        e.queue_free()
    intermission = INTERMISSION
    for p in players:
        p.pressure = 0.0
        p.say("Wave %d cleared" % wave)


func _spawn_group() -> void:
    var count := 2 + (wave + 1) / 2 + (players.size() - 1)
    for i in count:
        var roll := randf()
        var type := "grunt"
        if roll < 0.25:
            type = "runner"
        elif roll < 0.37 and wave >= 2:
            type = "brute"
        _spawn_enemy(type)


func _spawn_enemy(type: String) -> Enemy:
    var e := Enemy.new()
    e.configure(type, wave)
    # Resistance drift: from wave 3 a growing share is immune to an element the party carries.
    if wave >= 3 and randf() < minf(0.6, 0.05 * float(wave)):
        var kinds := _party_elements()
        if not kinds.is_empty():
            e.immune_to = kinds.pick_random()
    e.position = _spawn_point()
    e.died.connect(_on_enemy_died)
    _enemies.add_child(e)
    return e


func _spawn_elite() -> void:
    var e := _spawn_enemy("elite")
    var pairs := Elements.available_reactions(_party_elements())
    if pairs.is_empty():
        return
    var length := 1
    if wave >= 4:
        length += 1
    if wave >= 7:
        length += 1
    var seq: Array[Vector2i] = []
    for i in length:
        seq.append(pairs.pick_random())
    e.sequence = seq
    Elements.reaction_fired.emit("ELITE", e.global_position, Color(1.0, 0.85, 0.3))


func _spawn_point() -> Vector2:
    var center := _party_center()
    var dir := Vector2.RIGHT.rotated(randf() * TAU)
    var pos := center + dir * randf_range(640.0, 820.0)
    var inner := ARENA.grow(-30.0)
    pos.x = clampf(pos.x, inner.position.x, inner.end.x)
    pos.y = clampf(pos.y, inner.position.y, inner.end.y)
    return pos


func _on_enemy_died(e: Enemy) -> void:
    total_kills += 1


# --- Arena -----------------------------------------------------------------


func _build_walls() -> void:
    var body := StaticBody2D.new()
    body.name = "Walls"
    body.collision_layer = Player.LAYER_WALLS
    body.collision_mask = 0
    add_child(body)
    var cx := ARENA.get_center().x
    var cy := ARENA.get_center().y
    var w := ARENA.size.x + WALL * 2.0
    var h := ARENA.size.y + WALL * 2.0
    _wall(body, Vector2(cx, ARENA.position.y - WALL / 2.0), Vector2(w, WALL))
    _wall(body, Vector2(cx, ARENA.end.y + WALL / 2.0), Vector2(w, WALL))
    _wall(body, Vector2(ARENA.position.x - WALL / 2.0, cy), Vector2(WALL, h))
    _wall(body, Vector2(ARENA.end.x + WALL / 2.0, cy), Vector2(WALL, h))


func _wall(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = size
    shape.shape = rect
    shape.position = center
    body.add_child(shape)


func _draw() -> void:
    draw_rect(ARENA, Color(0.10, 0.11, 0.14))
    var grid := Color(1, 1, 1, 0.04)
    var x := ARENA.position.x
    while x <= ARENA.end.x:
        draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), grid, 1.0)
        x += 100.0
    var y := ARENA.position.y
    while y <= ARENA.end.y:
        draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), grid, 1.0)
        y += 100.0
    draw_rect(ARENA, Color(0.5, 0.5, 0.6, 0.6), false, 4.0)


# --- Debug input -----------------------------------------------------------


func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    var key: InputEventKey = event
    match key.physical_keycode:
        KEY_R:
            _restart()
        KEY_F1:
            show_help = not show_help
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
            var ids: Array = Guns.ids()
            var n: int = key.physical_keycode - KEY_1
            if n < ids.size() and not players.is_empty():
                players[0].add_gun(ids[n])


func _restart() -> void:
    get_tree().reload_current_scene()
