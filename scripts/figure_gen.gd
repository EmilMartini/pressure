class_name FigureGen
extends RefCounted
## Procedural paper-doll figures: the player's class and gear blend into one 16 x 16
## one-bit-style figure, so every pickup nudges the look instead of swapping it.
##
##   profile(player)  theme -> weight, from the class, worn items, carried guns, full sets
##   parts(profile)   one variant per layer (build, head, torso, cape, arms, accents)
##   palette(...)     [main, dark, light, accent]
##   generate(player) { frames: [idle, step] ImageTextures, id, name, color, aura, ... }
##   rim(frame)       a white ring one pixel outside a frame's outline (Player tints it)
##
## Parts are small string grids: "." empty, "#" main, "d" dark, "l" light, "a" accent,
## "o" outline black, "b" bone. Layers go cape, legs, torso, arms, head, head overlay,
## accents, then a 1 px dark outline around the silhouette (like the Kenney figures).
## Results are cached by the profile rounded to 0.5 steps plus the player colour and the
## worn items.
##
## Worn gear (WornGear): every head, chest, hands and feet item is drawn as its own piece
## (a wizard hat, a hood, plate, a cloak, gauntlets, boots...) in its icon's colours, on
## top of the blended body: a worn head replaces the theme head, a chest piece goes over
## the theme torso (open vests and straps let it show), hands and feet over the arms and
## legs. Pieces sit on their own layer, so theme accents never paint over them; accents
## that would fight a piece (flame tips on a hat, a gem on plate) are left out.

const CLASS_WEIGHT := 3.0
const GUN_WEIGHT := 0.5
const SET_WEIGHT := 2.5
const RARITY_WEIGHTS := [1.0, 1.5, 2.0, 3.0, 4.0]
const MOD_SLOT_MULT := 0.5      # gun mods count half
const MIN_PART := 1.0           # a theme below this never picks parts or accents
const OVERLAY_RATIO := 0.75     # themes 1 and 2 within 25%: theme 2's head is overlaid
const NAME_RATIO := 0.35        # theme 2 shows up in the name from 35% of theme 1
const BUILD_SHARE := 0.3        # share of the profile that makes the build broad or slim
const PLAYER_MIX := 0.3
const OUTLINE := Color(0.06, 0.05, 0.07)
const BONE := Color(0.93, 0.89, 0.80)

enum { ANY, EMPTY, OVER }
const L_CAPE := 1
const L_LEGS := 2
const L_TORSO := 3
const L_ARMS := 4
const L_HEAD := 5
const L_FX := 6
const L_WORN := 7                # worn gear pieces (WornGear)
const L_OUT := 9

const ORDER := ["fire", "wet", "shock", "ice", "oil", "poison", "acid", "blood", "void", "holy",
    "gale", "stone", "plate", "scout", "arcane", "gunslinger", "merchant", "vagrant"]
const GEAR := ["plate", "scout", "arcane", "gunslinger", "merchant", "vagrant"]
const ELEMENT_KINDS := {
    "wet": Element.Kind.WET, "shock": Element.Kind.SHOCK, "fire": Element.Kind.FIRE,
    "ice": Element.Kind.ICE, "oil": Element.Kind.OIL, "poison": Element.Kind.POISON,
    "acid": Element.Kind.ACID, "blood": Element.Kind.BLOOD, "void": Element.Kind.VOID,
    "holy": Element.Kind.HOLY, "gale": Element.Kind.GALE, "stone": Element.Kind.STONE,
}
const STATE_THEMES := {
    "burning": "fire", "shocked": "shock", "frozen": "ice", "chilled": "ice", "cold": "ice",
    "oiled": "oil", "poisoned": "poison", "wet": "wet", "corroded": "acid", "bleeding": "blood",
}

## Per theme: noun / adjective for the blend name, colour (element themes take theirs from
## Element.COLORS), accent, and the variant it picks for each layer plus its accent effect.
const THEMES := {
    "fire": { "noun": "Pyromancer", "adj": "Ember", "accent": Color(1.0, 0.85, 0.3),
        "head": "hood", "torso": "robe", "cape": "tattered", "arms": "bracers", "fx": "flame_tips" },
    "wet": { "noun": "Tidecaller", "adj": "Tide", "accent": Color(0.8, 0.95, 1.0),
        "head": "cowl", "torso": "robe", "cape": "long", "arms": "bare", "fx": "wave_hem" },
    "shock": { "noun": "Stormcaller", "adj": "Storm", "accent": Color(0.55, 0.85, 1.0),
        "head": "spiky", "torso": "coat", "cape": "short", "arms": "gauntlets", "fx": "bolt" },
    "ice": { "noun": "Frostbinder", "adj": "Frost", "accent": Color(0.45, 0.75, 1.0),
        "head": "pointed", "torso": "robe", "cape": "long", "arms": "sleeves", "fx": "frost_spikes" },
    "oil": { "noun": "Tarsmith", "adj": "Tar", "accent": Color(0.15, 0.12, 0.14),
        "head": "bare", "torso": "apron", "cape": "none", "arms": "gauntlets", "fx": "stains" },
    "poison": { "noun": "Plaguewright", "adj": "Venom", "accent": Color(0.75, 1.0, 0.3),
        "head": "mask", "torso": "coat", "cape": "short", "arms": "bandages", "fx": "drips" },
    "acid": { "noun": "Alchemist", "adj": "Caustic", "accent": Color(0.45, 0.95, 1.0),
        "head": "goggles", "torso": "apron", "cape": "none", "arms": "gauntlets", "fx": "flask_belt" },
    "blood": { "noun": "Bloodletter", "adj": "Crimson", "accent": Color(0.6, 0.02, 0.1),
        "head": "horns", "torso": "leather", "cape": "tattered", "arms": "bandages", "fx": "blood_stains" },
    "void": { "noun": "Voidwalker", "adj": "Abyssal", "accent": Color(0.95, 0.55, 1.0),
        "head": "hood", "torso": "robe", "cape": "tattered", "arms": "sleeves", "fx": "void_eyes" },
    "holy": { "noun": "Templar", "adj": "Radiant", "accent": Color(1.0, 0.8, 0.25),
        "head": "greathelm", "torso": "plate", "cape": "long", "arms": "gauntlets", "fx": "halo" },
    "gale": { "noun": "Windrunner", "adj": "Zephyr", "accent": Color(0.3, 0.75, 0.65),
        "head": "swept", "torso": "leather", "cape": "none", "arms": "bracers", "fx": "scarf" },
    "stone": { "noun": "Stonewarden", "adj": "Granite", "accent": Color(0.95, 0.7, 0.3),
        "head": "golem", "torso": "plate", "cape": "none", "arms": "gauntlets", "fx": "stone_shoulders" },
    "plate": { "noun": "Knight", "adj": "Plated", "color": Color(0.72, 0.76, 0.86), "accent": Color(0.9, 0.3, 0.3),
        "head": "helmet", "torso": "plate", "cape": "short", "arms": "gauntlets", "fx": "pauldrons" },
    "scout": { "noun": "Scout", "adj": "Swift", "color": Color(0.42, 0.68, 0.38), "accent": Color(0.8, 0.6, 0.3),
        "head": "band", "torso": "leather", "cape": "short", "arms": "bracers", "fx": "boots" },
    "arcane": { "noun": "Arcanist", "adj": "Arcane", "color": Color(0.52, 0.42, 0.95), "accent": Color(0.4, 0.95, 1.0),
        "head": "pointed", "torso": "robe", "cape": "long", "arms": "sleeves", "fx": "gem" },
    "gunslinger": { "noun": "Gunslinger", "adj": "Gunslinging", "color": Color(0.75, 0.52, 0.32), "accent": Color(0.95, 0.8, 0.35),
        "head": "wide_hat", "torso": "coat", "cape": "none", "arms": "bare", "fx": "bandolier" },
    "merchant": { "noun": "Merchant", "adj": "Gilded", "color": Color(0.3, 0.6, 0.5), "accent": Color(1.0, 0.85, 0.3),
        "head": "crown", "torso": "coat", "cape": "short", "arms": "bare", "fx": "purse" },
    "vagrant": { "noun": "Vagrant", "adj": "Ragged", "color": Color(0.7, 0.64, 0.58), "accent": Color(0.85, 0.7, 0.5),
        "head": "bare", "torso": "leather", "cape": "none", "arms": "bandages", "fx": "" },
}

## Builds: torso grid trim (columns removed / added at the centre), torso grid x, the left
## and right arm x, and the leg columns.
const BUILDS := {
    "slim": { "trim": -2, "tx": 5, "ax": 3, "ar": 11, "legs": [[6], [9]] },
    "normal": { "trim": 0, "tx": 4, "ax": 2, "ar": 12, "legs": [[5, 6], [9, 10]] },
    "broad": { "trim": 2, "tx": 3, "ax": 1, "ar": 13, "legs": [[4, 5], [10, 11]] },
}
const BROAD_THEMES := ["plate", "stone"]
const SLIM_THEMES := ["scout", "gale"]

## Heads: 8 wide at x 4, rows 0..6.
const HEADS := {
    "bare": ["........", "..dddd..", ".dddddd.", ".dlllld.", ".lollol.", ".llllll.", "..llll.."],
    "band": ["........", "..dddd..", ".dddddd.", ".aaaaaa.", ".lollol.", ".llllll.", "..llll.."],
    "spiky": [".d.dd.d.", ".dddddd.", ".dddddd.", ".dlllld.", ".lollol.", ".llllll.", "..llll.."],
    "swept": ["........", "..ddddd.", ".ddddddd", ".dlllldd", ".lollol.", ".llllll.", "..llll.."],
    "hood": ["...##...", "..####..", ".######.", ".#dddd#.", ".#adda#.", ".#dddd#.", "..####.."],
    "cowl": ["...##...", "..####..", ".######.", "#dlllld#", "#lollol#", "#llllll#", ".#llll#."],
    "pointed": ["......#.", ".....##.", "....###.", "..#####.", "dddddddd", ".lollol.", "..llll.."],
    "helmet": ["........", "..####..", ".##ll##.", ".######.", ".#oooo#.", ".######.", "..#dd#.."],
    "crown": [".a.aa.a.", ".aaaaaa.", ".dddddd.", ".dlllld.", ".lollol.", ".llllll.", "..llll.."],
    "horns": ["b......b", "bb####bb", ".######.", ".######.", ".#a##a#.", ".#dddd#.", "..####.."],
    "mask": ["..####..", ".######.", "dddddddd", ".bbbbbb.", ".bobbob.", ".bbbbbbb", "..bbbbb."],
    "goggles": ["........", "..dddd..", ".dddddd.", "daaddaad", ".aallaa.", ".llllll.", "..llll.."],
    "wide_hat": ["........", "..####..", "..aaaa..", "dddddddd", ".lollol.", ".llllll.", "..llll.."],
    "greathelm": ["........", "..####..", ".##ll##.", ".oooooo.", ".##oo##.", ".######.", "..#dd#.."],
    "golem": ["........", "..#l##..", ".##l###.", ".######.", ".#a##a#.", ".##dd##.", "..####.."],
}

## A second theme's head as a small detail on the first theme's head (x 4, from row y).
const HEAD_OVERLAYS := {
    "band": { "y": 2, "mode": OVER, "grid": [".aaaaaa."] },
    "spiky": { "y": 0, "mode": EMPTY, "grid": [".d.dd.d."] },
    "swept": { "y": 1, "mode": EMPTY, "grid": [".......d", ".......d"] },
    "hood": { "y": 2, "mode": EMPTY, "grid": ["#......#", "#......#", "#......#", "#......#"] },
    "cowl": { "y": 2, "mode": EMPTY, "grid": ["#......#", "#......#", "#......#", "#......#"] },
    "pointed": { "y": 0, "mode": EMPTY, "grid": ["......#.", ".....##."] },
    "helmet": { "y": 1, "mode": ANY, "grid": ["..llll.."] },
    "crown": { "y": 0, "mode": ANY, "grid": [".a.aa.a."] },
    "horns": { "y": 0, "mode": EMPTY, "grid": ["b......b", "bb....bb"] },
    "mask": { "y": 4, "mode": ANY, "grid": [".......b", ".......b"] },
    "goggles": { "y": 2, "mode": ANY, "grid": ["daaddaad"] },
    "wide_hat": { "y": 1, "mode": ANY, "grid": ["dddddddd"] },
    "greathelm": { "y": 0, "mode": EMPTY, "grid": [".aaaaaa.", "a......a"] },
    "golem": { "y": 0, "mode": EMPTY, "grid": ["..l..l..", ".ll..ll."] },
}

## Torsos: 8 wide (normal build) at the build's tx, rows 7..13. Slim drops the two centre
## columns, broad doubles them.
const TORSOS := {
    "robe": [".######.", ".#l##d#.", ".#l##d#.", ".aaaaaa.", ".#l##d#.", "##l##dd#", "########"],
    "plate": [".llllll.", ".l####d.", ".#l##d#.", ".#l##d#.", ".dddddd.", ".#d..d#.", "........"],
    "leather": [".######.", ".#d####.", ".##d###.", ".###d##.", ".dddddd.", ".##..##.", "........"],
    "apron": [".######.", ".#llll#.", ".#lddl#.", ".alllla.", ".#llll#.", ".#llll#.", "..llll.."],
    "coat": [".######.", ".##ll##.", ".#dlld#.", ".##aa##.", ".##dd##.", "##d..d##", "#......#"],
}

## Left arm, 2 wide, rows 7..12 (column 0 is the outer side); the right arm is mirrored.
const ARMS := {
    "bare": ["..", "##", "##", "ll", "ll", "ll"],
    "sleeves": ["..", "##", "##", "##", "dd", "ll"],
    "gauntlets": ["..", "##", "##", "dl", "ll", "ll"],
    "bandages": ["..", "##", "ll", "dd", "ll", "ll"],
    "bracers": ["..", "##", "##", "aa", "aa", "ll"],
}

## Capes behind the body: 14 wide at x 1, rows 7..14. The step frame shifts rows 12+ by 1.
const CAPES := {
    "none": [],
    "short": ["..dddddddddd..", "..dddddddddd..", "..dddddddddd..", "..dddddddddd..", "...dddddddd..."],
    "long": ["..dddddddddd..", "..dddddddddd..", "..dddddddddd..", "..dddddddddd..",
        ".dddddddddddd.", ".dddddddddddd.", ".dddddddddddd.", "##############"],
    "tattered": ["..dddddddddd..", "..dddddddddd..", "..dddddddddd..", "..dddddddddd..",
        ".dddddddddddd.", ".dddddddddddd.", ".dddddddddddd.", "dd..dd..dd..dd"],
}

## Theme accents left out under a worn piece: on the head, on a covering chest piece, and
## on any chest piece (they would draw over its sides).
const HEAD_FX := ["flame_tips"]
const COVERED_TORSO_FX := ["bolt", "stains", "gem", "blood_stains", "wave_hem"]
const CHEST_FX := ["flask_belt", "scarf", "bandolier"]

const DEBUG_BLENDS := [["fire", "acid"], ["ice", "plate"], ["void", "holy"], ["shock", "scout"],
    ["blood", "fire"], ["stone", "gale"], ["poison", "merchant"], ["holy", "plate"]]

static var _cache: Dictionary = {}   # profile key -> figure
static var _rims: Dictionary = {}    # frame texture instance id -> rim texture (see rim)


# --- Profile -------------------------------------------------------------------


## Theme weights for `player`: 3 for the class theme, each worn item by rarity
## (1 / 1.5 / 2 / 3 / 4, gun mods half), 0.5 per carried gun to its element, 2.5 per
## completed set.
static func profile(player: Player) -> Dictionary:
    var out: Dictionary = {}
    if player == null or not is_instance_valid(player):
        out["vagrant"] = CLASS_WEIGHT
        return out
    var cid := String(player.get_meta("class_id", "vagrant"))
    var cdef: Dictionary = Classes.get_def(cid)
    var cel := int(cdef.get("element", Element.Kind.NONE))
    var cth := element_theme(cel)
    _add(out, cth if cth != "" else "vagrant", CLASS_WEIGHT)
    for id in player.equipped_item_ids():
        var item_id := String(id)
        var it: Dictionary = Items.get_item(item_id)
        if it.is_empty():
            continue
        var pts := item_themes(item_id, it)
        for th in pts.keys():
            _add(out, String(th), float(pts[th]))
    for g in player.guns:
        if g == null or g.data == null:
            continue
        var gth := element_theme(int(g.data.element))
        if gth != "":
            _add(out, gth, GUN_WEIGHT)
    var counts: Dictionary = Items.set_counts(player)
    for sid in counts.keys():
        var set_items: Array = Items.SETS[sid]["items"]
        if int(counts[sid]) >= mini(4, set_items.size()):
            var sth := set_theme(String(sid))
            if sth != "":
                _add(out, sth, SET_WEIGHT)
    return out


## One item's theme weights, summing to its rarity weight.
static func item_themes(id: String, it: Dictionary) -> Dictionary:
    var raw: Dictionary = {}
    var el_field := String(it.get("element", ""))
    if ELEMENT_KINDS.has(el_field):
        _add(raw, el_field, 2.0)
    var mods: Dictionary = it.get("mods", {})
    for k in mods.keys():
        var v = mods[k]
        if v is String:
            if ELEMENT_KINDS.has(v):
                _add(raw, String(v), 2.0)
            continue
        if float(v) <= 0.0:
            continue
        var mth := key_theme(String(k))
        if mth != "":
            _add(raw, mth, 1.0)
    var cm: Dictionary = it.get("cond_mods", {})
    for cond in cm.keys():
        var cmods: Dictionary = cm[cond]
        for ck in cmods.keys():
            var cth := key_theme(String(ck))
            if cth != "":
                _add(raw, cth, 0.5)
    for t in it.get("triggers", []):
        var trig: Dictionary = t
        var tel := String(trig.get("element", ""))
        if ELEMENT_KINDS.has(tel):
            _add(raw, tel, 1.0)
        if String(trig.get("do", "")) == "chain":
            _add(raw, "shock", 1.0)
    var sth := set_theme(Items.set_of(id))
    if sth != "":
        _add(raw, sth, 2.0)
    var total := 0.0
    for th in raw.keys():
        total += float(raw[th])
    var out: Dictionary = {}
    if total <= 0.0:
        return out
    var weight := float(RARITY_WEIGHTS[clampi(int(it.get("rarity", 0)), 0, 4)])
    if String(it.get("slot", "")) == "mod":
        weight *= MOD_SLOT_MULT
    for rth in raw.keys():
        out[rth] = float(raw[rth]) / total * weight
    return out


## The theme a stat key points at (Items.THEME_KEYS, element suffixes, vs_<state>), or "".
static func key_theme(k: String) -> String:
    if Items.THEME_KEYS.has(k):
        return String(Items.THEME_KEYS[k])
    if k.begins_with("vs_"):
        return String(STATE_THEMES.get(k.substr(3), ""))
    for e in ELEMENT_KINDS.keys():
        if k.ends_with("_" + String(e)):
            return String(e)
    if k.begins_with("potency"):
        return "arcane"
    if k.begins_with("g_"):
        return "arcane" if k == "g_pressure" else "gunslinger"
    return ""


static func element_theme(kind: int) -> String:
    for e in ELEMENT_KINDS.keys():
        if int(ELEMENT_KINDS[e]) == kind:
            return String(e)
    return ""


static func set_theme(sid: String) -> String:
    if sid == "":
        return ""
    if ELEMENT_KINDS.has(sid):
        return sid
    return String(Items.SET_THEMES.get(sid, ""))


static func theme_color(th: String) -> Color:
    if ELEMENT_KINDS.has(th):
        return Element.COLORS[ELEMENT_KINDS[th]]
    var def: Dictionary = THEMES.get(th, THEMES["vagrant"])
    return def.get("color", Color.WHITE)


static func theme_accent(th: String) -> Color:
    var def: Dictionary = THEMES.get(th, THEMES["vagrant"])
    return def["accent"]


static func _add(d: Dictionary, key: String, amount: float) -> void:
    d[key] = float(d.get(key, 0.0)) + amount


## Known themes with weight > 0, heaviest first (ties in ORDER).
static func _sorted(prof: Dictionary) -> Array:
    var keys: Array = []
    for k in prof.keys():
        if THEMES.has(k) and float(prof[k]) > 0.0:
            keys.append(String(k))
    keys.sort_custom(func(a, b) -> bool:
        var wa := float(prof[a])
        var wb := float(prof[b])
        if wa != wb:
            return wa > wb
        return ORDER.find(a) < ORDER.find(b))
    if keys.is_empty():
        keys.append("vagrant")
    return keys


static func _weight(prof: Dictionary, th: String) -> float:
    return float(prof.get(th, CLASS_WEIGHT if prof.is_empty() else 0.0))


# --- Parts ---------------------------------------------------------------------


## One variant per layer. Theme 1 picks head and torso; theme 2 (from MIN_PART) picks
## cape and arms and adds its accent; theme 3 adds an accent too; when themes 1 and 2 are
## within 25%, theme 2's head is overlaid on theme 1's. The build follows the share of
## plate/stone (broad) or scout/gale (slim) in the whole profile.
static func parts(prof: Dictionary) -> Dictionary:
    var themes := _sorted(prof)
    var weights: Array = []
    for th in themes:
        weights.append(_weight(prof, th))
    var t1: String = themes[0]
    var w1: float = weights[0]
    var t2 := ""
    var w2 := 0.0
    if themes.size() > 1 and float(weights[1]) >= MIN_PART:
        t2 = themes[1]
        w2 = weights[1]
    var d1: Dictionary = THEMES[t1]
    var side_th := t2 if t2 != "" else t1
    var side: Dictionary = THEMES[side_th]
    var out := {
        "themes": themes.slice(0, 3), "weights": weights.slice(0, 3),
        "build": _build(prof), "head": d1["head"], "torso": d1["torso"],
        "cape": side["cape"], "arms": side["arms"], "side_theme": side_th,
        "overlay": "", "overlay_theme": "", "accents": [], "name": _blend_name(t1, w1, t2, w2),
    }
    if t2 != "" and w2 >= OVERLAY_RATIO * w1:
        var h2: String = THEMES[t2]["head"]
        if h2 != String(d1["head"]) and HEAD_OVERLAYS.has(h2):
            out["overlay"] = h2
            out["overlay_theme"] = t2
    var accents: Array = []
    var seen: Array = []
    for i in mini(3, themes.size()):
        var ath: String = themes[i]
        if i > 0 and float(weights[i]) < MIN_PART:
            continue
        var fx: String = THEMES[ath]["fx"]
        if fx == "" or seen.has(fx):
            continue
        seen.append(fx)
        accents.append({ "fx": fx, "theme": ath })
    out["accents"] = accents
    return out


static func _build(prof: Dictionary) -> String:
    var total := 0.0
    var broad := 0.0
    var slim := 0.0
    for k in prof.keys():
        var w := float(prof[k])
        total += w
        if BROAD_THEMES.has(k):
            broad += w
        elif SLIM_THEMES.has(k):
            slim += w
    if total <= 0.0:
        return "normal"
    if broad / total >= BUILD_SHARE and broad >= slim:
        return "broad"
    if slim / total >= BUILD_SHARE:
        return "slim"
    return "normal"


## "Pyromancer", "Pyromancer-Alchemist" (two elements), "Plated Pyromancer" or
## "Ember Knight" (a gear theme involved).
static func _blend_name(t1: String, w1: float, t2: String, w2: float) -> String:
    var n1: String = THEMES[t1]["noun"]
    if t2 == "" or w2 < NAME_RATIO * w1:
        return n1
    if GEAR.has(t1) or GEAR.has(t2):
        return "%s %s" % [THEMES[t2]["adj"], n1]
    return "%s-%s" % [n1, THEMES[t2]["noun"]]


# --- Palette -------------------------------------------------------------------


## [main, dark, light, accent]: main is the weighted blend of the top three theme colours
## with 30% of the player colour mixed in (skipped when player_color.a is 0), dark is
## main darkened 45%, light main lightened 35%, accent the top theme's accent.
static func palette(prof: Dictionary, player_color: Color) -> Array[Color]:
    var themes := _sorted(prof)
    var sum := 0.0
    var r := 0.0
    var g := 0.0
    var b := 0.0
    for i in mini(3, themes.size()):
        var th: String = themes[i]
        var w := maxf(0.01, _weight(prof, th))
        var c := theme_color(th)
        r += c.r * w
        g += c.g * w
        b += c.b * w
        sum += w
    var main := Color(r / sum, g / sum, b / sum)
    if player_color.a > 0.0:
        main = main.lerp(Color(player_color, 1.0), PLAYER_MIX)
    var out: Array[Color] = [main, main.darkened(0.45), main.lightened(0.35), theme_accent(themes[0])]
    return out


static func _pal(pal: Array[Color], accent: Color) -> Dictionary:
    return { "#": pal[0], "d": pal[1], "l": pal[2], "a": accent, "o": OUTLINE, "b": BONE }


# --- Generation ----------------------------------------------------------------


## The figure for `player`: { frames: [idle, step] (ImageTexture), images, id, name,
## color (main), aura (top theme colour), parts, profile }. Cached; only regenerates when
## the profile changes by a 0.5 step, the player colour changes or a worn piece changes.
static func generate(player: Player) -> Dictionary:
    var pc := Color(0, 0, 0, 0)
    if player != null and is_instance_valid(player):
        pc = player.color
    return generate_from(profile(player), pc, WornGear.worn_of(player))


## `worn`: { slot: item id } for the head, chest, hands and feet pieces drawn on the figure
## (WornGear.worn_of); empty draws the themes alone.
static func generate_from(prof: Dictionary, player_color: Color, worn: Dictionary = {}) -> Dictionary:
    var rounded: Dictionary = {}
    for k in prof.keys():
        var w := snappedf(float(prof[k]), 0.5)
        if w > 0.0 and THEMES.has(k):
            rounded[String(k)] = w
    if rounded.is_empty():
        rounded["vagrant"] = CLASS_WEIGHT
    var key := _key(rounded, player_color, worn)
    if _cache.has(key):
        return _cache[key]
    var p := parts(rounded)
    p["worn"] = WornGear.resolve(worn)
    var pal := palette(rounded, player_color)
    var idle := _render(p, pal, false)
    var step := _render(p, pal, true)
    var top: String = p["themes"][0]
    var frames: Array = [ImageTexture.create_from_image(idle), ImageTexture.create_from_image(step)]
    if _rims.size() > 256:
        _rims.clear()
    _rims[(frames[0] as Texture2D).get_instance_id()] = ImageTexture.create_from_image(rim_image(idle))
    _rims[(frames[1] as Texture2D).get_instance_id()] = ImageTexture.create_from_image(rim_image(step))
    var fig := {
        "frames": frames,
        "images": [idle, step],
        "id": "%s_%d" % [top, absi(key)],
        "name": p["name"],
        "color": pal[0],
        "aura": theme_color(top),
        "parts": p,
        "profile": rounded,
    }
    if _cache.size() > 128:
        _cache.clear()
    _cache[key] = fig
    return fig


## The rim for a figure frame: a white 18 x 18 ring one pixel outside the figure's dark
## outline (8-neighbours, so corners stay closed), drawn under the figure in the player's
## colour (Player._draw) so the figure separates from any floor, wall or crowd. Built with
## the frames; a frame from elsewhere gets one built from its image once.
static func rim(frame: Texture2D) -> Texture2D:
    if frame == null:
        return null
    var key := frame.get_instance_id()
    if _rims.has(key):
        return _rims[key]
    var img := frame.get_image()
    if img == null or img.is_empty():
        return null
    if _rims.size() > 256:
        _rims.clear()
    var t := ImageTexture.create_from_image(rim_image(img))
    _rims[key] = t
    return t


static func rim_image(src: Image) -> Image:
    var w := src.get_width()
    var h := src.get_height()
    var out := Image.create_empty(w + 2, h + 2, false, Image.FORMAT_RGBA8)
    out.fill(Color(0, 0, 0, 0))
    for y in h + 2:
        for x in w + 2:
            var sx := x - 1
            var sy := y - 1
            if sx >= 0 and sy >= 0 and sx < w and sy < h and src.get_pixel(sx, sy).a > 0.5:
                continue
            var near := false
            for dy in [-1, 0, 1]:
                for dx in [-1, 0, 1]:
                    var nx: int = sx + dx
                    var ny: int = sy + dy
                    if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
                        near = true
            if near:
                out.set_pixel(x, y, Color.WHITE)
    return out


static func _key(rounded: Dictionary, player_color: Color, worn: Dictionary = {}) -> int:
    var arr: Array = []
    for th in ORDER:
        if rounded.has(th):
            arr.append(th)
            arr.append(rounded[th])
    arr.append(player_color)
    for slot in WornGear.SLOTS:
        arr.append(String(worn.get(slot, "")))
    return hash(arr)


static func _render(p: Dictionary, pal: Array[Color], step: bool) -> Image:
    var buf := Buf.new()
    var b: Dictionary = BUILDS[p["build"]]
    var tx: int = b["tx"]
    var trim: int = b["trim"]
    var ax: int = b["ax"]
    var ar: int = b["ar"]
    var tw := 8 + trim
    var main_pal := _pal(pal, pal[3])
    var side_pal := _pal(pal, theme_accent(String(p["side_theme"])))
    var worn: Dictionary = p.get("worn", {})
    var wp := {}   # slot -> piece palette
    for slot in worn.keys():
        wp[slot] = WornGear.pal(worn[slot]["colors"], pal)
    var chest_kind := String(worn["chest"]["kind"]) if worn.has("chest") else ""

    # Cape (behind everything; the step frame flutters its lower rows). A cloak replaces it.
    if chest_kind != "" and WornGear.chest_cape(chest_kind) != "":
        WornGear.draw_cape(buf, chest_kind, wp["chest"], step)
    else:
        var cape: Array = CAPES.get(String(p["cape"]), [])
        for r in cape.size():
            var cy := 7 + r
            var shift := 1 if step and cy >= 12 else 0
            buf.row(String(cape[r]), 1 + shift, cy, side_pal, L_CAPE)
    # Legs (the step frame lifts the first leg by a pixel).
    var legs: Array = b["legs"]
    for li in legs.size():
        var cols: Array = legs[li]
        for lx in cols:
            if step and li == 0:
                buf.put(int(lx), 13, "d", main_pal, L_LEGS)
            else:
                buf.put(int(lx), 13, "#", main_pal, L_LEGS)
                buf.put(int(lx), 14, "d", main_pal, L_LEGS)
    # Torso.
    var torso: Array = TORSOS[p["torso"]]
    for r in torso.size():
        buf.row(_resize_row(String(torso[r]), trim), tx, 7 + r, main_pal, L_TORSO)
    # Arms.
    var arm: Array = ARMS[p["arms"]]
    for r in arm.size():
        var arow := String(arm[r])
        buf.row(arow, ax, 7 + r, side_pal, L_ARMS)
        buf.row(_mirror(arow), ar, 7 + r, side_pal, L_ARMS)
    # Worn pieces over the body: the chest piece (with its sleeves or pauldrons), boots,
    # then gloves.
    if chest_kind != "":
        WornGear.draw_chest(buf, chest_kind, wp["chest"], tx, trim, ax, ar)
    if worn.has("feet"):
        WornGear.draw_feet(buf, String(worn["feet"]["kind"]), wp["feet"], legs, step)
    if worn.has("hands"):
        WornGear.draw_hands(buf, String(worn["hands"]["kind"]), wp["hands"], ax, ar)
    # Head: the worn one, or the theme's with theme 2's head as a detail when the two are
    # close.
    var ov_id := String(p["overlay"])
    if worn.has("head"):
        WornGear.draw_head(buf, String(worn["head"]["kind"]), wp["head"])
        ov_id = ""
    else:
        var head: Array = HEADS[p["head"]]
        for r in head.size():
            buf.row(String(head[r]), 4, r, main_pal, L_HEAD)
    if ov_id != "":
        var ov: Dictionary = HEAD_OVERLAYS[ov_id]
        var ov_pal := _pal(pal, theme_accent(String(p["overlay_theme"])))
        var og: Array = ov["grid"]
        for r in og.size():
            buf.row(String(og[r]), 4, int(ov["y"]) + r, ov_pal, L_HEAD, int(ov["mode"]))
    # Accents, each in its own theme's accent colour.
    var lay := { "ax": ax, "ar": ar, "t0": tx + 1, "t1": tx + tw - 2 }
    for acc in p["accents"]:
        var ad: Dictionary = acc
        var fx := String(ad["fx"])
        if worn.has("head") and HEAD_FX.has(fx):
            continue
        if chest_kind != "" and (CHEST_FX.has(fx) or (WornGear.chest_covers(chest_kind) and COVERED_TORSO_FX.has(fx))):
            continue
        _fx(buf, fx, lay, _pal(pal, theme_accent(String(ad["theme"]))), step)
    buf.outline(OUTLINE)
    return buf.to_image()


## Slim (-2) drops the two centre columns of an 8-wide row; broad (+2) doubles them.
static func _resize_row(s: String, trim: int) -> String:
    if trim < 0:
        return s.substr(0, 3) + s.substr(5, 3)
    if trim > 0:
        return s.substr(0, 4) + s.substr(3, 2) + s.substr(4, 4)
    return s


static func _mirror(s: String) -> String:
    var out := ""
    for i in range(s.length() - 1, -1, -1):
        out += s[i]
    return out


static func _fx(buf: Buf, fx: String, lay: Dictionary, pal: Dictionary, step: bool) -> void:
    var ax: int = lay["ax"]
    var ar: int = lay["ar"]
    var t0: int = lay["t0"]
    var t1: int = lay["t1"]
    match fx:
        "flame_tips":
            # The top of the head burns, with two flicks that dance between frames.
            var flicks: Array = [7, 8] if step else [6, 9]
            for x in range(4, 12):
                var top := buf.top_of(x, L_HEAD)
                if top < 0:
                    continue
                buf.paint(x, top, "a", pal)
                if flicks.has(x) and top > 0:
                    buf.paint(x, top - 1, "a", pal, EMPTY)
        "wave_hem":
            for x in 16:
                for y in range(14, 8, -1):
                    var hl := buf.layer_at(x, y)
                    if hl == L_TORSO or hl == L_CAPE:
                        buf.paint(x, y, "a", pal)
                        break
        "bolt":
            for v in [Vector2i(8, 8), Vector2i(7, 9), Vector2i(8, 9), Vector2i(7, 10)]:
                var bv: Vector2i = v
                buf.paint(bv.x, bv.y, "a", pal, OVER, L_TORSO)
        "frost_spikes":
            for y in range(5, 8):
                buf.paint(ax, y, "a", pal)
                buf.paint(ar + 1, y, "a", pal)
            buf.paint(ax + 1, 7, "a", pal)
            buf.paint(ar, 7, "a", pal)
        "stains":
            for v in [Vector2i(t0 + 1, 9), Vector2i(t0 + 2, 9), Vector2i(t1 - 1, 11), Vector2i(t1, 8)]:
                var sv: Vector2i = v
                buf.paint(sv.x, sv.y, "a", pal, OVER, L_TORSO)
            buf.paint(ar + 1, 12, "a", pal, OVER)
        "drips":
            for x in [ax, ax + 1, ar, ar + 1]:
                buf.paint(int(x), 12, "a", pal, OVER, L_ARMS)
            var dy := 14 if step else 13
            buf.paint(ax, dy, "a", pal, EMPTY)
            buf.paint(ar + 1, dy, "a", pal, EMPTY)
        "flask_belt":
            for x in [t0, t1]:
                buf.paint(int(x), 10, "l", pal)
                buf.paint(int(x), 11, "a", pal)
                buf.paint(int(x), 12, "a", pal)
        "blood_stains":
            for v in [Vector2i(t0 + 1, 8), Vector2i(t0 + 2, 9), Vector2i(t1 - 1, 10), Vector2i(t1, 11)]:
                var dv: Vector2i = v
                buf.paint(dv.x, dv.y, "a", pal, OVER, L_TORSO)
            buf.paint(ar, 12, "a", pal, OVER)
            buf.paint(ar + 1, 12, "a", pal, OVER)
        "void_eyes":
            for y in 7:
                for x in range(4, 12):
                    if buf.layer_at(x, y) != L_HEAD:
                        continue
                    var ec := buf.code_at(x, y)
                    if ec == "o" or ec == "a":
                        buf.paint(x, y, "a", pal)
            # A skull pauldron on the left shoulder.
            buf.row("bbb", ax, 7, pal, L_FX)
            buf.row("obo", ax, 8, pal, L_FX)
        "halo":
            var htop := 16
            for x in range(4, 12):
                for hl in [L_HEAD, L_WORN]:
                    var ht := buf.top_of(x, int(hl))
                    if ht >= 0 and ht < htop:
                        htop = ht
            if htop < 1:
                return   # a tall worn hat leaves no room above it
            # An arc over the head: a bar above it with ends dropping past its sides.
            var hy := maxi(0, htop - 1)
            for x in range(5, 11):
                buf.paint(x, hy, "a", pal, EMPTY)
            buf.paint(4, hy + 1, "a", pal, EMPTY)
            buf.paint(11, hy + 1, "a", pal, EMPTY)
        "scarf":
            for x in 16:
                if buf.layer_at(x, 7) == L_TORSO:
                    buf.paint(x, 7, "a", pal)
            buf.paint(t1 + 1, 7, "a", pal)
            if step:
                buf.paint(t1 + 2, 6, "a", pal)
                buf.paint(t1 + 3, 6, "a", pal)
            else:
                buf.paint(t1 + 2, 7, "a", pal)
                buf.paint(t1 + 3, 8, "a", pal)
        "stone_shoulders":
            buf.row("ll", ax, 6, pal, L_FX)
            buf.row("#d", ax, 7, pal, L_FX)
            buf.row("ll", ar, 6, pal, L_FX)
            buf.row("d#", ar, 7, pal, L_FX)
        "pauldrons":
            buf.row("lll", ax - 1, 7, pal, L_FX)
            buf.row("dad", ax - 1, 8, pal, L_FX)
            buf.row("lll", ar, 7, pal, L_FX)
            buf.row("dad", ar, 8, pal, L_FX)
        "boots":
            for y in range(12, 16):
                for x in 16:
                    if buf.layer_at(x, y) == L_LEGS and buf.code_at(x, y) == "d":
                        buf.paint(x, y, "a", pal)
        "gem":
            for v in [Vector2i(7, 8), Vector2i(8, 8), Vector2i(7, 9), Vector2i(8, 9)]:
                var gv: Vector2i = v
                buf.paint(gv.x, gv.y, "a", pal, OVER, L_TORSO)
        "bandolier":
            for k in 5:
                var bx := t0 + roundi(float(k) * float(t1 - t0) / 4.0)
                buf.paint(bx, 7 + k, "a", pal, OVER, L_TORSO)
        "purse":
            buf.paint(t1 + 1, 10, "d", pal)
            for y in [11, 12]:
                buf.paint(t1, int(y), "a", pal)
                buf.paint(t1 + 1, int(y), "a", pal)


## A 16 x 16 working canvas: colour, part code and layer per pixel.
class Buf extends RefCounted:
    var code := PackedByteArray()
    var lay := PackedByteArray()
    var col := PackedColorArray()

    func _init() -> void:
        code.resize(256)
        lay.resize(256)
        col.resize(256)

    func _inside(x: int, y: int) -> bool:
        return x >= 0 and y >= 0 and x < 16 and y < 16

    func layer_at(x: int, y: int) -> int:
        if not _inside(x, y):
            return 0
        return lay[y * 16 + x]

    func code_at(x: int, y: int) -> String:
        if not _inside(x, y) or code[y * 16 + x] == 0:
            return ""
        return String.chr(code[y * 16 + x])

    ## Set one pixel on `layer`. mode: ANY, EMPTY (only where transparent), OVER (only
    ## where something is already drawn).
    func put(x: int, y: int, ch: String, pal: Dictionary, layer: int, mode: int = 0) -> void:
        if ch == "." or ch == "" or not _inside(x, y):
            return
        var i := y * 16 + x
        var has := code[i] != 0
        if mode == 1 and has:
            return
        if mode == 2 and not has:
            return
        code[i] = ch.unicode_at(0)
        lay[i] = layer
        col[i] = pal.get(ch, Color.MAGENTA)

    func row(s: String, x0: int, y: int, pal: Dictionary, layer: int, mode: int = 0) -> void:
        for c in s.length():
            put(x0 + c, y, s[c], pal, layer, mode)

    ## Recolour (or add) a pixel, keeping the layer it belongs to; `only_layer` > 0 limits
    ## it to pixels of that layer.
    func paint(x: int, y: int, ch: String, pal: Dictionary, mode: int = 0, only_layer: int = 0) -> void:
        if not _inside(x, y):
            return
        var cur := layer_at(x, y)
        if only_layer > 0 and cur != only_layer:
            return
        put(x, y, ch, pal, cur if cur != 0 else 6, mode)

    ## Topmost row holding a pixel of `layer` in column x, or -1.
    func top_of(x: int, layer: int) -> int:
        for y in 16:
            if lay[y * 16 + x] == layer and code[y * 16 + x] != 0:
                return y
        return -1

    ## A 1 px outline in every transparent pixel next to the figure (4-neighbours), which
    ## also turns 1 px gaps between parts into dark separators, Kenney style.
    func outline(c: Color) -> void:
        var snap := code.duplicate()
        for y in 16:
            for x in 16:
                var i := y * 16 + x
                if snap[i] != 0:
                    continue
                var near := (x > 0 and snap[i - 1] != 0) or (x < 15 and snap[i + 1] != 0) \
                    or (y > 0 and snap[i - 16] != 0) or (y < 15 and snap[i + 16] != 0)
                if near:
                    code[i] = 111   # "o"
                    lay[i] = 9
                    col[i] = c

    func to_image() -> Image:
        var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
        img.fill(Color(0, 0, 0, 0))
        for i in 256:
            if code[i] != 0:
                img.set_pixel(i % 16, i / 16, col[i])
        return img


# --- Debug sheet ---------------------------------------------------------------

const FONT3 := {
    "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
    "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
    "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
    "M": ["#.#", "###", "#.#", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
    "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
    "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W": ["#.#", "#.#", "#.#", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
    "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
    "-": ["...", "...", "###", "...", "..."], "+": ["...", ".#.", "###", ".#.", "..."],
    ".": ["...", "...", "...", "...", ".#."], "_": ["...", "...", "...", "...", "###"],
}


## Every class alone and eight two-theme blends (3.0 and 2.5, close enough to overlay the
## second head), idle and step frames at 6x with labels, saved as one PNG at `path`.
## `player_color` mixes in like in game; transparent (the default) shows pure themes.
static func debug_sheet(path: String, player_color: Color = Color(0, 0, 0, 0)) -> Error:
    var entries: Array = []
    for c in Classes.all():
        var cdef: Dictionary = c
        var cth := element_theme(int(cdef["element"]))
        if cth == "":
            cth = "vagrant"
        entries.append([String(cdef["id"]), { cth: CLASS_WEIGHT }])
    for pair in DEBUG_BLENDS:
        var bp: Array = pair
        entries.append(["%s+%s" % [bp[0], bp[1]], { String(bp[0]): 3.0, String(bp[1]): 2.5 }])
    var scale := 6
    var fs := 16 * scale
    var cols := 4
    var cell_w := fs * 2 + 24
    var cell_h := fs + 44
    var rows := (entries.size() + cols - 1) / cols
    var sheet := Image.create_empty(cols * cell_w + 16, rows * cell_h + 16, false, Image.FORMAT_RGBA8)
    sheet.fill(Color(0.09, 0.08, 0.10))
    for i in entries.size():
        var e: Array = entries[i]
        var fig := generate_from(e[1], player_color)
        var ox := 8 + (i % cols) * cell_w
        var oy := 8 + (i / cols) * cell_h
        var imgs: Array = fig["images"]
        for f in 2:
            var fx := ox + 4 + f * (fs + 8)
            sheet.fill_rect(Rect2i(fx, oy, fs, fs), Color(0.15, 0.13, 0.15))
            var src: Image = imgs[f]
            var big: Image = src.duplicate()
            big.resize(fs, fs, Image.INTERPOLATE_NEAREST)
            sheet.blend_rect(big, Rect2i(0, 0, fs, fs), Vector2i(fx, oy))
        var fc: Color = fig["color"]
        _text(sheet, ox + 4, oy + fs + 8, String(fig["name"]), fc.lightened(0.3), 2)
        _text(sheet, ox + 4, oy + fs + 24, String(e[0]), Color(0.6, 0.56, 0.6), 2)
    return sheet.save_png(path)


## Every item of `slot` (head, chest, hands, feet) worn on each profile in `profiles`: the
## item's icon at 2x, then the idle figures at 5x and the step frame of the last, with
## the item id and the kind it is drawn as. Saved as one PNG at `path`.
static func gear_sheet(path: String, slot: String, profiles: Array = [], player_color: Color = Color(0, 0, 0, 0)) -> Error:
    if profiles.is_empty():
        profiles = [{ "vagrant": CLASS_WEIGHT }, { "fire": CLASS_WEIGHT }, { "plate": 3.0, "ice": 2.5 }]
    var ids: Array = []
    for id in Items.catalog.keys():
        if String(Items.get_item(String(id)).get("slot", "")) == slot:
            ids.append(String(id))
    var scale := 5
    var fs := 16 * scale
    var cols := 3
    var cell_w := 64 + 12 + (fs + 6) * (profiles.size() + 1) + 16
    var cell_h := fs + 44
    var rows := (ids.size() + cols - 1) / cols
    var sheet := Image.create_empty(cols * cell_w + 16, rows * cell_h + 16, false, Image.FORMAT_RGBA8)
    sheet.fill(Color(0.09, 0.08, 0.10))
    for i in ids.size():
        var id: String = ids[i]
        var it: Dictionary = Items.get_item(id)
        var ox := 8 + (i % cols) * cell_w
        var oy := 8 + (i / cols) * cell_h
        var tex: Texture2D = Items.icon(it)
        var src: Image = tex.get_image() if tex != null else null
        sheet.fill_rect(Rect2i(ox, oy + (fs - 64) / 2, 64, 64), Color(0.15, 0.13, 0.15))
        if src != null and not src.is_empty():
            var big: Image = src.duplicate()
            if big.is_compressed():
                big.decompress()
            big.convert(Image.FORMAT_RGBA8)
            big.resize(64, 64, Image.INTERPOLATE_NEAREST)
            sheet.blend_rect(big, Rect2i(0, 0, 64, 64), Vector2i(ox, oy + (fs - 64) / 2))
        var fx := ox + 64 + 12
        for pi in profiles.size() + 1:
            var prof: Dictionary = profiles[mini(pi, profiles.size() - 1)]
            var fig := generate_from(prof, player_color, { slot: id })
            var img: Image = (fig["images"] as Array)[1 if pi == profiles.size() else 0]
            sheet.fill_rect(Rect2i(fx, oy, fs, fs), Color(0.15, 0.13, 0.15))
            var fb: Image = img.duplicate()
            fb.resize(fs, fs, Image.INTERPOLATE_NEAREST)
            sheet.blend_rect(fb, Rect2i(0, 0, fs, fs), Vector2i(fx, oy))
            fx += fs + 6
        var kind := WornGear.kind_of(id, it)
        _text(sheet, ox, oy + fs + 8, id, Color(0.85, 0.8, 0.75), 2)
        _text(sheet, ox, oy + fs + 22, kind, Color(0.95, 0.75, 0.4), 2)
    return sheet.save_png(path)


static func _text(img: Image, x: int, y: int, s: String, c: Color, scale: int) -> void:
    var cx := x
    for ch in s.to_upper():
        var glyph: Array = FONT3.get(ch, [])
        for gy in glyph.size():
            var grow: String = glyph[gy]
            for gx in 3:
                if grow[gx] == "#":
                    img.fill_rect(Rect2i(cx + gx * scale, y + gy * scale, scale, scale), c)
        cx += 4 * scale
