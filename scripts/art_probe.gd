class_name ArtProbe
extends Node
## Headless art-pass probe (design doc "Art direction", rollout 2026-11-10):
##   godot --headless --path . res://scenes/main.tscn -- --art-probe --instance=N [--art-fight=a,l,s]
## Builds one cleared 1000 x 600 arena per region theme (four doors, the plain `open`
## layout, then `four_pillars`), and with no renderer works out on a 2 px grid what the
## dressing does to the floor's luminance (Rec. 709, the clarity tool's `_lum`):
##   floor_l      mean fight-floor luminance: the theme's tiles through floor_tint, the
##                FLAT_FLOOR fight values and the floor_wash veil, sampled per cell
##   view%        share of the 800 x 450 view at the 1.6 camera (centred) the dressing touches
##   interior%    the same inside the lanes and the centre clearing (ArtPass.in_lane)
##   B_old/B_new  mean |floor luminance with the dressing in a fight - without it| over the floor,
##                old fight (layers at 30%, none at all for regions without a recipe) and new
##                (the fight grade). A body or a shot drawn opaque over the floor changes the
##                clarity metric by at most this much on average (|E - F'| - |E - F| <= |F' - F|).
##   p99          the 99th percentile of the same over 500 enemy-sized discs (r 14 px)
## Prints [ART-PROBE] per room and quits. Only this probe's own test save is touched.

const THEMES := ["crypt", "ruins", "garden", "cistern", "frozen", "forge", "sanctum", "void"]
const CELL := 2.0

var main: Main
var _floor: PackedFloat32Array
var _w := 0
var _h := 0
var _origin := Vector2.ZERO


func _init(m: Main) -> void:
    main = m


func _ready() -> void:
    await get_tree().create_timer(0.3).timeout
    var centre := Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2)
    var fk := ArtPass.fight_k()
    print("[ART-PROBE] fight grade alpha=%.2f lum=%.2f sat=%.2f (luminance factor %.3f; old fade 0.300)" % [fk.x, fk.y, fk.z, fk.x * fk.y])
    for layout in ["open", "four_pillars"]:
        for i in THEMES.size():
            var th: String = THEMES[i]
            main.floor_number = 2
            main.region_id = Regions.for_theme(th)
            main.rooms = main._shot_rooms(centre, { "layout": layout, "size": 1 })
            main.enter_room(centre, Vector2i.ZERO)
            await get_tree().process_frame
            await get_tree().process_frame
            _measure(main.current, th, layout, fk)
    get_tree().quit()


func _lum(c: Color) -> float:
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Per-pixel fight-floor luminances of the theme's tiles (weighted), after tint, FLAT_FLOOR
## (fight values: luminance' = mid * (1 - contrast) + contrast * l) and the wash veil.
func _floor_samples(th: String) -> PackedFloat32Array:
    var d := Themes.def(th)
    var tint: Color = d["floor_tint"]
    var wash: Color = d.get("floor_wash", Color(0, 0, 0, 0))
    var base: Array = ArtPass._floor_base if not ArtPass._floor_base.is_empty() else [0.5, 0.6, 0.08]
    var con := float(base[1])
    var mid := float(base[2])
    var wl := mid * (1.0 - con) + con * _lum(wash)
    var out := PackedFloat32Array()
    for e in d["floor"]:
        var img := Image.load_from_file(ProjectSettings.globalize_path(Themes.ROOT + String(e[0])))
        if img == null:
            continue
        img.convert(Image.FORMAT_RGBA8)
        var reps := maxi(1, int(float(e[1]) * 4.0))
        for y in range(0, img.get_height(), 2):
            for x in range(0, img.get_width(), 2):
                var c := img.get_pixel(x, y)
                var t := Color(minf(1.0, c.r * tint.r), minf(1.0, c.g * tint.g), minf(1.0, c.b * tint.b))
                var l := mid * (1.0 - con) + con * _lum(t)
                l = l * (1.0 - wash.a) + wl * wash.a
                for r in reps:
                    out.append(l)
    return out


# --- A tiny rasterizer: primitives [kind, rect or points, lum, alpha, graded] ----------


var _prims: Array = []


func _rect(r: Rect2, c: Color, a: float, graded: bool) -> void:
    _prims.append([0, r, _lum(c), a * c.a, graded])


func _soft(r: Rect2, c: Color, a: float, graded: bool) -> void:
    _prims.append([1, r, _lum(c), a * c.a, graded])


func _line(pts: PackedVector2Array, c: Color, a: float, w: float, graded: bool) -> void:
    for k in range(1, pts.size()):
        var seg := Rect2(pts[k - 1], Vector2.ZERO).expand(pts[k]).grow(w * 0.5)
        _prims.append([2, [pts[k - 1], pts[k], w * 0.5, seg], _lum(c), a * c.a, graded])


func _collect(room: Room) -> void:
    _prims.clear()
    var lv := room.get_node_or_null("Living") as ArtPass.Living
    var rd: ArtPass.RoomDressing = null
    for c in room.get_children():
        if c is ArtPass.RoomDressing and (c as ArtPass.RoomDressing).mode == 0:
            rd = c
    var tx := Themes.texel(room._zoom())
    if rd != null:
        var r := rd.recipe
        for s in rd.stains:
            var rad: float = s[1]
            _soft(Rect2(s[0] - Vector2(rad, rad * 0.7), Vector2(rad * 2.0, rad * 1.4)), r["stain"], 0.55, false)
        for m in rd.moss:
            var rad: float = m[1]
            _soft(Rect2(m[0] - Vector2(rad, rad * 0.6), Vector2(rad * 2.0, rad * 1.2)), r["moss"], 0.7, false)
        for c in rd.cracks:
            _line(c, Color.BLACK, 0.55, tx, false)
        for rb in rd.rubble:
            var s: float = float(rb[1]) * tx
            _rect(Rect2(rb[0] - Vector2(tx, tx), Vector2(s + 2.0 * tx, s + tx)), Color(0.02, 0.02, 0.02), 0.9, false)
            _rect(Rect2(rb[0], Vector2(s, s - tx)), (r["stone"] as Color) * float(rb[2]), 1.0, false)
        for b in rd.bones:
            _rect(Rect2(b[0] - Vector2(4, 3) * tx, Vector2(8, 5) * tx), Color(0.05, 0.05, 0.05), 0.5, false)
            _rect(Rect2(b[0] - Vector2(3, 1) * tx, Vector2(6, 2) * tx), r["bone"], 1.0, false)
        for p in rd.pools:
            _soft(Rect2(p - Vector2(80, 50), Vector2(160, 100)), r.get("shafts", Color.WHITE), 0.10, false)
            for k in 22:
                var a := float(k) * 2.4
                _rect(Rect2(p + Vector2(cos(a), sin(a) * 0.62) * 40.0, Vector2(tx, tx * 2.0)), (r["moss"] as Color).lightened(0.3), 1.0, false)
    if lv != null:
        var r := lv.recipe
        var mc: Color = r["moss"]
        var ac: Color = r.get("accent", Color.WHITE)
        var leaf: Array = r.get("leaf", [Color(0.3, 0.26, 0.12)])
        for w in lv.wash:
            var p: Vector2 = w[1]
            var sz: Vector2 = w[2]
            match String(w[0]):
                "slab":
                    var rr := Rect2(p - sz * tx / 2.0, sz * tx)
                    _rect(rr, Color.BLACK, 0.07, true)
                    _line(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y), rr.position]), Color.BLACK, 0.26, tx, true)
                "specks":
                    for q in (w[4] as PackedVector2Array):
                        _rect(Rect2(q, Vector2(tx, tx)), leaf[int(w[3]) % leaf.size()], 0.30, true)
                "streak":
                    _line(w[4], leaf[int(w[3]) % leaf.size()], 0.16, tx, true)
                "vein":
                    _line(w[4], r["stain"], 0.40, tx, true)
                "crack":
                    _line(w[4], Color.BLACK, 0.30, tx, true)
                "smear":
                    _soft(Rect2(p - Vector2(sz.x, sz.x * 0.6), Vector2(sz.x * 2.0, sz.x * 1.2)), r["stain"], 0.30, true)
                "drift":
                    _soft(Rect2(p - Vector2(sz.x, sz.x * 0.5), Vector2(sz.x * 2.0, sz.x)), leaf[0], 0.07, true)
        if lv.sigil > 0:
            for i in 40:
                var a := TAU * float(i) / 40.0
                _rect(Rect2(Vector2(cos(a) * 66.0, sin(a) * 40.0), Vector2(tx, tx)), Color.BLACK, 0.24 if i % 2 == 0 else 0.12, true)
                _rect(Rect2(Vector2(cos(a) * 30.0, sin(a) * 18.0), Vector2(tx, tx)), Color.BLACK, 0.16, true)
            for i in lv.sigil:
                var a := TAU * float(i) / float(lv.sigil) + 0.3
                _line(PackedVector2Array([Vector2(cos(a) * 34.0, sin(a) * 20.0), Vector2(cos(a) * 62.0, sin(a) * 37.0)]), Color.BLACK, 0.16, tx, true)
        for pc in lv.pieces:
            if pc["k"] == "moss":
                _soft(Rect2(pc["p"] - Vector2(84, 48), Vector2(168, 96)), mc, float(r.get("mat_a", 0.45)), true)
        for l in lv.litter:
            _rect(Rect2(l[0], Vector2(tx * 2.0, tx)), leaf[int(l[1]) % leaf.size()], 0.8, true)
        for c in lv.cracks:
            _line(c, Color.BLACK, 0.35, tx, true)
        for pb in lv.pebbles:
            var s: float = float(pb[1]) * tx
            _rect(Rect2(pb[0] - Vector2(tx, tx) * 0.5, Vector2(s + tx, s)), Color(0.02, 0.02, 0.02), 0.7, true)
            _rect(Rect2(pb[0], Vector2(s, s - tx * 0.5)), (r["stone"] as Color).darkened(0.15), 1.0, true)
        if lv.landmark != Vector2.INF:
            for i in 14:
                var a := TAU * float(i) / 14.0
                var q: Vector2 = lv.landmark + Vector2(cos(a) * 30.0, sin(a) * 18.0)
                _rect(Rect2(q - Vector2(3, 2) * tx, Vector2(6, 4) * tx), Color(0.03, 0.03, 0.03), 0.8, true)
                _rect(Rect2(q - Vector2(2, 2) * tx, Vector2(5, 3) * tx), (r["stone"] as Color).darkened(0.1), 1.0, true)
            _soft(Rect2(lv.landmark - Vector2(24, 14), Vector2(48, 28)), Color.BLACK, 0.45, true)
        for pc in lv.pieces:
            var p: Vector2 = pc["p"]
            match String(pc["k"]):
                "grass":
                    _rect(Rect2(p - Vector2(tx, 4.0 * tx), Vector2(3.0 * tx, 4.0 * tx)), mc.lightened(0.25), 0.8, true)
                "stalk":
                    _rect(Rect2(p - Vector2(0, 5.0 * tx), Vector2(2.0 * tx, 5.0 * tx)), mc.lightened(0.18), 0.8, true)
                "fern":
                    _rect(Rect2(p - Vector2(3, 0) * tx, Vector2(7, 1) * tx), Color.BLACK, 0.35, true)
                    _rect(Rect2(p - Vector2(2, 3) * tx, Vector2(5, 3) * tx), mc.lightened(0.15), 0.8, true)
                "shroom":
                    _rect(Rect2(p - Vector2(tx, 3.0 * tx), Vector2(3.0 * tx, tx)), ac, 1.0, true)
                    _rect(Rect2(p - Vector2(0, 2.0 * tx), Vector2(tx, 2.0 * tx)), (r["bone"] as Color).darkened(0.3), 1.0, true)
                    _rect(Rect2(p + Vector2(2.0 * tx, -3.0 * tx), Vector2(3.0 * tx, tx)), ac, 0.6, true)
                "crystal":
                    _soft(Rect2(p - Vector2(7, 3), Vector2(14, 6)), Color.BLACK, 0.30, true)
                    _rect(Rect2(p - Vector2(1.5 * tx, 5.5 * tx), Vector2(4.0 * tx, 6.0 * tx)), Color(0.02, 0.02, 0.05), 0.5, true)
                    _rect(Rect2(p - Vector2(tx, 5.0 * tx), Vector2(3.0 * tx, 5.0 * tx)), ac, 0.75, true)
                "slag":
                    _rect(Rect2(p - Vector2(2.5, 1.5) * tx, Vector2(5, 3) * tx), Color(0.01, 0.01, 0.01), 0.8, true)
                    _rect(Rect2(p - Vector2(2, 1) * tx, Vector2(4, 2) * tx), (r["stone"] as Color).darkened(0.3), 1.0, true)
                "shard":
                    _soft(Rect2(p - Vector2(8, 3), Vector2(16, 6)), Color.BLACK, 0.38, true)
                    _rect(Rect2(p + Vector2(-0.5, -6.5) * tx, Vector2(3, 4) * tx), Color(0.02, 0.0, 0.04), 0.8, true)
                    _rect(Rect2(p + Vector2(0, -6) * tx, Vector2(2, 3) * tx), (r["stone"] as Color).lightened(0.1), 1.0, true)
                "candle":
                    _rect(Rect2(p, Vector2(tx, tx * 3.0)), Color(0.80, 0.76, 0.64), 1.0, true)
                    _rect(Rect2(p - Vector2(0, tx), Vector2(tx, tx)), Color(1.0, 0.80, 0.36), 1.0, true)
    var ch := room.get_node_or_null("Chains") as LivingWorld.Chains
    if ch != null:
        for c in ch.chains:
            var pts: PackedVector2Array = c["pts"]
            var col: Color = c["col"]
            var w := tx * 2.0
            match String(c["k"]):
                "banner": w = float(c["w"]) * tx
                "web": w = tx * 0.5
                "chain", "lantern": w = tx * 1.5
            _line(pts.slice(0, int(c["alive"])), col, 0.55 if c["k"] == "web" else 1.0, w, true)


## Paints the primitives over the floor samples for one fight mode and returns the change map.
func _paint(mode: String, fk: Vector3, floor_l: float, recipe_room: bool) -> PackedFloat32Array:
    var f := _floor.duplicate()
    for pr in _prims:
        var graded: bool = pr[4]
        var l: float = pr[2]
        var a: float = pr[3]
        if graded:
            match mode:
                "old":
                    if not recipe_room:
                        continue    # regions without a recipe faded these out completely
                    a *= 0.30
                "new":
                    a *= fk.x
                    l = floor_l + (l - floor_l) * fk.y
        elif mode == "old" and not recipe_room:
            continue    # no RoomDressing at all where there was no recipe
        var box: Rect2
        if int(pr[0]) == 2:
            box = pr[1][3]
        else:
            box = pr[1]
        var x0 := clampi(int((box.position.x - _origin.x) / CELL), 0, _w - 1)
        var x1 := clampi(int((box.end.x - _origin.x) / CELL), 0, _w - 1)
        var y0 := clampi(int((box.position.y - _origin.y) / CELL), 0, _h - 1)
        var y1 := clampi(int((box.end.y - _origin.y) / CELL), 0, _h - 1)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                var p := _origin + Vector2(float(x) + 0.5, float(y) + 0.5) * CELL
                var k := 1.0
                match int(pr[0]):
                    1:
                        var c := box.get_center()
                        var d := Vector2((p.x - c.x) / (box.size.x * 0.5), (p.y - c.y) / (box.size.y * 0.5)).length()
                        if d >= 1.0:
                            continue
                        k = (1.0 - d) * (1.0 - d)
                    2:
                        var q := Geometry2D.get_closest_point_to_segment(p, pr[1][0], pr[1][1])
                        if q.distance_to(p) > float(pr[1][2]):
                            continue
                var o := y * _w + x
                var aa := a * k
                f[o] = f[o] * (1.0 - aa) + l * aa
    for o in f.size():
        f[o] = absf(f[o] - _floor[o])
    return f


func _measure(room: Room, th: String, layout: String, fk: Vector3) -> void:
    var half := room.room_size / 2.0
    _origin = -half
    _w = int(room.room_size.x / CELL)
    _h = int(room.room_size.y / CELL)
    var samples := _floor_samples(th)
    var rng := RandomNumberGenerator.new()
    rng.seed = 77
    _floor = PackedFloat32Array()
    _floor.resize(_w * _h)
    var sum := 0.0
    for o in _floor.size():
        _floor[o] = samples[rng.randi() % samples.size()] if not samples.is_empty() else 0.1
        sum += _floor[o]
    var floor_l := sum / float(_floor.size())
    _collect(room)
    var old_recipe := th in ["ruins"]
    var d_old := _paint("old", fk, floor_l, old_recipe)
    var d_new := _paint("new", Vector3(fk.x, ArtPass.fight_lum_of(th), fk.z), floor_l, true)
    var d_rest := _paint("rest", fk, floor_l, true)
    var view := Rect2(-400, -225, 800, 450)
    var on_view := 0
    var n_view := 0
    var on_int := 0
    var n_int := 0
    var b_old := 0.0
    var b_new := 0.0
    var n_floor := 0
    for y in _h:
        for x in _w:
            var p := _origin + Vector2(float(x) + 0.5, float(y) + 0.5) * CELL
            if not room.spot_ok_loose(p, 0.0):
                continue
            var o := y * _w + x
            n_floor += 1
            b_old += d_old[o]
            b_new += d_new[o]
            var touched := d_rest[o] > 0.004
            if view.has_point(p):
                n_view += 1
                on_view += 1 if touched else 0
            if ArtPass.in_lane(room, p, 0.0):
                n_int += 1
                on_int += 1 if touched else 0
    # Enemy-sized discs anywhere on the open floor.
    var discs: Array[float] = []
    var discs_old: Array[float] = []
    for i in 500:
        var c := Vector2(rng.randf_range(-half.x + 30, half.x - 30), rng.randf_range(-half.y + 30, half.y - 30))
        if not room.spot_ok_loose(c, 14.0):
            continue
        var s_new := 0.0
        var s_old := 0.0
        var n := 0
        for dy in range(-7, 8):
            for dx in range(-7, 8):
                if dx * dx + dy * dy > 49:
                    continue
                var cx := int((c.x - _origin.x) / CELL) + dx
                var cy := int((c.y - _origin.y) / CELL) + dy
                if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
                    continue
                s_new += d_new[cy * _w + cx]
                s_old += d_old[cy * _w + cx]
                n += 1
        if n > 0:
            discs.append(s_new / float(n))
            discs_old.append(s_old / float(n))
    discs.sort()
    discs_old.sort()
    var lv := room.get_node_or_null("Living") as ArtPass.Living
    var ch := room.get_node_or_null("Chains") as LivingWorld.Chains
    print("[ART-PROBE] theme=%s layout=%s floor_l=%.3f pieces=%d wash=%d chains=%d view=%.1f%% interior=%.1f%% B_old=%.4f B_new=%.4f p99_old=%.4f p99_new=%.4f" % [
        th, layout, floor_l, lv.pieces.size() if lv != null else 0, lv.wash.size() if lv != null else 0,
        ch.chains.size() if ch != null else 0, 100.0 * on_view / maxf(1.0, n_view), 100.0 * on_int / maxf(1.0, n_int),
        b_old / maxf(1.0, n_floor), b_new / maxf(1.0, n_floor),
        discs_old[int(discs_old.size() * 0.99)] if not discs_old.is_empty() else 0.0, discs[int(discs.size() * 0.99)] if not discs.is_empty() else 0.0])
