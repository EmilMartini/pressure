class_name Materials
extends Node2D
## The floor's material layer, Noita style but top-down: elements land on the floor as
## materials in a grid of 6 px cells and keep interacting there. Oil pools, creeps and burns
## with a bright flame front that leaves cooling embers and permanent char; water flows and
## sloshes, boils into steam on fire and carries a shock through the whole pool (and through
## ice); ice creeps through water and melts by fire; poison gas drifts and contaminates water
## (TOXIC, read by bodies as POISON); acid eats oil and ice and is diluted by water; blood
## cauterises on fire and dries. Big liquid stamps surge outward in ragged tendrils. Bodies
## read `material_at()` a few times a second (Enemy, Player). Fx particles land into the
## grid through `drop()` and `heat_at()`; the grid throws particles back through Fx.
##
## BUDGET (single-threaded web build, target ~100 fps with 8 clouds, 3 fires, 2 puddles):
##   - The grid is a handful of PackedByteArrays (mat, amt, life, flag, char): a 1120x720
##     room is 187x120 = 22,440 cells, ~110 KB. No per-cell Dictionaries or Objects.
##   - The simulation steps STEPS_PER_SEC (12) times a second, never per frame, and visits
##     only cells in the active queue (burning, flowing, drifting, dissolving, charged,
##     cooling), at most STEP_CAP (2500) per step; the rest carry over (FIFO). Cost is linear
##     in active cells; the 6 px grid only makes the draw lists longer, not the step.
##     Typical load: 3 oil fires of ~40 cells + 2 flowing puddles of ~80 cells + gas = 300-500
##     cell visits a step, ~4-6k a second, each a few array reads.
##   - Surges: at most MAX_SURGE (256) tendrils live, one cell move each per step.
##   - Settled liquids, ice and blood are not stepped: a 1 Hz sweep over the list of non-empty
##     cells ages them (evaporate, dry, melt) and compacts that list.
##   - Drawing (12 Hz at most, only after a change, fire/charge flicker or a moving glint):
##     the normal layer walks the non-empty list, 1-3 rects per cell (~600-1000 rects for the
##     load above); the additive glow layer walks the same list and draws only hot cells
##     (fire, charge, embers, acid, steam), 1-2 rects each. Char marks never expire and live
##     in their own list on a static layer, redrawn at most twice a second when new char lands.
##   - Fx out: FX_CAP (24) particles per step from all cells together (embers at 1 per 3
##     burning cells, smoke, steam puffs <= 3 a step, sparks, bubbles, glints, motes).
##   - Fx in: Fx caps particle landings at 40 drop()/heat_at() stamps a frame (one cell each).

enum { NONE, OIL, WATER, FIRE, ICE, POISON, ACID, BLOOD, STEAM, CHARGED, ASH, DRY_BLOOD, TOXIC }
const MAT_COUNT := 13

const CELL := 6
const HALF := 3
const STEPS_PER_SEC := 12.0
const STEP_CAP := 2500
const SWEEP_EVERY := 12          # steps between slow sweeps (1 s)
const MAX_LAY_RADIUS := 64.0     # stamps lay new material only this far; conversions reach the full radius
const MAX_CHARGE := 2500         # cells one shock stamp may charge
const ICE_KEEP := 0.88           # share of velocity kept per 60 Hz frame on ice: a real glide
const FX_CAP := 24               # particles the grid may spawn per step
const MAX_SURGE := 256           # live surge tendrils
const SURGE_MIN_R := 28.0        # liquid stamps this big surge outward instead of a clean disc
const MIN_GIVE := 6

# Thresholds and lifetimes. Slow materials count life in seconds (sweep), fast ones in steps.
const WATER_SPREAD := 20
const OIL_SPREAD := 12
const ACID_SPREAD := 20
const WATER_LIFE := 8            # s
const OIL_LIFE := 40             # s
const BLOOD_LIFE := 5            # s, then dries
const DRY_LIFE := 40             # s, dried blood
const ICE_LIFE := 10             # s, then melts to water
const POISON_TICKS := 60
const ACID_TICKS := 48
const STEAM_TICKS := 6
const CHARGE_TICKS := 6          # ~0.5 s
const FIRE_TICKS := 9            # bare-floor fire (forced)
const ASH_TICKS := 10            # cooling embers behind a fire, then char only

const F_ACTIVE := 1
const F_DRAWN := 2
const F_FRONT := 4               # a fire cell lit this step: the bright leading edge
const F_ZAP := 8                 # ice carrying a shock

# 8 directions for surge tendrils, clockwise from +x (y down).
const DX := [1, 1, 0, -1, -1, -1, 0, 1]
const DY := [0, 1, 1, 1, 0, -1, -1, -1]

var mat := PackedByteArray()
var amt := PackedByteArray()
var life := PackedByteArray()
var _flag := PackedByteArray()
var _char := PackedByteArray()     # permanent scorch level 0..3 under everything
var _char_list := PackedInt32Array()
var _char_dirty := false
var _queue := PackedInt32Array()   # active cells, FIFO; _head is the next to step
var _head := 0
var _drawn := PackedInt32Array()   # every cell that may be non-empty
var _sg := PackedInt32Array()      # surge tendrils, stride 5: cell, dir, steps left, mat, amount

var _w := 0
var _h := 0
var _n := 0
var _origin := Vector2.ZERO        # local position of cell (0, 0)
var _acc := 0.0
var _step_n := 0
var _dirty := false
var _flicker := false
var _glinty := false
var _fire_fx := 0
var _fx_left := 0
var _boils := 0
var _fx: Fx = null
## Show only (set by Fx from the run's spectacle, 0.35 .. 1.3): scales the particles the grid
## emits (budget, embers, steam puffs, sparks, bubbles) and the surge tendril count (>= 50%).
## Material amounts and reactions never depend on it.
var emit_scale := 1.0
var _cols := PackedColorArray()
var _fire_cols := PackedColorArray()
var _glow: GlowLayer
var _char_layer: CharLayer


## Additive child: fire, charge, embers, acid and steam cores as soft 2x squares for bloom.
class GlowLayer extends Node2D:
    var mats: Materials
    func _draw() -> void:
        mats._draw_glow(self)


## Static child under the materials: char marks that never expire.
class CharLayer extends Node2D:
    var mats: Materials
    func _draw() -> void:
        mats._draw_char(self)


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
    _char.resize(_n)
    _cols.resize(MAT_COUNT)
    _cols[NONE] = Color(0, 0, 0, 0)
    _cols[OIL] = Color(Element.COLORS[Element.Kind.OIL].darkened(0.45), 0.66)
    _cols[WATER] = Color(Element.COLORS[Element.Kind.WET], 0.42)
    _cols[FIRE] = Color(Element.COLORS[Element.Kind.FIRE], 0.6)
    _cols[ICE] = Color(Element.COLORS[Element.Kind.ICE], 0.45)
    _cols[POISON] = Color(Element.COLORS[Element.Kind.POISON], 0.34)
    _cols[ACID] = Color(Element.COLORS[Element.Kind.ACID], 0.5)
    _cols[BLOOD] = Color(Element.COLORS[Element.Kind.BLOOD], 0.58)
    _cols[STEAM] = Color(0.9, 0.93, 0.96, 0.32)
    _cols[CHARGED] = Color(Element.COLORS[Element.Kind.SHOCK], 0.6)
    _cols[ASH] = Color(0.14, 0.06, 0.04, 0.5)
    _cols[DRY_BLOOD] = Color(Element.COLORS[Element.Kind.BLOOD].darkened(0.68), 0.5)
    _cols[TOXIC] = Color(Element.COLORS[Element.Kind.WET].lerp(Element.COLORS[Element.Kind.POISON], 0.65), 0.5)
    _fire_cols = PackedColorArray([Color(1.0, 0.85, 0.35, 0.62), Color(1.0, 0.48, 0.14, 0.6), Color(0.78, 0.16, 0.06, 0.56)])
    _char_layer = CharLayer.new()
    _char_layer.mats = self
    _char_layer.show_behind_parent = true
    add_child(_char_layer)
    _glow = GlowLayer.new()
    _glow.mats = self
    var add := CanvasItemMaterial.new()
    add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    _glow.material = add
    add_child(_glow)
    clear()


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
    _char.fill(0)
    _char_list = PackedInt32Array()
    _char_dirty = true
    _queue = PackedInt32Array()
    _head = 0
    _drawn = PackedInt32Array()
    _sg = PackedInt32Array()
    _dirty = true


# --- Public API (world coordinates) ------------------------------------------


## Puts an element on the floor as its material. `force` lets Fire burn bare floor.
## Liquid stamps of radius >= SURGE_MIN_R lay a smaller core and surge outward in tendrils.
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
    var surge_m := _liquid_of(kind)
    var surge := surge_m != NONE and r >= SURGE_MIN_R
    if surge:
        lay *= 0.6
    var lay2 := lay * lay
    var ccx := floori(local.x / float(CELL))
    var ccy := floori(local.y / float(CELL))
    var rc := ceili(r / float(CELL))
    var charged := 0
    for cy in range(maxi(0, ccy - rc), mini(_h, ccy + rc + 1)):
        var dy := float(cy * CELL + HALF) - local.y
        for cx in range(maxi(0, ccx - rc), mini(_w, ccx + rc + 1)):
            var dx := float(cx * CELL + HALF) - local.x
            var d2 := dx * dx + dy * dy
            if d2 > r2:
                continue
            var i := cy * _w + cx
            if kind == Element.Kind.SHOCK:
                var mi := int(mat[i])
                if (mi == WATER or (mi == ICE and (_flag[i] & F_ZAP) == 0)) and charged < MAX_CHARGE:
                    charged += _charge_from(i, MAX_CHARGE - charged)
                continue
            # Ragged rim: the outer ring of the laid disc is patchy.
            var lay_here := d2 <= lay2 and (d2 < lay2 * 0.6 or ((i * 2654435761) >> 7) % 3 != 0)
            _stamp_cell(kind, i, a, force, lay_here)
    if surge:
        _surge(surge_m, local, lay, a)
    _dirty = true


## Sets fuel alight (oil, cells beside fire); `force` burns bare floor too.
func ignite(pos: Vector2, radius: float, force: bool = false) -> void:
    stamp(Element.Kind.FIRE, pos, radius, 200, force)


## One cell of an element where a particle landed (Fx). No radius loop, no surge.
func drop(kind: int, pos: Vector2, amount: int, force: bool = false) -> void:
    var i := _index_at(pos)
    if i < 0:
        return
    _stamp_cell(kind, i, clampi(amount, 8, 255), force, true)
    _dirty = true


## A hot particle dying at `pos`: oil there catches. Returns the material that was there.
func heat_at(pos: Vector2) -> int:
    var i := _index_at(pos)
    if i < 0:
        return NONE
    var m := int(mat[i])
    if m == OIL:
        _ignite_cell(i)
    return m


## What a body standing at `pos` feels. Contaminated water reads as POISON.
func material_at(pos: Vector2) -> int:
    var i := _index_at(pos)
    if i < 0:
        return NONE
    var m := int(mat[i])
    return POISON if m == TOXIC else m


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
    return global_position + _origin + Vector2(float((i % _w) * CELL + HALF), float((i / _w) * CELL + HALF))


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


## Empty floor (or cooling embers), free for liquids and gas to cover.
func _open(m: int) -> bool:
    return m == NONE or m == ASH or m == DRY_BLOOD


func _has_fire_nb(i: int) -> bool:
    for d in 4:
        var j := _nb(i, d)
        if j >= 0 and mat[j] == FIRE:
            return true
    return false


## The grid liquid an element lays, for surges; NONE when it does not flow.
func _liquid_of(kind: int) -> int:
    match kind:
        Element.Kind.WET:
            return WATER
        Element.Kind.OIL:
            return OIL
        Element.Kind.ACID:
            return ACID
        Element.Kind.BLOOD:
            return BLOOD
    return NONE


func _life_of(m: int) -> int:
    match m:
        WATER, TOXIC:
            return WATER_LIFE
        OIL:
            return OIL_LIFE
        ACID:
            return ACID_TICKS
        BLOOD:
            return BLOOD_LIFE
    return 8


## Particle budget for this step; false (and nothing spawned) once spent.
func _fx_ok(n: int) -> bool:
    if _fx_left < n or _fx == null or not is_instance_valid(_fx):
        return false
    if n <= 2 and emit_scale < 1.0 and randf() > emit_scale:
        return false   # single embers, sparks, bubbles thin out on a tame run
    _fx_left -= n
    return true


func _ignite_cell(i: int) -> void:
    var was := int(mat[i])
    var fuel := int(amt[i]) if was == OIL else 0
    _put(i, FIRE, 255 if was == OIL else 128, clampi(10 + fuel / 5, 10, 60))
    _flag[i] = _flag[i] | F_FRONT
    _wake(i)
    if was == OIL and randi() % 5 == 0 and _fx_ok(4):
        _fx.flame_tongue(_cell_world(i))


func _char_mark(i: int, level: int) -> void:
    if int(_char[i]) >= level:
        return
    if _char[i] == 0:
        _char_list.append(i)
    _char[i] = level
    _char_dirty = true


func _stamp_cell(kind: int, i: int, a: int, force: bool, lay: bool) -> void:
    var m := int(mat[i])
    match kind:
        Element.Kind.WET:
            if m == WATER or m == TOXIC:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = maxi(int(life[i]), WATER_LIFE)
                _wake(i)
            elif m == FIRE:
                _put(i, STEAM, 160, STEAM_TICKS)
                _wake(i)
            elif m == ACID:
                # Dilutes: the acid thins and fades sooner.
                var left := int(amt[i]) - a / 2
                if left <= 8:
                    _put(i, NONE, 0, 0)
                else:
                    amt[i] = left
                    life[i] = maxi(1, int(life[i]) / 2)
            elif m == POISON:
                _put(i, TOXIC, a, WATER_LIFE)
                _wake(i)
            elif lay and (_open(m) or m == STEAM or m == BLOOD):
                _put(i, WATER, a, WATER_LIFE)
                _wake(i)
        Element.Kind.OIL:
            if m == OIL:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = maxi(int(life[i]), OIL_LIFE)
                _wake(i)
            elif m == FIRE:
                life[i] = mini(255, int(life[i]) + a / 8)
                amt[i] = 255
            elif m == ACID:
                _put(i, NONE, 0, 0)   # acid eats the oil
            elif lay and (_open(m) or m == STEAM or m == POISON):
                _put(i, OIL, a, OIL_LIFE)
                _wake(i)
        Element.Kind.FIRE:
            if m == OIL:
                _ignite_cell(i)
            elif m == FIRE:
                life[i] = maxi(int(life[i]), 12)
            elif m == WATER or m == CHARGED or m == TOXIC:
                if lay:
                    _put(i, STEAM, 160, STEAM_TICKS)
                    _wake(i)
            elif m == ICE:
                _put(i, WATER, 48, 4)
            elif m == BLOOD:
                _put(i, DRY_BLOOD, 255, DRY_LIFE)   # cauterised
            elif lay and _open(m) and (force or _has_fire_nb(i)):
                _put(i, FIRE, 128, FIRE_TICKS + randi() % 6)
                _flag[i] = _flag[i] | F_FRONT
                _wake(i)
        Element.Kind.ICE:
            if m == WATER or m == CHARGED or m == TOXIC:
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
            elif m == WATER:
                _put(i, TOXIC, amt[i], WATER_LIFE)
                _wake(i)
            elif lay and (_open(m) or m == STEAM):
                _put(i, POISON, a, POISON_TICKS)
                _wake(i)
        Element.Kind.ACID:
            if m == ACID:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = ACID_TICKS
            elif m == OIL or m == ICE:
                _put(i, NONE, 0, 0)
            elif m == WATER or m == TOXIC:
                _put(i, ACID, a / 2, ACID_TICKS / 3)   # lands diluted
                _wake(i)
            elif lay and (_open(m) or m == STEAM or m == POISON):
                _put(i, ACID, a, ACID_TICKS)
                _wake(i)
        Element.Kind.BLOOD:
            if m == BLOOD:
                amt[i] = mini(255, int(amt[i]) + a / 2)
                life[i] = BLOOD_LIFE
            elif m == FIRE:
                _put(i, DRY_BLOOD, 255, DRY_LIFE)
            elif lay and (_open(m) or m == STEAM):
                _put(i, BLOOD, a, BLOOD_LIFE)
                _wake(i)


func _zap_cell(i: int) -> void:
    if mat[i] == WATER:
        _put(i, CHARGED, amt[i], CHARGE_TICKS)
    else:
        _flag[i] = _flag[i] | F_ZAP
        _dirty = true
    _wake(i)


## Shock through water: the whole connected pool flashes charged, and the shock runs on
## through ice it touches (ice strobes but stays ice). Returns cells charged.
func _charge_from(i0: int, cap: int) -> int:
    var m0 := int(mat[i0])
    if m0 != WATER and m0 != ICE:
        return 0
    var stack := PackedInt32Array([i0])
    _zap_cell(i0)
    var count := 1
    while stack.size() > 0 and count < cap:
        var i := stack[stack.size() - 1]
        stack.resize(stack.size() - 1)
        for d in 4:
            var j := _nb(i, d)
            if j < 0:
                continue
            var mj := int(mat[j])
            if mj == WATER or (mj == ICE and (_flag[j] & F_ZAP) == 0):
                _zap_cell(j)
                stack.append(j)
                count += 1
                if count % 24 == 0:
                    _spark(j)
    _spark(i0)
    return count


## Big liquid stamps: tendrils flung 2-4 cells outward from the rim over the next steps.
func _surge(m: int, local: Vector2, rad: float, a: int) -> void:
    var base := clampi(int(rad / 2.5), 10, 32)
    var count := maxi(ceili(float(base) * 0.5), roundi(float(base) * emit_scale))
    var a0 := randf() * TAU
    for k in count:
        if _sg.size() >= MAX_SURGE * 5:
            return
        var ang := a0 + TAU * float(k) / float(count) + randf_range(-0.2, 0.2)
        var p := local + Vector2.RIGHT.rotated(ang) * rad * randf_range(0.75, 1.0)
        var cx := floori(p.x / float(CELL))
        var cy := floori(p.y / float(CELL))
        if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
            continue
        var d := posmod(roundi(ang / (TAU / 8.0)), 8)
        _sg.append(cy * _w + cx)
        _sg.append(d)
        _sg.append(2 + randi() % 3)
        _sg.append(m)
        _sg.append(maxi(MIN_GIVE * 2, a * 2 / 3))


func _step_surge() -> void:
    var next := PackedInt32Array()
    var n := _sg.size() / 5
    for k in n:
        var b := k * 5
        var i := _sg[b]
        var d := _sg[b + 1]
        var left := _sg[b + 2]
        var m := _sg[b + 3]
        var a := _sg[b + 4]
        if randi() % 3 == 0:
            d = (d + (1 if randi() % 2 == 0 else 7)) & 7
        var cx := i % _w + int(DX[d])
        var cy := i / _w + int(DY[d])
        if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
            continue
        var j := cy * _w + cx
        if not _surge_into(j, m, a):
            continue
        # A side splash now and then, so the rims fray.
        if randi() % 4 == 0:
            var sd := (d + (2 if randi() % 2 == 0 else 6)) & 7
            var sx := cx + int(DX[sd])
            var sy := cy + int(DY[sd])
            if sx >= 0 and sy >= 0 and sx < _w and sy < _h:
                _surge_into(sy * _w + sx, m, a / 2)
        left -= 1
        a = a * 3 / 4
        if left > 0 and a >= MIN_GIVE:
            next.append(j)
            next.append(d)
            next.append(left)
            next.append(m)
            next.append(a)
    _sg = next


func _surge_into(j: int, m: int, a: int) -> bool:
    var mj := int(mat[j])
    if mj == m:
        amt[j] = mini(255, int(amt[j]) + a / 2)
    elif _open(mj) or mj == STEAM:
        _put(j, m, a, _life_of(m))
    else:
        return false
    _wake(j)
    return true


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
                if not (m == WATER or m == OIL or m == BLOOD or m == ACID or m == POISON or m == STEAM or m == CHARGED or m == TOXIC):
                    continue
                var dv := Vector2(float(cx * CELL + HALF) - local.x, float(cy * CELL + HALF) - local.y)
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
    _fx_left = roundi(FX_CAP * emit_scale) if _fx != null else 0
    _boils = 0
    if not _sg.is_empty():
        _step_surge()
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
                _step_liquid(i, WATER, WATER_SPREAD, 2, true)
            TOXIC:
                _step_liquid(i, TOXIC, WATER_SPREAD, 2, true)
            OIL:
                # Slow but far: moves one step in three, down to a thin film.
                if randi() % 3 == 0:
                    _step_liquid(i, OIL, OIL_SPREAD, 1, false)
                elif int(amt[i]) > OIL_SPREAD:
                    _wake(i)
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
            ASH:
                _step_ash(i)
    if _head >= _queue.size():
        _queue = PackedInt32Array()
        _head = 0
    elif _head > 2048:
        _queue = _queue.slice(_head)
        _head = 0
    if _step_n % SWEEP_EVERY == 0:
        _sweep()
    if _dirty or _flicker or (_glinty and _step_n % 2 == 0):
        _dirty = false
        queue_redraw()
        _glow.queue_redraw()
    if _char_dirty and _step_n % 6 == 0:
        _char_dirty = false
        _char_layer.queue_redraw()


func _step_fire(i: int) -> void:
    _flicker = true
    if (_flag[i] & F_FRONT) != 0:
        _flag[i] = _flag[i] & ~F_FRONT   # the front moves on to the cells it lit
    var doused := false
    for d in 4:
        var j := _nb(i, d)
        if j < 0:
            continue
        var m := int(mat[j])
        if m == OIL:
            _ignite_cell(j)   # one cell per step along the oil
        elif m == WATER or m == CHARGED or m == TOXIC:
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
        elif m == BLOOD:
            _put(j, DRY_BLOOD, 255, DRY_LIFE)   # cauterised with a hiss
            if _fx_ok(2):
                _fx.steam(_cell_world(j), 2)
    if doused:
        _put(i, STEAM, 160, STEAM_TICKS)
        _wake(i)
        var puff := maxi(3, roundi(float(8 + randi() % 5) * emit_scale))
        if _boils < 3 and _fx_ok(puff):
            _boils += 1
            _fx.steam(_cell_world(i), puff)
        return
    var l := int(life[i]) - 1
    if l <= 0:
        # Burnt out: cooling embers for a moment, a char mark for good.
        var oil := int(amt[i]) >= 200
        if oil:
            _char_mark(i, 2 + randi() % 2)
        elif randi() % 2 == 0:
            _char_mark(i, 1)
        _put(i, ASH, 255 if oil else 120, ASH_TICKS + randi() % 6)
        _wake(i)
        return
    life[i] = l
    _wake(i)
    _fire_fx += 1
    if _fire_fx % 3 == 0 and _fx_ok(1):
        var p := _cell_world(i)
        _fx.ember(p + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)))
        if _fire_fx % 12 == 0 and _fx_ok(1):
            _fx.smoke(p, 1, 4.0)


## Flat spreading: hand half the depth to an open neighbour (water jumps a second cell when
## the flow is strong), or even out with a shallower neighbour of the same liquid, until the
## cell is thin. `slosh` also nudges a random amount back and forth while it moves.
## Sleeps when nothing moved.
func _step_liquid(i: int, m: int, min_amt: int, tries: int, slosh: bool) -> void:
    var a := int(amt[i])
    if a <= min_amt:
        return
    var start := randi() & 3
    var moved := 0
    var l := int(life[i])
    for k in 4:
        var dir := (start + k) & 3
        var j := _nb(i, dir)
        if j < 0:
            continue
        var mj := int(mat[j])
        if _open(mj) or mj == STEAM:
            var give := a / 2
            if give < MIN_GIVE:
                break
            a -= give
            var j2 := _nb(j, dir) if slosh and give >= 40 else -1
            if j2 >= 0 and _open(int(mat[j2])):
                _put(j2, m, give / 2, l)
                _wake(j2)
                give -= give / 2
            _put(j, m, give, l)
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
    if slosh and moved > 0 and randi() % 3 == 0:
        var s := _nb(i, randi() & 3)
        if s >= 0 and int(mat[s]) == m:
            var dv := randi_range(-6, 6)
            amt[s] = clampi(int(amt[s]) + dv, 8, 255)
            a = clampi(a - dv, 8, 255)
    amt[i] = a
    if moved > 0:
        _dirty = true
        if a > min_amt:
            _wake(i)


## Acid fizzes, eats oil and ice beside it and is diluted (fades faster) by water.
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
            if _fx_ok(1):
                _fx.bubble(_cell_world(j))
            if m == OIL and randi() % 2 == 0 and _fx_ok(1):
                _fx.smoke(_cell_world(j), 1, 3.0)
        elif m == WATER or m == TOXIC:
            l -= 4
            var wl := int(amt[j]) - 12
            if wl <= 8:
                _put(j, NONE, 0, 0)
            else:
                amt[j] = wl
            if randi() % 3 == 0 and _fx_ok(1):
                _fx.bubble(_cell_world(j))
    if l <= 0 or a <= 8:
        _put(i, NONE, 0, 0)
        return
    life[i] = l
    amt[i] = a
    if randi() % 6 == 0 and _fx_ok(1):
        _fx.bubble(_cell_world(i))
    _step_liquid(i, ACID, ACID_SPREAD, 2, false)
    if mat[i] == ACID:
        _wake(i)


## Gas drifts, sheds motes, and contaminates water it touches (TOXIC).
func _step_poison(i: int) -> void:
    var l := int(life[i]) - 1
    if l <= 0:
        _put(i, NONE, 0, 0)
        return
    life[i] = l
    _dirty = true   # gas drifts every step
    if randi() % 10 == 0 and _fx_ok(1):
        _fx.mote(Element.Kind.POISON, _cell_world(i))
    var j := _nb(i, randi() & 3)
    if j >= 0:
        var mj := int(mat[j])
        if mj == WATER:
            _put(j, TOXIC, amt[j], WATER_LIFE)
            _wake(j)
            l = maxi(1, l - 6)
            life[i] = l
        elif mj == NONE and randi() % 3 == 0:
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
    if randi() % 6 == 0 and _fx_ok(1):
        _fx.steam(_cell_world(i), 1)
    if randi() % 2 == 0 and i >= _w and mat[i - _w] == NONE:
        _put(i - _w, STEAM, amt[i], l)
        _put(i, NONE, 0, 0)
        _wake(i - _w)
        return
    _wake(i)


## Charged water strobes and sparks along the pool's edge.
func _step_charged(i: int) -> void:
    _flicker = true
    var l := int(life[i]) - 1
    if l <= 0:
        _put(i, WATER, amt[i], 4)
        return
    life[i] = l
    var j := _nb(i, randi() & 3)
    if (j < 0 or (mat[j] != CHARGED and mat[j] != WATER)) and randi() % 3 == 0 and _fx_ok(2):
        _spark(i)
    _wake(i)


## Fresh ice creeps through the water it touches with white glints, then sleeps. Zapped
## ice strobes and sparks for a few steps.
func _step_ice(i: int) -> void:
    var left := false
    for d in 4:
        var j := _nb(i, d)
        if j < 0:
            continue
        var m := int(mat[j])
        if m == WATER or m == CHARGED or m == TOXIC:
            if randi() % 2 == 0:
                _put(j, ICE, 200, ICE_LIFE)
                _wake(j)
                if randi() % 3 == 0 and _fx_ok(1):
                    _fx.glint(_cell_world(j))
            else:
                left = true
    if (_flag[i] & F_ZAP) != 0:
        _flicker = true
        if randi() % 4 == 0 and _fx_ok(2):
            _spark(i)
        if randi() % 3 == 0:
            _flag[i] = _flag[i] & ~F_ZAP
            _dirty = true
        else:
            left = true
    if left:
        _wake(i)


## Cooling embers behind a fire front: a dull glow and a wisp of smoke, then bare char.
func _step_ash(i: int) -> void:
    var l := int(life[i]) - 1
    if l <= 0:
        _put(i, NONE, 0, 0)
        return
    life[i] = l
    _flicker = true
    if randi() % 10 == 0 and _fx_ok(1):
        _fx.smoke(_cell_world(i), 1, 3.0)
    _wake(i)


## 1 Hz: age the slow materials (evaporate, dry, melt), drop empty cells from the draw
## list, and let obstacles at the doors feel what is on the floor beside them.
func _sweep() -> void:
    var keep := PackedInt32Array()
    for i: int in _drawn:
        var m := int(mat[i])
        if m == NONE:
            _flag[i] = _flag[i] & ~F_DRAWN
            continue
        if m == WATER or m == OIL or m == BLOOD or m == ICE or m == DRY_BLOOD or m == TOXIC:
            var l := int(life[i]) - 1
            if l > 0:
                life[i] = l
                if l < 8 and m == DRY_BLOOD:
                    _dirty = true
                if m == TOXIC and randi() % 8 == 0 and _fx_ok(1):
                    _fx.mote(Element.Kind.POISON, _cell_world(i))
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
                    WATER, CHARGED, TOXIC:
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


func _find_fx() -> Fx:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        var f: Variant = scene.get("fx")
        if f != null and is_instance_valid(f):
            return f as Fx
    return null


func _spark(i: int) -> void:
    if _fx != null and is_instance_valid(_fx):
        _fx.pixels(Element.Kind.SHOCK, _cell_world(i), 2, 60.0, 4.0)


# --- Drawing -----------------------------------------------------------------


func _is_liquid(m: int) -> bool:
    return m == WATER or m == OIL or m == ACID or m == BLOOD or m == TOXIC


func _draw() -> void:
    var t := _step_n
    var white := Color(1, 1, 1, 0.7)
    var glints := 0
    var cs := float(CELL)
    var q := float(HALF)
    for i: int in _drawn:
        var m := int(mat[i])
        if m == NONE:
            continue
        var cx := i % _w
        var cy := i / _w
        var x := _origin.x + float(cx * CELL)
        var y := _origin.y + float(cy * CELL)
        var h := (i * 73856093) & 0xFFFF
        var c: Color = _cols[m]
        match m:
            FIRE:
                if (_flag[i] & F_FRONT) != 0:
                    # The leading edge: hot white-yellow with a white core.
                    draw_rect(Rect2(x, y, cs, cs), Color(1.0, 0.93, 0.62, 0.75))
                    draw_rect(Rect2(x + 2.0, y + 2.0, 2.0, 2.0), Color(1, 1, 1, 0.95))
                else:
                    var k := (h + t * 7 + randi()) % 3
                    draw_rect(Rect2(x, y, cs, cs), _fire_cols[k])
                    if k == 0 and (h & 1) == 0:
                        draw_rect(Rect2(x + 2.0, y + 2.0, 2.0, 2.0), Color(1.0, 0.95, 0.6, 0.65))
            ASH:
                var heat := clampf(float(life[i]) / float(ASH_TICKS), 0.0, 1.0)
                draw_rect(Rect2(x, y, cs, cs), c)
                if (h + t) % 3 != 0:
                    draw_rect(Rect2(x + float(h % 4), y + float((h >> 2) % 4), 2.0, 2.0), Color(1.0, 0.42, 0.12, 0.55 * heat))
            POISON, STEAM:
                # Soft drifting squares with a lighter centre.
                var fade := minf(1.0, float(life[i]) / 12.0) if m == POISON else minf(1.0, float(life[i]) / 3.0)
                c.a *= fade * clampf(float(amt[i]) / 64.0, 0.5, 1.0)
                var ox := float(((h >> 3) + t / 3) % 3) - 1.0
                var oy := float(((h >> 5) + t / 4) % 3) - 1.0
                draw_rect(Rect2(x + ox, y + oy, cs, cs), c)
                draw_rect(Rect2(x + ox + 2.0, y + oy + 2.0, 2.0, 2.0), Color(c.lightened(0.45), c.a * 1.2))
            CHARGED:
                draw_rect(Rect2(x, y, cs, cs), white if (t + h) % 3 == 0 else c)
            ICE:
                if (_flag[i] & F_ZAP) != 0:
                    draw_rect(Rect2(x, y, cs, cs), Color(1.0, 1.0, 0.8, 0.75) if (t + h) % 2 == 0 else c)
                else:
                    draw_rect(Rect2(x, y, cs, cs), c)
                    if (h & 7) == 0:
                        draw_rect(Rect2(x + 2.0, y + 1.0, 2.0, 2.0), Color(1, 1, 1, 0.8))
            DRY_BLOOD:
                c.a *= minf(1.0, float(life[i]) / 8.0)
                _draw_ragged(x, y, h, c, int(amt[i]) < 200 or (h & 3) == 0)
            _:
                # Liquids: inner cells full, edge and thin cells drop quadrants by a noise mask.
                var edge := int(amt[i]) < 24
                if not edge:
                    for d in 4:
                        var j := _nb(i, d)
                        if j < 0 or not _is_liquid(int(mat[j])):
                            edge = true
                            break
                if m == BLOOD and int(amt[i]) < 40:
                    c = c.darkened(0.2)   # thin blood darkens as it soaks in
                _draw_ragged(x, y, h, c, edge)
                match m:
                    WATER, TOXIC:
                        glints += 1
                        if (cx + cy * 2 + t) % 19 == 0:
                            draw_rect(Rect2(x + 1.0 + float(h & 1) * 2.0, y + 1.0, 2.0, 1.0), Color(1, 1, 1, 0.6))
                    OIL:
                        glints += 1
                        if (cx * 3 + cy * 5 + t / 2) % 23 == 0:
                            draw_rect(Rect2(x + 1.0 + float(h & 3), y + 1.0, 1.0, 1.0), Color(0.8, 0.7, 0.6, 0.7))
                        elif (h & 31) == 0:
                            draw_rect(Rect2(x + q, y + q, 1.0, 1.0), Color(0.55, 0.47, 0.42, 0.6))
                    ACID:
                        if (h + t) % 11 == 0:
                            draw_rect(Rect2(x + float(h % 5), y + float((h >> 3) % 5), 1.0, 1.0), Color(0.95, 1.0, 0.7, 0.8))
    _glinty = glints > 0


## A cell as four 3 px quadrants with one or two missing (edge) or a full square.
func _draw_ragged(x: float, y: float, h: int, c: Color, edge: bool) -> void:
    if not edge:
        draw_rect(Rect2(x, y, float(CELL), float(CELL)), c)
        return
    var skip := h & 3
    var skip2 := (h >> 4) & 3 if (h & 0x300) == 0 else -1
    for k in 4:
        if k != skip and k != skip2:
            draw_rect(Rect2(x + float(k & 1) * float(HALF), y + float(k >> 1) * float(HALF), float(HALF), float(HALF)), c)


## The additive layer: hot cells as soft double-size squares so the bloom catches them.
func _draw_glow(cv: CanvasItem) -> void:
    var t := _step_n
    var cs := float(CELL)
    for i: int in _drawn:
        var m := int(mat[i])
        if m == NONE or m == WATER or m == OIL or m == BLOOD or m == DRY_BLOOD or m == POISON or m == TOXIC:
            continue
        var x := _origin.x + float((i % _w) * CELL)
        var y := _origin.y + float((i / _w) * CELL)
        var h := (i * 73856093) & 0xFFFF
        match m:
            FIRE:
                if (_flag[i] & F_FRONT) != 0:
                    cv.draw_rect(Rect2(x - 3.0, y - 3.0, 12.0, 12.0), Color(1.0, 0.72, 0.32, 0.24))
                    cv.draw_rect(Rect2(x + 2.0, y + 2.0, 2.0, 2.0), Color(1.0, 1.0, 0.9, 1.0))
                else:
                    var a := 0.1 + 0.05 * float((h + t * 5) % 3)
                    cv.draw_rect(Rect2(x - 3.0, y - 3.0, 12.0, 12.0), Color(1.0, 0.42, 0.1, a))
            CHARGED:
                if (t + h) % 2 == 0:
                    cv.draw_rect(Rect2(x - 3.0, y - 3.0, 12.0, 12.0), Color(0.9, 0.9, 0.4, 0.15))
            ASH:
                var heat := clampf(float(life[i]) / float(ASH_TICKS), 0.0, 1.0)
                cv.draw_rect(Rect2(x, y, cs, cs), Color(0.6, 0.15, 0.03, 0.18 * heat))
            STEAM:
                if int(amt[i]) > 100:
                    cv.draw_rect(Rect2(x, y, cs, cs), Color(0.45, 0.47, 0.5, 0.07))
            ACID:
                if (h & 3) == 0:
                    cv.draw_rect(Rect2(x - 3.0, y - 3.0, 12.0, 12.0), Color(0.4, 0.62, 0.1, 0.08))
            ICE:
                if (_flag[i] & F_ZAP) != 0:
                    cv.draw_rect(Rect2(x - 3.0, y - 3.0, 12.0, 12.0), Color(0.8, 0.9, 1.0, 0.16))


## Char marks: near-black dots, a darker patch where oil burned hard. Never expire.
func _draw_char(cv: CanvasItem) -> void:
    for i: int in _char_list:
        var lv := int(_char[i])
        if lv == 0:
            continue
        var x := _origin.x + float((i % _w) * CELL)
        var y := _origin.y + float((i / _w) * CELL)
        var h := (i * 73856093) & 0xFFFF
        var col := Color(0.03, 0.025, 0.02, 0.3 + 0.12 * float(lv))
        if lv >= 3:
            cv.draw_rect(Rect2(x, y, float(CELL), float(CELL)), Color(0.03, 0.025, 0.02, 0.26))
        cv.draw_rect(Rect2(x + float(h % 4), y + float((h >> 2) % 4), 2.0, 2.0), col)
        if lv >= 2:
            cv.draw_rect(Rect2(x + float((h >> 4) % 5), y + float((h >> 7) % 5), 1.0, 1.0), col)
