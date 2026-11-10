class_name Melee
extends RefCounted
## Melee swings (Arsenal expansion 2.3). A melee weapon is still a Gun; Gun._fire_melee
## calls `swing` once per swing (+1 projectile is one more swing, back and forth). It
## swings only when an enemy is within reach (Player.gun_dir), takes no Focus slot, and
## hits everything in its shape: the first enemy at 100%, every other at 75%, at most
## MAX_HITS a swing, closest first. One shape query per swing; nothing runs while idle.
##
## Styles (GunData.style):
##   sweep   the plain arc in front of you
##   cleave  wide (200 deg) and slow, big knockback
##   thrust  a long, narrow line that pierces everything in it
##   slam    a circle at a point ahead; staggers ordinary enemies for 0.3 s
##   lash    long reach; the outer 30% (the tip) hits for x1.5
##   jab     fast; every 4th is a finisher at x2.5
##   spin    sweeps, and every 3rd swing is a full circle around you
##
## Stats (2.2): fire rate and half the shot speed make swings faster; +1 projectile is +1
## swing; each pierce is +10% reach; range adds half its bonus as reach; shot size widens
## the arc by 5 deg per 10%; each bounce lets the swing reach 1 more enemy just past its
## reach. Item stats: melee_dmg, reach, swing_speed, arc (deg), whirl (every 5th swing is a
## full spin), finisher_twice, cleave_bleed, melee_crit (buff: swings crit), blade_wave
## (the Blade resonance at 5: a short wave past the reach).

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


## One swing toward `dir`. `back` mirrors the smear (the return stroke of a +1 swing).
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
    _resolve(g, dir, style, el, full, finisher, back)
    if finisher and g.player.stat("finisher_twice") > 0.0:
        _later(g, 0.1, func(): _resolve(g, g.aim_dir(), style, el, false, true, not back))
    match d.id:
        "thunder_halberd":
            # The thrust soaks; 0.12 s later a sweep shocks.
            _later(g, 0.12, func(): _resolve(g, g.aim_dir(), "sweep", d.alt_element, false, false, not back))
        "twin_fangs":
            # The second blade takes the second-closest foe in reach (or the same one).
            var c := g.player.global_position
            var r := reach(g)
            var near := Strike.enemies_in(g.get_tree(), c, r)
            near.sort_custom(func(a, b): return a.global_position.distance_squared_to(c) < b.global_position.distance_squared_to(c))
            var d2 := dir
            if near.size() >= 2:
                d2 = (near[1].global_position - c).normalized()
            _resolve(g, d2, style, d.alt_element, false, false, not back)


static func _later(g: Gun, secs: float, f: Callable) -> void:
    g.get_tree().create_timer(secs, false).timeout.connect(func():
        if is_instance_valid(g) and g.is_inside_tree() and is_instance_valid(g.player):
            f.call())


## One shape: find, sort, cap, hit, then the weapon's rule and the smear.
static func _resolve(g: Gun, dir: Vector2, style: String, el: int, full: bool, finisher: bool, back: bool) -> void:
    var d := g.data
    var p := g.player
    var tree := g.get_tree()
    var c := p.global_position
    var r := reach(g)
    var half := PI if full else half_arc(g, style)
    var s := g.strike(el)
    if not s.crit and p.stat("melee_crit") > 0.0:
        var crit_mult := 2.0 + p.stat("crit_dmg")
        s.crit = true
        s.damage *= crit_mult
        s.potency *= 1.0 + (crit_mult - 1.0) * 0.5
    var centre := c
    var found: Array
    var extra := int(p.stat("bounce"))
    var wave := p.stat("blade_wave") > 0.0
    var far := r + BOUNCE_REACH * float(mini(extra, 1)) + (WAVE_REACH if wave else 0.0)
    if style == "slam":
        var scale := r / maxf(1.0, d.max_range)
        centre = c + dir * r
        var rad := d.aura_radius * scale * maxf(0.4, 1.0 + p.stat("shot_size"))
        found = Strike.enemies_in(tree, centre, rad)
        far = 0.0
    elif full:
        found = Strike.enemies_in(tree, c, far)
    else:
        found = Strike.enemies_in_cone(tree, c, dir, far, half)
    found.sort_custom(func(a, b): return a.global_position.distance_squared_to(centre) < b.global_position.distance_squared_to(centre))
    var hits: Array = []
    var past := 0
    for e in found:
        if hits.size() >= MAX_HITS:
            break
        if style != "slam" and e.global_position.distance_to(c) > r + float(e.radius) * 0.5:
            # Past the reach: a bounce point takes one, the Blade wave takes the rest at half.
            if past < extra:
                past += 1
                hits.append([e, 1.0])
            elif wave:
                hits.append([e, 0.5])
            continue
        hits.append([e, 1.0])
    var kb := d.knockback
    if full and d.id == "gale_glaive":
        kb = 220.0
    var hit_any := false
    for i in hits.size():
        var e: Enemy = hits[i][0]
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        var mult: float = float(hits[i][1]) * (1.0 if i == 0 else FOLLOW)
        var dist := e.global_position.distance_to(c)
        var tip := style == "lash" and dist >= r * TIP_FROM
        if tip:
            mult *= TIP_MULT
        if finisher:
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
        var away := (e.global_position - c).normalized()
        var knock := away * kb * (1.0 + p.stat("melee_knock"))
        if full and d.id == "hollow_sickle":
            knock = -away * 160.0   # drags them into the blade
        if tip and d.id == "riptide_whip":
            knock = -away * 280.0
        s.hit(e, mult, e.global_position, knock)
        hit_any = true
        if not is_instance_valid(e) or e.is_queued_for_deletion() or e.hp <= 0.0:
            Progress.add("kills_melee")
            continue
        if style == "slam" and not e.is_elite and e.kind_name != "boss":
            e.stun(STAGGER)
        if i > 0 and p.stat("cleave_bleed") > 0.0:
            e.add_bleed(s.damage * 0.15 * p.stat("cleave_bleed"), 3.0)
        _rule_on_hit(g, s, e, tip, finisher, mult)
    _rule_on_swing(g, s, dir, c, centre, r, half, hit_any)
    s.touch_world(tree, centre if style == "slam" else c + dir * r * 0.6, r * 0.45, dir)
    s.touch_clouds(tree, centre if style == "slam" else c + dir * r * 0.6, r * 0.45, {})
    var shape := "spin" if full else style
    var size := r
    if style == "slam":
        size = d.aura_radius * (r / maxf(1.0, d.max_range))
    GunFx.smear(Strike.world_parent(g), c if style != "slam" else centre, dir, size, half, s.color, back, shape)
    Sfx.play_at("shoot_" + String(Items.ELEMENT_KEYS.get(s.element, "stone")), c, -10.0)
    if finisher and d.weight >= 5:
        p.kick(dir, 3.0)


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


static func _rule_on_swing(g: Gun, s: Strike, dir: Vector2, c: Vector2, centre: Vector2, r: float, half: float, hit_any: bool) -> void:
    var p := g.player
    match g.data.id:
        "parry_blade":
            # Cut enemy shots inside the arc out of the air.
            var cut := 0
            for b in g.get_tree().get_nodes_in_group("enemy_projectiles"):
                if not is_instance_valid(b) or b.is_queued_for_deletion():
                    continue
                var to: Vector2 = b.global_position - c
                if to.length() <= r and absf(dir.angle_to(to)) <= half:
                    b.queue_free()
                    cut += 1
            if cut > 0:
                Progress.add("shots_cut", cut)
        "magma_maul":
            if hit_any:
                Cloud.spawn(Strike.world_parent(g), centre, Element.Kind.FIRE, 50.0, 3.0, maxf(3.0, s.potency * 0.3), p)
        "venom_pike":
            if hit_any:
                Cloud.spawn(Strike.world_parent(g), c + dir * r * 0.55, Element.Kind.POISON, 40.0, 2.0, maxf(3.0, s.potency * 0.3), p)
