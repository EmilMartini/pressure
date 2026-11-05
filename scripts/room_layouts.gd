class_name RoomLayouts
extends RefCounted
## Interior geometry for a room: wall segments, pillar clusters, rubble, chasms, deep
## water, oil slicks, ice sheets and dry grass. A layout is picked per RoomData at floor
## generation (`pick`) and generated from its name and seed (`build`), so a room keeps
## its shape on every visit. Everything is laid on a 20 px grid (Plan.cells for what
## blocks, Plan.terrain for what lies on open floor); Room turns that into collision,
## wall tiles, chasm drawing and Materials stamps.
##
## Guarantees, checked after generation (a layout that fails falls back to a simpler one):
##   - a clear circle at every door, at the room centre and at each pedestal spot (`keep`)
##   - every door landing, the centre and the keep spots joined by corridors ~110 px wide
##     or more (a flood fill over cells with MIN_CLEARANCE cells of room on every side)
##   - enclosed floor nobody can walk to is marked UNREACH, so nothing spawns there

const CELL := 20.0

## Cell values: what blocks.
const OPEN := 0
const WALL := 1
const CHASM := 2
const BREAK := 3     # the breakable front of a secret alcove: solid until broken
const POCKET := 4    # floor inside a closed alcove
const UNREACH := 5   # enclosed floor: never spawned on, never walked to

## Terrain values, on open cells.
const T_NONE := 0
const T_DEEP := 1    # deep water: wading slows bodies; refilled from the Materials grid
const T_OIL := 2
const T_ICE := 3
const T_GRASS := 4   # dry grass: a thin oil film under tufts, burns like a fuse

## Wall looks.
const S_WALL := 0
const S_PILLAR := 1
const S_RUBBLE := 2

const DOOR_CLEAR := 120.0
const MIN_CLEARANCE := 3   # cells to the nearest blocker: a corridor of ~110 px or more

## Arena layouts (also challenge rooms).
const ARENA := ["open", "four_pillars", "pillar_hall", "cross", "l_shape", "ring", "moat", "rift",
    "flooded", "channels", "refinery", "frozen", "broken", "twin", "diagonal", "pit_maze",
    "overgrown", "buttresses", "bastions", "corner_pits"]
## Shops and treasure rooms: nothing that hides the wares.
const SIMPLE := ["open", "four_pillars", "colonnade", "spring"]
const HIDDEN := ["open", "broken"]
const BOSS := ["open", "four_pillars", "pillar_hall", "channels", "broken"]
## Every layout name, for the debug capture.
const ALL := ["open", "four_pillars", "pillar_hall", "cross", "l_shape", "ring", "moat", "rift",
    "flooded", "channels", "refinery", "frozen", "broken", "twin", "diagonal", "pit_maze",
    "overgrown", "buttresses", "bastions", "corner_pits", "colonnade", "spring"]
## Smallest size class a layout fits in (0 small, 1 normal, 2 large).
const MIN_SIZE := { "ring": 1, "moat": 1 }


## The layout a room of this type and size gets.
static func pick(type: int, size_class: int, rng: RandomNumberGenerator) -> String:
    var pool: Array = []
    match type:
        RoomData.Type.ARENA, RoomData.Type.CHALLENGE:
            pool = ARENA
        RoomData.Type.SHOP, RoomData.Type.TREASURE:
            pool = SIMPLE
        RoomData.Type.HIDDEN:
            pool = HIDDEN
        RoomData.Type.BOSS:
            pool = BOSS
        _:
            return "open"
    pool = pool.filter(func(n): return size_class >= int(MIN_SIZE.get(n, 0)))
    if pool.is_empty():
        return "open"
    return String(pool[rng.randi() % pool.size()])


static func min_size(layout_name: String) -> int:
    return int(MIN_SIZE.get(layout_name, 0))


## One generated interior.
class Plan:
    var name := "open"
    var size := Vector2.ZERO
    var half := Vector2.ZERO
    var w := 0
    var h := 0
    var cells := PackedByteArray()
    var terrain := PackedByteArray()
    var style := PackedByteArray()
    var props: Array = []          # { "kind": String, "pos": Vector2 }
    var alcove: Dictionary = {}    # { "front": Rect2, "inner": Rect2, "out": Vector2 }
    var avoid: Array = []          # [Vector2, float]: spots props stay away from
    var rng := RandomNumberGenerator.new()

    func _init(p_size: Vector2, p_seed: int) -> void:
        size = p_size
        half = p_size / 2.0
        w = maxi(1, roundi(p_size.x / RoomLayouts.CELL))
        h = maxi(1, roundi(p_size.y / RoomLayouts.CELL))
        cells.resize(w * h)
        cells.fill(0)
        terrain.resize(w * h)
        terrain.fill(0)
        style.resize(w * h)
        style.fill(0)
        rng.seed = p_seed

    func cell_of(p: Vector2) -> Vector2i:
        return Vector2i(floori((p.x + half.x) / RoomLayouts.CELL), floori((p.y + half.y) / RoomLayouts.CELL))

    func centre_of(cx: int, cy: int) -> Vector2:
        return Vector2((float(cx) + 0.5) * RoomLayouts.CELL - half.x, (float(cy) + 0.5) * RoomLayouts.CELL - half.y)

    func inside(cx: int, cy: int) -> bool:
        return cx >= 0 and cy >= 0 and cx < w and cy < h

    ## Indices of every cell whose centre lies inside `r` (room-local px).
    func cells_in(r: Rect2) -> PackedInt32Array:
        var out := PackedInt32Array()
        var a := cell_of(r.position)
        var b := cell_of(r.end)
        for cy in range(maxi(0, a.y), mini(h, b.y + 1)):
            for cx in range(maxi(0, a.x), mini(w, b.x + 1)):
                if r.has_point(centre_of(cx, cy)):
                    out.append(cy * w + cx)
        return out

    func cells_near(c: Vector2, rad: float) -> PackedInt32Array:
        var out := PackedInt32Array()
        var a := cell_of(c - Vector2(rad, rad))
        var b := cell_of(c + Vector2(rad, rad))
        for cy in range(maxi(0, a.y), mini(h, b.y + 1)):
            for cx in range(maxi(0, a.x), mini(w, b.x + 1)):
                if centre_of(cx, cy).distance_to(c) <= rad:
                    out.append(cy * w + cx)
        return out

    func wall(r: Rect2, st: int = 0) -> void:
        for i in cells_in(r):
            cells[i] = RoomLayouts.WALL
            style[i] = st
            terrain[i] = RoomLayouts.T_NONE

    func chasm(r: Rect2) -> void:
        for i in cells_in(r):
            cells[i] = RoomLayouts.CHASM
            terrain[i] = RoomLayouts.T_NONE

    ## Terrain on open floor only.
    func paint(r: Rect2, t: int) -> void:
        for i in cells_in(r):
            if cells[i] == RoomLayouts.OPEN:
                terrain[i] = t

    func paint_circle(c: Vector2, rad: float, t: int) -> void:
        for i in cells_near(c, rad):
            if cells[i] == RoomLayouts.OPEN:
                terrain[i] = t

    ## Opens every blocker within `rad`; `all_terrain` also dries the floor, else only
    ## deep water goes (oil, ice and grass may lie in the middle of a room).
    func clear_circle(c: Vector2, rad: float, all_terrain: bool) -> void:
        for i in cells_near(c, rad):
            cells[i] = RoomLayouts.OPEN
            if all_terrain or terrain[i] == RoomLayouts.T_DEEP:
                terrain[i] = RoomLayouts.T_NONE

    func clear_rect(r: Rect2) -> void:
        for i in cells_in(r):
            cells[i] = RoomLayouts.OPEN
            terrain[i] = RoomLayouts.T_NONE

    func dry_circle(c: Vector2, rad: float) -> void:
        for i in cells_near(c, rad):
            terrain[i] = RoomLayouts.T_NONE

    ## Every cell within `rad` of `q` open (and dry when `dry`), and `q` clear of `avoid`.
    func area_open(q: Vector2, rad: float, dry: bool) -> bool:
        if absf(q.x) > half.x - rad or absf(q.y) > half.y - rad:
            return false
        for i in cells_near(q, rad):
            if cells[i] != RoomLayouts.OPEN or (dry and terrain[i] != RoomLayouts.T_NONE):
                return false
        for a in avoid:
            var ap: Vector2 = a[0]
            if q.distance_to(ap) < float(a[1]):
                return false
        return true

    ## A random open spot, or Vector2.INF.
    func find_open(rad: float, dry: bool, min_centre: float = 150.0) -> Vector2:
        for attempt in 50:
            var q := Vector2(rng.randf_range(-half.x + 70.0, half.x - 70.0), rng.randf_range(-half.y + 70.0, half.y - 70.0))
            if q.length() < min_centre:
                continue
            if area_open(q, rad, dry):
                return q
        return Vector2.INF

    func prop(kind: String, pos: Vector2, spacing: float = 60.0) -> void:
        if pos != Vector2.INF:
            props.append({ "kind": kind, "pos": pos })
            avoid.append([pos, spacing])

    ## Distance from a cell to the nearest terrain cell of kind `t`, in px (INF if none near).
    func near_terrain(q: Vector2, t: int, rad: float) -> bool:
        for i in cells_near(q, rad):
            if terrain[i] == t:
                return true
        return false


## Generates `layout_name` for a room of `size`; `keep` is [[pos, radius], ...] (centre,
## pedestals), `doors` the door positions (room-local, in the wall). Falls back to simpler
## layouts until one passes the reachability check.
static func build(layout_name: String, seed_v: int, size: Vector2, keep: Array, doors: Array, alcove: bool) -> Plan:
    var tries: Array = [layout_name]
    for f in ["four_pillars", "open"]:
        if not tries.has(f):
            tries.append(f)
    var last: Plan = null
    for i in tries.size():
        var nm: String = tries[i]
        if size.y < 700.0 and min_size(nm) >= 1:
            continue
        var variants: Array = [true, false] if alcove else [false]
        for with_alcove in variants:
            var p := Plan.new(size, seed_v + i * 7919)
            p.name = nm
            _generate(p)
            _clear_zones(p, keep, doors)
            if with_alcove and not _carve_alcove(p, doors):
                continue
            _place_props(p, keep, doors)
            last = p
            if validate(p, keep, doors):
                _mark_unreachable(p)
                return p
    if last == null:
        last = Plan.new(size, seed_v)
    _mark_unreachable(last)
    return last


static func _generate(p: Plan) -> void:
    match p.name:
        "four_pillars":
            _four_pillars(p)
        "pillar_hall":
            _pillar_hall(p)
        "cross":
            _cross(p)
        "l_shape":
            _l_shape(p)
        "ring":
            _ring(p)
        "moat":
            _moat(p)
        "rift":
            _rift(p)
        "flooded":
            _flooded(p)
        "channels":
            _channels(p)
        "refinery":
            _refinery(p)
        "frozen":
            _frozen(p)
        "broken":
            _broken(p)
        "twin":
            _twin(p)
        "diagonal":
            _diagonal(p)
        "pit_maze":
            _pit_maze(p)
        "overgrown":
            _overgrown(p)
        "buttresses":
            _buttresses(p)
        "bastions":
            _bastions(p)
        "corner_pits":
            _corner_pits(p)
        "colonnade":
            _colonnade(p)
        "spring":
            _spring(p)


# --- Generators (room-local px, origin at the centre) --------------------------


static func _four_pillars(p: Plan) -> void:
    var b := 80.0 if p.size.x >= 1100.0 else 60.0
    var o := Vector2(p.half.x * 0.45, p.half.y * 0.42)
    for sx in [-1.0, 1.0]:
        for sy in [-1.0, 1.0]:
            p.wall(Rect2(Vector2(sx * o.x, sy * o.y) - Vector2(b, b) / 2.0, Vector2(b, b)), S_PILLAR)


static func _pillar_hall(p: Plan) -> void:
    var n := 4 if p.size.x < 1000.0 else (5 if p.size.x < 1300.0 else 6)
    var y := p.half.y * 0.48
    for row in [-1.0, 1.0]:
        for i in n:
            var x := lerpf(-p.half.x * 0.72, p.half.x * 0.72, float(i) / float(n - 1))
            p.wall(Rect2(x - 20.0, row * y - 20.0, 40.0, 40.0), S_PILLAR)


## Walls along both axes, open in the middle and short of the doors; where the room is
## too short for the vertical arms, the horizontal ones end in T caps instead.
static func _cross(p: Plan) -> void:
    var t := 40.0
    var gx := p.half.x - 170.0
    var gy := p.half.y - 150.0
    p.wall(Rect2(-gx, -t / 2.0, gx - 150.0, t))
    p.wall(Rect2(150.0, -t / 2.0, gx - 150.0, t))
    if gy - 170.0 >= 80.0:
        p.wall(Rect2(-t / 2.0, -gy, t, gy - 140.0))
        p.wall(Rect2(-t / 2.0, 170.0, t, gy - 170.0))
    else:
        for sx in [-1.0, 1.0]:
            var cx: float = sx * gx
            p.wall(Rect2(cx - t / 2.0 + sx * -t / 2.0, -70.0, t, 140.0))


static func _l_shape(p: Plan) -> void:
    var sx := 1.0 if p.rng.randf() < 0.5 else -1.0
    var sy := 1.0 if p.rng.randf() < 0.5 else -1.0
    var x0 := maxf(170.0, p.half.x * 0.32)
    var y0 := maxf(150.0, p.half.y * 0.38)
    var a := Vector2(sx * x0, sy * y0)
    var b := Vector2(sx * p.half.x, sy * p.half.y)
    p.wall(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs()))


static func _ring(p: Plan) -> void:
    var cx := minf(p.half.x - 180.0, 340.0)
    var cy := p.half.y - 150.0
    var t := 40.0
    p.wall(Rect2(-cx, -cy - t / 2.0, 2.0 * cx, t))
    p.wall(Rect2(-cx, cy - t / 2.0, 2.0 * cx, t))
    p.wall(Rect2(-cx - t / 2.0, -cy, t, 2.0 * cy))
    p.wall(Rect2(cx - t / 2.0, -cy, t, 2.0 * cy))
    var corners: Array = [Vector2(-cx, -cy), Vector2(cx, cy)] if p.rng.randf() < 0.5 else [Vector2(cx, -cy), Vector2(-cx, cy)]
    for c in corners:
        var cv: Vector2 = c
        p.clear_rect(Rect2(cv - Vector2(130.0, 130.0), Vector2(260.0, 260.0)))


static func _moat(p: Plan) -> void:
    var ix := p.half.x * 0.45
    var iy := maxf(180.0, p.half.y * 0.42)
    var m := 60.0
    var bw := 60.0
    p.chasm(Rect2(-ix - m, -iy - m, 2.0 * (ix + m), m))
    p.chasm(Rect2(-ix - m, iy, 2.0 * (ix + m), m))
    p.chasm(Rect2(-ix - m, -iy, m, 2.0 * iy))
    p.chasm(Rect2(ix, -iy, m, 2.0 * iy))
    p.clear_rect(Rect2(-bw, -iy - m - 10.0, 2.0 * bw, m + 20.0))
    p.clear_rect(Rect2(-bw, iy - 10.0, 2.0 * bw, m + 20.0))
    p.clear_rect(Rect2(-ix - m - 10.0, -bw, m + 20.0, 2.0 * bw))
    p.clear_rect(Rect2(ix - 10.0, -bw, m + 20.0, 2.0 * bw))


static func _rift(p: Plan) -> void:
    var sx := 1.0 if p.rng.randf() < 0.5 else -1.0
    var x0 := sx * p.half.x * 0.38
    var wdt := 70.0
    var j := 0.0
    var y := -p.half.y
    while y < p.half.y:
        j = clampf(j + p.rng.randf_range(-12.0, 12.0), -30.0, 30.0)
        p.chasm(Rect2(x0 - wdt / 2.0 + j, y, wdt, CELL))
        y += CELL
    var by := p.half.y * 0.6 * (1.0 if p.rng.randf() < 0.5 else -1.0)
    for bridge_y in [0.0, by]:
        p.clear_rect(Rect2(x0 - 90.0, float(bridge_y) - 60.0, 180.0, 120.0))


static func _flooded(p: Plan) -> void:
    p.paint(Rect2(-p.half.x + 20.0, -p.half.y + 20.0, p.size.x - 40.0, p.size.y - 40.0), T_DEEP)
    p.dry_circle(Vector2.ZERO, 160.0)
    for i in p.rng.randi_range(2, 4):
        var c := Vector2(p.rng.randf_range(-p.half.x + 120.0, p.half.x - 120.0), p.rng.randf_range(-p.half.y + 110.0, p.half.y - 110.0))
        p.dry_circle(c, p.rng.randf_range(60.0, 100.0))


static func _channels(p: Plan) -> void:
    var y := p.half.y * 0.5
    var d := 70.0
    for s in [-1.0, 1.0]:
        p.paint(Rect2(-p.half.x, s * y - d / 2.0, p.size.x, d), T_DEEP)


static func _refinery(p: Plan) -> void:
    for i in p.rng.randi_range(4, 6):
        var sz := Vector2(p.rng.randf_range(80.0, 170.0), p.rng.randf_range(60.0, 120.0))
        var c := Vector2(p.rng.randf_range(-p.half.x + 100.0, p.half.x - 100.0), p.rng.randf_range(-p.half.y + 90.0, p.half.y - 90.0))
        p.paint(Rect2(c - sz / 2.0, sz), T_OIL)
    for i in 2:
        var q := p.find_open(40.0, false, 180.0)
        if q != Vector2.INF:
            p.wall(Rect2(q - Vector2(20, 20), Vector2(40, 40)), S_PILLAR)


static func _frozen(p: Plan) -> void:
    p.paint(Rect2(-p.half.x + 20.0, -p.half.y + 20.0, p.size.x - 40.0, p.size.y - 40.0), T_ICE)
    for i in p.rng.randi_range(2, 4):
        var q := p.find_open(40.0, false, 180.0)
        if q != Vector2.INF:
            p.wall(Rect2(q - Vector2(20, 20), Vector2(40, 40)), S_PILLAR)


static func _broken(p: Plan) -> void:
    for c_i in p.rng.randi_range(5, 8):
        var c := Vector2(p.rng.randf_range(-p.half.x + 110.0, p.half.x - 110.0), p.rng.randf_range(-p.half.y + 100.0, p.half.y - 100.0))
        if c.length() < 170.0:
            continue
        for k in p.rng.randi_range(2, 4):
            var s := p.rng.randf_range(20.0, 44.0)
            var o := Vector2(p.rng.randf_range(-34.0, 34.0), p.rng.randf_range(-30.0, 30.0))
            p.wall(Rect2(c + o - Vector2(s, s) / 2.0, Vector2(s, s)), S_RUBBLE)


static func _twin(p: Plan) -> void:
    if p.half.y >= 400.0 and p.rng.randf() < 0.5:
        p.wall(Rect2(-20.0, -p.half.y, 40.0, p.half.y - 150.0))
        p.wall(Rect2(-20.0, 150.0, 40.0, p.half.y - 150.0))
    else:
        p.wall(Rect2(-p.half.x, -20.0, p.half.x - 160.0, 40.0))
        p.wall(Rect2(160.0, -20.0, p.half.x - 160.0, 40.0))


static func _diagonal(p: Plan) -> void:
    var sy := 1.0 if p.rng.randf() < 0.5 else -1.0
    var a := Vector2(-0.7 * p.half.x, -0.6 * p.half.y * sy)
    var b := -a
    var steps := int(a.distance_to(b) / CELL)
    for k in steps + 1:
        var t := float(k) / float(maxi(1, steps))
        if t > 0.36 and t < 0.64:
            continue
        var q := a.lerp(b, t)
        p.wall(Rect2(q - Vector2(20, 20), Vector2(40, 40)))


static func _pit_maze(p: Plan) -> void:
    var want := p.rng.randi_range(5, 8)
    var pits: Array[Rect2] = []
    for attempt in 60:
        if pits.size() >= want:
            break
        var s := Vector2(p.rng.randf_range(60.0, 100.0), p.rng.randf_range(60.0, 100.0))
        var c := Vector2(p.rng.randf_range(-p.half.x + 130.0, p.half.x - 130.0), p.rng.randf_range(-p.half.y + 130.0, p.half.y - 130.0))
        if c.length() < 200.0:
            continue
        var r := Rect2(c - s / 2.0, s)
        var ok := true
        for q in pits:
            if q.grow(125.0).intersects(r):
                ok = false
                break
        if ok:
            pits.append(r)
            p.chasm(r)


static func _overgrown(p: Plan) -> void:
    for i in p.rng.randi_range(5, 8):
        var c := Vector2(p.rng.randf_range(-p.half.x + 90.0, p.half.x - 90.0), p.rng.randf_range(-p.half.y + 90.0, p.half.y - 90.0))
        p.paint_circle(c, p.rng.randf_range(60.0, 110.0), T_GRASS)


static func _buttresses(p: Plan) -> void:
    var t := 40.0
    var l := p.half.y * 0.35
    var lx := p.half.x * 0.22
    for sx in [-1.0, 1.0]:
        var x: float = sx * p.half.x * 0.5
        p.wall(Rect2(x - t / 2.0, -p.half.y, t, l))
        p.wall(Rect2(x - t / 2.0, p.half.y - l, t, l))
    for sy in [-1.0, 1.0]:
        var y: float = sy * p.half.y * 0.55
        p.wall(Rect2(-p.half.x, y - t / 2.0, lx, t))
        p.wall(Rect2(p.half.x - lx, y - t / 2.0, lx, t))


static func _bastions(p: Plan) -> void:
    var t := 40.0
    var c := Vector2(p.half.x * 0.5, p.half.y * 0.5)
    for sx in [-1.0, 1.0]:
        for sy in [-1.0, 1.0]:
            var fx: float = sx
            var fy: float = sy
            var k := Vector2(fx * c.x, fy * c.y)
            # The corner of the L points at the room corner; its arms reach toward the axes.
            var hx0 := minf(k.x - fx * 120.0, k.x + fx * t / 2.0)
            var vy0 := minf(k.y - fy * 100.0, k.y + fy * t / 2.0)
            p.wall(Rect2(Vector2(hx0, k.y - t / 2.0), Vector2(120.0 + t / 2.0, t)))
            p.wall(Rect2(Vector2(k.x - t / 2.0, vy0), Vector2(t, 100.0 + t / 2.0)))


static func _corner_pits(p: Plan) -> void:
    var s := Vector2(p.half.x * 0.36, p.half.y * 0.36)
    for sx in [-1.0, 1.0]:
        for sy in [-1.0, 1.0]:
            var corner := Vector2(sx * p.half.x, sy * p.half.y)
            var inner := corner - Vector2(sx * s.x, sy * s.y)
            p.chasm(Rect2(Vector2(minf(corner.x, inner.x), minf(corner.y, inner.y)), s))


static func _colonnade(p: Plan) -> void:
    var x := p.half.x - 120.0
    var n := 3 if p.size.y < 700.0 else 4
    for i in n:
        var y := lerpf(-0.45 * p.half.y, 0.55 * p.half.y, float(i) / float(n - 1))
        for s in [-1.0, 1.0]:
            p.wall(Rect2(s * x - 18.0, y - 18.0, 36.0, 36.0), S_PILLAR)


static func _spring(p: Plan) -> void:
    var sx := 1.0 if p.rng.randf() < 0.5 else -1.0
    var x0 := p.half.x * 0.6
    var x1 := p.half.x - 60.0
    var r := Rect2(Vector2(minf(sx * x0, sx * x1), p.half.y * 0.35), Vector2(x1 - x0, p.half.y * 0.65 - 60.0))
    p.paint(r, T_DEEP)


# --- Props that belong to a layout (after the clear zones) ---------------------


static func _place_props(p: Plan, keep: Array, doors: Array) -> void:
    for d in doors:
        var dp: Vector2 = d
        p.avoid.append([dp, 200.0])
    for k in keep:
        p.avoid.append([k[0], float(k[1]) + 40.0])
    match p.name:
        "refinery":
            # Braziers well clear of the slicks: their embers must not light the room alone.
            for i in p.rng.randi_range(2, 3):
                for attempt in 20:
                    var q := p.find_open(30.0, true, 160.0)
                    if q != Vector2.INF and not p.near_terrain(q, T_OIL, 110.0):
                        p.prop("brazier", q, 220.0)
                        break
        "frozen":
            for i in p.rng.randi_range(1, 2):
                p.prop("ice_crystal", p.find_open(30.0, false, 160.0))
        "overgrown":
            if p.rng.randf() < 0.5:
                for attempt in 20:
                    var q := p.find_open(30.0, true, 160.0)
                    if q != Vector2.INF and not p.near_terrain(q, T_GRASS, 100.0):
                        p.prop("brazier", q)
                        break


# --- Constraints ----------------------------------------------------------------


static func _door_inward(d: Vector2) -> Vector2:
    if absf(d.x) > absf(d.y):
        return Vector2(-signf(d.x), 0.0)
    return Vector2(0.0, -signf(d.y))


static func _door_edge(p: Plan, d: Vector2) -> Vector2:
    var inward := _door_inward(d)
    # The point on the floor just inside the doorway.
    if inward.x != 0.0:
        return Vector2(-inward.x * p.half.x, d.y) + inward * 20.0
    return Vector2(d.x, -inward.y * p.half.y) + inward * 20.0


static func _clear_zones(p: Plan, keep: Array, doors: Array) -> void:
    for d in doors:
        p.clear_circle(_door_edge(p, d), DOOR_CLEAR, true)
    for k in keep:
        p.clear_circle(k[0], float(k[1]), false)


## A pocket against one wall, closed by a breakable front, flanked by thin walls.
static func _carve_alcove(p: Plan, doors: Array) -> bool:
    var sides: Array = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
    for i in sides.size():
        var j := p.rng.randi_range(i, sides.size() - 1)
        var tmp: Vector2i = sides[i]
        sides[i] = sides[j]
        sides[j] = tmp
    for side_v in sides:
        var side: Vector2i = side_v
        var span := (p.half.x if side.y != 0 else p.half.y) - 130.0
        if span < 240.0:
            continue
        for attempt in 6:
            var along := p.rng.randf_range(230.0, span) * (1.0 if p.rng.randf() < 0.5 else -1.0)
            along = snappedf(along, CELL)
            var inner := _wall_rect(p, side, along - 70.0, 0.0, 140.0, 100.0)
            var front := _wall_rect(p, side, along - 90.0, 100.0, 180.0, 40.0)
            var flank_a := _wall_rect(p, side, along - 90.0, 0.0, 20.0, 100.0)
            var flank_b := _wall_rect(p, side, along + 70.0, 0.0, 20.0, 100.0)
            var bbox := _wall_rect(p, side, along - 130.0, 0.0, 260.0, 180.0)
            var near_door := false
            for d in doors:
                var dp: Vector2 = d
                if bbox.grow(40.0).has_point(_door_edge(p, dp)):
                    near_door = true
            if near_door:
                continue
            p.clear_rect(bbox)
            for k in p.cells_in(inner):
                p.cells[k] = POCKET
            for k in p.cells_in(front):
                p.cells[k] = BREAK
            p.wall(flank_a)
            p.wall(flank_b)
            p.alcove = { "front": front, "inner": inner, "out": -Vector2(side) }
            p.avoid.append([inner.get_center(), 170.0])
            return true
    return false


## A rect in wall coordinates: `u` along the wall, `v` inward from the wall face.
static func _wall_rect(p: Plan, side: Vector2i, u: float, v: float, du: float, dv: float) -> Rect2:
    var a: Vector2
    var b: Vector2
    if side == Vector2i.UP:
        a = Vector2(u, -p.half.y + v)
        b = Vector2(u + du, -p.half.y + v + dv)
    elif side == Vector2i.DOWN:
        a = Vector2(u, p.half.y - v)
        b = Vector2(u + du, p.half.y - v - dv)
    elif side == Vector2i.LEFT:
        a = Vector2(-p.half.x + v, u)
        b = Vector2(-p.half.x + v + dv, u + du)
    else:
        a = Vector2(p.half.x - v, u)
        b = Vector2(p.half.x - v - dv, u + du)
    return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


static func blocks(v: int) -> bool:
    return v == WALL or v == CHASM or v == BREAK or v == POCKET


## Clearance (cells to the nearest blocker or the room edge) for every cell.
static func clearance(p: Plan) -> PackedInt32Array:
    var dist := PackedInt32Array()
    dist.resize(p.w * p.h)
    var queue := PackedInt32Array()
    for i in p.w * p.h:
        if blocks(p.cells[i]):
            dist[i] = 0
            queue.append(i)
        else:
            dist[i] = 1 << 20
    var head := 0
    while head < queue.size():
        var i := queue[head]
        head += 1
        var cx := i % p.w
        var cy := i / p.w
        var nd := dist[i] + 1
        for oy in range(-1, 2):
            for ox in range(-1, 2):
                var nx := cx + ox
                var ny := cy + oy
                if (ox == 0 and oy == 0) or not p.inside(nx, ny):
                    continue
                var j := ny * p.w + nx
                if dist[j] > nd:
                    dist[j] = nd
                    queue.append(j)
    for i in p.w * p.h:
        var cx := i % p.w
        var cy := i / p.w
        dist[i] = mini(dist[i], mini(mini(cx + 1, cy + 1), mini(p.w - cx, p.h - cy)))
    return dist


## Every door landing and keep spot joined to the centre by wide corridors.
static func validate(p: Plan, keep: Array, doors: Array) -> bool:
    var clear := clearance(p)
    var start := p.cell_of(Vector2.ZERO)
    if not p.inside(start.x, start.y) or clear[start.y * p.w + start.x] < MIN_CLEARANCE:
        return false
    var seen := PackedByteArray()
    seen.resize(p.w * p.h)
    seen.fill(0)
    var queue := PackedInt32Array([start.y * p.w + start.x])
    seen[queue[0]] = 1
    var head := 0
    while head < queue.size():
        var i := queue[head]
        head += 1
        var cx := i % p.w
        var cy := i / p.w
        for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var nx: int = cx + dir.x
            var ny: int = cy + dir.y
            if not p.inside(nx, ny):
                continue
            var j := ny * p.w + nx
            if seen[j] == 0 and clear[j] >= MIN_CLEARANCE:
                seen[j] = 1
                queue.append(j)
    var targets: Array[Vector2] = []
    for d in doors:
        var dp: Vector2 = d
        targets.append(_door_edge(p, dp) + _door_inward(dp) * 50.0)
    for k in keep:
        targets.append(k[0])
    for t in targets:
        var c := p.cell_of(t)
        var hit := false
        for oy in range(-1, 2):
            for ox in range(-1, 2):
                if p.inside(c.x + ox, c.y + oy) and seen[(c.y + oy) * p.w + c.x + ox] == 1:
                    hit = true
        if not hit:
            return false
    return true


## Open floor nobody can walk to from the centre becomes UNREACH.
static func _mark_unreachable(p: Plan) -> void:
    var start := p.cell_of(Vector2.ZERO)
    if not p.inside(start.x, start.y):
        return
    var seen := PackedByteArray()
    seen.resize(p.w * p.h)
    seen.fill(0)
    var queue := PackedInt32Array([start.y * p.w + start.x])
    seen[queue[0]] = 1
    var head := 0
    while head < queue.size():
        var i := queue[head]
        head += 1
        var cx := i % p.w
        var cy := i / p.w
        for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var nx: int = cx + dir.x
            var ny: int = cy + dir.y
            if not p.inside(nx, ny):
                continue
            var j := ny * p.w + nx
            if seen[j] == 0 and p.cells[j] == OPEN:
                seen[j] = 1
                queue.append(j)
    for i in p.w * p.h:
        if p.cells[i] == OPEN and seen[i] == 0:
            p.cells[i] = UNREACH
            p.terrain[i] = T_NONE


## Greedy merge of the cells equal to `value` (and `st` style when >= 0) into rects, in cells.
static func rects_of(cells: PackedByteArray, w: int, h: int, value: int, styles: PackedByteArray = PackedByteArray(), st: int = -1) -> Array[Rect2i]:
    var out: Array[Rect2i] = []
    var used := PackedByteArray()
    used.resize(w * h)
    used.fill(0)
    var use_style := st >= 0 and styles.size() == cells.size()
    for y in h:
        for x in w:
            var i := y * w + x
            if used[i] != 0 or cells[i] != value or (use_style and styles[i] != st):
                continue
            var x2 := x
            while x2 + 1 < w:
                var k := y * w + x2 + 1
                if used[k] != 0 or cells[k] != value or (use_style and styles[k] != st):
                    break
                x2 += 1
            var y2 := y
            var grow := true
            while grow and y2 + 1 < h:
                for xx in range(x, x2 + 1):
                    var k := (y2 + 1) * w + xx
                    if used[k] != 0 or cells[k] != value or (use_style and styles[k] != st):
                        grow = false
                        break
                if grow:
                    y2 += 1
            for yy in range(y, y2 + 1):
                for xx in range(x, x2 + 1):
                    used[yy * w + xx] = 1
            out.append(Rect2i(x, y, x2 - x + 1, y2 - y + 1))
    return out
