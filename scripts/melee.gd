class_name Melee
extends RefCounted
## Melee swings (Arsenal expansion 2.3, decision A9). A melee weapon is still a Gun;
## Gun._fire_melee calls `swing` once per swing (+1 projectile is one more swing, back and
## forth). It swings only when an enemy is within reach of the player (Player.gun_dir) and
## takes no Focus slot. The weapon then really travels from its hover spot (A8) and hits
## only what its blade passes through: each frame its blade (a segment with a thickness) is
## tested along the path it moved, in ~10 px steps, against enemy circles. Each enemy is hit
## at most once a swing: the first at 100%, every other at FOLLOW, at most MAX_HITS. The
## first contact pauses the blade for HOLD (hit-stop), knocks the foe away from the pivot and
## leaves a small spark at the contact point.
##
## Styles (GunData.style), all from the hover spot toward the target:
##   sweep   the blade sweeps a real arc around the hover spot
##   cleave  wide (200 deg) and slow, big knockback
##   thrust  stabs out along a line through the target to the full reach and back
##   slam    the head arcs over and lands on the target; staggers ordinary enemies 0.3 s
##   lash    long reach; contact in the outer 30% (the tip) hits for x1.5
##   jab     a short fast thrust; every 4th is a finisher at x2.5
##   spin    sweeps, and every 3rd swing is a full circle around the player
##
## Stats (2.2): fire rate and half the shot speed make swings faster; +1 projectile is +1
## swing; each pierce is +10% reach; range adds half its bonus as reach; shot size widens
## the arc by 5 deg per 10% and thickens the blade; each bounce lets the blade reach 1 more
## enemy just past its reach. Item stats: melee_dmg, reach, swing_speed, arc (deg), whirl
## (every 5th swing is a full spin), finisher_twice, cleave_bleed, melee_crit (buff: swings
## crit), blade_wave (the Blade resonance at 5: the blade reaches WAVE_REACH further at half).

const MAX_HITS := 12
## Every hit after the first in one swing. The spec said 75%; measured on --gun-probe that
## put melee pack damage at 4 to 8 times the best gun of its weight, against the spec's
## own rule (pack at most the best gun's), so it is 25% (batch 1 deviation).
const FOLLOW := 0.25
const TIP_FROM := 0.7         # lash: the outer 30% of the reach is the tip
const TIP_MULT := 1.5
const FINISHER_EVERY := 4
const FINISHER_MULT := 2.5
const SPIN_EVERY := 3
const WHIRL_EVERY := 5
const STAGGER := 0.3
const BOUNCE_REACH := 40.0    # a bounce point reaches one enemy up to this far past the reach
const WAVE_REACH := 80.0      # Blade resonance at 5
const SLAM_TRIGGER := 0.8     # a slam triggers when an enemy is within centre + 80% radius
## Half the blade's thickness by style (px, default 6); shot size thickens it.
const BLADE := { "jab": 8.0, "cleave": 9.0, "lash": 5.0 }
const HOLD := 0.045           # hit-stop: the blade pauses this long on a swing's first contact
const SPARK_PX := 13.0        # the contact spark

## Card lines (section 4.2's behaviour column). A style's default line covers the rest.
const LINES := {
    "tin_sabre": "A plain, quick sweep in front of you",
    "ember_brand": "A burning sweep; the first foe hit takes double",
    "frost_hatchet": "A wide chop that chills all in front",
    "tide_spear": "A long thrust that soaks the whole line",
    "spark_knuckles": "Fast jabs; every fourth is a shock finisher",
    "bone_club": "A slam that staggers small foes",
    "thorn_whip": "A long lash; the tip poisons twice as hard",
    "pitch_cleaver": "Chops oil foes; burning ones take +40%",
    "gale_glaive": "Every third swing spins and throws foes back",
    "etching_claws": "Jabs strip armour; the finisher splashes acid",
    "blood_rapier": "Quick thrusts; bleeding foes are struck twice",
    "sanctified_mace": "Slams mark foes for your other weapons",
    "hollow_sickle": "Spins drag nearby foes into the blade",
    "storm_lash": "The tip's crack arcs to one more foe",
    "parry_blade": "Swings cut enemy shots out of the air",
    "magma_maul": "Slams crack a burning fissure for 3 s",
    "rimefang": "A long thrust; frozen foes in the line shatter",
    "venom_pike": "A piercing thrust that leaves a poison line",
    "crimson_gauntlets": "Finishers burst a foe's whole bleed at once",
    "riptide_whip": "The crack pulls the struck foe to you",
    "storm_pike": "A heavy shock sweep that throws foes back",
    "thunder_halberd": "The thrust soaks; the follow-up sweep shocks",
    "eclipse_scythe": "Spins alternate light and dark and react",
    "twin_fangs": "Two blades strike the two closest foes at once",
}
const STYLE_LINES := {
    "sweep": "Sweeps an arc in front of you",
    "cleave": "A wide, slow chop with big knockback",
    "thrust": "A long thrust through every foe in line",
    "slam": "A slam ahead that staggers small foes",
    "lash": "A long lash; the tip hits x1.5",
    "jab": "Fast jabs; every fourth is a finisher",
    "spin": "Sweeps; every third swing spins around you",
}


## Single-target factor on damage x rate (GunData.dps_at): finishers, double strikes.
static func single_mult(d: GunData) -> float:
    var m := 1.0
    if d.style == "jab":
        m *= (float(FINISHER_EVERY - 1) + FINISHER_MULT) / float(FINISHER_EVERY)
    match d.id:
        "ember_brand", "twin_fangs", "thunder_halberd":
            m *= 2.0
        "blood_rapier":
            m *= 1.5
    return m


static func how(d: GunData) -> String:
    return String(LINES.get(d.id, STYLE_LINES.get(d.style, "Sweeps an arc in front of you")))


## Reach in px with gear: half the range bonus, the reach stat, +10% per pierce.
static func reach(g: Gun) -> float:
    var d := g.data
    var bonus := 0.5 * (g.player.stat("range") + g._gm("g_range")) + g.player.stat("reach") + g._gm("g_reach")
    return d.max_range * maxf(0.4, 1.0 + bonus) * (1.0 + 0.1 * float(g.shot_pierce()))


## How close an enemy must be for this weapon to swing.
static func trigger_reach(g: Gun) -> float:
    if g.data.style == "slam":
        var scale := reach(g) / maxf(1.0, g.data.max_range)
        return reach(g) + g.data.aura_radius * scale * SLAM_TRIGGER
    return reach(g) + 4.0


## Half the arc in radians: shot size adds 5 deg per 10%, the arc stat adds degrees.
static func half_arc(g: Gun, style: String = "") -> float:
    var deg := g.data.arc_deg
    if style == "sweep" and deg <= 30.0:
        deg = 120.0   # the halberd's follow-up sweep
    deg += 50.0 * g.player.stat("shot_size") + g.player.stat("arc")
    return deg_to_rad(clampf(deg, 10.0, 360.0) * 0.5)


## One swing, alive for `dur` seconds while the weapon travels its path (A9).
class Swing:
    var style := ""
    var reach := 0.0         # the player's reach (+4): no tip goes past it from the player
    var el := 0
    var full := false        # a full spin: pivots on the player, not the hover spot
    var finisher := false
    var back := false        # the return stroke of a +1 swing sweeps the other way
    var second := false      # Twin Fangs' second blade (drawn, not the held sprite)
    var dir := Vector2.RIGHT # from the pivot toward the target
    var radius := 0.0        # sweep: blade length; thrust: tip reach; slam: landing distance
    var far := 0.0           # radius plus the bounce point and the Blade wave
    var half := 0.0
    var slam_rad := 0.0
    var blade := 6.0         # half the blade's thickness, px
    var t := 0.0
    var dur := 0.2
    var hold := 0.0          # hit-stop: the blade pauses on its first contact
    var s: Strike
    var done := {}           # enemy instance id -> true: each enemy at most once a swing
    var n := 0               # hits landed
    var past := 0            # hits past the reach taken by bounce points
    var extra := 0
    var wave := false
    var landed := false      # slam: the head has come down
    var any := false


## One swing toward `dir` (from the player). `back` mirrors the stroke (+1 swing).
static func swing(g: Gun, dir: Vector2, back: bool) -> void:
    if g.player == null or not is_instance_valid(g.player) or not g.is_inside_tree():
        return
    var d := g.data
    g.melee_n += 1
    var n := g.melee_n
    g.swing_tilt = 1.0
    var el := d.element
    if d.id == "eclipse_scythe":
        el = d.alt_element if n % 2 == 0 else d.element
    var style := d.style
    var full := false
    if style == "spin" and n % SPIN_EVERY == 0:
        full = true
    if g.player.stat("whirl") > 0.0 and n % WHIRL_EVERY == 0:
        full = true
    var finisher := style == "jab" and n % FINISHER_EVERY == 0
    if finisher or full:
        ProcFx.weapon_proc(g)   # every Nth swing: the weapon lights up (rate-limited)
    _start(g, _target(g, dir), dir, style, el, full, finisher, back)
    if finisher and g.player.stat("finisher_twice") > 0.0:
        _later(g, 0.1, func(): _start(g, _target(g, g.aim_dir()), g.aim_dir(), style, el, false, true, not back))
    match d.id:
        "thunder_halberd":
            # The thrust soaks; 0.12 s later a sweep shocks.
            _later(g, 0.12, func(): _start(g, _target(g, g.aim_dir()), g.aim_dir(), "sweep", d.alt_element, false, false, not back))
        "twin_fangs":
            # The second blade takes the second-closest foe in reach (or the same one).
            var c := g.player.global_position
            var near := Strike.enemies_in(g.get_tree(), c, trigger_reach(g))
            near.sort_custom(func(a, b): return a.global_position.distance_squared_to(c) < b.global_position.distance_squared_to(c))
            var t2: Enemy = near[1] if near.size() >= 2 else _target(g, dir)
            _start(g, t2, dir, style, d.alt_element, false, false, not back, true)


static func _later(g: Gun, secs: float, f: Callable) -> void:
    g.get_tree().create_timer(secs, false).timeout.connect(func():
        if is_instance_valid(g) and g.is_inside_tree() and is_instance_valid(g.player):
            f.call())


## The enemy this swing goes for: the closest to the player within the trigger reach and
## roughly along `dir` (auto aim already picked the closest; an aimed swing keeps its way).
static func _target(g: Gun, dir: Vector2) -> Enemy:
    var c := g.player.global_position
    var best: Enemy = null
    var bd := INF
    for e in Strike.enemies_in(g.get_tree(), c, trigger_reach(g) + 20.0):
        var to: Vector2 = e.global_position - c
        if to.length() > 1.0 and absf(dir.angle_to(to)) > 0.7:
            continue
        var dd := to.length_squared()
        if dd < bd:
            bd = dd
            best = e
    return best


static func _start(g: Gun, e: Enemy, dir: Vector2, style: String, el: int, full: bool, finisher: bool, back: bool, second := false) -> void:
    var p := g.player
    var d := g.data
    var sw := Swing.new()
    sw.style = style
    sw.el = el
    sw.full = full
    sw.finisher = finisher
    sw.back = back
    sw.second = second
    var s := g.strike(el)
    if not s.crit and p.stat("melee_crit") > 0.0:
        var crit_mult := 2.0 + p.stat("crit_dmg")
        s.crit = true
        s.damage *= crit_mult
        s.potency *= 1.0 + (crit_mult - 1.0) * 0.5
    sw.s = s
    var r := reach(g)
    var piv := p.global_position if full else g.global_position
    var aim := e.global_position if e != null else p.global_position + dir * r * 0.8
    var er := float(e.radius) if e != null else 10.0
    var to := aim - piv
    var dist := to.length()
    sw.dir = to / dist if dist > 1.0 else dir
    sw.extra = int(p.stat("bounce"))
    sw.wave = p.stat("blade_wave") > 0.0
    var size := maxf(0.6, 1.0 + 0.5 * p.stat("shot_size"))
    # Reach is the player's: the blade's tip never goes past `r` (+4) from the player's
    # centre, whichever hover spot it swings from (2026-11-11, Emil: weapons swung way out).
    sw.reach = r + 4.0
    var lim := maxf(16.0, _span(p.global_position, piv, sw.dir, sw.reach))
    if g._emp_now:
        size *= 1.3   # the empowered swing (ProcFx): a visibly broader blade (reach stays the player's)
    match style:
        "slam":
            # The head lands on the target, at most the reach away from the player.
            sw.radius = clampf(dist, 12.0, lim)
            var scale := r / maxf(1.0, d.max_range)
            sw.slam_rad = d.aura_radius * scale * maxf(0.4, 1.0 + p.stat("shot_size"))
        "jab":
            # A short punch into the target, not through the pack behind it.
            sw.radius = clampf(dist + er * 0.5 + 8.0, 16.0, lim)
        _:
            # Thrust, sweep, cleave, lash, spin: out to the full reach.
            sw.radius = lim
    sw.far = sw.radius
    if style != "slam":
        sw.far += (BOUNCE_REACH if sw.extra > 0 else 0.0) + (WAVE_REACH if sw.wave else 0.0)
    sw.half = PI if full else half_arc(g, style)
    sw.blade = float(BLADE.get(style, 6.0)) * size
    var rate := maxf(0.3, g.fire_rate())
    sw.dur = clampf(0.6 / rate, 0.12, 0.26)
    match style:
        "cleave":
            sw.dur = minf(0.32, sw.dur * 1.2)
        "slam":
            sw.dur = clampf(0.7 / rate, 0.2, 0.36)
    if full:
        sw.dur = maxf(sw.dur, 0.3)
    g.swings.append(sw)
    Sfx.play_at("shoot_" + String(Items.ELEMENT_KEYS.get(s.element, "stone")), g.global_position, -10.0)


## How far the blade can go from `piv` along `dir` before its tip leaves the circle of
## radius `rr` around the player at `c` (the hover spot sits inside that circle).
static func _span(c: Vector2, piv: Vector2, dir: Vector2, rr: float) -> float:
    var o := piv - c
    var b := o.dot(dir)
    var disc := b * b - o.length_squared() + rr * rr
    return -b + sqrt(disc) if disc > 0.0 else 0.0


## Where the swing turns: the hover spot, or the player for a full spin.
static func _pivot(g: Gun, sw: Swing) -> Vector2:
    return g.player.global_position if sw.full else g.global_position


static func _sweep_ang(sw: Swing, f: float) -> float:
    if sw.full:
        # Starts behind you and passes the target half way round.
        return (TAU * f - PI) * (-1.0 if sw.back else 1.0)
    var from := -sw.half if not sw.back else sw.half
    var k := clampf((f - 0.1) / 0.8, 0.0, 1.0)
    return lerpf(from, -from, k * k * (3.0 - 2.0 * k))


## The blade at progress `f` (0..1): [base, tip, can hit] in world space.
static func blade(g: Gun, sw: Swing, f: float) -> Array:
    var piv := _pivot(g, sw)
    if not sw.full:
        match sw.style:
            "thrust", "jab":
                var ext := 0.0
                if f < 0.4:
                    var k := f / 0.4
                    ext = 1.0 - (1.0 - k) * (1.0 - k)
                elif f < 0.6:
                    ext = 1.0
                else:
                    ext = 1.0 - (f - 0.6) / 0.4
                var tip := piv + sw.dir * ext * sw.radius
                var length := 16.0 if sw.style == "jab" else 28.0
                return [piv + sw.dir * maxf(0.0, ext * sw.radius - length), tip, f < 0.6]
            "slam":
                var k := 0.0
                if f < 0.55:
                    k = f / 0.55
                    k = k * k
                elif f < 0.75:
                    k = 1.0
                else:
                    k = 1.0 - (f - 0.75) / 0.25
                var lift := -22.0 * sin(clampf(f / 0.55, 0.0, 1.0) * PI)
                var head := piv + sw.dir * sw.radius * k + Vector2(0.0, lift)
                return [head - sw.dir * 10.0, head, false]
    var ext := 1.0
    if f < 0.12:
        ext = lerpf(0.45, 1.0, f / 0.12)
    elif f > 0.88:
        ext = lerpf(1.0, 0.4, (f - 0.88) / 0.12)
    var u := Vector2.from_angle(sw.dir.angle() + _sweep_ang(sw, f))
    var length := sw.radius * ext
    if not sw.full:
        # Swung from a hover spot, the arc is trimmed to the player's reach circle.
        length = minf(length, maxf(12.0, _span(g.player.global_position, piv, u, sw.reach)))
    return [piv + u * 8.0, piv + u * length, f >= 0.08 and f <= 0.92]


## Moves every live swing on; called from Gun._process for melee weapons.
static func tick(g: Gun, delta: float) -> void:
    if g.swings.is_empty():
        return
    if not is_instance_valid(g.player) or not g.is_inside_tree():
        g.swings.clear()
        return
    var i := 0
    while i < g.swings.size():
        var sw: Swing = g.swings[i]
        if sw.hold > 0.0:
            sw.hold -= delta
            i += 1
            continue
        var f0 := sw.t / sw.dur
        sw.t += delta
        var f1 := minf(1.0, sw.t / sw.dur)
        _contacts(g, sw, f0, f1)
        if f1 >= 1.0:
            _finish(g, sw)
            g.swings.remove_at(i)
            continue
        i += 1


## Tests the blade along its path from f0 to f1 (a segment against enemy circles, in steps
## of about 10 px at the tip so a fast blade cannot skip a foe).
static func _contacts(g: Gun, sw: Swing, f0: float, f1: float) -> void:
    var piv := _pivot(g, sw)
    if sw.style == "slam" and not sw.full:
        if not sw.landed and f1 >= 0.55:
            sw.landed = true
            _slam(g, sw, piv + sw.dir * sw.radius)
        return
    if sw.n >= MAX_HITS:
        return
    var b0: Array = blade(g, sw, f0)
    var b1: Array = blade(g, sw, f1)
    if not b0[2] and not b1[2]:
        return
    var steps := clampi(int(ceil((b1[1] as Vector2).distance_to(b0[1]) / 10.0)), 1, 12)
    var near := Strike.enemies_in(g.get_tree(), piv, sw.far + 48.0)
    var parry := g.data.id == "parry_blade" or g.data.legend == "mirror"
    for k in range(1, steps + 1):
        var bk: Array = blade(g, sw, lerpf(f0, f1, float(k) / float(steps)))
        if not bk[2]:
            continue
        var a: Vector2 = bk[0]
        var b: Vector2 = bk[1]
        if sw.far > sw.radius and b.distance_to(a) > 0.5:
            # Bounce points and the Blade wave reach past the drawn blade, unseen.
            b += (b - a).normalized() * (sw.far - sw.radius)
        for e in near:
            if sw.n >= MAX_HITS:
                return
            if not is_instance_valid(e) or e.is_queued_for_deletion():
                continue
            var id: int = e.get_instance_id()
            if sw.done.has(id):
                continue
            var q := Geometry2D.get_closest_point_to_segment(e.global_position, a, b)
            if q.distance_to(e.global_position) <= float(e.radius) + sw.blade:
                sw.done[id] = true
                _contact(g, sw, e, q, piv)
        if parry:
            _parry(g, a, b)


## The slam's head comes down: everything under it, closest first, at most MAX_HITS.
static func _slam(g: Gun, sw: Swing, centre: Vector2) -> void:
    var found := Strike.enemies_in(g.get_tree(), centre, sw.slam_rad)
    found.sort_custom(func(a, b): return a.global_position.distance_squared_to(centre) < b.global_position.distance_squared_to(centre))
    for e in found:
        if sw.n >= MAX_HITS:
            break
        sw.done[e.get_instance_id()] = true
        _contact(g, sw, e, e.global_position, centre)
    GunFx.smear(Strike.world_parent(g), centre, sw.dir, sw.slam_rad, sw.half, sw.s.color, sw.back, "slam")
    if sw.finisher and g.data.weight >= 5:
        g.player.kick(sw.dir, 3.0)


## One enemy touched by the blade at `q`.
static func _contact(g: Gun, sw: Swing, e: Enemy, q: Vector2, piv: Vector2) -> void:
    var p := g.player
    var d := g.data
    var s := sw.s
    var dist := q.distance_to(piv)
    var mult := 1.0
    if sw.style != "slam" and dist > sw.radius + 2.0:
        # Past the reach: a bounce point takes one, the Blade wave takes the rest at half.
        if sw.past < sw.extra:
            sw.past += 1
        elif sw.wave:
            mult = 0.5
        else:
            return
    var i := sw.n
    sw.n += 1
    if i > 0:
        mult *= FOLLOW
    var tip := sw.style == "lash" and dist >= sw.radius * TIP_FROM
    if tip:
        mult *= TIP_MULT
    if sw.finisher:
        mult *= FINISHER_MULT
    match d.id:
        "ember_brand":
            if i == 0:
                mult *= 2.0
        "pitch_cleaver":
            if e.burn_time > 0.0:
                mult *= 1.4
        "rimefang":
            if e.frozen_time > 0.0:
                mult *= 2.0
                e.frozen_time = minf(e.frozen_time, 0.05)   # shattered
    if e.frozen_time > 0.0:
        mult *= 1.0 + p.stat("melee_vs_frozen")
    if e.burn_time > 0.0:
        mult *= 1.0 + p.stat("melee_vs_burning")
    var away := e.global_position - piv
    away = away.normalized() if away.length() > 0.5 else sw.dir
    var kb := d.knockback
    if sw.full and d.id == "gale_glaive":
        kb = 220.0
    var knock := away * kb * (1.0 + p.stat("melee_knock"))
    if sw.full and d.id == "hollow_sickle":
        knock = -away * 160.0   # drags them into the blade
    if tip and d.id == "riptide_whip":
        knock = -away * 280.0
    s.hit(e, mult, q, knock)
    sw.any = true
    if i == 0:
        sw.hold = HOLD
    var fx := Strike.fx_of(g)
    if fx != null:
        fx.puff(Art.PARTICLES["light"], q, Color(s.color.lightened(0.45), 0.7), SPARK_PX * (1.4 if sw.finisher or tip else 1.0), 0.08, true)
    if not is_instance_valid(e) or e.is_queued_for_deletion() or e.hp <= 0.0:
        Progress.add("kills_melee")
        return
    if sw.style == "slam" and not e.is_elite and e.kind_name != "boss":
        e.stun(STAGGER)
    if i > 0 and p.stat("cleave_bleed") > 0.0:
        e.add_bleed(s.damage * 0.15 * p.stat("cleave_bleed"), 3.0)
    _rule_on_hit(g, s, e, tip, sw.finisher, mult)


## Parry Blade: the blade cuts enemy shots it passes through.
static func _parry(g: Gun, a: Vector2, b: Vector2) -> void:
    var cut := 0
    for sh in g.get_tree().get_nodes_in_group("enemy_projectiles"):
        if not is_instance_valid(sh) or sh.is_queued_for_deletion():
            continue
        if Geometry2D.get_closest_point_to_segment(sh.global_position, a, b).distance_to(sh.global_position) <= 12.0:
            if g.data.legend == "mirror":
                Legendary.mirror(g, sh)
            sh.queue_free()
            cut += 1
    if cut > 0:
        Progress.add("shots_cut", cut)


## The swing is over: the weapon's own after-rules, and the world it passed through.
static func _finish(g: Gun, sw: Swing) -> void:
    var p := g.player
    var piv := _pivot(g, sw)
    var tree := g.get_tree()
    var centre := piv + sw.dir * sw.radius if sw.style == "slam" else piv + sw.dir * sw.radius * 0.6
    match g.data.id:
        "magma_maul":
            if sw.any:
                Cloud.spawn(Strike.world_parent(g), piv + sw.dir * sw.radius, Element.Kind.FIRE, 50.0, 3.0, maxf(3.0, sw.s.potency * 0.3), p)
        "the_long_coil":
            # The Long Coil leaves venom along the lash.
            if sw.any:
                Cloud.spawn(Strike.world_parent(g), piv + sw.dir * sw.radius * 0.6, Element.Kind.POISON, 45.0, 3.0, maxf(3.0, sw.s.potency * 0.4), p)
                Legendary.note("coil")
        "venom_pike":
            if sw.any:
                Cloud.spawn(Strike.world_parent(g), piv + sw.dir * sw.radius * 0.55, Element.Kind.POISON, 40.0, 2.0, maxf(3.0, sw.s.potency * 0.3), p)
    sw.s.touch_world(tree, centre, sw.radius * 0.45, sw.dir)
    sw.s.touch_clouds(tree, centre, sw.radius * 0.45, {})


## The held weapon's pose during its newest swing: [local position, facing] (Gun._process).
static func pose(g: Gun) -> Array:
    for k in range(g.swings.size() - 1, -1, -1):
        var sw: Swing = g.swings[k]
        if sw.second:
            continue
        return pose_of(g, sw)
    return []


static func pose_of(g: Gun, sw: Swing) -> Array:
    var bl: Array = blade(g, sw, minf(1.0, sw.t / sw.dur))
    var a: Vector2 = bl[0]
    var b: Vector2 = bl[1]
    var u := (b - a).normalized() if b.distance_to(a) > 0.5 else sw.dir
    if sw.style == "slam" and not sw.full:
        u = sw.dir
    return [g.to_local(b - u * 9.0), u]


static func _rule_on_hit(g: Gun, s: Strike, e: Enemy, tip: bool, finisher: bool, mult: float) -> void:
    var p := g.player
    match g.data.id:
        "thorn_whip":
            if tip:
                e.apply_element(Element.Kind.POISON, s.potency * mult, p)   # the tip poisons twice
        "etching_claws":
            e.corrode(2.0)
            if finisher:
                Items._do({ "do": "spread", "element": "acid", "radius": 60.0, "potency": s.potency * 0.6 }, p, { "pos": e.global_position, "target": e })
        "blood_rapier":
            if e.bleed_time > 0.0 or e.has_state(Element.Kind.BLOOD):
                s.hit(e, 0.5 * mult, e.global_position)
        "sanctified_mace":
            e.marked_t = maxf(e.marked_t, 4.0)
        "storm_lash":
            if tip:
                var other := Strike.nearest(g.get_tree(), e.global_position, 150.0, { e: true })
                if other != null:
                    s.hit(other, 0.6, other.global_position)
                    var fx := Strike.fx_of(g)
                    if fx != null:
                        g._arc_fx(e.global_position, other.global_position, s.color, s.element)
        "crimson_gauntlets":
            if finisher and e.bleed_time > 0.0 and e.bleed_dps > 0.0:
                var burst := e.bleed_dps * e.bleed_time
                e.bleed_time = 0.0
                Strike.deal(e, burst, 0.0, Element.Kind.NONE, [], s.color, false, p, g.data.id, e.global_position)


