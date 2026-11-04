class_name Fx
extends Node2D
## Immediate-mode effects: lightning arcs, rings, floating text, particle puffs on a
## normal layer and an additive glow layer, corpses, bone bits and floor scorches.

const MAX_PUFFS := 180

var main: Main
var _arcs: Array = []      # { a, b, t }
var _rings: Array = []     # { pos, r, color, t, life }
var _texts: Array = []     # { pos, text, color, t, life }
var _puffs: Array = []     # normal blend
var _add_puffs: Array = [] # additive blend
var _corpses: Array = []   # { tex, pos, scale, color, flip, rot, t, life }
var _scorches: Array = []  # { pos, size, rot, t, life }
var _add: AddLayer
var _ground: GroundLayer


class AddLayer extends Node2D:
    var fx: Fx
    func _draw() -> void:
        fx._draw_puffs(fx._add_puffs, self)


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
            puff(P["spark"], position, Color(color, 0.95), 110.0, 0.3, true)
            puff(P["light"], position, Color(1, 1, 0.8, 0.7), 80.0, 0.2, true)
            _shake(3.0)
        "Steam":
            for i in 4:
                var v := Vector2(randf_range(-40, 40), randf_range(-90, -40))
                puff(P["smoke"], position + Vector2(randf_range(-20, 20), 0), Color(0.85, 0.9, 0.92, 0.55), randf_range(90, 140), 0.9, false, v, 0.3)
            _rings.append({ "pos": position, "r": 130.0, "color": Color(0.9, 0.95, 1.0, 0.5), "t": 0.35, "life": 0.35 })
            _shake(2.0)
        "Deep Freeze":
            puff(P["magic"], position, Color(0.75, 0.95, 1.0, 0.9), 130.0, 0.5, true, Vector2.ZERO, 0.2)
            for i in 6:
                var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(80, 160)
                puff(P["circle"], position, Color(0.8, 0.97, 1.0, 0.9), 14.0, 0.45, true, v)
            _shake(3.0)
        "Inferno":
            puff(P["flame"], position, Color(1.0, 0.55, 0.15, 0.95), 170.0, 0.5, true, Vector2(0, -30))
            puff(P["flame"], position + Vector2(0, -20), Color(1.0, 0.85, 0.3, 0.8), 110.0, 0.35, true, Vector2(0, -60))
            for i in 3:
                puff(P["smoke"], position, Color(0.15, 0.12, 0.12, 0.6), randf_range(80, 120), 1.1, false, Vector2(randf_range(-30, 30), -70), 0.3)
            scorch(position, 120.0)
            _shake(5.0)
        "Ignition":
            puff(P["spark"], position, Color(1.0, 0.95, 0.5, 0.95), 90.0, 0.25, true)
            puff(P["flame"], position, Color(1.0, 0.6, 0.2, 0.9), 100.0, 0.4, true, Vector2(0, -40))
            scorch(position, 70.0)
            _shake(3.0)
        "Fire Nova":
            puff(P["flame"], position, Color(1.0, 0.5, 0.15, 0.95), 260.0, 0.55, true)
            puff(P["light"], position, Color(1.0, 0.7, 0.3, 0.6), 320.0, 0.3, true)
            scorch(position, 220.0)
            _shake(9.0)
        "Frost Nova":
            puff(P["magic"], position, Color(0.75, 0.95, 1.0, 0.95), 280.0, 0.6, true, Vector2.ZERO, 0.15)
            for i in 10:
                var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(120, 260)
                puff(P["circle"], position, Color(0.85, 0.98, 1.0, 0.9), 16.0, 0.5, true, v)
            _shake(9.0)
        "Shield broken!":
            puff(P["light"], position, Color(1, 1, 1, 0.9), 220.0, 0.35, true)
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
            var additive := key != "smoke"
            puff(P[key], position, Color(color, 0.9 if additive else 0.55), minf(size, 320.0), 0.5, additive, Vector2(0, -20) if key == "smoke" else Vector2.ZERO)
            if key == "smoke":
                for i in 2:
                    puff(P["smoke"], position + Vector2(randf_range(-20, 20), 0), Color(color, 0.4), size * 0.7, 0.9, false, Vector2(randf_range(-30, 30), -60), 0.3)
            _shake(3.0)


func _on_nova(position: Vector2, radius: float, color: Color) -> void:
    _rings.append({ "pos": position, "r": radius, "color": color, "t": 0.45, "life": 0.45 })
    puff(Art.PARTICLES["light"], position, Color(color, 0.5), radius * 1.8, 0.35, true)


# --- Frame -----------------------------------------------------------------


func _process(delta: float) -> void:
    for list in [_arcs, _rings, _texts, _puffs, _add_puffs, _corpses, _scorches]:
        for i in range(list.size() - 1, -1, -1):
            list[i]["t"] -= delta
            if list[i]["t"] <= 0.0:
                list.remove_at(i)
    for t in _texts:
        t["pos"].y -= 34.0 * delta
    for list in [_puffs, _add_puffs]:
        for p in list:
            p["pos"] += p["vel"] * delta
            p["vel"] = p["vel"].move_toward(Vector2.ZERO, 120.0 * delta)
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
        var size := int(14 + 10 * pop)
        draw_string(Art.FONT, t["pos"] + Vector2(-99, 1), t["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, Color(0, 0, 0, col.a * 0.8))
        draw_string(Art.FONT, t["pos"] + Vector2(-100, 0), t["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, col)
