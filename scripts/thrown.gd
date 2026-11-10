class_name Thrown
extends RefCounted
## Thrown and lobbed weapons (Arsenal expansion 2.4), and the gun shots that stick, trap or
## reel (batch 2). Everything still flies as a pooled `Projectile`; its `behaviour` picks a
## path here instead of Projectile's own, and Projectile hands its tick, its touches and its
## look to these functions. No physics: stuck knives are inert, with one timer each.
##
## Styles (GunData.style / Projectile.behaviour):
##   knife    a straight fan; sticks in the floor or in a foe for STICK s, then flies back to
##            you, hitting along the way. At most KNIFE_CAP stuck per weapon (the oldest leaves)
##   disc     bounces from foe to foe (`bounces`), then returns
##   star     flies to its target and circles it twice at STAR_ORBIT px, then returns
##   grenade  rolls, bounces once off a wall or a foe, bursts when the fuse (`linger`) runs out
##   javelin  straight, slower, pierces; the last foe hit is pinned for PIN s
##   bola     wraps the first foe: it stops for BOLA s (elites and bosses BOLA_ELITE)
##   anchor   thrown out, then dragged back on a chain, pulling the foes it hits toward you
##   sticky   (gun) a dart that sticks, then bursts after STICKY_FUSE s
##   bubble   (gun) a slow bubble that traps small foes for BUBBLE_TRAP s
##   harpoon  (gun) a barbed shot that reels its foe toward you
##   converge (gun) pellets that curve inward to meet at one point, then fly on
## Lobs (`lob`, `pool`) keep Projectile's arc; their only floor mark is a small dark shadow
## under the shell, never a landing circle (a floor circle is how hostile lobbers warn you).
##
## Returns fly at RETURN_SPEED x the outward speed toward where the shooter is now, and
## vanish quietly on reaching them (an item can hook the "catch" event).
##
## Thrown stat map (2.2): fire rate is throws (plus `throw_rate`), +1 projectile is +1
## thrown, pierce is pierce, bounce is +1 jump for discs (a lap for stars) or +25% on the
## return hit for the rest, range is throw distance, shot speed is flight speed, size is
## object size, duration (`state_duration`) keeps knives stuck and pools down longer.

const HANDLES := {
    "knife": true, "disc": true, "star": true, "grenade": true, "javelin": true, "bola": true,
    "anchor": true, "sticky": true, "bubble": true, "harpoon": true, "converge": true,
}
## Styles that come back to you.
const RETURNERS := { "knife": true, "disc": true, "star": true, "anchor": true }

const FLY := 0
const STUCK := 1
const BACK := 2
const ORBIT := 3

const STICK := 1.5
const KNIFE_CAP := 12
const RETURN_SPEED := 1.2
const STAR_ORBIT := 40.0
const STAR_LAPS := 2
const STAR_SPIN := 2.2          # laps a second
const PIN := 1.0
const BOLA := 1.2
const BOLA_ELITE := 0.4
const BUBBLE_TRAP := 0.6
const STICKY_FUSE := 1.0
const STICKY_DART := 0.3        # the dart's own hit, before the burst
const GRENADE_ROLL := 2.4       # speed decay a second while rolling
const STORM_LINK := 180.0       # Storm Kunai: stuck knives this close arc to each other
const STUCK_TICK := 0.5

## "<shooter id>:<gun id>" -> the knives of that weapon now alive (any state).
static var _knives: Dictionary = {}


static func handles(b: String) -> bool:
    return HANDLES.has(b)


## Called once from Projectile._ready for a thrown behaviour.
static func setup(p: Projectile) -> void:
    p.t_speed0 = maxf(60.0, p.velocity.length())
    if p.behaviour == "knife":
        var key := _key(p)
        if not _knives.has(key):
            _knives[key] = []
        (_knives[key] as Array).append(p)
    if p.behaviour == "grenade":
        p.lifetime = maxf(0.2, p.linger * (1.0 - _stat(p, "fuse_cut")))


static func forget(p: Projectile) -> void:
    if p.behaviour == "knife":
        var arr: Array = _knives.get(_key(p), [])
        arr.erase(p)


static func _key(p: Projectile) -> String:
    var sid := p.shooter.get_instance_id() if p.shooter != null and is_instance_valid(p.shooter) else 0
    return "%d:%s" % [sid, p.gun_id]


static func _stat(p: Projectile, key: String) -> float:
    if p.shooter == null or not is_instance_valid(p.shooter):
        return 0.0
    return p.shooter.stat(key)


# --- The tick ------------------------------------------------------------------


static func tick(p: Projectile, delta: float) -> void:
    p._age += delta
    match p.t_state:
        STUCK:
            _tick_stuck(p, delta)
            return
        BACK:
            _tick_back(p, delta)
            return
        ORBIT:
            _tick_orbit(p, delta)
            return
    var b := p.behaviour
    match b:
        "star":
            if p.home_target != null and is_instance_valid(p.home_target) and not p.home_target.is_queued_for_deletion():
                var to := p.home_target.global_position - p.global_position
                p.velocity = p.velocity.rotated(clampf(p.velocity.angle_to(to), -9.0 * delta, 9.0 * delta))
                if to.length() <= STAR_ORBIT + 4.0:
                    _start_orbit(p, p.home_target)
                    return
        "grenade":
            p.velocity *= exp(-GRENADE_ROLL * delta)
            if p.element == Element.Kind.VOID and Engine.get_physics_frames() % 3 == 0:
                # Void Grenade: drags foes in over its fuse.
                for e in EnemyGrid.overlapping(p.get_tree(), p.global_position, 110.0):
                    if is_instance_valid(e) and e.boss_kind == "" and not e.is_queued_for_deletion():
                        var tv: Vector2 = p.global_position - e.global_position
                        e.global_position += tv.limit_length(minf(tv.length() * 0.4, 150.0 * delta * 3.0))
        "converge":
            if p.t_point != Vector2.INF:
                var tp := p.t_point - p.global_position
                if tp.length() < 10.0 or tp.dot(p.velocity) <= 0.0:
                    p.t_point = Vector2.INF   # met: fly on straight
                else:
                    p.velocity = p.velocity.rotated(clampf(p.velocity.angle_to(tp), -8.0 * delta, 8.0 * delta))
        "anchor":
            if p.lifetime <= p._life0 * 0.5:
                _start_back(p)
                return
    p.position += p.velocity * delta
    p.lifetime -= delta
    if b != "grenade":
        p._touch_enemies()
        if p.is_queued_for_deletion() or p.t_state != FLY:
            return
    else:
        _grenade_touch(p)
    if _hit_obstacle(p) or p.is_queued_for_deletion() or p.t_state != FLY:
        return
    var rm := Room.here
    if rm != null and is_instance_valid(rm) and _blocked(rm, p.global_position):
        _wall(p, rm)
        if p.is_queued_for_deletion() or p.t_state != FLY:
            return
    if p.lifetime <= 0.0:
        _end_flight(p)
        return
    _trail(p)


static func _trail(p: Projectile) -> void:
    p._trail.push_front(p.global_position)
    if p._trail.size() > 5:
        p._trail.pop_back()
    p.queue_redraw()


static func _blocked(rm: Room, pos: Vector2) -> bool:
    var r := Rect2(rm.global_position + rm.rect.position, rm.rect.size)
    if not r.has_point(pos):
        return true
    return rm.has_walls and rm.blocks_shot(pos)


## A wall or the room's edge in flight.
static func _wall(p: Projectile, rm: Room) -> void:
    match p.behaviour:
        "knife":
            p.global_position -= p.velocity.normalized() * 6.0
            _stick(p, null)
        "disc", "star", "anchor":
            _start_back(p)
        "grenade":
            if not p.t_bounced:
                p.t_bounced = true
                p.global_position -= p.velocity * p.get_physics_process_delta_time() * 2.0
                var back := p.global_position - p.velocity.normalized() * 8.0
                if _blocked(rm, Vector2(p.global_position.x + signf(p.velocity.x) * 8.0, back.y)):
                    p.velocity.x = -p.velocity.x
                else:
                    p.velocity.y = -p.velocity.y
                p.velocity *= 0.55
            else:
                p.velocity = Vector2.ZERO
        "javelin":
            _pin(p, p.t_last)
            p._leave_material(p.radius * 2.0, false)
            p.queue_free()
        _:
            p._splash(null)
            p.queue_free()


## Pillars, door blockers and props: a prop takes the element; a solid thing stops it like a wall.
static func _hit_obstacle(p: Projectile) -> bool:
    if p.spectral:
        return false
    for ob in EnemyGrid.nodes(p.get_tree(), &"obstacles"):
        if not is_instance_valid(ob) or ob.is_queued_for_deletion() or p._hit.has(ob) or not ob.overlaps(p.global_position, p.radius):
            continue
        p._hit[ob] = true
        if ob is Prop:
            p._hit_prop(ob as Prop)
            if not (ob as Prop).blocks_shots:
                return false
        elif ob.has_method("apply_element"):
            ob.apply_element(p.element, p.potency)
            Sfx.play_at("hit_wall", p.global_position, -6.0)
        var rm := Room.here
        if rm != null and is_instance_valid(rm):
            _wall(p, rm)
        else:
            p.queue_free()
        return true
    return false


## The flight ran out (its reach, or a grenade's fuse).
static func _end_flight(p: Projectile) -> void:
    match p.behaviour:
        "knife":
            _stick(p, null)
        "disc", "star", "anchor":
            _start_back(p)
        "grenade":
            _burst(p)
        "javelin":
            _pin(p, p.t_last)
            p.queue_free()
        _:
            p.queue_free()


# --- Touching foes -----------------------------------------------------------------


## Projectile._on_body_entered hands thrown behaviours here (enemies; obstacles are
## handled in the tick).
static func on_body(p: Projectile, body: Node) -> void:
    if not body is Enemy or p._hit.has(body) or (body as Enemy).emerge > 0.0:
        return
    var e := body as Enemy
    if p.t_state == BACK:
        p._hit[e] = true
        hit(p, e, _return_mult(p))
        if p.behaviour == "anchor" or _stat(p, "return_pull") > 0.0:
            _drag(p, e)
        return
    if p.t_state != FLY:
        return
    match p.behaviour:
        "grenade":
            return   # handled by _grenade_touch (no contact damage)
        "knife":
            p._hit[e] = true
            hit(p, e, 1.0)
            if p.pierce > 0:
                p.pierce -= 1
            else:
                _last_hit(p, e)
                _stick(p, e)
        "disc":
            p._hit[e] = true
            hit(p, e, 1.0)
            var left := p.bounces + int(_stat(p, "disc_bounce")) + int(_stat(p, "thrown_bounce")) - p.t_jumps
            var nxt: Node2D = p._next_target() if left > 0 else null
            if nxt != null:
                p.t_jumps += 1
                p.velocity = (nxt.global_position - p.global_position).normalized() * p.velocity.length()
                p.lifetime = maxf(p.lifetime, 0.6)
                var grow := _stat(p, "disc_grow") + (0.12 if p.gun_id == "halo_disc" else 0.0)
                if grow > 0.0:
                    p.radius *= 1.0 + grow
                    p.damage *= 1.0 + grow * 0.6
            else:
                _last_hit(p, e)
                _start_back(p)
        "star":
            p._hit[e] = true
            hit(p, e, 1.0)
            _start_orbit(p, e)
        "javelin":
            p._hit[e] = true
            hit(p, e, 1.0)
            p.t_last = e
            if p.gun_id == "etching_javelin":
                e.corrode(3.0)
            if p.pierce > 0:
                p.pierce -= 1
            else:
                _pin(p, e)
                _last_hit(p, e)
                p.queue_free()
        "bola":
            p._hit[e] = true
            hit(p, e, 1.0)
            if is_instance_valid(e) and not e.is_queued_for_deletion():
                _hold(p, e, BOLA_ELITE if (e.is_elite or e.boss_kind != "") else BOLA)
                if p.element == Element.Kind.SHOCK:
                    for o in Strike.enemies_in(p.get_tree(), e.global_position, 80.0):
                        if o != e:
                            o.apply_element(Element.Kind.SHOCK, p.potency * 0.5, p.shooter)
                    var fx := p._fx()
                    if fx != null:
                        fx.ring(e.global_position, 80.0, Color(p.color, 0.5), 0.2)
            _last_hit(p, e)
            p.queue_free()
        "anchor":
            p._hit[e] = true
            hit(p, e, 1.0)
        "sticky":
            p._hit[e] = true
            hit(p, e, STICKY_DART)
            _stick(p, e)
            p.t_timer = STICKY_FUSE
        "bubble":
            p._hit[e] = true
            hit(p, e, 1.0)
            if is_instance_valid(e) and not e.is_queued_for_deletion() and not e.is_elite and e.boss_kind == "":
                e.stun(BUBBLE_TRAP)
            p.queue_free()
        "harpoon":
            p._hit[e] = true
            hit(p, e, 1.0)
            if is_instance_valid(e) and not e.is_queued_for_deletion() and e.boss_kind == "" and p.shooter != null and is_instance_valid(p.shooter):
                var to: Vector2 = p.shooter.global_position - e.global_position
                e.shove(to.normalized() * minf(460.0, to.length() * 2.2))
            p.queue_free()
        "converge":
            p._hit[e] = true
            hit(p, e, 1.0)
            if p.pierce > 0:
                p.pierce -= 1
            else:
                p.queue_free()


## One hit by a thrown object (Strike.deal through Projectile), with the thrown item rules.
static func hit(p: Projectile, e: Enemy, mult: float) -> void:
    if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
        return
    if p.shooter != null and is_instance_valid(p.shooter):
        if e.frozen_time > 0.0:
            mult *= 1.0 + p.shooter.stat("thrown_vs_frozen")
        if e.stun_time > 0.0:
            mult *= 1.0 + p.shooter.stat("vs_stunned")
    p._deal_hit(e, p.damage * mult, p.potency * mult)


## Where a throw returns to: the hover spot of the weapon that threw it (A8), else the
## spot it left from.
static func home(p: Projectile) -> Vector2:
    for g in p.shooter.guns:
        if is_instance_valid(g) and g.data.id == p.gun_id:
            return g.global_position
    return p.shooter.global_position + p._hand


static func _return_mult(p: Projectile) -> float:
    var m := p.t_mult * (1.0 + _stat(p, "return_mult"))
    if p.behaviour != "disc" and p.behaviour != "star":
        m *= 1.0 + 0.25 * float(int(_stat(p, "bounce")) + int(_stat(p, "thrown_bounce")))
    return m


## The Thrown resonance at 5: a thrown object splits in two on its last hit.
static func _last_hit(p: Projectile, e: Enemy) -> void:
    if _stat(p, "thrown_split") > 0.0 and p.fork_count <= 0 and not p.t_split:
        p.t_split = true
        p.fork_count = 2
        p._fork(e)


static func _hold(p: Projectile, e: Enemy, secs: float) -> void:
    if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
        return
    e.stun(secs * (1.0 + _stat(p, "pin_time")))
    e.apply_slow(0.5, secs)


static func _pin(p: Projectile, e) -> void:
    # Untyped: the last foe hit may have died (a freed object) before the javelin ends.
    if e != null and is_instance_valid(e) and e is Enemy and not e.is_queued_for_deletion():
        _hold(p, e as Enemy, PIN if not ((e as Enemy).is_elite or (e as Enemy).boss_kind != "") else BOLA_ELITE)


## Dragged along by the chain (Drowned Anchor) or a magnet: toward the shooter.
static func _drag(p: Projectile, e: Enemy) -> void:
    if not is_instance_valid(e) or e.is_queued_for_deletion() or e.boss_kind != "" or p.shooter == null or not is_instance_valid(p.shooter):
        return
    var to: Vector2 = p.shooter.global_position - e.global_position
    var pull := 260.0 if p.behaviour == "anchor" else 140.0
    e.shove(to.normalized() * minf(pull, to.length() * 2.0))


# --- Sticking, recall and orbit -------------------------------------------------------


## Stuck in a foe (follows it) or in the floor (`on` null). Knives return after STICK s.
static func _stick(p: Projectile, on: Enemy) -> void:
    p.t_state = STUCK
    p.t_anchor = on
    p.t_offset = Vector2.ZERO
    if on != null and is_instance_valid(on):
        p.t_offset = (p.global_position - on.global_position).limit_length(on.radius * 0.6)
    p.t_timer = STICK * (1.0 + _stat(p, "stuck_time") + _stat(p, "state_duration"))
    p.t_tick = randf() * STUCK_TICK
    p.velocity = p.velocity.normalized() * 0.001
    p._trail.clear()
    if p.behaviour == "knife":
        var arr: Array = _knives.get(_key(p), [])
        var stuck: Array = arr.filter(func(k): return is_instance_valid(k) and k.t_state == STUCK)
        var cap := KNIFE_CAP + int(_stat(p, "knife_cap"))
        while stuck.size() > cap:
            _start_back(stuck.pop_front())
    p.queue_redraw()


static func _tick_stuck(p: Projectile, delta: float) -> void:
    if p.t_anchor != null:
        if is_instance_valid(p.t_anchor) and not p.t_anchor.is_queued_for_deletion():
            p.global_position = p.t_anchor.global_position + p.t_offset
        else:
            p.t_anchor = null   # its foe died: it drops to the floor
    p.t_timer -= delta
    p.t_tick -= delta
    if p.t_tick <= 0.0:
        p.t_tick = STUCK_TICK
        if p.behaviour == "knife":
            _stuck_effects(p)
    if p.t_timer <= 0.0:
        if p.behaviour == "sticky":
            _burst(p)
        else:
            _start_back(p)


## Storm Kunai arcs to the next stuck knife; Sticky Fingers poisons what touches a knife.
static func _stuck_effects(p: Projectile) -> void:
    var tree := p.get_tree()
    if _stat(p, "stuck_poison") > 0.0:
        for e in EnemyGrid.overlapping(tree, p.global_position, p.radius + 22.0):
            if is_instance_valid(e) and not e.is_queued_for_deletion() and e is Enemy:
                (e as Enemy).apply_element(Element.Kind.POISON, 3.0 * _stat(p, "stuck_poison"), p.shooter)
    if p.gun_id == "storm_kunai":
        var arr: Array = _knives.get(_key(p), [])
        var i := arr.find(p)
        for k in range(i + 1, arr.size()):
            var o = arr[k]
            if is_instance_valid(o) and o.t_state == STUCK and o.global_position.distance_to(p.global_position) <= STORM_LINK:
                var s := p._strike()
                s.damage *= 0.4
                s.potency *= 0.4
                for e in Strike.enemies_on_line(tree, p.global_position, o.global_position, 8.0):
                    s.hit(e, 1.0)
                Elements.lightning_arc.emit(p.global_position, o.global_position)
                break


static func _start_back(p: Projectile) -> void:
    if p == null or not is_instance_valid(p) or p.is_queued_for_deletion():
        return
    if p.behaviour == "sticky":
        _burst(p)
        return
    if not RETURNERS.has(p.behaviour):
        p.queue_free()
        return
    p.t_state = BACK
    p.t_anchor = null
    p.t_fresh = true
    p._hit.clear()
    p._inside.clear()
    p.queue_redraw()


## Flies back to where the shooter is now at RETURN_SPEED x, hitting along the way.
static func _tick_back(p: Projectile, delta: float) -> void:
    if p.shooter == null or not is_instance_valid(p.shooter) or p._age > 8.0:
        p.queue_free()
        return
    if p.t_fresh:
        # The way back starts by pulling out of what it was stuck in or last hit.
        p.t_fresh = false
        p._inside.clear()
        p._touch_enemies()
        if p.is_queued_for_deletion():
            return
    var to := home(p) - p.global_position
    var step := p.t_speed0 * RETURN_SPEED * maxf(1.0, p.t_mult) * delta
    if to.length() <= maxf(18.0, step):
        # Caught: it vanishes quietly, no effect and no sound.
        Items.fire(p.shooter, "catch", { "pos": p.global_position, "gun": p.gun_id })
        p.queue_free()
        return
    p.velocity = to.normalized() * p.t_speed0 * RETURN_SPEED
    p.position += to.normalized() * step
    p._touch_enemies()
    if p.is_queued_for_deletion():
        return
    _trail(p)


## Every thrown knife of `player` that is stuck or flying out comes back at once (Recall),
## hitting `mult` times as hard on the way.
static func recall_all(player: Player, mult: float = 2.0) -> int:
    var n := 0
    var prefix := "%d:" % player.get_instance_id()
    for key in _knives.keys():
        if not String(key).begins_with(prefix):
            continue
        for k in (_knives[key] as Array).duplicate():
            if is_instance_valid(k) and not k.is_queued_for_deletion() and k.t_state != BACK:
                k.t_mult = mult
                _start_back(k)
                n += 1
    return n


static func _start_orbit(p: Projectile, e: Node2D) -> void:
    p.t_state = ORBIT
    p.t_anchor = e
    p.t_angle = (p.global_position - e.global_position).angle()
    p.t_laps = 0.0
    p._hit.clear()
    p._hit[e] = true


## Wind Star: two laps at STAR_ORBIT px around its target; each lap hits the target once
## and whatever the star touches on the way.
static func _tick_orbit(p: Projectile, delta: float) -> void:
    var e = p.t_anchor
    if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
        p.t_anchor = null
        _start_back(p)
        return
    var step := TAU * STAR_SPIN * delta
    p.t_angle += step
    var before := int(p.t_laps)
    p.t_laps += step / TAU
    p.global_position = e.global_position + Vector2.RIGHT.rotated(p.t_angle) * STAR_ORBIT
    p._touch_enemies()
    if p.is_queued_for_deletion():
        return
    if int(p.t_laps) > before:
        p._hit.clear()
        p._hit[e] = true
        if e is Enemy:
            hit(p, e as Enemy, 1.0)
    var laps := STAR_LAPS + int(_stat(p, "disc_bounce")) + int(_stat(p, "thrown_bounce"))
    if p.t_laps >= float(laps):
        if e is Enemy:
            _last_hit(p, e as Enemy)
        _start_back(p)
        return
    _trail(p)


# --- Grenades and bursts ----------------------------------------------------------------


## A grenade bounces once off the first foe it rolls into, then stops on the next.
static func _grenade_touch(p: Projectile) -> void:
    for e in EnemyGrid.overlapping(p.get_tree(), p.global_position, p.radius):
        if p._hit.has(e) or e.emerge > 0.0:
            continue
        p._hit[e] = true
        if not p.t_bounced:
            p.t_bounced = true
            var away: Vector2 = (p.global_position - e.global_position).normalized()
            p.velocity = (p.velocity.bounce(away) if away != Vector2.ZERO else -p.velocity) * 0.45
        else:
            p.velocity *= 0.2
        return


## The burst (grenades when the fuse ends, sticky darts): everything within the splash at
## full damage, the element on the floor, shards, bomblets.
static func _burst(p: Projectile) -> void:
    if p.is_queued_for_deletion():
        return
    var tree := p.get_tree()
    var r := maxf(p.splash_radius, p.radius * 3.0)
    var s := p._strike()
    var last: Enemy = null
    for e in Strike.enemies_in(tree, p.global_position, r):
        s.hit(e, 1.0, e.global_position)
        last = e
    s.touch_world(tree, p.global_position, r * 0.6, Vector2.ZERO)
    s.touch_clouds(tree, p.global_position, r * 0.6, {})
    Elements.nova.emit(p.global_position, r, Color(p.color, 0.45))
    p._leave_material(r * 0.6, true)
    Sfx.play_at("burst_small", p.global_position, -6.0)
    var shards := p.shard_count + int(_stat(p, "grenade_shards") if p.behaviour == "grenade" else 0.0)
    if shards > 0:
        p.shard_count = shards
        p._burst_shards(null)
    if p.behaviour == "grenade":
        if p.gun_id == "cluster_bomb" and not p.t_child:
            _spawn_bomblets(p, 5, 0.35, 0.35)
        elif _stat(p, "grenade_twice") > 0.0 and not p.t_child:
            _spawn_bomblets(p, 1, 0.6, 0.4)   # Double Fuse: a second burst on the spot
    if last != null:
        _last_hit(p, last)
    p._landed = true
    p.queue_free()


## Child grenades: `n` at `dmg_mult` of the damage, each with a `fuse` s fuse. One stays put;
## several scatter.
static func _spawn_bomblets(p: Projectile, n: int, dmg_mult: float, fuse: float) -> void:
    var parent := p.get_parent()
    if parent == null:
        return
    for i in n:
        var b := Projectile.new()
        b.behaviour = "grenade"
        b.t_child = true
        b.velocity = Vector2.ZERO if n == 1 else Vector2.RIGHT.rotated(TAU * float(i) / float(n) + randf_range(-0.3, 0.3)) * randf_range(160.0, 240.0)
        b.damage = p.damage * dmg_mult
        b.potency = p.potency * dmg_mult
        b.element = p.element
        b.extra_elements = p.extra_elements
        b.linger = fuse
        b.lifetime = fuse
        b.splash_radius = maxf(30.0, p.splash_radius * 0.6)
        b.radius = maxf(3.0, p.radius * 0.7)
        b.color = p.color
        b.shooter = p.shooter
        b.gun_id = p.gun_id
        b.position = p.position
        parent.add_child.call_deferred(b)


# --- Spawning helpers (Gun.shoot_from) --------------------------------------------------


## Fills in what a thrown projectile needs at the muzzle: the star's target, the point
## Singularity's pellets meet at, the axes' crossing curve.
static func prepare(p: Projectile, g: Gun, muzzle: Vector2, dir: Vector2, i: int, count: int) -> void:
    match p.behaviour:
        "star":
            var tgt := Strike.nearest(g.get_tree(), muzzle, g.effective_range(), {})
            p.home_target = tgt
        "converge":
            var tgt2 := Strike.nearest(g.get_tree(), muzzle, g.effective_range(), {})
            var d := 180.0
            if tgt2 != null:
                d = clampf(muzzle.distance_to(tgt2.global_position), 70.0, 300.0)
            p.t_point = muzzle + dir * d   # `dir` is the volley's centre line
        "grenade":
            # Rolled to stop at its target: v0 = d * k / (1 - e^(-k * fuse)) under the roll's
            # decay, so the fuse runs out where the foe stands.
            var tg := Strike.nearest(g.get_tree(), muzzle, g.effective_range() * 1.1, {})
            var d2 := g.effective_range() * 0.6
            if tg != null:
                d2 = clampf(muzzle.distance_to(tg.global_position), 40.0, g.effective_range() * 1.1)
            var fuse := maxf(0.2, p.linger * (1.0 - _stat(p, "fuse_cut")))
            var v0 := d2 * GRENADE_ROLL / maxf(0.05, 1.0 - exp(-GRENADE_ROLL * fuse))
            p.velocity = p.velocity.normalized() * v0
        "boomerang":
            if g.data.id == "crossing_axes" and count > 1:
                p.helix_sign = 1.0 if i % 2 == 0 else -1.0


# --- Looks -----------------------------------------------------------------------------


## The thrown object itself, in its element colour (2.4, section 7): knives spin slowly and
## stuck ones tilt 30 degrees into the floor; discs and stars spin fast. True when drawn.
static func draw(p: Projectile) -> bool:
    var c := p.color
    var dark := Color(0.08, 0.07, 0.09, 0.9)
    var dir := p.velocity.normalized() if p.velocity.length() > 0.01 else Vector2.RIGHT
    var r := p.radius
    for i in range(p._trail.size() - 1):
        var f := 1.0 - float(i) / float(p._trail.size())
        p.draw_line(p.to_local(p._trail[i]), p.to_local(p._trail[i + 1]), Color(c, 0.3 * f), maxf(1.0, r * 0.8 * f))
    match p.behaviour:
        "knife", "sticky":
            var a := dir.angle() + (p._age * 3.0 if p.t_state == FLY or p.t_state == BACK else 0.0)
            if p.t_state == STUCK:
                a = dir.angle() + 0.52
            var v := Vector2.RIGHT.rotated(a)
            var n := v.orthogonal()
            var len := r * (2.6 if p.behaviour == "knife" else 2.0)
            var tip := v * len
            var pts := PackedVector2Array([tip, n * r * 0.55, -v * len * 0.35, -n * r * 0.55])
            p.draw_colored_polygon(pts, Color(0.78, 0.8, 0.86) if p.element == Element.Kind.NONE else c)
            p.draw_polyline(PackedVector2Array([tip, n * r * 0.55, -v * len * 0.35, -n * r * 0.55, tip]), dark, 1.0)
            p.draw_line(-v * len * 0.35, -v * len * 0.8, Color(0.3, 0.2, 0.14), 2.0)
            if p.behaviour == "sticky" and p.t_state == STUCK:
                var k := 1.0 - clampf(p.t_timer / STICKY_FUSE, 0.0, 1.0)
                p.draw_circle(Vector2.ZERO, r * (0.6 + 0.5 * k), Color(c, 0.35 + 0.3 * k))
        "disc", "star":
            var spin := p._age * 18.0
            if p.behaviour == "disc":
                p.draw_circle(Vector2.ZERO, r, Color(c, 0.85))
                p.draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, dark, 1.0)
                p.draw_arc(Vector2.ZERO, r * 0.55, spin, spin + PI * 1.2, 8, Color(1, 1, 1, 0.7), 1.2)
            else:
                var pts2 := PackedVector2Array()
                for k in 8:
                    pts2.append(Vector2.RIGHT.rotated(spin + PI * 0.25 * float(k)) * (r * 1.4 if k % 2 == 0 else r * 0.5))
                p.draw_colored_polygon(pts2, c)
                pts2.append(pts2[0])
                p.draw_polyline(pts2, dark, 1.0)
        "grenade":
            p.draw_circle(Vector2.ZERO, r, Color(c.darkened(0.25), 1.0))
            p.draw_arc(Vector2.ZERO, r, 0.0, TAU, 14, dark, 1.0)
            # The fuse spark blinks faster as it burns down (no floor marker).
            var left := clampf(p.lifetime / maxf(0.1, p.linger), 0.0, 1.0)
            if fmod(p._age, 0.08 + 0.2 * left) < 0.05:
                p.draw_circle(Vector2(r * 0.6, -r * 0.8), 1.6, Color(1, 0.95, 0.7))
        "javelin":
            var v2 := dir * r * 3.6
            p.draw_line(-v2, v2, Color(0.5, 0.36, 0.22), 2.0)
            p.draw_colored_polygon(PackedVector2Array([v2 + dir * r * 1.2, v2 + dir.orthogonal() * r * 0.5, v2 - dir.orthogonal() * r * 0.5]), c)
        "bola":
            var a2 := p._age * 14.0
            var o := Vector2.RIGHT.rotated(a2) * r * 1.4
            p.draw_line(-o, o, Color(0.55, 0.45, 0.3), 1.0)
            p.draw_circle(o, r * 0.6, c)
            p.draw_circle(-o, r * 0.6, c)
        "anchor":
            if p.shooter != null and is_instance_valid(p.shooter):
                var hm := p.to_local(home(p))
                p.draw_dashed_line(hm, Vector2.ZERO, Color(0.55, 0.55, 0.6, 0.5), 1.5, 5.0)
            var up := -dir
            p.draw_line(up * r, -up * r * 0.6, Color(0.5, 0.52, 0.56), 3.0)
            p.draw_arc(-up * r * 0.2, r * 0.9, up.angle() + PI * 0.6, up.angle() + PI * 1.4, 10, c, 2.5)
            p.draw_circle(up * r, r * 0.35, Color(0.5, 0.52, 0.56))
        "bubble":
            p.draw_circle(Vector2.ZERO, r, Color(c, 0.18))
            p.draw_arc(Vector2.ZERO, r, 0.0, TAU, 18, Color(c, 0.75), 1.2)
            p.draw_circle(Vector2(-r * 0.35, -r * 0.35), r * 0.22, Color(1, 1, 1, 0.8))
        "harpoon":
            var back := Vector2.ZERO
            if p.shooter != null and is_instance_valid(p.shooter):
                back = p.to_local(home(p))
            p.draw_line(back.limit_length(70.0), Vector2.ZERO, Color(0.45, 0.4, 0.32, 0.45), 1.0)
            p.draw_line(-dir * r * 2.2, dir * r * 1.6, Color(0.6, 0.6, 0.65), 2.0)
            p.draw_colored_polygon(PackedVector2Array([dir * r * 2.6, dir * r * 1.2 + dir.orthogonal() * r * 0.8, dir * r * 1.2 - dir.orthogonal() * r * 0.8]), c)
        _:
            return false
    return true
