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

## Aim modes (design doc section 7): "assisted" (default) fires where you aim with a soft lock,
## falling back to auto-fire after AIM_HOLD s without aim input; "manual" fires only while you
## hold (or toggle) fire; "auto" is the old behaviour, nearest enemy with RT to override.
const AIM_MODES := ["assisted", "manual", "auto"]
const AIM_HOLD := 1.2            # s after the last aim input before assisted falls back to auto
const SOFT_LOCK_DEG := 12.0      # half-angle of the soft-lock cone
static var aim_mode_override := ""   # bots: --aim=MODE (never saved)
var _aim_now := Vector2.ZERO     # this frame's aimed direction, ZERO = auto / no fire
var _aim_firing := false         # this frame the guns fire where aimed (else auto or none)
var _fire_toggled := false       # manual mode with toggle fire: constant fire is on
var _fire_was_held := false
var aim_secs := 0.0              # telemetry: seconds firing where aimed
var auto_secs := 0.0             # and seconds auto-firing with something in reach

var weight_capacity_base := 10
var weight_capacity := 10
var guns: Array[Gun] = []

## Core loop reset 3.1: no gear slots. `inventory` holds every passive as id -> copies;
## `equipment` holds only the one active item ("active" -> id). Gun mods live on the guns.
var inventory: Dictionary = {}
var equipment: Dictionary = {}
var synergies: Array = []          # synergy ids formed (Items.SYNERGIES), in the order formed
var resonance_tiers: Dictionary = {}   # tag -> 1 (3 items) or 2 (5 items)
var _buffs: Array = []             # timed stat buffs: [key, amount, until life_t]
var _cond_ids: Array = []          # owned items with conditional mods (stat() reads only these)
var mirror_left := 0               # Mirror Hide: hits this room that still bounce back
var guard_left := 0                # Guard resonance: the first hit this room is halved
var ward_t := 0.0                  # Ward Vent: seconds the ring still stops enemy shots
var _dash_hit: Dictionary = {}     # Shoulder Charge: enemies already hit this dash
var active_charges := 0           # charges on the active item (equipment["active"])
var _stats: Dictionary = {}

## Level-ups: xp from kills, upgrades picked on the level-up screen.
var xp := 0.0
var level := 1
var bonus_stats: Dictionary = {}
var xp_total := 0.0               # all XP earned this run (bot pacing logs)
var boon_triggers: Array = []    # level-up boons that work like gear triggers (Items.fire)

var aimed: Node2D = null        # the enemy the guns are on (Enemy shows its badges for it)
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
## Hit feel (Vision gap analysis 6.1): the figure stretches along a dash and squashes when it
## lands; a puff of dust at each footstep. Visual only.
var _stretch := 0.0
var _step := 0
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

## Mending (difficulty pass, 2026-11-09): passive healing (Leech, regen, on-kill and on-hurt
## item triggers, fusion heals) fades within one fight. Its rate is 1 / (1 + used / MEND_SOFT)
## of normal, where `used` is the share of max health it has already restored since the fight
## began: a quarter heals at full rate, the next quarter at about half. A storm build healed
## exactly what it took on floors 2 to 5 (0.5 to 1.45 max health a fight minute, Leech 70% of
## it) and never went under half health; fading keeps small sustain whole and cuts a stack.
## Chosen heals stay whole: actives, pickups, altars, shrines, the stairs, repairs, revives.
## Core loop reset, section 10 (2026-11-10): the fade is replaced by a visible Mending
## reserve per floor. Each floor starts with MEND_RESERVE of max health (+MEND_PER_BANDAGE per
## Bandage Roll worn); every passive heal (MEND_SOURCES, the perfect-dodge heal too) draws on
## it, and when it is empty passive healing stops until the next floor. The HUD shows it as a
## thin green bar under the health bar. Chosen heals (hearts, repairs, actives, revives) stay
## outside it. --old-balance keeps passive healing whole.
const MEND_RESERVE := 0.40
const MEND_PER_BANDAGE := 0.10
const MEND_SOURCES := ["leech", "regen", "item", "fusion", "dodge"]
var mend_left := 0.0          # Mending reserve left this floor, in HP
var mend_max := 0.0           # this floor's reserve at its start, in HP
var mend_used := 0.0          # drawn from the reserve this floor, in HP (telemetry)

## Leech only counts reactions on enemies this close (section 10: healing rewards risk).
const LEECH_REACH := 200.0

## Dash (section 7.3): 120 px in 0.15 s, untouchable for 0.2 s from the start, 1.0 s
## cooldown, 1 charge (items: up to 3, cooldown never under 0.5 s). Through enemies and their
## shots; walls, obstacles and closed doors still stop it. Guns keep firing.
const DASH_SPEED := 800.0
const DASH_TIME := 0.15
const DASH_IFRAMES := 0.20
const DASH_COOLDOWN := 1.0
const DASH_MIN_COOLDOWN := 0.5
const DASH_MAX_CHARGES := 3
const DODGE_HEAL := 0.03
const DODGE_CAP := 0.40
const ARMOR_K := 15.0   # damage taken = amount x 15 / (15 + armour)
var dash_charges := 1
var dash_recharge := 0.0      # seconds until the next charge comes back
var dashes := 0               # dashes this run (telemetry, bots)
var hostile_slow := 0.0       # s left slowed by tar or a bell's ring (Bestiary.TAR_SLOW)
var perfect_dodges := 0
var _dash_t := 0.0            # seconds of dash movement left
var _dash_dir := Vector2.RIGHT
var _dodge_window := 0.0      # seconds of dash invulnerability left
var _dodged_this_dash := false
var _dodge_flash := 0.0
var _ghosts: Array = []       # afterimages: [world pos, age, flip]

## Automatic vent (section 7.1): with the gauge full it fires once VENT_AUTO_CROWD enemies
## are inside its radius, or after VENT_AUTO_WAIT s at full. Options "Vent" = "button" puts
## it back on a button.
const VENT_AUTO_CROWD := 3
const VENT_AUTO_WAIT := 1.5
const VENT_FULL := 0.95
var _vent_full_t := 0.0

var focus := Focus.new()
var vents := 0                # vents this run (telemetry, bots)


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
        # Talent tree choices that act like gear triggers (Mastery.BRANCHES).
        boon_triggers.append_array(_mastery.triggers())


func main() -> Main:
    return get_tree().current_scene as Main


# --- Arsenal ---------------------------------------------------------------


func total_weight() -> int:
    var w := 0
    for g in guns:
        w += g.data.weight
    return w


## Four gun slots (Emil's decision 8, Core loop reset; was six), items may add one or two,
## and the weight budget on top. No save holds more than the kit gun and runs are not
## saved, so nothing migrates; bot builds with six keep their four strongest (Main).
const MAX_GUNS := 4


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
        say("All %d weapon slots full: drop or combine" % gun_slots())
        return false
    if not can_carry(data):
        say("Too heavy: %s needs %d, %d free" % [data.display_name, data.weight, weight_capacity - total_weight()])
        return false
    var gun := Gun.new(data, self)
    add_child(gun)
    guns.append(gun)
    _layout_guns()
    if data.family != "gun":
        recalc_stats()   # weapons count toward their family tag (resonances)
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


## Weapons hover at fixed spots around the figure (decision A8, Brotato-like): each slot
## has its own spot, beside the body rather than over the head or under the feet, so the
## figure stays readable. Guns fire from their spot; melee lunges out from it and back.
const GUN_SPOTS := [Vector2(34, -14), Vector2(-34, -14), Vector2(-30, 20), Vector2(30, 20)]
func _layout_guns() -> void:
    var n := guns.size()
    for i in n:
        if n <= GUN_SPOTS.size():
            guns[i].position = GUN_SPOTS[i]
        else:
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


## Take an item (3.1): a passive stacks one more copy, a mod goes on a gun with a free mod
## slot, an active swaps the old one out (returned so the caller can drop it). `_hint` is
## kept for old callers and ignored.
func equip(id: String, _hint: String = "") -> String:
    var item := Items.get_item(id)
    if item.is_empty():
        return ""
    var slot: String = item["slot"]
    var old := ""
    if slot == "mod":
        var g := mod_target()
        if g == null:
            say("No free mod slot: upgrade a weapon")
            return ""
        equip_mod_on(g, id)
        return ""
    if slot == "active":
        old = equipment.get("active", "")
        equipment["active"] = id
        active_charges = Items.active_max_charges(self)
        Telemetry.equip(id, "active", old)
    else:
        inventory[id] = int(inventory.get(id, 0)) + 1
        Telemetry.equip(id, "passive", "")
    Sfx.item_pickup(int(item.get("rarity", 0)), self)
    recalc_stats()
    return old


## Copies of an item the player owns (passives, the active, and mods across the guns).
func item_count(id: String) -> int:
    return int(gear_counts().get(id, 0))


## id -> copies of everything the player owns: passives, the active and every gun mod.
## Gear counts plus "gun:<id>" for every carried weapon: the synergy halves (Arsenal 5.4).
func synergy_counts(counts: Dictionary) -> Dictionary:
    var out := counts.duplicate()
    for g in guns:
        if g != null and is_instance_valid(g) and g.data != null:
            out["gun:" + g.data.id] = 1
    return out


func gear_counts() -> Dictionary:
    var out: Dictionary = inventory.duplicate()
    var act := String(equipment.get("active", ""))
    if act != "":
        out[act] = int(out.get(act, 0)) + 1
    for g in guns:
        for m in g.mods:
            out[m] = int(out.get(m, 0)) + 1
    return out


## Remove one copy of an item (it leaves the run: the Well). False when not owned.
func unequip_item(id: String) -> bool:
    if String(equipment.get("active", "")) == id:
        equipment.erase("active")
        active_charges = 0
        recalc_stats()
        return true
    if int(inventory.get(id, 0)) > 0:
        inventory[id] = int(inventory[id]) - 1
        if int(inventory[id]) <= 0:
            inventory.erase(id)
        recalc_stats()
        return true
    return false


## Use the active item (Isaac's spacebar item). False when empty or out of charges.
func use_active() -> bool:
    var used: bool = Items.use_active(self)
    if used:
        Telemetry.active_use(String(equipment.get("active", "")))
    return used


## Every distinct item the player owns (passives, the active, gun mods).
func equipped_item_ids() -> Array:
    return gear_counts().keys()


## What the figure wears (3.1: "slot" is only a look): the highest-rarity item per body part,
## two ring and trinket looks at most, and the active.
func worn_look_ids() -> Array:
    var best: Dictionary = {}   # look slot -> [ids by rarity]
    for id in inventory.keys():
        var it := Items.get_item(String(id))
        var sl := String(it.get("slot", ""))
        if not best.has(sl):
            best[sl] = []
        best[sl].append(String(id))
    var out: Array = []
    for sl in best.keys():
        var ids: Array = best[sl]
        ids.sort_custom(func(a, b): return int(Items.get_item(a).get("rarity", 0)) > int(Items.get_item(b).get("rarity", 0)))
        for k in mini(2 if sl in ["ring", "trinket"] else 1, ids.size()):
            out.append(ids[k])
    if equipment.has("active"):
        out.append(String(equipment["active"]))
    return out


## Stats from items (each by its stack rule), resonances and synergies. Announces a synergy
## or resonance the moment it forms (always at a pickup, so outside a fight).
func recalc_stats() -> void:
    var old_max := max_hp
    _stats = {}
    var counts := gear_counts()
    _cond_ids = inventory.keys().filter(func(x): return not (Items.get_item(String(x)).get("cond_mods", {}) as Dictionary).is_empty())
    for id in counts.keys():
        var it := Items.get_item(String(id))
        if String(it.get("slot", "")) == "mod":
            continue   # g_* keys are read by the gun they sit on
        var f := Items.stack_factor(String(it.get("stack", "add")), int(counts[id]))
        var mods: Dictionary = it.get("mods", {})
        for k in mods.keys():
            if mods[k] is String:
                continue
            _stats[k] = float(_stats.get(k, 0.0)) + float(mods[k]) * f
    var res := Items.resonances_for(counts, self)
    for t in res.keys():
        var rm := Items.resonance_mods(String(t), int(res[t]))
        for k in rm.keys():
            _stats[k] = float(_stats.get(k, 0.0)) + float(rm[k])
    var syn := Items.synergies_for(synergy_counts(counts), res)
    for sid in syn:
        var sd := Items.synergy(String(sid))
        _stats["syn_" + String(sid)] = 1.0
        var sm: Dictionary = sd.get("mods", {})
        for k in sm.keys():
            _stats[k] = float(_stats.get(k, 0.0)) + float(sm[k])
    for sid in syn:
        if not synergies.has(sid):
            synergies.append(sid)
            _announce_synergy(String(sid))
    synergies = synergies.filter(func(x): return syn.has(x))
    for t in res.keys():
        if int(res[t]) > int(resonance_tiers.get(t, 0)):
            _announce_resonance(String(t), int(res[t]))
    resonance_tiers = res
    if index == 0:
        Items.held = counts
    max_hp = maxf(20.0, max_hp_base + stat("max_hp"))
    hp = clampf(hp + maxf(0.0, max_hp - old_max), 1.0, max_hp)
    weight_capacity = weight_capacity_base + int(stat("carry"))


func _announce_synergy(sid: String) -> void:
    var sd := Items.synergy(sid)
    var mn := main()
    var fl: int = mn.floor_number if mn != null else 0
    Telemetry.event("synergy", { "id": sid, "floor": fl, "items": inventory.size() })
    if mn != null and mn.hud != null and mn.hud.has_method("banner"):
        mn.hud.banner("SYNERGY: " + String(sd["name"]), String(sd["line"]), sd.get("color", Color.WHITE), false)
    _dodge_flash = 0.3
    Sfx.play("level_up", -2.0)
    if mn != null:
        mn.hitstop(0.08)
    if mn != null and mn.autotest:
        print("[SYNERGY] formed %s on floor %d" % [sid, fl])


func _announce_resonance(tag: String, tier: int) -> void:
    var mn := main()
    var fl: int = mn.floor_number if mn != null else 0
    Telemetry.event("resonance", { "tag": tag, "tier": tier, "floor": fl })
    if mn != null and mn.hud != null and mn.hud.has_method("banner"):
        var title := "RESONANCE: %s%s" % [Items.tag_name(tag), " II" if tier >= 2 else ""]
        mn.hud.banner(title, Items.resonance_line(tag) + (" (doubled)" if tier >= 2 else ""), Items.tag_color(tag), true)
    Sfx.play("level_up", -2.0)
    # Half speed for 0.4 s, never with an enemy close (clarity rules, section 12).
    if mn != null and nearest_enemy(300.0) == null:
        mn.hitstop(0.4, 0.5)
    if mn != null and mn.autotest:
        print("[RESONANCE] %s tier %d on floor %d" % [tag, tier, fl])


## A timed stat buff (Close Shave, the Monocle, Overheat): refreshes a running one.
func add_buff(key: String, amount: float, secs: float) -> void:
    for b in _buffs:
        if String(b[0]) == key:
            b[1] = maxf(float(b[1]), amount)
            b[2] = maxf(float(b[2]), life_t + secs)
            return
    _buffs.append([key, amount, life_t + secs])


## Summed modifier for a key: items, resonances, synergies, level-ups, Shrine talents (their
## conditional ones too), conditional item modifiers that hold, and timed buffs. Keys in
## Items.STAT_CAPS are capped.
func stat(key: String) -> float:
    var v := float(_stats.get(key, 0.0)) + float(bonus_stats.get(key, 0.0))
    if _mastery != null:
        v += _mastery.bonus(key) + _mastery.cond_bonus(key, self)
    for id in _cond_ids:
        var it := Items.get_item(id)
        var cm: Dictionary = it.get("cond_mods", {})
        var f := Items.stack_factor(String(it.get("stack", "add")), int(inventory.get(id, 0)))
        for cond in cm.keys():
            if cm[cond].has(key) and Items.condition(cond, self, {}):
                v += float(cm[cond][key]) * f
    for b in _buffs:
        if String(b[0]) == key and float(b[2]) > life_t:
            v += float(b[1])
    if Items.STAT_CAPS.has(key):
        v = minf(v, float(Items.STAT_CAPS[key]))
    return v


## Brotato-shaped: each level costs noticeably more than the last, so a floor gives a
## few levels, not a dozen.
func xp_to_next() -> float:
    var n := float(level - 1)
    if Main.old_balance:
        return XP_BASE * (pow(n + 1.0, XP_EXP) - pow(n, XP_EXP))
    return XP_BASE_RESET * (pow(n + 1.0, XP_EXP_RESET) - pow(n, XP_EXP_RESET))


## Total XP to reach level `lv` from level 1 is XP_BASE * (lv - 1) ^ XP_EXP. Fitted to the
## XP a run actually earns per arena wave (human run 4487a37a46b6c384 and bots: about 80 in
## the first wave, 1,700 to 2,200 by the end of floor 1, 11k to 14k by arena 12, 43k by
## arena 20, kills grow with the floor), so a level comes about once a wave from the first
## room to the last. The old curve (20 + 15n + 3n^2 per level) gave 2 to 5 levels in the
## first wave and then one every 60 to 130 s on floor 5.
const XP_BASE := 55.0
const XP_EXP := 2.25
## Core loop reset 5.1 (decision 13): fewer, bigger level-ups, about 1.5 a floor and 7 or 8 a
## run (a level every 2 to 3 arenas). Fitted to the kill XP of the 4-arena floors (kite bots:
## about 3,400 on floor 2 and 5,200 on floor 3, close to linear in the floor), so the cost of a
## level grows linearly: 360 x (2n - 1) for level n + 1.
## Core loop reset 14 (2026-11-11): Emil's fresh-save run took 26 level-ups, not 7 or 8 (the
## floors grew denser since); 360 -> 700 puts that same XP at about 19.
const XP_BASE_RESET := 700.0
const XP_EXP_RESET := 2.0


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
    if opt.has("coat_el"):
        var gi := int(opt.get("coat_gun", 0))
        if gi >= 0 and gi < guns.size() and Items.ELEMENTS.has(String(opt["coat_el"])):
            guns[gi].boon_elements.append(Items.ELEMENTS[String(opt["coat_el"])])
    recalc_stats()
    say(opt.get("name", "Upgrade"))


func pressure_limit() -> float:
    return PRESSURE_LIMIT + pressure_limit_bonus + stat("pressure_limit")


func move_speed() -> float:
    return BASE_SPEED * (1.0 + stat("speed")) * maxf(0.4, 1.0 - SPEED_LOSS_PER_WEIGHT * total_weight())


func heal(amount: float, source: String = "other") -> void:
    if alive:
        var mending := MEND_SOURCES.has(source) and not Main.old_balance
        if mending:
            amount = minf(amount, mend_left)
            if amount <= 0.0:
                return
        var before := hp
        hp = minf(max_hp, hp + amount)
        healed_total += hp - before
        if mending:
            mend_left = maxf(0.0, mend_left - (hp - before))
            mend_used += hp - before
        var mn := main()
        if mn != null and mn.pressure_meter != null:
            mn.pressure_meter.on_heal(self, hp - before, source)


## Share of the floor's Mending reserve still left (1 = full), for the HUD bar.
func mend_rate() -> float:
    return mend_left / mend_max if mend_max > 0.0 else 0.0


## A new floor (or the run's start) fills the Mending reserve. Called by Main.
func refill_mending() -> void:
    mend_max = max_hp * (MEND_RESERVE + stat("mend"))   # Bandage Roll: +10% a copy
    if Main.curses.has("brittle"):
        mend_max *= 0.5   # Brittle curse (Core loop reset 11.1)
    mend_left = mend_max
    mend_used = 0.0


## Called by enemies when a reaction this player caused fires.
func on_reaction(_reaction_name: String, where := Vector2.INF) -> void:
    var steal := stat("lifesteal")
    if where != Vector2.INF and where.distance_to(global_position) > LEECH_REACH and not Main.old_balance:
        return   # Leech rewards fighting up close (section 10)
    if steal > 0.0 and (_leech_budget >= 1.0 or Main.old_balance):
        _leech_budget -= 1.0
        var h0 := healed_total
        heal(steal, "leech")
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
    vents += 1
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
    if not alive:
        return
    if _dodge_window > 0.0:
        _perfect_dodge()
        return
    if invuln > 0.0:
        return
    if randf() < minf(DODGE_CAP, stat("dodge")):
        say("Dodged")
        invuln = 0.25
        return
    if mirror_left > 0 and attacker != null and is_instance_valid(attacker):
        # Mirror Hide: the hit bounces back as a nova and never lands.
        mirror_left -= 1
        Items.nova(self, global_position, Element.Kind.HOLY, 140.0, maxf(12.0, amount * 2.0))
        invuln = 0.4
        _dodge_flash = 0.18
        return
    if Main.old_balance:
        amount = maxf(1.0, amount - stat("armor"))
    else:
        # Armour as a percentage (3.1): 3 takes 17% off, 10 takes 40%, 30 takes 67%.
        amount = maxf(1.0, amount * ARMOR_K / (ARMOR_K + maxf(0.0, stat("armor"))))
    if guard_left > 0:
        guard_left -= 1
        amount = maxf(1.0, amount * 0.5)   # Guard resonance: the first hit each room halved
    if Main.curses.has("frailty"):
        amount *= 1.25   # Frailty curse (Core loop reset 11.1)
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
    if hp <= 0.0 and Legendary.phoenix(self):
        pass   # Phoenix Lantern (Arsenal 3.5): whichever comes first, it or Last Breath
    elif hp <= 0.0 and revives_left > 0:
        _last_breath()
    elif hp <= 0.0:
        hp = 0.0
        alive = false
        killed_by = source
        remove_from_group("players")
        say("DOWN", true)
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
    var mn := main()
    if mn != null and mn.pressure_meter != null:
        mn.pressure_meter.on_heal(self, maxf(1.0, max_hp * Mastery.REVIVE_FRACTION), "revive")
    hp = maxf(1.0, max_hp * Mastery.REVIVE_FRACTION)
    invuln = Mastery.REVIVE_INVULN
    _squash = 1.0
    say("Last Breath" if revives_left <= 0 else "Last Breath (%d left)" % revives_left, true)
    Sfx.play("revive")
    var scene := get_tree().current_scene
    if scene != null and scene.has_method("flash"):
        scene.flash(Color(1.0, 0.6, 0.25), 0.45, 0.5)
    Telemetry.event("revive", { "player": index, "left": revives_left, "hp": snappedf(hp, 0.1) })


func display_name() -> String:
    return Progress.player_name(index)


## A short line by the player card. Quiet fights (section 4.5): during a fight only
## `important` lines show unless Options "Fight text" is Everything.
func say(text: String, important := false) -> void:
    if not important and Fx.fight_text() != "everything":
        var mn := main()
        if mn != null and mn.current != null and mn.current.active:
            return
    last_message = text
    _message_time = 2.5
    Fx.count_text("say:" + text)


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
    if BossShow.hold > 0.0:
        mv = Vector2.ZERO   # a boss entrance holds the party still (and invulnerable)
    if mv.length() > 0.2:
        _manual_dir = mv.normalized()
    var want := mv * move_speed() * (Room.WADE if _wading else 1.0)
    if hostile_slow > 0.0:
        hostile_slow = maxf(0.0, hostile_slow - delta)
        want *= Bestiary.TAR_SLOW
    _tick_dash(delta)
    _tick_items(delta)
    if input.just_pressed("dash") and BossShow.hold <= 0.0:
        dash(mv)
    if _dash_t > 0.0:
        velocity = _dash_dir * DASH_SPEED
    elif _on_ice:
        var keep := pow(Materials.ICE_KEEP, delta * 60.0)
        velocity = velocity * keep + want * (1.0 - keep)
    else:
        velocity = want
    move_and_slide()
    if _dash_t > 0.0:
        _dash_bump()

    if PlayerInput.vent_auto():
        _auto_vent(delta)
    elif input.just_pressed("vent"):
        vent()
    if input.take_pressed("active"):
        use_active()

    pressure = move_toward(pressure, 0.0, PRESSURE_DECAY * delta)
    invuln = maxf(0.0, invuln - delta)
    var regen := stat("regen")
    if regen > 0.0:
        var h1 := healed_total
        heal(regen * delta, "regen")
        healed_regen += healed_total - h1
    _leech_budget = minf(LEECH_PER_SEC, _leech_budget + LEECH_PER_SEC * delta)
    _message_time = maxf(0.0, _message_time - delta)
    if _message_time <= 0.0:
        last_message = ""

    _update_aim(delta)
    if aim_mode() == "auto":
        focus.update(self, delta)
    var nearest := nearest_enemy(900.0)
    aimed = nearest
    if _aim_firing and _aim_now != Vector2.ZERO:
        aim_dir = _aim_now
        aimed = _enemy_along(_aim_now, 900.0)
    elif nearest != null:
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
    if invuln > 0.0 or _dodge_window > 0.0:
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
    _stretch = move_toward(_stretch, 1.0 if _dash_t > 0.0 else 0.0, delta * 14.0)
    if _stretch > 0.01:
        _sprite.scale *= Fx.stretch(_dash_dir, 0.35 * _stretch)
    if moving and _dash_t <= 0.0:
        var step := int(_anim_t / PI)   # one footfall per hop
        if step != _step:
            _step = step
            var mn := main()
            if mn != null and mn.fx != null:
                mn.fx.puff(Art.PARTICLES["smoke"], global_position + Vector2(randf_range(-4.0, 4.0), radius * 0.6),
                        Color(0.62, 0.57, 0.5, 0.22), 14.0, 0.28)
    _sprite.position = Vector2(0, -hop) + _recoil
    _sprite.rotation = sin(_anim_t) * 0.08 if moving else 0.0


static func aim_mode() -> String:
    if aim_mode_override != "":
        return aim_mode_override
    var m := String(Settings.get_value("aim_mode"))
    return m if AIM_MODES.has(m) else "auto"


## Decides once per frame whether the guns fire where aimed (_aim_firing, _aim_now) or
## auto-fire (assisted fallback, auto mode), or hold fire (manual, nothing pressed).
func _update_aim(delta: float) -> void:
    var mode := aim_mode()
    var held := alive and input.fire_held()
    if mode == "manual" and String(Settings.get_value("manual_fire")) == "toggle" and not input.force_fire:
        if held and not _fire_was_held:
            _fire_toggled = not _fire_toggled
        _fire_was_held = held
        held = alive and _fire_toggled
    var aim := input.aim_vector(global_position, get_viewport())
    _aim_firing = false
    _aim_now = Vector2.ZERO
    if not alive:
        return
    match mode:
        "auto", "manual":
            # Auto: RT overrides. Manual: fire only while held, never on its own.
            if held:
                _aim_firing = true
                _aim_now = aim if aim != Vector2.ZERO else _manual_dir
        _:
            # Assisted: any aim input (stick, mouse moved, RT) fires there, with a soft lock.
            if held or input.aim_idle < AIM_HOLD:
                var d := aim if aim != Vector2.ZERO else input.last_aim
                if d == Vector2.ZERO:
                    d = _manual_dir
                _aim_firing = true
                _aim_now = d
    if _aim_firing:
        aim_secs += delta
    elif mode != "manual" and nearest_enemy(400.0) != null:
        auto_secs += delta


## Where gun `g` fires this frame, or ZERO for "not now". Assisted mode bends an aimed shot
## onto the enemy or boss part inside a narrow cone; manual never bends; auto picks the nearest.
func gun_dir(g: Gun) -> Vector2:
    if g.data.mechanic == "summon" or g.data.mechanic == "ground":
        return Vector2.ZERO   # summon bodies and ground zones pick their own spots; aim never moves them
    if g.data.family == "melee":
        return _melee_dir(g)
    if _aim_firing:
        if aim_mode() == "assisted":
            return soft_lock(g.global_position, _aim_now, g.effective_range())
        return _aim_now
    if aim_mode() == "manual":
        return Vector2.ZERO
    if aim_mode() == "auto":
        var at := Focus.aim_point(g, 0)
        if at != Vector2.INF and at.distance_to(g.global_position) > 1.0 and at.distance_to(global_position) <= g.effective_range() * 1.1:
            return (at - g.global_position).normalized()
        return Vector2.ZERO   # nothing focused in range: hold until the next pick
    var target := nearest_enemy(g.effective_range())
    if target == null:
        return Vector2.ZERO
    return (target.global_position - g.global_position).normalized()


## Melee (Arsenal expansion 2.1): swings only at an enemy within reach. Auto and assisted
## take the closest one; an aimed swing goes the aimed way when an enemy is in reach there.
func _melee_dir(g: Gun) -> Vector2:
    var reach := g.effective_range()
    if _aim_firing:
        var locked := soft_lock(global_position, _aim_now, reach)
        for e in Strike.enemies_in_cone(get_tree(), global_position, _aim_now, reach, deg_to_rad(40.0)):
            return locked
        return Vector2.ZERO
    if aim_mode() == "manual":
        return Vector2.ZERO
    var target := nearest_enemy(reach)
    if target == null:
        return Vector2.ZERO
    var to := target.global_position - global_position
    return to.normalized() if to.length() > 1.0 else Vector2.RIGHT


## `dir` snapped to the enemy, or the visible boss part, whose bearing from `from` is closest
## to it inside SOFT_LOCK_DEG (wider for big, close targets). Unchanged if nothing is there.
func soft_lock(from: Vector2, dir: Vector2, max_range: float) -> Vector2:
    var best := dir
    var best_a := INF
    var cone := deg_to_rad(SOFT_LOCK_DEG)
    var r2 := max_range * max_range
    for e in EnemyGrid.nodes(get_tree(), &"enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or e.emerge > 0.0:
            continue
        if e.global_position.distance_squared_to(from) > r2 * 1.2:
            continue
        var points: Array = []
        var body: BossBody = e.get("body")
        if body != null and body.has_parts():
            for i in body.parts.size():
                if body.visible(i):
                    points.append([body.part_world(i), float(body.parts[i]["r"]) * e.radius])
        else:
            points.append([e.global_position, float(e.radius)])
        for pt in points:
            var to: Vector2 = pt[0] - from
            var d := to.length()
            if d < 1.0 or d > max_range:
                continue
            # A big target close by may be wider than the cone: its own half-width counts.
            var a := absf(dir.angle_to(to))
            var allow := maxf(cone, minf(cone * 2.0, atan(float(pt[1]) * 0.6 / d)))
            if a < allow and a < best_a:
                best_a = a
                best = to / d
    return best


## Every gun fires where gun_dir says: aimed (with or without the soft lock) or at its own
## nearest target. Auto-fire never targets obstacles, props, secret walls or puzzle pieces:
## those you find and shoot yourself.
func _fire() -> void:
    for g in guns:
        if not g.can_fire():
            continue
        var d := gun_dir(g)
        if d != Vector2.ZERO:
            g.fire(d)


## True while the guns pick their own targets (auto aim, nothing held).
func focusing() -> bool:
    return alive and aim_mode() == "auto" and not _aim_firing


# --- Dash ------------------------------------------------------------------


func dash_max_charges() -> int:
    return clampi(1 + int(stat("dash_charges")), 1, DASH_MAX_CHARGES)


func dash_cooldown() -> float:
    return maxf(DASH_MIN_COOLDOWN, DASH_COOLDOWN * (1.0 - stat("dash_cooldown")))


## Dash toward `mv` (the move input), or the way we face with none. False when out of charges.
func dash(mv: Vector2) -> bool:
    if not alive or dash_charges <= 0 or _dash_t > 0.0:
        return false
    dash_charges -= 1
    if dash_recharge <= 0.0:
        dash_recharge = dash_cooldown()
    _dash_dir = mv.normalized() if mv.length() > 0.2 else (aim_dir if aim_dir != Vector2.ZERO else _manual_dir)
    _dash_t = DASH_TIME
    _dodge_window = DASH_IFRAMES
    _dodged_this_dash = false
    dashes += 1
    _squash = 0.6
    _ghosts.clear()
    var mn := main()
    if mn != null and mn.fx != null:
        mn.fx.puff(Art.PARTICLES["circle"], global_position + Vector2(0, radius * 0.6), Color(0.75, 0.7, 0.62, 0.55), 26.0, 0.3)
    Sfx.play("dash", -4.0)
    Items.fire(self, "dash", { "pos": global_position, "dir": _dash_dir })
    if not Settings.flag("dash_learned") and not (mn != null and mn.autotest):
        Settings.set_value("dash_learned", true)
    return true



## Secrets pass: a dash that runs into a cracked wall (SecretWall) knocks at it.
func _dash_bump() -> void:
    for i in get_slide_collision_count():
        var c := get_slide_collision(i)
        var o := c.get_collider()
        if o is SecretWall:
            (o as SecretWall).dash_hit(self)


func _tick_dash(delta: float) -> void:
    var cap := dash_max_charges()
    if dash_charges < cap:
        dash_recharge -= delta
        if dash_recharge <= 0.0:
            dash_charges += 1
            dash_recharge = dash_cooldown() if dash_charges < cap else 0.0
    else:
        dash_charges = cap
        dash_recharge = 0.0
    _dodge_window = maxf(0.0, _dodge_window - delta)
    _dodge_flash = maxf(0.0, _dodge_flash - delta)
    if _dash_t > 0.0:
        _dash_t -= delta
        if _dash_t <= 0.0:
            _squash = 0.7   # the landing
        # Three afterimages over the dash, each fading out in 0.2 s.
        if _ghosts.size() < 3 and _dash_t <= DASH_TIME * (1.0 - float(_ghosts.size()) / 3.0):
            _ghosts.append([global_position, 0.0, _sprite.flip_h, _sprite.texture])
    for gh in _ghosts:
        gh[1] = float(gh[1]) + delta
    _ghosts = _ghosts.filter(func(gh): return float(gh[1]) < 0.2)


## Item effects that run every frame: Shoulder Charge hits along the dash, Ward Vent stops
## enemy shots near you, expired buffs drop.
func _tick_items(delta: float) -> void:
    if _dash_t > 0.0 and stat("dash_hit") > 0.0:
        var dmg := gun_damage_avg() * stat("dash_hit")
        for e in EnemyGrid.overlapping(get_tree(), global_position, radius + 12.0):
            if not is_instance_valid(e) or _dash_hit.has(e) or e.emerge > 0.0:
                continue
            _dash_hit[e] = true
            e.take_damage(dmg, Color(0.9, 0.9, 1.0), true, self)
    elif not _dash_hit.is_empty():
        _dash_hit.clear()
    if ward_t > 0.0:
        ward_t -= delta
        for b in get_tree().get_nodes_in_group("enemy_projectiles"):
            if is_instance_valid(b) and not b.is_queued_for_deletion() and b.global_position.distance_to(global_position) <= WARD_RADIUS:
                b.queue_free()
        queue_redraw()
    if not _buffs.is_empty():
        _buffs = _buffs.filter(func(b): return float(b[2]) > life_t)


const WARD_RADIUS := 110.0


## A typical hit of the first gun with your damage bonus (Shoulder Charge).
func gun_damage_avg() -> float:
    if guns.is_empty() or guns[0].data == null:
        return 10.0
    var g: Gun = guns[0]
    return g.data.damage * g.tier_mult() * maxf(0.1, 1.0 + stat("dmg"))


## An enemy hit landed inside the dash window: a dodge. A soft chime and a white flash, no
## text (quiet fights), the perfect_dodge item event, and DODGE_HEAL from the reserve.
func _perfect_dodge() -> void:
    if _dodged_this_dash:
        return
    _dodged_this_dash = true
    perfect_dodges += 1
    _dodge_flash = 0.18
    Sfx.play("unlock", -10.0)
    heal(max_hp * DODGE_HEAL, "dodge")
    Items.fire(self, "perfect_dodge", { "pos": global_position })


## Automatic vent (section 7.1).
func _auto_vent(delta: float) -> void:
    var limit := pressure_limit()
    if absf(pressure) < limit * VENT_FULL:
        _vent_full_t = 0.0
        return
    _vent_full_t += delta
    var strength := absf(pressure) * (1.0 + stat("vent_power"))
    var r := (110.0 + strength * 1.6) * (1.0 + stat("vent_radius"))
    var near := 0
    for e in EnemyGrid.nodes(get_tree(), &"enemies"):
        if is_instance_valid(e) and e.emerge <= 0.0 and e.global_position.distance_squared_to(global_position) <= r * r:
            near += 1
            if near >= VENT_AUTO_CROWD:
                break
    if near >= VENT_AUTO_CROWD or _vent_full_t >= VENT_AUTO_WAIT:
        _vent_full_t = 0.0
        vent()


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


## The enemy closest to a ray along `dir` (within about 25 degrees), or null.
func _enemy_along(dir: Vector2, max_range: float) -> Node2D:
    var best: Node2D = null
    var best_s := -INF
    for e in get_tree().get_nodes_in_group("enemies"):
        var n := e as Node2D
        if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
            continue
        var to := n.global_position - global_position
        var d := to.length()
        if d > max_range or d < 1.0:
            continue
        var dot := dir.dot(to / d)
        if dot < 0.9:
            continue
        var s := dot * 2.0 - d / max_range
        if s > best_s:
            best_s = s
            best = n
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
    if _dodge_flash > 0.0:
        body = Color(2.2, 2.2, 2.2)   # a perfect dodge: a white flash, no text
    elif _hurt_flash > 0.0:

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
    _draw_dash_and_focus()


## Dash afterimages (40 / 25 / 10% in the player colour, 0.2 s), the recharge arc under the
## feet while a charge comes back, and a thin bracket on a focused elite or boss (section 7).
func _draw_dash_and_focus() -> void:
    var alphas := [0.4, 0.25, 0.1]
    for i in _ghosts.size():
        var gh: Array = _ghosts[i]
        var tex: Texture2D = gh[3]
        if tex == null:
            continue
        var fade := 1.0 - float(gh[1]) / 0.2
        var at := to_local(gh[0]) + _sprite.position
        draw_set_transform(at, 0.0, Vector2(_sprite.scale.x * (-1.0 if gh[2] else 1.0), _sprite.scale.y))
        draw_texture(tex, -tex.get_size() / 2.0, Color(color.lightened(0.2), float(alphas[mini(i, 2)]) * fade))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if dash_charges < dash_max_charges() and dash_recharge > 0.0:
        var k := 1.0 - dash_recharge / maxf(0.01, dash_cooldown())
        draw_arc(Vector2(0, radius * 0.8), 19.0, PI * 0.5 - PI * k, PI * 0.5 + PI * k, 20, Color(0.9, 0.9, 0.85, 0.55), 2.0)
    if not focusing():
        return
    var done := {}
    for g in guns:
        if g.targets.is_empty():
            continue
        var t = g.targets[0]
        if not is_instance_valid(t) or not t is Enemy or done.has(t.get_instance_id()):
            continue
        if not (t.is_elite or t.kind_name == "boss"):
            continue
        done[t.get_instance_id()] = true
        var c := to_local(t.global_position)
        var r: float = t.radius * 1.6 + 6.0
        var arm := r * 0.45
        var col := Color(0.92, 0.92, 0.88, 0.7)
        for sx in [-1.0, 1.0]:
            for sy in [-1.0, 1.0]:
                var corner := c + Vector2(sx * r, sy * r)
                draw_line(corner, corner - Vector2(sx * arm, 0), col, 1.5)
                draw_line(corner, corner - Vector2(0, sy * arm), col, 1.5)


## The rim's colour: the player's own, or the hurting floor's, pulsing toward white while
## we stand in it (and a moment after stepping off).
func _rim_color() -> Color:
    if _dodge_window > 0.0:
        return Color(1, 1, 1)   # dash: a thin white rim while untouchable, never red
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
    _draw_mark()
    var n := int(stat("orbitals"))
    if n <= 0:
        return
    var col: Color = Element.COLORS[orbital_element()].lerp(Color.WHITE, 0.3)
    var tex: Texture2D = Art.tile(ORBITAL_TILE)
    for i in n:
        var at := orbital_offset(i, n)
        _costume.draw_circle(at, 7.0, Color(col, 0.25))
        _costume.draw_texture_rect(tex, Rect2(at - Vector2(8, 8), Vector2(16, 16)), false, col)


## The Mark's accent (Loadout.accent): a small brand on the chest in the Mark's element
## colour, dark-edged, with a slow glow behind it. The body itself is always the Vagrant.
func _draw_mark() -> void:
    var c := Loadout.accent(String(get_meta("mark_id", "vagrant")))
    if c.a <= 0.0:
        return
    var at := _sprite.position + Vector2(0, 3) * _sprite.scale.y * 0.5
    var pulse := 0.5 + 0.5 * sin(life_t * 2.4)
    _costume.draw_texture_rect(Art.PARTICLES["light"], Rect2(at - Vector2(11, 11), Vector2(22, 22)), false, Color(c, 0.30 + 0.20 * pulse))
    var d := PackedVector2Array([at + Vector2(0, -4), at + Vector2(3, 0), at + Vector2(0, 4), at + Vector2(-3, 0)])
    var edge := PackedVector2Array([at + Vector2(0, -5.5), at + Vector2(4.5, 0), at + Vector2(0, 5.5), at + Vector2(-4.5, 0)])
    _costume.draw_colored_polygon(edge, Color(0.05, 0.04, 0.05, 0.95))
    _costume.draw_colored_polygon(d, c.lerp(Color.WHITE, 0.15 * pulse))


# --- Orbitals (familiars) ---------------------------------------------------


func orbital_offset(i: int, n: int) -> Vector2:
    return Vector2(ORBIT_RADIUS, 0).rotated(_orbit_angle + TAU * float(i) / float(maxi(1, n)))


## The first gun's element, or none.
func orbital_element() -> int:
    if stat("syn_living_orbit") > 0.0:
        # Living Orbit: the orbit carries your vial's element.
        for id in inventory.keys():
            if String(id).begins_with("vial_"):
                return int(Items.ELEMENTS.get(String(Items.get_item(id).get("element", "")), Element.Kind.NONE))
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
    var carry_element := (stat("orbital_element") > 0.0 or stat("syn_living_orbit") > 0.0) and kind != Element.Kind.NONE
    if stat("syn_living_orbit") > 0.0 and kind != Element.Kind.NONE:
        Items.note_syn("living_orbit")
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
