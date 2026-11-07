class_name ClarityShot
extends Node
## Clarity pass capture (design doc "Clarity pass"): the same staged moments before and after a
## readability change, with numbers. Real window, the bot's throwaway save:
##   godot --path . --audio-driver Dummy --fixed-fps 60 res://scenes/main.tscn -- --autotest
##     --build=storm --start-floor=3 --route=ossuary_gate,rust_ruins,frostvault
##     --clarity-shot[=boss] --tag=before --instance=N
## The bot is paused. The player stands near the middle of the floor's first arena (or its boss
## room with =boss) with the build's guns, health pinned, while the room spawns as usual from a
## fixed seed. Three shots, autotest/clarity_<region>[_boss]_<tag>_<n>.png, each with a
## [CLARITY] line:
##   own%      share of screen pixels the player's own effects change (shots, clouds, pools,
##             sprays, beams, mines, particles, floor fields): the frame against the
##             same frame with them hidden, tree paused
##   contrast  mean |luminance(enemy) - luminance(floor behind it)| over each on-screen enemy's
##             disc (1.15 x its radius), own effects hidden, 0..1
##   texts     floating texts in the world (damage numbers, reaction names, labels) plus the
##             HUD's toasts and its centre banner
## then [CLARITY-AVG] and quits.

const SHOT_AT := [5.0, 8.0, 11.0]
const BOSS_SHOT_AT := [5.0, 9.0, 13.0]

var main: Main
var _boss := false
var _tag := "now"


static func wanted() -> bool:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--clarity-shot"):
            return true
    return false


func _init(m: Main) -> void:
    main = m
    name = "ClarityShot"
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
    if main.players.is_empty():
        return
    var p: Player = main.players[0]
    if p.alive:
        p.hp = maxf(p.hp, p.max_hp * 0.9)


func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    main.bot_paused = true
    for a in OS.get_cmdline_user_args():
        if a == "--clarity-shot=boss":
            _boss = true
        elif a.begins_with("--tag="):
            _tag = a.substr(6)
    await _wait(1.0)
    var want := RoomData.Type.BOSS if _boss else RoomData.Type.ARENA
    var p: Player = main.players[0]
    seed(4242)
    for pos in main.rooms.keys():
        if main.rooms[pos].type == want:
            main.enter_room(pos, Vector2i.ZERO)
            break
    p.global_position = main.current.to_global(Vector2(0, 140) if _boss else Vector2(0, 40))
    main.hud._toasts.clear()   # the throwaway save's unlock toasts
    var boss: Enemy = main.current.boss
    if boss != null:
        boss.max_hp *= 5.0   # alive for every picture
        boss.hp = boss.max_hp
    var t := 0.0
    var sums := [0.0, 0.0, 0.0]
    var n := 0
    for at in (BOSS_SHOT_AT if _boss else SHOT_AT):
        await _wait(float(at) - t)
        t = float(at)
        n += 1
        var r: Array = await _measure("clarity_%s%s_%s_%d" % [main.region_id, "_boss" if _boss else "", _tag, n])
        for i in 3:
            sums[i] += float(r[i])
    print("[CLARITY-AVG] region=%s boss=%s tag=%s own=%.1f%% contrast=%.3f texts=%.1f" % [main.region_id, _boss, _tag, sums[0] / n, sums[1] / n, sums[2] / n])
    main.get_tree().quit()


func _wait(secs: float) -> void:
    if secs > 0.0:
        await get_tree().create_timer(secs, true, false, true).timeout


func _frame() -> Image:
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    img.convert(Image.FORMAT_RGBA8)
    return img


## [own %, contrast, texts]
func _measure(name_: String) -> Array:
    var texts := _texts()
    var tree := get_tree()
    tree.paused = true
    var full: Image = await _frame()
    full.save_png("res://autotest/%s.png" % name_)
    var hidden: Array[CanvasItem] = []
    _hide_own(main, hidden)
    var calm: Image = await _frame()
    var room: Room = main.current
    room.enemies.visible = false
    var bare: Image = await _frame()
    room.enemies.visible = true
    for c in hidden:
        c.visible = true
    # Own effects: pixels that change by more than 0.1 in any channel (every 2nd pixel).
    var a := full.get_data()
    var b := calm.get_data()
    var w := full.get_width()
    var h := full.get_height()
    var changed := 0
    var seen := 0
    for y in range(0, h, 2):
        var row := y * w * 4
        for x in range(0, w, 2):
            var o := row + x * 4
            seen += 1
            if absi(a[o] - b[o]) > 25 or absi(a[o + 1] - b[o + 1]) > 25 or absi(a[o + 2] - b[o + 2]) > 25:
                changed += 1
    var own := 100.0 * float(changed) / float(maxi(1, seen))
    # Enemy against floor, own effects hidden.
    var c := bare.get_data()
    var k := Vector2(w, h) / get_viewport().get_visible_rect().size
    var total := 0.0
    var bodies := 0
    for e in room.enemies.get_children():
        var en := e as Enemy
        if en == null or en.emerge > 0.0 or en.hp <= 0.0:
            continue
        var xf := en.get_global_transform_with_canvas()
        var sp := xf.origin * k
        var rp := en.radius * absf(xf.get_scale().x) * k.x * 1.15
        if sp.x < rp or sp.y < rp or sp.x > w - rp or sp.y > h - rp:
            continue
        var diff := 0.0
        var px := 0
        for y in range(int(sp.y - rp), int(sp.y + rp) + 1):
            for x in range(int(sp.x - rp), int(sp.x + rp) + 1):
                if Vector2(x, y).distance_to(sp) > rp:
                    continue
                var o := (y * w + x) * 4
                diff += absf(_lum(b, o) - _lum(c, o))
                px += 1
        if px > 0:
            total += diff / float(px)
            bodies += 1
    var contrast := total / float(maxi(1, bodies))
    tree.paused = false
    print("[CLARITY] %s own=%.1f%% contrast=%.3f (%d enemies) texts=%d" % [name_, own, contrast, bodies, texts])
    return [own, contrast, texts]


static func _lum(d: PackedByteArray, o: int) -> float:
    return (0.2126 * d[o] + 0.7152 * d[o + 1] + 0.0722 * d[o + 2]) / 255.0


## Hides the player's own effects (see the header) and lists what it hid.
func _hide_own(n: Node, out: Array[CanvasItem]) -> void:
    for ch in n.get_children():
        if ch is Fx:
            for sub in ch.get_children():
                if sub is CanvasItem and (sub as CanvasItem).visible:
                    (sub as CanvasItem).visible = false
                    out.append(sub)
            continue
        if ch is Projectile or ch is Cloud or ch is Pool or ch is Spray or ch is Beam or ch is Mine or ch is GunFx or ch is Materials:
            if (ch as CanvasItem).visible:
                (ch as CanvasItem).visible = false
                out.append(ch)
            continue
        _hide_own(ch, out)


func _texts() -> int:
    var n := 0
    if main.fx != null:
        n += main.fx._texts.size()
    n += mini(4, main.hud._toasts.size())
    if main._message_time > 0.0:
        n += 1
    return n
