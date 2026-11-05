extends Node
## Autoload "Mastery": the persistent skill tree. Runs earn mastery points (one per floor
## reached, one per 150 kills, three extra for a win) and points buy small permanent
## bonuses, idle-game style: many nodes, each worth a percent or two.
##
## A node is { id, branch, name, desc, cost, parent, mods, depth }. `mods` uses the same
## stat vocabulary as Items (see the header of items.gd), so a bonus is read the same way
## gear is: `Mastery.bonus("dmg")`. The tree is generated in `_build_tree`; repetitive
## tracks come from `_track`, roots and capstones are named by hand.

const SAVE_PATH := "user://mastery.json"
const KILLS_PER_POINT := 150
const WIN_BONUS := 3

const ELEMENT_KEYS := ["wet", "shock", "fire", "ice", "oil", "poison", "acid", "blood", "void", "holy", "gale", "stone"]
const ELEMENT_TITLES := {
    "wet": "Tide", "shock": "Storm", "fire": "Ember", "ice": "Frost", "oil": "Tar",
    "poison": "Venom", "acid": "Caustic", "blood": "Crimson", "void": "Abyssal",
    "holy": "Radiant", "gale": "Zephyr", "stone": "Granite",
}

## Branch name -> icon under Art.ICON_ROOT, shown on the branch root and capstone.
const BRANCH_ICONS := {
    "Offense": "gui/spells/enchantment/tukimas_vorpal_blade.png",
    "Defense": "item/armor/shields/large_shield_1_new.png",
    "Pressure": "gui/spells/fire/evaporate.png",
    "Economy": "item/gold/gold_pile_25.png",
    "Utility": "gui/spells/divination/magic_mapping.png",
    "Wet": "gui/spells/ice/ensorcelled_hibernation_new.png",
    "Shock": "gui/spells/air/lightning_bolt_new.png",
    "Fire": "gui/spells/fire/fireball_new.png",
    "Ice": "gui/spells/ice/throw_icicle_new.png",
    "Oil": "gui/spells/earth/ledas_liquefaction.png",
    "Poison": "gui/spells/poison/venom_bolt_new.png",
    "Acid": "gui/spells/poison/poisonous_cloud_new.png",
    "Blood": "gui/spells/necromancy/sublimation_of_blood_new.png",
    "Void": "gui/spells/enchantment/darkness.png",
    "Holy": "gui/invocations/tso_bless_weapon.png",
    "Gale": "gui/spells/air/tornado.png",
    "Stone": "gui/spells/earth/lees_rapid_deconstruction_new.png",
}

## Stats counted in whole units rather than fractions.
const INT_KEYS := ["max_hp", "armor", "pierce", "carry", "chain_jumps", "bounce", "starting_scrap",
    "pressure_limit", "thorns", "proj_count", "lifesteal"]
const STAT_WORDS := {
    "dmg": "damage", "fire_rate": "fire rate", "crit": "crit chance", "pierce": "pierce",
    "bounce": "bounce", "proj_count": "projectile", "max_hp": "max HP", "armor": "armour",
    "dodge": "dodge", "thorns": "thorns", "pressure_limit": "vent capacity",
    "vent_charge": "vent charge speed", "vent_radius": "vent radius", "vent_power": "vent power",
    "scrap_gain": "scrap gain", "carry": "carry slot", "starting_scrap": "starting scrap",
    "xp_gain": "XP gain", "state_duration": "state duration", "chain_jumps": "chain jump",
    "lifesteal": "HP per reaction", "range": "range",
}

var save_path := SAVE_PATH
var points := 0                       # unspent
var earned := 0                       # lifetime total
var purchased: Dictionary = {}        # id -> true
var nodes: Dictionary = {}            # id -> node
var _order: Array = []                # ids in tree order (parents before children)
var _branches: Array = []
var _totals: Dictionary = {}          # stat key -> summed amount over purchased nodes


func _init() -> void:
    _build_tree()


func _ready() -> void:
    load_save()


# --- Queries ---------------------------------------------------------------


func branches() -> Array:
    return _branches.duplicate()


func branch_icon_path(branch: String) -> String:
    return String(BRANCH_ICONS.get(branch, ""))


## The icon of a branch (a 1-bit sigil when the branch has none).
func branch_icon(branch: String) -> Texture2D:
    return Art.icon(branch_icon_path(branch), Vector2i(28, 12))


## Nodes of one branch in tree order: every parent comes before its children.
func nodes_in_branch(branch: String) -> Array:
    var out: Array = []
    for id in _order:
        if nodes[id]["branch"] == branch:
            out.append(nodes[id])
    return out


func get_node_data(id: String) -> Dictionary:
    return nodes.get(id, {})


func is_bought(id: String) -> bool:
    return purchased.has(id)


## True when the node's parent is bought (or it is a root).
func is_reachable(id: String) -> bool:
    if not nodes.has(id):
        return false
    var parent: String = nodes[id]["parent"]
    return parent == "" or purchased.has(parent)


func can_buy(id: String) -> bool:
    if not nodes.has(id) or purchased.has(id):
        return false
    return points >= int(nodes[id]["cost"]) and is_reachable(id)


## Sum of `mods[stat_key]` over every purchased node. Cached; cheap to call every frame.
func bonus(stat_key: String) -> float:
    return float(_totals.get(stat_key, 0.0))


func purchased_count() -> int:
    return purchased.size()


func total_nodes() -> int:
    return _order.size()


## A node's mods in words, e.g. "+2% damage, +1 pierce".
func mods_text(mods: Dictionary) -> String:
    var parts: Array = []
    for k in mods.keys():
        parts.append(_stat_text(k, mods[k]))
    return ", ".join(parts)


func _stat_text(key: String, v: Variant) -> String:
    if key.begins_with("dmg_"):
        return "+%d%% %s damage" % [roundi(float(v) * 100.0), key.substr(4).capitalize()]
    if key.begins_with("potency_"):
        return "+%d%% %s potency" % [roundi(float(v) * 100.0), key.substr(8).capitalize()]
    var word: String = STAT_WORDS.get(key, key)
    match key:
        "crit_dmg":
            return "+%.2fx crit damage" % float(v)
        "regen":
            return "+%.1f HP/s regen" % float(v)
    if INT_KEYS.has(key):
        return "+%d %s" % [int(v), word]
    return "+%d%% %s" % [roundi(float(v) * 100.0), word]


# --- Spending --------------------------------------------------------------


## Grant points for a finished run. Returns how many were gained.
func award(floor_number: int, kills: int, won: bool) -> int:
    var gained := maxi(floor_number, 0) + floori(maxi(kills, 0) / float(KILLS_PER_POINT))
    if won:
        gained += WIN_BONUS
    points += gained
    earned += gained
    save()
    return gained


func buy(id: String) -> bool:
    if not can_buy(id):
        return false
    points -= int(nodes[id]["cost"])
    purchased[id] = true
    _rebuild_totals()
    save()
    if Engine.has_singleton("Telemetry") or get_node_or_null("/root/Telemetry") != null:
        get_node("/root/Telemetry").hub_event("mastery_buy", { "id": id, "cost": int(nodes[id]["cost"]), "left": points })
    return true


func _rebuild_totals() -> void:
    _totals = {}
    for id in purchased.keys():
        if not nodes.has(id):
            continue
        var mods: Dictionary = nodes[id]["mods"]
        for k in mods.keys():
            _totals[k] = float(_totals.get(k, 0.0)) + float(mods[k])


# --- Persistence -----------------------------------------------------------


func save() -> void:
    var data := {
        "version": 1,
        "points": points,
        "earned": earned,
        "purchased": purchased.keys(),
    }
    var f := FileAccess.open(save_path, FileAccess.WRITE)
    if f == null:
        push_warning("Could not write mastery file: %s" % save_path)
        return
    f.store_string(JSON.stringify(data, "  "))
    f.close()


func load_save() -> void:
    points = 0
    earned = 0
    purchased = {}
    if FileAccess.file_exists(save_path):
        var f := FileAccess.open(save_path, FileAccess.READ)
        if f != null:
            var parsed = JSON.parse_string(f.get_as_text())
            f.close()
            if parsed is Dictionary:
                points = int(parsed.get("points", 0))
                earned = int(parsed.get("earned", points))
                for id in parsed.get("purchased", []):
                    if nodes.has(str(id)):
                        purchased[str(id)] = true
    _rebuild_totals()


## Wipe the tree: no points, nothing bought.
func reset() -> void:
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    load_save()


# --- Tree ------------------------------------------------------------------


func _add(id: String, branch: String, node_name: String, desc: String, cost: int, parent: String, mods: Dictionary) -> String:
    if not _branches.has(branch):
        _branches.append(branch)
    var depth := 0
    if parent != "" and nodes.has(parent):
        depth = int(nodes[parent]["depth"]) + 1
    nodes[id] = { "id": id, "branch": branch, "name": node_name, "desc": desc, "cost": cost,
        "parent": parent, "mods": mods, "depth": depth }
    _order.append(id)
    return id


## A chain of `count` nodes hanging off `parent`, each giving `amount` of `stat`.
## Cost starts at `base_cost` and rises by one every `cost_step` nodes, up to 3.
## Returns the id of the last node in the chain.
func _track(branch: String, stem: String, title: String, desc: String, parent: String,
        stat: String, amount: Variant, count: int, base_cost: int = 1, cost_step: int = 3) -> String:
    var prev := parent
    for i in count:
        var cost := mini(3, base_cost + int(i / float(cost_step)))
        prev = _add("%s_%d" % [stem, i + 1], branch, "%s %s" % [title, _roman(i + 1)], desc, cost, prev, { stat: amount })
    return prev


func _roman(n: int) -> String:
    const NUMERALS := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
    return NUMERALS[n] if n < NUMERALS.size() else str(n)


func _build_tree() -> void:
    _build_offense()
    _build_defense()
    _build_pressure()
    _build_economy()
    _build_utility()
    for el in ELEMENT_KEYS:
        _build_element(el)


func _build_offense() -> void:
    var b := "Offense"
    var root := _add("off_root", b, "Trigger Discipline", "Steady hands, cleaner shots.", 1, "", { "dmg": 0.02 })
    var dmg_end := _track(b, "off_dmg", "Hard Rounds", "Every shot lands a little harder.", root, "dmg", 0.02, 8)
    _track(b, "off_rate", "Quick Hands", "Cycle the action faster.", root, "fire_rate", 0.02, 6)
    var crit_end := _track(b, "off_crit", "Keen Eye", "Find the weak seams.", root, "crit", 0.01, 5)
    _track(b, "off_critdmg", "Cruel Edge", "Weak seams split wider.", crit_end, "crit_dmg", 0.05, 4, 2)
    _track(b, "off_pierce", "Punch Through", "Rounds keep going.", root, "pierce", 1, 2, 3)
    _track(b, "off_bounce", "Ricochet", "Rounds glance off walls into new targets.", root, "bounce", 1, 2, 3)
    _add("off_volley", b, "Spare Barrel", "One more round per trigger pull.", 3, dmg_end, { "proj_count": 1 })
    _add("off_cap", b, "Overkill", "Capstone. The dungeon learns to fear the sound of your gun.", 3, dmg_end, { "dmg": 0.03, "crit": 0.02 })


func _build_defense() -> void:
    var b := "Defense"
    var root := _add("def_root", b, "Thick Skin", "Scar tissue remembers.", 1, "", { "max_hp": 3 })
    var hp_end := _track(b, "def_hp", "Constitution", "A little more blood to lose.", root, "max_hp", 3, 8)
    _track(b, "def_armor", "Plating", "Scrap riveted to your coat.", root, "armor", 1, 5, 2)
    _track(b, "def_dodge", "Light Feet", "Not quite where they aimed.", root, "dodge", 0.01, 5)
    _track(b, "def_regen", "Mending", "Wounds close on their own, slowly.", root, "regen", 0.1, 4, 2)
    _track(b, "def_thorns", "Barbs", "Touching you hurts.", root, "thorns", 2, 3)
    _add("def_cap", b, "Unbroken", "Capstone. You have walked out of worse.", 3, hp_end, { "max_hp": 5, "armor": 1 })


func _build_pressure() -> void:
    var b := "Pressure"
    var root := _add("prs_root", b, "Gauge Reader", "Know the needle before it knows you.", 1, "", { "pressure_limit": 2 })
    var lim_end := _track(b, "prs_limit", "Reinforced Tank", "A little more room in the tank.", root, "pressure_limit", 3, 6)
    _track(b, "prs_decay", "Quick Charge", "The vent fills a little faster.", root, "vent_charge", 0.03, 5)
    _track(b, "prs_radius", "Wide Vent", "Vents reach further.", root, "vent_radius", 0.02, 5)
    _track(b, "prs_power", "Hard Vent", "Vents hit harder.", root, "vent_power", 0.02, 5)
    _add("prs_cap", b, "Pressure Cooker", "Capstone. Live at the red line.", 3, lim_end, { "pressure_limit": 5, "vent_power": 0.03 })


func _build_economy() -> void:
    var b := "Economy"
    var root := _add("eco_root", b, "Scavenger's Eye", "Junk is only junk to other people.", 1, "", { "scrap_gain": 0.02 })
    var scrap_end := _track(b, "eco_scrap", "Salvager", "Strip a little more from every wreck.", root, "scrap_gain", 0.02, 6)
    _track(b, "eco_carry", "Deep Pockets", "Room for one more thing.", root, "carry", 1, 2, 3)
    _track(b, "eco_start", "Nest Egg", "Start each run with a little scrap.", root, "starting_scrap", 5, 5)
    _track(b, "eco_xp", "Quick Study", "Learn faster from every fight.", root, "xp_gain", 0.02, 5)
    _add("eco_cap", b, "Merchant Prince", "Capstone. Every room pays.", 3, scrap_end, { "scrap_gain": 0.03, "starting_scrap": 5 })


func _build_utility() -> void:
    var b := "Utility"
    var root := _add("utl_root", b, "Field Kit", "The small tools that win long fights.", 1, "", { "state_duration": 0.02 })
    var state_end := _track(b, "utl_state", "Lingering Touch", "Elemental states last longer.", root, "state_duration", 0.02, 5)
    _track(b, "utl_chain", "Conductive Wire", "Chains find one more target.", root, "chain_jumps", 1, 2, 3)
    _track(b, "utl_leech", "Leech", "Reactions feed you.", root, "lifesteal", 1, 2, 3)
    _track(b, "utl_range", "Long Barrel", "Shots carry further.", root, "range", 0.02, 5)
    _add("utl_cap", b, "Old Hand", "Capstone. Nothing in here surprises you any more.", 3, state_end, { "state_duration": 0.03, "range": 0.03 })


func _build_element(el: String) -> void:
    var b: String = el.capitalize()
    var title: String = ELEMENT_TITLES[el]
    var dmg_key := "dmg_" + el
    var pot_key := "potency_" + el
    var root := _add("el_%s_root" % el, b, "%s Attunement" % title, "First steps with %s." % b.to_lower(), 1, "", { dmg_key: 0.02 })
    _track(b, "el_%s_dmg" % el, "%s Edge" % title, "%s rounds bite harder." % b, root, dmg_key, 0.02, 3)
    var pot_end := _track(b, "el_%s_pot" % el, "%s Potency" % title, "%s states and reactions run stronger." % b, root, pot_key, 0.03, 3)
    _add("el_%s_cap" % el, b, "%s Mastery" % title, "Capstone. %s answers when you call." % b, 3, pot_end, { dmg_key: 0.03, pot_key: 0.03 })
