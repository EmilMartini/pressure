class_name BalanceProbe
extends Node
## `--dps-probe` (with --autotest): a controlled damage measurement for level-up and build
## A/B tests. The player stands in the middle of the floor's entrance room, ring of harmless,
## stationary dummies around them that never die (topped up to full below half health and
## pinned in place, so damage is never lost to overkill, respawn or knockback and the group
## keeps its states, compounds and fields like an elite pack). After a warm-up it measures
## every point of damage dealt (Enemy.dealt_total: guns, reactions, fusions, cataclysms,
## damage over time) for `--probe-secs=N` (default 40) and prints one `[DPS]` line, then quits.
## The bot still vents every 6 s and uses its active item every 9 s; level-ups are off.
##
## Flags: `--probe-hp=N` dummy health (default 1500 x floor), `--probe-count=N` dummies
## (default 8), `--probe-picks=id,id` extra level-up options (LevelUps.options() ids) applied
## on top of the build, `--no-picks` (main.gd) drops the --build profile's own picks.

const RING := 230.0
const WARMUP := 6.0

var main
var _t := 0.0
var _secs := 40.0
var _hp := 0.0
var _count := 8
var _slots: Array = []        # Enemy or null per ring slot
var _dealt0 := -1.0
var _tier0: Array = []
var _label := ""


func _init(p_main) -> void:
    main = p_main


func start() -> void:
    var args := OS.get_cmdline_user_args()
    _hp = 1500.0 * float(maxi(1, main.floor_number))
    for a in args:
        if a.begins_with("--probe-secs="):
            _secs = float(a.substr(13))
        elif a.begins_with("--probe-hp="):
            _hp = float(a.substr(11))
        elif a.begins_with("--probe-count="):
            _count = maxi(1, int(a.substr(14)))
        elif a.begins_with("--probe-picks="):
            _label = a.substr(14)
    var p = main.players[0]
    if _label != "":
        var by_id := {}
        for opt in LevelUps.options():
            by_id[opt["id"]] = opt
        for id in _label.split(","):
            if by_id.has(id):
                p.apply_upgrade(by_id[id])
            else:
                print("[DPS] unknown pick id %s" % id)
    p.hp = p.max_hp
    _slots.resize(_count)
    print("[DPS] start floor=%d level=%d dummies=%d hp=%.0f picks=%s no_picks=%s" % [
        main.floor_number, p.level, _count, _hp, _label if _label != "" else "-", str(args.has("--no-picks"))])


func tick(delta: float) -> void:
    _t += delta
    var p = main.players[0]
    p.hp = p.max_hp   # survival is not what this measures
    p.input.force_move = -p.global_position.normalized() if p.global_position.length() > 20.0 else Vector2.ZERO
    p.input.force_fire = false
    for i in _count:
        var e = _slots[i]
        if e == null or not is_instance_valid(e) or e.is_queued_for_deletion() or e.hp <= 0.0:
            _slots[i] = _spawn(i)
            e = _slots[i]
        if e.hp < e.max_hp * 0.5:
            e.hp = e.max_hp
        e.position = _spot(i)
    if fmod(_t, 6.0) < delta:
        p.vent()
    if fmod(_t, 9.0) < delta and p.has_method("use_active"):
        p.use_active()
    if _dealt0 < 0.0 and _t >= WARMUP:
        _dealt0 = Enemy.dealt_total
        _tier0 = (Telemetry.fusion_summary().get("tier_dmg", []) as Array).duplicate()
    if _dealt0 >= 0.0 and _t >= WARMUP + _secs:
        var dealt := Enemy.dealt_total - _dealt0
        var tiers: Array = Telemetry.fusion_summary().get("tier_dmg", [])
        var parts: Array = []
        var tsum := 0.0
        for i in tiers.size():
            tsum += float(tiers[i]) - (float(_tier0[i]) if i < _tier0.size() else 0.0)
        for i in tiers.size():
            var d := float(tiers[i]) - (float(_tier0[i]) if i < _tier0.size() else 0.0)
            parts.append("t%d=%.0f%%" % [i, 100.0 * d / maxf(1.0, tsum)])
        print("[DPS] floor=%d picks=%s dps=%.0f secs=%.0f %s" % [main.floor_number, _label if _label != "" else "-", dealt / _secs, _secs, " ".join(parts)])
        get_tree().quit()


func _spawn(i: int) -> Node:
    var room = main.current
    var e = room._spawn_enemy("grunt", _spot(i))
    e.max_hp = _hp
    e.hp = _hp
    e.speed = 0.0
    e.contact_damage = 0.0
    e.damage_mult = 0.0
    e.scrap_value = 0
    return e


func _spot(i: int) -> Vector2:
    return main.current.nearest_open(Vector2.RIGHT.rotated(TAU * float(i) / float(_count)) * RING, 22.0)
