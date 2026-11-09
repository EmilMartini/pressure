extends Node
## Autoload "Telemetry": anonymous, opt-in gameplay telemetry for balancing.
##
## A run record is a Dictionary { kind: "run", run_id, device_id, build, platform, players,
## classes, start_time, bot, partial, events: [...] }; each event is { t, e, ...fields }
## with t in seconds since the run started (play time: it stops while the tree is paused).
## Events outside a run (tutorial, settings changes) go into a "session" record.
##
## Storage: every record is one JSON line in user://telemetry/runs.jsonl (the open run is
## written as a partial at every floor start, the final record replaces it). The file stays
## under MAX_BYTES by dropping the oldest lines. `export_text()` returns every line.
##
## Upload: only when Settings "telemetry" is "on" and ENDPOINT is not empty. Each stored
## record is POSTed as JSON; lines keep an `uploaded` flag and failed uploads retry on the
## next launch. Bot runs (`main.autotest`) are flagged `bot: true` and never uploaded.
## Nothing here records names, addresses or free text.

## The build label is VERSION + "+" + COMMIT (for example "2026.11.08-p4+1a2b3c4").
## VERSION: bump it by hand with each phase or shared build (date plus phase tag).
## COMMIT: stays "dev" in the repository; the export steps (`.github/workflows/deploy.yml`,
## `tools/export_exe.sh`) stamp the short commit hash into it before exporting.
const VERSION := "2026.11.09-fps3"
const COMMIT := "dev"
const BUILD := VERSION + "+" + COMMIT
## Where finished runs are POSTed (a Cloudflare Worker or Apps Script URL). Empty = local only.
const ENDPOINT := ""
## True for endpoints that cannot answer a CORS preflight (Google Apps Script): the web
## build then sends text/plain without the X-Build header (the build is in the body anyway).
const ENDPOINT_SIMPLE := false

const DIR := "user://telemetry"
const FILE_DEFAULT := "user://telemetry/runs.jsonl"
var FILE := FILE_DEFAULT   # parallel bot instances write runs_<n>.jsonl
const MAX_BYTES := 5 * 1024 * 1024
const WAVE_HP_EVERY := 5.0
const FPS_EVERY := 10.0
const HP_HISTORY := 10
const MATERIAL_NAMES := ["none", "oil", "water", "fire", "ice", "poison", "acid", "blood", "steam", "charged", "ash", "dry_blood", "toxic"]
const SKIP_SETTING_KEYS := ["telemetry_device_id"]

## Set just before a player is hurt by something the attacker argument cannot name
## (enemy shots, props). Cleared every physics frame.
var hurt_hint := ""

var device_id := ""
var _lines: Array = []          # stored records (Dictionaries), oldest first
var _rev := 0                   # bumps on every store, so a late upload reply never marks a newer version

# Current run.
var _run: Dictionary = {}
var _main_ref: WeakRef = null
var _clock := 0.0
var _floor := 0
var _region := ""   # Regions id of the floor (every event with a "floor" also gets "region")
var _floor_t0 := 0.0
var _floor_kills := 0
var _run_kills := 0
var _kills_by_kind_run: Dictionary = {}
var _scrap_earned := 0
var _scrap_spent := 0
var _last_source: String = ""
var _hp_history: Array = []
var _wave_t := 0.0
var _last_us := 0                # Time.get_ticks_usec() at the last _process
var _fps_t := 0.0

# Current room.
var _room_t0 := 0.0
var _room_kills: Dictionary = {}
var _room_hp_lost := 0.0
var _room_elites := 0
var _room_seen: Dictionary = {}     # "kind:id" -> { kind, id, price }
var _room_bought: Dictionary = {}   # "kind:id" -> true
var _reactions_seen: Dictionary = {}   # main._reaction_counts at the last flush

# Damage dealt since the last flush.
var _by_gun: Dictionary = {}
var _by_element: Dictionary = {}
var _by_reaction: Dictionary = {}
var _by_tier: Dictionary = {}       # "t0".."t4" -> damage this flush (tier of the effect that dealt it)
# Tier ladder, per run: fusion and cataclysm counts by name, damage by tier, damage by the
# outermost fusion or cataclysm it came from (DoTs count for whoever set them).
var _fusions_run: Dictionary = {}
var _cataclysms_run: Dictionary = {}
var _fusions_room: Dictionary = {}
var _tier_dmg_run: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var _fusion_dmg_run: Dictionary = {}
var _fus := ""          # outermost fusion / cataclysm being resolved
var _dot: Array = []    # [tier, fusion name] of the DoT ticking now, else empty

# Hit context (set by Projectile._deal_hit and Elements reactions around take_damage).
var _shot_on := false
var _shot_gun := ""
var _shot_el := 0
var _react := ""
var _color_names: Dictionary = {}   # Color html -> element name

# Fights.
var _elites: Dictionary = {}    # enemy instance id -> [t, affix, shield pair]
var _boss: Dictionary = {}      # { id, kind, floor, t0, phase2 }

# Session record (tutorial, settings) and its debounced save.
var _session: Dictionary = {}
var _session_t0 := 0
var _session_dirty := -1.0
var _tut_t := 0

# Upload queue.
var _http: HTTPRequest
var _queue: Array = []          # run ids waiting to upload
var _sending_id := ""
var _sending_rev := -1


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    for k in Element.COLORS.keys():
        var c: Color = Element.COLORS[k]
        _color_names[c.to_html()] = String(Element.NAMES[k])
    # Bot runs keep their records in runs_<n>.jsonl (runs_bot.jsonl without --instance).
    if Main.bot_run():
        var tag := Main._instance_tag()
        FILE = "%s/runs%s.jsonl" % [DIR, tag if tag != "" else "_bot"]
    device_id = String(Settings.get_value("telemetry_device_id"))
    if device_id == "" or device_id == "<null>":
        device_id = _hex(8)
        Settings.set_value("telemetry_device_id", device_id)
    DirAccess.make_dir_recursive_absolute(DIR)
    _load()
    _http = HTTPRequest.new()
    _http.timeout = 20.0
    _http.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(_http)
    _http.request_completed.connect(_on_upload_done)
    retry_pending.call_deferred()


func _exit_tree() -> void:
    if not _run.is_empty():
        _finish_run(false, true)
    _flush_session(false)


func _physics_process(_delta: float) -> void:
    hurt_hint = ""


func _process(delta: float) -> void:
    if _session_dirty >= 0.0:
        _session_dirty -= delta
        if _session_dirty < 0.0 and not _session.is_empty():
            _store(_session)
    if _run.is_empty():
        return
    var main := _main()
    if main == null:
        # The run scene went away without an ending (quit to hub, restart).
        _finish_run(false, true)
        return
    # Real seconds from the wall clock. delta / time_scale overcounted around hit-stops (a
    # frame whose delta was taken at time_scale 1.0 but divided by the 0.05 a hit-stop set
    # mid-frame counts 20 times): bot arena secs read 1.4x their wave, late human floors
    # about 2x. Clamped so a pause (this node does not process while paused) never counts.
    var now_us := Time.get_ticks_usec()
    var dt := clampf(float(now_us - _last_us) / 1000000.0, 0.0, 0.25) if _last_us > 0 else delta
    _last_us = now_us
    _clock += dt
    var room: Node = main.get("current")
    var fighting: bool = room != null and bool(room.get("active"))
    if fighting:
        _wave_t += dt
        if _wave_t >= WAVE_HP_EVERY:
            _wave_t = 0.0
            var pct := _party_hp_pct(main)
            _hp_history.append(pct)
            if _hp_history.size() > HP_HISTORY:
                _hp_history.pop_front()
            event("wave_hp", { "hp_pct": pct, "floor": _floor })
    else:
        _wave_t = 0.0
    _fps_t += dt
    if _fps_t >= FPS_EVERY:
        _fps_t = 0.0
        var fx: Node = main.get("fx")
        var px := 0
        if fx != null and fx.has_method("live_pixels"):
            px = int(fx.live_pixels())
        event("fps", { "fps": Engine.get_frames_per_second(), "enemies": get_tree().get_nodes_in_group("enemies").size(), "pixels": px, "floor": _floor })


# --- Recording -----------------------------------------------------------------


func recording() -> bool:
    return not _run.is_empty()


## Append an event to the open run. Fields must be numbers, bools, ids or lists of them.
func event(e: String, fields: Dictionary = {}) -> void:
    if _run.is_empty():
        return
    var ev := { "t": snappedf(_clock, 0.1), "e": e }
    ev.merge(fields)
    if fields.has("floor") and _region != "" and not fields.has("region"):
        ev["region"] = _region
    (_run["events"] as Array).append(ev)


func run_start(main: Node) -> void:
    if not _run.is_empty():
        _finish_run(false, true)
    _flush_session(true)
    _main_ref = weakref(main)
    _clock = 0.0
    _last_us = 0
    _floor = 0
    _region = ""
    _run_kills = 0
    _kills_by_kind_run = {}
    _scrap_earned = 0
    _scrap_spent = 0
    _last_source = ""
    _hp_history = []
    _wave_t = 0.0
    _fps_t = 0.0
    _elites = {}
    _boss = {}
    _reset_damage()
    _reset_room()
    _reactions_seen = {}
    _fusions_run = {}
    _cataclysms_run = {}
    _tier_dmg_run = [0.0, 0.0, 0.0, 0.0, 0.0]
    _fusion_dmg_run = {}
    var args := OS.get_cmdline_user_args()
    _run = _new_record("run")
    _run["bot"] = bool(main.get("autotest")) or args.has("--start-shot") or args.has("--obstacle-test")
    _update_party(main)
    # The Shrine loadout this run starts with: the active side and rank of every slot
    # with a rank bought, and the survival (revive) ranks.
    var talents: Array = Mastery.active_summary()
    var guns: Array = []
    var classes: Array = []
    for k in Progress.unlocks.keys():
        var key := String(k)
        if key.begins_with("gun:"):
            guns.append(key.substr(4))
        elif key.begins_with("mark:"):
            classes.append(key.substr(5))
    var lo := Loadout.current()
    # "class" keeps its name for old analysis scripts: it is the Mark (old class ids).
    event("run_start", { "class": String(lo["mark"]), "kit": String(lo["kit"]), "relic": String(lo["relic"]), "vow": String(lo["vow"]), "embers_spent": Mastery.spent(), "embers_bank": Mastery.embers,
        "talents": talents, "survival": Mastery.survival, "unlocked_guns": guns, "unlocked_classes": classes })


func floor_start(main: Node) -> void:
    if _run.is_empty():
        return
    if _floor > 0:
        _flush_damage()
        _skipped(main.get("current"))
        _floor_end(main)
    _floor = int(main.get("floor_number"))
    _region = String(main.get("region_id"))
    _floor_t0 = _clock
    _floor_kills = 0
    _update_party(main)
    event("floor_start", { "floor": _floor })
    # A partial every floor, so a crash or a closed tab still leaves data.
    _run["partial"] = true
    _store(_run)
    _queue_upload(String(_run["run_id"]))


func _floor_end(main: Node) -> void:
    var guns: Array = []
    var items: Array = []
    var level := 0
    for p in main.get("players"):
        level = maxi(level, int(p.level))
        for g in p.guns:
            guns.append("%s@%d" % [g.data.id, g.tier])
        for id in p.equipped_item_ids():
            items.append(String(id))
    event("floor_end", { "floor": _floor, "secs": snappedf(_clock - _floor_t0, 0.1), "kills": _floor_kills, "level": level, "guns": guns, "items": items, "hp_pct": _party_hp_pct(main) })


## `award` is the Shrine's payout for the run (Mastery.award): total and breakdown.
func run_end(main: Node, won: bool, award: Dictionary = {}) -> void:
    if _run.is_empty():
        return
    if not won:
        _death(main)
    _finish_run(won, false, award)


func _death(main: Node) -> void:
    var room: Node = main.get("current")
    if not _boss.is_empty():
        _boss_end(main, false)
    # The room you die in never clears, so flush its reactions here (they were lost).
    var counts: Dictionary = main.get("_reaction_counts")
    var reactions: Dictionary = {}
    for k in counts.keys():
        var n := int(counts[k]) - int(_reactions_seen.get(k, 0))
        if n > 0 and not Elements.def_by_name(String(k)).is_empty():
            reactions[String(k)] = n
    _reactions_seen = counts.duplicate()
    if not reactions.is_empty():
        event("death_room_reactions", { "reactions": reactions })
    _flush_damage()
    var guns: Array = []
    var items: Array = []
    var level := 0
    for p in main.get("players"):
        level = maxi(level, int(p.level))
        for g in p.guns:
            guns.append("%s@%d" % [g.data.id, g.tier])
        for id in p.equipped_item_ids():
            items.append(String(id))
    event("death", {
        "floor": _floor,
        "room": _room_type(room),
        "diff": int(main.difficulty()),
        "killer": _last_source if _last_source != "" else "unknown",
        "secs": snappedf(_clock, 0.1),
        "level": level, "guns": guns, "items": items,
        "hp_history": _hp_history.duplicate(),
        "room_kills": _room_kills.duplicate(),
    })


func _finish_run(won: bool, abandoned: bool, award: Dictionary = {}) -> void:
    var main := _main()
    if main != null:
        _flush_damage()
        _skipped(main.get("current"))
        if _floor > 0:
            _floor_end(main)
        _update_party(main)
    var level := 0
    var aim_secs := 0.0
    var auto_secs := 0.0
    if main != null:
        for p in main.get("players"):
            level = maxi(level, int(p.level))
            aim_secs += float(p.aim_secs)
            auto_secs += float(p.auto_secs)
    event("run_end", {
        "won": won, "abandoned": abandoned, "floor": _floor, "route": (main.get("route") as Array).duplicate() if main != null else [], "secs": snappedf(_clock, 0.1),
        "kills": _run_kills, "kills_by_kind": _kills_by_kind_run.duplicate(), "level": level,
        "scrap_total_earned": _scrap_earned, "scrap_spent": _scrap_spent,
        "unlocks": Progress.run_unlocks.duplicate(),
        "embers": int(award.get("total", 0)), "embers_parts": (award.get("parts", {}) as Dictionary).duplicate(),
        "embers_counts": (award.get("counts", {}) as Dictionary).duplicate(), "bounties": (award.get("bounties", []) as Array).duplicate(),
        "discoveries": Progress.run_discoveries.duplicate(),
        "fusions": _fusions_run.duplicate(), "cataclysms": _cataclysms_run.duplicate(),
        "tier_damage": [snappedf(_tier_dmg_run[0], 1.0), snappedf(_tier_dmg_run[1], 1.0), snappedf(_tier_dmg_run[2], 1.0), snappedf(_tier_dmg_run[3], 1.0), snappedf(_tier_dmg_run[4], 1.0)],
        "fusion_damage": _rounded(_fusion_dmg_run),
        "fusion_discoveries": Progress.run_fusion_discoveries.duplicate(),
        # How often players aim themselves (design doc section 7): seconds firing where
        # aimed, and seconds auto-firing with an enemy in reach.
        "aim_mode": Player.aim_mode(), "aim_secs": snappedf(aim_secs, 0.1), "auto_secs": snappedf(auto_secs, 0.1),
    })
    _run["partial"] = false
    var id := String(_run["run_id"])
    _store(_run)
    _run = {}
    _main_ref = null
    _queue_upload(id)


# --- Rooms ---------------------------------------------------------------------


func room_enter(room: Node) -> void:
    if _run.is_empty():
        return
    _reset_room()
    var data: RoomData = room.get("data")
    var main := _main()
    event("room_enter", { "floor": _floor, "type": data.type_name(), "diff": int(main.difficulty()) if main != null else 0, "revisit": data.visited })
    _shop_view(room)


## Offers with a price on show: one shop_view event, and remembered for the skip list.
func _shop_view(room: Node) -> void:
    var data: RoomData = room.get("data")
    var offers: Array = []
    for o in data.stock:
        var od: Dictionary = o
        if od.get("taken", false) or int(od.get("price", 0)) <= 0 or String(od["kind"]) in ["reroll", "stairs", "sigil"]:
            continue
        var key := "%s:%s" % [od["kind"], od.get("id", "")]
        offers.append({ "kind": String(od["kind"]), "id": String(od.get("id", "")), "price": int(od["price"]) })
        _room_seen[key] = { "kind": String(od["kind"]), "id": String(od.get("id", "")), "price": int(od["price"]) }
    if offers.is_empty():
        return
    var main := _main()
    event("shop_view", { "floor": _floor, "room": data.type_name(), "offers": offers, "scrap": int(main.get("scrap")) if main != null else 0 })


func room_exit(room: Node) -> void:
    if _run.is_empty():
        return
    _flush_damage()
    _skipped(room)


func _skipped(room: Node) -> void:
    if room == null or _room_seen.is_empty():
        return
    var left: Array = []
    for key in _room_seen.keys():
        if not _room_bought.has(key):
            left.append(_room_seen[key])
    _room_seen = {}
    if not left.is_empty():
        var data: RoomData = room.get("data")
        event("skipped", { "floor": _floor, "room": data.type_name(), "offers": left })


func room_clear(room: Node) -> void:
    if _run.is_empty():
        return
    var main := _main()
    var data: RoomData = room.get("data")
    var kills := 0
    for k in _room_kills.keys():
        kills += int(_room_kills[k])
    var reactions: Dictionary = {}
    if main != null:
        var counts: Dictionary = main.get("_reaction_counts")
        for k in counts.keys():
            var n := int(counts[k]) - int(_reactions_seen.get(k, 0))
            if n > 0 and not Elements.def_by_name(String(k)).is_empty():
                reactions[String(k)] = n
        _reactions_seen = counts.duplicate()
    event("room_clear", {
        "floor": _floor, "type": data.type_name(), "secs": snappedf(_clock - _room_t0, 0.1),
        "kills": kills, "kills_by_kind": _room_kills.duplicate(), "hp_lost": snappedf(_room_hp_lost, 0.1),
        "elites": _room_elites, "spectacle": snappedf(float(main.spectacle_value()), 0.01) if main != null else 0.0,
        "reactions": reactions, "fusions": _fusions_room.duplicate(),
    })
    _flush_damage()


# --- Kills, elites, bosses -----------------------------------------------------


func kill(e: Node) -> void:
    if _run.is_empty():
        return
    var kind := enemy_label(e)
    _room_kills[kind] = int(_room_kills.get(kind, 0)) + 1
    _kills_by_kind_run[kind] = int(_kills_by_kind_run.get(kind, 0)) + 1
    _floor_kills += 1
    _run_kills += 1
    var id := e.get_instance_id()
    if _elites.has(id):
        var el: Array = _elites[id]
        _elites.erase(id)
        _room_elites += 1
        event("elite", { "floor": _floor, "affix": el[1], "shield_pair": el[2], "secs_to_kill": snappedf(_clock - float(el[0]), 0.1) })
    if not _boss.is_empty() and int(_boss["id"]) == id:
        var main := _main()
        if main != null:
            _boss_end(main, true)


func elite_spawned(e: Node) -> void:
    if _run.is_empty():
        return
    _elites[e.get_instance_id()] = [_clock, String(e.get("affix")), String(e.weakness_name())]


func boss_start(boss: Node) -> void:
    if _run.is_empty() or boss == null:
        return
    _boss = { "id": boss.get_instance_id(), "kind": String(boss.get("boss_kind")), "floor": _floor, "t0": _clock, "phase2": -1.0 }


func boss_phase2(boss: Node) -> void:
    if _boss.is_empty() or boss == null or int(_boss["id"]) != boss.get_instance_id():
        return
    _boss["phase2"] = _clock - float(_boss["t0"])


func _boss_end(main: Node, won: bool) -> void:
    var p2 := float(_boss["phase2"])
    event("boss", {
        "kind": _boss["kind"], "floor": _boss["floor"], "secs": snappedf(_clock - float(_boss["t0"]), 0.1),
        "phase2_at_secs": snappedf(p2, 0.1) if p2 >= 0.0 else null,
        "player_hp_pct_at_end": _party_hp_pct(main), "won": won,
    })
    _boss = {}


# --- Damage --------------------------------------------------------------------


func begin_shot(gun_id: String, element: int) -> void:
    _shot_on = true
    _shot_gun = gun_id
    _shot_el = element


func end_shot() -> void:
    _shot_on = false
    _shot_gun = ""


func begin_reaction(reaction_name: String) -> String:
    var prev := _react
    _react = reaction_name
    return prev


func end_reaction(prev: String) -> void:
    _react = prev


## A fusion or cataclysm is resolving: its damage counts for it (by_reaction) and, per run,
## for the outermost one. Returns what end_fusion restores.
func begin_fusion(fusion_name: String, _tier: int) -> Array:
    var prev := [_react, _fus]
    _react = fusion_name
    if _fus == "":
        _fus = fusion_name
    return prev


func end_fusion(prev: Array) -> void:
    _react = String(prev[0])
    _fus = String(prev[1])


## What a damage-over-time set now should tick under: [tier, outermost fusion].
func dot_tag() -> Array:
    return [Elements.ctx_tier, _fus]


func dot_begin(tag: Array) -> void:
    _dot = tag


func dot_end() -> void:
    _dot = []


## A fusion (tier 3) or cataclysm (tier 4) fired.
func fusion(fusion_name: String, tier: int) -> void:
    var d: Dictionary = _cataclysms_run if tier >= Fusions.TIER_CATACLYSM else _fusions_run
    d[fusion_name] = int(d.get(fusion_name, 0)) + 1
    _fusions_room[fusion_name] = int(_fusions_room.get(fusion_name, 0)) + 1


## Run totals for the bot's [FUSION] line: counts by name per tier, damage by tier and by
## fusion name (since the run started).
func fusion_summary() -> Dictionary:
    return { "fusions": _fusions_run.duplicate(), "cataclysms": _cataclysms_run.duplicate(),
        "tier_dmg": _tier_dmg_run.duplicate(), "fusion_dmg": _fusion_dmg_run.duplicate() }


## Damage an enemy actually lost (overkill trimmed by the caller), attributed to the
## gun, element and reaction in context.
func hit(amount: float, color: Color, flash: bool, source: Node) -> void:
    if _run.is_empty() or amount <= 0.0:
        return
    var tier := Elements.ctx_tier
    var fus := _fus
    if not _dot.is_empty():
        tier = int(_dot[0])
        fus = String(_dot[1])
    tier = clampi(tier, 0, 4)
    _tier_dmg_run[tier] = float(_tier_dmg_run[tier]) + amount
    _by_tier["t%d" % tier] = float(_by_tier.get("t%d" % tier, 0.0)) + amount
    if fus != "":
        _fusion_dmg_run[fus] = float(_fusion_dmg_run.get(fus, 0.0)) + amount
    var gun := ""
    if _shot_on and _shot_gun != "":
        gun = _shot_gun
    elif _shot_on:
        gun = "(item)" if source != null else "(world)"
    elif not flash:
        gun = "(dot)"
    elif source == null:
        gun = "(world)"
    else:
        gun = "(player)"
    _by_gun[gun] = float(_by_gun.get(gun, 0.0)) + amount
    var el := ""
    if _react != "":
        el = "(reaction)"
        _by_reaction[_react] = float(_by_reaction.get(_react, 0.0)) + amount
    elif _shot_on:
        el = String(Element.NAMES.get(_shot_el, "None"))
    else:
        el = String(_color_names.get(color.to_html(), "None"))
    _by_element[el] = float(_by_element.get(el, 0.0)) + amount


func _flush_damage() -> void:
    if _by_gun.is_empty():
        return
    event("damage_dealt", { "floor": _floor, "by_gun": _rounded(_by_gun), "by_element": _rounded(_by_element), "by_reaction": _rounded(_by_reaction), "by_tier": _rounded(_by_tier) })
    _reset_damage()


## What hurt `p`: the hint the damage dealer left (a shot, a prop), else the enemy, else
## the floor material under `p`. Always consumes the hint, so one never outlives its hit
## (a shot that met invulnerability used to label the next floor tick). Player calls this
## once per hit and passes the result to `player_hurt` and its own death recap.
func hurt_source(p: Node, attacker: Node) -> String:
    var source := hurt_hint
    hurt_hint = ""
    if source == "":
        if attacker != null and is_instance_valid(attacker) and attacker is Enemy:
            source = enemy_label(attacker)
        elif attacker == null:
            var mats := Materials.find(p)
            var m := 0
            if mats != null:
                m = mats.material_at((p as Node2D).global_position)
            source = "material:%s" % MATERIAL_NAMES[m] if m > 0 and m < MATERIAL_NAMES.size() else "unknown"
        else:
            source = "unknown"
    return source


## A readable name for a damage source label: "projectile:spitter" -> "Spitter shot".
static func source_name(source: String) -> String:
    var parts := source.split(":")
    var head := parts[0]
    var rest := ":".join(parts.slice(1)) if parts.size() > 1 else ""
    match head:
        "projectile":
            return "%s shot" % source_name(rest)
        "material":
            return "%s floor" % rest.replace("_", " ").capitalize()
        "prop":
            return "Exploding barrel" if rest == "barrel" else rest.replace("_", " ").capitalize()
        "boss":
            return rest.replace("_", " ").capitalize()
        "unknown", "":
            return "Unknown"
    return source.replace("_", " ").capitalize()


func player_hurt(p: Node, amount: float, attacker: Node, source: String = "") -> void:
    if source == "":
        source = hurt_source(p, attacker)
    if _run.is_empty():
        return
    _last_source = source
    _room_hp_lost += amount
    event("damage_taken", { "source": source, "amount": snappedf(amount, 0.1), "floor": _floor, "hp_after": snappedf(maxf(0.0, float(p.get("hp"))), 0.1) })


# --- Shops, picks, gear --------------------------------------------------------


## Called at the top of Room.activate: what the offer was before it changes.
func offer_snapshot(o: Dictionary, room: Node) -> Dictionary:
    if _run.is_empty():
        return {}
    var main := _main()
    var data: RoomData = room.get("data")
    var offered: Array = []
    for other in data.stock:
        var od: Dictionary = other
        if String(od["kind"]) in ["gun", "item", "boon"] and not od.get("taken", false):
            offered.append(String(od.get("id", "")))
    return { "kind": String(o["kind"]), "id": String(o.get("id", "")), "price": int(o.get("price", 0)),
        "scrap": int(main.get("scrap")) if main != null else 0, "offered": offered, "choice": bool(o.get("choice", false)) }


## Called at the end of a successful Room.activate (and by mod_fitted).
func offer_used(snap: Dictionary, room: Node) -> void:
    if _run.is_empty() or snap.is_empty():
        return
    var data: RoomData = room.get("data")
    var kind := String(snap["kind"])
    var id := String(snap["id"])
    var price := int(snap["price"])
    match kind:
        "sigil", "stairs":
            return
        "reroll":
            _scrap_spent += price
            event("reroll", { "floor": _floor, "price": price })
            _shop_view(room)
            return
    _scrap_spent += price
    _room_bought["%s:%s" % [kind, id]] = true
    event("purchase", { "kind": kind, "id": id, "price": price, "floor": _floor, "scrap_before": int(snap["scrap"]), "room": data.type_name() })
    if bool(snap["choice"]):
        event("gun_pick", { "source": "start", "offered": snap["offered"], "picked": id })
    elif price == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE]:
        event("treasure", { "room": data.type_name(), "offered": snap["offered"], "picked": id, "floor": _floor })


## Room._fit_mod: the mod is paid for (scrap already taken), the offer not yet marked.
func mod_fitted(o: Dictionary, room: Node) -> void:
    var snap := offer_snapshot(o, room)
    if snap.is_empty():
        return
    snap["scrap"] = int(snap["scrap"]) + int(snap["price"])
    offer_used(snap, room)


## An arena wave just ended: what was lying on the floor (item pedestals, scrap pieces)
## before the payout and the vacuum. Measures clutter; before the spoils change elites
## left 1 to 5 pedestals and 50 to 900 scrap pieces per late wave.
func wave_end(room: Node, pedestals: int, scrap_pieces: int) -> void:
    var main := _main()
    if main != null and main.get("autotest"):
        var p0 = main.players[0] if not main.players.is_empty() else null
        print("[WAVE] end floor=%d t=%.0f peds=%d scrap_pieces=%d banked=%d level=%d low=%.2f xp_total=%.0f" % [
            _floor, float(main.get("_clock")), pedestals, scrap_pieces, (room.get("banked") as Array).size(),
            int(p0.level) if p0 != null else 0, float(room.get("low_hp")), float(p0.get("xp_total")) if p0 != null else 0.0])
    if _run.is_empty():
        return
    event("wave_end", { "floor": _floor, "pedestals": pedestals, "scrap_pieces": scrap_pieces,
        "banked": (room.get("banked") as Array).size() })


## The wave-end spoils: what the one choice offered (kind:id) and how many elites banked loot.
func spoils_offer(_room: Node, offers: Array, banked: int) -> void:
    if _run.is_empty():
        return
    var ids: Array = []
    for o in offers:
        ids.append("%s:%s" % [String(o.get("kind", "")), String(o.get("id", ""))])
    event("spoils", { "floor": _floor, "offered": ids, "banked": banked })


## Spoils not taken were turned into scrap: "picked" (the rest of the row after a pick) or
## "left" (the party walked out without choosing).
func salvage(ids: Array, scrap: int, reason: String) -> void:
    var main := _main()
    if main != null and main.get("autotest"):
        print("[SALVAGE] floor=%d %s n=%d scrap=%d" % [_floor, reason, ids.size(), scrap])
    if _run.is_empty():
        return
    event("salvage", { "floor": _floor, "ids": ids, "scrap": scrap, "reason": reason })


func levelup(options: Array, picked: int, level: int) -> void:
    if _run.is_empty():
        return
    var offered: Array = []
    for o in options:
        var od: Dictionary = o
        offered.append({ "id": String(od.get("base", od.get("id", ""))), "rarity": int(od.get("rarity", 0)) })
    var pick := ""
    if picked >= 0 and picked < offered.size():
        pick = String(offered[picked]["id"])
    event("levelup", { "offered": offered, "picked": pick, "level": level })


func gun_pick(guns: Array, picked: Node) -> void:
    if _run.is_empty():
        return
    var offered: Array = []
    for g in guns:
        if is_instance_valid(g):
            offered.append(String(g.data.id))
    event("gun_pick", { "source": "mod_target", "offered": offered, "picked": String(picked.data.id) if picked != null and is_instance_valid(picked) else "" })


func equip(id: String, slot: String, replaced: String) -> void:
    event("equip", { "id": id, "slot": slot, "replaced": replaced })


func drop_gun(id: String) -> void:
    event("drop_gun", { "id": id })


func combine(id: String, tier: int) -> void:
    event("combine", { "id": id, "tier": tier })


func vent(element: int, pressure: float) -> void:
    event("vent", { "element": String(Element.NAMES.get(element, "None")), "pressure": snappedf(pressure, 0.1) })


func active_use(id: String) -> void:
    event("active_use", { "id": id })


func prop(p: Node, element: int) -> void:
    if _run.is_empty():
        return
    var kind := String(p.get("kind"))
    var result := ""
    if bool(p.get("_gone")):
        result = "explode" if kind == "barrel" else "break"
    else:
        var states: Dictionary = p.get("states")
        var keys: Array = states.keys()
        keys.sort()
        result = ",".join(PackedStringArray(keys)) if not keys.is_empty() else "react"
    event("prop", { "kind": kind, "element": String(Element.NAMES.get(element, "None")), "result": result, "floor": _floor })


func scrap_earned(amount: int) -> void:
    if not _run.is_empty():
        _scrap_earned += amount


# --- Session events (outside runs) ---------------------------------------------


func tutorial_step(step: int, step_id: String) -> void:
    var now := Time.get_ticks_msec()
    if step == 0:
        _tut_t = now
    _session_event("tutorial", { "step": step, "id": step_id, "secs": snappedf(float(now - _tut_t) / 1000.0, 0.1) })


func tutorial_end(step: int, skipped: bool) -> void:
    var secs := snappedf(float(Time.get_ticks_msec() - _tut_t) / 1000.0, 0.1)
    if skipped:
        _session_event("tutorial_skipped", { "at_step": step, "secs": secs })
    else:
        _session_event("tutorial_done", { "secs": secs })
    _flush_session(true)


func setting_changed(key: String, value: Variant) -> void:
    if key in SKIP_SETTING_KEYS:
        return
    if not (value is bool or value is float or value is int or (key == "telemetry" and value is String)):
        return
    if value is float:
        value = snappedf(float(value), 0.01)
    var fields := { "key": key, "value": value }
    if not _run.is_empty():
        event("settings_change", fields)
    else:
        _session_event("settings_change", fields)
    if key == "telemetry" and String(value) == "on":
        retry_pending()


## Hub activity (station visits, mastery purchases) goes to the session record.
func hub_event(e: String, fields: Dictionary = {}) -> void:
    _session_event(e, fields)


func _session_event(e: String, fields: Dictionary) -> void:
    if _session.is_empty():
        _session = _new_record("session")
        _session_t0 = Time.get_ticks_msec()
    var ev := { "t": snappedf(float(Time.get_ticks_msec() - _session_t0) / 1000.0, 0.1), "e": e }
    ev.merge(fields)
    (_session["events"] as Array).append(ev)
    _session_dirty = 3.0


func _flush_session(upload: bool) -> void:
    if _session.is_empty():
        return
    _session["partial"] = false
    var id := String(_session["run_id"])
    _store(_session)
    _session = {}
    _session_dirty = -1.0
    if upload:
        _queue_upload(id)


# --- Consent, storage, export --------------------------------------------------


## "ask", "on" or "off".
func consent() -> String:
    var v := String(Settings.get_value("telemetry"))
    return v if v in ["ask", "on", "off"] else "ask"


func stored_count() -> int:
    var n := 0
    for rec in _lines:
        if String(rec.get("kind", "")) == "run":
            n += 1
    return n


## Every stored record, one JSON line each (the open run and session included).
func export_text() -> String:
    var out := PackedStringArray()
    for rec in _lines:
        out.append(JSON.stringify(rec))
    if not _run.is_empty() and _find(String(_run["run_id"])) < 0:
        out.append(JSON.stringify(_run))
    if not _session.is_empty() and _find(String(_session["run_id"])) < 0:
        out.append(JSON.stringify(_session))
    return "\n".join(out) + ("\n" if not out.is_empty() else "")


## Save the export where a person can find it. Web: a browser download. Desktop: the
## Downloads folder (or the user data folder). Returns a short line to show.
func export_file() -> String:
    var text := export_text()
    var file_name := "pressure_playdata_%s.jsonl" % Time.get_datetime_string_from_system(true).replace(":", "-").replace("T", "_")
    if OS.has_feature("web"):
        JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "application/x-ndjson")
        return "downloaded %s" % file_name
    var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
    if dir == "" or not DirAccess.dir_exists_absolute(dir):
        dir = ProjectSettings.globalize_path(DIR)
    var path := dir.path_join(file_name)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return "could not write %s" % path
    f.store_string(text)
    f.close()
    return path


func _new_record(kind: String) -> Dictionary:
    return {
        "kind": kind, "run_id": ("s-" if kind == "session" else "") + _hex(8), "device_id": device_id,
        "build": BUILD, "platform": OS.get_name(), "players": 1, "classes": [],
        "start_time": Time.get_datetime_string_from_system(true), "bot": false, "partial": true,
        "uploaded": false, "events": [],
    }


## Switch to another records file (bot runs) and reload from it, so the records already
## loaded from the player's own file are never written into the bot's file.
func use_file(path: String) -> void:
    FILE = path
    _load()


func _load() -> void:
    _lines = []
    if not FileAccess.file_exists(FILE):
        return
    var f := FileAccess.open(FILE, FileAccess.READ)
    if f == null:
        return
    while not f.eof_reached():
        var line := f.get_line().strip_edges()
        if line == "":
            continue
        var parsed: Variant = JSON.parse_string(line)
        if parsed is Dictionary:
            _lines.append(parsed)
    f.close()


func _save() -> void:
    var out := PackedStringArray()
    var total := 0
    # Newest first until the cap; the oldest lines fall off.
    var keep: Array = []
    for i in range(_lines.size() - 1, -1, -1):
        var s := JSON.stringify(_lines[i])
        if total + s.length() + 1 > MAX_BYTES and not keep.is_empty():
            break
        total += s.length() + 1
        keep.push_front(_lines[i])
        out.insert(0, s)
    _lines = keep
    var f := FileAccess.open(FILE, FileAccess.WRITE)
    if f == null:
        push_warning("Telemetry: could not write %s" % FILE)
        return
    f.store_string("\n".join(out) + ("\n" if not out.is_empty() else ""))
    f.close()


## Write a record, replacing an earlier version with the same run_id.
func _store(rec: Dictionary) -> void:
    _rev += 1
    var copy: Dictionary = rec.duplicate(true)
    copy["uploaded"] = false
    copy["_rev"] = _rev
    var i := _find(String(rec["run_id"]))
    if i >= 0:
        _lines[i] = copy
    else:
        _lines.append(copy)
    _save()


func _find(run_id: String) -> int:
    for i in _lines.size():
        if String(_lines[i].get("run_id", "")) == run_id:
            return i
    return -1


# --- Upload --------------------------------------------------------------------


func can_upload() -> bool:
    return ENDPOINT != "" and consent() == "on"


## Queue every stored line that has not reached the endpoint yet (startup, consent given).
func retry_pending() -> void:
    for rec in _lines:
        if not bool(rec.get("uploaded", false)) and not bool(rec.get("bot", false)):
            _queue_upload(String(rec.get("run_id", "")))


func _queue_upload(run_id: String) -> void:
    if not can_upload() or run_id == "" or _queue.has(run_id):
        return
    _queue.append(run_id)
    _pump()


func _pump() -> void:
    if _sending_id != "" or _http == null:
        return
    while not _queue.is_empty():
        var id := String(_queue.pop_front())
        var i := _find(id)
        if i < 0:
            continue
        var rec: Dictionary = _lines[i]
        if bool(rec.get("uploaded", false)) or bool(rec.get("bot", false)) or not can_upload():
            continue
        var body: Dictionary = rec.duplicate(true)
        body.erase("uploaded")
        body.erase("_rev")
        var headers := PackedStringArray()
        if ENDPOINT_SIMPLE and OS.has_feature("web"):
            headers.append("Content-Type: text/plain")
        else:
            headers.append("Content-Type: application/json")
            headers.append("X-Build: %s" % BUILD)
        var err := _http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
        if err != OK:
            _queue.clear()   # try again next launch
            return
        _sending_id = id
        _sending_rev = int(rec.get("_rev", -1))
        return


func _on_upload_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
    var id := _sending_id
    _sending_id = ""
    if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 400:
        var i := _find(id)
        if i >= 0 and int(_lines[i].get("_rev", -1)) == _sending_rev:
            _lines[i]["uploaded"] = true
            _save()
    else:
        _queue.clear()   # endpoint down or offline: stop for now, retry next launch
        return
    _pump()


# --- Helpers -------------------------------------------------------------------


func _main() -> Node:
    if _main_ref == null:
        return null
    var m: Variant = _main_ref.get_ref()
    if m == null or not is_instance_valid(m) or not (m as Node).is_inside_tree():
        return null
    return m


func _update_party(main: Node) -> void:
    var classes: Array = []
    var pl: Array = main.get("players")
    for p in pl:
        classes.append(String(p.get_meta("mark_id", "vagrant")))
    _run["players"] = pl.size()
    _run["classes"] = classes


func _party_hp_pct(main: Node) -> float:
    var sum := 0.0
    var n := 0
    for p in main.get("players"):
        sum += clampf(float(p.hp) / maxf(1.0, float(p.max_hp)), 0.0, 1.0) if p.alive else 0.0
        n += 1
    return snappedf(sum / float(maxi(1, n)), 0.01)


func enemy_label(e: Node) -> String:
    var kind := String(e.get("kind_name"))
    var boss_kind := String(e.get("boss_kind"))
    if kind == "boss" and boss_kind != "":
        return "boss:" + boss_kind
    return kind


func _room_type(room: Node) -> String:
    if room == null:
        return "-"
    var data: RoomData = room.get("data")
    return data.type_name()


func _reset_room() -> void:
    _room_t0 = _clock
    _room_kills = {}
    _room_hp_lost = 0.0
    _room_elites = 0
    _room_seen = {}
    _room_bought = {}
    _fusions_room = {}


func _reset_damage() -> void:
    _by_gun = {}
    _by_element = {}
    _by_reaction = {}
    _by_tier = {}


func _rounded(d: Dictionary) -> Dictionary:
    var out := {}
    for k in d.keys():
        out[k] = snappedf(float(d[k]), 0.1)
    return out


func _hex(bytes: int) -> String:
    var c := Crypto.new()
    return c.generate_random_bytes(bytes).hex_encode()
