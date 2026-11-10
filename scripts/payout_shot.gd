class_name PayoutShot
extends Node
## Debug capture for the level-up cards and the wave-end spoils, run with the bot (its
## throwaway save, add --instance=N):
##   godot --path . --audio-driver Dummy res://scenes/main.tscn -- --autotest --payout-shot --instance=N
## The bot is paused (Main.bot_paused) while this drives. Saves to autotest/:
##   levelup_cards.png    three cards: a stat boon, an element echo, a trade-off
##   levelup_cards4.png   four cards (Wider Choice): attunement, fusion, health, crit
##   spoils_vacuum.png    the instant a wave ends: scrap flying to the player
##   spoils.png           the wave-end choice (gun, item, two banked elite drops)
##   spoils_salvage.png   right after taking one: the rest salvaged, said out loud
##   ring_swap_a.png / ring_swap_b.png   a ring pedestal with both rings worn, default
##                        target (the weaker ring) and after pressing swap
##   merge.png            a gun pedestal for a gun you carry: "Merge: X tier N"
## then quits.

var main: Node


static func wanted() -> bool:
    return OS.get_cmdline_user_args().has("--payout-shot")


func _init(m: Node) -> void:
    main = m
    name = "PayoutShot"
    process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    main.bot_paused = true
    await _wait(1.0)
    var p: Player = main.players[0]
    p.weight_capacity_base = 40
    p.recalc_stats()
    for id in ["blowtorch", "spark_needler", "frost_caster", "venom_spitter"]:
        p.add_gun(id, false)
    p.level = 12
    p.bonus_stats["dmg"] = 0.20
    p.recalc_stats()
    p.input.lock_kind = true
    p.input.last_kind = "pad"
    # Level-up cards.
    main.levelup.open_with(p, _opts(["damage_1", "echo_shock_2", "glass_cannon_3"]))
    await _wait(0.8)
    await _shot("levelup_cards")
    main.levelup.open_with(p, _opts(["attune_fire_0", "fusion_power_1", "max_hp_2", "crit_3"]))
    await _wait(0.8)
    await _shot("levelup_cards4")
    main.levelup.close_for_test()
    await _wait(0.3)
    # Wave-end spoils in the nearest arena.
    for pos in main.rooms.keys():
        if main.rooms[pos].type == RoomData.Type.ARENA:
            main.enter_room(pos, Vector2i.ZERO)
            break
    var room: Room = main.current
    p.global_position = Vector2(0, -60)
    room._begin_arena()
    await _wait(2.5)
    for i in 2:
        room.banked.append(Items.offer(Drops.roll_item(main.difficulty() + 4, Items.Rarity.UNCOMMON, [], 0.0, "", main.players), 0))
    for i in 40:
        var s := Scrap.new(1, main)
        s.position = Vector2(randf_range(-480, 480), randf_range(-300, 300))
        room.pickups.add_child(s)
    await _wait(1.0)
    room.wave_time_left = 0.02
    await _wait(0.25)
    await _shot("spoils_vacuum")
    await _wait(1.5)
    var row: Array = room.pedestals.filter(func(pd): return is_instance_valid(pd) and not pd.empty())
    if not row.is_empty():
        var mid: Pedestal = row[mini(1, row.size() - 1)]
        p.global_position = mid.global_position + Vector2(0, 34)
    await _wait(0.6)
    await _shot("spoils")
    if not row.is_empty():
        var mid2: Pedestal = row[mini(1, row.size() - 1)]
        room.activate(mid2, p)
    await _wait(0.4)
    await _shot("spoils_salvage")
    # Ring swap: both rings worn, a third on a plinth.
    p.equip("copper_ring")
    p.equip("leech_mail")
    room.data.stock.append(Items.offer("alembic", 0, Vector2(-260, -140)))
    room._build_pedestals()
    p.global_position = Vector2(-260, -106)
    await _wait(0.6)
    await _shot("ring_swap_a")
    await _wait(0.4)
    await _shot("ring_swap_b")
    # A gun you already carry: it merges.
    room.data.stock.append(FloorGen.offer("gun", "blowtorch", 0))
    room.data.stock[room.data.stock.size() - 1]["pos"] = Vector2(260, -140)
    room._build_pedestals()
    p.global_position = Vector2(260, -106)
    await _wait(0.6)
    await _shot("merge")
    print("[PAYOUT-SHOT] done")
    main.get_tree().quit()


func _opts(ids: Array) -> Array:
    var by_id := {}
    for o in LevelUps.options():
        by_id[o["id"]] = o
    var out: Array = []
    for id in ids:
        if by_id.has(id):
            out.append((by_id[id] as Dictionary).duplicate(true))
        else:
            print("[PAYOUT-SHOT] unknown option %s" % id)
    return out


func _wait(secs: float) -> void:
    await get_tree().create_timer(secs, true, false, true).timeout


func _shot(name_: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png("res://autotest/%s.png" % name_)
        print("[PAYOUT-SHOT] autotest/%s.png" % name_)
