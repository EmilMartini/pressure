class_name Gun
extends Node2D
## One carried gun, drawn orbiting the player and pointing at whatever it last shot.
## Tiers I to IV raise its numbers (merge a duplicate or visit the gunsmith), and a gun
## holds as many mods as its tier; mod effects stack, which is the point.
##
## How a trigger pull works depends on the archetype's mechanic (GunData.ARCHETYPES):
##   shot    projectiles (Projectile), flying by data.behaviour
##   beam    a continuous ray (Beam) that ticks fire_rate times a second and sweeps to the aim
##   cone    a short spray (Spray) that hits everything in its cone each tick
##   chain   an instant arc to the target that jumps to the nearest enemies after it
##   nova    a ring around the player
##   melee   a sweep in front of the gun
##   charge  winds up for charge_time (aim tracked), then a rail through the whole line
##   mine    tosses a Mine a short way toward the target
##   turret  deploys a Turret that fires this gun's shots on its own
##   summon  keeps Summon bodies up (drones, familiars, orbits, swarms, the golem); the
##           weapon itself never fires, its bodies pick their own targets (Summon)
## Every hit goes through Strike (one hit path, attributed to this gun in Telemetry).
## Auto-fire (Player._fire) only ever passes an enemy direction; RT passes the aim.

const MAX_TIER := 4
const TIER_NAMES := ["", " II", " III", " IV"]
## On-screen size of the orbiting gun icon at tier I (a 32 px tile resampled down).
const ICON_PX := 22
const CHAIN_JUMP_RANGE := 150.0
const MINE_CAP := 6          # live mines per gun; the oldest pops when a seventh lands
const TURRET_CAP := 1        # live turrets per gun (+1 per extra projectile)

var data: GunData
var player: Player
var cooldown := 0.0
var tier := 1
var mods: Array = []   # item ids of the gun mods fitted to this gun
## Second elements from the Coating rare pick (LevelUps.rare_pick), applied with every hit.
var boon_elements: Array = []

var _sprite: Sprite2D
var _aim := Vector2.RIGHT
var _recoil := 0.0
var _burst_left := 0      # burst shots still queued from the last trigger
var _burst_timer := 0.0
var _alt_flip := false    # alternating-element guns flip this per projectile
var _upright := false     # flask and orb icons stand upright instead of pointing
var _spin := 0.0          # repeater: seconds of continuous fire
var _since_fire := 99.0   # seconds since the last trigger
var _charging := false    # charge: winding up
var _charge := 0.0        # charge: seconds wound
var _beams: Array = []    # beam: one Beam per ray
var _spray: Spray = null
var _mines: Array = []
var _turrets: Array = []
var bodies: Array = []    # summon: live Summon bodies (Summon.maintain)
var summon_room := 0      # summon: the room the bodies live in
var summon_t := 0.0       # summon: seconds until the next body may be made
var grown := 0            # summon: bodies grown this room (Hive Queen's wasps)
var orbit_t := 0.0        # summon: game seconds, the orbits' clock
var split_at := -99.0     # summon: when Acid Slime last split
var _target_k := 0        # homing: rotates which enemy each volley's first seeker takes
var melee_n := 0          # melee: swings so far (finishers, spins)
var swing_tilt := 0.0     # melee: 1 at a swing, the held weapon tilts back and returns
var _ready_t := 0.0       # melee: the ready pose re-aims every READY_EVERY s
var swings: Array = []    # melee: live Melee.Swing, each travelling its path (A9)
var _trail_on := false    # melee: drew a trail last frame (one more redraw clears it)
var _mag := 0             # revolver: shots fired from the current magazine
var _reload := 0.0        # revolver: seconds of reload left (drawn as a ring)
const READY_EVERY := 0.15
## Focus targeting (Focus.update): ranked targets; shot or beam k goes to targets[k], extras
## doubling up on targets[0]. Empty outside auto aim.
var targets: Array = []


func _init(p_data: GunData, p_player: Player) -> void:
    data = p_data
    player = p_player
    name = data.id


func _ready() -> void:
    z_index = 1
    _upright = Art.gun_icon_upright(data.id)
    _sprite = Art.icon_sprite(Art.icon_sized(Art.gun_icon(data.id), ICON_PX), 1.0)
    add_child(_sprite)


func _exit_tree() -> void:
    for b in _beams:
        if is_instance_valid(b):
            b.queue_free()
    _beams.clear()
    if _spray != null and is_instance_valid(_spray):
        _spray.queue_free()
    _spray = null
    for t in _turrets:
        if is_instance_valid(t):
            t.queue_free()
    _turrets.clear()
    for b in bodies:
        if is_instance_valid(b):
            b.queue_free()
    bodies.clear()


func _process(delta: float) -> void:
    cooldown = maxf(0.0, cooldown - delta)
    _recoil = move_toward(_recoil, 0.0, 45.0 * delta)
    _since_fire += delta
    if data.spin_up > 0.0:
        # Spinning up while the trigger keeps coming, winding down twice as fast after.
        if _since_fire < 0.35 + 1.0 / maxf(0.1, data.fire_rate):
            _spin = minf(data.spin_up, _spin + delta)
        else:
            _spin = maxf(0.0, _spin - 2.0 * delta)
    if _charging:
        _tick_charge(delta)
    if _burst_left > 0:
        _burst_timer -= delta
        if _burst_timer <= 0.0:
            _burst_left -= 1
            _burst_timer = data.burst_gap
            # Each burst shot re-aims: where you aim now, else whatever is nearest.
            if is_instance_valid(player):
                var bd := player.gun_dir(self)
                if bd != Vector2.ZERO:
                    _aim = bd
            _shoot(_aim)
    if data.mechanic == "summon":
        Summon.maintain(self, delta)
    elif data.mechanic == "ground":
        GroundZone.maintain(self, delta)
    var face := _aim
    var pose: Array = []
    if data.family == "melee":
        swing_tilt = maxf(0.0, swing_tilt - delta / 0.12)
        Melee.tick(self, delta)
        pose = Melee.pose(self)
        _ready_t -= delta
        if swings.is_empty() and _ready_t <= 0.0 and _since_fire > 0.3 and is_instance_valid(player):
            # The ready pose (2.1): with nothing in reach the weapon faces the closest enemy.
            _ready_t = READY_EVERY
            var near := player.nearest_enemy(500.0)
            if near != null:
                _aim = (near.global_position - global_position).normalized()
    if not pose.is_empty():
        # Mid-swing the weapon is out on its path (A9), its business end leading.
        _sprite.position = pose[0]
        face = pose[1]
    else:
        _sprite.position = -_aim * _recoil
    var left := face.x < 0.0
    _sprite.flip_h = left
    if _upright:
        _sprite.rotation = 0.0
    else:
        # The tiles lie diagonally with the business end up and to the right (-45 degrees);
        # mirrored for a left aim it points up-left (-135 degrees). Turn that end to the aim.
        _sprite.rotation = face.angle() + (PI * 0.75 if left else PI * 0.25)
        if swing_tilt > 0.0 and pose.is_empty():
            # A swing tilts back over the first 0.05 s, then follows through.
            var back := sin(swing_tilt * PI) * 0.7
            _sprite.rotation += -back if not left else back
    _sprite.scale = Vector2.ONE * (1.0 + 0.08 * float(tier - 1)) * (1.15 if not pose.is_empty() else 1.0)
    if _reload > 0.0:
        _reload = maxf(0.0, _reload - delta)
    if _charging or data.spin_up > 0.0 or data.magazine > 0 or not swings.is_empty() or _trail_on:
        _trail_on = not swings.is_empty()
        queue_redraw()


func _draw() -> void:
    if not swings.is_empty():
        _draw_swings()
    # Charge: a glow gathering at the muzzle. Repeater: a ring that fills as it spins up.
    if _charging and data.charge_time > 0.0:
        var f := clampf(_charge / _charge_needed(), 0.0, 1.0)
        var c := data.color()
        var tip := _aim * 12.0
        draw_circle(tip, 2.0 + 6.0 * f, Color(c, 0.25 + 0.35 * f))
        draw_circle(tip, 1.0 + 2.5 * f, Color(1, 1, 1, 0.5 + 0.5 * f))
        if f >= 1.0:
            draw_arc(tip, 10.0, 0.0, TAU, 16, Color(c, 0.8), 1.5)
    elif data.spin_up > 0.0 and _spin > 0.05:
        var s := clampf(_spin / data.spin_up, 0.0, 1.0)
        draw_arc(Vector2.ZERO, 13.0, -PI * 0.5, -PI * 0.5 + TAU * s, 18, Color(data.color(), 0.55), 1.5)
    elif data.magazine > 0 and _reload > 0.0:
        # Revolver: a thin ring fills while it reloads.
        var rl := 1.0 - clampf(_reload / maxf(0.05, data.reload_time), 0.0, 1.0)
        draw_arc(Vector2.ZERO, 13.0, -PI * 0.5, -PI * 0.5 + TAU * rl, 18, Color(0.85, 0.85, 0.9, 0.5), 1.5)


## Melee: a faint trail along the path each live swing has travelled (under hostile
## clarity: own-effects alpha, no additive), and Twin Fangs' second blade.
func _draw_swings() -> void:
    var a := WeaponLooks.SMEAR_ALPHA * Settings.own_fx()
    var col := data.color()
    for sw in swings:
        var f := minf(1.0, sw.t / sw.dur)
        var piv := to_local(Melee._pivot(self, sw))
        if sw.style in ["thrust", "jab"] and not sw.full:
            var bl: Array = Melee.blade(self, sw, f)
            draw_line(piv, to_local(bl[1]), Color(col, a), 3.0)
        elif sw.style != "slam" or sw.full:
            var f0 := maxf(0.08, f - 0.35)
            if f - f0 > 0.01:
                # The trail follows the blade's tip, which the player's reach trims.
                var w := clampf(sw.radius * 0.18, 4.0, 14.0)
                var pts := PackedVector2Array()
                for k in 12:
                    var bk: Array = Melee.blade(self, sw, lerpf(f0, f, float(k) / 11.0))
                    var tip: Vector2 = bk[1]
                    pts.append(to_local(tip - (tip - (bk[0] as Vector2)).normalized() * w * 0.5))
                draw_polyline(pts, Color(col, a * (1.0 - f * 0.5)), w)
        if sw.second:
            var ps: Array = Melee.pose_of(self, sw)
            var u: Vector2 = ps[1]
            draw_set_transform(ps[0], u.angle() + PI * 0.25, Vector2.ONE * 1.15)
            var tex := _sprite.texture
            draw_texture(tex, -tex.get_size() * 0.5)
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func display_name() -> String:
    return data.display_name + TIER_NAMES[tier - 1]


func can_fire() -> bool:
    return cooldown <= 0.0 and not _charging


## Summed mod value across every mod fitted to this gun.
func _gm(key: String) -> float:
    var v := 0.0
    for id in mods:
        v += float(Items.get_item(id).get("mods", {}).get(key, 0.0))
    return v


## Every extra element the fitted coatings add to each hit.
func extra_elements() -> Array:
    var out: Array = []
    for id in mods:
        var ex: String = Items.get_item(id).get("mods", {}).get("extra_element", "")
        if ex != "" and Items.ELEMENTS.has(ex):
            out.append(Items.ELEMENTS[ex])
    if data.extra_element != Element.Kind.NONE:
        out.append(data.extra_element)
    out.append_array(boon_elements)
    # Overheat (after a vent) and Second Nature (the first gun): your vent element rides along.
    if player != null and is_instance_valid(player):
        if player.stat("vent_shots") > 0.0 or (player.stat("second_nature") > 0.0 and not player.guns.is_empty() and player.guns[0] == self):
            var ve: int = Items.vent_element(player)
            if ve != data.element and not out.has(ve):
                out.append(ve)
    return out


func element_key() -> String:
    return Items.ELEMENT_KEYS.get(data.element, "none")


func tier_mult() -> float:
    return 1.0 + 0.35 * float(tier - 1)


func effective_range() -> float:
    if data.family == "melee":
        return Melee.trigger_reach(self)
    return data.max_range * (1.0 + player.stat("range") + _gm("g_range"))


## The way the weapon points now (melee follow-ups re-aim with it).
func aim_dir() -> Vector2:
    return _aim


func fire_rate() -> float:
    var ek := element_key()
    var spin := 1.0
    if data.spin_up > 0.0:
        spin = lerpf(GunData.SPIN_FLOOR, 1.0, clampf(_spin / data.spin_up, 0.0, 1.0))
    var fam := 0.0
    if data.family == "thrown":
        fam = player.stat("throw_rate")
    if data.family == "summon":
        fam = player.stat("summon_rate")
    if data.family == "melee":
        # Swing speed (2.2): its own stat plus half the shot speed.
        fam = player.stat("swing_speed") + 0.5 * (player.stat("proj_speed") + player.stat("shot_speed") + _gm("g_speed"))
    return data.fire_rate * spin * (1.0 + 0.12 * float(tier - 1)) * maxf(0.2, 1.0 + player.stat("fire_rate") + player.stat("fire_rate_" + ek) + _gm("g_fire_rate") + fam)


## Rate at full spin (what the cards show for repeaters).
func top_fire_rate() -> float:
    var keep := _spin
    _spin = data.spin_up
    var r := fire_rate()
    _spin = keep
    return r


## Shots, beams, arcs, rings, sweeps, rails, mines or flasks per trigger: projectile_count
## plus the projectile stat and mods.
func shot_count() -> int:
    var n := data.projectile_count + int(player.stat("proj_count")) + int(_gm("g_count"))
    if not player.guns.is_empty() and player.guns[0] == self:
        n += int(player.stat("first_gun_count"))   # Gunslinger resonance
    if data.mechanic == "beam":
        n += int(player.stat("fork"))   # Fork: a beam reaches one more enemy
    return maxi(1, n)


func shot_pierce() -> int:
    var ek := element_key()
    return data.pierce + int(player.stat("pierce")) + int(player.stat("pierce_" + ek)) + int(_gm("g_pierce")) + (1 if tier >= 3 else 0)


func speed_mult() -> float:
    return maxf(0.3, 1.0 + player.stat("proj_speed") + player.stat("shot_speed") + _gm("g_speed"))


## Bigger with tier and the shot-size gear.
func size_mult() -> float:
    return maxf(0.3, 1.0 + player.stat("shot_size")) * (1.0 + 0.1 * float(tier - 1))


## The numbers one trigger pull hits with: tier, gear and mods applied, crit rolled.
## `el` overrides the element (alternating guns).
func strike(el: int = -1) -> Strike:
    var ek := element_key()
    var s := Strike.new()
    s.element = data.element if el < 0 else el
    var fam_dmg := 0.0
    match data.family:
        "melee":
            fam_dmg = player.stat("melee_dmg")
        "gun":
            fam_dmg = player.stat("gun_dmg")
        "thrown":
            fam_dmg = player.stat("thrown_dmg")
        "summon":
            fam_dmg = player.stat("summon_dmg")
        "ground":
            fam_dmg = player.stat("ground_dmg")
    s.damage = data.damage * tier_mult() * maxf(0.1, 1.0 + player.stat("dmg") + player.stat("dmg_" + ek) + _gm("g_dmg") + fam_dmg)
    s.potency = s.damage * data.reaction_mult * (1.0 + potency_bonus(player.stat("potency") + player.stat("potency_" + ek)))
    s.crit = randf() < player.stat("crit")
    if s.crit:
        var crit_mult := 2.0 + player.stat("crit_dmg")
        s.damage *= crit_mult
        s.potency *= 1.0 + (crit_mult - 1.0) * 0.5
    s.damage *= 1.0 + 0.5 * (maxf(0.3, 1.0 + player.stat("shot_size")) - 1.0)
    if data.archetype == "hymn" and player.max_hp > 0.0:
        # Blood Hymn: up to triple damage as your health falls.
        s.damage *= 1.0 + 2.0 * (1.0 - clampf(player.hp / player.max_hp, 0.0, 1.0))
    s.extras = extra_elements()
    s.color = Element.COLORS[s.element]
    s.shooter = player
    s.gun_id = data.id
    return s


## Stacked reaction power with diminishing returns (Core loop reset 9): in full up to +50%,
## at half from +50% to +150%, at a quarter beyond (+100% is +75%, +250% is +125%).
static func potency_bonus(raw: float) -> float:
    if Main.old_balance or raw <= 0.5:
        return raw
    if raw <= 1.5:
        return 0.5 + 0.5 * (raw - 0.5)
    return 1.0 + 0.25 * (raw - 1.5)


## The element of the next projectile, flipping alternating guns.
func _next_element() -> int:
    if data.alt_element == Element.Kind.NONE:
        return data.element
    _alt_flip = not _alt_flip
    return data.alt_element if _alt_flip else data.element


## One trigger pull toward `dir`. Mechanics that hit at once do it here; projectile guns
## spawn their volley (the rest of a burst follows in _process). The cooldown covers a
## whole burst, so fire_rate stays triggers per second.
func fire(dir: Vector2) -> void:
    _aim = dir
    _since_fire = 0.0
    var rate := fire_rate()
    cooldown = 1.0 / rate
    var kick := 1.0 + float(data.weight) * 0.5
    match data.mechanic:
        "beam":
            _fire_beam(dir)
            kick = 0.25
        "cone":
            _fire_cone(dir)
            kick = 0.3
        "chain":
            _fire_chain(dir)
        "nova":
            _fire_nova()
            kick = 0.0
        "melee":
            _fire_melee(dir)
            kick = -2.0   # a lunge into the swing
        "charge":
            # Wind up now; the rail leaves from _tick_charge.
            _charging = true
            _charge = 0.0
            Sfx.play_at("shoot_" + Items.ELEMENT_KEYS.get(data.element, "stone"), global_position, -10.0)
            return
        "mine":
            _fire_mine(dir)
        "summon", "ground":
            cooldown = 0.5   # the bodies or zones fight on their own (Summon, GroundZone)
            return
        "turret":
            if player.alive and player._aim_firing:
                _shoot(dir)   # aimed: the gun fires too (doors, props), the turret keeps to enemies
            if not _fire_turret(dir):
                cooldown = 0.25   # a turret is already up: nothing to do
                return
        _:
            var burst := maxi(1, data.burst_count)
            cooldown = maxf(1.0 / rate, data.burst_gap * float(burst - 1) + 0.05)
            _burst_left = burst - 1
            _burst_timer = data.burst_gap
            if data.id == "ember_scattergun" and player.nearest_enemy(90.0) != null:
                _burst_left += 1   # point blank: a second blast
                _burst_timer = 0.09
            _shoot(dir)
            if data.magazine > 0:
                # Revolver: the magazine empties, then a slow reload.
                _mag += 1
                if _mag >= data.magazine:
                    _mag = 0
                    _reload = data.reload_time * data.fire_rate / maxf(0.05, rate)
                    cooldown = maxf(cooldown, _reload)
    _recoil = 5.0 + float(data.weight) if kick > 0.5 else 2.0
    player.add_pressure(data.pressure_per_shot * (1.0 + _gm("g_pressure")))
    if kick != 0.0:
        player.kick(dir, kick)


## Spawns one volley (shot_count projectiles) toward `dir` from the gun.
func _shoot(dir: Vector2) -> void:
    shoot_from(global_position + dir * 14.0, dir, player.focusing())


## Spawns one volley from `muzzle` (the gun, or a Turret this gun deployed).
## `focus`: aim each projectile at this gun's own ranked targets (auto aim, section 7.2);
## guns that shoot a spread by design (projectile_count above 1) keep it around their target.
func shoot_from(muzzle: Vector2, dir: Vector2, focus := false) -> void:
    var world := get_tree().current_scene
    var base := strike()
    var count := shot_count()
    var pierce := shot_pierce()
    var speed := data.projectile_speed * speed_mult()
    # Transformative gear (Isaac's tear modifiers), summed onto every shot.
    var homing := player.stat("homing")
    var splash := player.stat("splash")
    var shards := int(player.stat("shards"))
    var size_mult := maxf(0.3, 1.0 + player.stat("shot_size"))
    var spectral := player.stat("spectral") > 0.0
    var boomerang := player.stat("boomerang") > 0.0
    var bounces := int(player.stat("bounce")) + int(_gm("g_bounce"))
    # Straight guns take on the shape the gear asks for; other behaviours keep theirs.
    var shape := data.behaviour
    if shape == "straight":
        if boomerang:
            shape = "boomerang"
        elif homing > 0.0:
            shape = "homing"
        elif shards > 0 and pierce == 0 and bounces == 0:
            shape = "flak"
    var lifetime := data.lifetime * (1.0 + player.stat("range") + _gm("g_range"))
    var lobbed := shape == "lob" or shape == "pool"
    if lobbed:
        speed *= 1.0 + player.stat("lob_speed")   # Overarm
    var thrown_kind := Thrown.handles(shape)
    # Lobbed shells land on the nearest enemy (or most of the way out when there is none).
    var lob_dist := 0.0
    if lobbed:
        var rng := effective_range()
        lob_dist = rng * 0.6
        var tgt := Strike.nearest(get_tree(), muzzle, rng, {})
        if tgt != null and absf((tgt.global_position - muzzle).normalized().angle_to(dir)) < 0.6:
            lob_dist = clampf(muzzle.distance_to(tgt.global_position), 50.0, rng)
    # Homing: each seeker of a volley takes a different enemy, nearest first, rotating.
    var targets: Array = []
    if shape == "homing":
        targets = _targets_by_distance(muzzle, effective_range() * 1.2, maxi(count, 4))
        _target_k += 1
    var shot_element: int = data.element
    var split := focus and count > 1 and data.projectile_count <= 1 and not lobbed and shape != "homing" and shape != "helix" and shape != "star" and shape != "converge"
    if focus and not targets.is_empty():
        var t0 = targets[0]
        if is_instance_valid(t0) and t0 is Enemy:
            t0.add_pending(base.damage * float(count if not split else 1), muzzle.distance_to(t0.global_position) / maxf(60.0, speed) + 0.1)
    for i in count:
        var angle := 0.0
        if count > 1:
            angle = lerpf(-data.spread_deg, data.spread_deg, float(i) / float(count - 1)) * 0.5
        angle += randf_range(-data.spread_deg, data.spread_deg) * 0.15
        var el := _next_element()
        if shape == "helix":
            # A helix pair is one element each, whatever the alternation did.
            el = data.element if i % 2 == 0 else (data.alt_element if data.alt_element != Element.Kind.NONE else data.element)
            angle = randf_range(-data.spread_deg, data.spread_deg) * 0.15 if i < 2 else angle
        shot_element = el
        var p := Projectile.new()
        var shot_dir := dir
        if split:
            var at := Focus.aim_point(self, i)
            if at != Vector2.INF and at.distance_to(muzzle) > 4.0:
                shot_dir = (at - muzzle).normalized()
                angle = randf_range(-data.spread_deg, data.spread_deg) * 0.15
                if i > 0 and i < targets.size() and is_instance_valid(targets[i]) and targets[i] is Enemy:
                    targets[i].add_pending(base.damage, muzzle.distance_to(at) / maxf(60.0, speed) + 0.1)
        p.velocity = shot_dir.rotated(deg_to_rad(angle)) * speed
        p.damage = base.damage
        p.element = el
        p.extra_elements = base.extras
        p.potency = base.potency
        p.lifetime = lifetime
        p.pierce = pierce
        p.bounces = bounces + data.ricochets
        p.radius = data.projectile_radius * (1.4 if base.crit else 1.0) * (1.0 + 0.1 * float(tier - 1)) * size_mult
        p.color = Element.COLORS[el]
        p.crit = base.crit
        p.shooter = player
        p.gun_id = data.id
        p.behaviour = shape
        p.splash_radius = data.splash_radius * (1.0 + 0.1 * float(tier - 1)) + splash
        p.shard_count = data.shard_count + shards
        p.homing_turn = data.homing_turn + homing
        p.knockback = data.knockback
        p.aura_radius = data.aura_radius * size_mult * (1.0 + 0.1 * float(tier - 1))
        p.linger = data.linger
        if data.family == "thrown" and shape == "pool":
            p.linger *= 1.0 + player.stat("state_duration")   # pools last longer (2.2)
        if data.archetype == "sniper":
            p.far_crit = 300.0
        if data.archetype == "repeater" and data.element == Element.Kind.ICE and data.spin_up > 0.0:
            # Rime Repeater: each hit chills a little more as it spins up.
            p.potency *= 1.0 + clampf(_spin / data.spin_up, 0.0, 1.0)
        p.fork_count = data.fork_count
        p.ricochet_walls = data.ricochets > 0
        if shape == "helix":
            p.helix_sign = 1.0 if i % 2 == 0 else -1.0
        if shape == "homing" and not targets.is_empty():
            p.home_target = targets[(i + _target_k) % targets.size()]
        if thrown_kind or (shape == "boomerang" and data.id == "crossing_axes"):
            Thrown.prepare(p, self, muzzle, shot_dir, i, count)
        if data.id == "crossing_axes" and count > 1:
            p.velocity = p.velocity.rotated(0.55 * (1.0 if i % 2 == 0 else -1.0))
        if spectral and not lobbed:
            # Spectral: the obstacle grace never runs out, so walls of rock and crates are ignored.
            p.spectral = true
        if lobbed:
            p.lifetime = maxf(0.15, lob_dist * randf_range(0.9, 1.1) / maxf(1.0, speed))
            p.bounces = 0
        _item_shot(p)
        p.global_position = muzzle
        world.add_child(p)
    # Rear Guard: one more shot straight back per copy.
    var rear := int(player.stat("rear_shots"))
    if rear > 0 and not lobbed and not thrown_kind:
        for r in rear:
            var q := Projectile.new()
            q.velocity = (-dir).rotated(deg_to_rad(randf_range(-12.0, 12.0) + (float(r) - float(rear - 1) * 0.5) * 14.0)) * speed
            q.damage = base.damage
            q.element = data.element
            q.extra_elements = base.extras
            q.potency = base.potency
            q.lifetime = lifetime
            q.pierce = pierce
            q.radius = data.projectile_radius * size_mult
            q.color = Element.COLORS[data.element]
            q.shooter = player
            q.gun_id = data.id
            _item_shot(q)
            q.global_position = muzzle
            world.add_child(q)
    Sfx.shoot(shot_element, muzzle)
    if "fx" in world and world.fx != null:
        world.fx.puff(Art.PARTICLES["light"], muzzle, Color(Element.COLORS[shot_element], 0.9), 22.0 + float(data.weight) * 4.0, 0.08, true)


## Item and synergy rules every shot of this gun carries (Long Fuse, Gravity Shot, Rebound,
## the synergy signature colour).
func _item_shot(p: Projectile) -> void:
    p.grow = player.stat("grow")
    p.pull = player.stat("pull")
    p.rebound = 1 if player.stat("rebound") > 0.0 else 0
    if not player.synergies.is_empty():
        p.signature = Items.synergy(String(player.synergies[player.synergies.size() - 1])).get("color", Color(0, 0, 0, 0))


## Up to `n` live enemies within `r` of `pos`, nearest first.
func _targets_by_distance(pos: Vector2, r: float, n: int) -> Array:
    var pairs: Array = []
    for e in EnemyGrid.nodes(get_tree(), &"enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or not e is Enemy or e.emerge > 0.0:
            continue
        var d: float = e.global_position.distance_squared_to(pos)
        if d <= r * r:
            pairs.append([d, e])
    pairs.sort_custom(func(a, b): return a[0] < b[0])
    var out: Array = []
    for k in mini(n, pairs.size()):
        out.append(pairs[k][1])
    return out


# --- Beam ---------------------------------------------------------------------


func _fire_beam(dir: Vector2) -> void:
    var n := shot_count()
    _beams = _beams.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
    while _beams.size() < n:
        var b := Beam.new(self)
        Strike.world_parent(self).add_child(b)
        _beams.append(b)
    while _beams.size() > n:
        var old = _beams.pop_back()
        if is_instance_valid(old):
            old.queue_free()
    var s := strike()
    var reach := effective_range()
    var pierce := shot_pierce()
    var width := maxf(2.0, data.projectile_radius) * size_mult()
    for i in n:
        var b = _beams[i]
        if not is_instance_valid(b) or b.is_queued_for_deletion():
            b = Beam.new(self)
            Strike.world_parent(self).add_child(b)
            _beams[i] = b
        var off := 0.0 if n == 1 else lerpf(-1.0, 1.0, float(i) / float(n - 1)) * deg_to_rad(6.0 * float(n - 1))
        var bdir := dir.rotated(off)
        if player.focusing():
            # Focus: beam i holds its own target; beams beyond the targets double up on the top one.
            var at := Focus.aim_point(self, i)
            if at != Vector2.INF and at.distance_to(global_position) > 4.0:
                bdir = (at - global_position).normalized()
        b.tick(bdir, s, reach, pierce, width)


## Radians per second a beam turns toward its aim (shot speed mods turn it faster).
func beam_sweep() -> float:
    return 4.5 * speed_mult()


# --- Spray --------------------------------------------------------------------


func _fire_cone(dir: Vector2) -> void:
    if _spray == null or not is_instance_valid(_spray) or _spray.is_queued_for_deletion():
        _spray = Spray.new(self)
        Strike.world_parent(self).add_child(_spray)
    var s := strike(_next_element())
    var extra := shot_count() - 1
    # Extra projectiles widen the cone and hit harder; pierce reaches further.
    s.damage *= 1.0 + 0.25 * float(extra)
    s.potency *= 1.0 + 0.25 * float(extra)
    var half := deg_to_rad(data.arc_deg * 0.5 + 6.0 * float(extra))
    var reach := effective_range() * (1.0 + 0.1 * float(shot_pierce()))
    _spray.tick(dir, s, reach, half, data.knockback)


# --- Chain --------------------------------------------------------------------


func _fire_chain(dir: Vector2) -> void:
    var reach := effective_range()
    var jumps := data.chain_jumps + int(player.stat("chain_jumps")) + int(player.stat("bounce")) + shot_pierce()
    var hit: Dictionary = {}
    var arcs := 0
    for i in shot_count():
        var first := _chain_first(dir, reach, hit)
        if first == null:
            break
        arcs += 1
        var s := strike(_next_element())
        var from := global_position + dir * 10.0
        var cur: Enemy = first
        var mult := 1.0
        for j in jumps + 1:
            hit[cur] = true
            _arc_fx(from, cur.global_position, s.color, s.element)
            s.hit(cur, mult, cur.global_position, (cur.global_position - from).normalized() * data.knockback)
            from = cur.global_position
            mult *= GunData.CHAIN_FALLOFF
            var nxt := Strike.nearest(get_tree(), from, CHAIN_JUMP_RANGE * (1.0 + player.stat("range")), hit)
            if nxt == null:
                break
            cur = nxt
    if arcs == 0:
        # Nothing to arc to (RT into empty space, or at a door): a plain bolt instead, so
        # obstacles and props still take the element.
        shoot_from(global_position + dir * 14.0, dir)
        return
    Sfx.shoot(data.element, global_position)


## The first enemy an arc takes: the nearest one within reach and roughly ahead.
func _chain_first(dir: Vector2, reach: float, skip: Dictionary) -> Enemy:
    var best: Enemy = null
    var best_d := INF
    for e in Strike.enemies_in(get_tree(), global_position, reach):
        if skip.has(e):
            continue
        var to: Vector2 = e.global_position - global_position
        if to.length() > 30.0 and absf(dir.angle_to(to)) > 0.6:
            continue
        var d := to.length()
        if d < best_d:
            best_d = d
            best = e
    return best


func _arc_fx(a: Vector2, b: Vector2, col: Color, el: int) -> void:
    if el == Element.Kind.SHOCK:
        Elements.lightning_arc.emit(a, b)
    else:
        GunFx.rail(Strike.world_parent(self), a, b, 1.5, col)
        var fx := Strike.fx_of(self)
        if fx != null:
            fx.pixels(el, b, 4, 70.0, 4.0)


# --- Nova ---------------------------------------------------------------------


func _fire_nova() -> void:
    var r := effective_range()
    var echoes := shot_count()
    _nova_ring(r)
    for k in range(1, echoes):
        get_tree().create_timer(0.18 * float(k), false).timeout.connect(func():
            if is_instance_valid(self) and is_inside_tree():
                _nova_ring(r))


func _nova_ring(r: float) -> void:
    var s := strike(_next_element())
    var c := player.global_position
    for e in Strike.enemies_in(get_tree(), c, r):
        var away: Vector2 = (e.global_position - c).normalized()
        s.hit(e, 1.0, e.global_position, away * data.knockback)
    s.touch_world(get_tree(), c, r, Vector2.ZERO)
    s.touch_clouds(get_tree(), c, r, {})
    s.stamp(self, c, minf(r * 0.5, 50.0), false)
    var fx := Strike.fx_of(self)
    if fx != null:
        fx.ring(c, r, s.color, 0.3)
        fx.pixels(s.element, c, 10, r * 1.6, r * 0.2)
    Sfx.play_at("burst_small", c, -4.0)


# --- Sweep --------------------------------------------------------------------


func _fire_melee(dir: Vector2) -> void:
    var swings := shot_count()
    Melee.swing(self, dir, false)
    for k in range(1, swings):
        get_tree().create_timer(0.14 * float(k), false).timeout.connect(func():
            if is_instance_valid(self) and is_inside_tree():
                Melee.swing(self, _aim, k % 2 == 1))


func _swing(dir: Vector2, back: bool) -> void:
    var s := strike(_next_element())
    var c := player.global_position
    var reach := effective_range() * (1.0 + 0.1 * float(shot_pierce()))
    var half := deg_to_rad(data.arc_deg * 0.5)
    for e in Strike.enemies_in_cone(get_tree(), c, dir, reach, half):
        s.hit(e, 1.0, e.global_position, (e.global_position - c).normalized() * data.knockback)
    s.touch_world(get_tree(), c + dir * reach * 0.6, reach * 0.45, dir)
    s.touch_clouds(get_tree(), c + dir * reach * 0.6, reach * 0.45, {})
    GunFx.sweep(Strike.world_parent(self), c, dir, reach, half, s.color, back)
    Sfx.shoot(s.element, c)
    Sfx.play_at("hit_wall", c + dir * reach * 0.6, -8.0)


# --- Charge -------------------------------------------------------------------


func _charge_needed() -> float:
    # Fire rate gear and tiers wind it faster.
    return data.charge_time * data.fire_rate / maxf(0.05, fire_rate())


func _tick_charge(delta: float) -> void:
    _charge += delta
    var d := player.gun_dir(self)
    if d != Vector2.ZERO:
        _aim = d
    if _charge < _charge_needed():
        return
    if d == Vector2.ZERO:
        return   # fully charged: held until something comes in reach, or you aim
    _charging = false
    _rail(_aim)
    cooldown = 1.0 / fire_rate()
    _recoil = 6.0 + float(data.weight)
    player.add_pressure(data.pressure_per_shot * (1.0 + _gm("g_pressure")))
    player.kick(_aim, 2.0 + float(data.weight))


func _rail(dir: Vector2) -> void:
    var n := shot_count()
    for i in n:
        var off := 0.0 if n == 1 else lerpf(-1.0, 1.0, float(i) / float(n - 1)) * deg_to_rad(5.0 * float(n - 1))
        var d := dir.rotated(off)
        var s := strike(_next_element())
        # A rail already goes through everything: pierce makes it hit harder instead.
        s.damage *= 1.0 + 0.15 * float(shot_pierce())
        var a := global_position + d * 12.0
        var tr: Array = Strike.trace(get_tree(), a, d, effective_range())
        var b: Vector2 = tr[0]
        var width := data.projectile_radius * size_mult()
        for e in Strike.enemies_on_line(get_tree(), a, b, width):
            s.hit(e, 1.0, e.global_position, d * data.knockback)
        if tr[1] != null:
            s.touch_world(get_tree(), b, 6.0, d)
        var seen := {}
        var steps := int(a.distance_to(b) / 60.0)
        for k in steps + 1:
            s.touch_clouds(get_tree(), a.lerp(b, float(k) / float(maxi(1, steps))), 10.0, seen)
        GunFx.rail(Strike.world_parent(self), a, b, width, s.color)
        var fx := Strike.fx_of(self)
        if fx != null:
            fx.pixels(s.element, b, 8, 120.0, 4.0)
        Sfx.shoot(s.element, a)
        Sfx.play_at("burst_small", b, -6.0)


# --- Mines and turrets -----------------------------------------------------------


func _fire_mine(dir: Vector2) -> void:
    var n := shot_count()
    var tgt := Strike.nearest(get_tree(), global_position, effective_range(), {})
    var dist := 80.0
    if tgt != null:
        dist = clampf(global_position.distance_to(tgt.global_position) * 0.7, 30.0, 130.0)
    for i in n:
        var off := 0.0 if n == 1 else lerpf(-0.5, 0.5, float(i) / float(n - 1))
        var s := strike(_next_element())
        var m := Mine.new(s, data.aura_radius * size_mult() * (1.0 + 0.1 * float(shot_pierce())) * (1.0 + player.stat("zone_radius")), data.linger * (1.0 + player.stat("zone_life")))
        m.behaviour = data.behaviour
        var land := global_position + dir.rotated(off) * dist * randf_range(0.85, 1.15)
        Strike.world_parent(self).add_child(m)
        m.toss(global_position, land)
        _mines.append(m)
    _mines = _mines.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
    while _mines.size() > MINE_CAP * n:
        var old: Mine = _mines.pop_front()
        old.detonate()
    Sfx.play_at("shoot_" + Items.ELEMENT_KEYS.get(data.element, "stone"), global_position, -6.0)


## Deploys a turret when fewer than the cap are up. Returns false when none was placed.
func _fire_turret(dir: Vector2) -> bool:
    _turrets = _turrets.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
    if _turrets.size() >= TURRET_CAP + maxi(0, shot_count() - data.projectile_count) + int(player.stat("summon_cap")):
        return false
    if not Summon.make_room(player):
        return false   # 16 summon bodies already out (Arsenal expansion 2.5)
    var t := Turret.new(self, data.linger * (1.0 + 0.1 * float(tier - 1)) * (1.0 + player.stat("state_duration") + player.stat("turret_life")))
    Strike.world_parent(self).add_child(t)
    t.global_position = player.global_position + dir * 22.0
    _turrets.append(t)
    Sfx.play_at("hit_wall", t.global_position, -4.0)
    cooldown = 0.8
    return true
