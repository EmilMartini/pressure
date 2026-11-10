class_name Heart
extends Node2D
## A heart (Core loop reset 5.1 and 10): heals HEAL_PCT of max health, a chosen heal outside
## the Mending reserve. Dropped by arenas (a chance at the wave's end), elites, challenge and
## secret rooms. It sits where it fell and flies to the party when the room is clear, like
## scrap does. The Greed curse stops hearts from dropping at all (Room.drop_heart).

const HEAL_PCT := 0.12
const PULL_RANGE := 60.0

var main: Main
var vacuum := false
var _vel := Vector2.ZERO
var _t := 0.0


func _init(p_main: Main) -> void:
    main = p_main
    z_index = 4


func _ready() -> void:
    _vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 120.0)


func _physics_process(delta: float) -> void:
    _t += delta
    _vel = _vel.move_toward(Vector2.ZERO, 260.0 * delta)
    position += _vel * delta
    queue_redraw()
    var p := main.nearest_alive_player(global_position)
    if p == null:
        return
    var d := p.global_position - global_position
    var dist := d.length()
    if vacuum:
        position += d.normalized() * minf(dist, 800.0 * delta)
    elif dist < PULL_RANGE:
        position += d.normalized() * minf(dist, 300.0 * delta)
    if dist < 24.0:
        var before := p.hp
        p.heal(p.max_hp * HEAL_PCT, "heart")
        if p.hp > before:
            p.say("+%d" % int(roundf(p.hp - before)))
        Sfx.play("scrap", 0.0, 0.0)
        Telemetry.event("heart", { "floor": main.floor_number, "healed": snappedf(p.hp - before, 0.1) })
        queue_free()


func _draw() -> void:
    var s := 1.0 + 0.08 * sin(_t * 6.0)
    draw_circle(Vector2(0, 9), 7.0, Color(0, 0, 0, 0.3))
    var col := Color(0.95, 0.2, 0.3)
    var pts := PackedVector2Array()
    for i in 24:
        var a := TAU * float(i) / 24.0
        # A heart curve, about 18 px wide.
        var x := 16.0 * pow(sin(a), 3)
        var y := -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))
        pts.append(Vector2(x, y) * 0.6 * s)
    draw_colored_polygon(pts, col)
    draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.02, 0.05), 1.5)
