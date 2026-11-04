class_name Fx
extends Node2D
## Cheap immediate-mode effects: lightning arcs, expanding rings, floating reaction text.

var _arcs: Array = []    # { a, b, t }
var _rings: Array = []   # { pos, r, color, t, life }
var _texts: Array = []   # { pos, text, color, t }


func _ready() -> void:
    z_index = 20
    Elements.lightning_arc.connect(_on_arc)
    Elements.reaction_fired.connect(_on_reaction)
    Elements.nova.connect(_on_nova)


func _on_arc(from: Vector2, to: Vector2) -> void:
    _arcs.append({ "a": from, "b": to, "t": 0.22 })


func _on_reaction(reaction_name: String, position: Vector2, color: Color) -> void:
    _texts.append({ "pos": position + Vector2(0, -24), "text": reaction_name, "color": color, "t": 0.9 })
    _rings.append({ "pos": position, "r": 40.0, "color": Color(color, 0.7), "t": 0.3, "life": 0.3 })


func _on_nova(position: Vector2, radius: float, color: Color) -> void:
    _rings.append({ "pos": position, "r": radius, "color": color, "t": 0.45, "life": 0.45 })


func _process(delta: float) -> void:
    for list in [_arcs, _rings, _texts]:
        for i in range(list.size() - 1, -1, -1):
            list[i]["t"] -= delta
            if list[i]["t"] <= 0.0:
                list.remove_at(i)
    for t in _texts:
        t["pos"].y -= 30.0 * delta
    queue_redraw()


func _draw() -> void:
    var font := ThemeDB.fallback_font
    for a in _arcs:
        var alpha: float = clampf(a["t"] / 0.22, 0.0, 1.0)
        var pts := PackedVector2Array()
        var from: Vector2 = a["a"]
        var to: Vector2 = a["b"]
        pts.append(from)
        for i in range(1, 5):
            var p: Vector2 = from.lerp(to, float(i) / 5.0)
            p += (to - from).orthogonal().normalized() * randf_range(-10.0, 10.0)
            pts.append(p)
        pts.append(to)
        draw_polyline(pts, Color(1.0, 0.97, 0.5, alpha), 2.5)
    for r in _rings:
        var k: float = 1.0 - r["t"] / r["life"]
        var col: Color = r["color"]
        col.a *= 1.0 - k
        draw_arc(r["pos"], r["r"] * (0.4 + 0.6 * k), 0.0, TAU, 48, col, 3.0)
    for t in _texts:
        var col: Color = t["color"]
        col.a = clampf(t["t"] / 0.9, 0.0, 1.0)
        draw_string(font, t["pos"] + Vector2(-60, 0), t["text"], HORIZONTAL_ALIGNMENT_CENTER, 120, 14, col)
