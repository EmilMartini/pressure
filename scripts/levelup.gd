class_name LevelUps
extends RefCounted
## In-run level-up upgrades: pick one of three on each level, Brotato style.
##
## An option is data: { id, name, desc, key, amount, weight, icon, rarity }. `key` is a stat
## key from the Items mod vocabulary (see items.gd). `amount` is a fraction for percentage
## stats (0.08 = +8%) and an int (or hp/s for regen) for flat stats. `weight` is how often
## it is offered relative to the others of the same rarity; `icon` is a Dungeon Crawl tile
## path under Art.ICON_ROOT (see `icon()`); `rarity` is Items.Rarity COMMON..EPIC (no legendary).
##
## CATALOG holds one entry per stat with `amounts`: [common, uncommon, rare, epic], null
## where that stat is not offered at that rarity. `options()` expands it into one option
## per available rarity. Mechanical stats (bounce, pierce, chain jumps, carry) only exist
## at rare, extra projectiles only at epic.

## Keys whose amount is a fraction and reads as a percentage.
const PERCENT_KEYS := [
    "dmg", "fire_rate", "crit", "dodge", "speed", "range", "potency", "state_duration",
    "scrap_gain", "vent_charge", "vent_radius", "vent_power", "xp_gain", "proj_speed",
    "focus_gain", "luck",
]

## Short stat names used by `describe`.
const STAT_LABELS := {
    "dmg": "damage", "fire_rate": "attack speed", "crit": "crit chance",
    "crit_dmg": "crit damage", "bounce": "bounce", "pierce": "pierce",
    "proj_count": "projectile", "max_hp": "max health", "armor": "armour",
    "dodge": "dodge", "regen": "regeneration", "speed": "move speed", "range": "range",
    "potency": "reaction potency", "state_duration": "element duration",
    "chain_jumps": "chain jump", "lifesteal": "lifesteal", "thorns": "thorns",
    "scrap_gain": "scrap gain", "pressure_limit": "vent capacity",
    "vent_charge": "vent charge speed", "vent_radius": "vent radius", "carry": "carry",
    "xp_gain": "XP gain", "proj_speed": "projectile speed", "vent_power": "vent power",
    "focus_gain": "focus gain", "luck": "luck",
}

## Icon tint per stat family: offence, defence, elements, economy, pressure.
const OFFENCE := Color(1.00, 0.55, 0.35)
const DEFENCE := Color(0.55, 0.90, 0.55)
const ELEMENTAL := Color(0.55, 0.75, 1.00)
const ECONOMY := Color(0.85, 0.72, 0.35)
const PRESSURE := Color(0.90, 0.50, 0.95)
const KEY_TINTS := {
    "dmg": OFFENCE, "fire_rate": OFFENCE, "crit": OFFENCE, "crit_dmg": OFFENCE,
    "bounce": OFFENCE, "pierce": OFFENCE, "proj_count": OFFENCE, "range": OFFENCE,
    "proj_speed": OFFENCE,
    "max_hp": DEFENCE, "armor": DEFENCE, "dodge": DEFENCE, "regen": DEFENCE,
    "speed": DEFENCE, "lifesteal": DEFENCE, "thorns": DEFENCE,
    "potency": ELEMENTAL, "state_duration": ELEMENTAL, "chain_jumps": ELEMENTAL,
    "scrap_gain": ECONOMY, "carry": ECONOMY, "xp_gain": ECONOMY, "luck": ECONOMY,
    "pressure_limit": PRESSURE, "vent_charge": PRESSURE, "vent_radius": PRESSURE,
    "vent_power": PRESSURE, "focus_gain": PRESSURE,
}

## Rarities (same numbers as Items.Rarity).
const COMMON := 0
const UNCOMMON := 1
const RARE := 2
const EPIC := 3

## Rarity odds keyed on player level: [min level, growth per level, cap]. Checked from
## epic down to uncommon, else common; chance = clamp(growth * (level - min + 1) * (1 + luck)).
const RARITY_ODDS := {
    UNCOMMON: [2, 0.08, 0.55],
    RARE: [4, 0.035, 0.25],
    EPIC: [7, 0.012, 0.08],
}

## Percent stats per rarity [common, uncommon, rare, epic].
const PCT := [0.04, 0.07, 0.11, 0.16]

## Weights are relative within one rarity: 10 common, 6 uncommon, 3 rare, 1 very rare.
const CATALOG: Array = [
    { "id": "damage", "name": "Sharpened", "desc": "Every shot hits a little harder.",
        "key": "dmg", "amounts": PCT, "weight": 10, "icon": "gui/spells/enchantment/sure_blade_new.png" },
    { "id": "attack_speed", "name": "Quick Trigger", "desc": "Fire faster with every gun.",
        "key": "fire_rate", "amounts": PCT, "weight": 10, "icon": "gui/spells/enchantment/haste_new.png" },
    { "id": "crit", "name": "Keen Eye", "desc": "More shots land as critical hits.",
        "key": "crit", "amounts": [0.03, 0.05, 0.08, 0.12], "weight": 8, "icon": "gui/spells/enchantment/see_invisible.png" },
    { "id": "crit_dmg", "name": "Cruelty", "desc": "Critical hits deal extra damage.",
        "key": "crit_dmg", "amounts": [0.15, 0.25, 0.40, 0.60], "weight": 6, "icon": "gui/spells/necromancy/excruciating_wounds_new.png" },
    { "id": "bounce", "name": "Ricochet", "desc": "Projectiles bounce to another target.",
        "key": "bounce", "amounts": [null, null, 1, null], "weight": 2, "icon": "gui/spells/translocation/portal_projectile_old.png" },
    { "id": "pierce", "name": "Piercing Rounds", "desc": "Projectiles pass through one more enemy.",
        "key": "pierce", "amounts": [null, null, 1, null], "weight": 3, "icon": "gui/spells/conjuration/force_lance.png" },
    { "id": "proj_count", "name": "Split Barrel", "desc": "Every volley fires one more projectile.",
        "key": "proj_count", "amounts": [null, null, null, 1], "weight": 2, "icon": "gui/spells/conjuration/dazzling_spray.png" },
    { "id": "max_hp", "name": "Thick Hide", "desc": "Raise your maximum health.",
        "key": "max_hp", "amounts": [8, 14, 22, 32], "weight": 10, "icon": "gui/spells/enchantment/enslavement_new.png" },
    { "id": "armor", "name": "Plating", "desc": "Reduce the damage of every hit taken.",
        "key": "armor", "amounts": [1, 2, 3, 4], "weight": 8, "icon": "gui/spells/stonemail.png" },
    { "id": "dodge", "name": "Light Feet", "desc": "A chance to avoid a hit entirely.",
        "key": "dodge", "amounts": [0.03, 0.05, 0.08, 0.12], "weight": 7, "icon": "gui/spells/translocation/blink.png" },
    { "id": "regen", "name": "Mending", "desc": "Slowly recover health over time.",
        "key": "regen", "amounts": [0.3, 0.6, 1.0, 1.5], "weight": 7, "icon": "gui/spells/necromancy/regeneration_new.png" },
    { "id": "speed", "name": "Sprinter", "desc": "Move faster.",
        "key": "speed", "amounts": PCT, "weight": 8, "icon": "gui/spells/air/swiftness_new.png" },
    { "id": "range", "name": "Long Barrel", "desc": "Projectiles travel further.",
        "key": "range", "amounts": PCT, "weight": 7, "icon": "gui/spells/conjuration/searing_ray.png" },
    { "id": "potency", "name": "Catalyst", "desc": "Elemental reactions hit harder.",
        "key": "potency", "amounts": PCT, "weight": 8, "icon": "gui/spells/conjuration/orb_of_destruction.png" },
    { "id": "state_duration", "name": "Lingering", "desc": "Elements cling to enemies for longer.",
        "key": "state_duration", "amounts": PCT, "weight": 6, "icon": "gui/spells/enchantment/extension.png" },
    { "id": "chain_jumps", "name": "Conductor", "desc": "Chains leap to one more enemy.",
        "key": "chain_jumps", "amounts": [null, null, 1, null], "weight": 3, "icon": "gui/spells/air/chain_lightning_new.png" },
    { "id": "lifesteal", "name": "Leech", "desc": "Heal whenever you cause a reaction, up to three times a second.",
        "key": "lifesteal", "amounts": [null, null, 1, 2], "weight": 4, "icon": "gui/spells/necromancy/vampiric_draining_new.png" },
    { "id": "thorns", "name": "Spikes", "desc": "Enemies that hit you take damage back.",
        "key": "thorns", "amounts": [2, 4, 7, 10], "weight": 6, "icon": "gui/spells/earth/lehudibs_crystal_spear_old.png" },
    { "id": "scrap_gain", "name": "Scavenger", "desc": "Pick up more scrap from every drop.",
        "key": "scrap_gain", "amounts": PCT, "weight": 7, "icon": "item/gold/gold_pile_16.png" },
    { "id": "luck", "name": "Fortune", "desc": "Better odds of rare finds and upgrades.",
        "key": "luck", "amounts": [0.05, 0.10, 0.15, null], "weight": 5, "icon": "item/misc/misc_deck_legendary_new.png" },
    { "id": "pressure_limit", "name": "Reinforced Tank", "desc": "A bigger tank: your vent can charge further.",
        "key": "pressure_limit", "amounts": [6, 10, 15, 22], "weight": 6, "icon": "gui/invocations/gozag_potion_petition.png" },
    { "id": "vent_charge", "name": "Bellows", "desc": "Your vent charges faster.",
        "key": "vent_charge", "amounts": PCT, "weight": 6, "icon": "gui/spells/fire/flame_tongue_new.png" },
    { "id": "vent_radius", "name": "Wide Vent", "desc": "Your vent blast reaches further.",
        "key": "vent_radius", "amounts": PCT, "weight": 6, "icon": "gui/spells/fire/ring_of_flames_new.png" },
    { "id": "carry", "name": "Deep Pockets", "desc": "Carry one more item.",
        "key": "carry", "amounts": [null, null, 1, null], "weight": 3, "icon": "gui/spells/translocation/apportation_new.png" },
    { "id": "xp_gain", "name": "Studious", "desc": "Gain experience faster.",
        "key": "xp_gain", "amounts": PCT, "weight": 6, "icon": "gui/spells/memorise.png" },
    { "id": "proj_speed", "name": "Hot Load", "desc": "Projectiles fly faster.",
        "key": "proj_speed", "amounts": PCT, "weight": 5, "icon": "gui/spells/fire/bolt_of_fire_new.png" },
    { "id": "vent_power", "name": "Blowback", "desc": "Your vent blast hits harder.",
        "key": "vent_power", "amounts": PCT, "weight": 5, "icon": "gui/spells/fire/fire_storm_new.png" },
]

static var _expanded: Array = []


## Every concrete option: one per CATALOG entry and available rarity.
static func options() -> Array:
    if not _expanded.is_empty():
        return _expanded
    for base in CATALOG:
        var amounts: Array = base["amounts"]
        for r in amounts.size():
            if amounts[r] == null:
                continue
            var opt: Dictionary = {
                "id": "%s_%d" % [base["id"], r], "base": base["id"], "name": base["name"],
                "desc": base["desc"], "key": base["key"], "amount": amounts[r],
                "weight": base["weight"], "icon": base["icon"], "rarity": r,
            }
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


## `count` options on distinct stats. Each rolls a rarity from the player's level and
## luck, then an option of that rarity is picked by weight (falling back one rarity at a
## time when nothing of that rarity is left).
static func roll(player, count: int) -> Array:
    var level := 1
    var luck := 0.0
    if player != null and is_instance_valid(player):
        level = int(player.level)
        luck = float(player.stat("luck"))
    var used: Dictionary = {}
    var picked: Array = []
    while picked.size() < count:
        var rarity := roll_rarity(level, luck)
        var chosen: Dictionary = {}
        for r in range(rarity, -1, -1):
            var pool: Array = options().filter(func(o): return int(o["rarity"]) == r and not used.has(o["base"]))
            if not pool.is_empty():
                chosen = _weighted(pool)
                break
        if chosen.is_empty():
            break
        used[chosen["base"]] = true
        picked.append(chosen.duplicate(true))
    return picked


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


## The numeric effect in a few words, e.g. "+8% damage" or "+15 max health".
static func describe(opt: Dictionary) -> String:
    var key: String = opt.get("key", "")
    var amount = opt.get("amount", 0)
    var stat: String = STAT_LABELS.get(key, key)
    if key in PERCENT_KEYS:
        return "+%s%% %s" % [_num(float(amount) * 100.0), stat]
    match key:
        "crit_dmg":
            return "+%sx %s" % [_num(float(amount)), stat]
        "regen":
            return "+%s %s / s" % [_num(float(amount)), stat]
        "proj_count", "chain_jumps", "bounce":
            var n := int(amount)
            return "+%d %s" % [n, stat if n == 1 else stat + "s"]
    return "+%s %s" % [_num(float(amount)), stat]


## Icon tint for an option, by stat family.
## The option's icon texture; a 1-bit cog if its path is missing.
static func icon(opt: Dictionary) -> Texture2D:
    return Art.icon(String(opt.get("icon", "")), Vector2i(45, 16))


## Accent colour of a stat (the icons themselves are drawn untinted).
static func tint(opt: Dictionary) -> Color:
    return KEY_TINTS.get(opt.get("key", ""), Color(0.90, 0.86, 0.78))


## Rare or better options get a highlight on their card.
static func is_rare(opt: Dictionary) -> bool:
    return int(opt.get("rarity", COMMON)) >= RARE


static func _num(v: float) -> String:
    if is_equal_approx(v, roundf(v)):
        return str(int(roundf(v)))
    return String.num(v, 2)
