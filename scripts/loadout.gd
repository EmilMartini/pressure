class_name Loadout
extends RefCounted
## Loadouts (World and progression GDD, section 11): one descender, the Vagrant, with four
## slots chosen at the Gate. The old classes split in two: a **Kit** is the starting gun,
## a **Mark** the element affinity, the quirk and the starting item. Picking a class's Kit
## and Mark gives exactly the class's old start (Phase 2 acceptance). A **Relic** is one
## item saved in a Well and bought back from the Wellkeeper; a **Vow** makes the run
## harder for more Embers.
##
## Unlocks live in Progress: "mark:<id>" and "kit:<gun id>". The Unmarked and the bare Kit
## (a pick of two guns at the entrance) are always open. Mark ids are the old class ids,
## so Shrine bounties ("<mark>|<boss>") and telemetry keep their keys.

const AFFINITY_POTENCY := 0.20
const AFFINITY_DMG := 0.10
const BARE_KIT := ""            # no gun: the entrance offers a pick of two

## Mark rows: id (old class id), name, element, starting item, quirk mods, icon.
## Names are placeholders until the writing review (GDD section 9); see PLACEHOLDER.
const MARK_ROWS := [
    ["vagrant", "Unmarked", Element.Kind.NONE, "", { "carry": 1, "scrap_gain": 0.10 }, "item/armor/artefact/urand_ratskin_cloak.png"],
    ["pyromancer", "Mark of the Pyre", Element.Kind.FIRE, "charm_fire", { "max_hp": -10 }, "gui/spells/fire/inner_flame.png"],
    ["tidecaller", "Mark of the Drowned", Element.Kind.WET, "vial_wet", { "max_hp": 10 }, "gui/spells/ice/ensorcelled_hibernation_new.png"],
    ["stormcaller", "Mark of the Storm", Element.Kind.SHOCK, "charm_shock", { "crit": 0.05 }, "gui/spells/air/insulation.png"],
    ["frostbinder", "Mark of the Frost", Element.Kind.ICE, "vial_ice", { "speed": -0.05 }, "gui/spells/ice/ice_form_old.png"],
    ["tarsmith", "Mark of the Pitch", Element.Kind.OIL, "tar_coat", { "armor": 1 }, "gui/spells/earth/ledas_liquefaction.png"],
    ["plaguewright", "Mark of the Plague", Element.Kind.POISON, "vial_poison", { "state_duration": 0.15 }, "gui/spells/poison/olgrebs_toxic_radiance_new.png"],
    ["alchemist", "Mark of the Crucible", Element.Kind.ACID, "reagent_satchel", { "scrap_gain": 0.10 }, "gui/invocations/gozag_potion_petition.png"],
    ["bloodletter", "Mark of the Vein", Element.Kind.BLOOD, "charm_blood", { "lifesteal": 1, "max_hp": -10 }, "gui/spells/necromancy/sublimation_of_blood_old.png"],
    ["voidwalker", "Mark of the Void", Element.Kind.VOID, "vial_void", { "luck": 0.05 }, "gui/spells/translocation/disjunction.png"],
    ["templar", "Mark of the Vigil", Element.Kind.HOLY, "charm_holy", { "regen": 0.3 }, "gui/invocations/tso_bless_weapon.png"],
    ["windrunner", "Mark of the Gale", Element.Kind.GALE, "vial_gale", { "speed": 0.08, "max_hp": -10 }, "gui/spells/air/swiftness_old.png"],
    ["stonewarden", "Mark of the Stone", Element.Kind.STONE, "charm_stone", { "armor": 1, "speed": -0.05, "carry": 2 }, "gui/spells/earth/statue_form_old.png"],
]
const PLACEHOLDER := true       # Mark and Vow names and texts await the section 9 review

## The old classes: class id -> Kit (its starting gun). The Mark id is the class id.
const CLASS_KITS := {
    "vagrant": "", "pyromancer": "flare_pistol", "tidecaller": "water_pistol",
    "stormcaller": "spark_needler", "frostbinder": "frost_caster", "tarsmith": "slick_wand",
    "plaguewright": "venom_spitter", "alchemist": "etcher_beam", "bloodletter": "vein_pistol",
    "voidwalker": "null_wand", "templar": "prayer_burst", "windrunner": "zephyr_rang",
    "stonewarden": "gravel_shotgun",
}
## Kits in display order: bare first, then the old classes' guns.
const KITS := ["", "flare_pistol", "water_pistol", "spark_needler", "frost_caster", "slick_wand",
    "venom_spitter", "etcher_beam", "vein_pistol", "null_wand", "prayer_burst", "zephyr_rang",
    "gravel_shotgun"]

## Vows: id, name, what it does, Ember bonus. "" is no Vow. Placeholder names.
const VOWS := [
    { "id": "", "name": "No Vow", "desc": "The run as it is", "embers": 0.0 },
    { "id": "iron", "name": "Vow of Iron", "desc": "Enemies have 25% more health", "embers": 0.20, "enemy_hp": 1.25 },
    { "id": "glass", "name": "Vow of Glass", "desc": "-30 max HP", "embers": 0.20, "max_hp": -30 },
]

## Relic price in Embers by rarity (common .. legendary).
const RELIC_PRICES := [15, 30, 45, 60, 75]

static var _marks: Array = []


# --- Marks ---------------------------------------------------------------------


## Every Mark in display order, the Unmarked first.
static func marks() -> Array:
    if _marks.is_empty():
        for r in MARK_ROWS:
            var row: Array = r
            var mods: Dictionary = {}
            var element := int(row[2])
            if element != Element.Kind.NONE:
                var ek := String(Element.NAMES[element]).to_lower()
                mods["potency_" + ek] = AFFINITY_POTENCY
                mods["dmg_" + ek] = AFFINITY_DMG
            var quirk: Dictionary = row[4]
            for k in quirk.keys():
                mods[k] = quirk[k]
            _marks.append({ "id": row[0], "name": row[1], "element": element, "start_item": row[3],
                "mods": mods, "icon": row[5], "tint": Element.COLORS[element] })
    return _marks


static func mark(id: String) -> Dictionary:
    for m in marks():
        if m["id"] == id:
            return m
    return {}


static func mark_name(id: String) -> String:
    return String(mark(id).get("name", id))


static func mark_unlocked(id: String) -> bool:
    return id == "vagrant" or Progress.has("mark:" + id)


static func unlocked_marks() -> Array:
    var out: Array = []
    for m in marks():
        if mark_unlocked(String(m["id"])):
            out.append(m["id"])
    return out


## The Mark's accent colour on the figure; transparent for the Unmarked.
static func accent(id: String) -> Color:
    var m := mark(id)
    if m.is_empty() or int(m["element"]) == Element.Kind.NONE:
        return Color(0, 0, 0, 0)
    return m["tint"]


static func mark_icon(id: String) -> Texture2D:
    return Art.icon(String(mark(id).get("icon", "")), Vector2i(31, 0))


static func mark_icon_path(id: String) -> String:
    return String(mark(id).get("icon", ""))


# --- Kits ----------------------------------------------------------------------


static func kit_unlocked(gun_id: String) -> bool:
    return gun_id == BARE_KIT or Progress.has("kit:" + gun_id)


static func kit_name(gun_id: String) -> String:
    if gun_id == BARE_KIT:
        return "Bare hands"
    var gd: GunData = Guns.make(gun_id)
    return gd.display_name if gd != null else gun_id


# --- Vows and Relics -------------------------------------------------------------


static func vow(id: String) -> Dictionary:
    for v in VOWS:
        if v["id"] == id:
            return v
    return VOWS[0]


## The run's Vow (player 1's loadout).
static func run_vow() -> Dictionary:
    return vow(String(Progress.loadout.get("vow", "")))


static func vow_enemy_hp() -> float:
    return float(run_vow().get("enemy_hp", 1.0))


static func vow_embers() -> float:
    return float(run_vow().get("embers", 0.0))


static func relic_price(item_id: String) -> int:
    var r := clampi(int(Items.get_item(item_id).get("rarity", 0)), 0, RELIC_PRICES.size() - 1)
    return int(RELIC_PRICES[r])


# --- Applying ------------------------------------------------------------------


## The loadout Progress holds, with anything locked or unknown swapped for the default.
static func current() -> Dictionary:
    var lo: Dictionary = Progress.loadout
    var out := { "kit": String(lo.get("kit", BARE_KIT)), "mark": String(lo.get("mark", "vagrant")),
        "relic": String(lo.get("relic", "")), "vow": String(lo.get("vow", "")) }
    if not kit_unlocked(out["kit"]) or not KITS.has(out["kit"]):
        out["kit"] = BARE_KIT
    if mark(out["mark"]).is_empty() or not mark_unlocked(out["mark"]):
        out["mark"] = "vagrant"
    if out["relic"] != "" and not Progress.relics.has(out["relic"]):
        out["relic"] = ""
    if vow(out["vow"])["id"] != out["vow"]:
        out["vow"] = ""
    return out


## The loadout an old class stood for: its gun as the Kit, the class as the Mark.
static func from_class(class_id: String) -> Dictionary:
    return { "kit": String(CLASS_KITS.get(class_id, BARE_KIT)), "mark": class_id if CLASS_KITS.has(class_id) else "vagrant", "relic": "", "vow": "" }


## Fit a freshly spawned player out: the Mark (stats, item), the Kit (gun), the Relic, the
## Vow, full health. A bare Kit leaves the player unarmed (the entrance offers two guns).
static func apply(player, lo: Dictionary) -> void:
    var m := mark(String(lo.get("mark", "vagrant")))
    if m.is_empty():
        m = mark("vagrant")
    var mods: Dictionary = m["mods"]
    for k in mods.keys():
        player.bonus_stats[k] = float(player.bonus_stats.get(k, 0.0)) + float(mods[k])
    var v := vow(String(lo.get("vow", "")))
    if v.has("max_hp"):
        player.bonus_stats["max_hp"] = float(player.bonus_stats.get("max_hp", 0.0)) + float(v["max_hp"])
    player.recalc_stats()
    var kit := String(lo.get("kit", BARE_KIT))
    if kit != BARE_KIT:
        player.add_gun(kit)
    var item_id := String(m["start_item"])
    if item_id != "":
        player.equip(item_id)
    var relic := String(lo.get("relic", ""))
    if relic != "" and not Items.get_item(relic).is_empty():
        player.equip(relic)
    player.hp = player.max_hp
    player.set_meta("mark_id", m["id"])
    player.set_meta("kit_id", kit)
    player.say(String(m["name"]))


# --- Text for menus ------------------------------------------------------------


## "Fire: +20% potency, +10% damage", or "No element" for the Unmarked.
static func affinity_text(m: Dictionary) -> String:
    if int(m["element"]) == Element.Kind.NONE:
        return "No element"
    return "%s: +%d%% potency, +%d%% damage" % [Element.NAMES[m["element"]],
        roundi(AFFINITY_POTENCY * 100.0), roundi(AFFINITY_DMG * 100.0)]


## The non-affinity modifiers in one line, e.g. "-10 max HP, +8% speed".
static func quirk_text(m: Dictionary) -> String:
    var parts: Array = []
    var mods: Dictionary = m["mods"]
    for k in mods.keys():
        var key := String(k)
        if key.begins_with("potency_") or key.begins_with("dmg_"):
            continue
        var val := float(mods[k])
        var sgn := "+" if val >= 0.0 else "-"
        var a := absf(val)
        match key:
            "max_hp":
                parts.append("%s%d max HP" % [sgn, roundi(a)])
            "armor":
                parts.append("%s%d armour" % [sgn, roundi(a)])
            "carry":
                parts.append("%s%d carry" % [sgn, roundi(a)])
            "lifesteal":
                parts.append("%s%d HP per reaction" % [sgn, roundi(a)])
            "regen":
                parts.append("%s%.1f HP/s" % [sgn, a])
            "speed":
                parts.append("%s%d%% speed" % [sgn, roundi(a * 100.0)])
            "scrap_gain":
                parts.append("%s%d%% scrap" % [sgn, roundi(a * 100.0)])
            "luck":
                parts.append("%s%d%% luck" % [sgn, roundi(a * 100.0)])
            "crit":
                parts.append("%s%d%% crit" % [sgn, roundi(a * 100.0)])
            "state_duration":
                parts.append("%s%d%% state duration" % [sgn, roundi(a * 100.0)])
            _:
                parts.append("%s%s %s" % [sgn, str(a), key])
    return ", ".join(parts)


## How a locked Mark or Kit ("mark:<id>" / "kit:<gun>") is earned, with progress.
static func unlock_text(unlock_id: String) -> String:
    var g := unlock_goal(unlock_id)
    if g.is_empty():
        return "Not yet obtainable"
    return "%s  (%d / %d)" % [g["desc"], int(g["have"]), int(g["goal"])]


## { desc, have, goal } of the achievement that grants `unlock_id`, or {}.
static func unlock_goal(unlock_id: String) -> Dictionary:
    for a in Progress.ACHIEVEMENTS:
        if (a["rewards"] as Array).has(unlock_id):
            var goal := int(a["goal"])
            return { "desc": a["desc"], "have": mini(int(Progress.stat(String(a["stat"]))), goal), "goal": goal }
    return {}
