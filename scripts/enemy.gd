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
var reshield_sequence: Array[Vector2i] = []   # bosses re-shield at half health
var scrap_value := 1

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
var _sprite: Sprite2D
var _sprite_scale := 1.0
var _anim_t := 0.0
var _spawn_t := 0.0
var _squash := 0.0


func configure(type: String, wave: int) -> void:
    kind_name = type
    var scale := 1.0 + 0.12 * float(wave)
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
            scrap_value = 10
        "boss":
            max_hp = 700.0 * scale
            speed = 85.0
            radius = 30.0
            contact_damage = 20.0
            base_color = Color(0.55, 0.10, 0.20)
            is_elite = true
            scrap_value = 40
        _:
            max_hp = 22.0 * scale
            speed = 115.0
            radius = 11.0
            contact_damage = 8.0
            base_color = Color(0.85, 0.30, 0.30)
    if type == "brute":
        scrap_value = 3
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
    base_color = Art.ENEMY_TINT.get(kind_name, base_color)
    _sprite_scale = radius / 6.0
    _sprite = Art.sprite(Art.TILES.get(kind_name, Art.TILES["grunt"]), 0.01, base_color)
    add_child(_sprite)
    var fx := _fx()
    if fx != null:
        fx.puff(Art.PARTICLES["smoke"], global_position, Color(0.1, 0.08, 0.1, 0.7), radius * 4.5, 0.5, false, Vector2(0, -20))


func _fx() -> Fx:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        return scene.fx
    return null


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
        _squash = 1.0
        Sfx.play("hit")
    if hp <= 0.0:
        _die()
        return
    if not reshield_sequence.is_empty() and hp <= max_hp * 0.5:
        sequence = reshield_sequence
        reshield_sequence = []
        sequence_index = 0
        _shield_flash = 0.5
        Elements.reaction_fired.emit("Shield restored!", global_position, Color.WHITE)
    queue_redraw()


## Removed without dying: no scrap, no kill credit (room cleared, party left).
func vanish() -> void:
    remove_from_group("enemies")
    queue_free()


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
    var fx := _fx()
    if fx != null:
        fx.corpse(_sprite.texture, global_position, _sprite_scale, _sprite.modulate, _sprite.flip_h)
        fx.bones(global_position, base_color.darkened(0.2), 4 if is_elite else 2)
        if burn_time > 0.0:
            fx.scorch(global_position, radius * 4.0)
        fx._shake(6.0 if kind_name == "boss" else (2.5 if is_elite else 0.8))
    match kind_name:
        "boss":
            Sfx.play("die_boss")
        "elite":
            Sfx.play("die_elite")
        _:
            Sfx.play("die")
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
    _update_sprite()
    queue_redraw()


func _update_sprite() -> void:
    var c := base_color
    if states.has(Element.Kind.WET):
        c = c.lerp(Element.COLORS[Element.Kind.WET], 0.4)
    if states.has(Element.Kind.OIL):
        c = c.lerp(Color(0.15, 0.1, 0.08), 0.5)
    if states.has(Element.Kind.SHOCK) and randf() < 0.5:
        c = c.lerp(Element.COLORS[Element.Kind.SHOCK], 0.5)
    if frozen_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.ICE], 0.75)
    if burn_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.FIRE], 0.35)
    if _flash > 0.0:
        c = c.lerp(Color.WHITE, 0.8)
    _sprite.modulate = c
    if absf(velocity.x) > 1.0:
        _sprite.flip_h = velocity.x < 0.0
    # Animation: spawn pop, hop while walking, squash on hit, stiff when frozen.
    var delta := get_physics_process_delta_time()
    _spawn_t = minf(1.0, _spawn_t + delta * 3.0)
    _squash = maxf(0.0, _squash - delta * 6.0)
    var moving := velocity.length() > 5.0
    if moving:
        _anim_t += delta * (9.0 + speed * 0.02)
    var hop := absf(sin(_anim_t)) * 3.0 if moving else 0.0
    var s := _sprite_scale * (_spawn_t + 0.35 * sin(_spawn_t * PI))
    _sprite.scale = Vector2(s * (1.0 + 0.4 * _squash), s * (1.0 - 0.4 * _squash))
    _sprite.position = Vector2(0, -hop)
    _sprite.rotation = (sin(_anim_t) * 0.12 if moving else 0.0)


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
    draw_circle(Vector2(0, radius * 0.6), radius * 0.9, Color(0, 0, 0, 0.35))
    if is_elite:
        draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
    if immune_to != Element.Kind.NONE:
        draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Element.COLORS[immune_to], 3.0)
        draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color(0, 0, 0, 0.4), 1.0)
    if shielded():
        draw_arc(Vector2.ZERO, radius + 11.0, 0.0, TAU, 40, Color(1, 1, 1, 0.45 + _shield_flash), 2.5)

    # Element states drawn on the body.
    if states.has(Element.Kind.WET):
        for i in 2:
            var dx := -radius * 0.4 + float(i) * radius * 0.8
            draw_circle(Vector2(dx, radius * 0.6 + fmod(_anim_t * 6.0 + i * 3.0, 6.0)), 2.2, Color(Element.COLORS[Element.Kind.WET], 0.9))
    if states.has(Element.Kind.SHOCK):
        for i in 3:
            var a := randf() * TAU
            var p := Vector2.RIGHT.rotated(a) * radius * randf_range(0.8, 1.4)
            draw_line(p, p + Vector2.RIGHT.rotated(a + randf_range(-1.0, 1.0)) * 6.0, Color(1, 1, 0.6, 0.9), 1.5)
    if burn_time > 0.0:
        var f := radius * randf_range(2.4, 3.2)
        draw_texture_rect(Art.PARTICLES["flame"], Rect2(Vector2(-f / 2.0, -radius - f * 0.8), Vector2(f, f)), false, Color(1.0, 0.6, 0.2, 0.85))
    if frozen_time > 0.0:
        var f := radius * 3.4
        draw_texture_rect(Art.PARTICLES["magic"], Rect2(Vector2(-f / 2.0, -f / 2.0), Vector2(f, f)), false, Color(0.8, 0.97, 1.0, 0.55))

    # Required reaction sequence, each pair as two half-dots.
    if sequence.size() > 0:
        var sy := -radius - 24.0
        var n := sequence.size()
        for k in n:
            var x := (float(k) - float(n - 1) / 2.0) * 22.0
            var done := k < sequence_index
            var alpha := 0.3 if done else 1.0
            draw_circle(Vector2(x, sy), 7.5, Color(0, 0, 0, 0.6 * alpha))
            draw_circle(Vector2(x - 3.5, sy), 5.0, Color(Element.COLORS[sequence[k].x], alpha))
            draw_circle(Vector2(x + 3.5, sy), 5.0, Color(Element.COLORS[sequence[k].y], alpha))

    if (hp < max_hp and hp > 0.0) or is_elite:
        var w := radius * 2.2
        draw_rect(Rect2(-w / 2.0, radius + 5.0, w, 4.0), Color(0, 0, 0, 0.7))
        draw_rect(Rect2(-w / 2.0, radius + 5.0, w * hp / max_hp, 4.0), Color(0.9, 0.2, 0.2))
