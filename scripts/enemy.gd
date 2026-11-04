class_name Enemy
extends CharacterBody2D
## An enemy: chases the nearest player, carries element states, reacts, can be
## immune to one element's raw damage, and elites carry a shield attuned to one reaction.

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
var scrap_value := 1
var last_hit_by: Player = null

## Attuned shield: only the one reaction it is attuned to cracks it, one hit per crack.
var weakness := Vector2i(-1, -1)
var shield_hp := 0
var shield_max := 0
var reshield_weakness := Vector2i(-1, -1)   # bosses re-shield at half health
var reshield_hits := 0

var states: Dictionary = {}           # Element.Kind -> seconds remaining
var burn_dps := 0.0
var burn_time := 0.0
var frozen_time := 0.0
var slow_time := 0.0
var slow_factor := 1.0
var poison_dps := 0.0
var poison_time := 0.0
var poison_stacks := 0
var bleed_dps := 0.0
var bleed_time := 0.0
var corroded_time := 0.0
var stun_time := 0.0
var shove_vel := Vector2.ZERO

var _contact_cd := 0.0
var _spread_cd := 0.0
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
    return shield_hp > 0


func set_shield(pair: Vector2i, hits: int) -> void:
    weakness = pair
    shield_hp = hits
    shield_max = hits
    queue_redraw()


func weakness_name() -> String:
    if weakness.x < 0:
        return ""
    return Elements.reaction_name(weakness.x, weakness.y)


## Lands an element on this enemy. If a different state is already present and the
## pair reacts, the reaction fires and the old state is consumed. Returns the reaction name.
func apply_element(kind: int, potency: float, source: Player = null) -> String:
    if kind == Element.Kind.NONE:
        return ""
    if source != null:
        last_hit_by = source
    for existing in states.keys():
        if existing == kind:
            continue
        var reaction := Elements.reaction_name(existing, kind)
        if reaction == "":
            continue
        states.erase(existing)
        if source != null:
            potency *= 1.0 + source.stat("potency:" + reaction)
        _on_reaction_pair(existing, kind)
        Elements.try_react(self, existing, kind, potency)
        if source != null and is_instance_valid(source):
            source.on_reaction(reaction)
            Items.fire(source, "reaction", { "target": self, "reaction": reaction, "element": kind, "pos": global_position })
        if is_instance_valid(self):
            queue_redraw()
        return reaction
    var duration: float = Element.DURATION[kind]
    if source != null:
        duration *= 1.0 + source.stat("state_duration")
    states[kind] = duration
    queue_redraw()
    return ""


## Any reaction cracks a shield; the one it is attuned to cracks it twice.
func _on_reaction_pair(a: int, b: int) -> void:
    if not shielded():
        return
    shield_hp -= 2 if Element.pair_key(a, b) == weakness else 1
    _shield_flash = 0.4
    if shield_hp <= 0:
        shield_hp = 0
        Elements.reaction_fired.emit("Shield broken!", global_position, Color.WHITE)
    else:
        Elements.reaction_fired.emit("Shield cracked", global_position, Color(1, 1, 1, 0.9))


func take_damage(amount: float, color: Color, flash: bool = true, source: Player = null) -> void:
    if hp <= 0.0:
        return
    if source != null:
        last_hit_by = source
    if shielded():
        # A shield blocks most raw damage, never all of it: reactions are the fast way in.
        _shield_flash = maxf(_shield_flash, 0.15)
        amount *= 0.2
    if frozen_time > 0.0:
        amount *= 3.0
    if corroded_time > 0.0:
        amount *= 1.5
    hp -= amount
    if flash:
        _flash = 0.12
        _flash_color = color
        _squash = 1.0
        Sfx.play("hit")
    if hp <= 0.0:
        _die()
        return
    if reshield_hits > 0 and hp <= max_hp * 0.5:
        set_shield(reshield_weakness, reshield_hits)
        reshield_hits = 0
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


func add_poison(dps: float, seconds: float) -> void:
    poison_stacks = mini(6, poison_stacks + 1)
    poison_dps = maxf(poison_dps, dps)
    poison_time = maxf(poison_time, seconds)


func add_bleed(dps: float, seconds: float) -> void:
    bleed_dps = maxf(bleed_dps, dps)
    bleed_time = maxf(bleed_time, seconds)


func corrode(seconds: float) -> void:
    corroded_time = maxf(corroded_time, seconds)


func stun(seconds: float) -> void:
    stun_time = maxf(stun_time, seconds)


## A one-off kick, decays over a few frames.
func shove(v: Vector2) -> void:
    shove_vel += v


## Strip every element state; returns how many were removed.
func purge_states() -> int:
    var n := states.size()
    states.clear()
    queue_redraw()
    return n


func _die() -> void:
    if frozen_time > 0.0:
        Elements.nova.emit(global_position, radius * 2.5, Color(Element.COLORS[Element.Kind.ICE], 0.6))
    if last_hit_by != null and is_instance_valid(last_hit_by):
        var ctx := { "target": self, "pos": global_position, "elite": is_elite }
        Items.fire(last_hit_by, "kill", ctx)
        if is_elite:
            Items.fire(last_hit_by, "elite_kill", ctx)
    # Plague: a poisoned corpse passes it on.
    if poison_time > 0.0:
        for e in get_tree().get_nodes_in_group("enemies"):
            if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                    and e.global_position.distance_to(global_position) <= 110.0:
                e.add_poison(poison_dps, 3.0)
        Elements.nova.emit(global_position, 110.0, Color(Element.COLORS[Element.Kind.POISON], 0.5))
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
        if hp <= 0.0:
            return
        # Fire spreads when there is fuel: an oiled neighbour catches.
        _spread_cd -= delta
        if _spread_cd <= 0.0:
            _spread_cd = 0.5
            for e in get_tree().get_nodes_in_group("enemies"):
                if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                        and e.burn_time <= 0.0 and e.has_state(Element.Kind.OIL) \
                        and e.global_position.distance_to(global_position) <= 80.0:
                    e.apply_element(Element.Kind.FIRE, burn_dps, last_hit_by)
    if poison_time > 0.0:
        poison_time -= delta
        take_damage(poison_dps * float(poison_stacks) * delta, Element.COLORS[Element.Kind.POISON], false)
        if hp <= 0.0:
            return
        if poison_time <= 0.0:
            poison_stacks = 0
            poison_dps = 0.0
    if bleed_time > 0.0:
        bleed_time -= delta
        if velocity.length() > 10.0:
            take_damage(bleed_dps * delta, Element.COLORS[Element.Kind.BLOOD], false)
            if hp <= 0.0:
                return
    frozen_time = maxf(0.0, frozen_time - delta)
    stun_time = maxf(0.0, stun_time - delta)
    corroded_time = maxf(0.0, corroded_time - delta)
    slow_time = maxf(0.0, slow_time - delta)
    _contact_cd = maxf(0.0, _contact_cd - delta)
    _flash = maxf(0.0, _flash - delta)
    _shield_flash = maxf(0.0, _shield_flash - delta)

    var target := _nearest_player()
    if frozen_time > 0.0 or stun_time > 0.0 or target == null:
        velocity = Vector2.ZERO
    else:
        var dir := (target.global_position - global_position).normalized()
        var s := speed * (slow_factor if slow_time > 0.0 else 1.0)
        velocity = dir * s
    velocity += shove_vel
    shove_vel = shove_vel.move_toward(Vector2.ZERO, 900.0 * delta)
    move_and_slide()

    if target != null and _contact_cd <= 0.0:
        var reach := radius + target.radius + 2.0
        if global_position.distance_squared_to(target.global_position) <= reach * reach:
            target.take_damage(contact_damage, self)
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
    if poison_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.POISON], 0.45)
    if corroded_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.ACID], 0.3)
    if bleed_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.BLOOD], 0.3)
    if frozen_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.ICE], 0.75)
    if stun_time > 0.0 and fmod(stun_time, 0.2) < 0.1:
        c = c.lerp(Color.WHITE, 0.5)
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
    if poison_time > 0.0:
        for i in poison_stacks:
            var a := _anim_t * 0.7 + float(i) * 1.1
            draw_circle(Vector2(cos(a) * radius * 1.1, -radius * 0.5 - fmod(a * 4.0, 14.0)), 2.5, Color(Element.COLORS[Element.Kind.POISON], 0.9))
    if bleed_time > 0.0:
        draw_circle(Vector2(radius * 0.5, radius * 0.9), 2.5, Element.COLORS[Element.Kind.BLOOD])
        draw_circle(Vector2(-radius * 0.3, radius * 1.0), 2.0, Element.COLORS[Element.Kind.BLOOD])
    if corroded_time > 0.0:
        draw_arc(Vector2.ZERO, radius + 1.0, 0.0, TAU, 20, Color(Element.COLORS[Element.Kind.ACID], 0.7), 1.5)
    if stun_time > 0.0:
        for i in 3:
            var a := _anim_t * 0.3 + float(i) * TAU / 3.0 + stun_time * 6.0
            draw_circle(Vector2(cos(a), sin(a) * 0.4) * radius * 1.2 + Vector2(0, -radius - 4.0), 2.5, Color(1, 1, 0.6))
    # Generic markers for element states beyond the ones drawn above.
    var i := 0
    for kind in states.keys():
        if kind in [Element.Kind.WET, Element.Kind.SHOCK]:
            continue
        draw_circle(Vector2(-radius + 4.0 + 7.0 * i, -radius - 8.0), 3.0, Element.COLORS[kind])
        i += 1

    # Attuned shield: the reaction pair it is weak to, and how many cracks remain.
    if shielded():
        var sy := -radius - 26.0
        draw_circle(Vector2(0, sy), 9.0, Color(0, 0, 0, 0.65))
        draw_circle(Vector2(-4.0, sy), 6.0, Element.COLORS[weakness.x])
        draw_circle(Vector2(4.0, sy), 6.0, Element.COLORS[weakness.y])
        for k in shield_max:
            var px := (float(k) - float(shield_max - 1) / 2.0) * 9.0
            draw_rect(Rect2(px - 3.0, sy + 11.0, 6.0, 4.0), Color(1, 1, 1, 0.95) if k < shield_hp else Color(1, 1, 1, 0.25))

    if (hp < max_hp and hp > 0.0) or is_elite:
        var w := radius * 2.2
        draw_rect(Rect2(-w / 2.0, radius + 5.0, w, 4.0), Color(0, 0, 0, 0.7))
        draw_rect(Rect2(-w / 2.0, radius + 5.0, w * hp / max_hp, 4.0), Color(0.9, 0.2, 0.2))
