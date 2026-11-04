class_name Room
extends Node2D
## One room of the dungeon, rebuilt from its RoomData every time the party enters.
## Owns walls, doors, pedestals, the enemies and pickups inside, and the fight logic
## for arena waves, challenges and the boss.

signal door_entered(dir: Vector2i)

const SIZE := Vector2(1120, 720)
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
    if data.type == RoomData.Type.START and main.floor_number == 1 and data.stock.is_empty():
        for pl in main.players:
            if pl.guns.is_empty():
                add_gun_choice()
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
    Sfx.play("wave_start")


func _tick_arena(delta: float) -> void:
    var diff := main.difficulty()
    var before := ceili(wave_time_left)
    wave_time_left -= delta
    if wave_time_left <= 3.0 and ceili(wave_time_left) != before:
        Sfx.play("tick", 0.0, 0.0)
    _spawn_timer -= delta
    _elite_timer -= delta
    if _spawn_timer <= 0.0:
        _spawn_timer = maxf(0.45, 1.2 - 0.04 * float(diff))
        _spawn_group()
    if _elite_timer <= 0.0:
        _elite_timer = INF
        _spawn_elite(1 + int(diff >= 6))
    if wave_time_left <= 0.0:
        _finish_fight(6)
        _arena_reward()


## Every arena pays out: a free gun or a free item, so power grows with the rooms
## whether or not the shop turns up.
func _arena_reward() -> void:
    var owned: Array = []
    for pl in main.players:
        for g in pl.guns:
            owned.append(g.data.id)
    var guns: Array = Guns.ids().filter(func(id): return not owned.has(id))
    if randf() < 0.5 and not guns.is_empty():
        data.stock.append(FloorGen.offer("gun", guns.pick_random(), 0))
    else:
        data.stock.append(Items.offer(Items.roll(main.difficulty(), Items.Rarity.COMMON), 0))
    _build_pedestals()
    main.announce("Room cleared: take your reward")


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
        var picked: Array = []
        for i in 3:
            var id := Items.roll(main.difficulty() + 2, Items.Rarity.UNCOMMON, picked)
            picked.append(id)
            data.stock.append(Items.offer(id, 0))
        _finish_fight(20)
        _build_pedestals()


func _begin_boss() -> void:
    data.started = true
    active = true
    boss = _spawn_enemy("boss", Vector2(0, -220))
    var pairs := Elements.available_reactions(main.party_elements())
    var hits := 2 + main.difficulty() / 4
    if not pairs.is_empty():
        var first: Vector2i = pairs.pick_random()
        boss.set_shield(first, hits)
        var others: Array = pairs.filter(func(p): return p != first)
        boss.reshield_weakness = others.pick_random() if not others.is_empty() else first
        boss.reshield_hits = hits
    _add_timer = 5.0
    main.announce("BOSS: crack the shield with its reaction")
    Sfx.play("boss")
    Music.play("boss", 1.0)
    main.shake(10.0)


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
        Music.play("run", 2.0)


func _finish_fight(bonus_scrap: int) -> void:
    active = false
    data.cleared = true
    for e in enemies.get_children():
        e.vanish()
    _drop_scrap(Vector2.ZERO, bonus_scrap, 6)
    main.on_room_cleared(self)
    Sfx.play("cleared")
    for pl in main.players:
        if pl.alive:
            Items.fire(pl, "room_clear", { "pos": pl.global_position })
    _apply_doors()


# --- Spawning ----------------------------------------------------------------


func _spawn_group() -> void:
    var diff := main.difficulty()
    var count := mini(8, 3 + diff / 4 + (main.players.size() - 1))
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
    var hits := 1 + int(diff >= 5) + int(diff >= 9)
    var pairs := Elements.available_reactions(main.party_elements())
    for i in count:
        var e := _spawn_enemy("elite", _spawn_point())
        if not pairs.is_empty():
            e.set_shield(pairs.pick_random(), hits)
        Elements.reaction_fired.emit("ELITE", e.global_position, Color(1.0, 0.85, 0.3))


func _spawn_point() -> Vector2:
    for attempt in 12:
        var p := _perimeter_point()
        var ok := true
        for pl in main.players:
            if pl.global_position.distance_to(p) < 260.0:
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
    if e.last_hit_by != null and is_instance_valid(e.last_hit_by):
        e.last_hit_by.gain_xp(float(e.scrap_value) * 2.0 + 1.0)
    _drop_scrap(e.global_position, e.scrap_value, mini(e.scrap_value, 5))
    if e.is_elite and data.type == RoomData.Type.CHALLENGE:
        _elites_alive -= 1
    # Loot: bosses always drop rare or better, elites drop sometimes.
    var inner := rect.grow(-90.0)
    var drop_pos := Vector2(clampf(e.global_position.x, inner.position.x, inner.end.x), clampf(e.global_position.y, inner.position.y, inner.end.y))
    if e.kind_name == "boss":
        data.stock.append(Items.offer(Items.roll(main.difficulty() + 4, Items.Rarity.RARE), 0, Vector2(0, 150)))
        _build_pedestals()
    elif e.is_elite and randf() < 0.55:
        data.stock.append(Items.offer(Items.roll(main.difficulty()), 0, drop_pos))
        _build_pedestals()


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


const FLOOR_TINTS := {
    RoomData.Type.SHOP: Color(0.22, 0.17, 0.12),
    RoomData.Type.TREASURE: Color(0.22, 0.19, 0.11),
    RoomData.Type.BOSS: Color(0.20, 0.09, 0.10),
    RoomData.Type.CHALLENGE: Color(0.17, 0.11, 0.21),
    RoomData.Type.HIDDEN: Color(0.10, 0.17, 0.17),
}


## A decorative sprite from the sheet, placed in room space.
func _prop(coord: Vector2i, pos: Vector2, scale: float, tint: Color, z: int = -1) -> Sprite2D:
    var s := Art.sprite(coord, scale, tint)
    s.position = pos
    s.z_index = z
    add_child(s)
    return s


## Dressing per room type, so a shop reads as a shop before you see a price.
func _dress_room() -> void:
    var half := SIZE / 2.0
    match data.type:
        RoomData.Type.SHOP:
            # A counter along the back wall with a hooded keeper behind it, lanterns at the ends.
            for i in 7:
                _prop(Vector2i(16, 5), Vector2(-240.0 + float(i) * 80.0, -half.y + 110.0), 2.5, Color(0.45, 0.35, 0.25))
            _prop(Vector2i(26, 0), Vector2(0, -half.y + 70.0), 3.0, Color(0.75, 0.68, 0.6), 1)
            _prop(Vector2i(14, 10), Vector2(-300, -half.y + 80.0), 2.5, Color(1.0, 0.75, 0.3), 1)
            _prop(Vector2i(14, 10), Vector2(300, -half.y + 80.0), 2.5, Color(1.0, 0.75, 0.3), 1)
            for i in 4:
                _prop(Vector2i(3, 7), Vector2(-half.x + 60.0, -200.0 + float(i) * 120.0), 2.5, Color(0.5, 0.42, 0.35))
                _prop(Vector2i(3, 7), Vector2(half.x - 60.0, -200.0 + float(i) * 120.0), 2.5, Color(0.5, 0.42, 0.35))
        RoomData.Type.TREASURE:
            # The chest, sized by tier, on a dais with gold scattered around it.
            var tier := data.chest_tier
            _prop(Vector2i(9, 11), Vector2(0, -170.0), 3.5 + float(tier), Color(1.0, 0.8, 0.35), 1)
            for i in 8 + tier * 4:
                var a := randf() * TAU
                _prop(Vector2i(45, 16), Vector2(cos(a) * randf_range(90, 220), -170.0 + sin(a) * randf_range(50, 120)), 1.2, Color(0.9, 0.75, 0.3))
            for i in 2:
                _prop(Vector2i(13, 3), Vector2(-200.0 + float(i) * 400.0, -half.y + 90.0), 3.0, Color(0.55, 0.5, 0.45))
        RoomData.Type.BOSS:
            for i in 14:
                var d := _prop(Vector2i(38, 11), Vector2(randf_range(-half.x + 80, half.x - 80), randf_range(-half.y + 80, half.y - 80)), 2.0, Color(0.55, 0.3, 0.3))
                d.rotation = randf() * TAU
            for i in 2:
                _prop(Vector2i(13, 3), Vector2(-280.0 + float(i) * 560.0, -half.y + 90.0), 3.5, Color(0.45, 0.3, 0.3))
        RoomData.Type.CHALLENGE:
            # Weapon racks on the side walls.
            for i in 5:
                _prop(Vector2i(32 + i, 6), Vector2(-half.x + 50.0, -160.0 + float(i) * 80.0), 2.2, Color(0.7, 0.6, 0.8))
                _prop(Vector2i(37 + (i % 2), 7), Vector2(half.x - 50.0, -160.0 + float(i) * 80.0), 2.2, Color(0.7, 0.6, 0.8))
        RoomData.Type.HIDDEN:
            for i in 6:
                _prop(Vector2i(10, 7), Vector2(randf_range(-half.x + 100, half.x - 100), randf_range(-half.y + 100, half.y - 100)), 2.5, Color(0.5, 0.55, 0.5))
        RoomData.Type.START:
            for i in 2:
                _prop(Vector2i(14, 10), Vector2(-120.0 + float(i) * 240.0, -half.y + 70.0), 2.5, Color(1.0, 0.75, 0.3), 1)


func _build_floor() -> void:
    var floor_sprite := _tiled(Art.FLOOR, SIZE, FLOOR_TINTS.get(data.type, Art.FLOOR_TINT))
    floor_sprite.z_index = -2
    add_child(floor_sprite)
    _dress_room()
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
    var row: Array = offers.filter(func(o): return not o.has("pos"))
    var n := row.size()
    var per_row := 4
    var rows := int(ceil(float(n) / float(per_row)))
    for i in n:
        var ped := Pedestal.new(row[i])
        var r := i / per_row
        var in_row := mini(per_row, n - r * per_row)
        var c := i % per_row
        ped.position = Vector2((float(c) - float(in_row - 1) / 2.0) * 150.0, 90.0 + (float(r) - float(rows - 1) / 2.0) * 200.0)
        add_child(ped)
        pedestals.append(ped)
    for o in offers:
        if o.has("pos"):
            var ped := Pedestal.new(o)
            ped.position = o["pos"]
            add_child(ped)
            pedestals.append(ped)


## Two distinct unlocked guns to choose between, for one unarmed player.
func add_gun_choice() -> void:
    var offered: Array = []
    for o in data.stock:
        if o["kind"] == "gun" and not o["taken"]:
            offered.append(o["id"])
    var pool: Array = Guns.ids().filter(func(id): return not offered.has(id))
    pool.shuffle()
    if pool.size() < 2:
        pool = Guns.ids()
        pool.shuffle()
    for i in mini(2, pool.size()):
        var o := FloorGen.offer("gun", pool[i], 0)
        o["choice"] = true
        data.stock.append(o)
    main.announce("Choose your first gun")
    _build_pedestals()


## Put a gun on the floor at a position (dropped from the character sheet).
func add_floor_gun(id: String, pos: Vector2) -> void:
    var inner := rect.grow(-90.0)
    var p := Vector2(clampf(pos.x, inner.position.x, inner.end.x), clampf(pos.y, inner.position.y, inner.end.y))
    var o := FloorGen.offer("gun", id, 0)
    o["pos"] = p
    data.stock.append(o)
    _build_pedestals()


func has_gun_choice() -> bool:
    for o in data.stock:
        if o["kind"] == "gun" and o.get("choice", false) and not o["taken"]:
            return true
    return false


func _handle_interact() -> void:
    for ped in pedestals:
        if not is_instance_valid(ped):
            continue
        var near := main.nearest_alive_player(ped.global_position)
        ped.highlighted = near != null and near.global_position.distance_to(ped.global_position) <= Pedestal.RANGE
        if near != null:
            ped.prompt_key = near.input.prompt("interact")
            ped.prompt_kind = near.input.last_kind
    for pl in main.players:
        if not pl.alive or not pl.input.take_pressed("interact"):
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
                Sfx.play("error")
                return
            if not pl.can_carry(gdata):
                pl.say("Too heavy: %s is %d, %d free" % [gdata.display_name, gdata.weight, pl.weight_capacity - pl.total_weight()])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            pl.add_gun(o["id"])
            Sfx.play("buy")
            o["taken"] = true
            if o.get("choice", false):
                # Entrance pick: once everyone is armed, the rest of the choices vanish.
                var all_armed := true
                for other_pl in main.players:
                    if other_pl.alive and other_pl.guns.is_empty():
                        all_armed = false
                if all_armed:
                    for other in data.stock:
                        if other.get("choice", false):
                            other["taken"] = true
            elif o["price"] == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE]:
                for other in data.stock:
                    if other["kind"] in ["gun", "item", "boon"]:
                        other["taken"] = true
        "item":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            var item := Items.get_item(o["id"])
            if item["slot"] == "mod" and pl.guns.is_empty():
                pl.say("No gun to fit it to")
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            var replaced := pl.equip(o["id"])
            Progress.add("items_picked")
            Sfx.play("buy")
            o["taken"] = true
            if o["price"] == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE]:
                for other in data.stock:
                    if other["kind"] in ["gun", "item", "boon"]:
                        other["taken"] = true
            if replaced != "":
                # The old piece takes the plinth the new one came from.
                data.stock.append(Items.offer(replaced, 0, ped.position))
        "boon":
            match o["id"]:
                "vitality":
                    pl.max_hp_base += o["amount"]
                    pl.recalc_stats()
                    pl.heal(o["amount"])
                "haul":
                    pl.weight_capacity_base += o["amount"]
                    pl.recalc_stats()
                "boiler":
                    pl.pressure_limit_bonus += o["amount"]
                "hoard":
                    main.add_scrap(o["amount"])
            pl.say("%s" % FloorGen.BOONS[o["id"]]["name"])
            Sfx.play("buy")
            o["taken"] = true
            if data.type == RoomData.Type.TREASURE:
                for other in data.stock:
                    if other["kind"] in ["gun", "item", "boon"]:
                        other["taken"] = true
        "carry":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            pl.weight_capacity_base += o["amount"]
            pl.recalc_stats()
            pl.say("Carry capacity %d" % pl.weight_capacity)
            Sfx.play("buy")
            o["taken"] = true
        "repair":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            pl.hp = minf(pl.max_hp, pl.hp + o["amount"])
            pl.say("Repaired")
            Sfx.play("buy")
            o["taken"] = true
        "stairs":
            Sfx.play("stairs")
            main.next_floor()
            return
        "sigil":
            o["taken"] = true
            Sfx.play("confirm")
            begin_challenge()
    _build_pedestals()


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    # Inner shadow along the walls so the floor reads as sunken.
    draw_rect(rect.grow(-10.0), Color(0, 0, 0, 0.35), false, 20.0)
    draw_string(Art.FONT, Vector2(-200, -rect.size.y / 2.0 + 44), data.type_name().to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 400, 30, Color(data.color(), 0.3))
