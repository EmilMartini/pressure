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


func _ready() -> void:
    var coord: Vector2i
    match kind():
        "gun":
            coord = Art.gun_tile(offer["id"])
        _:
            coord = Art.TILES.get(kind(), Art.TILES["cog"])
    var s := Art.sprite(coord, 2.5, color())
    s.position = Vector2(0, -10)
    add_child(s)


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
        draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, Color(c, 0.6), 3.0)
        draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 6, Color(c, 0.8), 2.0)
    else:
        draw_circle(Vector2(0, 12), 22.0, Color(0, 0, 0, 0.45))
        draw_arc(Vector2(0, 12), 22.0, 0.0, TAU, 32, Color(c, 0.5), 2.0)
    if highlighted:
        draw_arc(Vector2.ZERO, RANGE - 6.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 1.5)
    draw_string(Art.FONT, Vector2(-130, 44), title(), HORIZONTAL_ALIGNMENT_CENTER, 260, 18, Color(0.92, 0.9, 0.85))
    var pt := price_text()
    if pt != "":
        draw_string(Art.FONT, Vector2(-130, 62), pt, HORIZONTAL_ALIGNMENT_CENTER, 260, 16, Art.SCRAP_TINT)
    if highlighted:
        var verb := "begin" if kind() == "sigil" else ("descend" if kind() == "stairs" else "take")
        draw_string(Art.FONT, Vector2(-130, 80), "E / A to %s" % verb, HORIZONTAL_ALIGNMENT_CENTER, 260, 16, Color(0.6, 1.0, 1.0))
