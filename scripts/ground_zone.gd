class_name GroundZone
extends Node2D
## One ground effect of a ground weapon (Arsenal expansion 2.6): an aura, pulse, trail,
## totem, field, snare, glyph or pod (GunData.mechanic "ground"). Mines stay in mine.gd.
##
## The rules:
## - Placement: rings and trails need no target. Pulses roll out when a foe is inside the
##   ring. Totems go at your feet when a foe is near. Fields go under the closest pack (the
##   middle of the foes within PACK_R of the closest one). Snares and pods go where the
##   closest foe will be in SNARE_LEAD s, 40 to 220 px from you. Glyphs appear where a foe
##   died (`on_kill`). Everything is placed from the closest enemy (decision 21).
## - Cap: at most CAP of a player's ground effects alive at once, today's pools and mines
##   included (group "ground_fx"); a trail counts one per three segments. The oldest
##   placed effect goes first; rings and trails are never evicted.
## - Ticks: a zone gathers its foes once per tick through one spatial query
##   (Strike.enemies_in), never per frame. Traps check their small circle every TRAP_POLL s.
## - Look (2.6, the rule that keeps hostile hazards readable): a dashed or dotted 1 px rim
##   at 50% alpha, a fill of at most 15% alpha in the element colour, no pulsing, a fade over
##   the last FADE s, drawn on the floor layer (z -1) under enemies and every telegraph. A
##   ring is a dashed circle only. A totem is a small pillar with an element gem, a trap a
##   jagged ring, a glyph a three-stroke rune, a trail a dotted line. No text; ticks are
##   silent and a zone makes a sound only when it is placed.
##
## Gun.gd calls `maintain` every frame for a ground weapon. Every hit goes through the
## weapon's own Strike (tier, mods, ground damage, crit), so items, telemetry and mastery
## see the weapon.

const CAP := 40
const FADE := 1.0
const TRAIL_STEP := 24.0
const TRAIL_MAX := 30
const TRAIL_HALF := 14.0      # half the trail's width: foes chasing you walk your line
const PACK_R := 60.0
const SNARE_LEAD := 0.6
const SNARE_MIN := 40.0
const SNARE_MAX := 220.0
const POD_TRIGGER := 50.0
const TRAP_POLL := 0.05
const ARM := 0.3
const GLYPH_GAP := 0.3
const RIM_A := 0.5
const FILL_A := 0.12
const HOLD := 1.2          # snares: seconds a foe is held (elites and bosses HOLD_ELITE)
const HOLD_ELITE := 0.4
const PLACE_DB := -10.0
const MAX_HITS := 12        # foes one zone tick may hit (like a melee swing)
const GEYSER_R := 25.0
const SPREAD := 0.75        # totems and fields: no new one within this share of the radius of another
## Effects kept up per weapon by style, before +1 projectile and Ground items.
const STYLE_CAP := { "aura": 1, "trail": 1, "totem": 2, "field": 2, "snare": 3, "glyph": 6, "pod": 4, "pulse": 2 }
## How long an untriggered trap waits (2.6).
const TRAP_LIFE := { "snare": 10.0, "glyph": 8.0, "pod": 8.0 }

static var _born := 0
static var _test_cap := -1
static var _dash := PackedVector2Array()   # a unit circle as 24 dashes (draw_multiline pairs)

var gun: Gun
var kind := "aura"
var radius := 60.0
var life := -1.0          # seconds left; -1 lasts while its weapon does (rings, trails)
var born := 0
var _life0 := 1.0
var _t := 0.0
var _tick := 0.0
var _gone := false
var _pts := PackedVector2Array()     # trail: segment points, oldest first
var _pt_t := PackedFloat32Array()    # trail: when each point was laid (zone time)
var _queue: Array = []               # pulse: [distance, enemy] not yet reached by the front
var _dur := 0.4                      # pulse: seconds to roll out
var _burst_k := 0                    # Geyser Field: which foe the next geyser bursts under
var _el_flip := false                # two-element fields alternate per tick


func _init(p_gun: Gun, p_kind: String, p_radius: float, p_life: float) -> void:
    gun = p_gun
    kind = p_kind
    radius = maxf(12.0, p_radius)
    life = p_life
    _life0 = maxf(0.1, p_life)
    z_index = -1   # the floor layer: under enemies (8) and every hostile telegraph
    _born += 1
    born = _born
    if _dash.is_empty():
        for k in 24:
            var a0 := TAU * float(k) / 24.0
            _dash.append(Vector2.RIGHT.rotated(a0))
            _dash.append(Vector2.RIGHT.rotated(a0 + TAU / 48.0))


func _ready() -> void:
    modulate.a = Settings.own_fx()   # "Your effects" (friend or foe)
    add_to_group("gun_fx")
    add_to_group("ground_fx")
    if kind in ["snare", "glyph", "pod"]:
        _tick = ARM


# --- The cap and the weapon's zones ----------------------------------------------


## Who placed a ground effect (zones, pools, mines), or null.
static func _owner(n: Node) -> Player:
    if n is GroundZone:
        return n.gun.player if is_instance_valid(n.gun) else null
    if "strike" in n and n.strike != null:
        return n.strike.shooter
    return null


## Cap units a node takes: a trail one per three segments, anything else one.
static func _units(n: Node) -> int:
    if n is GroundZone and n.kind == "trail":
        return int(ceil(float(n._pts.size()) / 3.0))
    return 1


## Live cap units of this player's ground effects.
static func count(p: Player) -> int:
    if p == null or not is_instance_valid(p) or not p.is_inside_tree():
        return 0
    var n := 0
    for z in p.get_tree().get_nodes_in_group("ground_fx"):
        if is_instance_valid(z) and not z.is_queued_for_deletion() and _owner(z) == p:
            n += _units(z)
    return n


## A pool or mine joins the cap: room is made first (the oldest goes), then it counts.
static func join(n: Node, p: Player) -> void:
    if p != null and is_instance_valid(p) and n.is_inside_tree():
        make_room(p, 1)
    n.add_to_group("ground_fx")
    _born += 1
    n.set_meta("born", _born)


static func _born_of(n: Node) -> int:
    if n is GroundZone:
        return n.born
    return int(n.get_meta("born", 0))


## Frees the oldest placed effects of this player until `need` more units fit under CAP.
## Rings and trails are never evicted. False when there is still no room.
static func make_room(p: Player, need: int) -> bool:
    if p == null or not is_instance_valid(p) or not p.is_inside_tree():
        return true
    var mine: Array = []
    var used := 0
    for z in p.get_tree().get_nodes_in_group("ground_fx"):
        if not is_instance_valid(z) or z.is_queued_for_deletion() or _owner(z) != p:
            continue
        used += _units(z)
        if z is GroundZone and (z.kind == "aura" or z.kind == "trail"):
            continue
        mine.append(z)
    if used + need <= CAP:
        return true
    mine.sort_custom(func(a, b): return _born_of(a) < _born_of(b))
    for z in mine:
        z.queue_free()
        used -= _units(z)
        if used + need <= CAP:
            return true
    return false


## Effects this weapon keeps up: its cap, +1 per extra projectile (2.2) and the Ground
## trap items. Rings and trails are always one.
static func cap_of(g: Gun) -> int:
    var st := g.data.style
    if st == "aura" or st == "trail":
        return 1
    var base := g.data.cap if g.data.cap > 0 else int(STYLE_CAP.get(st, 2))
    base += maxi(0, g.shot_count() - g.data.projectile_count)
    base += int(g.player.stat("trap_cap")) + test_cap()
    return maxi(1, base)


## `--ground-cap=N` (perf checks only): N more effects per weapon and 3N more trail points,
## so a test can fill the 40-effect cap without the items.
static func test_cap() -> int:
    if _test_cap < 0:
        _test_cap = 0
        for a in OS.get_cmdline_user_args():
            if a.begins_with("--ground-cap="):
                _test_cap = maxi(0, int(a.substr(13)))
    return _test_cap


## A zone's radius (2.2): half the range bonus, +10% per pierce, the size stats and Ground
## radius items; rings and pulses also +15% per extra projectile. A little bigger per tier.
static func radius_of(g: Gun) -> float:
    var p := g.player
    var base := g.data.max_range if g.data.style == "pulse" else g.data.aura_radius
    var m := 1.0 + 0.5 * (p.stat("range") + g._gm("g_range")) + 0.1 * float(g.shot_pierce() - g.data.pierce) \
        + p.stat("shot_size") + p.stat("zone_radius")
    if g.data.style == "aura" or g.data.style == "pulse":
        m += 0.15 * float(maxi(0, g.shot_count() - g.data.projectile_count)) + p.stat("ring_radius")
    elif g.data.style in ["snare", "glyph", "pod"]:
        m += p.stat("trap_radius")
    return base * maxf(0.4, m) * (1.0 + 0.05 * float(g.tier - 1))


## How long a placed zone lasts (2.2: duration items make zones last longer).
static func life_of(g: Gun) -> float:
    var p := g.player
    var base := float(TRAP_LIFE.get(g.data.style, g.data.linger))
    var m := 1.0 + p.stat("state_duration") + p.stat("zone_life")
    if g.data.style == "totem":
        m += p.stat("totem_life")
    elif g.data.style == "trail":
        m += p.stat("trail_life")
    return maxf(0.5, base * m)


## Seconds between two placements: the weapon's `lifetime`, faster with fire rate.
static func lay_gap(g: Gun) -> float:
    var rate_m := g.fire_rate() / maxf(0.05, g.data.fire_rate) * (1.0 + g.player.stat("lay_rate"))
    return maxf(0.15, g.data.lifetime / maxf(0.2, rate_m))


## Called by Gun._process: keeps rings and trails up, lays totems, fields, snares and pods,
## rolls pulses out. Zones live in the room; leaving it frees them.
static func maintain(g: Gun, delta: float) -> void:
    var p := g.player
    if p == null or not is_instance_valid(p) or not p.is_inside_tree() or not p.alive:
        return
    var home := Strike.world_parent(g)
    if home == null or not home.is_inside_tree():
        return
    var room_id := home.get_instance_id()
    if g.summon_room != room_id:
        g.summon_room = room_id
        for b in g.bodies:
            if is_instance_valid(b):
                b.queue_free()
        g.bodies.clear()
        g.cooldown = 0.4
    g.bodies = g.bodies.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
    var st := g.data.style
    if st == "aura" or st == "trail":
        if g.bodies.is_empty():
            _place(g, home, st, p.global_position, -1.0)
        return
    if st == "glyph" or g.cooldown > 0.0:
        return   # glyphs come from kills (on_kill)
    var r := radius_of(g)
    match st:
        "pulse":
            if p.nearest_enemy(r) == null:
                g.cooldown = 0.1
                return
            _place(g, home, st, p.global_position, -1.0)
            g.cooldown = 1.0 / maxf(0.1, g.fire_rate())
            _pressure(g)
        "totem":
            # A new totem only away from this weapon's others: standing still keeps one up.
            var feet := p.global_position + Vector2(0, 6)
            if g.bodies.size() >= cap_of(g) or p.nearest_enemy(r + 60.0) == null or _covered(g, feet, r * SPREAD):
                g.cooldown = 0.15
                return
            _place(g, home, st, feet, life_of(g))
            g.cooldown = lay_gap(g)
        "field", "snare", "pod":
            var e := p.nearest_enemy(g.effective_range())
            if e == null or g.bodies.size() >= cap_of(g):
                g.cooldown = 0.15
                return
            var at := e.global_position
            if st == "field":
                # Under the closest pack no field of this weapon covers yet.
                at = Vector2.INF
                for o in Focus.pick_from(p.get_tree(), p.global_position, g.effective_range(), 4):
                    var c := _pack_centre(p.get_tree(), o)
                    if not _covered(g, c, r * SPREAD):
                        at = c
                        break
                if at == Vector2.INF:
                    g.cooldown = 0.15
                    return
            else:
                # Where the foe will be in SNARE_LEAD s, kept 40 to 220 px from you.
                at += e.velocity * SNARE_LEAD
                var off := at - p.global_position
                var d := off.length()
                if d < SNARE_MIN or d > SNARE_MAX:
                    at = p.global_position + (off / maxf(1.0, d)) * clampf(d, SNARE_MIN, SNARE_MAX)
            _place(g, home, st, at, life_of(g))
            g.cooldown = lay_gap(g)
            if st != "field":
                _pressure(g)


## Hair Trigger: the player's traps within `r` of them burst now.
static func spring_near(p: Player, r: float) -> void:
    for z in _traps(p):
        if z.global_position.distance_to(p.global_position) <= r + z.radius:
            z._spring(null)


## Spring All: every trap and mine of this player bursts.
static func spring_all(p: Player) -> void:
    for z in _traps(p):
        z._spring(null)
    if p != null and is_instance_valid(p) and p.is_inside_tree():
        for m in p.get_tree().get_nodes_in_group("mines"):
            if m is Mine and is_instance_valid(m) and m.strike.shooter == p:
                m.detonate()


## Seed: every totem, field, snare and pod weapon lays up to its cap at once, from the
## closest foes (totems at your feet).
static func seed_all(p: Player) -> void:
    if p == null or not is_instance_valid(p) or not p.alive:
        return
    for g in p.guns:
        if g.data.mechanic != "ground" or not g.data.style in ["totem", "field", "snare", "pod"]:
            continue
        var home := Strike.world_parent(g)
        if home == null or not home.is_inside_tree():
            continue
        g.bodies = g.bodies.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
        var room := cap_of(g) - g.bodies.size()
        if room <= 0:
            continue
        var foes := Focus.pick_from(p.get_tree(), p.global_position, g.effective_range(), room)
        for k in room:
            var at := p.global_position + Vector2.RIGHT.rotated(TAU * float(k) / float(room)) * 30.0
            if g.data.style != "totem" and k < foes.size():
                at = foes[k].global_position
            _place(g, home, g.data.style, at, life_of(g))


static func _traps(p: Player) -> Array:
    var out: Array = []
    if p == null or not is_instance_valid(p):
        return out
    for g in p.guns:
        if g.data.mechanic != "ground" or not g.data.style in ["snare", "glyph", "pod"]:
            continue
        for b in g.bodies:
            if is_instance_valid(b) and not b.is_queued_for_deletion() and not b._gone:
                out.append(b)
    return out


## A kill by this player: each glyph weapon it carries leaves a glyph there.
static func on_kill(p: Player, pos: Vector2) -> void:
    if p == null or not is_instance_valid(p) or not p.alive:
        return
    for g in p.guns:
        if g.data.mechanic != "ground" or g.data.style != "glyph" or g.cooldown > 0.0:
            continue
        g.bodies = g.bodies.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
        if g.bodies.size() >= cap_of(g):
            continue
        var home := Strike.world_parent(g)
        if home == null or not home.is_inside_tree():
            continue
        _place(g, home, "glyph", pos, life_of(g))
        g.cooldown = maxf(GLYPH_GAP, lay_gap(g))
        _pressure(g)


static func _place(g: Gun, home: Node, st: String, at: Vector2, secs: float) -> GroundZone:
    var units := 1
    if not make_room(g.player, units):
        return null
    var z := GroundZone.new(g, st, radius_of(g), secs)
    home.add_child(z)
    z.global_position = at
    g.bodies.append(z)
    if st == "pulse":
        z._start_pulse()
    elif st == "field":
        g.strike().stamp(z, at, z.radius * 0.7, true)
    if st != "aura" and st != "trail" and st != "pulse":
        Summon.sound(g.data.element, at, PLACE_DB)
        var fx := Strike.fx_of(z)
        if fx != null:
            fx.pixels(g.data.element, at, 4, 30.0, 6.0)
    return z


## Whether a zone of this weapon already sits within `d` of `at`.
static func _covered(g: Gun, at: Vector2, d: float) -> bool:
    for b in g.bodies:
        if is_instance_valid(b) and not b.is_queued_for_deletion() and b.global_position.distance_to(at) < d:
            return true
    return false


## The densest point near the closest foe: the middle of the foes within PACK_R of it.
static func _pack_centre(tree: SceneTree, e: Enemy) -> Vector2:
    var sum := Vector2.ZERO
    var n := 0
    for o in Strike.enemies_in(tree, e.global_position, PACK_R):
        sum += o.global_position
        n += 1
    return e.global_position if n == 0 else sum / float(n)


static func _pressure(g: Gun) -> void:
    g.player.add_pressure(g.data.pressure_per_shot * (1.0 + g._gm("g_pressure")))


# --- A zone at work --------------------------------------------------------------


func _strike() -> Strike:
    var el := -1
    if gun.data.alt_element != Element.Kind.NONE:
        _el_flip = not _el_flip
        el = gun.data.alt_element if _el_flip else gun.data.element
    return gun.strike(el)


func _physics_process(delta: float) -> void:
    if _gone or not is_instance_valid(gun) or not is_instance_valid(gun.player):
        queue_free()
        return
    _t += delta
    if life > 0.0:
        life -= delta
        if life <= 0.0:
            queue_free()
            return
        if life < FADE:
            queue_redraw()
    match kind:
        "aura":
            global_position = gun.player.global_position
            _tick_zone(delta)
        "trail":
            _tick_trail(delta)
        "pulse":
            _tick_pulse()
        "totem", "field":
            _tick_zone(delta)
        "snare", "glyph", "pod":
            _tick_trap(delta)


## Rings, totems and fields: every 1 / fire rate s, one query, everything inside is hit.
func _tick_zone(delta: float) -> void:
    _tick -= delta
    if _tick > 0.0:
        return
    var tree := get_tree()
    var c := global_position
    var foes := Strike.enemies_in(tree, c, radius)
    if foes.is_empty():
        _tick = 0.1   # nothing inside: look again soon (cheap, one query)
        return
    _tick = _tick_gap()
    if foes.size() > MAX_HITS:
        # At most MAX_HITS foes a tick, the closest to the zone first (bounds the cost).
        foes.sort_custom(func(a, b): return a.global_position.distance_squared_to(c) < b.global_position.distance_squared_to(c))
        foes.resize(MAX_HITS)
    var s := _strike()
    _react(s)
    var id := gun.data.id
    match id:
        "pyre_totem":
            # Throws fire at the two foes closest to it.
            foes.sort_custom(func(a, b): return a.global_position.distance_squared_to(c) < b.global_position.distance_squared_to(c))
            var fx := Strike.fx_of(self)
            for k in mini(2, foes.size()):
                var e: Enemy = foes[k]
                s.hit(e, 1.0, e.global_position)
                if fx != null:
                    fx.ray(c + Vector2(0, -14), e.global_position, Color(s.color, 0.5), 0.12, 1.0)
            _pressured()
            return
        "geyser_field":
            # A geyser bursts under one foe in the field each tick (turn about), splashing
            # GEYSER_R px: steam where it lands, not over the whole field.
            _burst_k += 1
            var at: Vector2 = foes[_burst_k % foes.size()].global_position
            for e in Strike.enemies_in(tree, at, GEYSER_R):
                s.hit(e, 1.0, e.global_position)
            var fx := Strike.fx_of(self)
            if fx != null:
                fx.pixels(gun.data.element, at, 5, 60.0, 4.0)
            _pressured()
            return
        "lightning_rods":
            for e in foes:
                s.hit(e, 1.0, e.global_position)
            _arc_to_rods(s)
            _pressured()
            return
    var p := gun.player
    var move_mult := 1.0
    if kind == "aura" and p.velocity.length() > 40.0:
        move_mult += p.stat("ring_move")   # Footwork
    var slow := p.stat("zone_slow")
    for e in foes:
        var knock := Vector2.ZERO
        if gun.data.knockback != 0.0:
            knock = (e.global_position - c).normalized() * gun.data.knockback
        var mult := move_mult
        if id == "corrosion_halo" and (e.is_elite or e.boss_kind != ""):
            mult = 1.5   # armoured foes lose it faster
        s.hit(e, mult, e.global_position, knock)
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        if slow > 0.0:
            e.apply_slow(1.0 - slow, 0.6)   # Salted Earth
        match id:
            "thirst":
                e.apply_slow(0.75, 0.6)
            "corrosion_halo":
                e.corrode(1.0)
            "slick_field":
                e.apply_slow(0.8, 0.6)
            "hoarfrost":
                e.apply_slow(0.6, 0.6)   # the floor is ice: they slip
    _pressured()


## Seconds between ticks: 1 / fire rate, faster with Ley Lines.
func _tick_gap() -> float:
    return 1.0 / maxf(0.1, gun.fire_rate() * (1.0 + gun.player.stat("zone_rate")))


## The Ground resonance at 5: where this zone touches another of yours with a different
## element, its hits carry that element too (your zones react with each other).
func _react(s: Strike) -> void:
    var p := gun.player
    if p.stat("ground_react") <= 0.0:
        return
    for g in p.guns:
        if g.data.mechanic != "ground":
            continue
        for b in g.bodies:
            if b == self or not is_instance_valid(b) or b.kind == "trail" or b.kind == "pulse":
                continue
            var el: int = g.data.element
            if el == s.element or s.extras.has(el):
                continue
            if b.global_position.distance_to(global_position) <= radius + b.radius:
                var ex: Array = s.extras.duplicate()
                ex.append(el)
                s.extras = ex
                ProcFx.res_proc(p, "ground", gun.data.id)
                return


func _pressured() -> void:
    if kind == "aura" or kind == "totem" or kind == "field" or kind == "trail":
        GroundZone._pressure(gun)


## Lightning Rods: an arc between this rod and each other rod of its weapon within reach
## hits every foe on the line (one line query per pair, from the newer rod only).
func _arc_to_rods(s: Strike) -> void:
    var fx := Strike.fx_of(self)
    for b in gun.bodies:
        if b == self or not is_instance_valid(b) or b.born > born:
            continue
        var other: Vector2 = b.global_position
        if other.distance_to(global_position) > 260.0:
            continue
        for e in Strike.enemies_on_line(get_tree(), global_position, other, 10.0):
            s.hit(e, 0.8, e.global_position)
        if fx != null:
            gun._arc_fx(global_position + Vector2(0, -14), other + Vector2(0, -14), s.color, s.element)


## Trails: a point every TRAIL_STEP px you move, each lasting the weapon's linger; every
## tick one query around the whole line, then each foe is checked against its segments.
func _tick_trail(delta: float) -> void:
    var p := gun.player
    global_position = Vector2.ZERO
    var here := p.global_position
    var changed := false
    if _pts.is_empty() or _pts[_pts.size() - 1].distance_to(here) >= TRAIL_STEP:
        _pts.append(here)
        _pt_t.append(_t)
        changed = true
    var keep := life_of(gun)
    var cap := TRAIL_MAX + 3 * (int(p.stat("trap_cap")) + test_cap())
    while not _pts.is_empty() and (_t - _pt_t[0] > keep or _pts.size() > cap):
        _pts.remove_at(0)
        _pt_t.remove_at(0)
        changed = true
    if changed:
        queue_redraw()
    _tick -= delta
    if _tick > 0.0 or _pts.size() < 2:
        return
    _tick = _tick_gap()
    var lo := _pts[0]
    var hi := _pts[0]
    for q in _pts:
        lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
        hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
    var mid := (lo + hi) * 0.5
    var half := (hi - lo).length() * 0.5 + TRAIL_HALF
    var s: Strike = null
    for e in Strike.enemies_in(get_tree(), mid, half):
        var reach := TRAIL_HALF + float(e.radius)
        var r2 := reach * reach
        var on := false
        for i in range(1, _pts.size()):
            var cp := Geometry2D.get_closest_point_to_segment(e.global_position, _pts[i - 1], _pts[i])
            if cp.distance_squared_to(e.global_position) <= r2:
                on = true
                break
        if on:
            if s == null:
                s = _strike()
                _react(s)
            s.hit(e, 1.0, e.global_position)
            if gun.player.stat("zone_slow") > 0.0 and is_instance_valid(e) and not e.is_queued_for_deletion():
                e.apply_slow(1.0 - gun.player.stat("zone_slow"), 0.6)
    if s != null:
        _pressured()


## Pulses: the ring rolls out over _dur s; each foe inside the full ring at the start is hit
## once when the front reaches it, and shoved outward.
func _start_pulse() -> void:
    _dur = 0.8 if gun.data.id == "tide_ring" else 0.4
    life = _dur + 0.15
    _life0 = life
    for e in Strike.enemies_in(get_tree(), global_position, radius):
        _queue.append([e.global_position.distance_to(global_position), e])
    _queue.sort_custom(func(a, b): return a[0] < b[0])
    var s := _strike()
    s.touch_world(get_tree(), global_position, radius, Vector2.ZERO)
    s.touch_clouds(get_tree(), global_position, radius, {})
    Summon.sound(gun.data.element, global_position, -4.0)
    set_meta("strike", s)


func _tick_pulse() -> void:
    var front := radius * clampf(_t / _dur, 0.0, 1.0)
    var s: Strike = get_meta("strike")
    var c := global_position
    while not _queue.is_empty() and float(_queue[0][0]) <= front:
        var e = _queue.pop_front()[1]
        if is_instance_valid(e) and not e.is_queued_for_deletion():
            s.hit(e, 1.0, e.global_position, (e.global_position - c).normalized() * gun.data.knockback)
    queue_redraw()


## Traps: armed after ARM s, they look at their small circle every TRAP_POLL s.
func _tick_trap(delta: float) -> void:
    _tick -= delta
    if _tick > 0.0:
        return
    _tick = TRAP_POLL
    var trig := radius
    if kind == "pod":
        trig = POD_TRIGGER
    var tree := get_tree()
    var c := global_position
    var touching := EnemyGrid.overlapping(tree, c, trig)
    var first: Enemy = null
    for e in touching:
        if is_instance_valid(e) and not e.is_queued_for_deletion() and e is Enemy and e.emerge <= 0.0:
            first = e
            break
    if first == null:
        return
    _spring(first)


func _spring(first: Enemy) -> void:
    if _gone:
        return
    _gone = true
    if first == null or not is_instance_valid(first):
        var near := Strike.enemies_in(get_tree(), global_position, radius * 1.5)
        if near.is_empty():
            queue_free()
            return
        first = near[0]
    var tree := get_tree()
    var c := global_position
    var s := _strike()
    var fx := Strike.fx_of(self)
    match gun.data.id:
        "rift_snare":
            # Holds the foe and the pack around it, drawing them in.
            for e in Strike.enemies_in(tree, c, radius * 2.4):
                s.hit(e, 1.0 if e == first else 0.5, e.global_position, (c - e.global_position).normalized() * 120.0)
                _hold(e)
        "holy_glyph":
            s.hit(first, 1.0, first.global_position)
            if fx != null:
                fx.ray(first.global_position + Vector2(0, -60), first.global_position, Color(s.color, 0.6), 0.15, 2.0)
        "spike_glyphs":
            for e in Strike.enemies_in(tree, c, radius * 1.4):
                s.hit(e, 1.0, e.global_position)
        "ash_garden":
            for e in Strike.enemies_in(tree, c, radius):
                s.hit(e, 1.0, e.global_position)
            s.stamp(self, c, radius * 0.6, true)
            s.touch_clouds(tree, c, radius * 0.6, {})
        _:   # snap_trap: bites and holds the first foe
            s.hit(first, 1.0, first.global_position)
            _hold(first)
    if fx != null:
        fx.ring(c, radius, s.color, 0.2)
    Summon.sound(gun.data.element, c, -6.0)
    if gun.player.stat("trap_echo") > 0.0:
        # Aftershock: the spot bursts again 0.5 s later at half damage.
        var r := radius * (1.4 if gun.data.id != "holy_glyph" else 1.0)
        tree.create_timer(0.5, false).timeout.connect(func():
            for e2 in Strike.enemies_in(tree, c, r):
                s.hit(e2, 0.5, e2.global_position))
    queue_free()


func _hold(e) -> void:
    if not is_instance_valid(e) or e.is_queued_for_deletion():
        return
    var secs := HOLD_ELITE if (e.is_elite or e.boss_kind != "") else HOLD
    secs *= 1.0 + gun.player.stat("hold_time")   # Tripwire
    e.stun(secs)
    e.apply_slow(0.5, secs)


# --- The floor look --------------------------------------------------------------


func _fade() -> float:
    var f := clampf(_t / 0.12, 0.0, 1.0)
    if life > 0.0 and kind != "pulse":
        f *= clampf(life / FADE, 0.0, 1.0)
    return f


## A dashed 1 px circle: the unit dash pattern scaled to `r` (one draw call).
func _dashed(r: float, col: Color) -> void:
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(r, r))
    draw_multiline(_dash, col, -1.0)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
    if not is_instance_valid(gun):
        return
    var c := gun.data.color()
    var f := _fade()
    match kind:
        "aura":
            _dashed(radius, Color(c, RIM_A * f))
        "pulse":
            var front := radius * clampf(_t / _dur, 0.0, 1.0)
            var k := 1.0 - clampf((_t - _dur) / 0.15, 0.0, 1.0)
            _dashed(maxf(6.0, front), Color(c, RIM_A * k))
        "field":
            draw_circle(Vector2.ZERO, radius, Color(c, FILL_A * f))
            _dashed(radius, Color(c, RIM_A * f))
        "totem":
            _dashed(radius, Color(c, RIM_A * 0.5 * f))
            draw_rect(Rect2(-3, -16, 6, 16), Color(0.55, 0.52, 0.48, 0.9 * f))
            draw_rect(Rect2(-4, -2, 8, 3), Color(0.40, 0.38, 0.35, 0.9 * f))
            draw_circle(Vector2(0, -18), 3.5, Color(c, 0.95 * f))
            draw_circle(Vector2(-1, -19), 1.2, Color(1, 1, 1, 0.7 * f))
        "snare", "pod":
            var pts := PackedVector2Array()
            var teeth := 10
            for k in teeth * 2 + 1:
                var a := TAU * float(k) / float(teeth * 2)
                pts.append(Vector2.RIGHT.rotated(a) * (radius if k % 2 == 0 else radius * 0.72))
            draw_circle(Vector2.ZERO, radius, Color(c, FILL_A * 0.6 * f))
            draw_polyline(pts, Color(c, RIM_A * f), -1.0)
            if kind == "pod":
                draw_circle(Vector2.ZERO, 4.0, Color(c, 0.6 * f))
                if gun.data.extra_element != Element.Kind.NONE:
                    draw_circle(Vector2.ZERO, 2.0, Color(Element.COLORS[gun.data.extra_element], 0.7 * f))
        "glyph":
            var w := radius * 0.6
            var col := Color(c, 0.6 * f)
            draw_line(Vector2(-w, w * 0.6), Vector2(0, -w), col, 1.5)
            draw_line(Vector2(0, -w), Vector2(w, w * 0.6), col, 1.5)
            draw_line(Vector2(-w * 0.6, w * 0.1), Vector2(w * 0.6, w * 0.1), col, 1.5)
            _dashed(radius, Color(c, RIM_A * 0.6 * f))
        "trail":
            if _pts.size() < 2:
                return
            # A dotted line: short dashes along the path, one draw call.
            var segs := PackedVector2Array()
            for i in range(1, _pts.size()):
                var a := _pts[i - 1]
                var b := _pts[i]
                var n := maxi(1, int(a.distance_to(b) / 8.0))
                for k in n:
                    var u := float(k) / float(n)
                    segs.append(a.lerp(b, u))
                    segs.append(a.lerp(b, u + 0.35 / float(n)))
            draw_multiline(segs, Color(c, RIM_A), 2.0)
