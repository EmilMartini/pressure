class_name RareElite
extends RefCounted
## Rare elites (Emil, 2026-11-11, after WoW's rare spawns): now and then an arena holds one
## named foe that looks different (gold rim and crown, its own tint, 25% bigger) and fights
## harder (an affix plus one pattern of its own, both with a tell of at least 0.5 s). Killing
## it pays a pick of 1 of 2 cards at the room's clear, Rare or better, sometimes a weapon:
## better than the room's own bonus pick (Common or better). Auto-aim treats it like any
## other enemy (decision 21: the closest one first).
##
## How often: about one every 1 to 2 floors. A floor rolls FLOOR_CHANCE; a floor after one
## without a rare always has one. Never in the boss room, the shop, the treasure or the
## challenge rooms; on floor 1 not in the gun-pick arenas. Main.rare_arena holds this floor's
## arena index (Main.floor_arenas_done() when it starts), -1 for none.
##
## Names: PLACEHOLDERS for Emil's review (NPC-writing rule): short, said-out-loud names, one
## pool per region. Shown once, small, over the body as it arrives; nothing else in text.

const FLOOR_CHANCE := 0.55
const SPAWN_AT := 4.0          # s into the arena (a pending rare comes at once when the rest is dead)
const HP_SECS := 8.0           # health: this many seconds of the build's measured damage (P)
const HP_ELITE := 2.5          # at least this many times an elite's base health
## P reads low against a single body (the crowd spreads it), so the rare is also sized by how
## fast this run kills its plain elites: KILL_SECS of that damage (an elite dies in 2 to 3 s).
const KILL_SECS := 7.0
const SIZE := 1.25
const NAME_SECS := 2.6
const SLAM_EVERY := 4.2
const SLAM_WARN := 0.85        # the landing ring fills in for this long (>= 0.5 s: no unfair death)
const SLAM_LEAP := 0.3         # the body flies the last part of the warning
const SLAM_R := 62.0
const SLAM_DMG := 13.0         # share of a 100 HP bar, times the floor's damage multiplier
const NOVA_EVERY := 3.6
const NOVA_WARN := 0.7
const NOVA_SHOTS := 12
const NOVA_SPEED := 150.0
const GOLD := Color(1.0, 0.82, 0.3)
const REWARD_WEAPON := 0.35    # one of the two cards is a weapon (Rare or better)
const REWARD_UP := 0.25        # the cards roll one rarity higher

## [name, tint, pattern]. Placeholder names, for Emil to rename.
const NAMES := {
    "ossuary_gate": [["Old Knuckles", Color(0.92, 0.86, 0.66), "slam"], ["Mother Hollin", Color(0.75, 0.62, 0.86), "nova"], ["Gravel Tom", Color(0.70, 0.68, 0.62), "slam"]],
    "drowned_cistern": [["Sister Brine", Color(0.45, 0.80, 0.82), "nova"], ["Old Gullet", Color(0.50, 0.66, 0.50), "slam"], ["Drip", Color(0.55, 0.72, 0.95), "nova"]],
    "rotting_gardens": [["Mossjaw", Color(0.55, 0.78, 0.35), "slam"], ["Gran Thistle", Color(0.82, 0.55, 0.85), "nova"], ["The Gardener", Color(0.72, 0.62, 0.40), "slam"]],
    "rust_ruins": [["Crankshaft", Color(0.85, 0.50, 0.28), "slam"], ["Iron Molly", Color(0.68, 0.72, 0.78), "nova"], ["Bent Pike", Color(0.75, 0.42, 0.32), "slam"]],
    "frostvault": [["Old Rime", Color(0.78, 0.92, 1.00), "nova"], ["Brittle Jack", Color(0.62, 0.80, 0.95), "slam"], ["Kettle", Color(0.90, 0.95, 1.00), "nova"]],
    "the_forge": [["Slagmouth", Color(1.00, 0.55, 0.22), "slam"], ["Big Bellows", Color(0.92, 0.40, 0.30), "nova"], ["Tongs", Color(0.80, 0.70, 0.55), "slam"]],
    "chapel_of_ash": [["Brother Cinder", Color(0.95, 0.62, 0.40), "nova"], ["Deacon Soot", Color(0.55, 0.52, 0.58), "slam"], ["The Late Vicar", Color(0.85, 0.80, 0.70), "nova"]],
    "the_rift": [["Nobody", Color(0.70, 0.45, 0.98), "nova"], ["Twice", Color(0.55, 0.90, 0.85), "slam"], ["The Quiet One", Color(0.85, 0.85, 0.95), "nova"]],
}

static var _dry := 0           # floors in a row without a rare
static var _elite_dps := 0.0   # damage a second this run puts into its plain elites (smoothed)
static var spawned_run := 0
static var killed_run := 0
## Bot probe --rare-every: every floor has one.
static var force := false


## This floor's rare arena (an index into its arenas), or -1. Main.start_floor calls it.
static func plan_floor(floor_number: int, arenas: int, first_gun_picks: int) -> int:
    if floor_number <= 1:
        _dry = 0
        spawned_run = 0
        killed_run = 0
        _elite_dps = 0.0
    if Main.old_balance:
        return -1
    var has := force or _dry >= 1 or randf() < FLOOR_CHANCE
    if not has:
        _dry += 1
        return -1
    _dry = 0
    # Early enough that the floor's route reaches it; past floor 1's gun picks.
    var lo := first_gun_picks + 1 if floor_number == 1 else 1
    var hi := maxi(lo, mini(arenas - 2, lo + 2))
    return randi_range(lo, hi)


## A plain elite died: how fast this run kills one (Room._on_enemy_died; t0 is Main._clock at
## spawn, game time, so hit-stops and slow motion do not count).
static func note_elite(e: Enemy, now: float) -> void:
    if not e.has_meta("t0"):
        return
    var secs := now - float(e.get_meta("t0")) - Enemy.EMERGE_SECS
    if secs < 0.4:
        return
    var dps := e.max_hp / secs
    _elite_dps = dps if _elite_dps <= 0.0 else lerpf(_elite_dps, dps, 0.35)


static func elite_dps() -> float:
    return _elite_dps


## One name entry for the region, [name, tint, pattern].
static func pick(region_id: String) -> Array:
    var pool: Array = NAMES.get(region_id, NAMES["ossuary_gate"])
    return pool[randi() % pool.size()]


## Turns a freshly spawned elite (in the tree) into the rare. `power` is Main.measured_power().
static func apply(e: Enemy, region_id: String, power: float, diff: int, floor_number: int) -> void:
    var p := pick(region_id)
    var pat := String(p[2])
    var affix := ""
    for i in 6:
        affix = SpawnTable.elite_affix(maxi(diff, 10), floor_number)
        if affix != "" and not (pat == "nova" and affix == "barrage"):
            break
    e.rare = { "name": String(p[0]), "pat": pat, "t": 2.0, "warn": 0.0, "name_t": NAME_SECS, "from": Vector2.ZERO, "to": Vector2.ZERO, "t0": 0.0 }
    e.base_color = p[1]
    e.max_hp = maxf(maxf(e.max_hp * HP_ELITE, power * HP_SECS), _elite_dps * KILL_SECS)
    e.hp = e.max_hp
    e.radius *= SIZE
    e._sprite_scale *= SIZE
    e.scrap_value *= 2
    e.set_affix(affix)
    e._ensure_crisp()
    spawned_run += 1


## Per physics tick, after the body has arrived (Enemy._physics_process).
static func tick(e: Enemy, delta: float) -> void:
    var r: Dictionary = e.rare
    if e.hp <= 0.0 or e.emerge > 0.0:
        return
    r["name_t"] = maxf(0.0, float(r["name_t"]) - delta)
    var w := float(r["warn"])
    if w > 0.0:
        w -= delta
        r["warn"] = w
        if String(r["pat"]) == "slam" and w <= SLAM_LEAP:
            var k := clampf(1.0 - w / SLAM_LEAP, 0.0, 1.0)
            e.global_position = Vector2(r["from"]).lerp(Vector2(r["to"]), k)
            e._squash = 0.5
        if w <= 0.0:
            _strike(e)
        e.queue_redraw()
        return
    r["t"] = float(r["t"]) - delta
    if float(r["t"]) > 0.0:
        return
    var pl := e._nearest_player()
    if pl == null or pl.global_position.distance_to(e.global_position) > 640.0:
        r["t"] = 0.5
        return
    if String(r["pat"]) == "slam":
        var at := pl.global_position
        var rr := e._room_rect()
        if rr.has_area():
            at = Vector2(clampf(at.x, rr.position.x + 40.0, rr.end.x - 40.0), clampf(at.y, rr.position.y + 40.0, rr.end.y - 40.0))
        if e.rings_over(at) >= Enemy.MAX_RINGS:
            r["t"] = 0.6
            return
        r["from"] = e.global_position
        r["to"] = at
        r["warn"] = SLAM_WARN
        r["t"] = SLAM_EVERY
        e._lob_at(at, SLAM_WARN, SLAM_R, SLAM_DMG)   # the ring and its hit (drawn, read by the bots)
    else:
        r["warn"] = NOVA_WARN
        r["t"] = NOVA_EVERY
        Sfx.play("tick")


static func _strike(e: Enemy) -> void:
    var r: Dictionary = e.rare
    if String(r["pat"]) == "slam":
        e.global_position = Vector2(r["to"])
        e._squash = 0.9
        var fx := e._fx()
        if fx != null:
            fx._shake(2.0)
        return
    # Nova: a ring of shots carrying the region's element, with gaps to step through.
    var el := Bestiary.region_element()
    var off := randf() * TAU
    for i in NOVA_SHOTS:
        e._shoot(Vector2.RIGHT.rotated(off + TAU * float(i) / float(NOVA_SHOTS)), NOVA_SPEED, e._projectile_damage(5.0), el, 3.2, 7.0)
    e._squash = 0.8


static func winding_up(e: Enemy) -> bool:
    return not e.rare.is_empty() and float(e.rare.get("warn", 0.0)) > 0.0


## On the body (Enemy._draw): a thick gold rim and a small crown over the head.
static func draw_body(e: Enemy) -> void:
    var rad := e.radius
    e.draw_arc(Vector2.ZERO, rad + 3.0, 0.0, TAU, 40, Color(0.1, 0.06, 0.0, 0.7), 5.0)
    e.draw_arc(Vector2.ZERO, rad + 3.0, 0.0, TAU, 40, GOLD, 2.5)
    var top := Vector2(0, -rad * 1.55 - 6.0)
    var w := 9.0
    var pts := PackedVector2Array([top + Vector2(-w, 6), top + Vector2(-w, -1), top + Vector2(-w * 0.5, 3), top + Vector2(0, -5), top + Vector2(w * 0.5, 3), top + Vector2(w, -1), top + Vector2(w, 6)])
    var outline := PackedVector2Array(pts)
    outline.append(pts[0])
    e.draw_colored_polygon(pts, GOLD)
    e.draw_polyline(outline, Color(0.12, 0.07, 0.0, 0.9), 1.5)
    e.draw_circle(top + Vector2(0, 2.5), 1.6, Color(0.95, 0.25, 0.2))


## On the Crisp layer (Enemy._draw_hostile): the nova's tell and the name, once.
static func draw_hostile(e: Enemy, cv: CanvasItem) -> void:
    var r: Dictionary = e.rare
    if String(r["pat"]) == "nova" and float(r["warn"]) > 0.0 and e.hp > 0.0:
        var k := 1.0 - float(r["warn"]) / NOVA_WARN
        var a := 0.45 + 0.4 * absf(sin(e._fx_t * 18.0))
        var rr := e.radius * (2.4 - 0.8 * k)
        cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 36, Color(Hostile.DARK, 0.8), 5.0)
        cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 36, Color(Hostile.RED, a), 2.0)
    var nt := float(r["name_t"])
    if nt > 0.0 and e.emerge <= 0.0:
        var a2 := clampf(nt / 0.5, 0.0, 1.0)
        var font: Font = Art.FONT_BODY
        var size := 11
        var text := String(r["name"])
        var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
        var at := Vector2(-tw * 0.5, -e.radius * 1.55 - 16.0)
        cv.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.05, 0.02, 0.0, 0.85 * a2))
        cv.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(GOLD, a2))
