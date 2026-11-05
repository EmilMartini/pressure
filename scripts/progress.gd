extends Node
## Autoload "Progress": the save file. Isaac-style meta progression: every run starts
## naked, and achievements grow the pool of what a run can contain. Nothing here makes
## a run easier; it only makes runs different.

signal unlocked(unlock_id: String, achievement_name: String)

const SAVE_PATH := "user://save.json"

## Always available, run one included.
const BASE_UNLOCKS := ["gun:water_pistol", "gun:arc_rifle", "gun:flare_pistol", "gun:slick_wand", "obstacle:pool", "class:vagrant"]

## stat: the Progress stat that counts toward it. goal: the number to reach.
const ACHIEVEMENTS := [
    # Ordered by effort (next_goals shows them in this order). The first four land
    # in a first run; after that roughly one per run, then one every two or three.
    { "id": "first_blood", "name": "First Blood", "desc": "Kill 50 enemies",
        "stat": "kills", "goal": 50, "rewards": ["gun:blowtorch"] },
    { "id": "tourist", "name": "Tourist", "desc": "Reach 3 floors",
        "stat": "floors", "goal": 3, "rewards": ["gun:vein_pistol"] },
    { "id": "plumber", "name": "Plumber", "desc": "Open a hidden room",
        "stat": "hidden_rooms", "goal": 1, "rewards": ["obstacle:valve", "gun:mist_sprayer"] },
    { "id": "regular", "name": "Regular", "desc": "Start 2 runs",
        "stat": "runs_started", "goal": 2, "rewards": ["gun:spark_needler"] },
    { "id": "sparkplug", "name": "Sparkplug", "desc": "Fire 30 Ignitions",
        "stat": "reaction:Ignition", "goal": 50, "rewards": ["gun:cinder_flak"] },
    { "id": "kettle", "name": "Kettle", "desc": "Fire 30 Steams",
        "stat": "reaction:Steam", "goal": 50, "rewards": ["gun:oil_slinger"] },
    { "id": "arsonist", "name": "Arsonist", "desc": "Fire 30 Infernos or Ignitions",
        "stat": "reactions_fire", "goal": 30, "rewards": ["obstacle:thicket"] },
    { "id": "bloodied", "name": "Bloodied", "desc": "Kill 375 enemies",
        "stat": "kills", "goal": 375, "rewards": ["gun:etcher_beam"] },
    { "id": "conductor", "name": "Conductor", "desc": "Fire 60 Chain Lightnings",
        "stat": "reaction:Chain Lightning", "goal": 60, "rewards": ["gun:frost_caster"] },
    { "id": "class_tarsmith", "name": "Pitch Black", "desc": "Fire 60 Ignitions",
        "stat": "reaction:Ignition", "goal": 60, "rewards": ["class:tarsmith"] },
    { "id": "slayer", "name": "Slayer", "desc": "Kill 12 elites",
        "stat": "elites", "goal": 12, "rewards": ["gun:ember_carbine"] },
    { "id": "thermal", "name": "Thermal", "desc": "Fire 30 Thermal Shocks",
        "stat": "reaction:Thermal Shock", "goal": 50, "rewards": ["gun:duality_burst"] },
    { "id": "plasma", "name": "Plasma Physicist", "desc": "Fire 30 Plasmas",
        "stat": "reaction:Plasma", "goal": 50, "rewards": ["gun:storm_seeker"] },
    { "id": "floor_breaker", "name": "Floor Breaker", "desc": "Kill 2 bosses",
        "stat": "bosses", "goal": 2, "rewards": ["room:challenge", "gun:tar_mortar"] },
    { "id": "class_stormcaller", "name": "Lightning Rod", "desc": "Fire 90 Chain Lightnings",
        "stat": "reaction:Chain Lightning", "goal": 90, "rewards": ["class:stormcaller"] },
    { "id": "butcher", "name": "Butcher", "desc": "Kill 625 enemies",
        "stat": "kills", "goal": 625, "rewards": ["gun:blood_lance"] },
    { "id": "collector", "name": "Collector", "desc": "Equip 20 pieces of gear",
        "stat": "items_picked", "goal": 20, "rewards": ["rarity:epic"] },
    { "id": "black_ice", "name": "Black Ice", "desc": "Fire 30 Black Ices",
        "stat": "reaction:Black Ice", "goal": 50, "rewards": ["gun:rime_chakram"] },
    { "id": "chemist", "name": "Chemist", "desc": "Fire 75 Steams",
        "stat": "reaction:Steam", "goal": 75, "rewards": ["gun:venom_spitter"] },
    { "id": "polluter", "name": "Polluter", "desc": "Fire 30 Contaminations",
        "stat": "reaction:Contamination", "goal": 50, "rewards": ["gun:blight_seeker"] },
    { "id": "fumigator", "name": "Fumigator", "desc": "Fire 30 Noxious Flames",
        "stat": "reaction:Noxious Flame", "goal": 50, "rewards": ["gun:plague_mortar"] },
    { "id": "hemophile", "name": "Hemophile", "desc": "Fire 30 Thin Bloods",
        "stat": "reaction:Thin Blood", "goal": 50, "rewards": ["gun:clot_orb"] },
    { "id": "maelstrom", "name": "Maelstrom", "desc": "Fire 30 Whirlpools",
        "stat": "reaction:Whirlpool", "goal": 50, "rewards": ["gun:rift_seeker"] },
    { "id": "baptist", "name": "Baptist", "desc": "Fire 30 Baptisms",
        "stat": "reaction:Baptism", "goal": 50, "rewards": ["gun:prayer_burst"] },
    { "id": "windbreaker", "name": "Windbreaker", "desc": "Fire 30 Monsoons",
        "stat": "reaction:Monsoon", "goal": 50, "rewards": ["gun:cyclone_flak"] },
    { "id": "class_tidecaller", "name": "High Tide", "desc": "Fire 90 Steams",
        "stat": "reaction:Steam", "goal": 90, "rewards": ["class:tidecaller"] },
    { "id": "venter", "name": "Venter", "desc": "Vent 30 novas",
        "stat": "vents", "goal": 30, "rewards": ["gun:hydro_cannon"] },
    { "id": "class_frostbinder", "name": "Cold Hands", "desc": "Fire 60 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 60, "rewards": ["class:frostbinder"] },
    { "id": "catalyst", "name": "Catalyst", "desc": "Fire 900 reactions",
        "stat": "reactions", "goal": 900, "rewards": ["gun:null_wand"] },
    { "id": "alchemist", "name": "Alchemist", "desc": "Fire 75 Infernos",
        "stat": "reaction:Inferno", "goal": 75, "rewards": ["gun:acid_flask", "obstacle:rubble"] },
    { "id": "annihilator", "name": "Annihilator", "desc": "Fire 15 Annihilations",
        "stat": "reaction:Annihilation", "goal": 15, "rewards": ["gun:eclipse_carbine"] },
    { "id": "class_voidwalker", "name": "Event Horizon", "desc": "Fire 30 Singularities",
        "stat": "reaction:Singularity", "goal": 50, "rewards": ["class:voidwalker"] },
    { "id": "class_plaguewright", "name": "Patient Zero", "desc": "Fire 60 Contaminations",
        "stat": "reaction:Contamination", "goal": 60, "rewards": ["class:plaguewright"] },
    { "id": "class_pyromancer", "name": "Firestarter", "desc": "Fire 90 Infernos",
        "stat": "reaction:Inferno", "goal": 90, "rewards": ["class:pyromancer"] },
    { "id": "class_bloodletter", "name": "Leech", "desc": "Fire 60 Thin Bloods",
        "stat": "reaction:Thin Blood", "goal": 60, "rewards": ["class:bloodletter"] },
    { "id": "class_alchemist", "name": "Splash Zone", "desc": "Fire 60 Caustic Splashes",
        "stat": "reaction:Caustic Splash", "goal": 60, "rewards": ["class:alchemist"] },
    { "id": "class_templar", "name": "Anointed", "desc": "Fire 60 Baptisms",
        "stat": "reaction:Baptism", "goal": 60, "rewards": ["class:templar"] },
    { "id": "class_windrunner", "name": "Rainmaker", "desc": "Fire 60 Monsoons",
        "stat": "reaction:Monsoon", "goal": 60, "rewards": ["class:windrunner"] },
    { "id": "class_stonewarden", "name": "Bog Standard", "desc": "Fire 60 Muds",
        "stat": "reaction:Mud", "goal": 60, "rewards": ["class:stonewarden"] },
    { "id": "exterminator", "name": "Exterminator", "desc": "Kill 1500 enemies",
        "stat": "kills", "goal": 1500, "rewards": ["gun:corrosion_burst"] },
    { "id": "stormcaller", "name": "Stormcaller", "desc": "Fire 240 Chain Lightnings",
        "stat": "reaction:Chain Lightning", "goal": 240, "rewards": ["gun:gale_blaster", "obstacle:miasma"] },
    { "id": "pressure_cooker", "name": "Pressure Cooker", "desc": "Fire 180 Steams",
        "stat": "reaction:Steam", "goal": 180, "rewards": ["gun:kettle_gun"] },
    { "id": "abyss", "name": "Abyss", "desc": "Kill 6 bosses",
        "stat": "bosses", "goal": 6, "rewards": ["gun:void_orb"] },
    { "id": "deep_freezer", "name": "Deep Freezer", "desc": "Fire 120 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 120, "rewards": ["gun:glacier_lance"] },
    { "id": "explorer", "name": "Explorer", "desc": "Reach 20 floors",
        "stat": "floors", "goal": 20, "rewards": ["gun:zephyr_rang"] },
    { "id": "hoarder", "name": "Hoarder", "desc": "Equip 60 pieces of gear",
        "stat": "items_picked", "goal": 60, "rewards": ["rarity:legendary"] },
    { "id": "mason", "name": "Mason", "desc": "Kill 50 elites",
        "stat": "elites", "goal": 50, "rewards": ["gun:stone_sling"] },
    { "id": "reactionary", "name": "Reactionary", "desc": "Discover 20 different reactions",
        "stat": "reactions_discovered", "goal": 20, "rewards": ["shop:items"] },
    { "id": "veteran", "name": "Veteran", "desc": "Start 12 runs",
        "stat": "runs_started", "goal": 12, "rewards": ["gun:gravel_shotgun"] },
    { "id": "pyromaniac", "name": "Pyromaniac", "desc": "Fire 180 Infernos",
        "stat": "reaction:Inferno", "goal": 180, "rewards": ["gun:napalm_lobber"] },
    { "id": "survivor", "name": "Survivor", "desc": "Clear the dungeon",
        "stat": "runs_won", "goal": 1, "rewards": ["gun:storm_pike", "shop:extra"] },
    { "id": "sunbreaker", "name": "Sunbreaker", "desc": "Kill 12 bosses",
        "stat": "bosses", "goal": 12, "rewards": ["gun:sun_cannon"] },
    { "id": "zealot", "name": "Zealot", "desc": "Fire 240 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 240, "rewards": ["gun:radiant_ray", "obstacle:ward"] },
    { "id": "reaper", "name": "Reaper", "desc": "Kill 3750 enemies",
        "stat": "kills", "goal": 3750, "rewards": ["gun:railgun"] },
    { "id": "spelunker", "name": "Spelunker", "desc": "Reach 50 floors",
        "stat": "floors", "goal": 50, "rewards": ["gun:boulder_mortar"] },
]

var save_path := SAVE_PATH
var unlocks: Dictionary = {}          # unlock id -> true
var stats: Dictionary = {}            # stat -> int
var achievements_done: Dictionary = {}
var history: Array = []               # { won, floor, kills, unlocks }
var run_unlocks: Array = []           # unlock ids earned during the current run
var names: Array = ["", "", "", ""]   # player names; empty falls back to P1..P4
var chosen_class := "vagrant"         # class picked on the menu for player 1; not saved


func _ready() -> void:
    load_save()


# --- Queries ---------------------------------------------------------------


func has(unlock_id: String) -> bool:
    return unlocks.has(unlock_id)


## The name shown for player `i` (0-based): what they typed, else P1..P4.
func player_name(i: int) -> String:
    if i >= 0 and i < names.size() and names[i] != "":
        return names[i]
    return "P%d" % (i + 1)


func set_player_name(i: int, n: String) -> void:
    if i < 0 or i >= names.size():
        return
    names[i] = n.strip_edges().left(12)
    save()


func stat(key: String) -> int:
    return int(stats.get(key, 0))


## Human name for an unlock id.
func unlock_label(unlock_id: String) -> String:
    var parts := unlock_id.split(":")
    match parts[0]:
        "gun":
            return Guns.make(parts[1]).display_name
        "obstacle":
            return { "pool": "Pool obstacles", "thicket": "Thicket obstacles", "valve": "Valve obstacles",
                "ward": "Ward obstacles", "rubble": "Rubble obstacles", "miasma": "Miasma obstacles" }.get(parts[1], parts[1])
        "room":
            return "Challenge rooms" if parts[1] == "challenge" else parts[1]
        "class":
            return "%s class" % Classes.get_def(parts[1]).get("name", parts[1])
        "shop":
            return "Fourth shop slot" if parts[1] == "extra" else "Third shop item"
        "rarity":
            return "%s gear" % parts[1].capitalize()
    return unlock_id


## Which achievement grants an unlock, as "Name: how", or "Starting pool" for base content.
func unlock_source(unlock_id: String) -> String:
    for a in ACHIEVEMENTS:
        if a["rewards"].has(unlock_id):
            return "%s: %s" % [a["name"], a["desc"]]
    if BASE_UNLOCKS.has(unlock_id):
        return "Starting pool"
    return "Not yet obtainable"


## The next few achievements still open, with progress, for the run-end screen.
func next_goals(count: int) -> Array:
    var out: Array = []
    for a in ACHIEVEMENTS:
        if achievements_done.has(a["id"]):
            continue
        out.append({ "name": a["name"], "desc": a["desc"], "progress": mini(stat(a["stat"]), a["goal"]), "goal": a["goal"] })
        if out.size() >= count:
            break
    return out


func achievements_count() -> int:
    return achievements_done.size()


# --- Recording -------------------------------------------------------------


func add(key: String, amount: int = 1) -> void:
    stats[key] = stat(key) + amount
    _check_achievements()


func add_reaction(reaction_name: String) -> void:
    match reaction_name:
        "ELITE", "Shield broken!", "Shield restored!":
            return
        "Path opened!":
            add("hidden_rooms")
            return
        "Fire Nova", "Frost Nova":
            add("vents")
            return
    stats["reactions"] = stat("reactions") + 1
    if reaction_name in ["Inferno", "Ignition"]:
        stats["reactions_fire"] = stat("reactions_fire") + 1
    if stat("reaction:" + reaction_name) == 0:
        stats["reactions_discovered"] = stat("reactions_discovered") + 1
    add("reaction:" + reaction_name)


func discovered(reaction_name: String) -> bool:
    return stat("reaction:" + reaction_name) > 0


func start_run() -> void:
    run_unlocks = []
    add("runs_started")


func end_run(won: bool, floor_number: int, kills: int) -> void:
    history.append({ "won": won, "floor": floor_number, "kills": kills, "unlocks": run_unlocks.duplicate() })
    if history.size() > 50:
        history.pop_front()
    if won:
        add("runs_won")
    save()


func _check_achievements() -> void:
    for a in ACHIEVEMENTS:
        if achievements_done.has(a["id"]):
            continue
        if stat(a["stat"]) >= a["goal"]:
            _grant(a)


func _grant(a: Dictionary) -> void:
    achievements_done[a["id"]] = true
    for r in a["rewards"]:
        if not unlocks.has(r):
            unlocks[r] = true
            run_unlocks.append(r)
            unlocked.emit(r, a["name"])
    save()


# --- Persistence -----------------------------------------------------------


func save() -> void:
    var data := {
        "version": 1,
        "unlocks": unlocks.keys(),
        "stats": stats,
        "achievements": achievements_done.keys(),
        "history": history,
        "names": names,
    }
    var f := FileAccess.open(save_path, FileAccess.WRITE)
    if f == null:
        push_warning("Could not write save file: %s" % save_path)
        return
    f.store_string(JSON.stringify(data, "  "))
    f.close()


func load_save() -> void:
    unlocks = {}
    stats = {}
    achievements_done = {}
    history = []
    for u in BASE_UNLOCKS:
        unlocks[u] = true
    if not FileAccess.file_exists(save_path):
        return
    var f := FileAccess.open(save_path, FileAccess.READ)
    if f == null:
        return
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    if not parsed is Dictionary:
        return
    for u in parsed.get("unlocks", []):
        unlocks[u] = true
    for k in parsed.get("stats", {}).keys():
        stats[k] = int(parsed["stats"][k])
    for a in parsed.get("achievements", []):
        achievements_done[a] = true
    history = parsed.get("history", [])
    var saved_names: Array = parsed.get("names", [])
    for i in mini(4, saved_names.size()):
        names[i] = str(saved_names[i]).strip_edges().left(12)


## Wipe everything: back to a first-ever run.
func reset() -> void:
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    load_save()
