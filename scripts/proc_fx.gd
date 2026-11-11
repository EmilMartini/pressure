class_name ProcFx
extends Node2D
## Procs that light up (2026-11-11, WoW's procs): when an item or weapon effect triggers
## (a chance-on-hit, every Nth hit or swing, an on-kill or on-dodge rule, a synergy rule)
## the weapon in the ring flashes, a short ring and glow open on the player and a short
## synthesized "shing" plays. A proc that empowers the next attack (a timed damage or crit
## buff: Close Shave, Marksman's Monocle, Riposte, Catch Spark, Overheat) also charges the
## guns: they glow until their next volley, which leaves at 1.6x size with a bright muzzle
## ring (Hot Streak / Clearcasting). No text, ever.
##
## Rate limits, so frequent procs never become noise: one item or rule shows at most once
## per ITEM_GAP s, anything at most once per ANY_GAP s, and the sound at most once per
## SOUND_GAP s (empowering procs and drop moments keep their own sounds). Everything is
## counted for the bots ([PROC] line): raw procs, shown, sounded, per minute of game time.
##
## Also here: the drop moment (legendary and epic offers): a beam of the rarity colour, a
## sound, and for a legendary a brief hit-stop that never stacks on the cataclysm moment.
##
## One ProcFx node lives on each player (attach); it draws only while something is lit,
## so an idle one costs nothing.

const ITEM_GAP := 2.0      # s between two shows of the same item / rule
const ANY_GAP := 1.0       # s between any two shows
const SOUND_GAP := 1.5     # s between two proc sounds
const LIFE := 0.28         # s a ring and glow last
const EMPOWER_SCALE := 1.6 # an empowered volley's projectile size
## Buff keys that make the next attack stronger (the empowered-shot look).
const EMPOWER_KEYS := ["dmg", "crit", "crit_dmg", "melee_crit", "vent_shots", "summon_dmg", "fire_rate", "thrown_dmg"]
## Item-trigger events that are never a proc (bookkeeping, not a moment).
const QUIET_EVENTS := ["room_enter", "room_clear"]

## Off with --no-proc-fx (the A/B baseline for the frame-time check): counted, never shown.
static var enabled := true
## Bot counters (Main prints [PROC] at the end of a run).
static var raw := 0
static var shown := 0
static var sounded := 0
static var empowered := 0
static var empower_shots := 0
static var weapon_procs := 0
static var syn_procs := 0
static var _last_item: Dictionary = {}   # key -> msec of game clock when last shown
static var _last_any := -100000
static var _last_sound := -100000
## Drop moments.
static var legend_moments := 0
static var epic_moments := 0
static var drop_stops := 0
static var drop_stops_skipped := 0
static var _last_drop := -100000

var player: Player
var _t := 0.0          # seconds left on the ring and glow
var _col := Color.WHITE
var _big := false


## The ProcFx node of a player, made on first use.
static func of(p: Player) -> ProcFx:
    if p == null or not is_instance_valid(p):
        return null
    var n := p.get_node_or_null("ProcFx")
    if n == null:
        var f := ProcFx.new()
        f.name = "ProcFx"
        f.player = p
        f.z_index = 2
        p.add_child(f)
        return f
    return n as ProcFx


## Game-clock milliseconds (hit-stop and pause slow it, so gaps follow the fight).
static func _now() -> int:
    return int(Elements._clock * 1000.0)


## Is this item trigger a proc worth lighting? Chance and every-N rules, dodges, elite
## kills and empowering buffs; plain on-hit or on-kill rules that fire every time are passive.
static func is_proc(t: Dictionary, event: String, n: int) -> bool:
    if event in QUIET_EVENTS:
        return false
    if t.has("chance") and float(t["chance"]) * float(n) < 0.6:
        return true
    if t.has("every") and int(t["every"]) >= 3:
        return true
    if event in ["perfect_dodge", "elite_kill"]:
        return true
    if String(t.get("do", "")) == "buff" and String(t.get("key", "")) in EMPOWER_KEYS:
        return true
    return false


## An item trigger fired (Items.fire). `item` is the item dictionary, `t` the trigger.
static func item_proc(p: Player, item: Dictionary, t: Dictionary, ctx: Dictionary) -> void:
    raw += 1
    var emp := String(t.get("do", "")) == "buff" and String(t.get("key", "")) in EMPOWER_KEYS
    var col: Color = item.get("color", Color(0, 0, 0, 0)) if item.get("color", null) is Color else Color(0, 0, 0, 0)
    if col.a <= 0.0:
        col = Items.rarity_color(item).lightened(0.25)
    if emp:
        _empower(p, col, float(t.get("secs", 2.0)))
    _show(p, "i:" + String(item.get("id", "")), col, String(ctx.get("gun", "")), emp)


## A synergy rule acted (Items.note_syn).
static func syn_proc(id: String) -> void:
    raw += 1
    syn_procs += 1
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return
    var key := "s:" + id
    var now := _now()
    if now - int(_last_item.get(key, -100000)) < int(ITEM_GAP * 2000.0):
        return   # rules like Storm Lattice act on many hits: check the gap before looking up
    var p := tree.get_first_node_in_group("players") as Player
    if p == null:
        return
    _show(p, key, Items.synergy(id).get("color", Color(1.0, 0.9, 0.6)), "", false)


## A tag resonance acted (the Thrown split at 5, Ground zones reacting at 5).
static func res_proc(p: Player, tag: String, gun_id: String) -> void:
    raw += 1
    _show(p, "r:" + tag, Items.tag_color(tag), gun_id, false)


## A weapon's own every-Nth effect (a jab finisher): the weapon flashes, quietly.
static func weapon_proc(g: Gun) -> void:
    raw += 1
    if not enabled or g == null or not is_instance_valid(g):
        return
    var key := "w:%d" % g.get_instance_id()
    var now := _now()
    if now - int(_last_item.get(key, -100000)) < int(ITEM_GAP * 1000.0):
        return
    _last_item[key] = now
    weapon_procs += 1
    g.proc_flash(g.data.color().lightened(0.3))


static func _show(p: Player, key: String, col: Color, gun_id: String, big: bool) -> void:
    if not enabled or p == null or not is_instance_valid(p) or not p.is_inside_tree():
        return
    var now := _now()
    if now - int(_last_item.get(key, -100000)) < int(ITEM_GAP * 1000.0):
        return
    if now - _last_any < int(ANY_GAP * 1000.0):
        return   # empowering procs too: their weapon glow (Gun.empower) always shows
    _last_item[key] = now
    _last_any = now
    shown += 1
    # The weapon that made the hit flashes; a proc that is not tied to a hit lights them all.
    var lit := false
    for g in p.guns:
        if gun_id != "" and g.data.id != gun_id:
            continue
        g.proc_flash(col)
        lit = true
        if gun_id != "":
            break
    if not lit:
        for g in p.guns:
            g.proc_flash(col)
    var f := of(p)
    if f != null:
        f._light(col, big)
    if now - _last_sound >= int(SOUND_GAP * 1000.0):
        _last_sound = now
        sounded += 1
        Sfx.play_at("proc_big" if big else "proc", p.global_position)


## Charge every gun for one empowered volley inside the buff window.
static func _empower(p: Player, col: Color, secs: float) -> void:
    empowered += 1
    if not enabled:
        return
    for g in p.guns:
        g.empower(col, maxf(1.0, secs))


## A gun fired its empowered volley (Gun.shoot_from / the melee swing).
static func empowered_shot(g: Gun, at: Vector2) -> void:
    empower_shots += 1
    var main: Node = g.player.main() if is_instance_valid(g.player) else null
    if main != null and "fx" in main and main.fx != null:
        main.fx.puff(Art.PARTICLES["light"], at, Color(g.empower_col, 0.9), 64.0, 0.16, true)
        main.fx.ring(at, 26.0, g.empower_col, 0.22)


func _light(col: Color, big: bool) -> void:
    _col = col
    _big = big
    _t = LIFE * (1.4 if big else 1.0)
    set_process(true)
    queue_redraw()


func _ready() -> void:
    set_process(false)


func _process(delta: float) -> void:
    _t -= delta
    if _t <= 0.0:
        _t = 0.0
        set_process(false)
    queue_redraw()


func _draw() -> void:
    if _t <= 0.0:
        return
    var life := LIFE * (1.4 if _big else 1.0)
    var f := 1.0 - _t / life        # 0 -> 1
    var a := (1.0 - f) * Settings.own_fx()
    var r := lerpf(14.0, 46.0 if _big else 34.0, sqrt(f))
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := (90.0 if _big else 64.0) * (0.8 + 0.2 * f)
    draw_texture_rect(glow, Rect2(Vector2(-g, -g) * 0.5, Vector2(g, g)), false, Color(_col, 0.35 * a))
    draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(_col.lightened(0.3), 0.85 * a), 2.5 if _big else 1.5)
    if _big:
        draw_arc(Vector2.ZERO, r * 0.65, 0.0, TAU, 24, Color(1, 1, 1, 0.6 * a), 1.0)


# --- Drop moments ----------------------------------------------------------------


## A legendary or epic offer came into view (Pedestal). Plays the sound and, for a
## legendary, a brief hit-stop and a small zoom punch, unless a hit-stop is already
## running or a cataclysm moment played in the last second. Two offers revealed together
## share one moment (the second one only lights its beam).
static func drop_moment(main: Node, pos: Vector2, rarity: int) -> void:
    var now := Time.get_ticks_msec()
    if rarity >= Items.Rarity.LEGENDARY:
        legend_moments += 1
    else:
        epic_moments += 1
    if now - _last_drop < 1500:
        return
    _last_drop = now
    Sfx.play_at("legend_drop" if rarity >= Items.Rarity.LEGENDARY else "epic_drop", pos)
    if main == null:
        return
    var cata_recent := Elements._clock - FusionFx._moment_t < 1.0
    var busy: bool = main.has_method("hitstop_active") and main.hitstop_active()
    if busy or cata_recent:
        drop_stops_skipped += 1
        return
    if main.has_method("hitstop"):
        drop_stops += 1
        if rarity >= Items.Rarity.LEGENDARY:
            main.hitstop(0.12)
            if main.has_method("zoom_punch"):
                main.zoom_punch(0.035, 0.45)
            Rumble.boom(0.5)
        else:
            main.hitstop(0.05)


static func report() -> String:
    var mins := maxf(Elements._clock / 60.0, 0.01)
    return "[PROC] raw=%d shown=%d sounded=%d empowered=%d empower_shots=%d weapon=%d syn=%d mins=%.1f raw_per_min=%.1f shown_per_min=%.1f sound_per_min=%.1f" % [
        raw, shown, sounded, empowered, empower_shots, weapon_procs, syn_procs, mins,
        float(raw) / mins, float(shown) / mins, float(sounded) / mins]


static func drop_report() -> String:
    return "[DROP-MOMENT] legendary=%d epic=%d stops=%d stops_skipped=%d" % [legend_moments, epic_moments, drop_stops, drop_stops_skipped]
