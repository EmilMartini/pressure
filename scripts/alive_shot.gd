class_name AliveShot
extends Node
## Living-world captures (design doc "Art direction", living world): staged rooms at rest and
## after the elements touched them, before and after the art work. Real window, the bot's
## throwaway save, the bot paused:
##   tools/bot_window.sh 120 autotest/alive.log 200000 --path . --audio-driver Dummy
##     res://scenes/main.tscn -- --autotest --start-floor=2 --route=ossuary_gate,drowned_cistern
##     --alive-shot=river --alive-layout=channels --tag=after --instance=N
## Kinds (`--alive-shot=`):
##   river   a cleared arena of the floor's region with --alive-layout (default "stream"):
##           autotest/alive_<region>_river_<tag>_rest.png, then the river frozen in one place,
##           shocked in another and boiled by a fire on its bank: _react.png
##   react   the floor's first arena, cleared: at rest, then fire, ice, poison and a gale on
##           the dressing islands: alive_<region>_react_<tag>_rest.png / _react.png, and
##           _revisit.png after leaving and coming back (the marks stay)
##   route   the boss room after the fight, its route doors: alive_<region>_route_<tag>.png
## `--no-art` takes the same frames with the art pass off.

var main: Main
var _kind := "river"
var _tag := "now"
var _layout := ""


static func wanted() -> bool:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--alive-shot"):
            return true
    return false


func _init(m: Main) -> void:
    main = m
    name = "AliveShot"
    process_mode = Node.PROCESS_MODE_ALWAYS


func _wait(secs: float) -> void:
    await get_tree().create_timer(secs, true, false, true).timeout


func _save(suffix: String) -> void:
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    var path := "res://autotest/alive_%s_%s_%s%s.png" % [main.region_id, _kind, _tag, suffix]
    img.save_png(path)
    print("[ALIVE-SHOT] %s layout=%s" % [path.get_file(), main.current.layout_name if main.current != null else "?"])


func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    main.bot_paused = true
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--alive-shot="):
            _kind = a.substr(13)
        elif a.begins_with("--tag="):
            _tag = a.substr(6)
        elif a.begins_with("--alive-layout="):
            _layout = a.substr(15)
    await _wait(1.0)
    seed(4242)
    var p: Player = main.players[0]
    p.hp = p.max_hp
    match _kind:
        "river":
            await _river(p)
        "react":
            await _react(p)
        "route":
            await _route(p)
    print("[ALIVE-SHOT] done")
    main.get_tree().quit()


func _enter(rooms: Dictionary, at: Vector2i, stand: Vector2) -> void:
    main.rooms = rooms
    main.enter_room(at, Vector2i.ZERO)
    var p: Player = main.players[0]
    p.global_position = main.current.to_global(stand)
    p.velocity = Vector2.ZERO
    main.hud._toasts.clear()


func _river(p: Player) -> void:
    var centre := Vector2i(FloorGen.GRID / 2, FloorGen.GRID / 2)
    var lay := _layout if _layout != "" else "stream"
    var rooms: Dictionary = main._shot_rooms(centre, { "layout": lay, "size": 1 })
    await _enter(rooms, centre, Vector2(0, 30))
    var room := main.current
    var m := room.materials
    var half := room.room_size / 2.0
    var wet: Array = []
    for x in range(int(-half.x) + 40, int(half.x) - 40, 30):
        for y in range(int(-half.y) + 40, int(half.y) - 40, 30):
            var q := Vector2(x, y)
            if room.is_deep(room.to_global(q)):
                wet.append(q)
    if wet.size() < 3:
        await _wait(2.5)
        await _save("_rest")
        return
    # Three spots along one stretch near the middle: freeze, shock, and a fire on the bank.
    var b: Vector2 = wet[wet.size() / 2]
    var a := b
    var c := b
    for w in wet:
        var q: Vector2 = w
        if absf(q.y - b.y) < 40.0:
            if absf(q.x - (b.x - 230.0)) < absf(a.x - (b.x - 230.0)):
                a = q
            if absf(q.x - (b.x + 230.0)) < absf(c.x - (b.x + 230.0)):
                c = q
    p.global_position = room.to_global(b + Vector2(0, 110.0 if b.y < 0.0 else -110.0))
    await _wait(2.5)
    await _save("_rest")
    m.stamp(Element.Kind.ICE, room.to_global(a), 60.0, 200)
    var bank := c + Vector2(0, 60.0 if c.y < 0.0 else -60.0)
    m.stamp(Element.Kind.OIL, room.to_global(bank), 40.0, 160)
    m.ignite(room.to_global(bank), 40.0, true)
    m.stamp(Element.Kind.FIRE, room.to_global(c), 24.0, 220, true)
    print("[ALIVE-SHOT] river cells=%d freeze=%s shock=%s fire=%s" % [wet.size(), a, b, c])
    await _wait(1.2)
    await _save("_react")
    m.stamp(Element.Kind.SHOCK, room.to_global(b), 30.0, 200)
    await _wait(0.15)
    await _save("_shock")


func _react(p: Player) -> void:
    var pos := Vector2i(-99, -99)
    for k in main.rooms.keys():
        if main.rooms[k].type == RoomData.Type.ARENA:
            pos = k
            break
    if pos == Vector2i(-99, -99):
        return
    main.rooms[pos].cleared = true
    if _layout != "":
        main.rooms[pos].layout = _layout   # the same room as an older capture
    await _enter(main.rooms, pos, Vector2(0, 40))
    var room := main.current
    # The two dressing islands closest together; stand between them.
    var spots: Array = []
    var lv := room.get_node_or_null("Living")
    if lv != null and "pieces" in lv:
        for pc in lv.pieces:
            if String(pc["k"]) == "moss":
                spots.append(pc["p"])
    var pair := [Vector2(-200, 0), Vector2(200, 0)]
    var best := INF
    for i in spots.size():
        for j in range(i + 1, spots.size()):
            var d: float = (spots[i] as Vector2).distance_to(spots[j])
            if d < best:
                best = d
                pair = [spots[i], spots[j]]
    p.global_position = room.to_global(((pair[0] as Vector2) + (pair[1] as Vector2)) / 2.0)
    await _wait(2.5)
    await _save("_rest")
    var m := room.materials
    m.stamp(Element.Kind.OIL, room.to_global(pair[0]), 30.0, 100)
    m.ignite(room.to_global(pair[0]), 24.0, true)
    m.stamp(Element.Kind.WET, room.to_global(pair[1]), 40.0, 120)
    m.stamp(Element.Kind.ICE, room.to_global(pair[1]), 50.0, 200)
    await _wait(1.4)
    await _save("_react")
    await _wait(11.0)   # the fire burns out and the ice melts: char and frost rims are left
    # Leave and come back: what burned, froze and broke is still on the floor.
    var other: Vector2i = room.data.doors.keys()[0]
    var nxt: Vector2i = room.data.doors[other]["to"]
    main.rooms[nxt].cleared = true
    main.enter_room(nxt, other)
    await _wait(0.8)
    main.enter_room(pos, -other)
    p.global_position = main.current.to_global(((pair[0] as Vector2) + (pair[1] as Vector2)) / 2.0)
    main.hud._toasts.clear()
    await _wait(1.5)
    await _save("_revisit")


func _route(p: Player) -> void:
    var pos := Vector2i(-99, -99)
    for k in main.rooms.keys():
        if main.rooms[k].type == RoomData.Type.BOSS:
            pos = k
            break
    if pos == Vector2i(-99, -99):
        return
    var d: RoomData = main.rooms[pos]
    d.cleared = true
    d.started = true
    var ways: Array = Regions.next_options(main.region_id) if main.floor_number < Main.FLOORS else []
    if ways.is_empty():
        d.stock.append(FloorGen.offer("stairs", "", 0))
    for id in ways:
        d.stock.append(FloorGen.offer("stairs", String(id), 0))
    await _enter(main.rooms, pos, Vector2(0, 170))
    await _wait(2.5)
    await _save("")
