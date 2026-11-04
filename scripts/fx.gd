class_name Fx
extends Node2D
## Immediate-mode effects: lightning arcs, rings, floating text, particle puffs on a
## normal layer and an additive glow layer, corpses, bone bits and floor scorches.

const MAX_PUFFS := 180
const MAX_TEXTS := 48

var main: Main
var _arcs: Array = []      # { a, b, t }
var _rings: Array = []     # { pos, r, color, t, life }
var _texts: Array = []     # { pos, text, color, t, life }
var _puffs: Array = []     # normal blend
var _add_puffs: Array = [] # additive blend
var _corpses: Array = []   # { tex, pos, scale, color, flip, rot, t, life }
var _scorches: Array = []  # { pos, size, rot, t, life }
var _books: Array = []     # { sheet, pos, size, color, rot, t, life, add, vel, loops }
var _add: AddLayer
var _ground: GroundLayer


class AddLayer extends Node2D:
    var fx: Fx
    func _draw() -> void:
        fx._draw_puffs(fx._add_puffs, self)
        fx._draw_books(self, true)


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
    Elements.lightning_arc.connect(_on_arc)
    Elements.reaction_fired.connect(_on_reaction)
    Elements.nova.connect(_on_nova)


# --- Public spawners -------------------------------------------------------


func puff(tex: Texture2D, pos: Vector2, color: Color, size: float, life: float, additive := false, vel := Vector2.ZERO, spin := 0.6) -> void:
    var list := _add_puffs if additive else _puffs
    list.append({ "tex": tex, "pos": pos, "color": color, "size": size, "rot": randf() * TAU, "t": life, "life": life, "vel": vel, "spin": spin })
    if list.size() > MAX_PUFFS:
        list.pop_front()


## Play an animation sheet once (or `loops` times) at `pos`, `size` pixels wide.
func book(sheet: String, pos: Vector2, size: float, life: float, color := Color.WHITE, additive := true, rot := 0.0, vel := Vector2.ZERO, loops := 1) -> void:
    _books.append({ "sheet": sheet, "pos": pos, "size": size, "color": color, "rot": rot, "t": life, "life": life, "add": additive, "vel": vel, "loops": loops })
    if _books.size() > 60:
        _books.pop_front()


## The ring explosion sheet tinted to a colour, sized to a radius.
func blast(pos: Vector2, radius: float, color: Color, life := 0.55) -> void:
    book("ring", pos, radius * 2.3, life, Color(color.lightened(0.25), 0.95), true, randf() * TAU)


## A spread of spears or bolts flying out from a point.
func radial(sheet: String, pos: Vector2, count: int, speed: float, color: Color, life := 0.45, size := 56.0) -> void:
    for i in count:
        var a := TAU * float(i) / float(count) + randf_range(-0.2, 0.2)
        book(sheet, pos, size, life, color, true, a, Vector2.RIGHT.rotated(a) * speed)


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
    puff(Art.PARTICLES["spark"], to, Color(1.0, 0.97, 0.6, 0.9), 70.0, 0.25, true)


func _on_reaction(reaction_name: String, position: Vector2, color: Color) -> void:
    # Reactions speak through their visuals; only events that need words get text.
    if reaction_name in ["ELITE", "Shield broken!", "Shield restored!", "Path opened!"]:
        _texts.append({ "pos": position + Vector2(0, -30), "text": reaction_name, "color": color, "t": 0.95, "life": 0.95 })
    Sfx.reaction(reaction_name)
    var P := Art.PARTICLES
    match reaction_name:
        "Chain Lightning":
            book("thunder", position, 120.0, 0.35, Color(1.0, 1.0, 0.85, 0.95), true, randf() * TAU)
            puff(P["light"], position, Color(1, 1, 0.8, 0.6), 80.0, 0.2, true)
            _shake(3.0)
        "Steam":
            for i in 4:
                var v := Vector2(randf_range(-40, 40), randf_range(-90, -40))
                puff(P["smoke"], position + Vector2(randf_range(-20, 20), 0), Color(0.85, 0.9, 0.92, 0.55), randf_range(90, 140), 0.9, false, v, 0.3)
            _rings.append({ "pos": position, "r": 130.0, "color": Color(0.9, 0.95, 1.0, 0.5), "t": 0.35, "life": 0.35 })
            _shake(2.0)
        "Deep Freeze":
            book("cold_fire", position, 110.0, 0.5, Color(0.8, 0.97, 1.0, 0.95), true, 0.0, Vector2(0, -20))
            radial("icespear", position, 6, 140.0, Color(0.85, 0.98, 1.0, 0.95), 0.4, 48.0)
            _shake(3.0)
        "Inferno":
            blast(position, 70.0, Color(1.0, 0.55, 0.15), 0.5)
            for i in 3:
                book("fire", position + Vector2(randf_range(-30, 30), randf_range(-10, 10)), randf_range(70, 110), 0.7, Color(1.0, 0.8, 0.5, 0.95), true, 0.0, Vector2(0, -40))
                puff(P["smoke"], position, Color(0.15, 0.12, 0.12, 0.6), randf_range(80, 120), 1.1, false, Vector2(randf_range(-30, 30), -70), 0.3)
            scorch(position, 120.0)
            _shake(5.0)
        "Ignition":
            book("thunder", position, 90.0, 0.25, Color(1.0, 1.0, 0.7, 0.95), true, randf() * TAU)
            book("fire", position, 90.0, 0.5, Color(1.0, 0.75, 0.4, 0.95), true, 0.0, Vector2(0, -40))
            scorch(position, 70.0)
            _shake(3.0)
        "Fire Nova":
            blast(position, 130.0, Color(1.0, 0.5, 0.15), 0.7)
            radial("fireball", position, 10, 260.0, Color(1.0, 0.8, 0.5, 0.95), 0.5, 64.0)
            scorch(position, 220.0)
            _shake(9.0)
        "Frost Nova":
            blast(position, 130.0, Color(0.6, 0.9, 1.0), 0.7)
            radial("icespear", position, 12, 240.0, Color(0.85, 0.98, 1.0, 0.95), 0.55, 56.0)
            _shake(9.0)
        "Shield broken!":
            blast(position, 90.0, Color(1, 1, 1), 0.4)
            _shake(5.0)
        "Shield restored!":
            puff(P["light"], position, Color(0.8, 0.9, 1.0, 0.8), 180.0, 0.4, true)
        "Path opened!":
            puff(P["light"], position, Color(1, 1, 0.9, 0.9), 240.0, 0.5, true)
            _shake(4.0)
        "ELITE":
            puff(P["light"], position, Color(1.0, 0.85, 0.3, 0.8), 160.0, 0.6, true)
        _:
            # Data-driven reactions: the table names a texture; size follows what it does.
            var d := Elements.def_by_name(reaction_name)
            var key: String = d.get("fx", "circle")
            var size := 100.0
            for act in d.get("do", []):
                if act[0] in ["burst", "apply", "pull", "push", "cloud", "slow"] and act.size() > 1:
                    for v in act.slice(1):
                        if v is float or v is int:
                            size = maxf(size, float(v) * 1.1)
                            break
            size = minf(size, 320.0)
            match key:
                "smoke":
                    puff(P["smoke"], position, Color(color, 0.55), size, 0.5, false, Vector2(0, -20))
                    for i in 2:
                        puff(P["smoke"], position + Vector2(randf_range(-20, 20), 0), Color(color, 0.4), size * 0.7, 0.9, false, Vector2(randf_range(-30, 30), -60), 0.3)
                "flame":
                    blast(position, size * 0.45, color, 0.5)
                    book("fire", position, size * 0.7, 0.55, Color(color.lightened(0.4), 0.95), true, 0.0, Vector2(0, -40))
                "spark":
                    book("thunder", position, size * 0.9, 0.3, Color(color.lightened(0.5), 0.95), true, randf() * TAU)
                    puff(P["spark"], position, Color(color, 0.8), size * 0.8, 0.25, true)
                "magic":
                    book("cold_fire", position, size * 0.8, 0.5, Color(color.lightened(0.4), 0.95), true, 0.0, Vector2(0, -20))
                    radial("icespear", position, 5, size * 1.2, color.lightened(0.3), 0.35, 44.0)
                _:
                    blast(position, size * 0.45, color, 0.45)
                    if key == "twirl":
                        puff(P["twirl"], position, Color(color, 0.8), size, 0.5, true)
            _shake(3.0)


func _on_nova(position: Vector2, radius: float, color: Color) -> void:
    _rings.append({ "pos": position, "r": radius, "color": color, "t": 0.45, "life": 0.45 })
    blast(position, radius * 0.9, color, 0.5)


# --- Frame -----------------------------------------------------------------


func _process(delta: float) -> void:
    for list in [_arcs, _rings, _texts, _puffs, _add_puffs, _corpses, _scorches, _books]:
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
    for b in _books:
        b["pos"] += b["vel"] * delta
    queue_redraw()
    _add.queue_redraw()
    _ground.queue_redraw()


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


func _draw_books(canvas: CanvasItem, additive: bool) -> void:
    for b in _books:
        if b["add"] != additive:
            continue
        var k: float = 1.0 - b["t"] / b["life"]
        var col: Color = b["color"]
        col.a *= clampf((1.0 - k) * 4.0, 0.0, 1.0)   # hold, then a quick fade at the end
        var frame_k: float = fmod(k * float(b["loops"]), 1.0)
        Art.draw_frame(canvas, b["sheet"], frame_k, b["pos"], b["size"], col, b["rot"])


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
    _draw_books(self, false)
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
        var k: float = 1.0 - r["t"] / r["life"]
        var col: Color = r["color"]
        col.a *= 1.0 - k
        draw_arc(r["pos"], r["r"] * (0.4 + 0.6 * k), 0.0, TAU, 56, col, 4.0 * (1.0 - k) + 1.0)
    for t in _texts:
        var elapsed: float = t["life"] - t["t"]
        var pop: float = clampf(elapsed / 0.12, 0.0, 1.0)
        var col: Color = t["color"]
        col.a = clampf(t["t"] / 0.5, 0.0, 1.0)
        var size := int(t.get("size", 20) + 6 * pop)
        draw_string(Art.FONT, t["pos"] + Vector2(-99, 1), t["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, Color(0, 0, 0, col.a * 0.8))
        draw_string(Art.FONT, t["pos"] + Vector2(-100, 0), t["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, col)
