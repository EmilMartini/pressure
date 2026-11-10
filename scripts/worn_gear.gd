class_name WornGear
extends RefCounted
## The gear a figure actually wears: every head, chest, hands and feet item is drawn on the
## FigureGen paper doll as a hand-authored pixel piece of its kind (a pointed wizard hat, a
## hood, a horned helm, plate with pauldrons, a cloak, gauntlets, boots...), coloured from
## the item's own Dungeon Crawl icon, so the hat on your head is the hat you saw on the
## pedestal. The class and gear themes still blend the body underneath (FigureGen); rings
## and trinkets stay small accents (Items.draw_costume).
##
##   kind_of(id, item)   the archetype: KIND_OVERRIDES, else keyword rules on name + icon
##   colors_of(id, item) { "1" main, "2" dark, "3" light, "4" accent }, sampled from the
##                       icon once (spell icons have no garment colour: look tint, element
##                       or the archetype's material instead)
##   worn_of(player)     { slot: item id } for the four drawn slots
##
## Piece grids use FigureGen's string format with their own codes: "1" item main, "2" item
## dark, "3" item light, "4" item accent, "s" skin and "h" hair (the figure's light and
## dark, so the face blends with the body), "o" outline black, "b" bone, "y" lamp glow, "g" glass,
## "." leave what is under it.

const SLOTS := ["head", "chest", "hands", "feet"]

## Heads: 10 wide at x 3 (the head proper is columns 1..8), rows 0..6, face included. A
## worn head replaces the theme head completely.
const HEADS := {
    "wizard": ["......12..", ".....11...", "...2113...", "..244442..", "2111111112", "..sossos..", "...ssss..."],
    "wizard_tall": [".......21.", "......11..", ".....141..", "....2111..", "...211113.", "2111111112", "..sossos.."],
    "wide": ["..........", "..........", "...2113...", "2..4444..2", "2111111112", "..sossos..", "...ssss..."],
    "hood": ["....11....", "...1131...", "..111311..", ".11222211.", ".1sossos1.", ".12ssss21.", "..1ssss1.."],
    "bandana": ["..........", "...hhhh...", "..hhhhhh..", "..13111112", "..sossos.2", "..ssssss..", "...ssss..."],
    "helm": ["....22....", "...1331...", "..113311..", "..242242..", ".1so22os1.", ".1ssssss1.", "..1ssss1.."],
    "visor": ["....22....", "...1331...", "..113311..", ".11111111.", ".1o4oo4o1.", ".11122111.", "..122221.."],
    "pot": ["..........", "..222222..", ".13311112.", ".1oo11oo1.", ".13111112.", ".11111112.", "..222222.."],
    "horned": ["b........b", "b..1331..b", "bb113311bb", "..222222..", ".1so22os1.", ".1ssssss1.", "..1ssss1.."],
    "crown": ["..1.11.1..", "..114411..", "..111111..", "..hssssh..", "..sossos..", "..ssssss..", "...ssss..."],
    "circlet": ["..........", "...hhhh...", "..hh44hh..", "..114411..", "..sossos..", "..ssssss..", "...ssss..."],
    "cap": ["..........", "...1331...", "..113311..", ".12222221.", ".1sossos1.", ".1ssssss1.", "...ssss..."],
    "skullcap": ["..........", "...1331...", "..143141..", "..222222..", "..sossos..", "..ssssss..", "...ssss..."],
    "feather": [".......44.", "...1114...", "..113311..", "..222222..", "..sossos..", "..ssssss..", "...ssss..."],
    "lamp": ["....yy....", "...1yy1...", "..112211..", "..222222..", "..sossos..", "..ssssss..", "...ssss..."],
    "mask": ["..........", "...hhhh...", "..hhhhhh..", ".21111112.", "..141141..", "..111111..", "...1221..."],
    "goggles": ["..........", "...hhhh...", "..hhhhhh..", "..2hhhh2..", ".24411442.", "..ssssss..", "...ssss..."],
    "monocle": ["..........", "...hhhh...", "..hhhhhh..", "..hss333..", "..sos3g3..", "..sss333..", "...ssss2.."],
    "winged": ["4........4", "44.1331.44", ".41133114.", "..222222..", ".1so22os1.", ".1ssssss1.", "..1ssss1.."],
}

## Chest pieces: an 8 wide torso overlay (resized per build like FigureGen.TORSOS) at the
## build's torso x, rows 7..13, drawn over the theme torso ("." keeps it, so vests and
## straps show the body's own colours); optional "arm" { x, y, rows } on both arms (x is
## relative to the arm, -1 reaches one pixel out, the right arm is mirrored), optional
## "cape" (a FigureGen.CAPES shape in the item's colours, replacing the theme cape), and
## "covers" when the torso is hidden enough that torso accents are skipped.
const CHESTS := {
    "vest": { "torso": [".22..22.", ".13..31.", ".11..11.", ".14..41.", ".222222.", ".11..11.", "........"] },
    "jerkin": { "covers": true, "torso": [".333333.", ".131131.", ".313313.", ".131131.", ".222422.", ".11..11.", "........"],
        "arm": { "x": 0, "y": 8, "rows": ["13", "31"] } },
    "hide": { "covers": true, "torso": ["3.3333.3", ".131311.", ".111211.", ".121111.", ".112121.", "1.1..1.1", "........"],
        "arm": { "x": -1, "y": 7, "rows": ["33.", ".13"] } },
    "apron": { "torso": [".4....4.", "..3333..", "..3443..", ".233332.", "..3333..", "..3223..", "..3333.."] },
    "coat": { "covers": true, "torso": [".113311.", ".12..21.", ".14..41.", ".12..21.", ".122221.", "112..211", "11....11"],
        "arm": { "x": 0, "y": 8, "rows": ["11", "11", "12"] } },
    "robe": { "covers": true, "torso": [".133331.", ".111111.", ".112111.", ".244442.", ".111211.", "11121111", "12111121"],
        "arm": { "x": 0, "y": 8, "rows": ["11", "11", "12"] } },
    "shroud": { "covers": true, "cape": "tattered", "torso": [".133331.", ".111111.", ".112111.", ".111111.", ".111211.", "11121111", "1.11.1.1"],
        "arm": { "x": 0, "y": 8, "rows": ["11", "11", "12"] } },
    "plate": { "covers": true, "torso": [".333333.", ".311112.", ".131121.", ".131121.", ".244442.", ".12..21.", "........"],
        "arm": { "x": -1, "y": 7, "rows": ["333", "122"] } },
    "spiked": { "covers": true, "torso": [".333333.", ".311112.", ".131121.", ".131121.", ".244442.", ".12..21.", "........"],
        "arm": { "x": -1, "y": 5, "rows": ["3..", "33.", "333", "122"] } },
    "thorns": { "covers": true, "torso": [".333333.", ".131131.", ".313313.", ".131131.", ".222422.", ".11..11.", "........"],
        "arm": { "x": -1, "y": 6, "rows": ["3..", "333", "112"] } },
    "mail": { "covers": true, "torso": [".333333.", ".131313.", ".313131.", ".131313.", ".222222.", ".131313.", "........"],
        "arm": { "x": 0, "y": 8, "rows": ["13", "31"] } },
    "cloak": { "cape": "long", "torso": [".133331.", ".1.44.1.", ".1....1.", ".1....1.", ".2....2.", ".2....2.", "........"],
        "arm": { "x": 0, "y": 7, "rows": ["11", "12"] } },
    "bandolier": { "torso": [".24.....", "..24....", "...24...", "....24..", ".222224.", "........", "........"] },
    "harness": { "torso": [".2....2.", "..2..2..", "...44...", "..2..2..", ".244442.", "........", "........"] },
}

## Hands, on both arms: { x (relative to the arm, -1 reaches one pixel out), y, rows },
## left arm as written, right arm mirrored; "blade" adds a sword held up on the right.
const HANDS := {
    "gloves": { "x": 0, "y": 10, "rows": ["22", "13", "11"] },
    "gauntlets": { "x": -1, "y": 10, "rows": ["333", ".13", ".12"] },
    "spiked": { "x": -1, "y": 9, "rows": ["3..", "333", ".13", ".12"] },
    "mitts": { "x": -1, "y": 10, "rows": [".33", "111", "122"] },
    "wraps": { "x": 0, "y": 9, "rows": ["33", "1s", "33", "s1"] },
    "fingerless": { "x": 0, "y": 10, "rows": ["22", "11", "ss"] },
    "bracer": { "x": 0, "y": 9, "rows": ["33", "12"] },
    "blade": { "x": -1, "y": 10, "rows": ["333", ".13", ".12"], "blade": true },
}

## Feet, on both legs: { y, rows }; column 0 is one pixel outside the leg, then the outer
## and inner leg columns (slim legs drop the inner one). The right leg is mirrored.
const FEET := {
    "boots": { "y": 13, "rows": [".11", "122"] },
    "tall": { "y": 12, "rows": [".44", ".11", "122"] },
    "greaves": { "y": 12, "rows": [".33", ".31", "312"] },
    "sandals": { "y": 13, "rows": [".1s", ".s1"] },
    "wraps": { "y": 13, "rows": [".31", ".13"] },
    "shoes": { "y": 13, "rows": [".ss", "112"] },
    "winged": { "y": 12, "rows": ["4..", "411", "122"] },
}

## Explicit kind per item where the keyword rules would guess wrong or too plainly.
const KIND_OVERRIDES := {
    # Head
    "rusted_helm": "helm", "iron_pot": "pot", "feather_cap": "feather", "miners_lamp": "lamp",
    "leather_cap": "cap", "wide_brim": "wide", "scavenger_hood": "hood", "fume_mask": "mask",
    "sniper_visor": "visor", "hothead": "hood", "divers_goggles": "goggles",
    "thinking_cap": "wizard", "crown_of_focus": "crown", "marksman_monocle": "monocle",
    "storm_hood": "wizard_tall", "seer_circlet": "circlet", "boiler_cap": "visor",
    "berserker_helm": "horned", "skullcap_vented": "skullcap", "seeker_lens": "winged",
    "cerebral_spark": "wizard", "detonator_cap": "visor", "godhead": "crown",
    # Chest
    "padded_vest": "vest", "quilted_jerkin": "jerkin", "hide_vest": "hide", "lab_apron": "apron",
    "patched_coat": "coat", "cargo_vest": "vest", "thorn_vest": "thorns", "tar_coat": "coat",
    "riveted_plate": "plate", "bandolier": "bandolier", "slipstream_cloak": "cloak",
    "bellows": "mail", "chain_shirt": "mail", "conductors_mail": "mail", "leech_mail": "mail",
    "spiked_cuirass": "spiked", "glacier_plate": "plate", "ammo_harness": "harness",
    "phoenix_mantle": "cloak", "gilded_carapace": "plate", "shrapnel_vest": "plate",
    "phantom_shroud": "shroud", "hive_heart": "robe",
    # Hands
    "worn_gloves": "gloves", "hair_trigger": "gloves", "knuckle_wraps": "wraps",
    "steady_gloves": "gloves", "gardening_gloves": "mitts", "lab_gloves": "gloves",
    "quick_hands": "gloves", "spiked_gauntlets": "spiked", "fingerless_gloves": "fingerless",
    "chilled_knuckles": "gauntlets", "scrappers_mitts": "mitts", "grip_of_pierce": "gauntlets",
    "ricochet_gloves": "gauntlets", "kindling_mitts": "mitts", "twin_triggers": "gloves",
    "executioners_grip": "gauntlets", "hands_of_storm": "gauntlets", "rifled_sleeve": "bracer",
    "cluster_rounds": "gloves", "mothers_blade": "blade",
    # Feet
    "leather_boots": "boots", "runner_wraps": "wraps", "hobnail_boots": "boots",
    "sturdy_boots": "tall", "sandals": "sandals", "treaders": "boots", "mudwaders": "tall",
    "jogging_shoes": "shoes", "puddle_jumpers": "boots", "stompers": "greaves",
    "cinder_clogs": "shoes", "frost_treads": "boots", "anvil_boots": "greaves",
    "greased_soles": "shoes", "tidewalkers": "tall", "hover_greaves": "winged",
    "vent_striders": "greaves", "seven_league": "winged", "tracker_boots": "boots",
}

## Keyword rules per slot, first match on "<id> <name> <icon path>" (lower case).
const RULES := {
    "head": [["wizard|cornuthaum|hat_3", "wizard"], ["brim|hat_2", "wide"], ["crown|dyrovepreva", "crown"],
        ["circlet", "circlet"], ["monocle|lens|bullseye", "monocle"], ["goggle", "goggles"],
        ["mask", "mask"], ["hood|cap_1", "hood"], ["bandana", "bandana"], ["horn|berserk", "horned"],
        ["visor", "visor"], ["pot|helmet_5", "pot"], ["lamp", "lamp"], ["feather|elven", "feather"],
        ["skull", "skullcap"], ["cap|hat", "cap"]],
    "chest": [["robe", "robe"], ["cloak|mantle|cape|back/", "cloak"], ["shroud", "shroud"],
        ["apron", "apron"], ["spike", "spiked"], ["thorn", "thorns"], ["plate|carapace|cuirass|dragon", "plate"],
        ["mail|chain", "mail"], ["bandolier", "bandolier"], ["harness", "harness"], ["hide|skin|fur", "hide"],
        ["coat", "coat"], ["vest", "vest"]],
    "hands": [["blade|sword", "blade"], ["spike", "spiked"], ["gauntlet|knuckle|grip", "gauntlets"],
        ["mitt", "mitts"], ["wrap", "wraps"], ["fingerless", "fingerless"], ["sleeve|bracer", "bracer"]],
    "feet": [["wing|hover|league", "winged"], ["greave|stomp|anvil|iron", "greaves"], ["sandal", "sandals"],
        ["wrap", "wraps"], ["shoe|sole|clog", "shoes"], ["wader|jackboot|tall", "tall"]],
}
const DEFAULT_KIND := { "head": "cap", "chest": "jerkin", "hands": "gloves", "feet": "boots" }

## Material colour per kind for items whose icon is a spell (no garment to sample) and
## that have no element or look tint: leather, iron, cloth.
const LEATHER := Color(0.55, 0.36, 0.22)
const IRON := Color(0.62, 0.64, 0.70)
const CLOTH := Color(0.58, 0.52, 0.44)
const MATERIAL := {
    "helm": IRON, "visor": IRON, "pot": IRON, "horned": IRON, "crown": Color(0.95, 0.78, 0.3),
    "circlet": Color(0.85, 0.85, 0.9), "plate": IRON, "spiked": IRON, "mail": IRON,
    "gauntlets": IRON, "greaves": IRON, "blade": IRON, "robe": CLOTH, "shroud": CLOTH,
    "wraps": CLOTH, "bandana": CLOTH,
}
## Item id -> [main, accent] where neither the icon nor the item says enough.
const COLOR_OVERRIDES := {
    "cinder_clogs": [Color(0.5, 0.26, 0.16), Color(1.0, 0.55, 0.2)],
    "jogging_shoes": [Color(0.85, 0.82, 0.78), Color(0.9, 0.3, 0.25)],
    "puddle_jumpers": [Color(0.95, 0.8, 0.25), Color(0.3, 0.55, 0.9)],
    "fingerless_gloves": [Color(0.32, 0.27, 0.25), Color(0.6, 0.55, 0.5)],
    "grip_of_pierce": [Color(0.55, 0.5, 0.45), Color(0.85, 0.82, 0.75)],
    "miners_lamp": [Color(0.75, 0.6, 0.3), Color(1.0, 0.9, 0.5)],
}
## Luminance caps per piece code (bloom weights), see _tame.
const LUM_CAPS := { "1": 0.4, "2": 0.22, "3": 0.55 }
const LUM_SAT_BONUS := 0.18
const LAMP := Color(1.0, 0.93, 0.55)
const GLASS := Color(0.85, 0.95, 1.0)

static var _colors: Dictionary = {}   # item id -> colour dict


## { slot: item id } for the drawn slots `player` has filled.
static func worn_of(player) -> Dictionary:
    var out: Dictionary = {}
    if player == null or not is_instance_valid(player):
        return out
    # No slots (Core loop reset 3.1): each body part shows the highest-rarity item that
    # dresses it.
    for id in player.inventory.keys():
        var it: Dictionary = Items.get_item(String(id))
        var slot := String(it.get("slot", ""))
        if not SLOTS.has(slot):
            continue
        if not out.has(slot) or int(it.get("rarity", 0)) > int(Items.get_item(String(out[slot])).get("rarity", 0)):
            out[slot] = String(id)
    return out


## The archetype an item is drawn as ("" for slots that are not drawn).
static func kind_of(id: String, it: Dictionary) -> String:
    var slot := String(it.get("slot", ""))
    if not DEFAULT_KIND.has(slot):
        return ""
    if KIND_OVERRIDES.has(id):
        return String(KIND_OVERRIDES[id])
    var text := ("%s %s %s" % [id, String(it.get("name", "")), String(it.get("icon", ""))]).to_lower()
    for rule in RULES.get(slot, []):
        var r: Array = rule
        for word in String(r[0]).split("|"):
            if text.contains(word):
                return String(r[1])
    return String(DEFAULT_KIND[slot])


## { slot: { kind, colors, id } } for a { slot: item id } map, skipping unknown items.
static func resolve(worn: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for slot in SLOTS:
        if not worn.has(slot):
            continue
        var id := String(worn[slot])
        var it: Dictionary = Items.get_item(id)
        if it.is_empty():
            continue
        var kind := kind_of(id, it)
        if kind == "":
            continue
        out[slot] = { "kind": kind, "colors": colors_of(id, it), "id": id }
    return out


# --- Colours ---------------------------------------------------------------------


## The piece's colours from the item's icon: the most common hue in the tile (shading kept:
## dark and light come from its darkest and brightest quarter), and the most common clearly
## different hue as the accent (gems, trim, bands). Cached per item.
static func colors_of(id: String, it: Dictionary) -> Dictionary:
    if _colors.has(id):
        return _colors[id]
    var out: Dictionary
    var path := Items.icon_path(it)
    if COLOR_OVERRIDES.has(id):
        var ov: Array = COLOR_OVERRIDES[id]
        out = _shades(ov[0], ov[1])
    elif path.begins_with("gui/") or not Art.has_icon(path):
        out = _fallback(id, it)
    else:
        out = _sample(Art.icon(path), Items.icon_tint(it))
        if out.is_empty():
            out = _fallback(id, it)
    out = _tame(out)
    _colors[id] = out
    return out


## Pale pieces are toned down: the PostFx bloom (threshold 0.42) washes a pale piece on a
## pale face into one white blob, so main and dark stay about under it and the light shade
## only just above (the highlight still glints). Saturated colours (gold, red) may go a
## little brighter, they keep their hue under the glow. The accent (gems, lenses) may glow.
static func _tame(c: Dictionary) -> Dictionary:
    var out := c.duplicate()
    for code in LUM_CAPS.keys():
        var col: Color = c[code]
        var lum := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
        var cap := float(LUM_CAPS[code]) + LUM_SAT_BONUS * col.s
        if lum > cap:
            var k := cap / lum
            out[code] = Color(col.r * k, col.g * k, col.b * k)
    return out


static func _fallback(id: String, it: Dictionary) -> Dictionary:
    var main: Color = MATERIAL.get(kind_of(id, it), LEATHER)
    var look: Dictionary = it.get("look", {})
    var tint = look.get("tint", it.get("element", null))
    if tint is Color:
        main = Color(tint, 1.0)
    elif tint is String and Items.ELEMENTS.has(tint):
        main = Element.COLORS[Items.ELEMENTS[tint]]
    return _shades(main.darkened(0.15), main.lightened(0.45))


static func _shades(main: Color, accent: Color) -> Dictionary:
    return { "1": main, "2": main.darkened(0.45), "3": main.lightened(0.38), "4": accent }


static func _sample(tex: Texture2D, tint: Color) -> Dictionary:
    if tex == null:
        return {}
    var img := tex.get_image()
    if img == null or img.is_empty():
        return {}
    img = img.duplicate()
    if img.is_compressed():
        img.decompress()
    img.convert(Image.FORMAT_RGBA8)
    # Bins: 12 hues for coloured pixels, two greys (dark, light) for the rest.
    var bins: Array = []
    for i in 14:
        bins.append([])
    var total := 0
    for y in img.get_height():
        for x in img.get_width():
            var c := img.get_pixel(x, y)
            if c.a < 0.5:
                continue
            c = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0)
            if c.v < 0.14:
                continue   # the tile's black outline and deep shadow
            var bi := 0
            if c.s < 0.2:
                bi = 12 if c.v < 0.55 else 13
            else:
                bi = int(c.h * 12.0) % 12
            (bins[bi] as Array).append(c)
            total += 1
    if total == 0:
        return {}
    var best := 0
    for i in 14:
        if (bins[i] as Array).size() > (bins[best] as Array).size():
            best = i
    # Neighbouring hue bins are the same colour shaded: merge them into the main one.
    var main_px: Array = (bins[best] as Array).duplicate()
    if best < 12:
        for nb in [(best + 11) % 12, (best + 1) % 12]:
            if (bins[nb] as Array).size() * 3 >= main_px.size():
                main_px.append_array(bins[nb])
    main_px.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
    var n := main_px.size()
    var main := _mean(main_px, n / 4, n - n / 4)
    var dark := _mean(main_px, 0, maxi(1, n / 4))
    var light := _mean(main_px, n - maxi(1, n / 4), n)
    # Keep three readable steps however flat the tile's shading is.
    dark = dark.lerp(main.darkened(0.45), 0.5)
    light = light.lerp(main.lightened(0.38), 0.5)
    if main.get_luminance() < 0.2:
        main = main.lightened(0.25)
        light = light.lightened(0.25)
    # The accent: the strongest other bin that is clearly a different colour.
    var acc := Color(-1, 0, 0)
    var acc_score := 0.0
    for i in 14:
        var px: Array = bins[i]
        if i == best or px.size() < maxi(4, total / 25):
            continue
        if best < 12 and i < 12 and _hue_gap(i, best) < 2:
            continue
        var m := _mean(px, 0, px.size())
        var score := float(px.size()) * (0.4 + m.s) * (0.4 + m.v)
        if score > acc_score:
            acc_score = score
            px.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
            acc = _mean(px, px.size() / 2, px.size())
    if acc.r < 0.0:
        acc = light.lightened(0.35)
    return { "1": main, "2": dark, "3": light, "4": acc }


static func _hue_gap(a: int, b: int) -> int:
    var d := absi(a - b)
    return mini(d, 12 - d)


static func _mean(px: Array, from: int, to: int) -> Color:
    var r := 0.0
    var g := 0.0
    var b := 0.0
    var n := 0
    for i in range(clampi(from, 0, px.size()), clampi(to, 0, px.size())):
        var c: Color = px[i]
        r += c.r
        g += c.g
        b += c.b
        n += 1
    if n == 0:
        return Color(0.5, 0.5, 0.5)
    return Color(r / n, g / n, b / n)


# --- Drawing (called from FigureGen._render) -------------------------------------


## The piece palette: the item's colours plus the figure's skin and hair.
static func pal(colors: Dictionary, fig_pal: Array[Color]) -> Dictionary:
    var out := colors.duplicate()
    out["s"] = fig_pal[2]
    out["h"] = fig_pal[1]
    out["o"] = FigureGen.OUTLINE
    out["b"] = FigureGen.BONE
    out["y"] = LAMP
    out["g"] = GLASS
    return out


## The worn head (face included) replacing the theme head. Face and hair pixels go on the
## head layer (so accents that read eyes still find them), the piece on the worn layer.
static func draw_head(buf: FigureGen.Buf, kind: String, p: Dictionary) -> void:
    var grid: Array = HEADS.get(kind, HEADS["cap"])
    for r in grid.size():
        var row := String(grid[r])
        for c in row.length():
            var ch := row[c]
            var layer := FigureGen.L_HEAD if "sho".contains(ch) else FigureGen.L_WORN
            buf.put(3 + c, r, ch, p, layer)


## A chest piece's cape (behind everything), or "" when it has none.
static func chest_cape(kind: String) -> String:
    return String(CHESTS.get(kind, {}).get("cape", ""))


static func chest_covers(kind: String) -> bool:
    return bool(CHESTS.get(kind, {}).get("covers", false))


## The cape rows in item codes: the theme cape's "d" body as main, its "#" hem as dark.
static func draw_cape(buf: FigureGen.Buf, kind: String, p: Dictionary, step: bool) -> void:
    var cape: Array = FigureGen.CAPES.get(chest_cape(kind), [])
    for r in cape.size():
        var cy := 7 + r
        var shift := 1 if step and cy >= 12 else 0
        var row := String(cape[r]).replace("d", "1").replace("#", "2")
        buf.row(row, 1 + shift, cy, p, FigureGen.L_WORN)


static func draw_chest(buf: FigureGen.Buf, kind: String, p: Dictionary, tx: int, trim: int, ax: int, ar: int) -> void:
    var def: Dictionary = CHESTS.get(kind, CHESTS["jerkin"])
    var torso: Array = def["torso"]
    for r in torso.size():
        buf.row(FigureGen._resize_row(String(torso[r]), trim), tx, 7 + r, p, FigureGen.L_WORN)
    if def.has("arm"):
        _arms(buf, def["arm"], p, ax, ar)


static func draw_hands(buf: FigureGen.Buf, kind: String, p: Dictionary, ax: int, ar: int) -> void:
    var def: Dictionary = HANDS.get(kind, HANDS["gloves"])
    _arms(buf, def, p, ax, ar)
    if def.get("blade", false):
        # A sword held up along the outside of the right arm: guard over the fist, blade
        # to the shoulder.
        var bx := mini(ar + 2, 14)
        for y in range(4, 10):
            buf.put(bx, y, "3", p, FigureGen.L_WORN)
        buf.put(bx, 3, "1", p, FigureGen.L_WORN)
        buf.put(bx - 1, 10, "4", p, FigureGen.L_WORN)
        buf.put(bx, 10, "4", p, FigureGen.L_WORN)
        buf.put(bx, 11, "2", p, FigureGen.L_WORN)


## A grid on both arms: as written on the left arm at ax + x, mirrored on the right.
static func _arms(buf: FigureGen.Buf, def: Dictionary, p: Dictionary, ax: int, ar: int) -> void:
    var dx := int(def["x"])
    var rows: Array = def["rows"]
    for r in rows.size():
        var row := String(rows[r])
        var w := row.length()
        var y := int(def["y"]) + r
        _row_clipped(buf, row, ax + dx, y, p)
        _row_clipped(buf, FigureGen._mirror(row), ar + 2 - dx - w, y, p)


## Like Buf.row on the worn layer, but never in the outermost columns (the outline needs
## them).
static func _row_clipped(buf: FigureGen.Buf, row: String, x0: int, y: int, p: Dictionary) -> void:
    for c in row.length():
        var x := x0 + c
        if x < 1 or x > 14:
            continue
        buf.put(x, y, row[c], p, FigureGen.L_WORN)


## Feet on both legs, drawn after the torso and chest piece: the two foot rows always show
## on the leg columns (a long hem parts round the boots, so they read at this size), the
## rest (the toe column, anything above row 13) only lands on bare legs or empty pixels.
## In the step frame the first foot is lifted (only its sole, one row up), like the bare
## legs.
static func draw_feet(buf: FigureGen.Buf, kind: String, p: Dictionary, legs: Array, step: bool) -> void:
    var def: Dictionary = FEET.get(kind, FEET["boots"])
    var rows: Array = def["rows"]
    var y0 := int(def["y"])
    for li in legs.size():
        var cols: Array = legs[li]
        var xs: Array = []   # grid column -> x
        if li == 0:
            xs = [int(cols[0]) - 1, int(cols[0]), int(cols[cols.size() - 1]) if cols.size() > 1 else -99]
        else:
            xs = [int(cols[cols.size() - 1]) + 1, int(cols[cols.size() - 1]), int(cols[0]) if cols.size() > 1 else -99]
        for r in rows.size():
            var y := y0 + r
            if step and li == 0:
                if r != rows.size() - 1:
                    continue
                y = 13
            var row := String(rows[r])
            for c in mini(3, row.length()):
                var x: int = xs[c]
                if x < 1 or x > 14:
                    continue
                var under := buf.layer_at(x, y)
                var foot := y >= 13 and c > 0
                if not foot and y < 14 and under != 0 and under != FigureGen.L_LEGS:
                    continue
                buf.put(x, y, row[c], p, FigureGen.L_WORN)
