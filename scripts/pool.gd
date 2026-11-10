class_name Pool
extends Node2D
## What a thrower's flask leaves where it lands (Projectile behaviour "pool"): a patch of
## its element `radius` px across for `life` seconds. Every GunData.POOL_TICK it hits each
## enemy inside at the strike's damage (no shove) and re-applies the element, so it denies
## ground rather than bursting. Landing lays the element on the floor (Materials: acid
## fizzes, oil slicks, poison gas drifts), touches props and door obstacles and reacts with
## clouds. Pools never hurt players. Drawn as a faint disc and rim; the floor layer does
## the rest.

var strike: Strike
var radius := 50.0
var life := 3.0
var _life0 := 3.0
var _tick := 0.0
var _t := 0.0


func _init(s: Strike, p_radius: float, p_life: float) -> void:
    strike = s
    radius = maxf(20.0, p_radius)
    life = maxf(0.5, p_life)
    _life0 = life
    z_index = -1


func _ready() -> void:
    modulate.a = Settings.own_fx()   # "Your effects" (friend or foe, see Hostile)
    add_to_group("gun_fx")
    var tree := get_tree()
    strike.stamp(self, global_position, radius * 0.8, true)
    strike.touch_world(tree, global_position, radius * 0.6, Vector2.ZERO)
    strike.touch_clouds(tree, global_position, radius * 0.6, {})
    var fx := Strike.fx_of(self)
    if fx != null:
        fx.signature(strike.element, global_position, clampf(radius * 0.6, 20.0, 50.0), 0.5)
    Sfx.play_at("burst_small", global_position, -6.0)


func _physics_process(delta: float) -> void:
    _t += delta
    life -= delta
    if life <= 0.0:
        queue_free()
        return
    _tick -= delta
    if _tick <= 0.0:
        _tick = GunData.POOL_TICK
        var holy := strike.gun_id == "holy_water"
        for e in Strike.enemies_in(get_tree(), global_position, radius):
            strike.hit(e, 1.0, e.global_position)
            if holy and is_instance_valid(e) and not e.is_queued_for_deletion():
                e.marked_t = maxf(e.marked_t, GunData.POOL_TICK + 0.1)   # Holy Water: reactions inside hit harder
        var fx := Strike.fx_of(self)
        if fx != null:
            fx.mote(strike.element, global_position + Vector2.RIGHT.rotated(randf() * TAU) * radius * randf())
        queue_redraw()


func _draw() -> void:
    var fade := clampf(life / 0.6, 0.0, 1.0) * clampf(_t / 0.15, 0.0, 1.0)
    var c := strike.color
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.8))
    draw_circle(Vector2.ZERO, radius, Color(c, 0.10 * fade))
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(c, 0.35 * fade), 1.5)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
