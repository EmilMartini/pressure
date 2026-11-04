class_name Projectile
extends Area2D
## A bullet. Deals raw damage, then applies its element (which may react).
## Drawn per element: droplets, bolts, embers, shards, tar. Glows add on top.

const LAYER_ENEMIES := 2

static var _add_material: CanvasItemMaterial

var velocity := Vector2.ZERO
var damage := 1.0
var element: int = Element.Kind.NONE
var potency := 1.0
var lifetime := 1.0
var pierce := 0
var radius := 4.0
var color := Color.WHITE
var manual := false
var crit := false
var extra_element: int = Element.Kind.NONE   # from a Coating gun mod
var shooter: Player = null

var _hit: Dictionary = {}
var _trail: Array = []
var _smoke_cd := 0.0


func _ready() -> void:
    collision_layer = 0
    collision_mask = LAYER_ENEMIES | Obstacle.LAYER_OBSTACLES
    monitorable = false
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    add_child(shape)
    body_entered.connect(_on_body_entered)
    z_index = 5
    if element != Element.Kind.OIL:
        if _add_material == null:
            _add_material = CanvasItemMaterial.new()
            _add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        material = _add_material


func _physics_process(delta: float) -> void:
    _trail.push_front(global_position)
    if _trail.size() > 6:
        _trail.pop_back()
    position += velocity * delta
    lifetime -= delta
    for ob in get_tree().get_nodes_in_group("obstacles"):
        if is_instance_valid(ob) and not ob.is_queued_for_deletion() and ob.overlaps(global_position, radius):
            _on_body_entered(ob)
            return
    if element == Element.Kind.FIRE:
        _smoke_cd -= delta
        if _smoke_cd <= 0.0:
            _smoke_cd = 0.07
            var fx := _fx()
            if fx != null:
                fx.puff(Art.PARTICLES["smoke"], global_position, Color(0.25, 0.22, 0.2, 0.45), radius * 4.0, 0.35, false, Vector2(0, -20), 0.5)
    if lifetime <= 0.0:
        if manual and shooter != null and _hit.is_empty():
            shooter.on_projectile_missed()
        queue_free()
    queue_redraw()


func _fx() -> Fx:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        return scene.fx
    return null


func _draw() -> void:
    var dir := velocity.normalized() if velocity != Vector2.ZERO else Vector2.RIGHT
    var side := dir.orthogonal()
    if _trail.size() > 1 and element != Element.Kind.OIL:
        for i in range(_trail.size() - 1):
            var f := 1.0 - float(i) / float(_trail.size())
            draw_line(to_local(_trail[i]), to_local(_trail[i + 1]), Color(color, 0.45 * f), maxf(1.0, radius * 1.3 * f))
    match element:
        Element.Kind.WET:
            draw_circle(-dir * radius * 0.7, radius * 0.6, color)
            draw_circle(Vector2.ZERO, radius, color)
            draw_circle(dir * radius * 0.25 - side * radius * 0.25, radius * 0.4, Color(1, 1, 1, 0.9))
        Element.Kind.SHOCK:
            var pts := PackedVector2Array()
            for i in 6:
                var along := -radius * 3.0 + float(i) * radius * 1.2
                var jag := randf_range(radius * 0.5, radius * 1.2) * (1.0 if i % 2 == 0 else -1.0)
                pts.append(dir * along + side * jag)
            draw_polyline(pts, Color(color, 0.8), 3.0)
            draw_polyline(pts, Color(1, 1, 0.9, 0.9), 1.2)
            draw_circle(Vector2.ZERO, radius * 0.9, Color(1.0, 1.0, 0.85))
        Element.Kind.FIRE:
            var f := radius * randf_range(0.8, 1.25)
            draw_circle(-dir * f * 0.5, f * 0.8, Color(color, 0.6))
            draw_circle(Vector2.ZERO, f, Color(color, 0.9))
            draw_circle(dir * f * 0.2, f * 0.5, Color(1.0, 0.95, 0.6))
        Element.Kind.ICE:
            var shard := PackedVector2Array([dir * radius * 2.2, side * radius * 0.8, -dir * radius * 1.4, -side * radius * 0.8])
            draw_colored_polygon(shard, color)
            draw_polyline(PackedVector2Array([shard[0], shard[1], shard[2], shard[3], shard[0]]), Color(1, 1, 1, 0.9), 1.0)
        Element.Kind.OIL:
            draw_circle(Vector2.ZERO, radius, Color(0.18, 0.13, 0.11))
            draw_circle(Vector2(-radius * 0.3, -radius * 0.3), radius * 0.35, Color(0.55, 0.45, 0.4, 0.7))
        _:
            draw_circle(Vector2.ZERO, radius, color)
    if element != Element.Kind.OIL:
        var glow: Texture2D = Art.PARTICLES["light"]
        var gs := radius * 6.0
        draw_texture_rect(glow, Rect2(Vector2(-gs, -gs) / 2.0, Vector2(gs, gs)), false, Color(color, 0.35))


func _on_body_entered(body: Node) -> void:
    if body is Obstacle:
        body.apply_element(element, potency)
        if shooter != null:
            shooter.on_projectile_hit(manual)
        queue_free()
        return
    if not body is Enemy or _hit.has(body):
        return
    var enemy := body as Enemy
    _hit[enemy] = true
    var raw := damage
    if enemy.immune_to == element:
        raw = 0.0
    if shooter != null and raw > 0.0:
        if enemy.has_state(Element.Kind.WET):
            raw *= 1.0 + shooter.stat("vs_wet")
        if enemy.burn_time > 0.0:
            raw *= 1.0 + shooter.stat("vs_burning")
        if enemy.frozen_time > 0.0:
            raw *= 1.0 + shooter.stat("vs_frozen")
        if enemy.has_state(Element.Kind.SHOCK):
            raw *= 1.0 + shooter.stat("vs_shocked")
        if enemy.has_state(Element.Kind.OIL):
            raw *= 1.0 + shooter.stat("vs_oiled")
    enemy.take_damage(raw, color, true, shooter)
    if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
        enemy.apply_element(element, potency, shooter)
    if extra_element != Element.Kind.NONE and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
        enemy.apply_element(extra_element, potency * 0.8, shooter)
    if shooter != null:
        shooter.on_projectile_hit(manual)
        Items.fire(shooter, "hit", { "target": enemy, "pos": global_position, "element": element })
    if pierce > 0:
        pierce -= 1
    else:
        queue_free()
