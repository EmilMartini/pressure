class_name GunProbe
extends Node
## Balance probe: `godot --headless --path . res://scenes/main.tscn -- --autotest --gun-probe`
## (add `--fixed-fps 60` before the scene to run faster than real time). Fires each gun
## alone at tier I from a naked Vagrant standing still in an open arena, against dummies
## that cannot move or hurt (grunts with DUMMY_HP health, topped up whenever they drop
## below half so they never die, pinned in place every frame so knockback costs nothing
## here), and prints the damage they lost per second:
##
##   single  one dummy 75 px away
##   pack    eight dummies packed around a point 95 px away (total for the pack)
##
## Close enough that every gun reaches (sweeps and sprays too): range is not measured here,
## it is what the short-reach guns pay for their output.
##
## Everything the gun causes counts (hits, splash, burns and poison it leaves, floor it
## paints, reactions between its own elements). `--gun-probe=a,b,c` probes only those ids;
## `--probe-secs=N` sets the measured seconds per scenario (default 6, after a 1.5 s
## warm-up that lets charge-up and spin-up guns reach their stride).
## One line per gun: [GUN-PROBE] id archetype mechanic element weight single pack budget.
##
## `--gun-shots` (in a real window) instead fires each gun at a loose column of pinned
## dummies to the right and saves res://autotest/gun_<id>.png mid-volley: one picture
## per gun of its mechanic firing (with `--gun-probe=a,b` for some guns only).

const SINGLE_AT := Vector2(75, 0)
const PACK_AT := Vector2(95, 0)
const WARMUP := 1.5
## Like a floor 2 to 3 elite: effects that take a share of max health count at that size.
const DUMMY_HP := 2000.0

var main: Main
var _ids: Array = []
var _secs := 6.0
var _dummies: Array = []
var _spots: Array = []
var _banked := 0.0   # damage taken before a top-up
var _shots := false
var _origin := Vector2.ZERO   # where the player is pinned (lower for shots, clear of toasts)


func _init(p_main: Main) -> void:
    main = p_main
    name = "GunProbe"


static func wanted() -> bool:
    for a in OS.get_cmdline_user_args():
        if a == "--gun-probe" or a.begins_with("--gun-probe="):
            return true
    return false


func _ready() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--gun-probe="):
            for id in a.substr(12).split(","):
                if id != "":
                    _ids.append(id)
        elif a == "--gun-shots":
            _shots = true
        elif a.begins_with("--probe-secs="):
            _secs = maxf(1.0, float(a.substr(13)))
    if _ids.is_empty():
        _ids = Guns.all_ids()
    _run.call_deferred()


func _physics_process(_delta: float) -> void:
    # Pin everyone: the probe measures output, not positioning.
    for i in _dummies.size():
        var e: Enemy = _dummies[i]
        if is_instance_valid(e):
            if e.hp < e.max_hp * 0.5:
                _banked += e.max_hp - e.hp
                e.hp = e.max_hp
            e.global_position = _spots[i]
            e.velocity = Vector2.ZERO
            e.shove_vel = Vector2.ZERO
    if not main.players.is_empty():
        var p: Player = main.players[0]
        p.global_position = _origin
        p.velocity = Vector2.ZERO
        p.hp = p.max_hp
        p.pressure = 0.0


func _run() -> void:
    main.autotest = false   # the bot stays out of it; saves were already redirected
    var centre := Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2)
    main.rooms = main._shot_rooms(centre, { "layout": "open", "size": 1 })
    main.enter_room(centre, Vector2i.ZERO)
    var p: Player = main.players[0]
    p.weight_capacity_base = 99
    p.recalc_stats()
    p.input.force_move = Vector2.ZERO
    p.input.force_fire = false
    await get_tree().create_timer(0.5).timeout
    if Array(OS.get_cmdline_user_args()).any(func(x): return x == "--ground-perf" or x.begins_with("--ground-perf=")):
        await _ground_perf()
        get_tree().quit()
        return
    if _shots:
        await _take_shots()
        await _card_sheet()
        get_tree().quit()
        return
    print("[GUN-PROBE] id archetype mechanic element weight single pack budget family style rarity  (dps, %.0f s per scenario)" % _secs)
    for id in _ids:
        var data := Guns.make(String(id))
        var single := await _measure(String(id), [SINGLE_AT])
        var pack_spots: Array = [PACK_AT]
        for k in 7:
            pack_spots.append(PACK_AT + Vector2.RIGHT.rotated(TAU * float(k) / 7.0) * 38.0)
        var pack := await _measure(String(id), pack_spots)
        print("[GUN-PROBE] %s %s %s %s w%d single=%.1f pack=%.1f budget=%.1f %s %s %s" % [
            id, data.archetype, data.mechanic, Element.NAMES[data.element], data.weight, single, pack, data.dps(),
            data.family, data.style, Items.RARITY_NAMES[data.rarity]])
    get_tree().quit()


func _take_shots() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    _origin = Vector2(0, 150)
    var spots: Array = []
    for k in 7:
        spots.append(_origin + Vector2(62.0 + 26.0 * float(k % 3), -60.0 + 20.0 * float(k)))
    for id in _ids:
        await _measure_setup(String(id), spots)
        var data := Guns.make(String(id))
        var wait := 1.15
        if data.mechanic == "charge":
            wait = data.charge_time + 0.1
        elif data.behaviour == "lob" or data.behaviour == "pool" or data.mechanic == "mine" or data.mechanic == "turret":
            wait = 1.6
        await get_tree().create_timer(wait).timeout
        if data.mechanic in ["melee", "nova", "chain"] and not main.players[0].guns.is_empty():
            # Catch the instant it strikes: these show for a fraction of a second.
            var g: Gun = main.players[0].guns[0]
            for f in 120:
                if g._since_fire < 0.05:
                    break
                await get_tree().process_frame
        await main._screenshot("res://autotest/gun_%s.png" % id)
        print("[GUN-SHOT] %s -> autotest/gun_%s.png" % [id, id])


## The gun cards (what pedestals and the character sheet show) of the probed guns, eight
## to a picture: res://autotest/gun_cards_<n>.png.
func _card_sheet() -> void:
    _reset(main.players[0])
    var layer := CanvasLayer.new()
    layer.layer = 50
    add_child(layer)
    var cv := Control.new()
    cv.set_anchors_preset(Control.PRESET_FULL_RECT)
    layer.add_child(cv)
    var page := 0
    var i := 0
    while i < _ids.size():
        var ids := _ids.slice(i, i + 8)
        cv.draw.connect(func():
            cv.draw_rect(Rect2(Vector2.ZERO, cv.size), Color(0.05, 0.05, 0.07))
            var w := cv.size.x / 4.0 - 12.0
            for k in ids.size():
                var gd := Guns.make(String(ids[k]))
                var opts := { "width": w }
                var h := ItemCard.gun_height(gd, opts)
                var r := Rect2(Vector2(6.0 + float(k % 4) * (w + 12.0), 6.0 + float(k / 4) * (cv.size.y / 2.0)), Vector2(w, h))
                ItemCard.draw_gun(cv, r, gd, opts), CONNECT_ONE_SHOT)
        cv.queue_redraw()
        await get_tree().process_frame
        await get_tree().process_frame
        await main._screenshot("res://autotest/gun_cards_%d.png" % page)
        print("[GUN-SHOT] cards %d -> autotest/gun_cards_%d.png" % [page, page])
        page += 1
        i += 8
    layer.queue_free()


## Damage per second the dummies at `spots` lose to gun `id` alone.
func _measure(id: String, spots: Array) -> float:
    await _measure_setup(id, spots)
    await get_tree().create_timer(WARMUP).timeout
    var start := _lost()
    await get_tree().create_timer(_secs).timeout
    return (_lost() - start) / _secs


## Gun `id` alone on the player, fresh dummies at `spots`.
func _measure_setup(id: String, spots: Array) -> void:
    var p: Player = main.players[0]
    _reset(p)
    p.add_gun(id, false)
    _spots = spots
    _dummies = []
    _banked = 0.0
    for s in spots:
        var e := Enemy.new()
        e.configure("grunt", 1)
        e.max_hp = DUMMY_HP
        e.hp = e.max_hp
        e.speed = 0.0
        e.contact_damage = 0.0
        e.emerge = 0.0
        e.position = s
        main.current.enemies.add_child(e)
        _dummies.append(e)
    await get_tree().process_frame


## `--ground-perf` (Arsenal expansion 2.7): 40 pinned dummies around the player. Script plus
## physics time a frame (1) with no weapon, (2) with a four-weapon ground build at its own
## caps (Ember Halo, Frost Totem, Slick Field, Snap Trap, Spark Trail: rings, totems, fields,
## snares and a trail, every one ticking or armed among the dummies), and (3) a stress stage
## that adds 12 totems and fields and 20 armed snares up to the 40-effect cap. Prints
## [GROUND-PERF]; the build stage is the realistic worst case, the stress stage is not
## reachable in play (two to three ticking zones per weapon at most).
func _ground_perf() -> void:
    var p: Player = main.players[0]
    var spots: Array = []
    for k in 40:
        spots.append(Vector2.RIGHT.rotated(TAU * float(k) / 40.0 * 3.0) * (90.0 + 5.0 * float(k)))
    await _measure_setup("frost_totem", spots)
    for g in p.guns.duplicate():
        p.drop_gun(g)
    await get_tree().create_timer(1.0).timeout
    var empty := await _frame_ms(_secs)
    var build_ids := ["frost_totem", "slick_field", "snap_trap", "ember_halo"]
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--ground-perf="):
            build_ids = Array(a.substr(14).split(","))   # a comparison build (guns)
    for gid in build_ids:
        p.add_gun(gid, false)
    var by := {}
    for g in p.guns:
        by[g.data.style] = g
    await get_tree().create_timer(4.0).timeout
    var build := await _frame_ms(_secs)
    var build_units := GroundZone.count(p)
    var home := Strike.world_parent(p)
    var made := 0
    for k in (32 if by.has("totem") and by.has("field") and by.has("snare") else 0):
        var kind := "totem" if k < 6 else ("field" if k < 12 else "snare")
        var g: Gun = by[kind]
        var at: Vector2 = spots[(k * 7) % spots.size()]
        if kind == "snare":
            at = Vector2(-400.0 - 30.0 * float(k % 10), 240.0 + 30.0 * float(k / 10))   # armed, nothing on them
        var z := GroundZone.new(g, kind, GroundZone.radius_of(g), 600.0)
        home.add_child(z)
        z.global_position = at
        g.bodies.append(z)
        made += 1
    await get_tree().create_timer(1.0).timeout
    var stress := await _frame_ms(_secs)
    print("[GROUND-PERF] dummies=%d empty_ms=%.3f build_ms=%.3f (cap units %d) stress_ms=%.3f (cap units %d) build_extra_ms=%.3f stress_extra_ms=%.3f" % [
        spots.size(), empty, build, build_units, stress, GroundZone.count(p), build - empty, stress - empty])


## Mean script plus physics time a frame over `secs`.
func _frame_ms(secs: float) -> float:
    var t := 0.0
    var n := 0
    var until := Time.get_ticks_msec() + int(secs * 1000.0)
    while Time.get_ticks_msec() < until:
        await get_tree().process_frame
        t += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
        n += 1
    return t / maxf(1.0, float(n)) * 1000.0


func _lost() -> float:
    var t := _banked
    for e in _dummies:
        if is_instance_valid(e):
            t += e.max_hp - e.hp
    return t


## No guns, no shots, no dummies, a clean floor.
func _reset(p: Player) -> void:
    for g in p.guns.duplicate():
        p.drop_gun(g)
    for e in _dummies:
        if is_instance_valid(e):
            e.queue_free()
    _dummies = []
    for grp in [&"gun_fx", &"clouds"]:
        for n in get_tree().get_nodes_in_group(grp):
            n.queue_free()
    for c in main.get_children():
        if c is Projectile:
            c.queue_free()
    if main.current != null and main.current.materials != null:
        main.current.materials.clear()
    Elements.room_reset()
