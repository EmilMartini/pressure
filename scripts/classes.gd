class_name Classes
extends RefCounted
## Starting classes, Dark Souls style. A class only shapes the first room: a starting
## gun, one piece of gear, an elemental affinity and one small quirk. After that the run
## goes wherever it goes. Unlocks are "class:<id>" in Progress, granted by achievements.

const AFFINITY_POTENCY := 0.20
const AFFINITY_DMG := 0.10

## Class id -> icon under Art.ICON_ROOT: a spell from the class's element school (a
## figure where the pack has one), a ragged cloak for the elementless Vagrant.
const ICONS := {
    "vagrant": "item/armor/artefact/urand_ratskin_cloak.png",
    "pyromancer": "gui/spells/fire/inner_flame.png",
    "tidecaller": "gui/spells/ice/ensorcelled_hibernation_new.png",
    "stormcaller": "gui/spells/air/insulation.png",
    "frostbinder": "gui/spells/ice/ice_form_old.png",
    "tarsmith": "gui/spells/earth/ledas_liquefaction.png",
    "plaguewright": "gui/spells/poison/olgrebs_toxic_radiance_new.png",
    "alchemist": "gui/invocations/gozag_potion_petition.png",
    "bloodletter": "gui/spells/necromancy/sublimation_of_blood_old.png",
    "voidwalker": "gui/spells/translocation/disjunction.png",
    "templar": "gui/invocations/tso_bless_weapon.png",
    "windrunner": "gui/spells/air/swiftness_old.png",
    "stonewarden": "gui/spells/earth/statue_form_old.png",
}

static var _cache: Array = []


## Every class in display order, Vagrant first.
static func all() -> Array:
    if _cache.is_empty():
        _cache = [
            _make("vagrant", "Vagrant", Element.Kind.NONE,
                "Nothing to your name but a sharp eye.\nThe entrance offers two guns; take one.",
                "", "", { "carry": 1, "scrap_gain": 0.10 }, ""),
            _make("pyromancer", "Pyromancer", Element.Kind.FIRE,
                "Burned the bridge, then the village.\nFragile, but everything else burns faster.",
                "flare_pistol", "charm_fire", { "max_hp": -10 }, "class_pyromancer"),
            _make("tidecaller", "Tidecaller", Element.Kind.WET,
                "Raised on a drowned coast.\nSoaks the room and outlasts it.",
                "water_pistol", "vial_wet", { "max_hp": 10 }, "class_tidecaller"),
            _make("stormcaller", "Stormcaller", Element.Kind.SHOCK,
                "Struck twice and liked it.\nHits land a little harder, a little luckier.",
                "spark_needler", "charm_shock", { "crit": 0.05 }, "class_stormcaller"),
            _make("frostbinder", "Frostbinder", Element.Kind.ICE,
                "Patient as a glacier, and as quick.\nFreezes first, asks questions never.",
                "frost_caster", "vial_ice", { "speed": -0.05 }, "class_frostbinder"),
            _make("tarsmith", "Tarsmith", Element.Kind.OIL,
                "Works the pitch pits under the city.\nSlick hands, thick hide.",
                "slick_wand", "tar_coat", { "armor": 1 }, "class_tarsmith"),
            _make("plaguewright", "Plaguewright", Element.Kind.POISON,
                "Keeps the old sicknesses in jars.\nEvery state lingers a little longer.",
                "venom_spitter", "vial_poison", { "state_duration": 0.15 }, "class_plaguewright"),
            _make("alchemist", "Alchemist", Element.Kind.ACID,
                "Dissolves what it cannot sell.\nSells what it cannot dissolve.",
                "etcher_beam", "reagent_satchel", { "scrap_gain": 0.10 }, "class_alchemist"),
            _make("bloodletter", "Bloodletter", Element.Kind.BLOOD,
                "Pays in blood, collects in blood.\nEvery reaction feeds the wound.",
                "vein_pistol", "charm_blood", { "lifesteal": 1, "max_hp": -10 }, "class_bloodletter"),
            _make("voidwalker", "Voidwalker", Element.Kind.VOID,
                "Stepped into the dark and came back.\nThe dark sends gifts now and then.",
                "null_wand", "vial_void", { "luck": 0.05 }, "class_voidwalker"),
            _make("templar", "Templar", Element.Kind.HOLY,
                "Sworn to a god nobody else hears.\nWounds close slowly, but they close.",
                "prayer_burst", "charm_holy", { "regen": 0.3 }, "class_templar"),
            _make("windrunner", "Windrunner", Element.Kind.GALE,
                "Never where the blow lands.\nFast and light, too light.",
                "zephyr_rang", "vial_gale", { "speed": 0.08, "max_hp": -10 }, "class_windrunner"),
            _make("stonewarden", "Stonewarden", Element.Kind.STONE,
                "Carries the mountain on its back.\nSlow, sturdy, and strong enough to haul it.",
                "gravel_shotgun", "charm_stone", { "armor": 1, "speed": -0.05, "carry": 2 }, "class_stonewarden"),
        ]
    return _cache


## Icon path of a class (its "icon" field), "" when it has none.
static func icon_path(c: Dictionary) -> String:
    return String(c.get("icon", ""))


## A class's icon texture (a 1-bit figure when the class has no icon).
static func icon(c: Dictionary) -> Texture2D:
    return Art.icon(icon_path(c), Vector2i(31, 0))


## One class by id, or {} when unknown.
static func get_def(id: String) -> Dictionary:
    for c in all():
        if c["id"] == id:
            return c
    return {}


## Ids of the classes this save has unlocked, in display order.
static func unlocked() -> Array:
    var out: Array = []
    for c in all():
        if Progress.has("class:" + String(c["id"])):
            out.append(c["id"])
    if out.is_empty():
        out.append("vagrant")
    return out


static func is_unlocked(id: String) -> bool:
    return id == "vagrant" or Progress.has("class:" + id)


## Fit a freshly spawned player out as class `id`: stats, starting gun, starting gear,
## full health. The Vagrant gets no gun; the entrance offers it a pick of two.
static func apply(player, id: String) -> void:
    var c := get_def(id)
    if c.is_empty():
        c = get_def("vagrant")
    var mods: Dictionary = c["mods"]
    for k in mods.keys():
        player.bonus_stats[k] = float(player.bonus_stats.get(k, 0.0)) + float(mods[k])
    player.recalc_stats()
    var gun_id: String = c["start_gun"]
    if c["id"] != "vagrant" and gun_id != "":
        player.add_gun(gun_id)
    var item_id: String = c["start_item"]
    if item_id != "":
        player.equip(item_id)
    player.hp = player.max_hp
    player.set_meta("class_id", c["id"])
    player.say(String(c["name"]))


# --- Text for menus ------------------------------------------------------------


## "Fire: +20% potency, +10% damage", or "No element" for the Vagrant.
static func affinity_text(c: Dictionary) -> String:
    if c["element"] == Element.Kind.NONE:
        return "No element"
    return "%s: +%d%% potency, +%d%% damage" % [Element.NAMES[c["element"]],
        roundi(AFFINITY_POTENCY * 100.0), roundi(AFFINITY_DMG * 100.0)]


## The non-affinity modifiers in one line, e.g. "-10 max HP, +8% speed".
static func quirk_text(c: Dictionary) -> String:
    var parts: Array = []
    var mods: Dictionary = c["mods"]
    for k in mods.keys():
        var key := String(k)
        if key.begins_with("potency_") or key.begins_with("dmg_"):
            continue
        var v := float(mods[k])
        var sgn := "+" if v >= 0.0 else "-"
        var a := absf(v)
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


## How a locked class is earned, with progress: "Fire 30 Infernos  (12 / 30)".
static func unlock_text(c: Dictionary) -> String:
    var want := "class:" + String(c["id"])
    for a in Progress.ACHIEVEMENTS:
        if (a["rewards"] as Array).has(want):
            var goal := int(a["goal"])
            var have := mini(int(Progress.stat(String(a["stat"]))), goal)
            return "%s  (%d / %d)" % [a["desc"], have, goal]
    return "Not yet obtainable"


static func _make(id: String, title: String, element: int, desc: String, start_gun: String,
        start_item: String, quirk: Dictionary, unlock: String) -> Dictionary:
    var mods: Dictionary = {}
    if element != Element.Kind.NONE:
        var ek := String(Element.NAMES[element]).to_lower()
        mods["potency_" + ek] = AFFINITY_POTENCY
        mods["dmg_" + ek] = AFFINITY_DMG
    for k in quirk.keys():
        mods[k] = quirk[k]
    return {
        "id": id, "name": title, "element": element, "desc": desc,
        "start_gun": start_gun, "start_item": start_item, "mods": mods,
        "tint": Element.COLORS[element], "unlock": unlock, "icon": String(ICONS.get(id, "")),
    }
