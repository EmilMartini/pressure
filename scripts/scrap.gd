class_name Scrap
extends Node2D
## Currency dropped by enemies. Drifts to a nearby player and is collected on touch.

var value := 1
var main: Main
var _vel := Vector2.ZERO


func _init(p_value: int, p_main: Main) -> void:
    value = p_value
    main = p_main
    z_index = 4


func _ready() -> void:
    _vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 220.0)


func _physics_process(delta: float) -> void:
    _vel = _vel.move_toward(Vector2.ZERO, 320.0 * delta)
    position += _vel * delta
    var p := main.nearest_alive_player(global_position)
    if p == null:
        return
    var d := p.global_position - global_position
    var dist := d.length()
    if dist < 180.0:
        position += d.normalized() * 460.0 * delta
    if dist < 24.0:
        main.add_scrap(value)
        queue_free()


func _draw() -> void:
    var s := 5.0 + minf(4.0, float(value))
    draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)]), Color(1.0, 0.85, 0.3))
