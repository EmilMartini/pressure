class_name Element
extends Node
## Element kinds, colours, pressure weights and the reaction table.
## Constants are reachable as `Element.X`; the autoload instance is `Elements`.

enum Kind { NONE, WET, SHOCK, FIRE, ICE, OIL }

const NAMES := {
    Kind.NONE: "None",
    Kind.WET: "Wet",
    Kind.SHOCK: "Shock",
    Kind.FIRE: "Fire",
    Kind.ICE: "Ice",
    Kind.OIL: "Oil",
}

const COLORS := {
    Kind.NONE: Color.WHITE,
    Kind.WET: Color(0.30, 0.60, 1.00),
    Kind.SHOCK: Color(1.00, 0.95, 0.30),
    Kind.FIRE: Color(1.00, 0.45, 0.15),
    Kind.ICE: Color(0.70, 0.95, 1.00),
    Kind.OIL: Color(0.45, 0.32, 0.25),
}

## Positive pushes the pressure gauge hot, negative pushes it cold.
const PRESSURE := {
    Kind.NONE: 0.0,
    Kind.WET: -1.0,
    Kind.SHOCK: 1.0,
    Kind.FIRE: 1.5,
    Kind.ICE: -1.5,
    Kind.OIL: 0.0,
}

## How long an applied state lingers on an enemy, in seconds.
const DURATION := {
    Kind.WET: 6.0,
    Kind.SHOCK: 3.0,
    Kind.FIRE: 4.0,
    Kind.ICE: 5.0,
    Kind.OIL: 8.0,
}

signal reaction_fired(reaction_name: String, position: Vector2, color: Color)
signal lightning_arc(from: Vector2, to: Vector2)
signal nova(position: Vector2, radius: float, color: Color)

var _reactions: Dictionary = {}


func _ready() -> void:
    _register(Kind.WET, Kind.SHOCK, "Chain Lightning", _chain_lightning)
    _register(Kind.WET, Kind.FIRE, "Steam", _steam)
    _register(Kind.WET, Kind.ICE, "Deep Freeze", _deep_freeze)
    _register(Kind.OIL, Kind.FIRE, "Inferno", _inferno)
    _register(Kind.OIL, Kind.SHOCK, "Ignition", _ignition)


static func pair_key(a: int, b: int) -> Vector2i:
    return Vector2i(mini(a, b), maxi(a, b))


func _register(a: int, b: int, reaction_name: String, fn: Callable) -> void:
    _reactions[pair_key(a, b)] = { "name": reaction_name, "fn": fn }


## Name of the reaction between two elements, or "" if they do not react.
func reaction_name(a: int, b: int) -> String:
    var r = _reactions.get(pair_key(a, b))
    return "" if r == null else r["name"]


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
    var r = _reactions.get(pair_key(existing, incoming))
    if r == null:
        return ""
    var name: String = r["name"]
    reaction_fired.emit(name, enemy.global_position, COLORS[incoming])
    r["fn"].call(enemy, potency)
    return name


# --- Reactions -------------------------------------------------------------


func _chain_lightning(enemy: Node2D, potency: float) -> void:
    var damage := potency * 3.0
    var visited := { enemy: true }
    var current: Node2D = enemy
    enemy.take_damage(damage, COLORS[Kind.SHOCK])
    for i in 6:
        var next := _nearest_with_state(current.global_position, Kind.WET, 240.0, visited)
        if next == null:
            break
        visited[next] = true
        lightning_arc.emit(current.global_position, next.global_position)
        next.clear_state(Kind.WET)
        next.take_damage(damage, COLORS[Kind.SHOCK])
        current = next


func _steam(enemy: Node2D, potency: float) -> void:
    var origin := enemy.global_position
    nova.emit(origin, 130.0, Color(0.85, 0.9, 0.95, 0.6))
    for e in _enemies_within(origin, 130.0):
        e.take_damage(potency * 2.0, COLORS[Kind.FIRE])
        if is_instance_valid(e):
            e.apply_slow(0.5, 3.0)


func _deep_freeze(enemy: Node2D, potency: float) -> void:
    enemy.take_damage(potency * 1.0, COLORS[Kind.ICE])
    if is_instance_valid(enemy):
        enemy.freeze(3.0)


func _inferno(enemy: Node2D, potency: float) -> void:
    var origin := enemy.global_position
    nova.emit(origin, 160.0, Color(1.0, 0.5, 0.1, 0.5))
    enemy.add_burn(potency * 2.0, 4.0)
    for e in _nearby_with_state(origin, Kind.OIL, 160.0):
        if e == enemy:
            continue
        e.clear_state(Kind.OIL)
        e.add_burn(potency * 2.0, 4.0)


func _ignition(enemy: Node2D, potency: float) -> void:
    enemy.take_damage(potency * 2.0, COLORS[Kind.SHOCK])
    if is_instance_valid(enemy):
        enemy.add_burn(potency * 1.0, 3.0)


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
