extends Node
## Autoload "Progress": the save file. Isaac-style meta progression: every run starts
## naked, and achievements grow the pool of what a run can contain. Nothing here makes
## a run easier; it only makes runs different. It also counts what the current run did
## (`run_stats`, `run_discoveries`), which the Shrine pays Embers for (see Mastery).

signal unlocked(unlock_id: String, achievement_name: String)

const SAVE_PATH := "user://save.json"

## Always available, run one included.
const BASE_UNLOCKS := ["gun:water_pistol", "gun:arc_rifle", "gun:flare_pistol", "gun:slick_wand", "obstacle:pool", "class:vagrant"]

## stat: the Progress stat that counts toward it. goal: the number to reach.
const ACHIEVEMENTS := [
    # Ordered by effort. The first block teaches the basics, Risk of Rain 2 style, and
    # hands out one new element per run (report R8): every goal in it is cumulative and
    # comes from simply playing, so by about run 5 every element is in the pool.
    # Expected run from the bot data (Set A floor-1 runs: 6 distinct reactions, 7 vents,
    # 3 rooms, 0-3 elites, ~100 reactions): ice 1, acid 1-2, poison 2, gale 2-3, blood
    # 2-4, stone 3, void 3, holy 5 (holy waited until a median run of ~45 before).
    # Ids are the old ones wherever the reward stayed put, so saves keep their progress;
    # the old goals behind those ids (375 / 625 kills, 75 Steams, 60 / 240 Chain
    # Lightnings, 900 reactions, 12 runs, 240 Deep Freezes) are gone.
    { "id": "first_blood", "name": "First Blood", "desc": "Kill 50 enemies",
        "stat": "kills", "goal": 50, "rewards": ["gun:blowtorch"] },
    { "id": "conductor", "name": "Chemistry", "desc": "Discover 3 different reactions",
        "stat": "reactions_discovered", "goal": 3, "rewards": ["gun:frost_caster"] },
    { "id": "bloodied", "name": "Blow-off", "desc": "Vent 10 times",
        "stat": "vents", "goal": 10, "rewards": ["gun:etcher_beam"] },
    { "id": "regular", "name": "Regular", "desc": "Start 2 runs",
        "stat": "runs_started", "goal": 2, "rewards": ["gun:spark_needler"] },
    { "id": "chemist", "name": "Housekeeper", "desc": "Clear 5 rooms",
        "stat": "rooms", "goal": 5, "rewards": ["gun:venom_spitter"] },
    { "id": "stormcaller", "name": "Field Notes", "desc": "Discover 6 different reactions",
        "stat": "reactions_discovered", "goal": 6, "rewards": ["gun:gale_blaster", "obstacle:miasma"] },
    { "id": "butcher", "name": "Headhunter", "desc": "Kill 3 elites",
        "stat": "elites", "goal": 3, "rewards": ["gun:blood_lance"] },
    { "id": "veteran", "name": "Persistent", "desc": "Start 3 runs",
        "stat": "runs_started", "goal": 3, "rewards": ["gun:gravel_shotgun"] },
    { "id": "catalyst", "name": "Catalyst", "desc": "Fire 250 reactions",
        "stat": "reactions", "goal": 250, "rewards": ["gun:null_wand"] },
    { "id": "zealot", "name": "Pilgrim", "desc": "Start 5 runs",
        "stat": "runs_started", "goal": 5, "rewards": ["gun:radiant_ray", "obstacle:ward"] },
    # Then exploration and the first specific reactions. Reaction goals were 50 to 90 and
    # swung 5-10x between runs (142 Infernos in one run against a median of 4); they are
    # now about one to three median runs of their pairing (Set A medians per run: Chain
    # Lightning 25, Ignition 17, Steam 4, Inferno 4, Deep Freeze 3, Black Ice 1).
    { "id": "plumber", "name": "Plumber", "desc": "Open a hidden room",
        "stat": "hidden_rooms", "goal": 1, "rewards": ["obstacle:valve", "gun:mist_sprayer"] },
    { "id": "curious", "name": "Curious", "desc": "Find a secret",
        "stat": "secrets_found", "goal": 1, "rewards": ["secret:lantern"] },
    { "id": "arsonist", "name": "Arsonist", "desc": "Fire 30 Infernos or Ignitions",
        "stat": "reactions_fire", "goal": 30, "rewards": ["obstacle:thicket"] },
    { "id": "kettle", "name": "Kettle", "desc": "Fire 10 Steams",
        "stat": "reaction:Steam", "goal": 10, "rewards": ["gun:oil_slinger"] },
    { "id": "sparkplug", "name": "Sparkplug", "desc": "Fire 25 Ignitions",
        "stat": "reaction:Ignition", "goal": 25, "rewards": ["gun:cinder_flak"] },
    { "id": "class_tarsmith", "name": "Pitch Black", "desc": "Fire 30 Ignitions",
        "stat": "reaction:Ignition", "goal": 30, "rewards": ["class:tarsmith"] },
    { "id": "class_stormcaller", "name": "Lightning Rod", "desc": "Fire 40 Chain Lightnings",
        "stat": "reaction:Chain Lightning", "goal": 40, "rewards": ["class:stormcaller"] },
    { "id": "class_pyromancer", "name": "Firestarter", "desc": "Fire 15 Infernos",
        "stat": "reaction:Inferno", "goal": 15, "rewards": ["class:pyromancer"] },
    { "id": "class_tidecaller", "name": "High Tide", "desc": "Fire 20 Steams",
        "stat": "reaction:Steam", "goal": 20, "rewards": ["class:tidecaller"] },
    { "id": "class_frostbinder", "name": "Cold Hands", "desc": "Fire 15 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 15, "rewards": ["class:frostbinder"] },
    { "id": "venter", "name": "Venter", "desc": "Vent 30 novas",
        "stat": "vents", "goal": 30, "rewards": ["gun:hydro_cannon"] },
    { "id": "alchemist", "name": "Alchemist", "desc": "Fire 25 Infernos",
        "stat": "reaction:Inferno", "goal": 25, "rewards": ["gun:acid_flask", "obstacle:rubble"] },
    { "id": "collector", "name": "Collector", "desc": "Equip 8 pieces of gear",
        "stat": "items_picked", "goal": 8, "rewards": ["rarity:epic"] },
    { "id": "slayer", "name": "Slayer", "desc": "Kill 12 elites",
        "stat": "elites", "goal": 12, "rewards": ["gun:ember_carbine"] },
    { "id": "plasma", "name": "Plasma Physicist", "desc": "Fire 15 Plasmas",
        "stat": "reaction:Plasma", "goal": 15, "rewards": ["gun:storm_seeker"] },
    { "id": "black_ice", "name": "Black Ice", "desc": "Fire 15 Black Ices",
        "stat": "reaction:Black Ice", "goal": 15, "rewards": ["gun:rime_chakram"] },
    { "id": "thermal", "name": "Thermal", "desc": "Fire 20 Thermal Shocks",
        "stat": "reaction:Thermal Shock", "goal": 20, "rewards": ["gun:duality_burst"] },
    # Off-element reactions: each needs a gun of both elements, which the first block now
    # delivers by about run 5. No bot data yet for these signatures: 20 for the gun, 25
    # for the class (the class follows the gun on the same reaction).
    { "id": "polluter", "name": "Polluter", "desc": "Fire 20 Contaminations",
        "stat": "reaction:Contamination", "goal": 20, "rewards": ["gun:blight_seeker"] },
    { "id": "fumigator", "name": "Fumigator", "desc": "Fire 20 Noxious Flames",
        "stat": "reaction:Noxious Flame", "goal": 20, "rewards": ["gun:plague_mortar"] },
    { "id": "hemophile", "name": "Hemophile", "desc": "Fire 20 Thin Bloods",
        "stat": "reaction:Thin Blood", "goal": 20, "rewards": ["gun:clot_orb"] },
    { "id": "maelstrom", "name": "Maelstrom", "desc": "Fire 20 Whirlpools",
        "stat": "reaction:Whirlpool", "goal": 20, "rewards": ["gun:rift_seeker"] },
    { "id": "baptist", "name": "Baptist", "desc": "Fire 20 Baptisms",
        "stat": "reaction:Baptism", "goal": 20, "rewards": ["gun:prayer_burst"] },
    { "id": "windbreaker", "name": "Windbreaker", "desc": "Fire 20 Monsoons",
        "stat": "reaction:Monsoon", "goal": 20, "rewards": ["gun:cyclone_flak"] },
    { "id": "class_voidwalker", "name": "Event Horizon", "desc": "Fire 20 Singularities",
        "stat": "reaction:Singularity", "goal": 20, "rewards": ["class:voidwalker"] },
    { "id": "class_alchemist", "name": "Splash Zone", "desc": "Fire 20 Caustic Splashes",
        "stat": "reaction:Caustic Splash", "goal": 20, "rewards": ["class:alchemist"] },
    { "id": "class_stonewarden", "name": "Bog Standard", "desc": "Fire 20 Muds",
        "stat": "reaction:Mud", "goal": 20, "rewards": ["class:stonewarden"] },
    { "id": "class_plaguewright", "name": "Patient Zero", "desc": "Fire 25 Contaminations",
        "stat": "reaction:Contamination", "goal": 25, "rewards": ["class:plaguewright"] },
    { "id": "class_bloodletter", "name": "Leech", "desc": "Fire 25 Thin Bloods",
        "stat": "reaction:Thin Blood", "goal": 25, "rewards": ["class:bloodletter"] },
    { "id": "class_templar", "name": "Anointed", "desc": "Fire 25 Baptisms",
        "stat": "reaction:Baptism", "goal": 25, "rewards": ["class:templar"] },
    { "id": "class_windrunner", "name": "Rainmaker", "desc": "Fire 25 Monsoons",
        "stat": "reaction:Monsoon", "goal": 25, "rewards": ["class:windrunner"] },
    { "id": "annihilator", "name": "Annihilator", "desc": "Fire 15 Annihilations",
        "stat": "reaction:Annihilation", "goal": 15, "rewards": ["gun:eclipse_carbine"] },
    # Depth, bosses and the long tail.
    { "id": "tourist", "name": "Tourist", "desc": "Clear 3 floors",
        "stat": "floors", "goal": 3, "rewards": ["gun:vein_pistol"] },
    { "id": "floor_breaker", "name": "Floor Breaker", "desc": "Kill 2 bosses",
        "stat": "bosses", "goal": 2, "rewards": ["room:challenge", "gun:tar_mortar"] },
    { "id": "delver", "name": "Delver", "desc": "Find 10 secrets",
        "stat": "secrets_found", "goal": 10, "rewards": ["secret:alcove"] },
    { "id": "reactionary", "name": "Reactionary", "desc": "Discover 20 different reactions",
        "stat": "reactions_discovered", "goal": 20, "rewards": ["shop:items"] },
    { "id": "exterminator", "name": "Exterminator", "desc": "Kill 1500 enemies",
        "stat": "kills", "goal": 1500, "rewards": ["gun:corrosion_burst"] },
    { "id": "pressure_cooker", "name": "Pressure Cooker", "desc": "Fire 75 Steams",
        "stat": "reaction:Steam", "goal": 75, "rewards": ["gun:kettle_gun"] },
    { "id": "deep_freezer", "name": "Deep Freezer", "desc": "Fire 50 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 50, "rewards": ["gun:glacier_lance"] },
    { "id": "pyromaniac", "name": "Pyromaniac", "desc": "Fire 90 Infernos",
        "stat": "reaction:Inferno", "goal": 90, "rewards": ["gun:napalm_lobber"] },
    { "id": "hoarder", "name": "Hoarder", "desc": "Equip 25 pieces of gear",
        "stat": "items_picked", "goal": 25, "rewards": ["rarity:legendary"] },
    { "id": "abyss", "name": "Abyss", "desc": "Kill 6 bosses",
        "stat": "bosses", "goal": 6, "rewards": ["gun:void_orb"] },
    { "id": "mason", "name": "Mason", "desc": "Kill 50 elites",
        "stat": "elites", "goal": 50, "rewards": ["gun:stone_sling"] },
    { "id": "riddler", "name": "Riddler", "desc": "Solve every kind of secret",
        "stat": "secret_kinds", "goal": 10, "rewards": ["secret:hoard"] },
    { "id": "explorer", "name": "Explorer", "desc": "Clear 20 floors",
        "stat": "floors", "goal": 20, "rewards": ["gun:zephyr_rang"] },
    { "id": "survivor", "name": "Survivor", "desc": "Clear the dungeon",
        "stat": "runs_won", "goal": 1, "rewards": ["gun:storm_pike", "shop:extra"] },
    { "id": "sunbreaker", "name": "Sunbreaker", "desc": "Kill 12 bosses",
        "stat": "bosses", "goal": 12, "rewards": ["gun:sun_cannon"] },
    { "id": "reaper", "name": "Reaper", "desc": "Kill 3750 enemies",
        "stat": "kills", "goal": 3750, "rewards": ["gun:railgun"] },
    { "id": "spelunker", "name": "Spelunker", "desc": "Clear 50 floors",
        "stat": "floors", "goal": 50, "rewards": ["gun:boulder_mortar"] },
]

var save_path := SAVE_PATH
var unlocks: Dictionary = {}          # unlock id -> true
var stats: Dictionary = {}            # stat -> int
var achievements_done: Dictionary = {}
var history: Array = []               # { won, floor, kills, unlocks }
var run_unlocks: Array = []           # unlock ids earned during the current run
var run_stats: Dictionary = {}        # stat -> amount added during the current run
var run_discoveries: Array = []       # reactions fired for the first time ever, this run
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
        "secret":
            return { "lantern": "More hidden puzzles", "alcove": "More secret alcoves",
                "hoard": "Richer puzzle rewards" }.get(parts[1], parts[1])
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
    var rows: Array = []
    for a in ACHIEVEMENTS:
        if achievements_done.has(a["id"]) or not can_progress(a):
            continue
        var prog := mini(stat(a["stat"]), int(a["goal"]))
        rows.append({ "name": a["name"], "desc": a["desc"], "progress": prog, "goal": a["goal"],
            "frac": float(prog) / float(maxi(1, int(a["goal"]))) })
    # Closest to done first; among equals, the smaller goal.
    rows.sort_custom(func(x, y):
        if not is_equal_approx(float(x["frac"]), float(y["frac"])):
            return float(x["frac"]) > float(y["frac"])
        return int(x["goal"]) < int(y["goal"]))
    return rows.slice(0, count)


## Whether the current pool can move this achievement at all: a reaction goal needs a
## gun of each of its two elements unlocked.
func can_progress(a: Dictionary) -> bool:
    var st: String = a["stat"]
    if not st.begins_with("reaction:"):
        return true
    var d: Dictionary = Elements.def_by_name(st.substr(9))
    if d.is_empty():
        return true
    var have := {}
    for gid in Guns.ids():
        have[Guns.make(gid).element] = true
    return have.has(d["a"]) and have.has(d["b"])


## Icon of an achievement: its first reward's icon (the gun, the class, else a book or
## scroll; see Art.reward_icon_path).
func achievement_icon_path(a: Dictionary) -> String:
    var rewards: Array = a.get("rewards", [])
    return Art.reward_icon_path(String(rewards[0]) if not rewards.is_empty() else "")


func achievement_icon(a: Dictionary) -> Texture2D:
    return Art.icon(achievement_icon_path(a))


func achievements_count() -> int:
    return achievements_done.size()


# --- Recording -------------------------------------------------------------


func add(key: String, amount: int = 1) -> void:
    stats[key] = stat(key) + amount
    run_stats[key] = int(run_stats.get(key, 0)) + amount
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
    if Elements.def_by_name(reaction_name).is_empty():
        return   # "Shield cracked", "ENRAGED" and other popups are not reactions
    stats["reactions"] = stat("reactions") + 1
    if reaction_name in ["Inferno", "Ignition"]:
        stats["reactions_fire"] = stat("reactions_fire") + 1
    if stat("reaction:" + reaction_name) == 0:
        stats["reactions_discovered"] = stat("reactions_discovered") + 1
        run_discoveries.append(reaction_name)
    add("reaction:" + reaction_name)


func discovered(reaction_name: String) -> bool:
    return stat("reaction:" + reaction_name) > 0


## How much of `key` the current run added.
func run_stat(key: String) -> int:
    return int(run_stats.get(key, 0))


func start_run() -> void:
    run_unlocks = []
    run_stats = {}
    run_discoveries = []
    add("runs_started")


func end_run(won: bool, floor_number: int, kills: int, embers: int = 0) -> void:
    history.append({ "won": won, "floor": floor_number, "kills": kills, "unlocks": run_unlocks.duplicate(), "embers": embers })
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
        "version": 2,
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
    _settle()


## Save migration, run on every load (version 1 saves included): an achievement that is
## done always has all its rewards, and one whose goal the save already meets (goals were
## lowered and some ids got new, easier goals in version 2) is granted quietly, with no
## toast and nothing added to the next run's report.
func _settle() -> void:
    var touched := false
    for a in ACHIEVEMENTS:
        var id := String(a["id"])
        if not achievements_done.has(id):
            if stat(String(a["stat"])) < int(a["goal"]):
                continue
            achievements_done[id] = true
            touched = true
        for r in a["rewards"]:
            if not unlocks.has(r):
                unlocks[r] = true
                touched = true
    if touched:
        save()


## Wipe everything: back to a first-ever run.
func reset() -> void:
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    load_save()
