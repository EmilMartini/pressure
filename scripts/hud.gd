class_name Hud
extends Control
## Immediate-mode HUD: wave timer, one panel per player, help overlay, game over.

const PANEL_W := 280.0
const PANEL_H := 210.0

var main: Main
var _font: Font


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    var vp := get_viewport_rect().size
    _draw_top(vp)
    for p in main.players:
        _draw_player_panel(p, vp)
    if main.show_help:
        _draw_help(vp)
    if main.game_over:
        _draw_game_over(vp)


func _centered(y: float, text: String, size: int, color: Color, vp: Vector2) -> void:
    draw_string(_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, size, color)


func _draw_top(vp: Vector2) -> void:
    var text: String
    if main.intermission > 0.0:
        text = "Wave %d starts in %d" % [main.wave + 1, ceili(main.intermission)]
    else:
        text = "WAVE %d    %d s" % [main.wave, ceili(main.wave_time_left)]
    _centered(36, text, 26, Color.WHITE, vp)
    _centered(58, "Kills %d    Enemies %d" % [main.total_kills, main.enemy_count()], 14, Color(1, 1, 1, 0.6), vp)


func _bar(rect: Rect2, fraction: float, color: Color) -> void:
    draw_rect(rect, Color(0, 0, 0, 0.5))
    draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), color)


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

    draw_string(_font, Vector2(x, origin.y + 20), "P%d" % (p.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, p.color)
    var mode := "AUTO-AIM" if p.auto_aim else "MANUAL AIM"
    draw_string(_font, Vector2(x, origin.y + 20), mode, HORIZONTAL_ALIGNMENT_RIGHT, inner, 13, Color(1, 1, 1, 0.8))

    # Health
    _bar(Rect2(x, origin.y + 28, inner, 9), p.hp / p.max_hp, Color(0.35, 0.85, 0.4))

    # Pressure: fills from the centre, red when hot, blue when cold.
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
    draw_string(_font, Vector2(x, py + 20), "COLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.8, 1.0, 0.8))
    draw_string(_font, Vector2(x, py + 20), "PRESSURE", HORIZONTAL_ALIGNMENT_CENTER, inner, 10, Color(1, 1, 1, 0.6))
    draw_string(_font, Vector2(x, py + 20), "HOT", HORIZONTAL_ALIGNMENT_RIGHT, inner, 10, Color(1.0, 0.6, 0.4, 0.8))
    if p.overheated > 0.0:
        draw_string(_font, Vector2(x, py + 20), "OVERHEATED", HORIZONTAL_ALIGNMENT_CENTER, inner, 11, Color(1, 0.3, 0.1))
    elif p.frozen_up > 0.0:
        draw_string(_font, Vector2(x, py + 20), "FROZEN UP", HORIZONTAL_ALIGNMENT_CENTER, inner, 11, Color(0.6, 0.9, 1.0))

    # Focus (manual aim only)
    var fy := origin.y + 70.0
    if not p.auto_aim:
        _bar(Rect2(x, fy, inner, 5), p.focus, Color(0.85, 0.5, 1.0))
        draw_string(_font, Vector2(x, fy + 16), "focus x%.2f" % p.focus_multiplier(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.5, 1.0, 0.9))

    # Arsenal
    var gy := origin.y + 100.0
    draw_string(_font, Vector2(x, gy), "Weight %d / %d" % [p.total_weight(), p.weight_capacity], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
    var gx := x
    gy += 16.0
    for g in p.guns:
        var label := g.data.display_name
        if g == p.primary:
            label = "> " + label + " (trigger)"
        draw_string(_font, Vector2(gx, gy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, g.data.color())
        gy += 14.0
        if gy > origin.y + PANEL_H - 18.0:
            break

    if p.last_message != "":
        draw_string(_font, Vector2(x, origin.y + PANEL_H - 6), p.last_message, HORIZONTAL_ALIGNMENT_LEFT, inner, 12, Color(1.0, 0.9, 0.4))


func _draw_help(vp: Vector2) -> void:
    var lines := [
        "Move WASD / Left stick     Aim Mouse / Right stick     Fire primary LMB / RT",
        "Toggle aim Tab / Y     Vent Space / LB     Swap primary Q / X     Join: Start on a pad",
        "Debug: 1-5 give P1 a gun     R restart     F1 hide help",
    ]
    var y := vp.y - 16.0 - 16.0 * lines.size()
    for line in lines:
        _centered(y, line, 12, Color(1, 1, 1, 0.55), vp)
        y += 16.0


func _draw_game_over(vp: Vector2) -> void:
    draw_rect(Rect2(0, vp.y / 2 - 50, vp.x, 100), Color(0, 0, 0, 0.7))
    _centered(vp.y / 2 - 8, "RUN OVER", 36, Color(1.0, 0.4, 0.3), vp)
    _centered(vp.y / 2 + 26, "Reached wave %d with %d kills.  Press R or Start to restart." % [main.wave, main.total_kills], 16, Color.WHITE, vp)
