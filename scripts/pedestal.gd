class_name Pedestal
extends Node2D
## An interactable offer standing in a room: a gun for sale, an upgrade, the boss
## stairs, or the challenge sigil. The Room decides what activating it does.

const RANGE := 52.0

var offer: Dictionary
var highlighted := false


func _init(p_offer: Dictionary) -> void:
    offer = p_offer
    z_index = 3


func kind() -> String:
    return offer["kind"]


func title() -> String:
    match kind():
        "gun":
            var g := Guns.make(offer["id"])
            return "%s  (weight %d)" % [g.display_name, g.weight]
        "carry":
            return "Carry capacity +%d" % offer["amount"]
        "repair":
            return "Repair +%d HP" % offer["amount"]
        "stairs":
            return "Stairs down"
        "sigil":
            return "Challenge sigil"
    return "?"


func price_text() -> String:
    if kind() in ["stairs", "sigil"]:
        return ""
    return "FREE" if offer["price"] == 0 else "%d scrap" % offer["price"]


func color() -> Color:
    match kind():
        "gun":
            return Element.COLORS[Guns.make(offer["id"]).element]
        "carry":
            return Color(0.9, 0.9, 1.0)
        "repair":
            return Color(0.4, 0.9, 0.5)
        "stairs":
            return Color(0.7, 0.7, 0.7)
        "sigil":
            return Color(0.8, 0.4, 1.0)
    return Color.WHITE


func _process(_delta: float) -> void:
    queue_redraw()


func _draw() -> void:
    var c := color()
    if kind() == "sigil":
        draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 48, Color(c, 0.6), 3.0)
        draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 6, c, 2.0)
    elif kind() == "stairs":
        draw_rect(Rect2(-24, -16, 48, 32), Color(0.15, 0.15, 0.18))
        for i in 4:
            draw_line(Vector2(-24, -16 + i * 10), Vector2(24, -16 + i * 10), Color(0.5, 0.5, 0.55), 2.0)
    else:
        draw_circle(Vector2.ZERO, 18.0, Color(0.18, 0.18, 0.22))
        draw_circle(Vector2(0, -6), 9.0, c)
    if highlighted:
        draw_arc(Vector2.ZERO, RANGE - 8.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 1.5)
    var font := ThemeDB.fallback_font
    draw_string(font, Vector2(-120, 36), title(), HORIZONTAL_ALIGNMENT_CENTER, 240, 13, Color.WHITE)
    var pt := price_text()
    if pt != "":
        draw_string(font, Vector2(-120, 52), pt, HORIZONTAL_ALIGNMENT_CENTER, 240, 12, Color(1.0, 0.9, 0.4))
    if highlighted:
        var verb := "begin" if kind() == "sigil" else ("descend" if kind() == "stairs" else "take")
        draw_string(font, Vector2(-120, 68), "E / A to %s" % verb, HORIZONTAL_ALIGNMENT_CENTER, 240, 12, Color(0.6, 1.0, 1.0))
