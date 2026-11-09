class_name LivingWorld
extends RefCounted
## The living world (design doc "Art direction", living world; research in
## design/Living world visuals research.md): the room answers the elements and the player.
##   River    deep water drawn as flowing water: a flow map from the layout's river lines
##            (two noise layers cross-faded along it), depth from the bank, foam at the
##            banks, ripples and wakes from bodies, shots and drips. It reads the Materials
##            grid: ice stops the flow, shock crackles across it, fire and steam boil it.
##            `river_carry` (setting, off by default) lets it carry oil, blood, poisoned
##            water and ash downstream (a gameplay change: Emil's call).
##   Chains   Rain World style point chains: vines, banners and cobwebs on the top wall, iron
##            chains; gale and blasts swing them, void pulls them, fire burns them segment by
##            segment, ice stiffens them, shock lights them; they grow back out of a fight.
##   Critters beetles and rats that flee from the player and from bangs, burn, freeze, scatter
##            from shock and tumble in a gale; never towards the player, never hostile colours.
##   Vents    steam vents that puff every few seconds, hiss harder near fire, are capped by ice.
## Everything is drawing only: nothing here changes a fight (river carrying aside).
## All of it draws under the bodies (z -2 / -1) except the critters, and none of it uses the
## hostile signature (black outline, red rim).

## A room-wide gust (rest only): a wave of wind crosses the room every 14 to 24 s; plants,
## chains and critters lean into it. `gust_x` is the wave's x, `gust_dir` its direction.
static var gust_x := INF
static var gust_dir := 1.0


static func gust_at(x: float) -> float:
    if gust_x == INF:
        return 0.0
    var d := (x - gust_x) / 90.0
    return gust_dir * exp(-d * d)


static var _noise: ImageTexture = null


## A 64 px seamless value-noise texture, built once in code.
static func noise_tex() -> ImageTexture:
    if _noise != null:
        return _noise
    var rng := RandomNumberGenerator.new()
    rng.seed = 7177
    var lat := 8
    var g := PackedFloat32Array()
    g.resize(lat * lat)
    for i in g.size():
        g[i] = rng.randf()
    var g2 := PackedFloat32Array()
    var lat2 := 16
    g2.resize(lat2 * lat2)
    for i in g2.size():
        g2[i] = rng.randf()
    var img := Image.create(64, 64, false, Image.FORMAT_L8)
    for y in 64:
        for x in 64:
            var v := 0.0
            for o in 2:
                var l := lat if o == 0 else lat2
                var arr := g if o == 0 else g2
                var fx := float(x) / 64.0 * float(l)
                var fy := float(y) / 64.0 * float(l)
                var x0 := int(fx) % l
                var y0 := int(fy) % l
                var x1 := (x0 + 1) % l
                var y1 := (y0 + 1) % l
                var tx := fx - floorf(fx)
                var ty := fy - floorf(fy)
                tx = tx * tx * (3.0 - 2.0 * tx)
                ty = ty * ty * (3.0 - 2.0 * ty)
                var a := lerpf(arr[y0 * l + x0], arr[y0 * l + x1], tx)
                var b := lerpf(arr[y1 * l + x0], arr[y1 * l + x1], tx)
                v += lerpf(a, b, ty) * (0.65 if o == 0 else 0.35)
            img.set_pixel(x, y, Color(v, v, v))
    _noise = ImageTexture.create_from_image(img)
    return _noise


## River colours per floor theme: [deep, shallow, foam, glint].
const RIVER_COLS := {
    "cistern": [Color(0.09, 0.24, 0.30), Color(0.20, 0.42, 0.44), Color(0.74, 0.90, 0.88), Color(0.46, 0.72, 0.72)],
    "garden": [Color(0.12, 0.22, 0.12), Color(0.26, 0.38, 0.18), Color(0.70, 0.78, 0.52), Color(0.48, 0.62, 0.30)],
    "ruins": [Color(0.07, 0.17, 0.24), Color(0.15, 0.30, 0.36), Color(0.66, 0.80, 0.80), Color(0.38, 0.56, 0.64)],
    "frozen": [Color(0.18, 0.32, 0.46), Color(0.38, 0.56, 0.66), Color(0.86, 0.94, 0.98), Color(0.70, 0.84, 0.94)],
    "crypt": [Color(0.08, 0.18, 0.22), Color(0.18, 0.32, 0.34), Color(0.66, 0.78, 0.78), Color(0.42, 0.58, 0.62)],
    "_": [Color(0.09, 0.20, 0.26), Color(0.19, 0.36, 0.40), Color(0.70, 0.84, 0.88), Color(0.46, 0.66, 0.74)],
}


const RIVER_SHADER := """
shader_type canvas_item;
uniform sampler2D flow_tex : filter_linear;    // per Materials cell: RG dir*0.5+0.5, B speed, A depth
uniform sampler2D data : filter_nearest;       // the Materials data texture
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 origin = vec2(0.0);
uniform vec2 grid = vec2(1.0);
uniform float now = 0.0;
uniform float texel = 2.3;
uniform vec3 deep_col = vec3(0.05, 0.13, 0.16);
uniform vec3 shallow_col = vec3(0.15, 0.30, 0.30);
uniform vec3 foam_col = vec3(0.7, 0.85, 0.8);
uniform vec3 glint_col = vec3(0.45, 0.68, 0.62);
uniform vec4 ripples[12];
uniform float fight = 0.0;     // 0 at rest .. 1 in a fight: the river calms to a flat surface
varying vec2 lp;

void vertex() {
    lp = VERTEX;
}

ivec4 cell(ivec2 c) {
    c = clamp(c, ivec2(0), ivec2(grid) - 1);
    return ivec4(texelFetch(data, c, 0) * 255.0 + 0.5);
}

float h21(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 q = (floor(lp / texel) + 0.5) * texel;          // whole texels: on the PostFx grid
    vec2 g = (q - origin) / {CELL}.0;
    vec4 f = texture(flow_tex, g / grid);
    ivec2 c = ivec2(floor(g));
    ivec4 d = cell(c);
    int m = d.x & 15;
    bool ice = m == {ICE};
    int near_ice = 0;
    bool hot = m == {STEAM} || m == {FIRE};
    for (int k = 0; k < 4; k++) {
        ivec2 o = ivec2(k == 0 ? -2 : (k == 1 ? 2 : 0), k == 2 ? -2 : (k == 3 ? 2 : 0));
        int nm = cell(c + o).x & 15;
        near_ice += nm == {ICE} ? 1 : 0;
        hot = hot || nm == {FIRE} || nm == {STEAM};
    }
    float depth = clamp(f.a, 0.0, 1.0);
    float speed = f.b * (1.0 - 0.22 * float(near_ice));
    vec2 fl = (f.rg * 2.0 - 1.0) * speed;
    float t = floor(now * 12.0) / 12.0 / 1.7;           // stepped like pixel-art frames
    float pa = fract(t);
    float pb = fract(t + 0.5);
    float w = abs(pa - 0.5) * 2.0;
    // Streaks stretched along the flow (long along it, thin across), two phases cross-faded.
    vec2 dir = length(fl) > 0.01 ? normalize(fl) : vec2(1.0, 0.0);
    vec2 sq = vec2(dot(q, dir) / 260.0, dot(q, vec2(-dir.y, dir.x)) / 44.0);
    float run = length(fl) * 0.55;
    float n1 = texture(noise_tex, sq - vec2(run * pa, 0.0)).r;
    float n2 = texture(noise_tex, sq - vec2(run * pb, 0.0) + vec2(0.37, 0.61)).r;
    float n = mix(n1, n2, w);
    float n3 = mix(texture(noise_tex, q / 64.0 - fl * pa * 0.35).r, texture(noise_tex, q / 64.0 - fl * pb * 0.35 + 0.5).r, w);
    // Ripples and wakes: rings spreading from where something touched the water.
    float ring = 0.0;
    for (int i = 0; i < 12; i++) {
        vec4 r = ripples[i];
        float age = now - r.z;
        if (r.w <= 0.0 || age < 0.0 || age > 1.1) {
            continue;
        }
        float rad = 4.0 + age * 34.0 * (0.6 + 0.4 * r.w);
        float dd = abs(length(q - r.xy) - rad);
        ring += (1.0 - smoothstep(0.0, texel * 1.2, dd)) * (1.0 - age / 1.1) * r.w;
    }
    vec3 col = mix(shallow_col, deep_col, smoothstep(0.05, 0.85, depth));
    if (ice) {
        // Frozen: a flat pale sheet, cracks, a few still glints; the flow stops.
        float cn = texture(noise_tex, q / 30.0).r;
        col = vec3(0.56, 0.72, 0.82) * (0.92 + 0.12 * cn);
        if (abs(cn - 0.5) < 0.018 || abs(texture(noise_tex, q / 17.0 + 0.3).r - 0.52) < 0.012) {
            col = vec3(0.30, 0.42, 0.52);
        }
        if (h21(floor(q / (texel * 3.0))) > 0.985) {
            col = vec3(0.92, 0.97, 1.0);
        }
    } else {
        // Light streaks along the flow, dark troughs, bank foam that breaks up as it moves.
        col = mix(col, glint_col, smoothstep(0.58, 0.72, n) * 0.75 * (0.35 + 0.65 * depth));
        col *= 1.0 - 0.18 * (1.0 - smoothstep(0.25, 0.38, n));
        float band = 1.0 - smoothstep(0.0, 0.38, depth);
        float fo = step(0.66 - band * 0.40, n3) * band;
        col = mix(col, foam_col, fo * 0.8);
        col = mix(col, foam_col, clamp(ring, 0.0, 1.0) * 0.55);
        if (m == {TOXIC}) {
            col = mix(col, vec3(0.30, 0.48, 0.12), 0.45);
            if (h21(floor(q / (texel * 2.0)) + floor(now * 3.0)) > 0.985) {
                col = vec3(0.62, 0.80, 0.30);
            }
        }
        if (hot) {
            // Boiling: lighter, greyer water, bubbles popping.
            col = mix(col, vec3(0.70, 0.76, 0.78), 0.32);
            if (h21(floor(q / (texel * 2.0)) + floor(now * 7.0) * 0.37) > 0.90) {
                col = vec3(0.92, 0.95, 0.96);
            }
        }
    }
    // In a fight the surface goes flat and quiet (readability: bodies and shots read over it;
    // the Materials layer still draws ice, charge and steam on top).
    vec3 calm = deep_col * 0.75;
    col = mix(col, calm, fight * 0.92);
    if (fight < 0.5 && (m == {CHARGED} || ((d.x & 32) != 0 && ice))) {
        // Shock crackles across the surface: hard bright threads re-hashed at 15 Hz.
        float cr = texture(noise_tex, q / 19.0 + vec2(floor(now * 15.0) * 0.173, 0.0)).r;
        if (abs(cr - 0.5) < 0.035) {
            col = mix(col, vec3(1.0, 0.98, 0.62), 0.85);
        }
    }
    COLOR = vec4(col, 1.0);
}
"""


## Deep water as a river. Built once per room from the layout's deep cells and river lines;
## per frame it only sets `now` and the ripple slots.
class River extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var room: Room
    var mats: Materials
    var tx := 2.3
    var cells := PackedInt32Array()      # Materials cells of the river (deep water)
    var flow := PackedVector2Array()     # per entry of `cells`: flow direction * speed
    var _mat: ShaderMaterial
    var _rip: Array = []                 # 12 x Vector4
    var _ri := 0
    var _tick := 0.0
    var _carry_t := 0.0
    var _carry_at := 0
    var _drip_t := 1.0
    var _rng := RandomNumberGenerator.new()
    var _body_t: Dictionary = {}
    var _fade := 0.0

    func _init() -> void:
        name = "River"
        z_index = -2

    func build(p_room: Room, rects: Array) -> void:
        room = p_room
        mats = room.materials
        _rng.seed = hash(room.data.pos) + 31
        var w := mats._w
        var h := mats._h
        var deep := PackedByteArray()
        deep.resize(w * h)
        for r in rects:
            for i in mats.indices_in(r):
                if deep[i] == 0:
                    deep[i] = 1
                    cells.append(i)
        if cells.is_empty():
            return
        # Bank distance: a breadth-first search in from every cell beside dry floor.
        var dist := PackedInt32Array()
        dist.resize(w * h)
        dist.fill(-1)
        var q := PackedInt32Array()
        for i in cells:
            var x := i % w
            var y := i / w
            if x == 0 or y == 0 or x == w - 1 or y == h - 1 or deep[i - 1] == 0 or deep[i + 1] == 0 or deep[i - w] == 0 or deep[i + w] == 0:
                dist[i] = 0
                q.append(i)
        var head := 0
        while head < q.size():
            var i := q[head]
            head += 1
            var x := i % w
            for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
                if j >= 0 and j < w * h and deep[j] == 1 and dist[j] < 0:
                    dist[j] = dist[i] + 1
                    q.append(j)
        # Flow: along the nearest river line (sampled at layout cells), else a slow circling
        # along the banks (pools).
        var lines: Array = room.rivers
        var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
        var cache: Dictionary = {}
        flow.resize(cells.size())
        for k in cells.size():
            var i := cells[k]
            var x := i % w
            var y := i / w
            var dpt := clampf(float(dist[i]) / 5.0, 0.0, 1.0)
            var dir := Vector2.ZERO
            var spd := 0.0
            if not lines.is_empty():
                var key := Vector2i(x / 3, y / 3)
                if cache.has(key):
                    dir = cache[key]
                else:
                    var wp := mats._origin + Vector2(float(x * Materials.CELL), float(y * Materials.CELL))
                    var best := INF
                    for ln in lines:
                        var pts: PackedVector2Array = ln
                        for s in pts.size() - 1:
                            var cp := Geometry2D.get_closest_point_to_segment(wp, pts[s], pts[s + 1])
                            var dd := cp.distance_squared_to(wp)
                            if dd < best:
                                best = dd
                                dir = (pts[s + 1] - pts[s]).normalized()
                    cache[key] = dir
                spd = 0.55 + 0.45 * dpt
            else:
                # Perpendicular to the bank gradient: water circles slowly round the pool.
                var gx := float(_d(dist, deep, i + 1, w, x < w - 1) - _d(dist, deep, i - 1, w, x > 0))
                var gy := float(_d(dist, deep, i + w, w, y < h - 1) - _d(dist, deep, i - w, w, y > 0))
                dir = Vector2(-gy, gx).normalized() if absf(gx) + absf(gy) > 0.0 else Vector2.RIGHT
                spd = 0.18
            flow[k] = dir * spd
            img.set_pixel(x, y, Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, spd, maxf(dpt, 0.02)))
        var sh := Shader.new()
        sh.code = LivingWorld.RIVER_SHADER.format({ "CELL": Materials.CELL, "ICE": Materials.ICE, "STEAM": Materials.STEAM,
            "FIRE": Materials.FIRE, "CHARGED": Materials.CHARGED, "TOXIC": Materials.TOXIC })
        _mat = ShaderMaterial.new()
        _mat.shader = sh
        _mat.set_shader_parameter("flow_tex", ImageTexture.create_from_image(img))
        _mat.set_shader_parameter("data", mats._ttex)
        _mat.set_shader_parameter("noise_tex", LivingWorld.noise_tex())
        _mat.set_shader_parameter("origin", mats._origin)
        _mat.set_shader_parameter("grid", Vector2(w, h))
        _mat.set_shader_parameter("texel", tx)
        var cols: Array = LivingWorld.RIVER_COLS.get(room.theme, LivingWorld.RIVER_COLS["_"])
        for n in 4:
            var c: Color = cols[n]
            _mat.set_shader_parameter(["deep_col", "shallow_col", "foam_col", "glint_col"][n], Vector3(c.r, c.g, c.b))
        for n in 12:
            _rip.append(Vector4(0, 0, -10, 0))
        _mat.set_shader_parameter("ripples", _rip)
        material = _mat
        var rims := RiverRims.new()
        rims.room = room
        add_child(rims)

    func _d(dist: PackedInt32Array, deep: PackedByteArray, j: int, _w: int, ok: bool) -> int:
        if not ok or j < 0 or j >= dist.size() or deep[j] == 0:
            return 0
        return dist[j]

    func ripple(local: Vector2, strength: float) -> void:
        if _mat == null:
            return
        _rip[_ri] = Vector4(local.x, local.y, ArtPass.now(), strength)
        _ri = (_ri + 1) % 12
        _mat.set_shader_parameter("ripples", _rip)

    func _draw() -> void:
        if _mat == null:
            return
        # One rect per layout cell of deep water (the material draws the river in them).
        for r in room._deep_rects:
            draw_rect(r, Color.WHITE)

    func _process(delta: float) -> void:
        if _mat == null:
            return
        _mat.set_shader_parameter("now", ArtPass.now())
        # Mood at rest, clarity in a fight (the art pass rule): the river fades back to the
        # room's own water tiles while a fight runs, so the fight reads as it always did.
        _fade = move_toward(_fade, ArtPass.fight_of(room), delta * 1.2)
        _mat.set_shader_parameter("fight", _fade)
        modulate.a = 1.0 - _fade
        _tick -= delta
        if _tick <= 0.0:
            _tick = 0.1
            _touches()
        if room.active:
            return
        _drip_t -= delta
        if _drip_t <= 0.0:
            # A drip from the ceiling lands somewhere on the river.
            _drip_t = _rng.randf_range(0.6, 1.6)
            var i := cells[_rng.randi() % cells.size()]
            ripple(mats._origin + Vector2(float((i % mats._w) * Materials.CELL), float((i / mats._w) * Materials.CELL)), 0.6)
        if Settings.flag("river_carry") or OS.get_cmdline_user_args().has("--river-carry"):
            _carry_t -= delta
            if _carry_t <= 0.0:
                _carry_t = 0.25
                _carry()

    ## Bodies wading and shots crossing leave rings (a moving body leaves a wake of them).
    func _touches() -> void:
        var tree := get_tree()
        var n := 0
        var bodies: Array = tree.get_nodes_in_group("players")
        var en: Array = EnemyGrid.nodes(tree, &"enemies")
        for k in mini(en.size(), 30):
            if is_instance_valid(en[k]):
                bodies.append(en[k])
        for b in bodies:
            if n >= 3 or not is_instance_valid(b):
                continue
            var nb := b as Node2D
            var v: Variant = nb.get("velocity")
            if not v is Vector2 or (v as Vector2).length() < 25.0:
                continue
            var id := nb.get_instance_id()
            if float(_body_t.get(id, 0.0)) > ArtPass.now():
                continue
            if room.is_deep(nb.global_position):
                _body_t[id] = ArtPass.now() + 0.18
                ripple(nb.global_position - room.global_position, 0.8)
                n += 1
        for s in tree.get_nodes_in_group("player_shots"):
            if n >= 5:
                break
            var ns := s as Node2D
            if ns != null and (ns.get_instance_id() + Engine.get_process_frames()) % 4 == 0 and room.is_deep(ns.global_position):
                ripple(ns.global_position - room.global_position, 0.35)
                n += 1

    ## River carrying (setting `river_carry`, off by default): oil, blood, poisoned water and
    ## ash in the river move one cell downstream, a third of the river a tick.
    func _carry() -> void:
        var w := mats._w
        var count := cells.size()
        var span := maxi(1, count / 3)
        for kk in span:
            var k := (_carry_at + kk) % count
            var i := cells[k]
            var m := int(mats.mat[i])
            if not (m == Materials.OIL or m == Materials.BLOOD or m == Materials.TOXIC or m == Materials.ASH):
                continue
            var f := flow[k]
            if f.length() < 0.3:
                continue
            var dx := int(roundf(f.normalized().x))
            var dy := int(roundf(f.normalized().y))
            var x := i % w + dx
            var y := i / w + dy
            if x < 0 or y < 0 or x >= w or y >= mats._h:
                continue
            var j := y * w + x
            var mj := int(mats.mat[j])
            if mj != Materials.WATER and mj != Materials.NONE:
                continue
            mats._put(j, m, mats.amt[i], mats.life[i])
            mats._put(i, Materials.WATER, 90, 255)
            mats._wake(j)
        _carry_at = (_carry_at + span) % count


## The pool's stone rims again, over the river (the room drew them under it).
class RiverRims extends Node2D:
    var room: Room

    func _draw() -> void:
        var td := Themes.def(room.theme)
        var cs := Room.NAV
        var tx := Themes.texel(room._zoom())
        for i in room.terrain.size():
            if room.terrain[i] != RoomLayouts.T_DEEP:
                continue
            var cx := i % room.nav_w
            var cy := i / room.nav_w
            Themes.pool_rims(self, room.rect.position + Vector2(cx, cy) * cs, cs, tx, not room._terrain_is(cx, cy - 1, RoomLayouts.T_DEEP),
                not room._terrain_is(cx, cy + 1, RoomLayouts.T_DEEP), not room._terrain_is(cx - 1, cy, RoomLayouts.T_DEEP),
                not room._terrain_is(cx + 1, cy, RoomLayouts.T_DEEP), td, (i * 2654435761) & 0xFFFF)


# --- Point chains -------------------------------------------------------------------


## Vines, banners, cobwebs and iron chains as Verlet point chains, stepped at 30 Hz and
## drawn in whole texels. Forces: the room gust, gales, blasts (push), void (pull), bodies
## brushing past. Fire burns vines, banners and webs segment by segment from where it
## touched; the burnt part falls away and grows back out of a fight.
class Chains extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var room: Room = null           # null in the Hollow
    var mats: Materials = null
    var tx := 2.3
    var chains: Array = []          # see add()
    var _acc := 0.0
    var _t := 0.0
    var _touch_t := 0.0
    var _floor_t := 0.0

    func _init() -> void:
        name = "Chains"
        z_index = -1

    ## kind "vine", "banner", "web", "chain"; n points `seg` px apart hanging from `anchor`.
    func add(kind: String, anchor: Vector2, n: int, seg: float, col: Color, width: float = 1.0) -> void:
        var pts := PackedVector2Array()
        for k in n:
            pts.append(anchor + Vector2(0, seg * float(k)))
        chains.append({ "k": kind, "a": anchor, "n": n, "seg": seg, "pts": pts, "old": pts.duplicate(),
            "col": col, "w": width, "alive": n, "burn": -1, "bt": 0.0, "rg": 0.0, "ice": 0.0, "zap": 0.0, "ph": anchor.x * 0.05 })

    func _process(delta: float) -> void:
        _t += delta
        _acc += delta
        if room != null:
            modulate.a = 1.0 - ArtPass.fight_fade(room, 0.75) * ArtPass.fight_of(room)
        var moved := false
        if _acc >= 1.0 / 30.0:
            _acc = minf(_acc - 1.0 / 30.0, 1.0 / 30.0)
            moved = _step(1.0 / 30.0)
        _touch_t -= delta
        if _touch_t <= 0.0:
            _touch_t = 0.07
            _touches()
        _floor_t -= delta
        if _floor_t <= 0.0 and mats != null:
            _floor_t = 0.25
            _read_floor()
        if moved:
            queue_redraw()

    func _step(dt: float) -> bool:
        var calm := ArtPass.fight < 0.5 and (room == null or not room.active)
        for c in chains:
            var pts: PackedVector2Array = c["pts"]
            var old: PackedVector2Array = c["old"]
            var alive: int = c["alive"]
            if float(c["ice"]) > 0.0:
                c["ice"] = float(c["ice"]) - dt
                continue    # frozen stiff
            c["zap"] = maxf(0.0, float(c["zap"]) - dt)
            # Burning: the flame climbs one segment every 0.14 s; what is below it falls.
            if int(c["burn"]) >= 0:
                c["bt"] = float(c["bt"]) - dt
                if float(c["bt"]) <= 0.0:
                    c["bt"] = 0.14
                    var b: int = c["burn"]
                    _fall(pts, b, c)
                    c["alive"] = b
                    alive = b
                    c["burn"] = b - 1 if b > 1 else -1
                    if b <= 1:
                        c["rg"] = 26.0
            elif alive < int(c["n"]) and c["k"] != "web":
                if calm:
                    c["rg"] = float(c["rg"]) - dt
                    if float(c["rg"]) <= 0.0:
                        c["rg"] = 0.4
                        pts[alive] = pts[alive - 1] + Vector2(0, float(c["seg"]))
                        old[alive] = pts[alive]
                        c["alive"] = alive + 1
                        alive += 1
            var breeze := sin(_t * 0.9 + float(c["ph"])) * 0.05 + LivingWorld.gust_at(c["a"].x) * 0.5
            if c["k"] == "web":
                continue    # webs hold their shape (they only burn)
            var stiff := 0.98 if c["k"] == "chain" or c["k"] == "lantern" else 0.95
            for k in range(1, alive):
                var p := pts[k]
                var v := (p - old[k]) * stiff
                old[k] = p
                var g := 0.55 if c["k"] != "web" else 0.05
                pts[k] = p + v + Vector2(breeze * (0.3 if c["k"] == "chain" or c["k"] == "lantern" else 1.0), g) * dt * 30.0 * 0.5
            var seg: float = c["seg"]
            for it in 2:
                pts[0] = c["a"]
                for k in range(1, alive):
                    var d := pts[k] - pts[k - 1]
                    var l := d.length()
                    if l > 0.001:
                        pts[k] = pts[k - 1] + d / l * seg
            c["pts"] = pts
            c["old"] = old
        return true

    func _fall(pts: PackedVector2Array, from: int, c: Dictionary) -> void:
        var fx := _fx()
        if fx != null:
            for k in range(from, mini(int(c["alive"]), from + 1)):
                fx.ember(global_position + pts[k])
                fx.pixels(Element.Kind.OIL, global_position + pts[k], 1, 30.0, 3.0)
        if mats != null and from < int(c["alive"]):
            mats.scorch(global_position + pts[mini(from, pts.size() - 1)] + Vector2(0, 8), 1)

    func _fx() -> Fx:
        var scene := get_tree().current_scene
        if scene != null and "fx" in scene:
            var f: Variant = scene.get("fx")
            if f is Fx and is_instance_valid(f):
                return f as Fx
        return null

    ## Fire under a hanging end lights it; ice stiffens it; shock lights it up.
    func _read_floor() -> void:
        for c in chains:
            var alive: int = c["alive"]
            if alive < 2 or c["k"] == "chain" or c["k"] == "lantern":
                continue
            var tip: Vector2 = (c["pts"] as PackedVector2Array)[alive - 1]
            var m := mats.material_at(global_position + tip)
            if m == Materials.FIRE and int(c["burn"]) < 0:
                ignite(c, alive - 1)
            elif m == Materials.ICE:
                c["ice"] = 3.0
            elif m == Materials.CHARGED:
                c["zap"] = 0.5

    func ignite(c: Dictionary, at: int) -> void:
        if c["k"] == "chain" or c["k"] == "lantern" or int(c["burn"]) >= 0:
            return
        c["burn"] = clampi(at, 1, int(c["alive"]) - 1)
        c["bt"] = 0.14
        c["ice"] = 0.0

    ## Shots and bodies brushing past push the chains; fire, ice and shock shots answer too.
    func _touches() -> void:
        var tree := get_tree()
        var list: Array = []
        for p in tree.get_nodes_in_group("players"):
            list.append([(p as Node2D).global_position, Element.Kind.NONE, 14.0])
        for s in tree.get_nodes_in_group("player_shots"):
            var sp := s as Node2D
            if sp != null:
                list.append([sp.global_position, int(sp.get("element")), 10.0])
        if list.is_empty():
            return
        for c in chains:
            var pts: PackedVector2Array = c["pts"]
            var alive: int = c["alive"]
            if alive < 2:
                continue
            var a: Vector2 = global_position + pts[0]
            var b: Vector2 = global_position + pts[alive - 1]
            var box := Rect2(a, Vector2.ZERO).expand(b).grow(16.0)
            for it in list:
                var at: Vector2 = it[0]
                if not box.has_point(at):
                    continue
                for k in range(1, alive):
                    var d := global_position + pts[k] - at
                    if d.length_squared() < float(it[2]) * float(it[2]):
                        pts[k] += Vector2(signf(d.x) if d.x != 0.0 else 1.0, 0.0) * 2.0
                        var el: int = it[1]
                        if el == Element.Kind.FIRE:
                            ignite(c, k)
                        elif el == Element.Kind.ICE:
                            c["ice"] = 4.0
                        elif el == Element.Kind.SHOCK:
                            c["zap"] = 0.6
                        elif float(c["ice"]) > 0.0 and el != Element.Kind.NONE:
                            # A frozen strand shatters where it is hit.
                            c["ice"] = 0.0
                            var fx := _fx()
                            if fx != null:
                                fx.pixels(Element.Kind.ICE, global_position + pts[k], 3, 40.0, 3.0)
                            c["alive"] = k
                            c["rg"] = 20.0
                        break
            c["pts"] = pts

    ## A push (gale, blast) or a pull (void) at `at` (world) within `r`.
    func force(at: Vector2, r: float, strength: float) -> void:
        for c in chains:
            var pts: PackedVector2Array = c["pts"]
            for k in range(1, int(c["alive"])):
                var d := global_position + pts[k] - at
                var l := d.length()
                if l < r and l > 0.01:
                    pts[k] += d / l * strength * (1.0 - l / r)
            c["pts"] = pts
            c["ice"] = 0.0 if strength > 3.0 else c["ice"]

    func _snap(p: Vector2) -> Vector2:
        return (p / tx).round() * tx

    func _draw() -> void:
        var fire := [Color(1.0, 0.82, 0.35), Color(1.0, 0.52, 0.16)]
        var step := int(_t * 12.0)
        for c in chains:
            var pts: PackedVector2Array = c["pts"]
            var alive: int = c["alive"]
            if alive < 2:
                continue
            var col: Color = c["col"]
            if float(c["ice"]) > 0.0:
                col = col.lerp(Color(0.72, 0.86, 1.0), 0.6)
            if float(c["zap"]) > 0.0 and step % 2 == 0:
                col = col.lerp(Color(0.95, 0.98, 1.0), 0.7)
            var burn: int = c["burn"]
            var jit := Vector2(tx if float(c["zap"]) > 0.0 and step % 2 == 1 else 0.0, 0.0)
            match String(c["k"]):
                "vine":
                    for k in range(1, alive):
                        var a := _snap(pts[k - 1]) + jit
                        var b := _snap(pts[k]) + jit
                        draw_line(a, b, Color(0.02, 0.03, 0.02, 0.85), tx * 2.0)
                        draw_line(a, b, col, tx)
                        if k % 2 == 0:
                            var side := tx if k % 4 == 0 else -tx
                            draw_rect(Rect2(b + Vector2(side, -tx), Vector2(tx * 1.0, tx)), col.lightened(0.25))
                "chain", "lantern":
                    for k in range(alive):
                        var p := _snap(pts[k])
                        var sz := Vector2(tx, tx * 2.0) if k % 2 == 0 else Vector2(tx * 2.0, tx)
                        draw_rect(Rect2(p - sz / 2.0 - Vector2(tx, tx) * 0.5, sz + Vector2(tx, tx)), Color(0.02, 0.02, 0.03, 0.8))
                        draw_rect(Rect2(p - sz / 2.0, sz), col)
                    if c["k"] == "lantern":
                        var lp := _snap(pts[alive - 1]) + Vector2(0, tx)
                        var lt: Texture2D = Art.PARTICLES["light"]
                        var fl := 0.85 + 0.15 * sin(_t * 9.0 + float(c["ph"]))
                        draw_texture_rect(lt, Rect2(lp - Vector2(22, 18), Vector2(44, 44)), false, Color(1.0, 0.72, 0.36, 0.35 * fl))
                        draw_rect(Rect2(lp - Vector2(tx * 3.0, 0), Vector2(tx * 6.0, tx * 7.0)).grow(tx * 0.5), Color(0.02, 0.02, 0.02))
                        draw_rect(Rect2(lp - Vector2(tx * 3.0, 0), Vector2(tx * 6.0, tx * 7.0)), Color(0.22, 0.20, 0.18))
                        draw_rect(Rect2(lp - Vector2(tx * 2.0, -tx * 2.0), Vector2(tx * 4.0, tx * 4.0)), Color(1.0, 0.78, 0.40) * fl)
                        draw_rect(Rect2(lp - Vector2(tx * 0.5, -tx * 3.0), Vector2(tx, tx * 2.0)), Color(1.0, 0.95, 0.75))
                "banner":
                    var wd: float = float(c["w"]) * tx
                    for k in range(alive):
                        var p := _snap(pts[k]) + jit
                        var r := Rect2(p - Vector2(wd / 2.0, 0), Vector2(wd, float(c["seg"]) + tx * 0.5))
                        draw_rect(r.grow(tx * 0.5), Color(0.03, 0.02, 0.02, 0.7))
                        draw_rect(r, col.darkened(0.12 * float(k % 2)))
                        draw_rect(Rect2(r.position + Vector2(tx, 0), Vector2(tx, r.size.y)), col.lightened(0.18))
                        if k == 2:
                            draw_rect(Rect2(p - Vector2(tx, -tx), Vector2(tx * 2.0, tx * 2.0)), Color(0.78, 0.66, 0.34))
                    if alive < int(c["n"]):
                        # A ragged, charred edge where it burned.
                        var p := _snap(pts[alive - 1]) + Vector2(0, float(c["seg"]))
                        for x in range(int(-wd / 2.0 / tx), int(wd / 2.0 / tx)):
                            if (x + alive) % 2 == 0:
                                draw_rect(Rect2(p + Vector2(float(x) * tx, 0), Vector2(tx, tx)), Color(0.08, 0.06, 0.05))
                    else:
                        var p := _snap(pts[alive - 1]) + Vector2(0, float(c["seg"]))
                        draw_colored_polygon(PackedVector2Array([p + Vector2(-wd / 2.0, 0), p + Vector2(wd / 2.0, 0), p + Vector2(0, tx * 3.0)]), col.darkened(0.1))
                "web":
                    var a0 := _snap(pts[0])
                    for k in range(1, alive):
                        draw_line(a0, _snap(pts[k]), Color(col, 0.55), tx * 0.5)
                        if k > 1:
                            draw_line(_snap(pts[k - 1]), _snap(pts[k]), Color(col, 0.4), tx * 0.5)
            if burn >= 0 and burn < alive:
                # The burning segment: small stepped flames, no glow on the floor.
                var p := _snap(pts[burn])
                draw_rect(Rect2(p - Vector2(tx, tx * 2.0), Vector2(tx * 2.0, tx * 2.0)), fire[step % 2])
                draw_rect(Rect2(p + Vector2(0, -tx * 3.0 - float(step % 2) * tx), Vector2(tx, tx)), fire[(step + 1) % 2])


# --- Critters -------------------------------------------------------------------------


## Beetles and rats on the floor: they idle in small hops near the walls and islands, flee
## from the players and from bangs, hide in a fight, burn into a puff, freeze mid-step,
## scatter from shock and tumble in a gale. They never move towards a player, never use red
## or an outline, have no collision and no health.
class Critters extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var room: Room
    var mats: Materials
    var tx := 2.3
    var bugs: Array = []    # {p, home, v, st, t, k}
    var _acc := 0.0
    var _t := 0.0
    var _rng := RandomNumberGenerator.new()
    var _bang := Vector2.INF
    var _bang_t := 0.0

    func _init() -> void:
        name = "GroundCritters"
        z_index = -1

    func plan(p_room: Room, homes: Array) -> void:
        room = p_room
        mats = room.materials
        _rng.seed = hash(room.data.pos) + 77
        for h in homes:
            var hp: Vector2 = h
            if room.spot_ok_loose(hp, 6.0):
                bugs.append({ "p": hp, "home": hp, "v": Vector2.ZERO, "st": "idle", "t": _rng.randf_range(0.5, 2.0), "k": _rng.randi() % 3 })
        if Elements.nova.is_connected(_on_nova) == false:
            Elements.nova.connect(_on_nova)

    func _exit_tree() -> void:
        if Elements.nova.is_connected(_on_nova):
            Elements.nova.disconnect(_on_nova)

    func _on_nova(pos: Vector2, r: float, _c: Color) -> void:
        _bang = pos - global_position
        _bang_t = 0.6 + r * 0.0

    func gale(at: Vector2, r: float) -> void:
        for b in bugs:
            var d: Vector2 = b["p"] - (at - global_position)
            if d.length() < r * 1.4 and b["st"] != "dead":
                b["v"] = d.normalized() * 160.0
                b["st"] = "tumble"
                b["t"] = 0.6

    func _process(delta: float) -> void:
        _t += delta
        _acc += delta
        if _acc < 1.0 / 15.0:
            return
        var dt := _acc
        _acc = 0.0
        _bang_t = maxf(0.0, _bang_t - dt)
        var fight := room.active or ArtPass.fight > 0.5
        var players: Array = []
        for p in get_tree().get_nodes_in_group("players"):
            players.append((p as Node2D).global_position - global_position)
        var half := room.room_size / 2.0 - Vector2(16, 16)
        var fx := _fx()
        for b in bugs:
            var p: Vector2 = b["p"]
            var st: String = b["st"]
            b["t"] = float(b["t"]) - dt
            if st == "dead":
                if float(b["t"]) <= 0.0 and not fight:
                    b["p"] = b["home"]
                    b["st"] = "idle"
                continue
            if Engine.get_process_frames() % 2 == 0:
                var m := mats.material_at(global_position + p)
                if m == Materials.FIRE:
                    b["st"] = "dead"
                    b["t"] = 25.0
                    if fx != null:
                        fx.smoke(global_position + p, 2, 4.0)
                        fx.ember(global_position + p)
                    continue
                elif m == Materials.ICE:
                    b["st"] = "frozen"
                    b["t"] = 1.0
                elif m == Materials.CHARGED and st != "flee":
                    b["st"] = "flee"
                    b["v"] = Vector2.RIGHT.rotated(_rng.randf() * TAU) * 110.0
                    b["t"] = 0.8
            st = b["st"]
            if st == "frozen":
                if float(b["t"]) <= 0.0:
                    b["st"] = "idle"
                continue
            # The nearest threat: a player or a bang.
            var away := Vector2.ZERO
            var near := INF
            for pp in players:
                var d: Vector2 = p - pp
                if d.length() < near:
                    near = d.length()
                    away = d
            if _bang_t > 0.0 and p.distance_to(_bang) < 220.0 and p.distance_to(_bang) < near:
                away = p - _bang
                near = 0.0
            if st == "tumble":
                p += b["v"] * dt
                b["v"] = (b["v"] as Vector2) * 0.85
                if float(b["t"]) <= 0.0:
                    b["st"] = "idle"
            elif near < 100.0 or st == "flee":
                if near < 100.0:
                    var dir := away.normalized() if away.length() > 0.1 else Vector2.RIGHT
                    b["v"] = dir.rotated(_rng.randf_range(-0.4, 0.4)) * (75.0 if b["k"] != 2 else 95.0)
                    b["st"] = "flee"
                    b["t"] = 0.7
                elif float(b["t"]) <= 0.0:
                    b["st"] = "idle"
                p += b["v"] * dt
            elif fight:
                # Hide: back to the home spot by the wall, then still.
                var to: Vector2 = (b["home"] as Vector2) - p
                if to.length() > 3.0:
                    p += to.normalized() * minf(to.length(), 40.0 * dt)
            elif float(b["t"]) <= 0.0:
                # A small hop, never towards a player.
                b["t"] = _rng.randf_range(0.8, 2.4)
                var hop := Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(3.0, 7.0)
                var back: Vector2 = (b["home"] as Vector2) - p
                if back.length() > 30.0:
                    hop = back.normalized() * 6.0
                for pp in players:
                    if hop.dot((pp as Vector2) - p) > 0.0 and p.distance_to(pp) < 220.0:
                        hop = -hop
                p += hop
            p = Vector2(clampf(p.x, -half.x, half.x), clampf(p.y, -half.y, half.y))
            if not room.spot_ok_loose(p, 3.0):
                p = b["p"]
                b["v"] = -(b["v"] as Vector2)
            b["p"] = p
        queue_redraw()

    func _fx() -> Fx:
        var scene := get_tree().current_scene
        if scene != null and "fx" in scene:
            var f: Variant = scene.get("fx")
            if f is Fx and is_instance_valid(f):
                return f as Fx
        return null

    func _draw() -> void:
        var fight := room.active
        for b in bugs:
            if b["st"] == "dead":
                continue
            var p: Vector2 = ((b["p"] as Vector2) / tx).round() * tx
            var k: int = b["k"]
            var moving: bool = b["st"] == "flee" or b["st"] == "tumble"
            var body := Color(0.16, 0.12, 0.09) if k != 2 else Color(0.30, 0.26, 0.22)
            var back := Color(0.30, 0.24, 0.14) if k == 0 else (Color(0.20, 0.24, 0.16) if k == 1 else Color(0.40, 0.36, 0.30))
            if b["st"] == "frozen":
                body = Color(0.55, 0.70, 0.82)
                back = Color(0.80, 0.90, 0.98)
            if fight:
                continue   # hidden under the props and in the wall cracks while a fight runs
            var a := 1.0
            draw_rect(Rect2(p + Vector2(0, tx), Vector2(tx * (2.0 if k != 2 else 3.0), tx * 0.5)), Color(0, 0, 0, 0.3 * a))
            if k != 2:
                draw_rect(Rect2(p, Vector2(tx * 2.0, tx)), Color(body, a))
                draw_rect(Rect2(p, Vector2(tx, tx)), Color(back, a))
                if moving and int(_t * 12.0) % 2 == 0:
                    draw_rect(Rect2(p + Vector2(-tx * 0.5, tx * 0.5), Vector2(tx * 3.0, tx * 0.5)), Color(body, 0.6 * a))
            else:
                var dirx := signf((b["v"] as Vector2).x) if moving else 1.0
                draw_rect(Rect2(p, Vector2(tx * 3.0, tx)), Color(body, a))
                draw_rect(Rect2(p + Vector2(tx * 2.0 if dirx > 0 else 0.0, -tx * 0.5), Vector2(tx, tx * 0.5)), Color(back, a))
                draw_rect(Rect2(p + Vector2(-tx if dirx > 0 else tx * 3.0, tx * 0.5), Vector2(tx, tx * 0.5)), Color(back.darkened(0.2), a))


# --- Steam vents ----------------------------------------------------------------------


## Floor grates that puff steam every few seconds (a smaller puff just before, as a tell);
## faster with fire beside them, capped shut by ice; half as often in a fight. Steam is
## Fx pixels only: nothing lands in the grid.
class Vents extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var room: Room
    var tx := 2.3
    var vents: Array = []   # {p, t, capped}
    var _rng := RandomNumberGenerator.new()

    func _init() -> void:
        name = "Vents"
        z_index = -1

    func plan(p_room: Room, rng: RandomNumberGenerator) -> void:
        room = p_room
        _rng.seed = rng.randi()
        var half := room.room_size / 2.0
        for i in 30:
            if vents.size() >= 2:
                break
            var p := Vector2(rng.randf_range(-half.x + 50, half.x - 50), rng.randf_range(-half.y + 50, half.y - 50))
            if room.spot_ok_loose(p, 18.0) and not ArtPass.in_lane(room, p, 14.0):
                var far := true
                for v in vents:
                    far = far and p.distance_to(v["p"]) > 300.0
                if far:
                    vents.append({ "p": (p / tx).round() * tx, "t": rng.randf_range(1.0, 4.0), "capped": false, "pre": false })

    func _process(delta: float) -> void:
        modulate.a = 1.0 - ArtPass.fight_fade(room, 0.4) * ArtPass.fight_of(room)
        var fx: Fx = null
        var scene := get_tree().current_scene
        if scene != null and "fx" in scene:
            fx = scene.get("fx") as Fx
        for v in vents:
            var gp: Vector2 = global_position + (v["p"] as Vector2)
            var m := room.materials.material_at(gp)
            var was: bool = v["capped"]
            v["capped"] = m == Materials.ICE
            if was != v["capped"]:
                queue_redraw()
            if v["capped"]:
                continue
            var hot := m == Materials.FIRE or room.materials.material_at(gp + Vector2(20, 0)) == Materials.FIRE or room.materials.material_at(gp - Vector2(20, 0)) == Materials.FIRE
            v["t"] = float(v["t"]) - delta * (2.5 if hot else 1.0) * (0.5 if room.active else 1.0)
            if room.active:
                continue   # combat dim: the vents rest while a fight runs
            if float(v["t"]) < 0.5 and not v["pre"] and fx != null:
                v["pre"] = true
                fx.steam(gp + Vector2(0, -2), 2)
            if float(v["t"]) <= 0.0:
                v["t"] = _rng.randf_range(3.0, 6.0)
                v["pre"] = false
                if fx != null:
                    fx.steam(gp + Vector2(0, -2), 6 if not hot else 10)

    func _draw() -> void:
        for v in vents:
            var p: Vector2 = v["p"]
            var r := Rect2(p - Vector2(5, 3) * tx, Vector2(10, 6) * tx)
            draw_rect(r.grow(tx), Color(0.02, 0.02, 0.02, 0.85))
            draw_rect(r, Color(0.07, 0.07, 0.08))
            for k in 4:
                draw_rect(Rect2(r.position + Vector2(tx + float(k) * tx * 2.5, tx), Vector2(tx, r.size.y - tx * 2.0)), Color(0.30, 0.30, 0.32))
            draw_rect(Rect2(r.position, Vector2(r.size.x, tx)), Color(0.45, 0.45, 0.46, 0.8))
            if v["capped"]:
                draw_rect(r, Color(0.72, 0.86, 1.0, 0.6))
