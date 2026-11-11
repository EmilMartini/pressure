class_name Trials
extends RefCounted
## Trials (Arsenal expansion 6.2): Isaac-style challenge runs with one fixed rule, started
## from the board in the Hollow's Stair. Winning one (clearing all five floors under its
## rule) opens its rewards once. Batch 2 has the first three; batch 5 adds the rest (to 12).
##
## The rule lives in two places: `start` fixes the starting weapons, and `allows` filters
## every weapon the run offers (Drops.roll_gun). Progress.trial holds the Trial of the run
## in progress (not saved); a win is kept in Progress.world["trials_won"].
## Bots: `--trial=<id>`.

## The board opens once you have started this many runs (6.3: the first Trial at run 6).
const OPENS_AFTER := 5

const DEFS := {
    "blades_only": { "name": "Blades Only", "rule": "Melee weapons only. You start with a Tin Sabre.",
        "rewards": ["gun:blood_hymn", "item:hunters_oath"] },
    "no_guns": { "name": "No Guns", "rule": "No guns: melee, thrown and the rest only. You start with Steel Knives and a Tin Sabre.",
        "rewards": ["gun:singularity", "item:return_grip"] },
    "one_element": { "name": "One Element", "rule": "Every weapon you find shares your first weapon's element.",
        "rewards": ["gun:glint_beam", "gun:harpoon", "item:pin_cushion"] },
    "summoner": { "name": "Summoner", "rule": "Summons only: no weapon of yours may fire. You start with a Scout Drone.",
        "rewards": ["gun:hive_queen", "item:call_the_swarm", "item:hive_oath"] },
    "ground": { "name": "Ground", "rule": "You can't attack: auras and traps only. You start with an Ember Halo.",
        "rewards": ["gun:ash_garden", "item:seed", "item:earth_oath"] },
    # Batch 5: seven more, to 12. Each opens a legendary early (a second road to its feat).
    "thrown_only": { "name": "Thrown Only", "rule": "Thrown weapons only. You start with Steel Knives.",
        "rewards": ["gun:skyfall"] },
    "gunslinger": { "name": "Gunslinger", "rule": "Guns only. You start with a Water Pistol.",
        "rewards": ["gun:heart_of_the_forge"] },
    "light_touch": { "name": "Light Touch", "rule": "Only weapons of weight 1 or 2.",
        "rewards": ["gun:echo_engine"] },
    "heavy_hand": { "name": "Heavy Hand", "rule": "Only weapons of weight 3 or more. You start with an Arc Rifle.",
        "rewards": ["gun:glass_of_ages"] },
    "commons": { "name": "Commons", "rule": "Only Common and Uncommon weapons.",
        "rewards": ["gun:orrery"] },
    "cold_front": { "name": "Cold Front", "rule": "Only Wet and Ice weapons. You start with a Water Pistol.",
        "rewards": ["gun:tidebreaker"] },
    "pyre": { "name": "Pyre", "rule": "Only Fire weapons. You start with a Flare Pistol.",
        "rewards": ["gun:phoenix_lantern"] },
}
const ORDER := ["blades_only", "no_guns", "one_element", "summoner", "ground", "thrown_only", "gunslinger",
    "light_touch", "heavy_hand", "commons", "cold_front", "pyre"]

static var _element := -1   # one_element: the run's element, fixed at the start


## The Trial of the run in progress, or "".
static func active() -> String:
    if Progress.trial != "":
        return Progress.trial
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--trial="):
            var id := a.substr(8)
            if DEFS.has(id):
                Progress.trial = id
                return id
    return ""


static func open() -> bool:
    # `--trials-open`: the hub walk checks the open board on a young bot save.
    return Progress.stat("runs_started") >= OPENS_AFTER or OS.get_cmdline_user_args().has("--trials-open")


static func won(id: String) -> bool:
    return bool((Progress.world.get("trials_won", {}) as Dictionary).get(id, false))


static func name_of(id: String) -> String:
    return String(DEFS.get(id, {}).get("name", id))


## Whether the run's Trial lets this weapon be offered.
static func allows(id: String) -> bool:
    var t := active()
    if t == "":
        return true
    match t:
        "blades_only":
            return Guns.family_of(id) == "melee"
        "no_guns":
            return Guns.family_of(id) != "gun"
        "summoner":
            return Guns.family_of(id) == "summon"
        "ground":
            return Guns.family_of(id) == "ground"
        "one_element":
            if _element < 0:
                return true
            var d := Guns.make(id)
            return d.element == _element or d.alt_element == _element or d.extra_element == _element
        "thrown_only":
            return Guns.family_of(id) == "thrown"
        "gunslinger":
            return Guns.family_of(id) == "gun"
        "light_touch", "heavy_hand", "cold_front", "pyre":
            return _fits(t, Guns.make(id))
        "commons":
            return Guns.rarity_of(id) <= Items.Rarity.UNCOMMON
    return true


## The batch 5 rules that read the weapon's numbers.
static func _fits(t: String, d: GunData) -> bool:
    match t:
        "light_touch":
            return d.weight <= 2
        "heavy_hand":
            return d.weight >= 3
        "cold_front":
            return d.element in [Element.Kind.WET, Element.Kind.ICE]
        "pyre":
            return d.element == Element.Kind.FIRE
    return true


## The starting weapons under the rule (after the Loadout has given its Kit).
static func start(player: Player) -> void:
    var t := active()
    _element = -1
    if t == "" or player == null:
        return
    match t:
        "blades_only":
            for g in player.guns.duplicate():
                if g.data.family != "melee":
                    player.drop_gun(g)
            if player.guns.is_empty():
                player.add_gun("tin_sabre", false)
        "no_guns":
            for g in player.guns.duplicate():
                if g.data.family == "gun":
                    player.drop_gun(g)
            if player.guns.is_empty():
                player.add_gun("steel_knives", false)
                player.add_gun("tin_sabre", false)
        "summoner":
            for g in player.guns.duplicate():
                if g.data.family != "summon":
                    player.drop_gun(g)
            if player.guns.is_empty():
                player.add_gun("scout_drone", false)
        "ground":
            for g in player.guns.duplicate():
                if g.data.family != "ground":
                    player.drop_gun(g)
            if player.guns.is_empty():
                player.add_gun("ember_halo", false)
        "thrown_only", "gunslinger", "light_touch", "heavy_hand", "commons", "cold_front", "pyre":
            for g in player.guns.duplicate():
                if not allows(g.data.id):
                    player.drop_gun(g)
            if player.guns.is_empty():
                var first := { "thrown_only": "steel_knives", "gunslinger": "water_pistol", "light_touch": "water_pistol",
                    "heavy_hand": "arc_rifle", "commons": "water_pistol", "cold_front": "water_pistol", "pyre": "flare_pistol" }
                player.add_gun(String(first[t]), false)
        "one_element":
            if player.guns.is_empty():
                player.add_gun("water_pistol", false)
            _element = int(player.guns[0].data.element)
            for g in player.guns.duplicate():
                if g != player.guns[0] and int(g.data.element) != _element:
                    player.drop_gun(g)
    player.say("Trial: %s" % name_of(t))
    print("[TRIAL] %s start weapons=%s" % [t, ",".join(player.guns.map(func(g): return g.data.id))])
