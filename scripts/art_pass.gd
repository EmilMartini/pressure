class_name ArtPass
extends RefCounted
## Art pass (design doc "Art direction"): how good the existing art can look with engine
## work alone. Per region a recipe of light and grade, and rule-placed dressing:
##   lighting   PostFx multiplies the world (layer 0) by ambient + point lights, and adds a
##              faint scatter inside each light so pools read on the dark floor. Lights are
##              ArtPass.Light nodes (group "art_lights") plus one on every player. Saturated
##              bright pixels (fire, element colours, shots under Crisp) count as emissive
##              and are never darkened. Crisp (hostile shots and edges, world text) is a
##              layer above PostFx, so the hostile signature is never lit or darkened.
##   grade      a lift (shadow tint) and a gain (highlight tint) per region, and the
##              vignette's strength.
##   walls      the top wall shows a dark front face under a lit lip; the floor darkens
##              towards every wall (contact shadow).
##   doorways   stone jambs and a lintel shadow around each door, light spilling through
##              an open one (cool) or a red glow through a locked one.
##   props      rule-placed clutter along the walls (rubble, bones, moss, stains, cracks),
##              broken columns in the corners, banners on the top wall; never inside the
##              middle of the floor, never on a doorway, a reserved spot or a blocker.
##   foreground hanging roots over the top wall and corner pillars over the bottom wall,
##              drawn above everything with a little parallax.
## Off with the "lighting" option or `--no-art`; only themes listed in RECIPES get it.
## Everything is drawn in whole texels (Themes.texel) so it sits on the PostFx pixel grid.

const RECIPES := {
    # Rust Ruins: a cool, mossy dusk; warm torches and braziers, green-cyan spill from doors.
    "ruins": {
        "ambient": Color(0.42, 0.54, 0.58),
        "lift": Color(0.0, 0.030, 0.035),
        "gain": Color(1.07, 1.00, 0.86),
        "cap": 1.5,
        "rest_floor": [0.95, 0.9, 0.10],   # Room.FLAT_FLOOR sat, contrast, mid at rest
        "vignette": 1.05,
        "player": [Color(1.0, 0.88, 0.70), 430.0, 0.80, 0.04, 2.5],
        "player_fight": [Color(1.0, 0.92, 0.80), 540.0, 0.70, 0.0, 6.0],
        "shafts": Color(1.0, 0.82, 0.50),
        "fire": Color(1.0, 0.60, 0.28),
        "spill": Color(0.55, 0.95, 0.80),
        "torches": true,
        "moss": Color(0.20, 0.34, 0.16),
        "stone": Color(0.34, 0.33, 0.27),
        "bone": Color(0.70, 0.66, 0.54),
        "stain": Color(0.02, 0.05, 0.03),
        "root": Color(0.05, 0.08, 0.04),
    },
    # The Hollow: hearth-warm, darker corners, the Gate's cold light.
    "hollow": {
        "ambient": Color(0.46, 0.44, 0.52),
        "cap": 1.5,
        "lift": Color(0.025, 0.015, 0.035),
        "gain": Color(1.06, 1.00, 0.90),
        "vignette": 1.0,
        "player": [Color(1.0, 0.86, 0.66), 300.0, 0.45, 0.0, 3.0],
        "fire": Color(1.0, 0.62, 0.30),
        "spill": Color(0.50, 0.95, 1.0),
        "torches": true,
        "moss": Color(0.20, 0.34, 0.16),
        "stone": Color(0.34, 0.33, 0.30),
        "bone": Color(0.70, 0.66, 0.54),
        "stain": Color(0.03, 0.03, 0.04),
        "root": Color(0.05, 0.08, 0.04),
    },
}

## The recipe in use and the node that owns it (a Room or the hub); PostFx lights only
## while the owner is in the tree, so menus and other scenes stay unlit.
static var recipe: Dictionary = {}
static var owner_ref: WeakRef = null
static var critters_ref: WeakRef = null


static func enabled() -> bool:
    if OS.get_cmdline_user_args().has("--no-art"):
        return false
    return Settings.flag("lighting")


## Called by a Room (its theme) or the hub ("hollow"); returns whether the pass is on.
static func use(key: String, owner: Node) -> bool:
    if not enabled() or not RECIPES.has(key):
        if owner_ref != null and owner_ref.get_ref() == owner:
            recipe = {}
        return false
    recipe = RECIPES[key].duplicate()
    # Tuning overrides: --art-amb=v (grey ambient), --art-pl=energy, --art-grade=0.
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--art-amb="):
            var v := float(arg.substr(10))
            recipe["ambient"] = Color(v, v, v)
        elif arg.begins_with("--art-pl="):
            var pl: Array = (recipe["player"] as Array).duplicate()
            pl[2] = float(arg.substr(9))
            recipe["player"] = pl
        elif arg.begins_with("--art-cap="):
            recipe["cap"] = float(arg.substr(10))
        elif arg == "--art-grade=0":
            recipe["lift"] = Color(0, 0, 0)
            recipe["gain"] = Color(1, 1, 1)
    owner_ref = weakref(owner)
    return true


## 0 at rest .. 1 while the owner Room's fight runs: the room's darkness lifts (ambient
## to 1, light capped at 1, so lights only add their faint scatter) and the sun beams
## fade, so fights read exactly as before (design doc "Art direction": the paired
## clarity test). Eases over about a second each way.
static var fight := 0.0


## The fight weight for a room's living layers: ArtPass.fight where the recipe pass runs,
## else 1 while the room's fight runs.
static func fight_of(room: Node) -> float:
    if active() and owner_ref.get_ref() == room:
        return fight
    # Rooms without a light recipe: the same one-second ease, kept per room.
    var want := 1.0 if room is Room and (room as Room).active else 0.0
    var id := room.get_instance_id()
    var now_ms := Time.get_ticks_msec()
    var rec: Array = _nf.get(id, [want, now_ms])
    var v := move_toward(float(rec[0]), want, float(now_ms - int(rec[1])) / 1000.0 * 1.2)
    _nf[id] = [v, now_ms]
    if _nf.size() > 8:
        _nf.clear()
        _nf[id] = [v, now_ms]
    return v

static var _nf: Dictionary = {}


## How far the living layers fade in a fight: to 30% where a light recipe was measured at
## parity (ruins), all the way out in the regions that have no recipe yet (garden, cistern),
## so their fights read exactly as before (design doc "Art direction", living world).
static func fight_fade(room: Node, measured: float) -> float:
    var th := String(room.get("theme")) if room != null and "theme" in room else ""
    return measured if RECIPES.has(th) else 1.0
static var _last_t := -1.0


## Clarity A/B (`--clarity-ab`): lighting off and every dressing node hidden, in place.
static var suppressed := false


static func suppress(on: bool) -> void:
    suppressed = on
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        for n in tree.get_nodes_in_group("art_dressing"):
            (n as CanvasItem).visible = not on


static func active() -> bool:
    if suppressed or recipe.is_empty() or not Settings.flag("lighting") or owner_ref == null:
        return false
    var o: Node = owner_ref.get_ref()
    return o != null and o.is_inside_tree()


## A light for the PostFx pass. `energy` multiplies the world (1 = doubles it at the
## centre), `scatter` adds that much of the colour straight on (visible pools on dark
## floors), `flicker` 0..1 wobbles both like a flame.
class Light extends Node2D:
    var radius := 160.0
    var color := Color(1, 0.7, 0.4)
    var energy := 0.8
    var scatter := 0.05
    var flicker := 0.0
    var hard := 2.0

    func _ready() -> void:
        add_to_group("art_lights")


static func add_light(parent: Node, pos: Vector2, radius: float, col: Color, energy: float, scatter: float, flicker: float = 0.0) -> Light:
    var l := Light.new()
    l.position = pos
    l.radius = radius
    l.color = col
    l.energy = energy
    l.scatter = scatter
    l.flicker = flicker
    parent.add_child(l)
    return l


# --- Rooms ------------------------------------------------------------------------


## The whole room pass: lights on its fixtures, walls, doorways, props and foreground.
static func dress_room(room: Room) -> void:
    if not use(room.theme, room):
        return
    var t0 := Time.get_ticks_usec()
    var r := recipe
    var tx := Themes.texel(room._zoom())
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(room.data.pos) * 7 + room.main.floor_number * 131 + 99
    var half := room.room_size / 2.0
    # Torches along the side and bottom walls, where the theme has none of its own.
    if bool(r.get("torches", false)) and String(Themes.def(room.theme)["light"]) == "":
        var tile := 32.0 * tx
        var n := maxi(2, int(room.room_size.x / 200.0))   # Room._dress_theme's decor slots
        for i in range(1, n):
            var x := -half.x + room.room_size.x * float(i) / float(n)
            if room.data.doors.has(Vector2i.UP) and absf(x) < Room.GAP / 2.0 + tile:
                continue
            room.ambience.add_light(Vector2(x, -half.y - tile * 0.5 + 6.0), "torch")
        for sx in [-1, 1]:
            for fy in [-0.4, 0.4]:
                if room.data.doors.has(Vector2i(sx, 0)) and absf(fy * half.y) < Room.GAP / 2.0 + tile:
                    continue
                room.ambience.add_light(Vector2(float(sx) * (half.x + Room.WALL * 0.5), fy * half.y), "torch")
    # Floor clutter under the materials grid (own effects draw over it); the wall pass
    # (front face, columns, jambs) over the wall tiles. Same plan, two draw modes.
    var layer := RoomDressing.new()
    layer.room = room
    layer.recipe = r
    layer.tx = tx
    layer.z_index = -1
    layer.plan(rng)
    room.add_child(layer)
    room.move_child(layer, 0)
    var walls := RoomDressing.new()
    walls.room = room
    walls.recipe = r
    walls.tx = tx
    walls.z_index = -1
    walls.mode = 1
    walls.columns = layer.columns
    room.add_child(walls)
    # Sun shafts through the broken ceiling (ruins): a light pool on the floor, grass in
    # it, a faint beam and dust over it.
    if r.has("shafts"):
        var half2 := room.room_size / 2.0
        var tries := 0
        while layer.pools.size() < 3 and tries < 40:
            tries += 1
            var p := Vector2(rng.randf_range(-half2.x * 0.75, half2.x * 0.75), rng.randf_range(-half2.y * 0.7, half2.y * 0.7))
            if not room.spot_ok_loose(p, 40.0):
                continue
            var far := true
            for q in layer.pools:
                far = far and p.distance_to(q) > 260.0
            if not far:
                continue
            layer.pools.append(p)
            add_light(room, p, 180.0, r["shafts"], 0.5, 0.02, 0.0)
        var sh := Shafts.new()
        sh.pools = layer.pools
        sh.col = r["shafts"]
        sh.tx = tx
        room.add_child(sh)
    # Living dressing: interior islands off the lanes, plants that sway, a landmark, the
    # piece registry reactions will use (ArtPass.pieces_near / react); small critters.
    var lv := Living.new()
    lv.room = room
    lv.recipe = r
    lv.tx = tx
    lv.plan(rng, layer.pools)
    room.add_child(lv)
    room.move_child(lv, 1)
    for pc in lv.pieces:
        if pc["k"] == "candle":
            lv.candle_light = add_light(room, pc["p"], 90.0, Color(1.0, 0.76, 0.40), 0.5, 0.03, 0.8)
            break
    var cr := Critters.new()
    cr.tx = tx
    cr.pools = layer.pools
    room.add_child(cr)
    critters_ref = weakref(cr)
    var fg := Foreground.new()
    fg.room = room
    fg.recipe = r
    fg.tx = tx
    fg.plan(rng)
    room.add_child(fg)
    if OS.get_cmdline_user_args().has("--art-time"):
        print("[ART-DRESS] ms=%.2f pieces=%d" % [float(Time.get_ticks_usec() - t0) / 1000.0, lv.pieces.size()])


## After Room._dress_theme: a light on every wall torch and brazier, lit props, doorways.
static func light_room(room: Room) -> void:
    if not active() or owner_ref.get_ref() != room:
        return
    var r := recipe
    for l in room.ambience.lights:
        var big := String(l[1]) != "torch"
        add_light(room, (l[0] as Vector2) + Vector2(0, 10), 260.0 if big else 210.0, r["fire"], 1.0 if big else 0.85, 0.04, 0.6)
    if critters_ref != null and critters_ref.get_ref() != null:
        var cr: Critters = critters_ref.get_ref()
        for l in room.ambience.lights:
            cr.lamps.append((l[0] as Vector2) + Vector2(0, 6))
    for c in room.find_children("*", "Prop", true, false):
        if (c as Prop).kind == "brazier":
            add_light(c, Vector2(0, -6), 230.0, r["fire"], 0.9, 0.03, 0.6)
    for d in room.doors.keys():
        var door: Door = room.doors[d]
        var into := -Vector2(d)
        door.add_child(DoorSpill.new(d, r["spill"]))
        add_light(door, into * 30.0, 190.0, r["spill"], 0.55, 0.05, 0.0).name = "SpillLight"


## Floor and wall dressing under the bodies (one node, drawn once): contact shadows along
## the walls, the top wall's front face, doorway jambs, clutter.
class RoomDressing extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var room: Room
    var recipe: Dictionary
    var tx := 2.3
    var stains: Array = []     # [pos, radius]
    var rubble: Array = []     # [pos, size texels, shade]
    var bones: Array = []      # [pos, angle]
    var moss: Array = []       # [pos, radius]
    var cracks: Array = []     # PackedVector2Array
    var columns: Array = []    # [pos, texture]
    var mode := 0              # 0 floor clutter, 1 walls (face, columns, jambs)
    var pools: Array = []      # sun shaft pools (ruins)

    func _snap(p: Vector2) -> Vector2:
        return (p / tx).round() * tx

    func _clear(p: Vector2, r: float) -> bool:
        return room.spot_ok_loose(p, r)

    ## Clutter hugs the walls: a band 14..70 px in from each wall, thicker in corners.
    func plan(rng: RandomNumberGenerator) -> void:
        var half := room.room_size / 2.0
        var per := room.room_size.x * 2.0 + room.room_size.y * 2.0
        var n := int(per / 70.0)
        for i in n:
            var side := rng.randi() % 4
            var along := rng.randf_range(-1.0, 1.0)
            along = signf(along) * pow(absf(along), 0.6)   # more towards the corners
            var depth := 14.0 + pow(rng.randf(), 2.0) * 60.0
            var p: Vector2
            match side:
                0: p = Vector2(along * (half.x - 10.0), -half.y + depth)
                1: p = Vector2(along * (half.x - 10.0), half.y - depth)
                2: p = Vector2(-half.x + depth, along * (half.y - 10.0))
                _: p = Vector2(half.x - depth, along * (half.y - 10.0))
            if not _clear(p, 12.0):
                continue
            var roll := rng.randf()
            if roll < 0.42:
                for k in rng.randi_range(2, 5):
                    var q := p + Vector2(rng.randf_range(-16, 16), rng.randf_range(-10, 10))
                    rubble.append([_snap(q), float(rng.randi_range(2, 5)), rng.randf_range(0.75, 1.15)])
            elif roll < 0.58:
                bones.append([_snap(p), rng.randf() * TAU, rng.randi() % 3])
            elif roll < 0.82:
                moss.append([_snap(p), rng.randf_range(12.0, 26.0)])
            else:
                stains.append([_snap(p), rng.randf_range(18.0, 34.0)])
        # A few big stains and cracks on the open floor: dark and low, never a shape that
        # reads as a body or a pickup.
        for i in rng.randi_range(3, 5):
            var p := Vector2(rng.randf_range(-half.x + 90, half.x - 90), rng.randf_range(-half.y + 90, half.y - 90))
            if _clear(p, 30.0):
                stains.append([_snap(p), rng.randf_range(26.0, 48.0)])
        for i in rng.randi_range(4, 7):
            var p := Vector2(rng.randf_range(-half.x + 40, half.x - 40), rng.randf_range(-half.y + 40, half.y - 40))
            if not _clear(p, 10.0):
                continue
            var pts := PackedVector2Array()
            var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
            for k in rng.randi_range(4, 8):
                pts.append(_snap(p))
                dir = dir.rotated(rng.randf_range(-0.8, 0.8))
                p += dir * rng.randf_range(8.0, 15.0)
            cracks.append(pts)
        # Broken columns in the four corners, banners between the top wall's torches.
        var cols := ["statues/crumbled_column_1.png", "statues/crumbled_column_3.png", "statues/crumbled_column_4.png", "statues/crumbled_column_5.png", "statues/crumbled_column_6.png"]
        for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
            var p: Vector2 = c * (half - Vector2(26, 26))
            if rng.randf() < 0.75 and _clear(p, 20.0):
                columns.append([_snap(p), Themes.tex(String(cols[rng.randi() % cols.size()]))])

    func _draw() -> void:
        if mode == 1:
            _draw_walls()
            return
        var half := room.room_size / 2.0
        var lt: Texture2D = Art.PARTICLES["light"]
        # Contact shadow: the floor darkens towards every wall, most under the top wall.
        for k in 6:
            var a := 0.30 * (1.0 - float(k) / 6.0)
            var w := tx * 2.0
            draw_rect(Rect2(-half.x, -half.y + float(k) * w + 0.0, room.room_size.x, w), Color(0, 0, 0, a * 1.4))
            draw_rect(Rect2(-half.x, half.y - float(k + 1) * w, room.room_size.x, w), Color(0, 0, 0, a * 0.7))
            draw_rect(Rect2(-half.x + float(k) * w, -half.y, w, room.room_size.y), Color(0, 0, 0, a))
            draw_rect(Rect2(half.x - float(k + 1) * w, -half.y, w, room.room_size.y), Color(0, 0, 0, a))
        # Stains: soft dark blotches.
        var st: Color = recipe["stain"]
        for s in stains:
            var rad: float = s[1]
            draw_texture_rect(lt, Rect2(s[0] - Vector2(rad, rad * 0.7), Vector2(rad * 2.0, rad * 1.4)), false, Color(st, 0.55))
        # Moss: a dark mat with a few lighter tufts.
        var mc: Color = recipe["moss"]
        for m in moss:
            var p: Vector2 = m[0]
            var rad: float = m[1]
            draw_texture_rect(lt, Rect2(p - Vector2(rad, rad * 0.6), Vector2(rad * 2.0, rad * 1.2)), false, Color(mc, 0.7))
            var h := int(absf(p.x * 7.0 + p.y * 13.0))
            for k in 5:
                var q := p + Vector2(float((h >> k) % 9) - 4.0, float((h >> (k + 3)) % 5) - 2.0) * tx
                draw_rect(Rect2(_snap(q), Vector2(tx, tx)), mc.lightened(0.35))
        # Sunlit pools: a pale patch with grass grown in the light.
        var sc2: Color = recipe.get("shafts", Color.WHITE)
        for p in pools:
            draw_texture_rect(lt, Rect2(p - Vector2(80, 50), Vector2(160, 100)), false, Color(sc2, 0.10))
            var h := int(absf(p.x * 3.0 + p.y * 5.0))
            for k in 22:
                var a := float(k) * 2.4 + float(h % 7)
                var d := 22.0 + float((h >> (k % 9)) % 40)
                var q := _snap(p + Vector2(cos(a) * d, sin(a) * d * 0.62))
                draw_rect(Rect2(q, Vector2(tx, tx * 2.0)), mc.lightened(0.25))
                draw_rect(Rect2(q + Vector2(tx, tx), Vector2(tx, tx)), mc.lightened(0.45))
        # Cracks.
        for c in cracks:
            draw_polyline(c, Color(0.0, 0.0, 0.0, 0.55), tx)
        # Rubble: stones with a dark outline and a lit top-left texel.
        var sc: Color = recipe["stone"]
        for rb in rubble:
            var p: Vector2 = rb[0]
            var s: float = float(rb[1]) * tx
            var c := sc * float(rb[2])
            c.a = 1.0
            draw_rect(Rect2(p - Vector2(tx, tx), Vector2(s + 2.0 * tx, s + tx)), Color(0.02, 0.02, 0.02, 0.9))
            draw_rect(Rect2(p, Vector2(s, s - tx)), c)
            draw_rect(Rect2(p, Vector2(s - tx, tx)), c.lightened(0.35))
            draw_rect(Rect2(p + Vector2(0, s - tx), Vector2(s + tx, tx)), Color(0, 0, 0, 0.45))
        # Bones: a long bone, a skull or a pair, in pale ivory.
        var bc: Color = recipe["bone"]
        for b in bones:
            var p: Vector2 = b[0]
            var kind: int = b[2]
            if kind == 0:
                var d := Vector2.RIGHT.rotated(b[1]) * 7.0 * tx
                draw_line(p - d, p + d, Color(0, 0, 0, 0.8), tx * 3.0)
                draw_line(p - d, p + d, bc, tx)
                draw_rect(Rect2(_snap(p - d) - Vector2(tx, tx), Vector2(2 * tx, 2 * tx)), bc)
                draw_rect(Rect2(_snap(p + d) - Vector2(tx, tx), Vector2(2 * tx, 2 * tx)), bc)
            elif kind == 1:
                draw_rect(Rect2(p - Vector2(3, 3) * tx, Vector2(6, 5) * tx), Color(0, 0, 0, 0.85))
                draw_rect(Rect2(p - Vector2(2, 2) * tx, Vector2(4, 3) * tx), bc)
                draw_rect(Rect2(p + Vector2(-1, 1) * tx, Vector2(2, 1) * tx), bc.darkened(0.25))
                draw_rect(Rect2(p + Vector2(-2, -1) * tx, Vector2(1, 1) * tx), Color(0.05, 0.04, 0.04))
                draw_rect(Rect2(p + Vector2(1, -1) * tx, Vector2(1, 1) * tx), Color(0.05, 0.04, 0.04))
            else:
                for k in 3:
                    var q := p + Vector2(float(k) * 3.0 - 3.0, float(k % 2) * 2.0) * tx
                    draw_rect(Rect2(q - Vector2(tx, tx), Vector2(3, 2) * tx), Color(0, 0, 0, 0.7))
                    draw_rect(Rect2(q, Vector2(tx * 2.0, tx)), bc.darkened(0.1 * float(k)))
    func _draw_walls() -> void:
        var half := room.room_size / 2.0
        var lt: Texture2D = Art.PARTICLES["light"]
        # The top wall's front face: the lower part of the wall band, darker, with a lit
        # lip above it and a dark line where it meets the floor.
        var face := 26.0
        var top := Rect2(-half.x - Room.WALL, -half.y - face, room.room_size.x + 2.0 * Room.WALL, face)
        for k in 4:
            draw_rect(Rect2(top.position.x, top.position.y + float(k) * face / 4.0, top.size.x, face / 4.0), Color(0, 0, 0, 0.30 + 0.12 * float(k)))
        var lip: Color = Themes.def(room.theme).get("edge", Color(0.7, 0.7, 0.7))
        draw_rect(Rect2(top.position.x, top.position.y - tx, top.size.x, tx), Color(lip, 0.55))
        draw_rect(Rect2(top.position.x, -half.y - tx, top.size.x, tx), Color(0, 0, 0, 0.8))
        # Corner columns (DCSS broken columns) on a soft shadow.
        for c in columns:
            var t: Texture2D = c[1]
            var s := t.get_size() * tx
            var p: Vector2 = c[0]
            draw_texture_rect(lt, Rect2(p - Vector2(s.x * 0.6, -s.y * 0.1), Vector2(s.x * 1.2, s.y * 0.6)), false, Color(0, 0, 0, 0.6))
            draw_texture_rect(t, Rect2(p - s / 2.0, s), false, Color(0.78, 0.80, 0.72))
        # Doorway jambs: a stone block either side of every door, its lit top and a dark
        # gap line, and a lintel shadow across the opening.
        var td := Themes.def(room.theme)
        for d in room.data.doors.keys():
            _draw_jambs(d, td)


    func _draw_jambs(d: Vector2i, td: Dictionary) -> void:
        var half := room.room_size / 2.0
        var hi: Color = td.get("edge", Color(0.7, 0.7, 0.7))
        var wt: Color = (td["wall_tint"] as Color)
        var stone := Color(0.30 * wt.r + 0.08, 0.30 * wt.g + 0.08, 0.30 * wt.b + 0.08)
        var g := Room.GAP / 2.0
        var jw := 5.0 * tx    # jamb width
        var jd := 12.0 * tx   # how far it stands out of the wall
        if d.y != 0:
            var y := float(d.y) * half.y
            var into := -float(d.y)
            for sx in [-1.0, 1.0]:
                var x := float(sx) * (g + jw / 2.0) - jw / 2.0
                var r := Rect2(x, y if into > 0 else y - jd, jw, jd)
                draw_rect(r.grow(tx), Color(0.02, 0.02, 0.02))
                draw_rect(r, stone)
                draw_rect(Rect2(r.position, Vector2(r.size.x, tx * 2.0)), Color(hi, 0.8))
                draw_rect(Rect2(r.position + Vector2(r.size.x - tx, 0), Vector2(tx, r.size.y)), Color(0, 0, 0, 0.4))
            if d.y < 0:
                # Lintel shadow falls into the room under the top door.
                for k in 4:
                    draw_rect(Rect2(-g, y + float(k) * tx * 2.0, 2.0 * g, tx * 2.0), Color(0, 0, 0, 0.35 - 0.08 * float(k)))
        else:
            var x := float(d.x) * half.x
            var into := -float(d.x)
            for sy in [-1.0, 1.0]:
                var y := float(sy) * (g + jw / 2.0) - jw / 2.0
                var r := Rect2(x if into > 0 else x - jd, y, jd, jw)
                draw_rect(r.grow(tx), Color(0.02, 0.02, 0.02))
                draw_rect(r, stone)
                draw_rect(Rect2(r.position, Vector2(r.size.x, tx * 2.0)), Color(hi, 0.8))
                draw_rect(Rect2(r.position + Vector2(0, r.size.y - tx), Vector2(r.size.x, tx)), Color(0, 0, 0, 0.5))


## Light falling through a doorway onto the floor in front of it: a soft fan in the spill
## colour when open, a dim red one when locked; it breathes slowly. Drawn under bodies.
class DoorSpill extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var dir: Vector2i
    var col: Color
    var _t := 0.0

    func _init(d: Vector2i, c: Color) -> void:
        dir = d
        col = c
        z_index = -1
        name = "Spill"

    func _process(delta: float) -> void:
        _t += delta
        if Engine.get_process_frames() % 4 == 0:
            queue_redraw()

    func _draw() -> void:
        var door := get_parent() as Door
        if door == null:
            return
        var lt: Texture2D = Art.PARTICLES["light"]
        var into := -Vector2(dir)
        var open := door.state == Door.State.OPEN
        var c := col if open else Color(0.9, 0.25, 0.2)
        var a := (0.20 if open else 0.10) * (0.9 + 0.1 * sin(_t * 1.3))
        var across := Vector2(into.y, into.x).abs()
        var w := Room.GAP * 1.5
        for k in 3:
            var dist := 30.0 + float(k) * 34.0
            var sz := across * (w * (0.8 + 0.25 * float(k))) + into.abs() * (70.0 + 20.0 * float(k))
            var at := into * dist
            draw_texture_rect(lt, Rect2(at - sz / 2.0, sz), false, Color(c, a * (1.0 - 0.25 * float(k))))
        # The opening itself glows faintly.
        var gs := Vector2(door.size.x, door.size.y) * 0.9
        draw_texture_rect(lt, Rect2(-gs / 2.0, gs), false, Color(c, a * 1.6))


## Sun shafts: a faint additive beam from each pool up towards the broken ceiling (light
## from the top left), dust drifting in it. Above bodies, low alpha, additive only.
class Shafts extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var pools: Array = []
    var col := Color.WHITE
    var tx := 2.3
    var _t := 0.0

    func _init() -> void:
        z_index = 30
        z_as_relative = false
        name = "Shafts"
        var m := CanvasItemMaterial.new()
        m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        material = m

    func _process(delta: float) -> void:
        _t += delta
        if Engine.get_process_frames() % 3 == 0:
            queue_redraw()

    func _draw() -> void:
        var up := Vector2(-0.38, -1.0).normalized()
        var side := Vector2(1.0, 0.0)
        for p in pools:
            var c0 := Color(col, (0.08 + 0.015 * sin(_t * 0.7 + p.x)) * (1.0 - ArtPass.fight))
            var c1 := Color(col, 0.0)
            var top: Vector2 = p + up * 230.0
            draw_polygon(PackedVector2Array([p - side * 44.0, p + side * 44.0, top + side * 62.0, top - side * 62.0]),
                PackedColorArray([c0, c0, c1, c1]))
            draw_polygon(PackedVector2Array([p - side * 22.0, p + side * 22.0, top + side * 30.0, top - side * 30.0]),
                PackedColorArray([Color(col, c0.a * 0.8), Color(col, c0.a * 0.8), c1, c1]))
            # Dust motes turning slowly in the beam.
            for k in 9:
                var f := fmod(_t * 0.05 + float(k) * 0.113, 1.0)
                var q: Vector2 = p + up * (f * 210.0) + side * sin(_t * 0.6 + float(k) * 1.9) * 28.0 * (0.4 + f)
                var a := sin(PI * f) * 0.55
                draw_rect(Rect2((q / tx).round() * tx, Vector2(tx, tx)), Color(col, a))


## Over everything in the world (bodies included), only along the walls: roots hanging
## over the top wall's face and dark pillars rising over the bottom corners, shifted a
## little against the camera so they read as closer than the floor.
class Foreground extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var room: Room
    var recipe: Dictionary
    var tx := 2.3
    var roots: Array = []    # [x, length texels, sway phase]
    var _t := 0.0
    var _last_cam := Vector2.INF

    func _init() -> void:
        z_index = 40
        z_as_relative = false
        name = "Foreground"

    func plan(rng: RandomNumberGenerator) -> void:
        var half := room.room_size / 2.0
        var x := -half.x + rng.randf_range(10, 60)
        while x < half.x - 20.0:
            if not (room.data.doors.has(Vector2i.UP) and absf(x) < Room.GAP * 0.6):
                roots.append([x, float(rng.randi_range(3, 9)), rng.randf() * TAU])
            x += rng.randf_range(26.0, 90.0)

    func _process(delta: float) -> void:
        _t += delta
        var cam := get_viewport().get_camera_2d()
        if cam == null:
            return
        var c := cam.get_screen_center_position()
        # Parallax: 12% of the camera's offset from the room centre, whole texels.
        var off := ((room.global_position - c) * 0.12 / tx).round() * tx
        if off != position:
            position = off
        if Engine.get_process_frames() % 6 == 0:
            queue_redraw()

    func _draw() -> void:
        var half := room.room_size / 2.0
        var rc: Color = recipe["root"]
        var mc: Color = recipe["moss"]
        var top := -half.y - 30.0
        for r in roots:
            var x: float = r[0]
            var n := int(r[1])
            var sway := sin(_t * 0.8 + float(r[2])) * 1.2
            var px := x
            for k in n:
                var y := top + float(k) * tx * 2.0
                px = x + sway * float(k) / float(n) * tx * 2.0
                var p := (Vector2(px, y) / tx).round() * tx
                draw_rect(Rect2(p - Vector2(tx, 0), Vector2(tx * 3.0, tx * 2.0)), Color(0, 0, 0, 0.85))
                draw_rect(Rect2(p, Vector2(tx, tx * 2.0)), rc.lightened(0.15))
                if (k + int(x)) % 4 == 0:
                    draw_rect(Rect2(p + Vector2(tx, tx), Vector2(tx * 2.0, tx)), mc.lightened(0.25))
        # Bottom-corner pillars: dark silhouettes on the bottom wall.
        for sx in [-1.0, 1.0]:
            var w := 34.0
            var h := 70.0
            var base := Vector2(sx * (half.x + Room.WALL - w / 2.0 - 4.0), half.y + Room.WALL + 6.0)
            var r := Rect2(base - Vector2(w / 2.0, h), Vector2(w, h))
            draw_rect(r, Color(0.02, 0.025, 0.02, 0.92))
            draw_rect(Rect2(r.position + Vector2(sx * -1.0 if sx < 0 else 0.0, 0), Vector2(tx, h)), Color(recipe["stone"], 0.6))
            draw_rect(Rect2(r.position, Vector2(w, tx * 2.0)), Color(recipe["stone"], 0.8))


# --- Living dressing: interior islands, plants that move, a registry for reactions -------

## Lanes the interior keeps clear (design/Living world visuals research.md, 2.6): a band
## LANE wide from every doorway to the room centre, and a clearing CLEAR round the centre.
const LANE := 56.0
const CLEAR := 110.0


static func in_lane(room: Room, p: Vector2, r: float) -> bool:
    if p.length() < CLEAR + r:
        return true
    var half := room.room_size / 2.0
    for d in room.data.doors.keys():
        var a := Vector2(d) * half
        if Geometry2D.get_closest_point_to_segment(p, a, Vector2.ZERO).distance_to(p) < LANE + r:
            return true
    return false


## Every living piece in `room` within `radius` of `pos` (room-local), as the registry
## dictionaries: { k: kind, p: pos, s: size, ph: sway phase, st: state, t: state time }.
## Kinds: "grass", "fern", "moss" (plants, react), "candle" (lit). States: "live", "burnt",
## "frozen", "wet", "charged".
static func pieces_near(room: Room, pos: Vector2, radius: float) -> Array:
    var out: Array = []
    var lv := room.get_node_or_null("Living") as Living
    if lv == null:
        return out
    for pc in lv.pieces:
        if (pc["p"] as Vector2).distance_to(pos) <= radius + float(pc["s"]):
            out.append(pc)
    return out


## Element reactions on the living dressing (wired: the Living node reads the Materials grid
## four times a second, answers shots and bodies, gales and novas). This entry point lets
## other code react a spot directly: FIRE sets plants burning (fire spreads plant to plant,
## show only), ICE freezes them (a hit shatters them), POISON and ACID wilt them, WET soaks
## them, SHOCK makes them crackle, GALE leans them away from `pos`, VOID pulls them in.
## Returns how many pieces changed.
static func react(room: Room, pos: Vector2, radius: float, element: int, dir := Vector2.ZERO) -> int:
    var lv := room.get_node_or_null("Living") as Living
    if lv == null:
        return 0
    return lv.react_at(pos, radius, element, dir)


## A clock for the living-world shaders (seconds, wrapped so floats stay exact).
static func now() -> float:
    return fmod(float(Time.get_ticks_msec()) / 1000.0, 900.0)


## Materials.living_forces: a gale on the grid reaches plants, chains and critters.
static func force_at(m: Materials, pos: Vector2, r: float, kind: int) -> void:
    var room := m.get_parent() as Room
    if room == null:
        return
    var lv := room.get_node_or_null("Living") as Living
    if lv != null:
        lv.react_at(pos - room.global_position, r * 1.3, kind)
    var ch := room.get_node_or_null("Chains") as LivingWorld.Chains
    if ch != null:
        ch.force(pos, r * 1.5, 6.0)
    var cr := room.get_node_or_null("GroundCritters") as LivingWorld.Critters
    if cr != null:
        cr.gale(pos, r)


## The living world beyond the recipe regions (design doc "Art direction", living world):
## the river on every theme's deep water; vines, banners, cobwebs, critters and steam vents in
## the river regions (ruins, garden, cistern). Off with the "lighting" option or --no-art.
const LIVING_THEMES := ["ruins", "garden", "cistern"]


static func dress_living(room: Room) -> void:
    if not enabled():
        return
    Materials.living_forces = true
    var tx := Themes.texel(room._zoom())
    if not room._deep_rects.is_empty():
        var rv := LivingWorld.River.new()
        rv.tx = tx
        room.add_child(rv)
        var under := room.get_node_or_null("LayoutUnder")
        if under != null:
            room.move_child(rv, under.get_index() + 1)
        rv.build(room, room._deep_rects)
    if not room.theme in LIVING_THEMES:
        return
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(room.data.pos) * 13 + room.main.floor_number * 7 + 5
    if room.get_node_or_null("Living") == null:
        # The river regions without a light recipe still get the islands and plants.
        var lr: Dictionary = RECIPES["ruins"].duplicate()
        lr["moss"] = Color(0.26, 0.34, 0.12) if room.theme == "garden" else Color(0.14, 0.30, 0.26)
        lr["stone"] = Color(0.30, 0.31, 0.32) if room.theme == "cistern" else Color(0.32, 0.31, 0.24)
        var nl := Living.new()
        nl.room = room
        nl.recipe = lr
        nl.tx = Themes.texel(room._zoom())
        nl.plan(rng, [])
        room.add_child(nl)
        room.move_child(nl, 1)
    var half := room.room_size / 2.0
    var r: Dictionary = RECIPES.get(room.theme, RECIPES["ruins"])
    var moss: Color = r["moss"]
    var ch := LivingWorld.Chains.new()
    ch.room = room
    ch.mats = room.materials
    ch.tx = tx
    var top := -half.y - 16.0
    var x := -half.x + rng.randf_range(20.0, 70.0)
    while x < half.x - 20.0:
        if not (room.data.doors.has(Vector2i.UP) and absf(x) < Room.GAP * 0.65):
            ch.add("vine", Vector2(x, top), rng.randi_range(5, 12), tx * 2.2, moss.lightened(0.12))
        x += rng.randf_range(60.0, 130.0)
    # Banners between the torch slots, cobwebs in the top corners, a chain or two.
    var cloth := [Color(0.42, 0.14, 0.12), Color(0.16, 0.28, 0.32), Color(0.34, 0.30, 0.14)]
    var n := maxi(2, int(room.room_size.x / 200.0))
    for i in n:
        var bx := -half.x + room.room_size.x * (float(i) + 0.5) / float(n)
        if room.data.doors.has(Vector2i.UP) and absf(bx) < Room.GAP * 0.7:
            continue
        if rng.randf() < 0.55:
            ch.add("banner", Vector2(bx, top - 6.0), rng.randi_range(6, 9), tx * 2.0, cloth[rng.randi() % cloth.size()].darkened(0.1), 6.0)
        elif rng.randf() < 0.5:
            ch.add("chain", Vector2(bx, top - 4.0), rng.randi_range(6, 10), tx * 1.8, Color(0.34, 0.34, 0.36))
    for sx in [-1.0, 1.0]:
        var c := Vector2(sx * (half.x - 2.0), -half.y + 2.0)
        for k in 4:
            var dir := Vector2(-sx, 0.0).rotated(sx * (0.25 + float(k) * 0.42))
            ch.add("web", c, 2, 18.0 + float(k % 2) * 8.0, Color(0.80, 0.80, 0.76))
            ch.chains[-1]["pts"][1] = c + dir * (18.0 + float(k % 2) * 8.0)
            ch.chains[-1]["old"][1] = ch.chains[-1]["pts"][1]
    room.add_child(ch)
    # Critters near the walls and the islands; vents in the wet and ruined rooms.
    var homes: Array = []
    for i in 9:
        var side := rng.randi() % 4
        var along := rng.randf_range(-0.9, 0.9)
        var p: Vector2
        match side:
            0: p = Vector2(along * half.x, -half.y + 18.0)
            1: p = Vector2(along * half.x, half.y - 18.0)
            2: p = Vector2(-half.x + 18.0, along * half.y)
            _: p = Vector2(half.x - 18.0, along * half.y)
        homes.append(p)
    var lv := room.get_node_or_null("Living") as Living
    if lv != null:
        for m in lv.mats:
            homes.append((m[0] as Vector2) + Vector2(rng.randf_range(-40, 40), rng.randf_range(-20, 20)))
    var cr := LivingWorld.Critters.new()
    cr.tx = tx
    room.add_child(cr)
    cr.plan(room, homes.slice(0, 8))
    if room.theme in ["cistern", "ruins"]:
        var vt := LivingWorld.Vents.new()
        vt.tx = tx
        vt.plan(room, rng)
        room.add_child(vt)


## Interior islands and every plant in the room, under the bodies (z -1). Plants sway in
## steps of a texel (8 steps a second), half as much in a fight.
## Decals stay within about 10% of the floor's brightness; only the plants
## and the landmark rise above it (research note, Part 4). In a fight the layer fades to 45%.
class Living extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var room: Room
    var recipe: Dictionary
    var tx := 2.3
    var pieces: Array = []      # the registry (see ArtPass.pieces_near)
    var mats: Array = []        # [pos, radii]: moss mats under the islands
    var litter: Array = []      # [pos, colour]: leaf litter texels
    var pebbles: Array = []     # [pos, size texels]
    var cracks: Array = []      # hairline wear cracks
    var landmark := Vector2.INF
    var gust := Vector2.ZERO
    var gust_t := 0.0
    var _t := 0.0
    var _step := -1

    func _init() -> void:
        name = "Living"
        z_index = -1

    func _snap(p: Vector2) -> Vector2:
        return (p / tx).round() * tx

    func _ok(p: Vector2, r: float) -> bool:
        return room.spot_ok_loose(p, r) and not ArtPass.in_lane(room, p, r)

    func _add(k: String, p: Vector2, s: float, rng: RandomNumberGenerator) -> void:
        pieces.append({ "k": k, "p": _snap(p), "s": s, "ph": rng.randf() * TAU, "st": "live", "t": 0.0 })

    ## 2 to 4 islands on the room's thirds (plus the sun pools, which already are islands),
    ## the first one with the landmark; ferns and grass along the walls.
    func plan(rng: RandomNumberGenerator, pools: Array) -> void:
        var half := room.room_size / 2.0
        var want := clampi(int(room.room_size.x * room.room_size.y / 180000.0), 3, 5)
        var spots: Array = []
        for fx in [-0.74, -0.44, -0.15, 0.15, 0.44, 0.74]:
            for fy in [-0.6, -0.2, 0.2, 0.6]:
                spots.append(Vector2(fx * half.x, fy * half.y) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-24, 24)))
        # Shuffle with the room's rng (stable per room).
        for i in range(spots.size() - 1, 0, -1):
            var j := rng.randi() % (i + 1)
            var tmp: Vector2 = spots[i]
            spots[i] = spots[j]
            spots[j] = tmp
        var islands: Array = []
        for s in spots:
            if islands.size() >= want:
                break
            if not _ok(s, 46.0):
                continue
            var far := true
            for q in islands + pools:
                far = far and (s as Vector2).distance_to(q) > 200.0
            if far:
                islands.append(s)
        for i in islands.size():
            var c: Vector2 = islands[i]
            if i == 0:
                landmark = _snap(c)
                for k in 3:
                    var a := -0.6 + float(k) * 0.55
                    pieces.append({ "k": "candle", "p": _snap(c + Vector2(cos(a), sin(a) * 0.6) * 34.0 + Vector2(0, -6)), "s": 4.0, "ph": rng.randf() * TAU, "st": "live", "t": 0.0 })
            mats.append([_snap(c), Vector2(rng.randf_range(70, 96), rng.randf_range(40, 56))])
            for k in rng.randi_range(16, 24):
                var a := rng.randf() * TAU
                var d := rng.randf_range(0.3, 1.0)
                var p := c + Vector2(cos(a) * 84.0, sin(a) * 50.0) * d
                if i == 0 and p.distance_to(c) < 42.0:
                    continue   # the landmark's ring stays clear
                if _ok(p, 6.0):
                    _add("grass", p, 6.0, rng)
            for k in rng.randi_range(3, 5):
                var a := rng.randf() * TAU
                var p := c + Vector2(cos(a) * 70.0, sin(a) * 38.0)
                if _ok(p, 10.0):
                    _add("fern", p, 10.0, rng)
            for k in rng.randi_range(6, 10):
                var p := c + Vector2(rng.randf_range(-70, 70), rng.randf_range(-40, 40))
                litter.append([_snap(p), rng.randi() % 3])
            for k in rng.randi_range(3, 6):
                var p := c + Vector2(rng.randf_range(-60, 60), rng.randf_range(-34, 34))
                if _ok(p, 4.0):
                    pebbles.append([_snap(p), float(rng.randi_range(1, 3))])
            pieces.append({ "k": "moss", "p": _snap(c), "s": 60.0, "ph": 0.0, "st": "live", "t": 0.0 })
        # Wear over the rest of the off-lane floor: litter texels and hairline cracks, about
        # one per 9,000 px², all within the floor's value band.
        var wear := int(room.room_size.x * room.room_size.y / 9000.0)
        for i in wear:
            var p := Vector2(rng.randf_range(-half.x + 30, half.x - 30), rng.randf_range(-half.y + 30, half.y - 30))
            if not _ok(p, 6.0):
                continue
            if rng.randf() < 0.6:
                for k in rng.randi_range(1, 3):
                    litter.append([_snap(p + Vector2(rng.randf_range(-8, 8), rng.randf_range(-5, 5))), rng.randi() % 3])
            else:
                var pts := PackedVector2Array()
                var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
                var q := p
                for k in rng.randi_range(3, 5):
                    pts.append(_snap(q))
                    dir = dir.rotated(rng.randf_range(-0.9, 0.9))
                    q += dir * rng.randf_range(6.0, 11.0)
                cracks.append(pts)
        # The sun pools: grass already drawn by RoomDressing; ferns at their rim.
        for p0 in pools:
            for k in 2:
                var p: Vector2 = p0 + Vector2(rng.randf_range(-70, 70), rng.randf_range(-40, 40))
                if _ok(p, 10.0):
                    _add("fern", p, 10.0, rng)
        # Wall-foot plants: a fern or a tuft every ~110 px of wall, off doorways.
        var per := int((room.room_size.x + room.room_size.y) * 2.0 / 110.0)
        for i in per:
            var side := rng.randi() % 4
            var along := rng.randf_range(-0.95, 0.95)
            var depth := rng.randf_range(12.0, 30.0)
            var p: Vector2
            match side:
                0: p = Vector2(along * half.x, -half.y + depth)
                1: p = Vector2(along * half.x, half.y - depth)
                2: p = Vector2(-half.x + depth, along * half.y)
                _: p = Vector2(half.x - depth, along * half.y)
            if room.spot_ok_loose(p, 8.0):
                _add("fern" if rng.randf() < 0.4 else "grass", p, 8.0, rng)

    # --- Reactions (wired to the Materials grid, shots, bodies, gales and novas) ---------

    const PLANTS := ["grass", "fern", "moss"]
    var _buckets: Dictionary = {}   # Vector2i(32 px cell) -> piece indices (plants)
    var _busy: Dictionary = {}      # piece index -> true while it has a state to tick
    var _poll := 0.0
    var _touch_t := 0.0
    var _dirty := false
    var _last_draw := 0.0
    var _wave_t := 9.0
    var _fx_ref: Fx = null
    var candle_light: Node2D = null

    func _ready() -> void:
        for i in pieces.size():
            var pc: Dictionary = pieces[i]
            pc["lean"] = 0.0
            pc["rg"] = 0.0
            pc["fl"] = 0
            pc["sp"] = false
            pc["nb"] = []
            if String(pc["k"]) in PLANTS and pc["k"] != "moss":
                var key := Vector2i(floori((pc["p"] as Vector2).x / 32.0), floori((pc["p"] as Vector2).y / 32.0))
                if not _buckets.has(key):
                    _buckets[key] = []
                _buckets[key].append(i)
        # Neighbours for fire spreading plant to plant (within 22 px; moss mats reach further).
        for i in pieces.size():
            var a: Dictionary = pieces[i]
            if not String(a["k"]) in PLANTS:
                continue
            for j in range(i + 1, pieces.size()):
                var b: Dictionary = pieces[j]
                if not String(b["k"]) in PLANTS:
                    continue
                var reach := 22.0 if a["k"] != "moss" and b["k"] != "moss" else 70.0
                if (a["p"] as Vector2).distance_to(b["p"]) < reach:
                    (a["nb"] as Array).append(j)
                    (b["nb"] as Array).append(i)
        # What burned or broke here before is still burnt (a revisit).
        var saved: Variant = room.data.get_meta("living_state") if room.data.has_meta("living_state") else null
        if saved is Array and (saved as Array).size() == pieces.size():
            for i in pieces.size():
                var s: Array = saved[i]
                if String(s[0]) in ["burnt", "shattered", "wilted"]:
                    pieces[i]["st"] = s[0]
                    pieces[i]["rg"] = float(s[1])
                    pieces[i]["t"] = float(s[1])
                    _busy[i] = true
        if not Elements.nova.is_connected(_on_nova):
            Elements.nova.connect(_on_nova)

    func _exit_tree() -> void:
        if Elements.nova.is_connected(_on_nova):
            Elements.nova.disconnect(_on_nova)
        var out: Array = []
        for pc in pieces:
            var st := String(pc["st"])
            var keep := st in ["burnt", "shattered", "wilted", "burning"]
            out.append(["burnt" if st == "burning" else (st if keep else "live"), maxf(float(pc["rg"]), float(pc["t"])) if keep else 0.0])
        room.data.set_meta("living_state", out)

    func _fx() -> Fx:
        if _fx_ref != null and is_instance_valid(_fx_ref):
            return _fx_ref
        var scene := get_tree().current_scene
        if scene != null and "fx" in scene:
            _fx_ref = scene.get("fx") as Fx
        return _fx_ref

    func _put_state(i: int, st: String, t: float) -> void:
        var pc: Dictionary = pieces[i]
        pc["st"] = st
        pc["t"] = t
        pc["sp"] = false
        _busy[i] = true
        _dirty = true

    func _burnable(st: String) -> bool:
        return st == "live" or st == "wilted" or st == "sprout"

    ## Plants within `radius` of `pos` (room-local) take the element's answer.
    func react_at(pos: Vector2, radius: float, element: int, _dir := Vector2.ZERO) -> int:
        var n := 0
        for i in pieces.size():
            var pc: Dictionary = pieces[i]
            if (pc["p"] as Vector2).distance_to(pos) > radius + float(pc["s"]):
                continue
            if _hit(i, element, (pc["p"] as Vector2) - pos, 3.0):
                n += 1
        return n

    func _lean(pc: Dictionary, off: Vector2, amount: float) -> void:
        pc["lean"] = clampf(signf(off.x if absf(off.x) > 0.5 else 1.0) * amount, -3.0, 3.0)

    ## One element (or a plain touch, NONE) reaching piece i from offset `off`.
    func _hit(i: int, element: int, off: Vector2, push: float) -> bool:
        var pc: Dictionary = pieces[i]
        var k := String(pc["k"])
        var st := String(pc["st"])
        if k == "candle":
            if (element == Element.Kind.WET or element == Element.Kind.ICE or element == Element.Kind.GALE) and st == "live":
                _put_state(i, "out", 12.0 if element != Element.Kind.GALE else 3.0)
                return true
            if element == Element.Kind.FIRE and st == "out":
                _put_state(i, "live", 0.0)
                return true
            return false
        if not k in PLANTS:
            return false
        if element == Element.Kind.FIRE:
            if _burnable(st):
                _put_state(i, "burning", 0.9 if k != "moss" else 1.6)
                return true
            if st == "frozen":
                _put_state(i, "wet", 5.0)
                return true
        elif element == Element.Kind.ICE:
            if st != "burnt" and st != "shattered" and st != "burning" and st != "frozen":
                _put_state(i, "frozen", 6.0)
                return true
        elif element == Element.Kind.POISON or element == Element.Kind.ACID:
            if st == "live" or st == "wet" or st == "sprout":
                _put_state(i, "wilted", 14.0)
                return true
        elif element == Element.Kind.WET:
            if st == "live":
                _put_state(i, "wet", 6.0)
                return true
            if st == "burning":
                _put_state(i, "burnt", 0.0)
                pc["rg"] = 18.0
                return true
        elif element == Element.Kind.SHOCK:
            if st != "burnt" and st != "shattered" and not pc.has("zap"):
                pc["fl"] = 1
                pc["zap"] = 0.6
                _busy[i] = true
                _dirty = true
                return true
        elif element == Element.Kind.VOID:
            _lean(pc, off, -push)
            _busy[i] = true
            _dirty = true
            return true
        else:
            # Gale, stone, a plain hit: a frozen plant shatters, others lean away and flash.
            if st == "frozen":
                _shatter(i)
                return true
            if k == "moss":
                return false
            _lean(pc, off, push)
            if element != Element.Kind.GALE:
                pc["fl"] = 1
            _busy[i] = true
            _dirty = true
            return true
        return false

    func _shatter(i: int) -> void:
        _put_state(i, "shattered", 0.0)
        pieces[i]["rg"] = 16.0 + float(i % 7)
        var fx := _fx()
        if fx != null:
            fx.pixels(Element.Kind.ICE, global_position + (pieces[i]["p"] as Vector2), 3, 45.0, 3.0)

    func _on_nova(pos: Vector2, r: float, c: Color) -> void:
        var local := pos - global_position
        var pull := c.b > c.g + 0.3   # Elements' pull novas are violet
        for i in pieces.size():
            var pc: Dictionary = pieces[i]
            var off: Vector2 = (pc["p"] as Vector2) - local
            if off.length() < r and String(pc["k"]) in PLANTS and pc["k"] != "moss":
                _lean(pc, off, -3.0 if pull else 3.0)
                _busy[i] = true
                _dirty = true
        var ch := room.get_node_or_null("Chains")
        if ch != null and ch.has_method("force"):
            ch.force(pos, r * 1.2, -4.0 if pull else 4.0)

    ## Four times a second: what lies on the floor under each plant.
    func _read_floor() -> void:
        var m := room.materials
        if m == null:
            return
        var gp := global_position
        for i in pieces.size():
            var pc: Dictionary = pieces[i]
            var k := String(pc["k"])
            var st := String(pc["st"])
            var mat := m.material_at(gp + (pc["p"] as Vector2))
            if mat == Materials.NONE:
                continue
            if k == "candle":
                if mat == Materials.WATER or mat == Materials.ICE:
                    _hit(i, Element.Kind.WET, Vector2.ZERO, 0.0)
                continue
            if st == "burnt" or st == "shattered" or st == "burning":
                continue
            if mat == Materials.FIRE or mat == Materials.ASH:
                _hit(i, Element.Kind.FIRE, Vector2.ZERO, 0.0)
            elif mat == Materials.ICE:
                if st != "frozen":
                    _hit(i, Element.Kind.ICE, Vector2.ZERO, 0.0)
                else:
                    pc["t"] = maxf(float(pc["t"]), 2.0)
            elif mat == Materials.POISON or mat == Materials.ACID:
                _hit(i, Element.Kind.POISON, Vector2.ZERO, 0.0)
            elif mat == Materials.CHARGED:
                _hit(i, Element.Kind.SHOCK, Vector2.ZERO, 0.0)
            elif mat == Materials.WATER:
                _hit(i, Element.Kind.WET, Vector2.ZERO, 0.0)

    ## Twenty times a second: shots and bodies passing through the plants part them; a fire,
    ## ice or shock shot leaves its element; a frozen plant shatters under any hit.
    func _touch_bodies() -> void:
        if _buckets.is_empty():
            return
        var tree := get_tree()
        var list: Array = []
        for p in tree.get_nodes_in_group("players"):
            list.append([(p as Node2D).global_position, -1])
        for s in tree.get_nodes_in_group("player_shots"):
            var sp := s as Node2D
            if sp != null:
                list.append([sp.global_position, int(sp.get("element"))])
        var en: Array = EnemyGrid.nodes(tree, &"enemies")
        for k in mini(en.size(), 30):
            if is_instance_valid(en[k]):
                list.append([(en[k] as Node2D).global_position, -1])
        var gp := global_position
        for it in list:
            var at: Vector2 = (it[0] as Vector2) - gp
            var key := Vector2i(floori(at.x / 32.0), floori(at.y / 32.0))
            for oy in [-1, 0, 1]:
                for ox in [-1, 0, 1]:
                    var b: Variant = _buckets.get(key + Vector2i(ox, oy))
                    if b == null:
                        continue
                    for i: int in b:
                        var off: Vector2 = (pieces[i]["p"] as Vector2) - at
                        if off.length_squared() > 144.0:
                            continue
                        var el: int = it[1]
                        if el < 0:
                            # A body brushing through: lean away; a frozen plant cracks.
                            if pieces[i]["st"] == "frozen":
                                _shatter(i)
                            elif absf(float(pieces[i]["lean"])) < 1.5:
                                _lean(pieces[i], off, 2.0)
                                _busy[i] = true
                                _dirty = true
                        else:
                            _hit(i, el, off, 2.0)

    func _tick(delta: float, calm: bool) -> void:
        var done: Array = []
        var fx := _fx()
        for i: int in _busy.keys():
            var pc: Dictionary = pieces[i]
            var st := String(pc["st"])
            var t := float(pc["t"]) - delta
            pc["t"] = t
            if int(pc["fl"]) > 0:
                pc["fl"] = int(pc["fl"]) - 1
                _dirty = true
            var lean := float(pc["lean"])
            if lean != 0.0:
                var nl := move_toward(lean, 0.0, delta * 2.5)
                pc["lean"] = nl
                if roundf(nl) != roundf(lean):
                    _dirty = true
            if pc.has("zap"):
                pc["zap"] = float(pc["zap"]) - delta
                if float(pc["zap"]) <= 0.0:
                    pc.erase("zap")
                _dirty = true
            if st == "burning":
                if not pc["sp"] and t < (0.55 if pc["k"] != "moss" else 1.0):
                    pc["sp"] = true
                    for j: int in pc["nb"]:
                        if _burnable(String(pieces[j]["st"])):
                            _put_state(j, "burning", 0.9 if pieces[j]["k"] != "moss" else 1.6)
                if fx != null and (i + Engine.get_process_frames()) % 9 == 0:
                    fx.ember(global_position + (pc["p"] as Vector2) + Vector2(0, -4))
                _dirty = true
                if t <= 0.0:
                    pc["st"] = "burnt"
                    pc["rg"] = 18.0 + float(i % 9)
                    var mm := room.materials
                    if mm != null:
                        mm.scorch(global_position + (pc["p"] as Vector2), 2 if pc["k"] == "moss" else 1)
                        if pc["k"] == "moss":
                            for k in 6:
                                mm.scorch(global_position + (pc["p"] as Vector2) + Vector2.RIGHT.rotated(float(k)) * 30.0, 1)
                    if fx != null:
                        fx.smoke(global_position + (pc["p"] as Vector2), 1, 4.0)
            elif st == "burnt" or st == "shattered":
                if calm:
                    pc["rg"] = float(pc["rg"]) - delta
                    if float(pc["rg"]) <= 0.0:
                        pc["st"] = "sprout"
                        pc["t"] = 1.6
                        _dirty = true
            elif st == "sprout" or st == "frozen" or st == "wilted" or st == "wet" or st == "out":
                if t <= 0.0:
                    pc["st"] = "wet" if st == "frozen" else "live"
                    pc["t"] = 3.0
                    _dirty = true
            elif st == "live":
                if float(pc["lean"]) == 0.0 and int(pc["fl"]) == 0 and not pc.has("zap"):
                    done.append(i)
        for i in done:
            _busy.erase(i)

    func _process(delta: float) -> void:
        _t += delta
        var fight := ArtPass.fight_of(room)
        modulate.a = 1.0 - ArtPass.fight_fade(room, 0.7) * fight
        var calm := fight < 0.5 and not room.active
        if gust_t > 0.0:
            gust_t = maxf(0.0, gust_t - delta)
        _poll -= delta
        if _poll <= 0.0:
            _poll = 0.25
            _read_floor()
        _touch_t -= delta
        if _touch_t <= 0.0:
            _touch_t = 0.05
            _touch_bodies()
        if not _busy.is_empty():
            _tick(delta, calm)
        # The room-wide gust: a wave of wind crosses the room now and then, at rest only.
        _wave_t -= delta
        if LivingWorld.gust_x != INF:
            LivingWorld.gust_x += LivingWorld.gust_dir * 260.0 * delta
            if absf(LivingWorld.gust_x) > room.room_size.x * 0.5 + 200.0:
                LivingWorld.gust_x = INF
        elif _wave_t <= 0.0:
            _wave_t = 14.0 + float(int(_t * 7.0) % 10)
            if calm:
                LivingWorld.gust_dir = 1.0 if int(_t) % 2 == 0 else -1.0
                LivingWorld.gust_x = -LivingWorld.gust_dir * (room.room_size.x * 0.5 + 150.0)
        if candle_light != null:
            var lit := false
            for pc in pieces:
                lit = lit or (pc["k"] == "candle" and pc["st"] == "live")
            candle_light.visible = lit
        var step := int(_t * 8.0)
        var gusting := LivingWorld.gust_x != INF
        if step != _step or (_dirty and _t - _last_draw > 1.0 / 20.0) or (gusting and _t - _last_draw > 1.0 / 12.0):
            _step = step
            _dirty = false
            _last_draw = _t
            queue_redraw()

    ## Sway in whole texels at the tip: a slow wave with a per-piece phase, stepped; plus a
    ## lean (contact, gale, blasts, void) and the room gust passing.
    func _sway(pc: Dictionary) -> float:
        var st := String(pc["st"])
        if st == "frozen" or st == "shattered" or st == "burnt":
            return 0.0
        var fight := ArtPass.fight_of(room)
        var amp := (1.0 - 0.5 * fight) * (0.5 if st == "wilted" else 1.0)
        var s := sin(float(_step) / 8.0 * 1.6 + float(pc["ph"])) * amp
        if gust_t > 0.0:
            s += gust.x * 2.0 * gust_t / 1.2
        s += float(pc.get("lean", 0.0))
        s += LivingWorld.gust_at((pc["p"] as Vector2).x) * 2.0 * (1.0 - fight)
        if pc.has("zap"):
            s += 1.0 if int(_t * 15.0) % 2 == 0 else -1.0
        return roundf(clampf(s, -3.0, 3.0))

    func _tint(pc: Dictionary, c: Color) -> Color:
        # In a fight the answers stay small (readability): no white flash, a faint crackle.
        var quiet := ArtPass.fight_of(room) > 0.5
        if int(pc.get("fl", 0)) > 0 and not quiet:
            return Color(1.0, 1.0, 1.0)
        if pc.has("zap"):
            var k := (0.7 if int(_t * 15.0) % 2 == 0 else 0.3) * (0.35 if quiet else 1.0)
            return c.lerp(Color(0.85, 0.95, 1.0), k)
        match String(pc["st"]):
            "burnt":
                return Color(0.10, 0.08, 0.07)
            "frozen", "shattered":
                return c.lerp(Color(0.70, 0.85, 1.0), 0.6)
            "wet":
                return c.darkened(0.3)
            "wilted":
                return c.lerp(Color(0.36, 0.30, 0.12), 0.65)
            "sprout":
                return c.lightened(0.15)
        return c

    func _draw() -> void:
        var lt: Texture2D = Art.PARTICLES["light"]
        var mc: Color = recipe["moss"]
        # Moss mats: a low veil, close to the floor's value; a burnt mat is a dark patch.
        for pc in pieces:
            if pc["k"] == "moss":
                var p: Vector2 = pc["p"]
                var r := Vector2(84, 48)
                var st := String(pc["st"])
                var c := mc if st == "live" or st == "sprout" else _tint(pc, mc)
                draw_texture_rect(lt, Rect2(p - r, r * 2.0), false, Color(c, 0.45 if st != "burnt" else 0.6))
        # Leaf litter and pebbles: single texels, dim.
        var leaf := [Color(0.30, 0.26, 0.12), Color(0.24, 0.30, 0.12), Color(0.34, 0.22, 0.10)]
        for l in litter:
            draw_rect(Rect2(l[0], Vector2(tx * 2.0, tx)), Color(leaf[int(l[1])], 0.8))
        for c in cracks:
            draw_polyline(c, Color(0.0, 0.0, 0.0, 0.35), tx)
        var sc: Color = recipe["stone"]
        for pb in pebbles:
            var s: float = float(pb[1]) * tx
            draw_rect(Rect2(pb[0] - Vector2(tx, tx) * 0.5, Vector2(s + tx, s)), Color(0.02, 0.02, 0.02, 0.7))
            draw_rect(Rect2(pb[0], Vector2(s, s - tx * 0.5)), sc.darkened(0.15))
        # The landmark: a sunken ring of old flagstones with an offering in the middle.
        if landmark != Vector2.INF:
            var c := landmark
            for i in 14:
                var a := TAU * float(i) / 14.0
                var q := _snap(c + Vector2(cos(a) * 30.0, sin(a) * 18.0))
                draw_rect(Rect2(q - Vector2(3, 2) * tx, Vector2(6, 4) * tx), Color(0.03, 0.03, 0.03, 0.8))
                draw_rect(Rect2(q - Vector2(2, 2) * tx, Vector2(5, 3) * tx), sc.darkened(0.1))
                draw_rect(Rect2(q - Vector2(2, 2) * tx, Vector2(5, 1) * tx), sc.lightened(0.15))
            draw_texture_rect(lt, Rect2(c - Vector2(24, 14), Vector2(48, 28)), false, Color(0, 0, 0, 0.45))
            var bc: Color = recipe["bone"]
            draw_rect(Rect2(_snap(c) - Vector2(4, 2) * tx, Vector2(8, 3) * tx), Color(0.03, 0.02, 0.02))
            draw_rect(Rect2(_snap(c) - Vector2(3, 2) * tx, Vector2(6, 2) * tx), Color(0.40, 0.30, 0.20))
            draw_rect(Rect2(_snap(c) + Vector2(-1, -4) * tx, Vector2(3, 2) * tx), bc.darkened(0.15))
        # Plants.
        var fire := [Color(1.0, 0.84, 0.36), Color(1.0, 0.50, 0.14)]
        var fstep := int(_t * 12.0)
        for pc in pieces:
            var k := String(pc["k"])
            var p: Vector2 = pc["p"]
            var st := String(pc["st"])
            if k == "grass":
                var sw := _sway(pc)
                var base := _tint(pc, mc.lightened(0.10))
                var tip := _tint(pc, mc.lightened(0.42))
                if st == "burning":
                    tip = fire[(fstep + int(p.x)) % 2]
                for b in 3:
                    var bx := p.x + float(b - 1) * tx * 1.0
                    var h := 2 + (b % 2) + (1 if st == "live" else 0)
                    if st == "burnt" or st == "shattered" or st == "sprout":
                        h = 1
                    elif st == "wilted":
                        h = maxi(1, h - 1)
                    draw_rect(Rect2(bx, p.y - float(h) * tx, tx, float(h) * tx), base)
                    draw_rect(Rect2(bx + sw * tx * float(b % 2 + 1) * 0.5, p.y - float(h + 1) * tx, tx, tx), tip)
                    if st == "shattered" and b == 1:
                        draw_rect(Rect2(bx, p.y - tx * 2.0, tx, tx), Color(0.92, 0.97, 1.0))
                if st == "burning" and (fstep + int(p.y)) % 3 != 0:
                    draw_rect(Rect2(p.x + sw * tx, p.y - 5.0 * tx, tx, tx), fire[(fstep + 1) % 2])
            elif k == "fern":
                var sw := _sway(pc)
                var base := _tint(pc, mc.lightened(0.05))
                var tip := _tint(pc, mc.lightened(0.30))
                if st == "burning":
                    tip = fire[(fstep + int(p.x)) % 2]
                draw_rect(Rect2(p - Vector2(3, 0) * tx, Vector2(7, 1) * tx), Color(0, 0, 0, 0.35))
                var segs := 1 if st == "burnt" or st == "shattered" or st == "sprout" else 3
                var droop := 1.0 if st == "wilted" else 0.0
                for f in 5:
                    var dirx := float(f - 2)
                    var q := p
                    for sgm in segs:
                        q += Vector2(dirx * 0.8 + (sw * 0.5 if sgm == segs - 1 else 0.0), -1.0 + (droop if sgm == segs - 1 else 0.0)) * tx
                        draw_rect(Rect2(_snap(q), Vector2(tx, tx)), base if sgm < segs - 1 else tip)
            elif k == "candle":
                draw_rect(Rect2(p, Vector2(tx, tx * 3.0)), Color(0.80, 0.76, 0.64))
                if st != "out":
                    var fl := 1 if sin(_t * 11.0 + float(pc["ph"])) > 0.3 else 0
                    draw_rect(Rect2(p - Vector2(0, tx * float(1 + fl)), Vector2(tx, tx * float(1 + fl))), Color(1.0, 0.80, 0.36))
                else:
                    draw_rect(Rect2(p - Vector2(0, tx), Vector2(tx, tx)), Color(0.20, 0.18, 0.16))


## Small life over the floor (z 26, under the foreground): moths circling the wall lights,
## leaves drifting down the sun shafts. Single dim texels moving slowly, never round,
## glowing or red, so nothing reads as a shot.
class Critters extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var lamps: Array = []
    var pools: Array = []
    var tx := 2.3
    var _t := 0.0

    func _init() -> void:
        name = "Critters"
        z_index = 26
        z_as_relative = false

    func _process(delta: float) -> void:
        _t += delta
        if Engine.get_process_frames() % 3 == 0:
            queue_redraw()

    func _draw() -> void:
        var a := 0.75 * (1.0 - 0.5 * ArtPass.fight)
        for i in lamps.size():
            var c: Vector2 = lamps[i]
            for m in 2:
                var ph := float(i) * 2.1 + float(m) * 3.3
                var q := c + Vector2(cos(_t * 1.7 + ph) * 18.0, sin(_t * 2.3 + ph) * 12.0 + 14.0)
                var flap := 1.0 if int(_t * 10.0 + ph) % 2 == 0 else 2.0
                draw_rect(Rect2((q / tx).round() * tx, Vector2(tx * flap, tx)), Color(0.86, 0.80, 0.66, a))
        for i in pools.size():
            var c: Vector2 = pools[i]
            for m in 2:
                var f := fmod(_t * 0.07 + float(m) * 0.5 + float(i) * 0.31, 1.0)
                var q := c + Vector2(-0.38, -1.0).normalized() * (1.0 - f) * 190.0 + Vector2(sin(_t * 1.3 + float(m) * 2.0) * 10.0, 0)
                var col := Color(0.62, 0.50, 0.20, a * sin(PI * f))
                draw_rect(Rect2((q / tx).round() * tx, Vector2(tx * 2.0, tx)), col)


# --- PostFx ---------------------------------------------------------------------

static var _floor_k := -1.0
static var _floor_base: Array = []


## At rest the floor gets its colour back (Room.FLAT_FLOOR eased towards `rest_floor`);
## in a fight it is the clarity pass's flat backdrop again.
static func _floor_grade(o: Node) -> void:
    if not (o is Room) or not recipe.has("rest_floor"):
        return
    var mat := Room.flat_floor_material()
    if _floor_base.is_empty():
        _floor_base = [mat.get_shader_parameter("sat"), mat.get_shader_parameter("contrast"), mat.get_shader_parameter("mid")]
        for i in 3:
            if _floor_base[i] == null:
                _floor_base[i] = [0.5, 0.6, 0.08][i]
    if absf(fight - _floor_k) < 0.01:
        return
    _floor_k = fight
    var rf: Array = recipe["rest_floor"]
    for i in 3:
        mat.set_shader_parameter(["sat", "contrast", "mid"][i], lerpf(float(rf[i]), float(_floor_base[i]), fight))


## Puts the floor material back (scenes without the pass, or the pass suppressed).
static func reset_floor() -> void:
    if _floor_base.is_empty():
        return
    var mat := Room.flat_floor_material()
    for i in 3:
        mat.set_shader_parameter(["sat", "contrast", "mid"][i], float(_floor_base[i]))
    _floor_k = -1.0

const MAX_LIGHTS := 16


## The uniforms PostFx needs this frame: on, ambient, grade, vignette, lights in screen
## space (xy uv, z radius in screen heights, w energy) and colours (rgb, a scatter).
static func frame_uniforms(tree: SceneTree, vp: Viewport, size: Vector2, t: float) -> Dictionary:
    if not active() or size.y <= 0.0:
        if _floor_k >= 0.0:
            reset_floor()
        return {}
    var o: Node = owner_ref.get_ref()
    var want := 1.0 if (o is Room and (o as Room).active) else 0.0
    var dt := clampf(t - _last_t, 0.0, 0.1) if _last_t >= 0.0 else 1.0
    _last_t = t
    fight = move_toward(fight, want, dt * 1.2)
    var xf := vp.get_canvas_transform()
    var zoom := xf.get_scale().y
    var cand: Array = []
    var pl: Array = recipe["player"]
    if recipe.has("player_fight") and fight > 0.0:
        var pf: Array = recipe["player_fight"]
        pl = [(pl[0] as Color).lerp(pf[0], fight), lerpf(pl[1], pf[1], fight), lerpf(pl[2], pf[2], fight), lerpf(pl[3], pf[3], fight), lerpf(pl[4], pf[4], fight)]
    for p in tree.get_nodes_in_group("players"):
        var n := p as Node2D
        if n != null and n.visible:
            cand.append([n.global_position + Vector2(0, -6), float(pl[1]), pl[0], float(pl[2]), float(pl[3]), 0.0, float(pl[4])])
    for l in tree.get_nodes_in_group("art_lights"):
        var li := l as Light
        if li != null and li.is_visible_in_tree():
            cand.append([li.global_position, li.radius, li.color, li.energy, li.scatter, li.flicker, li.hard])
    var pos := PackedVector4Array()
    var col := PackedVector4Array()
    var hk := PackedFloat32Array()
    var screen := Rect2(Vector2.ZERO, size)
    for c in cand:
        if pos.size() >= MAX_LIGHTS:
            break
        var sp: Vector2 = xf * (c[0] as Vector2)
        var rad: float = float(c[1]) * zoom
        if not screen.grow(rad).has_point(sp):
            continue
        var fl: float = c[5]
        var k := 1.0
        if fl > 0.0:
            var ph := (c[0] as Vector2).x * 0.37 + (c[0] as Vector2).y * 0.11
            k = 1.0 + fl * (0.10 * sin(t * 9.0 + ph) + 0.06 * sin(t * 23.0 + ph * 2.0) + 0.04 * sin(t * 4.1 + ph))
        var cc: Color = c[2]
        pos.append(Vector4(sp.x / size.x, sp.y / size.y, rad / size.y, float(c[3]) * k))
        # Scatter (the visible pools) fades out in a fight: the paired test put it at
        # -0.002 shot contrast, the only number the pass moved.
        col.append(Vector4(cc.r, cc.g, cc.b, float(c[4]) * k * (1.0 - fight)))
        hk.append(float(c[6]))
    while pos.size() < MAX_LIGHTS:
        pos.append(Vector4.ZERO)
        col.append(Vector4.ZERO)
        hk.append(2.0)
    var amb: Color = (recipe["ambient"] as Color).lerp(Color.WHITE, fight)
    _floor_grade(o)
    var lift: Color = (recipe["lift"] as Color).lerp(Color(0, 0, 0), fight)
    var gain: Color = (recipe["gain"] as Color).lerp(Color.WHITE, fight)
    return {
        "light_on": 1.0, "ambient": Vector3(amb.r, amb.g, amb.b),
        "grade_lift": Vector3(lift.r, lift.g, lift.b), "grade_gain": Vector3(gain.r, gain.g, gain.b),
        "light_p": pos, "light_c": col, "light_k": hk, "light_cap": lerpf(float(recipe.get("cap", 1.0)), 1.0, fight), "vignette": lerpf(float(recipe["vignette"]), 0.75, fight),
    }


# --- The Hollow ---------------------------------------------------------------------


## The hub: lights on its torches, the Fire and the Gate, and the Gatewarden's room (the
## Stair) dressed as a gatehouse: a lit gate arch with steps down, a hearth brazier, a
## records table by the Gatewarden, a weapon rack, banners and a runner to the Gate.
static func dress_hub(hub: Node2D, amb: Ambience, stair: Rect2, gate: Vector2, fire: Vector2, walls_layer: int) -> void:
    if not use("hollow", hub):
        return
    var r := recipe
    var tx := Themes.texel(1.0)
    var hearth := Vector2(stair.position.x + 92.0, stair.position.y + 96.0)
    amb.add_light(hearth, "brazier")
    for l in amb.lights:
        var big := String(l[1]) != "torch"
        add_light(hub, (l[0] as Vector2) + Vector2(0, 10), 280.0 if big else 230.0, r["fire"], 0.75 if big else 0.8, 0.05, 0.6)

    var bottom := stair.end.y
    add_light(hub, Vector2(gate.x, bottom - 10.0), 300.0, r["spill"], 1.0, 0.10, 0.15)
    var table := Vector2(stair.position.x + 72.0, stair.position.y + 322.0)
    add_light(hub, Vector2(stair.end.x - 46.0, stair.position.y + 236.0), 200.0, Color(1.0, 0.78, 0.45), 0.7, 0.05, 0.5)
    add_light(hub, table + Vector2(-22, -26), 120.0, Color(1.0, 0.75, 0.42), 0.55, 0.04, 0.8)
    var body := StaticBody2D.new()
    body.collision_layer = walls_layer
    body.collision_mask = 0
    hub.add_child(body)
    var shapes := [[hearth + Vector2(0, 8), Vector2(56, 30)], [table, Vector2(84, 30)],
        [Vector2(gate.x - 92.0, bottom - 22.0), Vector2(34, 44)], [Vector2(gate.x + 92.0, bottom - 22.0), Vector2(34, 44)]]
    for s in shapes:
        var cs := CollisionShape2D.new()
        var rs := RectangleShape2D.new()
        rs.size = s[1]
        cs.shape = rs
        cs.position = s[0]
        body.add_child(cs)
    # Living touches (living world): cobwebs in the corners, iron chains with lanterns that
    # swing when the player brushes past, moths round the hearth and the lanterns.
    var ch := LivingWorld.Chains.new()
    ch.tx = tx
    ch.z_index = 0
    var lanterns := [Vector2(stair.position.x + 250.0, stair.position.y - 14.0), Vector2(stair.end.x - 150.0, stair.position.y - 14.0)]
    for a in lanterns:
        ch.add("lantern", a, 9, tx * 2.0, Color(0.30, 0.30, 0.33))
        add_light(hub, a + Vector2(0, tx * 18.0), 150.0, Color(1.0, 0.76, 0.42), 0.6, 0.04, 0.5)
    for c in [stair.position, Vector2(stair.end.x, stair.position.y)]:
        var sx := 1.0 if c.x < gate.x else -1.0
        for k in 4:
            var dir := Vector2(sx * cos(0.15 + float(k) * 0.45), sin(0.15 + float(k) * 0.45))
            var ln := 22.0 + float(k % 2) * 10.0
            ch.add("web", c + Vector2(sx * 2.0, 2.0), 2, ln, Color(0.82, 0.82, 0.78))
            ch.chains[-1]["pts"][1] = c + Vector2(sx * 2.0, 2.0) + dir * ln
            ch.chains[-1]["old"][1] = ch.chains[-1]["pts"][1]
    hub.add_child(ch)
    var moths := Critters.new()
    moths.tx = tx
    moths.lamps = [hearth + Vector2(0, -26)]
    for a in lanterns:
        moths.lamps.append(a + Vector2(0, tx * 18.0))
    hub.add_child(moths)
    for m in [0, 1]:
        var d := HubStairDressing.new()
        d.stair = stair
        d.gate = gate
        d.hearth = hearth
        d.table = table
        d.tx = tx
        d.mode = m
        d.z_index = -1 if m == 0 else 0
        hub.add_child(d)


class HubStairDressing extends Node2D:
    func _enter_tree() -> void:
        add_to_group("art_dressing")

    var stair: Rect2
    var gate: Vector2
    var hearth: Vector2
    var table: Vector2
    var tx := 3.0
    var mode := 0     # 0 floor (rug, shadows, clutter, table), 1 the gatehouse over the floor
    var _t := 0.0

    func _ready() -> void:
        texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

    func _process(delta: float) -> void:
        _t += delta
        if mode == 1 and Engine.get_process_frames() % 3 == 0:
            queue_redraw()

    func _s(p: Vector2) -> Vector2:
        return (p / tx).round() * tx

    func _icon(path: String, at: Vector2, k: float, rot: float = 0.0, tint: Color = Color.WHITE) -> void:
        var t: Texture2D = Art.icon(path)
        if t == null:
            return
        var s := t.get_size() * tx * k
        draw_set_transform(at, rot, Vector2.ONE)
        draw_texture_rect(t, Rect2(-s / 2.0, s), false, tint)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    func _draw() -> void:
        if mode == 1:
            _draw_gatehouse()
            return
        var lt: Texture2D = Art.PARTICLES["light"]
        var r := stair
        # Contact shadow along the walls.
        for k in 6:
            var a := 0.32 * (1.0 - float(k) / 6.0)
            var w := tx * 2.0
            draw_rect(Rect2(r.position.x, r.position.y + float(k) * w, r.size.x, w), Color(0, 0, 0, a * 1.3))
            draw_rect(Rect2(r.position.x + float(k) * w, r.position.y, w, r.size.y), Color(0, 0, 0, a))
            draw_rect(Rect2(r.end.x - float(k + 1) * w, r.position.y, w, r.size.y), Color(0, 0, 0, a))
            draw_rect(Rect2(r.position.x, r.end.y - float(k + 1) * w, r.size.x, w), Color(0, 0, 0, a * 0.7))
        # The runner: from the doorway down to the Gate, a dark red cloth with a border.
        var rug := Rect2(_s(Vector2(gate.x - 33.0, r.position.y + 24.0)), _s(Vector2(66.0, gate.y - r.position.y - 58.0)))
        draw_rect(rug.grow(tx), Color(0.03, 0.02, 0.02, 0.9))
        draw_rect(rug, Color(0.30, 0.07, 0.07))
        draw_rect(rug.grow(-tx * 2.0), Color(0.62, 0.46, 0.20), false, tx)
        draw_rect(rug.grow(-tx * 4.0), Color(0.22, 0.05, 0.06))
        var y := rug.position.y + tx * 10.0
        while y < rug.end.y - tx * 10.0:
            var c := Vector2(rug.get_center().x, y)
            draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4) * tx, c + Vector2(4, 0) * tx, c + Vector2(0, 4) * tx, c + Vector2(-4, 0) * tx]), Color(0.46, 0.14, 0.10))
            draw_rect(Rect2(_s(c) - Vector2(tx, tx) * 0.5, Vector2(tx, tx)), Color(0.70, 0.52, 0.22))
            y += tx * 16.0
        draw_rect(Rect2(rug.position.x, rug.end.y - tx * 2.0, rug.size.x, tx * 2.0), Color(0, 0, 0, 0.35))
        # Hearth: soot and a stone ring under the brazier, firewood beside it.
        draw_texture_rect(lt, Rect2(hearth + Vector2(-70, -4), Vector2(140, 52)), false, Color(0.03, 0.02, 0.01, 0.8))
        for i in 12:
            var a := TAU * float(i) / 12.0
            var p := _s(hearth + Vector2(cos(a) * 40.0, sin(a) * 16.0 + 26.0))
            draw_rect(Rect2(p - Vector2(3, 2) * tx, Vector2(6, 4) * tx), Color(0.02, 0.02, 0.02))
            draw_rect(Rect2(p - Vector2(2, 2) * tx, Vector2(4, 3) * tx), Color(0.36, 0.33, 0.30))
            draw_rect(Rect2(p - Vector2(2, 2) * tx, Vector2(4, 1) * tx), Color(0.55, 0.50, 0.45))
        for i in 3:
            var p := _s(hearth + Vector2(62.0 + float(i % 2) * 6.0, 16.0 - float(i) * 7.0))
            draw_rect(Rect2(p - Vector2(8, 2) * tx, Vector2(14, 3) * tx), Color(0.03, 0.02, 0.01))
            draw_rect(Rect2(p - Vector2(7, 1) * tx, Vector2(12, 2) * tx), Color(0.34, 0.20, 0.10))
            draw_rect(Rect2(p - Vector2(7, 1) * tx, Vector2(2, 2) * tx), Color(0.62, 0.44, 0.26))
        # The records table: a heavy plank top, legs, the open ledger, books, a candle.
        var top := Rect2(_s(table - Vector2(42, 20)), _s(Vector2(84, 30)))
        draw_texture_rect(lt, Rect2(top.position + Vector2(-10, 18), Vector2(top.size.x + 20, 34)), false, Color(0, 0, 0, 0.7))
        for lx in [top.position.x + tx * 2.0, top.end.x - tx * 4.0]:
            draw_rect(Rect2(lx, top.end.y - tx, tx * 2.0, tx * 6.0), Color(0.16, 0.09, 0.05))
        draw_rect(top.grow(tx), Color(0.03, 0.02, 0.01))
        draw_rect(top, Color(0.40, 0.25, 0.13))
        draw_rect(Rect2(top.position, Vector2(top.size.x, tx)), Color(0.62, 0.42, 0.24))
        draw_rect(Rect2(top.position.x, top.end.y - tx * 3.0, top.size.x, tx * 3.0), Color(0.24, 0.14, 0.07))
        var led := Rect2(_s(table + Vector2(-6, -16)), Vector2(14, 8) * tx)
        draw_rect(led.grow(tx), Color(0.05, 0.03, 0.02))
        draw_rect(led, Color(0.86, 0.80, 0.64))
        draw_rect(Rect2(led.position + Vector2(led.size.x / 2.0 - tx * 0.5, 0), Vector2(tx, led.size.y)), Color(0.45, 0.36, 0.26))
        for k in 3:
            draw_rect(Rect2(led.position + Vector2(tx, tx * (2.0 + float(k) * 2.0)), Vector2(tx * 5.0, tx * 0.6)), Color(0.30, 0.24, 0.20))
            draw_rect(Rect2(led.position + Vector2(tx * 8.0, tx * (2.0 + float(k) * 2.0)), Vector2(tx * 5.0, tx * 0.6)), Color(0.30, 0.24, 0.20))
        _icon("item/book/book_gray.png", table + Vector2(26, -12), 0.32)
        _icon("item/book/book_indigo.png", table + Vector2(30, -4), 0.32, 0.2)
        _icon("item/scroll/scroll-brown.png", table + Vector2(-30, -8), 0.3, -0.4)
        draw_rect(Rect2(_s(table + Vector2(-24, -28)), Vector2(3, 6) * tx), Color(0.86, 0.82, 0.70))
        # Barrels and crates in the right-hand corners.
        _barrel(Vector2(stair.end.x - 40.0, stair.end.y - 46.0))
        _barrel(Vector2(stair.end.x - 76.0, stair.end.y - 34.0))
        _crate(Vector2(stair.end.x - 52.0, stair.position.y + 250.0))
        _crate(Vector2(stair.end.x - 40.0, stair.position.y + 284.0))
        _icon("item/misc/misc_lantern.png", Vector2(stair.end.x - 52.0, stair.position.y + 232.0), 0.4)
        # The Gatewarden's corner (living world): a cot with a bedroll, a chest, a shelf of
        # ledgers against the wall and straw on the floor, so the room is lived in.
        var cot := Rect2(_s(Vector2(stair.end.x - 176.0, stair.position.y + 130.0)), _s(Vector2(76.0, 30.0)))
        draw_texture_rect(lt, Rect2(cot.position + Vector2(-10, 16), Vector2(cot.size.x + 20, 28)), false, Color(0, 0, 0, 0.65))
        for i in 26:
            var h := (i * 2654435761) & 0xFFFF
            var q := _s(cot.get_center() + Vector2(float(h % 160) - 80.0, float((h >> 8) % 60) - 18.0))
            draw_rect(Rect2(q, Vector2(tx * 2.0, tx)), Color(0.62, 0.54, 0.30, 0.55))
        draw_rect(cot.grow(tx), Color(0.03, 0.02, 0.01))
        draw_rect(cot, Color(0.34, 0.21, 0.11))
        var bed := cot.grow(-tx * 2.0)
        draw_rect(bed, Color(0.22, 0.26, 0.22))
        draw_rect(Rect2(bed.position, Vector2(bed.size.x * 0.62, bed.size.y)), Color(0.28, 0.32, 0.26))
        draw_rect(Rect2(bed.position + Vector2(bed.size.x * 0.62, 0), Vector2(tx, bed.size.y)), Color(0.16, 0.18, 0.15))
        draw_rect(Rect2(bed.end.x - tx * 8.0, bed.position.y + tx, tx * 7.0, bed.size.y - tx * 2.0), Color(0.78, 0.74, 0.62))
        draw_rect(Rect2(bed.end.x - tx * 8.0, bed.position.y + tx, tx * 7.0, tx), Color(0.92, 0.88, 0.76))
        var chest := Rect2(_s(Vector2(cot.position.x - 40.0, cot.position.y + 4.0)), _s(Vector2(28.0, 20.0)))
        draw_texture_rect(lt, Rect2(chest.position + Vector2(-6, chest.size.y - 6), Vector2(chest.size.x + 12, 14)), false, Color(0, 0, 0, 0.7))
        draw_rect(chest.grow(tx), Color(0.03, 0.02, 0.01))
        draw_rect(chest, Color(0.40, 0.24, 0.12))
        draw_rect(Rect2(chest.position, Vector2(chest.size.x, tx * 3.0)), Color(0.50, 0.32, 0.16))
        for bx in [chest.position.x + tx * 2.0, chest.end.x - tx * 3.0]:
            draw_rect(Rect2(bx, chest.position.y, tx, chest.size.y), Color(0.30, 0.30, 0.32))
        draw_rect(Rect2(chest.get_center() - Vector2(tx, 0), Vector2(tx * 2.0, tx * 2.0)), Color(0.80, 0.66, 0.30))
        var shelf := Rect2(_s(Vector2(stair.end.x - 22.0, stair.position.y + 84.0)), _s(Vector2(18.0, 96.0)))
        draw_rect(shelf.grow(tx), Color(0.03, 0.02, 0.01))
        draw_rect(shelf, Color(0.30, 0.18, 0.09))
        var spines := [Color(0.42, 0.12, 0.10), Color(0.16, 0.26, 0.36), Color(0.52, 0.44, 0.22), Color(0.24, 0.32, 0.18), Color(0.36, 0.30, 0.26)]
        for row in 4:
            var y0 := shelf.position.y + tx * 2.0 + float(row) * shelf.size.y / 4.0
            draw_rect(Rect2(shelf.position.x, y0 + shelf.size.y / 4.0 - tx * 2.0, shelf.size.x, tx), Color(0.46, 0.30, 0.15))
            for b in 4:
                draw_rect(Rect2(shelf.position.x + tx, y0 + float(b) * tx * 2.2, shelf.size.x - tx * 2.0, tx * 1.6), spines[(row * 3 + b) % spines.size()])
        # Weapon rack against the top wall, right of the doorway.
        var rack := Rect2(_s(Vector2(stair.position.x + 470.0, stair.position.y + 2.0)), _s(Vector2(150.0, 54.0)))
        draw_texture_rect(lt, Rect2(rack.position + Vector2(-10, rack.size.y - 8), Vector2(rack.size.x + 20, 26)), false, Color(0, 0, 0, 0.6))
        for px in [rack.position.x, rack.end.x - tx * 3.0]:
            draw_rect(Rect2(px - tx, rack.position.y - tx, tx * 5.0, rack.size.y + tx * 2.0), Color(0.03, 0.02, 0.01))
            draw_rect(Rect2(px, rack.position.y, tx * 3.0, rack.size.y), Color(0.36, 0.22, 0.11))
        for k in 2:
            var by := rack.position.y + tx * (4.0 + float(k) * 9.0)
            draw_rect(Rect2(rack.position.x, by - tx, rack.size.x, tx * 3.0), Color(0.03, 0.02, 0.01))
            draw_rect(Rect2(rack.position.x, by, rack.size.x, tx), Color(0.48, 0.30, 0.15))
        var weapons := ["item/weapon/greatsword_2.png", "item/weapon/battle_axe_2.png", "item/weapon/demon_trident.png", "item/weapon/broad_axe_1.png", "item/weapon/ancient_sword.png"]
        for k in weapons.size():
            _icon(String(weapons[k]), Vector2(rack.position.x + 18.0 + float(k) * 28.0, rack.position.y + 26.0), 0.45, -0.785, Color(0.85, 0.82, 0.78))
        # Banners either side of the doorway, hanging over the wall face.
        var ban := Themes.tex("wall/banners/banner_1.png")
        for sx in [-1.0, 1.0]:
            var s := ban.get_size() * tx * 0.9
            draw_texture_rect(ban, Rect2(_s(Vector2(gate.x + sx * 125.0 - s.x / 2.0, stair.position.y - 54.0)), s), false, Color(0.86, 0.80, 0.74))

    func _barrel(c: Vector2) -> void:
        var r := Rect2(_s(c - Vector2(10, 13)), _s(Vector2(20, 26)))
        draw_texture_rect(Art.PARTICLES["light"], Rect2(r.position + Vector2(-6, r.size.y - 6), Vector2(r.size.x + 12, 14)), false, Color(0, 0, 0, 0.7))
        draw_rect(r.grow(tx), Color(0.03, 0.02, 0.01))
        draw_rect(r, Color(0.38, 0.22, 0.11))
        draw_rect(Rect2(r.position, Vector2(tx, r.size.y)), Color(0.52, 0.33, 0.17))
        for k in [0.2, 0.75]:
            draw_rect(Rect2(r.position.x, r.position.y + r.size.y * k, r.size.x, tx), Color(0.20, 0.20, 0.22))
        draw_rect(Rect2(r.position, Vector2(r.size.x, tx * 2.0)), Color(0.24, 0.14, 0.07))

    func _crate(c: Vector2) -> void:
        var r := Rect2(_s(c - Vector2(13, 11)), _s(Vector2(26, 22)))
        draw_texture_rect(Art.PARTICLES["light"], Rect2(r.position + Vector2(-6, r.size.y - 6), Vector2(r.size.x + 12, 14)), false, Color(0, 0, 0, 0.7))
        draw_rect(r.grow(tx), Color(0.03, 0.02, 0.01))
        draw_rect(r, Color(0.42, 0.28, 0.14))
        draw_rect(r.grow(-tx * 2.0), Color(0.32, 0.20, 0.10))
        draw_line(r.position + Vector2(tx * 2.0, tx * 2.0), r.end - Vector2(tx * 2.0, tx * 2.0), Color(0.46, 0.30, 0.15), tx)
        draw_rect(Rect2(r.position, Vector2(r.size.x, tx)), Color(0.62, 0.44, 0.24))

    ## The Gate as a building: stone towers either side of the stairs, a lintel with a
    ## keystone, a raised portcullis, cold light breathing up the steps; the candle flame.
    func _draw_gatehouse() -> void:
        var bottom := stair.end.y
        var td := Themes.def("ruins")
        var wall_list: Array = td["wall"]
        var tint: Color = (td["wall_tint"] as Color) * Color(1.25, 1.25, 1.25)
        var hi: Color = td["edge"]
        var lt: Texture2D = Art.PARTICLES["light"]
        var breathe := 0.85 + 0.15 * sin(_t * 1.4)
        draw_texture_rect(lt, Rect2(Vector2(gate.x - 120.0, bottom - 110.0), Vector2(240, 170)), false, Color(0.45, 0.90, 1.0, 0.22 * breathe))
        for sx in [-1.0, 1.0]:
            var tower := Rect2(_s(Vector2(gate.x + sx * 92.0 - 20.0, bottom - 64.0)), _s(Vector2(40.0, 124.0)))
            draw_rect(tower.grow(tx), Color(0.02, 0.02, 0.02))
            Themes.draw_tiles(self, wall_list, tower, global_position, tx, 811, tint)
            draw_rect(Rect2(tower.position, Vector2(tower.size.x, tx * 2.0)), Color(hi, 0.95))
            draw_rect(Rect2(tower.position + Vector2(0, tx * 2.0), Vector2(tower.size.x, tx)), Color(hi, 0.4))
            var shade_x := tower.end.x - tx * 2.0 if sx > 0 else tower.position.x
            draw_rect(Rect2(shade_x, tower.position.y, tx * 2.0, tower.size.y), Color(0, 0, 0, 0.45))
            var cap := Rect2(tower.position - Vector2(tx * 2.0, tx * 5.0), Vector2(tower.size.x + tx * 4.0, tx * 5.0))
            draw_rect(cap.grow(tx), Color(0.02, 0.02, 0.02))
            draw_rect(cap, tint * Color(0.42, 0.42, 0.40))
            draw_rect(Rect2(cap.position, Vector2(cap.size.x, tx)), Color(hi, 0.9))
            var lamp := cap.get_center() + Vector2(0, -tx * 6.0)
            draw_texture_rect(lt, Rect2(lamp - Vector2(26, 26), Vector2(52, 52)), false, Color(0.5, 0.95, 1.0, 0.45 * breathe))
            draw_rect(Rect2(_s(lamp) - Vector2(2, 3) * tx, Vector2(4, 5) * tx), Color(0.03, 0.04, 0.05))
            draw_rect(Rect2(_s(lamp) - Vector2(1, 2) * tx, Vector2(2, 3) * tx), Color(0.70, 1.0, 1.0))
        var lin := Rect2(_s(Vector2(gate.x - 76.0, bottom - 22.0)), _s(Vector2(152.0, 18.0)))
        draw_rect(lin.grow(tx), Color(0.02, 0.02, 0.02))
        Themes.draw_tiles(self, wall_list, lin, global_position, tx, 812, tint * Color(0.9, 0.9, 0.9))
        draw_rect(Rect2(lin.position, Vector2(lin.size.x, tx)), Color(hi, 0.9))
        var key := Rect2(_s(Vector2(gate.x - 9.0, bottom - 28.0)), _s(Vector2(18.0, 24.0)))
        draw_rect(key.grow(tx), Color(0.02, 0.02, 0.02))
        draw_rect(key, tint * Color(0.5, 0.5, 0.48))
        draw_rect(Rect2(key.position, Vector2(key.size.x, tx)), Color(hi, 1.0))
        draw_rect(Rect2(_s(key.get_center()) - Vector2(1, 2) * tx, Vector2(2, 4) * tx), Color(0.55, 1.0, 1.0, 0.9 * breathe))
        for k in 7:
            var x := lin.position.x + tx * 4.0 + float(k) * (lin.size.x - tx * 8.0) / 6.0
            draw_rect(Rect2(_s(Vector2(x, lin.end.y)), Vector2(tx * 2.0, tx * 3.0)), Color(0.10, 0.10, 0.12))
            draw_rect(Rect2(_s(Vector2(x, lin.end.y + tx * 3.0)), Vector2(tx * 2.0, tx)), Color(0.40, 0.42, 0.46))
        var f := _s(table + Vector2(-24, -28) + Vector2(tx, -tx * 2.0))
        var h := 2.0 + (1.0 if sin(_t * 13.0) > 0.2 else 0.0)
        draw_rect(Rect2(f - Vector2(0, h * tx - tx * 2.0), Vector2(tx, h * tx)), Color(1.0, 0.75, 0.30))
        draw_rect(Rect2(f + Vector2(0, tx), Vector2(tx, tx)), Color(1.0, 0.95, 0.70))
