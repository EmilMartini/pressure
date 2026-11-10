class_name LevelUps
extends RefCounted
## In-run level-up boons: pick one of three on each level, Brotato style, with Hades-style
## build boons tied to the elements you carry and to the reaction tiers.
##
## Measured before this catalog (bots, `--dps-probe`, see GDD "Level-ups"): a typical old
## pick (+4 to 16% of one stat) moved the storm build's damage per second by 1 to 6%, and
## half the picks a human made (projectile speed, XP gain, luck, vent capacity, range)
## changed nothing that kills. A level now comes about once per arena wave (Player.xp_to_next)
## and every option changes damage or survival: bigger numbers, stats that feed what deals
## the damage (reactions 38%, fusions 29%, cataclysms 13% and damage over time 44% of a late
## run), boons for each element you carry, and a few trades with a cost.
##
## An entry: { id, name, cat, key, amounts: [common, uncommon, rare, epic] (null where not
## offered), weight, icon, affects (plain words: what it changes), optional:
##   also: { key: [amounts] }   a second stat at the same rarity (e.g. crit chance + damage)
##   cost: { key: amount }      a drawback applied with it (any rarity)
##   element: "fire"            only offered while you carry a gun of that element
##   min_elements: N            only offered while you carry N or more elements
##   echo: "wet"                a trigger boon: amounts are chances; your reactions that
##                              involve `element` spread `echo` onto enemies nearby
## }
## `options()` expands it into one option per rarity; element entries are made for all
## twelve elements from ELEMENT_BOONS.

## Keys whose amount is a fraction and reads as a percentage.
const PERCENT_KEYS := [
    "dmg", "fire_rate", "crit", "crit_dmg", "dodge", "speed", "potency", "state_duration",
    "vent_charge", "vent_radius", "vent_power", "dot_power", "fusion_power",
    "cataclysm_power", "compound_life", "field_life",
]

## Short stat names for headlines.
const STAT_LABELS := {
    "dmg": "damage", "fire_rate": "attack speed", "crit": "crit chance",
    "crit_dmg": "crit damage", "pierce": "pierce", "proj_count": "projectile",
    "max_hp": "max health", "armor": "armour", "dodge": "dodge", "regen": "health / s",
    "speed": "move speed", "potency": "reaction power", "state_duration": "element duration",
    "chain_jumps": "chain jump", "lifesteal": "health per reaction", "carry": "carry weight",
    "vent_charge": "vent charge speed", "vent_radius": "vent radius", "vent_power": "vent power",
    "dot_power": "burn, poison, bleed", "fusion_power": "fusion damage",
    "cataclysm_power": "cataclysm damage", "compound_life": "compound lifetime",
    "field_life": "field lifetime", "dash_charges": "dash charge",
}

## Core loop reset 5.1 (decision 13): fewer, bigger level-ups. Amounts are doubled (counts in
## NO_DOUBLE stay: a second pierce or projectile would be a rare pick's job), and one card in
## RARE_PICK_ODDS is a rare pick that changes play, on the Epic frame: an element Echo (the
## boons that already behave like triggers, only offered here now), a dash charge, a target
## more for every gun (a second beam) or a second element on one gun.
const NO_DOUBLE := ["pierce", "proj_count", "chain_jumps", "carry"]
const RARE_PICK_ODDS := 0.1
const RARE_PICKS: Array = [
    { "id": "rp_dash", "name": "Second Wind", "cat": "DEFENCE", "key": "dash_charges", "amount": 1, "weight": 3,
        "icon": "gui/spells/translocation/blink.png", "affects": "One more dash before the cooldown" },
    { "id": "rp_focus", "name": "Split Focus", "cat": "OFFENCE", "key": "proj_count", "amount": 1, "weight": 3,
        "icon": "gui/spells/conjuration/dazzling_spray.png", "affects": "Every gun takes one more target: a second beam, another shot" },
    { "id": "rp_coat", "name": "Coating", "cat": "ELEMENT", "key": "coat", "amount": 0, "weight": 3,
        "icon": "gui/spells/transmutation/irradiate.png", "affects": "" },
]

## Category word shown on the card (neutral text, no colour coding).
const CATS := ["OFFENCE", "DEFENCE", "REACTIONS", "FUSIONS", "ELEMENT", "VENT", "TRADE-OFF"]

## Rarities (same numbers as Items.Rarity).
const COMMON := 0
const UNCOMMON := 1
const RARE := 2
const EPIC := 3

## Rarity odds keyed on player level: [min level, growth per level, cap]. Checked from
## epic down to uncommon, else common; chance = clamp(growth * (level - min + 1) * (1 + luck)).
## A run is about 28 levels now (one a wave), so these climb about twice as fast as before.
const RARITY_ODDS := {
    UNCOMMON: [2, 0.12, 0.55],
    RARE: [3, 0.05, 0.28],
    EPIC: [5, 0.02, 0.10],
}

## Big percentages per rarity [common, uncommon, rare, epic].
const PCT := [0.10, 0.16, 0.24, 0.35]
## For stats that only touch part of the damage (reactions, damage over time, a tier).
const PCT_PART := [0.15, 0.24, 0.35, 0.50]

const CATALOG: Array = [
    # Offence: these multiply everything. A shot's damage seeds the potency of every
    # reaction, fusion and burn it causes, so +damage reaches all of it.
    { "id": "damage", "name": "Sharpened", "cat": "OFFENCE", "key": "dmg", "amounts": PCT, "weight": 10,
        "icon": "gui/spells/enchantment/sure_blade_new.png", "affects": "Guns, reactions, fusions and burns" },
    { "id": "attack_speed", "name": "Quick Trigger", "cat": "OFFENCE", "key": "fire_rate", "amounts": PCT, "weight": 9,
        "icon": "gui/spells/enchantment/haste_new.png", "affects": "Every gun: more hits, more reactions" },
    { "id": "crit", "name": "Keen Eye", "cat": "OFFENCE", "key": "crit", "amounts": [0.06, 0.09, 0.13, 0.18], "weight": 6,
        "also": { "crit_dmg": [0.20, 0.30, 0.45, 0.60] },
        "icon": "gui/spells/enchantment/see_invisible.png", "affects": "Crits hit x2 and power up reactions" },
    { "id": "pierce", "name": "Piercing Rounds", "cat": "OFFENCE", "key": "pierce", "amounts": [null, null, 1, null], "weight": 3,
        "icon": "gui/spells/conjuration/force_lance.png", "affects": "Every shot passes through one more enemy" },
    # Defence.
    { "id": "max_hp", "name": "Thick Hide", "cat": "DEFENCE", "key": "max_hp", "amounts": [15, 25, 35, 50], "weight": 9,
        "icon": "gui/spells/enchantment/enslavement_new.png", "affects": "Maximum health (healed by the gain)" },
    { "id": "armor", "name": "Plating", "cat": "DEFENCE", "key": "armor", "amounts": [2, 3, 4, 6], "weight": 7,
        "icon": "gui/spells/stonemail.png", "affects": "Taken off every hit you take" },
    { "id": "regen", "name": "Mending", "cat": "DEFENCE", "key": "regen", "amounts": [0.8, 1.2, 1.8, 2.5], "weight": 7,
        "icon": "gui/spells/necromancy/regeneration_new.png", "affects": "Health back every second" },
    { "id": "dodge", "name": "Light Feet", "cat": "DEFENCE", "key": "dodge", "amounts": [0.05, 0.07, 0.10, 0.14], "weight": 5,
        "icon": "gui/spells/translocation/blink.png", "affects": "Chance to avoid a hit entirely" },
    { "id": "speed", "name": "Sprinter", "cat": "DEFENCE", "key": "speed", "amounts": [0.08, 0.12, 0.16, 0.22], "weight": 5,
        "icon": "gui/spells/air/swiftness_new.png", "affects": "Move faster: kite the crowd" },
    { "id": "lifesteal", "name": "Leech", "cat": "DEFENCE", "key": "lifesteal", "amounts": [null, null, 1, 2], "weight": 4,
        "icon": "gui/spells/necromancy/vampiric_draining_new.png", "affects": "Heal on reactions, up to 3 a second" },
    # Reactions (tier 2) and what they leave behind. (Lingering, +element duration, is gear
    # only now: two of them measured -17% damage per second in the dps probe.)
    # Catalyst measured about 2x the damage per second of the same percentage of damage
    # (potency stacks with far less gear), so it moves at the same steps as damage.
    { "id": "potency", "name": "Catalyst", "cat": "REACTIONS", "key": "potency", "amounts": PCT, "weight": 8,
        "icon": "gui/spells/conjuration/orb_of_destruction.png", "affects": "Reactions, fusions, cataclysms, burns" },
    { "id": "dot", "name": "Smoulder", "cat": "REACTIONS", "key": "dot_power", "amounts": [0.20, 0.30, 0.45, 0.60], "weight": 6,
        "icon": "gui/spells/fire/sticky_flame_new.png", "affects": "Burn, poison and bleed from reactions" },
    { "id": "chain_jumps", "name": "Conductor", "cat": "REACTIONS", "key": "chain_jumps", "amounts": [null, null, 1, 2], "weight": 3,
        "element": "shock", "icon": "gui/spells/air/chain_lightning_new.png", "affects": "Chain Lightning and other chains" },
    # Fusions (tier 3) and cataclysms (tier 4): need three or four elements.
    { "id": "fusion_power", "name": "Alchemist", "cat": "FUSIONS", "key": "fusion_power", "amounts": [0.20, 0.30, 0.45, 0.60], "weight": 6,
        "min_elements": 3, "icon": "gui/spells/conjuration/fulminant_prism.png", "affects": "Fusions (a third element on a compound)" },
    { "id": "compound_life", "name": "Residue", "cat": "FUSIONS", "key": "compound_life", "amounts": [0.30, 0.45, 0.65, 0.90], "weight": 5,
        "min_elements": 3, "icon": "gui/spells/transmutation/irradiate.png", "affects": "Compounds wait longer: more fusions" },
    { "id": "field_life", "name": "Standing Fields", "cat": "FUSIONS", "key": "field_life", "amounts": [0.30, 0.45, 0.65, 0.90], "weight": 4,
        "min_elements": 4, "icon": "gui/spells/conjuration/battlesphere.png", "affects": "Fusion fields last: more cataclysms" },
    { "id": "cataclysm_power", "name": "Apocalypse", "cat": "FUSIONS", "key": "cataclysm_power", "amounts": [null, 0.40, 0.60, 0.80], "weight": 3,
        "min_elements": 4, "icon": "gui/spells/conjuration/orb_of_destruction_big.png", "affects": "Cataclysms (a fourth element on a field)" },
    # Vent.
    { "id": "vent", "name": "Blowback", "cat": "VENT", "key": "vent_power", "amounts": PCT_PART, "weight": 4,
        "also": { "vent_radius": [0.10, 0.15, 0.20, 0.30] },
        "icon": "gui/spells/fire/fire_storm_new.png", "affects": "Your vent blast: harder and wider" },
    { "id": "vent_charge", "name": "Bellows", "cat": "VENT", "key": "vent_charge", "amounts": [0.20, 0.30, 0.45, 0.60], "weight": 3,
        "icon": "gui/spells/fire/flame_tongue_new.png", "affects": "Vent fills faster: vent more often" },
    { "id": "carry", "name": "Deep Pockets", "cat": "DEFENCE", "key": "carry", "amounts": [null, 2, 3, null], "weight": 2,
        "icon": "gui/spells/translocation/apportation_new.png", "affects": "Carry heavier guns (each weight slows you)" },
    # Trade-offs (Brotato's items): more of one thing, less of another.
    { "id": "glass_cannon", "name": "Glass Cannon", "cat": "TRADE-OFF", "key": "dmg", "amounts": [null, null, 0.35, 0.50], "weight": 3,
        "cost": { "max_hp": -20 }, "icon": "gui/spells/necromancy/excruciating_wounds_new.png", "affects": "Everything you deal" },
    { "id": "overclock", "name": "Overclock", "cat": "TRADE-OFF", "key": "fire_rate", "amounts": [null, 0.25, 0.35, null], "weight": 3,
        "cost": { "speed": -0.08 }, "icon": "gui/spells/air/static_discharge_new.png", "affects": "Every gun fires faster" },
    { "id": "heavy_plate", "name": "Heavy Plate", "cat": "TRADE-OFF", "key": "armor", "amounts": [null, 5, 7, null], "weight": 3,
        "cost": { "speed": -0.08 }, "icon": "gui/spells/earth/statue_form_old.png", "affects": "Taken off every hit you take" },
    { "id": "split_barrel", "name": "Split Barrel", "cat": "TRADE-OFF", "key": "proj_count", "amounts": [null, null, null, 1], "weight": 2,
        "cost": { "dmg": -0.10 }, "icon": "gui/spells/conjuration/dazzling_spray.png", "affects": "Every volley fires one more shot" },
]

## Element boons, one set per element (offered only while you carry that element):
## Attunement (+damage for that element's guns, which also seeds the reactions they
## start) and Echo (rare/epic: your reactions that involve the element spread a partner
## element onto enemies nearby, priming the next reaction).
## element -> [partner it spreads, the reaction that partner sets up, icon]
const ELEMENT_BOONS := {
    "wet": ["shock", "Chain Lightning", "gui/spells/ice/ensorcelled_hibernation_new.png"],
    "shock": ["wet", "Chain Lightning", "gui/spells/air/insulation.png"],
    "fire": ["oil", "Inferno", "gui/spells/fire/inner_flame.png"],
    "ice": ["wet", "Deep Freeze", "gui/spells/ice/ice_form_old.png"],
    "oil": ["fire", "Inferno", "gui/spells/earth/ledas_liquefaction.png"],
    "poison": ["acid", "Virulence", "gui/spells/poison/olgrebs_toxic_radiance_new.png"],
    "acid": ["wet", "Caustic Splash", "gui/invocations/gozag_potion_petition.png"],
    "blood": ["poison", "Sepsis", "gui/spells/necromancy/sublimation_of_blood_old.png"],
    "void": ["holy", "Annihilation", "gui/spells/translocation/disjunction.png"],
    "holy": ["void", "Annihilation", "gui/invocations/tso_bless_weapon.png"],
    "gale": ["fire", "Firestorm", "gui/spells/air/swiftness_old.png"],
    "stone": ["blood", "Bludgeon", "gui/spells/earth/statue_form_old.png"],
}
const ATTUNE := [0.20, 0.30, 0.45, 0.60]
const ECHO := [null, null, 0.25, 0.50]
const ECHO_RADIUS := 110.0

static var _expanded: Array = []


## Every concrete option: one per entry and available rarity.
static func options() -> Array:
    if not _expanded.is_empty():
        return _expanded
    var entries: Array = CATALOG.duplicate(true)
    for ek in ELEMENT_BOONS.keys():
        var b: Array = ELEMENT_BOONS[ek]
        var el_name := String(ek).capitalize()
        entries.append({ "id": "attune_" + ek, "name": "%s Attunement" % el_name, "cat": "ELEMENT", "key": "dmg_" + ek,
            "amounts": ATTUNE, "weight": 4, "element": ek, "icon": b[2],
            "affects": "%s guns and the reactions they start" % el_name })
        entries.append({ "id": "echo_" + ek, "name": "%s Echo" % el_name, "cat": "ELEMENT", "key": "echo_" + ek,
            "amounts": ECHO, "weight": 3, "element": ek, "echo": b[0], "icon": b[2],
            "affects": "Your %s reactions soak enemies nearby: sets up %s" % [el_name, b[1]] })
    for base in entries:
        var amounts: Array = base["amounts"]
        for r in amounts.size():
            if amounts[r] == null:
                continue
            var opt: Dictionary = base.duplicate(true)
            opt.erase("amounts")
            opt["id"] = "%s_%d" % [base["id"], r]
            opt["base"] = base["id"]
            opt["amount"] = amounts[r]
            opt["rarity"] = r
            if base.has("also"):
                var also := {}
                for k in base["also"].keys():
                    also[k] = base["also"][k][r]
                opt["also"] = also
            _expanded.append(opt)
    return _expanded


## Rarity for one option at `level`, scaled by `luck`.
static func roll_rarity(level: int, luck: float = 0.0) -> int:
    for r in [EPIC, RARE, UNCOMMON]:
        var odds: Array = RARITY_ODDS[r]
        var min_level := int(odds[0])
        if level < min_level:
            continue
        var chance := clampf(float(odds[1]) * float(level - min_level + 1) * (1.0 + luck), 0.0, float(odds[2]))
        if randf() < chance:
            return r
    return COMMON


## Whether `player` may be offered `opt` (element boons need that element carried,
## fusion boons enough elements).
static func eligible(opt: Dictionary, player) -> bool:
    if player == null or not is_instance_valid(player):
        return not opt.has("element") and not opt.has("min_elements")
    var kinds: Array = player.element_kinds()
    if opt.has("element") and not kinds.has(Items.ELEMENTS.get(String(opt["element"]), -1)):
        return false
    if opt.has("min_elements") and kinds.size() < int(opt["min_elements"]):
        return false
    return true


## `count` options on distinct boons. Each rolls a rarity from the player's level and
## luck, then an eligible option of that rarity is picked by weight (falling back one
## rarity at a time when nothing of that rarity is left).
static func roll(player, count: int) -> Array:
    var level := 1
    var luck := 0.0
    if player != null and is_instance_valid(player):
        level = int(player.level)
        luck = float(player.stat("luck"))
    var used: Dictionary = {}
    var picked: Array = []
    var pool_all: Array = options().filter(func(o): return eligible(o, player))
    var reset := not Main.old_balance
    if reset:
        pool_all = pool_all.filter(func(o): return not String(o["base"]).begins_with("echo_"))
    while picked.size() < count:
        if reset and randf() < RARE_PICK_ODDS:
            var rp := rare_pick(player, used)
            if not rp.is_empty():
                used[rp["base"]] = true
                picked.append(rp)
                continue
        var rarity := roll_rarity(level, luck)
        var chosen: Dictionary = {}
        for r in range(rarity, -1, -1):
            var pool: Array = pool_all.filter(func(o): return int(o["rarity"]) == r and not used.has(o["base"]))
            if not pool.is_empty():
                chosen = _weighted(pool)
                break
        if chosen.is_empty():
            # Nothing at or below that rarity: take anything left above it.
            var rest: Array = pool_all.filter(func(o): return not used.has(o["base"]))
            if rest.is_empty():
                break
            chosen = _weighted(rest)
        used[chosen["base"]] = true
        picked.append(bigger(chosen) if reset else chosen.duplicate(true))
    return picked


## An option at twice its amounts (counts in NO_DOUBLE stay), its cost doubled with it.
static func bigger(opt: Dictionary) -> Dictionary:
    var o: Dictionary = opt.duplicate(true)
    if not String(o.get("key", "")) in NO_DOUBLE and (o.get("amount") is float or o.get("amount") is int):
        o["amount"] = float(o["amount"]) * 2.0
    for part in ["also", "cost"]:
        var d: Dictionary = o.get(part, {})
        for k in d.keys():
            if not String(k) in NO_DOUBLE:
                d[k] = float(d[k]) * 2.0
    return o


## One rare pick for `player` not in `used`: an eligible element Echo (at its Epic chance) or
## a behaviour boon. {} when none fits.
static func rare_pick(player, used: Dictionary) -> Dictionary:
    var pool: Array = []
    for o in options():
        if String(o["base"]).begins_with("echo_") and int(o["rarity"]) == EPIC and eligible(o, player) and not used.has(o["base"]):
            pool.append(o.duplicate(true))
    for base in RARE_PICKS:
        if used.has(base["id"]):
            continue
        var o: Dictionary = base.duplicate(true)
        o["base"] = base["id"]
        o["rarity"] = EPIC
        if o["id"] == "rp_coat":
            if player == null or not is_instance_valid(player) or player.guns.is_empty():
                continue
            # The gun with the fewest extra elements gets its element's partner.
            var best = null
            for g in player.guns:
                if best == null or g.extra_elements().size() < best.extra_elements().size():
                    best = g
            var el_key := String(Items.ELEMENT_KEYS.get(int(best.data.element), ""))
            if not ELEMENT_BOONS.has(el_key):
                continue
            var partner := String(ELEMENT_BOONS[el_key][0])
            if best.extra_elements().has(Items.ELEMENTS.get(partner, -1)):
                continue
            o["coat_el"] = partner
            o["coat_gun"] = player.guns.find(best)
            o["name"] = "%s Coating" % partner.capitalize()
            o["affects"] = "%s also applies %s with every hit" % [best.data.display_name, partner.capitalize()]
        elif o["id"] == "rp_dash" and player != null and is_instance_valid(player) and player.dash_max_charges() >= Player.DASH_MAX_CHARGES:
            continue
        pool.append(o)
    if pool.is_empty():
        return {}
    return _weighted(pool)


static func _weighted(pool: Array) -> Dictionary:
    var total := 0.0
    for opt in pool:
        total += float(opt["weight"])
    var at := randf() * total
    for opt in pool:
        at -= float(opt["weight"])
        if at < 0.0:
            return opt
    return pool[pool.size() - 1]


## Every stat change an option makes: {key: amount}, the main one first.
static func changes(opt: Dictionary) -> Dictionary:
    if opt.has("coat_el"):
        return {}
    var out := { String(opt.get("key", "")): opt.get("amount", 0) }
    var also: Dictionary = opt.get("also", {})
    for k in also.keys():
        out[k] = also[k]
    var cost: Dictionary = opt.get("cost", {})
    for k in cost.keys():
        out[k] = float(out.get(k, 0.0)) + float(cost[k])
    return out


## The trigger an echo option adds to the player (Items.fire runs it like gear).
static func echo_trigger(opt: Dictionary) -> Dictionary:
    return { "on": "reaction", "if": "el_" + String(opt["element"]), "chance": float(opt["amount"]),
        "do": "spread", "element": String(opt["echo"]), "radius": ECHO_RADIUS, "at": "target", "potency": 4.0 }


## The headline: the effect in a few words, e.g. "+16% damage" or "+25 max health".
static func describe(opt: Dictionary) -> String:
    if opt.has("coat_el"):
        return "+%s on one gun" % String(opt["coat_el"]).capitalize()
    if opt.has("echo"):
        return "Spreads %s" % String(opt["echo"]).capitalize()
    return amount_text(String(opt.get("key", "")), opt.get("amount", 0))


## One stat change as text: "+16% damage", "-20 max health", "+1 pierce".
static func amount_text(key: String, amount) -> String:
    var stat: String = STAT_LABELS.get(key, key)
    if key.begins_with("dmg_"):
        stat = "%s damage" % key.substr(4).capitalize()
    var v := float(amount)
    var sign := "+" if v >= 0.0 else "-"
    if key in PERCENT_KEYS or key.begins_with("dmg_"):
        return "%s%s%% %s" % [sign, _num(absf(v) * 100.0), stat]
    match key:
        "proj_count", "chain_jumps", "pierce", "dash_charges":
            return "%s%d %s" % [sign, absi(int(v)), stat]
    return "%s%s %s" % [sign, _num(absf(v)), stat]


## A player's current value of `key` as shown on the card ("+20%", "137", "1.5 / s").
static func value_text(key: String, v: float, player = null) -> String:
    if key in PERCENT_KEYS or key.begins_with("dmg_") or key.begins_with("echo_"):
        return "%s%s%%" % ["+" if v >= 0.0 else "-", _num(absf(v) * 100.0)]
    match key:
        "max_hp":
            return _num(v)
        "regen":
            return "%s / s" % _num(v)
        "lifesteal":
            return "%s" % _num(v)
    return _num(v)


## "now -> after" for the main stat of `opt` on `player`, e.g. "+20% -> +36%" or
## "137 -> 162". Empty when there is no player.
static func before_after(opt: Dictionary, player) -> String:
    if player == null or not is_instance_valid(player) or opt.has("coat_el"):
        return ""
    var key := String(opt.get("key", ""))
    var add := float(opt.get("amount", 0.0))
    var cost: Dictionary = opt.get("cost", {})
    if cost.has(key):
        add += float(cost[key])
    var now := 0.0
    if key == "max_hp":
        now = float(player.max_hp)
    elif key.begins_with("echo_"):
        now = float(player.bonus_stats.get(key, 0.0))
    else:
        now = float(player.stat(key))
    var text := "%s  >  %s" % [value_text(key, now, player), value_text(key, now + add, player)]
    if key.begins_with("echo_"):
        text = "chance " + text
    return text


## Lines under the headline: the second stat (also) and the cost, as text.
static func extra_lines(opt: Dictionary) -> Array:
    var out: Array = []
    var also: Dictionary = opt.get("also", {})
    for k in also.keys():
        out.append([amount_text(k, also[k]), false])
    var cost: Dictionary = opt.get("cost", {})
    for k in cost.keys():
        out.append([amount_text(k, cost[k]), true])
    return out


## The option's icon texture; a 1-bit cog if its path is missing.
static func icon(opt: Dictionary) -> Texture2D:
    return Art.icon(String(opt.get("icon", "")), Vector2i(45, 16))


## Element kind of an element boon, or Element.Kind.NONE.
static func element_of(opt: Dictionary) -> int:
    return int(Items.ELEMENTS.get(String(opt.get("element", "")), Element.Kind.NONE))


## Rare or better options get a highlight on their card.
static func is_rare(opt: Dictionary) -> bool:
    return int(opt.get("rarity", COMMON)) >= RARE


static func _num(v: float) -> String:
    if is_equal_approx(v, roundf(v)):
        return str(int(roundf(v)))
    return String.num(v, 1)
