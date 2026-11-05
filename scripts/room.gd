class_name Room
extends Node2D
## One room of the dungeon, rebuilt from its RoomData every time the party enters.
## Owns walls, doors, pedestals, the enemies and pickups inside, and the fight logic
## for arena waves, challenges and the boss.

signal door_entered(dir: Vector2i)

const SIZE := Vector2(1120, 720)
const WALL := 60.0
const GAP := 150.0
## Kinds that leave blood on the floor when they die.
const BLOODY_KINDS := ["grunt", "runner", "brute", "swarmer", "spitter", "charger", "splitter", "shaman", "elite", "boss"]

var data: RoomData
var main: Main
var rect := Rect2(-SIZE / 2.0, SIZE)
var enemies: Node2D
var pickups: Node2D
var materials: Materials            # floor material layer (oil, water, fire, gas...)
var doors: Dictionary = {}          # dir -> Door
var pedestals: Array[Pedestal] = []

var active := false                 # a fight is running
var wave_time_left := 0.0
var wave_duration := 0.0
var boss: Enemy = null

var _elites_alive := 0
var _spawn_timer := 0.0
var _elite_timer := INF
var _elite_timer2 := INF
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
    materials = Materials.new(rect)   # z -1: over floor and decals, under bodies
    add_child(materials)
    _build_walls()
    _build_doors()
    _build_pedestals()
    Props.dress(self)   # crates, barrels, fountains, braziers... that react to every element

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
    wave_duration = clampf(18.0 + 2.2 * float(diff), 18.0, 60.0)
    wave_time_left = wave_duration
    _spawn_timer = 0.8
    _elite_timer = wave_duration * 0.45 if diff >= 2 else INF
    _elite_timer2 = wave_duration * 0.78 if main.floor_number >= 2 else INF
    main.announce("Survive %d seconds" % int(wave_duration))
    Sfx.play("wave_start")


func _tick_arena(delta: float) -> void:
    var diff := main.difficulty()
    Music.set_intensity(clampf(float(enemies.get_child_count()) / 6.0, 0.15, 1.0))
    var before := ceili(wave_time_left)
    wave_time_left -= delta
    if wave_time_left <= 3.0 and ceili(wave_time_left) != before:
        Sfx.play("tick", 0.0, 0.0)
    _spawn_timer -= delta
    _elite_timer -= delta
    if _spawn_timer <= 0.0:
        # Pacing by hit-point budget: each group buys itself a pause proportional to its
        # total hp against what a party of this difficulty is expected to put out, so a
        # starter pistol holds floor 1 and a built party gets a flood on floor 5.
        if enemies.get_child_count() < mini(100, 24 + diff * 3):
            var before_count := enemies.get_child_count()
            var spawned_hp := _spawn_group()
            var spawned_n := enemies.get_child_count() - before_count
            # Two budgets: hit points per second, and bodies per second (a swarm of
            # cheap bodies is a different kind of pressure than one brute).
            var by_hp := spawned_hp / hp_inflow_target(diff)
            var by_bodies := float(spawned_n) / (1.4 + 0.18 * float(diff))
            _spawn_timer = clampf(maxf(by_hp, by_bodies), 0.5, 4.0)
        else:
            _spawn_timer = 1.0
    if _elite_timer <= 0.0:
        _elite_timer = INF
        _spawn_elite(SpawnTable.elite_count(diff))
    _elite_timer2 -= delta
    if _elite_timer2 <= 0.0:
        _elite_timer2 = INF
        _spawn_elite(SpawnTable.elite_count(diff))
    if wave_time_left <= 0.0:
        _finish_fight(6)
        _arena_reward()


## Every arena pays out: a free gun or a free item, so power grows with the rooms
## whether or not the shop turns up.
func _arena_reward() -> void:
    var owned := 0
    for pl in main.players:
        owned += pl.guns.size()
    # Duplicates are welcome (they combine); only guns maxed out everywhere are skipped.
    var gun_id := Drops.roll_gun(main.players, _maxed_gun_ids())
    # A naked start needs guns first: until the party carries three, the arena pays a gun.
    var few_guns := owned < 3 * main.players.size()
    if (few_guns or randf() < 0.5) and gun_id != "":
        data.stock.append(FloorGen.offer("gun", gun_id, 0))
    else:
        data.stock.append(Items.offer(Drops.roll_item(main.difficulty(), Items.Rarity.COMMON, [], main.party_luck(), "arena", main.players), 0))
    _build_pedestals()
    main.announce("Room cleared: take your reward")


## Gun ids the party carries only at max tier (no point offering another copy).
func _maxed_gun_ids() -> Array:
    var below: Dictionary = {}
    var maxed: Array = []
    for pl in main.players:
        for g in pl.guns:
            var gun: Gun = g
            if gun.tier < Gun.MAX_TIER:
                below[gun.data.id] = true
            elif not maxed.has(gun.data.id):
                maxed.append(gun.data.id)
    return maxed.filter(func(id): return not below.has(id))


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
            var id := Drops.roll_item(main.difficulty() + 2, Items.Rarity.UNCOMMON, picked, main.party_luck(), "challenge", main.players)
            picked.append(id)
            data.stock.append(Items.offer(id, 0))
        _finish_fight(20)
        _build_pedestals()


func _begin_boss() -> void:
    data.started = true
    active = true
    boss = _spawn_enemy("boss", Vector2(0, -220))
    boss.set_boss(SpawnTable.boss_for(main.floor_number))
    var pairs := Elements.available_reactions(main.party_elements())
    var hits := 5 + main.difficulty() / 3
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
    Music.set_intensity(0.2)
    data.cleared = true
    for e in enemies.get_children():
        e.vanish()
    for sh in get_tree().get_nodes_in_group("enemy_projectiles"):
        sh.queue_free()
    _drop_scrap(Vector2.ZERO, bonus_scrap, 6)
    main.on_room_cleared(self)
    Sfx.play("cleared")
    for pl in main.players:
        if pl.alive:
            Items.fire(pl, "room_clear", { "pos": pl.global_position })
    _apply_doors()


# --- Spawning ----------------------------------------------------------------


## Enemy hit points per second the arena feeds the party at a difficulty. Sized for a
## party with six gun slots and tiers; party_power() scales enemy hp on top of it.
static func hp_inflow_target(diff: int) -> float:
    var d := float(diff)
    return 32.0 + 16.0 * d + 0.6 * maxf(0.0, d - 6.0) * maxf(0.0, d - 6.0)


## Party gun dps a difficulty expects, the yardstick for party_power().
static func expected_dps(diff: int) -> float:
    return 45.0 + 22.0 * float(diff)


## Brotato-style soft scaling: carried gun dps (budget dps x tier) against what the
## difficulty expects, clamped to 0.8..2.2. Enemy max hp is multiplied by its sqrt.
func party_power() -> float:
    var total := 0.0
    for pl in main.players:
        for g in pl.guns:
            var gun: Gun = g
            total += gun.data.dps() * gun.tier_mult()
    return clampf(total / expected_dps(main.difficulty()), 0.8, 2.2)


## Floors three to five hit harder: contact and shot damage x1.15, x1.3, x1.5.
static func floor_damage_mult(floor_number: int) -> float:
    return 1.0 + 0.15 * float(maxi(0, floor_number - 2)) + (0.05 if floor_number >= 5 else 0.0)


func _spawn_group() -> float:
    var diff := main.difficulty()
    var total_hp := 0.0
    for type in SpawnTable.group(diff, main.floor_number, main.players.size()):
        var e := _spawn_enemy(type, _spawn_point())
        total_hp += e.max_hp
        if e.immune_to == Element.Kind.NONE and diff >= 2 and randf() < minf(0.5, 0.05 * float(diff)):
            # Never immune to the party's only element: that would be unkillable.
            var kinds := main.party_elements()
            if kinds.size() >= 2:
                e.immune_to = kinds.pick_random()
    return total_hp


func _spawn_enemy(type: String, pos: Vector2) -> Enemy:
    var e := Enemy.new()
    e.configure(type, main.difficulty())
    e.max_hp *= sqrt(party_power())
    e.hp = e.max_hp
    e.damage_mult = floor_damage_mult(main.floor_number)
    e.contact_damage *= e.damage_mult
    e.position = pos
    e.died.connect(_on_enemy_died)
    enemies.add_child(e)
    return e


func _spawn_elite(count: int) -> void:
    var diff := main.difficulty()
    var hits := 2 + diff / 4
    var pairs := Elements.available_reactions(main.party_elements())
    for i in count:
        var e := _spawn_enemy("elite", _spawn_point())
        e.set_affix(SpawnTable.elite_affix(diff))
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
        e.last_hit_by.gain_xp(2.0 + 2.0 * float(e.scrap_value))
    _drop_scrap(e.global_position, e.scrap_value, mini(e.scrap_value, 5))
    if materials != null:
        if e.kind_name in BLOODY_KINDS:
            materials.stamp(Element.Kind.BLOOD, e.global_position, e.radius * 0.8, 90)
        if e.has_state(Element.Kind.OIL):
            materials.stamp(Element.Kind.OIL, e.global_position, e.radius * 1.5, 120)
        if e.burn_time > 0.0:
            materials.ignite(e.global_position, e.radius * 1.5)
    if e.is_elite and data.type == RoomData.Type.CHALLENGE:
        _elites_alive -= 1
    # Loot: bosses always drop rare or better, elites drop sometimes.
    var inner := rect.grow(-90.0)
    var drop_pos := Vector2(clampf(e.global_position.x, inner.position.x, inner.end.x), clampf(e.global_position.y, inner.position.y, inner.end.y))
    if e.kind_name == "boss":
        data.stock.append(Items.offer(Drops.roll_item(main.difficulty() + 4, Items.Rarity.RARE, [], main.party_luck(), "boss", main.players), 0, Vector2(0, 150)))
        _build_pedestals()
    elif e.is_elite and randf() < 0.55:
        data.stock.append(Items.offer(Drops.roll_item(main.difficulty(), Items.Rarity.COMMON, [], main.party_luck(), "", main.players), 0, drop_pos))
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
    # Taken offers keep their plinth (bare) so the row stays put; stairs and sigils never do.
    var offers: Array = data.stock.filter(func(o): return not o["taken"] or o["kind"] in ["gun", "item", "boon", "gunsmith", "carry", "repair"])
    for o in offers:
        if o["kind"] == "item" and not o["taken"]:
            Items.mark_seen(o["id"])   # Isaac: an item on show leaves the run's pool
    var row: Array = offers.filter(func(o): return not o.has("pos"))
    var n := row.size()
    var per_row := 4
    var rows := int(ceil(float(n) / float(per_row)))
    for i in n:
        var ped := Pedestal.new(row[i])
        var r := i / per_row
        var in_row := mini(per_row, n - r * per_row)
        var c := i % per_row
        ped.position = Vector2((float(c) - float(in_row - 1) / 2.0) * 210.0, 90.0 + (float(r) - float(rows - 1) / 2.0) * 220.0)
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
        ped.highlighted = not ped.empty() and near != null and near.global_position.distance_to(ped.global_position) <= Pedestal.RANGE
        if near != null:
            ped.prompt_key = near.input.prompt("interact")
            ped.prompt_kind = near.input.last_kind
    for pl in main.players:
        if not pl.alive or not pl.input.take_pressed("interact"):
            continue
        var best: Pedestal = null
        var best_d := Pedestal.RANGE
        for ped in pedestals:
            if not is_instance_valid(ped) or ped.empty():
                continue
            var d := ped.global_position.distance_to(pl.global_position)
            if d < best_d:
                best_d = d
                best = ped
        if best != null:
            activate(best, pl)


## Finish buying a mod once the gun is known.
func _fit_mod(pl: Player, gun: Gun, o: Dictionary) -> void:
    if not is_instance_valid(gun) or main.scrap < o["price"]:
        return
    main.scrap -= o["price"]
    pl.equip_mod_on(gun, o["id"])
    Progress.add("items_picked")
    Sfx.play("buy")
    o["taken"] = true
    if o["price"] == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE]:
        for other in data.stock:
            if other["kind"] in ["gun", "item", "boon"]:
                other["taken"] = true
    _build_pedestals()


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
            if item["slot"] == "mod":
                var candidates: Array = pl.mod_candidates()
                if candidates.is_empty():
                    pl.say("No free mod slot: upgrade a gun" if not pl.guns.is_empty() else "No gun to fit it to")
                    Sfx.play("error")
                    return
                if candidates.size() == 1 or main.autotest:
                    _fit_mod(pl, candidates[0], o)
                else:
                    # More than one gun could take it: let the player choose.
                    main.gun_pick.pick(pl, candidates, o["id"], func(g): if g != null: _fit_mod(pl, g, o))
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
                o["id"] = replaced
                o["price"] = 0
                o["taken"] = false
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
        "gunsmith":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            var upgraded := pl.upgrade_lowest_gun()
            if upgraded == null:
                pl.say("Nothing to upgrade")
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            Sfx.play("buy")
            o["taken"] = true
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
        "reroll":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            o["amount"] += 1   # uses so far
            o["price"] = FloorGen.reroll_price(main.floor_number, o["amount"])
            for i in data.stock.size():
                var w: Dictionary = data.stock[i]
                if w.get("ware", false) and not w["taken"]:
                    data.stock[i] = FloorGen.roll_ware(main.floor_number, main.party_luck(), data.stock, main.players)
            pl.say("Rerolled")
            Sfx.play("buy")
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
