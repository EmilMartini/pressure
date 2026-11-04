class_name Scrap
extends Node2D
## Currency dropped by enemies. Drifts to a nearby player and is collected on touch.

var value := 1
var main: Main
var _vel := Vector2.ZERO
var _sprite: Sprite2D


func _init(p_value: int, p_main: Main) -> void:
    value = p_value
    main = p_main
    z_index = 4


func _ready() -> void:
    _vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 220.0)
    _sprite = Art.sprite(Art.TILES["scrap"], 0.9 + minf(0.6, float(value) * 0.1), Art.SCRAP_TINT)
    add_child(_sprite)


func _physics_process(delta: float) -> void:
    _vel = _vel.move_toward(Vector2.ZERO, 320.0 * delta)
    position += _vel * delta
    _sprite.rotation += delta * 4.0
    var p := main.nearest_alive_player(global_position)
    if p == null:
        return
    var d := p.global_position - global_position
    var dist := d.length()
    if dist < 180.0:
        position += d.normalized() * 460.0 * delta
    if dist < 24.0:
        main.add_scrap(value)
        Sfx.play("scrap", 0.0, 0.2)
        queue_free()


func _draw() -> void:
    draw_circle(Vector2(0, 6), 6.0, Color(0, 0, 0, 0.3))
