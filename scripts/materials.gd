class_name Materials
extends Node2D
## The floor's material layer, Noita style but top-down: elements land on the floor as
## materials in a grid of 8 px cells and keep interacting there. Oil pools and burns,
## water spreads, douses fire into steam and carries a shock through the whole pool,
## ice freezes water and melts by fire, poison gas drifts, acid eats oil and ice, blood
## sticks and dries. Bodies read `material_at()` a few times a second (Enemy, Player).
##
## BUDGET (single-threaded web build):
##   - The grid is a handful of PackedByteArrays (mat, amt, life, flag): a 1120x720 room
##     is 140x90 = 12,600 cells, ~50 KB. No per-cell Dictionaries or Objects.
##   - The simulation steps STEPS_PER_SEC (12) times a second, never per frame, and visits
##     only cells in the active queue (burning, flowing, drifting, dissolving, charged),
##     at most STEP_CAP (2500) per step; the rest carry over to the next step (FIFO).
##   - Settled liquids, ice, blood and scorch marks are not stepped: a 1 Hz sweep over the
##     list of non-empty cells ages them (evaporate, dry, melt, fade) and compacts that list.
##   - Drawing walks the non-empty list only, 1-2 rects per cell, and only redraws after a
##     step that changed something (or while fire / charge flicker).
##   - Fx: one ember per ~8 burning cells per step, one smoke per ~32; shock sparks capped.
##   Normal load (8 puddle clouds of ~20-40 cells, a few fires) is a few hundred cell
##   updates a step and a few hundred rects per redraw.

enum { NONE, OIL, WATER, FIRE, ICE, POISON, ACID, BLOOD, STEAM, CHARGED, ASH, DRY_BLOOD }
const MAT_COUNT := 12

const CELL := 8
const STEPS_PER_SEC := 12.0
const STEP_CAP := 2500
const SWEEP_EVERY := 12          # steps between slow sweeps (1 s)
const MAX_LAY_RADIUS := 64.0     # stamps lay new material only this far; conversions reach the full radius
const MAX_CHARGE := 2500         # cells one shock stamp may charge
const ICE_KEEP := 0.88           # share of velocity kept per 60 Hz frame on ice: a real glide

# Thresholds and lifetimes. Slow materials count life in seconds (sweep), fast ones in steps.
const WATER_SPREAD := 24
const OIL_SPREAD := 32
const ACID_SPREAD := 40
const WATER_LIFE := 8            # s
const OIL_LIFE := 40             # s
const BLOOD_LIFE := 5            # s, then dries
const DRY_LIFE := 40             # s, scorch and dried blood
const ICE_LIFE := 10             # s, then melts to water
const POISON_TICKS := 60
const ACID_TICKS := 48
const STEAM_TICKS := 6
const CHARGE_TICKS := 6          # ~0.5 s
const FIRE_TICKS := 9            # bare-floor fire (forced)

const F_ACTIVE := 1
const F_DRAWN := 2

var mat := PackedByteArray()
var amt := PackedByteArray()
var life := PackedByteArray()
var _flag := PackedByteArray()
var _queue := PackedInt32Array()   # active cells, FIFO; _head is the next to step
var _head := 0
var _drawn := PackedInt32Array()   # every cell that may be non-empty

var _w := 0
var _h := 0
var _n := 0
var _origin := Vector2.ZERO        # local position of cell (0, 0)
var _acc := 0.0
var _step_n := 0
var _dirty := false
var _flicker := false
var _fire_fx := 0
var _fx: Object = null
var _cols := PackedColorArray()


func _init(room_rect: Rect2 = Rect2(-560, -360, 1120, 720)) -> void:
    name = "Materials"
    z_index = -1
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _origin = room_rect.position
    _w = maxi(1, ceili(room_rect.size.x / float(CELL)))
    _h = maxi(1, ceili(room_rect.size.y / float(CELL)))
    _n = _w * _h
    mat.resize(_n)
    amt.resize(_n)
    life.resize(_n)
    _flag.resize(_n)
    clear()
    _cols.resize(MAT_COUNT)
    _cols[NONE] = Color(0, 0, 0, 0)
    _cols[OIL] = Color(Element.COLORS[Element.Kind.OIL].darkened(0.35), 0.6)
    _cols[WATER] = Color(Element.COLORS[Element.Kind.WET], 0.42)
    _cols[FIRE] = Color(Element.COLORS[Element.Kind.FIRE], 0.6)
    _cols[ICE] = Color(Element.COLORS[Element.Kind.ICE], 0.45)
    _cols[POISON] = Color(Element.COLORS[Element.Kind.POISON], 0.38)
    _cols[ACID] = Color(Element.COLORS[Element.Kind.ACID], 0.5)
    _cols[BLOOD] = Color(Element.COLORS[Element.Kind.BLOOD], 0.55)
    _cols[STEAM] = Color(0.9, 0.93, 0.96, 0.35)
    _cols[CHARGED] = Color(Element.COLORS[Element.Kind.SHOCK], 0.55)
    _cols[ASH] = Color(0.05, 0.04, 0.04, 0.45)
    _cols[DRY_BLOOD] = Color(Element.COLORS[Element.Kind.BLOOD].darkened(0.6), 0.45)


## The current room's material layer, or null (menus, transitions).
static func find(node: Node) -> Materials:
    if node == null or not node.is_inside_tree():
        return null
    var scene := node.get_tree().current_scene
    if scene == null or not "current" in scene:
        return null
    var room: Variant = scene.get("current")
    if room == null or not is_instance_valid(room) or not "materials" in room:
        return null
    var m: Variant = room.get("materials")
    if m == null or not is_instance_valid(m):
        return null
    return m as Materials


func clear() -> void:
    mat.fill(0)
    amt.fill(0)
    life.fill(0)
    _flag.fill(0)
    _queue = PackedInt32Array()
    _head = 0
    _drawn = PackedInt32Array()
    _dirty = true


# --- Public API (world coordinates) ------------------------------------------


## Puts an element on the floor as its material. `force` lets Fire burn bare floor.
func stamp(kind: int, pos: Vector2, radius: float, amount: int, force: bool = false) -> void:
    var local := pos - global_position - _origin
    var r := clampf(radius, 6.0, 240.0)
    if kind == Element.Kind.GALE:
        _gale(local, minf(r, 120.0))
        return
    if not (kind in [Element.Kind.WET, Element.Kind.OIL, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.POISON,
            Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.SHOCK]):
        return
    var a := clampi(amount, 8, 255)
    var r2 := r * r
    var lay := minf(r, MAX_LAY_RADIUS)
    var lay2 := lay * lay
    var ccx := floori(local.x / float(CELL))
    var ccy := floori(local.y / float(CELL))
    var rc := ceili(r / float(CELL))
    var charged := 0
    for cy in range(maxi(0, ccy - rc), mini(_h, ccy + rc + 1)):
        var dy := float(cy * CELL + CELL / 2) - local.y
        for cx in range(maxi(0, ccx - rc), mini(_w, ccx + rc + 1)):
            var dx := float(cx * CELL + CELL / 2) - local.x
            var d2 := dx * dx + dy * dy
            if d2 > r2:
                continue
            var i := cy * _w + cx
            if kind == Element.Kind.SHOCK:
                if mat[i] == WATER and charged < MAX_CHARGE:
                    charged += _charge_from(i, MAX_CHARGE - charged)
                continue
            _stamp_cell(kind, i, a, force, d2 <= lay2)
    _dirty = true


## Sets fuel alight (oil, cells beside fire); `force` burns bare floor too.
func ignite(pos: Vector2, radius: float, force: bool = false) -> void:
    stamp(Element.Kind.FIRE, pos, radius, 200, force)


func material_at(pos: Vector2) -> int:
    var i := _index_at(pos)
    return NONE if i < 0 else mat[i]


func is_slippery(pos: Vector2) -> bool:
    return material_at(pos) == ICE


## Wipes every cell overlapping a world rect.
func clear_rect(world_rect: Rect2) -> void:
    var lr := Rect2(world_rect.position - global_position - _origin, world_rect.size)
    var x0 := maxi(0, floori(lr.position.x / float(CELL)))
    var y0 := maxi(0, floori(lr.position.y / float(CELL)))
    var x1 := mini(_w - 1, floori(lr.end.x / float(CELL)))
    var y1 := mini(_h - 1, floori(lr.end.y / float(CELL)))
    for cy in range(y0, y1 + 1):
        for cx in range(x0, x1 + 1):
            _put(cy * _w + cx, NONE, 0, 0)
    _dirty = true


# --- Cells -------------------------------------------------------------------


func _index_at(pos: Vector2) -> int:
    var local := pos - global_position - _origin
    var cx := floori(local.x / float(CELL))
    var cy := floori(local.y / float(CELL))
    if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
        return -1
    return cy * _w + cx


func _cell_world(i: int) -> Vector2:
    return global_position + _origin + Vector2(float((i % _w) * CELL + CELL / 2), float((i / _w) * CELL + CELL / 2))


## Neighbour in direction d (0 left, 1 right, 2 up, 3 down), or -1 at the edge.
func _nb(i: int, d: int) -> int:
    if d == 0:
        return i - 1 if i % _w != 0 else -1
    if d == 1:
        return i + 1 if i % _w != _w - 1 else -1
    if d == 2:
        return i - _w if i >= _w else -1
    return i + _w if i + _w < _n else -1


func _put(i: int, m: int, a: int, l: int) -> void:
    mat[i] = m
    amt[i] = clampi(a, 0, 255)
    life[i] = clampi(l, 0, 255)
    if m != NONE and (_flag[i] & F_DRAWN) == 0:
        _flag[i] = _flag[i] | F_DRAWN
        _drawn.append(i)
    _dirty = true


func _wake(i: int) -> void:
    if (_flag[i] & F_ACTIVE) == 0:
        _flag[i] = _flag[i] | F_ACTIVE
        _queue.append(i)


## Empty floor (or an inert mark), free for liquids and gas to cover.
func _open(m: int) -> bool:
    return m == NONE or m == ASH or m == DRY_BLOOD


func _has_fire_nb(i: int) -> bool:
    for d in 4:
        var j := _nb(i, d)
        if j >= 0 and mat[j] == FIRE:
            return true
    return false


func _ignite_cell(i: int) -> void:
    _put(i, FIRE, 255, clampi(10 + int(amt[i]) / 5, 10, 60))
    _wake(i)


func _stamp_cell(kind: int, i: int, a: int, force: bool, lay: bool) -> void:
    var m := int(mat[i])
    match kind:
        Element.Kind.WET:
            if m == WATER:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = maxi(int(life[i]), WATER_LIFE)
                _wake(i)
            elif m == FIRE:
                _put(i, STEAM, 160, STEAM_TICKS)
                _wake(i)
            elif m == ACID:
                var left := int(amt[i]) - a / 2
                if left <= 8:
                    _put(i, NONE, 0, 0)
                else:
                    amt[i] = left
            elif lay and (_open(m) or m == STEAM or m == POISON or m == BLOOD):
                _put(i, WATER, a, WATER_LIFE)
                _wake(i)
        Element.Kind.OIL:
            if m == OIL:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = maxi(int(life[i]), OIL_LIFE)
                _wake(i)
            elif m == FIRE:
                life[i] = mini(255, int(life[i]) + a / 8)
            elif lay and (_open(m) or m == STEAM or m == POISON):
                _put(i, OIL, a, OIL_LIFE)
                _wake(i)
        Element.Kind.FIRE:
            if m == OIL:
                _ignite_cell(i)
            elif m == FIRE:
                life[i] = maxi(int(life[i]), 12)
            elif m == WATER or m == CHARGED:
                if lay:
                    _put(i, STEAM, 160, STEAM_TICKS)
                    _wake(i)
            elif m == ICE:
                _put(i, WATER, 48, 4)
            elif lay and _open(m) and (force or _has_fire_nb(i)):
                _put(i, FIRE, 255, FIRE_TICKS + randi() % 6)
                _wake(i)
        Element.Kind.ICE:
            if m == WATER or m == CHARGED:
                _put(i, ICE, 200, ICE_LIFE)
                _wake(i)
            elif m == FIRE:
                _put(i, STEAM, 120, STEAM_TICKS)
                _wake(i)
            elif lay and _open(m):
                _put(i, ICE, 200, ICE_LIFE / 2 + 1)
                _wake(i)
        Element.Kind.POISON:
            if m == POISON:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = POISON_TICKS
            elif lay and (_open(m) or m == STEAM):
                _put(i, POISON, a, POISON_TICKS)
                _wake(i)
        Element.Kind.ACID:
            if m == ACID:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = ACID_TICKS
            elif m == OIL or m == ICE:
                _put(i, NONE, 0, 0)
            elif lay and (_open(m) or m == STEAM or m == POISON):
                _put(i, ACID, a, ACID_TICKS)
                _wake(i)
        Element.Kind.BLOOD:
            if m == BLOOD:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = BLOOD_LIFE
            elif lay and (_open(m) or m == STEAM):
                _put(i, BLOOD, a, BLOOD_LIFE)


## Shock through water: the whole connected pool flashes charged. Returns cells charged.
func _charge_from(i0: int, cap: int) -> int:
    if mat[i0] != WATER:
        return 0
    var stack := PackedInt32Array([i0])
    _put(i0, CHARGED, amt[i0], CHARGE_TICKS)
    _wake(i0)
    var count := 1
    while stack.size() > 0 and count < cap:
        var i := stack[stack.size() - 1]
        stack.resize(stack.size() - 1)
        for d in 4:
            var j := _nb(i, d)
            if j >= 0 and mat[j] == WATER:
                _put(j, CHARGED, amt[j], CHARGE_TICKS)
                _wake(j)
                stack.append(j)
                count += 1
                if count % 24 == 0:
                    _spark(j)
    _spark(i0)
    return count


## Gale: liquids and gas inside the radius are blown two cells outward where there is room.
func _gale(local: Vector2, r: float) -> void:
    var ccx := floori(local.x / float(CELL))
    var ccy := floori(local.y / float(CELL))
    var rc := ceili(r / float(CELL))
    var r2 := r * r
    # Outer half first so inner cells have somewhere to go.
    for pass_n in 2:
        for cy in range(maxi(0, ccy - rc), mini(_h, ccy + rc + 1)):
            for cx in range(maxi(0, ccx - rc), mini(_w, ccx + rc + 1)):
                var i := cy * _w + cx
                var m := int(mat[i])
                if not (m == WATER or m == OIL or m == BLOOD or m == ACID or m == POISON or m == STEAM or m == CHARGED):
                    continue
                var dv := Vector2(float(cx * CELL + CELL / 2) - local.x, float(cy * CELL + CELL / 2) - local.y)
                var d2 := dv.length_squared()
                if d2 > r2 or ((d2 > r2 * 0.25) != (pass_n == 0)):
                    continue
                var dir := dv.normalized() if d2 > 0.5 else Vector2.RIGHT.rotated(randf() * TAU)
                var tx := cx + roundi(dir.x * 2.0)
                var ty := cy + roundi(dir.y * 2.0)
                if tx < 0 or ty < 0 or tx >= _w or ty >= _h:
                    continue
                var j := ty * _w + tx
                if not _open(int(mat[j])):
                    continue
                _put(j, m, amt[i], life[i])
                _put(i, NONE, 0, 0)
                _wake(j)
    _dirty = true


# --- Simulation --------------------------------------------------------------


func _process(delta: float) -> void:
    _acc += delta
    var step_t := 1.0 / STEPS_PER_SEC
    if _acc < step_t:
        return
    _acc = minf(_acc - step_t, step_t)   # at most one step per frame, no catch-up spiral
    _step()


func _step() -> void:
    _step_n += 1
    _flicker = false
    _fx = _find_fx()
    var start := _head
    var end := mini(_queue.size(), _head + STEP_CAP)
    _head = end
    for q in range(start, end):
        var i := _queue[q]
        _flag[i] = _flag[i] & ~F_ACTIVE
        match int(mat[i]):
            FIRE:
                _step_fire(i)
            WATER:
                _step_liquid(i, WATER, WATER_SPREAD, 2)
            OIL:
                _step_liquid(i, OIL, OIL_SPREAD, 1)
            ACID:
                _step_acid(i)
            POISON:
                _step_poison(i)
            STEAM:
                _step_steam(i)
            CHARGED:
                _step_charged(i)
            ICE:
                _step_ice(i)
    if _head >= _queue.size():
        _queue = PackedInt32Array()
        _head = 0
    elif _head > 2048:
        _queue = _queue.slice(_head)
        _head = 0
    if _step_n % SWEEP_EVERY == 0:
        _sweep()
    if _dirty or _flicker:
        _dirty = false
        queue_redraw()


func _step_fire(i: int) -> void:
    _flicker = true
    var doused := false
    for d in 4:
        var j := _nb(i, d)
        if j < 0:
            continue
        var m := int(mat[j])
        if m == OIL:
            if randi() % 3 != 0:
                _ignite_cell(j)
        elif m == WATER or m == CHARGED:
            doused = true
            var left := int(amt[j]) - 24
            if left <= 8:
                _put(j, STEAM, 120, STEAM_TICKS)
                _wake(j)
            else:
                amt[j] = left
        elif m == ICE:
            if randi() % 3 == 0:
                _put(j, WATER, 48, 4)
                _wake(j)
    if doused:
        _put(i, STEAM, 160, STEAM_TICKS)
        _wake(i)
        if _fx != null and randi() % 3 == 0 and _fx.has_method("smoke"):
            _fx.smoke(_cell_world(i), 2, 6.0)
        return
    var l := int(life[i]) - 1
    if l <= 0:
        if randi() % 5 == 0:
            _put(i, ASH, 255, DRY_LIFE)
        else:
            _put(i, NONE, 0, 0)
        return
    life[i] = l
    _wake(i)
    _fire_fx += 1
    if _fire_fx % 8 == 0 and _fx != null:
        var p := _cell_world(i)
        if _fx.has_method("ember"):
            _fx.ember(p + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)))
        if _fire_fx % 32 == 0 and _fx.has_method("smoke"):
            _fx.smoke(p, 1, 4.0)


## Flat spreading: hand half the depth to an empty neighbour, or even out with a
## shallower neighbour of the same liquid, until the cell is thin. Sleeps when nothing moved.
func _step_liquid(i: int, m: int, min_amt: int, tries: int) -> void:
    var a := int(amt[i])
    if a <= min_amt:
        return
    var start := randi() & 3
    var moved := 0
    for k in 4:
        var j := _nb(i, (start + k) & 3)
        if j < 0:
            continue
        var mj := int(mat[j])
        if _open(mj) or mj == STEAM:
            var give := a / 2
            if give < 8:
                break
            _put(j, m, give, life[i])
            a -= give
            _wake(j)
            moved += 1
        elif mj == m:
            var diff := a - int(amt[j])
            if diff > 16:
                var g := diff / 2
                amt[j] = int(amt[j]) + g
                a -= g
                _wake(j)
                moved += 1
        if moved >= tries or a <= min_amt:
            break
    amt[i] = a
    if moved > 0:
        _dirty = true
        if a > min_amt:
            _wake(i)


func _step_acid(i: int) -> void:
    var l := int(life[i]) - 1
    var a := int(amt[i])
    for d in 4:
        var j := _nb(i, d)
        if j < 0:
            continue
        var m := int(mat[j])
        if (m == OIL or m == ICE) and randi() % 3 == 0:
            _put(j, NONE, 0, 0)
            a -= 12
            if _fx != null and randi() % 4 == 0 and _fx.has_method("mote"):
                _fx.mote(Element.Kind.ACID, _cell_world(j))
    if l <= 0 or a <= 8:
        _put(i, NONE, 0, 0)
        return
    life[i] = l
    amt[i] = a
    _step_liquid(i, ACID, ACID_SPREAD, 1)
    if mat[i] == ACID:
        _wake(i)


func _step_poison(i: int) -> void:
    var l := int(life[i]) - 1
    if l <= 0:
        _put(i, NONE, 0, 0)
        return
    life[i] = l
    if l < 12:
        _dirty = true   # fading
    if randi() % 3 == 0:
        var j := _nb(i, randi() & 3)
        if j >= 0 and mat[j] == NONE:
            var a := int(amt[i])
            if a >= 48:
                _put(j, POISON, a / 2, l)
                amt[i] = a - a / 2
            else:
                _put(j, POISON, a, l)
                _put(i, NONE, 0, 0)
                _wake(j)
                return
            _wake(j)
    _wake(i)


func _step_steam(i: int) -> void:
    var l := int(life[i]) - 1
    if l <= 0:
        _put(i, NONE, 0, 0)
        return
    life[i] = l
    _dirty = true
    if randi() % 2 == 0 and i >= _w and mat[i - _w] == NONE:
        _put(i - _w, STEAM, amt[i], l)
        _put(i, NONE, 0, 0)
        _wake(i - _w)
        return
    _wake(i)


func _step_charged(i: int) -> void:
    _flicker = true
    var l := int(life[i]) - 1
    if l <= 0:
        _put(i, WATER, amt[i], 4)
        return
    life[i] = l
    _wake(i)


## Fresh ice creeps through the water it touches, then sleeps.
func _step_ice(i: int) -> void:
    var left := false
    for d in 4:
        var j := _nb(i, d)
        if j < 0:
            continue
        var m := int(mat[j])
        if m == WATER or m == CHARGED:
            if randi() % 2 == 0:
                _put(j, ICE, 200, ICE_LIFE)
                _wake(j)
            else:
                left = true
    if left:
        _wake(i)


## 1 Hz: age the slow materials (evaporate, dry, melt, fade), drop empty cells from the
## draw list, and let obstacles at the doors feel what is on the floor beside them.
func _sweep() -> void:
    var keep := PackedInt32Array()
    for i: int in _drawn:
        var m := int(mat[i])
        if m == NONE:
            _flag[i] = _flag[i] & ~F_DRAWN
            continue
        if m == WATER or m == OIL or m == BLOOD or m == ICE or m == ASH or m == DRY_BLOOD:
            var l := int(life[i]) - 1
            if l > 0:
                life[i] = l
                if l < 8 and (m == ASH or m == DRY_BLOOD):
                    _dirty = true
            else:
                match m:
                    BLOOD:
                        _put(i, DRY_BLOOD, 255, DRY_LIFE)
                    ICE:
                        _put(i, WATER, mini(int(amt[i]), 48), 4)
                    _:
                        _put(i, NONE, 0, 0)
                if mat[i] == NONE:
                    _flag[i] = _flag[i] & ~F_DRAWN
                    continue
        keep.append(i)
    _drawn = keep
    _touch_obstacles()


func _touch_obstacles() -> void:
    if _drawn.is_empty():
        return
    for ob in get_tree().get_nodes_in_group("obstacles"):
        if not is_instance_valid(ob) or ob.is_queued_for_deletion() or not ob.has_method("apply_element") or not ob is Node2D:
            continue
        var sz_v: Variant = ob.get("size")
        var sz: Vector2 = sz_v if sz_v is Vector2 else Vector2(32, 32)
        var gp: Vector2 = (ob as Node2D).global_position
        var lr := Rect2(gp - sz / 2.0 - global_position - _origin, sz).grow(12.0)
        var x0 := maxi(0, floori(lr.position.x / float(CELL)))
        var y0 := maxi(0, floori(lr.position.y / float(CELL)))
        var x1 := mini(_w - 1, floori(lr.end.x / float(CELL)))
        var y1 := mini(_h - 1, floori(lr.end.y / float(CELL)))
        var seen := 0
        for cy in range(y0, y1 + 1):
            for cx in range(x0, x1 + 1):
                match int(mat[cy * _w + cx]):
                    WATER, CHARGED:
                        seen |= 1
                    FIRE:
                        seen |= 2
                    ICE:
                        seen |= 4
                    ACID:
                        seen |= 8
        if seen == 0:
            continue
        # Wet first so a valve can take Wet then Fire (Steam) from the floor in one sweep.
        var kinds := [[1, Element.Kind.WET], [4, Element.Kind.ICE], [8, Element.Kind.ACID], [2, Element.Kind.FIRE]]
        for pair in kinds:
            if (seen & int(pair[0])) != 0 and is_instance_valid(ob) and not ob.is_queued_for_deletion():
                ob.apply_element(int(pair[1]), 1.0)


func _find_fx() -> Object:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        var f: Variant = scene.get("fx")
        if f != null and is_instance_valid(f):
            return f
    return null


func _spark(i: int) -> void:
    if _fx != null and _fx.has_method("pixels"):
        _fx.pixels(Element.Kind.SHOCK, _cell_world(i), 2, 60.0, 4.0)


# --- Drawing -----------------------------------------------------------------


func _draw() -> void:
    var t := _step_n
    var white := Color(1, 1, 1, 0.6)
    for i: int in _drawn:
        var m := int(mat[i])
        if m == NONE:
            continue
        var x := _origin.x + float((i % _w) * CELL)
        var y := _origin.y + float((i / _w) * CELL)
        var h := (i * 73856093) & 0xFFFF
        var c: Color = _cols[m]
        match m:
            FIRE:
                var k := (h + t * 7 + randi()) % 3
                if k == 0:
                    c = Color(1.0, 0.85, 0.35, 0.6)
                elif k == 2:
                    c = Color(0.8, 0.18, 0.06, 0.55)
                draw_rect(Rect2(x, y, 8, 8), c)
                if k == 0 and (h & 1) == 0:
                    draw_rect(Rect2(x + 2, y + 2, 4, 4), Color(1.0, 0.95, 0.6, 0.6))
            POISON, STEAM:
                var fade := minf(1.0, float(life[i]) / 12.0) if m == POISON else minf(1.0, float(life[i]) / 3.0)
                c.a *= fade * clampf(float(amt[i]) / 64.0, 0.5, 1.0)
                var o := float(h & 1) * 2.0
                draw_rect(Rect2(x + o, y + 1.0 + float((h >> 1) & 1), 6, 6), c)
            CHARGED:
                draw_rect(Rect2(x, y, 8, 8), white if (t + h) % 2 == 0 else c)
            ICE:
                draw_rect(Rect2(x, y, 8, 8), c)
                if (h & 7) == 0:
                    draw_rect(Rect2(x + 2, y + 2, 2, 2), Color(1, 1, 1, 0.8))
            ASH, DRY_BLOOD:
                c.a *= minf(1.0, float(life[i]) / 8.0)
                draw_rect(Rect2(x, y, 8, 8), c)
            _:
                # Liquids: deep cells are full squares, thin edge cells ragged 4 px pixels.
                if int(amt[i]) >= 24:
                    draw_rect(Rect2(x, y, 8, 8), c)
                else:
                    var skip := h & 3
                    for q in 4:
                        if q != skip:
                            draw_rect(Rect2(x + float(q & 1) * 4.0, y + float(q >> 1) * 4.0, 4, 4), c)
                if m == WATER and (h & 15) == 0:
                    draw_rect(Rect2(x + 4, y + 2, 2, 2), Color(1, 1, 1, 0.45))
