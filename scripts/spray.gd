class_name Spray
extends Node2D
## A short cone held by a sprayer (Gun mechanic "cone"): flame, mist, a gust. The gun calls
## tick() at its fire rate while it has a target (or RT is held); each tick hits every enemy
## whose body is inside the cone, shoving them along it when the gun has knockback. The
## cone paints the floor with its element (Materials.stamp; fire burns bare floor) at most
## every data.paint_every seconds, touches props and door obstacles at most every
## PROP_GAP s and reacts once with each cloud in it per second. The look is element pixels
## streaming along the cone (Fx.stream) over one faint fan polygon.

const LINGER := 0.14
const PROP_GAP := 0.35
const CLOUD_GAP := 1.0
const SFX_GAP := 0.22

var gun: Gun
var dir := Vector2.RIGHT
var reach := 120.0
var half := 0.4
var color := Color.WHITE
var element: int = Element.Kind.NONE
var _shown := 0.0
var _t := 0.0
var _prop_cd := 0.0
var _cloud_cd := 0.0
var _sfx_cd := 0.0
var _paint_cd := 0.0
var _clouds: Dictionary = {}


func _init(p_gun: Gun) -> void:
    gun = p_gun
    z_index = 4
    visible = false
    top_level = true


func _ready() -> void:
    add_to_group("gun_fx")


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
    global_position = gun.player.global_position if is_instance_valid(gun.player) else gun.global_position
    queue_redraw()


func tick(aim: Vector2, s: Strike, p_reach: float, p_half: float, knock: float) -> void:
    dir = dir.slerp(aim, 0.6).normalized() if _shown > 0.0 else aim
    reach = p_reach
    half = p_half
    color = s.color
    element = s.element
    _shown = LINGER + 1.0 / maxf(1.0, gun.fire_rate())
    visible = true
    var c := gun.player.global_position if is_instance_valid(gun.player) else gun.global_position
    global_position = c
    var tree := get_tree()
    for e in Strike.enemies_in_cone(tree, c, dir, reach, half):
        var away: Vector2 = (e.global_position - c).normalized()
        s.hit(e, 1.0, e.global_position, away * knock)
    var mid := c + dir * reach * 0.6
    if _prop_cd <= 0.0:
        _prop_cd = PROP_GAP
        s.touch_world(tree, mid, reach * 0.4, dir)
    s.touch_clouds(tree, mid, reach * 0.45, _clouds)
    if gun.data.paint_every > 0.0 and _paint_cd <= 0.0:
        _paint_cd = gun.data.paint_every
        var at := c + dir.rotated(randf_range(-half, half) * 0.7) * reach * randf_range(0.55, 0.9)
        # Fire sprays burn bare floor (force), liquids pool, a gust clears gas.
        s.stamp(self, at, 14.0, element == Element.Kind.FIRE)
    var fx := Strike.fx_of(self)
    if fx != null:
        var speed := reach * 2.6
        fx.stream(element, c + dir * 14.0, dir * speed, 3, half * 0.9)
    if _sfx_cd <= 0.0:
        _sfx_cd = SFX_GAP
        Sfx.shoot(element, c)


func _draw() -> void:
    var pts := PackedVector2Array()
    pts.append(dir * 10.0)
    var n := 7
    var breathe := 1.0 + 0.04 * sin(_t * 23.0)
    for k in n + 1:
        var a := lerpf(-half, half, float(k) / float(n))
        pts.append(dir.rotated(a) * reach * breathe)
    draw_colored_polygon(pts, Color(color, 0.10))
    draw_polyline(pts.slice(1), Color(color, 0.22), 1.0)
