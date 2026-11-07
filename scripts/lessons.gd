class_name Lessons
extends RefCounted
## Death teaches (World and progression GDD, section 10). One lesson per built boss and per
## built region: the first death to it unlocks a counter to what killed you (a gun that
## hits its weakness or tears its parts), never raw power. Back in the Hollow the Archivist,
## or the Gatewarden until the Archivist is home, names the killer and gives the hint:
## vague after the first death, plain from the third (`hint`).
##
## Keys: "boss:<boss kind>" when you die in a boss room, "region:<region id>" anywhere else
## (`Lessons.killer_key`). The counter guns moved here from today's achievements (their
## achievements stay as milestones so old saves keep their progress); see
## `MOVED_FROM` in the Phase 3 handoff.
##
## PLACEHOLDER: names and hints are plain, functional stand-ins until the voice sheets are
## approved; the real lines go through the section 9 review.

const PLAIN_AFTER := 3

const LESSONS := {
    "boss:brute_king": { "name": "The Brute King", "rewards": ["gun:oil_slinger"], "placeholder": true,
        "vague": "Its plates soak up plain shots.",
        "plain": "Reactions wear its plates down, and a barrel blast tears them off." },
    "boss:hive_mother": { "name": "The Hive Mother", "rewards": ["gun:ember_carbine"], "placeholder": true,
        "vague": "The sacs on its back feed the swarm.",
        "plain": "Firedamp on the sacs tears them. Fire first, then gas." },
    "boss:storm_warden": { "name": "The Storm Warden", "rewards": ["gun:stone_sling"], "placeholder": true,
        "vague": "The rods carry its charge.",
        "plain": "Ground the rods three times with stone and they break. A Storm Cloud on the core overloads it." },
    "boss:pyre_lord": { "name": "The Pyre Lord", "rewards": ["gun:glacier_lance", "gun:hydro_cannon"], "placeholder": true,
        "vague": "Its armour shrugs off cold and sparks.",
        "plain": "Steam the armour first. After that, ice and shock get through." },
    "boss:void_herald": { "name": "The Void Herald", "rewards": ["gun:sun_cannon"], "placeholder": true,
        "vague": "It steals the element you lean on.",
        "plain": "Holy hurts it. Any Rift fusion collapses the shards." },
    "region:ossuary_gate": { "name": "Ossuary Gate", "rewards": ["gun:cinder_flak"], "placeholder": true,
        "vague": "The barrels down there aren't decoration.",
        "plain": "Fire sets the barrels off. Pull the crowd onto them first." },
    "region:rust_ruins": { "name": "Rust Ruins", "rewards": ["gun:acid_flask"], "placeholder": true,
        "vague": "Everything in the Ruins is half stone.",
        "plain": "Stone is resisted there and acid is weak. Bring acid." },
    "region:frostvault": { "name": "Frostvault", "rewards": ["gun:napalm_lobber"], "placeholder": true,
        "vague": "Cold doesn't hurt what lives in the cold.",
        "plain": "Ice is resisted in the Frostvault. Fire is weak." },
    "region:the_forge": { "name": "The Forge", "rewards": ["gun:rime_chakram"], "placeholder": true,
        "vague": "Fire feeds the Forge.",
        "plain": "Fire is resisted in the Forge. Water and ice are weak." },
    "region:chapel_of_ash": { "name": "Chapel of Ash", "rewards": ["gun:void_orb"], "placeholder": true,
        "vague": "The Chapel's light is on its own side.",
        "plain": "Holy is resisted in the Chapel. Void is weak." },
    "region:the_rift": { "name": "The Rift", "rewards": ["gun:eclipse_carbine"], "placeholder": true,
        "vague": "The Rift is made of the same stuff it throws.",
        "plain": "Void is resisted in the Rift. Holy is weak." },
}


## The lesson key for a death: the boss if you fell in its room, else the region.
static func killer_key(region_id: String, in_boss_room: bool) -> String:
    if region_id == "":
        return ""
    if in_boss_room:
        return "boss:" + String(Regions.get_region(region_id).get("boss_kind", ""))
    return "region:" + region_id


static func has_lesson(key: String) -> bool:
    return LESSONS.has(key)


static func lesson_name(key: String) -> String:
    return String(LESSONS.get(key, {}).get("name", ""))


## The hint for `key` after `deaths` deaths to it: vague at first, plain from PLAIN_AFTER.
static func hint(key: String, deaths: int) -> String:
    var l: Dictionary = LESSONS.get(key, {})
    if l.is_empty():
        return ""
    return String(l["plain"] if deaths >= PLAIN_AFTER else l["vague"])


## The lesson that unlocks `unlock_id`, or "".
static func source_of(unlock_id: String) -> String:
    for k in LESSONS.keys():
        if (LESSONS[k]["rewards"] as Array).has(unlock_id):
            return String(k)
    return ""
