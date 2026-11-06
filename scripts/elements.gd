class_name Element
extends Node
## Element kinds, colours, pressure weights, and the reaction table.
## Constants are reachable as `Element.X`; the autoload instance is `Elements`.
##
## Reactions are data. Each entry pairs two elements with a list of actions run on the
## enemy that reacted, scaled by the hit's potency:
##   ["damage", mult]                      hit the target
##   ["burst", radius, mult]               hit everything in range (target included)
##   ["apply", element, radius]            put an element on enemies in range (0 = target)
##   ["burn", mult, secs]  ["poison", mult, secs]  ["bleed", mult, secs]
##   ["corrode", secs]                     target takes +50% damage
##   ["freeze", secs]  ["stun", secs]  ["slow", factor, secs, radius]
##   ["pull", radius, strength]  ["push", radius, strength]
##   ["chain", mult]                       chain lightning along wet enemies
##   ["chain_state", element, mult]        arc to enemies carrying an element
##   ["cloud", element, radius, secs]      a lingering patch that keeps applying an element
##   ["purge", mult]                       strip every state, damage per state stripped
##   ["spread", element, radius]           copy the target's element to neighbours
##   ["decay", fraction]                   damage as a share of max HP
##   ["heal_source", amount]               heal whoever caused it

enum Kind { NONE, WET, SHOCK, FIRE, ICE, OIL, POISON, ACID, BLOOD, VOID, HOLY, GALE, STONE }

const ALL := [Kind.WET, Kind.SHOCK, Kind.FIRE, Kind.ICE, Kind.OIL, Kind.POISON, Kind.ACID,
    Kind.BLOOD, Kind.VOID, Kind.HOLY, Kind.GALE, Kind.STONE]

const NAMES := {
    Kind.NONE: "None", Kind.WET: "Wet", Kind.SHOCK: "Shock", Kind.FIRE: "Fire", Kind.ICE: "Ice",
    Kind.OIL: "Oil", Kind.POISON: "Poison", Kind.ACID: "Acid", Kind.BLOOD: "Blood", Kind.VOID: "Void",
    Kind.HOLY: "Holy", Kind.GALE: "Gale", Kind.STONE: "Stone",
}

const COLORS := {
    Kind.NONE: Color.WHITE,
    Kind.WET: Color(0.30, 0.60, 1.00),
    Kind.SHOCK: Color(1.00, 0.95, 0.30),
    Kind.FIRE: Color(1.00, 0.45, 0.15),
    Kind.ICE: Color(0.70, 0.95, 1.00),
    Kind.OIL: Color(0.45, 0.32, 0.25),
    Kind.POISON: Color(0.45, 0.90, 0.20),
    Kind.ACID: Color(0.80, 1.00, 0.25),
    Kind.BLOOD: Color(0.85, 0.12, 0.18),
    Kind.VOID: Color(0.55, 0.25, 0.85),
    Kind.HOLY: Color(1.00, 0.95, 0.70),
    Kind.GALE: Color(0.75, 0.92, 0.88),
    Kind.STONE: Color(0.62, 0.56, 0.46),
}

## Positive pushes the pressure gauge hot, negative pushes it cold.
const PRESSURE := {
    Kind.NONE: 0.0, Kind.WET: -1.0, Kind.SHOCK: 1.0, Kind.FIRE: 1.5, Kind.ICE: -1.5, Kind.OIL: 0.0,
    Kind.POISON: 0.0, Kind.ACID: 0.5, Kind.BLOOD: 0.0, Kind.VOID: -0.5, Kind.HOLY: 1.0, Kind.GALE: -0.5, Kind.STONE: 0.0,
}

## How long an applied state lingers on an enemy, in seconds.
const DURATION := {
    Kind.WET: 6.0, Kind.SHOCK: 3.0, Kind.FIRE: 4.0, Kind.ICE: 5.0, Kind.OIL: 8.0, Kind.POISON: 6.0,
    Kind.ACID: 5.0, Kind.BLOOD: 6.0, Kind.VOID: 4.0, Kind.HOLY: 4.0, Kind.GALE: 3.0, Kind.STONE: 6.0,
}

## The table. a + b, a name, what it does in words, a sound, an fx texture key, and actions.
const DEFS := [
    # --- Wet
    { "a": Kind.WET, "b": Kind.SHOCK, "name": "Chain Lightning", "desc": "Lightning jumps between wet enemies", "sound": "react_chain", "fx": "spark", "do": [["chain", 3.0]] },
    { "a": Kind.WET, "b": Kind.FIRE, "name": "Steam", "desc": "A scalding cloud that slows everything in it; charge it with lightning", "sound": "react_steam", "fx": "smoke", "do": [["burst", 130, 2.0], ["slow", 0.5, 3.0, 130], ["cloud", Kind.WET, 130, 3.5]] },
    { "a": Kind.WET, "b": Kind.ICE, "name": "Deep Freeze", "desc": "Frozen solid: takes triple damage, shatters on death", "sound": "react_freeze", "fx": "magic", "do": [["damage", 1.0], ["freeze", 3.0]] },
    { "a": Kind.WET, "b": Kind.POISON, "name": "Contamination", "desc": "Poison dissolves and spreads through the wet", "sound": "react_steam", "fx": "smoke", "do": [["damage", 1.0], ["apply", Kind.POISON, 140]] },
    { "a": Kind.WET, "b": Kind.ACID, "name": "Caustic Splash", "desc": "Acid sprays onto everything nearby", "sound": "react_steam", "fx": "circle", "do": [["burst", 110, 1.5], ["apply", Kind.ACID, 110]] },
    { "a": Kind.WET, "b": Kind.BLOOD, "name": "Thin Blood", "desc": "Heavy bleeding, and the blood feeds you", "sound": "hit", "fx": "circle", "do": [["bleed", 2.5, 5.0], ["heal_source", 3]] },
    { "a": Kind.WET, "b": Kind.VOID, "name": "Whirlpool", "desc": "Drags nearby enemies into the target", "sound": "react_steam", "fx": "twirl", "do": [["pull", 220, 320], ["damage", 1.5]] },
    { "a": Kind.WET, "b": Kind.HOLY, "name": "Baptism", "desc": "Strips every state and punishes each one", "sound": "shield_break", "fx": "light", "do": [["purge", 3.0]] },
    { "a": Kind.WET, "b": Kind.GALE, "name": "Monsoon", "desc": "Soaks and shoves everything nearby", "sound": "react_steam", "fx": "smoke", "do": [["apply", Kind.WET, 180], ["push", 180, 380], ["damage", 1.0]] },
    { "a": Kind.WET, "b": Kind.STONE, "name": "Mud", "desc": "A mire that bogs enemies down", "sound": "die", "fx": "smoke", "do": [["damage", 1.0], ["slow", 0.3, 5.0, 150]] },
    # --- Shock
    { "a": Kind.SHOCK, "b": Kind.FIRE, "name": "Plasma", "desc": "A searing detonation", "sound": "react_inferno", "fx": "flame", "do": [["burst", 120, 3.5]] },
    { "a": Kind.SHOCK, "b": Kind.ICE, "name": "Cryoshock", "desc": "A jolt through a frozen body cracks it", "sound": "react_freeze", "fx": "spark", "do": [["damage", 3.0], ["stun", 1.5]] },
    { "a": Kind.SHOCK, "b": Kind.POISON, "name": "Galvanic Rot", "desc": "Poison leaps along the current", "sound": "react_chain", "fx": "spark", "do": [["poison", 1.5, 5.0], ["spread", Kind.POISON, 200], ["damage", 1.0]] },
    { "a": Kind.SHOCK, "b": Kind.ACID, "name": "Electrolysis", "desc": "Corrodes and blasts", "sound": "react_ignition", "fx": "spark", "do": [["corrode", 6.0], ["burst", 100, 2.0]] },
    { "a": Kind.SHOCK, "b": Kind.BLOOD, "name": "Defibrillate", "desc": "A stopping jolt", "sound": "react_chain", "fx": "light", "do": [["damage", 4.0], ["stun", 1.5]] },
    { "a": Kind.SHOCK, "b": Kind.VOID, "name": "Singularity", "desc": "Everything nearby is yanked in and crushed", "sound": "nova_frost", "fx": "twirl", "do": [["pull", 260, 520], ["burst", 90, 3.0]] },
    { "a": Kind.SHOCK, "b": Kind.HOLY, "name": "Smite", "desc": "One enormous strike", "sound": "shield_break", "fx": "light", "do": [["damage", 9.0]] },
    { "a": Kind.SHOCK, "b": Kind.GALE, "name": "Thunderstorm", "desc": "Arcs to every shocked enemy in a wide ring", "sound": "react_chain", "fx": "spark", "do": [["apply", Kind.SHOCK, 260], ["chain_state", Kind.SHOCK, 1.5]] },
    { "a": Kind.SHOCK, "b": Kind.STONE, "name": "Grounded", "desc": "Stone grounds the charge; little happens", "sound": "hit", "fx": "circle", "do": [["damage", 0.5]] },
    # --- Fire
    { "a": Kind.FIRE, "b": Kind.ICE, "name": "Thermal Shock", "desc": "Cracks apart in a violent burst", "sound": "react_freeze", "fx": "magic", "do": [["burst", 140, 3.0]] },
    { "a": Kind.FIRE, "b": Kind.OIL, "name": "Inferno", "desc": "A heavy burn that spreads along oiled enemies", "sound": "react_inferno", "fx": "flame", "do": [["burn", 2.0, 4.0], ["spread", Kind.FIRE, 160]] },
    { "a": Kind.FIRE, "b": Kind.POISON, "name": "Noxious Flame", "desc": "Burns and leaves a poison cloud", "sound": "react_inferno", "fx": "flame", "do": [["burn", 1.5, 3.0], ["cloud", Kind.POISON, 110, 3.5]] },
    { "a": Kind.FIRE, "b": Kind.ACID, "name": "Chemical Fire", "desc": "A long corrosive burn", "sound": "react_inferno", "fx": "flame", "do": [["burn", 2.5, 6.0], ["corrode", 6.0]] },
    { "a": Kind.FIRE, "b": Kind.BLOOD, "name": "Cauterize", "desc": "Seals the wound with a brutal flash", "sound": "react_ignition", "fx": "flame", "do": [["damage", 5.0], ["burn", 1.0, 2.0]] },
    { "a": Kind.FIRE, "b": Kind.VOID, "name": "Dark Flame", "desc": "A fire that hungers for neighbours", "sound": "react_inferno", "fx": "flame", "do": [["burn", 2.0, 4.0], ["apply", Kind.FIRE, 170]] },
    { "a": Kind.FIRE, "b": Kind.HOLY, "name": "Holy Fire", "desc": "Purifying flame", "sound": "shield_break", "fx": "light", "do": [["purge", 2.0], ["burn", 2.0, 4.0]] },
    { "a": Kind.FIRE, "b": Kind.GALE, "name": "Firestorm", "desc": "Flame fanned onto everything nearby", "sound": "nova_fire", "fx": "flame", "do": [["apply", Kind.FIRE, 200], ["burst", 170, 1.0]] },
    { "a": Kind.FIRE, "b": Kind.STONE, "name": "Magma", "desc": "A pool of lava", "sound": "nova_fire", "fx": "flame", "do": [["cloud", Kind.FIRE, 120, 6.0], ["damage", 2.0]] },
    # --- Ice
    { "a": Kind.ICE, "b": Kind.OIL, "name": "Black Ice", "desc": "Enemies slip and stall", "sound": "react_freeze", "fx": "magic", "do": [["slow", 0.25, 4.0, 150], ["stun", 0.8]] },
    { "a": Kind.ICE, "b": Kind.POISON, "name": "Frostbite", "desc": "Cold deepens the poison", "sound": "react_freeze", "fx": "magic", "do": [["poison", 2.5, 6.0], ["slow", 0.5, 4.0, 0]] },
    { "a": Kind.ICE, "b": Kind.ACID, "name": "Brittle", "desc": "Corroded and fragile", "sound": "react_freeze", "fx": "magic", "do": [["corrode", 8.0], ["damage", 2.0]] },
    { "a": Kind.ICE, "b": Kind.BLOOD, "name": "Hemostasis", "desc": "The blood freezes mid-flow", "sound": "react_freeze", "fx": "magic", "do": [["stun", 2.0], ["damage", 3.0]] },
    { "a": Kind.ICE, "b": Kind.VOID, "name": "Absolute Zero", "desc": "Freezes everything nearby", "sound": "nova_frost", "fx": "magic", "do": [["apply", Kind.WET, 150], ["apply", Kind.ICE, 150]] },
    { "a": Kind.ICE, "b": Kind.HOLY, "name": "Sanctuary", "desc": "Freezes the foe and mends you", "sound": "react_freeze", "fx": "light", "do": [["freeze", 2.5], ["heal_source", 6]] },
    { "a": Kind.ICE, "b": Kind.GALE, "name": "Blizzard", "desc": "A freezing wind", "sound": "nova_frost", "fx": "magic", "do": [["cloud", Kind.ICE, 160, 3.0], ["slow", 0.5, 3.0, 160]] },
    { "a": Kind.ICE, "b": Kind.STONE, "name": "Glacier", "desc": "Locked in ice for a long time", "sound": "react_freeze", "fx": "magic", "do": [["freeze", 5.0]] },
    # --- Oil
    { "a": Kind.OIL, "b": Kind.SHOCK, "name": "Ignition", "desc": "Shock damage plus a lighter burn", "sound": "react_ignition", "fx": "spark", "do": [["damage", 2.0], ["burn", 1.0, 3.0]] },
    { "a": Kind.OIL, "b": Kind.POISON, "name": "Tar Pit", "desc": "A slow, poisonous bog", "sound": "die", "fx": "smoke", "do": [["slow", 0.4, 5.0, 130], ["apply", Kind.POISON, 130]] },
    { "a": Kind.OIL, "b": Kind.ACID, "name": "Dissolve", "desc": "Eaten away", "sound": "react_steam", "fx": "circle", "do": [["poison", 2.0, 5.0], ["corrode", 5.0]] },
    { "a": Kind.OIL, "b": Kind.BLOOD, "name": "Slick", "desc": "Enemies lose their footing", "sound": "hit", "fx": "circle", "do": [["slow", 0.3, 4.0, 140], ["bleed", 1.5, 4.0]] },
    { "a": Kind.OIL, "b": Kind.VOID, "name": "Black Hole", "desc": "A pull that leaves everything oiled", "sound": "nova_frost", "fx": "twirl", "do": [["pull", 240, 400], ["apply", Kind.OIL, 160]] },
    { "a": Kind.OIL, "b": Kind.HOLY, "name": "Anointing", "desc": "Burns the oil away in holy light", "sound": "shield_break", "fx": "light", "do": [["burst", 120, 2.5], ["apply", Kind.FIRE, 120]] },
    { "a": Kind.OIL, "b": Kind.GALE, "name": "Oil Spray", "desc": "Oil everywhere", "sound": "react_steam", "fx": "smoke", "do": [["apply", Kind.OIL, 220], ["damage", 1.0]] },
    { "a": Kind.OIL, "b": Kind.STONE, "name": "Asphalt", "desc": "Stuck fast", "sound": "die", "fx": "smoke", "do": [["stun", 1.5], ["slow", 0.3, 6.0, 120]] },
    # --- Poison
    { "a": Kind.POISON, "b": Kind.ACID, "name": "Virulence", "desc": "A poison that stacks fast", "sound": "react_steam", "fx": "circle", "do": [["poison", 2.0, 6.0], ["poison", 2.0, 6.0], ["poison", 2.0, 6.0]] },
    { "a": Kind.POISON, "b": Kind.BLOOD, "name": "Sepsis", "desc": "Poison in the blood: bleeds and rots", "sound": "hit", "fx": "circle", "do": [["bleed", 2.0, 5.0], ["poison", 1.5, 5.0]] },
    { "a": Kind.POISON, "b": Kind.VOID, "name": "Decay", "desc": "Takes a slice of max health", "sound": "react_steam", "fx": "twirl", "do": [["decay", 0.15]] },
    { "a": Kind.POISON, "b": Kind.HOLY, "name": "Cleanse", "desc": "Burns the poison out, and you with it", "sound": "shield_break", "fx": "light", "do": [["purge", 2.0], ["heal_source", 5]] },
    { "a": Kind.POISON, "b": Kind.GALE, "name": "Plague Wind", "desc": "Poison carried on the wind", "sound": "react_steam", "fx": "smoke", "do": [["apply", Kind.POISON, 280], ["damage", 1.0]] },
    { "a": Kind.POISON, "b": Kind.STONE, "name": "Petrichor", "desc": "A slow poisonous mire", "sound": "die", "fx": "smoke", "do": [["poison", 1.5, 6.0], ["slow", 0.5, 4.0, 0]] },
    # --- Acid
    { "a": Kind.ACID, "b": Kind.BLOOD, "name": "Coagulant", "desc": "A clotting burn", "sound": "hit", "fx": "circle", "do": [["damage", 3.0], ["corrode", 4.0]] },
    { "a": Kind.ACID, "b": Kind.VOID, "name": "Null Acid", "desc": "Erases a share of what the target is", "sound": "react_steam", "fx": "twirl", "do": [["decay", 0.12], ["corrode", 5.0]] },
    { "a": Kind.ACID, "b": Kind.HOLY, "name": "Neutralize", "desc": "A clean, hard strike", "sound": "shield_break", "fx": "light", "do": [["damage", 5.0], ["purge", 1.0]] },
    { "a": Kind.ACID, "b": Kind.GALE, "name": "Acid Rain", "desc": "Corrosion on everything nearby", "sound": "react_steam", "fx": "smoke", "do": [["apply", Kind.ACID, 220], ["burst", 220, 0.8]] },
    { "a": Kind.ACID, "b": Kind.STONE, "name": "Erosion", "desc": "Stone crumbles", "sound": "die", "fx": "circle", "do": [["burst", 110, 2.5], ["corrode", 5.0]] },
    # --- Blood
    { "a": Kind.BLOOD, "b": Kind.VOID, "name": "Exsanguinate", "desc": "Drains them dry, feeds you", "sound": "hit", "fx": "twirl", "do": [["decay", 0.10], ["heal_source", 8]] },
    { "a": Kind.BLOOD, "b": Kind.HOLY, "name": "Martyrdom", "desc": "Sacred blood: damage and healing", "sound": "shield_break", "fx": "light", "do": [["damage", 4.0], ["heal_source", 5]] },
    { "a": Kind.BLOOD, "b": Kind.GALE, "name": "Spray", "desc": "Blood on everyone nearby", "sound": "hit", "fx": "circle", "do": [["apply", Kind.BLOOD, 200], ["bleed", 1.0, 4.0]] },
    { "a": Kind.BLOOD, "b": Kind.STONE, "name": "Bludgeon", "desc": "Crushing blow", "sound": "die_elite", "fx": "circle", "do": [["damage", 6.0], ["stun", 0.8]] },
    # --- Void
    { "a": Kind.VOID, "b": Kind.HOLY, "name": "Annihilation", "desc": "Opposites meet", "sound": "die_boss", "fx": "light", "do": [["burst", 160, 4.0]] },
    { "a": Kind.VOID, "b": Kind.GALE, "name": "Vacuum", "desc": "Air rushes in, then out", "sound": "nova_frost", "fx": "twirl", "do": [["pull", 240, 450], ["push", 120, 500]] },
    { "a": Kind.VOID, "b": Kind.STONE, "name": "Gravity Well", "desc": "Heavy pull and a crushing pin", "sound": "nova_frost", "fx": "twirl", "do": [["pull", 200, 380], ["stun", 1.5], ["damage", 2.0]] },
    # --- Holy
    { "a": Kind.HOLY, "b": Kind.GALE, "name": "Divine Wind", "desc": "A holy gust that scours states", "sound": "shield_break", "fx": "light", "do": [["push", 200, 400], ["purge", 1.5]] },
    { "a": Kind.HOLY, "b": Kind.STONE, "name": "Consecrate", "desc": "Hallowed ground that burns the unholy", "sound": "shield_break", "fx": "light", "do": [["cloud", Kind.HOLY, 140, 5.0]] },
    # --- Gale
    { "a": Kind.GALE, "b": Kind.STONE, "name": "Sandstorm", "desc": "Grinding wind", "sound": "react_steam", "fx": "smoke", "do": [["burst", 160, 1.5], ["slow", 0.5, 3.0, 160]] },
]

signal reaction_fired(reaction_name: String, position: Vector2, color: Color)
signal lightning_arc(from: Vector2, to: Vector2)
signal nova(position: Vector2, radius: float, color: Color)
## A fusion (tier 3) or cataclysm (tier 4) went off: presentation, counts and telemetry.
signal fusion_fired(fusion_name: String, tier: int, position: Vector2, radius: float, entry: Dictionary)

var _reactions: Dictionary = {}
var _by_name: Dictionary = {}

# --- The tier ladder (see fusions.gd) ---------------------------------------
## Tier of the effect being resolved right now: 0 a plain hit, 2 inside a reaction, 3 inside
## a fusion or a field's payload tick, 4 inside a cataclysm. Everything is synchronous, so
## it is set around each resolution and restored after it; a product may only be made when
## Fusions.can_produce(product tier, ctx_tier).
var ctx_tier := 0
## `--no-fusions` (baseline probes): reactions leave no compounds, so nothing climbs.
var fusions_enabled := true
var _clock := 0.0                  # game time, for the room budgets
var _fusion_times: Array = []      # game times of the fusions in the last second (room budget)
var _repeats: Dictionary = {}      # name -> game times it fired inside REPEAT_WINDOW
var _last_cataclysm := -99.0
var _apply_left := -1              # element applications the running fusion may still cause (-1 = no cap)
var _depth := 0                    # nested resolutions (reactions inside fusions inside ...)
var _frame_fusions := 0
## Termination proof, printed by the bot ([FUSION-CHECK]): the highest context tier entered,
## the most fusions and cataclysms run in one frame, the deepest nesting, and products made
## at or below the tier they were made in (must stay 0).
var dbg := { "max_ctx": 0, "max_frame": 0, "max_depth": 0, "violations": 0, "fusions": 0, "cataclysms": 0,
    "fields": 0, "compounds_enemy": 0, "compounds_patch": 0, "denied_budget": 0, "denied_gap": 0 }


func _ready() -> void:
    for d in DEFS:
        _reactions[pair_key(d["a"], d["b"])] = d
        _by_name[d["name"]] = d
    if OS.get_cmdline_user_args().has("--no-fusions"):
        fusions_enabled = false


func _process(delta: float) -> void:
    _clock += delta
    _frame_fusions = 0


## A new room: its budgets (fusions a second, repeats, the cataclysm cooldown) start fresh.
func room_reset() -> void:
    _fusion_times.clear()
    _repeats.clear()
    _last_cataclysm = -99.0


static func pair_key(a: int, b: int) -> Vector2i:
    return Vector2i(mini(a, b), maxi(a, b))


## Name of the reaction between two elements, or "" if they do not react.
func reaction_name(a: int, b: int) -> String:
    var r = _reactions.get(pair_key(a, b))
    return "" if r == null else r["name"]


func def_by_name(reaction_name: String) -> Dictionary:
    return _by_name.get(reaction_name, {})


func all_defs() -> Array:
    return DEFS


## Every reacting pair available from a set of element kinds.
func available_reactions(kinds: Array) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for key in _reactions.keys():
        if kinds.has(key.x) and kinds.has(key.y):
            out.append(key)
    return out


## Fires the reaction between `existing` and `incoming` on `enemy`.
## Returns the reaction name, or "" when the pair does not react.
## `context` is the tier this happens inside (-1: the current ctx_tier). The reaction's own
## actions run at tier 2 (or the context, if higher). It leaves its compound only when a
## tier 2 product may be made in `context`, so a reaction set off by a fusion's apply or a
## field's payload deals its damage and leaves nothing.
func try_react(enemy: Node2D, existing: int, incoming: int, potency: float, context: int = -1) -> String:
    var d = _reactions.get(pair_key(existing, incoming))
    if d == null:
        return ""
    var ctx := ctx_tier if context < 0 else context
    var name: String = d["name"]
    var pos: Vector2 = enemy.global_position
    var source: Player = enemy.last_hit_by if "last_hit_by" in enemy else null
    reaction_fired.emit(name, pos, COLORS[incoming])
    var prev := _enter(maxi(ctx, Fusions.TIER_REACTION))
    var tel_prev: String = Telemetry.begin_reaction(name)
    for act in d["do"]:
        if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
            # The target died mid-reaction; area actions still fire from where it was.
            break
        _act(enemy, potency, act)
    Telemetry.end_reaction(tel_prev)
    _leave(prev)
    if fusions_enabled and Fusions.can_produce(Fusions.TIER_REACTION, ctx):
        var alive := is_instance_valid(enemy) and not enemy.is_queued_for_deletion()
        _leave_compound(name, enemy if alive else null, enemy.global_position if alive else pos, potency, source)
    return name


## An element meets a cloud or puddle: the pair's reaction plays out once over everyone
## inside, and the patch is used up. Lightning through a steam puddle shocks everyone
## standing in it; fire into a poison cloud burns the crowd; then it is gone. One step,
## never a chain of its own.
##
## Compound patches and fusion fields are clouds too: an element entering a compound patch
## fuses it (tier 3), one entering a field may set off its cataclysm (tier 4).
func react_cloud(cloud: Cloud, incoming: int, potency: float, source: Player, context: int = -1) -> String:
    if cloud == null or not is_instance_valid(cloud) or cloud.element == incoming or cloud.cooldown > 0.0:
        return ""
    var ctx := ctx_tier if context < 0 else context
    if cloud.field_name != "":
        return _react_field(cloud, incoming, potency, source, ctx)
    if cloud.compound != "":
        return _react_compound_patch(cloud, incoming, potency, source, ctx)
    var d = _reactions.get(pair_key(cloud.element, incoming))
    if d == null:
        return ""
    cloud.cooldown = 0.5
    var name: String = d["name"]
    var pos: Vector2 = cloud.global_position
    reaction_fired.emit(name, pos, COLORS[incoming])
    nova.emit(pos, cloud.radius, Color(COLORS[incoming], 0.6))
    var inside := _enemies_within(pos, cloud.radius)
    var prev := _enter(maxi(ctx, Fusions.TIER_REACTION))
    var tel_prev: String = Telemetry.begin_reaction(name)
    var area_done := false
    for e in inside:
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        if source != null and is_instance_valid(source):
            e.last_hit_by = source
        for act in d["do"]:
            if not is_instance_valid(e) or e.is_queued_for_deletion():
                break
            if act[0] == "cloud":
                continue
            if _is_area_action(act):
                # Area actions run once over the cloud, anchored on its first enemy,
                # or ten enemies would mean ten bursts.
                if not area_done:
                    _act(e, potency * 0.7, act)
                continue
            _act(e, potency * 0.7, act)
        area_done = true
    Telemetry.end_reaction(tel_prev)
    _leave(prev)
    cloud.dissipate()
    if fusions_enabled and Fusions.can_produce(Fusions.TIER_REACTION, ctx):
        # A reaction played over a patch leaves its compound there, and primes the bodies
        # inside when the compound lives on enemies.
        var cid := Fusions.compound_for(name)
        var c := Fusions.compound(cid)
        if not c.is_empty() and String(c["where"]).contains("enemy"):
            for e in inside:
                if is_instance_valid(e) and not e.is_queued_for_deletion() and e.has_method("set_compound"):
                    if e.set_compound(cid, name, float(c["lifetime_enemy"])):
                        dbg["compounds_enemy"] += 1
        _leave_compound(name, null, pos, potency, source, false)
    return name


# --- Compounds, fusions, cataclysms -------------------------------------------------


## Enter a resolution at `tier`; returns the tier to restore with _leave.
func _enter(tier: int) -> int:
    var prev := ctx_tier
    ctx_tier = tier
    _depth += 1
    if tier > int(dbg["max_ctx"]):
        dbg["max_ctx"] = tier
    if _depth > int(dbg["max_depth"]):
        dbg["max_depth"] = _depth
    return prev


func _leave(prev: int) -> void:
    ctx_tier = prev
    _depth -= 1


## The compound a reaction leaves: on its target (when the compound lives on enemies and the
## target is not on its post-fusion cooldown) and/or as a patch where it happened.
func _leave_compound(reaction_name: String, enemy: Node2D, pos: Vector2, potency: float, source: Player, on_enemy := true) -> void:
    var cid := Fusions.compound_for(reaction_name)
    var c := Fusions.compound(cid)
    if c.is_empty():
        return
    var where := String(c["where"])
    # Residue boon (LevelUps): compounds wait longer for their third element.
    var life_mult := 1.0 + (source.stat("compound_life") if source != null and is_instance_valid(source) else 0.0)
    if on_enemy and where.contains("enemy") and enemy != null and enemy.has_method("set_compound"):
        if enemy.set_compound(cid, reaction_name, float(c["lifetime_enemy"]) * life_mult):
            dbg["compounds_enemy"] += 1
    if where.contains("cloud") or where.contains("floor"):
        if Cloud.spawn_compound(_world(), pos, cid, reaction_name, float(c["patch_radius"]), float(c["lifetime_cloud"]) * life_mult, potency, source):
            dbg["compounds_patch"] += 1


## Whether the room may run another fusion now (MAX_FUSIONS_PER_SEC). Past it the element
## lands as a plain element and the compound stays.
func fusion_budget() -> bool:
    while not _fusion_times.is_empty() and _clock - float(_fusion_times[0]) > 1.0:
        _fusion_times.pop_front()
    if _fusion_times.size() >= Fusions.MAX_FUSIONS_PER_SEC:
        dbg["denied_budget"] += 1
        return false
    return true


## Whether this fusion name may fire again yet (Fusions.REPEAT_GAP, room-wide).
func _gap_ok(fusion_name: String) -> bool:
    var times: Array = _repeats.get(fusion_name, [])
    if not times.is_empty() and _clock - float(times[times.size() - 1]) < Fusions.REPEAT_GAP:
        dbg["denied_gap"] = int(dbg.get("denied_gap", 0)) + 1
        return false
    return true


## An element lands on an enemy carrying a compound. Returns the fusion's name, or "" when
## nothing fused (the element then lands as usual). Called by Enemy.apply_element.
func try_fuse(enemy: Node2D, compound_id: String, origin: String, incoming: int, potency: float, source: Player) -> String:
    if not fusions_enabled or not Fusions.can_produce(Fusions.TIER_FUSION, ctx_tier):
        return ""
    var entry := Fusions.fusion(compound_id, incoming, origin)
    if entry.is_empty() or not _gap_ok(String(entry["name"])) or not fusion_budget():
        return ""
    play_fusion(entry, enemy, enemy.global_position, potency, 0.0, source, [], false)
    return String(entry["name"])


## A compound patch meets an element: the fusion plays once over everyone inside (area
## actions once from the patch's centre, the rest per enemy at PATCH_SCALE); the patch is used.
func _react_compound_patch(cloud: Cloud, incoming: int, potency: float, source: Player, ctx: int) -> String:
    if not fusions_enabled or not Fusions.can_produce(Fusions.TIER_FUSION, ctx):
        return ""
    var entry := Fusions.fusion(cloud.compound, incoming, cloud.origin)
    if entry.is_empty() or not _gap_ok(String(entry["name"])) or not fusion_budget():
        return ""
    cloud.cooldown = 99.0
    var pos := cloud.global_position
    var inside := _enemies_within(pos, cloud.radius)
    play_fusion(entry, null, pos, potency, cloud.radius, source, inside, true)
    cloud.dissipate()
    return String(entry["name"])


## A fusion field meets a fourth element: a cataclysm over everything inside, then nothing.
## The field must be FIELD_ARM_TIME old, and the room gets one cataclysm per
## CATACLYSM_ROOM_COOLDOWN; otherwise the element passes through and the field stays.
func _react_field(cloud: Cloud, incoming: int, potency: float, source: Player, ctx: int) -> String:
    if not fusions_enabled or not Fusions.can_produce(Fusions.TIER_CATACLYSM, ctx):
        return ""
    var entry := Fusions.cataclysm(cloud.field_name, incoming)
    if entry.is_empty() or cloud.age < Fusions.FIELD_ARM_TIME or cloud.cataclysms_left <= 0:
        return ""
    if _clock - _last_cataclysm < Fusions.CATACLYSM_ROOM_COOLDOWN:
        return ""
    _last_cataclysm = _clock
    cloud.cataclysms_left -= 1
    cloud.cooldown = 99.0
    var pos := cloud.global_position
    var inside := _enemies_within(pos, cloud.radius)
    play_fusion(entry, null, pos, maxf(potency, cloud.potency), cloud.radius, source, inside, true)
    cloud.dissipate()
    return String(entry["name"])


## Runs a fusion (tier 3) or cataclysm (tier 4). On an enemy (`anchor`, `is_patch` false)
## its actions run on the anchor at potency x mult x the repeat factor; over a patch or a
## field, area actions (and heal_source) run once from `pos` and the rest on each enemy in
## `inside` at PATCH_SCALE. Everything inside runs at context tier = the entry's tier, with
## at most MAX_SECONDARY_APPLIES element applications. A field is left after, if any.
func play_fusion(entry: Dictionary, anchor: Node2D, pos: Vector2, potency: float, patch_radius: float, source: Player, inside: Array, is_patch: bool) -> void:
    var tier := int(entry.get("tier", Fusions.TIER_FUSION))
    var name := String(entry["name"])
    if not Fusions.can_produce(tier, ctx_tier):
        dbg["violations"] += 1   # callers gate this; counting proves they do
        return
    _fusion_times.append(_clock)
    _frame_fusions += 1
    if _frame_fusions > int(dbg["max_frame"]):
        dbg["max_frame"] = _frame_fusions
    if tier >= Fusions.TIER_CATACLYSM:
        dbg["cataclysms"] += 1
    else:
        dbg["fusions"] += 1
    var times: Array = _repeats.get(name, [])
    while not times.is_empty() and _clock - float(times[0]) > Fusions.REPEAT_WINDOW:
        times.pop_front()
    var mult := float(entry["mult"]) * Fusions.repeat_mult(times.size())
    times.append(_clock)
    _repeats[name] = times
    var acts := Fusions.prepared_actions(entry, patch_radius)
    var reach := patch_radius
    for a in acts:
        match String(a[0]):
            "burst", "pull", "push":
                reach = maxf(reach, float(a[1]))
            "apply", "spread":
                reach = maxf(reach, float(a[2]))
            "slow":
                reach = maxf(reach, float(a[3]))
    if source == null and anchor != null and "last_hit_by" in anchor:
        source = anchor.last_hit_by
    # Alchemist / Apocalypse boons (LevelUps): fusion and cataclysm damage.
    if source != null and is_instance_valid(source):
        mult *= 1.0 + source.stat("cataclysm_power" if tier >= Fusions.TIER_CATACLYSM else "fusion_power")
    fusion_fired.emit(name, tier, pos, maxf(reach, 60.0), entry)
    var prev := _enter(tier)
    var tel_prev: Array = Telemetry.begin_fusion(name, tier)
    var apply_prev := _apply_left
    _apply_left = Fusions.MAX_SECONDARY_APPLIES_CATACLYSM if tier >= Fusions.TIER_CATACLYSM else Fusions.MAX_SECONDARY_APPLIES
    var cracks := Fusions.shield_cracks(tier)
    if not is_patch:
        if anchor != null and is_instance_valid(anchor) and anchor.has_method("crack_shield"):
            anchor.crack_shield(cracks)
            anchor.fusion_cd = Fusions.FUSION_COOLDOWN
        var p := potency * mult
        for act in acts:
            if anchor != null and is_instance_valid(anchor) and not anchor.is_queued_for_deletion():
                _act(anchor, p, act)
            elif _is_area_action(act) or act[0] == "heal_source":
                # The target died mid-fusion; area actions still fire from where it was.
                _act_at(null, pos, source, p, act)
    else:
        var p := potency * mult * Fusions.PATCH_SCALE
        for act in acts:
            if _is_area_action(act) or act[0] == "heal_source":
                _act_at(null, pos, source, p, act)
        for e in inside:
            if not is_instance_valid(e) or e.is_queued_for_deletion():
                continue
            if source != null and is_instance_valid(source):
                e.last_hit_by = source
            if e.has_method("crack_shield"):
                e.crack_shield(cracks)
                e.fusion_cd = Fusions.FUSION_COOLDOWN
            for act in acts:
                if not is_instance_valid(e) or e.is_queued_for_deletion():
                    break
                if _is_area_action(act) or act[0] == "heal_source":
                    continue
                _act(e, p, act)
    _apply_left = apply_prev
    Telemetry.end_fusion(tel_prev)
    _leave(prev)
    if tier == Fusions.TIER_FUSION and Fusions.leaves_field(name):
        var f := Fusions.field_of(name)
        if not f.is_empty():
            var field_mult := 1.0 + (source.stat("field_life") if source != null and is_instance_valid(source) else 0.0)
            Cloud.spawn_field(_world(), pos, name, int(f["payload"]), float(f["radius"]), float(f["life"]) * field_mult, potency * 0.6, source)
            dbg["fields"] += 1


## Smoulder boon (LevelUps): burn, poison and bleed set by reactions, fusions, cataclysms.
static func _dot_mult(source) -> float:
    if source == null or not is_instance_valid(source):
        return 1.0
    return 1.0 + float(source.stat("dot_power"))


static func _is_area_action(act: Array) -> bool:
    match act[0]:
        "burst", "chain_state", "spread", "pull", "push":
            return true
        "apply":
            return float(act[2]) > 0.0
        "slow":
            return float(act[3]) > 0.0
    return false


# --- Actions ---------------------------------------------------------------


func _act(enemy: Node2D, potency: float, act: Array) -> void:
    var source: Player = enemy.last_hit_by if "last_hit_by" in enemy else null
    _act_at(enemy, enemy.global_position, source, potency, act)


## One action at `pos`. `enemy` is the target; with null (a fusion over a patch, or a target
## that died mid-fusion) only the area actions do anything.
func _act_at(enemy: Node2D, pos: Vector2, source: Player, potency: float, act: Array) -> void:
    var has_target := enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion()
    match act[0]:
        "damage":
            if has_target:
                enemy.take_damage(potency * float(act[1]), Color.WHITE, true, source)
        "burst":
            nova.emit(pos, float(act[1]), Color(1, 1, 1, 0.5))
            for e in _enemies_within(pos, float(act[1])):
                if is_instance_valid(e) and not e.is_queued_for_deletion():
                    e.take_damage(potency * float(act[2]), Color.WHITE, true, source)
        "apply":
            var radius := float(act[2])
            if radius <= 0.0:
                if has_target and _may_apply():
                    enemy.apply_element(int(act[1]), potency, source)
            else:
                for e in _enemies_within(pos, radius):
                    if is_instance_valid(e) and not e.is_queued_for_deletion() and _may_apply():
                        e.apply_element(int(act[1]), potency * 0.8, source)
        "burn":
            if has_target:
                enemy.add_burn(potency * float(act[1]) * _dot_mult(source), float(act[2]))
        "poison":
            if has_target:
                enemy.add_poison(potency * float(act[1]) * 0.5 * _dot_mult(source), float(act[2]))
        "bleed":
            if has_target:
                enemy.add_bleed(potency * float(act[1]) * 0.6 * _dot_mult(source), float(act[2]))
        "corrode":
            if has_target:
                enemy.corrode(float(act[1]))
        "freeze":
            if has_target:
                enemy.freeze(float(act[1]))
        "stun":
            if has_target:
                enemy.stun(float(act[1]))
        "slow":
            var radius := float(act[3])
            if radius <= 0.0:
                if has_target:
                    enemy.apply_slow(float(act[1]), float(act[2]))
            else:
                for e in _enemies_within(pos, radius):
                    e.apply_slow(float(act[1]), float(act[2]))
        "pull":
            nova.emit(pos, float(act[1]), Color(0.6, 0.3, 0.9, 0.5))
            for e in _enemies_within(pos, float(act[1])):
                if e != enemy:
                    e.shove((pos - e.global_position).normalized() * float(act[2]))
        "push":
            nova.emit(pos, float(act[1]), Color(0.8, 0.9, 0.9, 0.5))
            for e in _enemies_within(pos, float(act[1])):
                if e != enemy:
                    e.shove((e.global_position - pos).normalized() * float(act[2]))
        "chain":
            if has_target:
                _chain_lightning(enemy, potency * float(act[1]) / 3.0)
        "chain_state":
            _chain_along_state(enemy if has_target else null, pos, int(act[1]), potency * float(act[2]), source)
        "cloud":
            Cloud.spawn(_world(), pos, int(act[1]), float(act[2]), float(act[3]), potency * 0.6, source)
        "purge":
            if has_target:
                var n: int = enemy.purge_states()
                if n > 0:
                    enemy.take_damage(potency * float(act[1]) * float(n), COLORS[Kind.HOLY], true, source)
        "spread":
            for e in _enemies_within(pos, float(act[2])):
                if e != enemy and is_instance_valid(e) and not e.is_queued_for_deletion() and _may_apply():
                    e.apply_element(int(act[1]), potency * 0.7, source)
        "decay":
            if has_target:
                enemy.take_damage(enemy.max_hp * float(act[1]) + potency, COLORS[Kind.VOID], true, source)
        "heal_source":
            if source != null and is_instance_valid(source):
                source.heal(float(act[1]))


## Element applications a running fusion may still cause (MAX_SECONDARY_APPLIES); always
## true outside one.
func _may_apply() -> bool:
    if _apply_left < 0:
        return true
    if _apply_left == 0:
        return false
    _apply_left -= 1
    return true


func _world() -> Node:
    var scene := get_tree().current_scene
    if scene != null and "current" in scene and scene.current != null:
        return scene.current
    return scene


## Chain lightning: jumps between wet enemies. `jump_potency` is the damage per jump / 3.
func _chain_lightning(enemy: Node2D, jump_potency: float) -> void:
    var damage := jump_potency * 3.0
    var visited := { enemy: true }
    var current: Node2D = enemy
    var source: Player = enemy.last_hit_by if "last_hit_by" in enemy else null
    var jumps := 6
    if source != null and is_instance_valid(source):
        jumps += int(source.stat("chain_jumps"))
    enemy.take_damage(damage, COLORS[Kind.SHOCK], true, source)
    for i in jumps:
        var next := _nearest_with_state(current.global_position, Kind.WET, 240.0, visited)
        if next == null:
            break
        visited[next] = true
        lightning_arc.emit(current.global_position, next.global_position)
        next.clear_state(Kind.WET)
        next.take_damage(damage, COLORS[Kind.SHOCK], true, source)
        current = next


func _chain_along_state(enemy: Node2D, from: Vector2, state: int, damage: float, source: Player) -> void:
    for e in _nearby_with_state(from, state, 300.0):
        if e == enemy:
            continue
        lightning_arc.emit(from, e.global_position)
        e.take_damage(damage, COLORS[Kind.SHOCK], true, source)


# --- Helpers ---------------------------------------------------------------


func _enemies() -> Array[Node]:
    return get_tree().get_nodes_in_group("enemies")


func _enemies_within(origin: Vector2, radius: float) -> Array[Node2D]:
    var out: Array[Node2D] = []
    var r2 := radius * radius
    for e in _enemies():
        if is_instance_valid(e) and not e.is_queued_for_deletion() \
                and e.global_position.distance_squared_to(origin) <= r2:
            out.append(e)
    return out


func _nearby_with_state(origin: Vector2, kind: int, radius: float) -> Array[Node2D]:
    var out: Array[Node2D] = []
    for e in _enemies_within(origin, radius):
        if e.has_state(kind):
            out.append(e)
    return out


func _nearest_with_state(origin: Vector2, kind: int, radius: float, exclude: Dictionary) -> Node2D:
    var best: Node2D = null
    var best_d := radius * radius
    for e in _enemies():
        if exclude.has(e) or not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        if not e.has_state(kind):
            continue
        var d: float = e.global_position.distance_squared_to(origin)
        if d < best_d:
            best_d = d
            best = e
    return best
