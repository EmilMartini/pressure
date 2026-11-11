class_name Legendary
extends RefCounted
## Arsenal expansion batch 5 (section 3.5): the legendary weapons' rules. A legendary is an
## ordinary weapon of its family (GunData), plus `GunData.legend`, the key of one rule here.
## Rules hook in at three places only:
##   - `on_event` from Items.fire (hit, kill, vent, reaction, room_enter);
##   - `tick` from Gun._process (timed rules: Stormcrown, Event Horizon, Skyfall, The Conductor);
##   - `strike_mult` / `extra_elements` from Gun.strike and Gun.extra_elements.
## Plus `phoenix` from Player.take_damage (Phoenix Lantern beside Last Breath) and
## `horizon_mult` from Strike.deal (Event Horizon's +30%).
## Every rule's hits go through Strike (attributed to the legendary in Telemetry).

## The card line per rule (at most 10 words, 60 characters; Arsenal expansion 3.5).
const LINES := {
    "forge": "Each vent turns every weapon molten for 5 s",
    "conductor": "Arcs leap between every foe you hit last second",
    "tidebreaker": "Every fourth swing sends a freezing wave across the room",
    "coil": "A whip that reaches across the room, leaving venom",
    "harvest": "Each kill adds 2% damage until the room ends",
    "skyfall": "A meteor falls on the biggest pack every 6 s",
    "second_sun": "Your reactions fire a beam from your orbiting sun",
    "phoenix": "Once a floor, the firebird saves you at 30%",
    "stormcrown": "While you move, lightning strikes the closest foe",
    "bell": "Plant a bell; each toll applies all your elements",
    "horizon": "Foes within 180 px drift to you, taking +30%",
    "echo": "Your other weapons fire again from this one",
    "glass": "Stops foes in time; their damage lands all at once",
    "mirror": "Swings send enemy shots back at their owners",
    "knives": "Knives stay down; each dash calls them all back",
    "prism": "Takes a new element at every bounce",
    "choir": "Each kill raises a shade that fights for 8 s",
    "orrery": "An orbiting mote for every element you carry",
}

const FORGE_SECS := 5.0
const FORGE_DMG := 0.2             # molten: +20% damage and a Fire coat on every weapon
const CONDUCTOR_EVERY := 1.0       # s between two nets
const CONDUCTOR_MAX := 8           # foes in one net
const CONDUCTOR_MULT := 0.6        # of the Conductor's strike, per foe in the net
const TIDE_EVERY := 4
const TIDE_RADIUS := 420.0
const TIDE_MULT := 0.5
const HARVEST_STEP := 0.02
const HARVEST_CAP := 50            # +100% at most
const SKY_EVERY := 6.0
const SKY_DELAY := 0.7             # the shadow before the meteor lands
const SKY_RADIUS := 90.0
const SKY_MULT := 2.5
const SUN_GAP := 0.5               # s between two of the sun's beams
const PHOENIX_HP := 0.3
const STORM_GAP := 0.45            # s between two strikes while moving
const STORM_REACH := 320.0
const STORM_MOVE := 40.0           # px/s that counts as moving
const HORIZON_R := 180.0
const HORIZON_PULL := 55.0         # px/s drift toward you
const HORIZON_BONUS := 0.3
const ECHO_EVERY := 2              # every other trigger of another weapon echoes
const ECHO_MULT := 0.5
const GLASS_SECS := 1.5            # a foe stays stopped this long (elites and bosses 0.5)
const GLASS_ELITE := 0.5
const GLASS_COOL := 1.5            # then can't be stopped again for this long
const MIRROR_MULT := 0.8           # of the Mirrorblade's strike, per shot sent back
const MIRROR_R := 110.0            # each swing sends back the shots this close to you
const KNIFE_STAY := 20.0           # s a Mother of Knives knife waits for a dash
const KNIFE_CALL := 1.5            # recalled knives hit this hard on the way
const CHOIR_GAP := 0.5
const CHOIR_MAX := 6
const CHOIR_SECS := 8.0
const PRISM := [Element.Kind.FIRE, Element.Kind.WET, Element.Kind.SHOCK, Element.Kind.ICE, Element.Kind.OIL,
    Element.Kind.POISON, Element.Kind.ACID, Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.BLOOD,
    Element.Kind.GALE, Element.Kind.STONE]

static var _hit_log: Dictionary = {}      # player id -> { enemy -> game time of the last hit }
static var _molten_until: Dictionary = {} # player id -> game time
static var _harvest: Dictionary = {}      # gun instance id -> kills this room
static var _phoenix_floor: Dictionary = {} # player id -> floor the firebird last saved you on
static var _horizon: Dictionary = {}      # player id -> true while an Event Horizon is carried
static var _last_sun: Dictionary = {}     # gun instance id -> game time of the last beam
static var _echo_n: Dictionary = {}       # player id -> other-weapon triggers seen
static var _glass: Dictionary = {}       # enemy -> [stopped until, stored damage, player, cool until]
static var _last_shade: Dictionary = {}  # gun instance id -> game time of the last shade
static var fired: Dictionary = {}
## Arsenal 3.3 and 3.5: legendaries offered this run (each at most once), and the hidden
## drought rule. `Progress` stat "legendary_drought" counts dry runs that reached floor 2:
## a run is counted dry when it reaches floor 2 unoffered, and the count resets when one
## is offered. After DROUGHT_RUNS dry runs, the next run's first treasure room from floor 2
## holds one (FloorGen).
const DROUGHT_RUNS := 4
static var offered_run: Dictionary = {}
static var _counted := false    # this run already added itself to the drought


static func new_run() -> void:
    offered_run.clear()
    _counted = false
    _hit_log.clear()
    _molten_until.clear()
    _harvest.clear()
    _phoenix_floor.clear()
    _glass.clear()


static func is_legend(id: String) -> bool:
    return Guns.rarity_of(id) >= Items.Rarity.LEGENDARY


## Drops.roll_gun picked a legendary for an offer.
static func mark_offered(id: String) -> void:
    offered_run[id] = true
    if Progress.stat("legendary_drought") > 0:
        Progress.stats["legendary_drought"] = 0
    Telemetry.event("legendary_offered", { "id": id })


## Main: the run reached floor 2.
static func reached_floor2() -> void:
    if offered_run.is_empty() and not _counted:
        _counted = true
        Progress.add("legendary_drought")


## FloorGen: whether this treasure room must hold a legendary weapon (the drought rule).
static func drought_due(floor_number: int) -> bool:
    if floor_number < 2 or not offered_run.is_empty():
        return false
    if Items.max_rarity_unlocked() < Items.Rarity.LEGENDARY:
        return false
    return Progress.stat("legendary_drought") >= DROUGHT_RUNS + (1 if _counted else 0)         # rule -> times it fired (--legendary-probe)


static func now() -> float:
    return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


static func note(rule: String) -> void:
    fired[rule] = int(fired.get(rule, 0)) + 1


static func line(rule: String) -> String:
    return String(LINES.get(rule, ""))


static func _legends(player: Player, rule: String) -> Array:
    var out: Array = []
    if player == null or not is_instance_valid(player):
        return out
    for g in player.guns:
        if is_instance_valid(g) and g.data.legend == rule:
            out.append(g)
    return out


## Items.fire: every event passes through here first.
static func on_event(player: Player, event: String, ctx: Dictionary) -> void:
    var pid := player.get_instance_id()
    var any := false
    for g in player.guns:
        if is_instance_valid(g) and g.data.legend != "":
            any = true
            break
    if not any:
        _horizon.erase(pid)
        return
    match event:
        "vent":
            if not _legends(player, "forge").is_empty():
                _molten_until[pid] = now() + FORGE_SECS
                note("forge")
                var scene := player.get_tree().current_scene
                if scene != null and scene.has_method("flash"):
                    scene.flash(Color(1.0, 0.5, 0.15), 0.2, 0.3)
        "hit":
            if not _legends(player, "conductor").is_empty():
                var t: Variant = ctx.get("target")
                if t != null and is_instance_valid(t):
                    var log: Dictionary = _hit_log.get(pid, {})
                    log[t] = now()
                    _hit_log[pid] = log
        "dash":
            if not _legends(player, "knives").is_empty():
                if Thrown.recall_all(player, KNIFE_CALL) > 0:
                    note("knives")
        "kill":
            for g in _legends(player, "choir"):
                _shade(g, ctx)
            for g in _legends(player, "harvest"):
                var k: int = g.get_instance_id()
                _harvest[k] = mini(HARVEST_CAP, int(_harvest.get(k, 0)) + 1)
                note("harvest")
        "room_enter", "room_clear":
            for g in _legends(player, "harvest"):
                _harvest.erase(g.get_instance_id())
        "reaction":
            for g in _legends(player, "second_sun"):
                _sun_beam(g, ctx)


## Gun.strike: a legendary's own damage factor (Red Harvest), and the molten bonus on every weapon.
static func strike_mult(gun: Gun) -> float:
    var m := 1.0
    if gun.data.legend == "harvest":
        m *= 1.0 + HARVEST_STEP * float(_harvest.get(gun.get_instance_id(), 0))
    if molten(gun.player):
        m *= 1.0 + FORGE_DMG
    return m


static func molten(player: Player) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    return float(_molten_until.get(player.get_instance_id(), -1.0)) > now()


## Gun.extra_elements: the Bell carries every element of your other weapons; molten weapons carry Fire.
static func extra_elements(gun: Gun, out: Array) -> void:
    if gun.data.legend == "bell" and is_instance_valid(gun.player):
        for g in gun.player.guns:
            if not is_instance_valid(g) or g == gun:
                continue
            for el in [g.data.element, g.data.extra_element, g.data.alt_element]:
                if int(el) != Element.Kind.NONE and int(el) != gun.data.element and not out.has(int(el)):
                    out.append(int(el))
        note("bell")
    if molten(gun.player) and gun.data.element != Element.Kind.FIRE and not out.has(Element.Kind.FIRE):
        out.append(Element.Kind.FIRE)


## Strike.deal: Event Horizon's +30% on foes inside its reach.
static func horizon_mult(src: Player, enemy: Enemy) -> float:
    if src == null or not _horizon.has(src.get_instance_id()):
        return 1.0
    if enemy.global_position.distance_squared_to(src.global_position) <= HORIZON_R * HORIZON_R:
        return 1.0 + HORIZON_BONUS
    return 1.0


## Player.take_damage: the firebird stands you back up at 30% once a floor.
static func phoenix(player: Player) -> bool:
    if _legends(player, "phoenix").is_empty():
        return false
    var mn := player.main()
    var fl: int = mn.floor_number if mn != null else 0
    var pid := player.get_instance_id()
    if int(_phoenix_floor.get(pid, -1)) == fl:
        return false
    _phoenix_floor[pid] = fl
    player.hp = maxf(1.0, player.max_hp * PHOENIX_HP)
    player.invuln = maxf(player.invuln, 1.5)
    note("phoenix")
    Sfx.play("revive")
    var scene := player.get_tree().current_scene
    if scene != null and scene.has_method("flash"):
        scene.flash(Color(1.0, 0.55, 0.2), 0.45, 0.5)
    Elements.nova.emit(player.global_position, 120.0, Color(1.0, 0.6, 0.2, 0.6))
    Telemetry.event("phoenix", { "player": player.index, "floor": fl })
    return true


## Gun.fire of any weapon: Echo Engine fires every other trigger of the others again.
static func on_fire(gun: Gun) -> void:
    var p := gun.player
    if p == null or not is_instance_valid(p) or gun.data.legend == "echo":
        return
    var echoes := _legends(p, "echo")
    if echoes.is_empty():
        return
    var pid := p.get_instance_id()
    var n := int(_echo_n.get(pid, 0)) + 1
    _echo_n[pid] = n
    if n % ECHO_EVERY != 0:
        return
    var echo: Gun = echoes[0]
    var from := echo.global_position
    var e := Strike.nearest(p.get_tree(), from, maxf(gun.effective_range(), 260.0), {})
    if e == null:
        return
    var s := gun.strike()
    s.gun_id = echo.data.id
    s.damage *= ECHO_MULT
    s.potency *= ECHO_MULT
    echo._arc_fx(from, e.global_position, Element.COLORS[Element.Kind.GALE], Element.Kind.GALE)
    s.hit(e)
    note("echo")


## Gun._process for a weapon with a timed rule.
static func tick(gun: Gun, delta: float) -> void:
    var p := gun.player
    if p == null or not is_instance_valid(p) or not p.alive:
        return
    match gun.data.legend:
        "glass":
            _glass_release()
        "mirror":
            # Each swing also sends back every enemy shot within MIRROR_R of you (the blade's
            # own path cuts them too, Melee._parry): crossing the line alone was rare.
            if gun.melee_n > 0 and gun.legend_t != float(gun.melee_n):
                gun.legend_t = float(gun.melee_n)
                var r2 := MIRROR_R * MIRROR_R
                for sh in gun.get_tree().get_nodes_in_group("enemy_projectiles"):
                    if is_instance_valid(sh) and not sh.is_queued_for_deletion() and sh.global_position.distance_squared_to(p.global_position) <= r2:
                        mirror(gun, sh)
                        sh.queue_free()
        "horizon":
            _horizon[p.get_instance_id()] = true
            gun.legend_t += delta
            if gun.legend_t < 0.1:
                return
            gun.legend_t = 0.0
            for e in Strike.enemies_in(p.get_tree(), p.global_position, HORIZON_R):
                var to: Vector2 = p.global_position - e.global_position
                if to.length() > 30.0:
                    e.global_position += to.normalized() * HORIZON_PULL * 0.1 * (0.4 if e.boss_kind != "" else 1.0)
            note("horizon")
        "stormcrown":
            gun.legend_t += delta
            if gun.legend_t < STORM_GAP / maxf(0.25, gun.fire_rate() / gun.data.fire_rate):
                return
            if p.velocity.length() < STORM_MOVE:
                return
            var e := Strike.nearest(p.get_tree(), p.global_position, STORM_REACH, {})
            if e == null:
                return
            gun.legend_t = 0.0
            Elements.lightning_arc.emit(e.global_position + Vector2(0, -160), e.global_position)
            gun.strike().hit(e)
            note("stormcrown")
        "conductor":
            gun.legend_t += delta
            if gun.legend_t < CONDUCTOR_EVERY:
                return
            gun.legend_t = 0.0
            _net(gun)
        "skyfall":
            gun.legend_t += delta
            if gun.legend_t < SKY_EVERY / maxf(0.25, gun.fire_rate() / gun.data.fire_rate):
                return
            var at := _biggest_pack(p)
            if at == Vector2.INF:
                return
            gun.legend_t = 0.0
            Elements.nova.emit(at, SKY_RADIUS, Color(1.0, 0.55, 0.2, 0.35))
            var tree := p.get_tree()
            tree.create_timer(SKY_DELAY, false).timeout.connect(func():
                if not is_instance_valid(gun) or not is_instance_valid(gun.player):
                    return
                var s := gun.strike(Element.Kind.STONE)
                s.damage *= SKY_MULT
                s.potency *= SKY_MULT
                if not s.extras.has(Element.Kind.FIRE):
                    s.extras = s.extras + [Element.Kind.FIRE]
                Elements.nova.emit(at, SKY_RADIUS, Color(1.0, 0.45, 0.15, 0.8))
                var fx := Strike.fx_of(gun)
                if fx != null:
                    fx.pixels(Element.Kind.FIRE, at, 14, 160.0, 5.0)
                for e in Strike.enemies_in(tree, at, SKY_RADIUS):
                    s.hit(e)
                note("skyfall"))
        "tidebreaker":
            if gun.melee_n >= TIDE_EVERY and gun.melee_n % TIDE_EVERY == 0 and gun.legend_t != float(gun.melee_n):
                gun.legend_t = float(gun.melee_n)
                var s := gun.strike(Element.Kind.ICE)
                s.damage *= TIDE_MULT
                s.potency *= TIDE_MULT
                Elements.nova.emit(p.global_position, TIDE_RADIUS, Color(0.6, 0.85, 1.0, 0.5))
                for e in Strike.enemies_in(p.get_tree(), p.global_position, TIDE_RADIUS):
                    var away: Vector2 = (e.global_position - p.global_position).normalized()
                    s.hit(e, 1.0, Vector2.INF, away * 80.0)
                note("tidebreaker")


## The Conductor: one arc through every foe you hit in the last second, closest first.
static func _net(gun: Gun) -> void:
    var p := gun.player
    var pid := p.get_instance_id()
    var log: Dictionary = _hit_log.get(pid, {})
    var t := now()
    var live: Array = []
    for e in log.keys():
        if is_instance_valid(e) and not e.is_queued_for_deletion() and t - float(log[e]) <= CONDUCTOR_EVERY:
            live.append(e)
    _hit_log[pid] = {}
    if live.size() < 2:
        return
    live.sort_custom(func(a, b): return a.global_position.distance_squared_to(p.global_position) < b.global_position.distance_squared_to(p.global_position))
    live.resize(mini(live.size(), CONDUCTOR_MAX))
    var s := gun.strike()
    s.damage *= CONDUCTOR_MULT
    s.potency *= CONDUCTOR_MULT
    for i in live.size():
        if i > 0 and is_instance_valid(live[i - 1]) and is_instance_valid(live[i]):
            Elements.lightning_arc.emit(live[i - 1].global_position, live[i].global_position)
        if is_instance_valid(live[i]):
            s.hit(live[i])
    note("conductor")


## The Second Sun: a reaction fires a beam from the sun at the foe that reacted.
static func _sun_beam(gun: Gun, ctx: Dictionary) -> void:
    var k := gun.get_instance_id()
    var t := now()
    if t - float(_last_sun.get(k, -9.0)) < SUN_GAP:
        return
    var target: Variant = ctx.get("target")
    if target == null or not is_instance_valid(target) or not target is Enemy:
        return
    _last_sun[k] = t
    var from := gun.global_position
    for b in gun.bodies:
        if is_instance_valid(b):
            from = b.global_position
            break
    gun._arc_fx(from, target.global_position, Element.COLORS[Element.Kind.HOLY], Element.Kind.HOLY)
    gun.strike(Element.Kind.HOLY).hit(target)
    note("second_sun")


## Hollow Choir: a kill raises a shade where the foe fell, for CHOIR_SECS.
static func _shade(gun: Gun, ctx: Dictionary) -> void:
    var k: int = gun.get_instance_id()
    var t := now()
    if t - float(_last_shade.get(k, -9.0)) < CHOIR_GAP:
        return
    var shades := 0
    for b in gun.bodies:
        if is_instance_valid(b) and b.temp_life > 0.0:
            shades += 1
    if shades >= CHOIR_MAX or not Summon.make_room(gun.player):
        return
    _last_shade[k] = t
    var at: Vector2 = ctx.get("pos", gun.player.global_position)
    Summon.spawn(gun, at, CHOIR_SECS)
    note("choir")


## Orrery: the elements you carry, in slot order (each once).
static func carried_elements(p: Player) -> Array:
    var out: Array = []
    if p == null or not is_instance_valid(p):
        return out
    for g in p.guns:
        if not is_instance_valid(g):
            continue
        for el in [g.data.element, g.data.extra_element, g.data.alt_element]:
            if int(el) != Element.Kind.NONE and not out.has(int(el)):
                out.append(int(el))
    return out


## Summon.cap_of and Summon.spawn: one mote per element, each mote its own element.
static func orrery_cap(gun: Gun, base: int) -> int:
    if gun.data.legend != "orrery":
        return base
    return maxi(base, carried_elements(gun.player).size())


static func orrery_element(gun: Gun, idx: int) -> int:
    var els := carried_elements(gun.player)
    if els.is_empty():
        return gun.data.element
    note("orrery")
    return int(els[idx % els.size()])


## Thrown disc bounce: Prism Disc takes the next element.
static func prism_next(el: int) -> int:
    var i := PRISM.find(el)
    note("prism")
    return int(PRISM[(i + 1) % PRISM.size()])


## Melee._parry: Mirrorblade sends a cut shot back at the foe that fired it.
static func mirror(gun: Gun, shot: Node2D) -> void:
    var owner: Variant = shot.get("owner_enemy")
    var target: Enemy = null
    if owner != null and is_instance_valid(owner) and owner is Enemy:
        target = owner as Enemy
    if target == null:
        target = Strike.nearest(gun.get_tree(), shot.global_position, 400.0, {})
    if target == null or target.is_queued_for_deletion():
        return
    var s := gun.strike()
    s.damage *= MIRROR_MULT
    s.potency *= MIRROR_MULT
    gun._arc_fx(shot.global_position, target.global_position, Element.COLORS[Element.Kind.HOLY], Element.Kind.HOLY)
    s.hit(target)
    note("mirror")


## Glass of Ages: a hit by it stops the foe; Strike.deal then banks damage instead.
## Returns the damage to deal now (0 while banked).
static func glass_bank(enemy: Enemy, raw: float, src: Player, gid: String) -> float:
    if _glass.is_empty() and gid != "glass_of_ages":
        return raw
    var t := now()
    var st: Array = _glass.get(enemy, [])
    if not st.is_empty() and t < float(st[0]):
        st[1] = float(st[1]) + raw
        return 0.0
    if gid == "glass_of_ages" and (st.is_empty() or t >= float(st[3])):
        var secs := GLASS_ELITE if (enemy.is_elite or enemy.boss_kind != "") else GLASS_SECS
        enemy.stun(secs)
        _glass[enemy] = [t + secs, raw, src, t + secs + GLASS_COOL]
        note("glass")
        return 0.0
    return raw


## Gun._process of the Glass: banked damage lands when a foe's time runs again.
static func _glass_release() -> void:
    var t := now()
    for e in _glass.keys():
        var st: Array = _glass[e]
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            if t >= float(st[3]):
                _glass.erase(e)
            continue
        if float(st[1]) > 0.0 and t >= float(st[0]):
            var dmg := float(st[1])
            st[1] = 0.0
            Elements.nova.emit(e.global_position, e.radius * 2.5, Color(0.7, 0.75, 1.0, 0.7))
            var src: Player = st[2] if is_instance_valid(st[2]) else null
            Telemetry.begin_shot("glass_of_ages", Element.Kind.VOID)
            e.take_damage(dmg, Color(0.75, 0.8, 1.0), true, src, false)
            Telemetry.end_shot()
        if t >= float(st[3]):
            _glass.erase(e)


## The middle of the biggest pack: the foe with the most others within SKY_RADIUS.
static func _biggest_pack(p: Player) -> Vector2:
    var best := Vector2.INF
    var best_n := 0
    var all := Strike.enemies_in(p.get_tree(), p.global_position, 600.0)
    for e in all:
        var n := 0
        for o in all:
            if e.global_position.distance_squared_to(o.global_position) <= SKY_RADIUS * SKY_RADIUS:
                n += 1
        if n > best_n:
            best_n = n
            best = e.global_position
    return best
