class_name GunFx
extends Node2D
## Short-lived shapes for the instant gun mechanics: the arc a melee sweep cuts and the
## line a charged rail leaves. One node per swing or rail, a few lines a frame, gone in a
## fraction of a second.

var kind := ""
var a := Vector2.ZERO      # sweep: centre; rail: start
var b := Vector2.ZERO      # rail: end
var dir := Vector2.RIGHT
var reach := 0.0
var half := 0.0
var width := 3.0
var color := Color.WHITE
var back := false
var shape := ""
var life := 0.2
var _t := 0.0
static var _add_material: CanvasItemMaterial


## A melee sweep: an arc of `half` radians either side of `p_dir`, `p_reach` long, drawn
## as a blade edge travelling across it (reversed for a back swing).
static func sweep(parent: Node, c: Vector2, p_dir: Vector2, p_reach: float, p_half: float, col: Color, p_back := false) -> void:
    var g := GunFx.new()
    g.kind = "sweep"
    g.a = c
    g.dir = p_dir
    g.reach = p_reach
    g.half = p_half
    g.color = col
    g.back = p_back
    g.life = 0.18
    parent.add_child(g)


## A melee smear (Arsenal expansion 2.3): the swing's shape at 35% alpha for 0.1 s,
## drawn by WeaponLooks.draw_smear. `p_shape`: a style, or "spin" for a full circle.
static func smear(parent: Node, c: Vector2, p_dir: Vector2, p_reach: float, p_half: float, col: Color, p_back: bool, p_shape: String) -> void:
    var g := GunFx.new()
    g.kind = "smear"
    g.shape = p_shape
    g.a = c
    g.dir = p_dir
    g.reach = p_reach
    g.half = p_half
    g.color = col
    g.back = p_back
    g.life = 0.1
    parent.add_child(g)


## A rail: a bright line a..b that thins out.
static func rail(parent: Node, p_a: Vector2, p_b: Vector2, w: float, col: Color) -> void:
    var g := GunFx.new()
    g.kind = "rail"
    g.a = p_a
    g.b = p_b
    g.width = maxf(2.0, w)
    g.color = col
    g.life = 0.3
    parent.add_child(g)


func _ready() -> void:
    modulate.a = Settings.own_fx()   # "Your effects" (friend or foe, see Hostile)
    top_level = true
    z_index = 6
    add_to_group("gun_fx")
    if _add_material == null:
        _add_material = CanvasItemMaterial.new()
        _add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    material = _add_material


func _process(delta: float) -> void:
    _t += delta
    if _t >= life:
        queue_free()
        return
    queue_redraw()


func _draw() -> void:
    var f := clampf(_t / life, 0.0, 1.0)
    match kind:
        "smear":
            WeaponLooks.draw_smear(self, shape, a, dir, reach, half, color, back, f)
        "sweep":
            # The swept area fades; the edge runs from one side to the other.
            var from := -half if not back else half
            var to := half if not back else -half
            var edge := lerpf(from, to, minf(1.0, f * 1.6))
            var pts := PackedVector2Array([a])
            var n := 10
            for k in n + 1:
                pts.append(a + dir.rotated(lerpf(from, edge, float(k) / float(n))) * reach)
            draw_colored_polygon(pts, Color(color, 0.3 * (1.0 - f)))
            var e := dir.rotated(edge)
            draw_line(a + e * reach * 0.35, a + e * reach, Color(1, 1, 1, 0.9 * (1.0 - f)), 3.0)
            draw_line(a + e * reach * 0.25, a + e * reach * 1.04, Color(color, 0.6 * (1.0 - f)), 6.0)
            draw_arc(a, reach, dir.angle() + from, dir.angle() + edge, 14, Color(color, 0.9 * (1.0 - f)), 3.0)
        "rail":
            var w := width * (1.0 - f)
            draw_line(a, b, Color(color, 0.25 * (1.0 - f)), w * 4.0 + 2.0)
            draw_line(a, b, Color(color, 0.85 * (1.0 - f)), w * 1.5 + 1.0)
            draw_line(a, b, Color(1, 1, 1, 1.0 - f), maxf(1.0, w * 0.5))
            draw_circle(b, width * 2.0 * (1.0 - f) + 1.0, Color(color, 0.7 * (1.0 - f)))
