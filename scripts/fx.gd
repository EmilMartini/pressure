class_name Fx
extends Node2D
## Immediate-mode effects. The core is a pixel particle system in the spirit of falling-sand
## games: squares of 2-5 world px in a 3-step palette per element (base, light core, dark
## edge), translucent so the floor and enemies stay readable under a burst, each moving by
## a behaviour (fire rises, water falls and splashes, oil sticks, void spirals in...).
## Also lightning arcs, ring outlines, floating text, corpses, bone bits and floor scorches.

const MAX_PUFFS := 120
const MAX_TEXTS := 48
const MAX_PIXELS := 700   # ring buffer: a new pixel past the cap overwrites the oldest
const MAX_ALPHA := 0.75

## Pixel behaviours.
enum B { FIRE, SMOKE, WET, ICE, SHOCK, OIL, POISON, ACID, BLOOD, VOID, HOLY, GALE, STONE, RING, DRIFT, ORBIT, EMBER, STUCK }

## Palette ids 0..12 are Element.Kind (0 = NONE = white); the extras follow.
const PAL_SMOKE := 13
const PAL_STEAM := 14
const PAL_GOLD := 15
const GRAVITY := 560.0

var main: Main
var _arcs: Array = []      # { a, b, t }
var _rings: Array = []     # { pos, r, color, t, life }  thin outlines that follow the pixel rings
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


## An expanding hollow ring of pixels that reaches `r` at the end of `life`, plus a faint outline.
func ring(pos: Vector2, r: float, pal: int, count := 40, life := 0.45, outline := true) -> void:
    var speed := r * 2.5 / (1.0 - exp(-2.5 * life))
    for n in count:
        var d := Vector2.RIGHT.rotated(TAU * float(n) / float(count) + randf_range(-0.05, 0.05))
        _px(pos + d * 3.0, d * speed * randf_range(0.94, 1.0), life * randf_range(0.85, 1.0), 2.0, randf_range(0.4, 0.55), B.RING, pal, true)
    if outline:
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
            ring(pos, size * 0.5, pal, clampi(int(size / 4.0), 12, 32), maxf(life, 0.2), false)
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


## Thin wrapper for older callers (bomber): an element ring of pixels, no sheet.
func blast(pos: Vector2, radius: float, color: Color, _life := 0.55) -> void:
    var kind := _kind_of(color)
    pixels(kind, pos, 24, radius * 0.9, 10.0)
    if kind == Element.Kind.FIRE:
        smoke(pos, 8, 16.0)
        for k in 6:
            ember(pos + Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 10.0)))


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
            pixels(Element.Kind.SHOCK, position, 28, 170.0, 8.0)
            pixels(Element.Kind.WET, position, 10, 90.0)
            ring(position, 60.0, Element.Kind.SHOCK, 32, 0.3)
            _glow(position, 90.0, Color(1, 1, 0.8, 0.3), 0.2)
            _shake(3.0)
        "Steam":
            for n in 40:
                var off := Vector2(randf_range(-50.0, 50.0), randf_range(-20.0, 20.0))
                _px(position + off, Vector2(randf_range(-25.0, 25.0), randf_range(-70.0, -25.0)), randf_range(0.9, 1.6), randf_range(3.0, 5.0), randf_range(0.3, 0.45), B.SMOKE, PAL_STEAM, false)
            pixels(Element.Kind.WET, position, 12, 120.0)
            ring(position, 130.0, PAL_STEAM, 40, 0.45)
            _shake(2.0)
        "Deep Freeze":
            shards(position, 8, 34.0)
            linger(position, 50.0, 16, Element.Kind.ICE, true)
            ring(position, 55.0, Element.Kind.ICE, 32, 0.35)
            _glow(position, 80.0, Color(0.8, 0.95, 1.0, 0.3), 0.3)
            _shake(3.0)
        "Inferno":
            ring(position, 90.0, Element.Kind.FIRE, 48, 0.5)
            for n in 50:
                var off := Vector2(randf_range(-45.0, 45.0), randf_range(-15.0, 15.0))
                _element_px(Element.Kind.FIRE, position + off, Vector2(randf_range(-40.0, 40.0), randf_range(-60.0, 0.0)))
            smoke(position, 16, 30.0)
            for n in 10:
                ember(position + Vector2(randf_range(-40.0, 40.0), randf_range(-10.0, 10.0)))
            pixels(Element.Kind.OIL, position, 8, 120.0)
            scorch(position, 120.0)
            _shake(5.0)
        "Ignition":
            pixels(Element.Kind.SHOCK, position, 16, 160.0)
            pixels(Element.Kind.FIRE, position, 30, 70.0, 12.0)
            ring(position, 60.0, Element.Kind.FIRE, 32, 0.35)
            smoke(position, 6, 12.0)
            scorch(position, 70.0)
            _shake(3.0)
        "Fire Nova":
            ring(position, 130.0, Element.Kind.FIRE, 48, 0.5)
            ring(position, 90.0, Element.Kind.SHOCK, 32, 0.4, false)
            for n in 60:
                var d := Vector2.RIGHT.rotated(randf() * TAU)
                _px(position + d * 8.0, d * randf_range(150.0, 320.0) + Vector2(0, -30.0), randf_range(0.35, 0.65), randf_range(3.0, 5.0), randf_range(0.45, 0.65), B.FIRE, Element.Kind.FIRE, true)
            smoke(position, 20, 50.0)
            for n in 12:
                ember(position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20.0, 90.0))
            scorch(position, 220.0)
            _shake(9.0)
        "Frost Nova":
            ring(position, 130.0, Element.Kind.ICE, 48, 0.5)
            shards(position, 12, 40.0)
            linger(position, 120.0, 24, Element.Kind.ICE, true)
            _glow(position, 140.0, Color(0.7, 0.9, 1.0, 0.25), 0.35)
            _shake(9.0)
        "Shield broken!":
            ring(position, 90.0, 0, 40, 0.4)
            for n in 24:
                var d := Vector2.RIGHT.rotated(randf() * TAU)
                _px(position + d * 14.0, d * randf_range(200.0, 420.0), randf_range(0.5, 0.8), randf_range(2.0, 4.0), randf_range(0.55, 0.75), B.ICE, 0, true)
            _shake(5.0)
        "Shield restored!":
            spiral(position, 70.0, 30, Element.Kind.ICE)
            ring(position, 50.0, 0, 32, 0.6)
            rise(position, 8, 14.0)
        "Path opened!":
            pixels(Element.Kind.STONE, position, 40, 180.0, 20.0)
            smoke(position, 16, 30.0, Element.Kind.STONE)
            ring(position, 120.0, 0, 44, 0.5)
            _shake(4.0)
        "ELITE":
            rise(position, 30, 22.0)
            ring(position, 60.0, PAL_GOLD, 36, 0.5)
            _glow(position, 100.0, Color(1.0, 0.85, 0.3, 0.3), 0.5)
        _:
            _react_data(reaction_name, position, color)


## Data-driven reactions: the visual follows what the reaction does.
func _react_data(reaction_name: String, pos: Vector2, color: Color) -> void:
    var d := Elements.def_by_name(reaction_name)
    var inc := _kind_of(color)
    var pal := _pal_of(color)
    if d.is_empty():
        # Shield cracked, ENRAGED and other one-off events.
        pixels(inc, pos, 12, 90.0)
        ring(pos, 45.0, pal, 24, 0.35)
        return
    var ka: int = d["a"]
    var kb: int = d["b"]
    var shake := 3.0
    for act in d.get("do", []):
        var verb: String = act[0]
        match verb:
            "burst":
                var br := float(act[1])
                ring(pos, br, pal, clampi(32 + int(br / 12.0), 32, 48), 0.45)
                pixels(ka, pos, 8, br * 0.6)
                pixels(kb, pos, 8, br * 0.6)
                shake = maxf(shake, 2.0 + br / 60.0)
            "apply", "spread":
                var ak: int = act[1]
                var ar := float(act[2])
                if ar <= 0.0:
                    pixels(ak, pos, 8, 50.0)
                else:
                    ring(pos, ar, ak, clampi(24 + int(ar / 20.0), 24, 40), 0.8)
                    pixels(ak, pos, 6, 60.0)
            "cloud":
                var ck: int = act[1]
                linger(pos, float(act[2]), 26, ck, ck in [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.SHOCK, Element.Kind.ICE])
            "burn":
                pixels(Element.Kind.FIRE, pos, 10, 50.0)
            "poison":
                pixels(Element.Kind.POISON, pos, 8, 50.0)
            "bleed":
                pixels(Element.Kind.BLOOD, pos, 8, 90.0)
            "corrode":
                pixels(Element.Kind.ACID, pos, 8, 50.0)
            "freeze":
                shards(pos, 7, 26.0)
            "stun":
                orbit(pos, 3, 0)
            "pull":
                spiral(pos, float(act[1]) * 0.6, 28, pal)
            "push":
                streaks(pos, float(act[1]), 24, pal)
            "chain", "chain_state":
                pixels(Element.Kind.SHOCK, pos, 10, 110.0)
            "purge", "heal_source":
                rise(pos, 14)
            "slow":
                var sr := float(act[3]) if act.size() > 3 else 0.0
                if sr > 0.0:
                    ring(pos, sr, pal, 24, 0.9, false)
            "decay":
                spiral(pos, 45.0, 16, Element.Kind.VOID)
            "damage":
                pixels(inc, pos, 6, 70.0)
    # A small accent from the table's fx key.
    match str(d.get("fx", "")):
        "smoke":
            smoke(pos, 6, 14.0)
        "flame":
            pixels(Element.Kind.FIRE, pos, 8, 40.0)
        "spark":
            pixels(Element.Kind.SHOCK, pos, 8, 120.0)
        "magic":
            for n in 6:
                _px(pos + Vector2(randf_range(-14.0, 14.0), randf_range(-8.0, 8.0)), Vector2(0, randf_range(-50.0, -25.0)), randf_range(0.5, 0.8), 2.0, 0.7, B.HOLY, pal, true)
        "light":
            _glow(pos, 80.0, color, 0.25)
        "twirl":
            spiral(pos, 40.0, 10, pal)
    _shake(shake)


func _on_nova(position: Vector2, radius: float, color: Color) -> void:
    ring(position, radius, _pal_of(color), clampi(32 + int(radius / 12.0), 32, 48), 0.5)
    var kind := _kind_of(color)
    if kind != Element.Kind.NONE:
        pixels(kind, position, 10, radius * 0.5, 8.0)


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
            if b == B.FIRE and randf() < 0.3:
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
            B.RING, B.GALE:
                step = 0 if f > 0.4 else 2
        if f < 0.3:
            a *= 0.55
        var c: Color = _pal[_pc[i] * 3 + step]
        c.a = a
        var p: Vector2 = _pp[i]
        s = floorf(s + 0.5)
        if b == B.GALE:
            var v: Vector2 = _pv[i]
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
