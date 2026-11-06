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

var main: Main
var _pin := -1.0   # hold player 1's health at this fraction or above while shooting


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


func _wait(secs: float) -> void:
    await get_tree().create_timer(secs, true, false, true).timeout


func _shot(name_: String) -> void:
    var p: Player = main.players[0]
    print("[HURT-SHOT] %s: hp %.0f/%.0f, floor hazard %d" % [name_, p.hp, p.max_hp, p.hazard_mat])
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png("res://autotest/%s.png" % name_)
        print("[HURT-SHOT] autotest/%s.png" % name_)
