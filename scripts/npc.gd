class_name Npc
extends RefCounted
## The Hollow's people: names, colours and looks. Figures are drawn in code by FigureGen
## (a theme blend, no worn gear), larger than the player so they read on a TV, with a rim
## in the NPC's colour like the player's.

const SCALE := 3.5
const DEFS := {
    "keeper": { "name": "THE KEEPER", "profile": { "fire": 3.0, "vagrant": 2.0 }, "color": Color(1.0, 0.72, 0.38) },
    "gatewarden": { "name": "THE GATEWARDEN", "profile": { "plate": 3.0, "stone": 1.5 }, "color": Color(0.62, 0.88, 1.0) },
    "archivist": { "name": "THE ARCHIVIST", "profile": { "arcane": 3.0, "poison": 1.5 }, "color": Color(0.78, 1.0, 0.55) },
}


static func display_name(id: String) -> String:
    return String(DEFS[id]["name"])


static func color(id: String) -> Color:
    return DEFS[id]["color"]


static func figure(id: String) -> Dictionary:
    return FigureGen.generate_from(DEFS[id]["profile"], Color(0, 0, 0, 0))


## The NPC standing at `at` (feet), breathing; `lit` when a player is close. `chained`
## adds shackles and two chains running up to the wall behind.
static func draw(ci: CanvasItem, id: String, at: Vector2, t: float, lit: bool, chained: bool = false, scale: float = SCALE) -> void:
    var fig := figure(id)
    var frames: Array = fig["frames"]
    var tex: Texture2D = frames[0]
    var c := color(id)
    var sz := tex.get_size() * scale
    var breathe := 1.0 + sin(t * 1.7 + float(id.length())) * 0.025
    var centre := at + Vector2(0, -sz.y / 2.0)
    ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := sz.x * (2.2 if lit else 1.6)
    ci.draw_texture_rect(glow, Rect2(centre - Vector2(g, g) / 2.0, Vector2(g, g)), false, Color(c, 0.22 if lit else 0.10))
    _ellipse(ci, at + Vector2(0, -2), Vector2(sz.x * 0.45, sz.x * 0.16), Color(0, 0, 0, 0.5))
    if chained:
        for side in [-1.0, 1.0]:
            var wrist := centre + Vector2(side * sz.x * 0.36, sz.y * 0.08)
            var anchor := at + Vector2(side * sz.x * 1.1, -sz.y * 1.55)
            _chain(ci, anchor, wrist)
    ci.draw_set_transform(centre + Vector2(0, sz.y * (1.0 - breathe) / 2.0), 0.0, Vector2(scale, scale * breathe))
    var rim := FigureGen.rim(tex)
    if rim != null:
        ci.draw_texture(rim, -rim.get_size() / 2.0, Color(c, 0.95 if lit else 0.55))
    ci.draw_texture(tex, -tex.get_size() / 2.0)
    ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if chained:
        for side in [-1.0, 1.0]:
            var wrist := centre + Vector2(side * sz.x * 0.36, sz.y * 0.08)
            ci.draw_rect(Rect2(wrist - Vector2(5, 3), Vector2(10, 6)), Color(0.42, 0.40, 0.42))
            ci.draw_rect(Rect2(wrist - Vector2(5, 3), Vector2(10, 6)), Color(0.08, 0.07, 0.08), false, 1.5)


static func _chain(ci: CanvasItem, a: Vector2, b: Vector2) -> void:
    var n := maxi(3, int(a.distance_to(b) / 9.0))
    for i in n:
        var p := a.lerp(b, (float(i) + 0.5) / float(n))
        # Sag: links hang lower in the middle of the span.
        p.y += sin(PI * (float(i) + 0.5) / float(n)) * 10.0
        var r := Rect2(p - Vector2(3.5, 2.5), Vector2(7, 5)) if i % 2 == 0 else Rect2(p - Vector2(2, 3.5), Vector2(4, 7))
        ci.draw_rect(r, Color(0.08, 0.07, 0.08))
        ci.draw_rect(r.grow(-1.0), Color(0.5, 0.48, 0.5))


static func _ellipse(ci: CanvasItem, at: Vector2, radii: Vector2, col: Color) -> void:
    var pts := PackedVector2Array()
    for i in 20:
        var a := TAU * float(i) / 20.0
        pts.append(at + Vector2(cos(a) * radii.x, sin(a) * radii.y))
    ci.draw_colored_polygon(pts, col)
