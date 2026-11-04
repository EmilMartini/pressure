class_name Player
extends CharacterBody2D
## One player: movement, the carried arsenal (which aims and fires itself), gear,
## level-ups, pressure gauge, health. Guns orbit the figure and point where they shoot.

signal died(player: Player)
signal leveled_up(player: Player)

const LAYER_PLAYERS := 1
const LAYER_WALLS := 4
const BASE_SPEED := 320.0
const SPEED_LOSS_PER_WEIGHT := 0.025
const PRESSURE_DECAY := 7.0        # per second, toward neutral
const PRESSURE_LIMIT := 100.0
const VENT_MIN := 20.0
const GUN_RING := 26.0
const EQUIP_KEYS := ["head", "chest", "hands", "feet", "ring1", "ring2", "trinket1", "trinket2", "active"]

const PLAYER_COLORS := [
    Color(0.40, 0.90, 0.55),
    Color(0.95, 0.55, 0.85),
    Color(0.95, 0.80, 0.35),
    Color(0.55, 0.75, 1.00),
]

var index := 0
var input: PlayerInput
var color := Color.WHITE
var radius := 14.0

var max_hp_base := 100.0
var max_hp := 100.0
var hp := 100.0
var alive := true
var invuln := 0.0

var weight_capacity_base := 10
var weight_capacity := 10
var guns: Array[Gun] = []

## Equipped gear: EQUIP_KEYS -> item id. Gun mods live on the guns.
var equipment: Dictionary = {}
var active_charges := 0           # charges on the active item (equipment["active"])
var _stats: Dictionary = {}

## Level-ups: xp from kills, upgrades picked on the level-up screen.
var xp := 0.0
var level := 1
var bonus_stats: Dictionary = {}

var aim_dir := Vector2.RIGHT      # where the figure faces: the nearest enemy, else movement
var pressure := 0.0               # -limit cold .. +limit hot: vent charge, nothing more
var pressure_limit_bonus := 0.0   # from run boons
var kills := 0
var last_message := ""
var _message_time := 0.0
var _sprite: Sprite2D
var _anim_t := 0.0
var _recoil := Vector2.ZERO
var _squash := 0.0
var _mastery: Node = null
var _squash_scale := 2.0


func _init(p_index: int, p_input: PlayerInput) -> void:
    index = p_index
    input = p_input
    color = PLAYER_COLORS[p_index % PLAYER_COLORS.size()]
    name = "Player%d" % (p_index + 1)


func _ready() -> void:
    add_to_group("players")
    collision_layer = LAYER_PLAYERS
    collision_mask = LAYER_WALLS
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    add_child(shape)
    z_index = 10
    var tiles: Array = Art.TILES["player"]
    _sprite = Art.sprite(tiles[index % tiles.size()], 2.0, color.lerp(Color.WHITE, 0.35))
    add_child(_sprite)
    _mastery = get_node_or_null("/root/Mastery")


func main() -> Main:
    return get_tree().current_scene as Main


# --- Arsenal ---------------------------------------------------------------


func total_weight() -> int:
    var w := 0
    for g in guns:
        w += g.data.weight
    return w


func can_carry(data: GunData) -> bool:
    return total_weight() + data.weight <= weight_capacity


## Pick up a gun. A duplicate of a gun you carry merges into it one tier higher, Brotato
## style, instead of taking weight.
func add_gun(id: String) -> bool:
    for g in guns:
        if g.data.id == id and g.tier < Gun.MAX_TIER:
            g.tier += 1
            say("%s" % g.display_name())
            Sfx.play("unlock")
            return true
    var data := Guns.make(id)
    if not can_carry(data):
        say("Too heavy: %s needs %d, %d free" % [data.display_name, data.weight, weight_capacity - total_weight()])
        return false
    var gun := Gun.new(data, self)
    add_child(gun)
    guns.append(gun)
    _layout_guns()
    say("Picked up %s" % data.display_name)
    return true


## The gunsmith raises your lowest-tier gun. Returns it, or null when nothing can rise.
func upgrade_lowest_gun() -> Gun:
    var best: Gun = null
    for g in guns:
        if g.tier < Gun.MAX_TIER and (best == null or g.tier < best.tier):
            best = g
    if best != null:
        best.tier += 1
        say("%s" % best.display_name())
    return best


## Take a gun off the player. Returns its id so the room can put it on the floor.
func drop_gun(gun: Gun) -> String:
    if not guns.has(gun):
        return ""
    var id := gun.data.id
    guns.erase(gun)
    remove_child(gun)
    gun.queue_free()
    _layout_guns()
    recalc_stats()
    say("Dropped %s" % gun.data.display_name)
    return id


## Guns sit in a ring around the figure so what you carry is what you see.
func _layout_guns() -> void:
    var n := guns.size()
    for i in n:
        var angle := -PI / 2.0 + TAU * float(i) / float(n)
        guns[i].position = Vector2.RIGHT.rotated(angle) * (GUN_RING + 4.0 * float(mini(n, 8)))


func element_kinds() -> Array:
    var kinds := []
    for g in guns:
        if not kinds.has(g.data.element):
            kinds.append(g.data.element)
    return kinds


## The gun a new mod goes on: the first with a free slot (a gun holds as many mods as
## its tier), or null when every slot is full.
func mod_target() -> Gun:
    for g in guns:
        if g.mods.size() < g.tier:
            return g
    return null


# --- Gear and level-ups -----------------------------------------------------


## Fit a mod to a chosen gun.
func equip_mod_on(gun: Gun, id: String) -> void:
    if gun == null or not is_instance_valid(gun):
        return
    gun.mods.append(id)
    say("%s fitted to %s" % [Items.get_item(id)["name"], gun.display_name()])
    recalc_stats()


## Guns that still have a free mod slot.
func mod_candidates() -> Array:
    return guns.filter(func(g): return g.mods.size() < g.tier)


## Equip an item. Returns the id it replaced, or "".
func equip(id: String) -> String:
    var item := Items.get_item(id)
    if item.is_empty():
        return ""
    var slot: String = item["slot"]
    var old := ""
    if slot == "mod":
        var g := mod_target()
        if g == null:
            say("No free mod slot: upgrade a gun")
            return ""
        equip_mod_on(g, id)
        return ""
    else:
        var key := slot
        if slot in ["ring", "trinket"]:
            if not equipment.has(slot + "1"):
                key = slot + "1"
            elif not equipment.has(slot + "2"):
                key = slot + "2"
            else:
                key = slot + "1"
        old = equipment.get(key, "")
        equipment[key] = id
        if slot == "active":
            active_charges = Items.active_max_charges(self)
        say("Equipped %s" % item["name"])
    recalc_stats()
    return old


## Use the active item (Isaac's spacebar item). False when empty or out of charges.
func use_active() -> bool:
    return Items.use_active(self)


func equipped_item_ids() -> Array:
    var out: Array = equipment.values().duplicate()
    for g in guns:
        out.append_array(g.mods)
    return out


func recalc_stats() -> void:
    var old_max := max_hp
    _stats = {}
    for id in equipment.values():
        var mods: Dictionary = Items.get_item(id).get("mods", {})
        for k in mods.keys():
            _stats[k] = float(_stats.get(k, 0.0)) + float(mods[k])
    var set_mods := Items.set_bonus_mods(self)
    for k in set_mods.keys():
        _stats[k] = float(_stats.get(k, 0.0)) + float(set_mods[k])
    max_hp = maxf(20.0, max_hp_base + stat("max_hp"))
    hp = clampf(hp + maxf(0.0, max_hp - old_max), 1.0, max_hp)
    weight_capacity = weight_capacity_base + int(stat("carry"))


## Summed modifier for a key: gear, set bonuses, level-ups, mastery, and conditional
## gear modifiers that currently hold.
func stat(key: String) -> float:
    var v := float(_stats.get(key, 0.0)) + float(bonus_stats.get(key, 0.0))
    if _mastery != null:
        v += _mastery.bonus(key)
    for id in equipment.values():
        var cm: Dictionary = Items.get_item(id).get("cond_mods", {})
        for cond in cm.keys():
            if cm[cond].has(key) and Items.condition(cond, self, {}):
                v += float(cm[cond][key])
    return v


## Brotato-shaped: each level costs noticeably more than the last, so a floor gives a
## few levels, not a dozen.
func xp_to_next() -> float:
    var n := float(level - 1)
    return 20.0 + 15.0 * n + 3.0 * n * n


func gain_xp(amount: float) -> void:
    if not alive:
        return
    xp += amount * (1.0 + stat("xp_gain"))
    while xp >= xp_to_next():
        xp -= xp_to_next()
        level += 1
        say("Level %d" % level)
        Sfx.play("unlock")
        leveled_up.emit(self)


## Called by the level-up screen with an option from LevelUps.
func apply_upgrade(opt: Dictionary) -> void:
    var key: String = opt["key"]
    bonus_stats[key] = float(bonus_stats.get(key, 0.0)) + float(opt["amount"])
    recalc_stats()
    say(opt.get("name", "Upgrade"))


func pressure_limit() -> float:
    return PRESSURE_LIMIT + pressure_limit_bonus + stat("pressure_limit")


func move_speed() -> float:
    return BASE_SPEED * (1.0 + stat("speed")) * maxf(0.4, 1.0 - SPEED_LOSS_PER_WEIGHT * total_weight())


func heal(amount: float) -> void:
    if alive:
        hp = minf(max_hp, hp + amount)


## Called by enemies when a reaction this player caused fires.
func on_reaction(_reaction_name: String) -> void:
    var steal := stat("lifesteal")
    if steal > 0.0:
        heal(steal)


# --- Pressure --------------------------------------------------------------


## Pressure is vent charge. Hot and cold guns push it either way; it never stalls you.
func add_pressure(amount: float) -> void:
    var limit := pressure_limit()
    pressure = clampf(pressure + amount, -limit, limit)


## Nudge the figure opposite to a shot; called by Gun.
func kick(dir: Vector2, strength: float) -> void:
    _recoil = -dir * strength


func vent() -> void:
    if absf(pressure) < VENT_MIN:
        say("Nothing to vent")
        return
    var hot := pressure > 0.0
    var strength := absf(pressure) * (1.0 + stat("vent_power"))
    var vent_radius := (110.0 + strength * 1.6) * (1.0 + stat("vent_radius"))
    _squash = 1.0
    var kind: int = Element.Kind.FIRE if hot else Element.Kind.ICE
    var col: Color = Element.COLORS[kind]
    Elements.nova.emit(global_position, vent_radius, Color(col, 0.55))
    Elements.reaction_fired.emit("Fire Nova" if hot else "Frost Nova", global_position, col)
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        if e.global_position.distance_to(global_position) > vent_radius:
            continue
        e.take_damage(strength * 0.35, col, true, self)
        if is_instance_valid(e) and not e.is_queued_for_deletion():
            e.apply_element(kind, strength * 0.3, self)
    # A vent sweeping through a cloud reacts with the whole cloud.
    for c in get_tree().get_nodes_in_group("clouds"):
        if is_instance_valid(c) and c.global_position.distance_to(global_position) <= vent_radius + c.radius:
            Elements.react_cloud(c, kind, strength * 0.3, self)
    pressure = 0.0
    Items.fire(self, "vent", { "pos": global_position, "element": kind })


# --- Health ----------------------------------------------------------------


func take_damage(amount: float, attacker: Node2D = null) -> void:
    if not alive or invuln > 0.0:
        return
    if randf() < stat("dodge"):
        say("Dodged")
        invuln = 0.25
        return
    amount = maxf(1.0, amount - stat("armor"))
    hp -= amount
    invuln = 0.6
    var tree_scene := get_tree().current_scene
    if tree_scene != null and "fx" in tree_scene and tree_scene.fx != null:
        tree_scene.fx.number(global_position + Vector2(0, -16), amount, Color(1.0, 0.35, 0.3), true)
    _squash = 1.0
    Sfx.play("hurt")
    var scene := get_tree().current_scene
    if scene != null and scene.has_method("shake"):
        scene.shake(5.0)
    var thorns := stat("thorns")
    if thorns > 0.0 and attacker != null and is_instance_valid(attacker) and attacker is Enemy:
        attacker.take_damage(thorns, Color.WHITE, true, self)
    Items.fire(self, "hurt", { "pos": global_position, "target": attacker })
    if hp <= 0.0:
        hp = 0.0
        alive = false
        remove_from_group("players")
        say("DOWN")
        Sfx.play("down")
        died.emit(self)
    queue_redraw()


func display_name() -> String:
    return Progress.player_name(index)


func say(text: String) -> void:
    last_message = text
    _message_time = 2.5


# --- Frame -----------------------------------------------------------------


func _physics_process(delta: float) -> void:
    input.poll()
    if not alive:
        return

    var mv := input.move_vector()
    velocity = mv * move_speed()
    move_and_slide()

    if input.just_pressed("vent"):
        vent()
    if input.take_pressed("active"):
        use_active()

    pressure = move_toward(pressure, 0.0, PRESSURE_DECAY * (1.0 + stat("pressure_decay")) * delta)
    invuln = maxf(0.0, invuln - delta)
    var regen := stat("regen")
    if regen > 0.0:
        heal(regen * delta)
    _message_time = maxf(0.0, _message_time - delta)
    if _message_time <= 0.0:
        last_message = ""

    var nearest := nearest_enemy(900.0)
    if nearest != null:
        aim_dir = (nearest.global_position - global_position).normalized()
    elif mv != Vector2.ZERO:
        aim_dir = mv.normalized()

    _fire()
    _animate(delta, mv)
    queue_redraw()


func _animate(delta: float, mv: Vector2) -> void:
    var moving := mv != Vector2.ZERO
    if moving:
        _anim_t += delta * 11.0
    var hop := absf(sin(_anim_t)) * 3.0 if moving else 0.0
    _squash = maxf(0.0, _squash - delta * 6.0)
    _recoil = _recoil.move_toward(Vector2.ZERO, 60.0 * delta)
    _sprite.scale = Vector2(_squash_scale * (1.0 + 0.3 * _squash), _squash_scale * (1.0 - 0.3 * _squash))
    _sprite.position = Vector2(0, -hop) + _recoil
    _sprite.rotation = sin(_anim_t) * 0.08 if moving else 0.0


## Every gun picks its own nearest target in range and fires.
func _fire() -> void:
    for g in guns:
        if not g.can_fire():
            continue
        var target := nearest_enemy(g.effective_range())
        if target == null:
            # Nothing to shoot: an obstacle in range gets the gun's element instead.
            target = nearest_obstacle(g.effective_range())
        if target == null:
            continue
        g.fire((target.global_position - g.global_position).normalized())


func nearest_obstacle(max_range: float) -> Node2D:
    var best: Node2D = null
    var best_d := max_range * max_range
    for ob in get_tree().get_nodes_in_group("obstacles"):
        if not is_instance_valid(ob) or ob.is_queued_for_deletion():
            continue
        var d: float = ob.global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = ob
    return best


func nearest_enemy(max_range: float, prefer_elite: bool = false) -> Node2D:
    var best: Node2D = null
    var best_d := max_range * max_range
    var best_elite: Node2D = null
    var best_elite_d := max_range * max_range
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        var d: float = e.global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = e
        if prefer_elite and e.is_elite and d < best_elite_d:
            best_elite_d = d
            best_elite = e
    return best_elite if best_elite != null else best


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    var body := color.lerp(Color.WHITE, 0.35)
    if not alive:
        _sprite.modulate = Color(0.35, 0.3, 0.3, 0.7)
        return
    if invuln > 0.0 and fmod(invuln, 0.2) < 0.1:
        body = Color(body, 0.35)
    _sprite.modulate = body
    if absf(aim_dir.x) > 0.05:
        _sprite.flip_h = aim_dir.x < 0.0
    draw_circle(Vector2(0, radius * 0.7), radius * 0.9, Color(0, 0, 0, 0.35))
    draw_string(Art.FONT, Vector2(-20, -radius - 8), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, color)
