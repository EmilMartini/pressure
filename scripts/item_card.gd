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
const ICON := 64.0   # a 32 px Dungeon Crawl tile at 2x
const TITLE_SIZE := 26
const LABEL_SIZE := 22
const TEXT_SIZE := 20
const LINE_GAP := 4.0
const DEFAULT_WIDTH := 340.0

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
    "trinket": "Trinket", "mod": "Gun mod", "active": "Active",
}

## key -> [label, format, plural label]. Formats: pct (fraction), int, dec, x.
const STATS := {
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
    "g_dmg": ["damage on this gun", "pct"], "g_fire_rate": ["fire rate on this gun", "pct"],
    "g_count": ["projectile on this gun", "int", "projectiles on this gun"],
    "g_pierce": ["pierce on this gun", "int"], "g_range": ["range on this gun", "pct"],
    "g_speed": ["shot speed on this gun", "pct"], "g_pressure": ["pressure on this gun", "pct"],
    "homing": ["homing", "dec"], "splash": ["px splash", "int"], "shards": ["shard per shot", "int", "shards per shot"],
    "shot_size": ["shot size", "pct"], "shot_speed": ["shot speed", "pct"],
    "orbitals": ["orbiting familiar", "int", "orbiting familiars"], "gun_slots": ["gun slot", "int", "gun slots"],
}
const FLAGS := {
    "spectral": "Spectral shots: pass through obstacles",
    "boomerang": "Shots return like boomerangs",
    "orbital_element": "Familiars carry your first gun's element",
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
static func rival_for(player, item: Dictionary) -> Dictionary:
    if player == null or not is_instance_valid(player) or item.is_empty():
        return {}
    var slot := String(item.get("slot", ""))
    if slot == "" or slot == "mod":
        return {}
    var key := slot
    if slot == "ring" or slot == "trinket":
        # Both of the pair worn: the one this would replace (the player's swap pick, else
        # the weaker piece; Player.jewel_key).
        key = player.jewel_key(slot)
        if key == "":
            return {}
    var rival: Dictionary = Items.get_item(String(player.equipment.get(key, "")))
    if rival.get("id", "") == item.get("id", ""):
        return {}
    return rival


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
        return "This gun also applies %s" % _el_name(String(value))
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
        return "%s fire rate with %s guns" % [_fmt("pct", v), _el_name(key.substr(10))]
    if key.begins_with("pierce_"):
        return "%s pierce with %s guns" % [_fmt("int", v), _el_name(key.substr(7))]
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


static func _item_model(item: Dictionary, opts: Dictionary) -> Dictionary:
    var rarity := clampi(int(item.get("rarity", 0)), 0, Items.RARITY_COLORS.size() - 1)
    var rc: Color = Items.RARITY_COLORS[rarity]
    var slot := String(item.get("slot", "trinket"))
    var rows: Array = _effect_rows(item)
    var player = opts.get("player", null)
    if player != null and not is_instance_valid(player):
        player = null

    # Set: pieces worn (counting this one if you take it) and the next bonus.
    var sid := Items.set_of(String(item.get("id", "")))
    if sid != "":
        var s: Dictionary = Items.SETS[sid]
        var total: int = (s["items"] as Array).size()
        var scol: Color = SET_COL
        rows.append(_sep())
        var thresholds: Array = s["bonuses"].keys()
        thresholds.sort()
        if player == null:
            rows.append(_row("%s set  (%d pieces)" % [s["name"], total], LABEL_SIZE, scol))
            for th in thresholds:
                rows.append(_row("%d: %s" % [int(th), _bonus_text(s["bonuses"][th])], TEXT_SIZE, DIM, 0.0, 8.0))
        else:
            var have := int(Items.set_counts(player).get(sid, 0))
            var worn: bool = player.equipped_item_ids().has(item.get("id", ""))
            var after := have if worn else have + 1
            var suffix := "" if worn else "  with this"
            rows.append(_row("%s set  %d / %d pieces%s" % [s["name"], after, total, suffix], LABEL_SIZE, scol))
            var next_found := false
            for th in thresholds:
                if after >= int(th):
                    rows.append(_row("%d: %s" % [int(th), _bonus_text(s["bonuses"][th])], TEXT_SIZE, GOOD, 0.0, 8.0))
                elif not next_found:
                    next_found = true
                    rows.append(_row("Next at %d: %s" % [int(th), _bonus_text(s["bonuses"][th])], TEXT_SIZE, DIM, 0.0, 8.0))

    # Comparison with what it would replace.
    var cmp: Dictionary = opts.get("compare", {})
    if not cmp.is_empty() and cmp.get("id", "") != item.get("id", ""):
        rows.append(_sep())
        rows.append(_row("> Replaces %s (%s)" % [cmp.get("name", "?"), Items.rarity_name(cmp)], LABEL_SIZE, Items.rarity_text_color(cmp)))
        rows.append_array(_compare_rows(item, cmp))
        # A full ring / trinket pair: the piece that stays, and the button that swaps them.
        var keeps: Dictionary = opts.get("keeps", {})
        if not keeps.is_empty():
            rows.append(_row("Keeps %s (%s)" % [keeps.get("name", "?"), Items.rarity_name(keeps)], TEXT_SIZE, DIM, 2.0))
            rows.append(_row("%s: replace %s instead" % [String(opts.get("swap_key", "Y")), keeps.get("name", "?")], TEXT_SIZE, PROMPT_COL, 2.0))

    if opts.has("price"):
        rows.append(_sep())
        var price := int(opts["price"])
        var afford: bool = bool(opts.get("afford", true))
        var ptext := "FREE" if price <= 0 else "%d scrap" % price
        if price > 0 and not afford:
            ptext += "  (not enough)"
        rows.append(_row(ptext, LABEL_SIZE, SCRAP_COL if afford or price <= 0 else BAD))
    for n in opts.get("notes", []):
        rows.append(_row(String(n), TEXT_SIZE, DIM, 2.0))

    var badges: Array = []
    if item.has("element"):
        var ek := element_kind(item["element"])
        if ek != Element.Kind.NONE:
            badges.append(ek)
    if not badges.is_empty():
        rows.push_front(_badges(badges))
    var tc: Color = Items.RARITY_TEXT_COLORS[rarity]
    return {
        "icon": Items.icon(item), "icon_tint": Items.ui_icon_tint(item),
        "title": String(item.get("name", "?")), "title_col": tc,
        "sub": "%s %s" % [Items.RARITY_NAMES[rarity], SLOT_TITLES.get(slot, slot.capitalize())],
        "sub_col": tc, "frame": rc, "pips": rarity + 1, "rows": rows,
    }


## "+12% damage (was +8%)" for stats both touch, then what you would lose.
static func _compare_rows(item: Dictionary, old: Dictionary) -> Array:
    var rows: Array = []
    var nm: Dictionary = item.get("mods", {})
    var om: Dictionary = old.get("mods", {})
    for k in nm.keys():
        var key := String(k)
        if not om.has(k) or key == "extra_element" or FLAGS.has(key):
            continue
        var nv := float(nm[k])
        var ov := float(om[k])
        var col := TEXT
        if nv > ov + 0.0001:
            col = GOOD
        elif nv < ov - 0.0001:
            col = BAD
        rows.append(_row("%s (was %s)" % [stat_line(key, nm[k]), stat_value(key, om[k])], TEXT_SIZE, col))
    for k in om.keys():
        var key := String(k)
        if nm.has(k):
            continue
        var lost_bad := true
        if key != "extra_element" and not FLAGS.has(key):
            lost_bad = float(om[k]) > 0.0
        rows.append(_row("Lose %s" % stat_line(key, om[k]), TEXT_SIZE, BAD if lost_bad else GOOD))
    var ocm: Dictionary = old.get("cond_mods", {})
    var ncm: Dictionary = item.get("cond_mods", {})
    for cond in ocm.keys():
        for k in ocm[cond].keys():
            if ncm.has(cond) and ncm[cond].has(k):
                continue
            rows.append(_row("Lose %s: %s" % [CONDS.get(String(cond), String(cond)), stat_line(String(k), ocm[cond][k])], TEXT_SIZE, BAD))
    var new_trig: Array = []
    for t in item.get("triggers", []):
        new_trig.append(trigger_line(t))
    for t in old.get("triggers", []):
        var line := trigger_line(t)
        if not new_trig.has(line):
            rows.append(_row("Lose %s" % line, TEXT_SIZE, BAD))
    if old.has("active") and old.get("id", "") != item.get("id", ""):
        rows.append(_row("Lose the %s active" % old.get("name", "?"), TEXT_SIZE, BAD))
    return rows


## "Heats you 3 per shot"; continuous guns (beams, sprays) say it per second.
static func _pressure_text(verb: String, data: GunData, rate: float) -> String:
    var v := absf(data.pressure_per_shot)
    if data.mechanic == "beam" or data.mechanic == "cone":
        return "%s you %.0f per second" % [verb, v * rate]
    return "%s you %.0f per shot" % [verb, v]


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
        rate = gun.top_fire_rate()   # repeaters show their full speed
    var dps := data.dps_at(dmg, rate)
    var rows: Array = []
    var badges: Array = [data.element]
    for extra in [data.alt_element, data.extra_element]:
        if extra != Element.Kind.NONE and not badges.has(extra):
            badges.append(extra)
    rows.append(_badges(badges))
    if data.mechanic == "charge":
        rows.append(_row("%.0f damage every %.1f s" % [dmg, data.charge_time + 1.0 / maxf(0.05, rate)], LABEL_SIZE, TEXT))
    else:
        rows.append(_row("%.0f damage x %.1f / s" % [dmg, rate], LABEL_SIZE, TEXT))
    rows.append(_row("DPS %.0f" % dps, LABEL_SIZE, Color.WHITE))
    # How it fires, in plain words (GunData.how), then counts it does not already say.
    if data.how() != "":
        rows.append(_row(data.how(), TEXT_SIZE, TEXT))
    if data.projectile_count > 1 and data.mechanic == "shot" and not data.archetype in ["shotgun", "homing", "helix"]:
        rows.append(_row("%d projectiles per shot" % data.projectile_count, TEXT_SIZE, TEXT))
    if data.pierce > 0 and data.pierce < 10 and data.mechanic != "beam":
        rows.append(_row("Pierce %d" % data.pierce, TEXT_SIZE, TEXT))
    if data.alt_element != Element.Kind.NONE:
        rows.append(_row("Every other shot: %s" % Element.NAMES[data.alt_element], TEXT_SIZE, TEXT))
    if data.extra_element != Element.Kind.NONE:
        rows.append(_row("Every hit also applies %s" % Element.NAMES[data.extra_element], TEXT_SIZE, TEXT))
    if data.pressure_per_shot > 0.0:
        rows.append(_row(_pressure_text("Heats", data, rate), TEXT_SIZE, TEXT))
    elif data.pressure_per_shot < 0.0:
        rows.append(_row(_pressure_text("Chills", data, rate), TEXT_SIZE, TEXT))
    var weight_text := "Weight %d" % data.weight
    var weight_col := TEXT
    if player != null and gun == null:
        var free: int = int(player.weight_capacity) - int(player.total_weight())
        weight_text += "  (%d free)" % free
        if free < data.weight:
            weight_col = BAD
    rows.append(_row(weight_text, TEXT_SIZE, weight_col))

    # Mods fitted (a carried gun) or slots it would have.
    if gun != null or not mods.is_empty():
        rows.append(_sep())
        rows.append(_row("Mod slots %d / %d" % [mods.size(), tier], LABEL_SIZE, DIM))
        for mid in mods:
            var m: Dictionary = Items.get_item(String(mid))
            if m.is_empty():
                continue
            rows.append(_row("%s (%s)" % [m["name"], Items.rarity_name(m)], TEXT_SIZE, Items.rarity_text_color(m), 0.0, 8.0))
            if not bool(opts.get("compact", false)):
                for line in describe_mods(m):
                    rows.append(_row(line, TEXT_SIZE, DIM, 0.0, 20.0))

    # Copies: duplicates are a build, two at one tier combine into the next.
    if player != null:
        var copies: Array = []
        for g in player.guns:
            if g != gun and g.data.id == data.id:
                copies.append(g)
        if not copies.is_empty():
            rows.append(_sep())
            var twin = null
            for g in copies:
                if int(g.tier) == tier:
                    twin = g
                    break
            if twin != null and tier < Gun.MAX_TIER:
                var lead := "Twin carried" if gun != null else "You carry one"
                rows.append(_row("%s: combines to tier %s" % [lead, ROMAN[tier]], LABEL_SIZE, GOOD))
            else:
                var tiers: Array = []
                for g in copies:
                    tiers.append(ROMAN[clampi(int(g.tier) - 1, 0, ROMAN.size() - 1)])
                rows.append(_row("Copies carried: tier %s" % ", ".join(tiers), TEXT_SIZE, DIM))

    if opts.has("price"):
        rows.append(_sep())
        var price := int(opts["price"])
        var afford: bool = bool(opts.get("afford", true))
        var ptext := "FREE" if price <= 0 else "%d scrap" % price
        if price > 0 and not afford:
            ptext += "  (not enough)"
        rows.append(_row(ptext, LABEL_SIZE, SCRAP_COL if afford or price <= 0 else BAD))
    for n in opts.get("notes", []):
        rows.append(_row(String(n), TEXT_SIZE, DIM, 2.0))

    var arche := data.archetype.capitalize() if data.archetype != "" else "Gun"
    var title := data.display_name
    if tier > 1:
        title += " " + ROMAN[clampi(tier - 1, 0, ROMAN.size() - 1)]
    # A tier wears the rarity palette (Items.tier_rarity); the element is the badge row.
    var tr := Items.tier_rarity(tier)
    return {
        "icon": Art.gun_icon(data.id), "icon_tint": Color.WHITE, "title": title, "title_col": Items.RARITY_TEXT_COLORS[tr],
        "sub": "%s %s  tier %s" % [Items.RARITY_NAMES[tr], arche, ROMAN[clampi(tier - 1, 0, ROMAN.size() - 1)]],
        "sub_col": Items.RARITY_TEXT_COLORS[tr], "frame": Items.RARITY_COLORS[tr], "pips": clampi(tier, 1, 5), "rows": rows,
    }


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
    return maxf(ICON + 8.0, text_h) + 12.0


static func _row_height(row: Dictionary, width: float) -> float:
    if row.get("sep", false):
        return float(row.get("gap", 6.0)) + 6.0
    if row.has("badges"):
        return float(row.get("gap", 0.0)) + float(BADGE_SIZE) + 6.0 + LINE_GAP + 2.0
    var size := int(row["s"])
    var lines := _wrap(String(row["t"]), size, width - PAD * 2.0 - float(row.get("indent", 0.0))).size()
    return float(row.get("gap", 0.0)) + float(lines) * (size + LINE_GAP)


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

    # Header: the icon at 2x, the title (wrapped), slot and rarity.
    var ib := Rect2(r.position + Vector2(PAD, PAD), Vector2(ICON + 8.0, ICON + 8.0))
    canvas.draw_rect(ib, Color(0, 0, 0, 0.55))
    canvas.draw_rect(ib, Color(frame, 0.6), false, 2.0)
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
    _text(canvas, Vector2(tx, y), String(model.get("sub", "")), LABEL_SIZE, model.get("sub_col", DIM))
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
        var size := int(row["s"])
        var indent := float(row.get("indent", 0.0))
        for line in _wrap(String(row["t"]), size, w - PAD * 2.0 - indent):
            _text(canvas, Vector2(r.position.x + PAD + indent, y), line, size, row["c"])
            y += size + LINE_GAP


## Text whose top edge is at `top`, with a drop shadow.
static func _text(canvas: CanvasItem, top: Vector2, text: String, size: int, color: Color) -> void:
    var font: Font = Art.FONT
    var base := top + Vector2(0, font.get_ascent(size))
    canvas.draw_string(font, base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8 * color.a))
    canvas.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func _wrap(text: String, size: int, width: float) -> PackedStringArray:
    var font: Font = Art.FONT
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
