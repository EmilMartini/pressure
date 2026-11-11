class_name InputProbe
extends RefCounted
## Bot probes for two bugs Emil hit on 2026-11-11 (bot runs only):
##   --reward-probe  a gun dropped in a challenge room and picked back up must leave the
##                   room's reward row standing; taking a reward card still clears it.
##   --modal-probe   the key / button that confirms a level-up must not reach the pedestal
##                   the player stands on (the stairs); a fresh press after the lockout does.
## Each prints one [REWARD-PROBE] / [MODAL-PROBE] PASS or FAIL line.


static func wanted(flag: String) -> bool:
    return OS.get_cmdline_user_args().has(flag)


static func _free_guns(main) -> void:
    var p: Player = main.players[0]
    if p.guns.is_empty():
        p.add_gun("water_pistol", false)


static func reward(main) -> void:
    var room: Room = Room.here
    var p: Player = main.players[0]
    main.bot_paused = true
    p.input.force_move = Vector2.ZERO
    _free_guns(main)
    var keep_type: int = room.data.type
    room.data.type = RoomData.Type.CHALLENGE
    var before: int = room.data.stock.size()
    room._reward_cards("challenge", "challenge", "boss", ["", "", ""], Items.Rarity.RARE, 90.0)
    var row: Array = room.data.stock.slice(before)
    room._build_pedestals()
    # Drop the gun from the character sheet's path and take that same gun back.
    var gun: Gun = p.guns[0]
    var gid := p.drop_gun(gun)
    room.add_floor_gun(gid, p.global_position + Vector2(0, 40))
    var dropped: Dictionary = room.data.stock[room.data.stock.size() - 1]
    var mine: Pedestal = null
    for ped in room.pedestals:
        if is_instance_valid(ped) and ped.offer == dropped:
            mine = ped
    var back := false
    if mine != null:
        room.activate(mine, p)
        for g in p.guns:
            back = back or g.data.id == gid
    var left := row.filter(func(o): return not o["taken"]).size()
    # Now take a real reward card (not a mod, which can wait on a gun choice).
    var card: Dictionary = {}
    for o in row:
        if o["kind"] == "gun" or (o["kind"] == "item" and String(Items.get_item(o["id"]).get("slot", "")) != "mod"):
            card = o
            break
    var after := -1
    if not card.is_empty():
        for ped in room.pedestals:
            if is_instance_valid(ped) and ped.offer == card:
                room.activate(ped, p)
        after = row.filter(func(o): return not o["taken"]).size()
    room.data.type = keep_type
    var ok := mine != null and back and left == row.size() and after == 0
    print("[REWARD-PROBE] %s row=%d regrab_left=%d gun_back=%s after_pick_left=%d" % [
        "PASS" if ok else "FAIL", row.size(), left, str(back), after])
    main.bot_paused = false


## One physics tick with `ev` fed through Input first (it updates Input's held state and
## reaches the level-up screen's _input / the focused card).
static func _feed(main, ev: InputEvent) -> void:
    Input.parse_input_event(ev)
    Input.flush_buffered_events()
    await main.get_tree().physics_frame


static func _key(pressed: bool) -> InputEventKey:
    var k := InputEventKey.new()
    k.physical_keycode = KEY_E
    k.keycode = KEY_E
    k.pressed = pressed
    return k


static func _pad(pressed: bool) -> InputEventJoypadButton:
    var b := InputEventJoypadButton.new()
    b.device = 0
    b.button_index = JOY_BUTTON_A
    b.pressed = pressed
    return b


## A free test plinth under the player; true once something activated it.
static func _plinth(room: Room, p: Player) -> Dictionary:
    var o := FloorGen.offer("repair", "repair", 0, 0)
    o["pos"] = room.to_local(p.global_position)
    room.data.stock.append(o)
    room._build_pedestals()
    return o


## `pad`: headless Godot has no connected joypad, so MenuPad (which reads connected pads)
## cannot see A; the case holds A through Input and confirms the focused card the way
## MenuPad's accept does, on that same frame.
static func _hold_case(main, label: String, down: InputEvent, up: InputEvent, pad := false) -> Array:
    var room: Room = Room.here
    var p: Player = main.players[0]
    var tree: SceneTree = main.get_tree()
    var o := _plinth(room, p)
    p.level = maxi(2, p.level)
    main.levelup.open(p)
    await tree.create_timer(LevelUpScreen.GRACE + 0.2, true).timeout
    var opened: bool = main.levelup.is_open()
    # Confirm the level-up and keep the button held for half a second on the plinth.
    if pad:
        Input.parse_input_event(down)
        Input.flush_buffered_events()
        var at: int = main.levelup._cards.find(main.get_viewport().gui_get_focus_owner())
        main.levelup._choose(maxi(0, at))
        await tree.physics_frame
    else:
        await _feed(main, down)
    for i in 30:
        await tree.physics_frame
    var closed: bool = not main.levelup.is_open()
    var leaked: bool = o["taken"]
    # Release, then a fresh press after the lockout: the plinth works again.
    await _feed(main, up)
    for i in 3:
        await tree.physics_frame
    await _feed(main, down)
    for i in 3:
        await tree.physics_frame
    await _feed(main, up)
    var fresh: bool = o["taken"]
    var ok := opened and closed and not leaked and fresh
    print("[MODAL-PROBE] %s %s opened=%s closed=%s leaked_to_world=%s fresh_press_works=%s" % [
        "PASS" if ok else "FAIL", label, str(opened), str(closed), str(leaked), str(fresh)])
    return [ok]


static func modal(main) -> void:
    var p: Player = main.players[0]
    main.bot_paused = true
    p.input.force_move = Vector2.ZERO
    p.input.lock_kind = true
    var all_ok := true
    var r: Array = await _hold_case(main, "keyboard_E", _key(true), _key(false))
    all_ok = all_ok and r[0]
    # Gamepad: A held through the confirm (MenuPad's accept), on the plinth.
    var keep_dev := p.input.device
    p.input.device = 0
    r = await _hold_case(main, "pad_A", _pad(true), _pad(false), true)
    all_ok = all_ok and r[0]
    p.input.device = keep_dev
    print("[MODAL-PROBE] %s overall" % ("PASS" if all_ok else "FAIL"))
    p.input.lock_kind = false
    main.bot_paused = false
