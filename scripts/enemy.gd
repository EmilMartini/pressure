class_name Enemy
extends CharacterBody2D
## An enemy: chases the nearest player, carries element states, reacts, can be
## immune to one element's raw damage, and elites carry a shield attuned to one reaction.
## Kinds behave differently (ranged, chargers, healers, bombers, armour...), elites can
## carry an affix, and bosses pick one of five scripted patterns with set_boss().

signal died(enemy: Enemy)

const LAYER_ENEMIES := 2
const LAYER_WALLS := 4

## Per kind: [hp base, hp per difficulty, speed, radius, contact damage base, scrap].
const STATS := {
    "grunt": [26.0, 5.5, 115.0, 11.0, 8.0, 1],
    "runner": [12.0, 2.7, 215.0, 8.0, 5.0, 1],
    "brute": [110.0, 19.0, 70.0, 20.0, 16.0, 3],
    "swarmer": [7.0, 1.35, 190.0, 6.0, 4.0, 1],
    "spitter": [35.0, 6.8, 75.0, 12.0, 6.0, 2],
    "charger": [53.0, 9.5, 100.0, 14.0, 12.0, 3],
    "splitter": [70.0, 12.0, 95.0, 15.0, 9.0, 3],
    "shaman": [41.0, 8.0, 85.0, 11.0, 5.0, 4],
    "bomber": [29.0, 5.4, 160.0, 10.0, 6.0, 2],
    "warden": [190.0, 32.0, 60.0, 22.0, 14.0, 5],
    "wisp": [19.0, 4.0, 170.0, 9.0, 6.0, 2],
    "elite": [420.0, 70.0, 95.0, 17.0, 14.0, 10],
    "boss": [1800.0, 420.0, 85.0, 30.0, 20.0, 40],
}

## Sprite tiles (column, row) in the 1-bit sheet; boss kinds are keyed by boss_kind.
const KIND_TILES := {
    "grunt": Vector2i(29, 6),
    "runner": Vector2i(26, 8),
    "brute": Vector2i(30, 6),
    "swarmer": Vector2i(31, 5),
    "spitter": Vector2i(25, 8),
    "charger": Vector2i(29, 7),
    "splitter": Vector2i(27, 8),
    "shaman": Vector2i(26, 9),
    "bomber": Vector2i(23, 8),
    "warden": Vector2i(24, 7),
    "wisp": Vector2i(27, 6),
    "elite": Vector2i(28, 5),
    "boss": Vector2i(30, 8),
    "brute_king": Vector2i(30, 8),
    "hive_mother": Vector2i(26, 5),
    "storm_warden": Vector2i(24, 8),
    "pyre_lord": Vector2i(25, 9),
    "void_herald": Vector2i(31, 9),
}

const KIND_COLORS := {
    "grunt": Color(0.82, 0.78, 0.70),
    "runner": Color(0.66, 0.54, 0.76),
    "brute": Color(0.62, 0.30, 0.30),
    "swarmer": Color(0.78, 0.62, 0.40),
    "spitter": Color(0.50, 0.78, 0.45),
    "charger": Color(0.85, 0.48, 0.30),
    "splitter": Color(0.55, 0.80, 0.75),
    "shaman": Color(0.55, 0.85, 0.55),
    "bomber": Color(0.95, 0.50, 0.25),
    "warden": Color(0.60, 0.62, 0.70),
    "wisp": Color(0.70, 0.85, 1.00),
    "elite": Color(0.88, 0.45, 0.78),
    "boss": Color(0.92, 0.22, 0.30),
    "brute_king": Color(0.90, 0.35, 0.28),
    "hive_mother": Color(0.60, 0.85, 0.35),
    "storm_warden": Color(0.95, 0.90, 0.40),
    "pyre_lord": Color(1.00, 0.50, 0.20),
    "void_herald": Color(0.65, 0.35, 0.95),
}

const AFFIXES := ["regenerating", "hasted", "trail", "volatile"]
const BOSS_KINDS := ["brute_king", "hive_mother", "storm_warden", "pyre_lord", "void_herald"]

const BOMB_DAMAGE := 18.0
const BOMB_RADIUS := 90.0
const BOMB_TRIGGER := 40.0
const WARDEN_ARMOUR := 0.4
const SHAMAN_ARMOUR := 0.7
const MAX_ENEMIES_FOR_SUMMON := 45

# Charger modes (also used by the brute king).
const MODE_CHASE := 0
const MODE_TELEGRAPH := 1
const MODE_DASH := 2
const MODE_COOL := 3

var kind_name := "grunt"
var max_hp := 20.0
var hp := 20.0
var speed := 110.0
var radius := 12.0
var contact_damage := 8.0
var damage_mult := 1.0   # late-floor pressure, set by the room on spawn; scales shots too
var base_color := Color(0.85, 0.30, 0.30)
var immune_to: int = Element.Kind.NONE
var is_elite := false
var scrap_value := 1
var last_hit_by: Player = null

## Elite affix: "" | "regenerating" | "hasted" | "trail" | "volatile". Set with set_affix().
var affix := ""
## Boss pattern: "" (plain chase) or one of BOSS_KINDS. Set with set_boss().
var boss_kind := ""

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
var armour_time := 0.0      # shaman blessing: incoming damage x0.7
var haste_aura_time := 0.0  # near a hasted elite: +15% speed

var _contact_cd := 0.0
var _spread_cd := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _shield_flash := 0.0
var _sprite: Sprite2D
var _shape: CircleShape2D
var _sprite_scale := 1.0
var _anim_t := 0.0
var _fx_t := 0.0   # status animation clock, runs even while frozen
var _shed_ms := 0  # last time a status shed a pixel into Fx (embers, poison motes)
var _dot_accum := 0.0   # damage-over-time waiting to be shown as one number
var _dot_color := Color.WHITE
var _dot_timer := 0.0
var _spawn_t := 0.0
var _squash := 0.0
var _floor_t := randf() * 0.25   # next floor-material check, staggered across enemies
var _on_ice := false

var _wave := 0
var _dead := false
var _exploded := false
var _reshield_at: Array = [0.5]   # fractions of max hp where the reshield fires
var _react_window := 0.0   # a reaction just fired: armour does not apply
var _since_hit := 99.0
var _strafe_sign := 1.0
var _strafe_t := 0.0

# Behaviour timers.
var _shoot_t := 0.0
var _pulse_t := 0.0
var _pulse_fx := 0.0
var _mode := MODE_CHASE
var _mode_t := 0.0
var _dash_dir := Vector2.RIGHT
var _fuse := -1.0
var _teleport_cd := 0.0
var _wisp_phase := 0.0
var _trail_t := 0.0

# Boss state.
var _phase := 1
var _t1 := 0.0
var _t2 := 0.0
var _t3 := 0.0
var _summoned_60 := false
var _summoned_30 := false
var _burst_left := 0
var _burst_t := 0.0
var _spiral_left := 0.0
var _spiral_angle := 0.0
var _ring_warn := 0.0
var _tele_warn := 0.0
var _tele_pos := Vector2.ZERO
var _pending: Array = []    # [{ "pos": Vector2, "t": float, "type": String }] summons being telegraphed
var _hazards: Array = []    # [{ "pos": Vector2, "t": float }] boss fire patches that hurt players
var _hazard_tick := 0.0


func configure(type: String, wave: int) -> void:
    kind_name = type
    _wave = wave
    var s: Array = STATS.get(type, STATS["grunt"])
    max_hp = float(s[0]) + float(s[1]) * float(wave)
    speed = float(s[2])
    radius = float(s[3])
    var per := 0.35
    if type == "elite" or type == "boss":
        per = 0.6
        is_elite = true
    if type == "boss":
        per = 0.8   # boss contact: 20 + 0.8 per difficulty
    contact_damage = float(s[4]) + per * float(wave)
    scrap_value = int(s[5])
    base_color = KIND_COLORS.get(type, base_color)
    match type:
        "swarmer":
            scrap_value = randi() % 2
        "wisp":
            immune_to = Element.ALL.pick_random()
            _wisp_phase = randf() * TAU
        "spitter":
            _shoot_t = randf_range(0.6, 1.6)
        "shaman":
            _pulse_t = randf_range(1.0, 3.0)
    _strafe_sign = 1.0 if randf() < 0.5 else -1.0
    hp = max_hp


## Elite affix; "" clears it. Call after configure (before or after adding to the tree).
func set_affix(name: String) -> void:
    affix = name if AFFIXES.has(name) else ""
    queue_redraw()


## Boss pattern. Call after configure("boss", wave), before or after adding to the tree.
func set_boss(kind: String) -> void:
    boss_kind = kind if BOSS_KINDS.has(kind) else ""
    base_color = KIND_COLORS.get(boss_kind if boss_kind != "" else kind_name, base_color)
    _reshield_at = [0.5]
    _t1 = 2.0
    _t2 = 3.0
    _t3 = 4.0
    match boss_kind:
        "brute_king":
            speed = 95.0
            radius = 32.0
        "hive_mother":
            speed = 65.0
            radius = 32.0
            _t1 = 2.0
            _t2 = 3.5
        "storm_warden":
            speed = 70.0
            radius = 30.0
            _t1 = 2.5
            _t2 = 6.0
        "pyre_lord":
            speed = 80.0
            radius = 30.0
            _t1 = 0.5
            _t2 = 5.0
        "void_herald":
            speed = 70.0
            radius = 30.0
            _reshield_at = [0.66, 0.33]
            _t1 = 2.0
            _t2 = 5.0
    if _shape != null:
        _shape.radius = radius
    _setup_sprite()
    queue_redraw()


func _ready() -> void:
    add_to_group("enemies")
    collision_layer = LAYER_ENEMIES
    collision_mask = LAYER_WALLS | LAYER_ENEMIES
    var shape := CollisionShape2D.new()
    _shape = CircleShape2D.new()
    _shape.radius = radius
    shape.shape = _shape
    add_child(shape)
    z_index = 8
    _setup_sprite()
    var fx := _fx()
    if fx != null:
        fx.puff(Art.PARTICLES["smoke"], global_position, Color(0.1, 0.08, 0.1, 0.7), radius * 4.5, 0.5, false, Vector2(0, -20))


func _setup_sprite() -> void:
    if not is_inside_tree():
        return
    var key := boss_kind if boss_kind != "" else kind_name
    if KIND_COLORS.has(key):
        base_color = KIND_COLORS[key]
    else:
        base_color = Art.ENEMY_TINT.get(kind_name, base_color)
    var coord: Vector2i = KIND_TILES[key] if KIND_TILES.has(key) else Art.TILES.get(kind_name, Art.TILES["grunt"])
    _sprite_scale = radius / 6.0
    if _sprite == null:
        _sprite = Art.sprite(coord, 0.01, base_color)
        add_child(_sprite)
    else:
        _sprite.texture = Art.tile(coord)
        _sprite.modulate = base_color


func _fx() -> Fx:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        return scene.fx
    return null


## Where projectiles, clouds and other loose effects go: the current room, else our parent.
func _world() -> Node:
    var scene := get_tree().current_scene
    if scene != null and "current" in scene and scene.current != null:
        return scene.current
    return get_parent()


## The room's floor area in global coordinates, if the room exposes one.
func _room_rect() -> Rect2:
    var w := _world()
    if w != null and w is Node2D and "rect" in w:
        var r = w.rect
        if r is Rect2:
            var rr: Rect2 = r
            return Rect2((w as Node2D).global_position + rr.position, rr.size)
    return Rect2()


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
    # What the element does to the body's condition before any pair reaction:
    # water puts fire out, fire thaws ice, wind fans a burning body onto its neighbours.
    if kind == Element.Kind.WET and burn_time > 0.0:
        burn_time = 0.0
        Elements.nova.emit(global_position, radius * 2.0, Color(0.9, 0.95, 1.0, 0.5))
    if kind == Element.Kind.FIRE and frozen_time > 0.0:
        frozen_time = 0.0
    if kind == Element.Kind.GALE and burn_time > 0.0:
        for e in get_tree().get_nodes_in_group("enemies"):
            if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                    and e.global_position.distance_to(global_position) <= 110.0:
                e.add_burn(burn_dps * 0.7, 2.5)
    for existing in states.keys():
        if existing == kind:
            continue
        var reaction := Elements.reaction_name(existing, kind)
        if reaction == "":
            continue
        states.erase(existing)
        if source != null:
            potency *= 1.0 + source.stat("potency:" + reaction)
        _react_window = 0.3
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


## Armoured bodies (wardens, the storm warden) shrug off raw hits until they carry an element.
func is_armoured() -> bool:
    return kind_name == "warden" or boss_kind == "storm_warden"


func take_damage(amount: float, color: Color, flash: bool = true, source: Player = null, crit: bool = false) -> void:
    if hp <= 0.0:
        return
    if source != null:
        last_hit_by = source
    if shielded():
        # A shield blocks most raw damage, never all of it: reactions are the fast way in.
        _shield_flash = maxf(_shield_flash, 0.15)
        amount *= 0.2
    if flash and is_armoured() and states.is_empty() and _react_window <= 0.0:
        amount *= WARDEN_ARMOUR
    if armour_time > 0.0:
        amount *= SHAMAN_ARMOUR
    if frozen_time > 0.0:
        amount *= 3.0
    if corroded_time > 0.0:
        amount *= 1.5
    hp -= amount
    Telemetry.hit(amount + minf(hp, 0.0), color, flash, source)
    _since_hit = 0.0
    if flash:
        var fx := _fx()
        if fx != null:
            fx.number(global_position + Vector2(0, -radius), amount, color if color != Color.WHITE else Color(0.95, 0.9, 0.85), crit)
    else:
        _dot_accum += amount
        _dot_color = color
    if flash:
        _flash = 0.12
        _flash_color = color
        _squash = 1.0
        Sfx.play("hit")
    if hp <= 0.0:
        _die()
        return
    if reshield_hits > 0 and not _reshield_at.is_empty() and hp <= max_hp * float(_reshield_at[0]):
        _reshield_at.pop_front()
        set_shield(reshield_weakness, reshield_hits)
        if _reshield_at.is_empty():
            reshield_hits = 0
        _shield_flash = 0.5
        Elements.reaction_fired.emit("Shield restored!", global_position, Color.WHITE)
    if flash and kind_name == "wisp" and _teleport_cd <= 0.0:
        _teleport_cd = 1.0
        _blink(150.0)
    queue_redraw()


func heal(amount: float) -> void:
    if hp <= 0.0:
        return
    hp = minf(max_hp, hp + amount)
    queue_redraw()


## Removed without dying: no scrap, no kill credit (room cleared, party left).
func vanish() -> void:
    _dead = true
    remove_from_group("enemies")
    queue_free()


func freeze(seconds: float) -> void:
    frozen_time = maxf(frozen_time, seconds)
    queue_redraw()


func apply_slow(factor: float, seconds: float) -> void:
    slow_factor = minf(slow_factor, factor) if slow_time > 0.0 else factor
    slow_time = maxf(slow_time, seconds)


func add_burn(dps: float, seconds: float) -> void:
    if has_state(Element.Kind.OIL):
        seconds *= 1.5   # oil keeps it burning
    if has_state(Element.Kind.WET):
        seconds *= 0.5   # damp bodies burn badly
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
    if _dead:
        return
    _dead = true
    hp = minf(hp, 0.0)
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
    remove_from_group("enemies")
    if kind_name == "bomber" or affix == "volatile":
        _explode(BOMB_DAMAGE, BOMB_RADIUS)
    if kind_name == "splitter":
        for i in 2:
            var off := Vector2.RIGHT.rotated(randf() * TAU) * radius
            _summon("swarmer", global_position + off, false)
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
    died.emit(self)
    queue_free()


## Bomber blast: hurts players, and lands Fire on nearby enemies so reactions go off.
func _explode(dmg: float, rad: float) -> void:
    if _exploded:
        return
    _exploded = true
    var pos := global_position
    Elements.nova.emit(pos, rad, Color(Element.COLORS[Element.Kind.FIRE], 0.7))
    Sfx.play("nova_fire")
    var fx := _fx()
    if fx != null:
        fx.blast(pos, rad, Element.COLORS[Element.Kind.FIRE])
        fx._shake(4.0)
    for p in get_tree().get_nodes_in_group("players"):
        if is_instance_valid(p) and p.alive and p.global_position.distance_to(pos) <= rad + p.radius:
            p.take_damage(dmg, self)
    var potency := 5.0 + 0.3 * float(_wave)
    for e in get_tree().get_nodes_in_group("enemies"):
        if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                and e.global_position.distance_to(pos) <= rad:
            e.apply_element(Element.Kind.FIRE, potency, null)
    var mats := Materials.find(self)
    if mats != null:
        mats.ignite(pos, rad)          # fuel in the blast catches
        mats.ignite(pos, 20.0, true)   # and the crater burns briefly


## What the floor does to us, a few times a second (see Materials).
func _feel_floor() -> void:
    _on_ice = false
    var mats := Materials.find(self)
    if mats == null:
        return
    match mats.material_at(global_position):
        Materials.FIRE:
            add_burn(4.0, 1.5)
        Materials.WATER:
            if not has_state(Element.Kind.WET):
                apply_element(Element.Kind.WET, 1.0, null)
        Materials.CHARGED:
            take_damage(3.0, Element.COLORS[Element.Kind.SHOCK], true)
            if not _dead and hp > 0.0 and not has_state(Element.Kind.SHOCK):
                apply_element(Element.Kind.SHOCK, 1.0, null)
        Materials.POISON:
            add_poison(2.0, 2.0)
        Materials.ACID:
            corrode(1.0)
        Materials.OIL:
            if burn_time > 0.0:
                mats.ignite(global_position, radius)   # a burning body lights the oil it walks in
            elif not has_state(Element.Kind.OIL):
                apply_element(Element.Kind.OIL, 1.0, null)
        Materials.ICE:
            _on_ice = true


## A bomber that reached a player: blows up, no scrap.
func _detonate() -> void:
    scrap_value = 0
    _explode(BOMB_DAMAGE, BOMB_RADIUS)
    hp = 0.0
    _die()


## Spawns another enemy beside this one, in the same container, reporting its death to
## whoever listens to ours (the room). Added deferred: this can run inside a physics callback.
func _summon(type: String, pos: Vector2, check_cap: bool = true) -> Enemy:
    var parent := get_parent()
    if parent == null:
        return null
    if check_cap and get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES_FOR_SUMMON:
        return null
    var rr := _room_rect()
    if rr.has_area():
        var inner := rr.grow(-40.0)
        pos = Vector2(clampf(pos.x, inner.position.x, inner.end.x), clampf(pos.y, inner.position.y, inner.end.y))
    var e := Enemy.new()
    e.configure(type, _wave)
    if parent is Node2D:
        e.position = (parent as Node2D).to_local(pos)
    else:
        e.position = pos
    for c in died.get_connections():
        var cb: Callable = c["callable"]
        if not e.died.is_connected(cb):
            e.died.connect(cb)
    parent.add_child.call_deferred(e)
    return e


func _shoot(dir: Vector2, spd: float, dmg: float, element: int, life: float = 3.0, rad: float = 6.0) -> void:
    var w := _world()
    if w == null:
        return
    var p := EnemyProjectile.new()
    p.damage = dmg * damage_mult
    p.speed = spd
    p.element = element
    p.lifetime = life
    p.radius = rad
    p.direction = dir.normalized()
    p.owner_enemy = self
    w.add_child(p)
    p.global_position = global_position + p.direction * radius * 0.8


func _projectile_damage(base: float) -> float:
    return base + 0.35 * float(_wave)


## Jumps up to `dist` px in a random direction, kept inside the room.
func _blink(dist: float) -> void:
    var to := global_position + Vector2.RIGHT.rotated(randf() * TAU) * dist
    var rr := _room_rect()
    if rr.has_area():
        var inner := rr.grow(-50.0)
        to = Vector2(clampf(to.x, inner.position.x, inner.end.x), clampf(to.y, inner.position.y, inner.end.y))
    _teleport_to(to)


func _teleport_to(to: Vector2) -> void:
    Elements.nova.emit(global_position, radius * 2.5, Color(base_color, 0.5))
    set_deferred("global_position", to)
    _spawn_t = 0.3
    var fx := _fx()
    if fx != null:
        fx.puff(Art.PARTICLES["smoke"], to, Color(base_color, 0.6), radius * 3.0, 0.4, false, Vector2(0, -10))


# --- Frame -----------------------------------------------------------------


func _physics_process(delta: float) -> void:
    for kind in states.keys():
        states[kind] -= delta
        if states[kind] <= 0.0:
            states.erase(kind)
    _fx_t += delta
    _dot_timer -= delta
    if _dot_timer <= 0.0 and _dot_accum >= 0.5:
        var fx := _fx()
        if fx != null:
            fx.number(global_position + Vector2(0, -radius), _dot_accum, _dot_color, false, true)
        _dot_accum = 0.0
        _dot_timer = 0.5
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
    armour_time = maxf(0.0, armour_time - delta)
    haste_aura_time = maxf(0.0, haste_aura_time - delta)
    _react_window = maxf(0.0, _react_window - delta)
    _teleport_cd = maxf(0.0, _teleport_cd - delta)
    _pulse_fx = maxf(0.0, _pulse_fx - delta)
    _since_hit += delta
    _contact_cd = maxf(0.0, _contact_cd - delta)
    _flash = maxf(0.0, _flash - delta)
    _shield_flash = maxf(0.0, _shield_flash - delta)

    _floor_t -= delta
    if _floor_t <= 0.0:
        _floor_t = 0.25
        _feel_floor()
        if _dead or hp <= 0.0:
            return

    _tick_affix(delta)
    if kind_name == "boss":
        _tick_boss_passive(delta)
        if _dead:
            return

    var prev_vel := velocity
    var target := _nearest_player()
    if frozen_time > 0.0 or stun_time > 0.0 or target == null:
        velocity = Vector2.ZERO
    else:
        velocity = _think(delta, target)
        if _dead:
            return
    if _on_ice and frozen_time <= 0.0:
        var keep := pow(Materials.ICE_KEEP, delta * 60.0)
        velocity = prev_vel * keep + velocity * (1.0 - keep)
    velocity += shove_vel
    shove_vel = shove_vel.move_toward(Vector2.ZERO, 900.0 * delta)
    move_and_slide()

    if target != null and _contact_cd <= 0.0 and is_instance_valid(target):
        var reach := radius + target.radius + 2.0
        if global_position.distance_squared_to(target.global_position) <= reach * reach:
            target.take_damage(contact_damage, self)
            _contact_cd = 0.8
    _update_sprite()
    queue_redraw()


func _speed_mult() -> float:
    var m := slow_factor if slow_time > 0.0 else 1.0
    if has_state(Element.Kind.STONE):
        m *= 0.75   # weighed down
    if affix == "hasted":
        m *= 1.35
    if haste_aura_time > 0.0:
        m *= 1.15
    if boss_kind == "pyre_lord" and _phase == 2:
        m *= 1.4
    return m


## Desired velocity for this frame, per kind. Also fires shots, pulses, fuses.
func _think(delta: float, target: Player) -> Vector2:
    var to_target := target.global_position - global_position
    var dist := to_target.length()
    var dir := to_target / dist if dist > 0.01 else Vector2.RIGHT
    var mult := _speed_mult()
    if kind_name == "boss":
        return _think_boss(delta, target, dir, dist, mult)
    match kind_name:
        "spitter":
            _shoot_t -= delta
            if _shoot_t <= 0.0 and dist < 560.0:
                _shoot_t = 1.6
                var el: int = immune_to if immune_to != Element.Kind.NONE else Element.Kind.NONE
                _shoot(dir, 250.0, _projectile_damage(6.0), el, 3.0, 6.0)
                _squash = 0.6
            return _keep_range(delta, dir, dist, 220.0, 300.0) * speed * mult
        "charger":
            return _charge_ai(delta, dir, dist, mult, 0.6, 420.0, 0.5, 1.5, 260.0)
        "shaman":
            _pulse_t -= delta
            if _pulse_t <= 0.0:
                _pulse_t = 3.0
                _shaman_pulse()
            return _keep_range(delta, dir, dist, 260.0, 340.0) * speed * mult
        "bomber":
            if _fuse >= 0.0:
                _fuse -= delta
                if _fuse <= 0.0:
                    _detonate()
                    return Vector2.ZERO
                return dir * speed * 0.3 * mult
            if dist <= BOMB_TRIGGER + target.radius:
                _fuse = 0.3
                Sfx.play("tick")
            return dir * speed * mult
        "wisp":
            _wisp_phase += delta * 5.0
            var wobble := sin(_wisp_phase) * 1.1 + sin(_wisp_phase * 0.37) * 0.5
            return dir.rotated(wobble) * speed * mult
    return dir * speed * mult


## Approach when far, back off when near, strafe in between. Returns a direction (0..1 length).
func _keep_range(delta: float, dir: Vector2, dist: float, near: float, far: float) -> Vector2:
    _strafe_t -= delta
    if _strafe_t <= 0.0:
        _strafe_t = randf_range(1.5, 3.0)
        _strafe_sign = -_strafe_sign
    if dist > far:
        return dir
    if dist < near:
        return -dir
    return dir.orthogonal() * _strafe_sign * 0.5


## Chase, telegraph (stand still, aim), dash, cool down. Shared by charger and brute king.
func _charge_ai(delta: float, dir: Vector2, dist: float, mult: float, warn: float, dash_speed: float, dash_time: float, cool: float, trigger: float) -> Vector2:
    _mode_t -= delta
    match _mode:
        MODE_TELEGRAPH:
            if _mode_t <= 0.0:
                _mode = MODE_DASH
                _mode_t = dash_time
                Sfx.play("hit")
            return Vector2.ZERO
        MODE_DASH:
            if _mode_t <= 0.0:
                _mode = MODE_COOL
                _mode_t = cool
            return _dash_dir * dash_speed
        MODE_COOL:
            if _mode_t <= 0.0:
                _mode = MODE_CHASE
            return dir * speed * 0.4 * mult
    if dist <= trigger:
        _mode = MODE_TELEGRAPH
        _mode_t = warn
        _dash_dir = dir
        return Vector2.ZERO
    return dir * speed * mult


func _shaman_pulse() -> void:
    _pulse_fx = 0.6
    Elements.nova.emit(global_position, 160.0, Color(0.5, 1.0, 0.5, 0.5))
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or e.kind_name == "boss":
            continue
        if e.global_position.distance_to(global_position) <= 160.0:
            e.heal(e.max_hp * 0.10)
            e.armour_time = maxf(e.armour_time, 2.0)


func _tick_affix(delta: float) -> void:
    match affix:
        "regenerating":
            if _since_hit >= 2.0 and hp < max_hp:
                heal(max_hp * 0.02 * delta)
        "hasted":
            for e in get_tree().get_nodes_in_group("enemies"):
                if e != self and is_instance_valid(e) and e.global_position.distance_to(global_position) <= 150.0:
                    e.haste_aura_time = 0.25
        "trail":
            _trail_t -= delta
            if _trail_t <= 0.0:
                _trail_t = 0.8
                var el: int = immune_to if immune_to != Element.Kind.NONE else Element.Kind.OIL
                var w := _world()
                if w != null:
                    Cloud.spawn(w, global_position, el, 60.0, 4.0, 4.0, null)


# --- Bosses ----------------------------------------------------------------


## Phase change, scripted summons and hazards; runs even while the boss is frozen.
func _tick_boss_passive(delta: float) -> void:
    if _phase == 1 and hp <= max_hp * 0.5:
        _phase = 2
        Telemetry.boss_phase2(self)
        Elements.reaction_fired.emit("ENRAGED", global_position, Color(1.0, 0.3, 0.2))
        var fx := _fx()
        if fx != null:
            fx._shake(8.0)
    # Telegraphed summons land when their timer runs out.
    for i in range(_pending.size() - 1, -1, -1):
        var s: Dictionary = _pending[i]
        s["t"] = float(s["t"]) - delta
        if float(s["t"]) <= 0.0:
            _pending.remove_at(i)
            var spawned := _summon(String(s["type"]), s["pos"])
            if spawned != null:
                Elements.nova.emit(s["pos"], 30.0, Color(base_color, 0.6))
    match boss_kind:
        "brute_king":
            if not _summoned_60 and hp <= max_hp * 0.6:
                _summoned_60 = true
                _queue_summons("grunt", 3, 0.8)
            if not _summoned_30 and hp <= max_hp * 0.3:
                _summoned_30 = true
                _queue_summons("grunt", 3, 0.8)
        "pyre_lord":
            _hazard_tick -= delta
            for i in range(_hazards.size() - 1, -1, -1):
                var hz: Dictionary = _hazards[i]
                hz["t"] = float(hz["t"]) - delta
                if float(hz["t"]) <= 0.0:
                    _hazards.remove_at(i)
            if _hazard_tick <= 0.0:
                _hazard_tick = 0.5
                for p in get_tree().get_nodes_in_group("players"):
                    if not is_instance_valid(p) or not p.alive:
                        continue
                    for hz in _hazards:
                        if p.global_position.distance_to(hz["pos"]) <= 55.0:
                            p.take_damage(5.0 + 0.25 * float(_wave), self)
                            break


func _queue_summons(type: String, count: int, warn: float) -> void:
    for i in count:
        var a := TAU * float(i) / float(count) + randf() * 0.5
        var pos := global_position + Vector2.RIGHT.rotated(a) * (radius + 60.0)
        _pending.append({ "pos": pos, "t": warn, "type": type })


func _think_boss(delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    match boss_kind:
        "brute_king":
            if _phase == 1:
                return _charge_ai(delta, dir, dist, mult, 0.8, 480.0, 0.6, 2.5, 340.0)
            return _charge_ai(delta, dir, dist, mult, 0.5, 540.0, 0.6, 1.2, 420.0)
        "hive_mother":
            _t1 -= delta
            _t2 -= delta
            if _t1 <= 0.0:
                _t1 = 4.0
                _queue_summons("swarmer", 3 if _phase == 1 else 5, 0.7)
            _ring_warn = maxf(0.0, _t2) if _t2 < 0.6 else 0.0
            if _t2 <= 0.0:
                _t2 = 5.0 if _phase == 1 else 3.5
                _ring_warn = 0.0
                var n := 8 if _phase == 1 else 12
                var off := randf() * TAU
                for i in n:
                    _shoot(Vector2.RIGHT.rotated(off + TAU * float(i) / float(n)), 170.0, _projectile_damage(7.0), Element.Kind.POISON, 4.0, 7.0)
                _squash = 1.0
            return _keep_range(delta, dir, dist, 200.0, 320.0) * speed * mult
        "storm_warden":
            _t1 -= delta
            _t2 -= delta
            # Bursts of shock bolts: five aimed shots; in phase two each shot is a three-way fan.
            if _t1 <= 0.0 and _burst_left <= 0:
                _t1 = 3.0 if _phase == 1 else 2.0
                _burst_left = 5
                _burst_t = 0.0
            if _burst_left > 0:
                _burst_t -= delta
                if _burst_t <= 0.0:
                    _burst_t = 0.12
                    _burst_left -= 1
                    var dmg := _projectile_damage(6.0)
                    _shoot(dir, 300.0, dmg, Element.Kind.SHOCK, 3.0, 6.0)
                    if _phase == 2:
                        _shoot(dir.rotated(0.3), 300.0, dmg, Element.Kind.SHOCK, 3.0, 6.0)
                        _shoot(dir.rotated(-0.3), 300.0, dmg, Element.Kind.SHOCK, 3.0, 6.0)
            # Teleport, telegraphed by a crackling circle where it will land.
            if _tele_warn > 0.0:
                _tele_warn -= delta
                if _tele_warn <= 0.0:
                    _teleport_to(_tele_pos)
                    Sfx.play("react_chain")
                return Vector2.ZERO
            if _t2 <= 0.0:
                _t2 = 6.0 if _phase == 1 else 4.0
                _tele_pos = _pick_point_near(target.global_position, 200.0, 340.0)
                _tele_warn = 0.8
                return Vector2.ZERO
            return _keep_range(delta, dir, dist, 160.0, 280.0) * speed * mult
        "pyre_lord":
            _t1 -= delta
            _t2 -= delta
            if _t1 <= 0.0:
                _t1 = 1.2 if _phase == 1 else 0.7
                var w := _world()
                if w != null:
                    Cloud.spawn(w, global_position, Element.Kind.FIRE, 60.0, 5.0, 5.0, null)
                _hazards.append({ "pos": global_position, "t": 5.0 })
                if _hazards.size() > 12:
                    _hazards.pop_front()
            if _t2 <= 0.0:
                _t2 = 8.0
                _queue_summons("bomber", 2 if _phase == 1 else 3, 0.9)
            return dir * speed * mult
        "void_herald":
            _t1 -= delta
            _t2 -= delta
            _t3 -= delta
            # Pull: players within range are dragged slowly towards the herald.
            var pull_r := 260.0 if _phase == 1 else 320.0
            var pull_s := 40.0 if _phase == 1 else 65.0
            for p in get_tree().get_nodes_in_group("players"):
                if is_instance_valid(p) and p.alive and p is CharacterBody2D:
                    var d: float = p.global_position.distance_to(global_position)
                    if d <= pull_r and d > radius + 20.0:
                        (p as CharacterBody2D).move_and_collide((global_position - p.global_position).normalized() * pull_s * delta)
            # Spiral volleys.
            if _t1 <= 0.0 and _spiral_left <= 0.0:
                _t1 = 5.0 if _phase == 1 else 3.5
                _spiral_left = 2.5
                _burst_t = 0.0
            if _spiral_left > 0.0:
                _spiral_left -= delta
                _burst_t -= delta
                _spiral_angle += delta * 3.2
                if _burst_t <= 0.0:
                    _burst_t = 0.12
                    var arms := 2 if _phase == 1 else 3
                    for i in arms:
                        _shoot(Vector2.RIGHT.rotated(_spiral_angle + TAU * float(i) / float(arms)), 180.0, _projectile_damage(6.0), Element.Kind.VOID, 4.0, 7.0)
            if _t2 <= 0.0:
                _t2 = 7.0
                _queue_summons("wisp", 2 if _phase == 1 else 3, 0.8)
            return _keep_range(delta, dir, dist, 140.0, 240.0) * speed * mult
    return dir * speed * mult


func _pick_point_near(around: Vector2, min_d: float, max_d: float) -> Vector2:
    var rr := _room_rect()
    var inner := rr.grow(-70.0) if rr.has_area() else Rect2()
    var p := around
    for attempt in 10:
        p = around + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(min_d, max_d)
        if not inner.has_area() or inner.has_point(p):
            return p
    if inner.has_area():
        p = Vector2(clampf(p.x, inner.position.x, inner.end.x), clampf(p.y, inner.position.y, inner.end.y))
    return p


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
    if _mode == MODE_TELEGRAPH and fmod(_mode_t, 0.16) < 0.08:
        c = c.lerp(Color(1, 0.3, 0.2), 0.7)
    if _fuse >= 0.0 and fmod(_fuse, 0.1) < 0.05:
        c = c.lerp(Color(1, 1, 0.6), 0.8)
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
    _draw_kind()
    if is_elite:
        draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
    if immune_to != Element.Kind.NONE:
        draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Element.COLORS[immune_to], 3.0)
        draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color(0, 0, 0, 0.4), 1.0)
    if shielded():
        draw_arc(Vector2.ZERO, radius + 11.0, 0.0, TAU, 40, Color(1, 1, 1, 0.45 + _shield_flash), 2.5)
    if armour_time > 0.0:
        draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 24, Color(0.5, 1.0, 0.5, 0.6), 2.0)
    if affix != "":
        _draw_affix()

    # Element states drawn on the body.
    if states.has(Element.Kind.WET):
        for i in 2:
            var dx := -radius * 0.4 + float(i) * radius * 0.8
            draw_circle(Vector2(dx, radius * 0.6 + fmod(_anim_t * 6.0 + i * 3.0, 6.0)), 2.2, Color(Element.COLORS[Element.Kind.WET], 0.9))
    if states.has(Element.Kind.SHOCK):
        # One or two jagged 1 px arcs crawling over the body, a white pixel at each tip.
        for k in 1 + randi() % 2:
            var a0 := randf() * TAU
            var p0 := Vector2.RIGHT.rotated(a0) * radius * randf_range(0.7, 1.2)
            var p2 := Vector2.RIGHT.rotated(a0 + randf_range(0.6, 1.4)) * radius * randf_range(0.7, 1.2)
            var p1 := (p0 + p2) * 0.5 + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
            draw_polyline(PackedVector2Array([p0, p1, p2]), Color(1.0, 0.95, 0.4, 0.7), 1.0)
            draw_rect(Rect2(floorf(p2.x - 1.0), floorf(p2.y - 1.0), 2.0, 2.0), Color(1, 1, 0.9, 0.75))
    # Statuses shed pixels into the world effects layer about ten times a second.
    if burn_time > 0.0 or poison_time > 0.0:
        var now := Time.get_ticks_msec()
        if now - _shed_ms >= 100:
            _shed_ms = now
            var fx := _fx()
            if fx != null:
                if burn_time > 0.0:
                    fx.ember(global_position + Vector2(randf_range(-radius * 0.5, radius * 0.5), -radius * randf_range(0.6, 1.2)))
                if poison_time > 0.0 and randf() < 0.3 + 0.15 * float(poison_stacks):
                    fx.mote(Element.Kind.POISON, global_position + Vector2(randf_range(-radius, radius), randf_range(-radius, radius * 0.3)))
    if burn_time > 0.0:
        _draw_pixel_flame(Vector2(0, -radius * 0.2), radius * 1.1, radius * 1.6, 8)
    if frozen_time > 0.0:
        # A crystalline outline: pale pixels around the body, one glint running round.
        var n := 14
        var glint := int(_fx_t * 10.0) % n
        draw_circle(Vector2.ZERO, radius + 2.0, Color(0.7, 0.95, 1.0, 0.12))
        for k in n:
            var a1 := TAU * float(k) / float(n)
            var q := Vector2(cos(a1), sin(a1)) * (radius + 3.0 + (1.5 if k % 3 == 0 else 0.0))
            var sz := 3.0 if k % 2 == 0 else 2.0
            var cc := Color(1, 1, 1, 0.75) if k == glint else (Color(0.85, 0.97, 1.0, 0.6) if k % 2 == 0 else Color(0.55, 0.8, 0.95, 0.5))
            draw_rect(Rect2(floorf(q.x - sz * 0.5), floorf(q.y - sz * 0.5), sz, sz), cc)
    if poison_time > 0.0:
        for k in poison_stacks:
            var a2 := _anim_t * 0.7 + float(k) * 1.1
            var q2 := Vector2(cos(a2) * radius * 1.1, -radius * 0.5 - fmod(a2 * 4.0, 14.0))
            draw_rect(Rect2(floorf(q2.x - 1.5), floorf(q2.y - 1.5), 3.0, 3.0), Color(0.45, 0.9, 0.2, 0.55))
            draw_rect(Rect2(floorf(q2.x - 0.5), floorf(q2.y - 0.5), 1.0, 1.0), Color(0.75, 1.0, 0.5, 0.75))
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
        draw_rect(Rect2(-w / 2.0, radius + 5.0, w * maxf(0.0, hp) / max_hp, 4.0), Color(0.9, 0.2, 0.2))


## A flickering flame of `count` pixel squares rising from `base` (local), `w` wide, `h` tall.
func _draw_pixel_flame(base: Vector2, w: float, h: float, count: int) -> void:
    var tick := int(_fx_t * 15.0)
    for k in count:
        var rise := fmod(_fx_t * 1.6 + float(k) * 0.618, 1.0)   # 0 at the base, 1 at the tip
        var x := sin(_fx_t * 9.0 + float(k) * 2.1) * w * 0.4 * (1.0 - rise)
        var pos := base + Vector2(x, -rise * h)
        var sz := floorf(4.0 - 2.5 * rise + 0.5)
        var col: Color
        if rise < 0.35:
            col = Color(1.0, 0.88, 0.35, 0.7) if (k + tick) % 3 == 0 else Color(1.0, 0.45, 0.15, 0.6)
        elif rise < 0.75:
            col = Color(1.0, 0.45, 0.15, 0.55) if (k + tick) % 2 == 0 else Color(0.72, 0.14, 0.08, 0.5)
        else:
            col = Color(0.72, 0.14, 0.08, 0.4)
        draw_rect(Rect2(floorf(pos.x - sz * 0.5), floorf(pos.y - sz * 0.5), sz, sz), col)
    # A 2 px hot core at the base, the only opaque bit.
    draw_rect(Rect2(floorf(base.x - 1.0), floorf(base.y - 1.0), 2.0, 2.0), Color(1.0, 0.95, 0.6, 0.9))


## Per-kind tells: charge lines, fuses, armour plates, heal pulses, boss telegraphs.
func _draw_kind() -> void:
    if _mode == MODE_TELEGRAPH:
        var length := 420.0 * 0.5 if kind_name == "charger" else 300.0
        var a := 0.35 + 0.35 * absf(sin(_fx_t * 20.0))
        var w := radius * (0.6 if kind_name == "charger" else 1.6)
        draw_line(Vector2.ZERO, _dash_dir * length, Color(1, 0.25, 0.2, a), w)
        draw_line(Vector2.ZERO, _dash_dir * length, Color(1, 0.9, 0.8, a), 1.5)
    match kind_name:
        "bomber":
            # Lit fuse on the head; while armed, the blast radius flashes.
            draw_line(Vector2(0, -radius), Vector2(3, -radius - 6), Color(0.6, 0.5, 0.4), 1.5)
            draw_circle(Vector2(3, -radius - 6), 2.0 + absf(sin(_fx_t * 12.0)), Color(1, 0.8, 0.3))
            if _fuse >= 0.0:
                draw_arc(Vector2.ZERO, BOMB_RADIUS, 0.0, TAU, 40, Color(1, 0.4, 0.2, 0.7), 2.0)
                draw_circle(Vector2.ZERO, BOMB_RADIUS, Color(1, 0.4, 0.2, 0.12))
        "warden":
            if states.is_empty():
                for k in 4:
                    var a0 := float(k) * TAU / 4.0 + 0.2
                    draw_arc(Vector2.ZERO, radius + 2.0, a0, a0 + TAU / 4.0 - 0.4, 8, Color(0.75, 0.78, 0.85, 0.9), 3.0)
        "shaman":
            if _pulse_fx > 0.0:
                var r := 160.0 * (1.0 - _pulse_fx / 0.6)
                draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.5, 1.0, 0.5, _pulse_fx), 2.0)
            draw_circle(Vector2(0, -radius - 3.0), 2.5, Color(0.5, 1.0, 0.5, 0.6 + 0.4 * sin(_fx_t * 4.0)))
        "spitter":
            if _shoot_t < 0.35:
                draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - _shoot_t / 0.35) + 2.0, Color(0.6, 1.0, 0.4, 0.5))
        "wisp":
            draw_circle(Vector2.ZERO, radius * 1.6, Color(base_color, 0.12 + 0.08 * sin(_fx_t * 6.0)))
        "boss":
            _draw_boss()


func _draw_affix() -> void:
    var pos := Vector2(radius + 6.0, -radius - 4.0)
    draw_circle(pos, 6.0, Color(0, 0, 0, 0.6))
    match affix:
        "regenerating":
            var c := Color(0.4, 1.0, 0.4)
            draw_line(pos + Vector2(-3.5, 0), pos + Vector2(3.5, 0), c, 2.0)
            draw_line(pos + Vector2(0, -3.5), pos + Vector2(0, 3.5), c, 2.0)
            if _since_hit >= 2.0 and hp < max_hp:
                draw_arc(Vector2.ZERO, radius + 7.0, _fx_t * 2.0, _fx_t * 2.0 + 1.5, 12, Color(c, 0.6), 2.0)
        "hasted":
            var c := Color(0.5, 0.9, 1.0)
            draw_line(pos + Vector2(-3, -3), pos + Vector2(0, 0), c, 2.0)
            draw_line(pos + Vector2(0, 0), pos + Vector2(-3, 3), c, 2.0)
            draw_line(pos + Vector2(1, -3), pos + Vector2(4, 0), c, 2.0)
            draw_line(pos + Vector2(4, 0), pos + Vector2(1, 3), c, 2.0)
            draw_arc(Vector2.ZERO, 150.0, 0.0, TAU, 48, Color(c, 0.12), 1.5)
        "trail":
            var el: int = immune_to if immune_to != Element.Kind.NONE else Element.Kind.OIL
            var c: Color = Element.COLORS[el]
            draw_circle(pos + Vector2(-2, 1), 2.5, c)
            draw_circle(pos + Vector2(2.5, -1.5), 1.8, c)
        "volatile":
            var c := Color(1.0, 0.45 + 0.3 * sin(_fx_t * 8.0), 0.2)
            draw_circle(pos, 3.5, c)
            draw_line(pos + Vector2(0, -3.5), pos + Vector2(2, -6), Color(1, 0.9, 0.5), 1.5)


func _draw_boss() -> void:
    # Phase two: a red pulse around the body.
    if _phase == 2:
        draw_arc(Vector2.ZERO, radius + 16.0, 0.0, TAU, 48, Color(1, 0.2, 0.15, 0.35 + 0.25 * sin(_fx_t * 6.0)), 3.0)
    # Telegraphed summons: a closing ring where each will appear.
    for s in _pending:
        var lp := to_local(s["pos"])
        var k := clampf(float(s["t"]) / 0.9, 0.0, 1.0)
        draw_arc(lp, 10.0 + 24.0 * k, 0.0, TAU, 24, Color(base_color, 0.8 - 0.5 * k), 2.0)
        draw_circle(lp, 6.0, Color(base_color, 0.3))
    match boss_kind:
        "brute_king":
            # A crown.
            var top := -radius - 10.0
            var pts := PackedVector2Array([Vector2(-10, top + 8), Vector2(-10, top), Vector2(-5, top + 4), Vector2(0, top - 2), Vector2(5, top + 4), Vector2(10, top), Vector2(10, top + 8)])
            draw_colored_polygon(pts, Color(1.0, 0.8, 0.3))
        "hive_mother":
            for k in 5:
                var a := float(k) * TAU / 5.0 + _fx_t * 0.3
                draw_circle(Vector2.RIGHT.rotated(a) * (radius + 6.0), 4.0, Color(0.7, 0.9, 0.4, 0.8))
            if _ring_warn > 0.0:
                var r := radius + 70.0 * (1.0 - _ring_warn / 0.6)
                draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(Element.COLORS[Element.Kind.POISON], 0.8), 3.0)
        "storm_warden":
            if states.is_empty():
                for k in 6:
                    var a0 := float(k) * TAU / 6.0 + _fx_t * 0.5
                    draw_arc(Vector2.ZERO, radius + 4.0, a0, a0 + 0.7, 6, Color(0.85, 0.85, 0.6, 0.9), 3.5)
            if _tele_warn > 0.0:
                var lp := to_local(_tele_pos)
                var c: Color = Element.COLORS[Element.Kind.SHOCK]
                draw_arc(lp, radius + 10.0, 0.0, TAU, 32, Color(c, 0.9), 2.5)
                for k in 4:
                    var a := randf() * TAU
                    var p := lp + Vector2.RIGHT.rotated(a) * radius
                    draw_line(p, p + Vector2.RIGHT.rotated(a + randf_range(-1.0, 1.0)) * 12.0, c, 2.0)
                draw_line(Vector2.ZERO, lp, Color(c, 0.25), 2.0)
            if _burst_left > 0:
                draw_circle(Vector2.ZERO, radius * 0.5, Color(Element.COLORS[Element.Kind.SHOCK], 0.35))
        "pyre_lord":
            for hz in _hazards:
                draw_circle(to_local(hz["pos"]), 55.0, Color(1.0, 0.35, 0.1, 0.10 * clampf(float(hz["t"]), 0.0, 1.0)))
            _draw_pixel_flame(Vector2(0, -radius * 0.5), radius * 1.6, radius * 2.2, 14 if _phase == 2 else 10)
        "void_herald":
            var pull_r := 260.0 if _phase == 1 else 320.0
            var c: Color = Element.COLORS[Element.Kind.VOID]
            draw_arc(Vector2.ZERO, pull_r, 0.0, TAU, 64, Color(c, 0.18), 2.0)
            var r := pull_r * (1.0 - fmod(_fx_t * 0.5, 1.0))
            draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(c, 0.25), 1.5)
            if _spiral_left > 0.0 or _t1 < 0.6:
                for k in 3:
                    var a := _spiral_angle + float(k) * TAU / 3.0
                    draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(a) * (radius + 14.0), Color(c, 0.7), 3.0)
