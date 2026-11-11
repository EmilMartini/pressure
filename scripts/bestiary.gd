class_name Bestiary
extends RefCounted
## The enemy roster (Core loop reset, "Enemy roster", 2026-11-11): twelve kinds beside the
## classics, each with one clear pattern that forces a decision, drawn in code (16 px
## bitmaps below, tinted like the sheet tiles, with the same dark outline), carrying its
## region's element so your reactions have something to bite on. Enemy calls in at a few
## hooks (configure, _think, _physics_process, _draw, _draw_hostile, take_damage, _die);
## per-body state lives in `Enemy.bx`. SpawnTable.ROSTERS says which region fields which.
##
## Damage numbers are shares of a 100 HP bar before the floor's damage multiplier.

## Per kind: [hp base, hp per difficulty, speed, radius, contact damage base, scrap].
const STATS := {
    "hopper": [30.0, 5.5, 75.0, 11.0, 6.0, 1],
    "burrower": [48.0, 8.5, 70.0, 13.0, 8.0, 2],
    "sentry": [55.0, 9.5, 0.0, 14.0, 6.0, 2],
    "mirror": [44.0, 8.0, 110.0, 12.0, 8.0, 2],
    "bloater": [36.0, 6.5, 62.0, 13.0, 6.0, 1],
    "orbiter": [16.0, 3.0, 220.0, 8.0, 4.0, 1],
    "ricochet": [50.0, 9.0, 95.0, 13.0, 10.0, 3],
    "nest": [80.0, 14.0, 0.0, 18.0, 8.0, 3],
    "ghost": [24.0, 4.8, 95.0, 11.0, 7.0, 1],
    "tarcrawler": [42.0, 7.5, 55.0, 12.0, 7.0, 1],
    "bell": [60.0, 10.0, 45.0, 15.0, 6.0, 3],
    "sniper": [34.0, 6.5, 85.0, 11.0, 5.0, 2],
}

## Key threats among them (Core loop reset 8: on the key budget, 1.15x drawn, edge arrows).
const KEY := ["burrower", "sentry", "mirror", "ricochet", "nest", "bell", "sniper"]

const COLORS := {
    "hopper": Color(0.50, 0.78, 0.62),
    "burrower": Color(0.74, 0.58, 0.40),
    "sentry": Color(0.70, 0.74, 0.82),
    "mirror": Color(0.72, 0.86, 0.98),
    "bloater": Color(0.70, 0.82, 0.42),
    "orbiter": Color(1.00, 0.88, 0.55),
    "ricochet": Color(0.86, 0.56, 0.42),
    "nest": Color(0.66, 0.50, 0.58),
    "ghost": Color(0.82, 0.86, 0.96),
    "tarcrawler": Color(0.48, 0.40, 0.36),
    "bell": Color(0.88, 0.74, 0.40),
    "sniper": Color(0.80, 0.50, 0.55),
}

## Silhouettes, 16 x 16, "#" solid. Each reads as its own shape at the 1.5 zoom: a squat
## frog, a drill, a tripod turret, a split diamond, a spotted sac, a winged halo, a spiked
## ball, a hive mound, a sheet ghost, a low slug, a bell, a hooded rifleman.
const SHAPES := {
    "hopper": [
        "................",
        "................",
        "................",
        "....##....##....",
        "...####..####...",
        "...#.##..##.#...",
        "..############..",
        ".##############.",
        ".##############.",
        "..############..",
        "...##########...",
        "..###......###..",
        ".####......####.",
        ".##..........##.",
        "................",
        "................"],
    "burrower": [
        ".......##.......",
        "......####......",
        "......#.##......",
        ".....######.....",
        ".....##.###.....",
        "....########....",
        "...##########...",
        "..############..",
        ".##############.",
        ".###.######.###.",
        ".##..######..##.",
        ".#...######...#.",
        ".....######.....",
        "....##....##....",
        "...##......##...",
        "................"],
    "sentry": [
        "................",
        ".....######.....",
        "....########....",
        "...###....###...",
        "...##..##..##...",
        "...##..##..##...",
        "...###....###...",
        "....########....",
        ".....######.....",
        ".......##.......",
        "......####......",
        ".....##..##.....",
        "....##....##....",
        "...##......##...",
        "..###......###..",
        "................"],
    "mirror": [
        ".......##.......",
        "......####......",
        ".....######.....",
        "....###..###....",
        "...###....###...",
        "..###..##..###..",
        ".###..####..###.",
        "###..######..###",
        ".###..####..###.",
        "..###..##..###..",
        "...###....###...",
        "....###..###....",
        ".....######.....",
        "......####......",
        ".......##.......",
        "................"],
    "bloater": [
        "................",
        "......####......",
        "....########....",
        "...##########...",
        "..####.##.####..",
        "..############..",
        ".##.########.##.",
        ".##############.",
        ".#####.###.####.",
        ".##############.",
        "..############..",
        "..##.######.##..",
        "...##########...",
        "....########....",
        "......#..#......",
        "................"],
    "orbiter": [
        "................",
        "................",
        ".#....####....#.",
        ".##..######..##.",
        ".###.##..##.###.",
        "..####....####..",
        "...##..##..##...",
        "...##.####.##...",
        "...##..##..##...",
        "..####....####..",
        ".###.##..##.###.",
        ".##..######..##.",
        ".#....####....#.",
        "................",
        "................",
        "................"],
    "ricochet": [
        ".......#........",
        "...#...##...#...",
        "....########....",
        "...##########...",
        "..############.#",
        "######....######",
        "..####.##.####..",
        ".#####....#####.",
        "..############..",
        "...##########.#.",
        "..#.########....",
        "....#..##..#....",
        ".......#........",
        "................",
        "................",
        "................"],
    "nest": [
        "................",
        ".......##.......",
        "......####......",
        ".....##..##.....",
        "....###..###....",
        "....########....",
        "...###.##.###...",
        "...##########...",
        "..####.##.####..",
        "..############..",
        ".###.######.###.",
        ".##############.",
        "################",
        "################",
        "................",
        "................"],
    "ghost": [
        "................",
        ".....######.....",
        "....########....",
        "...##########...",
        "..###..##..###..",
        "..###..##..###..",
        "..############..",
        "..############..",
        "..####....####..",
        "..############..",
        "..############..",
        "..############..",
        "..##.###.###.##.",
        "..#...#...#...#.",
        "................",
        "................"],
    "tarcrawler": [
        "................",
        "................",
        "................",
        "................",
        "...##.......#...",
        "..####....###...",
        ".######..#####..",
        "################",
        "################",
        "##.##########.##",
        ".##############.",
        "..#.#.#.#.#.#...",
        "................",
        "................",
        "................",
        "................"],
    "bell": [
        ".......##.......",
        "......####......",
        ".....######.....",
        "....########....",
        "....########....",
        "...##########...",
        "...##########...",
        "...##########...",
        "..############..",
        "..############..",
        ".##############.",
        "################",
        ".......##.......",
        "......####......",
        ".......##.......",
        "................"],
    "sniper": [
        ".....###........",
        "....#####.......",
        "....##.##.......",
        "....#####.......",
        ".....###.......#",
        "...#######....#.",
        "..#########..#..",
        "..##.###.##.#...",
        "..##.###.####...",
        ".....###..#.....",
        ".....###........",
        "....##.##.......",
        "....##.##.......",
        "...##...##......",
        "..##.....##.....",
        "................"],
}

# --- Tuning ------------------------------------------------------------------

const HOP_CROUCH := 0.45
const HOP_AIR := 0.5
const HOP_RANGE := 280.0
const HOP_TRIGGER := 330.0
const HOP_LEAD := 0.55
const HOP_R := 44.0
const HOP_DMG := 9.0

const DIG_SECS := 0.5
const UNDER_SECS := 0.6
const CRACK_SECS := 1.0
const ERUPT_R := 52.0
const ERUPT_DMG := 12.0
const EXPOSED_SECS := 1.4
const BURROW_EVERY := 3.0

const BEAM_LEN := 300.0
const BEAM_WARM := 1.0
const BEAM_ON := 2.6
const BEAM_OFF := 1.6
const BEAM_TURN := 0.45       # rad/s while it burns
const BEAM_DMG := 3.0         # per 0.25 s in the beam
const BEAM_W := 8.0

const MIRROR_TELL := 0.35
const MIRROR_LEN := 220.0
const MIRROR_SPEED := 700.0
const MIRROR_DMG := 11.0
const MIRROR_SHARD_EVERY := 2.8
const MIRROR_SHARD_DMG := 5.0

const POOL_R := 62.0
const POOL_WARN := 0.7
const POOL_LIFE := 3.5
const POOL_DMG := 4.0         # per 0.5 s

const ORBIT_R := 46.0
const ORBIT_SPIN := 2.4
const WARD_TAKEN := 0.4       # a warded ally takes 40% damage

const RICO_TELL := 0.7
const RICO_SPEED := 520.0
const RICO_TRAVEL := 900.0
const RICO_BOUNCES := 2
const RICO_DMG := 13.0
const RICO_STUN := 1.0

const NEST_EVERY := 3.2
const NEST_WARN := 0.8
const NEST_KEEP := 4

const GHOST_FADED := 2.0
const GHOST_SOLID := 1.8
const GHOST_TELL := 0.4
const GHOST_FADED_TAKEN := 0.5

const TAR_EVERY := 0.35
const TAR_LIFE := 7.0
const TAR_R := 15.0
const TAR_SLOW := 0.6         # speed in tar

const BELL_EVERY := 4.2
const BELL_WIND := 0.9
const BELL_REACH := 230.0
const BELL_WAVE_SPEED := 320.0
const BELL_BAND := 16.0
const BELL_DMG := 8.0
const BELL_DAZE := 0.8        # seconds at TAR_SLOW speed after a hit

const SNIPE_AIM := 1.3
const SNIPE_LOCK := 0.4
const SNIPE_COOL := 1.6
const SNIPE_SPEED := 950.0
const SNIPE_DMG := 13.0
const SNIPE_LEN := 900.0

## Carried element: refreshed this long after a reaction took it.
const CARRY_REFRESH := 4.0

static var _tex := {}

## Bot stats per kind (`[ROSTER]` lines): spawned, killed, summed life in seconds.
static var tally := {}


static func has(kind: String) -> bool:
    return STATS.has(kind)


static func texture(kind: String) -> Texture2D:
    if _tex.has(kind):
        return _tex[kind]
    var rows: Array = SHAPES.get(kind, SHAPES["ghost"])
    var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    for y in rows.size():
        var row := String(rows[y])
        for x in mini(16, row.length()):
            if row[x] == "#":
                img.set_pixel(x, y, Color.WHITE)
    var t := ImageTexture.create_from_image(img)
    _tex[kind] = t
    return t


## The region's element a body carries (its resisted element), NONE in the Ossuary Gate.
static func region_element() -> int:
    return int(Regions.active_resists[0]) if not Regions.active_resists.is_empty() else Element.Kind.NONE


## After Enemy.configure.
static func setup(e: Enemy) -> void:
    var bx := e.bx
    bx["carry"] = region_element()
    bx["carry_t"] = 0.0
    bx["born"] = -1.0
    match e.kind_name:
        "hopper":
            bx["cd"] = randf_range(0.6, 1.4)
        "burrower":
            bx["cd"] = randf_range(1.5, 2.5)
            bx["st"] = 0
        "sentry":
            bx["st"] = 2
            bx["t"] = randf_range(0.6, 1.4)
            bx["ang"] = randf() * TAU
        "mirror":
            bx["seen"] = -1
            bx["shard"] = randf_range(1.5, 2.5)
        "ricochet":
            bx["st"] = 0
        "nest":
            bx["t"] = 1.2
            bx["kids"] = []
            bx["pend"] = []
        "ghost":
            bx["solid"] = false
            bx["t"] = randf_range(0.8, GHOST_FADED)
        "tarcrawler":
            bx["t"] = 0.0
            bx["trail"] = []
        "bell":
            bx["t"] = randf_range(1.5, 2.5)
            bx["wind"] = -1.0
            bx["wave"] = -1.0
        "sniper":
            bx["st"] = 0
            bx["t"] = randf_range(0.8, 1.6)
        "orbiter":
            bx["ang"] = randf() * TAU


static func _now() -> float:
    return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


# --- Every frame (before _think) ---------------------------------------------


## Runs from Enemy._physics_process before the emerge branch. True: the body is underground
## (a burrower) and this frame is handled here.
static func hidden_tick(e: Enemy, delta: float) -> bool:
    if e.kind_name != "burrower" or int(e.bx.get("st", 0)) != 2:
        return false
    e._fx_t += delta
    e._tick_shells(delta)
    var bx := e.bx
    bx["t"] = float(bx["t"]) - delta
    var spot: Vector2 = bx.get("spot", Vector2.INF)
    if spot == Vector2.INF:
        # Under the floor, heading for you; then it picks the spot and the cracks show.
        var pl := e._nearest_player()
        if pl != null:
            var to := pl.global_position - e.global_position
            if to.length() > 2.0:
                e.global_position += to.normalized() * minf(to.length(), 260.0 * delta)
        if float(bx["t"]) <= 0.0:
            var at := pl.global_position if pl != null else e.global_position
            var rr := e._room_rect()
            if rr.has_area():
                at = Vector2(clampf(at.x, rr.position.x + 30.0, rr.end.x - 30.0), clampf(at.y, rr.position.y + 30.0, rr.end.y - 30.0))
            if e.rings_over(at) >= Enemy.MAX_RINGS:
                bx["t"] = 0.3
            else:
                bx["spot"] = at
                bx["t"] = CRACK_SECS
                e._lob_at(at, CRACK_SECS, ERUPT_R, ERUPT_DMG)
                Telemetry.hurt_hint = ""
    else:
        e.global_position = e.global_position.move_toward(spot, 400.0 * delta)
        if float(bx["t"]) <= 0.0:
            # Up through the cracks (the shell already did the damage): open to fire a moment.
            e.global_position = spot
            e.emerge = 0.0
            bx["st"] = 3
            bx["t"] = EXPOSED_SECS
            bx.erase("spot")
            if e._sprite != null:
                e._sprite.visible = true
            e._squash = 1.0
            e.stun_time = maxf(e.stun_time, EXPOSED_SECS)
            var fx := e._fx()
            if fx != null:
                fx.puff(Art.PARTICLES["smoke"], spot, Color(0.35, 0.28, 0.2, 0.7), 60.0, 0.5, false, Vector2(0, -20))
            Sfx.play_at("hit_wall", spot, -2.0)
    e.queue_redraw()
    return true


## After the emerge branch, every living frame: carried element, trails, wards, tallies.
static func tick(e: Enemy, delta: float) -> void:
    var bx := e.bx
    if float(bx.get("born", -1.0)) < 0.0:
        bx["born"] = _now()
        _count(e.kind_name, "spawned", 1.0)
    var carry := int(bx.get("carry", Element.Kind.NONE))
    if carry != Element.Kind.NONE and not e.states.has(carry):
        bx["carry_t"] = float(bx["carry_t"]) + delta
        if float(bx["carry_t"]) >= CARRY_REFRESH or float(bx.get("carried", 0.0)) == 0.0:
            bx["carry_t"] = 0.0
            bx["carried"] = 1.0
            e.states[carry] = 9999.0
    match e.kind_name:
        "tarcrawler":
            _tick_tar(e, delta)
        "ghost":
            if e.collision_mask != 0:
                e.collision_mask = 0   # through walls (Enemy._ready set the mask)
            var rr := e._room_rect()
            if rr.has_area():
                var inner := rr.grow(-24.0)
                e.global_position = Vector2(clampf(e.global_position.x, inner.position.x, inner.end.x), clampf(e.global_position.y, inner.position.y, inner.end.y))
        "nest":
            _tick_nest(e, delta)
        "bell":
            _tick_bell(e, delta)
        "sentry":
            _tick_beam(e, delta)


static func _count(kind: String, key: String, v: float) -> void:
    if not tally.has(kind):
        tally[kind] = { "spawned": 0.0, "killed": 0.0, "life": 0.0 }
    tally[kind][key] = float(tally[kind][key]) + v


## `[ROSTER]` per kind this floor; the tally starts again. Classics are counted too.
static func print_tally(floor_number: int) -> void:
    var parts: Array = []
    var kinds := tally.keys()
    kinds.sort()
    for k in kinds:
        var r: Dictionary = tally[k]
        var kills := float(r["killed"])
        parts.append("%s:%d/%d/%.1fs" % [k, int(r["spawned"]), int(kills), float(r["life"]) / maxf(1.0, kills)])
    print("[ROSTER] floor=%d region=%s spawned/killed/life %s" % [floor_number, _region_id(), " ".join(parts)])
    tally.clear()


static func _region_id() -> String:
    var rm := Room.here
    if rm != null and is_instance_valid(rm) and rm.main != null:
        return String(rm.main.region_id)
    return "-"


## Every enemy on its death (classics too, for the kill-time table).
static func on_death(e: Enemy) -> void:
    var born := float(e.bx.get("born", -1.0))
    if born < 0.0 and not has(e.kind_name):
        return
    if born >= 0.0:
        _count(e.kind_name, "killed", 1.0)
        _count(e.kind_name, "life", _now() - born)
    if not has(e.kind_name):
        return
    match e.kind_name:
        "bloater":
            var w := e._world()
            if w != null:
                var pool := HostilePool.new()
                pool.dmg = POOL_DMG * e.damage_mult
                pool.element = int(e.bx.get("carry", Element.Kind.NONE))
                pool.position = e.global_position
                w.add_child.call_deferred(pool)
                _splash(e, e.global_position, POOL_R * 0.7)
        "nest":
            e.bx["pend"] = []


## A plain enemy (classic) only needs its birth noted for the kill-time table.
static func note_alive(e: Enemy) -> void:
    if float(e.bx.get("born", -1.0)) < 0.0:
        e.bx["born"] = _now()
        _count(e.kind_name, "spawned", 1.0)


## Damage this body takes, x (a ward, a ghost between worlds, an exposed burrower).
static func taken_mult(e: Enemy) -> float:
    var m := 1.0
    var w = e.bx.get("warded_by")
    if w != null:
        if is_instance_valid(w) and not (w as Enemy).is_queued_for_deletion() and (w as Enemy).hp > 0.0 \
                and (w as Enemy).bx.get("ward") == e:
            m *= WARD_TAKEN
        else:
            e.bx.erase("warded_by")
    if e.kind_name == "ghost" and not bool(e.bx.get("solid", false)):
        m *= GHOST_FADED_TAKEN
    if e.kind_name == "burrower" and int(e.bx.get("st", 0)) == 3:
        m *= 1.3
    return m


## The body's own element landing on the floor (a hop, a pool): water, ice or oil.
static func _splash(e: Enemy, at: Vector2, r: float) -> void:
    var mats := Materials.find(e)
    if mats == null:
        return
    match int(e.bx.get("carry", Element.Kind.NONE)):
        Element.Kind.WET:
            mats.stamp(Materials.WATER, at, r, 3)
        Element.Kind.ICE:
            mats.stamp(Materials.ICE, at, r * 0.7, 2)
        Element.Kind.OIL:
            mats.stamp(Materials.OIL, at, r * 0.7, 2)


# --- Thinking -----------------------------------------------------------------


## Desired velocity for a roster kind (Enemy._think hands over here).
static func think(e: Enemy, delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    match e.kind_name:
        "hopper":
            return _think_hopper(e, delta, target, dir, dist, mult)
        "burrower":
            return _think_burrower(e, delta, target, dir, dist, mult)
        "sentry":
            return Vector2.ZERO
        "mirror":
            return _think_mirror(e, delta, target, dir, dist, mult)
        "bloater":
            return dir * e.speed * mult
        "orbiter":
            return _think_orbiter(e, delta, target, dir, mult)
        "ricochet":
            return _think_ricochet(e, delta, target, dir, dist, mult)
        "nest":
            return Vector2.ZERO
        "ghost":
            return _think_ghost(e, delta, dir, dist, mult)
        "tarcrawler":
            return dir * e.speed * mult
        "bell":
            if float(e.bx.get("wind", -1.0)) >= 0.0:
                return Vector2.ZERO
            return e._keep_range(delta, dir, dist, 150.0, 260.0) * e.speed * mult
        "sniper":
            return _think_sniper(e, delta, target, dir, dist, mult)
    return dir * e.speed * mult


static func _think_hopper(e: Enemy, delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    var bx := e.bx
    var air := float(bx.get("air", -1.0))
    if air >= 0.0:
        air -= delta
        bx["air"] = air
        if air <= 0.0:
            bx["air"] = -1.0
            bx["cd"] = randf_range(1.6, 2.3)
            e._squash = 1.0
            _splash(e, e.global_position, 36.0)
            return Vector2.ZERO
        return Vector2(bx["vel"])
    if e._crouch_t > 0.0:
        e._crouch_t -= delta
        if e._crouch_t <= 0.0:
            var spot: Vector2 = bx["spot"]
            bx["air"] = HOP_AIR
            bx["vel"] = (spot - e.global_position) / HOP_AIR
            e._contact_cd = HOP_AIR + 0.2   # no body hit in the air: the landing ring is the hit
            e._lunge_t = HOP_AIR
        return Vector2.ZERO
    bx["cd"] = float(bx["cd"]) - delta
    if float(bx["cd"]) <= 0.0 and dist < HOP_TRIGGER:
        # Where you will be: half a second of your run ahead, never past HOP_RANGE.
        var at := target.global_position + target.velocity * HOP_LEAD
        var off := at - e.global_position
        if off.length() > HOP_RANGE:
            at = e.global_position + off.normalized() * HOP_RANGE
        var rr := e._room_rect()
        if rr.has_area():
            at = Vector2(clampf(at.x, rr.position.x + 30.0, rr.end.x - 30.0), clampf(at.y, rr.position.y + 30.0, rr.end.y - 30.0))
        if e.rings_over(at) >= Enemy.MAX_RINGS:
            bx["cd"] = 0.3
        else:
            bx["spot"] = at
            e._crouch_t = HOP_CROUCH
            e._squash = 0.8
            e._lob_at(at, HOP_CROUCH + HOP_AIR, HOP_R, HOP_DMG)
            return Vector2.ZERO
    return dir * e.speed * mult


static func _think_burrower(e: Enemy, delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    var bx := e.bx
    match int(bx.get("st", 0)):
        1:
            # Digging in: a red crouch, then under.
            bx["t"] = float(bx["t"]) - delta
            if float(bx["t"]) <= 0.0:
                bx["st"] = 2
                bx["t"] = UNDER_SECS
                e.emerge = 99.0   # untargetable underground (every gun skips emerging bodies)
                if e._sprite != null:
                    e._sprite.visible = false
                var fx := e._fx()
                if fx != null:
                    fx.puff(Art.PARTICLES["smoke"], e.global_position, Color(0.35, 0.28, 0.2, 0.7), 50.0, 0.4, false, Vector2(0, -10))
            return Vector2.ZERO
        3:
            bx["t"] = float(bx["t"]) - delta
            if float(bx["t"]) <= 0.0:
                bx["st"] = 0
                bx["cd"] = BURROW_EVERY
            return Vector2.ZERO
    bx["cd"] = float(bx["cd"]) - delta
    if float(bx["cd"]) <= 0.0 and dist < 460.0:
        bx["st"] = 1
        bx["t"] = DIG_SECS
        e._crouch_t = DIG_SECS
        e._squash = 0.8
        return Vector2.ZERO
    return dir * e.speed * mult


static func _think_mirror(e: Enemy, delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    var bx := e.bx
    var tell := float(bx.get("tell", -1.0))
    if tell >= 0.0:
        tell -= delta
        bx["tell"] = tell
        if tell <= 0.0:
            bx["tell"] = -1.0
            bx["run"] = MIRROR_LEN / MIRROR_SPEED
            e._lunge_t = MIRROR_LEN / MIRROR_SPEED
            Sfx.play("hit")
        return Vector2.ZERO
    var run := float(bx.get("run", -1.0))
    if run >= 0.0:
        run -= delta
        bx["run"] = run
        if run <= 0.0:
            bx["run"] = -1.0
        return Vector2(bx["dir"]) * MIRROR_SPEED
    var seen := int(bx.get("seen", -1))
    if seen < 0:
        bx["seen"] = target.dashes
    elif target.dashes != seen:
        # You dashed: it copies it, straight at where you went.
        bx["seen"] = target.dashes
        if dist < 520.0:
            bx["dir"] = dir
            bx["tell"] = MIRROR_TELL
            e._crouch_t = MIRROR_TELL
            return Vector2.ZERO
    bx["shard"] = float(bx["shard"]) - delta
    if float(bx["shard"]) <= 0.0 and dist < 520.0:
        bx["shard"] = MIRROR_SHARD_EVERY
        var el := int(bx.get("carry", Element.Kind.NONE))
        for a in [-0.18, 0.18]:
            e._shoot(dir.rotated(a), 230.0, MIRROR_SHARD_DMG, el, 3.0, 6.0)
        e._squash = 0.6
    return e._keep_range(delta, dir, dist, 200.0, 280.0) * e.speed * mult


static func _think_orbiter(e: Enemy, delta: float, target: Player, dir: Vector2, mult: float) -> Vector2:
    var bx := e.bx
    var ally = bx.get("ward")
    if ally == null or not is_instance_valid(ally) or (ally as Enemy).hp <= 0.0 or (ally as Enemy).is_queued_for_deletion():
        ally = null
        bx.erase("ward")
        bx["look"] = float(bx.get("look", 0.0)) - delta
        if float(bx["look"]) <= 0.0:
            bx["look"] = 0.5
            ally = _ward_pick(e)
            if ally != null:
                bx["ward"] = ally
                (ally as Enemy).bx["warded_by"] = e
    if ally == null:
        return dir * e.speed * 0.8 * mult
    var a := ally as Enemy
    bx["ang"] = float(bx["ang"]) + ORBIT_SPIN * delta
    var want := a.global_position + Vector2.from_angle(float(bx["ang"])) * (ORBIT_R + a.radius)
    var to := want - e.global_position
    return to.normalized() * minf(e.speed * mult * 1.4, to.length() / maxf(delta, 0.001))


## The ally an orbiter wards: the nearest unwarded key threat or elite within 360 px, else
## the nearest unwarded body. Never a boss, never another orbiter.
static func _ward_pick(e: Enemy) -> Enemy:
    var best: Enemy = null
    var best_s := INF
    for n in e.get_tree().get_nodes_in_group("enemies"):
        var o := n as Enemy
        if o == null or o == e or not is_instance_valid(o) or o.kind_name in ["orbiter", "boss"] or o.hp <= 0.0 or o.emerge > 0.0:
            continue
        var by = o.bx.get("warded_by")
        if by != null and is_instance_valid(by) and by != e:
            continue
        var d := o.global_position.distance_to(e.global_position)
        if d > 360.0:
            continue
        var s := d - (200.0 if (o.is_elite or o.is_key_threat()) else 0.0)
        if s < best_s:
            best_s = s
            best = o
    return best


static func _think_ricochet(e: Enemy, delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    var bx := e.bx
    match int(bx.get("st", 0)):
        1:
            bx["t"] = float(bx["t"]) - delta
            if float(bx["t"]) <= 0.0:
                bx["st"] = 2
                bx["left"] = RICO_TRAVEL
                bx["bounces"] = 0
                e._lunge_t = 0.2
                Sfx.play("hit")
            return Vector2.ZERO
        2:
            bx["left"] = float(bx["left"]) - RICO_SPEED * delta
            if float(bx["left"]) <= 0.0:
                bx["st"] = 3
                bx["t"] = 1.2
            return Vector2(bx["dir"]) * RICO_SPEED
        3:
            bx["t"] = float(bx["t"]) - delta
            if float(bx["t"]) <= 0.0:
                bx["st"] = 0
            return dir * e.speed * 0.4 * mult
    if dist < 420.0 and dist > 60.0:
        bx["st"] = 1
        bx["t"] = RICO_TELL
        bx["dir"] = dir
        bx["path"] = _bounce_path(e, e.global_position, dir)
        e._crouch_t = RICO_TELL
        return Vector2.ZERO
    return dir * e.speed * mult


## The ricochet's path off the room's walls (global points), for the telegraph.
static func _bounce_path(e: Enemy, from: Vector2, d: Vector2) -> Array:
    var pts: Array = [from]
    var rr := e._room_rect()
    if not rr.has_area():
        pts.append(from + d * RICO_TRAVEL)
        return pts
    var inner := rr.grow(-(e.radius + 2.0))
    var left := RICO_TRAVEL
    var p := from
    var v := d
    for i in RICO_BOUNCES + 1:
        var tx := INF
        var ty := INF
        if v.x > 0.001:
            tx = (inner.end.x - p.x) / v.x
        elif v.x < -0.001:
            tx = (inner.position.x - p.x) / v.x
        if v.y > 0.001:
            ty = (inner.end.y - p.y) / v.y
        elif v.y < -0.001:
            ty = (inner.position.y - p.y) / v.y
        var t := minf(maxf(tx, 0.0), maxf(ty, 0.0))
        if t >= left:
            pts.append(p + v * left)
            return pts
        p += v * t
        left -= t
        pts.append(p)
        if i == RICO_BOUNCES:
            return pts
        if tx < ty:
            v.x = -v.x
        else:
            v.y = -v.y
    return pts


## Enemy._physics_process after move_and_slide: a ricochet that met a wall bounces (twice),
## then is stunned on the third.
static func after_move(e: Enemy) -> void:
    if e.kind_name != "ricochet" or int(e.bx.get("st", 0)) != 2:
        return
    for i in e.get_slide_collision_count():
        var c := e.get_slide_collision(i)
        if not (c.get_collider() is StaticBody2D):
            continue
        var bounces := int(e.bx.get("bounces", 0)) + 1
        e.bx["bounces"] = bounces
        Sfx.play_at("hit_wall", e.global_position, -4.0)
        e._squash = 1.0
        if bounces > RICO_BOUNCES:
            e.bx["st"] = 3
            e.bx["t"] = 1.2
            e.stun_time = maxf(e.stun_time, RICO_STUN)
        else:
            e.bx["dir"] = Vector2(e.bx["dir"]).bounce(c.get_normal()).normalized()
        break


static func _think_ghost(e: Enemy, delta: float, dir: Vector2, dist: float, mult: float) -> Vector2:
    var bx := e.bx
    bx["t"] = float(bx["t"]) - delta
    var solid := bool(bx.get("solid", false))
    if float(bx["t"]) <= 0.0:
        solid = not solid
        bx["solid"] = solid
        bx["t"] = GHOST_SOLID if solid else GHOST_FADED
        if solid:
            e._contact_cd = 0.0
    if not solid:
        e._contact_cd = maxf(e._contact_cd, 0.1)   # between worlds: it cannot touch you
        return dir * e.speed * 0.8 * mult
    return dir * e.speed * 1.45 * mult


## Seconds before the ghost turns solid (0 when solid or far off): its fade-in tell.
static func ghost_tell(e: Enemy) -> float:
    if bool(e.bx.get("solid", false)):
        return 0.0
    var t := float(e.bx.get("t", 9.0))
    return clampf(1.0 - t / GHOST_TELL, 0.0, 1.0) if t < GHOST_TELL else 0.0


static func _think_sniper(e: Enemy, delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    var bx := e.bx
    var rm := Room.here
    var seen := rm == null or not is_instance_valid(rm) or rm.line_clear(e.global_position, target.global_position)
    bx["t"] = float(bx["t"]) - delta
    match int(bx.get("st", 0)):
        1:
            # Aiming: the line follows you; losing sight drops it.
            if not seen or dist > SNIPE_LEN:
                bx["st"] = 0
                bx["t"] = 0.6
                return Vector2.ZERO
            bx["aim"] = dir
            if float(bx["t"]) <= 0.0:
                bx["st"] = 2
                bx["t"] = SNIPE_LOCK
                Sfx.play("tick")
            return Vector2.ZERO
        2:
            if float(bx["t"]) <= 0.0:
                var el := int(bx.get("carry", Element.Kind.NONE))
                e._shoot(Vector2(bx["aim"]), SNIPE_SPEED, SNIPE_DMG, el, 1.2, 7.0)
                bx["st"] = 0
                bx["t"] = SNIPE_COOL
                e._squash = 0.8
            return Vector2.ZERO
    if float(bx["t"]) <= 0.0 and seen and dist < 640.0:
        bx["st"] = 1
        bx["t"] = SNIPE_AIM
        bx["aim"] = dir
        return Vector2.ZERO
    return e._keep_range(delta, dir, dist, 380.0, 520.0) * e.speed * mult


# --- Passive ticks --------------------------------------------------------------


static func _tick_tar(e: Enemy, delta: float) -> void:
    var bx := e.bx
    var trail: Array = bx["trail"]
    var now := _now()
    while not trail.is_empty() and now - float(trail[0][1]) > TAR_LIFE:
        trail.pop_front()
    bx["t"] = float(bx["t"]) - delta
    if float(bx["t"]) <= 0.0 and e.velocity.length() > 5.0:
        bx["t"] = TAR_EVERY
        trail.append([e.global_position, now])
        var mats := Materials.find(e)
        if mats != null:
            mats.stamp(Materials.OIL, e.global_position, 9.0, 1)   # light it: the whole trail burns
    for p in e.get_tree().get_nodes_in_group("players"):
        var pl := p as Player
        if pl == null or not pl.alive:
            continue
        for pt in trail:
            if Vector2(pt[0]).distance_to(pl.global_position) <= TAR_R + pl.radius * 0.5:
                pl.hostile_slow = maxf(pl.hostile_slow, 0.25)
                break


## Tar left by every crawler alive (global points with their age 0..1), for drawing.
static func _tick_nest(e: Enemy, delta: float) -> void:
    var bx := e.bx
    var kids: Array = bx["kids"]
    for i in range(kids.size() - 1, -1, -1):
        var k = kids[i]
        if k == null or not is_instance_valid(k) or (k as Enemy).hp <= 0.0:
            kids.remove_at(i)
    var pend: Array = bx["pend"]
    for i in range(pend.size() - 1, -1, -1):
        pend[i]["t"] = float(pend[i]["t"]) - delta
        if float(pend[i]["t"]) <= 0.0:
            var at: Vector2 = pend[i]["pos"]
            pend.remove_at(i)
            if e._party_near(at, 140.0):
                continue   # never on top of you: that one is lost
            var kid := e._summon("swarmer", at)
            if kid != null:
                kid.scrap_value = 0
                kids.append(kid)
    if e.stun_time > 0.0 or e.frozen_time > 0.0:
        return
    bx["t"] = float(bx["t"]) - delta
    if float(bx["t"]) <= 0.0:
        bx["t"] = NEST_EVERY
        if kids.size() + pend.size() < NEST_KEEP:
            for n in 2:
                var at := e.global_position + Vector2.from_angle(randf() * TAU) * (e.radius + 30.0)
                if not e._party_near(at, 140.0):
                    pend.append({ "pos": at, "t": NEST_WARN })
            e._squash = 0.8


static func _tick_bell(e: Enemy, delta: float) -> void:
    var bx := e.bx
    if e.stun_time > 0.0 or e.frozen_time > 0.0:
        bx["wind"] = -1.0
    var wave := float(bx.get("wave", -1.0))
    if wave >= 0.0:
        wave += BELL_WAVE_SPEED * delta
        bx["wave"] = wave
        var hit: Dictionary = bx["hit"]
        for p in e.get_tree().get_nodes_in_group("players"):
            var pl := p as Player
            if pl == null or not pl.alive or hit.has(pl):
                continue
            var d := pl.global_position.distance_to(e.global_position)
            if absf(d - wave) <= BELL_BAND * 0.5 + pl.radius:
                hit[pl] = true
                var dodging := pl.invuln > 0.0 or pl._dodge_window > 0.0
                Telemetry.hurt_hint = "ring:bell"
                pl.take_damage(BELL_DMG * e.damage_mult, e, e.global_position)
                if not dodging:
                    pl.hostile_slow = maxf(pl.hostile_slow, BELL_DAZE)
        if wave >= BELL_REACH:
            bx["wave"] = -1.0
        e.queue_redraw()
        return
    var wind := float(bx.get("wind", -1.0))
    if wind >= 0.0:
        wind -= delta
        bx["wind"] = wind
        if wind <= 0.0:
            bx["wind"] = -1.0
            bx["wave"] = e.radius
            bx["hit"] = {}
            e._squash = 1.0
            Sfx.play_at("hit_wall", e.global_position, 0.0)
        return
    if e.stun_time > 0.0 or e.frozen_time > 0.0:
        return
    bx["t"] = float(bx["t"]) - delta
    var pl := e._nearest_player()
    if float(bx["t"]) <= 0.0 and pl != null and pl.global_position.distance_to(e.global_position) < BELL_REACH + 80.0:
        bx["t"] = BELL_EVERY
        bx["wind"] = BELL_WIND
        Sfx.play("tick")


static func _tick_beam(e: Enemy, delta: float) -> void:
    var bx := e.bx
    if e.stun_time > 0.0 or e.frozen_time > 0.0:
        return
    var pl := e._nearest_player()
    var want := (pl.global_position - e.global_position).angle() if pl != null else float(bx["ang"])
    var st := int(bx["st"])
    bx["t"] = float(bx["t"]) - delta
    match st:
        0:   # warming: it swings to face you, a thin flicker shows the line
            bx["ang"] = rotate_toward(float(bx["ang"]), want, 1.6 * delta)
            if float(bx["t"]) <= 0.0:
                bx["st"] = 1
                bx["t"] = BEAM_ON
                bx["tick"] = 0.0
        1:   # burning: it sweeps after you, slowly
            bx["ang"] = rotate_toward(float(bx["ang"]), want, BEAM_TURN * delta)
            bx["tick"] = float(bx["tick"]) - delta
            if float(bx["tick"]) <= 0.0:
                bx["tick"] = 0.25
                var a := Vector2.from_angle(float(bx["ang"]))
                var reach := beam_reach(e)
                for p in e.get_tree().get_nodes_in_group("players"):
                    var q := p as Player
                    if q == null or not q.alive:
                        continue
                    var rel := q.global_position - e.global_position
                    var along := rel.dot(a)
                    if along < 0.0 or along > reach:
                        continue
                    if absf(rel.cross(a)) <= BEAM_W * 0.5 + q.radius:
                        Telemetry.hurt_hint = "beam:sentry"
                        q.take_damage(BEAM_DMG * e.damage_mult, e, e.global_position)
            if float(bx["t"]) <= 0.0:
                bx["st"] = 2
                bx["t"] = BEAM_OFF
        2:
            bx["ang"] = rotate_toward(float(bx["ang"]), want, 0.8 * delta)
            if float(bx["t"]) <= 0.0 and pl != null and pl.global_position.distance_to(e.global_position) < BEAM_LEN + 160.0:
                bx["st"] = 0
                bx["t"] = BEAM_WARM
                Sfx.play("tick")
    e.queue_redraw()


## The sentry's beam length: BEAM_LEN, cut short by a wall in the way.
static func beam_reach(e: Enemy) -> float:
    var a := Vector2.from_angle(float(e.bx.get("ang", 0.0)))
    var rm := Room.here
    if rm == null or not is_instance_valid(rm):
        return BEAM_LEN
    var r := BEAM_LEN
    for k in 4:
        if rm.line_clear(e.global_position, e.global_position + a * r):
            return r
        r *= 0.7
    return r


# --- Drawing --------------------------------------------------------------------


## Body tells drawn with the sprite (Enemy._draw): the ward link, the ghost's fade.
static func draw_body(e: Enemy) -> void:
    match e.kind_name:
        "ghost":
            if e._sprite != null:
                var solid := bool(e.bx.get("solid", false))
                var k := ghost_tell(e)
                e._sprite.modulate.a = 1.0 if solid else (0.35 + 0.55 * k)
        "orbiter":
            var w = e.bx.get("ward")
            if w != null and is_instance_valid(w):
                var to := e.to_local((w as Enemy).global_position)
                var pulse := 0.5 + 0.3 * sin(e._fx_t * 6.0)
                e.draw_line(Vector2.ZERO, to, Color(0.05, 0.0, 0.03, 0.6), 4.0)
                e.draw_line(Vector2.ZERO, to, Color(e.base_color, pulse), 2.0)
                e.draw_arc(to, (w as Enemy).radius + 6.0, 0.0, TAU, 28, Color(e.base_color, 0.35 + 0.3 * pulse), 2.5)
        "nest":
            var n := (e.bx.get("kids", []) as Array).size()
            for i in NEST_KEEP:
                var a := -PI * 0.5 + (float(i) - 1.5) * 0.45
                e.draw_circle(Vector2.from_angle(a) * (e.radius + 5.0), 2.0, Color(1.0, 0.85, 0.6, 0.9) if i < n else Color(0.2, 0.15, 0.15, 0.6))


## Hostile tells on the Crisp layer (Enemy._draw_hostile): the red signature.
static func draw_hostile(e: Enemy, cv: CanvasItem) -> void:
    var bx := e.bx
    match e.kind_name:
        "burrower":
            var st := int(bx.get("st", 0))
            if st == 2:
                # A dirt mound moving under the floor, cracks spreading round it.
                cv.draw_circle(Vector2(0, 4), 11.0, Color(0.12, 0.08, 0.05, 0.75))
                for k in 5:
                    var a := TAU * float(k) / 5.0 + e._fx_t * 0.7
                    var p0 := Vector2.from_angle(a) * 6.0
                    var p1 := Vector2.from_angle(a + 0.3) * 16.0
                    cv.draw_line(p0, p1, Color(Hostile.DARK, 0.85), 3.0)
                    cv.draw_line(p0, p1, Color(Hostile.RED, 0.6), 1.0)
        "sentry":
            var st := int(bx.get("st", 2))
            if st == 2 or e.hp <= 0.0:
                return
            var a := Vector2.from_angle(float(bx.get("ang", 0.0)))
            var reach := beam_reach(e)
            var tip := a * reach
            var from := a * e.radius * 0.6
            if st == 0:
                var k := 1.0 - float(bx["t"]) / BEAM_WARM
                var fl := 0.35 + 0.45 * k * absf(sin(e._fx_t * 22.0))
                cv.draw_line(from, tip, Color(Hostile.DARK, 0.5 * fl), 4.0)
                cv.draw_line(from, tip, Color(Hostile.RED, fl), 1.5)
            else:
                var col := _carry_color(e, Color(1.0, 0.55, 0.3))
                cv.draw_line(from, tip, Color(Hostile.DARK, 0.85), BEAM_W + 4.0)
                cv.draw_line(from, tip, Color(Hostile.RED, 0.95), BEAM_W)
                cv.draw_line(from, tip, Color(col.lightened(0.5), 0.9), BEAM_W * 0.4)
                cv.draw_circle(tip, BEAM_W * 0.8, Color(Hostile.RED, 0.8))
        "mirror":
            if float(bx.get("tell", -1.0)) >= 0.0:
                var d := Vector2(bx["dir"])
                var a := 0.45 + 0.45 * absf(sin(e._fx_t * 20.0))
                cv.draw_line(Vector2.ZERO, d * MIRROR_LEN, Color(Hostile.DARK, 0.6 * a), e.radius * 0.6 + 4.0)
                cv.draw_line(Vector2.ZERO, d * MIRROR_LEN, Color(Hostile.RED, a), e.radius * 0.6)
        "ricochet":
            if int(bx.get("st", 0)) == 1:
                var pts: Array = bx.get("path", [])
                var a := 0.45 + 0.4 * absf(sin(e._fx_t * 20.0))
                for i in range(1, pts.size()):
                    var p0 := e.to_local(Vector2(pts[i - 1]))
                    var p1 := e.to_local(Vector2(pts[i]))
                    cv.draw_line(p0, p1, Color(Hostile.DARK, 0.6 * a), e.radius * 0.6 + 4.0)
                    cv.draw_line(p0, p1, Color(Hostile.RED, a * (1.0 - 0.2 * float(i - 1))), e.radius * 0.6)
                    if i < pts.size() - 1:
                        Hostile.dash_ring(cv, p1, 10.0, a, 2.0)
        "nest":
            for pd in bx.get("pend", []):
                var k := 1.0 - float(pd["t"]) / NEST_WARN
                Enemy.draw_spawn_marker(cv, e.to_local(Vector2(pd["pos"])), 7.0, k, e._fx_t)
        "tarcrawler":
            var now := _now()
            for pt in bx.get("trail", []):
                var age := (now - float(pt[1])) / TAR_LIFE
                var at := e.to_local(Vector2(pt[0]))
                cv.draw_circle(at, TAR_R, Color(0.06, 0.04, 0.03, 0.55 * (1.0 - age)))
                cv.draw_circle(at + Vector2(-3, -3), TAR_R * 0.35, Color(0.35, 0.3, 0.25, 0.25 * (1.0 - age)))
        "bell":
            var wind := float(bx.get("wind", -1.0))
            if wind >= 0.0:
                var k := 1.0 - wind / BELL_WIND
                Hostile.dash_ring(cv, Vector2.ZERO, BELL_REACH, 0.35 + 0.5 * k, 2.0)
                cv.draw_arc(Vector2.ZERO, e.radius + 6.0 + 6.0 * k, 0.0, TAU, 32, Color(Hostile.DARK, 0.8), 5.0)
                cv.draw_arc(Vector2.ZERO, e.radius + 6.0 + 6.0 * k, 0.0, TAU, 32, Color(Hostile.RED, 0.5 + 0.5 * absf(sin(e._fx_t * 18.0))), 2.5)
            var wave := float(bx.get("wave", -1.0))
            if wave >= 0.0:
                var fade := clampf((BELL_REACH - wave) / 60.0, 0.2, 1.0)
                cv.draw_arc(Vector2.ZERO, wave, 0.0, TAU, 64, Color(Hostile.DARK, 0.8 * fade), BELL_BAND + 4.0)
                cv.draw_arc(Vector2.ZERO, wave, 0.0, TAU, 64, Color(Hostile.RED, 0.85 * fade), BELL_BAND * 0.6)
                cv.draw_arc(Vector2.ZERO, wave, 0.0, TAU, 64, Color(_carry_color(e, Color(1, 0.9, 0.6)), 0.7 * fade), 2.0)
        "sniper":
            var st := int(bx.get("st", 0))
            if st == 1 or st == 2:
                var d := Vector2(bx["aim"])
                var tip := d * SNIPE_LEN
                if st == 1:
                    var k := 1.0 - float(bx["t"]) / SNIPE_AIM
                    cv.draw_line(Vector2.ZERO, tip, Color(Hostile.DARK, 0.35 * k), 3.0)
                    cv.draw_line(Vector2.ZERO, tip, Color(Hostile.RED, 0.25 + 0.45 * k), 1.0)
                else:
                    var a := 0.6 + 0.4 * absf(sin(e._fx_t * 30.0))
                    cv.draw_line(Vector2.ZERO, tip, Color(Hostile.DARK, 0.8), 6.0)
                    cv.draw_line(Vector2.ZERO, tip, Color(Hostile.RED, a), 3.0)
        "ghost":
            var k := ghost_tell(e)
            if k > 0.0:
                cv.draw_arc(Vector2.ZERO, e.radius + 6.0, 0.0, TAU, 24, Color(Hostile.DARK, 0.7 * k), 4.0)
                cv.draw_arc(Vector2.ZERO, e.radius + 6.0, 0.0, TAU, 24, Color(Hostile.RED, 0.9 * k), 2.0)


static func _carry_color(e: Enemy, fallback: Color) -> Color:
    var c := int(e.bx.get("carry", Element.Kind.NONE))
    return Element.COLORS[c] if c != Element.Kind.NONE else fallback


## Kinds whose tells need the Crisp layer.
static func needs_crisp(kind: String) -> bool:
    return kind in ["burrower", "sentry", "mirror", "ricochet", "nest", "tarcrawler", "bell", "sniper", "ghost", "hopper"]


## Winding up right now (the kite bot and the auto-aim's notion of a telegraph).
static func winding_up(e: Enemy) -> bool:
    var bx := e.bx
    match e.kind_name:
        "sentry":
            return int(bx.get("st", 2)) != 2
        "mirror":
            return float(bx.get("tell", -1.0)) >= 0.0
        "ricochet":
            return int(bx.get("st", 0)) == 1
        "bell":
            return float(bx.get("wind", -1.0)) >= 0.0 or float(bx.get("wave", -1.0)) >= 0.0
        "sniper":
            return int(bx.get("st", 0)) >= 1
        "burrower":
            return int(bx.get("st", 0)) in [1, 2]
    return false


# --- Bots ----------------------------------------------------------------------


## Danger a player would read from this body: [[global centre, radius], ...] to step out of
## (the kite bot pushes away from each), plus a `dash` flag for "about to hit you".
static func bot_threats(e: Enemy, pos: Vector2) -> Dictionary:
    var out := { "rings": [], "dash": false, "from": Vector2.INF }
    var bx := e.bx
    match e.kind_name:
        "bell":
            var wind := float(bx.get("wind", -1.0))
            var wave := float(bx.get("wave", -1.0))
            var d := pos.distance_to(e.global_position)
            if wind >= 0.0 and d < BELL_REACH + 30.0:
                out["rings"].append([e.global_position, BELL_REACH])
            if wave >= 0.0 and d < BELL_REACH + 20.0 and d > wave and d - wave < 70.0:
                out["dash"] = true   # dash through the wave
                out["from"] = e.global_position
        "sentry":
            if int(bx.get("st", 2)) != 2:
                var a := Vector2.from_angle(float(bx.get("ang", 0.0)))
                var rel := pos - e.global_position
                var along := rel.dot(a)
                if along > 0.0 and along < beam_reach(e) + 20.0 and absf(rel.cross(a)) < 60.0:
                    out["rings"].append([e.global_position + a * along, 60.0])
        "sniper":
            if int(bx.get("st", 0)) == 2:
                var a2 := Vector2(bx["aim"])
                var rel2 := pos - e.global_position
                if rel2.dot(a2) > 0.0 and absf(rel2.cross(a2)) < 40.0:
                    out["rings"].append([e.global_position + a2 * rel2.dot(a2), 50.0])
        "mirror":
            if float(bx.get("tell", -1.0)) >= 0.0:
                var a3 := Vector2(bx["dir"])
                var rel3 := pos - e.global_position
                if rel3.dot(a3) > 0.0 and absf(rel3.cross(a3)) < 40.0:
                    out["rings"].append([e.global_position + a3 * rel3.dot(a3), 50.0])
        "ricochet":
            if int(bx.get("st", 0)) == 1:
                var pts: Array = bx.get("path", [])
                for i in range(1, pts.size()):
                    var c := Geometry2D.get_closest_point_to_segment(pos, Vector2(pts[i - 1]), Vector2(pts[i]))
                    if c.distance_to(pos) < 50.0:
                        out["rings"].append([c, 50.0])
    return out


## Every bloater pool alive, as [[global centre, radius]] (the kite bot steps out).
static func pools(tree: SceneTree) -> Array:
    var out: Array = []
    for n in tree.get_nodes_in_group("hostile_pools"):
        if is_instance_valid(n):
            out.append([(n as Node2D).global_position, POOL_R])
    return out


## A bloater's last breath: a circle that fills for POOL_WARN s, then hurts every 0.5 s for
## POOL_LIFE s (the Sower's circle, left on the floor). Its element lands too (Wet water to
## shock, Poison gas to light).
class HostilePool extends Node2D:
    var dmg := 4.0
    var element: int = Element.Kind.NONE
    var age := 0.0
    var _tick := 0.0

    func _ready() -> void:
        add_to_group("hostile_pools")
        z_index = 2
        Crisp.attach(self, _draw_crisp, 3)
        if element == Element.Kind.POISON:
            Cloud.spawn(get_parent(), global_position, Element.Kind.POISON, Bestiary.POOL_R, Bestiary.POOL_WARN + Bestiary.POOL_LIFE, 2.0, null)

    func _physics_process(delta: float) -> void:
        age += delta
        var rm := Room.here
        if rm == null or not is_instance_valid(rm) or not rm.active:
            queue_free()   # the fight is over: nothing on the floor hurts any more
            return
        if age > Bestiary.POOL_WARN + Bestiary.POOL_LIFE:
            queue_free()
            return
        if age < Bestiary.POOL_WARN:
            return
        _tick -= delta
        if _tick > 0.0:
            return
        _tick = 0.5
        for p in get_tree().get_nodes_in_group("players"):
            var pl := p as Player
            if pl != null and pl.alive and pl.global_position.distance_to(global_position) <= Bestiary.POOL_R + pl.radius * 0.5:
                Telemetry.hurt_hint = "pool:bloater"
                pl.take_damage(dmg, null, global_position)

    func _draw_crisp(cv: CanvasItem) -> void:
        var r := Bestiary.POOL_R
        var fill := clampf(age / Bestiary.POOL_WARN, 0.0, 1.0)
        var fade := clampf((Bestiary.POOL_WARN + Bestiary.POOL_LIFE - age) / 0.4, 0.0, 1.0)
        var col: Color = Element.COLORS[element] if element != Element.Kind.NONE else Hostile.RED
        cv.draw_circle(Vector2.ZERO, r * fill, Color(col.darkened(0.3), (0.14 if age < Bestiary.POOL_WARN else 0.24) * fade))
        Hostile.dash_ring(cv, Vector2.ZERO, r, (0.6 if age < Bestiary.POOL_WARN else 0.95) * fade, 2.0 if age < Bestiary.POOL_WARN else 3.0)
