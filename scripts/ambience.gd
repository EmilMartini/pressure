class_name Ambience
extends Node2D
## A room's ambient life, by theme (see Themes): a small pixel system of its own (never
## more than CAP live pixels, each one post-process cell big) plus the room's fixtures:
##   crypt   drifting dust, cobwebs in the floor corners, flickering wall torches with glows
##   ruins   ceiling drips that land as tiny puddles (Materials WATER), fireflies, spores
##           (moss patches that burn are laid by Room as a thin oil film, see GrassLayer)
##   frozen  falling snow, frost glints, breath puffs from the players now and then
##           (ice sheets are laid by Room through Materials.lay_still)
##   forge   rising embers, a low heat shimmer pulse (PostFx.heat_pulse), glowing floor
##           cracks, flame braziers, lava pools that keep a patch of fire lit (forced
##           Materials fire: burns walkers, lights oil, never spreads over bare floor)
##   void    violet motes, small rifts that bend the picture (PostFx.set_rift), wisps
##           drifting to the room centre
##   sanctum warm dust and torches (the hub)
## Sound: the theme's ambient bed lives in Sfx (so it carries across rooms and crossfades
## on a new floor); this node claims it on entering and releases it on leaving. Ceiling
## drips that land also tick quietly in the world.
## Counts scale down with post-processing off and grow a little with the run's spectacle
## (Fx.spectacle). Pixels are drawn over everything but are single cells at low alpha, so
## they never hide a shot or a body; lights and lava glows are additive and faint.

const CAP := 110
const K_DRIFT := 0     # slow wander (dust, motes, spores)
const K_FALL := 1      # straight fall (snow)
const K_RISE := 2      # rising with a wobble (embers)
const K_BLINK := 3     # stays put, pulses (glints, fireflies)
const K_WISP := 4      # drifts to the room centre
const K_DRIP := 5      # falls to a floor line, then splashes
const K_PUFF := 6      # breath: rises and spreads a little

var theme := "crypt"
var area := Rect2(-560, -360, 1120, 720)
var room: Room = null
var lights: Array = []          # [pos, kind] kind: "torch" / "brazier"
var lava: Array[Rect2] = []
var rifts: Array[Vector2] = []

var _tx := 2.3                  # one texel / screen cell in world units
var _k := 1.0                   # count scale
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _acc: Dictionary = {}       # spawner name -> accumulated count
var _timers: Dictionary = {}    # one-shot cadences (drips, heat, breath)
var _drip_n := 0
var _webs: Array = []           # [corner, dir x, dir y]
var _cracks: Array = []         # PackedVector2Array polylines (forge)

var _pp := PackedVector2Array()
var _pv := PackedVector2Array()
var _pa := PackedVector2Array()     # anchor (drip floor line, wisp start)
var _pt := PackedFloat32Array()     # life left
var _pl := PackedFloat32Array()     # life at spawn
var _ps := PackedFloat32Array()     # size in texels
var _pk := PackedByteArray()        # kind
var _pg := PackedByteArray()        # 1 = additive
var _pc := PackedColorArray()

var _floor_fix: FixLayer
var _wall_fix: FixLayer
var _glow: GlowLayer


func _init(p_room: Room = null, p_theme: String = "crypt", p_area: Rect2 = Rect2()) -> void:
    room = p_room
    theme = p_theme
    name = "Ambience"
    if room != null:
        area = room.rect
    elif p_area.has_area():
        area = p_area
    z_index = 25
    z_as_relative = false


func _ready() -> void:
    var cam := get_viewport().get_camera_2d()
    _tx = Themes.texel(cam.zoom.x if cam != null else 1.3)
    _rng.seed = hash(area) + hash(theme)
    if room != null and room.data != null:
        _rng.seed = hash(room.data.pos) * 7 + hash(theme)
    _k = 1.0 if Settings.flag("post_fx") else 0.6
    if room != null and room.main != null and "fx" in room.main and room.main.fx != null:
        _k *= lerpf(0.85, 1.15, clampf((float(room.main.fx.spectacle) - 0.35) / 0.95, 0.0, 1.0))
    _floor_fix = FixLayer.new()
    _floor_fix.amb = self
    _floor_fix.mode = 0
    _floor_fix.z_index = -2
    _floor_fix.z_as_relative = false
    add_child(_floor_fix)
    _wall_fix = FixLayer.new()
    _wall_fix.amb = self
    _wall_fix.mode = 1
    _wall_fix.z_index = -1
    _wall_fix.z_as_relative = false
    add_child(_wall_fix)
    _glow = GlowLayer.new()
    _glow.amb = self
    var m := CanvasItemMaterial.new()
    m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    _glow.material = m
    _glow.z_index = 24
    _glow.z_as_relative = false
    add_child(_glow)
    _make_static()
    _prefill()
    Sfx.set_ambience(theme, self)


func _exit_tree() -> void:
    Sfx.release_ambience(self)
    for i in 2:
        PostFx.set_rift(i, Vector2.ZERO, 0.0, 0.0)


# --- Fixtures --------------------------------------------------------------------


func add_light(pos: Vector2, kind: String) -> void:
    lights.append([pos, kind])


func add_lava(r: Rect2) -> void:
    lava.append(r)


func add_rift(pos: Vector2) -> void:
    rifts.append(pos)


func _make_static() -> void:
    var a := area
    if theme == "crypt" or theme == "sanctum":
        _webs = [[a.position, 1.0, 1.0], [Vector2(a.end.x, a.position.y), -1.0, 1.0],
            [Vector2(a.position.x, a.end.y), 1.0, -1.0], [a.end, -1.0, -1.0]]
    if theme == "forge":
        for k in _rng.randi_range(3, 5):
            var p := Vector2(_rng.randf_range(a.position.x + 80.0, a.end.x - 80.0), _rng.randf_range(a.position.y + 80.0, a.end.y - 80.0))
            if room != null and not room.is_open(p, 20.0):
                continue
            var pts := PackedVector2Array()
            var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
            for i in _rng.randi_range(4, 7):
                pts.append(_snap(p))
                dir = dir.rotated(_rng.randf_range(-0.7, 0.7))
                p += dir * _rng.randf_range(9.0, 16.0)
            _cracks.append(pts)


# --- Pixels ---------------------------------------------------------------------


func live() -> int:
    return _pp.size()


func _spawn(kind: int, pos: Vector2, vel: Vector2, life: float, col: Color, add: bool, size: float = 1.0, anchor := Vector2.ZERO) -> void:
    if _pp.size() >= CAP:
        return
    _pp.append(pos)
    _pv.append(vel)
    _pa.append(anchor)
    _pt.append(life)
    _pl.append(life)
    _ps.append(size)
    _pk.append(kind)
    _pg.append(1 if add else 0)
    _pc.append(col)


func _kill(i: int) -> void:
    var last := _pp.size() - 1
    if i != last:
        _pp[i] = _pp[last]
        _pv[i] = _pv[last]
        _pa[i] = _pa[last]
        _pt[i] = _pt[last]
        _pl[i] = _pl[last]
        _ps[i] = _ps[last]
        _pk[i] = _pk[last]
        _pg[i] = _pg[last]
        _pc[i] = _pc[last]
    _pp.resize(last)
    _pv.resize(last)
    _pa.resize(last)
    _pt.resize(last)
    _pl.resize(last)
    _ps.resize(last)
    _pk.resize(last)
    _pg.resize(last)
    _pc.resize(last)


## `rate` per second, scaled; calls `f` once per whole spawn due.
func _emit(key: String, rate: float, delta: float, f: Callable) -> void:
    var acc: float = _acc.get(key, 0.0) + rate * _k * delta
    while acc >= 1.0:
        acc -= 1.0
        f.call()
    _acc[key] = acc


func _every(key: String, lo: float, hi: float, delta: float) -> bool:
    var left: float = _timers.get(key, _rng.randf_range(lo, hi) * 0.5) - delta
    if left <= 0.0:
        _timers[key] = _rng.randf_range(lo, hi)
        return true
    _timers[key] = left
    return false


func _rand_in(margin: float = 30.0) -> Vector2:
    return Vector2(_rng.randf_range(area.position.x + margin, area.end.x - margin), _rng.randf_range(area.position.y + margin, area.end.y - margin))


func _snap(p: Vector2) -> Vector2:
    return (p / _tx).floor() * _tx


func _prefill() -> void:
    var steps := 24
    for i in steps:
        _tick_spawners(0.25)
        _move(0.25)


func _process(delta: float) -> void:
    _t += delta
    _tick_spawners(delta)
    _move(delta)
    _tick_world(delta)
    queue_redraw()
    _glow.queue_redraw()
    if not lava.is_empty() or not lights.is_empty() or not rifts.is_empty() or not _cracks.is_empty():
        _floor_fix.queue_redraw()
        _wall_fix.queue_redraw()


func _tick_spawners(delta: float) -> void:
    match theme:
        "crypt", "sanctum":
            var dust := Color(0.86, 0.78, 0.62) if theme == "crypt" else Color(1.0, 0.86, 0.55)
            _emit("dust", 3.2, delta, func():
                _spawn(K_DRIFT, _rand_in(), Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-4, 3)), _rng.randf_range(6.0, 10.0), Color(dust, _rng.randf_range(0.18, 0.4)), false))
        "ruins":
            _emit("spore", 1.6, delta, func():
                _spawn(K_DRIFT, _rand_in(), Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-9, -4)), _rng.randf_range(6.0, 9.0), Color(0.74, 0.86, 0.52, _rng.randf_range(0.25, 0.45)), false))
            _emit("firefly", 1.0, delta, func():
                _spawn(K_BLINK, _rand_in(60.0), Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-10, 10)), _rng.randf_range(5.0, 9.0), Color(0.86, 1.0, 0.42, 0.9), true))
        "frozen":
            _emit("snow", 2.4, delta, func():
                var p := Vector2(_rng.randf_range(area.position.x - 60.0, area.end.x), area.position.y - 20.0)
                if _pp.size() < 20:
                    p.y = _rng.randf_range(area.position.y, area.end.y)
                _spawn(K_FALL, p, Vector2(_rng.randf_range(6, 16), _rng.randf_range(22, 36)), 30.0, Color(0.92, 0.96, 1.0, _rng.randf_range(0.45, 0.8)), false))
            _emit("glint", 4.0, delta, func():
                _spawn(K_BLINK, _rand_in(40.0), Vector2.ZERO, 0.6, Color(0.85, 0.95, 1.0, 0.9), true))
        "forge":
            _emit("ember", 9.0, delta, func():
                var p := _rand_in()
                if not lava.is_empty() and _rng.randf() < 0.5:
                    var r: Rect2 = lava[_rng.randi() % lava.size()]
                    p = Vector2(_rng.randf_range(r.position.x, r.end.x), _rng.randf_range(r.position.y, r.end.y))
                elif not lights.is_empty() and _rng.randf() < 0.4:
                    p = (lights[_rng.randi() % lights.size()][0] as Vector2) + Vector2(_rng.randf_range(-6, 6), -20)
                var c := Color(1.0, 0.55, 0.15, 0.9) if _rng.randf() < 0.7 else Color(1.0, 0.85, 0.35, 0.9)
                _spawn(K_RISE, p, Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-40, -22)), _rng.randf_range(1.4, 2.6), c, true))
        "void":
            _emit("mote", 4.5, delta, func():
                _spawn(K_DRIFT, _rand_in(), Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-8, -2)), _rng.randf_range(5.0, 8.0), Color(0.74, 0.46, 1.0, _rng.randf_range(0.35, 0.7)), true))
            _emit("wisp", 0.6, delta, func():
                var side := _rng.randi() % 4
                var p := _rand_in(20.0)
                match side:
                    0:
                        p.x = area.position.x + 20.0
                    1:
                        p.x = area.end.x - 20.0
                    2:
                        p.y = area.position.y + 20.0
                    _:
                        p.y = area.end.y - 20.0
                _spawn(K_WISP, p, Vector2.ZERO, _rng.randf_range(7.0, 10.0), Color(0.82, 0.62, 1.0, 0.75), true, 2.0, p))
            for r in rifts:
                _emit("rift%d" % hash(r), 1.2, delta, func():
                    var a := _rng.randf() * TAU
                    _spawn(K_WISP, r + Vector2.RIGHT.rotated(a) * 46.0, Vector2.ZERO, 1.6, Color(0.9, 0.7, 1.0, 0.8), true, 1.0, r))


func _move(delta: float) -> void:
    var i := _pp.size() - 1
    var centre := area.get_center()
    while i >= 0:
        _pt[i] -= delta
        if _pt[i] <= 0.0:
            _kill(i)
            i -= 1
            continue
        var k := _pk[i]
        var p := _pp[i]
        var v := _pv[i]
        match k:
            K_DRIFT:
                v += Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)) * delta
                v = v.limit_length(10.0)
            K_FALL:
                if p.y > area.end.y + 10.0:
                    _pt[i] = 0.0
            K_RISE:
                v.x += sin(_t * 4.0 + float(i)) * 20.0 * delta
            K_BLINK:
                v = (v + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-14, 14)) * delta).limit_length(12.0)
            K_WISP:
                var target := centre
                var anchor := _pa[i]
                if anchor.distance_to(centre) > 1.0 and rifts.has(anchor):
                    target = anchor
                var to := target - p
                if to.length() < 6.0:
                    _pt[i] = minf(_pt[i], 0.2)
                v = v.lerp(to.normalized() * 34.0 + to.orthogonal().normalized() * sin(_t * 2.0 + float(i)) * 8.0, minf(1.0, delta * 1.5))
            K_DRIP:
                v.y += 520.0 * delta
                if p.y >= _pa[i].y:
                    _land_drip(_pa[i])
                    _pt[i] = 0.0
            K_PUFF:
                v *= 1.0 - minf(1.0, delta * 1.6)
        _pv[i] = v
        _pp[i] = p + v * delta
        i -= 1


func _land_drip(at: Vector2) -> void:
    if _t > 1.0:
        Sfx.play_at("drip", at, -2.0 if theme == "crypt" else 0.0)
    for s in 3:
        _spawn(K_PUFF, at, Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-40, -18)), 0.35, Color(0.62, 0.78, 0.95, 0.75), false)
    _drip_n += 1
    if room != null and room.materials != null and _drip_n % 3 == 0:
        room.materials.stamp(Element.Kind.WET, at, 7.0, 40)


## Things that touch the world: drips, breath, heat, lava fire, rifts.
func _tick_world(delta: float) -> void:
    match theme:
        "ruins":
            if _every("drip", 1.1, 2.4, delta):
                var at := _rand_in(60.0)
                if room == null or room.is_open(at, 8.0):
                    _spawn(K_DRIP, at - Vector2(0, 90), Vector2(0, 40), 3.0, Color(0.68, 0.84, 1.0, 0.85), false, 1.0, at)
        "frozen":
            if _every("breath", 2.2, 4.0, delta):
                for pl in _players():
                    var p := pl as Node2D
                    if p == null or not ("alive" in p) or not bool(p.get("alive")):
                        continue
                    var head := p.global_position - global_position + Vector2(_rng.randf_range(-3, 3), -26)
                    for s in 4:
                        _spawn(K_PUFF, head, Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-22, -10)), _rng.randf_range(0.7, 1.1), Color(0.9, 0.95, 1.0, 0.45), false)
        "forge":
            if Settings.flag("post_fx") and _every("heat", 5.0, 8.0, delta):
                PostFx.heat_pulse(0.22, 2.0)
            if not lava.is_empty() and room != null and room.materials != null and _every("lava", 0.4, 0.4, delta):
                for r in lava:
                    var c := r.get_center()
                    var rad := minf(r.size.x, r.size.y) * 0.5
                    room.materials.ignite(c - Vector2(r.size.x * 0.22, 0), rad, true)
                    room.materials.ignite(c + Vector2(r.size.x * 0.22, 0), rad, true)
        "void":
            if Settings.flag("post_fx"):
                for i in mini(2, rifts.size()):
                    PostFx.set_rift(i, global_position + rifts[i], 70.0, 0.32 + 0.08 * sin(_t * 1.3 + float(i)))


func _players() -> Array:
    if room != null and room.main != null and "players" in room.main:
        return room.main.players
    return get_tree().get_nodes_in_group("players") if is_inside_tree() else []


# --- Drawing ------------------------------------------------------------------------


func _draw() -> void:
    for i in _pp.size():
        if _pg[i] == 1:
            continue
        _draw_px(self, i)


func _draw_px(ci: CanvasItem, i: int) -> void:
    var c := _pc[i]
    var k := _pk[i]
    var life := _pl[i]
    var left := _pt[i]
    var a := c.a * minf(1.0, left / 0.6) * minf(1.0, (life - left) / 0.4)
    if k == K_BLINK:
        a *= 0.5 + 0.5 * sin(_t * 6.0 + float(i) * 1.7)
        if life < 1.0:
            a = c.a * sin(PI * (1.0 - left / life))
    if a <= 0.02:
        return
    var s := _ps[i] * _tx
    ci.draw_rect(Rect2(_snap(_pp[i]), Vector2(s, s)), Color(c, a))


## Floor fixtures (mode 0: lava, glowing cracks, cobwebs, rift holes) and wall fixtures
## (mode 1: torches, braziers).
class FixLayer extends Node2D:
    var amb: Ambience
    var mode := 0
    func _draw() -> void:
        if mode == 0:
            amb._draw_floor_fix(self)
        else:
            amb._draw_wall_fix(self)


class GlowLayer extends Node2D:
    var amb: Ambience
    func _draw() -> void:
        amb._draw_glow(self)


func _draw_floor_fix(ci: CanvasItem) -> void:
    var web := Color(0.78, 0.76, 0.80, 0.28)
    for w in _webs:
        var c: Vector2 = w[0]
        var dx: float = w[1]
        var dy: float = w[2]
        for s in 5:
            var ang := float(s) / 4.0 * PI * 0.5
            ci.draw_line(c, c + Vector2(cos(ang) * dx, sin(ang) * dy) * 46.0, web, 1.0)
        for ring in [14.0, 26.0, 38.0]:
            var pts := PackedVector2Array()
            for s in 5:
                var ang := float(s) / 4.0 * PI * 0.5
                pts.append(c + Vector2(cos(ang) * dx, sin(ang) * dy) * (ring + (2.0 if s % 2 == 1 else 0.0)))
            ci.draw_polyline(pts, web, 1.0)
    if not lava.is_empty():
        var lava_list := [[String(Themes.LAVA_FRAMES[int(_t * 3.0) % Themes.LAVA_FRAMES.size()]), 1.0]]
        for r in lava:
            ci.draw_rect(r.grow(_tx), Color(0.10, 0.04, 0.03))
            Themes.draw_tiles(ci, lava_list, r, global_position, _tx, 77, Color(1.0, 0.9, 0.85))
            ci.draw_rect(r, Color(0.16, 0.05, 0.02), false, _tx)
    for r in rifts:
        var pulse := 0.5 + 0.5 * sin(_t * 2.0)
        ci.draw_circle(r, 11.0, Color(0.02, 0.0, 0.05))
        ci.draw_arc(r, 11.0 + pulse * 2.0, 0.0, TAU, 20, Color(0.62, 0.34, 0.95, 0.8), _tx)


func _draw_wall_fix(ci: CanvasItem) -> void:
    for l in lights:
        var p: Vector2 = l[0]
        var kind := String(l[1])
        var frames: Array = Themes.TORCH_FRAMES if kind == "torch" else Themes.BRAZIER_FRAMES
        var fps := 8.0 if kind == "torch" else 10.0
        var f := int(_t * fps + p.x * 0.37) % frames.size()
        var t: Texture2D = Themes.tex(String(frames[f]))
        var size := Vector2(32, 32) * _tx
        ci.draw_texture_rect(t, Rect2(_snap(p - size / 2.0), size), false, Color(0.95, 0.9, 0.86))


func _draw_glow(ci: CanvasItem) -> void:
    var amb: Color = Themes.def(theme)["ambient"]
    var light_tex: Texture2D = Art.PARTICLES["light"]
    for l in lights:
        var p: Vector2 = l[0]
        var flick := 0.8 + 0.12 * sin(_t * 9.0 + p.x) + 0.08 * sin(_t * 23.0 + p.y)
        var g := 150.0 if String(l[1]) == "torch" else 190.0
        ci.draw_texture_rect(light_tex, Rect2(p + Vector2(-g / 2.0, -g / 2.0 + 10.0), Vector2(g, g)), false, Color(amb, 0.16 * flick))
    for r in lava:
        var g2 := maxf(r.size.x, r.size.y) * 2.4
        ci.draw_texture_rect(light_tex, Rect2(r.get_center() - Vector2(g2, g2) / 2.0, Vector2(g2, g2)), false, Color(1.0, 0.42, 0.12, 0.2 + 0.05 * sin(_t * 3.0)))
    for pts in _cracks:
        var pulse := 0.45 + 0.25 * sin(_t * 1.7 + float((pts as PackedVector2Array).size()))
        ci.draw_polyline(pts, Color(1.0, 0.38, 0.08, pulse), _tx)
    for r in rifts:
        ci.draw_texture_rect(light_tex, Rect2(r - Vector2(60, 60), Vector2(120, 120)), false, Color(0.55, 0.25, 0.95, 0.14))
    for i in _pp.size():
        if _pg[i] == 1:
            _draw_px(ci, i)
