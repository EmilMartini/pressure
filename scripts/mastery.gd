extends Node
## Autoload "Mastery": the Shrine. Runs pay Embers for how well they were played, and
## Embers buy ranks on a board of eleven talent slots plus a short survival track.
##
## Why it looks like this (reports/Roguelite meta progression analysis.md, R4 to R7):
## the old 212-node tree sold +21% damage, +12% fire rate, +32 max HP and +6 armour, and
## a bot probe with it bought reached floor 2 in every run at 120-147 HP while two of
## three naked runs died on floor 1. Hades keeps its combat talents to a cheap core of
## swappable A/B pairs, Dead Cells caps permanent power at four flask charges, and Risk
## of Rain 2 sells no stats at all. So:
##   R4  Eleven slots, each an exclusive pair: side A or side B is active, switching is
##       free (in the Shrine, between runs), each side has its own 2 to 3 ranks, and a
##       full refund costs nothing. Most pairs are sidegrades or agency, not damage.
##   R5  A capped survival track (Last Breath, 3 ranks): cheap first rank, dear later.
##   R6  The twelve element-damage branches are gone. Two slots are element sidegrades
##       (ice or acid, holy or void) that only open once a gun of that element is
##       unlocked.
##   R7  Embers pay for rooms cleared, elites, first-ever reactions, boss kills and
##       first-kill bounties per boss kind and class; depth is a small part.
##
## Power budget (GDD target pacing: meta stat power at most +10% damage and +20 max HP).
## Every side carries `eq`: its damage-equivalent fraction and HP-equivalent at max rank,
## converted with factors measured from the mastery-free bot telemetry (runs.jsonl,
## build 2026.11.05, 2,018 damage_dealt and 500 damage_taken events):
##   REACTION_SHARE 0.49  reactions dealt 98,055 of 201,824 damage, so +x potency ~ +0.49x
##   VENT_SHARE     0.126 player-sourced damage (vents) was 25,396 of 201,824
##   HIGH_HP_SHARE  0.44  median share of wave samples at >= 80% HP (20 runs with 5+ waves)
##   DAMAGE_PER_FLOOR 150 floor-1 deaths took 100-222 damage in 9-31 hits (about 6.5 each)
##   DURATION_TO_DMG 0.15 assumed, not measured: longer states only matter when a second
##                        element lands in the extra time
## Economy and agency sides (scrap, luck, rerolls, choices, carry, map reveals) count as
## zero stat power; they change options, not numbers. `max_power()` sums the larger side
## of every slot, so it is an upper bound: dmg +9.7%, HP +15 (see the table in GDD.md).
## The old tree at completion, by the same factors: +21% dmg +12% fire rate +7 pp crit
## (+40% before projectiles, pierce and the 12 element branches) and +32 HP + 6 armour
## (6 armour alone turned the measured ~6.5 average hit into ~1.5-2.7).

signal changed

const SAVE_PATH := "user://mastery.json"
const SAVE_VERSION := 2

## Old saves had mastery points (1 per floor reached, 1 per 150 kills, 3 per win). One
## point was about one floor of play; a floor now pays about 8 Embers (5 rooms, an
## elite, the floor bonus), so every point ever earned converts to 8 Embers and the old
## tree is fully refunded, as Hades' Patch 040 refunded over-investment when it moved
## to A/B pairs.
const LEGACY_EMBERS_PER_POINT := 8

## Measured conversion factors for the power budget (see the header).
const REACTION_SHARE := 0.49
const VENT_SHARE := 0.126
const HIGH_HP_SHARE := 0.44
const DAMAGE_PER_FLOOR := 150.0
const DURATION_TO_DMG := 0.15

# --- Embers (R7) -------------------------------------------------------------
# Scale: one cleared room = 1 Ember, the way a Hades chamber pays 10 Darkness, so Hades
# prices divide by 10 (Death Defiance 30/500/1,000 Darkness -> Last Breath 3/50/100).
#   rooms       1 per room cleared: the basic unit of play quality.
#   elites      2 each: a Hades skull chamber pays double a normal one.
#   discoveries 3 per reaction fired for the first time ever on this save: discovery is
#               what the early game should teach, and it front-loads income (65
#               reactions, 195 Embers in all, most of it in the first runs).
#   bosses      3 per boss kill: Hades bosses drop 50-250 Darkness when no bounty is due.
#   bounties    12 the first time a boss kind dies to a class (5 kinds x 13 classes),
#               Hades' first-kill-per-weapon reward: rotating classes pays.
#   floors      2 per floor reached beyond the first: depth matters, but a floor of play
#               (about 5 rooms and an elite) is worth more than the stairs.
#   win         10 for clearing the dungeon.
# Worked example, two floor-1 deaths on a save that already knows the base reactions:
#   bad:  1 room, no elites, nothing new           = 1 Ember
#   good: 5 rooms, 2 elites, 2 new reactions       = 5 + 4 + 6 = 15 Embers
# The old formula paid both runs 1 point.
#   fusions     4 per fusion (tier 3) set off for the first time ever, 6 per cataclysm
#   cataclysms  (tier 4). There are 220 and 176 of them (1,936 Embers, twice the whole
#               Shrine), so together they pay at most FUSION_PAY_CAP a run: about one more
#               good floor. A fusion build earns its Shrine a little faster, never a lot.
#
# Phase 3 retune (World and progression GDD, section 13 proposal): with the values above two
# bot wins bought the whole Shrine (elites alone paid 336 to 362 of a win). Now rooms 1,
# elites 1 for at most ELITE_PAY_CAP a run, first discoveries 2, the fusion ladder at most
# FUSION_PAY_CAP a run, bosses 3, bounties 5, each floor past the first 3, a win 20.
const PAY := { "rooms": 1, "elites": 1, "discoveries": 2, "fusions": 2, "cataclysms": 3, "bosses": 3, "bounties": 5, "floors": 3, "win": 20 }
const ELITE_PAY_CAP := 10
const PAY_ORDER := ["rooms", "elites", "discoveries", "fusions", "cataclysms", "bosses", "bounties", "floors", "win"]
const FUSION_PAY_CAP := 6
const PAY_WORDS := {
    "rooms": "rooms", "elites": "elites", "discoveries": "new reactions", "fusions": "new fusions",
    "cataclysms": "new cataclysms", "bosses": "bosses",
    "bounties": "bounties", "floors": "depth", "win": "clear", "legacy": "old mastery",
}

const EMBER_COLOR := Color(1.0, 0.6, 0.25)
const EMBER_ICON := "gui/spells/fire/inner_flame.png"

# --- Survival (R5) -----------------------------------------------------------
# Last Breath: each rank is one revive per run. Costs are Hades' Death Defiance
# 30/500/1,000 Darkness at 1 Ember = 10 Darkness; Dead Cells' flasks (5/50/150/300 cells)
# have the same shape: the first charge almost free, the last ones a long-term goal.
# A revive restores 25% of max HP (Death Defiance gives 50%): Pressure's stairs already
# heal to 60% / 40% each floor, and 25 HP is about four of the measured 6.5 HP hits.
# Two seconds of invulnerability keep the revive from being eaten on the spot.
const SURVIVAL := {
    "id": "last_breath", "name": "Last Breath",
    "desc": "When you would fall, stand back up once.",
    "icon": "gui/spells/necromancy/deaths_door_new.png",
    "costs": [3, 50, 100],
}
const REVIVE_FRACTION := 0.25
const REVIVE_INVULN := 2.0

# --- Talent slots (R4, R6) -----------------------------------------------------
# A side is { id, name, desc, icon, costs, per_rank | ranks, cond?, requires?, eq }.
#   per_rank: mods added once per rank (Items stat vocabulary, or a meta key below).
#   ranks:    a list of mods, one per rank, summed up to the current rank.
#   cond:     an Items player condition; the mods only hold while it does.
#   requires: an element key; the side can only be bought once a gun of it is unlocked.
#   eq:       [damage-equivalent fraction, HP-equivalent] at max rank (budget only).
# Meta keys (read by the systems they change, never by Player.stat users):
#   levelup_rerolls  rerolls of the level-up offer per run (LevelUpScreen)
#   levelup_extra    1: a fourth level-up card every other level-up, 2: every level-up
#   free_gunsmith    the gunsmith of floors 1..N costs nothing (FloorGen)
#   reveal_rooms     1 shop, 2 + treasure, 3 + boss shown on the map at floor start (Main)
#   reveal_secrets   1 hidden rooms, 2 + puzzle and alcove rooms shown on the map (Main)
# Cost ladders: power sides [4, 10, 20], comfort sides [3, 8, 16], two-rank sides
# [6, 16] or dearer, agency at the top (Hades' Fated rerolls are 59% of its Mirror;
# here rerolls and the extra choice are 190 of 775 Embers, about a quarter, so the
# board completes in dozens of runs, not hundreds).
const SLOTS := [
    { "id": "sights", "name": "Sights",
        # Reach versus travel time; neither adds damage (old tree: +13% range).
        "a": { "id": "long_barrel", "name": "Long Barrel", "desc": "Shots carry further.",
            "icon": "gui/spells/divination/forescry.png", "per_rank": { "range": 0.04 },
            "costs": [3, 8, 16], "eq": [0.0, 0.0] },
        "b": { "id": "hot_load", "name": "Hot Load", "desc": "Shots fly faster and land sooner.",
            "icon": "gui/spells/conjuration/magic_dart.png", "per_rank": { "proj_speed": 0.05 },
            "costs": [3, 8, 16], "eq": [0.0, 0.0] } },
    { "id": "catalyst", "name": "Catalyst",
        # Potency vs duration. 4.5% potency x 0.49 = 2.2%; 12% duration x 0.15 = 1.8%.
        "a": { "id": "catalyst", "name": "Catalyst", "desc": "Reactions hit harder.",
            "icon": "gui/spells/transmutation/irradiate.png", "per_rank": { "potency": 0.015 },
            "costs": [4, 10, 20], "eq": [0.022, 0.0] },
        "b": { "id": "lingering", "name": "Lingering Touch", "desc": "Elements cling to enemies for longer.",
            "icon": "gui/spells/enchantment/extension.png", "per_rank": { "state_duration": 0.04 },
            "costs": [4, 10, 20], "eq": [0.018, 0.0] } },
    { "id": "nerve", "name": "Nerve",
        # Hades' Thick Skin vs High Confidence. +12 HP; 4.5% x 0.44 time at >= 80% = 2.0%.
        "a": { "id": "thick_skin", "name": "Thick Skin", "desc": "A little more blood to lose.",
            "icon": "gui/spells/earth/stoneskin_new.png", "per_rank": { "max_hp": 4 },
            "costs": [4, 10, 20], "eq": [0.0, 12.0] },
        "b": { "id": "high_confidence", "name": "High Confidence", "desc": "Hit harder while you are healthy.",
            "icon": "gui/spells/enchantment/berserker_rage_new.png", "per_rank": { "dmg": 0.015 },
            "cond": "high_hp", "costs": [4, 10, 20], "eq": [0.02, 0.0] } },
    { "id": "vent", "name": "Vent",
        # Capacity vs power. +12 capacity is +12% vent strength only with a full gauge;
        # +12% power always. Both x 0.126 vent share = 1.5%.
        "a": { "id": "tank", "name": "Reinforced Tank", "desc": "A bigger tank: vents can charge further.",
            "icon": "gui/invocations/gozag_potion_petition.png", "per_rank": { "pressure_limit": 4 },
            "costs": [4, 10, 20], "eq": [0.015, 0.0] },
        "b": { "id": "hard_vent", "name": "Hard Vent", "desc": "Vents hit harder and reach further.",
            "icon": "gui/spells/fire/fire_storm_new.png", "per_rank": { "vent_power": 0.04 },
            "costs": [4, 10, 20], "eq": [0.015, 0.0] } },
    { "id": "footwork", "name": "Footwork",
        # Speed vs dodge. 2% dodge x 150 damage per floor = 3 HP-equivalent.
        "a": { "id": "light_feet", "name": "Light Feet", "desc": "Move faster.",
            "icon": "gui/spells/air/swiftness_new.png", "per_rank": { "speed": 0.02 },
            "costs": [3, 8, 16], "eq": [0.0, 0.0] },
        "b": { "id": "sidestep", "name": "Sidestep", "desc": "Sometimes a hit just misses.",
            "icon": "gui/skills/dodging.png", "per_rank": { "dodge": 0.01 },
            "costs": [6, 16], "eq": [0.0, 3.0] } },
    { "id": "salvage", "name": "Salvage",
        # Scrap vs rerolling the level-up offer: economy vs agency (old tree: +17% scrap).
        "a": { "id": "salvager", "name": "Salvager", "desc": "Strip more scrap from every wreck.",
            "icon": "gui/invocations/gozag_call_merchant.png", "per_rank": { "scrap_gain": 0.04 },
            "costs": [3, 8, 16], "eq": [0.0, 0.0] },
        "b": { "id": "second_thoughts", "name": "Second Thoughts", "desc": "Reroll a level-up offer.",
            "icon": "gui/spells/enchantment/selective_amnesia.png", "per_rank": { "levelup_rerolls": 1 },
            "costs": [10, 25, 45], "eq": [0.0, 0.0] } },
    { "id": "fortune", "name": "Fortune",
        # Luck vs a fourth level-up card: better odds or more options.
        "a": { "id": "lucky_coin", "name": "Lucky Coin", "desc": "Rarer gear and level-ups turn up.",
            "icon": "gui/invocations/gozag_bribe_branch.png", "per_rank": { "luck": 0.04 },
            "costs": [4, 10, 20], "eq": [0.0, 0.0] },
        "b": { "id": "wider_choice", "name": "Wider Choice", "desc": "Level-ups offer a fourth card.",
            "icon": "gui/spells/divination/identify.png", "per_rank": { "levelup_extra": 1 },
            "costs": [35, 75], "eq": [0.0, 0.0] } },
    { "id": "pack", "name": "Pack",
        # Carry vs a gun tier banked at the shop (a gunsmith visit is 65 / 85 scrap).
        "a": { "id": "deep_pockets", "name": "Deep Pockets", "desc": "Carry heavier guns.",
            "icon": "gui/spells/translocation/apportation_new.png", "per_rank": { "carry": 1 },
            "costs": [8, 20], "eq": [0.0, 0.0] },
        "b": { "id": "heirloom", "name": "Heirloom", "desc": "The gunsmith raises a gun for free.",
            "icon": "gui/invocations/kiku_bless_weapon.png", "per_rank": { "free_gunsmith": 1 },
            "costs": [10, 25], "eq": [0.0, 0.0] } },
    { "id": "scout", "name": "Scout",
        # Knowing the floor vs knowing its secrets: pure information.
        "a": { "id": "cartographer", "name": "Cartographer", "desc": "Key rooms show on the map.",
            "icon": "gui/spells/divination/magic_mapping.png", "per_rank": { "reveal_rooms": 1 },
            "costs": [3, 6, 12], "eq": [0.0, 0.0] },
        "b": { "id": "dowser", "name": "Dowser", "desc": "Hidden places show on the map.",
            "icon": "gui/spells/divination/detect_secret_doors.png", "per_rank": { "reveal_secrets": 1 },
            "costs": [6, 15], "eq": [0.0, 0.0] } },
    { "id": "bite", "name": "Bite",
        # R6: element sidegrades for the first two elements the challenges hand out.
        # 3% of that element's damage + 2% potency x 0.49 = 4% of its share. Shares of
        # the arsenal sum to 1, so both element slots together add at most 4%.
        "a": { "id": "rime", "name": "Rime", "desc": "Ice guns fire faster and freeze harder.",
            "icon": "gui/spells/ice/throw_icicle_new.png", "requires": "ice",
            "ranks": [{ "fire_rate_ice": 0.03 }, { "potency_ice": 0.02 }],
            "costs": [8, 20], "eq": [0.04, 0.0] },
        "b": { "id": "etch", "name": "Etch", "desc": "Acid guns bite deeper.",
            "icon": "gui/spells/poison/poisonous_cloud_new.png", "requires": "acid",
            "ranks": [{ "dmg_acid": 0.03 }, { "potency_acid": 0.02 }],
            "costs": [8, 20], "eq": [0.04, 0.0] } },
    { "id": "twilight", "name": "Twilight",
        # R6: the same shape for the last two elements, holy and void (shares as above).
        "a": { "id": "halo", "name": "Halo", "desc": "Holy guns burn brighter.",
            "icon": "gui/invocations/tso_bless_weapon.png", "requires": "holy",
            "ranks": [{ "dmg_holy": 0.03 }, { "potency_holy": 0.02 }],
            "costs": [8, 20], "eq": [0.04, 0.0] },
        "b": { "id": "hollow", "name": "Hollow", "desc": "Void guns fire faster and pull harder.",
            "icon": "gui/spells/enchantment/darkness.png", "requires": "void",
            "ranks": [{ "fire_rate_void": 0.03 }, { "potency_void": 0.02 }],
            "costs": [8, 20], "eq": [0.04, 0.0] } },
]

## Keys that are not player stats (see above).
const META_KEYS := ["levelup_rerolls", "levelup_extra", "free_gunsmith", "reveal_rooms", "reveal_secrets"]
## Stats counted in whole units rather than fractions.
const INT_KEYS := ["max_hp", "armor", "pierce", "carry", "chain_jumps", "bounce", "pressure_limit", "thorns", "proj_count", "lifesteal"]
const STAT_WORDS := {
    "dmg": "damage", "fire_rate": "fire rate", "crit": "crit chance", "max_hp": "max HP",
    "dodge": "dodge", "speed": "move speed", "range": "range", "proj_speed": "shot speed",
    "potency": "reaction potency", "state_duration": "element duration",
    "pressure_limit": "vent capacity", "vent_power": "vent power", "vent_radius": "vent radius",
    "vent_charge": "vent charge speed", "scrap_gain": "scrap", "luck": "luck", "carry": "carry",
    "xp_gain": "XP gain", "armor": "armour",
}
const COND_WORDS := { "high_hp": "while at 80%+ HP", "low_hp": "while below 40% HP", "hot": "while hot", "cold": "while cold" }

var save_path := SAVE_PATH
var embers := 0                       # unspent
var earned := 0                       # lifetime total
var ranks: Dictionary = {}            # "slot:a" / "slot:b" -> rank bought
var active: Dictionary = {}           # slot id -> "a" or "b"
var survival := 0                     # Last Breath ranks bought
var bounties: Dictionary = {}         # "class|boss kind" -> true once paid
var earned_by: Dictionary = {}        # PAY_ORDER key (or "legacy") -> lifetime Embers
var last_award: Dictionary = {}       # the last run's payout: { total, parts, counts, bounties }
var _totals: Dictionary = {}          # key -> summed amount over active sides (no condition)
var _cond: Dictionary = {}            # condition -> { key -> amount }
var _slot_index: Dictionary = {}      # slot id -> index in SLOTS
var _quiet := false                   # balance probes buy without logging hub events


func _init() -> void:
    for i in SLOTS.size():
        _slot_index[String(SLOTS[i]["id"])] = i


func _ready() -> void:
    # Bot runs never touch the player's Shrine (main.gd / hub.gd reset this file later).
    if Main.bot_run():
        save_path = "user://mastery_autotest%s.json" % Main._instance_tag()
    load_save()


# --- Queries ---------------------------------------------------------------


func slots() -> Array:
    return SLOTS


func slot(slot_id: String) -> Dictionary:
    if not _slot_index.has(slot_id):
        return {}
    return SLOTS[int(_slot_index[slot_id])]


## The side definition ("a" or "b") of a slot.
func side(slot_id: String, s: String) -> Dictionary:
    var sl := slot(slot_id)
    if sl.is_empty():
        return {}
    return sl.get(s, {})


func rank(slot_id: String, s: String) -> int:
    return int(ranks.get("%s:%s" % [slot_id, s], 0))


func max_rank(slot_id: String, s: String) -> int:
    return (side(slot_id, s).get("costs", []) as Array).size()


func active_side(slot_id: String) -> String:
    return String(active.get(slot_id, "a"))


func other_side(s: String) -> String:
    return "b" if s == "a" else "a"


## Whether a side can be bought at all: element sidegrades need a gun of that element
## in the unlocked pool (R6).
func is_available(slot_id: String, s: String) -> bool:
    var el := String(side(slot_id, s).get("requires", ""))
    return el == "" or element_unlocked(el)


func element_unlocked(el: String) -> bool:
    for gid in Guns.ids():
        if String(Element.NAMES[Guns.make(String(gid)).element]).to_lower() == el:
            return true
    return false


## "Needs an Ice gun" for a locked element side, else "".
func requirement_text(slot_id: String, s: String) -> String:
    var el := String(side(slot_id, s).get("requires", ""))
    if el == "" or element_unlocked(el):
        return ""
    var article := "an" if el in ["ice", "acid", "oil"] else "a"
    return "Needs %s %s gun" % [article, el.capitalize()]


## Embers for the next rank of a side, or -1 when it is maxed.
func next_cost(slot_id: String, s: String) -> int:
    var costs: Array = side(slot_id, s).get("costs", [])
    var r := rank(slot_id, s)
    if r >= costs.size():
        return -1
    return int(costs[r])


func can_buy(slot_id: String, s: String) -> bool:
    var c := next_cost(slot_id, s)
    return c >= 0 and embers >= c and is_available(slot_id, s)


func survival_max() -> int:
    return (SURVIVAL["costs"] as Array).size()


func survival_next_cost() -> int:
    if survival >= survival_max():
        return -1
    return int(SURVIVAL["costs"][survival])


func can_buy_survival() -> bool:
    var c := survival_next_cost()
    return c >= 0 and embers >= c


## Revives each player starts a run with.
func revives() -> int:
    return survival


## Summed bonus for a stat or meta key over the active sides (unconditional mods only).
## Cached; cheap to call every frame.
func bonus(key: String) -> float:
    return float(_totals.get(key, 0.0))


## Conditional bonus for `key` that holds for `player` right now (e.g. High Confidence).
func cond_bonus(key: String, player) -> float:
    if _cond.is_empty():
        return 0.0
    var v := 0.0
    for c in _cond.keys():
        var mods: Dictionary = _cond[c]
        if mods.has(key) and Items.condition(String(c), player, {}):
            v += float(mods[key])
    return v


## The mods a side gives at rank `r`.
func side_mods(slot_id: String, s: String, r: int) -> Dictionary:
    var d := side(slot_id, s)
    var out: Dictionary = {}
    if r <= 0 or d.is_empty():
        return out
    if d.has("ranks"):
        var list: Array = d["ranks"]
        for i in mini(r, list.size()):
            var m: Dictionary = list[i]
            for k in m.keys():
                out[k] = float(out.get(k, 0.0)) + float(m[k])
    else:
        var per: Dictionary = d.get("per_rank", {})
        for k in per.keys():
            out[k] = float(per[k]) * float(r)
    return out


## What a side does at rank `r`, in words: "+8 max HP", "+3% damage while at 80%+ HP".
func effect_text(slot_id: String, s: String, r: int) -> String:
    var d := side(slot_id, s)
    if r <= 0:
        return "not learned"
    var mods := side_mods(slot_id, s, r)
    var parts: Array = []
    for k in mods.keys():
        parts.append(_effect_part(String(k), mods[k]))
    var text := ", ".join(parts)
    var cond := String(d.get("cond", ""))
    if cond != "":
        text += " " + String(COND_WORDS.get(cond, cond))
    return text


func _effect_part(key: String, v: Variant) -> String:
    var n := int(roundf(float(v)))
    match key:
        "levelup_rerolls":
            return "%d level-up reroll%s per run" % [n, "" if n == 1 else "s"]
        "levelup_extra":
            return "a 4th level-up card every level-up" if n >= 2 else "a 4th level-up card every other level-up"
        "free_gunsmith":
            return "free gunsmith on floor 1" if n <= 1 else "free gunsmith on floors 1 to %d" % n
        "reveal_rooms":
            var reveal: Array = ["", "shop on the map", "shop and treasure on the map", "shop, treasure and boss on the map"]
            return String(reveal[clampi(n, 0, 3)])
        "reveal_secrets":
            return "hidden rooms on the map" if n <= 1 else "hidden rooms and puzzle rooms on the map"
    return _stat_text(key, v)


## A mods dictionary in words, e.g. "+2% damage, +4 max HP".
func mods_text(mods: Dictionary) -> String:
    var parts: Array = []
    for k in mods.keys():
        parts.append(_effect_part(String(k), mods[k]))
    return ", ".join(parts)


func _stat_text(key: String, v: Variant) -> String:
    var words := { "dmg_": "damage", "potency_": "potency", "fire_rate_": "fire rate" }
    for pre in words.keys():
        var p := String(pre)
        if key.begins_with(p):
            var el := key.substr(p.length()).capitalize()
            return "+%s%% %s %s" % [_num(float(v) * 100.0), el, String(words[pre])]
    var word := String(STAT_WORDS.get(key, key))
    if INT_KEYS.has(key):
        return "+%d %s" % [int(roundf(float(v))), word]
    return "+%s%% %s" % [_num(float(v) * 100.0), word]


func _num(v: float) -> String:
    if is_equal_approx(v, roundf(v)):
        return str(int(roundf(v)))
    return String.num(v, 1)


func talent_icon_path(slot_id: String, s: String) -> String:
    return String(side(slot_id, s).get("icon", ""))


func talent_icon(slot_id: String, s: String) -> Texture2D:
    return Art.icon(talent_icon_path(slot_id, s), Vector2i(28, 12))


func ember_icon() -> Texture2D:
    return Art.icon(EMBER_ICON, Vector2i(28, 12))


func survival_icon() -> Texture2D:
    return Art.icon(String(SURVIVAL["icon"]), Vector2i(28, 12))


## Embers spent on the board and the survival track.
func spent() -> int:
    var total := 0
    for sl in SLOTS:
        for s in ["a", "b"]:
            var costs: Array = sl[s]["costs"]
            for i in mini(rank(String(sl["id"]), s), costs.size()):
                total += int(costs[i])
    var sc: Array = SURVIVAL["costs"]
    for i in mini(survival, sc.size()):
        total += int(sc[i])
    return total


## Embers to buy every rank of every side and the whole survival track.
func total_cost() -> int:
    var total := 0
    for sl in SLOTS:
        for s in ["a", "b"]:
            for c in sl[s]["costs"]:
                total += int(c)
    for c in SURVIVAL["costs"]:
        total += int(c)
    return total


## Ranks bought over all sides, and the number of ranks that exist.
func ranks_bought() -> int:
    var n := 0
    for k in ranks.keys():
        n += int(ranks[k])
    return n


func ranks_total() -> int:
    var n := 0
    for sl in SLOTS:
        n += (sl["a"]["costs"] as Array).size() + (sl["b"]["costs"] as Array).size()
    return n


## The active side of every slot with at least one rank, for telemetry and the probe log.
func active_summary() -> Array:
    var out: Array = []
    for sl in SLOTS:
        var sid := String(sl["id"])
        var s := active_side(sid)
        var r := rank(sid, s)
        if r > 0:
            out.append({ "slot": sid, "side": s, "id": String(sl[s]["id"]), "rank": r })
    return out


## Upper bound on the board's stat power with every rank bought: the larger side of each
## slot, summed. { dmg: fraction, hp: HP-equivalent per floor }.
func max_power() -> Dictionary:
    var dmg := 0.0
    var hp := 0.0
    var el_eq := 0.0
    for sl in SLOTS:
        var ea: Array = sl["a"]["eq"]
        var eb: Array = sl["b"]["eq"]
        var best := maxf(float(ea[0]), float(eb[0]))
        if (sl["a"] as Dictionary).has("requires"):
            # Element slots: their shares of the arsenal sum to at most 1 (see SLOTS),
            # so together they add at most the largest one.
            el_eq = maxf(el_eq, best)
        else:
            dmg += best
        hp += maxf(float(ea[1]), float(eb[1]))
    return { "dmg": dmg + el_eq, "hp": hp }


## Stat power of what is active now, by the same factors (scaled by rank / max).
func current_power() -> Dictionary:
    var dmg := 0.0
    var hp := 0.0
    var el_eq := 0.0
    for sl in SLOTS:
        var sid := String(sl["id"])
        var s := active_side(sid)
        var m := max_rank(sid, s)
        if m <= 0:
            continue
        var f := float(rank(sid, s)) / float(m)
        var eq: Array = sl[s]["eq"]
        if (sl[s] as Dictionary).has("requires"):
            el_eq = maxf(el_eq, float(eq[0]) * f)
        else:
            dmg += float(eq[0]) * f
        hp += float(eq[1]) * f
    return { "dmg": dmg + el_eq, "hp": hp }


# --- Spending --------------------------------------------------------------


## Buy the next rank of a side. The active side does not change (switch with set_active).
func buy(slot_id: String, s: String) -> bool:
    if not can_buy(slot_id, s):
        return false
    var cost := next_cost(slot_id, s)
    embers -= cost
    ranks["%s:%s" % [slot_id, s]] = rank(slot_id, s) + 1
    _rebuild_totals()
    save()
    if not _quiet:
        Telemetry.hub_event("talent_buy", { "slot": slot_id, "side": s, "id": String(side(slot_id, s)["id"]), "rank": rank(slot_id, s), "cost": cost, "left": embers })
    changed.emit()
    return true


## Make side `s` the slot's active one. Free, any number of times (Hades' Mirror).
func set_active(slot_id: String, s: String) -> void:
    if slot(slot_id).is_empty() or not s in ["a", "b"] or active_side(slot_id) == s:
        return
    active[slot_id] = s
    _rebuild_totals()
    save()
    Telemetry.hub_event("talent_side", { "slot": slot_id, "side": s })
    changed.emit()


func toggle(slot_id: String) -> void:
    set_active(slot_id, other_side(active_side(slot_id)))


func buy_survival() -> bool:
    if not can_buy_survival():
        return false
    var cost := survival_next_cost()
    embers -= cost
    survival += 1
    save()
    if not _quiet:
        Telemetry.hub_event("survival_buy", { "rank": survival, "cost": cost, "left": embers })
    changed.emit()
    return true


## Refund every rank and the survival track, free (Hades charges a Key; the report's R4
## asks for free or cheap respec). Active sides stay as they were. Returns the refund.
func refund_all() -> int:
    var back := spent()
    embers += back
    ranks = {}
    survival = 0
    _rebuild_totals()
    save()
    Telemetry.hub_event("talent_refund", { "embers": back, "left": embers })
    changed.emit()
    return back


## Balance probe (`--mastery=full`): every rank of both sides and the whole survival track,
## element gates ignored, side `s` active everywhere.
func debug_max_all(s: String = "a") -> void:
    for sl in SLOTS:
        var sid := String(sl["id"])
        for k in ["a", "b"]:
            ranks["%s:%s" % [sid, k]] = (sl[k]["costs"] as Array).size()
        active[sid] = s
    survival = survival_max()
    _rebuild_totals()
    save()


## Balance probe (`--mastery=N`): spend `budget` Embers cheapest-first on the survival
## track and the active sides (element gates respected), the way a player who never
## switches sides would. Returns the Embers left over.
func debug_spend_greedy(budget: int, s: String = "a") -> int:
    embers = budget
    _quiet = true
    for sl in SLOTS:
        active[String(sl["id"])] = s
    _rebuild_totals()
    while true:
        var best_cost := -1
        var best_slot := ""
        if can_buy_survival():
            best_cost = survival_next_cost()
            best_slot = "*"
        for sl in SLOTS:
            var sid := String(sl["id"])
            var side_key := active_side(sid)
            if can_buy(sid, side_key):
                var c := next_cost(sid, side_key)
                if best_cost < 0 or c < best_cost:
                    best_cost = c
                    best_slot = sid
        if best_slot == "":
            break
        if best_slot == "*":
            buy_survival()
        else:
            buy(best_slot, active_side(best_slot))
    _quiet = false
    return embers


func _rebuild_totals() -> void:
    _totals = {}
    _cond = {}
    for sl in SLOTS:
        var sid := String(sl["id"])
        var s := active_side(sid)
        var r := rank(sid, s)
        if r <= 0:
            continue
        var mods := side_mods(sid, s, r)
        var cond := String(sl[s].get("cond", ""))
        for k in mods.keys():
            if cond == "":
                _totals[k] = float(_totals.get(k, 0.0)) + float(mods[k])
            else:
                if not _cond.has(cond):
                    _cond[cond] = {}
                _cond[cond][k] = float(_cond[cond].get(k, 0.0)) + float(mods[k])


# --- Earning (R7) ------------------------------------------------------------


## Pay a finished run. Reads what the run did from Progress (rooms, elites, bosses and
## first-ever reactions are counted there per run). `class_id` is player 1's class, for
## the bounties. Returns { total, parts, counts, bounties } and keeps it in `last_award`.
func award(floor_number: int, won: bool, class_id: String) -> Dictionary:
    var a := preview(floor_number, won, class_id)
    for b in a["bounties"]:
        bounties["%s|%s" % [class_id, String(b)]] = true
    var parts: Dictionary = a["parts"]
    for k in parts.keys():
        earned_by[k] = int(earned_by.get(k, 0)) + int(parts[k])
    embers += int(a["total"])
    earned += int(a["total"])
    last_award = a
    save()
    changed.emit()
    return last_award


## What `award` would pay for the current run, without paying it.
func preview(floor_number: int, won: bool, class_id: String) -> Dictionary:
    var counts := {
        "rooms": Progress.run_stat("rooms"),
        "elites": mini(Progress.run_stat("elites"), ELITE_PAY_CAP),
        "discoveries": Progress.run_discoveries.size(),
        "fusions": Progress.run_fusion_discoveries.size(),
        "cataclysms": Progress.run_cataclysm_discoveries.size(),
        "bosses": Progress.run_stat("bosses"),
        "bounties": 0,
        "floors": maxi(0, floor_number - 1),
        "win": 1 if won else 0,
    }
    var new_bounties: Array = []
    for key in Progress.run_stats.keys():
        var k := String(key)
        if not k.begins_with("boss:") or int(Progress.run_stats[key]) <= 0:
            continue
        var tag := "%s|%s" % [class_id, k.substr(5)]
        if not bounties.has(tag):
            new_bounties.append(k.substr(5))
    counts["bounties"] = new_bounties.size()
    var parts: Dictionary = {}
    var total := 0
    var ladder_left := FUSION_PAY_CAP
    for k in PAY_ORDER:
        var v: int = int(counts[k]) * int(PAY[k])
        if k == "fusions" or k == "cataclysms":
            v = mini(v, ladder_left)
            ladder_left -= v
        parts[k] = v
        total += v
    # A Vow pays its share on top of the whole run (Loadout.VOWS).
    var vow_bonus := roundi(float(total) * Loadout.vow_embers())
    if vow_bonus > 0:
        parts["vow"] = vow_bonus
        total += vow_bonus
    return { "total": total, "parts": parts, "counts": counts, "bounties": new_bounties, "class": class_id }


## "5 rooms 5, 2 elites 4, 2 new reactions 6" for a payout's non-zero parts.
func award_text(a: Dictionary) -> String:
    var bits: Array = []
    var parts: Dictionary = a.get("parts", {})
    var counts: Dictionary = a.get("counts", {})
    for k in PAY_ORDER + ["vow"]:
        var v := int(parts.get(k, 0))
        if v <= 0:
            continue
        var n := int(counts.get(k, 0))
        match k:
            "floors":
                bits.append("floor %d +%d" % [n + 1, v])
            "win":
                bits.append("clear +%d" % v)
            "bounties":
                bits.append("%d bount%s +%d" % [n, "y" if n == 1 else "ies", v])
            "vow":
                bits.append("vow +%d" % v)
            _:
                var word := String(PAY_WORDS[k])
                if n == 1:
                    word = { "rooms": "room", "elites": "elite", "discoveries": "new reaction", "fusions": "new fusion",
                        "cataclysms": "new cataclysm", "bosses": "boss" }.get(k, word)
                bits.append("%d %s +%d" % [n, word, v])
    return ", ".join(bits) if not bits.is_empty() else "nothing this time"


## Lifetime Embers by source, e.g. "rooms 40, elites 12, new reactions 27".
func earned_text() -> String:
    var bits: Array = []
    for k in PAY_ORDER + ["legacy"]:
        var v := int(earned_by.get(k, 0))
        if v > 0:
            bits.append("%s %d" % [String(PAY_WORDS.get(k, k)), v])
    return ", ".join(bits) if not bits.is_empty() else "none yet"


# --- Persistence -----------------------------------------------------------


func save() -> void:
    var data := {
        "version": SAVE_VERSION,
        "embers": embers,
        "earned": earned,
        "ranks": ranks,
        "active": active,
        "survival": survival,
        "bounties": bounties.keys(),
        "earned_by": earned_by,
        "last_award": last_award,
    }
    var f := FileAccess.open(save_path, FileAccess.WRITE)
    if f == null:
        push_warning("Could not write mastery file: %s" % save_path)
        return
    f.store_string(JSON.stringify(data, "  "))
    f.close()


func load_save() -> void:
    embers = 0
    earned = 0
    ranks = {}
    active = {}
    survival = 0
    bounties = {}
    earned_by = {}
    last_award = {}
    var migrated := false
    if FileAccess.file_exists(save_path):
        var f := FileAccess.open(save_path, FileAccess.READ)
        if f != null:
            var parsed = JSON.parse_string(f.get_as_text())
            f.close()
            if parsed is Dictionary:
                var d: Dictionary = parsed
                if int(d.get("version", 1)) < 2:
                    # Version 1 (the node tree): refund everything as Embers.
                    var legacy := maxi(int(d.get("earned", d.get("points", 0))), int(d.get("points", 0)))
                    embers = legacy * LEGACY_EMBERS_PER_POINT
                    earned = embers
                    if embers > 0:
                        earned_by["legacy"] = embers
                    migrated = true
                else:
                    embers = int(d.get("embers", 0))
                    earned = int(d.get("earned", embers))
                    survival = clampi(int(d.get("survival", 0)), 0, survival_max())
                    var saved_ranks: Dictionary = d.get("ranks", {})
                    for k in saved_ranks.keys():
                        var parts := String(k).split(":")
                        if parts.size() == 2 and not slot(parts[0]).is_empty() and parts[1] in ["a", "b"]:
                            ranks[String(k)] = clampi(int(saved_ranks[k]), 0, max_rank(parts[0], parts[1]))
                    var saved_active: Dictionary = d.get("active", {})
                    for k in saved_active.keys():
                        if not slot(String(k)).is_empty() and String(saved_active[k]) in ["a", "b"]:
                            active[String(k)] = String(saved_active[k])
                    for b in d.get("bounties", []):
                        bounties[String(b)] = true
                    var eb: Dictionary = d.get("earned_by", {})
                    for k in eb.keys():
                        earned_by[String(k)] = int(eb[k])
                    var la = d.get("last_award", {})
                    if la is Dictionary:
                        last_award = la
    _rebuild_totals()
    if migrated:
        save()


## Wipe the board: no Embers, nothing bought.
func reset() -> void:
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    load_save()
