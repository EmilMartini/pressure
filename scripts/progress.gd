extends Node
## Autoload "Progress": the save file. Isaac-style meta progression: every run starts
## naked, and achievements grow the pool of what a run can contain. Nothing here makes
## a run easier; it only makes runs different.

signal unlocked(unlock_id: String, achievement_name: String)

const SAVE_PATH := "user://save.json"

## Always available, run one included.
const BASE_UNLOCKS := ["gun:water_pistol", "gun:arc_rifle", "obstacle:pool"]

## stat: the Progress stat that counts toward it. goal: the number to reach.
const ACHIEVEMENTS := [
    { "id": "first_blood", "name": "First Blood", "desc": "Kill 50 enemies",
        "stat": "kills", "goal": 50, "rewards": ["gun:blowtorch"] },
    { "id": "conductor", "name": "Conductor", "desc": "Fire 20 Chain Lightnings",
        "stat": "reaction:Chain Lightning", "goal": 20, "rewards": ["gun:frost_caster"] },
    { "id": "kettle", "name": "Kettle", "desc": "Fire 10 Steams",
        "stat": "reaction:Steam", "goal": 10, "rewards": ["gun:oil_slinger"] },
    { "id": "arsonist", "name": "Arsonist", "desc": "Fire 10 Infernos or Ignitions",
        "stat": "reactions_fire", "goal": 10, "rewards": ["obstacle:thicket"] },
    { "id": "plumber", "name": "Plumber", "desc": "Open a hidden room",
        "stat": "hidden_rooms", "goal": 1, "rewards": ["obstacle:valve", "gun:mist_sprayer"] },
    { "id": "slayer", "name": "Slayer", "desc": "Kill 5 elites",
        "stat": "elites", "goal": 5, "rewards": ["gun:ember_carbine"] },
    { "id": "floor_breaker", "name": "Floor Breaker", "desc": "Kill a boss",
        "stat": "bosses", "goal": 1, "rewards": ["room:challenge", "gun:tar_mortar"] },
    { "id": "venter", "name": "Venter", "desc": "Vent 15 novas",
        "stat": "vents", "goal": 15, "rewards": ["gun:hydro_cannon"] },
    { "id": "deep_freezer", "name": "Deep Freezer", "desc": "Fire 40 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 40, "rewards": ["gun:glacier_lance"] },
    { "id": "survivor", "name": "Survivor", "desc": "Clear the dungeon",
        "stat": "runs_won", "goal": 1, "rewards": ["gun:storm_pike", "shop:extra"] },
]

var save_path := SAVE_PATH
var unlocks: Dictionary = {}          # unlock id -> true
var stats: Dictionary = {}            # stat -> int
var achievements_done: Dictionary = {}
var history: Array = []               # { won, floor, kills, unlocks }
var run_unlocks: Array = []           # unlock ids earned during the current run


func _ready() -> void:
    load_save()


# --- Queries ---------------------------------------------------------------


func has(unlock_id: String) -> bool:
    return unlocks.has(unlock_id)


func stat(key: String) -> int:
    return int(stats.get(key, 0))


## Human name for an unlock id.
func unlock_label(unlock_id: String) -> String:
    var parts := unlock_id.split(":")
    match parts[0]:
        "gun":
            return Guns.make(parts[1]).display_name
        "obstacle":
            return { "pool": "Pool obstacles", "thicket": "Thicket obstacles", "valve": "Valve obstacles" }.get(parts[1], parts[1])
        "room":
            return "Challenge rooms" if parts[1] == "challenge" else parts[1]
        "shop":
            return "Fourth shop slot"
    return unlock_id


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
    add("reaction:" + reaction_name)


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


## Wipe everything: back to a first-ever run.
func reset() -> void:
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    load_save()
