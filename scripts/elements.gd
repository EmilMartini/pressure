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

var _reactions: Dictionary = {}
var _by_name: Dictionary = {}


func _ready() -> void:
    for d in DEFS:
        _reactions[pair_key(d["a"], d["b"])] = d
        _by_name[d["name"]] = d


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
func try_react(enemy: Node2D, existing: int, incoming: int, potency: float) -> String:
    var d = _reactions.get(pair_key(existing, incoming))
    if d == null:
        return ""
    var name: String = d["name"]
    reaction_fired.emit(name, enemy.global_position, COLORS[incoming])
    var tel_prev: String = Telemetry.begin_reaction(name)
    for act in d["do"]:
        if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
            # The target died mid-reaction; area actions still fire from where it was.
            break
        _act(enemy, potency, act)
    Telemetry.end_reaction(tel_prev)
    return name


## An element meets a cloud or puddle: the pair's reaction plays out once over everyone
## inside, and the patch is used up. Lightning through a steam puddle shocks everyone
## standing in it; fire into a poison cloud burns the crowd; then it is gone. One step,
## never a chain of its own.
func react_cloud(cloud: Cloud, incoming: int, potency: float, source: Player) -> String:
    if cloud == null or not is_instance_valid(cloud) or cloud.element == incoming or cloud.cooldown > 0.0:
        return ""
    var d = _reactions.get(pair_key(cloud.element, incoming))
    if d == null:
        return ""
    cloud.cooldown = 0.5
    var name: String = d["name"]
    var pos: Vector2 = cloud.global_position
    reaction_fired.emit(name, pos, COLORS[incoming])
    nova.emit(pos, cloud.radius, Color(COLORS[incoming], 0.6))
    var inside := _enemies_within(pos, cloud.radius)
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
    cloud.dissipate()
    return name


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
    var pos: Vector2 = enemy.global_position
    match act[0]:
        "damage":
            enemy.take_damage(potency * float(act[1]), Color.WHITE, true, source)
        "burst":
            nova.emit(pos, float(act[1]), Color(1, 1, 1, 0.5))
            for e in _enemies_within(pos, float(act[1])):
                e.take_damage(potency * float(act[2]), Color.WHITE, true, source)
        "apply":
            var radius := float(act[2])
            if radius <= 0.0:
                enemy.apply_element(int(act[1]), potency, source)
            else:
                for e in _enemies_within(pos, radius):
                    if is_instance_valid(e) and not e.is_queued_for_deletion():
                        e.apply_element(int(act[1]), potency * 0.8, source)
        "burn":
            enemy.add_burn(potency * float(act[1]), float(act[2]))
        "poison":
            enemy.add_poison(potency * float(act[1]) * 0.5, float(act[2]))
        "bleed":
            enemy.add_bleed(potency * float(act[1]) * 0.6, float(act[2]))
        "corrode":
            enemy.corrode(float(act[1]))
        "freeze":
            enemy.freeze(float(act[1]))
        "stun":
            enemy.stun(float(act[1]))
        "slow":
            var radius := float(act[3])
            if radius <= 0.0:
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
            _chain_lightning(enemy, potency * float(act[1]) / 3.0)
        "chain_state":
            _chain_along_state(enemy, int(act[1]), potency * float(act[2]), source)
        "cloud":
            Cloud.spawn(_world(), pos, int(act[1]), float(act[2]), float(act[3]), potency * 0.6, source)
        "purge":
            var n: int = enemy.purge_states()
            if n > 0:
                enemy.take_damage(potency * float(act[1]) * float(n), COLORS[Kind.HOLY], true, source)
        "spread":
            for e in _enemies_within(pos, float(act[2])):
                if e != enemy and is_instance_valid(e) and not e.is_queued_for_deletion():
                    e.apply_element(int(act[1]), potency * 0.7, source)
        "decay":
            enemy.take_damage(enemy.max_hp * float(act[1]) + potency, COLORS[Kind.VOID], true, source)
        "heal_source":
            if source != null and is_instance_valid(source):
                source.heal(float(act[1]))


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


func _chain_along_state(enemy: Node2D, state: int, damage: float, source: Player) -> void:
    var from := enemy.global_position
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
