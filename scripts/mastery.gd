extends Node
## Autoload "Mastery": the Shrine. Runs pay Embers for how well they were played, and
## Embers buy nodes on a talent tree plus a short survival track (Last Breath).
##
## The tree (design/Talent tree.md, Emil 2026-11-11, modern WoW talents): five branches, one
## per playstyle, five nodes each. Rows 1 and 3 are passives (3 ranks of a small stat), rows
## 2, 4 and 5 are choice nodes: bought once, then one of two options is picked, and the pick
## changes how a fight plays ("Burning foes spread fire when they die" or "Fire burns twice
## as long"). Picks swap for free in the Hollow, never during a run. A node opens when the
## node above it in its branch is full. Refund all is free.
##
## Why: the A/B board before this (eleven slots of +4% range or +5% shot speed, the report's
## R4) was fair but felt like nothing to buy (2026-11-10, "no growth or reward"). The
## report's other findings stay: permanent stat power stays small (passives come to about
## +7% damage-equivalent and +17 HP-equivalent, inside the GDD budget of +10% and +20), and
## survival stays a cheap capped track. The choices' damage is measured by the bot probe
## (`--mastery=full --mastery-side=a|b|mix`), not estimated here.
##
## Effects use the Items vocabulary: `mods` are player stats (or the meta keys below) summed
## into `bonus()`, which Player.stat reads; `triggers` are Items trigger dicts that Player
## adds to its boon_triggers at spawn, so Items.fire runs them on kill, dash, vent and so on.

signal changed

const SAVE_PATH := "user://mastery.json"
const SAVE_VERSION := 3

## Old saves had mastery points (1 per floor reached, 1 per 150 kills, 3 per win). One
## point was about one floor of play; a floor now pays about 8 Embers (5 rooms, an
## elite, the floor bonus), so every point ever earned converts to 8 Embers and the old
## tree is fully refunded, as Hades' Patch 040 refunded over-investment when it moved
## to A/B pairs.
const LEGACY_EMBERS_PER_POINT := 8

## Version 2 (the A/B board): the cost ladder of every side, "slot:side" -> Embers per rank,
## so a version 2 save refunds exactly what it spent (Talent tree.md, Migration).
const LEGACY_V2_COSTS := {
    "sights:a": [3, 8, 16], "sights:b": [3, 8, 16],
    "catalyst:a": [4, 10, 20], "catalyst:b": [4, 10, 20],
    "nerve:a": [4, 10, 20], "nerve:b": [4, 10, 20],
    "vent:a": [4, 10, 20], "vent:b": [4, 10, 20],
    "footwork:a": [3, 8, 16], "footwork:b": [6, 16],
    "salvage:a": [3, 8, 16], "salvage:b": [10, 25, 45],
    "fortune:a": [4, 10, 20], "fortune:b": [35, 75],
    "pack:a": [8, 20], "pack:b": [10, 25],
    "scout:a": [3, 6, 12], "scout:b": [6, 15],
    "bite:a": [8, 20], "bite:b": [8, 20],
    "twilight:a": [8, 20], "twilight:b": [8, 20],
}

## Measured conversion factors for the power estimate (telemetry, build 2026.11.05):
## reactions dealt 49% of all damage; 44% of wave samples were at >= 80% HP; a floor of
## play took about 150 damage; longer element states convert at an assumed 0.15.
const REACTION_SHARE := 0.49
const VENT_SHARE := 0.126
const HIGH_HP_SHARE := 0.44
const DAMAGE_PER_FLOOR := 150.0
const DURATION_TO_DMG := 0.15

# --- Embers (R7) -------------------------------------------------------------
# Scale: one cleared room = 1 Ember, the way a Hades chamber pays 10 Darkness, so Hades
# prices divide by 10 (Death Defiance 30/500/1,000 Darkness -> Last Breath 3/50/100).
#   rooms       1 per room cleared: the basic unit of play quality.
#   elites      1 each, at most ELITE_PAY_CAP a run.
#   discoveries 2 per reaction fired for the first time ever on this save.
#   fusions     2 per fusion (tier 3) and 3 per cataclysm (tier 4) set off for the first
#   cataclysms  time ever, together at most FUSION_PAY_CAP a run.
#   bosses      3 per boss kill.
#   bounties    5 the first time a boss kind dies to a class.
#   floors      3 per floor reached beyond the first.
#   win         20 for clearing the dungeon.
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
# 30/500/1,000 Darkness at 1 Ember = 10 Darkness. A revive restores 25% of max HP, with two
# seconds of invulnerability so it is not eaten on the spot.
const SURVIVAL := {
    "id": "last_breath", "name": "Last Breath",
    "desc": "When you would fall, stand back up once.",
    "icon": "gui/spells/necromancy/deaths_door_new.png",
    "costs": [3, 50, 100],
}
const REVIVE_FRACTION := 0.25
const REVIVE_INVULN := 2.0

# --- The tree -------------------------------------------------------------------
# Row costs (Embers per rank). Rows 1 and 3 are passives, rows 2, 4 and 5 choice nodes.
const ROW_COSTS := [[3, 6, 10], [12], [8, 14, 22], [24], [40]]

# A branch is { id, name, color, nodes: [5 nodes, top to bottom] }.
# A passive node: { id, name, desc, icon, per_rank: mods, eq: [dmg, hp] at full rank }.
# A choice node: { id, a: option, b: option }; an option is { id, name, desc, icon,
#   mods?: mods, triggers?: [Items trigger dicts] }.
# Meta keys in mods (read by the systems they change, never by Player.stat users):
#   levelup_rerolls  rerolls of the level-up offer per run (LevelUpScreen)
#   levelup_extra    1: a fourth level-up card every other level-up, 2: every level-up
#   free_gunsmith    the gunsmith of floors 1..N costs nothing (FloorGen)
#   reveal_rooms     1 shop, 2 + treasure, 3 + boss shown on the map at floor start (Main)
#   reveal_secrets   1 hidden rooms, 2 + puzzle and alcove rooms shown on the map (Main)
# New player stats: burn_time (fire from your reactions burns longer, Elements).
const BRANCHES := [
    { "id": "pyre", "name": "Pyre", "color": Color(1.0, 0.5, 0.25), "nodes": [
        { "id": "kindling", "name": "Kindling", "desc": "Reactions hit harder.",
            "icon": "gui/spells/transmutation/irradiate.png", "per_rank": { "potency": 0.02 }, "eq": [0.029, 0.0] },
        { "id": "pyre_c1",
            "a": { "id": "wildfire", "name": "Wildfire", "desc": "Burning foes spread fire to foes near them when they die.",
                "icon": "gui/spells/fire/fire_storm_new.png",
                "triggers": [{ "on": "kill", "if": "target_burning", "do": "spread", "element": "fire", "radius": 120.0, "potency": 5.0 }] },
            "b": { "id": "slow_burn", "name": "Slow Burn", "desc": "Fire burns twice as long.",
                "icon": "gui/spells/fire/flame_tongue_new.png", "mods": { "burn_time": 1.0 } } },
        { "id": "lingering", "name": "Lingering Touch", "desc": "Elements cling to foes for longer.",
            "icon": "gui/spells/enchantment/extension.png", "per_rank": { "state_duration": 0.05 }, "eq": [0.023, 0.0] },
        { "id": "pyre_c2",
            "a": { "id": "flashpoint", "name": "Flashpoint", "desc": "Every 4th reaction sets off a fire blast.",
                "icon": "gui/spells/fire/fireball_new.png",
                "triggers": [{ "on": "reaction", "every": 4, "do": "nova", "element": "fire", "radius": 110.0, "potency": 6.0, "at": "target" }] },
            "b": { "id": "feeding_flame", "name": "Feeding Flame", "desc": "Reactions heal you a little.",
                "icon": "gui/spells/fire/conjure_flame_new.png", "mods": { "lifesteal": 1 } } },
        { "id": "pyre_c3",
            "a": { "id": "pyre_heart", "name": "Pyre Heart", "desc": "Elite kills erupt in a huge fire blast.",
                "icon": "gui/spells/fire/ring_of_flames_new.png",
                "triggers": [{ "on": "elite_kill", "do": "nova", "element": "fire", "radius": 220.0, "potency": 14.0 }] },
            "b": { "id": "ash_wake", "name": "Ash Wake", "desc": "Burning foes leave a fire cloud when they die.",
                "icon": "gui/spells/fire/delayed_fireball.png",
                "triggers": [{ "on": "kill", "if": "target_burning", "do": "cloud", "element": "fire", "radius": 70.0, "secs": 3.0, "potency": 8.0 }] } },
    ] },
    { "id": "rime", "name": "Rime", "color": Color(0.55, 0.85, 1.0), "nodes": [
        { "id": "thick_skin", "name": "Thick Skin", "desc": "A little more blood to lose.",
            "icon": "gui/spells/earth/stoneskin_new.png", "per_rank": { "max_hp": 4 }, "eq": [0.0, 12.0] },
        { "id": "rime_c1",
            "a": { "id": "shatter", "name": "Shatter", "desc": "Frozen foes take 30% more damage.",
                "icon": "gui/spells/ice/throw_icicle_new.png", "mods": { "vs_frozen": 0.3 } },
            "b": { "id": "frostbite", "name": "Frostbite", "desc": "Hits on wet foes may freeze them.",
                "icon": "gui/spells/ice/freeze_new.png",
                "triggers": [{ "on": "hit", "if": "target_wet", "chance": 0.25, "do": "apply", "element": "ice", "potency": 5.0 }] } },
        { "id": "cold_blood", "name": "Cold Blood", "desc": "Sometimes a hit just misses.",
            "icon": "gui/skills/dodging.png", "per_rank": { "dodge": 0.01 }, "eq": [0.0, 4.5] },
        { "id": "rime_c2",
            "a": { "id": "cold_snap", "name": "Cold Snap", "desc": "When you are hit, foes near you freeze.",
                "icon": "gui/spells/ice/freezing_aura.png",
                "triggers": [{ "on": "hurt", "do": "nova", "element": "ice", "radius": 150.0, "potency": 6.0 }] },
            "b": { "id": "bramble", "name": "Bramble", "desc": "Foes that hit you take 10 damage.",
                "icon": "gui/spells/ice/ozocubus_armor_new.png", "mods": { "thorns": 10 } } },
        { "id": "rime_c3",
            "a": { "id": "winters_grip", "name": "Winter's Grip", "desc": "Entering a room slows every foe near you.",
                "icon": "gui/spells/ice/ice_storm_new.png",
                "triggers": [{ "on": "room_enter", "do": "slow", "radius": 420.0 }] },
            "b": { "id": "shatterburst", "name": "Shatterburst", "desc": "Frozen foes burst into ice when they die.",
                "icon": "gui/spells/ice/freezing_cloud_new.png",
                "triggers": [{ "on": "kill", "if": "target_frozen", "do": "nova", "element": "ice", "radius": 120.0, "potency": 6.0 }] } },
    ] },
    { "id": "stride", "name": "Stride", "color": Color(0.6, 1.0, 0.7), "nodes": [
        { "id": "light_feet", "name": "Light Feet", "desc": "Move faster.",
            "icon": "gui/spells/air/swiftness_new.png", "per_rank": { "speed": 0.02 }, "eq": [0.0, 0.0] },
        { "id": "stride_c1",
            "a": { "id": "frost_trail", "name": "Frost Trail", "desc": "Your dash leaves a trail of ice.",
                "icon": "gui/spells/ice/throw_frost_new.png",
                "triggers": [{ "on": "dash", "do": "trail", "element": "ice", "secs": 2.5 }] },
            "b": { "id": "second_wind", "name": "Second Wind", "desc": "A kill gives back a dash.",
                "icon": "gui/spells/translocation/blink.png",
                "triggers": [{ "on": "kill", "do": "dash_refill" }] } },
        { "id": "quick_recovery", "name": "Quick Recovery", "desc": "Your dash comes back sooner.",
            "icon": "gui/spells/translocation/phase_shift_new.png", "per_rank": { "dash_cooldown": 0.06 }, "eq": [0.0, 0.0] },
        { "id": "stride_c2",
            "a": { "id": "shoulder_charge", "name": "Shoulder Charge", "desc": "Your dash hits every foe it passes through.",
                "icon": "gui/spells/translocation/dispersal_new.png", "mods": { "dash_hit": 1.0 } },
            "b": { "id": "close_shave", "name": "Close Shave", "desc": "Dash through a hit: 30% more damage for 3 s.",
                "icon": "gui/spells/air/deflect_missiles_new.png",
                "triggers": [{ "on": "perfect_dodge", "do": "buff", "key": "dmg", "amount": 0.3, "secs": 3.0 }] } },
        { "id": "stride_c3",
            "a": { "id": "twin_dash", "name": "Twin Dash", "desc": "One more dash charge.",
                "icon": "gui/spells/translocation/controlled_blink_new.png", "mods": { "dash_charges": 1 } },
            "b": { "id": "dash_volley", "name": "Dash Volley", "desc": "Each dash fires 4 shots of your gun's element.",
                "icon": "gui/spells/conjuration/magic_dart.png",
                "triggers": [{ "on": "dash", "do": "shoot", "element": "gun", "count": 4, "potency": 5.0 }] } },
    ] },
    { "id": "vent", "name": "Vent", "color": Color(1.0, 0.8, 0.4), "nodes": [
        { "id": "tank", "name": "Reinforced Tank", "desc": "A bigger tank: vents can charge further.",
            "icon": "gui/invocations/gozag_potion_petition.png", "per_rank": { "pressure_limit": 4 }, "eq": [0.015, 0.0] },
        { "id": "vent_c1",
            "a": { "id": "hard_vent", "name": "Hard Vent", "desc": "Vents hit 20% harder.",
                "icon": "gui/spells/fire/bolt_of_magma_new.png", "mods": { "vent_power": 0.2 } },
            "b": { "id": "quick_vent", "name": "Quick Vent", "desc": "The vent fills 20% faster.",
                "icon": "gui/spells/air/airstrike_new.png", "mods": { "vent_charge": 0.2 } } },
        { "id": "wide_valve", "name": "Wide Valve", "desc": "Vents reach further.",
            "icon": "gui/spells/air/cloud_cone.png", "per_rank": { "vent_radius": 0.05 }, "eq": [0.01, 0.0] },
        { "id": "vent_c2",
            "a": { "id": "scald_cloud", "name": "Scald Cloud", "desc": "Vents leave a cloud of their element.",
                "icon": "gui/spells/poison/poisonous_cloud_new.png",
                "triggers": [{ "on": "vent", "do": "cloud", "element": "last", "radius": 90.0, "secs": 4.0, "potency": 8.0 }] },
            "b": { "id": "venting_mend", "name": "Venting Mend", "desc": "Vents heal you 6 HP.",
                "icon": "gui/spells/air/insulation.png",
                "triggers": [{ "on": "vent", "do": "heal", "amount": 6.0 }] } },
        { "id": "vent_c3",
            "a": { "id": "overpressure", "name": "Overpressure", "desc": "Vents fire 6 shots of their element.",
                "icon": "gui/spells/fire/fire_storm_old.png",
                "triggers": [{ "on": "vent", "do": "shoot", "element": "last", "count": 6, "potency": 6.0 }] },
            "b": { "id": "storm_vent", "name": "Storm Vent", "desc": "Vents arc lightning to 4 foes.",
                "icon": "gui/spells/air/chain_lightning_new.png",
                "triggers": [{ "on": "vent", "do": "chain", "count": 4, "radius": 320.0, "potency": 6.0 }] } },
    ] },
    { "id": "fortune", "name": "Fortune", "color": Color(1.0, 0.9, 0.45), "nodes": [
        { "id": "salvager", "name": "Salvager", "desc": "Strip more scrap from every wreck.",
            "icon": "gui/invocations/gozag_call_merchant.png", "per_rank": { "scrap_gain": 0.04 }, "eq": [0.0, 0.0] },
        { "id": "fortune_c1",
            "a": { "id": "cartographer", "name": "Cartographer", "desc": "Shop, treasure and boss show on the map.",
                "icon": "gui/spells/divination/magic_mapping.png", "mods": { "reveal_rooms": 3 } },
            "b": { "id": "dowser", "name": "Dowser", "desc": "Hidden and puzzle rooms show on the map.",
                "icon": "gui/spells/divination/detect_secret_doors.png", "mods": { "reveal_secrets": 2 } } },
        { "id": "lucky_coin", "name": "Lucky Coin", "desc": "Rarer gear and level-ups turn up.",
            "icon": "gui/invocations/gozag_bribe_branch.png", "per_rank": { "luck": 0.04 }, "eq": [0.0, 0.0] },
        { "id": "fortune_c2",
            "a": { "id": "second_thoughts", "name": "Second Thoughts", "desc": "Reroll the level-up offer twice a run.",
                "icon": "gui/spells/enchantment/selective_amnesia.png", "mods": { "levelup_rerolls": 2 } },
            "b": { "id": "heirloom", "name": "Heirloom", "desc": "The gunsmith is free on floors 1 and 2.",
                "icon": "gui/invocations/kiku_bless_weapon.png", "mods": { "free_gunsmith": 2 } } },
        { "id": "fortune_c3",
            "a": { "id": "wider_choice", "name": "Wider Choice", "desc": "Every level-up offers a fourth card.",
                "icon": "gui/spells/divination/identify.png", "mods": { "levelup_extra": 2 } },
            "b": { "id": "deep_pockets", "name": "Deep Pockets", "desc": "Carry heavier guns.",
                "icon": "gui/spells/translocation/apportation_new.png", "mods": { "carry": 2 } } },
    ] },
]

## Keys that are not player stats (see above).
const META_KEYS := ["levelup_rerolls", "levelup_extra", "free_gunsmith", "reveal_rooms", "reveal_secrets"]
## Stats counted in whole units rather than fractions.
const INT_KEYS := ["max_hp", "armor", "pierce", "carry", "chain_jumps", "bounce", "pressure_limit", "thorns", "proj_count", "lifesteal", "dash_charges"]
const STAT_WORDS := {
    "dmg": "damage", "fire_rate": "fire rate", "crit": "crit chance", "max_hp": "max HP",
    "dodge": "dodge", "speed": "move speed", "range": "range", "proj_speed": "shot speed",
    "potency": "reaction potency", "state_duration": "element duration",
    "pressure_limit": "vent capacity", "vent_power": "vent power", "vent_radius": "vent radius",
    "vent_charge": "vent charge speed", "scrap_gain": "scrap", "luck": "luck", "carry": "carry",
    "xp_gain": "XP gain", "armor": "armour", "dash_cooldown": "dash recharge speed",
    "burn_time": "burn time", "vs_frozen": "damage to frozen foes", "thorns": "thorns",
    "lifesteal": "HP per reaction", "dash_charges": "dash charge", "dash_hit": "dash hit",
}

var save_path := SAVE_PATH
var embers := 0                       # unspent
var earned := 0                       # lifetime total
var nodes: Dictionary = {}            # node id -> rank bought (choice nodes: 0 or 1)
var picks: Dictionary = {}            # choice node id -> "a" or "b"
var survival := 0                     # Last Breath ranks bought
var bounties: Dictionary = {}         # "class|boss kind" -> true once paid
var earned_by: Dictionary = {}        # PAY_ORDER key (or "legacy") -> lifetime Embers
var last_award: Dictionary = {}       # the last run's payout: { total, parts, counts, bounties }
var rebuilt_refund := 0               # Embers the v2 -> v3 migration gave back, until the Shrine shows it
var legacy_v2: Dictionary = {}        # the v2 board as it was migrated (ranks, active), kept for the record
var _totals: Dictionary = {}          # key -> summed amount over bought passives and picked options
var _triggers: Array = []             # Items trigger dicts of the picked options
var _node_index: Dictionary = {}      # node id -> [branch index, row]
var _quiet := false                   # balance probes buy without logging hub events
var fired: Dictionary = {}            # option id -> times its trigger ran this run (bot log)


func _init() -> void:
    for bi in BRANCHES.size():
        var ns: Array = BRANCHES[bi]["nodes"]
        for row in ns.size():
            _node_index[String(ns[row]["id"])] = [bi, row]


func _ready() -> void:
    # Bot runs never touch the player's Shrine (main.gd / hub.gd reset this file later).
    if Main.bot_run():
        save_path = "user://mastery_autotest%s.json" % Main._instance_tag()
    load_save()


# --- Queries ---------------------------------------------------------------


func branches() -> Array:
    return BRANCHES


func node(id: String) -> Dictionary:
    if not _node_index.has(id):
        return {}
    var at: Array = _node_index[id]
    return BRANCHES[int(at[0])]["nodes"][int(at[1])]


## [branch index, row] of a node, or [-1, -1].
func node_at(id: String) -> Array:
    return _node_index.get(id, [-1, -1])


func is_choice(id: String) -> bool:
    return node(id).has("a")


func rank(id: String) -> int:
    return int(nodes.get(id, 0))


func node_costs(id: String) -> Array:
    var at := node_at(id)
    if int(at[0]) < 0:
        return []
    return ROW_COSTS[int(at[1])]


func max_rank(id: String) -> int:
    return node_costs(id).size()


func is_full(id: String) -> bool:
    return rank(id) >= max_rank(id)


## The picked option of a choice node ("a" by default).
func pick(id: String) -> String:
    return String(picks.get(id, "a"))


func other_side(s: String) -> String:
    return "b" if s == "a" else "a"


## The option dict of a choice node.
func option(id: String, s: String) -> Dictionary:
    return node(id).get(s, {})


## A node opens when the node above it in its branch is full.
func is_open(id: String) -> bool:
    var at := node_at(id)
    if int(at[0]) < 0:
        return false
    if int(at[1]) == 0:
        return true
    var above: Dictionary = BRANCHES[int(at[0])]["nodes"][int(at[1]) - 1]
    return is_full(String(above["id"]))


## "Fill Kindling first" for a closed node, else "".
func requirement_text(id: String) -> String:
    if is_open(id):
        return ""
    var at := node_at(id)
    var above: Dictionary = BRANCHES[int(at[0])]["nodes"][int(at[1]) - 1]
    return "Fill %s first" % node_title(String(above["id"]))


## A passive's name, or "Wildfire / Slow Burn" for a choice node.
func node_title(id: String) -> String:
    var d := node(id)
    if d.has("a"):
        return "%s / %s" % [String(d["a"]["name"]), String(d["b"]["name"])]
    return String(d.get("name", id))


## Embers for the next rank of a node, or -1 when it is full.
func next_cost(id: String) -> int:
    var costs := node_costs(id)
    var r := rank(id)
    if r >= costs.size():
        return -1
    return int(costs[r])


func can_buy(id: String) -> bool:
    var c := next_cost(id)
    return c >= 0 and embers >= c and is_open(id)


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


## Summed bonus for a stat or meta key over bought passives and picked options. Cached;
## cheap to call every frame.
func bonus(key: String) -> float:
    return float(_totals.get(key, 0.0))


## Conditional bonuses: the tree has none (High Confidence went with the A/B board). Kept
## because Player.stat and the character sheet ask.
func cond_bonus(_key: String, _player) -> float:
    return 0.0


## Items trigger dicts of the picked options; Player adds copies to boon_triggers at spawn.
func triggers() -> Array:
    var out: Array = []
    for t in _triggers:
        out.append((t as Dictionary).duplicate())
    fired = {}
    return out


## Items.fire calls this when a talent trigger runs (the bot's [TALENTS] line).
func note_fired(id: String) -> void:
    fired[id] = int(fired.get(id, 0)) + 1


## "wildfire 12, second_wind 30" for the run so far, or "none".
func fired_text() -> String:
    var bits: Array = []
    for k in fired.keys():
        bits.append("%s %d" % [String(k), int(fired[k])])
    return ", ".join(bits) if not bits.is_empty() else "none"


## The mods of a passive at rank `r`.
func passive_mods(id: String, r: int) -> Dictionary:
    var out: Dictionary = {}
    var per: Dictionary = node(id).get("per_rank", {})
    if r <= 0:
        return out
    for k in per.keys():
        out[k] = float(per[k]) * float(r)
    return out


## What a passive gives at rank `r`, in words: "+8 max HP".
func effect_text(id: String, r: int) -> String:
    if r <= 0:
        return "not learned"
    return mods_text(passive_mods(id, r))


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
    var word := String(STAT_WORDS.get(key, key))
    if INT_KEYS.has(key):
        return "+%d %s" % [int(roundf(float(v))), word]
    return "+%s%% %s" % [_num(float(v) * 100.0), word]


func _num(v: float) -> String:
    if is_equal_approx(v, roundf(v)):
        return str(int(roundf(v)))
    return String.num(v, 1)


## Icon path of a passive, or of option `s` of a choice node.
func icon_path(id: String, s: String = "") -> String:
    var d := node(id)
    if d.has("a"):
        return String(d.get(s if s != "" else pick(id), {}).get("icon", ""))
    return String(d.get("icon", ""))


func node_icon(id: String, s: String = "") -> Texture2D:
    return Art.icon(icon_path(id, s), Vector2i(28, 12))


## [id, icon path] of every passive and option, for the icon sheet (Art).
func icon_rows() -> Array:
    var out: Array = []
    for br in BRANCHES:
        for n in br["nodes"]:
            if (n as Dictionary).has("a"):
                for s in ["a", "b"]:
                    out.append([String(n[s]["id"]), String(n[s]["icon"])])
            else:
                out.append([String(n["id"]), String(n["icon"])])
    return out


func ember_icon() -> Texture2D:
    return Art.icon(EMBER_ICON, Vector2i(28, 12))


func survival_icon() -> Texture2D:
    return Art.icon(String(SURVIVAL["icon"]), Vector2i(28, 12))


## Embers spent on the tree and the survival track.
func spent() -> int:
    var total := 0
    for id in nodes.keys():
        var costs := node_costs(String(id))
        for i in mini(rank(String(id)), costs.size()):
            total += int(costs[i])
    var sc: Array = SURVIVAL["costs"]
    for i in mini(survival, sc.size()):
        total += int(sc[i])
    return total


## Embers to buy every node and the whole survival track.
func total_cost() -> int:
    var total := 0
    for br in BRANCHES:
        for row in (br["nodes"] as Array).size():
            for c in ROW_COSTS[row]:
                total += int(c)
    for c in SURVIVAL["costs"]:
        total += int(c)
    return total


## Ranks bought over all nodes, and the number of ranks that exist.
func ranks_bought() -> int:
    var n := 0
    for k in nodes.keys():
        n += int(nodes[k])
    return n


func ranks_total() -> int:
    var n := 0
    for br in BRANCHES:
        for row in (br["nodes"] as Array).size():
            n += (ROW_COSTS[row] as Array).size()
    return n


## Every bought node, with the pick of a choice node, for telemetry and the probe log.
## { slot: node id, side: "a" / "b" / "", id: the option or node id, rank }.
func active_summary() -> Array:
    var out: Array = []
    for br in BRANCHES:
        for n in br["nodes"]:
            var id := String(n["id"])
            var r := rank(id)
            if r <= 0:
                continue
            if (n as Dictionary).has("a"):
                var s := pick(id)
                out.append({ "slot": id, "side": s, "id": String(n[s]["id"]), "rank": r })
            else:
                out.append({ "slot": id, "side": "", "id": id, "rank": r })
    return out


## Stat power of the passives with every rank bought: { dmg: fraction, hp: HP-equivalent
## per floor }. Choice options are left out: their damage is measured by the bot probe.
func max_power() -> Dictionary:
    var dmg := 0.0
    var hp := 0.0
    for br in BRANCHES:
        for n in br["nodes"]:
            var eq: Array = (n as Dictionary).get("eq", [0.0, 0.0])
            dmg += float(eq[0])
            hp += float(eq[1])
    return { "dmg": dmg, "hp": hp }


## Stat power of the passives bought now, by the same factors (scaled by rank / max).
func current_power() -> Dictionary:
    var dmg := 0.0
    var hp := 0.0
    for br in BRANCHES:
        for n in br["nodes"]:
            var id := String(n["id"])
            var eq: Array = (n as Dictionary).get("eq", [0.0, 0.0])
            var m := max_rank(id)
            if m <= 0:
                continue
            var f := float(rank(id)) / float(m)
            dmg += float(eq[0]) * f
            hp += float(eq[1]) * f
    return { "dmg": dmg, "hp": hp }


# --- Spending --------------------------------------------------------------


## Buy the next rank of a node. A newly bought choice node starts on its picked option (A
## unless it was flipped before).
func buy(id: String) -> bool:
    if not can_buy(id):
        return false
    var cost := next_cost(id)
    embers -= cost
    nodes[id] = rank(id) + 1
    _rebuild_totals()
    save()
    if not _quiet:
        Telemetry.hub_event("talent_buy", { "node": id, "pick": pick(id) if is_choice(id) else "", "rank": rank(id), "cost": cost, "left": embers })
    changed.emit()
    return true


## Pick option `s` of a choice node. Free, any number of times, in the Hollow.
func set_pick(id: String, s: String) -> void:
    if not is_choice(id) or not s in ["a", "b"] or pick(id) == s:
        return
    picks[id] = s
    _rebuild_totals()
    save()
    if not _quiet:
        Telemetry.hub_event("talent_pick", { "node": id, "side": s, "id": String(option(id, s)["id"]) })
    changed.emit()


func flip(id: String) -> void:
    set_pick(id, other_side(pick(id)))


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


## Refund every node and the survival track, free. Picks stay as they were. Returns the refund.
func refund_all() -> int:
    var back := spent()
    embers += back
    nodes = {}
    survival = 0
    _rebuild_totals()
    save()
    Telemetry.hub_event("talent_refund", { "embers": back, "left": embers })
    changed.emit()
    return back


## The migration's refund, once: the Shrine shows it the first time it opens, then it is gone.
func take_rebuild_note() -> int:
    var n := rebuilt_refund
    if n > 0:
        rebuilt_refund = 0
        save()
    return n


## The probe's pick for choice node number `i` (in tree order): "a", "b", or alternating
## for "mix".
func _probe_pick(s: String, i: int) -> String:
    if s == "mix":
        return "a" if i % 2 == 0 else "b"
    return "b" if s == "b" else "a"


## Balance probe (`--mastery=full`): every node and the whole survival track, option `s`
## ("a", "b" or "mix") picked everywhere.
func debug_max_all(s: String = "a") -> void:
    var ci := 0
    for br in BRANCHES:
        for n in br["nodes"]:
            var id := String(n["id"])
            nodes[id] = max_rank(id)
            if (n as Dictionary).has("a"):
                picks[id] = _probe_pick(s, ci)
                ci += 1
    survival = survival_max()
    _rebuild_totals()
    save()


## Balance probe (`--mastery=N`): spend `budget` Embers cheapest-first on the survival
## track and open nodes. Returns the Embers left over.
func debug_spend_greedy(budget: int, s: String = "a") -> int:
    embers = budget
    _quiet = true
    var ci := 0
    for br in BRANCHES:
        for n in br["nodes"]:
            if (n as Dictionary).has("a"):
                picks[String(n["id"])] = _probe_pick(s, ci)
                ci += 1
    _rebuild_totals()
    while true:
        var best_cost := -1
        var best := ""
        if can_buy_survival():
            best_cost = survival_next_cost()
            best = "*"
        for br in BRANCHES:
            for n in br["nodes"]:
                var id := String(n["id"])
                if can_buy(id):
                    var c := next_cost(id)
                    if best_cost < 0 or c < best_cost:
                        best_cost = c
                        best = id
        if best == "":
            break
        if best == "*":
            buy_survival()
        else:
            buy(best)
    _quiet = false
    return embers


## `--talent-test` (hub bot, on its own instance file): buys, picks, gates and refunds on
## whatever save is loaded, checking that no Ember is ever lost. Prints [TALENT-TEST].
func self_test() -> bool:
    var ok := true
    _quiet = true
    embers += 200   # enough to walk a branch; taken back at the end
    var whole := embers + spent()   # lambdas capture by value: fixed before `check` exists
    var fails: Array = []
    var check := func(cond: bool, what: String) -> void:
        if not cond:
            fails.append(what)
        if embers + spent() != whole:
            fails.append("embers lost after " + what)
    check.call(not can_buy("pyre_c1") or is_full("kindling"), "choice closed until the passive above is full")
    for i in 3:
        buy("kindling")
    check.call(is_full("kindling"), "kindling full")
    check.call(absf(bonus("potency") - 0.06) < 0.001, "kindling gives potency")
    check.call(buy("pyre_c1"), "pyre_c1 bought")
    check.call(not buy("pyre_c2"), "pyre_c2 closed until lingering is full")
    set_pick("pyre_c1", "b")
    check.call(absf(bonus("burn_time") - 1.0) < 0.001 and _triggers.is_empty(), "slow burn picked")
    set_pick("pyre_c1", "a")
    check.call(bonus("burn_time") == 0.0 and _triggers.size() == 1, "wildfire picked")
    for i in 3:
        buy("light_feet")
    buy("stride_c1")
    set_pick("stride_c1", "b")
    check.call(_triggers.size() == 2, "second wind adds a trigger")
    var back := refund_all()
    check.call(spent() == 0 and back > 0, "refund all")
    check.call(_triggers.is_empty() and _totals.is_empty(), "nothing active after refund")
    embers -= 200
    _quiet = false
    save()
    ok = fails.is_empty()
    print("[TALENT-TEST] %s embers %d, picks %s%s" % ["PASS" if ok else "FAIL", embers, str(picks), "" if ok else " | " + "; ".join(fails)])
    return ok


func _rebuild_totals() -> void:
    _totals = {}
    _triggers = []
    for br in BRANCHES:
        for n in br["nodes"]:
            var id := String(n["id"])
            var r := rank(id)
            if r <= 0:
                continue
            var mods: Dictionary
            if (n as Dictionary).has("a"):
                var opt: Dictionary = n[pick(id)]
                mods = opt.get("mods", {})
                for t in opt.get("triggers", []):
                    var tt: Dictionary = (t as Dictionary).duplicate()
                    tt["talent"] = String(opt["id"])
                    _triggers.append(tt)
            else:
                mods = passive_mods(id, r)
            for k in mods.keys():
                _totals[k] = float(_totals.get(k, 0.0)) + float(mods[k])


# --- Earning (R7) ------------------------------------------------------------


## Pay a finished run. Reads what the run did from Progress (rooms, elites, bosses and
## first-ever reactions are counted there per run). `class_id` is player 1's class, for
## the bounties. Returns { total, parts, counts, bounties } and keeps it in `last_award`.
## `share` < 1 pays that part of the award: leaving a run from the pause menu pays 75% of a
## death's (Main.QUIT_EMBERS, Core loop reset 11.2). Each part is scaled; "death_total" keeps
## what a death would have paid.
func award(floor_number: int, won: bool, class_id: String, share: float = 1.0) -> Dictionary:
    var a := preview(floor_number, won, class_id)
    if share < 1.0:
        a["death_total"] = int(a["total"])
        var scaled := 0
        var ps: Dictionary = a["parts"]
        for k in ps.keys():
            ps[k] = roundi(float(ps[k]) * share)
            scaled += int(ps[k])
        a["total"] = scaled
        a["share"] = share
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
        "nodes": nodes,
        "picks": picks,
        "survival": survival,
        "bounties": bounties.keys(),
        "earned_by": earned_by,
        "last_award": last_award,
        "rebuilt_refund": rebuilt_refund,
    }
    if not legacy_v2.is_empty():
        data["legacy_v2"] = legacy_v2
    var f := FileAccess.open(save_path, FileAccess.WRITE)
    if f == null:
        push_warning("Could not write mastery file: %s" % save_path)
        return
    f.store_string(JSON.stringify(data, "  "))
    f.close()


## Embers a version 2 board spent: every rank of every side at its old price.
static func legacy_v2_spent(saved_ranks: Dictionary) -> int:
    var total := 0
    for k in saved_ranks.keys():
        var costs: Array = LEGACY_V2_COSTS.get(String(k), [])
        for i in mini(int(saved_ranks[k]), costs.size()):
            total += int(costs[i])
    return total


func load_save() -> void:
    embers = 0
    earned = 0
    nodes = {}
    picks = {}
    survival = 0
    bounties = {}
    earned_by = {}
    last_award = {}
    rebuilt_refund = 0
    legacy_v2 = {}
    var migrated := false
    if FileAccess.file_exists(save_path):
        var f := FileAccess.open(save_path, FileAccess.READ)
        if f != null:
            var parsed = JSON.parse_string(f.get_as_text())
            f.close()
            if parsed is Dictionary:
                var d: Dictionary = parsed
                var version := int(d.get("version", 1))
                if version < 2:
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
                    for b in d.get("bounties", []):
                        bounties[String(b)] = true
                    var eb: Dictionary = d.get("earned_by", {})
                    for k in eb.keys():
                        earned_by[String(k)] = int(eb[k])
                    var la = d.get("last_award", {})
                    if la is Dictionary:
                        last_award = la
                    if version == 2:
                        # Version 2 (the A/B board, Talent tree.md Migration): every rank
                        # bought comes back as Embers at its old price; Last Breath, lifetime
                        # Embers and bounties carry over. The old file is kept as a backup.
                        var saved_ranks: Dictionary = d.get("ranks", {})
                        var back := legacy_v2_spent(saved_ranks)
                        embers += back
                        rebuilt_refund = back
                        legacy_v2 = { "ranks": saved_ranks, "active": d.get("active", {}), "refund": back }
                        _backup(save_path, "_v2_backup")
                        print("[MASTERY] save v2 -> v3: talent tree rebuilt, %d Embers refunded, %d to spend" % [back, embers])
                        migrated = true
                    else:
                        var saved_nodes: Dictionary = d.get("nodes", {})
                        for k in saved_nodes.keys():
                            if not node(String(k)).is_empty():
                                nodes[String(k)] = clampi(int(saved_nodes[k]), 0, max_rank(String(k)))
                        var saved_picks: Dictionary = d.get("picks", {})
                        for k in saved_picks.keys():
                            if is_choice(String(k)) and String(saved_picks[k]) in ["a", "b"]:
                                picks[String(k)] = String(saved_picks[k])
                        rebuilt_refund = int(d.get("rebuilt_refund", 0))
                        var lv = d.get("legacy_v2", {})
                        if lv is Dictionary:
                            legacy_v2 = lv
    _rebuild_totals()
    if migrated:
        save()


## Copy `path` to the same name with `suffix` before ".json", once (an existing backup stays).
static func _backup(path: String, suffix: String) -> void:
    var to := path.trim_suffix(".json") + suffix + ".json"
    if FileAccess.file_exists(to):
        return
    var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(to))
    if err != OK:
        push_warning("Could not back up %s (error %d)" % [path, err])


## Wipe the board: no Embers, nothing bought.
func reset() -> void:
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    load_save()
