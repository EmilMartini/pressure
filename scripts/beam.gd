class_name Beam
extends Node2D
## A continuous ray held by a beam gun (Gun mechanic "beam"). The gun calls tick() at its
## fire rate while it has a target (or RT is held); each tick hits the first 1 + pierce
## enemies on the ray. Between ticks the ray keeps drawing and turns toward the latest aim
## at Gun.beam_sweep() rad/s, so a beam sweeps across a crowd rather than snapping. It
## stops at interior walls, the room's edge, pillars and door obstacles (which take its
## element, as do props it ends on, at most every PROP_GAP s), reacts once with each cloud
## it crosses per second, and acid and fire beams etch the floor where they end.
## Drawing is three lines and two circles a frame (no per-pixel loops).

const LINGER := 0.16      # seconds a beam stays drawn after its last tick
const PROP_GAP := 0.3
const CLOUD_GAP := 1.0
const SFX_GAP := 0.2

var gun: Gun
var dir := Vector2.RIGHT
var want := Vector2.RIGHT
var origin := Vector2.ZERO
var end := Vector2.ZERO
var color := Color.WHITE
var width := 3.0
var element: int = Element.Kind.NONE
var _shown := 0.0
var _t := 0.0
var _prop_cd := 0.0
var _cloud_cd := 0.0
var _sfx_cd := 0.0
var _paint_cd := 0.0
var _clouds: Dictionary = {}
var _hit_points: Array = []
var _segs: Array = []   # reflect (Glint Beam): [from, to] after each bounce off a wall
static var _add_material: CanvasItemMaterial


func _init(p_gun: Gun) -> void:
    gun = p_gun
    z_index = 5
    visible = false
    top_level = true


func _ready() -> void:
    modulate.a = Settings.own_fx()   # "Your effects" (friend or foe, see Hostile)
    add_to_group("gun_fx")
    if _add_material == null:
        _add_material = CanvasItemMaterial.new()
        _add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    material = _add_material


func _process(delta: float) -> void:
    if gun == null or not is_instance_valid(gun) or not gun.is_inside_tree():
        queue_free()
        return
    _t += delta
    _prop_cd -= delta
    _sfx_cd -= delta
    _paint_cd -= delta
    _cloud_cd -= delta
    if _cloud_cd <= 0.0:
        _cloud_cd = CLOUD_GAP
        _clouds.clear()
    if _shown <= 0.0:
        visible = false
        return
    _shown -= delta
    var turn := gun.beam_sweep() * delta
    dir = dir.rotated(clampf(dir.angle_to(want), -turn, turn))
    origin = gun.global_position + dir * 12.0
    # The drawn end follows the sweep between ticks (cheap: the trace is a few cell reads).
    if _segs.is_empty():
        var reach := origin.distance_to(end)
        end = origin + dir * reach
    queue_redraw()


## One tick of damage along the ray, after turning toward `aim` this frame.
func tick(aim: Vector2, s: Strike, reach: float, pierce: int, w: float) -> void:
    want = aim
    if _shown <= 0.0:
        dir = aim   # a fresh beam starts on target
    _shown = LINGER + 1.0 / maxf(1.0, gun.fire_rate())
    visible = true
    color = s.color
    element = s.element
    width = w
    origin = gun.global_position + dir * 12.0
    var tree := get_tree()
    var tr: Array = Strike.trace(tree, origin, dir, reach)
    end = tr[0]
    var hits := Strike.enemies_on_line(tree, origin, end, w)
    _hit_points.clear()
    var n := mini(hits.size(), 1 + pierce)
    for i in n:
        var e: Enemy = hits[i]
        s.hit(e, 1.0, e.global_position)
        _hit_points.append(e.global_position)
    if n == 1 + pierce and n > 0:
        # Pierce spent: the ray ends in the last body it burned through.
        var last: Enemy = hits[n - 1]
        end = origin + dir * maxf(8.0, (last.global_position - origin).dot(dir))
    elif tr[1] != null and _prop_cd <= 0.0:
        _prop_cd = PROP_GAP
        s.touch_world(tree, end, 6.0, dir)
    _segs.clear()
    if gun.data.ricochets > 0 and tr[1] == null and n < 1 + pierce:
        _reflect(s, tree, reach - origin.distance_to(end), pierce, w, hits)
    var length := origin.distance_to(end)
    var steps := int(length / 60.0)
    for k in steps + 1:
        s.touch_clouds(tree, origin.lerp(end, float(k) / float(maxi(1, steps))), 8.0, _clouds)
    if gun.data.paint_every > 0.0 and _paint_cd <= 0.0:
        _paint_cd = gun.data.paint_every
        s.stamp(self, end, 9.0, false)
    var fx := Strike.fx_of(self)
    if fx != null:
        fx.stream(element, end, -dir * 60.0, 2, 1.2)
    if _sfx_cd <= 0.0:
        _sfx_cd = SFX_GAP
        Sfx.shoot(element, origin)


## Glint Beam: the ray bounces off walls and the room's edge `ricochets` times; each leg hits
## the first 1 + pierce foes it crosses that the ray has not hit this tick.
func _reflect(s: Strike, tree: SceneTree, left: float, pierce: int, w: float, seen: Array) -> void:
    var p := end
    var d := dir
    var rm := Room.here
    for r in gun.data.ricochets:
        if left <= 12.0 or rm == null or not is_instance_valid(rm):
            return
        var box := Rect2(rm.global_position + rm.rect.position, rm.rect.size).grow(8.0)
        var bx := p + Vector2(d.x * 8.0, 0.0)
        var by := p + Vector2(0.0, d.y * 8.0)
        var flip_x := not box.has_point(bx) or (rm.has_walls and rm.blocks_shot(bx))
        var flip_y := not box.has_point(by) or (rm.has_walls and rm.blocks_shot(by))
        if not flip_x and not flip_y:
            flip_x = true
            flip_y = true
        d = Vector2(-d.x if flip_x else d.x, -d.y if flip_y else d.y)
        var a := p + d * 6.0
        var tr2: Array = Strike.trace(tree, a, d, left)
        var b: Vector2 = tr2[0]
        var k := 0
        for e in Strike.enemies_on_line(tree, a, b, w):
            if seen.has(e):
                continue
            seen.append(e)
            s.hit(e, 1.0, e.global_position)
            _hit_points.append(e.global_position)
            k += 1
            if k >= 1 + pierce:
                b = a + d * maxf(8.0, (e.global_position - a).dot(d))
                _segs.append([a, b])
                return
        _segs.append([a, b])
        left -= a.distance_to(b)
        p = b
        if tr2[1] != null:
            return


func _draw() -> void:
    for sg in _segs:
        draw_line(sg[0], sg[1], Color(color, 0.14), width * 2.6)
        draw_line(sg[0], sg[1], Color(color, 0.6), width * 0.8)
    var a := origin
    var b := end
    var flick := 0.8 + 0.2 * sin(_t * 47.0)
    draw_line(a, b, Color(color, 0.18), width * 3.2 * flick)
    draw_line(a, b, Color(color, 0.75), width * flick)
    draw_line(a, b, Color(1, 1, 1, 0.8), maxf(1.0, width * 0.35))
    draw_circle(a, width * 1.1, Color(color, 0.7))
    draw_circle(b, width * (1.4 + 0.4 * sin(_t * 31.0)), Color(color, 0.6))
    for p in _hit_points:
        draw_circle(p, width * 1.6, Color(1, 1, 1, 0.25))
