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
##   own_int   mean change over the whole screen from those effects, % of full scale
##   contrast  mean |luminance(enemy) - luminance(floor behind it)| over each on-screen enemy's
##             disc (1.15 x its radius), own effects hidden, 0..1; mean_contrast is
##             |mean luminance of the disc with the body - without it| (floor detail not counted)
##   texts     floating texts in the world (damage numbers, reaction names, labels) plus the
##             HUD's toasts and its centre banner
## then [CLARITY-AVG] and quits.
## `--clarity-spitters=N` adds N plain spitters on a ring 300 px out (fired shots read the
## same in any region), and every shot adds a [CLARITY-SHOTS] line: over each on-screen
## enemy shot's disc, mean |luminance with the shot - without it|, against the bare floor
## (own effects hidden: shot_floor) and against the floor with the player's own effects
## (shot_own); `edge` is the share of the disc whose luminance differs by more than 0.25.

const SHOT_AT := [5.0, 8.0, 11.0]
const BOSS_SHOT_AT := [5.0, 9.0, 13.0]

var main: Main
var _boss := false
var _tag := "now"
var _shot_sums := [0.0, 0.0, 0.0]
## "background luminance:contrast" per shot, for the last _disc_diff calls.
var _per_shot: Array[String] = []


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
    # --clarity-rest: the same room already cleared (doors open, no fight), one picture
    # at rest, autotest/clarity_<region>[_boss]_<tag>_rest.png, then quit (art pass).
    var rest := OS.get_cmdline_user_args().has("--clarity-rest")
    for pos in main.rooms.keys():
        if main.rooms[pos].type == want:
            if rest:
                main.rooms[pos].cleared = true
            main.enter_room(pos, Vector2i.ZERO)
            break
    p.global_position = main.current.to_global(Vector2(0, 140) if _boss else Vector2(0, 40))
    if rest:
        main.hud._toasts.clear()
        await _wait(2.5)
        var img := await _frame()
        img.save_png("res://autotest/clarity_%s%s_%s_rest.png" % [main.region_id, "_boss" if _boss else "", _tag])
        # And by the top wall's doorway (or its middle): the wall face, torches, doorway.
        var half: Vector2 = main.current.room_size / 2.0
        p.global_position = main.current.to_global(Vector2(0, -half.y + 150.0))
        await _wait(2.0)
        img = await _frame()
        img.save_png("res://autotest/clarity_%s%s_%s_rest_wall.png" % [main.region_id, "_boss" if _boss else "", _tag])
        print("[CLARITY-REST] saved")
        main.get_tree().quit()
        return
    main.hud._toasts.clear()   # the throwaway save's unlock toasts
    var spit := 0
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--clarity-spitters="):
            spit = int(a.substr(19))
    for i in spit:
        var ring := Vector2.RIGHT.rotated(TAU * float(i) / float(spit) + 0.4) * 300.0
        main.current._spawn_enemy("spitter", p.global_position - main.current.global_position + ring)
    var boss: Enemy = main.current.boss
    if boss != null:
        boss.max_hp *= 5.0   # alive for every picture
        boss.hp = boss.max_hp
    var t := 0.0
    var sums := [0.0, 0.0, 0.0, 0.0, 0.0]
    var ab_sums := [0.0, 0.0, 0.0, 0.0, 0.0]
    var ab_shots := [0.0, 0.0, 0.0]
    var n := 0
    for at in (BOSS_SHOT_AT if _boss else SHOT_AT):
        await _wait(float(at) - t)
        t = float(at)
        n += 1
        # --clarity-ab (art pass): the same paused moment measured again with ArtPass off
        # (lighting, grade and its dressing hidden), so the pair differs only by the pass.
        var ab := OS.get_cmdline_user_args().has("--clarity-ab")
        if ab:
            main.get_tree().paused = true
        # --clarity-ab-off-first: the no-art capture first (checks capture-order bias).
        var off_first := ab and OS.get_cmdline_user_args().has("--clarity-ab-off-first")
        var k0 := _shot_sums.duplicate()
        if off_first:
            ArtPass.suppress(true)
        var r: Array = await _measure("clarity_%s%s_%s_%d%s" % [main.region_id, "_boss" if _boss else "", _tag, n, "_noart" if off_first else ""])
        ArtPass.suppress(false)
        if off_first:
            for i in 5:
                ab_sums[i] += float(r[i])
            for i in 3:
                ab_shots[i] += _shot_sums[i] - k0[i]
                _shot_sums[i] = k0[i]
            main.get_tree().paused = true
            r = await _measure("clarity_%s%s_%s_%d" % [main.region_id, "_boss" if _boss else "", _tag, n])
        for i in 5:
            sums[i] += float(r[i])
        if ab and not off_first:
            var keep := _shot_sums.duplicate()
            ArtPass.suppress(true)
            main.get_tree().paused = true
            var r2: Array = await _measure("clarity_%s%s_%s_%d_noart" % [main.region_id, "_boss" if _boss else "", _tag, n])
            ArtPass.suppress(false)
            for i in 5:
                ab_sums[i] += float(r2[i])
            for i in 3:
                ab_shots[i] += _shot_sums[i] - keep[i]
                _shot_sums[i] = keep[i]
    if _shot_sums[2] > 0.0:
        print("[CLARITY-SHOTS-AVG] region=%s tag=%s shot_floor=%.3f shot_own=%.3f" % [main.region_id, _tag, _shot_sums[0] / _shot_sums[2], _shot_sums[1] / _shot_sums[2]])
    print("[CLARITY-AVG] region=%s boss=%s tag=%s own=%.1f%% own_int=%.1f contrast=%.3f mean_contrast=%.3f texts=%.1f fps=%d" % [main.region_id, _boss, _tag, sums[0] / n, sums[3] / n, sums[1] / n, sums[4] / n, sums[2] / n, Engine.get_frames_per_second()])
    if ab_shots[2] > 0.0 or ab_sums[0] > 0.0:
        print("[CLARITY-AB-NOART] region=%s tag=%s own=%.1f%% own_int=%.1f contrast=%.3f mean_contrast=%.3f shot_floor=%.3f shot_own=%.3f" % [main.region_id, _tag, ab_sums[0] / n, ab_sums[3] / n, ab_sums[1] / n, ab_sums[4] / n, ab_shots[0] / maxf(1.0, ab_shots[2]), ab_shots[1] / maxf(1.0, ab_shots[2])])
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
    var again: Image = null
    if OS.get_cmdline_user_args().has("--clarity-parts"):
        # Which of the own effects carries the change: each category hidden alone.
        var parts := []
        again = await _frame()   # nothing hidden: what moves while paused
        parts.append("noise=%.1f" % _intensity(full, again))
        for cat in ["materials", "fx", "clouds", "shots"]:
            var only: Array[CanvasItem] = []
            _hide_own(main, only, cat)
            var img: Image = await _frame()
            for ci in only:
                ci.visible = true
            parts.append("%s=%.1f" % [cat, _intensity(full, img)])
        print("[CLARITY-PARTS] %s %s" % [name_, " ".join(parts)])
        # Which floor materials are down: cells per material, and how many of them are rim.
        var mats := main.current.materials
        var names := ["none", "oil", "water", "fire", "ice", "poison", "acid", "blood", "steam", "charged", "ash", "dry_blood", "toxic"]
        var cells := {}
        for i in mats._n:
            var m := int(mats.mat[i])
            if m != 0:
                cells[names[m]] = int(cells.get(names[m], 0)) + 1
        print("[CLARITY-CELLS] %s %s" % [name_, cells])
    var shots := _shots_on_screen(full)
    var no_shot_full: Image = null
    if not shots.is_empty():
        _show_shots(shots, false)
        no_shot_full = await _frame()
        _show_shots(shots, true)
    var hidden: Array[CanvasItem] = []
    _hide_own(main, hidden)
    var calm: Image = await _frame()
    if not shots.is_empty():
        _show_shots(shots, false)
        var calm_bare: Image = await _frame()
        _show_shots(shots, true)
        _per_shot.clear()
        var vf := _disc_diff(calm, calm_bare, shots)
        print("[CLARITY-SHOT-EACH] %s floor bg:contrast %s" % [name_, " ".join(_per_shot)])
        _per_shot.clear()
        var vo := _disc_diff(full, no_shot_full, shots)
        print("[CLARITY-SHOT-EACH] %s own bg:contrast %s" % [name_, " ".join(_per_shot)])
        print("[CLARITY-SHOTS] %s shot_floor=%.3f edge_floor=%.2f shot_own=%.3f edge_own=%.2f (%d shots)" % [name_, vf.x, vf.y, vo.x, vo.y, shots.size()])
        _shot_sums[0] += vf.x
        _shot_sums[1] += vo.x
        _shot_sums[2] += 1.0
    var room: Room = main.current
    room.enemies.visible = false
    var bare: Image = await _frame()
    room.enemies.visible = true
    for c in hidden:
        c.visible = true
    if again != null:
        _mask(full, calm, again).save_png("res://autotest/%s_mask.png" % name_)
    # Own effects: pixels that change by more than 0.1 in any channel (every 2nd pixel).
    var a := full.get_data()
    var b := calm.get_data()
    var w := full.get_width()
    var h := full.get_height()
    var changed := 0
    var seen := 0
    var energy := 0
    for y in range(0, h, 2):
        var row := y * w * 4
        for x in range(0, w, 2):
            var o := row + x * 4
            seen += 1
            var m := maxi(absi(a[o] - b[o]), maxi(absi(a[o + 1] - b[o + 1]), absi(a[o + 2] - b[o + 2])))
            energy += m
            if m > 25:
                changed += 1
    var own := 100.0 * float(changed) / float(maxi(1, seen))
    var own_int := 100.0 * float(energy) / 255.0 / float(maxi(1, seen))
    # Enemy against floor, own effects hidden.
    var c := bare.get_data()
    var k := Vector2(w, h) / get_viewport().get_visible_rect().size
    var total := 0.0
    var means := 0.0
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
        var le := 0.0
        var lf := 0.0
        var px := 0
        for y in range(int(sp.y - rp), int(sp.y + rp) + 1):
            for x in range(int(sp.x - rp), int(sp.x + rp) + 1):
                if Vector2(x, y).distance_to(sp) > rp:
                    continue
                var o := (y * w + x) * 4
                diff += absf(_lum(b, o) - _lum(c, o))
                le += _lum(b, o)
                lf += _lum(c, o)
                px += 1
        if px > 0:
            total += diff / float(px)
            means += absf(le - lf) / float(px)
            bodies += 1
    var contrast := total / float(maxi(1, bodies))
    var mean_c := means / float(maxi(1, bodies))
    tree.paused = false
    print("[CLARITY] %s own=%.1f%% own_int=%.1f contrast=%.3f mean_contrast=%.3f (%d enemies) texts=%d" % [name_, own, own_int, contrast, mean_c, bodies, texts])
    return [own, contrast, texts, own_int, mean_c]


## On-screen enemy shots as [shot, screen centre, screen radius of its crisp disc].
func _shots_on_screen(img: Image) -> Array:
    var out := []
    var k := Vector2(img.get_width(), img.get_height()) / get_viewport().get_visible_rect().size
    for s in get_tree().get_nodes_in_group("enemy_projectiles"):
        var sh := s as EnemyProjectile
        if sh == null:
            continue
        var xf := sh.get_global_transform_with_canvas()
        var sp := xf.origin * k
        var rp := (maxf(sh.radius * 0.85, 4.0) + 3.5) * absf(xf.get_scale().x) * k.x
        if sp.x < rp or sp.y < rp or sp.x > img.get_width() - rp or sp.y > img.get_height() - rp:
            continue
        out.append([sh, sp, rp])
    return out


## Hides or shows shots: the glow (the node) and the Crisp disc (Fx draws the group).
func _show_shots(shots: Array, on: bool) -> void:
    for e in shots:
        var sh: EnemyProjectile = e[0]
        if not is_instance_valid(sh):
            continue
        sh.visible = on
        if on:
            sh.add_to_group("enemy_projectiles")
        else:
            sh.remove_from_group("enemy_projectiles")


## Mean over shots of (mean |lum a - lum b| over the disc, share of the disc above 0.25).
func _disc_diff(a_img: Image, b_img: Image, shots: Array) -> Vector2:
    var a := a_img.get_data()
    var b := b_img.get_data()
    var w := a_img.get_width()
    var sum := Vector2.ZERO
    for e in shots:
        var sp: Vector2 = e[1]
        var rp: float = e[2]
        var diff := 0.0
        var strong := 0
        var px := 0
        var bg := 0.0
        for y in range(int(sp.y - rp), int(sp.y + rp) + 1):
            for x in range(int(sp.x - rp), int(sp.x + rp) + 1):
                if Vector2(x, y).distance_to(sp) > rp:
                    continue
                var o := (y * w + x) * 4
                bg += _lum(b, o)
                var d := absf(_lum(a, o) - _lum(b, o))
                diff += d
                if d > 0.25:
                    strong += 1
                px += 1
        sum += Vector2(diff / float(maxi(1, px)), float(strong) / float(maxi(1, px)))
        _per_shot.append("%.2f:%.3f" % [bg / float(maxi(1, px)), diff / float(maxi(1, px))])
    return sum / float(maxi(1, shots.size()))


## Red: pixels the own effects change by more than 0.1; blue: pixels that move with nothing hidden.
static func _mask(full: Image, calm: Image, again: Image) -> Image:
    var w := full.get_width()
    var h := full.get_height()
    var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
    var a := full.get_data()
    var b := calm.get_data()
    var c := again.get_data()
    for y in h:
        for x in w:
            var o := (y * w + x) * 4
            var own := maxi(absi(a[o] - b[o]), maxi(absi(a[o + 1] - b[o + 1]), absi(a[o + 2] - b[o + 2]))) > 25
            var mv := maxi(absi(a[o] - c[o]), maxi(absi(a[o + 1] - c[o + 1]), absi(a[o + 2] - c[o + 2]))) > 25
            var g := a[o + 1] / 4
            out.set_pixel(x, y, Color8(255 if own else g, g, 255 if mv else g))
    return out


static func _lum(d: PackedByteArray, o: int) -> float:
    return (0.2126 * d[o] + 0.7152 * d[o + 1] + 0.0722 * d[o + 2]) / 255.0


## Mean change between two frames, % of full scale (every 2nd pixel).
static func _intensity(x: Image, y: Image) -> float:
    var a := x.get_data()
    var b := y.get_data()
    var w := x.get_width()
    var energy := 0
    var seen := 0
    for yy in range(0, x.get_height(), 2):
        for xx in range(0, w, 2):
            var o := (yy * w + xx) * 4
            energy += maxi(absi(a[o] - b[o]), maxi(absi(a[o + 1] - b[o + 1]), absi(a[o + 2] - b[o + 2])))
            seen += 1
    return 100.0 * float(energy) / 255.0 / float(maxi(1, seen))


## Hides the player's own effects (see the header), or one category of them, and lists what
## it hid.
func _hide_own(n: Node, out: Array[CanvasItem], only := "") -> void:
    for ch in n.get_children():
        var cat := ""
        if ch is Fx:
            if only == "" or only == "fx":
                for sub in ch.get_children():
                    if sub is CanvasItem and (sub as CanvasItem).visible:
                        (sub as CanvasItem).visible = false
                        out.append(sub)
            continue
        if ch is Materials:
            cat = "materials"
        elif ch is Projectile:
            cat = "shots"
        elif ch is Cloud or ch is Pool or ch is Spray or ch is Beam or ch is Mine or ch is GunFx:
            cat = "clouds"
        if cat != "":
            if (only == "" or only == cat) and (ch as CanvasItem).visible:
                (ch as CanvasItem).visible = false
                out.append(ch)
            continue
        _hide_own(ch, out, only)


func _texts() -> int:
    var n := 0
    if main.fx != null:
        n += main.fx._texts.size()
    n += mini(4, main.hud._toasts.size())
    if main._message_time > 0.0:
        n += 1
    return n
