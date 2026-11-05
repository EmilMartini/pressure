class_name Projectile
extends Area2D
## A bullet. Deals raw damage, then applies its element (which may react). Passing
## through a cloud of another element reacts with the whole cloud. Bounces redirect it
## to the next enemy. Drawn per element: droplets, bolts, embers, shards, tar...
## `behaviour` (from GunData) changes the flight: "straight", "lob" (arcs over everything
## and splashes on landing), "homing", "boomerang" (returns to the shooter and can hit the
## same enemies again on the way back) and "flak" (bursts into shards on hit or at range).

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
var gun_id := ""   # the GunData id that fired it, for telemetry ("" for item and prop shots)
var behaviour := "straight"
var splash_radius := 0.0
var shard_count := 0
var homing_turn := 0.0

var _hit: Dictionary = {}
var _clouds_hit: Dictionary = {}
var _trail: Array = []
var _smoke_cd := 0.0
var _life0 := 1.0
var _pierce0 := 0
var _returning := false
var _ob_grace := 0.0
var spectral := false   # passes through obstacles (Wisp Lantern and friends)
var _home_target: Node2D = null
var _landed := false


func _ready() -> void:
    collision_layer = 0
    collision_mask = LAYER_ENEMIES | Obstacle.LAYER_OBSTACLES
    set_deferred("monitorable", false)   # may be spawned from inside a collision callback
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    add_child(shape)
    body_entered.connect(_on_body_entered)
    z_index = 5
    _life0 = maxf(0.01, lifetime)
    _pierce0 = pierce
    if behaviour == "lob":
        # In the air: no contact with anything until it lands.
        set_deferred("monitoring", false)
        z_index = 6
    if element != Element.Kind.OIL:
        if _add_material == null:
            _add_material = CanvasItemMaterial.new()
            _add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        material = _add_material


func _physics_process(delta: float) -> void:
    if _landed:
        return
    _trail.push_front(global_position)
    if _trail.size() > 6:
        _trail.pop_back()
    _ob_grace = maxf(0.0, _ob_grace - delta)
    if homing_turn > 0.0 and not _returning:
        _steer(delta)   # homing stacks with flak, boomerang (on the way out) and straight shots
    match behaviour:
        "boomerang":
            if not _returning and lifetime <= _life0 * 0.5:
                _turn_back()
            if _returning and shooter != null and is_instance_valid(shooter):
                var to_home := shooter.global_position - global_position
                if to_home.length() < 18.0:
                    queue_free()
                    return
                velocity = to_home.normalized() * velocity.length()
    position += velocity * delta
    lifetime -= delta
    if behaviour == "lob":
        if lifetime <= 0.0:
            _land()
            return
        queue_redraw()
        return
    if _ob_grace <= 0.0 and not spectral:
        for ob in get_tree().get_nodes_in_group("obstacles"):
            if is_instance_valid(ob) and not ob.is_queued_for_deletion() and not _hit.has(ob) and ob.overlaps(global_position, radius):
                _on_body_entered(ob)
                if is_queued_for_deletion():
                    return
                break   # a prop let the shot through (pierce): fly on
    # Interior walls of a room layout stop shots (chasms they fly over).
    var rm := Room.here
    if not spectral and rm != null and rm.has_walls and rm.blocks_shot(global_position):
        if behaviour == "boomerang" and not _returning:
            _turn_back()
        else:
            if shard_count > 0:
                _burst_shards(null)
            _splash(null)
            queue_free()
            return
    if element != Element.Kind.NONE:
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
        if shard_count > 0:
            _burst_shards(null)
        queue_free()
    queue_redraw()


## Homing: turn toward the nearest enemy not yet hit, at most homing_turn rad/s.
func _steer(delta: float) -> void:
    if _home_target == null or not is_instance_valid(_home_target) or _home_target.is_queued_for_deletion() or _hit.has(_home_target):
        _home_target = _next_target()
    if _home_target == null or velocity == Vector2.ZERO:
        return
    var want := (_home_target.global_position - global_position).angle()
    var diff := wrapf(want - velocity.angle(), -PI, PI)
    velocity = velocity.rotated(clampf(diff, -homing_turn * delta, homing_turn * delta))


## Boomerang: head back to the shooter, free to hit everything again.
func _turn_back() -> void:
    _returning = true
    _hit.clear()
    pierce = _pierce0
    _ob_grace = 0.2
    velocity = -velocity
    lifetime = maxf(lifetime, _life0 * 0.5 + 0.8)


## Lob: the shell comes down and splashes everything within splash_radius at full damage.
func _land() -> void:
    _landed = true
    var r := maxf(splash_radius, radius * 2.0)
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or not e is Enemy:
            continue
        var en := e as Enemy
        if en.global_position.distance_to(global_position) <= r + en.radius:
            _hit[en] = true
            _deal_hit(en, damage, potency)
    for ob in get_tree().get_nodes_in_group("obstacles"):
        if is_instance_valid(ob) and not ob.is_queued_for_deletion() and ob.overlaps(global_position, r * 0.5):
            if ob is Prop:
                _hit_prop(ob as Prop)
            else:
                ob.apply_element(element, potency)
    if element != Element.Kind.NONE:
        for c in get_tree().get_nodes_in_group("clouds"):
            if is_instance_valid(c) and c.element != element and c.global_position.distance_to(global_position) <= c.radius + r * 0.5:
                Elements.react_cloud(c, element, potency, shooter)
    Elements.nova.emit(global_position, r, Color(color, 0.55))
    _leave_material(r * 0.6, true)
    var fx := _fx()
    if fx != null:
        fx.puff(Art.PARTICLES["smoke"], global_position, Color(color, 0.6), r * 1.2, 0.3, false)
    if shard_count > 0:
        _burst_shards(null)
    queue_free()


## Splash from a shot that ended on a hit: half damage to everyone else nearby.
func _splash(center_hit: Node) -> void:
    _leave_material(maxf(splash_radius * 0.5, radius * 2.0), splash_radius > 0.0)
    if splash_radius <= 0.0:
        return
    for e in get_tree().get_nodes_in_group("enemies"):
        if e == center_hit or not is_instance_valid(e) or e.is_queued_for_deletion() or not e is Enemy:
            continue
        var en := e as Enemy
        if en.global_position.distance_to(global_position) <= splash_radius + en.radius:
            _deal_hit(en, damage * 0.5, potency * 0.5)
    Elements.nova.emit(global_position, splash_radius, Color(color, 0.45))


## Flak: shard_count small straight shards of the same element at 50% damage.
func _burst_shards(exclude: Node) -> void:
    var parent := get_parent()
    if parent == null:
        return
    var n := shard_count
    shard_count = 0
    var base_angle := randf() * TAU
    for i in n:
        var s := Projectile.new()
        var a := base_angle + TAU * float(i) / float(n) + randf_range(-0.15, 0.15)
        s.velocity = Vector2.RIGHT.rotated(a) * 520.0
        s.damage = damage * 0.5
        s.element = element
        s.extra_elements = extra_elements
        s.potency = potency * 0.5
        s.lifetime = 0.22
        s.radius = maxf(2.0, radius * 0.45)
        s.color = color
        s.crit = crit
        s.shooter = shooter
        s.gun_id = gun_id
        s.position = position
        if exclude != null:
            s._hit[exclude] = true
        parent.add_child.call_deferred(s)


## Where the shot ends, its element lands on the floor (see Materials): one stamp per shot.
## `big` (lobs and splash shots) lays more and lets Fire burn a small patch of bare floor.
func _leave_material(r: float, big: bool) -> void:
    if element == Element.Kind.NONE:
        return
    var mats := Materials.find(self)
    if mats == null:
        return
    var amount := clampi(int(40.0 + potency * 6.0), 40, 200)
    if big:
        amount = mini(255, amount + 40)
    mats.stamp(element, global_position, r, amount, big)


func _fx() -> Fx:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        return scene.fx
    return null


func _draw() -> void:
    var dir := velocity.normalized() if velocity != Vector2.ZERO else Vector2.RIGHT
    var side := dir.orthogonal()
    if behaviour == "lob":
        # Shadow on the ground, the shell drawn up in the air along a sine arc.
        var t := clampf(1.0 - lifetime / _life0, 0.0, 1.0)
        var arc := clampf(_life0 * velocity.length() * 0.35, 30.0, 140.0)
        var h := sin(PI * t) * arc
        draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
        draw_circle(Vector2.ZERO, radius * (1.2 - 0.4 * sin(PI * t)), Color(0, 0, 0, 0.45))
        draw_set_transform(Vector2(0, -h), 0.0, Vector2.ONE)
    elif _trail.size() > 1 and element != Element.Kind.OIL:
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
            # A white pixel head leading the bolt.
            var head := pts[pts.size() - 1]
            draw_rect(Rect2(floorf(head.x - 1.5), floorf(head.y - 1.5), 3.0, 3.0), Color(1, 1, 1, 0.95))
            draw_rect(Rect2(floorf(head.x - 3.0), floorf(head.y - 3.0), 6.0, 6.0), Color(1.0, 0.95, 0.4, 0.35))
        Element.Kind.FIRE:
            # A pixel comet: hot core, orange shell, a flickering tail of shrinking squares.
            for k in 4:
                var back := -dir * radius * (0.9 + 0.8 * float(k)) + side * randf_range(-1.0, 1.0)
                var ts := floorf(maxf(1.0, radius * 0.8 - float(k) * 1.2) + 0.5)
                var tc := Color(1.0, 0.45, 0.15, 0.6 - 0.1 * float(k)) if randi() % 2 == 0 else Color(0.75, 0.15, 0.08, 0.5 - 0.1 * float(k))
                draw_rect(Rect2(floorf(back.x - ts * 0.5), floorf(back.y - ts * 0.5), ts, ts), tc)
            var fs := floorf(radius * 1.2 + 0.5)
            draw_rect(Rect2(-floorf(fs * 0.5), -floorf(fs * 0.5), fs, fs), Color(1.0, 0.5, 0.15, 0.6))
            draw_rect(Rect2(-1.5, -1.5, 3.0, 3.0), Color(1.0, 0.92, 0.45))
        Element.Kind.ICE:
            # A shard: pale squares along the flight line around a 2 px white core.
            for k in 5:
                var along2 := (float(k) - 2.0) * radius * 0.55
                var ss := 3.0 if k in [1, 2, 3] else 2.0
                var q := dir * along2
                draw_rect(Rect2(floorf(q.x - ss * 0.5), floorf(q.y - ss * 0.5), ss, ss), Color(0.7, 0.95, 1.0, 0.6 if k > 0 else 0.4))
            var tip := dir * radius * 1.6
            draw_rect(Rect2(floorf(tip.x - 1.0), floorf(tip.y - 1.0), 2.0, 2.0), Color(0.85, 0.97, 1.0, 0.7))
            draw_rect(Rect2(-1.0, -1.0, 2.0, 2.0), Color(1, 1, 1))
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
    if behaviour == "boomerang":
        draw_arc(Vector2.ZERO, radius * 1.5, lifetime * 14.0, lifetime * 14.0 + PI, 10, Color(color, 0.8), 2.0)
    if behaviour == "lob":
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _on_body_entered(body: Node) -> void:
    if _landed or behaviour == "lob":
        return
    if body is Obstacle or (body.is_in_group("obstacles") and body.has_method("apply_element")):
        if _ob_grace > 0.0 or spectral or _hit.has(body):
            return
        if body is Prop:
            var prop := body as Prop
            _hit[prop] = true
            _hit_prop(prop)
            # Props (not pillars) let piercing shots through, one pierce each.
            if not prop.blocks_shots and pierce > 0:
                pierce -= 1
                return
        else:
            body.apply_element(element, potency)
        if behaviour == "boomerang" and not _returning:
            _turn_back()
            return
        if shard_count > 0:
            _burst_shards(null)
        _splash(null)
        queue_free()
        return
    if not body is Enemy or _hit.has(body) or (body as Enemy).emerge > 0.0:
        return
    var enemy := body as Enemy
    _hit[enemy] = true
    _deal_hit(enemy, damage, potency)
    if behaviour == "flak":
        _burst_shards(enemy)
        _splash(enemy)
        queue_free()
        return
    if bounces > 0:
        var next := _next_target()
        if next != null:
            bounces -= 1
            velocity = (next.global_position - global_position).normalized() * velocity.length()
            lifetime = maxf(lifetime, 0.6)
            return
    if pierce > 0:
        pierce -= 1
    elif behaviour == "boomerang" and not _returning:
        _turn_back()
    else:
        if shard_count > 0:
            _burst_shards(enemy)
        _splash(enemy)
        queue_free()


## A prop takes the element (and any coatings); when none of them did anything to it,
## the shot is a plain hit and chips it instead.
func _hit_prop(prop: Prop) -> void:
    var dir := velocity.normalized()
    var used := prop.apply_element(element, potency, dir)
    for extra in extra_elements:
        if is_instance_valid(prop) and not prop.is_queued_for_deletion():
            used = prop.apply_element(int(extra), potency * 0.8, dir) or used
    if not used and is_instance_valid(prop) and not prop.is_queued_for_deletion():
        prop.take_damage(damage)


## The shared hit path: raw damage (with element-vs-state multipliers), then the element.
func _deal_hit(enemy: Enemy, dmg: float, pot: float) -> void:
    var raw := dmg
    if enemy.immune_to == element and element != Element.Kind.NONE:
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
    Telemetry.begin_shot(gun_id, element)
    enemy.take_damage(raw, color, true, shooter, crit)
    if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
        enemy.apply_element(element, pot, shooter)
    for extra in extra_elements:
        if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
            enemy.apply_element(extra, pot * 0.8, shooter)
    Telemetry.end_shot()
    if shooter != null:
        Items.fire(shooter, "hit", { "target": enemy, "pos": global_position, "element": element })


func _next_target() -> Node2D:
    var best: Node2D = null
    var best_d := (450.0 * 450.0) if behaviour == "homing" else (320.0 * 320.0)
    for e in get_tree().get_nodes_in_group("enemies"):
        if _hit.has(e) or not is_instance_valid(e) or e.is_queued_for_deletion() or e.emerge > 0.0:
            continue
        var d: float = e.global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = e
    return best
