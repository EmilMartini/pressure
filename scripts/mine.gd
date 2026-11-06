class_name Mine
extends Node2D
## A mine from a mine gun (Gun mechanic "mine"): tossed a short way toward the target, it
## lands, arms after ARM seconds and bursts when an enemy body comes within TRIGGER px (or
## when its life runs out, or when the gun lays one past its cap). The burst hits every
## enemy within `blast` at full damage, lays the element on the floor, touches props and
## door obstacles and reacts with clouds in it. Mines never hurt players.

const ARM := 0.4
const TRIGGER := 22.0
const TOSS := 0.25

var strike: Strike
var blast := 50.0
var life := 8.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _armed := false
var _gone := false


func _init(s: Strike, p_blast: float, p_life: float) -> void:
    strike = s
    blast = maxf(20.0, p_blast)
    life = maxf(1.0, p_life)
    z_index = 3


func _ready() -> void:
    add_to_group("gun_fx")


## Fly from `from` to `to` in a short hop, then settle.
func toss(from: Vector2, to: Vector2) -> void:
    _from = from
    _to = to
    global_position = from


func _physics_process(delta: float) -> void:
    if _gone:
        return
    _t += delta
    if _t < TOSS:
        var f := _t / TOSS
        global_position = _from.lerp(_to, f) + Vector2(0, -sin(PI * f) * 18.0)
        queue_redraw()
        return
    global_position = _to
    if _t >= TOSS + ARM and not _armed:
        _armed = true
    if _armed and not EnemyGrid.overlapping(get_tree(), global_position, TRIGGER).is_empty():
        detonate()
        return
    if _t >= TOSS + life:
        detonate()
        return
    queue_redraw()


func detonate() -> void:
    if _gone or not is_inside_tree():
        return
    _gone = true
    var tree := get_tree()
    var c := global_position
    for e in Strike.enemies_in(tree, c, blast):
        strike.hit(e, 1.0, e.global_position, (e.global_position - c).normalized() * 160.0)
    strike.touch_world(tree, c, blast * 0.6, Vector2.ZERO)
    strike.touch_clouds(tree, c, blast * 0.6, {})
    strike.stamp(self, c, blast * 0.55, true)
    var fx := Strike.fx_of(self)
    if fx != null:
        fx.ring(c, blast, strike.color, 0.28)
        fx.signature(strike.element, c, clampf(blast * 0.5, 20.0, 50.0), 0.45)
    Sfx.play_at("burst_small", c)
    queue_free()


func _draw() -> void:
    var c := strike.color
    draw_set_transform(Vector2(0, 3), 0.0, Vector2(1.0, 0.45))
    draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.4))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    draw_circle(Vector2.ZERO, 5.0, Color(0.16, 0.14, 0.13))
    draw_circle(Vector2.ZERO, 3.5, c.darkened(0.3))
    if _armed:
        var blink := fmod(_t * (2.0 + 4.0 * clampf((_t - TOSS) / life, 0.0, 1.0)), 1.0) < 0.5
        draw_circle(Vector2(0, -1), 1.6, Color(1, 1, 1, 0.95) if blink else c.lightened(0.4))
        draw_arc(Vector2.ZERO, TRIGGER, 0.0, TAU, 20, Color(c, 0.18), 1.0)
