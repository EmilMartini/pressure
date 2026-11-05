class_name Pedestal
extends Node2D
## An interactable offer standing in a room: a gun for sale, an upgrade, the boss
## stairs, or the challenge sigil. The Room decides what activating it does.

const RANGE := 52.0
## 32 px icons at 1.25x sit where the old 16 px tiles did at 2.5x.
const ICON_SCALE := 1.25
## Boon id -> icon under Art.ICON_ROOT.
const BOON_ICONS := {
    "vitality": "gui/spells/enchantment/enslavement_new.png",
    "haul": "gui/spells/translocation/apportation_new.png",
    "boiler": "gui/invocations/gozag_potion_petition.png",
    "hoard": "item/gold/gold_pile_25.png",
}
## Service pedestals -> icon under Art.ICON_ROOT.
const KIND_ICONS := {
    "gunsmith": "gui/spells/earth/maxwells_silver_hammer.png",
    "reroll": "item/misc/misc_deck_new.png",
    "carry": "gui/spells/translocation/apportation_new.png",
    "repair": "gui/spells/necromancy/regeneration_new.png",
}

var offer: Dictionary
var highlighted := false
var prompt_key := "E"      # set by the room from the nearest player's device
var prompt_kind := "kb"    # "pad" or "kb"
var _sprite: Sprite2D

var _t := randf() * TAU
var _card: Node2D           # labels and the ItemCard, on the Crisp layer (sharp, above the pixel grid)
var _gun_data: GunData      # cached for gun offers


func _init(p_offer: Dictionary) -> void:
    offer = p_offer
    z_index = 3


## A plinth whose offer has been taken: the altar stays, bare, until the room is rebuilt.
func empty() -> bool:
    return bool(offer.get("taken", false))


func _ready() -> void:
    if empty():
        return
    # Guns, gear and upgrades show their 32 px Dungeon Crawl icon untinted (the frame and
    # the card carry the rarity); stairs and sigils keep their 1-bit tiles.
    match kind():
        "gun":
            _sprite = Art.icon_sprite(Art.gun_icon(offer["id"]), ICON_SCALE)
        "item":
            _sprite = Art.icon_sprite(Items.icon(item()), ICON_SCALE)
            _sprite.modulate = Items.icon_tint(item())
        "boon":
            _sprite = Art.icon_sprite(Art.icon(String(BOON_ICONS.get(offer["id"], "item/gold/gold_pile_25.png"))), ICON_SCALE)
        "gunsmith", "reroll", "carry", "repair":
            _sprite = Art.icon_sprite(Art.icon(String(KIND_ICONS[kind()])), ICON_SCALE)
        _:
            _sprite = Art.sprite(Art.TILES.get(kind(), Art.TILES["cog"]), 2.5, color())
    _sprite.position = Vector2(0, -36)
    add_child(_sprite)
    _card = Crisp.attach(self, _draw_crisp, 80)


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
        "reroll":
            return "Reroll wares"
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
        "reroll":
            return Color(0.95, 0.75, 0.3)
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
    if empty():
        # Bare plinth: shadow, shaft and top, a little dust where the item stood.
        draw_circle(Vector2(0, 18), 26.0, Color(0, 0, 0, 0.45))
        draw_colored_polygon(PackedVector2Array([Vector2(-16, -8), Vector2(16, -8), Vector2(20, 14), Vector2(-20, 14)]), Color(0.26, 0.23, 0.25))
        draw_rect(Rect2(-20, 10, 40, 6), Color(0.2, 0.18, 0.2))
        draw_rect(Rect2(-18, -12, 36, 6), Color(0.36, 0.33, 0.35))
        draw_rect(Rect2(-18, -12, 36, 2), Color(0.48, 0.45, 0.46))
        draw_line(Vector2(-10, -4), Vector2(-10, 8), Color(0.18, 0.16, 0.18), 1.0)
        draw_line(Vector2(10, -4), Vector2(10, 8), Color(0.18, 0.16, 0.18), 1.0)
        draw_circle(Vector2(0, -11), 7.0, Color(0, 0, 0, 0.25))
        return
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


## Labels, prompt and card, drawn on the Crisp layer so they stay sharp above the pixel
## grid. Name and price always; the description only when you are close enough to take
## it, so a row of plinths does not turn into a wall of overlapping text.
func _draw_crisp(cv: CanvasItem) -> void:
    if empty():
        return
    _draw_labels(cv)
    _draw_card(cv)


func _draw_labels(cv: CanvasItem) -> void:
    var y := 44.0
    var title_col := Color(0.92, 0.9, 0.85)
    if kind() == "item":
        title_col = Items.rarity_color(item())
    var body: Font = Art.FONT_BODY
    cv.draw_string(body, Vector2(-141, y + 1), title(), HORIZONTAL_ALIGNMENT_CENTER, 280, 20, Color(0, 0, 0, 0.8))
    cv.draw_string(body, Vector2(-140, y), title(), HORIZONTAL_ALIGNMENT_CENTER, 280, 20, title_col)
    y += 22.0
    var pt := price_text()
    if pt != "":
        cv.draw_string(body, Vector2(-141, y + 1), pt, HORIZONTAL_ALIGNMENT_CENTER, 280, 20, Color(0, 0, 0, 0.8))
        cv.draw_string(body, Vector2(-140, y), pt, HORIZONTAL_ALIGNMENT_CENTER, 280, 20, Art.SCRAP_TINT)
        y += 22.0
    if highlighted:
        # Items and guns show their full ItemCard beside the plinth (see _draw_card).
        var desc := ""
        match kind():
            "boon":
                desc = FloorGen.BOONS[offer["id"]]["desc"]
            "gunsmith":
                desc = "Raise your lowest-tier gun one tier."
            "reroll":
                desc = "New wares in every slot still on offer. Dearer each time."
            "carry":
                desc = "More guns before the weight slows you."
            "repair":
                desc = "Patch yourself up."
        if desc != "":
            var box_h := 52.0
            cv.draw_rect(Rect2(-170, y - 4, 340, box_h), Color(0.05, 0.04, 0.06, 0.92))
            cv.draw_multiline_string(body, Vector2(-162, y + 16), desc, HORIZONTAL_ALIGNMENT_CENTER, 324, 20, 2, Color(0.92, 0.9, 0.85))
            y += box_h + 4.0
        var verb := "begin" if kind() == "sigil" else ("descend" if kind() == "stairs" else ("equip" if kind() == "item" else "take"))
        # The player's own device's button, floating over the item.
        Prompts.draw(cv, Vector2(0, -78.0 + sin(_t * 5.0) * 2.0), prompt_key, prompt_kind, 24.0)
        cv.draw_string(body, Vector2(-140, y + 4.0), verb, HORIZONTAL_ALIGNMENT_CENTER, 280, 20, Color(0.6, 1.0, 1.0))


## The item or gun card, beside the plinth on whichever side keeps it on screen, compared
## against what the nearest player wears in that slot.
func _draw_card(cv: CanvasItem) -> void:
    if not highlighted or empty() or not (kind() in ["item", "gun"]):
        return
    var p := _nearest_player()
    var price := int(offer.get("price", 0))
    var opts := { "player": p, "price": price, "width": ItemCard.DEFAULT_WIDTH }
    if p != null and p.main() != null:
        opts["afford"] = p.main().scrap >= price
    var h := 0.0
    var it := item()
    if kind() == "item":
        var rival := ItemCard.rival_for(p, it)
        if not rival.is_empty():
            opts["compare"] = rival
        h = ItemCard.height_for(it, opts)
    else:
        if _gun_data == null:
            _gun_data = Guns.make(offer["id"])
        h = ItemCard.gun_height(_gun_data, opts)
    var w: float = ItemCard.DEFAULT_WIDTH
    # Screen placement: right of the plinth, flipped left near the right edge, clamped
    # vertically inside the view.
    var xf := get_global_transform_with_canvas()
    var s := maxf(0.05, xf.get_scale().x)
    var vp := get_viewport_rect().size
    var x := 64.0
    if xf.origin.x + (x + w) * s > vp.x - 12.0:
        x = -64.0 - w
    var y := -40.0 - h / 2.0
    if xf.origin.y + y * s < 12.0:
        y = (12.0 - xf.origin.y) / s
    if xf.origin.y + (y + h) * s > vp.y - 12.0:
        y = (vp.y - 12.0 - xf.origin.y) / s - h
    var rect := Rect2(Vector2(x, y), Vector2(w, h))
    if kind() == "item":
        ItemCard.draw(cv, rect, it, opts)
    else:
        ItemCard.draw_gun(cv, rect, _gun_data, opts)


func _nearest_player() -> Player:
    var best: Player = null
    var best_d := INF
    for n in get_tree().get_nodes_in_group("players"):
        if not n is Player or not is_instance_valid(n):
            continue
        var d: float = (n as Player).global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = n
    return best
