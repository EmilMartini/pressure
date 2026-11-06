class_name HurtShot
extends Node
## Debug capture for danger readability, run with the bot (its throwaway save):
##   godot --path . --audio-driver Dummy res://scenes/main.tscn -- --autotest --hurt-shot --instance=N
## The bot is paused (Main.bot_paused) while this drives a six-gun player in a floor 1
## arena. Saves to autotest/:
##   hurt_hit.png      a 9 damage shot from the left at 30% HP: edge flash on the left,
##                     the red "-9" over the figure, the figure flashing
##   hurt_low.png      30% HP in the fight: the pulsing red edge, the HP bar pulsing
##   hurt_crit.png     12% HP: deeper, wider edge, "CRITICAL"
##   hurt_floor.png    standing in charged water: rim and feet ring, the warning label
##   hurt_barrel.png   a lit barrel next to the player mid-fuse: blink and growing ring
##   hurt_recap.png    the barrel's blast kills: the run-over screen's death recap
## then quits.
## With --read-shot it takes the friend-vs-foe pictures instead (GDD "Friend or foe"):
##   read_fight[_zoom].png   the six guns firing, enemy shots coming in from all sides, a
##                           burning and a charged floor beside the player, bats and wisps
##                           next to a grunt; the _zoom file is the middle, 2x
##   read_fight2[_zoom].png  the same half a second later
##   read_flyers[_zoom].png  first, before any gun: bat, grunt, wisp, bat standing in a row
## Options for the capture (not saved): --pixel-size=2 and --set=crt:1,bloom:0, and
## --tag=name to suffix the file names.

var main: Main
var _pin := -1.0   # hold player 1's health at this fraction or above while shooting
var _tag := ""


static func wanted() -> bool:
    return OS.get_cmdline_user_args().has("--hurt-shot")


func _init(m: Main) -> void:
    main = m
    name = "HurtShot"
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
    if _pin < 0.0 or main.players.is_empty():
        return
    var p: Player = main.players[0]
    if p.alive:
        p.hp = maxf(p.hp, p.max_hp * _pin)


func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    main.bot_paused = true
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--pixel-size="):
            Settings.values["pixel_size"] = int(a.substr(13))
        elif a.begins_with("--tag="):
            _tag = "_" + a.substr(6)
        elif a.begins_with("--set="):
            for kv in a.substr(6).split(","):
                var parts := String(kv).split(":")
                if parts.size() == 2:
                    var was: Variant = Settings.get_value(parts[0])
                    Settings.values[parts[0]] = bool(int(parts[1])) if typeof(was) == TYPE_BOOL else float(parts[1])
    Settings.apply()
    if OS.get_cmdline_user_args().has("--read-shot"):
        await _read_shot()
        return
    await _wait(1.0)
    var p: Player = main.players[0]
    p.weight_capacity_base = 40
    p.recalc_stats()
    for id in ["frost_caster", "blowtorch", "mist_sprayer", "gale_blaster", "storm_pike", "arc_rifle"]:
        p.add_gun(id, false)
    for pos in main.rooms.keys():
        if main.rooms[pos].type == RoomData.Type.ARENA:
            main.enter_room(pos, Vector2i.ZERO)
            break
    var room: Room = main.current
    p.global_position = Vector2(0, 0)
    room._begin_arena()
    _pin = 0.3
    await _wait(3.0)
    main.hud._toasts.clear()   # the throwaway save's unlock toasts, not part of the picture
    # A shot from the left at 30% HP.
    p.hp = p.max_hp * 0.3
    p.invuln = 0.0
    Telemetry.hurt_hint = "projectile:spitter"
    p.take_damage(9.0, null, p.global_position + Vector2(-220, 0))
    await _wait(0.07)
    await _shot("hurt_hit")
    await _wait(1.0)
    await _shot("hurt_low")
    _pin = 0.12
    p.hp = p.max_hp * 0.12
    await _wait(1.2)
    await _shot("hurt_crit")
    # Charged water underfoot.
    main.hud._toasts.clear()
    _pin = 0.3
    p.hp = p.max_hp * 0.3
    var mats := Materials.find(p)
    # The frost gun may freeze the pool first: lay and charge it until it holds.
    for i in 8:
        if mats == null or p.hazard_mat == Materials.CHARGED:
            break
        mats.stamp(Element.Kind.WET, p.global_position, 46.0, 220)
        await _wait(0.1)
        mats.stamp(Element.Kind.SHOCK, p.global_position, 46.0, 220)
        p.invuln = 0.0
        await _wait(0.3)
    await _wait(0.15)
    await _shot("hurt_floor")
    # A barrel lit beside the player: shot mid-fuse, then its blast ends the run.
    p.global_position += Vector2(-120, 0)
    var holder := room.get_node_or_null("Props")
    if holder == null:
        holder = Node2D.new()
        holder.name = "Props"
        room.add_child(holder)
    var barrel := Prop.new("barrel")
    barrel.room = room
    barrel.position = room.to_local(p.global_position + Vector2(70, 10))
    holder.add_child(barrel)
    await _wait(0.6)
    main.hud._toasts.clear()
    barrel.states.erase("frozen")   # the frost gun may have got there first
    barrel.apply_element(Element.Kind.FIRE, 1.0, Vector2.ZERO)
    await _wait(0.38)
    await _shot("hurt_barrel")
    _pin = -1.0
    p.hp = 6.0
    p.invuln = 0.0
    await _wait(1.6)
    if not p.alive:
        main.pause_menu.show_menu()
        await _wait(0.6)
        await _shot("hurt_recap")
    else:
        print("[HURT-SHOT] the barrel did not kill (hp %.0f)" % p.hp)
    print("[HURT-SHOT] done")
    main.get_tree().quit()


## Friend or foe: the player's six guns against incoming shots, hurting floors and flyers.
func _read_shot() -> void:
    await _wait(1.0)
    var p: Player = main.players[0]
    for pos in main.rooms.keys():
        if main.rooms[pos].type == RoomData.Type.ARENA:
            main.enter_room(pos, Vector2i.ZERO)
            break
    var room: Room = main.current
    p.global_position = Vector2(0, 0)
    # Flyers next to a grunt, standing still, before any gun is drawn.
    var line: Array[Enemy] = []
    var xs := [46.0, 82.0, 116.0, 152.0]
    var kinds := ["swarmer", "grunt", "wisp", "swarmer"]
    for i in 4:
        var e := room._spawn_enemy(kinds[i], room.enemies.to_local(p.global_position + Vector2(xs[i], 0)))
        e.speed = 0.0
        e.contact_damage = 0.0
        line.append(e)
    main.hud._toasts.clear()
    await _wait(0.8)
    await _shot("read_flyers" + _tag, true)
    for e in line:
        e.queue_free()
    await _wait(0.1)
    p.weight_capacity_base = 40
    p.recalc_stats()
    for id in ["frost_caster", "blowtorch", "mist_sprayer", "gale_blaster", "storm_pike", "arc_rifle"]:
        p.add_gun(id, false)
    room._begin_arena()
    _pin = 0.9
    await _wait(3.0)
    main.hud._toasts.clear()
    var mats := Materials.find(p)
    for k in 2:
        var at := p.global_position
        # The guns' mist and frost douse and freeze the floor: lay it again until it holds.
        for t in 4:
            if mats != null:
                mats.stamp(Element.Kind.OIL, at + Vector2(80, 36), 28.0, 220, true)
                mats.ignite(at + Vector2(80, 36), 28.0, true)
                mats.stamp(Element.Kind.WET, at + Vector2(-80, 40), 30.0, 220, true)
            await _wait(0.06)
            if mats != null:
                mats.stamp(Element.Kind.SHOCK, at + Vector2(-80, 40), 30.0, 220, true)
            await _wait(0.1)
        var ring := [["swarmer", 70.0, 0.3], ["swarmer", 95.0, 1.2], ["swarmer", 80.0, 2.4], ["swarmer", 110.0, 3.6],
            ["wisp", 120.0, 0.9], ["wisp", 105.0, 4.6], ["grunt", 125.0, 5.4], ["spitter", 170.0, 2.0]]
        for r in ring:
            var e := room._spawn_enemy(r[0], room.enemies.to_local(at + Vector2.RIGHT.rotated(r[2]) * r[1]))
            e.max_hp *= 50.0   # alive for the picture
            e.hp = e.max_hp
        for i in 7:
            var from := at + Vector2.RIGHT.rotated(0.4 + TAU * float(i) / 7.0) * randf_range(70.0, 150.0)
            var s := EnemyProjectile.new()
            s.damage = 1.0
            s.speed = 90.0
            s.element = [Element.Kind.NONE, Element.Kind.FIRE, Element.Kind.WET, Element.Kind.POISON, Element.Kind.SHOCK, Element.Kind.ICE, Element.Kind.NONE][i]
            s.direction = (at - from).normalized()
            s.shooter = "spitter"
            room.add_child(s)
            s.global_position = from
        await _wait(0.15)
        await _shot("read_fight" + ("2" if k == 1 else "") + _tag, true)
        await _wait(0.3)
    print("[HURT-SHOT] done")
    main.get_tree().quit()


func _wait(secs: float) -> void:
    await get_tree().create_timer(secs, true, false, true).timeout


func _shot(name_: String, zoom: bool = false) -> void:
    var p: Player = main.players[0]
    print("[HURT-SHOT] %s: hp %.0f/%.0f, floor hazard %d" % [name_, p.hp, p.max_hp, p.hazard_mat])
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png("res://autotest/%s.png" % name_)
        print("[HURT-SHOT] autotest/%s.png" % name_)
        if zoom:
            var sz := img.get_size()
            var w := sz.x / 3
            var h := sz.y / 3
            var crop := img.get_region(Rect2i((sz.x - w) / 2, (sz.y - h) / 2, w, h))
            crop.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
            crop.save_png("res://autotest/%s_zoom.png" % name_)
