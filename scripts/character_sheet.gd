class_name CharacterSheet
extends PanelContainer
## One player's character screen, paper-doll style. Gear slots sit around the figure (the
## same form the player has in game), guns below, the focused thing's ItemCard in the
## middle and a grouped stat panel on the right.
##
## Controls (no Godot focus: the sheet polls pads itself and reads keys in _input):
##   d-pad / left stick / arrows / WASD  move through the slots and guns in reading order
##   A / Enter / Space                   Combine the focused gun with its twin
##   X / X / Delete                      Drop the focused gun on the floor
##   B / Esc                             Back (handled by the pause menu)
##   LB RB / Q E                         other player (handled by the pause menu)
##   right stick / Page Up Page Down     scroll the stat panel
## Opened from the pause menu, or with C / the pad's Back.

const PANEL_SIZE := Vector2(1240, 684)
const TOP := 56.0                 # header band (title and the prompt legend)
const SLOT_SIZE := 60.0
const DOLL_W := 400.0
const DOLL_H := 330.0
const GUN_CELL := 60.0
const GUN_GAP := 8.0
const GUNS_PER_ROW := 6
const CARD_X := 416.0
const CARD_W := 340.0
const STATS_X := 772.0
const STAT_LINE := 26.0
const STAT_HEAD := 32.0
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.11
const GOOD := Color(0.45, 0.95, 0.45)
const STAT_SWATCH := 10.0   # element swatch before an element stat's name

## Slot positions inside the doll (its top-left is (0, TOP)).
const SLOT_LAYOUT := {
    "head": Vector2(12, 24), "chest": Vector2(12, 96), "hands": Vector2(12, 168), "feet": Vector2(12, 240),
    "trinket1": Vector2(328, 24), "trinket2": Vector2(328, 96), "ring1": Vector2(328, 168), "ring2": Vector2(328, 240),
    "active": Vector2(170, 6),
}
## Reading order, row by row; up / down move between rows.
const SLOT_ROWS := [["head", "active", "trinket1"], ["chest", "trinket2"], ["hands", "ring1"], ["feet", "ring2"]]

var on_close: Callable
var player: Player
var _canvas: Control
var _stats_view: Control
var _cells: Array = []            # { kind: "slot" | "gun", key, gun, rect, row }
var _focus := 0
var _stats: Array = []            # { h } | { n, v, c } | { t, c }
var _stats_scroll := 0.0
var _stats_layout: Dictionary = {}
var _kind := "kb"
var _was: Dictionary = {}
var _held: Dictionary = {}
var _legend_rects: Dictionary = {}   # action -> Rect2, for mouse clicks
var _stats_mark := 0              # where the group being built starts in _stats


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = PANEL_SIZE
    size = custom_minimum_size
    _canvas = Control.new()
    _canvas.custom_minimum_size = PANEL_SIZE - Vector2(64, 32)
    _canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _canvas.mouse_filter = Control.MOUSE_FILTER_STOP
    _canvas.draw.connect(_draw_canvas)
    _canvas.gui_input.connect(_on_canvas_input)
    add_child(_canvas)
    _stats_view = Control.new()
    _stats_view.clip_contents = true
    _stats_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stats_view.position = Vector2(STATS_X, TOP)
    _stats_view.size = Vector2(_canvas.custom_minimum_size.x - STATS_X, _canvas.custom_minimum_size.y - TOP)
    _stats_view.draw.connect(_draw_stats)
    _canvas.add_child(_stats_view)


func show_player(p: Player) -> void:
    # The pause menu also maps the d-pad's left / right to "other player"; while the sheet
    # is up those buttons move through the grid instead, so ignore that switch.
    if is_visible_in_tree() and player != null and p != player and _dpad_sideways_down():
        return
    var first := player != p or not is_visible_in_tree()
    player = p
    if player != null and is_instance_valid(player) and player.input != null:
        _kind = player.input.last_kind
    _rebuild()
    if first:
        _focus = 0
        _stats_scroll = 0.0
    _prime_buttons()
    _redraw()


func _redraw() -> void:
    if _canvas != null:
        _canvas.queue_redraw()
    if _stats_view != null:
        _stats_view.queue_redraw()


func _rebuild() -> void:
    _cells.clear()
    if player == null or not is_instance_valid(player):
        return
    var row := 0
    for keys in SLOT_ROWS:
        for key in keys:
            var pos: Vector2 = SLOT_LAYOUT[key]
            _cells.append({ "kind": "slot", "key": key, "rect": Rect2(Vector2(pos.x, TOP + pos.y), Vector2(SLOT_SIZE, SLOT_SIZE)), "row": row })
        row += 1
    var gy := _guns_top() + 34.0
    for i in player.guns.size():
        var r := i / GUNS_PER_ROW
        var c := i % GUNS_PER_ROW
        var rect := Rect2(Vector2(float(c) * (GUN_CELL + GUN_GAP), gy + float(r) * (GUN_CELL + GUN_GAP)), Vector2(GUN_CELL, GUN_CELL))
        _cells.append({ "kind": "gun", "gun": player.guns[i], "rect": rect, "row": row + r })
    _focus = clampi(_focus, 0, maxi(0, _cells.size() - 1))
    _build_stats()


func _guns_top() -> float:
    return TOP + DOLL_H + 10.0


# --- Input -------------------------------------------------------------------------


func _input(event: InputEvent) -> void:
    if not is_visible_in_tree() or player == null:
        return
    if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
        if _kind != "pad":
            _kind = "pad"
            _redraw()
        return
    if not event is InputEventKey or not event.pressed:
        return
    if _kind != "kb":
        _kind = "kb"
        _redraw()
    var key := (event as InputEventKey).physical_keycode
    var handled := true
    match key:
        KEY_UP, KEY_W:
            _move(Vector2i(0, -1))
        KEY_DOWN, KEY_S:
            _move(Vector2i(0, 1))
        KEY_LEFT, KEY_A:
            _move(Vector2i(-1, 0))
        KEY_RIGHT, KEY_D:
            _move(Vector2i(1, 0))
        KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            if not event.echo:
                _combine()
        KEY_X, KEY_DELETE:
            if not event.echo:
                _drop()
        KEY_PAGEUP:
            _scroll_stats(-STAT_LINE * 6.0)
        KEY_PAGEDOWN:
            _scroll_stats(STAT_LINE * 6.0)
        _:
            handled = false
    if handled:
        get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
    if not is_visible_in_tree() or player == null:
        return
    if not is_instance_valid(player):
        player = null
        return
    var up := false
    var down := false
    var left := false
    var right := false
    var accept := false
    var drop := false
    var scroll := 0.0
    for d in Input.get_connected_joypads():
        var ax := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
        var ay := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
        up = up or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or ay < -0.55
        down = down or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or ay > 0.55
        left = left or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or ax < -0.55
        right = right or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or ax > 0.55
        accept = accept or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
        drop = drop or Input.is_joy_button_pressed(d, JOY_BUTTON_X)
        var ry := Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y)
        if absf(ry) > 0.25:
            scroll += ry
    if _edge("up", up, delta, true):
        _move(Vector2i(0, -1))
    if _edge("down", down, delta, true):
        _move(Vector2i(0, 1))
    if _edge("left", left, delta, true):
        _move(Vector2i(-1, 0))
    if _edge("right", right, delta, true):
        _move(Vector2i(1, 0))
    if _edge("accept", accept, delta, false):
        _combine()
    if _edge("drop", drop, delta, false):
        _drop()
    if scroll != 0.0:
        _scroll_stats(scroll * 700.0 * delta)
    _canvas.queue_redraw()   # the figure breathes and the aura pulses


## Buttons already held when the sheet opens (the A that pressed "Character") only count
## once they are released and pressed again.
func _prime_buttons() -> void:
    var accept := false
    var drop := false
    for d in Input.get_connected_joypads():
        accept = accept or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
        drop = drop or Input.is_joy_button_pressed(d, JOY_BUTTON_X)
    _was["accept"] = accept
    _was["drop"] = drop


func _dpad_sideways_down() -> bool:
    for d in Input.get_connected_joypads():
        if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT):
            return true
    return false


func _edge(key: String, down: bool, delta: float, repeat: bool) -> bool:
    var was: bool = _was.get(key, false)
    _was[key] = down
    if down and _kind != "pad":
        _kind = "pad"
    if not down:
        _held[key] = 0.0
        return false
    if not was:
        _held[key] = 0.0
        return true
    if not repeat:
        return false
    var h: float = float(_held.get(key, 0.0)) + delta
    if h >= REPEAT_DELAY:
        _held[key] = h - REPEAT_RATE
        return true
    _held[key] = h
    return false


func _on_canvas_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        var at := _cell_at((event as InputEventMouseMotion).position)
        if at >= 0 and at != _focus:
            _focus = at
            _redraw()
    elif event is InputEventMouseButton and event.pressed:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll_stats(-STAT_LINE * 2.0)
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll_stats(STAT_LINE * 2.0)
        elif mb.button_index == MOUSE_BUTTON_LEFT:
            for action in _legend_rects.keys():
                if (_legend_rects[action] as Rect2).has_point(mb.position):
                    match String(action):
                        "combine":
                            _combine()
                        "drop":
                            _drop()
                        "back":
                            if on_close.is_valid():
                                on_close.call()
                    return
            var at := _cell_at(mb.position)
            if at >= 0:
                _focus = at
                _redraw()


func _cell_at(pos: Vector2) -> int:
    for i in _cells.size():
        if (_cells[i]["rect"] as Rect2).has_point(pos):
            return i
    return -1


## Left / right walk the reading order (wrapping); up / down change row, keeping x.
func _move(dir: Vector2i) -> void:
    var n := _cells.size()
    if n == 0:
        return
    var from := _focus
    if dir.x != 0:
        _focus = wrapi(_focus + dir.x, 0, n)
    else:
        var row := int(_cells[_focus]["row"]) + dir.y
        var cx: float = (_cells[_focus]["rect"] as Rect2).get_center().x
        var best := -1
        var best_d := INF
        for i in n:
            if int(_cells[i]["row"]) != row:
                continue
            var d := absf((_cells[i]["rect"] as Rect2).get_center().x - cx)
            if d < best_d:
                best_d = d
                best = i
        if best >= 0:
            _focus = best
    if _focus != from:
        Sfx.play("ui_move")
        _redraw()


func _scroll_stats(amount: float) -> void:
    var max_scroll := maxf(0.0, float(_stats_layout.get("height", 0.0)) - _stats_view.size.y + 8.0)
    var was := _stats_scroll
    _stats_scroll = clampf(_stats_scroll + amount, 0.0, max_scroll)
    if was != _stats_scroll:
        _stats_view.queue_redraw()


func _focused() -> Dictionary:
    if _focus < 0 or _focus >= _cells.size():
        return {}
    return _cells[_focus]


func _focused_gun() -> Gun:
    var c := _focused()
    if c.is_empty() or c["kind"] != "gun":
        return null
    var g = c["gun"]
    if g == null or not is_instance_valid(g):
        return null
    return g


func _twin_of(g: Gun) -> Gun:
    if g == null or player == null:
        return null
    for pair in player.combinable_pairs():
        if pair[0] == g:
            return pair[1]
        if pair[1] == g:
            return pair[0]
    return null


# --- Actions -----------------------------------------------------------------------


func _combine() -> void:
    var g := _focused_gun()
    var twin := _twin_of(g)
    if g == null or twin == null:
        Sfx.play("error")
        return
    var result := player.combine(g, twin)
    _rebuild()
    if result != null:
        for i in _cells.size():
            if _cells[i]["kind"] == "gun" and _cells[i]["gun"] == result:
                _focus = i
                break
    _redraw()


func _drop() -> void:
    var g := _focused_gun()
    if g == null or player == null:
        Sfx.play("error")
        return
    var main := player.main()
    var id := player.drop_gun(g)
    if id != "" and main != null and main.current != null:
        main.current.add_floor_gun(id, player.global_position + Vector2(0, 40))
    Sfx.play("ui_back")
    _rebuild()
    _redraw()


# --- Drawing -----------------------------------------------------------------------


func _draw_canvas() -> void:
    if player == null or not is_instance_valid(player):
        return
    _draw_header()
    _draw_doll()
    _draw_guns()
    _draw_card()


func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
    var font: Font = Art.FONT
    _canvas.draw_string(font, pos + Vector2(1, 1), text, align, width, size, Color(0, 0, 0, 0.8))
    _canvas.draw_string(font, pos, text, align, width, size, color)


func _draw_header() -> void:
    var font: Font = Art.FONT
    var title := "%s   LEVEL %d" % [player.display_name().to_upper(), player.level]
    _text(Vector2(0, 34), title, 34, player.color)
    # Legend: the three actions in this device's buttons, right-aligned.
    var pad := _kind == "pad"
    var g := _focused_gun()
    var can_combine := _twin_of(g) != null
    var items := [
        ["combine", "A" if pad else "Enter", "Combine", can_combine],
        ["drop", "X", "Drop gun", g != null],
        ["back", "B" if pad else "Esc", "Back", true],
        ["player", "LB RB" if pad else "Q E", "Player", true],
    ]
    var x := _canvas.size.x
    var cy := 22.0
    _legend_rects.clear()
    for k in range(items.size() - 1, -1, -1):
        var it: Array = items[k]
        var label := String(it[2])
        var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
        var pw := _prompt_width(String(it[1]), pad, 28.0)
        x -= lw
        _text(Vector2(x, cy + 8.0), label, 22, UiTheme.BONE if bool(it[3]) else Color(UiTheme.DIM, 0.6))
        x -= 8.0 + pw
        if String(it[0]) == "player" and pad:
            var pill := 28.0 * 0.55 * 2.0 + 28.0 * 0.6
            Prompts.draw(_canvas, Vector2(x + pill / 2.0, cy), "LB", "pad", 28.0)
            Prompts.draw(_canvas, Vector2(x + pw - pill / 2.0, cy), "RB", "pad", 28.0)
        elif String(it[0]) == "player":
            Prompts.draw(_canvas, Vector2(x + 14.0, cy), "Q", "kb", 28.0)
            Prompts.draw(_canvas, Vector2(x + pw - 14.0, cy), "E", "kb", 28.0)
        else:
            Prompts.draw(_canvas, Vector2(x + pw / 2.0, cy), String(it[1]), "pad" if pad else "kb", 28.0)
        _legend_rects[it[0]] = Rect2(x - 4.0, cy - 18.0, pw + lw + 16.0, 36.0)
        x -= 28.0
    _canvas.draw_line(Vector2(0, TOP - 8.0), Vector2(_canvas.size.x, TOP - 8.0), Color(0.3, 0.26, 0.28), 2.0)


func _prompt_width(label: String, pad: bool, size: float) -> float:
    if label == "LB RB" or label == "Q E":
        return size * 2.0 + 16.0 if not pad else (size * 0.55 * 2.0 + size * 0.6) * 2.0 + 8.0
    if pad:
        if Prompts.FACE.has(label):
            return size
        return size * 0.55 * float(label.length()) + size * 0.6
    return maxf(size, size * 0.5 * float(label.length()) + size * 0.5)


func _draw_doll() -> void:
    var r := Rect2(Vector2(0, TOP), Vector2(DOLL_W, DOLL_H))
    _canvas.draw_rect(r, Color(0.05, 0.04, 0.06, 0.8))
    _canvas.draw_rect(r, Color(0.3, 0.26, 0.28), false, 2.0)
    var form: Dictionary = Items.form_for(player)
    var tint: Color = form["color"]
    var center := Vector2(DOLL_W / 2.0, TOP + 170.0)
    var t := float(Time.get_ticks_msec()) / 1000.0
    _canvas.draw_texture_rect(Art.PARTICLES["light"], Rect2(center - Vector2(130, 130), Vector2(260, 260)), false, Color(tint, 0.16))
    _canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(-50, 84), center + Vector2(50, 84), center + Vector2(60, 104), center + Vector2(-60, 104)]), Color(0.3, 0.27, 0.29))
    # The figure is the same generated one as in game, at 9 screen px per figure pixel
    # (nearest filtering on the canvas keeps it crisp).
    var bob := sin(t * 2.0) * 3.0
    var body_center := center + Vector2(0, -8.0 + bob)
    Items.draw_costume(_canvas, player, body_center, 9.0, 1.0, false)
    var frames: Array = form["frames"]
    var doll_tex: Texture2D = frames[0]
    _canvas.draw_texture_rect(doll_tex, Rect2(body_center - Vector2(72, 72), Vector2(144, 144)), false, Color.WHITE)
    Items.draw_costume(_canvas, player, body_center, 9.0, 1.0, true)
    var form_name := String(form["name"])
    var name_size := 22 if form_name.length() <= 18 else 20
    _text(Vector2(center.x - 120.0, TOP + 290.0), form_name, name_size, tint.lerp(Color.WHITE, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 240.0)
    _text(Vector2(center.x - 120.0, TOP + 316.0), "%d / %d HP" % [int(ceilf(player.hp)), int(player.max_hp)], 20, UiTheme.BONE, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
    for i in _cells.size():
        var c: Dictionary = _cells[i]
        if c["kind"] == "slot":
            _draw_slot(c, i == _focus)


func _draw_slot(c: Dictionary, focused: bool) -> void:
    var key := String(c["key"])
    var rect: Rect2 = c["rect"]
    var filled := player.equipment.has(key)
    var it: Dictionary = Items.get_item(player.equipment[key]) if filled else {}
    var border := Items.rarity_color(it) if filled else Color(0.3, 0.27, 0.3)
    if focused:
        _canvas.draw_rect(rect.grow(6.0), Color(border, 0.3))
    _canvas.draw_rect(rect, Color(0.08, 0.06, 0.08, 0.95))
    if filled:
        var charged := key != "active" or player.active_charges > 0
        Art.draw_icon(_canvas, Items.icon(it), rect.grow(-4.0), Items.ui_icon_tint(it) if charged else Color(0.4, 0.38, 0.4))
        # Rarity as a count too (1 Common .. 5 Legendary), top-left: not colour alone.
        ItemCard.draw_pips(_canvas, rect.position + Vector2(5, 5), int(it.get("rarity", 0)) + 1, border)
        if key == "active":
            var max_charges := Items.active_max_charges(player)
            for k in max_charges:
                var pip := Rect2(rect.position.x + 5.0 + float(k) * 9.0, rect.end.y - 9.0, 7.0, 5.0)
                _canvas.draw_rect(pip, Color(1.0, 0.9, 0.4) if k < player.active_charges else Color(0.25, 0.22, 0.24))
    else:
        Art.draw_icon(_canvas, Items.slot_icon(key), rect.grow(-4.0), Color(0.32, 0.3, 0.32, 0.8))
    _canvas.draw_rect(rect, Color.WHITE if focused else border, false, 3.0 if focused else 2.0)


func _draw_guns() -> void:
    var top := _guns_top()
    var slots := player.gun_slots()
    var line := "GUNS  %d / %d      WEIGHT  %d / %d" % [player.guns.size(), slots, player.total_weight(), player.weight_capacity]
    _text(Vector2(0, top + 22.0), line, 22, UiTheme.BONE)
    var gy := top + 34.0
    for i in slots:
        var r := i / GUNS_PER_ROW
        var col := i % GUNS_PER_ROW
        var rect := Rect2(Vector2(float(col) * (GUN_CELL + GUN_GAP), gy + float(r) * (GUN_CELL + GUN_GAP)), Vector2(GUN_CELL, GUN_CELL))
        if i >= player.guns.size():
            _canvas.draw_rect(rect, Color(0.06, 0.05, 0.06, 0.8))
            _canvas.draw_rect(rect, Color(0.22, 0.2, 0.22), false, 1.0)
    for i in _cells.size():
        var c: Dictionary = _cells[i]
        if c["kind"] != "gun":
            continue
        var g = c["gun"]
        if g == null or not is_instance_valid(g):
            continue
        var rect: Rect2 = c["rect"]
        var focused := i == _focus
        # Frame and tier pips in the tier's rarity colour (Items.tier_color); the element
        # is only a small swatch, top-left (GDD 6, "Rarity owns colour").
        var ec: Color = Items.tier_color(int(g.tier))
        if focused:
            _canvas.draw_rect(rect.grow(6.0), Color(ec, 0.3))
        _canvas.draw_rect(rect, Color(0.08, 0.06, 0.08, 0.95))
        Art.draw_icon(_canvas, Art.gun_icon(g.data.id), rect.grow(-4.0))
        ItemCard.draw_pips(_canvas, Vector2(rect.position.x + 5.0, rect.end.y - 9.0), int(g.tier), ec, 5.0)
        var sw := Rect2(rect.position + Vector2(5, 5), Vector2(7, 7))
        _canvas.draw_rect(sw.grow(1.0), Color(0, 0, 0, 0.85))
        _canvas.draw_rect(sw, Element.COLORS[g.data.element])
        var m := 0
        for id in g.mods:
            var dot := Vector2(rect.end.x - 7.0 - float(m) * 9.0, rect.position.y + 7.0)
            _canvas.draw_circle(dot, 4.5, Color(0, 0, 0, 0.8))
            _canvas.draw_circle(dot, 3.5, Items.rarity_color(Items.get_item(String(id))))
            m += 1
        if _twin_of(g) != null:
            # A twin at the same tier: a pulsing green corner says "combine me".
            var pulse := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) / 180.0)
            _canvas.draw_colored_polygon(PackedVector2Array([rect.end - Vector2(18, 0), rect.end, rect.end - Vector2(0, 18)]), Color(GOOD, pulse))
        _canvas.draw_rect(rect, Color.WHITE if focused else ec, false, 3.0 if focused else 2.0)


func _draw_card() -> void:
    var c := _focused()
    if c.is_empty():
        return
    var avail := _canvas.size.y - TOP
    var rect := Rect2(Vector2(CARD_X, TOP), Vector2(CARD_W, 0))
    if c["kind"] == "gun":
        var g = c["gun"]
        if g == null or not is_instance_valid(g):
            return
        var gun_opts := { "gun": g, "player": player, "width": CARD_W }
        if _twin_of(g) != null:
            gun_opts["notes"] = ["Combine merges the pair into one gun a tier higher."]
        if ItemCard.gun_height(g.data, gun_opts) > avail:
            gun_opts["compact"] = true
        ItemCard.draw_gun(_canvas, rect, g.data, gun_opts)
        return
    var key := String(c["key"])
    if player.equipment.has(key):
        var it: Dictionary = Items.get_item(player.equipment[key])
        var opts := { "player": player, "width": CARD_W }
        if it.has("active"):
            opts["notes"] = ["Charges %d / %d. A cleared room refills one." % [player.active_charges, Items.active_max_charges(player)]]
        ItemCard.draw(_canvas, rect, it, opts)
    else:
        var slot := key.rstrip("12")
        ItemCard.draw_note(_canvas, rect, String(ItemCard.SLOT_TITLES.get(slot, slot.capitalize())), "Empty slot",
            "Gear drops from elites and bosses, and sits in shops and treasure rooms.", Items.slot_icon(slot))


# --- Stats -------------------------------------------------------------------------


func _pct(v: float) -> String:
    return "%+d%%" % roundi(v * 100.0)


## `el`: an Element.Kind drawn as a small swatch before the name (NONE for none).
func _add(name: String, value: String, color: Color = UiTheme.BONE, el: int = Element.Kind.NONE) -> void:
    _stats.append({ "n": name, "v": value, "c": color, "el": el })


## Rows only for stats that are not zero, under a header per group (headers with no rows
## are dropped).
func _build_stats() -> void:
    _stats.clear()
    var p := player
    var groups: Array = []

    _stats_begin()
    _add("Max HP", "%d / %d" % [int(ceilf(p.hp)), int(p.max_hp)])
    _nz("Armour", p.stat("armor"), "%d" % int(p.stat("armor")))
    _nz("Dodge", p.stat("dodge"), "%d%%" % roundi(p.stat("dodge") * 100.0))
    _nz("Regen", p.stat("regen"), "%.1f / s" % p.stat("regen"))
    _nz("Thorns", p.stat("thorns"), "%d" % int(p.stat("thorns")))
    _nz("Lifesteal", p.stat("lifesteal"), "%d / reaction, max %d/s" % [int(p.stat("lifesteal")), int(p.stat("lifesteal") * Player.LEECH_PER_SEC)])
    _add("Speed", "%d  (%s)" % [int(p.move_speed()), _pct(p.stat("speed"))])
    groups.append(["DEFENCE", _stats_end()])

    _stats_begin()
    _nz("Damage", p.stat("dmg"), _pct(p.stat("dmg")))
    _nz("Fire rate", p.stat("fire_rate"), _pct(p.stat("fire_rate")))
    _nz("Crit chance", p.stat("crit"), "%d%%" % roundi(p.stat("crit") * 100.0))
    if p.stat("crit") > 0.0 or p.stat("crit_dmg") != 0.0:
        _add("Crit damage", "x%.2f" % (2.0 + p.stat("crit_dmg")))
    _nz("Projectiles", p.stat("proj_count"), "%+d" % int(p.stat("proj_count")))
    _nz("Pierce", p.stat("pierce"), "%+d" % int(p.stat("pierce")))
    _nz("Bounce", p.stat("bounce"), "%+d" % int(p.stat("bounce")))
    _nz("Range", p.stat("range"), _pct(p.stat("range")))
    _nz("Shot speed", p.stat("proj_speed") + p.stat("shot_speed"), _pct(p.stat("proj_speed") + p.stat("shot_speed")))
    _nz("Shot size", p.stat("shot_size"), _pct(p.stat("shot_size")))
    _nz("Homing", p.stat("homing"), "%.1f" % p.stat("homing"))
    _nz("Splash", p.stat("splash"), "+%d px" % int(p.stat("splash")))
    _nz("Shards", p.stat("shards"), "%d" % int(p.stat("shards")))
    _nz("Spectral", p.stat("spectral"), "yes")
    _nz("Boomerang", p.stat("boomerang"), "yes")
    _nz("Familiars", p.stat("orbitals"), "%d" % int(p.stat("orbitals")))
    groups.append(["OFFENCE", _stats_end()])

    _stats_begin()
    _nz("Potency", p.stat("potency"), _pct(p.stat("potency")))
    for e in Element.ALL:
        var ek: String = Items.ELEMENT_KEYS[e]
        var el_name := String(Element.NAMES[e])
        # Neutral text with an element swatch before the name, never element-coloured text.
        _nz("%s damage" % el_name, p.stat("dmg_" + ek), _pct(p.stat("dmg_" + ek)), UiTheme.BONE, e)
        _nz("%s potency" % el_name, p.stat("potency_" + ek), _pct(p.stat("potency_" + ek)), UiTheme.BONE, e)
    _nz("Duration", p.stat("state_duration"), _pct(p.stat("state_duration")))
    _nz("Chain jumps", p.stat("chain_jumps"), "%+d" % int(p.stat("chain_jumps")))
    _nz("Burn, poison, bleed", p.stat("dot_power"), _pct(p.stat("dot_power")))
    _nz("Fusion damage", p.stat("fusion_power"), _pct(p.stat("fusion_power")))
    _nz("Cataclysm damage", p.stat("cataclysm_power"), _pct(p.stat("cataclysm_power")))
    _nz("Compound lifetime", p.stat("compound_life"), _pct(p.stat("compound_life")))
    _nz("Field lifetime", p.stat("field_life"), _pct(p.stat("field_life")))
    for ek in LevelUps.ELEMENT_BOONS.keys():
        var echo := float(p.bonus_stats.get("echo_" + ek, 0.0))
        _nz("%s Echo" % String(ek).capitalize(), echo, "%d%%" % roundi(echo * 100.0), UiTheme.BONE, Items.ELEMENTS[ek])
    groups.append(["ELEMENTS", _stats_end()])

    _stats_begin()
    var limit := p.pressure_limit()
    _nz("Pressure limit", limit - Player.PRESSURE_LIMIT, "%d" % int(limit))
    _nz("Vent charge speed", p.stat("vent_charge"), _pct(p.stat("vent_charge")))
    _nz("Vent radius", p.stat("vent_radius"), _pct(p.stat("vent_radius")))
    _nz("Vent power", p.stat("vent_power"), _pct(p.stat("vent_power")))
    groups.append(["PRESSURE", _stats_end()])

    _stats_begin()
    _nz("Last Breath", p.revives_left, "%d revive%s left" % [p.revives_left, "" if p.revives_left == 1 else "s"], Mastery.EMBER_COLOR)
    _nz("Level-up rerolls", p.levelup_rerolls, "%d left" % p.levelup_rerolls)
    _nz("Level-up cards", Mastery.bonus("levelup_extra"), "4 every level-up" if Mastery.bonus("levelup_extra") >= 2.0 else "4 every other level-up")
    _nz("High Confidence", Mastery.cond_bonus("dmg", p), "%s damage" % _pct(Mastery.cond_bonus("dmg", p)))
    groups.append(["SHRINE", _stats_end()])

    _stats_begin()
    _add("XP", "%d / %d" % [int(p.xp), int(p.xp_to_next())])
    _nz("XP gain", p.stat("xp_gain"), _pct(p.stat("xp_gain")))
    _nz("Scrap gain", p.stat("scrap_gain"), _pct(p.stat("scrap_gain")))
    _nz("Luck", p.stat("luck"), _pct(p.stat("luck")))
    groups.append(["PROGRESS", _stats_end()])

    _stats_begin()
    var counts := Items.set_counts(p)
    for sid in counts.keys():
        var s: Dictionary = Items.SETS[sid]
        var have := int(counts[sid])
        var col := ItemCard.SET_COL   # not the set's element colour: names stay neutral
        _add(String(s["name"]), "%d / %d" % [have, (s["items"] as Array).size()], col)
        var thresholds: Array = s["bonuses"].keys()
        thresholds.sort()
        for th in thresholds:
            var bits: Array = []
            for bk in s["bonuses"][th].keys():
                bits.append(ItemCard.stat_line(String(bk), s["bonuses"][th][bk]))
            var on := have >= int(th)
            if on or th == _next_threshold(thresholds, have):
                _stats.append({ "t": "%s %d: %s" % ["*" if on else "next", int(th), ", ".join(bits)], "c": GOOD if on else UiTheme.DIM })
    groups.append(["SETS", _stats_end()])

    _stats.clear()
    for grp in groups:
        var entries: Array = grp[1]
        if entries.is_empty():
            continue
        _stats.append({ "h": grp[0] })
        _stats.append_array(entries)
    _layout_stats()


func _stats_begin() -> void:
    _stats_mark = _stats.size()


func _stats_end() -> Array:
    var out: Array = _stats.slice(_stats_mark)
    return out


func _nz(name: String, v: float, text: String, color: Color = UiTheme.BONE, el: int = Element.Kind.NONE) -> void:
    if absf(v) > 0.0001:
        _add(name, text, color, el)


func _next_threshold(thresholds: Array, have: int) -> int:
    for th in thresholds:
        if int(th) > have:
            return int(th)
    return -1


func _entry_height(e: Dictionary, width: float) -> float:
    if e.has("h"):
        return STAT_HEAD
    if e.has("t"):
        return float(ItemCard._wrap(String(e["t"]), 20, width - 12.0).size()) * 24.0
    return STAT_LINE


## Two columns when every row fits half the width and one column would overflow.
func _layout_stats() -> void:
    var w := _stats_view.size.x
    var half := (w - 16.0) / 2.0
    var font: Font = Art.FONT
    var fits_half := true
    var total := 0.0
    for e in _stats:
        total += _entry_height(e, w)
        if e.has("n"):
            var need := font.get_string_size(String(e["n"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + font.get_string_size(String(e["v"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 18.0
            if int(e.get("el", Element.Kind.NONE)) != Element.Kind.NONE:
                need += STAT_SWATCH + 6.0
            if need > half:
                fits_half = false
    var cols := 1
    if total > _stats_view.size.y and fits_half:
        cols = 2
    var col_w := w if cols == 1 else half
    var placed: Array = []   # [entry, column, y]
    var heights: Array = [0.0, 0.0]
    if cols == 1:
        var y := 0.0
        for e in _stats:
            placed.append([e, 0, y])
            y += _entry_height(e, col_w)
        heights[0] = y
    else:
        # Fill the left column to about half, breaking only before a header.
        var target := 0.0
        for e in _stats:
            target += _entry_height(e, col_w)
        target /= 2.0
        var col := 0
        var y := 0.0
        for e in _stats:
            if col == 0 and e.has("h") and y >= target * 0.8:
                heights[0] = y
                col = 1
                y = 0.0
            placed.append([e, col, y])
            y += _entry_height(e, col_w)
        heights[col] = y
    _stats_layout = { "cols": cols, "col_w": col_w, "placed": placed, "height": maxf(heights[0], heights[1]) }
    _stats_scroll = clampf(_stats_scroll, 0.0, maxf(0.0, float(_stats_layout["height"]) - _stats_view.size.y + 8.0))


func _draw_stats() -> void:
    if player == null or _stats_layout.is_empty():
        return
    var v := _stats_view
    var font: Font = Art.FONT
    v.draw_rect(Rect2(Vector2.ZERO, v.size), Color(0.05, 0.04, 0.06, 0.6))
    var col_w := float(_stats_layout["col_w"])
    for p in _stats_layout["placed"]:
        var e: Dictionary = p[0]
        var x := 8.0 + float(p[1]) * (col_w + 16.0)
        var y := float(p[2]) - _stats_scroll
        if y > v.size.y or y + 60.0 < 0.0:
            continue
        if e.has("h"):
            # Neutral headings: orange here read as Legendary next to the cards.
            v.draw_string(font, Vector2(x, y + 24.0), String(e["h"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiTheme.BONE)
            v.draw_line(Vector2(x, y + 29.0), Vector2(x + col_w - 16.0, y + 29.0), Color(UiTheme.BONE, 0.3), 1.0)
        elif e.has("t"):
            var ty := y
            for line in ItemCard._wrap(String(e["t"]), 20, col_w - 12.0):
                v.draw_string(font, Vector2(x + 8.0, ty + 19.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, e["c"])
                ty += 24.0
        else:
            var nx := x
            var el := int(e.get("el", Element.Kind.NONE))
            if el != Element.Kind.NONE:
                var sq := Rect2(Vector2(x + 1.0, y + 7.0), Vector2(STAT_SWATCH, STAT_SWATCH))
                v.draw_rect(sq.grow(1.0), Color(0, 0, 0, 0.9))
                v.draw_rect(sq, Element.COLORS[el])
                nx += STAT_SWATCH + 6.0
            v.draw_string(font, Vector2(nx, y + 20.0), String(e["n"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.DIM)
            v.draw_string(font, Vector2(x, y + 20.0), String(e["v"]), HORIZONTAL_ALIGNMENT_RIGHT, col_w - 16.0, 20, e["c"])
    # Scroll hint when there is more below or above.
    var max_scroll := float(_stats_layout["height"]) - v.size.y + 8.0
    if max_scroll > 0.0:
        var hint := "RS scroll" if _kind == "pad" else "PgUp PgDn scroll"
        var bar_h := v.size.y * v.size.y / float(_stats_layout["height"])
        var bar_y := (_stats_scroll / max_scroll) * (v.size.y - bar_h)
        v.draw_rect(Rect2(v.size.x - 5.0, bar_y, 4.0, bar_h), Color(UiTheme.BONE, 0.5))
        v.draw_rect(Rect2(0, v.size.y - 26.0, v.size.x, 26.0), Color(0.05, 0.04, 0.06, 0.9))
        v.draw_string(font, Vector2(8, v.size.y - 6.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.DIM)
