class_name Pedestal
extends Node2D
## An interactable offer standing in a room: a gun for sale, an upgrade, the boss
## stairs, or the challenge sigil. The Room decides what activating it does.

const RANGE := 52.0

var offer: Dictionary
var highlighted := false
var prompt_key := "E"      # set by the room from the nearest player's device
var prompt_kind := "kb"    # "pad" or "kb"
var _sprite: Sprite2D
var _t := randf() * TAU


func _init(p_offer: Dictionary) -> void:
    offer = p_offer
    z_index = 3


func _ready() -> void:
    var coord: Vector2i
    var tint := color()
    match kind():
        "gun":
            coord = Art.gun_tile(offer["id"])
        "item":
            coord = Items.icon(item())
            tint = Items.icon_tint(item())
        "boon":
            coord = { "vitality": Vector2i(40, 10), "haul": Vector2i(47, 4), "boiler": Vector2i(45, 16), "hoard": Vector2i(45, 16) }.get(offer["id"], Vector2i(45, 16))
        "gunsmith":
            coord = Vector2i(41, 5)
        _:
            coord = Art.TILES.get(kind(), Art.TILES["cog"])
    _sprite = Art.sprite(coord, 2.5, tint)
    _sprite.position = Vector2(0, -36)
    add_child(_sprite)


func kind() -> String:
    return offer["kind"]


func item() -> Dictionary:
    return Items.get_item(offer["id"]) if kind() == "item" else {}


func title() -> String:
    match kind():
        "item":
            return item().get("name", "?")
        "boon":
            return "%s  (+%d)" % [FloorGen.BOONS[offer["id"]]["name"], offer["amount"]]
        "gunsmith":
            return "Gunsmith"
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
        "item":
            return Items.rarity_color(item())
        "boon":
            return Color(1.0, 0.85, 0.4)
        "gunsmith":
            return Color(0.85, 0.8, 0.7)
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


func _process(delta: float) -> void:
    _t += delta
    if _sprite != null and kind() not in ["sigil", "stairs"]:
        _sprite.position.y = -38.0 + sin(_t * 2.2) * 3.0
        _sprite.rotation = sin(_t * 1.1) * 0.08
    elif _sprite != null:
        _sprite.position.y = -12.0
    queue_redraw()


func _draw() -> void:
    var c := color()
    var glow: Texture2D = Art.PARTICLES["light"]
    var g := 110.0 + sin(_t * 2.2) * 8.0
    draw_texture_rect(glow, Rect2(Vector2(-g / 2.0, -g / 2.0 - 36.0), Vector2(g, g)), false, Color(c, 0.16 + (0.1 if highlighted else 0.0)))
    if kind() == "sigil":
        draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, Color(c, 0.6), 3.0)
        draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 6, Color(c, 0.8), 2.0)
    elif kind() == "stairs":
        draw_circle(Vector2(0, 12), 22.0, Color(0, 0, 0, 0.45))
    else:
        # A stone plinth: shadow, shaft, lit top; the item hovers above it.
        draw_circle(Vector2(0, 18), 26.0, Color(0, 0, 0, 0.45))
        draw_colored_polygon(PackedVector2Array([Vector2(-16, -8), Vector2(16, -8), Vector2(20, 14), Vector2(-20, 14)]), Color(0.30, 0.27, 0.29))
        draw_rect(Rect2(-20, 10, 40, 6), Color(0.22, 0.2, 0.22))
        draw_rect(Rect2(-18, -12, 36, 6), Color(0.42, 0.38, 0.40))
        draw_rect(Rect2(-18, -12, 36, 2), Color(0.58, 0.54, 0.55))
        draw_line(Vector2(-10, -4), Vector2(-10, 8), Color(0.2, 0.18, 0.2), 1.0)
        draw_line(Vector2(10, -4), Vector2(10, 8), Color(0.2, 0.18, 0.2), 1.0)
        draw_circle(Vector2(0, -14), 10.0, Color(0, 0, 0, 0.35))
        if highlighted:
            draw_rect(Rect2(-18, -12, 36, 6), Color(c, 0.6))
    # Name and price always; the description only when you are close enough to take it,
    # so a row of plinths does not turn into a wall of overlapping text.
    var y := 44.0
    var title_col := Color(0.92, 0.9, 0.85)
    if kind() == "item":
        title_col = Items.rarity_color(item())
    var body: Font = Art.FONT_BODY
    draw_string(body, Vector2(-141, y + 1), title(), HORIZONTAL_ALIGNMENT_CENTER, 280, 18, Color(0, 0, 0, 0.8))
    draw_string(body, Vector2(-140, y), title(), HORIZONTAL_ALIGNMENT_CENTER, 280, 18, title_col)
    y += 20.0
    var pt := price_text()
    if pt != "":
        draw_string(body, Vector2(-140, y), pt, HORIZONTAL_ALIGNMENT_CENTER, 280, 16, Art.SCRAP_TINT)
        y += 20.0
    if highlighted:
        var desc := ""
        match kind():
            "item":
                var it := item()
                desc = "%s %s.  %s" % [Items.RARITY_NAMES[it["rarity"]], it["slot"], it["desc"]]
            "boon":
                desc = FloorGen.BOONS[offer["id"]]["desc"]
            "gunsmith":
                desc = "Raise your lowest-tier gun one tier."
            "gun":
                var gd := Guns.make(offer["id"])
                desc = "%s.  %.0f damage, %.1f shots/s.  A duplicate merges into a higher tier." % [Element.NAMES[gd.element], gd.damage, gd.fire_rate]
            "carry":
                desc = "More guns before the weight slows you."
            "repair":
                desc = "Patch yourself up."
        if desc != "":
            var box_h := 44.0
            draw_rect(Rect2(-160, y - 4, 320, box_h), Color(0, 0, 0, 0.7))
            draw_multiline_string(body, Vector2(-152, y + 14), desc, HORIZONTAL_ALIGNMENT_CENTER, 304, 15, 2, Color(0.92, 0.9, 0.85))
            y += box_h + 4.0
        var verb := "begin" if kind() == "sigil" else ("descend" if kind() == "stairs" else ("equip" if kind() == "item" else "take"))
        # The player's own device's button, floating over the item.
        Prompts.draw(self, Vector2(0, -78.0 + sin(_t * 5.0) * 2.0), prompt_key, prompt_kind, 24.0)
        draw_string(body, Vector2(-140, y), verb, HORIZONTAL_ALIGNMENT_CENTER, 280, 16, Color(0.6, 1.0, 1.0))
