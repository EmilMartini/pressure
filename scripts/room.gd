class_name Room
extends Node2D
## One room of the dungeon, rebuilt from its RoomData every time the party enters.
## Owns walls, doors, pedestals, the enemies and pickups inside, and the fight logic
## for arena waves, challenges and the boss.

signal door_entered(dir: Vector2i)

const SIZE := Vector2(1500, 950)
const WALL := 60.0
const GAP := 150.0

var data: RoomData
var main: Main
var rect := Rect2(-SIZE / 2.0, SIZE)
var enemies: Node2D
var pickups: Node2D
var doors: Dictionary = {}          # dir -> Door
var pedestals: Array[Pedestal] = []

var active := false                 # a fight is running
var wave_time_left := 0.0
var wave_duration := 0.0
var boss: Enemy = null

var _elites_alive := 0
var _spawn_timer := 0.0
var _elite_timer := INF
var _add_timer := 0.0
var _add_time_left := 0.0


func _init(p_data: RoomData, p_main: Main) -> void:
    data = p_data
    main = p_main
    name = "Room"


func _ready() -> void:
    enemies = Node2D.new()
    enemies.name = "Enemies"
    add_child(enemies)
    pickups = Node2D.new()
    pickups.name = "Pickups"
    add_child(pickups)
    _build_floor()
    _build_walls()
    _build_doors()
    _build_pedestals()

    data.visited = true
    data.discovered = true
    for d in data.doors.keys():
        if data.doors[d]["obstacle"] == "":
            main.rooms[data.doors[d]["to"]].discovered = true
    if data.loose_scrap > 0:
        _drop_scrap(Vector2(0, 80), data.loose_scrap, 8)
        data.loose_scrap = 0
    if data.is_safe():
        data.cleared = true
    if not data.cleared:
        match data.type:
            RoomData.Type.ARENA:
                _begin_arena()
            RoomData.Type.BOSS:
                _begin_boss()
            # A challenge waits for someone to touch the sigil.
    _apply_doors()


func _process(delta: float) -> void:
    _handle_interact()
    if not active:
        return
    match data.type:
        RoomData.Type.ARENA:
            _tick_arena(delta)
        RoomData.Type.CHALLENGE:
            _tick_challenge(delta)
        RoomData.Type.BOSS:
            _tick_boss(delta)


# --- Fights ------------------------------------------------------------------


func _begin_arena() -> void:
    data.started = true
    active = true
    var diff := main.difficulty()
    wave_duration = clampf(16.0 + 2.5 * float(diff), 16.0, 40.0)
    wave_time_left = wave_duration
    _spawn_timer = 0.8
    _elite_timer = wave_duration * 0.45 if diff >= 2 else INF
    main.announce("Survive %d seconds" % int(wave_duration))


func _tick_arena(delta: float) -> void:
    var diff := main.difficulty()
    wave_time_left -= delta
    _spawn_timer -= delta
    _elite_timer -= delta
    if _spawn_timer <= 0.0:
        _spawn_timer = maxf(0.4, 1.2 - 0.05 * float(diff))
        _spawn_group()
    if _elite_timer <= 0.0:
        _elite_timer = INF
        _spawn_elite(1 + int(diff >= 6))
    if wave_time_left <= 0.0:
        _finish_fight(6)


func begin_challenge() -> void:
    data.started = true
    active = true
    _elites_alive = 2
    for i in 2:
        _spawn_elite(1)
    _add_time_left = 25.0
    _add_timer = 0.0
    main.announce("Challenge: kill both elites")
    _apply_doors()


func _tick_challenge(delta: float) -> void:
    _add_time_left -= delta
    _add_timer -= delta
    if _add_time_left > 0.0 and _add_timer <= 0.0:
        _add_timer = 1.6
        _spawn_group()
    if _elites_alive <= 0:
        var pool: Array = Guns.ids()
        pool.shuffle()
        for i in mini(3, pool.size()):
            data.stock.append(FloorGen.offer("gun", pool[i], 0))
        _finish_fight(20)
        _build_pedestals()


func _begin_boss() -> void:
    data.started = true
    active = true
    boss = _spawn_enemy("boss", Vector2(0, -220))
    var pairs := Elements.available_reactions(main.party_elements())
    boss.sequence = _random_sequence(pairs, 2)
    boss.reshield_sequence = _random_sequence(pairs, 2)
    _add_timer = 5.0
    main.announce("BOSS: break the shield in order")


func _tick_boss(delta: float) -> void:
    _add_timer -= delta
    if _add_timer <= 0.0:
        _add_timer = maxf(4.0, 8.0 - 0.3 * float(main.difficulty()))
        _spawn_group()
    if boss == null or not is_instance_valid(boss):
        boss = null
        data.stock.append(FloorGen.offer("stairs", "", 0))
        _finish_fight(30)
        _build_pedestals()


func _finish_fight(bonus_scrap: int) -> void:
    active = false
    data.cleared = true
    for e in enemies.get_children():
        e.vanish()
    _drop_scrap(Vector2.ZERO, bonus_scrap, 6)
    main.on_room_cleared(self)
    _apply_doors()


# --- Spawning ----------------------------------------------------------------


func _spawn_group() -> void:
    var diff := main.difficulty()
    var count := mini(7, 2 + diff / 3 + (main.players.size() - 1))
    for i in count:
        var roll := randf()
        var type := "grunt"
        if roll < 0.25:
            type = "runner"
        elif roll < 0.37 and diff >= 1:
            type = "brute"
        var e := _spawn_enemy(type, _spawn_point())
        if diff >= 2 and randf() < minf(0.6, 0.06 * float(diff)):
            var kinds := main.party_elements()
            if not kinds.is_empty():
                e.immune_to = kinds.pick_random()


func _spawn_enemy(type: String, pos: Vector2) -> Enemy:
    var e := Enemy.new()
    e.configure(type, main.difficulty())
    e.position = pos
    e.died.connect(_on_enemy_died)
    enemies.add_child(e)
    return e


func _spawn_elite(count: int) -> void:
    var diff := main.difficulty()
    var length := 1 + int(diff >= 4) + int(diff >= 8)
    for i in count:
        var e := _spawn_enemy("elite", _spawn_point())
        e.sequence = _random_sequence(Elements.available_reactions(main.party_elements()), length)
        Elements.reaction_fired.emit("ELITE", e.global_position, Color(1.0, 0.85, 0.3))


func _random_sequence(pairs: Array[Vector2i], length: int) -> Array[Vector2i]:
    var seq: Array[Vector2i] = []
    if pairs.is_empty():
        return seq
    for i in length:
        seq.append(pairs.pick_random())
    return seq


func _spawn_point() -> Vector2:
    for attempt in 12:
        var p := _perimeter_point()
        var ok := true
        for pl in main.players:
            if pl.global_position.distance_to(p) < 320.0:
                ok = false
        if ok:
            return p
    return _perimeter_point()


func _perimeter_point() -> Vector2:
    var inner := rect.grow(-50.0)
    match randi() % 4:
        0:
            return Vector2(randf_range(inner.position.x, inner.end.x), inner.position.y)
        1:
            return Vector2(randf_range(inner.position.x, inner.end.x), inner.end.y)
        2:
            return Vector2(inner.position.x, randf_range(inner.position.y, inner.end.y))
    return Vector2(inner.end.x, randf_range(inner.position.y, inner.end.y))


func _on_enemy_died(e: Enemy) -> void:
    main.total_kills += 1
    Progress.add("kills")
    if e.kind_name == "boss":
        Progress.add("bosses")
    elif e.is_elite:
        Progress.add("elites")
    _drop_scrap(e.global_position, e.scrap_value, mini(e.scrap_value, 5))
    if e.is_elite and data.type == RoomData.Type.CHALLENGE:
        _elites_alive -= 1


func _drop_scrap(pos: Vector2, total: int, pieces: int) -> void:
    if total <= 0:
        return
    pieces = maxi(1, pieces)
    var each := total / pieces
    var rem := total - each * pieces
    for i in pieces:
        var s := Scrap.new(each + (1 if i < rem else 0), main)
        s.position = pos
        pickups.add_child(s)


func collect_all_scrap() -> void:
    for s in pickups.get_children():
        if s is Scrap:
            main.add_scrap(s.value)


# --- Doors and walls -------------------------------------------------------


func _build_doors() -> void:
    for d in data.doors.keys():
        var door := Door.new(d, GAP, WALL)
        door.position = Vector2(d) * (SIZE / 2.0 + Vector2(WALL / 2.0, WALL / 2.0))
        add_child(door)
        doors[d] = door
        door.entered.connect(func(dir: Vector2i): door_entered.emit(dir))
        var ob: String = data.doors[d]["obstacle"]
        if ob != "":
            door.set_obstacle(ob)
            door.obstacle_cleared.connect(_on_obstacle_cleared)


func _on_obstacle_cleared(dir: Vector2i) -> void:
    data.doors[dir]["obstacle"] = ""
    main.rooms[data.doors[dir]["to"]].discovered = true


func _apply_doors() -> void:
    var open := not active and (data.cleared or data.type == RoomData.Type.CHALLENGE)
    for d in doors.keys():
        var door: Door = doors[d]
        if door.state == Door.State.OBSTACLE:
            continue
        door.set_state(Door.State.OPEN if open else Door.State.LOCKED)


func door_world_position(dir: Vector2i) -> Vector2:
    return doors[dir].global_position


## Where the party appears when entering from a given side of this room.
func entry_position(side: Vector2i) -> Vector2:
    return Vector2(side) * (SIZE / 2.0 - Vector2(90.0, 90.0))


func _build_walls() -> void:
    var body := StaticBody2D.new()
    body.name = "Walls"
    body.collision_layer = Player.LAYER_WALLS
    body.collision_mask = 0
    add_child(body)
    var half := SIZE / 2.0
    for d in FloorGen.DIRS:
        var has_door := data.doors.has(d)
        if d.y != 0:
            var y := float(d.y) * (half.y + WALL / 2.0)
            if has_door:
                var seg := (SIZE.x + 2.0 * WALL - GAP) / 2.0
                _wall(body, Vector2(-(GAP / 2.0 + seg / 2.0), y), Vector2(seg, WALL))
                _wall(body, Vector2(GAP / 2.0 + seg / 2.0, y), Vector2(seg, WALL))
                _wall(body, Vector2(0, float(d.y) * (half.y + WALL * 1.5)), Vector2(GAP + WALL, WALL))
            else:
                _wall(body, Vector2(0, y), Vector2(SIZE.x + 2.0 * WALL, WALL))
        else:
            var x := float(d.x) * (half.x + WALL / 2.0)
            if has_door:
                var seg := (SIZE.y + 2.0 * WALL - GAP) / 2.0
                _wall(body, Vector2(x, -(GAP / 2.0 + seg / 2.0)), Vector2(WALL, seg))
                _wall(body, Vector2(x, GAP / 2.0 + seg / 2.0), Vector2(WALL, seg))
                _wall(body, Vector2(float(d.x) * (half.x + WALL * 1.5), 0), Vector2(WALL, GAP + WALL))
            else:
                _wall(body, Vector2(x, 0), Vector2(WALL, SIZE.y + 2.0 * WALL))


func _wall(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
    var shape := CollisionShape2D.new()
    var r := RectangleShape2D.new()
    r.size = size
    shape.shape = r
    shape.position = center
    body.add_child(shape)
    var bricks := _tiled(Art.WALL, size, Art.WALL_TINT)
    bricks.position = center
    bricks.z_index = -1
    add_child(bricks)


## A Sprite2D that repeats a 16px tile at 2x over `size`.
func _tiled(tex: Texture2D, size: Vector2, tint: Color) -> Sprite2D:
    var s := Sprite2D.new()
    s.texture = tex
    s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    s.region_enabled = true
    s.region_rect = Rect2(Vector2.ZERO, size / 2.0)
    s.scale = Vector2(2, 2)
    s.modulate = tint
    return s


func _build_floor() -> void:
    var floor_sprite := _tiled(Art.FLOOR, SIZE, Art.FLOOR_TINT)
    floor_sprite.z_index = -2
    add_child(floor_sprite)
    # Bones, skulls and rubble, fixed per room so they do not shuffle on re-entry.
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(data.pos) + main.floor_number * 7919
    var decals: Array = Art.TILES["decals"]
    for i in 9:
        var d := Art.sprite(decals[rng.randi() % decals.size()], 2.0, Art.DECAL_TINT)
        d.position = Vector2(rng.randf_range(rect.position.x + 80, rect.end.x - 80), rng.randf_range(rect.position.y + 80, rect.end.y - 80))
        d.rotation = float(rng.randi() % 4) * PI / 2.0
        d.z_index = -1
        add_child(d)


# --- Pedestals and interaction ---------------------------------------------


func _build_pedestals() -> void:
    for p in pedestals:
        if is_instance_valid(p):
            p.queue_free()
    pedestals.clear()
    var offers: Array = data.stock.filter(func(o): return not o["taken"])
    var n := offers.size()
    for i in n:
        var ped := Pedestal.new(offers[i])
        ped.position = Vector2((float(i) - float(n - 1) / 2.0) * 170.0, 0.0)
        add_child(ped)
        pedestals.append(ped)


func _handle_interact() -> void:
    for ped in pedestals:
        if not is_instance_valid(ped):
            continue
        var near := main.nearest_alive_player(ped.global_position)
        ped.highlighted = near != null and near.global_position.distance_to(ped.global_position) <= Pedestal.RANGE
    for pl in main.players:
        if not pl.alive or not pl.input.just_pressed("interact"):
            continue
        var best: Pedestal = null
        var best_d := Pedestal.RANGE
        for ped in pedestals:
            if not is_instance_valid(ped):
                continue
            var d := ped.global_position.distance_to(pl.global_position)
            if d < best_d:
                best_d = d
                best = ped
        if best != null:
            activate(best, pl)


func activate(ped: Pedestal, pl: Player) -> void:
    var o := ped.offer
    match o["kind"]:
        "gun":
            var gdata := Guns.make(o["id"])
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                return
            if not pl.can_carry(gdata):
                pl.say("Too heavy: %s is %d, %d free" % [gdata.display_name, gdata.weight, pl.weight_capacity - pl.total_weight()])
                return
            main.scrap -= o["price"]
            pl.add_gun(o["id"])
            o["taken"] = true
            if o["price"] == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE]:
                for other in data.stock:
                    if other["kind"] == "gun":
                        other["taken"] = true
        "carry":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                return
            main.scrap -= o["price"]
            pl.weight_capacity += o["amount"]
            pl.say("Carry capacity %d" % pl.weight_capacity)
            o["taken"] = true
        "repair":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                return
            main.scrap -= o["price"]
            pl.hp = minf(pl.max_hp, pl.hp + o["amount"])
            pl.say("Repaired")
            o["taken"] = true
        "stairs":
            main.next_floor()
            return
        "sigil":
            o["taken"] = true
            begin_challenge()
    _build_pedestals()


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    # Inner shadow along the walls so the floor reads as sunken.
    draw_rect(rect.grow(-10.0), Color(0, 0, 0, 0.35), false, 20.0)
    draw_string(Art.FONT, Vector2(-200, -rect.size.y / 2.0 + 44), data.type_name().to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 400, 30, Color(data.color(), 0.3))
