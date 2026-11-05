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
##   - Drawing is on the GPU (see Drawing): one RGBA8 texel per cell in a data texture and two
##     shaded quads over the room (normal, additive glow). The CPU rewrites only the texels of
##     cells that changed (a dirty list, flushed once per step) and sets two uniforms when the
##     picture should move on (flicker, glints, drift): no per-cell draw calls, so settled
##     pools, dry blood and char marks (which never expire) cost nothing per frame.
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
const F_STILL := 16              # laid by a room layout and drawn by the room until it changes

# 8 directions for surge tendrils, clockwise from +x (y down).
const DX := [1, 1, 0, -1, -1, -1, 0, 1]
const DY := [0, 1, 1, 1, 0, -1, -1, -1]

var mat := PackedByteArray()
var amt := PackedByteArray()
var life := PackedByteArray()
var _flag := PackedByteArray()
var _char := PackedByteArray()     # permanent scorch level 0..3 under everything
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
var _tdata := PackedByteArray()    # the data texture's bytes, 4 per cell (see Drawing)
var _tmark := PackedByteArray()    # 1 while a cell waits in _tlist
var _tlist := PackedInt32Array()   # cells whose texel must be rewritten
var _timg: Image
var _ttex: ImageTexture
var _draw_rng := RandomNumberGenerator.new()


## Additive child: fire, charge, embers, acid and steam cores as soft 2x squares for bloom
## (one quad, see Drawing).
class GlowLayer extends Node2D:
    var mats: Materials
    func _draw() -> void:
        draw_rect(mats._quad_rect(), Color.WHITE)


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
    _tdata.resize(_n * 4)
    _tmark.resize(_n)
    _timg = Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, _tdata)
    _ttex = ImageTexture.create_from_image(_timg)
    material = _make_draw_material(false)
    _glow = GlowLayer.new()
    _glow.mats = self
    _glow.material = _make_draw_material(true)
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
    _tdata.fill(0)
    _tmark.fill(0)
    _tlist = PackedInt32Array()
    _timg.set_data(_w, _h, false, Image.FORMAT_RGBA8, _tdata)
    _ttex.update(_timg)
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


## Lays still terrain (a room layout's pools, slicks, ice sheets, grass) over every cell
## whose centre is inside a world rect, without waking it, so it sits where it was put
## until something touches it. Water tops up water and poisoned water and fills bare
## floor; oil and ice only cover bare floor. `life_s` (seconds, <= 255) outlasts the
## usual evaporation; -1 keeps the material's own lifetime. Fire, ice, steam and charged
## cells are left alone, so a pool can still be frozen, boiled or shocked.
func fill_rect(kind: int, world_rect: Rect2, amount: int, life_s: int = -1) -> void:
    var m := NONE
    match kind:
        Element.Kind.WET:
            m = WATER
        Element.Kind.OIL:
            m = OIL
        Element.Kind.ICE:
            m = ICE
        _:
            return
    var a := clampi(amount, 8, 255)
    var l := ICE_LIFE if m == ICE else _life_of(m)
    if life_s > 0:
        l = clampi(life_s, 1, 255)
    var lr := Rect2(world_rect.position - global_position - _origin, world_rect.size)
    var x0 := maxi(0, ceili(lr.position.x / float(CELL) - 0.5))
    var y0 := maxi(0, ceili(lr.position.y / float(CELL) - 0.5))
    var x1 := mini(_w - 1, floori(lr.end.x / float(CELL) - 0.5))
    var y1 := mini(_h - 1, floori(lr.end.y / float(CELL) - 0.5))
    for cy in range(y0, y1 + 1):
        for cx in range(x0, x1 + 1):
            var i := cy * _w + cx
            var c := int(mat[i])
            if m == WATER and (c == WATER or c == TOXIC):
                amt[i] = maxi(int(amt[i]), a)
                life[i] = maxi(int(life[i]), l)
                _touch(i)
            elif _open(c):
                _put(i, m, a, l)
    _dirty = true


## Grid indices of every cell whose centre is inside a world rect (see lay_still_water).
func indices_in(world_rect: Rect2) -> PackedInt32Array:
    var out := PackedInt32Array()
    var lr := Rect2(world_rect.position - global_position - _origin, world_rect.size)
    var x0 := maxi(0, ceili(lr.position.x / float(CELL) - 0.5))
    var y0 := maxi(0, ceili(lr.position.y / float(CELL) - 0.5))
    var x1 := mini(_w - 1, floori(lr.end.x / float(CELL) - 0.5))
    var y1 := mini(_h - 1, floori(lr.end.y / float(CELL) - 0.5))
    for cy in range(y0, y1 + 1):
        for cx in range(x0, x1 + 1):
            out.append(cy * _w + cx)
    return out


## A room layout's terrain (deep pools, an ice sheet, the oil film under dry grass): laid
## straight into the grid without entering the draw list or the slow sweep. The room draws
## it (thousands of still cells would swamp the budget above). It is real material to
## everything else: bodies wade, slip and soak in it, shock charges a whole pool, ice
## freezes it, fire boils water, melts ice and runs along the oil. A cell that changes goes
## through _put and is drawn and ages as usual from then on. Pools are topped back up by
## calling this again over time, a slice of `idx` at a time.
func lay_still(kind: int, idx: PackedInt32Array, from: int, count: int, amount: int) -> void:
    var m := WATER if kind == Element.Kind.WET else (OIL if kind == Element.Kind.OIL else ICE)
    var a := clampi(amount, 8, 255)
    var end := mini(idx.size(), from + count)
    for k in range(from, end):
        var i := idx[k]
        var c := int(mat[i])
        if c == m:
            if int(amt[i]) < a:
                amt[i] = a
            life[i] = 255
            if (_flag[i] & F_STILL) == 0 and (_flag[i] & F_DRAWN) != 0:
                _flag[i] = _flag[i] | F_STILL
                _touch(i)
                _dirty = true
        elif c == TOXIC and m == WATER:
            life[i] = 255
        elif _open(c):
            mat[i] = m
            amt[i] = a
            life[i] = 255
            _flag[i] = _flag[i] | F_STILL
            _touch(i)
            if (_flag[i] & F_DRAWN) != 0:
                _dirty = true   # it was drawn as something else a moment ago


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
    _flag[i] = _flag[i] & ~F_STILL   # changed: the grid draws it from now on
    if m != NONE and (_flag[i] & F_DRAWN) == 0:
        _flag[i] = _flag[i] | F_DRAWN
        _drawn.append(i)
    if m == WATER or m == TOXIC or m == OIL:
        _glinty = true
    _touch(i)
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
    _char[i] = level
    _touch(i)


func _stamp_cell(kind: int, i: int, a: int, force: bool, lay: bool) -> void:
    var m := int(mat[i])
    _touch(i)
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
        _flag[i] = (_flag[i] | F_ZAP) & ~F_STILL
        _touch(i)
        if (_flag[i] & F_DRAWN) == 0:
            _flag[i] = _flag[i] | F_DRAWN
            _drawn.append(i)   # still ice joins the draw list to strobe
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
        _touch(j)
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
        _redraw_uniforms()
    if not _tlist.is_empty():
        _flush_texels()


func _step_fire(i: int) -> void:
    _flicker = true
    if (_flag[i] & F_FRONT) != 0:
        _flag[i] = _flag[i] & ~F_FRONT   # the front moves on to the cells it lit
        _touch(i)
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
                _touch(j)
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
                _touch(j)
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
            _touch(s)
            a = clampi(a - dv, 8, 255)
    amt[i] = a
    if moved > 0:
        _touch(i)
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
                _touch(j)
            if randi() % 3 == 0 and _fx_ok(1):
                _fx.bubble(_cell_world(j))
    if l <= 0 or a <= 8:
        _put(i, NONE, 0, 0)
        return
    life[i] = l
    amt[i] = a
    _touch(i)
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
    _touch(i)
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
    _touch(i)
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
            _touch(i)
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
    _touch(i)
    _flicker = true
    if randi() % 10 == 0 and _fx_ok(1):
        _fx.smoke(_cell_world(i), 1, 3.0)
    _wake(i)


## 1 Hz: age the slow materials (evaporate, dry, melt), drop empty cells from the draw
## list, and let obstacles at the doors feel what is on the floor beside them.
func _sweep() -> void:
    var keep := PackedInt32Array()
    var glinty := false
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
                    _touch(i)   # fading out
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
        var km := int(mat[i])
        if (km == WATER or km == TOXIC or km == OIL) and (_flag[i] & F_STILL) == 0:
            glinty = true
        keep.append(i)
    _drawn = keep
    _glinty = glinty
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
#
# The grid is drawn by the GPU: one RGBA8 texel per cell (r = material | 16 fire front |
# 32 zapped ice | 64 still, g = amount, b = life, a = char level) in a data texture, and two
# quads over the room: the normal layer (this node, premultiplied blend) and the additive
# glow layer (GlowLayer). Their fragment shaders read the texel under each world pixel (and
# the neighbours that reach into it) and paint exactly what the old per-cell rects did: char
# marks under everything, fire flicker and the white-hot front, ragged liquid edges, water
# glints, oil sheen, acid sparkles, the charged strobe, drifting gas, dry blood fading out;
# the glow layer adds the 12 px soft squares of fire, charge, acid and zapped ice and the
# cores of embers and steam. The CPU only rewrites the texels of cells that changed
# (`_touch` -> `_flush_texels`, once per step) and sets two uniforms when the old code would
# have redrawn: `t` (the step, for flicker and glints) and `seed` (fire flicker).

const MAT_SHADER := """
shader_type canvas_item;
render_mode {BLEND};
uniform sampler2D data : filter_nearest;
uniform int t = 0;
uniform float seed = 0.0;
uniform vec2 origin = vec2(0.0);
uniform ivec2 grid = ivec2(1, 1);
const int CELL = {CELL};
const vec4 COLS[{N}] = {COLS};
const vec4 FIRE_COLS[3] = {FIRE_COLS};
varying vec2 lp;

void vertex() {
    lp = VERTEX;
}

bool inside(ivec2 c) {
    return c.x >= 0 && c.y >= 0 && c.x < grid.x && c.y < grid.y;
}

// x: material | 16 front | 32 zap | 64 still, y: amount, z: life, w: char level.
ivec4 cell_at(ivec2 c) {
    if (!inside(c)) {
        return ivec4(0);
    }
    return ivec4(texelFetch(data, c, 0) * 255.0 + 0.5);
}

int hash16(ivec2 c) {
    return int((uint(c.y * grid.x + c.x) * 73856093u) & 65535u);
}

bool in_rect(ivec2 p, int x, int y, int w, int h) {
    return p.x >= x && p.y >= y && p.x < x + w && p.y < y + h;
}

vec4 over(vec4 acc, vec4 c) {
    return vec4(c.rgb * c.a + acc.rgb * (1.0 - c.a), c.a + acc.a * (1.0 - c.a));
}

bool liquid(int m) {
    return m == {WATER} || m == {OIL} || m == {ACID} || m == {BLOOD} || m == {TOXIC};
}

// A gas cell's drifting square and its lighter centre, at `q` = pixel relative to that cell.
vec4 gas(vec4 acc, ivec2 c, ivec4 d, ivec2 q) {
    int m = d.x & 15;
    int h = hash16(c);
    ivec2 r = q - ivec2(((h >> 3) + t / 3) % 3 - 1, ((h >> 5) + t / 4) % 3 - 1);
    if (in_rect(r, 0, 0, CELL, CELL)) {
        vec4 col = COLS[m];
        float fade = m == {POISON} ? min(1.0, float(d.z) / 12.0) : min(1.0, float(d.z) / 3.0);
        col.a *= fade * clamp(float(d.y) / 64.0, 0.5, 1.0);
        acc = over(acc, col);
        if (in_rect(r, 2, 2, 2, 2)) {
            acc = over(acc, vec4(col.rgb + (1.0 - col.rgb) * 0.45, col.a * 1.2));
        }
    }
    return acc;
}

// A cell as four 3 px quadrants with one or two missing (edge) or a full square.
vec4 ragged(vec4 acc, ivec2 sp, int h, vec4 c, bool edge) {
    if (!edge) {
        return over(acc, c);
    }
    int q = (sp.x >= {HALF} ? 1 : 0) + (sp.y >= {HALF} ? 2 : 0);
    int skip2 = (h & 768) == 0 ? (h >> 4) & 3 : -1;
    if (q != (h & 3) && q != skip2) {
        acc = over(acc, c);
    }
    return acc;
}

void fragment() {
    ivec2 px = ivec2(floor(lp - origin));
    ivec2 c = ivec2(floor(vec2(px) / float(CELL)));
    ivec2 sp = px - c * CELL;
    ivec4 d = cell_at(c);
#ifdef GLOW
    // Additive: soft 12 px squares reach 3 px into the neighbours on this pixel's side.
    vec3 sum = vec3(0.0);
    ivec2 side = ivec2(sp.x < {HALF} ? -1 : 1, sp.y < {HALF} ? -1 : 1);
    for (int k = 0; k < 4; k++) {
        ivec2 n = c + ivec2((k & 1) * side.x, (k >> 1) * side.y);
        ivec4 nd = k == 0 ? d : cell_at(n);
        int m = nd.x & 15;
        if (m == 0 || (nd.x & 64) != 0) {
            continue;
        }
        ivec2 q = px - n * CELL;
        bool own = k == 0;
        int h = hash16(n);
        if (m == {FIRE}) {
            if ((nd.x & 16) != 0) {
                sum += vec3(1.0, 0.72, 0.32) * 0.24;
                if (own && in_rect(q, 2, 2, 2, 2)) {
                    sum += vec3(1.0, 1.0, 0.9);
                }
            } else {
                sum += vec3(1.0, 0.42, 0.1) * (0.1 + 0.05 * float((h + t * 5) % 3));
            }
        } else if (m == {CHARGED}) {
            if ((t + h) % 2 == 0) {
                sum += vec3(0.9, 0.9, 0.4) * 0.15;
            }
        } else if (m == {ASH}) {
            if (own) {
                sum += vec3(0.6, 0.15, 0.03) * 0.18 * clamp(float(nd.z) / {ASH_TICKS}.0, 0.0, 1.0);
            }
        } else if (m == {STEAM}) {
            if (own && nd.y > 100) {
                sum += vec3(0.45, 0.47, 0.5) * 0.07;
            }
        } else if (m == {ACID}) {
            if ((h & 3) == 0) {
                sum += vec3(0.4, 0.62, 0.1) * 0.08;
            }
        } else if (m == {ICE}) {
            if ((nd.x & 32) != 0) {
                sum += vec3(0.8, 0.9, 1.0) * 0.16;
            }
        }
    }
    if (sum.r + sum.g + sum.b <= 0.0) {
        discard;
    }
    COLOR = vec4(sum, 1.0);
#else
    vec4 acc = vec4(0.0);
    int h = hash16(c);
    // Char marks: near-black dots, a darker patch where oil burned hard. Under everything.
    if (d.w > 0) {
        vec4 cc = vec4(0.03, 0.025, 0.02, 0.3 + 0.12 * float(d.w));
        if (d.w >= 3) {
            acc = over(acc, vec4(0.03, 0.025, 0.02, 0.26));
        }
        if (in_rect(sp, h % 4, (h >> 2) % 4, 2, 2)) {
            acc = over(acc, cc);
        }
        if (d.w >= 2 && in_rect(sp, (h >> 4) % 5, (h >> 7) % 5, 1, 1)) {
            acc = over(acc, cc);
        }
    }
    int m = d.x & 15;
    if (m != 0 && (d.x & 64) == 0) {
        vec4 col = COLS[m];
        if (m == {FIRE}) {
            if ((d.x & 16) != 0) {
                // The leading edge: hot white-yellow with a white core.
                acc = over(acc, vec4(1.0, 0.93, 0.62, 0.75));
                if (in_rect(sp, 2, 2, 2, 2)) {
                    acc = over(acc, vec4(1.0, 1.0, 1.0, 0.95));
                }
            } else {
                float r = fract(sin(dot(vec2(c) + vec2(seed, seed * 0.37), vec2(12.9898, 78.233))) * 43758.5453);
                int k = min(2, int(r * 3.0));
                acc = over(acc, FIRE_COLS[k]);
                if (k == 0 && (h & 1) == 0 && in_rect(sp, 2, 2, 2, 2)) {
                    acc = over(acc, vec4(1.0, 0.95, 0.6, 0.65));
                }
            }
        } else if (m == {ASH}) {
            acc = over(acc, col);
            if ((h + t) % 3 != 0 && in_rect(sp, h % 4, (h >> 2) % 4, 2, 2)) {
                acc = over(acc, vec4(1.0, 0.42, 0.12, 0.55 * clamp(float(d.z) / {ASH_TICKS}.0, 0.0, 1.0)));
            }
        } else if (m == {POISON} || m == {STEAM}) {
            acc = gas(acc, c, d, sp);
        } else if (m == {CHARGED}) {
            acc = over(acc, (t + h) % 3 == 0 ? vec4(1.0, 1.0, 1.0, 0.7) : col);
        } else if (m == {ICE}) {
            if ((d.x & 32) != 0) {
                acc = over(acc, (t + h) % 2 == 0 ? vec4(1.0, 1.0, 0.8, 0.75) : col);
            } else {
                acc = over(acc, col);
                if ((h & 7) == 0 && in_rect(sp, 2, 1, 2, 2)) {
                    acc = over(acc, vec4(1.0, 1.0, 1.0, 0.8));
                }
            }
        } else if (m == {DRY_BLOOD}) {
            col.a *= min(1.0, float(d.z) / 8.0);
            acc = ragged(acc, sp, h, col, d.y < 200 || (h & 3) == 0);
        } else {
            // Liquids: inner cells full, edge and thin cells drop quadrants by a noise mask.
            bool edge = d.y < 24;
            if (!edge) {
                for (int k = 0; k < 4; k++) {
                    ivec2 n = c + ivec2(k == 0 ? -1 : (k == 1 ? 1 : 0), k == 2 ? -1 : (k == 3 ? 1 : 0));
                    if (!inside(n) || !liquid(cell_at(n).x & 15)) {
                        edge = true;
                        break;
                    }
                }
            }
            if (m == {BLOOD} && d.y < 40) {
                col.rgb *= 0.8;   // thin blood darkens as it soaks in
            }
            acc = ragged(acc, sp, h, col, edge);
            if (m == {WATER} || m == {TOXIC}) {
                if ((c.x + c.y * 2 + t) % 19 == 0 && in_rect(sp, 1 + (h & 1) * 2, 1, 2, 1)) {
                    acc = over(acc, vec4(1.0, 1.0, 1.0, 0.6));
                }
            } else if (m == {OIL}) {
                if ((c.x * 3 + c.y * 5 + t / 2) % 23 == 0) {
                    if (in_rect(sp, 1 + (h & 3), 1, 1, 1)) {
                        acc = over(acc, vec4(0.8, 0.7, 0.6, 0.7));
                    }
                } else if ((h & 31) == 0 && in_rect(sp, {HALF}, {HALF}, 1, 1)) {
                    acc = over(acc, vec4(0.55, 0.47, 0.42, 0.6));
                }
            } else if (m == {ACID}) {
                if ((h + t) % 11 == 0 && in_rect(sp, h % 5, (h >> 3) % 5, 1, 1)) {
                    acc = over(acc, vec4(0.95, 1.0, 0.7, 0.8));
                }
            }
        }
    }
    // Gas of the neighbours drifts a pixel into this cell's border.
    if (sp.x == 0 || sp.y == 0 || sp.x == CELL - 1 || sp.y == CELL - 1) {
        for (int k = 0; k < 9; k++) {
            ivec2 o = ivec2(k % 3 - 1, k / 3 - 1);
            if ((o.x == 0 && o.y == 0) || (o.x == -1 && sp.x != 0) || (o.x == 1 && sp.x != CELL - 1)
                    || (o.y == -1 && sp.y != 0) || (o.y == 1 && sp.y != CELL - 1)) {
                continue;
            }
            ivec2 n = c + o;
            ivec4 nd = cell_at(n);
            int nm = nd.x & 15;
            if ((nm == {POISON} || nm == {STEAM}) && (nd.x & 64) == 0) {
                acc = gas(acc, n, nd, px - n * CELL);
            }
        }
    }
    if (acc.a <= 0.0) {
        discard;
    }
    COLOR = acc;
#endif
}
"""


func _shader_code(glow: bool) -> String:
    var cols: Array = []
    for c in _cols:
        cols.append("vec4(%f, %f, %f, %f)" % [c.r, c.g, c.b, c.a])
    var fire: Array = []
    for c in _fire_cols:
        fire.append("vec4(%f, %f, %f, %f)" % [c.r, c.g, c.b, c.a])
    var code := MAT_SHADER.format({
        "BLEND": "blend_add" if glow else "blend_premul_alpha",
        "CELL": CELL, "HALF": HALF, "N": MAT_COUNT, "ASH_TICKS": ASH_TICKS,
        "COLS": "{ %s }" % ", ".join(cols), "FIRE_COLS": "{ %s }" % ", ".join(fire),
        "WATER": WATER, "OIL": OIL, "FIRE": FIRE, "ICE": ICE, "POISON": POISON, "ACID": ACID,
        "BLOOD": BLOOD, "STEAM": STEAM, "CHARGED": CHARGED, "ASH": ASH, "DRY_BLOOD": DRY_BLOOD, "TOXIC": TOXIC,
    })
    if glow:
        code = code.replace("render_mode blend_add;", "render_mode blend_add;\n#define GLOW")
    return code


func _make_draw_material(glow: bool) -> ShaderMaterial:
    var sh := Shader.new()
    sh.code = _shader_code(glow)
    var m := ShaderMaterial.new()
    m.shader = sh
    m.set_shader_parameter("data", _ttex)
    m.set_shader_parameter("origin", _origin)
    m.set_shader_parameter("grid", Vector2i(_w, _h))
    return m


## The room's grid plus a half-cell margin (gas drifts and glow squares reach past the rim).
func _quad_rect() -> Rect2:
    return Rect2(_origin - Vector2(HALF, HALF), Vector2(_w * CELL + CELL, _h * CELL + CELL))


## A cell's texel needs rewriting before the next flush.
func _touch(i: int) -> void:
    if _tmark[i] == 0:
        _tmark[i] = 1
        _tlist.append(i)


## Rewrites the texels of the touched cells and uploads the data texture (once per step).
func _flush_texels() -> void:
    for i: int in _tlist:
        _tmark[i] = 0
        var o := i * 4
        _tdata[o] = int(mat[i]) | ((int(_flag[i]) & (F_FRONT | F_ZAP | F_STILL)) << 2)
        _tdata[o + 1] = amt[i]
        _tdata[o + 2] = life[i]
        _tdata[o + 3] = _char[i]
    _tlist.clear()
    _timg.set_data(_w, _h, false, Image.FORMAT_RGBA8, _tdata)
    _ttex.update(_timg)


## The old redraw moment: flicker, glints and drift advance to this step.
func _redraw_uniforms() -> void:
    var sd := _draw_rng.randf() * 997.0   # its own generator: drawing never shifts gameplay rolls
    for m: ShaderMaterial in [material as ShaderMaterial, _glow.material as ShaderMaterial]:
        m.set_shader_parameter(&"t", _step_n)
        m.set_shader_parameter(&"seed", sd)


func _draw() -> void:
    draw_rect(_quad_rect(), Color.WHITE)
