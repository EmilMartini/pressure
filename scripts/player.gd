class_name Player
extends CharacterBody2D
## One player: movement, the carried arsenal (which aims and fires itself), gear,
## level-ups, pressure gauge, health. Guns orbit the figure and point where they shoot.

signal died(player: Player)
signal leveled_up(player: Player)
## Every hit that lands (after dodge, armour and invulnerability): `from` is where it came
## from in the world (INF: from everywhere, the floor), `source` the Telemetry label.
signal hurt(player: Player, amount: float, from: Vector2, source: String)

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
var _manual_dir := Vector2.RIGHT   # last movement direction, for manual fire with no aim input

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
var jewel_target := { "ring": "", "trinket": "" }   # swap pick at a pedestal (ring1 / ring2...)
var xp_total := 0.0               # all XP earned this run (bot pacing logs)
var boon_triggers: Array = []    # level-up boons that work like gear triggers (Items.fire)

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
var revives_left := 0             # Shrine's Last Breath charges left this run
var levelup_rerolls := 0          # Shrine's Second Thoughts rerolls left this run
var levelups_shown := 0           # level-up offers seen this run (Wider Choice alternates)
var _squash_scale := 2.0
var _costume: Node2D              # front costume layer, drawn over the body sprite
var _pool: Node2D = null          # additive light pool at the feet (see _make_pool)
var _crowd := 0.0                 # 0..1: enemies pressing round, shows the crisp feet ring
var _orbit_angle := 0.0
var _orbit_hits: Dictionary = {}  # enemy instance id -> msec when an orbital may hit it again
var _floor_t := 0.0               # next floor-material check
var _on_ice := false
var _wading := false               # deep water in a room layout slows us
var _leech_budget := LEECH_PER_SEC  # reactions that may still heal right now (refills per second)
var hurt_total := 0.0             # health lost this run (bots: per-arena [ARENA] lines)
var healed_total := 0.0           # health healed this run, by any source
var healed_leech := 0.0           # of which by Leech
var healed_regen := 0.0           # of which by regen
var burst_guards := 0             # times the burst guard fired this run (bots print it)
var _burst_ready_t := 0.0         # life_t from which the burst guard may fire again

## Danger readability. The last RECAP_SECS of hits ([time, amount, source]) and of health
## (one sample every TRACE_STEP s) for the death recap on the run-over screen; the red
## hit flash on the figure; the floor hazard we stand in (rim, feet ring, warning).
const RECAP_SECS := 30.0
const TRACE_STEP := 0.25
var life_t := 0.0                 # seconds alive this run (game time)
var hurt_log: Array = []          # [t, amount, source]
var hp_trace: Array = []          # [t, hp fraction]
var killed_by := ""               # source label of the blow that put us down
var _trace_t := 0.0
var _hurt_flash := 0.0
var _floor_hit := false           # take_damage runs for a floor tick (sizzle, not the punch)
var hazard_mat := 0               # Materials id of the hurting floor under us, 0 = none
var _hazard_t := 0.0              # seconds left on the hazard tint after stepping off

## Floor hazards: material -> [damage per tick, name, colour, element that makes it].
## Ticks land every 0.75 s at most (polled every 0.25 s, then 0.6 s of invulnerability).
## Halved while you carry the element that makes it (OWN_FLOOR_SCALE): the grid keeps no
## owner per cell, but charged water is only ever made by shock (your guns, a vent, a rare
## prop) and with a fire gun most fire on the floor is your own. Human telemetry of
## 2026-11-06 (22 runs): floor ticks were 1% of all damage taken, but the deciding damage
## of one death in three (a Stormcaller: 24 of the last 29 HP in 10 s from charged
## puddles of their own making).
const HAZARDS := {
    Materials.FIRE: [2.0, "Burning floor", Color(1.0, 0.5, 0.15), Element.Kind.FIRE],
    Materials.CHARGED: [4.0, "Charged floor", Color(0.55, 0.85, 1.0), Element.Kind.SHOCK],
}
const OWN_FLOOR_SCALE := 0.5
const HAZARD_TICK_SECS := 0.75

## Lifesteal heals its amount per reaction, but only LEECH_PER_SEC reactions a second count
## (a small bucket, so a burst can spend it at once). A six-element build causes 40 to 80
## reactions a second late in a run (telemetry, run 4487a37a), which made any lifesteal a
## full heal every second: 10 to 20 times the damage the floor dealt. Capped, Leech is a
## strong sustain (3 HP/s per point) that a hard moment can still outpace.
const LEECH_PER_SEC := 3.0

## Burst guard (floors 2+, not with --old-balance): losing BURST_FRACTION of max health
## within BURST_WINDOW seconds buys BURST_INVULN seconds untouchable ("Steady"), at most
## once per BURST_COOLDOWN. A crowd still kills, but not from 60% health in under 5 s:
## human run ce704d42 lost 66 HP in 4.8 s on floor 2's first arena (bomber 23, grunts 13,
## 13, 13, swarmer 8) with nothing to read or answer between the hits, and a pinned bot
## took a hit every 0.6 s (the hit invulnerability) for 88 HP in 5.8 s. At 0.3 in 2.5 s
## that bot never tripped it (47 of 49 HP); 0.25 in 3 s catches both. It only fires once
## the burst has left you under BURST_BELOW of max health: on floors 3+ a build that heals
## as fast as it bleeds tripped it every 6 s at high health (a hidden 25% damage cut).
const BURST_FRACTION := 0.25
const BURST_BELOW := 0.5
const BURST_WINDOW := 3.0
const BURST_INVULN := 1.5
const BURST_COOLDOWN := 6.0

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
    z_index = 22   # above the particle layers (Fx 20, additive 21): your own effects never hide you
    var tiles: Array = Art.TILES["player"]
    _sprite = Art.sprite(tiles[index % tiles.size()], 2.0, Color.WHITE)
    _sprite.texture = Items.form_for(self)["texture"]
    add_child(_sprite)
    _costume = Node2D.new()
    _costume.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _costume.draw.connect(_draw_costume)
    add_child(_costume)
    _mastery = get_node_or_null("/root/Mastery")
    if _mastery != null:
        revives_left = int(_mastery.revives())
        levelup_rerolls = int(_mastery.bonus("levelup_rerolls"))


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
    if merge_target(data.id) != null:
        return true   # a copy merges into the gun already carried: no slot, no extra weight
    return guns.size() < gun_slots() and total_weight() + data.weight <= weight_capacity


## The carried copy of this gun that a picked-up duplicate merges into: the lowest tier
## one that can still rise. Null when the gun is not carried or every copy is at max tier.
func merge_target(id: String) -> Gun:
    var best: Gun = null
    for g in guns:
        if g.data.id == id and g.tier < Gun.MAX_TIER and (best == null or g.tier < best.tier):
            best = g
    return best


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


## Pick up a gun. A copy of a gun already carried merges into it: that gun rises one tier
## (no slot or weight needed). Only when every copy is at max tier does it take a new slot.
## `allow_merge` false is for bot build replays that set tiers themselves.
func add_gun(id: String, allow_merge := true) -> bool:
    var data := Guns.make(id)
    var into := merge_target(id) if allow_merge else null
    if into != null:
        into.tier += 1
        _layout_guns()
        recalc_stats()
        Telemetry.combine(into.data.id, into.tier)
        say("Merged: %s" % into.display_name())
        Sfx.play("unlock")
        return true
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
    Sfx.pickup("pickup_gun", self)
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
## Which ring or trinket slot a new piece of `slot` ("ring" / "trinket") replaces when both
## are full: the one the player picked at the pedestal (swap button), else the weaker piece
## (lower rarity, then the cheaper one). Empty when a slot of the pair is free.
func jewel_key(slot: String) -> String:
    if not (slot in ["ring", "trinket"]) or not equipment.has(slot + "1") or not equipment.has(slot + "2"):
        return ""
    var chosen := String(jewel_target.get(slot, ""))
    if chosen != "":
        return chosen
    var a := Items.get_item(String(equipment[slot + "1"]))
    var b := Items.get_item(String(equipment[slot + "2"]))
    var ra := int(a.get("rarity", 0))
    var rb := int(b.get("rarity", 0))
    if rb < ra or (rb == ra and Items.price(b, 0) < Items.price(a, 0)):
        return slot + "2"
    return slot + "1"


## The other piece of a full pair (the one that stays), or "".
func jewel_kept(slot: String) -> String:
    var k := jewel_key(slot)
    if k == "":
        return ""
    return slot + ("2" if k.ends_with("1") else "1")


## Swap button at a pedestal: replace the other ring / trinket instead.
func cycle_jewel(slot: String) -> void:
    var k := jewel_kept(slot)
    if k != "":
        jewel_target[slot] = k


## Equip an item. `key` picks the slot for rings and trinkets ("ring2"); empty means a free
## one, else jewel_key (the player's pick at the pedestal, or the weaker piece).
func equip(id: String, key_hint: String = "") -> String:
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
            if key_hint.begins_with(slot) and key_hint in [slot + "1", slot + "2"]:
                key = key_hint
            elif not equipment.has(slot + "1"):
                key = slot + "1"
            elif not equipment.has(slot + "2"):
                key = slot + "2"
            else:
                key = jewel_key(slot)
            jewel_target[slot] = ""   # the next pedestal starts from the default again
        old = equipment.get(key, "")
        equipment[key] = id
        Telemetry.equip(id, key, old)
        if slot == "active":
            active_charges = Items.active_max_charges(self)
        say("Equipped %s" % item["name"])
        Sfx.item_pickup(int(item.get("rarity", 0)), self)
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


## Summed modifier for a key: gear, set bonuses, level-ups, Shrine talents (their
## conditional ones too), and conditional gear modifiers that currently hold.
func stat(key: String) -> float:
    var v := float(_stats.get(key, 0.0)) + float(bonus_stats.get(key, 0.0))
    if _mastery != null:
        v += _mastery.bonus(key) + _mastery.cond_bonus(key, self)
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
    return XP_BASE * (pow(n + 1.0, XP_EXP) - pow(n, XP_EXP))


## Total XP to reach level `lv` from level 1 is XP_BASE * (lv - 1) ^ XP_EXP. Fitted to the
## XP a run actually earns per arena wave (human run 4487a37a46b6c384 and bots: about 80 in
## the first wave, 1,700 to 2,200 by the end of floor 1, 11k to 14k by arena 12, 43k by
## arena 20, kills grow with the floor), so a level comes about once a wave from the first
## room to the last. The old curve (20 + 15n + 3n^2 per level) gave 2 to 5 levels in the
## first wave and then one every 60 to 130 s on floor 5.
const XP_BASE := 55.0
const XP_EXP := 2.25


func gain_xp(amount: float) -> void:
    if not alive:
        return
    xp += amount * (1.0 + stat("xp_gain"))
    xp_total += amount * (1.0 + stat("xp_gain"))
    while xp >= xp_to_next():
        xp -= xp_to_next()
        level += 1
        say("Level %d" % level)
        Sfx.play("level_up")
        leveled_up.emit(self)


## Called by the level-up screen with an option from LevelUps.
func apply_upgrade(opt: Dictionary) -> void:
    # Main stat, a second stat ("also") and a drawback ("cost"), all into bonus_stats.
    var ch: Dictionary = LevelUps.changes(opt)
    for key in ch.keys():
        bonus_stats[key] = float(bonus_stats.get(key, 0.0)) + float(ch[key])
    if opt.has("echo"):
        boon_triggers.append(LevelUps.echo_trigger(opt))
    recalc_stats()
    say(opt.get("name", "Upgrade"))


func pressure_limit() -> float:
    return PRESSURE_LIMIT + pressure_limit_bonus + stat("pressure_limit")


func move_speed() -> float:
    return BASE_SPEED * (1.0 + stat("speed")) * maxf(0.4, 1.0 - SPEED_LOSS_PER_WEIGHT * total_weight())


func heal(amount: float) -> void:
    if alive:
        var before := hp
        hp = minf(max_hp, hp + amount)
        healed_total += hp - before


## Called by enemies when a reaction this player caused fires.
func on_reaction(_reaction_name: String) -> void:
    var steal := stat("lifesteal")
    if steal > 0.0 and (_leech_budget >= 1.0 or Main.old_balance):
        _leech_budget -= 1.0
        var h0 := healed_total
        heal(steal)
        healed_leech += healed_total - h0


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


func take_damage(amount: float, attacker: Node2D = null, from: Vector2 = Vector2.INF) -> void:
    # Who did it, read first: the hint a shot or a prop left must never outlive this call.
    var source := Telemetry.hurt_source(self, attacker)
    if not alive or invuln > 0.0:
        return
    if randf() < stat("dodge"):
        say("Dodged")
        invuln = 0.25
        return
    amount = maxf(1.0, amount - stat("armor"))
    hurt_total += minf(amount, maxf(0.0, hp))
    hp -= amount
    Telemetry.player_hurt(self, amount, attacker, source)
    _log_hurt(amount, source)
    invuln = 0.6
    _burst_guard()
    _hurt_flash = 0.14
    if from == Vector2.INF and attacker != null and is_instance_valid(attacker):
        from = attacker.global_position
    var tree_scene := get_tree().current_scene
    if tree_scene != null and "fx" in tree_scene and tree_scene.fx != null:
        tree_scene.fx.hurt_number(global_position + Vector2(0, -16), amount)
    _squash = 1.0
    if not _floor_hit:
        Sfx.play("hurt")
        Sfx.play("hurt_low")
    var scene := get_tree().current_scene
    if scene != null and scene.has_method("shake"):
        scene.shake(5.0)
    hurt.emit(self, amount, from, source)
    var thorns := stat("thorns")
    if thorns > 0.0 and attacker != null and is_instance_valid(attacker) and attacker is Enemy:
        attacker.take_damage(thorns, Color.WHITE, true, self)
    Items.fire(self, "hurt", { "pos": global_position, "target": attacker })
    if hp <= 0.0 and revives_left > 0:
        _last_breath()
    elif hp <= 0.0:
        hp = 0.0
        alive = false
        killed_by = source
        remove_from_group("players")
        say("DOWN")
        Sfx.play("down")
        died.emit(self)
    queue_redraw()


func _burst_guard() -> void:
    if hp <= 0.0 or hp > BURST_BELOW * max_hp or life_t < _burst_ready_t or Main.old_balance:
        return
    var mn := main()
    if mn == null or mn.floor_number < 2:
        return
    var recent := 0.0
    for h in hurt_log:
        if life_t - float(h[0]) <= BURST_WINDOW:
            recent += float(h[1])
    if recent < BURST_FRACTION * max_hp:
        return
    invuln = BURST_INVULN
    _burst_ready_t = life_t + BURST_COOLDOWN
    burst_guards += 1
    say("Steady")


func _log_hurt(amount: float, source: String) -> void:
    hurt_log.append([life_t, amount, source])
    while not hurt_log.is_empty() and life_t - float(hurt_log[0][0]) > RECAP_SECS:
        hurt_log.pop_front()


## Health once every TRACE_STEP s for the last RECAP_SECS (the death recap's line).
func _trace_hp(delta: float) -> void:
    life_t += delta
    _trace_t -= delta
    if _trace_t > 0.0:
        return
    _trace_t = TRACE_STEP
    hp_trace.append([life_t, clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)])
    while hp_trace.size() > int(RECAP_SECS / TRACE_STEP) + 1:
        hp_trace.pop_front()


## The Shrine's survival track: stand back up at a quarter of max HP, briefly untouchable.
func _last_breath() -> void:
    revives_left -= 1
    hp = maxf(1.0, max_hp * Mastery.REVIVE_FRACTION)
    invuln = Mastery.REVIVE_INVULN
    _squash = 1.0
    say("Last Breath" if revives_left <= 0 else "Last Breath (%d left)" % revives_left)
    Sfx.play("revive")
    var scene := get_tree().current_scene
    if scene != null and scene.has_method("flash"):
        scene.flash(Color(1.0, 0.6, 0.25), 0.45, 0.5)
    Telemetry.event("revive", { "player": index, "left": revives_left, "hp": snappedf(hp, 0.1) })


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
    _trace_hp(delta)
    _hurt_flash = maxf(0.0, _hurt_flash - delta)
    _hazard_t = maxf(0.0, _hazard_t - delta)

    _floor_t -= delta
    if _floor_t <= 0.0:
        _floor_t = 0.25
        _feel_floor()
        if not alive:
            return
    var mv := input.move_vector()
    if mv.length() > 0.2:
        _manual_dir = mv.normalized()
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
        var h1 := healed_total
        heal(regen * delta)
        healed_regen += healed_total - h1
    _leech_budget = minf(LEECH_PER_SEC, _leech_budget + LEECH_PER_SEC * delta)
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
## A hurting floor tints the rim and the feet ring in its colour, hisses on each tick and,
## the first time each kind is stood in during a run, names itself over the player.
func _feel_floor() -> void:
    _on_ice = false
    var rm := Room.here
    _wading = rm != null and is_instance_valid(rm) and rm.is_deep(global_position)
    var mats := Materials.find(self)
    if mats == null:
        hazard_mat = 0
        return
    var m := mats.material_at(global_position)
    if m == Materials.ICE:
        _on_ice = true
    if not HAZARDS.has(m):
        hazard_mat = 0
        return
    hazard_mat = m
    _hazard_t = 0.6
    var dmg := hazard_damage(m)
    _warn_hazard(m, dmg)
    if invuln > 0.0:
        return
    var before := hp
    _floor_hit = true
    take_damage(dmg, null, Vector2.INF)
    _floor_hit = false
    if hp < before:
        Sfx.play("sizzle_shock" if m == Materials.CHARGED else "sizzle_fire")
        Sfx.play("hurt", -8.0)


## Damage per tick of a hurting floor for this player (see HAZARDS).
func hazard_damage(m: int) -> float:
    var h: Array = HAZARDS[m]
    var dmg := float(h[0])
    if Main.old_balance:
        return dmg
    if int(h[3]) in element_kinds():
        dmg *= OWN_FLOOR_SCALE
    return dmg


## Once per run and kind: the floor's name and its bite over the player, and a toast.
func _warn_hazard(m: int, dmg: float) -> void:
    var mn := main()
    if mn == null:
        return
    var seen: Dictionary = mn.get_meta("hazards_warned", {})
    if seen.has(m):
        return
    seen[m] = true
    mn.set_meta("hazards_warned", seen)
    var h: Array = HAZARDS[m]
    var per_sec := maxf(1.0, dmg - stat("armor")) / HAZARD_TICK_SECS
    var text := "%s: %d/s" % [String(h[1]), maxi(1, roundi(per_sec))]
    if mn.fx != null:
        mn.fx.label(global_position + Vector2(0, -60), text, h[2], 26, 2.4)
    if mn.hud != null:
        var own := ""
        if dmg < float(h[0]):
            own = " (your own %s: half damage)" % ("shock" if m == Materials.CHARGED else "fire")
        mn.hud.toast("%s: %d damage a second. Step off it%s" % [String(h[1]), maxi(1, roundi(per_sec)), own])


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
    # Holding RT (or the left mouse button) fires every gun where you aim: right stick,
    # mouse cursor, or the way you face. Otherwise guns auto-fire at enemies only, never
    # at obstacles, props, secret walls or puzzle pieces: those you find and shoot yourself.
    var manual := alive and input.fire_held()
    var aim := Vector2.ZERO
    if manual:
        aim = input.aim_vector(global_position, get_viewport())
        if aim == Vector2.ZERO:
            aim = _manual_dir
    for g in guns:
        if not g.can_fire():
            continue
        if manual:
            g.fire(aim)
            continue
        var target := nearest_enemy(g.effective_range())
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
    for e in EnemyGrid.nodes(get_tree(), &"enemies"):   # cached: each gun asks every tick
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
    # One figure pixel per PostFx cell, like the room tiles (Themes.texel): at 2 world px a
    # 16 px figure covered about 14 cells and the pixel grid dropped rows of it (worn hats
    # and boots included). Used by the squash in _process. Stays 2 with post-processing
    # off, when cells are smaller (pixel size 2: nothing is dropped, the figure never
    # shrinks) or much larger (the hub's zoom, pixel size 4: it never grows by over a
    # quarter).
    var cam := get_viewport().get_camera_2d()
    var cell := Themes.texel(cam.zoom.x) if cam != null and Settings.flag("post_fx") else 2.0
    _squash_scale = cell if cell >= 2.0 and cell <= 2.5 else 2.0
    # A touch brighter than white: the player outshines the enemies' tinted sprites.
    var body := Color(1.1, 1.1, 1.1)
    var glow: Color = form["color"]
    if _pool == null:
        _make_pool.call_deferred()   # not while drawing
    else:
        _pool.visible = alive
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
    if _hurt_flash > 0.0:
        # Hit: the figure flashes hot red-white for a beat (overbright, so it blooms).
        body = Color(2.4, 0.55, 0.5)
    elif invuln > 0.0 and fmod(invuln, 0.2) < 0.1:
        body = Color(body, 0.35)
    _sprite.modulate = body
    if absf(aim_dir.x) > 0.05:
        _sprite.flip_h = aim_dir.x < 0.0
    draw_circle(Vector2(0, radius * 0.7), radius * 0.9, Color(0, 0, 0, 0.35))
    # A faint ring in the player's colour round the feet (over the light pool, see
    # _make_pool): where you stand reads at a glance, and in co-op whose figure is whose.
    var ring := PackedVector2Array()
    for s in 25:
        var a := TAU * float(s) / 24.0
        ring.append(Vector2(cos(a) * 15.0, radius * 0.8 + sin(a) * 6.5))
    draw_polyline(ring, Color(color, 0.5 * body.a), 2.4)
    # Back layer (form and item auras, ring sparkles, the active item) under the body.
    Items.draw_costume(self, self, _sprite.position, 2.0, _facing(), false)
    # A 1 px rim in the player's colour just outside the figure's dark outline
    # (FigureGen.rim), drawn under the body sprite with its exact transform. A deeper shade
    # of the colour: at full brightness the PostFx bloom flooded the small figure with it
    # and washed out the worn gear.
    var rim := FigureGen.rim(frames[fi])
    if rim != null:
        var sx := _sprite.scale.x * (-1.0 if _sprite.flip_h else 1.0)
        draw_set_transform(_sprite.position, _sprite.rotation, Vector2(sx, _sprite.scale.y))
        draw_texture(rim, -rim.get_size() / 2.0, Color(_rim_color(), 0.92 * body.a))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The rim's colour: the player's own, or the hurting floor's, pulsing toward white while
## we stand in it (and a moment after stepping off).
func _rim_color() -> Color:
    var base := color.darkened(0.3)
    if _hazard_t <= 0.0 or not HAZARDS.has(hazard_mat):
        return base
    var hc: Color = HAZARDS[hazard_mat][2]
    var beat := 0.5 + 0.5 * sin(life_t * 14.0)
    return hc.lerp(Color(1, 1, 1), 0.45 * beat).lerp(base, 1.0 - clampf(_hazard_t / 0.3, 0.0, 1.0))


## The light pool under the player: a soft additive glow in the player's colour on the
## floor, behind everything the player draws. Made on the first draw.
func _make_pool() -> void:
    if _pool != null:
        return
    _pool = Node2D.new()
    _pool.name = "LightPool"
    _pool.show_behind_parent = true
    var m := CanvasItemMaterial.new()
    m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    _pool.material = m
    _pool.position = Vector2(0, radius * 0.8)
    _pool.draw.connect(func() -> void:
        _pool.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
        _pool.draw_texture_rect(Art.PARTICLES["light"], Rect2(-44, -44, 88, 88), false, Color(color, 0.36))
        _pool.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
    add_child(_pool)


## The player number over the head, sharp above the pixel grid (Crisp layer).
## When enemies press round (three or more touching distance), a thin ring at the feet
## fades in on the crisp layer too, above particles and the pixel grid, so the player is
## never lost in a crowd.
func _draw_crisp(cv: CanvasItem) -> void:
    cv.draw_string(Art.FONT, Vector2(-19, -radius - 7), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(0, 0, 0, 0.7))
    cv.draw_string(Art.FONT, Vector2(-20, -radius - 8), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, color)
    var near := 0
    if alive and is_inside_tree():
        for e in get_tree().get_nodes_in_group("enemies"):
            var en := e as Node2D
            if en != null and en.global_position.distance_squared_to(global_position) < 46.0 * 46.0:
                near += 1
                if near >= 3:
                    break
    _crowd = move_toward(_crowd, 1.0 if near >= 3 else 0.0, 0.08)
    # Standing in a hurting floor: the feet ring in its colour, pulsing, thick.
    if alive and _hazard_t > 0.0 and HAZARDS.has(hazard_mat):
        var hc: Color = HAZARDS[hazard_mat][2]
        var beat := 0.5 + 0.5 * sin(life_t * 14.0)
        var k := clampf(_hazard_t / 0.3, 0.0, 1.0)
        var hz := PackedVector2Array()
        for s in 25:
            var a := TAU * float(s) / 24.0
            hz.append(Vector2(cos(a) * (19.0 + 2.0 * beat), radius * 0.8 + sin(a) * (8.5 + beat)))
        cv.draw_polyline(hz, Color(0, 0, 0, 0.6 * k), 4.5)
        cv.draw_polyline(hz, Color(hc.lerp(Color.WHITE, 0.4 * beat), k), 2.5)
    if _crowd > 0.01:
        var pts := PackedVector2Array()
        for s in 25:
            var a := TAU * float(s) / 24.0
            pts.append(Vector2(cos(a) * 17.0, radius * 0.8 + sin(a) * 7.5))
        cv.draw_polyline(pts, Color(0, 0, 0, 0.5 * _crowd), 3.0)
        cv.draw_polyline(pts, Color(color.lightened(0.2), 0.85 * _crowd), 1.5)


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
