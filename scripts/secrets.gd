class_name Secrets
extends Node2D
## Hidden environmental puzzles: at most one per room, stumbled upon. Nothing explains
## them; each has a clear look once noticed and answers the right element visibly. Floor
## generation gives about one arena in four and most special rooms a kind (`pick`); the
## Room adds a Secrets node that builds the pieces from RoomData.layout_seed and pays out
## where the puzzle is: a pedestal item, a scrap cache, a heal or a free gun upgrade.
## Solving records `secrets_found`, `secret:<kind>` and `secret_kinds` in Progress and a
## `secret_found` telemetry event. Pieces stay off the doors and the room centre, and the
## bot never aims at them.
##
## Pieces that take hits are `Bit`s: StaticBody2D in group "obstacles" with overlaps() and
## apply_element(), so shots, lobbed shells and the floor's materials reach them the way
## they reach props. A vent counts as its element on every piece in its radius; a nova of
## BLAST_MIN or more counts as an explosion.

const KINDS := {
    "braziers": { "name": "Cold Braziers", "desc": "Light all three braziers with fire within 20 seconds of each other." },
    "fountain": { "name": "Dry Fountain", "desc": "Fill the cracked basin with water until it overflows: coins inside." },
    "ice_block": { "name": "Frozen Cache", "desc": "Melt the ice block in the corner with fire or a hot vent to free what it holds." },
    "rune": { "name": "Floor Rune", "desc": "Set off any reaction on top of the faint glyph: a free gun upgrade." },
    "shrine": { "name": "Wilted Shrine", "desc": "Water the plant, then touch it with the element its gem shows: it heals." },
    "lantern": { "name": "Dead Lantern", "desc": "Strike the lightning rod with shock: the lantern lights and a niche opens." },
    "gong": { "name": "Wall Gong", "desc": "Ring it with stone or a plain shot, then beat the gilded wave it calls." },
    "statues": { "name": "Three Statues", "desc": "Turn them with gale until all three face the middle of the room." },
    "plate": { "name": "Buried Plate", "desc": "Blast or stone the rubble away, then stand on the plate beneath." },
    "oil_trail": { "name": "Oil Trail", "desc": "Ignite the trail: the fire runs under the wall to a hidden cache." },
}
const ORDER := ["braziers", "fountain", "ice_block", "rune", "shrine", "lantern", "gong", "statues", "plate", "oil_trail"]
const BLAST_MIN := 90.0
const BRAZIER_LIT := 20.0
const SHRINE_ORDER := [Element.Kind.HOLY, Element.Kind.BLOOD, Element.Kind.VOID, Element.Kind.POISON,
    Element.Kind.GALE, Element.Kind.SHOCK, Element.Kind.OIL, Element.Kind.ACID, Element.Kind.ICE, Element.Kind.STONE]
const STONE_C := Color(0.55, 0.52, 0.48)

var room: Room
var data: RoomData
var kind := ""
var done := false
var rng := RandomNumberGenerator.new()
var bits: Array = []

var _pt := Vector2.INF            # the puzzle's anchor (rune, plate, trail end, niche)
var _wall_in := Vector2.ZERO      # inward normal of the wall a piece sits on
var _trail: PackedVector2Array = PackedVector2Array()
var _shrine_el: int = Element.Kind.HOLY
var _item := ""
var _wave: Array = []
var _wave_on := false
var _poll := 0.0
var _pulse := 0.0
var _last_nova := Vector2.INF
var _last_nova_r := 0.0


## A puzzle piece that takes hits.
class Bit extends StaticBody2D:
    var ctl: Secrets
    var role := ""
    var size := Vector2(28, 28)
    var solid := true
    var idx := 0
    var lit := 0.0
    var level := 0.0
    var facing := 0
    var target := 0
    var flash := 0.0
    var cd := 0.0
    var hits := 0
    var gone := false

    func _ready() -> void:
        add_to_group("obstacles")
        collision_layer = (Player.LAYER_WALLS if solid else 0) | Obstacle.LAYER_OBSTACLES
        collision_mask = 0
        texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        var shape := CollisionShape2D.new()
        var r := RectangleShape2D.new()
        r.size = size
        shape.shape = r
        add_child(shape)

    func overlaps(point: Vector2, margin: float) -> bool:
        if gone:
            return false
        var local := to_local(point)
        var half := size / 2.0
        var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
        return closest.distance_squared_to(local) <= margin * margin

    func apply_element(element: int, _potency: float = 1.0, dir: Vector2 = Vector2.ZERO) -> bool:
        if gone or ctl == null:
            return false
        return ctl.on_hit(self, element, dir)

    func vanish() -> void:
        gone = true
        remove_from_group("obstacles")
        set_deferred("collision_layer", 0)
        queue_redraw()

    func _draw() -> void:
        if ctl != null:
            ctl.draw_bit(self)


# --- Floor generation and records ----------------------------------------------


## The puzzle a room gets, or "" (most rooms have none). `used` keeps a floor varied;
## `layout` rules out a trail of oil across a flooded or frozen floor.
static func pick(type: int, rng: RandomNumberGenerator, used: Array, layout: String = "open") -> String:
    var chance := 0.0
    match type:
        RoomData.Type.ARENA:
            chance = 0.34 if Progress.has("secret:lantern") else 0.25
        RoomData.Type.SHOP, RoomData.Type.TREASURE, RoomData.Type.CHALLENGE, RoomData.Type.HIDDEN:
            chance = 0.75
        _:
            return ""
    if rng.randf() >= chance:
        return ""
    var pool: Array = ORDER.filter(func(k): return not used.has(k))
    if type == RoomData.Type.SHOP:
        pool.erase("gong")
    if layout == "flooded" or layout == "frozen":
        pool.erase("oil_trail")
    if pool.is_empty():
        return ""
    return String(pool[rng.randi() % pool.size()])


static func kinds_solved() -> int:
    var n := 0
    for k in ORDER:
        if Progress.stat("secret:" + k) > 0:
            n += 1
    return n


static func record(secret_kind: String, floor_number: int) -> void:
    if ORDER.has(secret_kind) and Progress.stat("secret:" + secret_kind) == 0:
        Progress.add("secret_kinds")
    Progress.add("secret:" + secret_kind)
    Progress.add("secrets_found")
    Telemetry.event("secret_found", { "kind": secret_kind, "floor": floor_number })


# --- Building ----------------------------------------------------------------------


func _init(p_room: Room) -> void:
    room = p_room
    data = p_room.data
    kind = data.secret
    done = data.secret_done
    name = "Secrets"
    rng.seed = data.layout_seed * 7 + 4099


func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    match kind:
        "braziers":
            _build_braziers()
        "fountain":
            _build_single("fountain", Vector2(44, 34), 44.0)
        "ice_block":
            _build_ice()
        "rune":
            _pt = _find(60.0, 170.0)
            if _pt != Vector2.INF:
                room.reserve(_pt, 60.0)
        "shrine":
            _build_shrine()
        "lantern":
            _build_lantern()
        "gong":
            _build_gong()
        "statues":
            _build_statues()
        "plate":
            _build_plate()
        "oil_trail":
            _build_trail()
    Elements.reaction_fired.connect(_on_reaction)
    Elements.nova.connect(_on_nova)
    queue_redraw()


func _bit(role: String, pos: Vector2, size: Vector2, solid: bool = true) -> Bit:
    var b := Bit.new()
    b.ctl = self
    b.role = role
    b.size = size
    b.solid = solid
    b.position = pos
    b.idx = bits.size()
    bits.append(b)
    add_child(b)
    room.reserve(pos, maxf(size.x, size.y) * 0.5 + 30.0)
    return b


## A random spot with `r` of open floor, away from doors, keep zones and other pieces:
## dry floor if there is any, else standing in the room's water or on its ice.
func _find(r: float, min_centre: float, tries: int = 60) -> Vector2:
    var inner := room.rect.grow(-r - 30.0)
    for pass_i in 2:
        for attempt in tries:
            var q := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
            if q.length() >= min_centre and room.spot_ok(q, r, pass_i == 0):
                return q
    return Vector2.INF


## A point on the wall face of `side` (UP/DOWN/LEFT/RIGHT), `along` from its middle.
func _wall_point(side: Vector2i, along: float) -> Vector2:
    var half := room.room_size / 2.0
    match side:
        Vector2i.UP:
            return Vector2(along, -half.y)
        Vector2i.DOWN:
            return Vector2(along, half.y)
        Vector2i.LEFT:
            return Vector2(-half.x, along)
    return Vector2(half.x, along)


## A wall spot away from doors and corners with open floor in front: [point, inward] or [].
func _find_wall(depth: float, tries: int = 40) -> Array:
    var half := room.room_size / 2.0
    var sides: Array = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
    for attempt in tries:
        var side: Vector2i = sides[rng.randi() % 4]
        var span := (half.x if side.y != 0 else half.y) - 90.0
        var along := rng.randf_range(-span, span)
        if data.doors.has(side) and absf(along) < 200.0:
            continue
        var p := _wall_point(side, along)
        var inward := -Vector2(side)
        if room.spot_ok(p + inward * depth, 26.0, attempt < tries / 2) and room.is_open(p + inward * 30.0, 20.0):
            return [p, inward]
    return []


func _build_single(role: String, size: Vector2, r: float) -> Bit:
    var q := _find(r, 170.0)
    if q == Vector2.INF:
        return null
    var b := _bit(role, q, size)
    if done:
        b.level = 6.0
    return b


func _build_braziers() -> void:
    var spread := minf(room.room_size.x, room.room_size.y) * 0.5
    for round_i in 3:
        var pts: Array[Vector2] = []
        for attempt in 80:
            if pts.size() >= 3:
                break
            var q := _find(30.0, 150.0, 4)
            if q == Vector2.INF:
                continue
            var ok := true
            for o in pts:
                if o.distance_to(q) < spread:
                    ok = false
            if ok:
                pts.append(q)
        if pts.size() == 3:
            for bp in pts:
                _bit("brazier", bp, Vector2(26, 26))
            return
        spread *= 0.8


func _build_ice() -> void:
    var half := room.room_size / 2.0
    var corners: Array = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
    for attempt in 40:
        var c: Vector2 = corners[rng.randi() % 4]
        var inset := Vector2(rng.randf_range(80.0, 150.0), rng.randf_range(80.0, 140.0))
        var q := Vector2(c.x * (half.x - inset.x), c.y * (half.y - inset.y))
        if room.spot_ok(q, 34.0, attempt < 20):
            var b := _bit("ice", q, Vector2(40, 40))
            _item = String(data.get_meta("secret_item", ""))
            if _item == "" and not done:
                _item = _roll_item()
                data.set_meta("secret_item", _item)
            if done:
                b.vanish()
            return


func _build_shrine() -> void:
    var b := _build_single("shrine", Vector2(26, 30), 34.0)
    if b == null:
        return
    if data.has_meta("secret_el"):
        _shrine_el = int(data.get_meta("secret_el"))
    else:
        var party: Array = room.main.party_elements() if room.main != null else []
        _shrine_el = Element.Kind.HOLY
        for el in SHRINE_ORDER:
            if party.has(el):
                _shrine_el = el
                break
        data.set_meta("secret_el", _shrine_el)
    if done:
        b.level = 99.0
        b.lit = 1.0


func _build_lantern() -> void:
    var w := _find_wall(60.0)
    if w.is_empty():
        return
    var wp: Vector2 = w[0]
    _wall_in = w[1]
    _pt = wp   # the niche
    var q := wp + _wall_in * 62.0 + _wall_in.orthogonal() * rng.randf_range(-40.0, 40.0)
    var b := _bit("lantern", q, Vector2(18, 30))
    if done:
        b.lit = 1.0


func _build_gong() -> void:
    var w := _find_wall(40.0)
    if w.is_empty():
        return
    var wp: Vector2 = w[0]
    _wall_in = w[1]
    var b := _bit("gong", wp + _wall_in * 6.0, Vector2(34, 34), false)
    b.target = 0


func _build_statues() -> void:
    var r := minf(room.room_size.x, room.room_size.y) * 0.5 * 0.55
    for attempt in 24:
        var a0 := rng.randf() * TAU
        var pts: Array[Vector2] = []
        for k in 3:
            var q := Vector2.RIGHT.rotated(a0 + TAU * float(k) / 3.0) * r * Vector2(1.25, 1.0)
            if room.is_open(q, 30.0) and room.spot_ok_loose(q, 26.0, attempt >= 12):
                pts.append(q)
        if pts.size() < 3:
            continue
        for sp in pts:
            var b := _bit("statue", sp, Vector2(28, 28))
            b.target = posmod(roundi((-sp).angle() / (TAU / 8.0)), 8)
            b.facing = posmod(b.target + rng.randi_range(1, 7), 8) if not done else b.target
        return


func _build_plate() -> void:
    _pt = _find(44.0, 170.0)
    if _pt == Vector2.INF:
        return
    var b := _bit("rubble", _pt, Vector2(50, 40))
    if done:
        b.vanish()
        b.lit = 1.0


func _build_trail() -> void:
    for attempt in 30:
        var w := _find_wall(40.0, 6)
        if w.is_empty():
            continue
        var wp: Vector2 = w[0]
        var inward: Vector2 = w[1]
        var side := inward.orthogonal()
        var end := wp + inward * 10.0
        var start := wp + inward * rng.randf_range(220.0, 300.0) + side * rng.randf_range(-130.0, 130.0)
        var mid := end.lerp(start, 0.5) + side * rng.randf_range(-70.0, 70.0)
        var pts := PackedVector2Array()
        var ok := true
        for seg in [[end, mid], [mid, start]]:
            var a: Vector2 = seg[0]
            var bpt: Vector2 = seg[1]
            var n := maxi(1, int(a.distance_to(bpt) / 10.0))
            for k in n:
                var q := a.lerp(bpt, float(k) / float(n))
                if pts.size() > 3 and not room.spot_ok_loose(q, 14.0):
                    ok = false
                    break
                pts.append(q)
            if not ok:
                break
        if not ok or not room.is_open(start, 20.0):
            continue
        pts.append(start)
        _trail = pts
        _pt = end
        _wall_in = inward
        for tp in pts:
            room.reserve(tp, 24.0)
        if not done:
            _lay_trail()
        return


func _lay_trail() -> void:
    var mats := room.materials
    if mats == null:
        return
    for q in _trail:
        mats.fill_rect(Element.Kind.OIL, Rect2(q - Vector2(7, 7), Vector2(14, 14)), 150, 255)


# --- Hits -----------------------------------------------------------------------------


## An element (or a plain hit) lands on a piece. Returns true when it did something.
func on_hit(b: Bit, element: int, _dir: Vector2) -> bool:
    if done:
        return false
    match b.role:
        "brazier":
            if element == Element.Kind.FIRE:
                if b.lit <= 0.0:
                    Sfx.play("react_ignition", -8.0)
                    _fxc("signature", [Element.Kind.FIRE, b.global_position + Vector2(0, -10), 18.0, 0.8, Vector2.ZERO])
                b.lit = BRAZIER_LIT
                b.queue_redraw()
                _check_braziers()
                return true
            if (element == Element.Kind.WET or element == Element.Kind.ICE) and b.lit > 0.0:
                b.lit = 0.0
                _fxc("smoke", [b.global_position + Vector2(0, -10), 8, 10.0, Fx.PAL_STEAM])
                Sfx.play("react_steam", -12.0)
                b.queue_redraw()
                return true
        "fountain":
            if element == Element.Kind.WET:
                b.level += 1.0
                b.flash = 0.2
                _fxc("pixels", [Element.Kind.WET, b.global_position + Vector2(0, -6), 4, 40.0, 8.0])
                b.queue_redraw()
                if b.level >= 6.0:
                    _overflow(b)
                return true
        "ice":
            if element == Element.Kind.FIRE:
                _melt(b, 1.0)
                return true
        "shrine":
            if element == Element.Kind.WET:
                if b.level <= 0.0:
                    _fxc("pixels", [Element.Kind.WET, b.global_position, 6, 30.0, 8.0])
                b.level = 14.0
                b.queue_redraw()
                return true
            if element == Element.Kind.FIRE:
                b.level = 0.0
                b.queue_redraw()
                return true
            if element == _shrine_el:
                b.flash = 0.3
                if b.level > 0.0:
                    _bloom(b)
                b.queue_redraw()
                return true
        "lantern":
            if element == Element.Kind.SHOCK and b.lit <= 0.0:
                b.lit = 1.0
                Sfx.play("react_chain", -6.0)
                Elements.lightning_arc.emit(b.global_position + Vector2(0, -26), b.global_position)
                b.queue_redraw()
                _open_niche(b)
                return true
        "gong":
            if element == Element.Kind.NONE or element == Element.Kind.STONE:
                _ring(b)
                return true
        "statue":
            if element == Element.Kind.GALE and b.cd <= 0.0:
                b.cd = 0.3
                b.facing = (b.facing + 1) % 8
                b.flash = 0.25
                _fxc("pixels", [Element.Kind.STONE, b.global_position + Vector2(0, 8), 4, 50.0, 10.0])
                Sfx.play("hit", -10.0)
                b.queue_redraw()
                _check_statues()
                return true
        "rubble":
            if element == Element.Kind.STONE:
                b.hits += 1
                b.flash = 0.2
                _fxc("pixels", [Element.Kind.STONE, b.global_position, 5, 60.0, 10.0])
                if b.hits >= 2:
                    _clear_rubble(b)
                return true
    return false


func _on_nova(pos: Vector2, radius: float, _color: Color) -> void:
    _last_nova = pos
    _last_nova_r = radius
    if done or radius < BLAST_MIN:
        return
    for bv in bits:
        var b: Bit = bv
        if is_instance_valid(b) and not b.gone and b.role == "rubble" and b.global_position.distance_to(pos) <= radius + 20.0:
            _clear_rubble(b)


func _on_reaction(reaction_name: String, pos: Vector2, _col: Color) -> void:
    if done:
        return
    # A vent: its nova came first with the radius. Hot is fire, cold is ice, on every piece.
    if (reaction_name == "Fire Nova" or reaction_name == "Frost Nova") and _last_nova.distance_to(pos) < 2.0:
        var el: int = Element.Kind.FIRE if reaction_name == "Fire Nova" else Element.Kind.ICE
        for bv in bits:
            var b: Bit = bv
            if is_instance_valid(b) and not b.gone and b.global_position.distance_to(pos) <= _last_nova_r + 20.0:
                if b.role == "ice" and el == Element.Kind.FIRE:
                    _melt(b, 4.0)
                else:
                    on_hit(b, el, Vector2.ZERO)
        return
    if kind == "rune" and _pt != Vector2.INF and not Elements.def_by_name(reaction_name).is_empty():
        var d := pos.distance_to(global_position + _pt)
        if d <= 80.0:
            _pulse = 1.5
            Sfx.play("shield_break", -6.0)
            _offer("gunsmith", _pt + Vector2(0, -60))
            _solved(_pt)
        elif d <= 200.0:
            _pulse = maxf(_pulse, 0.5)   # the glyph stirs when something happens close by
        queue_redraw()


# --- Puzzle logic -----------------------------------------------------------------------


func _check_braziers() -> void:
    var lit := 0
    var c := Vector2.ZERO
    for bv in bits:
        var b: Bit = bv
        if b.lit > 0.0:
            lit += 1
        c += b.position
    if lit >= 3 and bits.size() >= 3:
        var at := room.nearest_open(c / float(bits.size()), 30.0)
        _offer_item(at)
        _solved(at)


func _overflow(b: Bit) -> void:
    var gp := b.global_position
    if room.materials != null:
        room.materials.stamp(Element.Kind.WET, gp, 80.0, 220)
    _fxc("pixels", [Element.Kind.WET, gp + Vector2(0, -10), 24, 140.0, 10.0])
    Sfx.play("react_steam", -6.0)
    _cache(b.position + Vector2(0, 30), 24 + 10 * _floor())
    _solved(b.position)


func _melt(b: Bit, amount: float) -> void:
    if done or b.gone:
        return
    b.level += amount
    b.flash = 0.25
    _fxc("steam", [b.global_position + Vector2(0, -10), 3])
    b.queue_redraw()
    if b.level >= 4.0:
        _fxc("shards", [b.global_position, 8, 24.0, Element.Kind.ICE])
        Sfx.play("react_freeze", -4.0)
        if room.materials != null:
            room.materials.stamp(Element.Kind.WET, b.global_position, 40.0, 160)
        b.vanish()
        if _item == "":
            _item = _roll_item()
        var o := Items.offer(_item, 0, b.position)
        o["secret"] = true
        data.stock.append(o)
        room.call_deferred("_build_pedestals")
        _solved(b.position)


func _bloom(b: Bit) -> void:
    b.lit = 1.0
    b.level = 99.0
    var gp := b.global_position
    _fxc("rise", [gp, 20, 26.0])
    _fxc("signature", [_shrine_el, gp + Vector2(0, -12), 30.0, 1.0, Vector2.ZERO])
    Sfx.play("shield_restore", -4.0)
    for p in room.main.players:
        if p.alive:
            p.heal(p.max_hp * 0.4, "shrine")
            _fxc("rise", [p.global_position, 10, 12.0])
    _cache(b.position + Vector2(0, 34), 10)
    _solved(b.position)


func _open_niche(b: Bit) -> void:
    if _pt == Vector2.INF:
        _offer_item(room.nearest_open(b.position + Vector2(0, 50), 30.0))
        _solved(b.position)
        return
    var gp := global_position + _pt
    _fxc("smoke", [gp + _wall_in * 10.0, 18, 30.0, Fx.PAL_SMOKE])
    _fxc("shards", [gp, 6, 16.0, Element.Kind.STONE])
    Sfx.play("die_elite", -10.0, 0.05)
    _offer_item(room.nearest_open(_pt + _wall_in * 60.0, 30.0))
    _solved(_pt + _wall_in * 30.0)


func _ring(b: Bit) -> void:
    if b.cd > 0.0:
        return
    b.cd = 0.5
    b.flash = 0.6
    b.queue_redraw()
    Sfx.play("shield_break", -4.0, 0.03)
    _fxc("burst_outline", [b.global_position, 60.0, Fx.PAL_GOLD, 0.5])
    if _wave_on or room.active:
        return
    _wave_on = true
    var types := ["grunt", "runner", "swarmer"]
    var n := 4 + mini(4, _floor())
    for i in n:
        var e: Enemy = room._spawn_enemy(String(types[i % types.size()]), room._spawn_point())
        e.emerge = Enemy.EMERGE_SECS
        e.scrap_value = maxi(3, e.scrap_value * 4)
        e.modulate = Color(1.3, 1.1, 0.45)
        _wave.append(e)
    Sfx.play("elite", -6.0)
    _fxc("pixels", [Element.Kind.HOLY, b.global_position + _wall_in * 30.0, 14, 120.0, 10.0, Fx.PAL_GOLD])


func _check_statues() -> void:
    for bv in bits:
        var b: Bit = bv
        if b.facing != b.target:
            return
    Sfx.play("door_open", -4.0)
    for sv in bits:
        var sb: Bit = sv
        _fxc("pixels", [Element.Kind.STONE, sb.global_position, 8, 60.0, 10.0])
    var at := room.nearest_open(Vector2(0, -70), 30.0)
    _offer_item(at)
    _solved(at)


func _clear_rubble(b: Bit) -> void:
    if b.gone:
        return
    _fxc("shards", [b.global_position, 8, 20.0, Element.Kind.STONE])
    _fxc("smoke", [b.global_position, 12, 20.0, Fx.PAL_SMOKE])
    Sfx.play("die", -6.0)
    b.vanish()
    queue_redraw()


func _process(delta: float) -> void:
    _pulse = maxf(0.0, _pulse - delta)
    if kind == "rune" and _pulse > 0.0:
        queue_redraw()
    for bv in bits:
        var b: Bit = bv
        if not is_instance_valid(b):
            continue
        b.cd = maxf(0.0, b.cd - delta)
        if b.flash > 0.0:
            b.flash = maxf(0.0, b.flash - delta)
            b.queue_redraw()
        if b.role == "brazier" and b.lit > 0.0 and not done:
            b.lit = maxf(0.0, b.lit - delta)
            b.queue_redraw()
            if randf() < delta * 6.0:
                _fxc("ember", [b.global_position + Vector2(randf_range(-6.0, 6.0), -16.0)])
            if b.lit <= 0.0:
                _fxc("smoke", [b.global_position + Vector2(0, -12), 6, 6.0, Fx.PAL_SMOKE])
        elif b.role == "shrine" and b.level > 0.0 and b.level < 90.0:
            b.level = maxf(0.0, b.level - delta)
            if b.level <= 0.0:
                b.queue_redraw()
        elif b.role == "lantern" and b.lit > 0.0:
            b.queue_redraw()
        elif b.role == "statue" and b.facing == b.target and not done:
            b.queue_redraw()
    if done:
        return
    _poll -= delta
    if _poll > 0.0:
        return
    _poll = 0.25
    match kind:
        "plate":
            if not bits.is_empty() and (bits[0] as Bit).gone:
                for p in room.main.players:
                    if p.alive and p.global_position.distance_to(global_position + _pt) <= 22.0:
                        (bits[0] as Bit).lit = 1.0
                        Sfx.play("door_lock", -4.0)
                        _offer_item(room.nearest_open(_pt + (-_pt).normalized() * 70.0, 30.0))
                        _solved(_pt)
                        queue_redraw()
                        break
        "oil_trail":
            if _pt != Vector2.INF and room.materials != null:
                var gp := global_position + _pt
                for o in [Vector2.ZERO, _wall_in * 6.0, _wall_in.orthogonal() * 6.0, -_wall_in.orthogonal() * 6.0]:
                    var m := room.materials.material_at(gp + o)
                    if m == Materials.FIRE or m == Materials.ASH:
                        _fxc("smoke", [gp, 20, 24.0, Fx.PAL_SMOKE])
                        _fxc("shards", [gp, 7, 18.0, Element.Kind.STONE])
                        Sfx.play("die_elite", -8.0, 0.05)
                        var at := room.nearest_open(_pt + _wall_in * 60.0, 30.0)
                        _cache(at, 20 + 8 * _floor())
                        if rng.randf() < 0.5:
                            _offer_item(room.nearest_open(_pt + _wall_in * 110.0, 30.0))
                        _solved(_pt + _wall_in * 30.0)
                        queue_redraw()
                        break
        "gong":
            if _wave_on:
                var alive := 0
                for e in _wave:
                    if is_instance_valid(e) and not e.is_queued_for_deletion():
                        alive += 1
                if alive == 0:
                    _wave_on = false
                    var gong: Bit = bits[0]
                    _cache(gong.position + _wall_in * 60.0, 15 + 6 * _floor())
                    _solved(gong.position + _wall_in * 40.0)


# --- Rewards -------------------------------------------------------------------------


func _floor() -> int:
    return room.main.floor_number if room.main != null else 1


func _roll_item() -> String:
    var rarity: int = Items.Rarity.RARE if Progress.has("secret:hoard") else Items.Rarity.UNCOMMON
    return Drops.roll_item(room.main.difficulty() + 2, rarity, [], room.main.party_luck(), "treasure", room.main.players)


func _offer_item(pos: Vector2) -> void:
    var o := Items.offer(_roll_item(), 0, pos)
    o["secret"] = true
    data.stock.append(o)
    room.call_deferred("_build_pedestals")


func _offer(offer_kind: String, pos: Vector2) -> void:
    var o := FloorGen.offer(offer_kind, "", 0)
    o["pos"] = room.nearest_open(pos, 30.0)
    o["secret"] = true
    data.stock.append(o)
    room.call_deferred("_build_pedestals")


func _cache(pos: Vector2, scrap: int) -> void:
    room._drop_scrap(room.nearest_open(pos, 20.0), scrap, mini(8, maxi(3, scrap / 6)))
    _fxc("pixels", [Element.Kind.HOLY, global_position + pos, 12, 90.0, 8.0, Fx.PAL_GOLD])


func _solved(pos: Vector2) -> void:
    if done:
        return
    done = true
    data.secret_done = true
    Secrets.record(kind, _floor())
    Sfx.play("secret_found")
    _fxc("rise", [global_position + pos, 18, 22.0])
    _fxc("pixels", [Element.Kind.HOLY, global_position + pos, 16, 120.0, 10.0, Fx.PAL_GOLD])
    for bv in bits:
        if is_instance_valid(bv):
            (bv as Bit).queue_redraw()
    queue_redraw()


func _fxc(method: String, args: Array) -> void:
    var scene := get_tree().current_scene
    if scene == null or not "fx" in scene:
        return
    var f: Variant = scene.get("fx")
    if f is Object and is_instance_valid(f) and (f as Object).has_method(method):
        (f as Object).callv(method, args)


# --- Drawing ---------------------------------------------------------------------------


## Floor pieces: the rune, the plate, the trail's hole under the wall, the lantern niche.
func _draw() -> void:
    match kind:
        "rune":
            if _pt == Vector2.INF:
                return
            var a := 0.11
            var col := Color(0.62, 0.56, 0.78)
            if done:
                a = 0.55
                col = Color(1.0, 0.85, 0.45)
            a = maxf(a, minf(0.9, _pulse * 0.6))
            draw_arc(_pt, 44.0, 0.0, TAU, 40, Color(col, a), 2.0)
            draw_arc(_pt, 36.0, 0.0, TAU, 32, Color(col, a * 0.7), 1.0)
            for k in 6:
                var d := Vector2.RIGHT.rotated(TAU * float(k) / 6.0 + 0.26)
                draw_line(_pt + d * 36.0, _pt + d * 44.0, Color(col, a), 2.0)
                var g := _pt + d * 22.0
                draw_rect(Rect2(g - Vector2(2, 2), Vector2(4, 4)), Color(col, a * 0.9))
            var tri := PackedVector2Array()
            for k in 4:
                tri.append(_pt + Vector2.UP.rotated(TAU * float(k) / 3.0) * 16.0)
            draw_polyline(tri, Color(col, a), 1.0)
        "plate":
            if _pt == Vector2.INF or bits.is_empty():
                return
            var b: Bit = bits[0]
            var r := Rect2(_pt - Vector2(18, 18), Vector2(36, 36))
            if not b.gone:
                # Only a corner of metal shows past the rubble.
                draw_line(r.position + Vector2(r.size.x - 10, r.size.y), r.end, Color(0.55, 0.6, 0.65, 0.6), 2.0)
                draw_line(r.end, r.end - Vector2(0, 8), Color(0.55, 0.6, 0.65, 0.6), 2.0)
                return
            var pressed := b.lit > 0.0
            draw_rect(r, Color(0.20, 0.22, 0.25) if not pressed else Color(0.12, 0.13, 0.15))
            draw_rect(r, Color(0.55, 0.6, 0.65, 0.8), false, 2.0)
            draw_rect(r.grow(-8.0), Color(0.35, 0.38, 0.42, 0.7), false, 1.0)
        "oil_trail":
            if _pt == Vector2.INF:
                return
            var hs := _wall_in.orthogonal()
            var hole := PackedVector2Array([_pt + hs * 8.0, _pt + hs * 8.0 - _wall_in * 9.0, _pt - hs * 8.0 - _wall_in * 9.0, _pt - hs * 8.0])
            draw_colored_polygon(hole, Color(0.02, 0.02, 0.02, 0.85 if not done else 1.0))
            if done:
                draw_rect(Rect2(_pt - Vector2(14, 14), Vector2(28, 28)), Color(0.02, 0.02, 0.02, 0.9))
        "lantern":
            if done and _pt != Vector2.INF:
                var ns := _wall_in.orthogonal()
                var niche := PackedVector2Array([_pt + ns * 22.0, _pt + ns * 22.0 - _wall_in * 30.0, _pt - ns * 22.0 - _wall_in * 30.0, _pt - ns * 22.0])
                draw_colored_polygon(niche, Color(0.03, 0.02, 0.03))


func draw_bit(b: Bit) -> void:
    var fl := clampf(b.flash * 3.0, 0.0, 1.0)
    match b.role:
        "brazier":
            var burning := b.lit > 0.0
            var btint := Color(0.42, 0.36, 0.32) if not burning else Color(0.75, 0.55, 0.40)
            _tile(b, Vector2i(14, 10), 2.2, btint.lerp(Color.WHITE, fl * 0.4))
            if not burning:
                # Cobwebs and cold ash: plainly out.
                b.draw_line(Vector2(-10, -14), Vector2(-3, -8), Color(0.75, 0.75, 0.75, 0.25), 1.0)
                b.draw_line(Vector2(-3, -8), Vector2(4, -15), Color(0.75, 0.75, 0.75, 0.25), 1.0)
                b.draw_rect(Rect2(-6, -16, 12, 3), Color(0.25, 0.24, 0.24, 0.8))
            else:
                var hgt := 10.0 + 6.0 * (b.lit / BRAZIER_LIT)
                for fi in 5:
                    var fx0 := randf_range(-7.0, 6.0)
                    var fs := randf_range(2.0, 4.0)
                    var fc := Color(1.0, 0.55, 0.15, 0.85) if randi() % 2 == 0 else Color(1.0, 0.85, 0.35, 0.9)
                    b.draw_rect(Rect2(floorf(fx0), floorf(-14.0 - randf() * hgt), fs, fs), fc)
                _glow(b, Vector2(0, -16), 46.0, Color(1.0, 0.6, 0.25, 0.35))
                # How long it has left: three pips of embers.
                for pip in 3:
                    if b.lit > BRAZIER_LIT * float(pip) / 3.0:
                        b.draw_rect(Rect2(-6 + pip * 5, 12, 3, 2), Color(1.0, 0.5, 0.2, 0.8))
        "fountain":
            var full := clampf(b.level / 6.0, 0.0, 1.0)
            b.draw_rect(Rect2(-8, 2, 16, 14), STONE_C.darkened(0.25))
            _ellipse(b, Vector2(0, -2), Vector2(24, 13), STONE_C.lerp(Color.WHITE, fl * 0.3))
            _ellipse(b, Vector2(0, -3), Vector2(19, 9), Color(0.16, 0.13, 0.11))
            if full > 0.0:
                _ellipse(b, Vector2(0, -3), Vector2(19, 9) * (0.4 + 0.6 * full), Color(0.25, 0.5, 0.95, 0.5 + 0.4 * full))
            if full < 1.0:
                # The crack the water drains through.
                b.draw_polyline(PackedVector2Array([Vector2(-12, -4), Vector2(-6, -1), Vector2(-1, -5), Vector2(5, -2), Vector2(10, -6)]), Color(0.05, 0.04, 0.04, 0.9), 1.0)
                b.draw_line(Vector2(-14, 3), Vector2(-9, 8), Color(0.08, 0.07, 0.07, 0.8), 1.0)
            else:
                b.draw_rect(Rect2(-4, -6, 2, 2), Color(1, 1, 1, 0.8))
        "ice":
            if b.gone:
                return
            var left := clampf(1.0 - b.level / 4.0, 0.25, 1.0)
            var isz := b.size * left
            var irect := Rect2(-isz / 2.0, isz)
            b.draw_rect(irect, Color(0.70, 0.90, 1.0, 0.55).lerp(Color.WHITE, fl * 0.5))
            if _item != "":
                var it := Items.get_item(_item)
                if not it.is_empty():
                    var ic := 26.0 * left
                    Art.draw_icon(b, Items.icon(it), Rect2(Vector2(-ic, -ic) / 2.0, Vector2(ic, ic)), Color(0.8, 0.9, 1.0, 0.65))
            b.draw_rect(irect, Color(0.85, 0.97, 1.0, 0.85), false, 2.0)
            b.draw_line(irect.position + Vector2(4, 6), irect.position + Vector2(12, 3), Color(1, 1, 1, 0.8), 1.0)
            b.draw_line(irect.end - Vector2(14, 6), irect.end - Vector2(5, 10), Color(1, 1, 1, 0.5), 1.0)
        "shrine":
            var base := Rect2(-13, 6, 26, 9)
            b.draw_rect(base, STONE_C.darkened(0.2))
            b.draw_rect(base, STONE_C.darkened(0.45), false, 1.0)
            # The gem names the second element, dimly.
            var gem: Color = Element.COLORS[_shrine_el]
            b.draw_rect(Rect2(-2, 8, 4, 4), Color(gem, 0.55 + fl * 0.45))
            var watered := b.level > 0.0
            var bloomed := b.lit > 0.0
            var stem := Color(0.45, 0.38, 0.28) if not watered else Color(0.35, 0.7, 0.3)
            for st in 3:
                var x0 := -6.0 + 6.0 * float(st)
                var pts := PackedVector2Array()
                for j in 5:
                    var t := float(j) / 4.0
                    var droop := 0.0 if watered else t * t * 9.0 * (1.0 if st != 0 else -1.0)
                    pts.append(Vector2(x0 + droop, 6.0 - t * 22.0 + (t * t * 10.0 if not watered else 0.0)))
                b.draw_polyline(pts, stem, 2.0)
                if bloomed:
                    var top := pts[pts.size() - 1]
                    b.draw_rect(Rect2(top - Vector2(3, 3), Vector2(6, 6)), gem)
                    b.draw_rect(Rect2(top - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 0.8))
            if bloomed:
                _glow(b, Vector2(0, -10), 40.0, Color(gem, 0.3))
        "lantern":
            _tile(b, Vector2i(5, 15), 2.4, Color(0.62, 0.62, 0.70).lerp(Color.WHITE, fl * 0.4))
            var box := Rect2(6, -4, 10, 12)
            var on := b.lit > 0.0
            b.draw_line(Vector2(4, -10), Vector2(11, -4), Color(0.5, 0.5, 0.55), 1.0)
            b.draw_rect(box, Color(1.0, 0.85, 0.35) if on else Color(0.12, 0.11, 0.1))
            b.draw_rect(box, Color(0.45, 0.42, 0.40), false, 1.0)
            if on:
                _glow(b, box.get_center(), 60.0 + randf() * 6.0, Color(1.0, 0.85, 0.4, 0.4))
        "gong":
            var rim := Color(0.70, 0.52, 0.25).lerp(Color(1.0, 0.9, 0.5), fl)
            b.draw_line(Vector2(-10, -16) - _wall_in * 8.0, Vector2(-8, -10), Color(0.4, 0.38, 0.35), 2.0)
            b.draw_line(Vector2(10, -16) - _wall_in * 8.0, Vector2(8, -10), Color(0.4, 0.38, 0.35), 2.0)
            b.draw_circle(Vector2.ZERO, 16.0, Color(0.45, 0.32, 0.15))
            b.draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 28, rim, 2.0)
            b.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 20, Color(rim, 0.6), 1.0)
            b.draw_circle(Vector2.ZERO, 4.0, rim)
            if b.flash > 0.0:
                b.draw_arc(Vector2.ZERO, 18.0 + (0.6 - b.flash) * 40.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.4, b.flash), 2.0)
        "statue":
            b.draw_rect(Rect2(-14, 2, 28, 12), STONE_C.darkened(0.35))
            b.draw_rect(Rect2(-14, 2, 28, 3), STONE_C.darkened(0.1))
            var face := Vector2.RIGHT.rotated(float(b.facing) * TAU / 8.0)
            _tile(b, Art.TILES["player"][0], 2.2, STONE_C.lerp(Color.WHITE, fl * 0.5), Vector2(0, -10), face.x < -0.1)
            # The gaze: a stone arm pointing the way the statue faces.
            var arm := Vector2(0, -8)
            b.draw_line(arm, arm + face * 18.0, STONE_C.lightened(0.15), 3.0)
            b.draw_rect(Rect2(arm + face * 18.0 - Vector2(2, 2), Vector2(4, 4)), STONE_C.lightened(0.3))
            if b.facing == b.target:
                b.draw_circle(Vector2(0, 8), 3.0, Color(1.0, 0.85, 0.45, 0.25 + 0.2 * sin(Time.get_ticks_msec() / 200.0)))
        "rubble":
            if b.gone:
                return
            var rtint := Color(0.56, 0.5, 0.42).lerp(Color.WHITE, fl * 0.4)
            var decals: Array = Art.TILES["decals"]
            _tile(b, decals[3], 2.2, rtint, Vector2(-10, 2))
            _tile(b, decals[4], 2.2, rtint, Vector2(10, 4))
            _tile(b, decals[3], 1.8, rtint.darkened(0.1), Vector2(0, -8))


func _tile(b: Bit, coord: Vector2i, scale: float, tint: Color, off: Vector2 = Vector2.ZERO, flip: bool = false) -> void:
    var s := 16.0 * scale
    var r := Rect2(off - Vector2(s, s) / 2.0, Vector2(s, s))
    if flip:
        r = Rect2(r.position + Vector2(s, 0), Vector2(-s, s))
    b.draw_texture_rect(Art.tile(coord), r, false, tint)


func _ellipse(b: Bit, c: Vector2, r: Vector2, col: Color) -> void:
    b.draw_set_transform(c, 0.0, Vector2(1.0, r.y / maxf(1.0, r.x)))
    b.draw_circle(Vector2.ZERO, r.x, col)
    b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _glow(b: Bit, c: Vector2, size: float, col: Color) -> void:
    var tex: Texture2D = Art.PARTICLES["light"]
    b.draw_texture_rect(tex, Rect2(c - Vector2(size, size) / 2.0, Vector2(size, size)), false, col)
