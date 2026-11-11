class_name RoomPickup
extends Node2D
## Small room pickups (secrets pass, 2026-11-11), Isaac's batteries and small chests. Neither is
## a card and neither heals, so a clear feels like more without more to read (Core loop reset
## 5.1, decision 14).
##   cell   A spark cell: flies to the party at the clear and refills the active item. With the
##          active already full it overcharges by one (Items.recharge_active never takes it back).
##   chest  A small chest standing where the room's scrap burst would have popped: walk or dash
##          into it and it bursts with CHEST_MULT of that burst, sometimes a spark cell too.

const PULL_RANGE := 60.0
const CHEST_MULT := 1.5
const CHEST_CELL := 0.3

var main: Main
var kind := "cell"
var value := 0          # chest: scrap inside
var vacuum := false
var _vel := Vector2.ZERO
var _t := 0.0
var _done := false


func _init(p_main: Main, p_kind: String, p_value: int = 0) -> void:
    main = p_main
    kind = p_kind
    value = p_value
    z_index = 4
    name = "Pickup_" + kind


func _ready() -> void:
    if kind == "cell":
        _vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 120.0)


func _physics_process(delta: float) -> void:
    _t += delta
    queue_redraw()
    if _done:
        return
    var p := main.nearest_alive_player(global_position)
    if p == null:
        return
    var d := p.global_position - global_position
    var dist := d.length()
    if kind == "chest":
        if dist < 30.0:
            _open_chest()
        return
    _vel = _vel.move_toward(Vector2.ZERO, 260.0 * delta)
    position += _vel * delta
    if vacuum:
        position += d.normalized() * minf(dist, 800.0 * delta)
    elif dist < PULL_RANGE:
        position += d.normalized() * minf(dist, 300.0 * delta)
    if dist < 24.0:
        _done = true
        var before := p.active_charges
        var cap := Items.active_max_charges(p)
        p.active_charges = maxi(cap, mini(before + 1, cap + 1)) if cap > 0 else 0
        Sfx.play("confirm", -6.0, 0.05)
        Telemetry.event("pickup", { "floor": main.floor_number, "kind": "cell", "charges": p.active_charges - before })
        queue_free()


func _open_chest() -> void:
    _done = true
    var room := main.current
    if room != null and is_instance_valid(room):
        room.open_chest(self)
    Sfx.play("buy", -2.0)
    Sfx.play("hit_wood", -4.0, 0.05)
    if main.fx != null:
        main.fx.pixels(Element.Kind.STONE, global_position, 12, 120.0, 14.0)
    Telemetry.event("pickup", { "floor": main.floor_number, "kind": "chest", "scrap": value })
    queue_free()


func _draw() -> void:
    draw_circle(Vector2(0, 9), 8.0, Color(0, 0, 0, 0.3))
    if kind == "cell":
        # A small battery: a pale-gold cell with a bright band that pulses.
        var k := 0.5 + 0.5 * sin(_t * 5.0)
        var body := Rect2(-5, -9, 10, 16)
        draw_rect(body.grow(1.5), Color(0.12, 0.10, 0.06))
        draw_rect(body, Color(0.95, 0.80, 0.30))
        draw_rect(Rect2(-5, -3, 10, 4), Color(1.0, 0.98, 0.75, 0.6 + 0.4 * k))
        draw_rect(Rect2(-2.5, -12, 5, 3), Color(0.55, 0.50, 0.45))
        return
    # The chest: dark wood, a brass band and lock; it sways a little to say "open me".
    var sway := sin(_t * 2.4) * 0.6
    var r := Rect2(-12, -10 + sway, 24, 18)
    draw_rect(r.grow(1.5), Color(0.08, 0.05, 0.03))
    draw_rect(r, Color(0.45, 0.28, 0.14))
    draw_rect(Rect2(-12, -10 + sway, 24, 6), Color(0.55, 0.35, 0.18))
    draw_rect(Rect2(-12, -4.5 + sway, 24, 2), Color(0.85, 0.68, 0.30))
    draw_rect(Rect2(-2.5, -5.5 + sway, 5, 5), Color(0.95, 0.80, 0.35))
