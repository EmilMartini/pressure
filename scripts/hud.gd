class_name Hud
extends Control
## In-run HUD, Brotato and Isaac style: big readable bars, gun icons, a minimap with
## room icons, a large wave timer, scrap with its cog, toasts and announcements.

const PANEL_W := 316.0
const PANEL_H := 190.0
const CELL := 22.0
const CELL_GAP := 5.0

const ROOM_ICONS := {
    RoomData.Type.START: Vector2i(41, 16),
    RoomData.Type.BOSS: Vector2i(38, 11),
    RoomData.Type.SHOP: Vector2i(36, 16),
    RoomData.Type.TREASURE: Vector2i(9, 11),
    RoomData.Type.CHALLENGE: Vector2i(28, 12),
    RoomData.Type.HIDDEN: Vector2i(37, 13),
}

var main: Main
var _font: Font
var _toasts: Array = []   # { text, t }
var _time := 0.0


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _font = Art.FONT


func toast(text: String) -> void:
    _toasts.append({ "text": text, "t": 5.0 })


func _process(delta: float) -> void:
    _time += delta
    for i in range(_toasts.size() - 1, -1, -1):
        _toasts[i]["t"] -= delta
        if _toasts[i]["t"] <= 0.0:
            _toasts.remove_at(i)
    queue_redraw()


func _draw() -> void:
    var vp := get_viewport_rect().size
    _draw_top(vp)
    _draw_minimap(vp)
    for i in main.players.size():
        _draw_player_panel(main.players[i], Vector2(16, 16 + float(i) * (PANEL_H + 10.0)))
    if main.show_help:
        _draw_help(vp)
    _draw_toasts(vp)


# --- Helpers ---------------------------------------------------------------


func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shadow := true) -> void:
    if shadow:
        draw_string(_font, pos + Vector2(2, 2), text, align, width, size, Color(0, 0, 0, 0.7 * color.a))
    draw_string(_font, pos, text, align, width, size, color)


func _centered(y: float, text: String, size: int, color: Color, vp: Vector2) -> void:
    _text(Vector2(0, y), text, size, color, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _bar(rect: Rect2, fraction: float, color: Color, border := Color(0, 0, 0, 0.8)) -> void:
    draw_rect(rect, Color(0.05, 0.04, 0.05, 0.85))
    draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), color)
    draw_rect(rect.grow(1.0), border, false, 2.0)


func _icon(coord: Vector2i, rect: Rect2, color: Color) -> void:
    draw_texture_rect(Art.tile(coord), rect, false, color)


# --- Top: room, timer, boss, scrap ----------------------------------------


func _draw_top(vp: Vector2) -> void:
    var room := main.current
    if room == null:
        return
    var cx := vp.x / 2.0
    _centered(30, "FLOOR %d   %s" % [main.floor_number, room.data.type_name().to_upper()], 24, Color(room.data.color(), 0.95), vp)
    if room.active and room.data.type == RoomData.Type.ARENA:
        var secs := ceili(room.wave_time_left)
        var col := Color(1.0, 0.35, 0.3) if secs <= 5 else UiTheme.BONE
        var size := 64 if secs > 5 else 72 + int(8.0 * absf(sin(_time * 8.0)))
        _centered(92, str(secs), size, col, vp)
    elif room.boss != null and is_instance_valid(room.boss):
        var w := 560.0
        var r := Rect2(cx - w / 2.0, 54, w, 20)
        _bar(r, room.boss.hp / room.boss.max_hp, Color(0.85, 0.15, 0.25))
        if room.boss.shielded():
            draw_rect(r.grow(3.0), Color(1, 1, 1, 0.5 + 0.4 * absf(sin(_time * 6.0))), false, 3.0)
            var b := room.boss
            var wn := b.weakness_name()
            var pair := "%s + %s" % [Element.NAMES[b.weakness.x], Element.NAMES[b.weakness.y]]
            _centered(100, "SHIELD attuned to %s (%s)   %d / %d cracks" % [wn.to_upper(), pair, b.shield_hp, b.shield_max], 20, Color(1, 1, 1, 0.9), vp)
        else:
            _centered(100, "BOSS", 20, Color(1, 0.8, 0.8), vp)
    elif room.active:
        _centered(80, "FIGHT", 40, Color(1.0, 0.5, 0.4), vp)
    else:
        var hint := ""
        match room.data.type:
            RoomData.Type.CHALLENGE:
                hint = "Doors stay open. Touch the sigil to begin." if not room.data.cleared else "Cleared"
            RoomData.Type.SHOP:
                hint = "Scrap buys guns, carry capacity and repairs"
            RoomData.Type.TREASURE:
                hint = "Take one"
            RoomData.Type.START:
                hint = "Pick a door"
            _:
                hint = "Cleared" if room.data.cleared else ""
        if hint != "":
            _centered(70, hint, 20, UiTheme.DIM, vp)

    # Scrap with its cog, to the right of the title.
    var sx := cx + 230.0
    _icon(Art.TILES["scrap"], Rect2(sx, 10, 34, 34), Art.SCRAP_TINT)
    _text(Vector2(sx + 42, 40), str(main.scrap), 36, Art.SCRAP_TINT)
    _text(Vector2(sx, 66), "KILLS %d" % main.total_kills, 16, UiTheme.DIM)

    if main.message != "":
        var pop: float = clampf((3.0 - main._message_time) / 0.15, 0.0, 1.0)
        _centered(150, main.message, int(26 + 12 * pop), Color(1.0, 0.9, 0.4), vp)


# --- Minimap ---------------------------------------------------------------


func _draw_minimap(vp: Vector2) -> void:
    var pitch := CELL + CELL_GAP
    var grid := float(FloorGen.GRID)
    var size := grid * pitch
    var origin := Vector2(vp.x - 16.0 - size, 16.0)
    draw_rect(Rect2(origin - Vector2(6, 6), Vector2(size + 12, size + 12)), Color(0, 0, 0, 0.45))
    for pos in main.rooms.keys():
        var r: RoomData = main.rooms[pos]
        if not r.discovered:
            continue
        var cell := Rect2(origin + Vector2(pos.x, pos.y) * pitch, Vector2(CELL, CELL))
        var col: Color = r.color()
        if not r.visited:
            col = Color(col, 0.35)
        elif not r.cleared:
            col = Color(col, 0.7)
        draw_rect(cell, Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, col.a))
        draw_rect(cell, col, false, 1.5)
        if ROOM_ICONS.has(r.type):
            _icon(ROOM_ICONS[r.type], cell.grow(-2.0), Color(1, 1, 1, col.a))
        for d in r.doors.keys():
            if r.doors[d]["obstacle"] != "":
                continue
            var c := cell.get_center() + Vector2(d.x, d.y) * (CELL / 2.0 + 2.0)
            draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 1, 0.6 * col.a))
        if pos == main.current_pos:
            draw_rect(cell.grow(3.0), Color(1, 1, 1, 0.6 + 0.4 * absf(sin(_time * 4.0))), false, 2.0)


# --- Player panel ----------------------------------------------------------


func _draw_player_panel(p: Player, origin: Vector2) -> void:
    draw_rect(Rect2(origin, Vector2(PANEL_W, PANEL_H)), Color(0.03, 0.02, 0.04, 0.72))
    draw_rect(Rect2(origin, Vector2(PANEL_W, PANEL_H)), Color(p.color, 0.5), false, 2.0)
    var x := origin.x + 10.0
    var y := origin.y + 10.0

    # Portrait
    var box := Rect2(x, y, 48, 48)
    draw_rect(box, Color(0.08, 0.06, 0.08))
    draw_rect(box, p.color, false, 2.0)
    var tiles: Array = Art.TILES["player"]
    var tint := p.color.lerp(Color.WHITE, 0.35) if p.alive else Color(0.3, 0.3, 0.3)
    _icon(tiles[p.index % tiles.size()], box.grow(-6.0), tint)
    _text(Vector2(x + 2, y + 62), "P%d" % (p.index + 1), 18, p.color)

    # Aim mode badge
    var bx := x + 64.0
    var badge := Rect2(origin.x + PANEL_W - 96, y, 86, 20)
    var badge_col := Color(0.25, 0.5, 0.9) if p.auto_aim else Color(0.75, 0.4, 0.95)
    draw_rect(badge, Color(badge_col, 0.85))
    _text(Vector2(badge.position.x, badge.position.y + 15), "AUTO" if p.auto_aim else "MANUAL", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, false)

    # Health
    var hp_rect := Rect2(bx, y + 24, PANEL_W - 84, 20)
    var hp_frac := p.hp / p.max_hp
    _bar(hp_rect, hp_frac, Color(0.85, 0.2, 0.2).lerp(Color(0.35, 0.85, 0.4), hp_frac))
    _text(Vector2(hp_rect.position.x, hp_rect.position.y + 15), "%d / %d" % [int(p.hp), int(p.max_hp)], 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, hp_rect.size.x)

    # Pressure gauge with cold and hot ends
    var gy := y + 50.0
    var g := Rect2(bx + 22, gy, PANEL_W - 84 - 44, 14)
    draw_rect(g, Color(0.05, 0.04, 0.05, 0.85))
    var half := g.size.x / 2.0
    var frac := p.pressure / p.pressure_limit()
    if frac > 0.0:
        draw_rect(Rect2(g.position.x + half, gy, half * frac, g.size.y), Color(1.0, 0.45, 0.15))
    elif frac < 0.0:
        draw_rect(Rect2(g.position.x + half + half * frac, gy, -half * frac, g.size.y), Color(0.45, 0.75, 1.0))
    draw_rect(g.grow(1.0), Color(0, 0, 0, 0.8), false, 2.0)
    draw_rect(Rect2(g.position.x + half - 1.5, gy - 3, 3, g.size.y + 6), Color.WHITE)
    _icon(Vector2i(40, 11), Rect2(bx, gy - 3, 20, 20), Color(0.6, 0.85, 1.0))
    draw_texture_rect(Art.PARTICLES["flame"], Rect2(g.end.x + 2, gy - 5, 24, 24), false, Color(1.0, 0.55, 0.2))
    if p.overheated > 0.0:
        _text(Vector2(g.position.x, gy + 12), "OVERHEATED", 14, Color(1, 0.3, 0.1), HORIZONTAL_ALIGNMENT_CENTER, g.size.x)
    elif p.frozen_up > 0.0:
        _text(Vector2(g.position.x, gy + 12), "FROZEN UP", 14, Color(0.6, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, g.size.x)

    # Focus, manual only
    if not p.auto_aim:
        var f := Rect2(bx, y + 70, PANEL_W - 84, 6)
        _bar(f, p.focus, Color(0.85, 0.5, 1.0))
        _text(Vector2(f.end.x - 80, y + 69), "FOCUS x%.2f" % p.focus_multiplier(), 13, Color(0.85, 0.5, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 80)

    # Gun icons with element frames; primary carries the trigger tag.
    var gx := x
    var gyy := y + 84.0
    for gun in p.guns:
        var slot := Rect2(gx, gyy, 36, 36)
        var ec: Color = gun.data.color()
        var is_primary := gun == p.primary
        draw_rect(slot, Color(0.08, 0.06, 0.08, 0.9))
        _icon(Art.gun_tile(gun.data.id), slot.grow(-4.0), ec)
        draw_rect(slot, Color.WHITE if is_primary else Color(ec, 0.8), false, 3.0 if is_primary else 1.5)
        if gun.mod != "":
            draw_rect(Rect2(gx + 26, gyy + 2, 8, 8), Items.rarity_color(Items.get_item(gun.mod)))
        if is_primary:
            draw_rect(Rect2(gx, gyy + 36, 36, 12), Color.WHITE)
            _text(Vector2(gx, gyy + 46), "RT", 11, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, 36, false)
        gx += 40.0
        if gx > origin.x + PANEL_W - 60:
            break

    # Gear slots: head, chest, hands, feet, rings, trinkets.
    var ex := x
    var ey := y + 136.0
    for key in Player.EQUIP_KEYS:
        var gbox := Rect2(ex, ey, 24, 24)
        var slot_name: String = key.rstrip("12")
        draw_rect(gbox, Color(0.08, 0.06, 0.08, 0.9))
        if p.equipment.has(key):
            var it := Items.get_item(p.equipment[key])
            _icon(Items.icon(it), gbox.grow(-3.0), Items.icon_tint(it))
            draw_rect(gbox, Items.rarity_color(it), false, 2.0)
        else:
            _icon(Items.SLOT_ICONS[slot_name], gbox.grow(-4.0), Color(0.3, 0.28, 0.3))
            draw_rect(gbox, Color(0.25, 0.22, 0.24), false, 1.0)
        ex += 28.0

    # Weight pips
    var wx := x
    var wy := y + 168.0
    for i in p.weight_capacity:
        var filled := i < p.total_weight()
        draw_rect(Rect2(wx + float(i) * 11.0, wy, 8, 8), UiTheme.BONE if filled else Color(0.25, 0.22, 0.24))
    _text(Vector2(wx + float(p.weight_capacity) * 11.0 + 8.0, wy + 8), "WEIGHT %d/%d" % [p.total_weight(), p.weight_capacity], 14, UiTheme.DIM)

    if p.last_message != "":
        _text(Vector2(origin.x + PANEL_W - 10, y + 68), p.last_message, 14, Color(1.0, 0.9, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, -1)


# --- Overlays --------------------------------------------------------------


func _draw_help(vp: Vector2) -> void:
    var lines := [
        "MOVE  WASD / left stick      AIM  mouse / right stick      FIRE PRIMARY  LMB / RT      INTERACT  E / A",
        "AIM MODE  Tab / Y      VENT  Space / LB      SWAP PRIMARY  Q / X      PAUSE  Esc / Start      JOIN  Start on a new pad",
    ]
    var y := vp.y - 14.0 - 22.0 * lines.size()
    draw_rect(Rect2(0, y - 22, vp.x, 22.0 * lines.size() + 14), Color(0, 0, 0, 0.55))
    for line in lines:
        _centered(y, line, 16, Color(0.85, 0.82, 0.78), vp)
        y += 22.0


func _draw_toasts(vp: Vector2) -> void:
    var y := 200.0
    for t in _toasts:
        var alpha: float = clampf(t["t"], 0.0, 1.0)
        var pop: float = clampf((5.0 - t["t"]) / 0.15, 0.0, 1.0)
        draw_rect(Rect2(vp.x / 2.0 - 300, y - 24, 600, 34), Color(0, 0, 0, 0.6 * alpha))
        draw_rect(Rect2(vp.x / 2.0 - 300, y - 24, 600, 34), Color(0.6, 1.0, 0.8, 0.5 * alpha), false, 2.0)
        _centered(y, t["text"], int(16 + 6 * pop), Color(0.6, 1.0, 0.8, alpha), vp)
        y += 40.0
