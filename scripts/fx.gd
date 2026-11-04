class_name Fx
extends Node2D
## Immediate-mode effects. The core is a pixel particle system in the spirit of falling-sand
## games: squares of 2-5 world px in a 3-step palette per element (base, light core, dark
## edge), translucent so the floor and enemies stay readable under a burst, each moving by
## a behaviour (fire rises, water falls and splashes, oil sticks, void spirals in...).
## Also lightning arcs, ring outlines, floating text, corpses, bone bits and floor scorches.
##
## Every element has a signature shape (sig_fire, sig_wet, ... via signature()): flame
## tongues, a splash crown, lightning bolts, ice spikes, oil splatter, gas blooms, a fizzing
## puddle, a blood spray, an implosion, a pillar of light, a whirl, heavy chunks. A reaction
## is element a's signature, then element b's at 70%, then accents for what it does. Lines
## (bolts, spikes, rays, collapse lines) are short-lived vector shapes in `_shapes`.

const MAX_PUFFS := 120
const MAX_TEXTS := 48
const MAX_PIXELS := 700   # ring buffer: a new pixel past the cap overwrites the oldest
const MAX_ALPHA := 0.75
const MAX_SHAPES := 96

## Pixel behaviours.
enum B { FIRE, SMOKE, WET, ICE, SHOCK, OIL, POISON, ACID, BLOOD, VOID, HOLY, GALE, STONE, RING, DRIFT, ORBIT, EMBER, STUCK,
    TONGUE, BLOOM, SHEEN, FALL, SIZZLE, WHIRL }

## Vector shape kinds.
const SH_BOLT := 0       # { pts, w }            jagged polyline, yellow glow under a white core
const SH_SPIKE := 1      # { a, b, grow, pal, w } a line of squares growing a -> b, crumbles at the end
const SH_RAY := 2        # { a, b, grow, c, w }  a thin line growing a -> b, fading
const SH_COLLAPSE := 3   # { c, a, len }          a short line sliding from a into c
const SH_DISC := 4       # { c, r }               a dark disc with a thin violet edge

## Palette ids 0..12 are Element.Kind (0 = NONE = white); the extras follow.
const PAL_SMOKE := 13
const PAL_STEAM := 14
const PAL_GOLD := 15
const GRAVITY := 560.0

var main: Main
var _arcs: Array = []      # { a, b, t }
var _rings: Array = []     # { pos, r, color, t, life }  thin brief outlines of a burst radius
var _shapes: Array = []    # { k, t, life, d (delay), ... }  see SH_*
var _texts: Array = []     # { pos, text, color, t, life }
var _puffs: Array = []     # textured puffs (bone bits), normal blend
var _add_puffs: Array = [] # textured soft glow underlays, additive
var _corpses: Array = []   # { tex, pos, scale, color, flip, rot, t, life }
var _scorches: Array = []  # { pos, size, rot, t, life }
var _add: AddLayer
var _ground: GroundLayer
var _tex_keys: Dictionary = {}   # Art.PARTICLES texture -> key, for routing puff()

# Pixel pool: parallel packed arrays, one slot per pixel, used as a ring buffer.
var _pp := PackedVector2Array()   # position
var _pv := PackedVector2Array()   # velocity (ORBIT: x = angle, y = orbit radius)
var _po := PackedVector2Array()   # anchor: falling kinds y = floor line, x = state; VOID/ORBIT = centre; POISON/ACID x = phase
var _pt := PackedFloat32Array()   # life left (<= 0 is a free slot)
var _pl := PackedFloat32Array()   # life at spawn
var _ps := PackedFloat32Array()   # size in world px
var _pa := PackedFloat32Array()   # alpha (<= MAX_ALPHA)
var _pb := PackedInt32Array()     # behaviour (B)
var _pc := PackedInt32Array()     # palette id
var _pk := PackedByteArray()      # layer: 0 normal, 1 additive
var _head := 0                    # next slot to write
var _cnt := 0                     # slots in the live window, oldest first, ending at _head

var _pal := PackedColorArray()    # 3 colours per palette: base, core, edge
var _pal_count := 0
var _pal_ids: Dictionary = {}     # snapped Color -> palette id


class AddLayer extends Node2D:
    var fx: Fx
    func _draw() -> void:
        fx._draw_puffs(fx._add_puffs, self)
        fx._draw_pixels(self, 1)


class GroundLayer extends Node2D:
    var fx: Fx
    func _draw() -> void:
        fx._draw_scorches(self)


func _ready() -> void:
    z_index = 20
    _add = AddLayer.new()
    _add.fx = self
    var m := CanvasItemMaterial.new()
    m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    _add.material = m
    _add.z_index = 1
    add_child(_add)
    _ground = GroundLayer.new()
    _ground.fx = self
    _ground.z_index = -21   # relative: lands just above the floor tiles
    add_child(_ground)
    _pp.resize(MAX_PIXELS)
    _pv.resize(MAX_PIXELS)
    _po.resize(MAX_PIXELS)
    _pt.resize(MAX_PIXELS)
    _pl.resize(MAX_PIXELS)
    _ps.resize(MAX_PIXELS)
    _pa.resize(MAX_PIXELS)
    _pb.resize(MAX_PIXELS)
    _pc.resize(MAX_PIXELS)
    _pk.resize(MAX_PIXELS)
    _pt.fill(0.0)
    _build_palettes()
    for key in Art.PARTICLES:
        _tex_keys[Art.PARTICLES[key]] = key
    Elements.lightning_arc.connect(_on_arc)
    Elements.reaction_fired.connect(_on_reaction)
    Elements.nova.connect(_on_nova)


func _build_palettes() -> void:
    # base, core (lighter), edge (darker), per Element.Kind order.
    var table := [
        [Color(1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0), Color(0.70, 0.72, 0.78)],       # NONE / white
        [Color(0.30, 0.60, 1.00), Color(0.90, 0.97, 1.00), Color(0.15, 0.32, 0.70)], # WET
        [Color(1.00, 0.95, 0.30), Color(1.00, 1.00, 0.90), Color(0.85, 0.60, 0.15)], # SHOCK
        [Color(1.00, 0.45, 0.15), Color(1.00, 0.88, 0.35), Color(0.72, 0.14, 0.08)], # FIRE
        [Color(0.70, 0.95, 1.00), Color(1.00, 1.00, 1.00), Color(0.40, 0.68, 0.90)], # ICE
        [Color(0.20, 0.15, 0.12), Color(0.55, 0.47, 0.42), Color(0.10, 0.07, 0.06)], # OIL
        [Color(0.45, 0.90, 0.20), Color(0.75, 1.00, 0.50), Color(0.20, 0.50, 0.10)], # POISON
        [Color(0.80, 1.00, 0.25), Color(0.95, 1.00, 0.70), Color(0.45, 0.60, 0.10)], # ACID
        [Color(0.85, 0.12, 0.18), Color(1.00, 0.40, 0.40), Color(0.45, 0.04, 0.08)], # BLOOD
        [Color(0.55, 0.25, 0.85), Color(0.85, 0.65, 1.00), Color(0.25, 0.08, 0.40)], # VOID
        [Color(1.00, 0.95, 0.70), Color(1.00, 1.00, 1.00), Color(1.00, 0.78, 0.30)], # HOLY
        [Color(0.75, 0.92, 0.88), Color(0.95, 1.00, 1.00), Color(0.45, 0.62, 0.60)], # GALE
        [Color(0.62, 0.56, 0.46), Color(0.80, 0.75, 0.65), Color(0.36, 0.32, 0.26)], # STONE
        [Color(0.22, 0.20, 0.22), Color(0.32, 0.30, 0.32), Color(0.12, 0.11, 0.12)], # smoke
        [Color(0.80, 0.85, 0.88), Color(0.95, 0.97, 1.00), Color(0.55, 0.60, 0.65)], # steam
        [Color(1.00, 0.80, 0.30), Color(1.00, 0.97, 0.75), Color(0.75, 0.50, 0.12)], # gold
    ]
    for row in table:
        for c in row:
            _pal.append(c)
        _pal_count += 1
    for kind in Element.COLORS:
        _pal_ids[_snap(Element.COLORS[kind])] = int(kind)


static func _snap(c: Color) -> Color:
    return Color(snappedf(c.r, 0.02), snappedf(c.g, 0.02), snappedf(c.b, 0.02), 1.0)


## Palette for an arbitrary colour: the element palette when it is an element colour.
func _pal_of(c: Color) -> int:
    var key := _snap(c)
    if _pal_ids.has(key):
        return _pal_ids[key]
    if _pal_count >= 96:
        return 0
    _pal.append(key)
    _pal.append(key.lightened(0.45))
    _pal.append(key.darkened(0.45))
    var id := _pal_count
    _pal_count += 1
    _pal_ids[key] = id
    return id


## The element a colour belongs to, or NONE.
static func _kind_of(c: Color) -> int:
    for kind in Element.COLORS:
        var e: Color = Element.COLORS[kind]
        if absf(e.r - c.r) + absf(e.g - c.g) + absf(e.b - c.b) < 0.06:
            return int(kind)
    return Element.Kind.NONE


# --- Pixel spawners --------------------------------------------------------


func _px(pos: Vector2, vel: Vector2, life: float, size: float, alpha: float, beh: int, pal: int, additive: bool, anchor := Vector2.ZERO) -> void:
    var i := _head
    _pp[i] = pos
    _pv[i] = vel
    _po[i] = anchor
    _pt[i] = life
    _pl[i] = life
    _ps[i] = size
    _pa[i] = minf(alpha, MAX_ALPHA)
    _pb[i] = beh
    _pc[i] = pal
    _pk[i] = 1 if additive else 0
    _head = (_head + 1) % MAX_PIXELS
    _cnt = mini(_cnt + 1, MAX_PIXELS)


## One element pixel at `pos` with a base velocity `v`; the element decides how it moves.
func _element_px(kind: int, pos: Vector2, v: Vector2, pal := -1) -> void:
    var p := kind if pal < 0 else pal
    match kind:
        Element.Kind.FIRE:
            _px(pos, v * 0.5 + Vector2(0, randf_range(-90.0, -40.0)), randf_range(0.35, 0.7), randf_range(2.0, 4.0), randf_range(0.45, 0.65), B.FIRE, p, true)
        Element.Kind.WET:
            _px(pos, v * 0.8 + Vector2(0, randf_range(-130.0, -60.0)), 1.2, randf_range(2.0, 3.0), randf_range(0.45, 0.6), B.WET, p, false, Vector2(0, pos.y + randf_range(8.0, 24.0)))
        Element.Kind.ICE:
            _px(pos, v * 1.3, randf_range(0.5, 0.85), randf_range(2.0, 4.0), randf_range(0.45, 0.65), B.ICE, p, true)
        Element.Kind.SHOCK:
            _px(pos, v, randf_range(0.15, 0.3), 2.0, randf_range(0.55, 0.75), B.SHOCK, p, true)
        Element.Kind.OIL:
            _px(pos, v * 0.7 + Vector2(0, randf_range(-120.0, -50.0)), 1.2, randf_range(3.0, 5.0), randf_range(0.55, 0.7), B.OIL, p, false, Vector2(0, pos.y + randf_range(6.0, 20.0)))
        Element.Kind.POISON:
            _px(pos, v * 0.35 + Vector2(0, -10.0), randf_range(0.9, 1.5), randf_range(2.0, 4.0), randf_range(0.4, 0.55), B.POISON, p, false, Vector2(randf() * TAU, 0))
        Element.Kind.ACID:
            _px(pos, v * 0.4 + Vector2(0, -25.0), randf_range(0.5, 0.9), randf_range(2.0, 4.0), randf_range(0.45, 0.6), B.ACID, p, false, Vector2(randf() * TAU, 0))
        Element.Kind.BLOOD:
            _px(pos, v * 0.8 + Vector2(0, randf_range(-120.0, -50.0)), 1.2, randf_range(2.0, 4.0), randf_range(0.55, 0.7), B.BLOOD, p, false, Vector2(0, pos.y + randf_range(6.0, 22.0)))
        Element.Kind.VOID:
            var out := pos + v.normalized() * (20.0 + v.length() * 0.4)
            _px(out, Vector2.ZERO, randf_range(0.6, 0.9), randf_range(2.0, 3.0), randf_range(0.5, 0.7), B.VOID, p, true, pos)
        Element.Kind.HOLY:
            _px(pos, Vector2(randf_range(-12.0, 12.0), randf_range(-120.0, -60.0)), randf_range(0.5, 0.9), randf_range(2.0, 3.0), randf_range(0.55, 0.75), B.HOLY, p, true)
        Element.Kind.GALE:
            var sx := 1.0 if v.x >= 0.0 else -1.0
            _px(pos, Vector2(sx * randf_range(220.0, 360.0), randf_range(-25.0, 25.0)), randf_range(0.25, 0.45), 2.0, randf_range(0.4, 0.55), B.GALE, p, false)
        Element.Kind.STONE:
            _px(pos, v * 0.7 + Vector2(0, randf_range(-150.0, -80.0)), 1.5, randf_range(3.0, 5.0), randf_range(0.6, 0.7), B.STONE, p, false, Vector2(0, pos.y + randf_range(8.0, 20.0)))
        _:
            _px(pos, v, randf_range(0.3, 0.5), 2.0, 0.5, B.RING, p, true)


## `count` pixels of an element bursting from `pos` at up to `speed` px/s.
func pixels(kind: int, pos: Vector2, count: int, speed := 80.0, spread := 6.0, pal := -1) -> void:
    for n in count:
        var off := Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
        _element_px(kind, pos + off, Vector2.RIGHT.rotated(randf() * TAU) * speed * randf_range(0.4, 1.0), pal)


## A rising ember, shed by burning enemies.
func ember(pos: Vector2) -> void:
    _px(pos, Vector2(randf_range(-10.0, 10.0), randf_range(-55.0, -30.0)), randf_range(0.5, 0.9), 2.0, randf_range(0.45, 0.65), B.EMBER, Element.Kind.FIRE, true)


## One drifting pixel of an element (status shedding).
func mote(kind: int, pos: Vector2) -> void:
    _element_px(kind, pos, Vector2.RIGHT.rotated(randf() * TAU) * 15.0)


## Dark smoke pixels drifting up and spreading.
func smoke(pos: Vector2, count: int, spread := 10.0, pal := PAL_SMOKE) -> void:
    for n in count:
        var off := Vector2(randf_range(-spread, spread), randf_range(-spread, spread) * 0.5)
        _px(pos + off, Vector2(randf_range(-15.0, 15.0), randf_range(-35.0, -15.0)), randf_range(0.8, 1.4), randf_range(3.0, 4.0), randf_range(0.35, 0.45), B.SMOKE, pal, false)


## A thin, brief outline of a burst radius. Never the body of an effect. Two outlines of the
## same radius at the same spot in the same instant (reaction + nova signal) draw once.
func outline(pos: Vector2, r: float, pal: int, life := 0.3) -> void:
    for o in _rings:
        var op: Vector2 = o["pos"]
        var orad: float = o["r"]
        var oage: float = float(o["life"]) - float(o["t"])
        if op.distance_squared_to(pos) < 16.0 and absf(orad - r) < r * 0.1 and oage < 0.1:
            return
    var c: Color = _pal[pal * 3]
    _rings.append({ "pos": pos, "r": r, "color": Color(c, 0.3), "t": life, "life": life })


## Pixels on a circle spiralling into `pos`.
func spiral(pos: Vector2, r: float, count: int, pal: int) -> void:
    for n in count:
        var d := Vector2.RIGHT.rotated(randf() * TAU) * r * randf_range(0.5, 0.9)
        _px(pos + d, Vector2.ZERO, randf_range(0.5, 0.85), randf_range(2.0, 3.0), randf_range(0.5, 0.7), B.VOID, pal, true, pos)


## Pixels streaking outward from `pos` (a shove).
func streaks(pos: Vector2, r: float, count: int, pal: int) -> void:
    for n in count:
        var d := Vector2.RIGHT.rotated(randf() * TAU)
        _px(pos + d * 8.0, d * r * randf_range(2.2, 3.2), randf_range(0.25, 0.4), 2.0, randf_range(0.4, 0.55), B.GALE, pal, true)


## A star of ice shards: each arm is 3 pixels flying straight out and stopping.
func shards(pos: Vector2, arms: int, length: float, pal := Element.Kind.ICE) -> void:
    for k in arms:
        var d := Vector2.RIGHT.rotated(TAU * float(k) / float(arms) + randf_range(-0.12, 0.12))
        for m in 3:
            _px(pos + d * (4.0 + 3.0 * m), d * length * 6.0 * (1.0 - 0.25 * m), randf_range(0.55, 0.8), 3.0 - 0.5 * m, 0.65 - 0.1 * m, B.ICE, pal, true)


## Small pixels orbiting above `pos` (stun).
func orbit(pos: Vector2, count: int, pal := 0) -> void:
    var c := pos + Vector2(0, -22.0)
    for k in count:
        var a := TAU * float(k) / float(count)
        _px(c + Vector2(cos(a), sin(a) * 0.45) * 14.0, Vector2(a, 14.0), 0.9, 2.0, MAX_ALPHA, B.ORBIT, pal, true, c)


## White and gold pixels rising (purge, heal).
func rise(pos: Vector2, count: int, spread := 18.0) -> void:
    for n in count:
        var off := Vector2(randf_range(-spread, spread), randf_range(-spread, spread) * 0.6)
        _px(pos + off, Vector2(randf_range(-6.0, 6.0), randf_range(-110.0, -55.0)), randf_range(0.6, 1.0), randf_range(2.0, 3.0), randf_range(0.55, 0.75), B.HOLY, PAL_GOLD if n % 2 == 1 else Element.Kind.HOLY, true)


## A lingering puff of slow pixels (a cloud forming).
func linger(pos: Vector2, r: float, count: int, pal: int, additive := false) -> void:
    for n in count:
        var off := Vector2.RIGHT.rotated(randf() * TAU) * r * sqrt(randf()) * 0.6
        _px(pos + off, Vector2(randf_range(-12.0, 12.0), randf_range(-14.0, 4.0)), randf_range(1.0, 1.8), randf_range(2.0, 4.0), randf_range(0.35, 0.5), B.DRIFT, pal, additive)


## Motes of an element scattered over a disc of radius `r` (an area being coated, no ring).
func _scatter(kind: int, pos: Vector2, r: float, count: int) -> void:
    for n in count:
        mote(kind, pos + Vector2.RIGHT.rotated(randf() * TAU) * r * sqrt(randf()) * 0.8)


## A flat sheen on the floor: wide low squares that spread a little and fade.
func _patch(pos: Vector2, r: float, pal: int, count: int, alpha := 0.25, life := 1.2) -> void:
    for n in count:
        var off := Vector2(randf_range(-r, r), randf_range(-r, r) * 0.35)
        _px(pos + off, off.normalized() * randf_range(8.0, 20.0), life * randf_range(0.8, 1.2), randf_range(3.0, 5.0), alpha * randf_range(0.8, 1.2), B.SHEEN, pal, false)


# --- Vector shapes ---------------------------------------------------------


func _shape(sh: Dictionary, life: float, delay := 0.0) -> void:
    sh["life"] = life
    sh["d"] = delay
    sh["t"] = life + delay
    _shapes.append(sh)
    if _shapes.size() > MAX_SHAPES:
        _shapes.pop_front()


## Jagged polyline from `from` heading `dir`.
func _bolt_pts(from: Vector2, dir: Vector2, length: float, segs: int) -> PackedVector2Array:
    var pts := PackedVector2Array()
    pts.append(from)
    var p := from
    var step := length / float(segs)
    for n in segs:
        p += dir.rotated(randf_range(-0.7, 0.7)) * step * randf_range(0.7, 1.2)
        pts.append(p)
    return pts


## One lightning bolt with 1-2 sub-branches and sparks at the tips.
func _bolt(pos: Vector2, dir: Vector2, length: float, life: float, w := 1.0) -> void:
    var pts := _bolt_pts(pos, dir, length, 6)
    _shape({ "k": SH_BOLT, "pts": pts, "w": w }, life)
    _sparks(pts[pts.size() - 1], 2)
    for m in 1 + randi() % 2:
        var side := 1.0 if randi() % 2 == 0 else -1.0
        var sub := _bolt_pts(pts[2 + randi() % 3], dir.rotated(randf_range(0.5, 0.9) * side), length * 0.4, 3)
        _shape({ "k": SH_BOLT, "pts": sub, "w": w * 0.6 }, life * 0.8)
        _sparks(sub[sub.size() - 1], 1)


func _sparks(pos: Vector2, count: int) -> void:
    for n in count:
        _px(pos, Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30.0, 90.0), randf_range(0.12, 0.25), 2.0, 0.7, B.SHOCK, Element.Kind.SHOCK, true)


## Spikes growing out of the ground from `pos`, fanned `fan` radians either side of up.
func _spikes(pos: Vector2, count: int, length: float, pal := Element.Kind.ICE, fan := 1.25, hold := 0.35) -> void:
    for k in count:
        var q := 0.5 if count == 1 else float(k) / float(count - 1)
        var ang := -PI * 0.5 + lerpf(-fan, fan, q) + randf_range(-0.12, 0.12)
        var base := pos + Vector2(randf_range(-5.0, 5.0), randf_range(0.0, 6.0))
        var tip := base + Vector2.RIGHT.rotated(ang) * length * randf_range(0.6, 1.0)
        _shape({ "k": SH_SPIKE, "a": base, "b": tip, "grow": 0.2, "pal": pal, "w": 4.0 if length > 30.0 else 3.0 }, 0.2 + hold * randf_range(0.8, 1.2), randf_range(0.0, 0.06))


## A spike at the end of its hold breaks into falling fragments.
func _crumble(sh: Dictionary) -> void:
    var a0: Vector2 = sh["a"]
    var b0: Vector2 = sh["b"]
    var pal: int = sh["pal"]
    var n := clampi(int(a0.distance_to(b0) / 6.0), 2, 5)
    for m in n:
        var p := a0.lerp(b0, (float(m) + 0.5) / float(n))
        _px(p, Vector2(randf_range(-25.0, 25.0), randf_range(-30.0, 0.0)), randf_range(0.35, 0.6), randf_range(2.0, 3.0), 0.6, B.FALL, pal, true)


func _ray(a: Vector2, b: Vector2, c: Color, life: float, w := 1.0, delay := 0.0) -> void:
    _shape({ "k": SH_RAY, "a": a, "b": b, "grow": 0.08, "c": c, "w": w }, life, delay)


# --- Element signatures ----------------------------------------------------
# Each takes pos, size (reach in px) and strength (1 = a full signature, 20-60 pixels).


static func _n(base: float, strength: float, lo: int, hi: int) -> int:
    return clampi(roundi(base * strength), lo, hi)


## The signature shape of an element. `dir` aims directional ones (blood).
func signature(kind: int, pos: Vector2, size: float, strength := 1.0, dir := Vector2.ZERO) -> void:
    match kind:
        Element.Kind.FIRE: sig_fire(pos, size, strength)
        Element.Kind.WET: sig_wet(pos, size, strength)
        Element.Kind.SHOCK: sig_shock(pos, size, strength)
        Element.Kind.ICE: sig_ice(pos, size, strength)
        Element.Kind.OIL: sig_oil(pos, size, strength)
        Element.Kind.POISON: sig_poison(pos, size, strength)
        Element.Kind.ACID: sig_acid(pos, size, strength)
        Element.Kind.BLOOD: sig_blood(pos, size, strength, dir)
        Element.Kind.VOID: sig_void(pos, size, strength)
        Element.Kind.HOLY: sig_holy(pos, size, strength)
        Element.Kind.GALE: sig_gale(pos, size, strength)
        Element.Kind.STONE: sig_stone(pos, size, strength)
        _: pixels(0, pos, _n(12.0, strength, 4, 20), size * 1.5)


## One flame tongue: a short vertical run of squares, yellow at the base to red at the top,
## rising and swaying together.
func _tongue(base: Vector2, height: int, vy: float, life: float, sz: float) -> void:
    var ph := randf() * TAU
    var vx := randf_range(-6.0, 6.0)
    for m in height:
        var step := 1 if m == 0 else (2 if m == height - 1 else 0)
        _px(base + Vector2(0, -float(m) * sz * 0.9), Vector2(vx, vy), life * (1.0 - 0.12 * float(m)), maxf(2.0, sz - 0.4 * float(m)), randf_range(0.5, 0.65), B.TONGUE, Element.Kind.FIRE, true, Vector2(ph, float(step)))


## FIRE: 5-9 flame tongues, embers; tongues leave a little smoke when they die.
func sig_fire(pos: Vector2, size: float, strength := 1.0) -> void:
    var n := _n(5.0 + size / 30.0, strength, 3, 12)
    for k in n:
        var x := lerpf(-size * 0.45, size * 0.45, (float(k) + randf_range(0.2, 0.8)) / float(n))
        var tall := 1.0 - absf(x) / maxf(size, 1.0) * 0.8
        _tongue(pos + Vector2(x, randf_range(-4.0, 8.0)), 3 + randi() % 3, randf_range(-110.0, -60.0) * tall, randf_range(0.35, 0.6), randf_range(3.0, 4.0))
    for k in _n(4.0, strength, 1, 8):
        ember(pos + Vector2(randf_range(-size * 0.4, size * 0.4), randf_range(-10.0, 4.0)))
    _glow(pos, size * 1.2, Color(1.0, 0.6, 0.2, 0.25), 0.25)


## WET: a crown of droplets thrown up and out that fall back and splash, plus a puddle sheen.
func sig_wet(pos: Vector2, size: float, strength := 1.0) -> void:
    var n := _n(14.0, strength, 6, 22)
    var spd := clampf(size * 1.6, 60.0, 200.0)
    var a0 := randf() * TAU
    for k in n:
        var ang := a0 + TAU * float(k) / float(n) + randf_range(-0.1, 0.1)
        var d := Vector2(cos(ang), sin(ang) * 0.45)
        var floor_y := pos.y + maxf(d.y, 0.0) * size * 0.6 + randf_range(2.0, 8.0)
        var v := Vector2(d.x * spd * randf_range(0.6, 1.0), d.y * spd * 0.4 - randf_range(140.0, 220.0))
        _px(pos + d * 4.0, v, 1.4, randf_range(2.0, 3.0), randf_range(0.5, 0.65), B.WET, Element.Kind.WET, false, Vector2(0, floor_y))
    _patch(pos + Vector2(0, 4.0), size * 0.35, Element.Kind.WET, _n(6.0, strength, 3, 8), 0.25, 1.2)


## SHOCK: 3-5 branching bolts from the point outward, sparks at the tips.
func sig_shock(pos: Vector2, size: float, strength := 1.0) -> void:
    var n := _n(3.0 + 2.0 * minf(strength, 1.0), maxf(strength, 1.0), 2, 7)
    var a0 := randf() * TAU
    for k in n:
        var dir := Vector2.RIGHT.rotated(a0 + TAU * float(k) / float(n) + randf_range(-0.4, 0.4))
        _bolt(pos, dir, size * randf_range(0.7, 1.1), randf_range(0.15, 0.3), clampf(strength, 0.6, 1.3))
    for k in _n(6.0, strength, 2, 10):
        _px(pos, Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 110.0), randf_range(0.15, 0.3), 2.0, 0.7, B.SHOCK, Element.Kind.SHOCK, true)
    _glow(pos, size * 1.2, Color(1.0, 1.0, 0.8, 0.3), 0.15)


## ICE: 5-7 crystal spikes growing from the ground, holding, then crumbling; white tip glints.
func sig_ice(pos: Vector2, size: float, strength := 1.0) -> void:
    _spikes(pos, _n(5.0 + 2.0 * minf(strength, 1.0), maxf(strength, 1.0), 3, 9), size * 0.8)
    for k in _n(5.0, strength, 2, 8):
        _px(pos + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)), Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30.0, 70.0), randf_range(0.4, 0.7), randf_range(2.0, 3.0), 0.6, B.ICE, Element.Kind.ICE, true)
    _glow(pos, size, Color(0.8, 0.95, 1.0, 0.25), 0.25)


## OIL: dark droplets that arc out and stick as glossy dots, plus a small dark pool.
func sig_oil(pos: Vector2, size: float, strength := 1.0) -> void:
    for k in _n(16.0, strength, 6, 22):
        var d := Vector2.RIGHT.rotated(randf() * TAU)
        var spd := size * randf_range(0.8, 1.8)
        _px(pos + d * 3.0, Vector2(d.x * spd, d.y * spd * 0.4 - randf_range(60.0, 130.0)), 1.4, randf_range(3.0, 5.0), randf_range(0.55, 0.7), B.OIL, Element.Kind.OIL, false, Vector2(0, pos.y + maxf(d.y, 0.0) * size * 0.4 + randf_range(4.0, 14.0)))
    _patch(pos + Vector2(0, 4.0), size * 0.25, Element.Kind.OIL, _n(5.0, strength, 2, 6), 0.45, 1.9)


## POISON: 3-4 gas blooms (clusters with a light core) that rise slowly, wobble and thin out.
func sig_poison(pos: Vector2, size: float, strength := 1.0) -> void:
    var blobs := _n(3.5, strength, 2, 5)
    var br := clampf(size * 0.12, 5.0, 12.0)
    for k in blobs:
        var c := pos + Vector2(randf_range(-size * 0.4, size * 0.4), randf_range(-size * 0.2, size * 0.1))
        var vel := Vector2(randf_range(-10.0, 10.0), randf_range(-28.0, -14.0))
        var ph := randf() * TAU
        var life := randf_range(1.1, 1.7)
        for j in 6 + randi() % 5:
            var off := Vector2.RIGHT.rotated(randf() * TAU) * br * sqrt(randf())
            var step := 1 if off.length() < br * 0.45 else (0 if randf() < 0.7 else 2)
            _px(c + off, vel + off * 0.6, life * randf_range(0.95, 1.0), randf_range(3.0, 4.0), randf_range(0.35, 0.5), B.BLOOM, Element.Kind.POISON, false, Vector2(ph, float(step)))


## ACID: a bright fizzing pool, bubbles rising and popping, eating sparks on the ground.
func sig_acid(pos: Vector2, size: float, strength := 1.0) -> void:
    var r := size * 0.35
    _patch(pos + Vector2(0, 4.0), r, Element.Kind.ACID, _n(6.0, strength, 3, 8), 0.3, 1.3)
    for k in _n(13.0, strength, 5, 18):
        var off := Vector2(randf_range(-r, r), randf_range(-r, r) * 0.35)
        _px(pos + off, Vector2(0, randf_range(-35.0, -12.0)), randf_range(0.4, 1.0), randf_range(2.0, 3.0), 0.55, B.ACID, Element.Kind.ACID, false, Vector2(randf() * TAU, 0))
    for k in _n(8.0, strength, 3, 12):
        var off2 := Vector2(randf_range(-r, r), randf_range(-r, r) * 0.35)
        _px(pos + off2 + Vector2(0, 4.0), Vector2.ZERO, randf_range(0.2, 0.5), 2.0, 0.7, B.SIZZLE, Element.Kind.ACID, true)


## BLOOD: a spray along `dir` (radial when zero); droplets arc out and splat into dots.
func sig_blood(pos: Vector2, size: float, strength := 1.0, dir := Vector2.ZERO) -> void:
    var aim := dir.normalized()
    for k in _n(18.0, strength, 8, 24):
        var d := aim.rotated(randf_range(-0.5, 0.5)) if aim != Vector2.ZERO else Vector2.RIGHT.rotated(randf() * TAU)
        var spd := size * randf_range(1.2, 2.4)
        _px(pos + d * 4.0, Vector2(d.x * spd, d.y * spd * 0.5 - randf_range(60.0, 140.0)), 1.4, randf_range(2.0, 4.0), randf_range(0.55, 0.7), B.BLOOD, Element.Kind.BLOOD, false, Vector2(0, pos.y + maxf(d.y, 0.0) * size * 0.3 + randf_range(4.0, 14.0)))


## VOID: an implosion. Pixels spiral in, a dark disc with a violet edge opens and closes,
## then a pulse of short lines collapses inward.
func sig_void(pos: Vector2, size: float, strength := 1.0) -> void:
    spiral(pos, size, _n(22.0, strength, 8, 40), Element.Kind.VOID)
    _shape({ "k": SH_DISC, "c": pos, "r": clampf(size * 0.3, 8.0, 40.0) * clampf(strength, 0.6, 1.5) }, 0.45)
    var lines := _n(10.0, strength, 5, 16)
    for k in lines:
        var d := Vector2.RIGHT.rotated(TAU * float(k) / float(lines) + randf_range(-0.1, 0.1))
        _shape({ "k": SH_COLLAPSE, "c": pos, "a": pos + d * size * randf_range(0.8, 1.0), "len": randf_range(6.0, 10.0) }, 0.28, 0.2)


## HOLY: a pillar of light. Rising white and gold column, a bright flash at the base, thin
## rays fanning up.
func sig_holy(pos: Vector2, size: float, strength := 1.0) -> void:
    var w := clampf(size * 0.15, 6.0, 20.0)
    for k in _n(22.0, strength, 8, 50):
        _px(pos + Vector2(randf_range(-w, w), randf_range(-4.0, 4.0) - randf() * size * 0.3), Vector2(randf_range(-4.0, 4.0), randf_range(-150.0, -70.0)), randf_range(0.5, 0.9), randf_range(2.0, 3.0), randf_range(0.55, 0.75), B.HOLY, PAL_GOLD if k % 2 == 1 else Element.Kind.HOLY, true)
    for k in _n(6.0, strength, 3, 10):
        _px(pos, Vector2.RIGHT.rotated(randf() * TAU) * Vector2(1.0, 0.4) * randf_range(40.0, 90.0), randf_range(0.1, 0.18), 3.0, MAX_ALPHA, B.RING, 0, true)
    _glow(pos, size * 0.9, Color(1.0, 0.95, 0.7, 0.3), 0.2)
    var rays := _n(5.0, strength, 3, 9)
    for k in rays:
        var q := 0.5 if rays == 1 else float(k) / float(rays - 1)
        var ang := -PI * 0.5 + lerpf(-0.55, 0.55, q) + randf_range(-0.06, 0.06)
        _ray(pos, pos + Vector2.RIGHT.rotated(ang) * size * randf_range(0.9, 1.3), Color(1.0, 0.85, 0.4), 0.35, 1.0, randf_range(0.0, 0.05))


## GALE: a whirl. Streaks orbit the point once and fly off; grey dust swept up.
func sig_gale(pos: Vector2, size: float, strength := 1.0) -> void:
    for k in _n(14.0, strength, 6, 24):
        var ang := randf() * TAU
        var r := size * randf_range(0.35, 0.6)
        _px(pos + Vector2(cos(ang), sin(ang) * 0.55) * r, Vector2(ang, r), randf_range(0.5, 0.7), 2.0, randf_range(0.45, 0.6), B.WHIRL, Element.Kind.GALE, false, pos)
    for k in _n(10.0, strength, 4, 16):
        _px(pos + Vector2(randf_range(-size * 0.4, size * 0.4), randf_range(0.0, 8.0)), Vector2(randf_range(-60.0, 60.0), randf_range(-25.0, -5.0)), randf_range(0.6, 1.0), randf_range(2.0, 4.0), randf_range(0.3, 0.45), B.DRIFT, PAL_STEAM, false, Vector2(randf() * TAU, 0))


## STONE: heavy chunks arcing out and bouncing once, a dust cloud at ground level.
func sig_stone(pos: Vector2, size: float, strength := 1.0) -> void:
    for k in _n(10.0, strength, 4, 30):
        var d := Vector2.RIGHT.rotated(randf() * TAU)
        var spd := size * randf_range(0.8, 1.6)
        _px(pos + d * 4.0, Vector2(d.x * spd, d.y * spd * 0.3 - randf_range(120.0, 220.0)), 1.6, randf_range(3.0, 5.0), randf_range(0.6, 0.7), B.STONE, Element.Kind.STONE, false, Vector2(0, pos.y + maxf(d.y, 0.0) * size * 0.3 + randf_range(4.0, 16.0)))
    for k in _n(12.0, strength, 4, 30):
        _px(pos + Vector2(randf_range(-size * 0.5, size * 0.5), randf_range(2.0, 10.0)), Vector2(randf_range(-40.0, 40.0), randf_range(-10.0, 0.0)), randf_range(0.8, 1.4), randf_range(3.0, 4.0), randf_range(0.3, 0.4), B.DRIFT, Element.Kind.STONE, false, Vector2(randf() * TAU, 0))


# --- Public spawners -------------------------------------------------------


## Legacy puff. Kenney particle textures are turned into pixels; any other texture (bone
## tiles) is still drawn as a spinning textured puff.
func puff(tex: Texture2D, pos: Vector2, color: Color, size: float, life: float, additive := false, vel := Vector2.ZERO, spin := 0.6) -> void:
    var key: String = _tex_keys.get(tex, "")
    if key == "":
        _tex_puff(tex, pos, color, size, life, additive, vel, spin)
        return
    var pal := _pal_of(color)
    var a := minf(color.a, 0.6)
    match key:
        "smoke":
            var n := clampi(int(size / 24.0), 2, 10)
            for k in n:
                var off := Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6)) * size * 0.3
                _px(pos + off, vel + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 6.0)), life * randf_range(1.0, 1.6), randf_range(2.0, 4.0), a * randf_range(0.6, 0.85), B.SMOKE if color.v < 0.35 else B.DRIFT, pal, false)
        "light":
            _glow(pos, minf(size, 140.0), color, life)
            for k in clampi(int(size / 24.0), 2, 8):
                _px(pos, Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30.0, 90.0) + vel, maxf(life, 0.12) * randf_range(1.0, 1.8), 2.0, 0.6, B.RING, pal, true)
        "spark":
            for k in clampi(int(size / 10.0), 4, 12):
                _px(pos, Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 120.0), randf_range(0.15, 0.3), 2.0, 0.7, B.SHOCK, pal, true)
        "circle":
            outline(pos, size * 0.5, pal, maxf(life, 0.2))
            for k in clampi(int(size / 12.0), 3, 8):
                _px(pos, Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30.0, 80.0), randf_range(0.15, 0.3), 2.0, 0.6, B.RING, pal, true)
        "flame":
            for k in clampi(int(size / 12.0), 3, 12):
                _element_px(Element.Kind.FIRE, pos, Vector2.RIGHT.rotated(randf() * TAU) * 40.0, pal)
        "twirl":
            spiral(pos, size * 0.5, clampi(int(size / 10.0), 6, 16), pal)
        _:
            for k in clampi(int(size / 14.0), 3, 10):
                _px(pos, Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20.0, 60.0) + Vector2(0, -30.0), life * 1.5, 2.0, a, B.DRIFT, pal, additive)


func _tex_puff(tex: Texture2D, pos: Vector2, color: Color, size: float, life: float, additive: bool, vel: Vector2, spin: float) -> void:
    var list := _add_puffs if additive else _puffs
    list.append({ "tex": tex, "pos": pos, "color": color, "size": size, "rot": randf() * TAU, "t": life, "life": life, "vel": vel, "spin": spin })
    if list.size() > MAX_PUFFS:
        list.pop_front()


## Soft additive glow underlay (small Kenney light texture), kept faint.
func _glow(pos: Vector2, size: float, color: Color, life: float) -> void:
    _tex_puff(Art.PARTICLES["light"], pos, Color(color, minf(color.a, 0.3)), size, life, true, Vector2.ZERO, 0.0)


## Thin wrapper for older callers (bomber): the element's signature at the blast's size.
func blast(pos: Vector2, radius: float, color: Color, _life := 0.55) -> void:
    var kind := _kind_of(color)
    signature(kind, pos, clampf(radius * 0.6, 40.0, 100.0), 1.2)
    if kind == Element.Kind.FIRE:
        smoke(pos, 8, 16.0)


## A floating damage number. `big` is a crit: larger, brighter, and it lingers.
func number(pos: Vector2, amount: float, color: Color, big := false, dim := false) -> void:
    var n := maxi(1, roundi(amount))
    var text := str(n) + ("!" if big else "")
    var size := 30 if big else (20 if dim else 24)
    var col := color
    if big:
        col = Color(1.0, 0.95, 0.55)
    elif dim:
        col = Color(color, 0.75)
    var p := pos + Vector2(randf_range(-14.0, 14.0), -22.0 + randf_range(-6.0, 6.0))
    _texts.append({ "pos": p, "text": text, "color": col, "t": 0.9 if big else 0.7, "life": 0.9 if big else 0.7, "size": size,
        "vel": Vector2(randf_range(-20.0, 20.0), -70.0 if big else -50.0) })
    if _texts.size() > MAX_TEXTS:
        _texts.pop_front()


func corpse(tex: Texture2D, pos: Vector2, scale: float, color: Color, flip: bool) -> void:
    _corpses.append({ "tex": tex, "pos": pos, "scale": scale, "color": color, "flip": flip, "rot": randf_range(-1.2, 1.2), "t": 0.5, "life": 0.5 })


func bones(pos: Vector2, color: Color, count: int = 3) -> void:
    var decals: Array = Art.TILES["decals"]
    for i in count:
        var tile: Texture2D = Art.tile(decals[1 + randi() % 2])
        var vel := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(70.0, 180.0)
        puff(tile, pos, color, 20.0, 0.7, false, vel, 4.0)


func scorch(pos: Vector2, size: float) -> void:
    _scorches.append({ "pos": pos, "size": size, "rot": randf() * TAU, "t": 12.0, "life": 12.0 })
    if _scorches.size() > 40:
        _scorches.pop_front()


func _shake(amount: float) -> void:
    if main != null:
        main.shake(amount)


# --- Signal handlers -------------------------------------------------------


func _on_arc(from: Vector2, to: Vector2) -> void:
    _arcs.append({ "a": from, "b": to, "t": 0.22 })
    pixels(Element.Kind.SHOCK, to, 6, 110.0, 4.0)
    _glow(to, 50.0, Color(1.0, 0.97, 0.6, 0.3), 0.2)


func _on_reaction(reaction_name: String, position: Vector2, color: Color) -> void:
    # Reactions speak through their visuals; only events that need words get text.
    if reaction_name in ["ELITE", "Shield broken!", "Shield restored!", "Path opened!"]:
        _texts.append({ "pos": position + Vector2(0, -30), "text": reaction_name, "color": color, "t": 0.95, "life": 0.95 })
    Sfx.reaction(reaction_name)
    match reaction_name:
        "Chain Lightning":
            sig_shock(position, 120.0, 1.6)
            sig_wet(position, 50.0, 0.5)
            _sparks(position, 8)
            _glow(position, 90.0, Color(1, 1, 0.8, 0.3), 0.2)
            _shake(3.0)
        "Steam":
            # A scalding white cloud billowing up off a snuffed splash.
            for n in 45:
                var off := Vector2(randf_range(-55.0, 55.0), randf_range(-20.0, 20.0))
                _px(position + off, Vector2(randf_range(-25.0, 25.0), randf_range(-70.0, -25.0)), randf_range(0.9, 1.6), randf_range(3.0, 5.0), randf_range(0.3, 0.45), B.SMOKE, PAL_STEAM, false)
            sig_wet(position, 90.0, 0.9)
            sig_fire(position, 50.0, 0.4)
            outline(position, 130.0, PAL_STEAM, 0.3)
            _shake(2.0)
        "Deep Freeze":
            sig_ice(position, 100.0, 1.4)
            _spikes(position, 5, 26.0, Element.Kind.ICE, PI * 0.8, 0.5)
            sig_wet(position, 40.0, 0.4)
            linger(position, 50.0, 12, Element.Kind.ICE, true)
            _glow(position, 90.0, Color(0.8, 0.95, 1.0, 0.3), 0.3)
            _shake(3.0)
        "Inferno":
            sig_fire(position, 130.0, 1.5)
            sig_oil(position, 70.0, 0.8)
            for n in 8:
                ember(position + Vector2(randf_range(-50.0, 50.0), randf_range(-10.0, 10.0)))
            smoke(position, 10, 30.0)
            scorch(position, 120.0)
            _shake(5.0)
        "Ignition":
            sig_shock(position, 70.0, 0.8)
            sig_fire(position, 70.0, 1.0)
            sig_oil(position, 50.0, 0.5)
            scorch(position, 70.0)
            _shake(3.0)
        "Fire Nova":
            outline(position, 130.0, Element.Kind.FIRE, 0.35)
            sig_fire(position, 70.0, 1.0)
            for k in 8:
                var fp := position + Vector2.RIGHT.rotated(TAU * float(k) / 8.0 + randf_range(-0.2, 0.2)) * Vector2(1.0, 0.6) * randf_range(70.0, 110.0)
                _tongue(fp, 3 + randi() % 3, randf_range(-100.0, -60.0), randf_range(0.35, 0.55), randf_range(3.0, 4.0))
            for n in 30:
                var d := Vector2.RIGHT.rotated(randf() * TAU)
                _px(position + d * 8.0, d * randf_range(150.0, 320.0) + Vector2(0, -30.0), randf_range(0.3, 0.55), randf_range(3.0, 4.0), randf_range(0.45, 0.65), B.FIRE, Element.Kind.FIRE, true)
            smoke(position, 12, 50.0)
            for n in 8:
                ember(position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20.0, 90.0))
            scorch(position, 220.0)
            _shake(9.0)
        "Frost Nova":
            outline(position, 130.0, Element.Kind.ICE, 0.35)
            sig_ice(position, 90.0, 1.3)
            for k in 4:
                var ip := position + Vector2.RIGHT.rotated(TAU * float(k) / 4.0 + randf_range(-0.3, 0.3)) * Vector2(1.0, 0.6) * randf_range(70.0, 100.0)
                _spikes(ip, 3, 26.0, Element.Kind.ICE, 0.8, 0.4)
            linger(position, 120.0, 16, Element.Kind.ICE, true)
            _glow(position, 140.0, Color(0.7, 0.9, 1.0, 0.25), 0.35)
            _shake(9.0)
        "Shield broken!":
            outline(position, 90.0, 0, 0.3)
            _spikes(position, 8, 36.0, 0, PI * 0.875, 0.12)
            for n in 22:
                var sd := Vector2.RIGHT.rotated(randf() * TAU)
                _px(position + sd * 14.0, sd * randf_range(120.0, 260.0) + Vector2(0, -60.0), randf_range(0.5, 0.8), randf_range(2.0, 4.0), randf_range(0.55, 0.75), B.FALL, 0, true)
            _shake(5.0)
        "Shield restored!":
            spiral(position, 70.0, 26, Element.Kind.ICE)
            sig_holy(position, 60.0, 0.6)
            outline(position, 50.0, 0, 0.4)
        "Path opened!":
            sig_stone(position, 120.0, 2.5)
            outline(position, 120.0, Element.Kind.STONE, 0.3)
            _shake(4.0)
        "ELITE":
            sig_holy(position, 110.0, 1.8)
            outline(position, 60.0, PAL_GOLD, 0.4)
            _glow(position, 100.0, Color(1.0, 0.85, 0.3, 0.3), 0.5)
        _:
            _react_data(reaction_name, position, color)


## Data-driven reactions: element a's signature, element b's at 70%, then an accent per
## thing the reaction does.
func _react_data(reaction_name: String, pos: Vector2, color: Color) -> void:
    var d := Elements.def_by_name(reaction_name)
    var inc := _kind_of(color)
    var pal := _pal_of(color)
    if d.is_empty():
        # Shield cracked, ENRAGED and other one-off events.
        if inc != Element.Kind.NONE:
            signature(inc, pos, 45.0, 0.5)
        else:
            pixels(0, pos, 12, 90.0)
        outline(pos, 45.0, pal, 0.25)
        _shake(3.0)
        return
    var ka: int = d["a"]
    var kb: int = d["b"]
    var acts: Array = d.get("do", [])
    var reach := 0.0
    for act in acts:
        var verb0: String = act[0]
        if verb0 in ["burst", "pull", "push"]:
            reach = maxf(reach, float(act[1]))
        elif verb0 in ["apply", "spread", "cloud"]:
            reach = maxf(reach, float(act[2]))
        elif verb0 == "slow" and act.size() > 3:
            reach = maxf(reach, float(act[3]))
    var sz := clampf(reach * 0.45, 40.0, 80.0) if reach > 0.0 else 50.0
    signature(ka, pos, sz, 1.0)
    signature(kb, pos, sz * 0.7, 0.7)
    var shake := 2.5
    for ac in acts:
        var verb: String = ac[0]
        match verb:
            "burst":
                var br := float(ac[1])
                outline(pos, br, pal, 0.3)
                shake = maxf(shake, 2.0 + br / 60.0)
            "apply", "spread":
                var ak: int = ac[1]
                var ar := float(ac[2])
                if ar <= 0.0:
                    pixels(ak, pos, 6, 50.0)
                else:
                    _scatter(ak, pos, ar, 8)
            "cloud":
                var ck: int = ac[1]
                linger(pos, float(ac[2]), 18, ck, ck in [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.SHOCK, Element.Kind.ICE])
            "burn":
                pixels(Element.Kind.FIRE, pos, 6, 40.0)
            "poison":
                pixels(Element.Kind.POISON, pos, 5, 30.0)
            "bleed":
                pixels(Element.Kind.BLOOD, pos, 6, 80.0)
            "corrode":
                pixels(Element.Kind.ACID, pos, 6, 40.0)
            "freeze":
                _spikes(pos, 4, 28.0, Element.Kind.ICE, 1.2, 0.5)
            "stun":
                orbit(pos, 3, 0)
            "pull":
                spiral(pos, float(ac[1]) * 0.5, 18, Element.Kind.VOID)
            "push":
                streaks(pos, float(ac[1]), 14, Element.Kind.GALE)
            "chain", "chain_state":
                _bolt(pos, Vector2.RIGHT.rotated(randf() * TAU), 40.0, 0.2, 0.7)
                _sparks(pos, 6)
            "purge", "heal_source":
                rise(pos, 10)
            "slow":
                var sr := float(ac[3]) if ac.size() > 3 else 0.0
                if sr > 0.0:
                    _patch(pos, sr * 0.4, kb, 6, 0.22, 1.6)
            "decay":
                spiral(pos, 45.0, 14, Element.Kind.VOID)
    if str(d.get("fx", "")) == "light":
        _glow(pos, 80.0, color, 0.25)
    _shake(shake)


## Burst/pull/push/death novas: a thin brief outline, plus a small signature when the
## colour is an element's.
func _on_nova(position: Vector2, radius: float, color: Color) -> void:
    outline(position, radius, _pal_of(color), 0.3)
    var kind := _kind_of(color)
    if kind != Element.Kind.NONE:
        signature(kind, position, clampf(radius * 0.4, 30.0, 70.0), 0.35)


# --- Frame -----------------------------------------------------------------


func _process(delta: float) -> void:
    for list in [_arcs, _rings, _texts, _puffs, _add_puffs, _corpses, _scorches]:
        for i in range(list.size() - 1, -1, -1):
            list[i]["t"] -= delta
            if list[i]["t"] <= 0.0:
                list.remove_at(i)
    for t in _texts:
        if t.has("vel"):
            t["pos"] += t["vel"] * delta
            t["vel"].y += 60.0 * delta   # numbers pop up and settle
        else:
            t["pos"].y -= 34.0 * delta
    for list in [_puffs, _add_puffs]:
        for p in list:
            p["pos"] += p["vel"] * delta
            p["vel"] = p["vel"].move_toward(Vector2.ZERO, 120.0 * delta)
    for i in range(_shapes.size() - 1, -1, -1):
        var sh: Dictionary = _shapes[i]
        var st: float = float(sh["t"]) - delta
        sh["t"] = st
        if st <= 0.0:
            if int(sh["k"]) == SH_SPIKE:
                _crumble(sh)
            _shapes.remove_at(i)
    _step_pixels(delta)
    queue_redraw()
    _add.queue_redraw()
    _ground.queue_redraw()


## One linear pass over the live window of the ring buffer.
func _step_pixels(delta: float) -> void:
    var cnt := _cnt
    if cnt == 0:
        return
    var s0 := _head - cnt + MAX_PIXELS
    var damp_soft := maxf(0.0, 1.0 - 2.0 * delta)
    var damp_fast := maxf(0.0, 1.0 - 6.0 * delta)
    var damp_ring := maxf(0.0, 1.0 - 2.5 * delta)
    var spin := 3.5 * delta
    var shrink := maxf(0.0, 1.0 - 2.4 * delta)
    for j in cnt:
        var i := (s0 + j) % MAX_PIXELS
        var t: float = _pt[i]
        if t <= 0.0:
            continue
        t -= delta
        var b: int = _pb[i]
        var p: Vector2 = _pp[i]
        if t <= 0.0:
            _pt[i] = 0.0
            if (b == B.FIRE and randf() < 0.3) or (b == B.TONGUE and randf() < 0.2):
                _px(p, Vector2(randf_range(-8.0, 8.0), -25.0), randf_range(0.6, 1.0), 3.0, 0.4, B.SMOKE, PAL_SMOKE, false)
            continue
        var v: Vector2 = _pv[i]
        match b:
            B.FIRE:
                v.y -= 90.0 * delta
                v.x += randf_range(-260.0, 260.0) * delta
                v *= damp_soft
            B.EMBER:
                v.y = maxf(v.y - 30.0 * delta, -70.0)
                v.x += randf_range(-120.0, 120.0) * delta
            B.TONGUE:
                # The run of a tongue shares its phase and age, so it sways as one column.
                v.y -= 30.0 * delta
                p.x += sin((_pl[i] - t) * 14.0 + _po[i].x) * 22.0 * delta
            B.BLOOM:
                v.x *= damp_soft
                v.y = lerpf(v.y, -12.0, 1.5 * delta)
                p.x += sin((_pl[i] - t) * 3.0 + _po[i].x) * 14.0 * delta
            B.SHEEN:
                v *= damp_fast
            B.FALL:
                v.x *= damp_soft
                v.y += GRAVITY * 0.7 * delta
            B.SIZZLE:
                p += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
                v = Vector2.ZERO
            B.WHIRL:
                # v = (angle, radius) around the anchor; one turn, then fly off as a streak.
                var wc: Vector2 = _po[i]
                var wl: float = _pl[i]
                v.x += TAU / (wl * 0.6) * delta
                p = wc + Vector2(cos(v.x), sin(v.x) * 0.55) * v.y
                if t < wl * 0.4:
                    _pb[i] = B.GALE
                    v = Vector2(-sin(v.x), cos(v.x) * 0.55).normalized() * randf_range(220.0, 320.0)
                _pv[i] = v
                _pp[i] = p
                _pt[i] = t
                continue
            B.SMOKE:
                v.x = v.x * damp_soft + randf_range(-20.0, 20.0) * delta
                v.y = lerpf(v.y, -22.0, 1.5 * delta)
            B.DRIFT, B.POISON:
                v *= damp_soft
                var ph: float = _po[i].x
                p.x += sin(t * 4.0 + ph) * 16.0 * delta
                if b == B.POISON:
                    p.y -= 8.0 * delta
            B.ACID:
                v *= damp_soft
                v.y -= 40.0 * delta
                p.x += sin(t * 9.0 + _po[i].x) * 8.0 * delta
            B.WET, B.OIL, B.BLOOD, B.STONE:
                v.y += (GRAVITY * 1.6 if b == B.STONE else GRAVITY) * delta
                var a: Vector2 = _po[i]
                if v.y > 0.0 and p.y >= a.y:
                    p.y = a.y
                    if b == B.WET:
                        if a.x >= 0.0:
                            # Splash: two or three droplets, then gone.
                            for k in 2 + randi() % 2:
                                _px(p, Vector2(randf_range(-70.0, 70.0), randf_range(-110.0, -50.0)), 0.3, 2.0, _pa[i], B.WET, _pc[i], false, Vector2(-1.0, p.y))
                        _pt[i] = 0.0
                        continue
                    elif b == B.STONE and a.x < 1.0:
                        v = Vector2(v.x * 0.6, -v.y * 0.35)
                        a.x = 1.0
                        _po[i] = a
                    elif a.x < 0.0:
                        _pt[i] = 0.0   # a splash droplet landing
                        continue
                    else:
                        if b == B.BLOOD:
                            for k in 1 + randi() % 2:
                                _px(p, Vector2(randf_range(-60.0, 60.0), randf_range(-80.0, -40.0)), 0.3, 2.0, _pa[i], B.BLOOD, _pc[i], false, Vector2(-1.0, p.y))
                        # Stick to the floor as a dot that fades out.
                        _pb[i] = B.STUCK
                        v = Vector2.ZERO
                        t = randf_range(1.2, 2.2) if b == B.OIL else randf_range(0.6, 1.2)
                        _pl[i] = t
            B.ICE:
                v *= damp_fast
                if t < _pl[i] * 0.3:
                    v.y += 260.0 * delta   # crumbles
            B.SHOCK:
                p += Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
                v *= damp_fast
            B.VOID:
                var c: Vector2 = _po[i]
                var dv := (p - c).rotated(spin) * shrink
                p = c + dv
                if dv.length_squared() < 9.0:
                    t = 0.0
            B.GALE:
                v *= maxf(0.0, 1.0 - 1.2 * delta)
            B.RING:
                v *= damp_ring
            B.ORBIT:
                v.x += 7.0 * delta
                p = _po[i] + Vector2(cos(v.x), sin(v.x) * 0.45) * v.y
                _pv[i] = v
                _pp[i] = p
                _pt[i] = t
                continue
            B.STUCK:
                _pt[i] = t
                continue
        if b != B.VOID:
            p += v * delta
        _pp[i] = p
        _pv[i] = v
        _pt[i] = t
    # Trim the window from the oldest end while it is dead.
    while _cnt > 0 and _pt[(_head - _cnt + MAX_PIXELS) % MAX_PIXELS] <= 0.0:
        _cnt -= 1


## Draw the pixels of one layer (0 normal, 1 additive) as snapped squares.
func _draw_pixels(canvas: CanvasItem, layer: int) -> void:
    var cnt := _cnt
    var s0 := _head - cnt + MAX_PIXELS
    var flick := randi() % 7
    var has_spark := false
    var last_spark := Vector2.ZERO
    for j in cnt:
        var i := (s0 + j) % MAX_PIXELS
        var t: float = _pt[i]
        if t <= 0.0 or _pk[i] != layer:
            continue
        var b: int = _pb[i]
        var f: float = t / _pl[i]   # 1 at birth, 0 at death
        var s: float = _ps[i]
        var a: float = _pa[i]
        var step := 0               # 0 base, 1 core, 2 edge
        if f > 0.75:
            step = 1
        elif f < 0.3:
            step = 2
        match b:
            B.FIRE, B.EMBER:
                if f > 0.45:
                    step = 1 if (i + flick) % 3 == 0 else 0
                else:
                    step = 0 if (i + flick) % 2 == 0 else 2
                s = maxf(1.0, s * (0.4 + 0.6 * f))
            B.SMOKE:
                s *= 1.0 + 0.9 * (1.0 - f)
                step = 0 if f > 0.4 else 2
            B.WET, B.STUCK, B.OIL, B.BLOOD, B.STONE:
                step = 1 if b == B.WET and (i + flick) % 9 == 0 else 0
            B.ICE:
                if f < 0.3:
                    s = maxf(1.0, s * f / 0.3)
            B.SHOCK:
                step = 1 if (i + flick) % 3 != 0 else 0
            B.HOLY:
                step = 1 if f > 0.5 else (0 if f > 0.25 else 2)
            B.ACID:
                if f < 0.15:
                    s += 2.0      # the bubble pops
                    a *= 0.6
                    step = 1
            B.RING, B.GALE, B.WHIRL:
                step = 0 if f > 0.4 else 2
            B.TONGUE:
                step = int(_po[i].y)
                if (i + flick) % 5 == 0:
                    step = 1 if step == 0 else 0
                if f < 0.35:
                    step = 2
                s = maxf(1.0, s * (0.5 + 0.5 * f))
            B.BLOOM:
                step = int(_po[i].y) if f > 0.3 else 2
                s *= 1.0 + 0.7 * (1.0 - f)
            B.SHEEN:
                step = 1 if (i + flick) % 11 == 0 else 0
                a *= minf(1.0, f * 2.0)
            B.SIZZLE:
                step = 1 if (i + flick) % 2 == 0 else 0
        if f < 0.3:
            a *= 0.55
        var c: Color = _pal[_pc[i] * 3 + step]
        c.a = a
        var p: Vector2 = _pp[i]
        s = floorf(s + 0.5)
        if b == B.SHEEN:
            var sw := s * 3.0
            var sh := maxf(1.0, floorf(s * 0.5))
            canvas.draw_rect(Rect2(floorf(p.x - sw * 0.5), floorf(p.y - sh * 0.5), sw, sh), c)
            continue
        if b == B.GALE or b == B.WHIRL:
            var v: Vector2 = _pv[i]
            if b == B.WHIRL:
                v = Vector2(-sin(v.x), cos(v.x) * 0.55) * 200.0
            var ln := clampf(v.length() * 0.05, s, 14.0)
            if absf(v.x) >= absf(v.y):
                canvas.draw_rect(Rect2(floorf(p.x - ln * 0.5), floorf(p.y - s * 0.5), ln, s), c)
            else:
                canvas.draw_rect(Rect2(floorf(p.x - s * 0.5), floorf(p.y - ln * 0.5), s, ln), c)
            continue
        var x := floorf(p.x - s * 0.5)
        var y := floorf(p.y - s * 0.5)
        canvas.draw_rect(Rect2(x, y, s, s), c)
        if b == B.STUCK and _pc[i] == Element.Kind.OIL and s >= 3.0:
            canvas.draw_rect(Rect2(x, y, 1.0, 1.0), Color(_pal[_pc[i] * 3 + 1], a))   # glossy glint
        elif b == B.SHOCK:
            if has_spark and p.distance_squared_to(last_spark) < 900.0:
                var mid := (p + last_spark) * 0.5 + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
                var ac := Color(_pal[_pc[i] * 3 + 1], 0.5)
                canvas.draw_line(last_spark, mid, ac, 1.0)
                canvas.draw_line(mid, p, ac, 1.0)
            last_spark = p
            has_spark = true


func _draw_puffs(list: Array, canvas: CanvasItem) -> void:
    for p in list:
        var k: float = 1.0 - p["t"] / p["life"]
        var tex: Texture2D = p["tex"]
        var s: float = p["size"] * (0.55 + 0.65 * k) / tex.get_width()
        var col: Color = p["color"]
        col.a *= 1.0 - k * k
        canvas.draw_set_transform(p["pos"], p["rot"] + k * p["spin"], Vector2(s, s))
        canvas.draw_texture(tex, -tex.get_size() / 2.0, col)
    canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## Short-lived vector shapes: bolts, ice spikes, light rays, collapse lines, void discs.
func _draw_shapes() -> void:
    for sh in _shapes:
        var life: float = sh["life"]
        var e: float = life + float(sh["d"]) - float(sh["t"])
        if e < 0.0:
            continue
        var k := clampf(e / life, 0.0, 1.0)
        match int(sh["k"]):
            SH_BOLT:
                var pts: PackedVector2Array = sh["pts"]
                var bw: float = sh["w"]
                var ba := (1.0 - k) * randf_range(0.6, 1.0)
                draw_polyline(pts, Color(1.0, 0.9, 0.4, ba * 0.45), maxf(2.0, 5.0 * bw))
                draw_polyline(pts, Color(1.0, 1.0, 0.85, ba * MAX_ALPHA), maxf(1.0, 1.5 * bw))
            SH_SPIKE:
                var sa: Vector2 = sh["a"]
                var sb: Vector2 = sh["b"]
                var grow: float = sh["grow"]
                var g := clampf(e / grow, 0.0, 1.0)
                g = 1.0 - (1.0 - g) * (1.0 - g)
                var tip := sa.lerp(sb, g)
                var spal: int = sh["pal"]
                var sw: float = sh["w"]
                var cnt := maxi(1, int(sa.distance_to(tip) / 3.0))
                for m in cnt + 1:
                    var q := float(m) / float(cnt)
                    var sp := sa.lerp(tip, q)
                    var ss := floorf(lerpf(sw, 2.0, q) + 0.5)
                    var sc: Color = _pal[spal * 3 + (1 if q > 0.6 else 0)]
                    sc.a = 0.6
                    draw_rect(Rect2(floorf(sp.x - ss * 0.5), floorf(sp.y - ss * 0.5), ss, ss), sc)
                if g >= 1.0:
                    var ga := MAX_ALPHA if int(e * 20.0) % 3 != 0 else 0.4
                    draw_rect(Rect2(floorf(tip.x) - 1.0, floorf(tip.y) - 1.0, 2.0, 2.0), Color(1, 1, 1, ga))
                    if e - grow < 0.1:
                        draw_line(tip + Vector2(-3, 0), tip + Vector2(3, 0), Color(1, 1, 1, 0.6), 1.0)
                        draw_line(tip + Vector2(0, -3), tip + Vector2(0, 3), Color(1, 1, 1, 0.6), 1.0)
            SH_RAY:
                var ra: Vector2 = sh["a"]
                var rb: Vector2 = sh["b"]
                var rg := clampf(e / float(sh["grow"]), 0.0, 1.0)
                var rc: Color = sh["c"]
                var rw: float = sh["w"]
                var rend := ra.lerp(rb, rg)
                var fade := 1.0 - k
                draw_line(ra, rend, Color(rc, 0.2 * fade), rw * 3.0)
                draw_line(ra, rend, Color(rc, MAX_ALPHA * fade), rw)
            SH_COLLAPSE:
                var cc: Vector2 = sh["c"]
                var ca: Vector2 = sh["a"]
                var outer := cc + (ca - cc) * (1.0 - k * k)
                var inner := outer.move_toward(cc, float(sh["len"]))
                draw_line(outer, inner, Color(0.85, 0.65, 1.0, MAX_ALPHA * (1.0 - 0.5 * k)), 1.0 if (int(e * 30.0) % 2 == 0) else 2.0)
            SH_DISC:
                var dc: Vector2 = sh["c"]
                var dr: float = sh["r"]
                var rr := dr * minf(1.0, k / 0.2) * (1.0 - smoothstep(0.55, 1.0, k))
                if rr >= 1.0:
                    draw_circle(dc, rr, Color(0.06, 0.02, 0.1, 0.55))
                    draw_arc(dc, rr, 0.0, TAU, 32, Color(0.75, 0.5, 1.0, 0.6), 1.0)


func _draw_scorches(canvas: CanvasItem) -> void:
    var tex: Texture2D = Art.PARTICLES["scorch"]
    for s in _scorches:
        var k: float = s["t"] / s["life"]
        var sc: float = s["size"] / tex.get_width()
        canvas.draw_set_transform(s["pos"], s["rot"], Vector2(sc, sc))
        canvas.draw_texture(tex, -tex.get_size() / 2.0, Color(0, 0, 0, 0.55 * minf(1.0, k * 3.0)))
    canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw() -> void:
    for c in _corpses:
        var k: float = 1.0 - c["t"] / c["life"]
        var tex: Texture2D = c["tex"]
        var sx: float = c["scale"] * (1.0 - 0.5 * k) * (-1.0 if c["flip"] else 1.0)
        var sy: float = c["scale"] * (1.0 - 0.7 * k)
        var col: Color = c["color"]
        col = col.darkened(0.5 * k)
        col.a = 1.0 - k
        draw_set_transform(c["pos"] + Vector2(0, 6.0 * k), c["rot"] * k, Vector2(sx, sy))
        draw_texture(tex, -tex.get_size() / 2.0, col)
    draw_set_transform_matrix(Transform2D.IDENTITY)
    _draw_puffs(_puffs, self)
    _draw_pixels(self, 0)
    _draw_shapes()
    for a in _arcs:
        var alpha: float = clampf(a["t"] / 0.22, 0.0, 1.0)
        var pts := PackedVector2Array()
        var from: Vector2 = a["a"]
        var to: Vector2 = a["b"]
        pts.append(from)
        for i in range(1, 6):
            var p: Vector2 = from.lerp(to, float(i) / 6.0)
            p += (to - from).orthogonal().normalized() * randf_range(-12.0, 12.0)
            pts.append(p)
        pts.append(to)
        draw_polyline(pts, Color(1.0, 0.9, 0.4, alpha * 0.6), 6.0)
        draw_polyline(pts, Color(1.0, 1.0, 0.85, alpha), 2.0)
    for r in _rings:
        # Thin outline that tracks the pixel ring (same exponential ease), at most 30% alpha.
        var life: float = r["life"]
        var el: float = life - r["t"]
        var k: float = el / life
        var col: Color = r["color"]
        col.a = minf(col.a, 0.3) * (1.0 - k)
        var rr: float = r["r"] * (1.0 - exp(-2.5 * el)) / (1.0 - exp(-2.5 * life))
        draw_arc(r["pos"], maxf(rr, 2.0), 0.0, TAU, 48, col, 1.0)
    for t in _texts:
        var elapsed: float = t["life"] - t["t"]
        var pop: float = clampf(elapsed / 0.12, 0.0, 1.0)
        var col: Color = t["color"]
        col.a = clampf(t["t"] / 0.5, 0.0, 1.0)
        var size := int(t.get("size", 20) + 6 * pop)
        draw_string(Art.FONT, t["pos"] + Vector2(-99, 1), t["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, Color(0, 0, 0, col.a * 0.8))
        draw_string(Art.FONT, t["pos"] + Vector2(-100, 0), t["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, col)
