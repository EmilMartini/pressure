class_name Hud
extends Control
## Immediate-mode HUD: floor and room status, boss bar, minimap, one panel per
## player, announcements, help overlay, game over and victory.

const PANEL_W := 280.0
const PANEL_H := 210.0
const CELL := 14.0
const CELL_GAP := 3.0

var main: Main
var _font: Font
var _toasts: Array = []   # { text, t }


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _font = Art.FONT


func toast(text: String) -> void:
    _toasts.append({ "text": text, "t": 5.0 })


func _process(delta: float) -> void:
    for i in range(_toasts.size() - 1, -1, -1):
        _toasts[i]["t"] -= delta
        if _toasts[i]["t"] <= 0.0:
            _toasts.remove_at(i)
    queue_redraw()


func _draw() -> void:
    var vp := get_viewport_rect().size
    _draw_top(vp)
    _draw_minimap(vp)
    for p in main.players:
        _draw_player_panel(p, vp)
    if main.show_help:
        _draw_help(vp)
    _draw_toasts(vp)
    if main.game_over:
        _draw_banner(vp, "RUN OVER", "Floor %d, %d kills.  Press R or Start to restart." % [main.floor_number, main.total_kills], Color(1.0, 0.4, 0.3))
    elif main.victory:
        _draw_banner(vp, "DUNGEON CLEARED", "%d kills, %d scrap left.  Press R or Start for a new run." % [main.total_kills, main.scrap], Color(0.5, 1.0, 0.6))


func _draw_toasts(vp: Vector2) -> void:
    var y := 170.0
    for t in _toasts:
        var alpha: float = clampf(t["t"], 0.0, 1.0)
        draw_rect(Rect2(vp.x / 2.0 - 260, y - 20, 520, 28), Color(0, 0, 0, 0.55 * alpha))
        _centered(y, t["text"], 20, Color(0.6, 1.0, 0.8, alpha), vp)
        y += 32.0


func _centered(y: float, text: String, size: int, color: Color, vp: Vector2) -> void:
    draw_string(_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, size, color)


func _bar(rect: Rect2, fraction: float, color: Color) -> void:
    draw_rect(rect, Color(0, 0, 0, 0.5))
    draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), color)


func _draw_top(vp: Vector2) -> void:
    var room := main.current
    if room == null:
        return
    var text := "Floor %d   %s" % [main.floor_number, room.data.type_name()]
    if room.active and room.data.type == RoomData.Type.ARENA:
        text += "   %d s" % ceili(room.wave_time_left)
    _centered(36, text, 32, Color.WHITE, vp)
    _centered(58, "Scrap %d    Kills %d" % [main.scrap, main.total_kills], 18, Color(1.0, 0.9, 0.5, 0.8), vp)
    if room.boss != null and is_instance_valid(room.boss):
        var w := 420.0
        var r := Rect2(vp.x / 2.0 - w / 2.0, 70, w, 12)
        _bar(r, room.boss.hp / room.boss.max_hp, Color(0.85, 0.15, 0.25))
        if room.boss.shielded():
            draw_rect(r.grow(2.0), Color(1, 1, 1, 0.8), false, 2.0)
        _centered(96, "BOSS" + ("  (shielded)" if room.boss.shielded() else ""), 18, Color(1, 0.8, 0.8), vp)
    if main.message != "":
        _centered(130, main.message, 30, Color(1.0, 0.9, 0.4), vp)


func _draw_minimap(vp: Vector2) -> void:
    var origin := Vector2(vp.x / 2.0 + 190.0, 14.0)
    var pitch := CELL + CELL_GAP
    for pos in main.rooms.keys():
        var r: RoomData = main.rooms[pos]
        if not r.discovered:
            continue
        var cell := Rect2(origin + Vector2(pos.x, pos.y) * pitch, Vector2(CELL, CELL))
        var col: Color = r.color()
        if not r.visited:
            col = Color(col, 0.45)
        elif r.cleared:
            col = Color(col, 0.9)
        draw_rect(cell, col)
        if pos == main.current_pos:
            draw_rect(cell.grow(2.0), Color.WHITE, false, 2.0)
        # Door ticks toward known neighbours.
        for d in r.doors.keys():
            if r.doors[d]["obstacle"] != "":
                continue
            var c := cell.get_center() + Vector2(d.x, d.y) * (CELL / 2.0 + 1.0)
            draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1, 1, 1, 0.5))


func _draw_player_panel(p: Player, vp: Vector2) -> void:
    var origin: Vector2
    match p.index:
        0: origin = Vector2(16, 16)
        1: origin = Vector2(vp.x - PANEL_W - 16, 16)
        2: origin = Vector2(16, vp.y - PANEL_H - 16)
        _: origin = Vector2(vp.x - PANEL_W - 16, vp.y - PANEL_H - 16)
    draw_rect(Rect2(origin, Vector2(PANEL_W, PANEL_H)), Color(0, 0, 0, 0.45))
    var x := origin.x + 10.0
    var inner := PANEL_W - 20.0

    draw_string(_font, Vector2(x, origin.y + 20), "P%d" % (p.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, p.color)
    var mode := "AUTO-AIM" if p.auto_aim else "MANUAL AIM"
    draw_string(_font, Vector2(x, origin.y + 20), mode, HORIZONTAL_ALIGNMENT_RIGHT, inner, 18, Color(1, 1, 1, 0.8))

    _bar(Rect2(x, origin.y + 28, inner, 9), p.hp / p.max_hp, Color(0.35, 0.85, 0.4))

    var py := origin.y + 44.0
    draw_rect(Rect2(x, py, inner, 9), Color(0, 0, 0, 0.5))
    var half := inner / 2.0
    var cx := x + half
    var frac := p.pressure / Player.PRESSURE_LIMIT
    if frac > 0.0:
        draw_rect(Rect2(cx, py, half * frac, 9), Color(1.0, 0.4, 0.15))
    elif frac < 0.0:
        draw_rect(Rect2(cx + half * frac, py, -half * frac, 9), Color(0.4, 0.7, 1.0))
    draw_rect(Rect2(cx - 1, py - 2, 2, 13), Color.WHITE)
    draw_string(_font, Vector2(x, py + 20), "COLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.8, 1.0, 0.8))
    draw_string(_font, Vector2(x, py + 20), "PRESSURE", HORIZONTAL_ALIGNMENT_CENTER, inner, 14, Color(1, 1, 1, 0.6))
    draw_string(_font, Vector2(x, py + 20), "HOT", HORIZONTAL_ALIGNMENT_RIGHT, inner, 14, Color(1.0, 0.6, 0.4, 0.8))
    if p.overheated > 0.0:
        draw_string(_font, Vector2(x, py + 20), "OVERHEATED", HORIZONTAL_ALIGNMENT_CENTER, inner, 15, Color(1, 0.3, 0.1))
    elif p.frozen_up > 0.0:
        draw_string(_font, Vector2(x, py + 20), "FROZEN UP", HORIZONTAL_ALIGNMENT_CENTER, inner, 15, Color(0.6, 0.9, 1.0))

    var fy := origin.y + 70.0
    if not p.auto_aim:
        _bar(Rect2(x, fy, inner, 5), p.focus, Color(0.85, 0.5, 1.0))
        draw_string(_font, Vector2(x, fy + 16), "focus x%.2f" % p.focus_multiplier(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.5, 1.0, 0.9))

    var gy := origin.y + 100.0
    draw_string(_font, Vector2(x, gy), "Weight %d / %d" % [p.total_weight(), p.weight_capacity], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))
    gy += 16.0
    for g in p.guns:
        var label := g.data.display_name
        if g == p.primary:
            label = "> " + label + " (trigger)"
        draw_string(_font, Vector2(x, gy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, g.data.color())
        gy += 14.0
        if gy > origin.y + PANEL_H - 18.0:
            break

    if p.last_message != "":
        draw_string(_font, Vector2(x, origin.y + PANEL_H - 6), p.last_message, HORIZONTAL_ALIGNMENT_LEFT, inner, 16, Color(1.0, 0.9, 0.4))


func _draw_help(vp: Vector2) -> void:
    var lines := [
        "Move WASD / Left stick     Aim Mouse / Right stick     Fire primary LMB / RT     Interact E / A",
        "Toggle aim Tab / Y     Vent Space / LB     Swap primary Q / X     Join: Start on a pad",
        "Debug: 1-0 give P1 a gun     R restart     F1 hide help     F9 wipe save",
    ]
    var y := vp.y - 16.0 - 16.0 * lines.size()
    for line in lines:
        _centered(y, line, 16, Color(1, 1, 1, 0.55), vp)
        y += 16.0


func _draw_banner(vp: Vector2, title: String, sub: String, color: Color) -> void:
    var goals: Array = Progress.next_goals(3)
    var lines: Array = []
    if not Progress.run_unlocks.is_empty():
        var names: Array = []
        for u in Progress.run_unlocks:
            names.append(Progress.unlock_label(u))
        lines.append({ "text": "Unlocked this run: " + ", ".join(names), "color": Color(0.6, 1.0, 0.8) })
    for g in goals:
        lines.append({ "text": "%s  %d / %d   (%s)" % [g["name"], g["progress"], g["goal"], g["desc"]], "color": Color(0.8, 0.8, 0.85) })
    var h := 110.0 + 24.0 * lines.size()
    draw_rect(Rect2(0, vp.y / 2 - 60, vp.x, h), Color(0, 0, 0, 0.75))
    _centered(vp.y / 2 - 14, title, 48, color, vp)
    _centered(vp.y / 2 + 18, sub, 22, Color.WHITE, vp)
    var y := vp.y / 2 + 48
    for line in lines:
        _centered(y, line["text"], 18, line["color"], vp)
        y += 24.0
