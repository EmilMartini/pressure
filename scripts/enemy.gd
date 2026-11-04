class_name Enemy
extends CharacterBody2D
## An enemy: chases the nearest player, carries element states, reacts, can be
## immune to one element's raw damage, and elites demand a reaction sequence.

signal died(enemy: Enemy)

const LAYER_ENEMIES := 2
const LAYER_WALLS := 4

var kind_name := "grunt"
var max_hp := 20.0
var hp := 20.0
var speed := 110.0
var radius := 12.0
var contact_damage := 8.0
var base_color := Color(0.85, 0.30, 0.30)
var immune_to: int = Element.Kind.NONE
var is_elite := false
var sequence: Array[Vector2i] = []   # required reaction pairs, in order
var sequence_index := 0

var states: Dictionary = {}           # Element.Kind -> seconds remaining
var burn_dps := 0.0
var burn_time := 0.0
var frozen_time := 0.0
var slow_time := 0.0
var slow_factor := 1.0

var _contact_cd := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _shield_flash := 0.0


func configure(type: String, wave: int) -> void:
    kind_name = type
    var scale := 1.0 + 0.18 * float(wave - 1)
    match type:
        "runner":
            max_hp = 10.0 * scale
            speed = 215.0
            radius = 8.0
            contact_damage = 5.0
            base_color = Color(0.95, 0.55, 0.30)
        "brute":
            max_hp = 95.0 * scale
            speed = 70.0
            radius = 20.0
            contact_damage = 16.0
            base_color = Color(0.60, 0.20, 0.35)
        "elite":
            max_hp = 240.0 * scale
            speed = 95.0
            radius = 17.0
            contact_damage = 14.0
            base_color = Color(0.75, 0.25, 0.60)
            is_elite = true
        _:
            max_hp = 22.0 * scale
            speed = 115.0
            radius = 11.0
            contact_damage = 8.0
            base_color = Color(0.85, 0.30, 0.30)
    hp = max_hp


func _ready() -> void:
    add_to_group("enemies")
    collision_layer = LAYER_ENEMIES
    collision_mask = LAYER_WALLS | LAYER_ENEMIES
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    add_child(shape)
    z_index = 8


# --- States and reactions --------------------------------------------------


func has_state(kind: int) -> bool:
    return states.has(kind)


func clear_state(kind: int) -> void:
    states.erase(kind)
    queue_redraw()


func shielded() -> bool:
    return sequence_index < sequence.size()


## Lands an element on this enemy. If a different state is already present and the
## pair reacts, the reaction fires and the old state is consumed. Returns the reaction name.
func apply_element(kind: int, potency: float) -> String:
    if kind == Element.Kind.NONE:
        return ""
    for existing in states.keys():
        if existing == kind:
            continue
        var reaction := Elements.reaction_name(existing, kind)
        if reaction == "":
            continue
        states.erase(existing)
        _advance_sequence(existing, kind)
        Elements.try_react(self, existing, kind, potency)
        if is_instance_valid(self):
            queue_redraw()
        return reaction
    states[kind] = Element.DURATION[kind]
    queue_redraw()
    return ""


func _advance_sequence(a: int, b: int) -> void:
    if not shielded():
        return
    if sequence[sequence_index] == Element.pair_key(a, b):
        sequence_index += 1
        _shield_flash = 0.3
        if not shielded():
            Elements.reaction_fired.emit("Shield broken!", global_position, Color.WHITE)


func take_damage(amount: float, color: Color, flash: bool = true) -> void:
    if hp <= 0.0:
        return
    if shielded():
        _shield_flash = maxf(_shield_flash, 0.15)
        queue_redraw()
        return
    if frozen_time > 0.0:
        amount *= 3.0
    hp -= amount
    if flash:
        _flash = 0.12
        _flash_color = color
    if hp <= 0.0:
        _die()
    else:
        queue_redraw()


func freeze(seconds: float) -> void:
    frozen_time = maxf(frozen_time, seconds)
    queue_redraw()


func apply_slow(factor: float, seconds: float) -> void:
    slow_factor = minf(slow_factor, factor) if slow_time > 0.0 else factor
    slow_time = maxf(slow_time, seconds)


func add_burn(dps: float, seconds: float) -> void:
    burn_dps = maxf(burn_dps, dps)
    burn_time = maxf(burn_time, seconds)
    queue_redraw()


func _die() -> void:
    if frozen_time > 0.0:
        Elements.nova.emit(global_position, radius * 2.5, Color(Element.COLORS[Element.Kind.ICE], 0.6))
    remove_from_group("enemies")
    died.emit(self)
    queue_free()


# --- Frame -----------------------------------------------------------------


func _physics_process(delta: float) -> void:
    for kind in states.keys():
        states[kind] -= delta
        if states[kind] <= 0.0:
            states.erase(kind)
    if burn_time > 0.0:
        burn_time -= delta
        take_damage(burn_dps * delta, Element.COLORS[Element.Kind.FIRE], false)
        if not is_instance_valid(self) or hp <= 0.0:
            return
    frozen_time = maxf(0.0, frozen_time - delta)
    slow_time = maxf(0.0, slow_time - delta)
    _contact_cd = maxf(0.0, _contact_cd - delta)
    _flash = maxf(0.0, _flash - delta)
    _shield_flash = maxf(0.0, _shield_flash - delta)

    var target := _nearest_player()
    if frozen_time > 0.0 or target == null:
        velocity = Vector2.ZERO
    else:
        var dir := (target.global_position - global_position).normalized()
        var s := speed * (slow_factor if slow_time > 0.0 else 1.0)
        velocity = dir * s
    move_and_slide()

    if target != null and _contact_cd <= 0.0:
        var reach := radius + target.radius + 2.0
        if global_position.distance_squared_to(target.global_position) <= reach * reach:
            target.take_damage(contact_damage)
            _contact_cd = 0.8
    queue_redraw()


func _nearest_player() -> Player:
    var best: Player = null
    var best_d := INF
    for p in get_tree().get_nodes_in_group("players"):
        var d: float = p.global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = p
    return best


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    var c := base_color
    if frozen_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.ICE], 0.7)
    if _flash > 0.0:
        c = c.lerp(Color.WHITE, 0.7)
    draw_circle(Vector2.ZERO, radius, c)
    if is_elite:
        draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
    if immune_to != Element.Kind.NONE:
        draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 32, Element.COLORS[immune_to], 2.5)
    if shielded():
        draw_arc(Vector2.ZERO, radius + 9.0, 0.0, TAU, 40, Color(1, 1, 1, 0.45 + _shield_flash), 2.0)

    # Active states as dots above the body.
    var i := 0
    var y := -radius - 7.0
    for kind in states.keys():
        draw_circle(Vector2(-8.0 + 8.0 * i, y), 3.5, Element.COLORS[kind])
        i += 1
    if burn_time > 0.0:
        draw_circle(Vector2(-8.0 + 8.0 * i, y), 3.5, Element.COLORS[Element.Kind.FIRE])

    # Required reaction sequence, each pair as two half-dots.
    if sequence.size() > 0:
        var sy := -radius - 20.0
        var n := sequence.size()
        for k in n:
            var x := (float(k) - float(n - 1) / 2.0) * 16.0
            var done := k < sequence_index
            var alpha := 0.3 if done else 1.0
            draw_circle(Vector2(x - 3.0, sy), 4.0, Color(Element.COLORS[sequence[k].x], alpha))
            draw_circle(Vector2(x + 3.0, sy), 4.0, Color(Element.COLORS[sequence[k].y], alpha))

    if hp < max_hp and hp > 0.0:
        var w := radius * 2.0
        draw_rect(Rect2(-radius, radius + 4.0, w, 3.0), Color(0, 0, 0, 0.6))
        draw_rect(Rect2(-radius, radius + 4.0, w * hp / max_hp, 3.0), Color(0.9, 0.2, 0.2))
