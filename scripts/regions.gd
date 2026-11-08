class_name Regions
extends RefCounted
## The Descent: the world graph a run walks down (design/World and progression GDD.md,
## sections 4 and 5). A run takes one region per depth along the edges, from Ossuary Gate
## at depth 1 to The Rift at depth 5. The region sets a floor's theme, its boss and its
## layout; its depth sets difficulty (Main.floor_number is the depth).
##
## Every region of section 4 is listed so the graph is whole, but only `built` regions are
## picked: the six whose themes exist as art. The rest wait for phase 5.
##
## `resists` and `weak` are element names (Element.NAMES). The region the party is in is
## `activate`d by Main.start_floor; every enemy then takes RESISTED damage from a resisted
## element and WEAK from a weakness, and its states of those elements last as much shorter
## or longer (Enemy.resist_mult). A reaction on an enemy leaves it Exposed for EXPOSED_SECS:
## its resistances count as weaknesses, so a resisted build breaks through with reactions.
## `boss` is the region's own boss from the design; `boss_kind` is the SpawnTable boss
## fought there today (a stand-in where the region's own boss is not built yet).
## `layouts` are the region's signature arena layouts (RoomLayouts.FAVOUR_SHARE of arenas).

const FIRST := "ossuary_gate"
const DEPTHS := 5

## Soft resistances (design section 5, locked start values; tune with data).
const RESISTED := 0.6
const WEAK := 1.4
const EXPOSED_SECS := 4.0

## The active region's profile as Element.Kind lists (empty in the hub and Ossuary Gate).
static var active_resists: Array = []
static var active_weak: Array = []
## Bots: `--no-exposed` turns Exposed off to measure what it is worth.
static var exposed_enabled := true
## Counters for bot logs: reactions that exposed an enemy, and damage dealt at each rate.
static var stat_exposed := 0
static var stat_dmg := { "resisted": 0.0, "weak": 0.0, "exposed": 0.0, "plain": 0.0 }

const REGIONS := {
    "ossuary_gate": { "name": "Ossuary Gate", "depth": 1, "theme": "crypt", "built": true,
        "resists": [], "weak": [], "hazards": ["bone piles", "barrels"],
        "boss": "brute_king", "boss_kind": "brute_king",
        "layouts": ["four_pillars", "pillar_hall", "buttresses"],
        "edges": ["drowned_cistern", "rotting_gardens", "rust_ruins"] },

    "drowned_cistern": { "name": "Drowned Cistern", "depth": 2, "theme": "", "built": false,
        "resists": ["Wet"], "weak": ["Shock"], "hazards": ["rising water", "conductive puddles"],
        "boss": "drowned_choir", "boss_kind": "hive_mother",
        "layouts": ["flooded", "channels", "moat"],
        "edges": ["frostvault", "pitch_mire"] },
    "rotting_gardens": { "name": "Rotting Gardens", "depth": 2, "theme": "garden", "built": true,
        "resists": ["Poison"], "weak": ["Fire"], "hazards": ["spore clouds", "gas that ignites"],
        "boss": "hive_mother", "boss_kind": "hive_mother",
        "layouts": ["overgrown", "l_shape", "diagonal"],
        # frostvault: a stand-in way down until Pitch Mire or Abattoir is built (default BQ)
        "edges": ["pitch_mire", "abattoir", "frostvault"] },
    "rust_ruins": { "name": "Rust Ruins", "depth": 2, "theme": "ruins", "built": true,
        "resists": ["Stone"], "weak": ["Acid"], "hazards": ["collapsing floors", "rust dust"],
        "boss": "rusted_colossus", "boss_kind": "hive_mother",
        "layouts": ["broken", "overgrown", "l_shape"],
        "edges": ["frostvault", "abattoir"] },

    "frostvault": { "name": "Frostvault", "depth": 3, "theme": "frozen", "built": true,
        "resists": ["Ice"], "weak": ["Fire"], "hazards": ["ice sheets", "cold that slows"],
        "boss": "frost_matron", "boss_kind": "storm_warden",
        "layouts": ["frozen", "moat", "flooded"],
        "edges": ["stormspire", "the_forge", "chapel_of_ash"] },
    "pitch_mire": { "name": "Pitch Mire", "depth": 3, "theme": "", "built": false,
        "resists": ["Oil"], "weak": ["Fire"], "hazards": ["tar that slows", "oil that can be lit"],
        "boss": "tar_saint", "boss_kind": "storm_warden",
        "layouts": ["refinery", "channels"],
        "edges": ["stormspire", "the_forge"] },
    "abattoir": { "name": "Abattoir", "depth": 3, "theme": "", "built": false,
        "resists": ["Blood"], "weak": ["Holy"], "hazards": ["blood floors that heal enemies"],
        "boss": "butcher_abbot", "boss_kind": "storm_warden",
        "layouts": ["twin", "diagonal"],
        "edges": ["the_forge", "chapel_of_ash"] },

    "stormspire": { "name": "Stormspire", "depth": 4, "theme": "", "built": false,
        "resists": ["Shock"], "weak": ["Stone"], "hazards": ["lightning strikes on a rhythm"],
        "boss": "storm_warden", "boss_kind": "storm_warden",
        "layouts": ["ring", "cross"],
        "edges": ["the_rift"] },
    "the_forge": { "name": "The Forge", "depth": 4, "theme": "forge", "built": true,
        "resists": ["Fire"], "weak": ["Wet", "Ice"], "hazards": ["lava", "steam vents"],
        "boss": "pyre_lord", "boss_kind": "pyre_lord",
        "layouts": ["refinery", "channels", "broken"],
        "edges": ["the_rift"] },
    "chapel_of_ash": { "name": "Chapel of Ash", "depth": 4, "theme": "sanctum", "built": true,
        "resists": ["Holy"], "weak": ["Void"], "hazards": ["light pillars", "consecrated ground"],
        "boss": "ashen_bishop", "boss_kind": "pyre_lord",
        "layouts": ["pillar_hall", "cross", "bastions"],
        "edges": ["the_rift"] },

    "the_rift": { "name": "The Rift", "depth": 5, "theme": "void", "built": true,
        "resists": ["Void"], "weak": ["Holy"], "hazards": ["gravity wells", "collapsing space"],
        "boss": "void_herald", "boss_kind": "void_herald",
        "layouts": ["rift", "pit_maze", "corner_pits"],
        "edges": [] },
}


static func get_region(id: String) -> Dictionary:
    return REGIONS.get(id, REGIONS[FIRST])


static func display_name(id: String) -> String:
    return String(get_region(id)["name"])


static func depth_of(id: String) -> int:
    return int(get_region(id)["depth"])


## Make `id` the region enemies take their resistances from ("" clears it).
static func activate(id: String) -> void:
    active_resists = kinds(get_region(id)["resists"]) if id != "" else []
    active_weak = kinds(get_region(id)["weak"]) if id != "" else []
    Materials.gas_ignites = id != "" and (get_region(id)["hazards"] as Array).has("gas that ignites")


## Element names -> Element.Kind values.
static func kinds(names: Array) -> Array:
    var out: Array = []
    for n in names:
        var k: int = Element.Kind.get(String(n).to_upper(), Element.Kind.NONE)
        if k != Element.Kind.NONE:
            out.append(k)
    return out


static func reset_stats() -> void:
    stat_exposed = 0
    for k in stat_dmg.keys():
        stat_dmg[k] = 0.0


## The built regions one step down from `id` (what a route choice offers).
static func next_options(id: String) -> Array:
    var out: Array = []
    for n in get_region(id)["edges"]:
        if REGIONS.has(n) and bool(REGIONS[n]["built"]):
            out.append(String(n))
    return out


## The next region after `id`: a random built neighbour, "" at the bottom (used when no
## door was taken, e.g. a planned bot route that ran out).
static func pick_next(id: String) -> String:
    var opts := next_options(id)
    return "" if opts.is_empty() else String(opts.pick_random())


## A random route from the top down to `depth` (for bots that start deeper).
static func random_route(depth: int) -> Array:
    var route: Array = [FIRST]
    while route.size() < depth:
        var n := pick_next(String(route[-1]))
        if n == "":
            break
        route.append(n)
    return route


## `--route=a,b,c` (bots): a fixed route, checked against the graph. Returns [] when invalid.
static func parse_route(spec: String) -> Array:
    var route: Array = []
    for part in spec.split(",", false):
        var id := part.strip_edges()
        if not REGIONS.has(id) or not bool(REGIONS[id]["built"]):
            return []
        if route.is_empty():
            if id != FIRST:
                return []
        elif not next_options(String(route[-1])).has(id):
            return []
        route.append(id)
    return route


## The built region drawn with a theme (the themes capture uses it).
static func for_theme(theme: String) -> String:
    for id in REGIONS.keys():
        if bool(REGIONS[id]["built"]) and String(REGIONS[id]["theme"]) == theme:
            return String(id)
    return FIRST


## Graph checks: every edge goes one depth down to a known region, every built region below
## the top has a built way in, and every built region above the bottom has a built way on.
static func validate() -> Array:
    var bad: Array = []
    var reached := { FIRST: true }
    for id in REGIONS.keys():
        var r: Dictionary = REGIONS[id]
        for n in r["edges"]:
            if not REGIONS.has(n):
                bad.append("%s -> unknown %s" % [id, n])
            elif depth_of(String(n)) != int(r["depth"]) + 1:
                bad.append("%s -> %s skips a depth" % [id, n])
        if bool(r["built"]):
            for n in next_options(String(id)):
                reached[n] = true
            if int(r["depth"]) < DEPTHS and next_options(String(id)).is_empty():
                bad.append("%s has no built way down" % id)
    for id in REGIONS.keys():
        if bool(REGIONS[id]["built"]) and not reached.has(id):
            bad.append("%s has no built way in" % id)
    return bad
