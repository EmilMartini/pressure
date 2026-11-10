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
    "page": "item/book/parchment_new.png",
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
    if kind() == "archivist" or kind() == "well":
        # Drawn by Npc.draw in _draw, chained until freed; the line he says floats above.
        _card = Crisp.attach(self, _draw_crisp, 80)
        return
    # Guns, gear and upgrades show their 32 px Dungeon Crawl icon untinted (the frame and
    # the card carry the rarity); stairs and sigils keep their 1-bit tiles.
    match kind():
        "gun":
            _sprite = Art.icon_sprite(Art.gun_icon(offer["id"]), ICON_SCALE)
        "item" when offer.get("mystery", false):
            _sprite = Art.icon_sprite(Art.icon(String(KIND_ICONS["reroll"])), ICON_SCALE)
            _sprite.modulate = Color(0.6, 0.5, 0.8)
        "item":
            _sprite = Art.icon_sprite(Items.icon(item()), ICON_SCALE)
            _sprite.modulate = Items.icon_tint(item())
        "boon":
            _sprite = Art.icon_sprite(Art.icon(String(BOON_ICONS.get(offer["id"], "item/gold/gold_pile_25.png"))), ICON_SCALE)
        "gunsmith", "reroll", "carry", "repair", "page":
            _sprite = Art.icon_sprite(Art.icon(String(KIND_ICONS[kind()])), ICON_SCALE)
        "stairs" when ArtPass.enabled():
            # A stairwell built in code (see _draw_stairwell) instead of the 1-bit tile.
            _card = Crisp.attach(self, _draw_crisp, 80)
            if ArtPass.active():
                ArtPass.add_light(self, Vector2(0, -16), 190.0, stair_accent(), 0.85, 0.06, 0.15)
            return
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
            if offer.get("mystery", false):
                return "Mystery ware"
            return item().get("name", "?")
        "boon":
            return "%s  (+%d)" % [FloorGen.BOONS[offer["id"]]["name"], offer["amount"]]
        "gunsmith":
            return "Gunsmith"
        "reroll":
            return "Reroll wares"
        "gun":
            var g := Guns.make(offer["id"])
            # A copy of a carried gun merges into it one tier up (Player.add_gun).
            var into := _merge_into()
            if into != null:
                return "Merge: %s  tier %d" % [g.display_name, into.tier + 1]
            return "%s  (weight %d)" % [g.display_name, g.weight]
        "carry":
            return "Carry capacity +%d" % offer["amount"]
        "repair":
            if offer.get("pct", false):
                return "Heal %d%% health" % offer["amount"]
            return "Repair +%d HP" % offer["amount"]
        "sluice":
            return "Turn the sluice wheel"   # placeholder
        "stairs":
            # A route-choice door names the region it leads to (Regions).
            return "Down to %s" % Regions.display_name(String(offer["id"])) if String(offer["id"]) != "" else "Stairs down"
        "sigil":
            return "Challenge sigil"
        "page":
            return "Torn Bestiary Page"
        "well":
            return "The Well"
        "archivist":
            return Npc.display_name("archivist")
    return "?"


func price_text() -> String:
    if kind() in ["stairs", "sigil"]:
        return ""
    if kind() == "sluice":
        return "Drains the Cistern for good. Harder fights in the open"   # placeholder
    if kind() == "page":
        return "for the Archivist"
    if kind() == "well":
        return "Drop one worn item: it is kept"   # placeholder text
    if kind() == "archivist":
        return "Give: Torn Bestiary Page" if offer.get("page", false) and not offer.get("freed", false) else ""
    if offer.get("spoils", false):
        return "SPOILS: take 1"
    match String(offer.get("deal", "")):
        "hp":
            return "Costs %d max health" % FloorGen.deal_hp(offer)
        "money":
            var held := Room.here.main.scrap if Room.here != null and Room.here.main != null else 0
            var fl := Room.here.main.floor_number if Room.here != null and Room.here.main != null else 1
            return "Costs %d scrap" % FloorGen.deal_money(held, fl)
        "curse":
            return "Costs a curse for the run"
    var txt := "FREE" if offer["price"] == 0 else "%d scrap" % offer["price"]
    if offer.get("locked", false):
        txt += "   LOCKED"
    elif offer.has("group") and offer["price"] == 0:
        txt = "FREE: take 1"
    return txt


## The red chip (Core loop reset 11.1): cursed loot and deals name their curse; trade-off
## items (a stat they lower) show the chip too. "" when none.
func curse_line() -> String:
    if kind() != "item" or offer.get("mystery", false):
        return ""
    if offer.has("curse") and Items.CURSES.has(String(offer["curse"])):
        var c: Dictionary = Items.CURSES[String(offer["curse"])]
        return "%s: %s%s" % [c["name"], c["line"], " (this floor)" if String(offer.get("curse_span", "")) == "floor" else ""]
    if not Main.old_balance and Items.is_tradeoff(item()):
        return "Trade-off"
    return ""


## The carried gun a gun offer would merge into for the nearest player, or null.
func _merge_into() -> Gun:
    if kind() != "gun" or not is_inside_tree():
        return null
    var p := _nearest_player()
    if p == null:
        return null
    return p.merge_target(String(offer["id"]))


## Rarity word of an item offer, or the tier's rarity word for a gun ("" otherwise).
func rarity_word() -> String:
    match kind():
        "item":
            return Items.rarity_name(item())
        "gun":
            var into := _merge_into()
            return String(Items.RARITY_NAMES[Items.tier_rarity(into.tier + 1 if into != null else 1)])
    return ""


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
            # Rarity owns colour: a gun wears its tier's rarity colour, never its element's.
            var into := _merge_into()
            return Items.tier_color(into.tier + 1 if into != null else 1)
        "carry":
            return Color(0.9, 0.9, 1.0)
        "repair":
            return Color(0.4, 0.9, 0.5)
        "stairs":
            return Color(0.7, 0.7, 0.7)
        "sluice":
            return Color(0.45, 0.68, 0.88)
        "sigil":
            return Color(0.8, 0.4, 1.0)
        "page":
            return Color(0.93, 0.89, 0.80)
        "well":
            return WELL_WATER
        "archivist":
            return Npc.color("archivist")
    return Color.WHITE


func _process(delta: float) -> void:
    _t += delta
    if offer.has("say_age"):
        offer["say_age"] = float(offer["say_age"]) + delta
    if _sprite != null and kind() not in ["sigil", "stairs"]:
        _sprite.position.y = -38.0 + sin(_t * 2.2) * 3.0
        _sprite.rotation = sin(_t * 1.1) * 0.08
    elif _sprite != null:
        _sprite.position.y = -12.0
    queue_redraw()


func _draw() -> void:
    if kind() == "well":
        draw_well(self, Vector2.ZERO, _t, highlighted, not empty())
        return
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
    if kind() == "archivist":
        Npc.draw(self, "archivist", Vector2(0, 14), _t, highlighted, not offer.get("freed", false))
        return
    if kind() == "sigil":
        draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, Color(c, 0.6), 3.0)
        draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 6, Color(c, 0.8), 2.0)
    elif kind() == "stairs":
        if ArtPass.enabled():
            _draw_stairwell()
        else:
            draw_circle(Vector2(0, 12), 22.0, Color(0, 0, 0, 0.45))
    elif kind() == "sluice":
        # An iron wheel on a post (drawn in code, placeholder art).
        draw_circle(Vector2(0, 18), 26.0, Color(0, 0, 0, 0.45))
        draw_rect(Rect2(-5, -10, 10, 28), Color(0.22, 0.2, 0.22))
        var a := _t * (2.0 if highlighted else 0.4)
        draw_arc(Vector2(0, -16), 22.0, 0.0, TAU, 32, Color(0.05, 0.05, 0.06), 7.0)
        draw_arc(Vector2(0, -16), 22.0, 0.0, TAU, 32, Color(0.55, 0.5, 0.45), 4.0)
        for k in 4:
            var d := Vector2.RIGHT.rotated(a + float(k) * PI / 4.0) * 22.0
            draw_line(Vector2(0, -16) - d, Vector2(0, -16) + d, Color(0.55, 0.5, 0.45), 3.0)
        draw_circle(Vector2(0, -16), 5.0, c)
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


const WELL_WATER := Color(0.42, 0.68, 0.92)

## Each region's light, rising out of the stairwell that leads there (living world).
const STAIR_ACCENTS := {
    "crypt": Color(0.70, 0.90, 0.62), "cistern": Color(0.45, 0.82, 0.95), "garden": Color(0.74, 0.92, 0.40),
    "ruins": Color(0.98, 0.74, 0.42), "frozen": Color(0.72, 0.90, 1.0), "forge": Color(1.0, 0.60, 0.26),
    "sanctum": Color(1.0, 0.88, 0.52), "void": Color(0.72, 0.48, 1.0),
}


## The light colour of the region these stairs lead to (plain stairs: a pale stone light).
func stair_accent() -> Color:
    var id := String(offer.get("id", ""))
    if id == "":
        return Color(0.86, 0.84, 0.74)
    var th := String(Regions.get_region(id).get("theme", ""))
    return STAIR_ACCENTS.get(th, Color(0.86, 0.84, 0.74))


## A route door as a real threshold: steps going down into the dark with the next region's
## light spilling up them, stone walls either side, an arch over the far end with a lit
## keystone, two lamps and a line of runes across the top step that wakes as you come near.
func _draw_stairwell() -> void:
    var tx := Themes.texel(1.3)
    var acc := stair_accent()
    var lt: Texture2D = Art.PARTICLES["light"]
    var stone := Color(0.34, 0.32, 0.30)
    var dark := Color(0.03, 0.03, 0.035)
    var breathe := 0.85 + 0.15 * sin(_t * 1.5)
    var near := 1.0 if highlighted else 0.0
    var w := 38.0
    var top := -40.0
    var bot := 26.0
    # Ground shadow and the well's mouth.
    draw_texture_rect(lt, Rect2(Vector2(-70, bot - 26), Vector2(140, 60)), false, Color(0, 0, 0, 0.55))
    draw_rect(Rect2(-w - tx * 2.0, top - tx, w * 2.0 + tx * 4.0, bot - top + tx * 2.0), dark)
    # Steps: the near one lit, each further one darker, a lit lip and a dark riser each.
    var steps := 7
    var sh := (bot - top) / float(steps)
    for k in steps:
        var y := bot - float(k + 1) * sh
        var f := float(k) / float(steps - 1)
        var c := stone.lerp(dark, f * 0.85)
        c = c.lerp(acc.darkened(0.55), f * 0.35)
        draw_rect(Rect2(-w, y, w * 2.0, sh), c)
        draw_rect(Rect2(-w, y, w * 2.0, tx), c.lightened(0.28 * (1.0 - f)))
        draw_rect(Rect2(-w, y + sh - tx, w * 2.0, tx), Color(0, 0, 0, 0.45))
    # The next region's light rising up the steps.
    draw_texture_rect(lt, Rect2(Vector2(-w * 1.4, top - 30.0), Vector2(w * 2.8, 70.0)), false, Color(acc, 0.42 * breathe + 0.15 * near))
    draw_texture_rect(lt, Rect2(Vector2(-w, top - 12.0), Vector2(w * 2.0, 34.0)), false, Color(acc.lightened(0.3), 0.30 * breathe))
    for i in 6:
        var f2 := fmod(_t * 0.35 + float(i) * 0.167, 1.0)
        var q := Vector2(sin(_t * 0.9 + float(i) * 2.1) * w * 0.7, top + 6.0 - f2 * 60.0)
        draw_rect(Rect2((q / tx).round() * tx, Vector2(tx, tx)), Color(acc.lightened(0.4), sin(PI * f2) * 0.8))
    # Side walls of the well.
    for sx in [-1.0, 1.0]:
        var r := Rect2(sx * w - (tx * 4.0 if sx < 0 else 0.0), top - tx, tx * 4.0, bot - top + tx)
        draw_rect(r.grow(tx * 0.5), Color(0.02, 0.02, 0.02))
        draw_rect(r, stone.darkened(0.1))
        draw_rect(Rect2(r.position, Vector2(r.size.x, tx)), stone.lightened(0.3))
        var inner := r.position.x + (r.size.x - tx if sx < 0 else 0.0)
        draw_rect(Rect2(inner, r.position.y, tx, r.size.y), Color(acc, 0.35 * breathe))
    # The arch over the far end: two pillars, a lintel, a keystone lit in the region's colour.
    for sx in [-1.0, 1.0]:
        var pr := Rect2(sx * (w + tx * 2.0) - tx * 4.0, top - 50.0, tx * 8.0, 50.0)
        draw_rect(pr.grow(tx), Color(0.02, 0.02, 0.02))
        draw_rect(pr, stone)
        draw_rect(Rect2(pr.position, Vector2(tx * 2.0, pr.size.y)), stone.lightened(0.18))
        draw_rect(Rect2(pr.end.x - tx * 2.0, pr.position.y, tx * 2.0, pr.size.y), stone.darkened(0.35))
        for k in 3:
            draw_rect(Rect2(pr.position.x, pr.position.y + 12.0 + float(k) * 13.0, pr.size.x, tx * 0.6), Color(0, 0, 0, 0.4))
    var lin := Rect2(-w - tx * 8.0, top - 62.0, w * 2.0 + tx * 16.0, 14.0)
    draw_rect(lin.grow(tx), Color(0.02, 0.02, 0.02))
    draw_rect(lin, stone.darkened(0.05))
    draw_rect(Rect2(lin.position, Vector2(lin.size.x, tx)), stone.lightened(0.35))
    draw_rect(Rect2(lin.position.x, lin.end.y - tx, lin.size.x, tx), Color(0, 0, 0, 0.5))
    var key := Rect2(-tx * 4.0, top - 66.0, tx * 8.0, 20.0)
    draw_rect(key.grow(tx), Color(0.02, 0.02, 0.02))
    draw_rect(key, stone.lightened(0.08))
    draw_texture_rect(lt, Rect2(key.get_center() - Vector2(18, 18), Vector2(36, 36)), false, Color(acc, 0.5 * breathe + 0.3 * near))
    draw_rect(Rect2(key.get_center() - Vector2(tx, tx * 1.5), Vector2(tx * 2.0, tx * 3.0)), acc.lightened(0.2))
    # Lamps on the pillar tops.
    for sx in [-1.0, 1.0]:
        var lp := Vector2(sx * (w + tx * 2.0), top - 56.0)
        draw_texture_rect(lt, Rect2(lp - Vector2(16, 16), Vector2(32, 32)), false, Color(acc, 0.35 * breathe))
        draw_rect(Rect2((lp / tx).round() * tx - Vector2(tx, tx * 2.0), Vector2(tx * 2.0, tx * 2.0)), acc.lightened(0.35))
    # The threshold: runes across the top step that wake as a player comes near.
    var n := 9
    for i in n:
        var x := -w + tx * 2.0 + float(i) * (w * 2.0 - tx * 4.0) / float(n - 1)
        var on := 0.35 + 0.65 * near * (0.6 + 0.4 * sin(_t * 4.0 + float(i)))
        var g := ((Vector2(x, bot + tx * 2.0)) / tx).round() * tx
        draw_rect(Rect2(g, Vector2(tx, tx * (2.0 if i % 2 == 0 else 1.0))), Color(acc, on))
    draw_rect(Rect2(-w - tx * 2.0, bot, w * 2.0 + tx * 4.0, tx), stone.lightened(0.25))


## A Well drawn in code (also the Hollow's, Hub): a ring of stones round dark water that
## glints while it is still open; a used one is a dry ring.
static func draw_well(ci: CanvasItem, at: Vector2, t: float, lit: bool, open: bool) -> void:
    var glow: Texture2D = Art.PARTICLES["light"]
    if open:
        var g := 120.0 + sin(t * 1.6) * 8.0
        ci.draw_texture_rect(glow, Rect2(at - Vector2(g, g) / 2.0, Vector2(g, g)), false, Color(WELL_WATER, 0.14 + (0.12 if lit else 0.0)))
    ci.draw_set_transform(at + Vector2(0, 6), 0.0, Vector2(1.0, 0.55))
    ci.draw_circle(Vector2.ZERO, 40.0, Color(0, 0, 0, 0.45))
    ci.draw_circle(Vector2.ZERO, 33.0, Color(0.30, 0.27, 0.29))
    for i in 12:
        var a := TAU * float(i) / 12.0
        var sp := Vector2(cos(a), sin(a)) * 29.0
        ci.draw_circle(sp, 6.5, Color(0.42, 0.38, 0.40) if i % 2 == 0 else Color(0.36, 0.33, 0.35))
        ci.draw_arc(sp, 6.5, 0.0, TAU, 10, Color(0.12, 0.1, 0.12), 1.2)
    ci.draw_circle(Vector2.ZERO, 22.0, Color(0.03, 0.03, 0.05))
    if open:
        var w := Color(WELL_WATER, 0.55 + 0.25 * sin(t * 2.0))
        ci.draw_arc(Vector2(-4, -2), 10.0 + sin(t * 1.3) * 2.0, PI * 1.1, PI * 1.6, 8, w, 2.0)
        ci.draw_arc(Vector2(5, 4), 6.0, -0.4, 0.6, 6, Color(WELL_WATER, 0.4), 1.5)
        if lit:
            ci.draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 32, Color(WELL_WATER, 0.7), 2.0)
    ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Labels, prompt and card, drawn on the Crisp layer so they stay sharp above the pixel
## grid. Name and price always; the description only when you are close enough to take
## it, so a row of plinths does not turn into a wall of overlapping text.
func _draw_crisp(cv: CanvasItem) -> void:
    if empty():
        return
    _draw_labels(cv)
    _draw_card(cv)
    if kind() == "archivist" and offer.has("say") and float(offer.get("say_age", 99.0)) < 8.0:
        # His line, over his head, until it has had time to be read.
        var body: Font = Art.FONT_BODY
        var a := clampf((8.0 - float(offer["say_age"])) / 1.0, 0.0, 1.0)
        cv.draw_rect(Rect2(-214, -150, 428, 66), Color(0.04, 0.03, 0.05, 0.85 * a))
        cv.draw_multiline_string(body, Vector2(-204, -126), String(offer["say"]), HORIZONTAL_ALIGNMENT_CENTER, 408, 20, 3, Color(0.93, 0.89, 0.80, a))


func _draw_labels(cv: CanvasItem) -> void:
    var y := 44.0
    var title_col := Color(0.92, 0.9, 0.85)
    if kind() == "item":
        title_col = Items.rarity_text_color(item())
    elif kind() == "gun":
        var into := _merge_into()
        title_col = Items.tier_text_color(into.tier + 1 if into != null else 1)
    var body: Font = Art.FONT_BODY
    cv.draw_string(body, Vector2(-141, y + 1), title(), HORIZONTAL_ALIGNMENT_CENTER, 280, 20, Color(0, 0, 0, 0.8))
    cv.draw_string(body, Vector2(-140, y), title(), HORIZONTAL_ALIGNMENT_CENTER, 280, 20, title_col)
    y += 22.0
    var rw := rarity_word()
    if rw != "":
        # The rarity in words (colour-blind safe), and the element as a neutral badge.
        var el := Element.Kind.NONE
        if kind() == "gun":
            el = Guns.make(offer["id"]).element
        elif kind() == "item" and item().has("element"):
            el = ItemCard.element_kind(item()["element"])
        var tw := body.get_string_size(rw.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
        var bs := ItemCard.element_badge_size(el, 16) if el != Element.Kind.NONE else Vector2.ZERO
        var total := tw + (bs.x + 8.0 if bs.x > 0.0 else 0.0)
        var x0 := -total / 2.0
        cv.draw_string(body, Vector2(x0 + 1, y + 1), rw.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, 0.8))
        cv.draw_string(body, Vector2(x0, y), rw.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, title_col)
        if bs.x > 0.0:
            ItemCard.draw_element_badge(cv, Vector2(x0 + tw + 8.0, y - 15.0), el, 16)
        y += 22.0
    var cl := curse_line()
    if cl != "":
        # The red Cursed chip and its drawback.
        var red := Color(1.0, 0.25, 0.25)
        cv.draw_rect(Rect2(-40, y - 16, 80, 20), Color(0.35, 0.02, 0.04, 0.95))
        cv.draw_rect(Rect2(-40, y - 16, 80, 20), red, false, 1.5)
        cv.draw_string(body, Vector2(-40, y), "CURSED", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, red)
        y += 22.0
        cv.draw_string(body, Vector2(-160, y + 1), cl, HORIZONTAL_ALIGNMENT_CENTER, 320, 16, Color(0, 0, 0, 0.8))
        cv.draw_string(body, Vector2(-160, y), cl, HORIZONTAL_ALIGNMENT_CENTER, 320, 16, Color(1.0, 0.55, 0.5))
        y += 20.0
    if kind() == "stairs" and String(offer["id"]) != "":
        y = _draw_region_profile(cv, y)
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
        if offer.get("ware", false) and not Main.old_balance:
            verb += ("     Y / R: unlock" if offer.get("locked", false) else "     Y / R: lock")
        if kind() == "archivist":
            verb = "give the page" if offer.get("page", false) and not offer.get("freed", false) else "talk"
        elif kind() == "well":
            verb = "drop an item"
        # The player's own device's button, floating over the item.
        Prompts.draw(cv, Vector2(0, -78.0 + sin(_t * 5.0) * 2.0), prompt_key, prompt_kind, 24.0)
        cv.draw_string(body, Vector2(-140, y + 4.0), verb, HORIZONTAL_ALIGNMENT_CENTER, 280, 20, Color(0.6, 1.0, 1.0))


## Under a route door: what its region resists and is weak to, as element badges, so the
## choice reads before the stairs are taken. Returns the next free line.
func _draw_region_profile(cv: CanvasItem, y: float) -> float:
    var r := Regions.get_region(String(offer["id"]))
    var body: Font = Art.FONT_BODY
    var parts: Array = []   # [word, kinds]
    if not (r["resists"] as Array).is_empty():
        parts.append(["RESISTS", Regions.kinds(r["resists"])])
    if not (r["weak"] as Array).is_empty():
        parts.append(["WEAK", Regions.kinds(r["weak"])])
    if parts.is_empty():
        return y
    for part in parts:
        var word: String = part[0]
        var tw := body.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
        var total := tw
        for k in part[1]:
            total += 8.0 + ItemCard.element_badge_size(k, 16).x
        var x := -total / 2.0
        var col := Color(0.75, 0.72, 0.7) if word == "RESISTS" else Color(1.0, 0.85, 0.5)
        cv.draw_string(body, Vector2(x + 1, y + 1), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, 0.8))
        cv.draw_string(body, Vector2(x, y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
        x += tw + 8.0
        for k in part[1]:
            ItemCard.draw_element_badge(cv, Vector2(x, y - 15.0), k, 16)
            x += ItemCard.element_badge_size(k, 16).x + 8.0
        y += 22.0
    return y


## The item or gun card, beside the plinth on whichever side keeps it on screen, compared
## against what the nearest player wears in that slot.
func _draw_card(cv: CanvasItem) -> void:
    if not highlighted or empty() or not (kind() in ["item", "gun"]) or offer.get("mystery", false):
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
            var slot := String(it.get("slot", ""))
            if p != null and p.jewel_kept(slot) != "":
                opts["keeps"] = Items.get_item(String(p.equipment[p.jewel_kept(slot)]))
                opts["swap_key"] = p.input.prompt("swap")
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
