class_name LevelUps
extends RefCounted
## In-run level-up upgrades: pick one of three on each level, Brotato style.
##
## An option is data: { id, name, desc, key, amount, weight, icon }. `key` is a stat key
## from the Items mod vocabulary (see items.gd), plus "bounce" (projectile bounces, int)
## and "xp_gain" (fraction). `amount` is a fraction for percentage stats (0.08 = +8%) and
## an int (or hp/s for regen) for flat stats. `weight` is how often it is offered relative
## to the others; `icon` is a coordinate on the Kenney 1-bit sheet (Art.tile).

## Keys whose amount is a fraction and reads as a percentage.
const PERCENT_KEYS := [
    "dmg", "fire_rate", "crit", "dodge", "speed", "range", "potency", "state_duration",
    "scrap_gain", "pressure_decay", "vent_radius", "vent_power", "xp_gain", "proj_speed",
    "focus_gain",
]

## Short stat names used by `describe`.
const STAT_LABELS := {
    "dmg": "damage", "fire_rate": "attack speed", "crit": "crit chance",
    "crit_dmg": "crit damage", "bounce": "bounce", "pierce": "pierce",
    "proj_count": "projectile", "max_hp": "max health", "armor": "armour",
    "dodge": "dodge", "regen": "regeneration", "speed": "move speed", "range": "range",
    "potency": "reaction potency", "state_duration": "element duration",
    "chain_jumps": "chain jump", "lifesteal": "lifesteal", "thorns": "thorns",
    "scrap_gain": "scrap gain", "pressure_limit": "pressure limit",
    "pressure_decay": "pressure decay", "vent_radius": "vent radius", "carry": "carry",
    "xp_gain": "XP gain", "proj_speed": "projectile speed", "vent_power": "vent power",
    "focus_gain": "focus gain",
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
    "scrap_gain": ECONOMY, "carry": ECONOMY, "xp_gain": ECONOMY,
    "pressure_limit": PRESSURE, "pressure_decay": PRESSURE, "vent_radius": PRESSURE,
    "vent_power": PRESSURE, "focus_gain": PRESSURE,
}

## Weights: 10 common, 6 uncommon, 3 rare, 1 very rare.
const CATALOG: Array = [
    { "id": "damage", "name": "Sharpened", "desc": "Every shot hits a little harder.",
        "key": "dmg", "amount": 0.08, "weight": 10, "icon": Vector2i(32, 6) },
    { "id": "attack_speed", "name": "Quick Trigger", "desc": "Fire faster with every gun.",
        "key": "fire_rate", "amount": 0.08, "weight": 10, "icon": Vector2i(38, 9) },
    { "id": "crit", "name": "Keen Eye", "desc": "More shots land as critical hits.",
        "key": "crit", "amount": 0.05, "weight": 8, "icon": Vector2i(36, 4) },
    { "id": "crit_dmg", "name": "Cruelty", "desc": "Critical hits deal extra damage.",
        "key": "crit_dmg", "amount": 0.25, "weight": 6, "icon": Vector2i(34, 2) },
    { "id": "bounce", "name": "Ricochet", "desc": "Projectiles bounce to another target.",
        "key": "bounce", "amount": 1, "weight": 3, "icon": Vector2i(35, 2) },
    { "id": "pierce", "name": "Piercing Rounds", "desc": "Projectiles pass through one more enemy.",
        "key": "pierce", "amount": 1, "weight": 3, "icon": Vector2i(32, 2) },
    { "id": "proj_count", "name": "Split Barrel", "desc": "Every volley fires one more projectile.",
        "key": "proj_count", "amount": 1, "weight": 1, "icon": Vector2i(43, 9) },
    { "id": "max_hp", "name": "Thick Hide", "desc": "Raise your maximum health.",
        "key": "max_hp", "amount": 15, "weight": 10, "icon": Vector2i(40, 11) },
    { "id": "armor", "name": "Plating", "desc": "Reduce the damage of every hit taken.",
        "key": "armor", "amount": 1, "weight": 8, "icon": Vector2i(35, 1) },
    { "id": "dodge", "name": "Light Feet", "desc": "A chance to avoid a hit entirely.",
        "key": "dodge", "amount": 0.04, "weight": 7, "icon": Vector2i(41, 1) },
    { "id": "regen", "name": "Mending", "desc": "Slowly recover health over time.",
        "key": "regen", "amount": 0.5, "weight": 7, "icon": Vector2i(39, 11) },
    { "id": "speed", "name": "Sprinter", "desc": "Move faster.",
        "key": "speed", "amount": 0.06, "weight": 8, "icon": Vector2i(40, 0) },
    { "id": "range", "name": "Long Barrel", "desc": "Projectiles travel further.",
        "key": "range", "amount": 0.10, "weight": 7, "icon": Vector2i(42, 9) },
    { "id": "potency", "name": "Catalyst", "desc": "Elemental reactions hit harder.",
        "key": "potency", "amount": 0.10, "weight": 8, "icon": Vector2i(33, 4) },
    { "id": "state_duration", "name": "Lingering", "desc": "Elements cling to enemies for longer.",
        "key": "state_duration", "amount": 0.15, "weight": 6, "icon": Vector2i(39, 9) },
    { "id": "chain_jumps", "name": "Conductor", "desc": "Chains leap to one more enemy.",
        "key": "chain_jumps", "amount": 1, "weight": 4, "icon": Vector2i(35, 3) },
    { "id": "lifesteal", "name": "Leech", "desc": "Heal whenever you cause a reaction.",
        "key": "lifesteal", "amount": 1, "weight": 4, "icon": Vector2i(43, 7) },
    { "id": "thorns", "name": "Spikes", "desc": "Enemies that hit you take damage back.",
        "key": "thorns", "amount": 3, "weight": 6, "icon": Vector2i(33, 0) },
    { "id": "scrap_gain", "name": "Scavenger", "desc": "Pick up more scrap from every drop.",
        "key": "scrap_gain", "amount": 0.10, "weight": 7, "icon": Vector2i(45, 16) },
    { "id": "pressure_limit", "name": "Reinforced Tank", "desc": "Hold more pressure before overheating.",
        "key": "pressure_limit", "amount": 15, "weight": 6, "icon": Vector2i(44, 9) },
    { "id": "pressure_decay", "name": "Heat Sink", "desc": "Pressure bleeds off faster.",
        "key": "pressure_decay", "amount": 0.15, "weight": 6, "icon": Vector2i(41, 9) },
    { "id": "vent_radius", "name": "Wide Vent", "desc": "Your vent blast reaches further.",
        "key": "vent_radius", "amount": 0.15, "weight": 6, "icon": Vector2i(34, 5) },
    { "id": "carry", "name": "Deep Pockets", "desc": "Carry one more item.",
        "key": "carry", "amount": 1, "weight": 3, "icon": Vector2i(47, 4) },
    { "id": "xp_gain", "name": "Studious", "desc": "Gain experience faster.",
        "key": "xp_gain", "amount": 0.10, "weight": 6, "icon": Vector2i(28, 12) },
    { "id": "proj_speed", "name": "Hot Load", "desc": "Projectiles fly faster.",
        "key": "proj_speed", "amount": 0.12, "weight": 5, "icon": Vector2i(37, 9) },
    { "id": "vent_power", "name": "Blowback", "desc": "Your vent blast hits harder.",
        "key": "vent_power", "amount": 0.15, "weight": 5, "icon": Vector2i(44, 6) },
]


## `count` distinct options chosen by weight. `player` is reserved for future biasing.
static func roll(player, count: int) -> Array:
    var pool: Array = CATALOG.duplicate()
    var picked: Array = []
    while picked.size() < count and not pool.is_empty():
        var total := 0.0
        for opt in pool:
            total += float(opt["weight"])
        var r := randf() * total
        var index := pool.size() - 1
        for i in pool.size():
            r -= float(pool[i]["weight"])
            if r < 0.0:
                index = i
                break
        picked.append((pool[index] as Dictionary).duplicate(true))
        pool.remove_at(index)
    return picked


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
static func tint(opt: Dictionary) -> Color:
    return KEY_TINTS.get(opt.get("key", ""), Color(0.90, 0.86, 0.78))


## Rare options (low weight) get a highlight colour on their card.
static func is_rare(opt: Dictionary) -> bool:
    return int(opt.get("weight", 10)) <= 3


static func _num(v: float) -> String:
    if is_equal_approx(v, roundf(v)):
        return str(int(roundf(v)))
    return String.num(v, 2)
