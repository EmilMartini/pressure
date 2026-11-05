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
var _costume: Node2D              # front costume layer, drawn over the body sprite
var _orbit_angle := 0.0
var _orbit_hits: Dictionary = {}  # enemy instance id -> msec when an orbital may hit it again
var _floor_t := 0.0               # next floor-material check
var _on_ice := false
var _wading := false               # deep water in a room layout slows us

const ORBIT_RADIUS := 60.0
const ORBIT_HIT := 10.0
const ORBITAL_TILE := Vector2i(34, 12)


func _init(p_index: int, p_input: PlayerInput) -> void:
    index = p_index
    input = p_input
    color = PLAYER_COLORS[p_index % PLAYER_COLORS.size()]
    name = "Player%d" % (p_index + 1)


func _ready() -> void:
    add_to_group("players")
    Crisp.attach(self, _draw_crisp)
    collision_layer = LAYER_PLAYERS
    collision_mask = LAYER_WALLS
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    add_child(shape)
    z_index = 10
    var tiles: Array = Art.TILES["player"]
    _sprite = Art.sprite(tiles[index % tiles.size()], 2.0, Color.WHITE)
    _sprite.texture = Items.form_for(self)["texture"]
    add_child(_sprite)
    _costume = Node2D.new()
    _costume.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _costume.draw.connect(_draw_costume)
    add_child(_costume)
    _mastery = get_node_or_null("/root/Mastery")


func main() -> Main:
    return get_tree().current_scene as Main


# --- Arsenal ---------------------------------------------------------------


func total_weight() -> int:
    var w := 0
    for g in guns:
        w += g.data.weight
    return w


## Six gun slots like Brotato (items may add one or two), and the weight budget on top.
const MAX_GUNS := 6


func gun_slots() -> int:
    return MAX_GUNS + int(stat("gun_slots"))


func can_carry(data: GunData) -> bool:
    return guns.size() < gun_slots() and total_weight() + data.weight <= weight_capacity


## Merge two copies of the same gun at the same tier into one a tier higher (Brotato's
## combine). Returns the surviving gun, or null when the pair does not match.
func combine(a: Gun, b: Gun) -> Gun:
    if a == null or b == null or a == b or a.data.id != b.data.id or a.tier != b.tier or a.tier >= Gun.MAX_TIER:
        return null
    a.tier += 1
    for m in b.mods:
        if a.mods.size() < a.tier:
            a.mods.append(m)
    guns.erase(b)
    b.queue_free()
    _layout_guns()
    recalc_stats()
    Telemetry.combine(a.data.id, a.tier)
    say("%s" % a.display_name())
    Sfx.play("unlock")
    return a


## Pairs of guns that `combine` would accept, for the sheet's Combine action.
func combinable_pairs() -> Array:
    var out: Array = []
    for i in guns.size():
        for j in range(i + 1, guns.size()):
            if guns[i].data.id == guns[j].data.id and guns[i].tier == guns[j].tier and guns[i].tier < Gun.MAX_TIER:
                out.append([guns[i], guns[j]])
    return out


## Pick up a gun. Duplicates are allowed (three oil slingers is a build); combining two
## of the same into a higher tier is a deliberate action in the character sheet.
func add_gun(id: String) -> bool:
    var data := Guns.make(id)
    if guns.size() >= gun_slots():
        say("All %d gun slots full: drop or combine" % gun_slots())
        return false
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
    Telemetry.drop_gun(id)
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
    Telemetry.equip(id, "mod:" + gun.data.id, "")
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
        Telemetry.equip(id, key, old)
        if slot == "active":
            active_charges = Items.active_max_charges(self)
        say("Equipped %s" % item["name"])
    recalc_stats()
    return old


## Use the active item (Isaac's spacebar item). False when empty or out of charges.
func use_active() -> bool:
    var used: bool = Items.use_active(self)
    if used:
        Telemetry.active_use(String(equipment.get("active", "")))
    return used


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
    # The gauge is the vent's charge: vent_charge makes every shot fill it faster.
    pressure = clampf(pressure + amount * (1.0 + stat("vent_charge")), -limit, limit)


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
    Telemetry.vent(kind, pressure)
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
    var mats := Materials.find(self)
    if mats != null:
        mats.stamp(kind, global_position, vent_radius, 160)
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
    Telemetry.player_hurt(self, amount, attacker)
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

    _floor_t -= delta
    if _floor_t <= 0.0:
        _floor_t = 0.25
        _feel_floor()
        if not alive:
            return
    var mv := input.move_vector()
    var want := mv * move_speed() * (Room.WADE if _wading else 1.0)
    if _on_ice:
        var keep := pow(Materials.ICE_KEEP, delta * 60.0)
        velocity = velocity * keep + want * (1.0 - keep)
    else:
        velocity = want
    move_and_slide()

    if input.just_pressed("vent"):
        vent()
    if input.take_pressed("active"):
        use_active()

    pressure = move_toward(pressure, 0.0, PRESSURE_DECAY * delta)
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
    _update_orbitals(delta)
    _animate(delta, mv)
    queue_redraw()
    _costume.queue_redraw()


## What the floor does to us: fire and charged water hurt (invuln still applies), ice slides.
func _feel_floor() -> void:
    _on_ice = false
    var rm := Room.here
    _wading = rm != null and is_instance_valid(rm) and rm.is_deep(global_position)
    var mats := Materials.find(self)
    if mats == null:
        return
    match mats.material_at(global_position):
        Materials.FIRE:
            take_damage(2.0, null)
        Materials.CHARGED:
            take_damage(4.0, null)
        Materials.ICE:
            _on_ice = true


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
        if ob is Prop:
            continue   # props are for deliberate shots and reactions, not idle auto-fire
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
    var rm := Room.here
    var walls := rm != null and is_instance_valid(rm) and rm.has_walls
    var near: Array = []
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or e.emerge > 0.0:
            continue
        var d: float = e.global_position.distance_squared_to(global_position)
        if walls and d < max_range * max_range:
            near.append([d, e])
        if d < best_d:
            best_d = d
            best = e
        if prefer_elite and e.is_elite and d < best_elite_d:
            best_elite_d = d
            best_elite = e
    if walls and not near.is_empty():
        # Interior walls stop shots: aim at the nearest enemy in sight, if one of the
        # closest few is; else the nearest anyway (it may step out).
        if best_elite != null and rm.line_clear(global_position, best_elite.global_position):
            return best_elite
        if best != null and rm.line_clear(global_position, best.global_position):
            return best
        var taken := {}
        for tries in mini(6, near.size()):
            var pick := -1
            var pick_d := INF
            for k in near.size():
                if not taken.has(k) and float(near[k][0]) < pick_d:
                    pick_d = float(near[k][0])
                    pick = k
            taken[pick] = true
            var cand: Node2D = near[pick][1]
            if cand != best and rm.line_clear(global_position, cand.global_position):
                return cand
    return best_elite if best_elite != null else best


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    # The body sprite is the figure generated from the class and gear (FigureGen): idle
    # and step frames, alternating while moving. It is already coloured, so modulate white.
    var form: Dictionary = Items.form_for(self)
    var frames: Array = form["frames"]
    var fi := 0
    if frames.size() > 1 and velocity.length() > 20.0:
        fi = int(floorf(_anim_t / PI)) % 2
    _sprite.texture = frames[fi]
    var body := Color.WHITE
    var glow: Color = form["color"]
    if not alive:
        _sprite.modulate = Color(0.35, 0.3, 0.3, 0.7)
        return
    # A changed figure pops in: a squash and a flash of its colour.
    var fid := String(form["id"])
    var now := float(Time.get_ticks_msec()) / 1000.0
    if String(get_meta("form_id", fid)) != fid:
        set_meta("form_t", now)
        _squash = 1.0
    set_meta("form_id", fid)
    var since := now - float(get_meta("form_t", -10.0))
    if since < 0.5:
        var k := 1.0 - since / 0.5
        draw_texture_rect(Art.PARTICLES["light"], Rect2(_sprite.position - Vector2(60, 60), Vector2(120, 120)), false, Color(glow, 0.7 * k))
        draw_arc(_sprite.position, 18.0 + 30.0 * (1.0 - k), 0.0, TAU, 24, Color(glow, k), 2.0)
    if invuln > 0.0 and fmod(invuln, 0.2) < 0.1:
        body = Color(body, 0.35)
    _sprite.modulate = body
    if absf(aim_dir.x) > 0.05:
        _sprite.flip_h = aim_dir.x < 0.0
    draw_circle(Vector2(0, radius * 0.7), radius * 0.9, Color(0, 0, 0, 0.35))
    # Back layer (form and item auras, ring sparkles, the active item) under the body.
    Items.draw_costume(self, self, _sprite.position, 2.0, _facing(), false)


## The player number over the head, sharp above the pixel grid (Crisp layer).
func _draw_crisp(cv: CanvasItem) -> void:
    cv.draw_string(Art.FONT, Vector2(-20, -radius - 8), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, color)


func _facing() -> float:
    return -1.0 if _sprite.flip_h else 1.0


## Front layer (a hat on a bare-headed form) and the orbitals.
func _draw_costume() -> void:
    if not alive:
        return
    Items.draw_costume(_costume, self, _sprite.position, 2.0, _facing(), true)
    var n := int(stat("orbitals"))
    if n <= 0:
        return
    var col: Color = Element.COLORS[orbital_element()].lerp(Color.WHITE, 0.3)
    var tex: Texture2D = Art.tile(ORBITAL_TILE)
    for i in n:
        var at := orbital_offset(i, n)
        _costume.draw_circle(at, 7.0, Color(col, 0.25))
        _costume.draw_texture_rect(tex, Rect2(at - Vector2(8, 8), Vector2(16, 16)), false, col)


# --- Orbitals (familiars) ---------------------------------------------------


func orbital_offset(i: int, n: int) -> Vector2:
    return Vector2(ORBIT_RADIUS, 0).rotated(_orbit_angle + TAU * float(i) / float(maxi(1, n)))


## The first gun's element, or none.
func orbital_element() -> int:
    if guns.is_empty():
        return Element.Kind.NONE
    return guns[0].data.element


## Half the average gun damage (tier and damage bonuses included).
func orbital_damage() -> float:
    if guns.is_empty():
        return 3.0
    var total := 0.0
    for g in guns:
        total += g.data.damage * g.tier_mult()
    return total / float(guns.size()) * maxf(0.1, 1.0 + stat("dmg")) * 0.5


func _update_orbitals(delta: float) -> void:
    var n := int(stat("orbitals"))
    if n <= 0:
        return
    _orbit_angle = wrapf(_orbit_angle + delta * 2.4, 0.0, TAU)
    var now := Time.get_ticks_msec()
    var dmg := orbital_damage()
    var kind := orbital_element()
    var col: Color = Element.COLORS[kind]
    var carry_element := stat("orbital_element") > 0.0 and kind != Element.Kind.NONE
    for i in n:
        var at := global_position + orbital_offset(i, n)
        for e in get_tree().get_nodes_in_group("enemies"):
            if not is_instance_valid(e) or e.is_queued_for_deletion() or not e is Enemy:
                continue
            if e.global_position.distance_to(at) > ORBIT_HIT + e.radius:
                continue
            var eid: int = e.get_instance_id()
            if int(_orbit_hits.get(eid, 0)) > now:
                continue
            _orbit_hits[eid] = now + 500
            e.take_damage(dmg, col, true, self)
            if carry_element and is_instance_valid(e) and not e.is_queued_for_deletion():
                e.apply_element(kind, dmg, self)
    if _orbit_hits.size() > 64:
        for k in _orbit_hits.keys():
            if int(_orbit_hits[k]) <= now:
                _orbit_hits.erase(k)
