class_name Turret
extends Node2D
## A turret from a turret gun (Gun mechanic "turret"): set down beside the player, it
## fires the gun's own volley (Gun.shoot_from: same damage, mods, tier and alternating
## elements) at the nearest enemy within the gun's range at the gun's fire rate, for
## `life` seconds. Enemies ignore it; it holds ground where you put it. Freed with its
## gun or its room.

var gun: Gun
var life := 8.0
var _life0 := 8.0
var _cd := 0.3
var _aim := Vector2.RIGHT
var _t := 0.0


func _init(p_gun: Gun, p_life: float) -> void:
    gun = p_gun
    life = maxf(1.0, p_life)
    _life0 = life
    z_index = 2


func _ready() -> void:
    modulate.a = Settings.own_fx()   # "Your effects" (friend or foe, see Hostile)
    add_to_group("gun_fx")
    var fx := Strike.fx_of(self)
    if fx != null:
        fx.ring(global_position, 16.0, gun.data.color(), 0.25)


func _physics_process(delta: float) -> void:
    if gun == null or not is_instance_valid(gun) or not gun.is_inside_tree():
        queue_free()
        return
    _t += delta
    life -= delta
    if life <= 0.0:
        var fx := Strike.fx_of(self)
        if fx != null:
            fx.smoke(global_position, 5, 6.0)
        queue_free()
        return
    _cd -= delta
    if _cd <= 0.0:
        var tgt := Strike.nearest(get_tree(), global_position, gun.effective_range(), {})
        if tgt != null:
            _aim = (tgt.global_position - global_position).normalized()
            gun.shoot_from(global_position + _aim * 10.0, _aim)
            _cd = 1.0 / maxf(0.1, gun.fire_rate())
        else:
            _cd = 0.15
    queue_redraw()


func _draw() -> void:
    var c := gun.data.color() if is_instance_valid(gun) else Color.WHITE
    var f := clampf(life / _life0, 0.0, 1.0)
    draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
    draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.4))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    draw_circle(Vector2.ZERO, 8.0, Color(0.22, 0.2, 0.19))
    draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color(0.8, 0.78, 0.72, 0.8), 1.5)   # pale rim: yours (Hostile)
    draw_circle(Vector2.ZERO, 5.5, c.darkened(0.35))
    draw_line(Vector2.ZERO, _aim * 11.0, Color(0.75, 0.72, 0.68), 3.0)
    draw_circle(_aim * 11.0, 2.0, c)
    # What it has left, as a ring running down.
    draw_arc(Vector2.ZERO, 11.0, -PI * 0.5, -PI * 0.5 + TAU * f, 18, Color(c, 0.6), 1.5)
