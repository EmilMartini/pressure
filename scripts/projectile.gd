class_name Projectile
extends Node2D
## A bullet. Deals raw damage, then applies its element (which may react). Passing
## through a cloud of another element reacts with the whole cloud. Bounces redirect it
## to the next enemy. Drawn per element: droplets, bolts, embers, shards, tar...
## `behaviour` (from GunData) changes the flight: "straight", "lob" (arcs over everything
## and splashes on landing), "homing" (steers to its own target), "boomerang" (returns to
## the shooter and can hit the same enemies again on the way back), "flak" (bursts into
## shards when it comes near an enemy, or at range), "orb" (slow, never stops on a body,
## pulses damage around it), "pool" (lobbed, leaves a Pool where it lands), "fork" (splits
## into fork_count bolts on the first hit), "ricochet" (caroms off walls; enemy rebounds
## are `bounces`) and "helix" (weaves around its line, a pair of them crossing).
## Hits go through Strike.deal, the hit path every gun mechanic shares.
## Not a physics body: each tick it asks EnemyGrid which enemy bodies its circle touches and
## takes a hit from each one it newly touches (the Area2D body_entered rule), and tests
## obstacles, walls and clouds directly.

## A body (enemy or obstacle) this shot just touched; the hit itself is _on_body_entered.
signal body_entered(body: Node)

static var _add_material: CanvasItemMaterial

var velocity := Vector2.ZERO
## The Void Herald's gravity wells: [{ "pos", "r", "warn", "t" }] while he lives (Enemy).
static var wells: Array = []
static var well_owner: Node = null
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
var knockback := 0.0        # shove per enemy hit, px/s along the flight
var aura_radius := 0.0      # orb: pulse radius; pool: pool radius
var linger := 0.0           # pool: seconds the pool lasts
var fork_count := 0         # fork: bolts on the first hit
var ricochet_walls := false # ricochet: walls reflect while bounces last
var helix_sign := 0.0       # helix: which side of the line it weaves to first
var home_target: Node2D = null   # homing: the enemy this seeker was sent after

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
var _inside: Dictionary = {}   # enemies the circle touched at the last check
var _pulse := 0.0              # orb: seconds to the next pulse
var _base := Vector2.ZERO      # helix: the point on the line it weaves around
var _age := 0.0
static var live := 0   # shots in the tree (the bot's --perf probe prints it)


func _ready() -> void:
    modulate.a = Settings.own_fx()   # "Your effects" (friend or foe, see Hostile)
    live += 1
    add_to_group(&"player_shots")   # the living world reads them (plants part, rivers ripple)
    body_entered.connect(_on_body_entered)
    z_index = 5
    _life0 = maxf(0.01, lifetime)
    _pierce0 = pierce
    _base = global_position
    if home_target != null:
        _home_target = home_target
    if behaviour == "lob" or behaviour == "pool":
        # In the air: no contact with anything until it lands (see _physics_process).
        z_index = 6
    if element != Element.Kind.OIL:
        if _add_material == null:
            _add_material = CanvasItemMaterial.new()
            _add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        material = _add_material


## A gravity well bends the shot towards its centre; a holy shot collapses it.
func _bend(delta: float) -> void:
    if not is_instance_valid(well_owner) or well_owner.hp <= 0.0:
        wells = []
        return
    var here := global_position
    for w in wells:
        var to: Vector2 = w["pos"] - here
        var r: float = w["r"]
        var d2 := to.length_squared()
        if d2 > r * r or d2 < 1.0 or float(w["warn"]) > 0.0 or float(w["t"]) <= 0.0:
            continue
        var d := sqrt(d2)
        if element == Element.Kind.HOLY or extra_elements.has(Element.Kind.HOLY):
            w["t"] = 0.0
            Elements.reaction_fired.emit("Well collapsed", w["pos"], Color(1.0, 0.95, 0.7))
            Elements.nova.emit(w["pos"], float(w["r"]), Color(1.0, 0.95, 0.7, 0.6))
            continue
        var turn := clampf(velocity.angle_to(to), -1.0, 1.0) * 5.0 * delta * (1.0 - d / float(w["r"]))
        velocity = velocity.rotated(turn)


func _physics_process(delta: float) -> void:
    if _landed:
        return
    _age += delta
    var lobbed := behaviour == "lob" or behaviour == "pool"
    if behaviour == "orb":
        _tick_orb(delta)
    elif not lobbed:
        _touch_enemies()
        if is_queued_for_deletion():
            return
        if behaviour == "flak" and _age > 0.05:
            # Proximity fuse: bursts beside the first enemy it comes near.
            for e in EnemyGrid.overlapping(get_tree(), global_position, radius + 26.0):
                if not _hit.has(e) and e.emerge <= 0.0:
                    body_entered.emit(e)
                    return
    _trail.push_front(global_position)
    if _trail.size() > 6:
        _trail.pop_back()
    _ob_grace = maxf(0.0, _ob_grace - delta)
    if not wells.is_empty() and not lobbed:
        _bend(delta)
    if homing_turn > 0.0 and not _returning:
        _steer(delta)   # homing stacks with flak, boomerang (on the way out) and straight shots
    match behaviour:
        "boomerang":
            if not _returning and lifetime <= _life0 * 0.5:
                _turn_back()
            if _returning:
                # Back along the throw line to where it left the hand (so it crosses what it
                # cut on the way out), caught early if the shooter is in its path.
                var to_home := _base - global_position
                if to_home.length() < 18.0 or (shooter != null and is_instance_valid(shooter) and shooter.global_position.distance_to(global_position) < 18.0):
                    queue_free()
                    return
                velocity = to_home.normalized() * velocity.length()
    if behaviour == "helix":
        _base += velocity * delta
        var side := velocity.normalized().orthogonal()
        global_position = _base + side * sin(_age * 16.0) * 9.0 * helix_sign
    else:
        position += velocity * delta
    lifetime -= delta
    if lobbed:
        if lifetime <= 0.0:
            _land()
            return
        queue_redraw()
        return
    if behaviour == "orb":
        # Orbs pass props and door blockers (their pulses reach them) and stop at walls.
        var rmo := Room.here
        if rmo != null and rmo.has_walls and rmo.blocks_shot(global_position + velocity.normalized() * radius):
            velocity = Vector2.ZERO
        if lifetime <= 0.0:
            _orb_pulse()
            queue_free()
        queue_redraw()
        return
    if ricochet_walls and bounces > 0 and _ricochet():
        queue_redraw()
        return
    if _ob_grace <= 0.0 and not spectral:
        for ob in EnemyGrid.nodes(get_tree(), &"obstacles"):
            if is_instance_valid(ob) and not ob.is_queued_for_deletion() and not _hit.has(ob) and ob.overlaps(global_position, radius):
                body_entered.emit(ob)
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
        for c in EnemyGrid.nodes(get_tree(), &"clouds"):
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


func _exit_tree() -> void:
    live -= 1


## Enemy bodies the shot's circle touches now; each one it did not touch at the last check
## is entered (one body_entered each, like an Area2D monitoring the enemy layer).
func _touch_enemies() -> void:
    var touching := EnemyGrid.overlapping(get_tree(), global_position, radius)
    if touching.is_empty() and _inside.is_empty():
        return
    var now: Dictionary = {}
    for e in touching:
        now[e] = true
        if not _inside.has(e):
            body_entered.emit(e)
    _inside = now


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
    if behaviour == "pool":
        var pool := Pool.new(_strike(), aura_radius, linger)
        pool.position = global_position
        Strike.world_parent(self).add_child(pool)
        queue_free()
        return
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
    var lobbed := behaviour == "lob" or behaviour == "pool"
    if behaviour == "orb":
        # The aura it pulses through, breathing with the pulse.
        var k := clampf(_pulse / GunData.PULSE, 0.0, 1.0)
        draw_circle(Vector2.ZERO, aura_radius, Color(color, 0.07 + 0.06 * k))
        draw_arc(Vector2.ZERO, aura_radius * (1.0 - 0.15 * k), 0.0, TAU, 32, Color(color, 0.35), 1.5)
    if lobbed:
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
            draw_circle(Vector2.ZERO, radius, Color(color.darkened(0.55), 1.0))   # deep, never black (Hostile)
            draw_arc(Vector2.ZERO, radius * 1.1, 0.0, TAU, 20, color.lightened(0.2), 2.0)
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
    if lobbed:
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _on_body_entered(body: Node) -> void:
    if _landed or behaviour == "lob" or behaviour == "pool" or behaviour == "orb":
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
            Sfx.play_at("hit_wall", global_position)
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
    if knockback > 0.0 and is_instance_valid(enemy) and velocity != Vector2.ZERO:
        enemy.shove(velocity.normalized() * knockback)
    if behaviour == "fork" and fork_count > 0:
        _fork(enemy)
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
    Sfx.hit_prop(prop.kind, global_position)
    var dir := velocity.normalized()
    var used := prop.apply_element(element, potency, dir)
    for extra in extra_elements:
        if is_instance_valid(prop) and not prop.is_queued_for_deletion():
            used = prop.apply_element(int(extra), potency * 0.8, dir) or used
    if not used and is_instance_valid(prop) and not prop.is_queued_for_deletion():
        prop.take_damage(damage)


## The shared hit path (Strike.deal): raw damage with the element-vs-state multipliers,
## then the element and coatings, attributed to the gun.
func _deal_hit(enemy: Enemy, dmg: float, pot: float) -> void:
    Strike.deal(enemy, dmg, pot, element, extra_elements, color, crit, shooter, gun_id, global_position)


## This shot's numbers as a Strike (for the pools, pulses and splits it makes).
func _strike() -> Strike:
    var st := Strike.new()
    st.damage = damage
    st.potency = potency
    st.element = element
    st.extras = extra_elements
    st.color = color
    st.crit = crit
    st.shooter = shooter
    st.gun_id = gun_id
    return st


## Orb: every GunData.PULSE seconds, everything within aura_radius takes a hit; a negative
## knockback pulls them toward the orb.
func _tick_orb(delta: float) -> void:
    _pulse -= delta
    if _pulse <= 0.0:
        _pulse = GunData.PULSE
        _orb_pulse()


func _orb_pulse() -> void:
    var st := _strike()
    for e in Strike.enemies_in(get_tree(), global_position, aura_radius):
        var to: Vector2 = e.global_position - global_position
        var kn := to.normalized() * knockback if to.length() > 8.0 else Vector2.ZERO
        st.hit(e, 1.0, e.global_position, kn)
    st.touch_world(get_tree(), global_position, aura_radius * 0.6, velocity.normalized())
    st.touch_clouds(get_tree(), global_position, aura_radius, _clouds_hit)
    var fx := _fx()
    if fx != null:
        fx.ring(global_position, aura_radius, color, 0.22)


## Fork: fork_count bolts at 60% leave the hit enemy toward the next nearest ones (or
## fanned out ahead when there are none). They do not fork again.
func _fork(from_enemy: Node) -> void:
    var parent := get_parent()
    if parent == null:
        return
    var n := fork_count
    fork_count = 0
    var skip: Dictionary = _hit.duplicate()
    var dir0 := velocity.normalized() if velocity != Vector2.ZERO else Vector2.RIGHT
    for i in n:
        var nxt := Strike.nearest(get_tree(), global_position, 260.0, skip)
        var d := dir0.rotated(lerpf(-0.6, 0.6, float(i) / float(maxi(1, n - 1))))
        if nxt != null:
            skip[nxt] = true
            d = (nxt.global_position - global_position).normalized()
        var b := Projectile.new()
        b.velocity = d * velocity.length() * 0.9
        b.damage = damage * 0.6
        b.potency = potency * 0.6
        b.element = element
        b.extra_elements = extra_elements
        b.lifetime = 0.45
        b.radius = maxf(2.0, radius * 0.7)
        b.color = color
        b.crit = crit
        b.shooter = shooter
        b.gun_id = gun_id
        b.position = position
        b._hit[from_enemy] = true
        if nxt != null:
            b.home_target = nxt
            b.homing_turn = 6.0
        parent.add_child.call_deferred(b)
    var fx := _fx()
    if fx != null:
        fx.pixels(element, global_position, 5, 90.0, 3.0)


## Ricochet: off the room's edge or an interior wall, reflecting the blocked axis.
## Returns true when it bounced this tick.
func _ricochet() -> bool:
    var rm := Room.here
    if rm == null or not is_instance_valid(rm):
        return false
    var r := Rect2(rm.global_position + rm.rect.position, rm.rect.size).grow(-radius)
    var p := global_position
    var flipped := false
    if p.x < r.position.x or p.x > r.end.x:
        velocity.x = -velocity.x
        flipped = true
    if p.y < r.position.y or p.y > r.end.y:
        velocity.y = -velocity.y
        flipped = true
    if not flipped and rm.has_walls and rm.blocks_shot(p):
        var back := p - velocity * get_physics_process_delta_time()
        if rm.blocks_shot(Vector2(p.x, back.y)):
            velocity.x = -velocity.x
        else:
            velocity.y = -velocity.y
        flipped = true
    if not flipped:
        return false
    bounces -= 1
    global_position = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
    global_position += velocity * get_physics_process_delta_time()
    _hit.clear()
    _inside.clear()
    lifetime = maxf(lifetime, 0.35)
    Sfx.play_at("hit_wall", global_position, -8.0)
    return true


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
