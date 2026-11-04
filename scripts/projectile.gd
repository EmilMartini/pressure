class_name Projectile
extends Area2D
## A bullet. Deals raw damage, then applies its element (which may react). Passing
## through a cloud of another element reacts with the whole cloud. Bounces redirect it
## to the next enemy. Drawn per element: droplets, bolts, embers, shards, tar...

const LAYER_ENEMIES := 2

static var _add_material: CanvasItemMaterial

var velocity := Vector2.ZERO
var damage := 1.0
var element: int = Element.Kind.NONE
var potency := 1.0
var lifetime := 1.0
var pierce := 0
var bounces := 0
var radius := 4.0
var color := Color.WHITE
var crit := false
var extra_elements: Array = []   # from Coating gun mods, one element each
var shooter: Player = null

var _hit: Dictionary = {}
var _clouds_hit: Dictionary = {}
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
    for c in get_tree().get_nodes_in_group("clouds"):
        if not is_instance_valid(c) or _clouds_hit.has(c) or c.element == element:
            continue
        if c.global_position.distance_to(global_position) <= c.radius:
            _clouds_hit[c] = true
            Elements.react_cloud(c, element, potency, shooter)
    if element == Element.Kind.FIRE:
        _smoke_cd -= delta
        if _smoke_cd <= 0.0:
            _smoke_cd = 0.07
            var fx := _fx()
            if fx != null:
                fx.puff(Art.PARTICLES["smoke"], global_position, Color(0.25, 0.22, 0.2, 0.45), radius * 4.0, 0.35, false, Vector2(0, -20), 0.5)
    if lifetime <= 0.0:
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
            Art.draw_frame(self, "thunder", 1.0 - fmod(lifetime * 4.0, 1.0), Vector2.ZERO, radius * 6.0, Color(1.0, 1.0, 0.9), dir.angle())
        Element.Kind.FIRE:
            Art.draw_frame(self, "fireball", 1.0 - fmod(lifetime * 3.0, 1.0), Vector2.ZERO, radius * 7.0, Color(1.0, 0.9, 0.7), dir.angle())
        Element.Kind.ICE:
            Art.draw_frame(self, "icespear", 1.0 - fmod(lifetime * 2.0, 1.0), Vector2.ZERO, radius * 7.0, Color(0.9, 1.0, 1.0), dir.angle())
        Element.Kind.OIL:
            draw_circle(Vector2.ZERO, radius, Color(0.18, 0.13, 0.11))
            draw_circle(Vector2(-radius * 0.3, -radius * 0.3), radius * 0.35, Color(0.55, 0.45, 0.4, 0.7))
        Element.Kind.POISON:
            draw_circle(Vector2.ZERO, radius, color)
            for i in 3:
                var a := float(i) * 2.1 + lifetime * 9.0
                draw_circle(Vector2.RIGHT.rotated(a) * radius * 0.9, radius * 0.3, Color(0.8, 1.0, 0.6, 0.9))
        Element.Kind.ACID:
            draw_circle(-dir * radius * 0.5, radius * 0.7, color)
            draw_circle(Vector2.ZERO, radius, color)
            draw_circle(dir * radius * 0.4, radius * 0.35, Color(1, 1, 0.8))
        Element.Kind.BLOOD:
            draw_circle(-dir * radius * 1.2, radius * 0.5, Color(color, 0.7))
            draw_circle(-dir * radius * 0.6, radius * 0.75, color)
            draw_circle(Vector2.ZERO, radius, color)
        Element.Kind.VOID:
            draw_circle(Vector2.ZERO, radius * 1.3, Color(color, 0.35))
            draw_circle(Vector2.ZERO, radius, Color(0.05, 0.02, 0.1))
            draw_arc(Vector2.ZERO, radius * 1.1, 0.0, TAU, 20, color, 2.0)
        Element.Kind.HOLY:
            draw_line(-dir * radius * 1.6, dir * radius * 1.6, Color(1, 1, 1), 2.0)
            draw_line(-side * radius * 1.2, side * radius * 1.2, Color(1, 1, 1), 2.0)
            draw_circle(Vector2.ZERO, radius * 0.7, color)
        Element.Kind.GALE:
            for i in 3:
                var off := -dir * radius * float(i) * 1.1
                draw_arc(off, radius * (0.6 + 0.3 * float(i)), -1.2, 1.2, 10, Color(color, 0.9 - 0.25 * float(i)), 1.5)
        Element.Kind.STONE:
            var hex := PackedVector2Array()
            for i in 6:
                hex.append(Vector2.RIGHT.rotated(float(i) * TAU / 6.0 + lifetime * 6.0) * radius)
            draw_colored_polygon(hex, color)
            draw_polyline(hex, Color(0.3, 0.27, 0.22), 1.5)
        _:
            draw_circle(Vector2.ZERO, radius, color)
    if element != Element.Kind.OIL:
        var glow: Texture2D = Art.PARTICLES["light"]
        var gs := radius * 6.0
        draw_texture_rect(glow, Rect2(Vector2(-gs, -gs) / 2.0, Vector2(gs, gs)), false, Color(color, 0.35))


func _on_body_entered(body: Node) -> void:
    if body is Obstacle:
        body.apply_element(element, potency)
        queue_free()
        return
    if not body is Enemy or _hit.has(body):
        return
    var enemy := body as Enemy
    _hit[enemy] = true
    var raw := damage
    if enemy.immune_to == element:
        raw = 0.0
    # How the element meets what the target already carries, before any gear bonuses:
    # water conducts, damp things burn badly, oil feeds fire, frozen things shatter.
    if raw > 0.0:
        if element == Element.Kind.SHOCK and enemy.has_state(Element.Kind.WET):
            raw *= 1.5
        if element == Element.Kind.FIRE and enemy.has_state(Element.Kind.WET):
            raw *= 0.5
        if element == Element.Kind.FIRE and enemy.has_state(Element.Kind.OIL):
            raw *= 1.25
        if element == Element.Kind.STONE and enemy.frozen_time > 0.0:
            raw *= 1.5
        if element == Element.Kind.HOLY and (enemy.poison_time > 0.0 or enemy.has_state(Element.Kind.VOID)):
            raw *= 1.25
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
    enemy.take_damage(raw, color, true, shooter, crit)
    if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
        enemy.apply_element(element, potency, shooter)
    for extra in extra_elements:
        if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
            enemy.apply_element(extra, potency * 0.8, shooter)
    if shooter != null:
        Items.fire(shooter, "hit", { "target": enemy, "pos": global_position, "element": element })
    if bounces > 0:
        var next := _next_target()
        if next != null:
            bounces -= 1
            velocity = (next.global_position - global_position).normalized() * velocity.length()
            lifetime = maxf(lifetime, 0.6)
            return
    if pierce > 0:
        pierce -= 1
    else:
        queue_free()


func _next_target() -> Node2D:
    var best: Node2D = null
    var best_d := 320.0 * 320.0
    for e in get_tree().get_nodes_in_group("enemies"):
        if _hit.has(e) or not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        var d: float = e.global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = e
    return best
