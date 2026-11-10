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
}
const ORDER := ["blades_only", "no_guns", "one_element"]

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
        "one_element":
            if _element < 0:
                return true
            var d := Guns.make(id)
            return d.element == _element or d.alt_element == _element or d.extra_element == _element
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
        "one_element":
            if player.guns.is_empty():
                player.add_gun("water_pistol", false)
            _element = int(player.guns[0].data.element)
            for g in player.guns.duplicate():
                if g != player.guns[0] and int(g.data.element) != _element:
                    player.drop_gun(g)
    player.say("Trial: %s" % name_of(t))
    print("[TRIAL] %s start weapons=%s" % [t, ",".join(player.guns.map(func(g): return g.data.id))])
