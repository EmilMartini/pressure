class_name Shortcuts
extends RefCounted
## Shortcuts and world state (design/World and progression GDD.md, section 8 and Phase 4).
##
## A far-side gate per built region: a chain-gate in the region's start room, barred from
## the start side, that leads to the boss antechamber (the one room the boss room opens
## onto). The first time a player walks through it from the antechamber side, it opens for
## good (Progress.world, saved at once, so a death right after still keeps it). In later
## runs the start room's gate is open: entrance, antechamber, boss door. The arenas between,
## and their loot and XP, are skipped; the boss never is.
##
## Locked rules this keeps (section 8): no waystones (every run starts at the top), no free
## warping (the gate is a door you walk through, inside one region), shortcuts never skip
## bosses (the gate ends in the antechamber, never the boss room, and the stairs down only
## appear when the boss dies: Main.next_floor checks it, [BOSS-CHECK]), opened shortcuts
## never close (nothing removes them; only a full save reset).
##
## Floors are generated fresh each run, so the gate is laid every run between that run's
## start room and antechamber, on a side both have free. When the antechamber is the start
## room or next to it, or no side is free, the floor has no gate that run ([SHORTCUT] skip).
##
## Names and lines are placeholders (`placeholder: true`) for the section 9 review.

## One per built region today. Lifts, sluices and secret edges need regions phase 5 builds
## (section 15, Phase 4 handoff).
const DEFS := {
    "ossuary_gate:gate": { "region": "ossuary_gate", "kind": "gate", "name": "Ossuary chain-gate", "placeholder": true },
    "rust_ruins:gate": { "region": "rust_ruins", "kind": "gate", "name": "Rust Ruins floodgate", "placeholder": true },
    "drowned_cistern:gate": { "region": "drowned_cistern", "kind": "gate", "name": "Cistern grate", "placeholder": true },
    "rotting_gardens:gate": { "region": "rotting_gardens", "kind": "gate", "name": "Gardens trellis gate", "placeholder": true },
    "frostvault:gate": { "region": "frostvault", "kind": "gate", "name": "Frostvault portcullis", "placeholder": true },
    "the_forge:gate": { "region": "the_forge", "kind": "gate", "name": "Forge blast door", "placeholder": true },
    "chapel_of_ash:gate": { "region": "chapel_of_ash", "kind": "gate", "name": "Chapel grille", "placeholder": true },
    "the_rift:gate": { "region": "the_rift", "kind": "gate", "name": "Rift seam", "placeholder": true },
    "drowned_cistern:sluice": { "region": "drowned_cistern", "kind": "sluice", "name": "Cistern sluice", "placeholder": true },
}

## The Cistern's sluice (section 8, "bridge or sluice"): a wheel in the Choir's arena,
## offered only once the Choir is dead, so it can never skip the boss. Turned by hand, it
## stays open (Progress.world, saved at once). In later runs the Cistern is drained: no
## standing puddles, no drains, the layout's deep pools dry, and enemies in the open are
## tougher (DRAINED_HP, DRAINED_DMG). The Choir still floods its own arena.
const SLUICE := "drowned_cistern:sluice"
const DRAINED_HP := 1.3
const DRAINED_DMG := 1.15

const OBSTACLE := "chain_gate"


static func gate_id(region_id: String) -> String:
    return "%s:gate" % region_id


static func display_name(id: String) -> String:
    return String((DEFS.get(id, {}) as Dictionary).get("name", id))


static func is_open(id: String) -> bool:
    return Progress.shortcut_open(id)


## True when `region_id` is the Cistern and its sluice is open (a drained Cistern).
static func drained(region_id: String) -> bool:
    return region_id == String(DEFS[SLUICE]["region"]) and is_open(SLUICE)


## Every shortcut opened so far, in DEFS order (the Cartographer's map).
static func opened() -> Array:
    var out: Array = []
    for id in DEFS.keys():
        if is_open(id):
            out.append(id)
    return out


## Built regions whose gate is still shut (the Cartographer's hint).
static func closed_built() -> Array:
    var out: Array = []
    for id in DEFS.keys():
        if bool(Regions.get_region(String(DEFS[id]["region"]))["built"]) and not is_open(id):
            out.append(id)
    return out


## Lays this run's gate into a freshly generated floor. Returns { id, start, ante, dir,
## open } or {} when the floor has none.
static func plan(rooms: Dictionary, region_id: String) -> Dictionary:
    var id := gate_id(region_id)
    if not DEFS.has(id):
        return {}
    var start := Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2)
    var boss := Vector2i(-99, -99)
    for p in rooms.keys():
        if (rooms[p] as RoomData).type == RoomData.Type.BOSS:
            boss = p
    if not rooms.has(boss) or not rooms.has(start):
        return {}
    # The antechamber: the boss room's neighbour nearest the start (a leaf has just one).
    var ante := Vector2i(-99, -99)
    for d in rooms[boss].doors.keys():
        var n: Vector2i = rooms[boss].doors[d]["to"]
        if not rooms.has(ante) or _steps(rooms, start, n) < _steps(rooms, start, ante):
            ante = n
    if not rooms.has(ante) or ante == start or _steps(rooms, start, ante) <= 1:
        _log("[SHORTCUT] %s skip: the antechamber is the start room or next to it" % id)
        return {}
    # A free wall in each room; the opposite side when both have it, so the way through
    # reads straight.
    var side := Vector2i.ZERO
    var back := Vector2i.ZERO
    for d in FloorGen.DIRS:
        if _free(rooms, start, d) and _free(rooms, ante, -d):
            side = d
            back = -d
            break
    if side == Vector2i.ZERO:
        for d in FloorGen.DIRS:
            if side == Vector2i.ZERO and _free(rooms, start, d):
                side = d
            if back == Vector2i.ZERO and _free(rooms, ante, d):
                back = d
    if side == Vector2i.ZERO or back == Vector2i.ZERO:
        _log("[SHORTCUT] %s skip: no free wall (start %s, antechamber %s)" % [id, side, back])
        return {}
    # Never the boss room: the gate ends at the boss door, not past it.
    assert(rooms[ante].type != RoomData.Type.BOSS)
    var open := is_open(id)
    rooms[start].doors[side] = { "to": ante, "obstacle": "" if open else OBSTACLE, "gate": id, "back": back }
    rooms[ante].doors[back] = { "to": start, "obstacle": "", "gate": id, "back": side }
    if open:
        rooms[ante].discovered = true   # a known way: on the map from the start
    _log("[SHORTCUT] %s laid start=%s ante=%s side=%s steps=%d open=%s" % [id, start, ante, side, _steps(rooms, start, ante), open])
    return { "id": id, "start": start, "ante": ante, "dir": side, "back": back, "open": open }


## A wall with no door and no room behind it (adjacent rooms always share a door).
static func _free(rooms: Dictionary, at: Vector2i, d: Vector2i) -> bool:
    return not rooms[at].doors.has(d) and not rooms.has(at + d)


## Doors between two rooms over plain doors (gates and obstacles ignored), -1 if none.
static func _steps(rooms: Dictionary, a: Vector2i, b: Vector2i) -> int:
    var dist := { a: 0 }
    var queue: Array = [a]
    while not queue.is_empty():
        var cur: Vector2i = queue.pop_front()
        if cur == b:
            return int(dist[cur])
        for d in rooms[cur].doors.keys():
            var door: Dictionary = rooms[cur].doors[d]
            if door.has("gate"):
                continue
            var n: Vector2i = door["to"]
            if rooms.has(n) and not dist.has(n):
                dist[n] = int(dist[cur]) + 1
                queue.append(n)
    return 999


static func _log(line: String) -> void:
    if Main.bot_run():
        print(line)
