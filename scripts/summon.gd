class_name Summon
extends Node2D
## One summon body (Arsenal expansion 2.5): a drone, familiar, orbit, swarm flier or golem
## made by a summon weapon (GunData.mechanic "summon"). Turrets stay in turret.gd but join
## the same body cap.
##
## The rules that keep summons fair and cheap:
## - Leash: no body goes more than LEASH px from its player. They fight where you are.
## - They don't tank: enemies never target them, they have no collision and block no shot,
##   so a summon build can't make standing still safe. The threat stays on you.
## - They target by distance: each body asks Focus.pick_from with its own position every
##   RETARGET s and takes the enemy closest to itself (decision 21). Bodies of one weapon
##   take different targets when there are two or more to choose from. They take no Focus
##   slot and don't count against the 2-per-enemy limit.
## - Cap: at most CAP bodies per player across all four slots (swarm fliers and turrets
##   count). Past it the oldest turret goes first; with none, the new body is not made.
## - Respawn: bodies live in the room (Strike.world_parent). A body left in another room is
##   freed and its weapon makes a fresh one beside you, a beat apart.
## - Looks: a small round body with an element core, a dark rim and the player-colour friend
##   ring under it, a 2 px bob, no health bar, no text. Sounds sit 6 dB under a shot, at
##   most SOUND_MAX per 0.1 s.
##
## Gun.gd calls `maintain` every frame for a summon weapon. Everything a body hits goes
## through the weapon's own Strike (tier, mods, the family stats, crit), so on-hit items,
## telemetry and mastery see the weapon.

const LEASH := 260.0
const CAP := 16
const RETARGET := 0.2
const TOUCH_EVERY := 0.1
const SWARM_RESPAWN := 2.0
const SPAWN_GAP := 0.25
const SOUND_DB := -6.0
const SOUND_MAX := 4
## Default bodies per weapon by style when the entry sets no cap.
const STYLE_CAP := { "drone": 1, "familiar": 1, "orbit": 3, "swarm": 4, "golem": 1 }
## Body radius in px by style (2.5: drones, familiars and orbiters 10 to 18 px across, swarm
## fliers 4 px, the golem 26 px).
const STYLE_R := { "drone": 7.0, "familiar": 7.0, "orbit": 6.0, "swarm": 2.5, "golem": 13.0 }

static var _snd_ms := 0
static var _snd_n := 0

var gun: Gun
var kind := "drone"
var idx := 0
var element: int = Element.Kind.NONE
var target: Enemy = null
var temp_life := -1.0     # split slimes: seconds left (-1: lasts the room)
var state := 0            # swarm: 0 home, 1 flying, 2 gone (respawning), 3 latched (leeches)
var _retarget := 0.0
var _cd := 0.0
var _t := 0.0
var _touch := 0.0
var _touched := {}        # enemy instance id -> [game time of the last touch, touches]
var _gone := 0.0
var _zap_to := Vector2.INF
var _zap_t := 0.0
var _slam_t := 0.0
var _dash_to := Vector2.INF
var _trail := 0.0
var _face := Vector2.RIGHT


func _init(p_gun: Gun, p_kind: String, p_idx: int) -> void:
    gun = p_gun
    kind = p_kind
    idx = p_idx
    element = gun.data.element
    if gun.data.alt_element != Element.Kind.NONE and idx % 2 == 1:
        element = gun.data.alt_element
    z_index = 2   # over your ground effects, under enemies (8): a summon never covers a foe
    _cd = randf_range(0.1, 0.4)
    _t = randf() * TAU


func _ready() -> void:
    modulate.a = Settings.own_fx()   # "Your effects" (friend or foe)
    add_to_group("summon_bodies")
    add_to_group("gun_fx")


# --- The cap and the weapon's bodies ---------------------------------------------


## Live bodies (and turrets) of this player.
static func count(p: Player) -> int:
    if p == null or not is_instance_valid(p) or not p.is_inside_tree():
        return 0
    var n := 0
    for b in p.get_tree().get_nodes_in_group("summon_bodies"):
        if is_instance_valid(b) and not b.is_queued_for_deletion() and "gun" in b and is_instance_valid(b.gun) and b.gun.player == p:
            n += 1
    return n


## Makes room for one more body: true when there is room, or after the oldest turret of this
## player has gone (2.5: temporary bodies go first).
static func make_room(p: Player) -> bool:
    if count(p) < CAP:
        return true
    for b in p.get_tree().get_nodes_in_group("summon_bodies"):
        if b is Turret and is_instance_valid(b) and not b.is_queued_for_deletion() and is_instance_valid(b.gun) and b.gun.player == p:
            b.queue_free()
            return true
    return false


## Bodies this weapon keeps up: its cap, +1 per extra projectile (2.2), Pack Leader and the
## Swarm resonance (5.3), plus what the weapon has grown this room (Hive Queen's wasps).
static func cap_of(g: Gun) -> int:
    var base := g.data.cap if g.data.cap > 0 else int(STYLE_CAP.get(g.data.style, 1))
    var p := g.player
    base += maxi(0, g.shot_count() - g.data.projectile_count)
    base += int(p.stat("summon_cap"))
    return maxi(1, base + g.grown)


## Called by Gun._process: prunes dead and stranded bodies, makes missing ones a beat apart.
static func maintain(g: Gun, delta: float) -> void:
    var p := g.player
    if p == null or not is_instance_valid(p) or not p.is_inside_tree() or not p.alive:
        return
    var home := Strike.world_parent(g)
    var room_id := home.get_instance_id()
    if g.summon_room != room_id:
        # A new room: bodies stay behind with the old one; grown bodies go.
        g.summon_room = room_id
        g.grown = 0
        for b in g.bodies:
            if is_instance_valid(b):
                b.queue_free()
        g.bodies.clear()
        g.summon_t = 0.4
    g.bodies = g.bodies.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
    g.summon_t -= delta
    if g.summon_t > 0.0 or not home.is_inside_tree():
        return
    if g.bodies.size() >= cap_of(g):
        return
    g.summon_t = SPAWN_GAP
    if not make_room(p):
        return
    spawn(g, p.global_position)


static func spawn(g: Gun, at: Vector2, life := -1.0) -> Summon:
    var s := Summon.new(g, g.data.style, g.bodies.size())
    s.temp_life = life
    Strike.world_parent(g).add_child(s)
    s.global_position = at + Vector2.RIGHT.rotated(randf() * TAU) * 10.0
    g.bodies.append(s)
    return s


# --- Numbers from the weapon (the summon column of the stat map, 2.2) --------------


func _rate() -> float:
    var r := gun.fire_rate()
    if kind == "drone":
        r *= 1.0 + gun.player.stat("drone_rate")   # Overclock
    return maxf(0.1, r)


## Movement speed: the weapon's projectile_speed scaled by shot speed (and Swift Wings).
func _speed() -> float:
    return gun.data.projectile_speed * gun.speed_mult() * (1.0 + gun.player.stat("summon_speed"))


## Where a body may look for foes from itself: the weapon's range (range stat, mods).
func _reach() -> float:
    return gun.effective_range() * (1.0 + gun.player.stat("summon_reach"))


func _radius() -> float:
    return float(STYLE_R.get(kind, 7.0)) * maxf(0.5, gun.size_mult()) * (1.0 + gun.player.stat("summon_size"))


## The weapon's strike in this body's element. Tether adds your first weapon's element;
## the Swarm resonance at 5 adds your highest-tier weapon's (5.3).
func _strike() -> Strike:
    var s := gun.strike(element)
    var p := gun.player
    var adds: Array = []
    if p.stat("tether") > 0.0 and not p.guns.is_empty():
        adds.append(int(p.guns[0].data.element))
    if p.stat("swarm_tether") > 0.0 and not p.guns.is_empty():
        var best: Gun = p.guns[0]
        for g in p.guns:
            if g.tier > best.tier:
                best = g
        adds.append(int(best.data.element))
    if not adds.is_empty():
        var ex: Array = s.extras.duplicate()
        for a in adds:
            if a != Element.Kind.NONE and a != element and not ex.has(a):
                ex.append(a)
        s.extras = ex
    return s


func _pressure() -> void:
    gun.player.add_pressure(gun.data.pressure_per_shot * (1.0 + gun._gm("g_pressure")))


static func sound(el: int, pos: Vector2, db := 0.0) -> void:
    var now := Time.get_ticks_msec()
    if now - _snd_ms > 100:
        _snd_ms = now
        _snd_n = 0
    if _snd_n >= SOUND_MAX:
        return
    _snd_n += 1
    Sfx.play_at("shoot_" + String(Items.ELEMENT_KEYS.get(el, "stone")), pos, SOUND_DB + db)


# --- Targeting -------------------------------------------------------------------


## Bodies of one weapon take different targets when there are two or more to choose from.
func _sibling_targets() -> Dictionary:
    var skip := {}
    for b in gun.bodies:
        if b != self and is_instance_valid(b) and b.target != null and is_instance_valid(b.target):
            skip[b.target] = true
    return skip


func _live(e) -> bool:
    return e != null and is_instance_valid(e) and not e.is_queued_for_deletion() and e.hp > 0.0 and e.emerge <= 0.0


func _pick() -> void:
    var p := gun.player
    if p.stat("shared_mind") > 0.0 and not p.guns.is_empty() and not p.guns[0].targets.is_empty():
        # Shared Mind: your first weapon's target, when it is within the leash.
        var t = p.guns[0].targets[0]
        if _live(t) and t.global_position.distance_to(p.global_position) <= LEASH + 40.0:
            target = t
            return
    var got := Focus.pick_from(get_tree(), global_position, _reach(), 1, _sibling_targets(), p.global_position, LEASH + 40.0)
    if got.is_empty():
        got = Focus.pick_from(get_tree(), global_position, _reach(), 1, {}, p.global_position, LEASH + 40.0)
    target = got[0] if not got.is_empty() else null


# --- The tick --------------------------------------------------------------------


func _physics_process(delta: float) -> void:
    if gun == null or not is_instance_valid(gun) or not gun.is_inside_tree() or not is_instance_valid(gun.player):
        queue_free()
        return
    var p := gun.player
    _t += delta
    _cd -= delta
    _zap_t = maxf(0.0, _zap_t - delta)
    _slam_t = maxf(0.0, _slam_t - delta)
    if temp_life > 0.0:
        temp_life -= delta
        if temp_life <= 0.0:
            queue_free()
            return
    _retarget -= delta
    if _retarget <= 0.0 or not _live(target):
        _retarget = RETARGET
        if state != 3:
            _pick()
    match kind:
        "drone":
            _tick_drone(delta, p)
        "familiar":
            _tick_familiar(delta, p)
        "orbit":
            _tick_orbit(delta, p)
        "swarm":
            _tick_swarm(delta, p)
        "golem":
            _tick_golem(delta, p)
        _:
            _tick_drone(delta, p)
    # The leash: never more than LEASH px from you.
    var off := global_position - p.global_position
    if off.length() > LEASH:
        global_position = p.global_position + off.normalized() * LEASH
        if kind == "familiar" or kind == "golem":
            target = null
    queue_redraw()


func _move_to(to: Vector2, speed: float, delta: float) -> void:
    var d := to - global_position
    var step := speed * delta
    if d.length() <= step:
        global_position = to
    else:
        global_position += d.normalized() * step
    if d.length() > 1.0:
        _face = d.normalized()


## Where a body waits beside you: its own spot on a ring, by index.
func _home(p: Player, r: float) -> Vector2:
    var n := maxi(1, gun.bodies.size())
    var a := TAU * float(idx) / float(n) + float(gun.get_index()) * 0.9 - PI * 0.5
    return p.global_position + Vector2.RIGHT.rotated(a) * r


# --- Drones: hover by you and shoot their own target ------------------------------


func _tick_drone(delta: float, p: Player) -> void:
    var how := gun.data.behaviour
    var spot := _home(p, 50.0)
    if how == "rain" and _live(target):
        # Rain Drone, Thunderhead: hover over the closest pack.
        spot = target.global_position + Vector2(0, -6)
    _move_to(spot, maxf(160.0, _speed()), delta)
    if _cd > 0.0 or not _live(target):
        return
    if global_position.distance_to(target.global_position) > _reach() + 20.0:
        return
    _cd = 1.0 / _rate()
    _face = (target.global_position - global_position).normalized()
    match how:
        "rain":
            if global_position.distance_to(target.global_position) > 40.0:
                _cd = 0.1
                return
            var s := _strike()
            var r := gun.data.aura_radius * maxf(0.5, gun.size_mult())
            for e in Strike.enemies_in(get_tree(), target.global_position, r):
                s.hit(e, 1.0 if e == target else 0.6)
            s.stamp(self, target.global_position, r * 0.8, false)
            var fx := Strike.fx_of(self)
            if fx != null:
                fx.pixels(element, target.global_position, 5, 60.0, 3.0)
            if gun.data.extra_element == Element.Kind.SHOCK or element == Element.Kind.SHOCK:
                _zap_to = target.global_position
                _zap_t = 0.08
        "lob":
            gun.shoot_from(global_position, _face)
        _:
            # Zap: an instant thin line to its target (Scout Drone, Watcher's Eye).
            var s := _strike()
            s.hit(target, 1.0, target.global_position)
            if gun.data.id == "watchers_eye":
                target.marked_t = maxf(target.marked_t, 3.0)
            _zap_to = target.global_position
            _zap_t = 0.08
    _pressure()
    sound(element, global_position)


# --- Familiars: run at foes and bite ---------------------------------------------


func _tick_familiar(delta: float, p: Player) -> void:
    var spd := maxf(80.0, _speed())
    if _dash_to != Vector2.INF:
        # Blood Hound: a dash through the pack.
        var from := global_position
        _move_to(_dash_to, spd * 3.0, delta)
        var s := _strike()
        for e in Strike.enemies_on_line(get_tree(), from, global_position, _radius() + 4.0):
            var id: int = e.get_instance_id()
            if not _touched.has(id):
                _touched[id] = [_t, 1]
                s.hit(e, 1.0)
        if global_position.distance_to(_dash_to) < 2.0:
            _dash_to = Vector2.INF
        return
    if not _live(target):
        _move_to(_home(p, 34.0), spd, delta)
        return
    var to := target.global_position
    var touch := _radius() + float(target.radius) + 3.0
    var d := global_position.distance_to(to)
    if gun.data.id == "blood_hound" and _cd <= 0.0 and d < 160.0:
        _cd = 1.0 / _rate()
        _touched.clear()
        var dir := (to - global_position).normalized()
        _dash_to = to + dir * 60.0
        var off := _dash_to - p.global_position
        if off.length() > LEASH:
            _dash_to = p.global_position + off.normalized() * LEASH
        _pressure()
        sound(element, global_position)
        return
    if d > touch:
        _move_to(to - (to - global_position).normalized() * (touch - 1.0), spd, delta)
        if gun.data.id == "tar_crawler":
            _trail -= delta
            if _trail <= 0.0:
                _trail = 0.25
                var ts := _strike()
                ts.stamp(self, global_position, 14.0, false)
        return
    if _cd > 0.0:
        return
    _cd = 1.0 / _rate()
    _face = (to - global_position).normalized()
    var s := _strike()
    s.hit(target, 1.0, global_position.lerp(to, 0.6))
    _pressure()
    sound(element, global_position, -2.0)
    match gun.data.id:
        "acid_slime":
            # Splits in two on each hit, up to four.
            if gun.bodies.size() < 4 and make_room(p):
                var kid := spawn(gun, global_position, 8.0)
                kid.target = target
        "sun_and_moon":
            # A foe bitten by both bursts.
            var key := "sun_t" if element == gun.data.element else "moon_t"
            var other := "moon_t" if key == "sun_t" else "sun_t"
            var now := Enemy._game_now()
            target.set_meta(key, now)
            if target.has_meta(other) and now - float(target.get_meta(other)) < 2.0:
                target.remove_meta(other)
                target.remove_meta(key)
                var bs := _strike()
                for e in Strike.enemies_in(get_tree(), to, 60.0):
                    bs.hit(e, 1.5)
                var fx := Strike.fx_of(self)
                if fx != null:
                    fx.ring(to, 60.0, Element.COLORS[gun.data.alt_element], 0.25)


# --- Orbits: circle you and hit what they touch ------------------------------------


func _tick_orbit(delta: float, p: Player) -> void:
    var n := maxi(1, gun.bodies.size())
    var r := gun.data.aura_radius * (1.0 + 0.5 * p.stat("range") + 0.5 * p.stat("summon_size"))
    var spin := gun.data.projectile_speed / maxf(20.0, r)   # rad/s from the rim speed
    var a := _t * 0.0 + Time.get_ticks_msec() * 0.001 * spin + TAU * float(idx) / float(n) + float(gun.get_index()) * 0.7
    var spot := p.global_position + Vector2.RIGHT.rotated(a) * r
    _face = Vector2.RIGHT.rotated(a + PI * 0.5)
    global_position = spot
    _touch -= delta
    if _touch > 0.0:
        return
    _touch = TOUCH_EVERY
    var again := 1.0 / _rate()   # each foe is hit at most once per this
    var now := Enemy._game_now()
    var s: Strike = null
    for e in Strike.enemies_in(get_tree(), global_position, _radius() + 2.0):
        var id: int = e.get_instance_id()
        var rec: Array = _touched.get(id, [-99.0, 0])
        if now - float(rec[0]) < again:
            continue
        var touches := int(rec[1]) + 1 if now - float(rec[0]) < 2.0 else 1
        _touched[id] = [now, touches]
        if s == null:
            s = _strike()
            _pressure()
            sound(element, global_position, -3.0)
        var knock: Vector2 = (e.global_position - p.global_position).normalized() * gun.data.knockback
        s.hit(e, 1.0, global_position, knock)
        if gun.data.id == "frost_blades" and touches >= 2 and is_instance_valid(e):
            # A second touch freezes.
            e.freeze(0.6 if not e.is_elite else 0.25)
            _touched[id] = [now, 0]
    if _touched.size() > 64:
        _touched.clear()


# --- Swarms: small fliers that strike once, then respawn at you --------------------


func _tick_swarm(delta: float, p: Player) -> void:
    match state:
        2:
            _gone -= delta
            if _gone <= 0.0:
                state = 0
                global_position = p.global_position
                _cd = 1.0 / _rate()
            return
        3:
            # Leech Jar: latched on, bleeding the foe until it dies.
            if not _live(target):
                _vanish()
                return
            global_position = target.global_position + Vector2.RIGHT.rotated(float(idx) * 1.7) * float(target.radius) * 0.8
            if _cd <= 0.0:
                _cd = 1.0 / _rate()
                _strike().hit(target, 1.0)
                _pressure()
            return
        1:
            if not _live(target):
                state = 0
                return
            var to := target.global_position
            _move_to(to, maxf(200.0, _speed()), delta)
            if global_position.distance_to(to) <= float(target.radius) + 3.0:
                _arrive(p)
            return
    # Home: buzzing close beside you until there is a foe in reach.
    var wob := Vector2(cos(_t * 3.1 + idx), sin(_t * 2.3 + idx * 1.3)) * 6.0
    _move_to(_home(p, 22.0) + wob, maxf(200.0, _speed()), delta)
    if _cd <= 0.0 and _live(target):
        state = 1


func _arrive(p: Player) -> void:
    var s := _strike()
    var to := target.global_position
    match gun.data.id:
        "holy_wisps":
            # Bursts in light.
            for e in Strike.enemies_in(get_tree(), to, 40.0):
                s.hit(e, 1.0 if e == target else 0.5)
            var fx := Strike.fx_of(self)
            if fx != null:
                fx.ring(to, 40.0, Element.COLORS[element], 0.2)
        "leech_jar":
            s.hit(target, 1.0)
            state = 3
            _cd = 1.0 / _rate()
            _pressure()
            return
        _:
            s.hit(target, 1.0)
    _pressure()
    sound(element, to, -3.0)
    if gun.data.id == "hive_queen" and is_instance_valid(target) and target.hp <= 0.0:
        # Each kill adds a wasp, up to twelve.
        if gun.bodies.size() < 12 and make_room(p):
            gun.grown += 1
    _vanish()


func _vanish() -> void:
    if temp_life > 0.0:
        queue_free()   # a hatched wasp strikes once and is gone
        return
    state = 2
    _gone = SWARM_RESPAWN * maxf(0.2, 1.0 - gun.player.stat("swarm_respawn"))   # Quick Hatch
    target = null


# --- Items (Arsenal expansion 5.2) -----------------------------------------------


## Rally: every body of this player dashes to the foe nearest it and strikes at `mult`.
static func rally(p: Player, mult: float) -> void:
    for b in p.get_tree().get_nodes_in_group("summon_bodies"):
        if not (b is Summon) or not is_instance_valid(b) or b.is_queued_for_deletion() or b.gun.player != p:
            continue
        var got := Focus.pick_from(p.get_tree(), b.global_position, LEASH * 1.5, 1, {}, p.global_position, LEASH + 40.0)
        if got.is_empty():
            continue
        var e: Enemy = got[0]
        var to: Vector2 = e.global_position - (e.global_position - b.global_position).normalized() * (float(e.radius) + 4.0)
        b._zap_to = e.global_position
        b._zap_t = 0.08
        if b.kind != "orbit":
            b.global_position = to
        b.target = e
        b._strike().hit(e, mult)
    Summon.sound(Element.Kind.NONE, p.global_position)


## Brood and Call the Swarm: `n` wasps that strike once and are gone (they last `secs` at
## most). They fly for the weapon that made the kill (`gid`), else your first summon
## weapon, else your first weapon, and count toward the 16-body cap.
static func brood(p: Player, gid: String, at: Vector2, n: int, secs: float) -> void:
    var g: Gun = null
    for w in p.guns:
        if w.data.id == gid:
            g = w
    if g == null:
        for w in p.guns:
            if w.data.mechanic == "summon":
                g = w
                break
    if g == null and not p.guns.is_empty():
        g = p.guns[0]
    if g == null:
        return
    for i in n:
        if not make_room(p):
            return
        var s := Summon.new(g, "swarm", i)
        s.temp_life = secs
        Strike.world_parent(g).add_child(s)
        s.global_position = at + Vector2.RIGHT.rotated(randf() * TAU) * 12.0


# --- The golem: a big slow walker that slams packs ------------------------------------


func _tick_golem(delta: float, p: Player) -> void:
    var spd := maxf(60.0, _speed())
    if _live(target) and target.global_position.distance_to(p.global_position) < LEASH:
        var to := target.global_position
        var reach := gun.data.aura_radius * 0.5 + float(target.radius)
        if global_position.distance_to(to) > reach:
            _move_to(to, spd, delta)
        if _cd <= 0.0 and global_position.distance_to(to) <= reach + 6.0:
            _cd = 1.0 / _rate()
            _slam_t = 0.18
            var s := _strike()
            var r := gun.data.aura_radius * maxf(0.5, gun.size_mult())
            for e in Strike.enemies_in(get_tree(), global_position, r):
                var knock: Vector2 = (e.global_position - global_position).normalized() * gun.data.knockback
                s.hit(e, 1.0 if e == target else 0.6, e.global_position, knock)
            s.stamp(self, global_position, r * 0.7, false)
            var fx := Strike.fx_of(self)
            if fx != null:
                fx.smoke(global_position, 4, 8.0)
            _pressure()
            sound(element, global_position, -2.0)
        return
    var behind := p.global_position - p.aim_dir.normalized() * 46.0 if p.aim_dir != Vector2.ZERO else _home(p, 46.0)
    if global_position.distance_to(behind) > 20.0:
        _move_to(behind, spd, delta)


# --- Looks (Arsenal expansion 7) -------------------------------------------------


func _draw() -> void:
    if kind == "swarm" and state == 2:
        return
    var c: Color = Element.COLORS.get(element, Color(0.8, 0.8, 0.8))
    var r := _radius()
    var bob := sin(_t * TAU * 1.5) * 2.0 if kind != "orbit" and state != 3 else 0.0
    var pc: Color = gun.player.color if is_instance_valid(gun.player) else Color.WHITE
    # The friend marker: a small ring in the player's colour under the body.
    draw_set_transform(Vector2(0, r * 0.7 + 2.0), 0.0, Vector2(1.0, 0.45))
    if kind != "swarm":
        draw_circle(Vector2.ZERO, r + 1.0, Color(0, 0, 0, 0.28))
    draw_arc(Vector2.ZERO, r + 3.0, 0.0, TAU, 16, Color(pc, 0.55), 1.2)
    draw_set_transform(Vector2(0, -bob), 0.0, Vector2.ONE)
    if gun.data.id == "storm_kite" and is_instance_valid(gun.player):
        draw_line(Vector2.ZERO, to_local(gun.player.global_position) + Vector2(0, bob), Color(0.85, 0.85, 0.8, 0.35), 1.0)
    var rim := c.darkened(0.55)
    match kind:
        "swarm":
            draw_circle(Vector2.ZERO, r + 1.0, WeaponLooks.OUTLINE)
            draw_circle(Vector2.ZERO, r, c)
        "golem":
            var lift := -3.0 if _slam_t > 0.0 else 0.0
            draw_rect(Rect2(-r, -r * 0.4, r * 2.0, r * 1.2), WeaponLooks.OUTLINE)
            draw_rect(Rect2(-r + 1.5, -r * 0.4 + 1.5, r * 2.0 - 3.0, r * 1.2 - 3.0), Color(0.55, 0.45, 0.36))
            draw_rect(Rect2(-r * 0.7, -r * 1.2 + lift, r * 1.4, r * 0.9), WeaponLooks.OUTLINE)
            draw_rect(Rect2(-r * 0.7 + 1.5, -r * 1.2 + 1.5 + lift, r * 1.4 - 3.0, r * 0.9 - 3.0), Color(0.62, 0.52, 0.42))
            draw_circle(Vector2(0, -r * 1.55 + lift), r * 0.42, WeaponLooks.OUTLINE)
            draw_circle(Vector2(0, -r * 1.55 + lift), r * 0.42 - 1.5, c)
        _:
            draw_circle(Vector2.ZERO, r + 1.0, WeaponLooks.OUTLINE)
            draw_circle(Vector2.ZERO, r, rim)
            draw_circle(Vector2.ZERO, r * 0.62, c)
            match kind:
                "drone":
                    # Two rotor ticks.
                    for sx in [-1.0, 1.0]:
                        var at := Vector2(sx * (r + 2.0), -r * 0.5)
                        draw_line(at - Vector2(3, 0), at + Vector2(3, 0), Color(0.85, 0.85, 0.9, 0.8), 1.2)
                    if gun.data.id == "watchers_eye":
                        draw_circle(_face * r * 0.3, r * 0.25, Color(0.05, 0.02, 0.08))
                "familiar":
                    # Two eye dots, looking where it goes.
                    var side := _face.orthogonal() * r * 0.3
                    for s in [side, -side]:
                        draw_circle(_face * r * 0.35 + s, 1.3, Color(0.05, 0.03, 0.04))
                "orbit":
                    # A spike leading the way round.
                    draw_colored_polygon(PackedVector2Array([_face * (r + 5.0), _face.orthogonal() * r * 0.6, -_face.orthogonal() * r * 0.6]), c.lightened(0.15))
    if gun.data.rarity >= Items.Rarity.LEGENDARY:
        draw_arc(Vector2.ZERO, r + 1.5, 0.0, TAU, 16, Color(0.95, 0.8, 0.35, 0.8), 1.0)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if _zap_t > 0.0 and _zap_to != Vector2.INF:
        draw_line(Vector2(0, -bob), to_local(_zap_to), Color(c, 0.7 * _zap_t / 0.08), 1.5)
