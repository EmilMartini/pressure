class_name Focus
extends RefCounted
## Auto-aim that focuses (Core loop reset, section 7.2; Emil's decisions 10 and 21). Every
## RETARGET seconds each gun picks its own list of targets within its range, closest first:
##   score = 1 / (1 + distance / FALLOFF). Every enemy weighs the same: no boss, elite, key-threat
##   or wind-up priority (Emil, 2026-11-04 and 2026-11-10: "target closest enemy").
## No overkill: a target whose pending damage (shots in flight) already covers its health is
## skipped. Spread: at most MAX_PER_ORDINARY guns on one enemy, elites and bosses included.
## Stickiness: a gun keeps its target until it dies, leaves range or another scores STICKY x
## higher. `Gun.targets[k]` is where shot / beam k goes: extra beams and extra projectiles take
## the next-closest different enemies, doubling up on the first when nothing else is in range.

const RETARGET := 0.1
const FALLOFF := 300.0
const REACT_BONUS := 1.0   # 1.3 before decision 21: no pull toward a reacting target either
const MAX_PER_ORDINARY := 2
const STICKY := 1.5

var _t := 0.0
## Probe counters (--focus-probe): frames with 2+ beams and 2+ enemies in range, and of
## those how many had the beams on distinct targets.
var probe_multi_frames := 0
var probe_multi_distinct := 0
## Seconds from an elite or boss entering any gun's range to the first gun picking it (shown
## for information; no longer a target), and retarget passes where more than MAX_PER_ORDINARY
## guns sat on one enemy.
var elite_latency: Array = []
var over_spread := 0
var _elite_seen := {}   # instance id -> game time it came in range


## Decision 21: every enemy weighs the same; distance alone orders the targets.
static func weight(_e: Enemy, _from: Vector2) -> float:
    return 1.0


static func _reacts(e: Enemy, element: int) -> bool:
    for k in e.states.keys():
        if float(e.states[k]) > 0.0 and int(k) != element and Elements.reaction_name(int(k), element) != "":
            return true
    return false


## Re-picks every gun's targets on the RETARGET clock. Call once per physics frame.
func update(p: Player, delta: float) -> void:
    _t -= delta
    if _t > 0.0:
        _drop_dead(p)
        return
    _t = RETARGET
    var rm := Room.here
    var walls := rm != null and is_instance_valid(rm) and rm.has_walls
    var cands: Array = []
    for e in EnemyGrid.nodes(p.get_tree(), &"enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or not e is Enemy or e.emerge > 0.0 or e.hp <= 0.0:
            continue
        cands.append(e)
    var claims := {}   # enemy instance id -> guns with it as their first target
    for g in p.guns:
        if g.data.family == "melee":
            g.targets = []   # melee takes no Focus slot: it swings at what is in reach (2.1)
            continue
        var rng := g.effective_range()
        var r2 := rng * rng
        var scored: Array = []
        var spare: Array = []   # skipped as overkill: extra beams may still take them
        var keep_score := -1.0
        var old: Enemy = g.targets[0] if not g.targets.is_empty() and is_instance_valid(g.targets[0]) else null
        for e: Enemy in cands:
            var d2 := e.global_position.distance_squared_to(p.global_position)
            if d2 > r2:
                continue
            if e.pending_damage() >= e.hp and e != old:
                spare.append(e)
                continue
            var s := weight(e, p.global_position) / (1.0 + sqrt(d2) / FALLOFF)
            if REACT_BONUS != 1.0 and _reacts(e, g.data.element):
                s *= REACT_BONUS
            scored.append([s, e])
            if e == old:
                keep_score = s
        scored.sort_custom(func(a, b): return a[0] > b[0])
        var want := g.shot_count() if g.data.mechanic == "beam" or g.data.projectile_count <= 1 else 1
        var picked: Array = []
        # Stickiness: the old target stays first unless something scores STICKY x higher.
        if old != null and keep_score > 0.0 and (scored.is_empty() or float(scored[0][0]) < keep_score * STICKY):
            if int(claims.get(old.get_instance_id(), 0)) < MAX_PER_ORDINARY:
                picked.append(old)
        var tries := 0
        for pair in scored:
            if picked.size() >= want:
                break
            var e: Enemy = pair[1]
            if picked.has(e):
                continue
            if picked.is_empty() and int(claims.get(e.get_instance_id(), 0)) >= MAX_PER_ORDINARY:
                continue
            if walls and tries < 6:
                tries += 1
                if not rm.line_clear(p.global_position, e.global_position):
                    continue
            picked.append(e)
        # Everything left is claimed or out of sight: double up rather than hold fire.
        if picked.is_empty() and not scored.is_empty():
            picked.append(scored[0][1])
        # Extra beams and shots spread before they double up: any other enemy in range will do.
        if not picked.is_empty() and picked.size() < want:
            for pair in scored:
                if picked.size() >= want:
                    break
                if not picked.has(pair[1]):
                    picked.append(pair[1])
            for e in spare:
                if picked.size() >= want:
                    break
                if not picked.has(e):
                    picked.append(e)

        if not picked.is_empty():
            var id: int = picked[0].get_instance_id()
            claims[id] = int(claims.get(id, 0)) + 1
        g.targets = picked
    _probe(p)
    _probe_focus(p, cands)


func _drop_dead(p: Player) -> void:
    for g in p.guns:
        if not g.targets.is_empty():
            var t = g.targets[0]
            if not is_instance_valid(t) or t.is_queued_for_deletion() or t.hp <= 0.0:
                _t = 0.0   # re-pick next frame
                return


## The world point shot `k` of gun `g` goes to, or Vector2.INF when the gun has no target.
static func aim_point(g: Gun, k: int) -> Vector2:
    if g.targets.is_empty():
        return Vector2.INF
    var t = g.targets[k] if k < g.targets.size() else g.targets[0]
    if not is_instance_valid(t) or t.is_queued_for_deletion():
        t = g.targets[0]
        if not is_instance_valid(t) or t.is_queued_for_deletion():
            return Vector2.INF
    return (t as Node2D).global_position


func _probe_focus(p: Player, cands: Array) -> void:
    var min_range := INF
    for g in p.guns:
        min_range = minf(min_range, g.effective_range())
    var near := 0
    for e: Enemy in cands:
        if e.global_position.distance_to(p.global_position) <= min_range:
            near += 1
    var now := Enemy._game_now()
    var firsts := {}
    for g in p.guns:
        if not g.targets.is_empty() and is_instance_valid(g.targets[0]):
            var id: int = g.targets[0].get_instance_id()
            firsts[id] = int(firsts.get(id, 0)) + 1
    for e: Enemy in cands:
        var id := e.get_instance_id()
        if (e.is_elite or e.kind_name == "boss") and _elite_seen.get(id, -1.0) != -2.0:
            var in_range := false
            for g in p.guns:
                if e.global_position.distance_to(p.global_position) <= g.effective_range():
                    in_range = true
                    break
            if in_range and not _elite_seen.has(id):
                _elite_seen[id] = now
            if _elite_seen.has(id) and firsts.has(id) and float(_elite_seen[id]) >= 0.0:
                elite_latency.append(now - float(_elite_seen[id]))
                _elite_seen[id] = -2.0   # measured
        if int(firsts.get(id, 0)) > MAX_PER_ORDINARY and near >= p.guns.size():

            over_spread += 1


func _probe(p: Player) -> void:

    for g in p.guns:
        if g.data.mechanic != "beam" or g.shot_count() < 2:
            continue
        var rng := g.effective_range()
        var n := 0
        for e in EnemyGrid.nodes(p.get_tree(), &"enemies"):
            if is_instance_valid(e) and e is Enemy and e.emerge <= 0.0 and e.global_position.distance_to(p.global_position) <= rng:
                n += 1
                if n >= 2:
                    break
        if n >= 2:
            probe_multi_frames += 1
            var live := g.targets.filter(func(t): return is_instance_valid(t))
            var uniq := {}
            for t in live:
                uniq[t.get_instance_id()] = true
            if uniq.size() >= 2:
                probe_multi_distinct += 1
