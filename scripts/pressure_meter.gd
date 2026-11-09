class_name PressureMeter
extends Node
## How hard a floor pushed the player, not how fast it died (difficulty pass, 2026-11-09).
##
## Per floor, player 1 only (the game is designed for one player):
## - fight time: seconds a room was active (enemies up);
## - lt50 / lt25: share of fight time spent below 50% and 25% health;
## - dmg_pm / heal_pm: damage taken and health healed per fight minute, as shares of max health;
## - heal by source (Player.heal's `source`): leech, regen, item, pickup, altar, shrine, stairs,
##   repair, revive, fusion, other;
## - close calls: dropped under 20% health and lived (re-armed above 35%);
## - threat: share of fight time with an enemy shot within THREAT_SHOT px or an enemy body
##   within THREAT_BODY px; moving: share of that threat time spent moving;
## - near misses per fight minute: enemy shots that passed within NEAR_MISS px of a hit;
## - clean rooms: fights cleared without losing health, of all fights cleared;
## - burst1 / burst3: the most damage taken inside any 1 s and 3 s window, as shares of max health.
## Bots print `[PRESSURE]`; every run records a "pressure" telemetry event per floor.

const SAMPLE := 0.1
const THREAT_SHOT := 150.0
const THREAT_BODY := 70.0
const NEAR_MISS := 24.0
const CLOSE_BELOW := 0.2
const CLOSE_REARM := 0.35
const MOVING := 60.0   # px/s: a step, not drift

var main: Node = null
var _floor := 0
var _region := ""
var _flushed := true
var _t := 0.0          # game seconds on this floor
var _sample_t := 0.0
var fight := 0.0
var lt50 := 0.0
var lt25 := 0.0
var threat := 0.0
var moving := 0.0
var dmg := 0.0          # sum of hit / max hp
var dmg_abs := 0.0
var hits := 0
var max_hit := 0.0
var healed: Dictionary = {}   # source -> share of max hp
var close := 0
var _armed := true
var _pending_close := false
var near_miss := 0
var rooms := 0
var clean := 0
var _room_hurt0 := -1.0
var _hurt_log: Array = []     # [t, share of max hp]


func _ready() -> void:
    process_physics_priority = 10


func player() -> Player:
    if main == null or main.players.is_empty():
        return null
    return main.players[0]


func start_floor(n: int, region: String) -> void:
    _floor = n
    _region = region
    _flushed = false
    _t = 0.0
    _sample_t = 0.0
    fight = 0.0
    lt50 = 0.0
    lt25 = 0.0
    threat = 0.0
    moving = 0.0
    dmg = 0.0
    dmg_abs = 0.0
    hits = 0
    max_hit = 0.0
    healed = {}
    close = 0
    _armed = true
    _pending_close = false
    near_miss = 0
    rooms = 0
    clean = 0
    _room_hurt0 = -1.0
    _hurt_log = []


func _physics_process(delta: float) -> void:
    if _flushed or main == null:
        return
    var p := player()
    if p == null or not p.alive:
        return
    _t += delta
    var room: Node = main.current
    if room == null or not bool(room.get("active")):
        return
    fight += delta
    var frac := p.hp / maxf(1.0, p.max_hp)
    if frac < 0.5:
        lt50 += delta
    if frac < 0.25:
        lt25 += delta
    if frac >= CLOSE_REARM:
        _armed = true
        _pending_close = false
    _sample_t -= delta
    if _sample_t > 0.0:
        return
    _sample_t = SAMPLE
    var pos := p.global_position
    var under := false
    for s in get_tree().get_nodes_in_group("enemy_projectiles"):
        if is_instance_valid(s) and (s as Node2D).global_position.distance_squared_to(pos) < THREAT_SHOT * THREAT_SHOT:
            under = true
            break
    if not under:
        for e in get_tree().get_nodes_in_group("enemies"):
            if is_instance_valid(e) and (e as Node2D).global_position.distance_squared_to(pos) < THREAT_BODY * THREAT_BODY:
                under = true
                break
    if under:
        threat += SAMPLE
        if p.velocity.length() > MOVING:
            moving += SAMPLE


func on_hurt(p: Player, amount: float) -> void:
    if _flushed or p != player():
        return
    var share := amount / maxf(1.0, p.max_hp)
    dmg += share
    dmg_abs += amount
    hits += 1
    max_hit = maxf(max_hit, share)
    _hurt_log.append([_t, share])
    var frac := p.hp / maxf(1.0, p.max_hp)
    if _armed and frac < CLOSE_BELOW:
        _armed = false
        _pending_close = true
        close += 1


func on_heal(p: Player, amount: float, source: String) -> void:
    if _flushed or p != player() or amount <= 0.0:
        return
    healed[source] = float(healed.get(source, 0.0)) + amount / maxf(1.0, p.max_hp)


## An enemy shot left play without hitting; `gap` is how far its closest pass was from a hit.
func shot_missed(gap: float) -> void:
    if not _flushed and gap <= NEAR_MISS:
        near_miss += 1


func room_entered() -> void:
    var p := player()
    _room_hurt0 = p.hurt_total if p != null else -1.0


func room_cleared(room: Node) -> void:
    var p := player()
    if _flushed or p == null or _room_hurt0 < 0.0 or room == null:
        return
    rooms += 1
    if p.hurt_total - _room_hurt0 <= 0.01:
        clean += 1


func _burst(window: float) -> float:
    var best := 0.0
    var sum := 0.0
    var i := 0
    for j in _hurt_log.size():
        sum += float(_hurt_log[j][1])
        while float(_hurt_log[j][0]) - float(_hurt_log[i][0]) > window:
            sum -= float(_hurt_log[i][1])
            i += 1
        best = maxf(best, sum)
    return best


func summary(died: bool) -> Dictionary:
    var mins := maxf(fight, 1.0) / 60.0
    var heal_total := 0.0
    var by: Dictionary = {}
    for k in healed.keys():
        heal_total += float(healed[k])
        by[String(k)] = snappedf(float(healed[k]) / mins, 0.001)
    var closes := close - (1 if died and _pending_close else 0)
    return {
        "floor": _floor, "region": _region, "secs": snappedf(_t, 0.1), "fight": snappedf(fight, 0.1),
        "lt50": snappedf(lt50 / maxf(fight, 1.0), 0.001), "lt25": snappedf(lt25 / maxf(fight, 1.0), 0.001),
        "dmg_pm": snappedf(dmg / mins, 0.001), "heal_pm": snappedf(heal_total / mins, 0.001), "heal_by": by,
        "hits": hits, "max_hit": snappedf(max_hit, 0.001),
        "close": closes, "threat": snappedf(threat / maxf(fight, 1.0), 0.001),
        "moving": snappedf(moving / maxf(threat, 0.1), 0.001), "near_miss_pm": snappedf(float(near_miss) / mins, 0.01),
        "rooms": rooms, "clean": clean,
        "burst1": snappedf(_burst(1.0), 0.001), "burst3": snappedf(_burst(3.0), 0.001), "died": died,
    }


## Ends the floor's readout once: bots print it, telemetry stores it.
func flush(died: bool = false) -> void:
    if _flushed or _floor <= 0:
        return
    var s := summary(died)
    _flushed = true
    Telemetry.event("pressure", s)
    if main != null and main.autotest:
        var heal_txt := ""
        for k in s["heal_by"].keys():
            heal_txt += "%s:%.2f " % [k, float(s["heal_by"][k])]
        print("[PRESSURE] floor=%d region=%s fight=%.0f lt50=%.2f lt25=%.2f dmg_pm=%.2f heal_pm=%.2f (%s) hits=%d max_hit=%.2f close=%d threat=%.2f moving=%.2f near_miss_pm=%.1f clean=%d/%d burst1=%.2f burst3=%.2f died=%s" % [
            s["floor"], s["region"], s["fight"], s["lt50"], s["lt25"], s["dmg_pm"], s["heal_pm"], heal_txt.strip_edges(),
            s["hits"], s["max_hit"], s["close"], s["threat"], s["moving"], s["near_miss_pm"], s["clean"], s["rooms"],
            s["burst1"], s["burst3"], str(died)])


func _exit_tree() -> void:
    flush(false)
