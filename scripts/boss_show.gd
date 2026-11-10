class_name BossShow
extends Node2D
## Boss presentation (design/Vision gap analysis.md, slam dunk 1): the entrance, the phase
## change and the death. Pure show: it never changes a boss's numbers. The room adds one when
## the boss fight starts; it lives as the room's child and draws the dimmed lights in world
## space above the bodies (z 60), under the HUD.
##
## Entrance (ENTER_SECS): the party is held and can't be hurt, the boss rises as a
## non-target (Enemy.intro, which reuses `emerge` so nothing aims at it), the camera pans to
## it, the room goes dark around it, the roar lands at REVEAL with a heavy shake and rumble,
## and the HUD shows the big name card. Control returns after ENTER_SECS; the fight clock
## (BossBody.age, Room._boss_secs, telemetry) starts then. After the first sight of a boss
## kind (Progress stat "boss_seen:<kind>") any press skips to the end.
## Phase change: a short freeze, a sting, a flash and a ring in the boss's colour; the music
## crossfades to the next track (Music.boss_phase); the body shows it (Enemy._draw_boss).
## Death: slow motion, a white flash, the body bursts into its element, the music stops, a
## beat of quiet, then the room hands out the spoils and the stairwells light up.

const ENTER_SECS := 2.5
const REVEAL := 0.9           # s into the entrance: the roar, the landing, the ignition
const CAM_BACK := 2.0         # s into the entrance: the camera heads back to the party
const DIM := 0.62             # darkness round the boss at the height of the entrance
const DEATH_SLOW := 0.6       # real seconds of slow motion
const DEATH_BEAT := 1.7       # game seconds from the death to the spoils
const MUSIC_BACK := 2.8       # game seconds from the death to the run music

## The boss's own element: what its body bursts into, its rings and crack glow.
const ELEMENT := {
    "brute_king": Element.Kind.STONE,
    "hive_mother": Element.Kind.POISON,
    "storm_warden": Element.Kind.SHOCK,
    "pyre_lord": Element.Kind.FIRE,
    "void_herald": Element.Kind.VOID,
    "drowned_choir": Element.Kind.WET,
}
## Glow of the cracks and phase light.
const ACCENT := {
    "brute_king": Color(1.0, 0.78, 0.40),
    "hive_mother": Color(0.72, 1.0, 0.32),
    "storm_warden": Color(1.0, 0.95, 0.45),
    "pyre_lord": Color(1.0, 0.45, 0.10),
    "void_herald": Color(0.72, 0.38, 1.0),
    "drowned_choir": Color(0.45, 0.78, 1.0),
}

## Party held still (Player._physics_process) while > 0. A float, never a Callable.
static var hold := 0.0

var room: Room
var boss: Enemy
var kind := ""
var t := 0.0                  # s since the entrance began
var entering := false
var skippable := false
var _revealed := false
var _released := false
var _dim := 0.0               # 0..1 darkness now
var _spot := Vector2.ZERO     # world centre of the light hole
var _tint := Color(0, 0, 0, 0)  # phase light: a coloured wash that fades
var _death_t := -1.0          # >= 0: game seconds since the boss died
var _spoils_done := false
var _music_done := false
var _toll_left := 0
var _waves: Array = []        # shockwaves drawn over the fight: [pos, age (real s), colour, max r, life]
var _shots: Array = []        # --boss-shot captures: [seconds left (real), path]


static func accent(boss_kind: String) -> Color:
    return ACCENT.get(boss_kind, Color(1.0, 0.3, 0.2))


func _init(r: Room, b: Enemy) -> void:
    room = r
    boss = b
    kind = b.boss_kind
    z_index = 60
    z_as_relative = false


## The entrance begins (Room._begin_boss, after the boss is sized).
func enter() -> void:
    entering = true
    t = 0.0
    var key := "boss_seen:" + kind
    skippable = Progress.stat(key) > 0
    Progress.add(key)
    boss.start_intro(ENTER_SECS)
    hold = ENTER_SECS + 0.1
    for pl in room.main.players:
        pl.invuln = maxf(pl.invuln, ENTER_SECS + 0.6)
        pl.velocity = Vector2.ZERO
    _spot = boss.global_position
    room.main.cam_focus = boss.global_position
    room.main.cam_focus_w = 0.0
    Music.stop(0.5)
    Sfx.play("boss_rumble", -2.0)
    _shot(1.7, "entrance")
    if BossBody.log_enabled:
        print("[BOSS-SHOW] entrance kind=%s skippable=%s" % [kind, skippable])


func dying() -> bool:
    return _death_t >= 0.0 and not _spoils_done


## The name card's strength, 0..1 (HUD).
func card() -> float:
    if not entering:
        return 0.0
    return clampf(minf((t - REVEAL + 0.1) / 0.25, (ENTER_SECS - t) / 0.4), 0.0, 1.0)


func epithet() -> String:
    return BossBody.epithet(kind)


func _unhandled_input(event: InputEvent) -> void:
    if not entering or not skippable or t >= CAM_BACK:
        return
    var press: bool = (event is InputEventMouseButton and event.pressed) \
            or (event is InputEventJoypadButton and event.pressed) \
            or (event is InputEventKey and event.pressed and not event.echo)
    if press:
        if not _revealed:
            _reveal()
        t = CAM_BACK
        boss.emerge = minf(boss.emerge, ENTER_SECS - CAM_BACK)
        hold = minf(hold, ENTER_SECS - CAM_BACK + 0.1)


## --boss-shot (real window): capture the entrance card, each phase change and the death.
func _shot(after: float, what: String) -> void:
    if room.main.autotest and OS.get_cmdline_user_args().has("--boss-shot"):
        _shots.append([after, "res://autotest/boss_%s_%s.png" % [kind, what]])


func _process(delta: float) -> void:
    var real := delta / maxf(Engine.time_scale, 0.001)
    for i in range(_shots.size() - 1, -1, -1):
        _shots[i][0] = float(_shots[i][0]) - real
        if float(_shots[i][0]) <= 0.0:
            room.main._screenshot(String(_shots[i][1]))
            _shots.remove_at(i)
    for w in _waves:
        w[1] = float(w[1]) + real
    _waves = _waves.filter(func(w): return float(w[1]) < float(w[4]))
    hold = maxf(0.0, hold - delta)
    _tint.a = maxf(0.0, _tint.a - delta * 0.9)
    var main := room.main
    if entering:
        t += delta
        if is_instance_valid(boss):
            _spot = boss.global_position
            main.cam_focus = _spot
        # Camera: out to the boss in the first 0.6 s, back to the party from CAM_BACK.
        var w := clampf(t / 0.6, 0.0, 1.0)
        if t >= CAM_BACK:
            w = clampf(1.0 - (t - CAM_BACK) / 0.5, 0.0, 1.0)
        main.cam_focus_w = w * w * (3.0 - 2.0 * w)
        _dim = DIM * clampf(minf(t / 0.4, (ENTER_SECS - t) / 0.5), 0.0, 1.0)
        if not _revealed and t >= REVEAL:
            _reveal()
        if _toll_left > 0 and t >= REVEAL + 0.55 * float(3 - _toll_left):
            _toll()
        if t >= ENTER_SECS:
            _release()
    if _death_t >= 0.0:
        _death_t += delta
        _dim = maxf(0.0, _dim - delta * 0.3)
        if not _spoils_done and _death_t >= DEATH_BEAT:
            _spoils_done = true
        if not _music_done and _death_t >= MUSIC_BACK:
            _music_done = true
            Music.play("run", 2.0)
    queue_redraw()


## The roar: the moment the boss is there.
func _reveal() -> void:
    _revealed = true
    var main := room.main
    var at := boss.global_position if is_instance_valid(boss) else _spot
    Sfx.play("boss", 0.0)
    Sfx.play("boss_roar_low", -1.0)
    Sfx.play("boss_rumble", 0.0)
    main.shake(16.0)
    Rumble.boom(1.0)
    var el: int = ELEMENT.get(kind, Element.Kind.FIRE)
    var c := accent(kind)
    Elements.nova.emit(at, boss.radius * 4.0 if is_instance_valid(boss) else 160.0, Color(c, 0.7))
    var fx: Fx = main.fx
    match kind:
        "brute_king":
            # He lands: a ring of dust and bone chips.
            if fx != null:
                for k in 8:
                    var a := TAU * float(k) / 8.0
                    fx.puff(Art.PARTICLES["smoke"], at + Vector2.from_angle(a) * 40.0, Color(0.55, 0.5, 0.42, 0.7), 70.0, 0.9, false, Vector2.from_angle(a) * 60.0)
                fx.pixels(Element.Kind.STONE, at, 40, 220.0, 20.0)
            Sfx.play("die_elite", 0.0)
        "hive_mother":
            if fx != null:
                for k in 6:
                    fx.puff(Art.PARTICLES["smoke"], at + Vector2(randf_range(-50, 50), randf_range(-20, 30)), Color(0.45, 0.62, 0.2, 0.6), 80.0, 1.2, false, Vector2(0, -30))
                fx.pixels(Element.Kind.POISON, at, 40, 180.0, 24.0)
            Sfx.play("rx_poison", 0.0)
        "storm_warden":
            main.flash(Color(0.95, 0.95, 1.0), 0.5, 0.25)
            if fx != null:
                fx.pixels(Element.Kind.SHOCK, at, 40, 240.0, 12.0)
            Sfx.play("react_chain", 0.0)
        "pyre_lord":
            main.flash(Color(1.0, 0.55, 0.2), 0.35, 0.3)
            if fx != null:
                fx.pixels(Element.Kind.FIRE, at, 50, 200.0, 20.0)
                fx.puff(Art.PARTICLES["smoke"], at, Color(1.0, 0.5, 0.15, 0.5), 140.0, 0.6, true, Vector2(0, -40))
            Sfx.play("react_ignition", 0.0)
        "void_herald":
            main.flash(Color(0.55, 0.3, 0.85), 0.35, 0.3)
            if fx != null:
                fx.pixels(Element.Kind.VOID, at, 40, 200.0, 16.0)
            Sfx.play("rx_void", 0.0)
        "drowned_choir":
            _toll_left = 3   # the bell tolls three times
            if fx != null:
                fx.pixels(Element.Kind.WET, at, 40, 160.0, 20.0)
    if BossBody.log_enabled:
        print("[BOSS-SHOW] reveal kind=%s el=%d t=%.2f" % [kind, el, t])


func _toll() -> void:
    _toll_left -= 1
    Sfx.play("boss_toll", -2.0 if _toll_left == 2 else -6.0)
    if is_instance_valid(boss):
        Elements.nova.emit(boss.global_position + Vector2(0, -boss.radius * 1.2), 120.0 + 60.0 * float(2 - _toll_left), Color(1.0, 0.9, 0.55, 0.6))
    room.main.shake(6.0)


## Control returns: the fight clock starts.
func _release() -> void:
    if _released:
        return
    _released = true
    entering = false
    hold = 0.0
    _dim = 0.0
    room.main.cam_focus_w = 0.0
    room.on_show_released()
    if BossBody.log_enabled:
        print("[BOSS-SHOW] control kind=%s t=%.2f" % [kind, t])


## A new phase (BossBody.on_phase).
func phase(n: int) -> void:
    var main := room.main
    var c := accent(kind)
    main.hitstop(0.14, 0.05)
    main.flash(c, 0.28, 0.35)
    main.shake(12.0)
    _tint = Color(c, 0.22)
    Sfx.play("boss_sting", -2.0)
    _shot(0.3, "phase%d" % n)
    if is_instance_valid(boss):
        Elements.nova.emit(boss.global_position, boss.radius * 5.0, Color(c, 0.75))
        _waves.append([boss.global_position, 0.0, c, boss.radius * 7.0, 0.7])
        var fx: Fx = main.fx
        if fx != null:
            fx.pixels(ELEMENT.get(kind, Element.Kind.FIRE), boss.global_position, 30, 200.0, boss.radius * 0.5)
    if BossBody.log_enabled:
        print("[BOSS-SHOW] phase kind=%s n=%d" % [kind, n])


## The boss died (Enemy._die): slow motion, flash, the body bursts, quiet.
func death(at: Vector2, radius: float) -> void:
    if _death_t >= 0.0:
        return
    _death_t = 0.0
    entering = false
    hold = 0.0
    var main := room.main
    main.cam_focus_w = 0.0
    main.hitstop(DEATH_SLOW, 0.25)
    main.flash(Color(1.0, 0.97, 0.9), 0.85, 0.7)
    main.shake(18.0)
    Music.stop(0.15)
    Sfx.play("boss_roar_low", -4.0)
    _shot(0.25, "death")
    # The fight is over: its adds and shots go with it, so the beat is a real breather.
    for en in room.enemies.get_children():
        if en != boss and en is Enemy and not en.is_queued_for_deletion():
            en.vanish()
    for sh in get_tree().get_nodes_in_group("enemy_projectiles"):
        sh.queue_free()
    var el: int = ELEMENT.get(kind, Element.Kind.FIRE)
    var c := accent(kind)
    _tint = Color(c, 0.3)
    # The light goes out round the body for the beat of quiet, and comes back with the spoils.
    _spot = at
    _dim = 0.55
    _waves.append([at, 0.0, Color(1.0, 0.97, 0.9), radius * 4.0, 0.5])
    _waves.append([at, 0.0, c, radius * 10.0, 1.2])
    Elements.nova.emit(at, radius * 6.0, Color(c, 0.8))
    Elements.nova.emit(at, radius * 3.0, Color(1, 1, 1, 0.7))
    var fx: Fx = main.fx
    if fx != null:
        fx.pixels(el, at, 90, 320.0, radius * 0.6)
        for k in 10:
            var a := TAU * float(k) / 10.0 + randf() * 0.3
            fx.puff(Art.PARTICLES["smoke"], at + Vector2.from_angle(a) * radius * 0.8, Color(c.darkened(0.3), 0.55), radius * 1.6, 1.4, false, Vector2.from_angle(a) * 90.0)
        match kind:
            "pyre_lord":
                fx.scorch(at, radius * 5.0)
            "brute_king":
                fx.bones(at, Color(0.86, 0.82, 0.70), 10)
            "storm_warden":
                fx.shards(at, 10, radius * 3.0, Element.Kind.SHOCK)
            "void_herald":
                fx.shards(at, 10, radius * 3.0, Element.Kind.VOID)
    if kind == "drowned_choir":
        # Its water spills over the floor (harmless: plain water).
        var mats := Materials.find(room)
        if mats != null:
            mats.stamp(Element.Kind.WET, at, radius * 3.5, 200)
    if BossBody.log_enabled:
        print("[BOSS-SHOW] death kind=%s el=%d" % [kind, el])


## The spoils are out: the stairwells light up (Room, after _build_pedestals).
func light_stairs(peds: Array) -> void:
    for p in peds:
        var n := p as Node2D
        if n == null:
            continue
        ArtPass.add_light(n, Vector2(0, -8), 240.0, Color(1.0, 0.85, 0.55), 1.1, 0.05, 0.3)
        Elements.nova.emit(n.global_position, 90.0, Color(1.0, 0.85, 0.55, 0.7))
    if not peds.is_empty():
        Sfx.play("path_open", -2.0)


func _exit_tree() -> void:
    hold = 0.0
    if room != null and is_instance_valid(room) and room.main != null:
        room.main.cam_focus_w = 0.0


func _draw() -> void:
    var dark := _dim
    if dark > 0.01:
        # The room goes dark round the boss: a thick ring of shade with a soft inner edge.
        var hole := 150.0 + (boss.radius * 2.0 if is_instance_valid(boss) else 60.0)
        var c := to_local(_spot)
        var outer := 2600.0
        var mid := (hole + 40.0 + outer) * 0.5
        draw_arc(c, mid, 0.0, TAU, 96, Color(0.0, 0.0, 0.02, dark), outer - hole - 40.0)
        for k in 4:
            var r := hole + 5.0 + 10.0 * float(k)
            draw_arc(c, r, 0.0, TAU, 64, Color(0.0, 0.0, 0.02, dark * (0.2 + 0.2 * float(k))), 10.0)
        var a := accent(kind)
        draw_circle(c, hole, Color(a, 0.07 * dark / DIM))
    for w in _waves:
        var k := float(w[1]) / float(w[4])
        var at := to_local(w[0])
        var r := float(w[3]) * (1.0 - pow(1.0 - k, 3.0))
        var col: Color = w[2]
        draw_circle(at, r, Color(col, 0.28 * (1.0 - k)))
        draw_arc(at, r, 0.0, TAU, 64, Color(0.02, 0.0, 0.02, 0.7 * (1.0 - k)), 12.0)
        draw_arc(at, r, 0.0, TAU, 64, Color(col.lightened(0.3), 0.95 * (1.0 - k)), 6.0)
    if _tint.a > 0.01 and room != null:
        draw_rect(Rect2(room.rect.position - global_position - Vector2(200, 200), room.rect.size + Vector2(400, 400)), _tint)


# --- The antechamber -------------------------------------------------------------------------


## A room next to a boss room nobody has cleared: the door to it glows a slow dark red and a
## low rumble comes through it every few seconds (Room, on entering).
static func add_dread(r: Room) -> void:
    if r.main == null or r.data == null:
        return
    for d in r.data.doors.keys():
        var to: Vector2i = r.data.doors[d]["to"]
        if not r.main.rooms.has(to):
            continue
        var rd: RoomData = r.main.rooms[to]
        if rd.type != RoomData.Type.BOSS or rd.cleared or not r.doors.has(d):
            continue
        var door: Node2D = r.doors[d]
        var dread := Dread.new()
        dread.into = -Vector2(d)
        door.add_child(dread)
        ArtPass.add_light(door, -Vector2(d) * 36.0, 230.0, Color(1.0, 0.22, 0.12), 0.8, 0.05, 0.5)


class Dread extends Node2D:
    var into := Vector2.DOWN
    var _t := 0.0
    var _next := 1.2

    func _ready() -> void:
        z_index = 2

    func _process(delta: float) -> void:
        _t += delta
        _next -= delta
        if _next <= 0.0:
            _next = 6.5
            Sfx.play("boss_rumble", -9.0, -1.0, global_position)
            var m := get_tree().current_scene
            if m != null and m.has_method("shake"):
                m.shake(1.5)
        queue_redraw()

    func _draw() -> void:
        # A pool of red light spilling in through the doorway, breathing slowly.
        var k := 0.5 + 0.5 * sin(_t * 1.6)
        var c := into * 40.0
        for i in 4:
            draw_circle(c, 70.0 - 14.0 * float(i), Color(0.9, 0.12, 0.06, (0.05 + 0.05 * k) * (1.0 + 0.4 * float(i)) * 0.5))
