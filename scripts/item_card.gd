class_name ItemCard
extends RefCounted
## One item card for every screen (WoW / Brotato style): a rarity frame and title, the
## slot and rarity, the icon at 2x, then every effect as its own short line, the set and
## its next bonus, the price, and a comparison against what the player wears now.
## Pedestals, the character sheet, the journal and the overlays all draw through here,
## so an item reads the same everywhere.
##
##   ItemCard.draw(canvas, rect, item, opts)       rect.position + width; height grows to fit
##   ItemCard.height_for(item, opts)               opts.width (default 340)
##   ItemCard.describe_mods(item)                  every effect line as plain strings
##   ItemCard.draw_gun(canvas, rect, data, opts)   the same card for a gun
##   ItemCard.gun_height(data, opts)
##   ItemCard.draw_note(canvas, rect, title, sub, body, icon)   a plain card (empty slots;
##                                                              icon is a Texture2D, dimmed)
##   ItemCard.draw_frame(canvas, rect, color, highlight)        the frame alone
##   ItemCard.rival_for(player, item)              what equipping `item` would replace
##   ItemCard.draw_element_badge(canvas, pos, element, size)    a neutral element chip
##   ItemCard.element_badge_size(element, size)                 its size, for layout
##   ItemCard.draw_pips(canvas, pos, count, color, pip)         tier / rarity pips
##
## Colour rule (GDD 6, "Rarity owns colour"): the frame, border, title and pips take the
## rarity colour (Items.RARITY_COLORS; a gun's tier through Items.tier_rarity) and the
## rarity word is always printed beside it. An element never colours a frame, border or
## name: it shows only as a badge, a dark chip with a neutral border, a small swatch of
## the element colour and the element's name in neutral text.
##
## opts: player (set counts, carried guns, free weight), compare (item Dictionary it would
## replace), price (int), afford (bool), highlight (bool), notes (Array of String, dim),
## width (float, for the height functions). Gun opts: tier, mods, gun (the carried Gun),
## compact (bool: names only for mods).

const PAD := 14.0
const ICON := 96.0   # a 32 px Dungeon Crawl tile at 3x (4.1)
const TITLE_SIZE := 28
const LABEL_SIZE := 18
const TEXT_SIZE := 22
const PRICE_SIZE := 24
const LINE_GAP := 4.0
const DEFAULT_WIDTH := 360.0
const MAX_WORDS := 25        # 4.4: name, effect, stack, deltas and resonance lines
const MAX_HEIGHT := 300.0    # 4.4
const CURSED_COL := Color(1.0, 0.25, 0.25)

const BG := Color(0.05, 0.04, 0.06, 0.92)
const PROMPT_COL := Color(0.6, 1.0, 1.0)   # a button hint, like the pedestal's verb
const TEXT := Color(0.92, 0.89, 0.82)
const DIM := Color(0.62, 0.59, 0.57)
const GOOD := Color(0.45, 0.95, 0.45)
const BAD := Color(1.0, 0.42, 0.38)
const TRIGGER_COL := Color(0.55, 0.9, 1.0)
const COND_COL := Color(1.0, 0.72, 0.4)
const ACTIVE_COL := Color(1.0, 0.9, 0.45)
const SCRAP_COL := Color(0.85, 0.72, 0.35)
## Set names (WoW's set yellow): never the set's element colour, never a rarity colour.
const SET_COL := Color("#FFD100")

const ROMAN := ["I", "II", "III", "IV", "V"]

## Element badge: neutral chip, swatch of the element colour, neutral name.
const BADGE_SIZE := 18
const BADGE_FILL := Color(0.10, 0.09, 0.11, 0.95)
const BADGE_EDGE := Color(0.46, 0.43, 0.42)
const BADGE_TEXT := Color(0.86, 0.83, 0.77)

const SLOT_TITLES := {
    "head": "Head", "chest": "Chest", "hands": "Hands", "feet": "Feet", "ring": "Ring",
    "trinket": "Trinket", "mod": "Weapon mod", "active": "Active",
}

## key -> [label, format, plural label]. Formats: pct (fraction), int, dec, x.
const STATS := {
    "summon_dmg": ["summon damage", "pct"], "summon_rate": ["summon attack rate", "pct"],
    "summon_cap": ["to every summon cap", "int"], "summon_reach": ["summon reach", "pct"],
    "summon_speed": ["summon speed", "pct"], "summon_size": ["summon size", "pct"],
    "drone_rate": ["drone attack rate", "pct"], "swarm_respawn": ["faster swarm return", "pct"],
    "turret_life": ["turret time", "pct"],
    "ground_dmg": ["ground damage", "pct"], "zone_radius": ["zone radius", "pct"],
    "zone_life": ["zone time", "pct"], "zone_rate": ["zone tick rate", "pct"],
    "zone_slow": ["zone slow", "pct"], "trap_cap": ["to every trap cap", "int"],
    "trap_radius": ["trap size", "pct"], "hold_time": ["snare hold", "pct"],
    "lay_rate": ["laying speed", "pct"], "ring_radius": ["ring radius", "pct"],
    "ring_move": ["ring damage while moving", "pct"], "totem_life": ["totem time", "pct"],
    "trail_life": ["trail time", "pct"],
    "dmg": ["damage", "pct"], "potency": ["reaction potency", "pct"], "fire_rate": ["fire rate", "pct"],
    "proj_speed": ["projectile speed", "pct"], "range": ["range", "pct"], "pierce": ["pierce", "int"],
    "proj_count": ["projectile per shot", "int", "projectiles per shot"], "max_hp": ["max HP", "int"],
    "regen": ["HP regen per second", "dec"], "speed": ["move speed", "pct"], "carry": ["carry weight", "int"],
    "vent_charge": ["vent charge speed", "pct"], "pressure_limit": ["vent capacity", "int"],
    "vent_radius": ["vent radius", "pct"], "vent_power": ["vent power", "pct"], "scrap_gain": ["scrap", "pct"],
    "crit": ["crit chance", "pct"], "crit_dmg": ["crit damage", "x"], "armor": ["armour", "int"],
    "dodge": ["dodge", "pct"], "state_duration": ["element duration", "pct"],
    "vs_wet": ["damage vs wet", "pct"], "vs_burning": ["damage vs burning", "pct"],
    "vs_frozen": ["damage vs frozen", "pct"], "vs_shocked": ["damage vs shocked", "pct"],
    "vs_oiled": ["damage vs oiled", "pct"], "lifesteal": ["HP per reaction", "int"],
    "thorns": ["thorns damage", "int"], "chain_jumps": ["chain jump", "int", "chain jumps"],
    "bounce": ["bounce", "int", "bounces"], "xp_gain": ["XP gain", "pct"], "luck": ["luck", "pct"],
    "g_dmg": ["damage on this weapon", "pct"], "g_fire_rate": ["fire rate on this weapon", "pct"],
    "g_count": ["projectile on this weapon", "int", "projectiles on this weapon"],
    "g_pierce": ["pierce on this weapon", "int"], "g_range": ["range on this weapon", "pct"],
    "g_speed": ["shot speed on this weapon", "pct"], "g_pressure": ["pressure on this weapon", "pct"],
    "homing": ["homing", "dec"], "splash": ["px splash", "int"], "shards": ["shard per shot", "int", "shards per shot"],
    "shot_size": ["shot size", "pct"], "shot_speed": ["shot speed", "pct"],
    "orbitals": ["orbiting familiar", "int", "orbiting familiars"], "gun_slots": ["gun slot", "int", "gun slots"],
}
const FLAGS := {
    "spectral": "Spectral shots: pass through obstacles",
    "boomerang": "Shots return like boomerangs",
    "orbital_element": "Familiars carry your first weapon's element",
}
const EVENTS := {
    "hit": "On hit", "kill": "On kill", "elite_kill": "On elite kill", "reaction": "On any reaction",
    "vent": "When you vent", "room_clear": "On room clear", "hurt": "When hurt",
    "overheat": "On overheat", "freeze_up": "On freeze-up",
}
const CONDS := {
    "target_wet": "vs wet foes", "target_burning": "vs burning foes", "target_frozen": "vs frozen foes",
    "target_shocked": "vs shocked foes", "target_oiled": "vs oiled foes", "target_poisoned": "vs poisoned foes",
    "target_marked": "vs marked foes", "elite": "vs elites", "hot": "while hot", "cold": "while cold",
    "low_hp": "below 40% HP", "high_hp": "above 80% HP", "full_hp": "at full HP", "moving": "while moving",
    "still": "standing still", "calm": "while calm",
}


# --- Public: items ------------------------------------------------------------


static func draw(canvas: CanvasItem, rect: Rect2, item: Dictionary, opts: Dictionary = {}) -> void:
    if item.is_empty():
        return
    _render(canvas, rect, _item_model(item, opts), opts)


static func height_for(item: Dictionary, opts: Dictionary = {}) -> float:
    if item.is_empty():
        return 0.0
    return _model_height(_item_model(item, opts), float(opts.get("width", DEFAULT_WIDTH)))


## Every effect of an item as short lines: one per mod, trigger, conditional and active.
static func describe_mods(item: Dictionary) -> Array[String]:
    var out: Array[String] = []
    for row in _effect_rows(item):
        out.append(String(row["t"]))
    return out


## The item that equipping `item` would replace (mirrors Player.equip), or {}.
## Items stack (3.1): nothing is replaced, so there is never a rival. Kept for old callers.
static func rival_for(_player, _item: Dictionary) -> Dictionary:
    return {}


# --- Public: guns ---------------------------------------------------------------


static func draw_gun(canvas: CanvasItem, rect: Rect2, data: GunData, opts: Dictionary = {}) -> void:
    if data == null:
        return
    _render(canvas, rect, _gun_model(data, opts), opts)


static func gun_height(data: GunData, opts: Dictionary = {}) -> float:
    if data == null:
        return 0.0
    return _model_height(_gun_model(data, opts), float(opts.get("width", DEFAULT_WIDTH)))


# --- Public: plain card and frame -----------------------------------------------


static func draw_note(canvas: CanvasItem, rect: Rect2, title: String, sub: String, body: String, icon: Texture2D, opts: Dictionary = {}) -> void:
    var model := {
        "icon": icon, "icon_tint": Color(0.45, 0.42, 0.45), "title": title, "title_col": TEXT,
        "sub": sub, "sub_col": DIM, "frame": Color(0.4, 0.36, 0.38),
        "rows": [_row(body, TEXT_SIZE, DIM)],
    }
    _render(canvas, rect, model, opts)


static func note_height(title: String, sub: String, body: String, width: float = DEFAULT_WIDTH) -> float:
    var model := { "title": title, "sub": sub, "rows": [_row(body, TEXT_SIZE, DIM)] }
    return _model_height(model, width)


## The card frame: dark panel, rarity band on top, double border, corner studs.
static func draw_frame(canvas: CanvasItem, r: Rect2, col: Color, highlight: bool = false) -> void:
    if highlight:
        canvas.draw_rect(r.grow(5.0), Color(col, 0.25))
    canvas.draw_rect(r, BG)
    canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), Color(col, 0.9))
    var edge := col.lightened(0.35) if highlight else Color(col, 0.95)
    canvas.draw_rect(r, edge, false, 4.0 if highlight else 2.5)
    canvas.draw_rect(r.grow(-6.0), Color(col, 0.22), false, 1.0)
    for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
        var corner: Vector2 = c
        canvas.draw_rect(Rect2(corner - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.9))
        canvas.draw_rect(Rect2(corner - Vector2(3, 3), Vector2(6, 6)), edge)


## A tag chip (4.1): an element tag is its element badge; any other tag the same neutral
## chip with a small swatch in the tag colour and its name.
static func draw_tag_chip(canvas: CanvasItem, pos: Vector2, tag: String, size: int = BADGE_SIZE) -> Vector2:
    if Items.ELEMENTS.has(tag):
        return draw_element_badge(canvas, pos, tag, size)
    var font: Font = Art.FONT
    var label := Items.tag_name(tag)
    var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    var sw := float(size) * 0.6
    var box := Rect2(pos, Vector2(8.0 + sw + 6.0 + tw + 8.0, float(size) + 6.0))
    canvas.draw_rect(box, BADGE_FILL)
    canvas.draw_rect(box, BADGE_EDGE, false, 1.0)
    canvas.draw_rect(Rect2(pos + Vector2(8.0, (box.size.y - sw) / 2.0), Vector2(sw, sw)), Items.tag_color(tag))
    canvas.draw_string(font, pos + Vector2(8.0 + sw + 6.0, 3.0 + font.get_ascent(size)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, BADGE_TEXT)
    return box.size


## Element.Kind of an element given as a Kind int or an item element key ("fire").
## NONE for anything else.
static func element_kind(element) -> int:
    if element is String or element is StringName:
        return int(Items.ELEMENTS.get(String(element), Element.Kind.NONE))
    if element is int and Element.NAMES.has(element):
        return element
    return Element.Kind.NONE


## Size of an element badge whose name is drawn at font `size`.
static func element_badge_size(element, size: int = BADGE_SIZE) -> Vector2:
    var kind := element_kind(element)
    var name := String(Element.NAMES.get(kind, "?"))
    var sw := roundf(float(size) * 0.6)
    var tw := Art.FONT.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    return Vector2(roundf(6.0 + sw + 5.0 + tw + 7.0), float(size) + 6.0)


## A neutral element chip at `pos` (top-left): dark fill, neutral border, a small swatch
## of the element colour, then the element's name in neutral text. The only way an
## element shows in UI (never a frame or name colour). `element` is an Element.Kind or
## an item element key. Returns the badge size so callers can lay out a row.
static func draw_element_badge(canvas: CanvasItem, pos: Vector2, element, size: int = BADGE_SIZE) -> Vector2:
    var kind := element_kind(element)
    if kind == Element.Kind.NONE:
        return Vector2.ZERO
    var bs := element_badge_size(kind, size)
    var r := Rect2(pos.floor(), bs)
    canvas.draw_rect(r, BADGE_FILL)
    canvas.draw_rect(r, BADGE_EDGE, false, 1.0)
    var sw := roundf(float(size) * 0.6)
    var sq := Rect2(r.position + Vector2(6.0, roundf((bs.y - sw) * 0.5)), Vector2(sw, sw))
    canvas.draw_rect(sq.grow(1.0), Color(0, 0, 0, 0.9))
    canvas.draw_rect(sq, Element.COLORS[kind])
    _text(canvas, Vector2(sq.end.x + 5.0, r.position.y + 3.0), String(Element.NAMES[kind]), size, BADGE_TEXT)
    return bs


static var _swatch_cache: Dictionary = {}


## A small square texture of element swatches (Colors or Element.Kinds), side by side in
## vertical bands with a dark rim: the element mark for Button icons and lists, where a
## drawn badge does not fit. Cached.
static func swatch_texture(colors: Array, px: int = 18) -> Texture2D:
    var cols: Array = []
    for c in colors:
        cols.append(c if c is Color else Element.COLORS.get(element_kind(c), Color.WHITE))
    var key := "%d:%s" % [px, str(cols)]
    if _swatch_cache.has(key):
        return _swatch_cache[key]
    var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0.9))
    var inner := px - 4
    var n := maxi(1, cols.size())
    for x in inner:
        var col: Color = cols[mini(n - 1, x * n / inner)] if not cols.is_empty() else Color.WHITE
        for y in inner:
            img.set_pixel(2 + x, 2 + y, Color(col, 1.0))
    var tex := ImageTexture.create_from_image(img)
    _swatch_cache[key] = tex
    return tex


## A row of `count` square pips from `pos` (top-left) rightward, each with a dark rim:
## a gun's tier or an item's rarity (count = rarity + 1) as a cue that is not colour.
static func draw_pips(canvas: CanvasItem, pos: Vector2, count: int, color: Color, pip: float = 4.0) -> void:
    for i in count:
        var r := Rect2(pos + Vector2(float(i) * (pip + 2.0), 0.0), Vector2(pip, pip))
        canvas.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.8))
        canvas.draw_rect(r, color)


## One stat line, e.g. "+12% damage", "+2 armour", "Chain Lightning +40% potency".
static func stat_line(key: String, value) -> String:
    if key == "extra_element":
        return "This weapon also applies %s" % _el_name(String(value))
    if FLAGS.has(key):
        return String(FLAGS[key])
    var v := float(value)
    if key.begins_with("potency:"):
        return "%s %s potency" % [key.substr(8), _fmt("pct", v)]
    if key.begins_with("dmg_"):
        return "%s %s damage" % [_fmt("pct", v), _el_name(key.substr(4))]
    if key.begins_with("potency_"):
        return "%s %s potency" % [_fmt("pct", v), _el_name(key.substr(8))]
    if key.begins_with("fire_rate_"):
        return "%s fire rate with %s weapons" % [_fmt("pct", v), _el_name(key.substr(10))]
    if key.begins_with("pierce_"):
        return "%s pierce with %s weapons" % [_fmt("int", v), _el_name(key.substr(7))]
    if STATS.has(key):
        var s: Array = STATS[key]
        var label := String(s[0])
        if s.size() > 2 and absf(v) > 1.0:
            label = String(s[2])
        return "%s %s" % [_fmt(String(s[1]), v), label]
    return "%s %s" % [_fmt("pct", v), key]


## Just the value part of a stat line ("+8%", "+2", "+0.5x").
static func stat_value(key: String, value) -> String:
    if key == "extra_element":
        return _el_name(String(value))
    if FLAGS.has(key):
        return "yes"
    var v := float(value)
    if key.begins_with("pierce_"):
        return _fmt("int", v)
    if key.begins_with("dmg_") or key.begins_with("potency") or key.begins_with("fire_rate_"):
        return _fmt("pct", v)
    if STATS.has(key):
        return _fmt(String(STATS[key][1]), v)
    return _fmt("pct", v)


## A trigger in plain words: "On hit vs oiled foes (18%): apply Fire".
static func trigger_line(t: Dictionary) -> String:
    var on := String(t.get("on", ""))
    var head := String(EVENTS.get(on, on.capitalize()))
    if on.begins_with("reaction:"):
        head = "On %s" % on.substr(9)
    if t.has("if"):
        head += " " + String(CONDS.get(String(t["if"]), String(t["if"])))
    if t.has("every"):
        head += ", every %s" % _ordinal(int(t["every"]))
    if t.has("chance"):
        head += " (%d%%)" % roundi(float(t["chance"]) * 100.0)
    return "%s: %s" % [head, action_text(t, false)]


## What one trigger or active action does.
static func action_text(t: Dictionary, active: bool) -> String:
    var el := _act_el(t, active)
    var pot := roundi(float(t.get("potency", 5.0)))
    var where := ""
    if String(t.get("at", "")) == "target":
        where = " on the nearest foe"
    match String(t.get("do", "")):
        "apply":
            return "apply %s" % el
        "nova":
            return "%s nova%s, %d damage" % [el, where, pot]
        "heal":
            return "heal %d" % roundi(float(t.get("amount", 10.0)))
        "scrap":
            return "+%d scrap" % roundi(float(t.get("amount", 5.0)))
        "pressure":
            return "%+d pressure" % roundi(float(t.get("amount", 0.0)))
        "shoot":
            return "fire %d %s shots" % [int(t.get("count", 3)), el]
        "shield":
            return "untouchable for %.1f s" % float(t.get("amount", 1.0))
        "slow":
            return "slow every foe nearby"
        "chain":
            if t.has("count"):
                return "lightning arcs from the %d nearest foes" % int(t["count"])
            return "arc lightning"
        "spread":
            return "spread %s%s" % [el, where if where != "" else " around you"]
        "xp":
            return "+%d XP" % roundi(float(t.get("amount", 5.0)))
        "recall":
            return "every knife flies back"
        "rally":
            return "every summon dashes to a foe and strikes"
        "brood":
            return "hatch a wasp for %.0f s" % float(t.get("secs", 4.0))
        "swarm_call":
            return "%d wasps fight beside you for %.0f s" % [int(t.get("count", 6)), float(t.get("secs", 8.0))]
        "mark":
            return "mark the foe"
        "hair_trigger":
            return "your traps near you burst"
        "seed":
            return "plant every trap and totem at once"
        "spring_all":
            return "every trap and mine of yours bursts"
    return String(t.get("do", "?"))


# --- Models -----------------------------------------------------------------------


static func _row(text: String, size: int, color: Color, gap: float = 0.0, indent: float = 0.0) -> Dictionary:
    return { "t": text, "s": size, "c": color, "gap": gap, "indent": indent }


static func _sep() -> Dictionary:
    return { "sep": true, "gap": 6.0 }


## A row of element badges (Element.Kind ints).
static func _badges(kinds: Array) -> Dictionary:
    return { "badges": kinds, "gap": 2.0 }


## Effect rows of an item: mods, conditionals, triggers, the active use.
static func _effect_rows(item: Dictionary) -> Array:
    var rows: Array = []
    var mods: Dictionary = item.get("mods", {})
    for k in mods.keys():
        var key := String(k)
        var neg := false
        if key != "extra_element" and not FLAGS.has(key):
            neg = float(mods[k]) < 0.0
        rows.append(_row(stat_line(key, mods[k]), TEXT_SIZE, BAD if neg else TEXT))
    var cm: Dictionary = item.get("cond_mods", {})
    for cond in cm.keys():
        var label := String(CONDS.get(String(cond), String(cond)))
        for k in cm[cond].keys():
            rows.append(_row("%s: %s" % [label, stat_line(String(k), cm[cond][k])], TEXT_SIZE, COND_COL))
    for t in item.get("triggers", []):
        rows.append(_row(trigger_line(t), TEXT_SIZE, TRIGGER_COL))
    if item.has("active"):
        var act: Dictionary = item["active"]
        var parts: Array = []
        for a in act.get("do", []):
            parts.append(action_text(a, true))
        var charges := int(act.get("charges", 1))
        rows.append(_row("Use: %s (%d charge%s)" % [", then ".join(parts), charges, "" if charges == 1 else "s"], TEXT_SIZE, ACTIVE_COL))
    if rows.is_empty():
        rows.append(_row(String(item.get("desc", "")), TEXT_SIZE, TEXT))
    return rows


## "Heats you 3 per shot"; continuous guns (beams, sprays) say it per second.
static func _pressure_text(verb: String, data: GunData, rate: float) -> String:
    var v := absf(data.pressure_per_shot)
    if data.mechanic == "beam" or data.mechanic == "cone":
        return "%s you %.0f per second" % [verb, v * rate]
    return "%s you %.0f per shot" % [verb, v]


## Core loop reset 4.1: one card, Brotato style. A big icon on a rarity plate, the name, the
## rarity word, up to 3 tag chips, "you have 2" when owned; then ONE effect line, up to 3
## deltas against your build (green better, red worse), one resonance or synergy line, the
## curse, the price. No slots, no "replaces", no set lists. Cards keep to MAX_WORDS words
## (name, effect, stack, deltas, resonance) and MAX_HEIGHT px: deltas are dropped first.
static func _item_model(item: Dictionary, opts: Dictionary) -> Dictionary:
    var rarity := clampi(int(item.get("rarity", 0)), 0, Items.RARITY_COLORS.size() - 1)
    var rc: Color = Items.RARITY_COLORS[rarity]
    var tc: Color = Items.RARITY_TEXT_COLORS[rarity]
    var id := String(item.get("id", ""))
    var player = opts.get("player", null)
    if player != null and not is_instance_valid(player):
        player = null
    var width := float(opts.get("width", DEFAULT_WIDTH))
    var rows: Array = []
    var words := _words(String(item.get("name", "")))

    # The one effect line (Items' authored line: verb first, or a signed number and unit).
    var effect := String(item.get("desc", ""))
    rows.append(_row(effect, TEXT_SIZE, TEXT))
    words += _words(effect)

    # Stack: "You have 2. Taking this makes 3." (in the header, dim).
    var stack := ""
    var owned := 0
    if player != null and id != "":
        owned = int(player.item_count(id))
        if bool(opts.get("owned", false)):
            stack = "You have %d." % owned if owned > 1 else ""
        elif owned > 0 and String(item.get("slot", "")) != "active":
            stack = "You have %d. Taking this makes %d." % [owned, owned + 1]
            if String(item.get("stack", "add")) == "once":
                stack = "You have it: a copy adds nothing."
        words += _words(stack)

    # Synergy, else resonance: one line in its colour.
    var extra: Array = []
    if player != null and id != "" and not bool(opts.get("owned", false)):
        var syn: Dictionary = Items.synergy_if_taken(player, id)
        if not syn.is_empty():
            extra.append(_row("Forms SYNERGY: %s" % syn["name"], TEXT_SIZE, syn.get("color", SET_COL)))
        else:
            var res_line := _resonance_line(player, item)
            if not res_line.is_empty():
                extra.append(res_line)
    for e in extra:
        words += _words(String(e["t"]))

    # Curse (cursed loot, deal cards): the red line under the effect.
    var curse := String(opts.get("curse", ""))
    var curse_rows: Array = []
    if curse != "" and Items.CURSES.has(curse):
        curse_rows.append(_row("Curse: %s" % String(Items.CURSES[curse]["line"]), TEXT_SIZE, BAD))
    var drawback := String(opts.get("drawback", ""))
    if drawback != "":
        curse_rows.append(_row(drawback, TEXT_SIZE, BAD))

    # Actives swap: the one honest line about what leaves.
    if player != null and String(item.get("slot", "")) == "active" and player.equipment.has("active") and String(player.equipment["active"]) != id:
        var old: Dictionary = Items.get_item(String(player.equipment["active"]))
        curse_rows.append(_row("Swaps out your %s" % String(old.get("name", "active")), LABEL_SIZE, DIM))

    var price_rows: Array = []
    if opts.has("price"):
        var price := int(opts["price"])
        var afford: bool = bool(opts.get("afford", true))
        var ptext := "FREE" if price <= 0 else "%d scrap" % price
        if price > 0 and not afford:
            var short := int(opts.get("short", 0))
            ptext += ("  need %d more" % short) if short > 0 else "  (not enough)"
        price_rows.append(_row(ptext, PRICE_SIZE, SCRAP_COL if afford or price <= 0 else BAD, 2.0))
    for n in opts.get("notes", []):
        price_rows.append(_row(String(n), LABEL_SIZE, DIM, 2.0))

    var chips: Array = []
    for t in item.get("tags", []):
        if chips.size() < 3:
            chips.append(String(t))
    var model := {
        "icon": Items.icon(item), "icon_tint": Items.ui_icon_tint(item), "big": true,
        "title": String(item.get("name", "?")), "title_col": tc,
        "sub": _sub_line(item), "sub_col": tc, "frame": rc, "pips": rarity + 1,
        "chips": chips, "stack": stack, "cursed": curse != "" or bool(opts.get("cursed", false)),
        "rows": rows,
    }
    # Deltas against the build, as many as the word and height budgets allow.
    var deltas: Array = _delta_rows(player, item, owned) if player != null and not bool(opts.get("owned", false)) else []
    var fixed: Array = rows + extra + curse_rows + price_rows
    model["rows"] = fixed
    while not deltas.is_empty():
        var dw := 0
        for d in deltas:
            dw += _words(String(d["t"]))
        model["rows"] = rows + deltas + extra + curse_rows + price_rows
        if words + dw <= MAX_WORDS and _model_height(model, width) <= MAX_HEIGHT:
            break
        deltas.pop_back()
        model["rows"] = rows + deltas + extra + curse_rows + price_rows
    for d in deltas:
        words += _words(String(d["t"]))
    model["words"] = words
    return model


## "Rare" (with "active, 2 charges" for an active, "gun mod" for a mod).
static func _sub_line(item: Dictionary) -> String:
    var word := Items.rarity_name(item)
    match String(item.get("slot", "")):
        "active":
            var ch := int(item.get("active", {}).get("charges", 1))
            return "%s active, %d charge%s" % [word, ch, "" if ch == 1 else "s"]
        "mod":
            return "%s weapon mod" % word
    return word


## Words for the readability budget: spaces split, numbers count, "->" does not.
static func _words(text: String) -> int:
    var n := 0
    for w in text.split(" ", false):
        if w != "->" and w != ":":
            n += 1
    return n


## Up to 3 stat lines this item changes on the build, before -> after, green or red.
static func _delta_rows(player, item: Dictionary, owned: int) -> Array:
    var out: Array = []
    if String(item.get("slot", "")) in ["mod", "active"]:
        return out
    var rule := String(item.get("stack", "add"))
    var marginal := Items.stack_factor(rule, owned + 1) - Items.stack_factor(rule, owned)
    if marginal <= 0.0:
        return out
    var mods: Dictionary = item.get("mods", {})
    for k in mods.keys():
        var key := String(k)
        if out.size() >= 3 or not DELTA_LABELS.has(key) or mods[k] is String:
            continue
        var add := float(mods[k]) * marginal
        var before: float = player.max_hp if key == "max_hp" else player.stat(key)
        var after := before + add
        if Items.STAT_CAPS.has(key):
            after = minf(after, float(Items.STAT_CAPS[key]))
        if key == "max_hp":
            after = maxf(20.0, after)
        var lab: Array = DELTA_LABELS[key]
        var line := "%s %s -> %s" % [lab[0], _dfmt(String(lab[1]), before), _dfmt(String(lab[1]), after)]
        var col := TEXT
        if after > before + 0.0001:
            col = GOOD
        elif after < before - 0.0001:
            col = BAD
        out.append(_row(line, TEXT_SIZE, col))
    return out


static func _dfmt(kind: String, v: float) -> String:
    match kind:
        "int":
            return "%d" % roundi(v)
        "pct0":
            return "%d%%" % roundi(v * 100.0)
        "x":
            return "x%.1f" % (2.0 + v)
    return "%+d%%" % roundi(v * 100.0)


## Stats a card shows before -> after: label, format ("pct" signed share, "pct0" plain share,
## "int", "x" crit multiplier).
const DELTA_LABELS := {
    "max_hp": ["Max HP", "int"], "armor": ["Armour", "int"], "speed": ["Speed", "pct"],
    "dodge": ["Dodge", "pct0"], "fire_rate": ["Fire rate", "pct"], "dmg": ["Damage", "pct"],
    "potency": ["Reaction power", "pct"], "crit": ["Crit", "pct0"], "crit_dmg": ["Crit hit", "x"],
    "range": ["Range", "pct"], "luck": ["Luck", "pct"], "scrap_gain": ["Scrap", "pct"],
    "xp_gain": ["XP", "pct"], "pressure_limit": ["Vent capacity", "int"],
    "vent_power": ["Vent power", "pct"], "vent_charge": ["Vent fill", "pct"],
    "vent_radius": ["Vent radius", "pct"], "thorns": ["Thorns", "int"],
    "state_duration": ["Element time", "pct"], "mend": ["Mending", "pct"],
    "shot_size": ["Shot size", "pct"], "lifesteal": ["Leech", "int"],
    "bounce": ["Bounces", "int"], "pierce": ["Pierce", "int"], "proj_count": ["Shots", "int"],
    "dash_charges": ["Dash charges", "int"], "orbitals": ["Orbitals", "int"], "shards": ["Shards", "int"],
}


## The resonance this item completes or advances: "Vent 2/3 -> 3/3: resonance!" in the tag's
## colour, or {} when it has no tag.
static func _resonance_line(player, item: Dictionary) -> Dictionary:
    var tags: Array = item.get("tags", [])
    if tags.is_empty():
        return {}
    var tc: Dictionary = Items.tag_counts(player)
    var best := ""
    var best_score := -1
    for t in tags:
        var n := int(tc.get(t, 0))
        var completes := n + 1 == Items.RESONANCE_AT[0] or n + 1 == Items.RESONANCE_AT[1]
        var score := (100 if completes else 0) + n
        if score > best_score:
            best_score = score
            best = String(t)
    var have := int(tc.get(best, 0))
    var goal := Items.RESONANCE_AT[0] if have < Items.RESONANCE_AT[0] else Items.RESONANCE_AT[1]
    if have >= Items.RESONANCE_AT[1]:
        return {}
    var text := "%s %d/%d -> %d/%d" % [Items.tag_name(best), have, goal, have + 1, goal]
    if have + 1 == goal:
        text += ": resonance!"
    return _row(text, TEXT_SIZE, Items.tag_color(best))


## A gun card (4.1): name, tier pips, element badges, one line for how it fires, damage per
## second and pressure, weight, copies; mods by name on a carried gun; the price.
static func _gun_model(data: GunData, opts: Dictionary) -> Dictionary:
    var gun = opts.get("gun", null)
    if gun != null and not is_instance_valid(gun):
        gun = null
    var player = opts.get("player", null)
    if player != null and not is_instance_valid(player):
        player = null
    var tier := int(opts.get("tier", 1))
    var mods: Array = opts.get("mods", [])
    if gun != null:
        tier = int(gun.tier)
        mods = gun.mods
    var dmg: float = data.damage * (1.0 + 0.35 * float(tier - 1))
    var rate: float = data.fire_rate * (1.0 + 0.12 * float(tier - 1))
    if gun != null:
        rate = gun.fire_rate()
    if gun != null and data.spin_up > 0.0:
        rate = gun.top_fire_rate()
    var dps := data.dps_at(dmg, rate)
    var rows: Array = []
    var how := data.how()
    if how == "" or how.length() > 60:
        how = (data.archetype.capitalize() if data.archetype != "" else "Gun")
    rows.append(_row(how, TEXT_SIZE, TEXT))
    var heat := ""
    if data.pressure_per_shot > 0.0:
        heat = ", heats %.0f" % absf(data.pressure_per_shot)
    elif data.pressure_per_shot < 0.0:
        heat = ", chills %.0f" % absf(data.pressure_per_shot)
    rows.append(_row("DPS %.0f%s" % [dps, heat], TEXT_SIZE, Color.WHITE))
    var weight_text := "Weight %d" % data.weight
    var weight_col := TEXT
    if player != null and gun == null:
        var free: int = int(player.weight_capacity) - int(player.total_weight())
        weight_text += ", %d free" % free
        if free < data.weight:
            weight_col = BAD
    rows.append(_row(weight_text, LABEL_SIZE, weight_col))
    if gun != null or not mods.is_empty():
        var names: Array = []
        for mid in mods:
            var m: Dictionary = Items.get_item(String(mid))
            if not m.is_empty():
                names.append(String(m["name"]))
        rows.append(_row("Mods %d/%d%s" % [mods.size(), tier, (": " + ", ".join(names)) if not names.is_empty() else ""], LABEL_SIZE, DIM))
    if player != null:
        for g in player.guns:
            if g != gun and g.data.id == data.id and int(g.tier) == tier and tier < Gun.MAX_TIER:
                rows.append(_row("You carry one: combines to tier %s" % ROMAN[tier], LABEL_SIZE, GOOD))
                break
    if opts.has("price"):
        var price := int(opts["price"])
        var afford: bool = bool(opts.get("afford", true))
        var ptext := "FREE" if price <= 0 else "%d scrap" % price
        if price > 0 and not afford:
            var short := int(opts.get("short", 0))
            ptext += ("  need %d more" % short) if short > 0 else "  (not enough)"
        rows.append(_row(ptext, PRICE_SIZE, SCRAP_COL if afford or price <= 0 else BAD, 2.0))
    for n in opts.get("notes", []):
        rows.append(_row(String(n), LABEL_SIZE, DIM, 2.0))
    var title := data.display_name
    if tier > 1:
        title += " " + ROMAN[clampi(tier - 1, 0, ROMAN.size() - 1)]
    # Arsenal expansion 3.1: rarity is fixed per weapon and owns the frame and the name
    # colour; the tier shows as pips (and a bright rim at IV). The family is a tag chip.
    var tr := clampi(data.rarity, 0, Items.RARITY_NAMES.size() - 1)
    var chips: Array = [data.element]
    for extra in [data.alt_element, data.extra_element]:
        if extra != Element.Kind.NONE and not chips.has(extra):
            chips.append(extra)
    chips = chips.slice(0, 2)
    chips.append(data.family_tag())
    var words := _words(title)
    for r in rows:
        if r.has("t") and String(r["t"]).find("scrap") < 0 and r["s"] != PRICE_SIZE:
            words += _words(String(r["t"]))
    return {
        "icon": Art.gun_icon(data.id), "icon_tint": Color.WHITE, "big": true, "title": title,
        "title_col": Items.RARITY_TEXT_COLORS[tr],
        "sub": "%s %s, tier %s" % [Items.RARITY_NAMES[tr], "gun" if data.family == "gun" else data.family + " weapon", ROMAN[clampi(tier - 1, 0, ROMAN.size() - 1)]],
        "sub_col": Items.RARITY_TEXT_COLORS[tr], "frame": Items.RARITY_COLORS[tr], "pips": clampi(tier, 1, 5),
        "rim": tier >= Gun.MAX_TIER,
        "chips": chips, "rows": rows, "words": words,
    }


## Readability numbers of one card (the --card-shot test): words, effect lines, smallest
## font, height.
static func card_stats(item: Dictionary, opts: Dictionary = {}) -> Dictionary:
    var model := _item_model(item, opts)
    return _stats_of(model, opts)


static func gun_stats(data: GunData, opts: Dictionary = {}) -> Dictionary:
    return _stats_of(_gun_model(data, opts), opts)


static func _stats_of(model: Dictionary, opts: Dictionary) -> Dictionary:
    var w := float(opts.get("width", DEFAULT_WIDTH))
    var smallest := TITLE_SIZE
    for r in model.get("rows", []):
        if r.has("s"):
            smallest = mini(smallest, int(_row_font(r)[1]))
    smallest = mini(smallest, LABEL_SIZE if (model.get("chips", []) as Array).size() > 0 or String(model.get("stack", "")) != "" else smallest)
    var eff_lines := 1
    return { "words": int(model.get("words", 0)), "effect_lines": eff_lines, "font": smallest,
        "height": _model_height(model, w), "wrapped": _wrap(String(model["rows"][0]["t"]), int(_row_font(model["rows"][0])[1]), w - PAD * 2.0, _row_font(model["rows"][0])[0]).size() }


static func _bonus_text(mods: Dictionary) -> String:
    var bits: Array = []
    for k in mods.keys():
        bits.append(stat_line(String(k), mods[k]))
    return ", ".join(bits)


# --- Layout and drawing -----------------------------------------------------------


static func _header_height(model: Dictionary, width: float) -> float:
    var tw := width - PAD * 2.0 - ICON - 8.0 - 10.0
    var lines := _wrap(String(model.get("title", "")), TITLE_SIZE, tw).size()
    var text_h := float(lines) * (TITLE_SIZE + LINE_GAP) + LABEL_SIZE + LINE_GAP
    if not (model.get("chips", []) as Array).is_empty():
        text_h += float(BADGE_SIZE) + 6.0 + LINE_GAP
    if String(model.get("stack", "")) != "":
        text_h += float(_wrap(String(model["stack"]), LABEL_SIZE, tw).size()) * (LABEL_SIZE + LINE_GAP)
    return maxf(ICON + 8.0, text_h) + 12.0


## How a text row is set (the text rule in art.gd): effect sentences at TEXT_SIZE or more
## in the body font at Art.BODY_SIZE, everything else (names, numbers, prices, small
## labels) in the pixel font at the row's size. Returns [font, px, line step].
static func _row_font(row: Dictionary) -> Array:
    var size := int(row["s"])
    if size >= TEXT_SIZE and Art.FONT_BODY != null and Art.is_prose(String(row["t"])):
        return [Art.FONT_BODY, Art.BODY_SIZE, float(Art.BODY_SIZE) + 5.0]
    return [Art.FONT, size, float(size) + LINE_GAP]


static func _row_height(row: Dictionary, width: float) -> float:
    if row.get("sep", false):
        return float(row.get("gap", 6.0)) + 6.0
    if row.has("badges"):
        return float(row.get("gap", 0.0)) + float(BADGE_SIZE) + 6.0 + LINE_GAP + 2.0
    var rf := _row_font(row)
    var lines := _wrap(String(row["t"]), int(rf[1]), width - PAD * 2.0 - float(row.get("indent", 0.0)), rf[0]).size()
    return float(row.get("gap", 0.0)) + float(lines) * float(rf[2])


static func _model_height(model: Dictionary, width: float) -> float:
    var h := PAD + _header_height(model, width)
    for row in model.get("rows", []):
        h += _row_height(row, width)
    return h + PAD


static func _render(canvas: CanvasItem, rect: Rect2, model: Dictionary, opts: Dictionary) -> void:
    var w := rect.size.x if rect.size.x > 0.0 else DEFAULT_WIDTH
    var h := maxf(rect.size.y, _model_height(model, w))
    var r := Rect2(rect.position, Vector2(w, h))
    var frame: Color = model.get("frame", TEXT)
    draw_frame(canvas, r, frame, bool(opts.get("highlight", false)))
    if bool(model.get("rim", false)):
        # A tier IV weapon: one thin bright rim inside the frame (Arsenal expansion 3.4).
        canvas.draw_rect(r.grow(-5.0), Color(1, 1, 1, 0.85), false, 1.0)

    # Header: the icon at 2x, the title (wrapped), slot and rarity.
    var ib := Rect2(r.position + Vector2(PAD, PAD), Vector2(ICON + 8.0, ICON + 8.0))
    canvas.draw_rect(ib, Color(0, 0, 0, 0.55))
    canvas.draw_rect(ib, Color(frame, 0.22))   # the rarity plate
    canvas.draw_rect(ib, Color(frame, 0.75), false, 2.0)
    if model.has("icon"):
        Art.draw_icon(canvas, model["icon"], Rect2(ib.position + Vector2(4, 4), Vector2(ICON, ICON)), model.get("icon_tint", Color.WHITE))
    if model.has("pips"):
        draw_pips(canvas, Vector2(ib.position.x + 5.0, ib.end.y - 9.0), int(model["pips"]), frame)
    var tx := ib.end.x + 10.0
    var tw := r.end.x - PAD - tx
    var y := r.position.y + PAD
    for line in _wrap(String(model.get("title", "")), TITLE_SIZE, tw):
        _text(canvas, Vector2(tx, y), line, TITLE_SIZE, model.get("title_col", TEXT))
        y += TITLE_SIZE + LINE_GAP
    var sub := String(model.get("sub", ""))
    _text(canvas, Vector2(tx, y), sub, LABEL_SIZE, model.get("sub_col", DIM))
    if bool(model.get("cursed", false)):
        # The red CURSED chip beside the rarity word (cursed loot and deals, 11.1).
        var cx := tx + Art.FONT.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x + 10.0
        var cw := Art.FONT.get_string_size("CURSED", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x + 12.0
        var chip := Rect2(cx, y - 1.0, cw, LABEL_SIZE + 4.0)
        canvas.draw_rect(chip, Color(0.35, 0.03, 0.05, 0.95))
        canvas.draw_rect(chip, CURSED_COL, false, 1.5)
        _text(canvas, Vector2(cx + 6.0, y + 1.0), "CURSED", LABEL_SIZE, Color(1.0, 0.85, 0.85))
    y += LABEL_SIZE + LINE_GAP
    var chips: Array = model.get("chips", [])
    if not chips.is_empty():
        var bx := tx
        for c in chips:
            if c is int:
                bx += draw_element_badge(canvas, Vector2(bx, y + 2.0), c).x + 6.0
            else:
                bx += draw_tag_chip(canvas, Vector2(bx, y + 2.0), String(c)).x + 6.0
        y += float(BADGE_SIZE) + 6.0 + LINE_GAP
    if String(model.get("stack", "")) != "":
        for line in _wrap(String(model["stack"]), LABEL_SIZE, tw):
            _text(canvas, Vector2(tx, y), line, LABEL_SIZE, DIM)
            y += LABEL_SIZE + LINE_GAP
    y = r.position.y + PAD + _header_height(model, w) - 8.0
    canvas.draw_line(Vector2(r.position.x + PAD, y), Vector2(r.end.x - PAD, y), Color(frame, 0.5), 2.0)
    y += 8.0

    for row in model.get("rows", []):
        if row.get("sep", false):
            var sy := y + float(row.get("gap", 6.0)) * 0.5 + 2.0
            canvas.draw_line(Vector2(r.position.x + PAD + 20.0, sy), Vector2(r.end.x - PAD - 20.0, sy), Color(frame, 0.3), 1.0)
            y += _row_height(row, w)
            continue
        if row.has("badges"):
            var bx := r.position.x + PAD
            for k in row["badges"]:
                bx += draw_element_badge(canvas, Vector2(bx, y + float(row.get("gap", 0.0))), k).x + 6.0
            y += _row_height(row, w)
            continue
        y += float(row.get("gap", 0.0))
        var rf := _row_font(row)
        var indent := float(row.get("indent", 0.0))
        for line in _wrap(String(row["t"]), int(rf[1]), w - PAD * 2.0 - indent, rf[0]):
            _text(canvas, Vector2(r.position.x + PAD + indent, y), line, int(rf[1]), row["c"], rf[0])
            y += float(rf[2])


## Text whose top edge is at `top`, with a drop shadow.
static func _text(canvas: CanvasItem, top: Vector2, text: String, size: int, color: Color, with_font: Font = null) -> void:
    var font: Font = with_font if with_font != null else Art.FONT
    var base := top + Vector2(0, font.get_ascent(size))
    canvas.draw_string(font, base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8 * color.a))
    canvas.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func _wrap(text: String, size: int, width: float, with_font: Font = null) -> PackedStringArray:
    var font: Font = with_font if with_font != null else Art.FONT
    var out := PackedStringArray()
    for para in text.split("\n"):
        var line := ""
        for word in para.split(" ", false):
            var test: String = word if line == "" else line + " " + word
            if line != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
                out.append(line)
                line = word
            else:
                line = test
        out.append(line)
    return out


# --- Small helpers ------------------------------------------------------------------


static func _fmt(kind: String, v: float) -> String:
    match kind:
        "int":
            return "%+d" % roundi(v)
        "dec":
            return ("+" if v >= 0.0 else "") + ("%.1f" % v)
        "x":
            return ("+" if v >= 0.0 else "") + ("%.1fx" % v)
    return "%+d%%" % roundi(v * 100.0)


static func _el_name(key: String) -> String:
    if Items.ELEMENTS.has(key):
        return String(Element.NAMES[Items.ELEMENTS[key]])
    return key.capitalize()


static func _act_el(t: Dictionary, active: bool) -> String:
    var e := String(t.get("element", "wet"))
    if e == "last":
        return "your last vent's element" if active else "its element"
    return _el_name(e)


static func _ordinal(n: int) -> String:
    if n % 10 == 2 and n % 100 != 12:
        return "%dnd" % n
    if n % 10 == 3 and n % 100 != 13:
        return "%drd" % n
    if n % 10 == 1 and n % 100 != 11:
        return "%dst" % n
    return "%dth" % n
