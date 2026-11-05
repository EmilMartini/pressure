extends Node
## Autoload "Items": the gear catalog and the effect engine.
##
## An item is data: a slot, a rarity, flat stat modifiers ("mods"), modifiers that only
## apply while a condition holds ("cond_mods"), and triggered effects ("triggers").
## Everything synergises through the same small vocabulary, so adding an item is a
## few lines in `_build_catalog` and never new code.
##
## Rarity gates power (Brotato style):
##   Common     one modest stat.
##   Uncommon   two small stats, or one stat and a mild drawback, or a weak trigger.
##   Rare       first mechanics: bounce, pierce, chain jumps, lifesteal, small conditionals.
##   Epic       strong with a cost or a condition; the only non-legendary +projectile.
##   Legendary  run-defining triggers and combos.
##
## Mods (fractions unless noted):
##   dmg, dmg_<el>, potency, potency_<el>, potency:<Reaction Name>, fire_rate,
##   fire_rate_<el>, proj_speed, range, pierce (int), pierce_<el> (int), proj_count (int),
##   max_hp (int), regen (hp/s), speed, carry (int), vent_charge (vent fills faster), pressure_limit (int, vent capacity),
##   vent_radius, vent_power, scrap_gain, crit, crit_dmg (added to the x2 base), armor (int),
##   dodge, state_duration, vs_wet, vs_burning, vs_frozen, vs_shocked, vs_oiled, lifesteal
##   (hp per reaction), thorns (int), chain_jumps (int), bounce (int), xp_gain,
##   luck (fraction: multiplies the rarity odds of item rolls and level-up rolls, see `roll`)
## Gun mods (slot "mod", apply to the gun they sit on): g_dmg, g_fire_rate, g_count (int),
##   g_pierce (int), g_range, g_speed, g_pressure, extra_element (el key)
##   Only g_* keys work on a gun mod (player-wide mods are summed from worn gear only),
##   but triggers on gun mods fire like any other gear.
## Cond mods: { "<condition>": { <mod>: value } }, active while the condition holds. Only
##   player conditions make sense here (hot, cold, low_hp, high_hp, full_hp, moving, still,
##   calm); target conditions never hold outside a trigger. Do not put max_hp or carry
##   in cond mods (they are only read on recalc).
## Triggers: { on, chance, every, if, do, element, potency, radius, amount, count }
##   on:  hit, kill, elite_kill, reaction, reaction:<Reaction Name>, vent, room_clear, hurt
##        (overheat, freeze_up are reserved: nothing fires them yet)
##   every: int N, the trigger only fires on every Nth matching event (counted per player,
##        per item, per trigger; checked before `chance`)
##   if:  target_wet, target_burning, target_frozen, target_shocked, target_oiled,
##        target_poisoned, target_marked (target carries any element state), elite,
##        hot, cold, low_hp (< 40%), high_hp (>= 80%), full_hp, moving, still,
##        calm (|pressure| <= 15)
##   do:  apply, nova, heal, scrap, pressure, shoot, shield, slow, chain,
##        spread (apply `element` to every enemy within `radius`, no damage),
##        xp (grant `amount` experience)
##   element: wet, shock, fire, ice, oil, poison, acid, blood, void, holy, gale, stone,
##        or "last" (the element of the event)
##   at: "target" centres nova/spread/slow on the event's target instead of `pos`.
##   chain with `count`: arcs from each of the `count` nearest enemies within `radius`.
## Shot modifiers (Isaac's tear effects; worn gear only, consumed in Gun._shoot):
##   homing (rad/s turn; straight guns become homing), splash (px, added to splash radius),
##   shards (int; straight guns without pierce/bounce become flak, others burst at end of
##   life), shot_size (fraction: radius x(1+v), damage x(1+v/2)), shot_speed (fraction,
##   stacks with proj_speed), spectral (int flag: shots ignore obstacles), boomerang (int
##   flag: straight guns become boomerangs; wins over homing and shards).
## Familiars (Player): orbitals (int: discs circling at 60 px, hit for half the average
##   gun damage every 0.5 s per enemy), orbital_element (int flag: they also apply the
##   first gun's element).
## Looks (costumes): look: { tile: Vector2i, tint: Color or el key, offset: Vector2 (in
##   body-tile pixels from the figure's centre), scale: float (1 = body tile size), aura:
##   Color or el key, side: bool (offset.x follows facing) }. Merged over SLOT_LOOKS; the
##   LOOKS table gives rare-and-up items theirs. A full set (4 pieces, or all if fewer)
##   tints the figure toward the set colour (SETS[sid].color, or the element colour) with
##   a stronger aura. Drawn by `draw_costume`, used by Player and the character sheet.
## Extra item keys: element (el key, for tint), cond_mods, look, price (int: overrides the
##   rarity base price for an item that is cheaper or pricier than its rarity),
##   pools (Array of POOLS names; when absent the pools are derived from the item's shape
##   by `_auto_pools`), weight (float, default 1.0: pick weight inside a pool, Isaac style;
##   below 1 for very strong items), active (see below).
## Active items (slot "active", Isaac's spacebar item):
##   active: { "charges": N, "do": [ trigger-like dicts: do/element/radius/potency/amount/
##   count/at ] }. Equipping fills the charges; each room clear refills one; each use spends
##   one. Actions run with ctx { pos: player, target: nearest enemy, element: the player's
##   last vented element }, so element "last" means "what you last vented" (fire if none).
## Pools (Isaac): shop, treasure, boss, hidden, challenge, arena. `roll(..., pool)` only
##   draws from that pool. Items already seen this run (`mark_seen`) are skipped until the
##   pool runs dry at every rarity; `new_run` clears them.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [
    Color(0.78, 0.78, 0.78),
    Color(0.35, 0.90, 0.40),
    Color(0.35, 0.60, 1.00),
    Color(0.75, 0.40, 1.00),
    Color(1.00, 0.55, 0.15),
]
const RARITY_PRICE := [22, 38, 62, 98, 150]
## Roll odds per rarity above common: [min difficulty, growth per difficulty, cap].
## chance = clamp(growth * (difficulty - min + 1) * (1 + luck), 0, cap).
const RARITY_ODDS := {
    Rarity.UNCOMMON: [1, 0.07, 0.55],
    Rarity.RARE: [3, 0.03, 0.25],
    Rarity.EPIC: [6, 0.012, 0.10],
    Rarity.LEGENDARY: [9, 0.005, 0.04],
}
const SLOTS := ["head", "chest", "hands", "feet", "ring", "trinket", "mod", "active"]
const SLOT_ICONS := {
    "head": Vector2i(33, 0), "chest": Vector2i(35, 1), "hands": Vector2i(41, 1),
    "feet": Vector2i(40, 0), "ring": Vector2i(43, 7), "trinket": Vector2i(44, 6), "mod": Vector2i(45, 16),
    "active": Vector2i(44, 9),
}
## Item pools, Isaac style. Which pool a room draws from shapes what it offers.
const POOLS := ["shop", "treasure", "boss", "hidden", "challenge", "arena"]
const ECONOMY_KEYS := ["scrap_gain", "luck", "xp_gain", "carry"]
const DEFENCE_KEYS := ["armor", "max_hp", "regen", "thorns", "dodge", "speed"]
const UTILITY_KEYS := ["range", "proj_speed", "pressure_limit", "vent_charge", "vent_radius", "vent_power"]
const MECHANIC_KEYS := ["bounce", "pierce", "chain_jumps", "proj_count", "lifesteal", "state_duration", "g_count", "g_pierce", "extra_element"]
const BOSS_KEYS := ["max_hp", "dmg", "armor", "potency", "fire_rate", "crit", "regen", "speed", "crit_dmg", "lifesteal", "state_duration", "luck"]
const ELEMENTS := {
    "wet": Element.Kind.WET, "shock": Element.Kind.SHOCK, "fire": Element.Kind.FIRE,
    "ice": Element.Kind.ICE, "oil": Element.Kind.OIL, "poison": Element.Kind.POISON,
    "acid": Element.Kind.ACID, "blood": Element.Kind.BLOOD, "void": Element.Kind.VOID,
    "holy": Element.Kind.HOLY, "gale": Element.Kind.GALE, "stone": Element.Kind.STONE,
}
const ELEMENT_KEYS := {
    Element.Kind.WET: "wet", Element.Kind.SHOCK: "shock", Element.Kind.FIRE: "fire",
    Element.Kind.ICE: "ice", Element.Kind.OIL: "oil", Element.Kind.POISON: "poison",
    Element.Kind.ACID: "acid", Element.Kind.BLOOD: "blood", Element.Kind.VOID: "void",
    Element.Kind.HOLY: "holy", Element.Kind.GALE: "gale", Element.Kind.STONE: "stone",
    Element.Kind.NONE: "none",
}
const ELEMENT_TITLES := {
    "wet": "Tide", "shock": "Storm", "fire": "Ember", "ice": "Frost", "oil": "Tar",
    "poison": "Venom", "acid": "Caustic", "blood": "Crimson", "void": "Abyssal",
    "holy": "Radiant", "gale": "Zephyr", "stone": "Granite",
}
## Fourth-piece bonus for each elemental set; the first three are shared.
const ELEMENT_SET_CAPSTONES := {
    "wet": { "lifesteal": 1 }, "shock": { "crit": 0.10 }, "fire": { "crit_dmg": 0.5 },
    "ice": { "armor": 3 }, "oil": { "speed": 0.10 }, "poison": { "state_duration": 0.3 },
    "acid": { "dmg": 0.10 }, "blood": { "regen": 1 }, "void": { "range": 0.20 },
    "holy": { "max_hp": 25 }, "gale": { "proj_speed": 0.25 }, "stone": { "armor": 4 },
}

## Sets: wear several pieces for bonuses at 2, 3 and 4 pieces. Gun mods count.
## Elemental sets are generated per element in _build_sets; these are the hand-made ones.
const BASE_SETS := {
    "scavenger": { "name": "Scavenger", "color": Color(0.85, 0.72, 0.35), "items": ["scavenger_hood", "scrap_magnet", "mudwaders", "lucky_cog"],
        "bonuses": { 2: { "scrap_gain": 0.20 }, 3: { "carry": 2 } } },
    "overloader": { "name": "Overloader", "color": Color(1.00, 0.50, 0.20), "items": ["boiler_cap", "overclock", "signet_of_overload", "hot_rod"],
        "bonuses": { 2: { "pressure_limit": 20 }, 3: { "dmg": 0.15 } } },
    "warden": { "name": "Warden", "color": Color(0.70, 0.75, 0.85), "items": ["padded_vest", "rusted_helm", "worn_gloves", "leather_boots", "bone_ring"],
        "bonuses": { 2: { "max_hp": 15 }, 3: { "armor": 2 }, 4: { "regen": 1 } } },
    "gunslinger": { "name": "Gunslinger", "color": Color(0.95, 0.80, 0.55), "items": ["hair_trigger", "bandolier", "gun_oil", "marksman_monocle"],
        "bonuses": { 2: { "fire_rate": 0.08 }, 3: { "proj_speed": 0.15 }, 4: { "pierce": 1 } } },
    "bulwark": { "name": "Bulwark", "color": Color(0.55, 0.65, 0.80), "items": ["iron_pot", "riveted_plate", "spiked_gauntlets", "anvil_boots"],
        "bonuses": { 2: { "armor": 2 }, 3: { "thorns": 6 }, 4: { "max_hp": 30 } } },
    "alchemist": { "name": "Alchemist", "color": Color(0.45, 0.95, 0.55), "items": ["reagent_satchel", "fume_mask", "catalyst_ring", "alembic"],
        "bonuses": { 2: { "potency": 0.10 }, 3: { "state_duration": 0.20 }, 4: { "lifesteal": 1 } } },
    "windrunner": { "name": "Windrunner", "color": Color(0.60, 1.00, 0.95), "items": ["feather_cap", "runner_wraps", "slipstream_cloak", "quicksilver_band"],
        "bonuses": { 2: { "speed": 0.08 }, 3: { "dodge": 0.06 }, 4: { "crit": 0.08 } } },
    "prospector": { "name": "Prospector", "color": Color(1.00, 0.85, 0.30), "items": ["miners_lamp", "coin_purse", "ledger", "gilded_ring"],
        "bonuses": { 2: { "luck": 0.10 }, 3: { "xp_gain": 0.15 }, 4: { "scrap_gain": 0.25 } } },
    "steamworks": { "name": "Steamworks", "color": Color(0.90, 0.55, 0.40), "items": ["gasket_ring", "bellows", "heat_gauge", "exhaust_pipes"],
        "bonuses": { 2: { "vent_radius": 0.15 }, 3: { "vent_power": 0.20 }, 4: { "pressure_limit": 25 } } },
}

var SETS: Dictionary = {}
var catalog: Dictionary = {}   # id -> item
var _by_rarity: Array = [[], [], [], [], []]
var _depth := 0
var _counters: Dictionary = {}   # "player:item:trigger" -> events seen, for `every`
var seen_run: Dictionary = {}    # item id -> true once it has appeared this run
var _last_vent: Dictionary = {}  # player instance id -> element kind last vented


func _build_sets() -> void:
    SETS = BASE_SETS.duplicate(true)
    for e in ELEMENTS.keys():
        SETS[e] = {
            "name": ELEMENT_TITLES[e],
            "items": ["ring_%s" % e, "vial_%s" % e, "gloves_%s" % e, "coating_%s" % e, "mantle_%s" % e],
            "bonuses": { 2: { "dmg_%s" % e: 0.10 }, 3: { "potency_%s" % e: 0.20 }, 4: ELEMENT_SET_CAPSTONES[e] },
        }


## set id -> number of that set's pieces the player has equipped.
func set_counts(player: Player) -> Dictionary:
    var out: Dictionary = {}
    var ids: Array = player.equipped_item_ids()
    for sid in SETS.keys():
        var n := 0
        for id in SETS[sid]["items"]:
            if ids.has(id):
                n += 1
        if n > 0:
            out[sid] = n
    return out


## Merged mods from every set threshold the player currently meets.
func set_bonus_mods(player: Player) -> Dictionary:
    var mods: Dictionary = {}
    var counts := set_counts(player)
    for sid in counts.keys():
        for threshold in SETS[sid]["bonuses"].keys():
            if counts[sid] >= int(threshold):
                for k in SETS[sid]["bonuses"][threshold].keys():
                    mods[k] = float(mods.get(k, 0.0)) + float(SETS[sid]["bonuses"][threshold][k])
    return mods


## Which set an item belongs to, or "".
func set_of(item_id: String) -> String:
    for sid in SETS.keys():
        if SETS[sid]["items"].has(item_id):
            return sid
    return ""


func _ready() -> void:
    _build_sets()
    _build_catalog()


# --- Queries ---------------------------------------------------------------


func get_item(id: String) -> Dictionary:
    return catalog.get(id, {})


func rarity_color(item: Dictionary) -> Color:
    return RARITY_COLORS[int(item.get("rarity", 0))]


## Brotato-shaped: base + diff + base * 0.08 * diff. `floor_number` is the difficulty
## (callers pass main.difficulty()); the name is kept for compatibility.
func price(item: Dictionary, floor_number: int) -> int:
    var base := float(item.get("price", RARITY_PRICE[int(item.get("rarity", 0))]))
    var diff := float(maxi(0, floor_number))
    return int(roundf(base + 2.0 * diff + base * 0.10 * diff))


func icon(item: Dictionary) -> Vector2i:
    return SLOT_ICONS.get(item.get("slot", "trinket"), SLOT_ICONS["trinket"])


func icon_tint(item: Dictionary) -> Color:
    if item.has("element"):
        return Element.COLORS[ELEMENTS[item["element"]]]
    return rarity_color(item)


func max_rarity_unlocked() -> int:
    if Progress.has("rarity:legendary"):
        return Rarity.LEGENDARY
    if Progress.has("rarity:epic"):
        return Rarity.EPIC
    return Rarity.RARE


## Chance that a roll at `difficulty` lands on `rarity` (checked from legendary down).
func rarity_chance(rarity: int, difficulty: int, luck: float = 0.0) -> float:
    if not RARITY_ODDS.has(rarity):
        return 0.0
    var odds: Array = RARITY_ODDS[rarity]
    var min_diff := int(odds[0])
    if difficulty < min_diff:
        return 0.0
    var growth := float(odds[1])
    var cap := float(odds[2])
    return clampf(growth * float(difficulty - min_diff + 1) * (1.0 + luck), 0.0, cap)


## Random item id. Tiered odds: each rarity above common has a min difficulty, a growth
## per difficulty and a cap, scaled by `luck`; checked from legendary down to uncommon,
## else common. `min_rarity` raises the floor; unlocks cap the result. `pool` limits the
## draw to one of POOLS ("" = any). Items seen this run are skipped; the roll steps down
## a rarity at a time, and only allows repeats once the pool is dry at every rarity.
func roll(difficulty: int, min_rarity: int = Rarity.COMMON, exclude: Array = [], luck: float = 0.0, pool: String = "") -> String:
    var cap := max_rarity_unlocked()
    var rarity: int = Rarity.COMMON
    for r in [Rarity.LEGENDARY, Rarity.EPIC, Rarity.RARE, Rarity.UNCOMMON]:
        if r > cap:
            continue
        if randf() < rarity_chance(r, difficulty, luck):
            rarity = r
            break
    rarity = mini(maxi(rarity, min_rarity), cap)
    for pass_pool in [pool, ""]:
        for allow_seen in [false, true]:
            var step := rarity
            while step >= 0:
                var ids := _candidates(step, pass_pool, exclude, allow_seen)
                if not ids.is_empty():
                    return _pick_weighted(ids)
                step -= 1
    return "bone_ring"


func _candidates(rarity: int, pool: String, exclude: Array, allow_seen: bool) -> Array:
    return _by_rarity[rarity].filter(func(id):
        if exclude.has(id) or (not allow_seen and seen_run.has(id)):
            return false
        return pool == "" or catalog[id].get("pools", POOLS).has(pool))


func _pick_weighted(ids: Array) -> String:
    var total := 0.0
    for id in ids:
        total += float(catalog[id].get("weight", 1.0))
    var at := randf() * total
    for id in ids:
        at -= float(catalog[id].get("weight", 1.0))
        if at <= 0.0:
            return id
    return ids[ids.size() - 1]


## Isaac's pool quality: treasure and hidden rooms never offer commons.
func pool_min_rarity(pool: String) -> int:
    if pool == "treasure" or pool == "hidden":
        return Rarity.UNCOMMON
    return Rarity.COMMON


## Ids in a pool (any rarity), for debugging and UI.
func pool_items(pool: String) -> Array:
    var out: Array = []
    for id in catalog.keys():
        if catalog[id].get("pools", POOLS).has(pool):
            out.append(id)
    return out


## Start of a run: every item is back in its pool.
func new_run() -> void:
    seen_run.clear()
    _counters.clear()
    _last_vent.clear()


## An item has appeared (offered, dropped or taken): it leaves the pools for this run.
func mark_seen(id: String) -> void:
    if id != "":
        seen_run[id] = true


func offer(id: String, price_scrap: int, pos = null) -> Dictionary:
    var o := { "kind": "item", "id": id, "price": price_scrap, "amount": 0, "taken": false }
    if pos != null:
        o["pos"] = pos
    return o


# --- Effect engine ---------------------------------------------------------


## Fire every trigger on the player's gear that matches `event`.
func fire(player: Player, event: String, ctx: Dictionary) -> void:
    if player == null or not is_instance_valid(player) or _depth > 2:
        return
    if event == "vent":
        _last_vent[player.get_instance_id()] = int(ctx.get("element", Element.Kind.FIRE))
    elif event == "room_clear":
        recharge_active(player, 1)
    _depth += 1
    for id in player.equipped_item_ids():
        var item: Dictionary = catalog.get(id, {})
        var triggers: Array = item.get("triggers", [])
        for ti in triggers.size():
            var t: Dictionary = triggers[ti]
            if not _event_matches(t["on"], event, ctx):
                continue
            if t.has("every"):
                var ckey := "%d:%s:%d" % [player.get_instance_id(), id, ti]
                var seen: int = int(_counters.get(ckey, 0)) + 1
                _counters[ckey] = seen
                if seen % maxi(1, int(t["every"])) != 0:
                    continue
            if t.has("chance") and randf() > float(t["chance"]):
                continue
            if t.has("if") and not condition(t["if"], player, ctx):
                continue
            _do(t, player, ctx)
    _depth -= 1


func _event_matches(on: String, event: String, ctx: Dictionary) -> bool:
    if on == event:
        return true
    if on.begins_with("reaction:") and event == "reaction":
        return ctx.get("reaction", "") == on.substr(9)
    return false


func condition(c: String, player: Player, ctx: Dictionary) -> bool:
    var target = ctx.get("target")
    var tv: bool = target != null and is_instance_valid(target) and target is Enemy
    match c:
        "target_wet":
            return tv and target.has_state(Element.Kind.WET)
        "target_burning":
            return tv and target.burn_time > 0.0
        "target_frozen":
            return tv and target.frozen_time > 0.0
        "target_shocked":
            return tv and target.has_state(Element.Kind.SHOCK)
        "target_oiled":
            return tv and target.has_state(Element.Kind.OIL)
        "target_poisoned":
            return tv and target.poison_time > 0.0
        "target_marked":
            return tv and not target.states.is_empty()
        "elite":
            return tv and target.is_elite
        "hot":
            return player.pressure > 30.0
        "cold":
            return player.pressure < -30.0
        "calm":
            return absf(player.pressure) <= 15.0
        "low_hp":
            return player.hp < player.max_hp * 0.4
        "high_hp":
            return player.hp >= player.max_hp * 0.8
        "full_hp":
            return player.hp >= player.max_hp - 0.5
        "moving":
            return player.velocity.length() > 20.0
        "still":
            return player.velocity.length() <= 20.0
    return false


func _element_of(t: Dictionary, ctx: Dictionary) -> int:
    var e: String = t.get("element", "wet")
    if e == "last":
        return int(ctx.get("element", Element.Kind.WET))
    return ELEMENTS.get(e, Element.Kind.WET)


func _do(t: Dictionary, player: Player, ctx: Dictionary) -> void:
    var pos: Vector2 = ctx.get("pos", player.global_position)
    var target = ctx.get("target")
    var tv: bool = target != null and is_instance_valid(target) and target is Enemy and not target.is_queued_for_deletion()
    if t.get("at", "") == "target" and tv:
        pos = target.global_position
    var potency := float(t.get("potency", 5.0))
    match t["do"]:
        "apply":
            if tv:
                target.apply_element(_element_of(t, ctx), potency, player)
        "nova":
            nova(player, pos, _element_of(t, ctx), float(t.get("radius", 120.0)), potency)
        "heal":
            player.heal(float(t.get("amount", 10.0)))
        "scrap":
            player.main().add_scrap(int(t.get("amount", 5)))
        "pressure":
            player.add_pressure(float(t.get("amount", 0.0)))
        "shoot":
            shoot(player, pos, _element_of(t, ctx), int(t.get("count", 3)), potency, target if tv else null)
        "shield":
            player.invuln = maxf(player.invuln, float(t.get("amount", 1.0)))
        "slow":
            for e in _enemies_within(pos, float(t.get("radius", 160.0))):
                e.apply_slow(0.5, 2.5)
        "chain":
            if t.has("count"):
                var near := _enemies_within(pos, float(t.get("radius", 400.0)))
                near.sort_custom(func(a, b): return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
                for i in mini(int(t["count"]), near.size()):
                    if is_instance_valid(near[i]) and not near[i].is_queued_for_deletion():
                        Elements._chain_lightning(near[i], potency)
            elif tv:
                Elements._chain_lightning(target, potency)
        "spread":
            var kind := _element_of(t, ctx)
            var col: Color = Element.COLORS[kind]
            Elements.nova.emit(pos, float(t.get("radius", 140.0)), Color(col, 0.3))
            for e in _enemies_within(pos, float(t.get("radius", 140.0))):
                e.apply_element(kind, potency, player)
        "xp":
            player.gain_xp(float(t.get("amount", 5.0)))


# --- Active items ----------------------------------------------------------


## The player's active item, or {}.
func active_of(player: Player) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {}
    return catalog.get(player.equipment.get("active", ""), {})


func active_max_charges(player: Player) -> int:
    var it := active_of(player)
    if it.is_empty():
        return 0
    return int(it.get("active", {}).get("charges", 1))


## Refill `amount` charges (room clears refill one); equipping fills them all.
func recharge_active(player: Player, amount: int) -> void:
    var max_charges := active_max_charges(player)
    if max_charges <= 0:
        return
    player.active_charges = clampi(player.active_charges + amount, 0, max_charges)


## Spend one charge and run the active item's actions. False when there is nothing to use.
func use_active(player: Player) -> bool:
    var it := active_of(player)
    if it.is_empty() or not player.alive:
        return false
    if player.active_charges <= 0:
        Sfx.play("error")
        player.say("%s is recharging" % it["name"])
        return false
    player.active_charges -= 1
    var target = null
    if player.has_method("nearest_enemy"):
        target = player.nearest_enemy(900.0)
    var ctx := {
        "pos": player.global_position, "target": target,
        "element": int(_last_vent.get(player.get_instance_id(), Element.Kind.FIRE)),
    }
    _depth += 1
    for action in it.get("active", {}).get("do", []):
        _do(action, player, ctx)
    _depth -= 1
    Sfx.play("ui_confirm")
    player.say(it["name"])
    return true


func nova(player: Player, pos: Vector2, element: int, radius: float, potency: float) -> void:
    var col: Color = Element.COLORS[element]
    Elements.nova.emit(pos, radius, Color(col, 0.5))
    for e in _enemies_within(pos, radius):
        e.take_damage(potency, col, true, player)
        if is_instance_valid(e) and not e.is_queued_for_deletion():
            e.apply_element(element, potency, player)


func shoot(player: Player, pos: Vector2, element: int, count: int, potency: float, target: Node2D) -> void:
    var world := player.get_tree().current_scene
    for i in count:
        var dir := Vector2.RIGHT.rotated(randf() * TAU)
        if target != null:
            dir = (target.global_position - pos).normalized().rotated(randf_range(-0.35, 0.35))
        var p := Projectile.new()
        p.velocity = dir * 650.0
        p.damage = potency
        p.element = element
        p.potency = potency
        p.lifetime = 0.7
        p.radius = 5.0
        p.color = Element.COLORS[element]
        p.shooter = player
        p.global_position = pos
        world.add_child(p)


func _enemies_within(pos: Vector2, radius: float) -> Array:
    var out: Array = []
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e) and not e.is_queued_for_deletion() and e.global_position.distance_to(pos) <= radius:
            out.append(e)
    return out


# --- Catalog ---------------------------------------------------------------


func _add(id: String, name: String, slot: String, rarity: int, desc: String, mods: Dictionary = {}, triggers: Array = [], extra: Dictionary = {}) -> void:
    var item := { "id": id, "name": name, "slot": slot, "rarity": rarity, "desc": desc, "mods": mods, "triggers": triggers }
    for k in extra.keys():
        item[k] = extra[k]
    catalog[id] = item
    _by_rarity[rarity].append(id)


func _build_catalog() -> void:
    var C := Rarity.COMMON
    var U := Rarity.UNCOMMON
    var R := Rarity.RARE
    var E := Rarity.EPIC
    var L := Rarity.LEGENDARY

    # ======================= HEAD
    # Common
    _add("rusted_helm", "Rusted Helm", "head", C, "+15 max HP", { "max_hp": 15 })
    _add("iron_pot", "Iron Pot", "head", C, "+1 armour", { "armor": 1 })
    _add("feather_cap", "Feather Cap", "head", C, "+6% move speed", { "speed": 0.06 })
    _add("miners_lamp", "Miner's Lamp", "head", C, "+8% XP gain", { "xp_gain": 0.08 })
    _add("leather_cap", "Leather Cap", "head", C, "+12 max HP", { "max_hp": 12 })
    _add("wide_brim", "Wide Brim Hat", "head", C, "+12% range", { "range": 0.12 })
    # Uncommon
    _add("scavenger_hood", "Scavenger Hood", "head", U, "+15% scrap, +6% XP gain", { "scrap_gain": 0.15, "xp_gain": 0.06 })
    _add("fume_mask", "Fume Mask", "head", U, "+6% potency, elements last 10% longer", { "potency": 0.06, "state_duration": 0.10 })
    _add("sniper_visor", "Sniper Visor", "head", U, "+10% range, +3% crit chance", { "range": 0.10, "crit": 0.03 })
    _add("hothead", "Hothead Bandana", "head", U, "+10% damage, vent charges 15% faster", { "dmg": 0.10, "vent_charge": 0.15 })
    _add("divers_goggles", "Diver's Goggles", "head", U, "+10% damage to wet and shocked foes", { "vs_wet": 0.10, "vs_shocked": 0.10 })
    _add("thinking_cap", "Thinking Cap", "head", U, "+12% XP gain, +4% potency", { "xp_gain": 0.12, "potency": 0.04 })
    # Rare
    _add("crown_of_focus", "Crown of Focus", "head", R, "Shots bounce +1, +4% crit chance", { "bounce": 1, "crit": 0.04 })
    _add("marksman_monocle", "Marksman's Monocle", "head", R, "+6% crit. Standing still: +50% crit damage", { "crit": 0.06 }, [], { "cond_mods": { "still": { "crit_dmg": 0.5 } } })
    _add("storm_hood", "Storm Hood", "head", R, "Chains jump to 2 more enemies, +5% potency", { "chain_jumps": 2, "potency": 0.05 })
    _add("seer_circlet", "Seer's Circlet", "head", R, "+15% luck, +10% XP gain", { "luck": 0.15, "xp_gain": 0.10 })
    # Epic
    _add("boiler_cap", "Boiler Cap", "head", E, "+40 vent capacity, +30% vent power, -8% speed", { "pressure_limit": 40, "vent_power": 0.30, "speed": -0.08 })
    _add("berserker_helm", "Berserker Helm", "head", E, "Below 40% HP: +40% damage, +20% fire rate", {}, [], { "cond_mods": { "low_hp": { "dmg": 0.40, "fire_rate": 0.20 } } })
    # Legendary
    _add("skullcap_vented", "Skullcap of the Vented", "head", L, "Venting fires 8 shots of its element. +15% vent radius", { "vent_radius": 0.15 }, [{ "on": "vent", "do": "shoot", "element": "last", "count": 8, "potency": 8 }])

    # ======================= CHEST
    # Common
    _add("padded_vest", "Padded Vest", "chest", C, "+2 armour", { "armor": 2 })
    _add("quilted_jerkin", "Quilted Jerkin", "chest", C, "+15 max HP", { "max_hp": 15 })
    _add("hide_vest", "Hide Vest", "chest", C, "+0.4 HP regen per second", { "regen": 0.4 })
    _add("lab_apron", "Lab Apron", "chest", C, "+6% reaction potency", { "potency": 0.06 })
    _add("patched_coat", "Patched Coat", "chest", C, "+1 armour", { "armor": 1 })
    _add("cargo_vest", "Cargo Vest", "chest", C, "+12% scrap", { "scrap_gain": 0.12 })
    # Uncommon
    _add("thorn_vest", "Thorn Vest", "chest", U, "Attackers take 4 damage, +1 armour", { "thorns": 4, "armor": 1 })
    _add("tar_coat", "Tar-stained Coat", "chest", U, "When hurt, oil everything nearby", {}, [{ "on": "hurt", "do": "nova", "element": "oil", "radius": 140, "potency": 3 }])
    _add("riveted_plate", "Riveted Plate", "chest", U, "+2 armour, -4% move speed", { "armor": 2, "speed": -0.04 })
    _add("bandolier", "Bandolier", "chest", U, "+6% fire rate, carry +1", { "fire_rate": 0.06, "carry": 1 })
    _add("slipstream_cloak", "Slipstream Cloak", "chest", U, "+6% move speed, 4% dodge", { "speed": 0.06, "dodge": 0.04 })
    _add("bellows", "Bellows", "chest", U, "+12% vent power, +8% vent radius", { "vent_power": 0.12, "vent_radius": 0.08 })
    _add("chain_shirt", "Chainmail Shirt", "chest", U, "+15 max HP, +1 armour", { "max_hp": 15, "armor": 1 })
    # Rare
    _add("conductors_mail", "Conductor's Mail", "chest", R, "Chain Lightning +40% potency and +2 jumps", { "potency:Chain Lightning": 0.4, "chain_jumps": 2 })
    _add("leech_mail", "Leech Mail", "chest", R, "Heal 1 per reaction, +15 max HP", { "lifesteal": 1, "max_hp": 15 })
    _add("spiked_cuirass", "Spiked Cuirass", "chest", R, "Attackers take 10. Hurt: 20% to slow all nearby", { "thorns": 10 }, [{ "on": "hurt", "chance": 0.20, "do": "slow", "radius": 180 }])
    # Epic
    _add("glacier_plate", "Glacier Plate", "chest", E, "4 armour, -8% speed. When hurt, frost nova", { "armor": 4, "speed": -0.08 }, [{ "on": "hurt", "do": "nova", "element": "ice", "radius": 130, "potency": 6 }])
    _add("ammo_harness", "Ammo Harness", "chest", E, "Every gun fires +1 projectile, -12% move speed", { "proj_count": 1, "speed": -0.12 }, [], { "weight": 0.5 })
    # Legendary
    _add("phoenix_mantle", "Phoenix Mantle", "chest", L, "+20 max HP. Hurt below 40%: may heal 30 and erupt", { "max_hp": 20 }, [{ "on": "hurt", "if": "low_hp", "chance": 0.35, "do": "heal", "amount": 30 }, { "on": "hurt", "if": "low_hp", "chance": 0.35, "do": "nova", "element": "fire", "radius": 220, "potency": 14 }])
    _add("gilded_carapace", "Gilded Carapace", "chest", L, "+25% luck and scrap. Elites pay 25, rooms 15 XP", { "luck": 0.25, "scrap_gain": 0.25 }, [{ "on": "elite_kill", "do": "scrap", "amount": 25 }, { "on": "room_clear", "do": "xp", "amount": 15 }], { "weight": 0.5 })

    # ======================= HANDS
    # Common
    _add("worn_gloves", "Worn Gloves", "hands", C, "+8% fire rate", { "fire_rate": 0.08 })
    _add("hair_trigger", "Hair Trigger", "hands", C, "+7% fire rate", { "fire_rate": 0.07 })
    _add("knuckle_wraps", "Knuckle Wraps", "hands", C, "+6% damage", { "dmg": 0.06 })
    _add("steady_gloves", "Steady Gloves", "hands", C, "+4% crit chance", { "crit": 0.04 })
    _add("gardening_gloves", "Gardening Gloves", "hands", C, "+0.3 HP regen per second", { "regen": 0.3 })
    _add("lab_gloves", "Lab Gloves", "hands", C, "+7% reaction potency", { "potency": 0.07 })
    # Uncommon
    _add("quick_hands", "Quick Hands", "hands", U, "+10% fire rate, +10% projectile speed", { "fire_rate": 0.10, "proj_speed": 0.10 })
    _add("spiked_gauntlets", "Spiked Gauntlets", "hands", U, "Attackers take 4 damage, +1 armour", { "thorns": 4, "armor": 1 })
    _add("fingerless_gloves", "Fingerless Gloves", "hands", U, "+6% fire rate, +3% crit chance", { "fire_rate": 0.06, "crit": 0.03 })
    _add("chilled_knuckles", "Chilled Knuckles", "hands", U, "10% of hits chill the target", {}, [{ "on": "hit", "chance": 0.10, "do": "apply", "element": "ice", "potency": 3 }])
    _add("scrappers_mitts", "Scrapper's Mitts", "hands", U, "+10% scrap, +4% fire rate", { "scrap_gain": 0.10, "fire_rate": 0.04 })
    # Rare
    _add("grip_of_pierce", "Grip of Pierce", "hands", R, "All shots pierce +1", { "pierce": 1 })
    _add("ricochet_gloves", "Ricochet Gloves", "hands", R, "Shots bounce +1, -5% damage", { "bounce": 1, "dmg": -0.05 })
    _add("kindling_mitts", "Kindling Mitts", "hands", R, "18% of hits on oiled foes set them alight", {}, [{ "on": "hit", "if": "target_oiled", "chance": 0.18, "do": "apply", "element": "fire", "potency": 5 }])
    # Epic
    _add("twin_triggers", "Twin Triggers", "hands", E, "Every gun fires +1 projectile, -10% damage", { "proj_count": 1, "dmg": -0.10 }, [], { "weight": 0.5 })
    _add("executioners_grip", "Executioner's Grip", "hands", E, "+12% crit, +0.5x crit dmg, -12% fire rate", { "crit": 0.12, "crit_dmg": 0.5, "fire_rate": -0.12 }, [{ "on": "elite_kill", "do": "heal", "amount": 20 }])
    # Legendary
    _add("hands_of_storm", "Hands of the Storm", "hands", L, "15% of hits arc lightning. Chains jump +2", { "chain_jumps": 2 }, [{ "on": "hit", "chance": 0.15, "do": "chain", "potency": 6 }])

    # ======================= FEET
    # Common
    _add("leather_boots", "Leather Boots", "feet", C, "+8% move speed", { "speed": 0.08 })
    _add("runner_wraps", "Runner Wraps", "feet", C, "+7% move speed", { "speed": 0.07 })
    _add("hobnail_boots", "Hobnail Boots", "feet", C, "+1 armour", { "armor": 1 })
    _add("sturdy_boots", "Sturdy Boots", "feet", C, "+12 max HP", { "max_hp": 12 })
    _add("sandals", "Pilgrim Sandals", "feet", C, "+0.4 HP regen per second", { "regen": 0.4 })
    _add("treaders", "Wanderer's Treads", "feet", C, "+8% XP gain", { "xp_gain": 0.08 })
    # Uncommon
    _add("mudwaders", "Mudwaders", "feet", U, "+8% move speed, 4% dodge", { "speed": 0.08, "dodge": 0.04 })
    _add("jogging_shoes", "Jogging Shoes", "feet", U, "+7% move speed, +0.3 HP regen", { "speed": 0.07, "regen": 0.3 })
    _add("puddle_jumpers", "Puddle Jumpers", "feet", U, "10% of hits soak the target", {}, [{ "on": "hit", "chance": 0.10, "do": "apply", "element": "wet", "potency": 3 }])
    _add("stompers", "Stompers", "feet", U, "+1 armour, attackers take 3 damage", { "armor": 1, "thorns": 3 })
    _add("cinder_clogs", "Cinder Clogs", "feet", U, "+10% damage to burning foes, +4% speed", { "vs_burning": 0.10, "speed": 0.04 })
    # Rare
    _add("frost_treads", "Frost Treads", "feet", R, "Whatever hurts you gets frozen solid", {}, [{ "on": "hurt", "do": "apply", "element": "ice", "potency": 6 }, { "on": "hurt", "do": "apply", "element": "wet", "potency": 6 }])
    _add("anvil_boots", "Anvil Boots", "feet", R, "+3 armour, attackers take 6, -5% speed", { "armor": 3, "thorns": 6, "speed": -0.05 })
    _add("greased_soles", "Greased Soles", "feet", R, "8% dodge. When hurt, oil spills all around", { "dodge": 0.08 }, [{ "on": "hurt", "do": "spread", "element": "oil", "radius": 160, "potency": 4 }])
    _add("tidewalkers", "Tidewalkers", "feet", R, "+20% reaction potency while moving", {}, [], { "cond_mods": { "moving": { "potency": 0.20 } } })
    # Epic
    _add("hover_greaves", "Hover Greaves", "feet", E, "15% dodge, +12% move speed, -15 max HP", { "dodge": 0.15, "speed": 0.12, "max_hp": -15 })
    _add("vent_striders", "Vent Striders", "feet", E, "+30% vent radius, -10 max HP. Venting shields you", { "vent_radius": 0.30, "max_hp": -10 }, [{ "on": "vent", "do": "shield", "amount": 1.5 }])
    # Legendary
    _add("seven_league", "Seven-League Boots", "feet", L, "+20% speed, 8% dodge, +20% damage while moving", { "speed": 0.20, "dodge": 0.08 }, [], { "cond_mods": { "moving": { "dmg": 0.20 } } })

    # ======================= TRINKETS
    # Common
    _add("scrap_magnet", "Scrap Magnet", "trinket", C, "+12% scrap", { "scrap_gain": 0.12 })
    _add("reagent_satchel", "Reagent Satchel", "trinket", C, "+7% reaction potency", { "potency": 0.07 })
    _add("four_leaf_clover", "Four-leaf Clover", "trinket", C, "+5% luck", { "luck": 0.05 }, [], { "price": 18 })
    _add("whetstone", "Whetstone", "trinket", C, "+7% damage", { "dmg": 0.07 })
    _add("bandage_roll", "Bandage Roll", "trinket", C, "+0.5 HP regen per second", { "regen": 0.5 })
    _add("brass_spyglass", "Brass Spyglass", "trinket", C, "+15% range", { "range": 0.15 })
    _add("ticking_clock", "Ticking Clock", "trinket", C, "+6% fire rate", { "fire_rate": 0.06 })
    # Uncommon
    _add("lucky_cog", "Lucky Cog", "trinket", U, "+10% luck, +3% crit chance", { "luck": 0.10, "crit": 0.03 })
    _add("coin_purse", "Coin Purse", "trinket", U, "+15% scrap, -5 max HP", { "scrap_gain": 0.15, "max_hp": -5 })
    _add("ledger", "Dusty Ledger", "trinket", U, "+10% luck, +8% XP gain", { "luck": 0.10, "xp_gain": 0.08 })
    _add("pocket_watch", "Pocket Watch", "trinket", U, "Elements last 10% longer, +4% fire rate", { "state_duration": 0.10, "fire_rate": 0.04 })
    _add("spark_plug", "Spark Plug", "trinket", U, "10% of hits shock the target", {}, [{ "on": "hit", "chance": 0.10, "do": "apply", "element": "shock", "potency": 3 }])
    _add("heat_gauge", "Heat Gauge", "trinket", U, "+15 vent capacity, +8% vent power", { "pressure_limit": 15, "vent_power": 0.08 })
    # Rare
    _add("steam_whistle", "Steam Whistle", "trinket", R, "Steam soaks everything nearby", {}, [{ "on": "reaction:Steam", "do": "nova", "element": "wet", "radius": 140, "potency": 3 }])
    _add("pressure_valve", "Pressure Valve", "trinket", R, "Vent charges 40% faster, +15% vent power", { "vent_charge": 0.4, "vent_power": 0.15 })
    _add("alembic", "Alembic", "trinket", R, "Elements last 25% longer, +8% potency", { "state_duration": 0.25, "potency": 0.08 })
    _add("rabbit_foot", "Rabbit's Foot", "trinket", R, "+20% luck", { "luck": 0.20 }, [], { "price": 38 })
    _add("grisly_trophy", "Grisly Trophy", "trinket", R, "+5% damage. Kills have 15% to heal 4", { "dmg": 0.05 }, [{ "on": "kill", "chance": 0.15, "do": "heal", "amount": 4 }])
    _add("static_jar", "Static Jar", "trinket", R, "15% of hits on wet foes arc lightning", {}, [{ "on": "hit", "if": "target_wet", "chance": 0.15, "do": "chain", "potency": 4 }])
    # Epic
    _add("hot_rod", "Hot Rod", "trinket", E, "+35% damage while hot", {}, [], { "cond_mods": { "hot": { "dmg": 0.35 } } })
    _add("cold_snap", "Cold Snap", "trinket", E, "+35% reaction potency while cold", {}, [], { "cond_mods": { "cold": { "potency": 0.35 } } })
    _add("blood_pact", "Blood Pact", "trinket", E, "+30% damage, -25 max HP", { "dmg": 0.30, "max_hp": -25 })
    _add("plague_censer", "Plague Censer", "trinket", E, "Reactions have 30% to spread poison around", {}, [{ "on": "reaction", "chance": 0.30, "do": "spread", "element": "poison", "radius": 150, "potency": 4 }])
    # Legendary
    _add("heart_of_forge", "Heart of the Forge", "trinket", L, "Burning foes explode on death. +15% vs burning", { "vs_burning": 0.15 }, [{ "on": "kill", "if": "target_burning", "do": "nova", "element": "fire", "radius": 140, "potency": 9 }])
    _add("permafrost_core", "Permafrost Core", "trinket", L, "Deep Freeze throws shards; frozen kills burst", {}, [{ "on": "reaction:Deep Freeze", "do": "shoot", "element": "ice", "count": 5, "potency": 6 }, { "on": "kill", "if": "target_frozen", "do": "nova", "element": "ice", "radius": 120, "potency": 6 }])

    # ======================= RINGS
    # Common
    _add("bone_ring", "Bone Ring", "ring", C, "+10 max HP", { "max_hp": 10 })
    _add("gasket_ring", "Gasket Ring", "ring", C, "+10% vent radius", { "vent_radius": 0.10 })
    _add("copper_ring", "Copper Ring", "ring", C, "+3% crit chance", { "crit": 0.03 })
    _add("tin_ring", "Tin Ring", "ring", C, "+10% scrap", { "scrap_gain": 0.10 })
    _add("jade_ring", "Jade Ring", "ring", C, "+0.3 HP regen per second", { "regen": 0.3 })
    _add("oak_ring", "Oak Ring", "ring", C, "+15 max HP", { "max_hp": 15 })
    _add("wishbone_ring", "Wishbone Ring", "ring", C, "+5% luck", { "luck": 0.05 }, [], { "price": 18 })
    # Uncommon
    _add("ring_of_reach", "Ring of Reach", "ring", U, "+15% range, +10% projectile speed", { "range": 0.15, "proj_speed": 0.10 })
    _add("catalyst_ring", "Catalyst Ring", "ring", U, "+7% reaction potency, +4% damage", { "potency": 0.07, "dmg": 0.04 })
    _add("gilded_ring", "Gilded Ring", "ring", U, "+10% luck, +5% scrap", { "luck": 0.10, "scrap_gain": 0.05 })
    _add("iron_band", "Iron Band", "ring", U, "+1 armour, +10 max HP", { "armor": 1, "max_hp": 10 })
    _add("ring_of_embers", "Ring of Embers", "ring", U, "+12% vs burning, +6% fire potency", { "vs_burning": 0.12, "potency_fire": 0.06 })
    # Rare
    _add("band_of_lingering", "Band of Lingering", "ring", R, "Elements linger 35% longer on enemies", { "state_duration": 0.35 })
    _add("vampiric_loop", "Vampiric Loop", "ring", R, "Heal 2 per reaction", { "lifesteal": 2 })
    _add("quicksilver_band", "Quicksilver Band", "ring", R, "6% dodge. +15% fire rate while moving", { "dodge": 0.06 }, [], { "cond_mods": { "moving": { "fire_rate": 0.15 } } })
    _add("bloodstone", "Bloodstone", "ring", R, "+0.8 regen. Below 40% HP: +20% damage", { "regen": 0.8 }, [], { "cond_mods": { "low_hp": { "dmg": 0.20 } } })
    _add("echo_loop", "Echo Loop", "ring", R, "Reactions have 15% to fling 2 elemental shards", {}, [{ "on": "reaction", "chance": 0.15, "do": "shoot", "element": "last", "count": 2, "potency": 4 }])
    # Epic
    _add("ring_of_multiplicity", "Ring of Multiplicity", "ring", E, "25% of hits fire an extra shot of that element", {}, [{ "on": "hit", "chance": 0.25, "do": "shoot", "element": "last", "count": 1, "potency": 5 }])
    _add("frenzy_band", "Frenzy Band", "ring", E, "+30% fire rate, -20 max HP", { "fire_rate": 0.30, "max_hp": -20 })
    # Legendary
    _add("signet_of_overload", "Signet of Overload", "ring", L, "Venting detonates a huge nova of its element", {}, [{ "on": "vent", "do": "nova", "element": "last", "radius": 300, "potency": 24 }])
    _add("storm_halo", "Storm Halo", "ring", L, "Shots bounce +2 and 30% of hits shock", { "bounce": 2 }, [{ "on": "hit", "chance": 0.30, "do": "apply", "element": "shock", "potency": 4 }], { "weight": 0.3 })

    # ======================= GUN MODS (g_* keys only; triggers work as usual)
    # Common
    _add("sight_rail", "Sight Rail", "mod", C, "This gun: +15% range", { "g_range": 0.15 })
    _add("oiled_bolt", "Oiled Bolt", "mod", C, "This gun: +10% fire rate", { "g_fire_rate": 0.10 })
    # Uncommon
    _add("heavy_barrel", "Heavy Barrel", "mod", U, "This gun: +20% damage, -8% fire rate", { "g_dmg": 0.20, "g_fire_rate": -0.08 })
    _add("long_barrel", "Long Barrel", "mod", U, "This gun: +30% range, +20% shot speed", { "g_range": 0.3, "g_speed": 0.2 })
    _add("gun_oil", "Gun Oil", "mod", U, "This gun: +15% fire rate, -5% range", { "g_fire_rate": 0.15, "g_range": -0.05 })
    _add("exhaust_pipes", "Exhaust Pipes", "mod", U, "This gun: +25% pressure, +6% fire rate", { "g_pressure": 0.25, "g_fire_rate": 0.06 })
    # Rare
    _add("piercing_rounds", "Piercing Rounds", "mod", R, "This gun: pierce +2", { "g_pierce": 2 })
    _add("pressure_coupler", "Pressure Coupler", "mod", R, "This gun: +40% pressure, +15% damage", { "g_pressure": 0.4, "g_dmg": 0.15 })
    _add("arc_emitter", "Arc Emitter", "mod", R, "12% of hits arc lightning. Gun: -5% fire rate", { "g_fire_rate": -0.05 }, [{ "on": "hit", "chance": 0.12, "do": "chain", "potency": 4 }])
    # Epic
    _add("overclock", "Overclock", "mod", E, "This gun: +40% fire rate, +50% pressure", { "g_fire_rate": 0.4, "g_pressure": 0.5 })
    _add("split_chamber", "Split Chamber", "mod", E, "This gun: +1 projectile, -20% damage", { "g_count": 1, "g_dmg": -0.2 }, [], { "weight": 0.6 })
    # Legendary
    _add("chain_reactor", "Chain Reactor", "mod", L, "Reactions have 25% to burst into more. Gun +10% dmg", { "g_dmg": 0.10 }, [{ "on": "reaction", "chance": 0.25, "do": "nova", "element": "last", "radius": 120, "potency": 8 }], { "weight": 0.4 })

    # ======================= SHOT MODIFIERS (Isaac's tear effects; treasure pool, low weights)
    var TR := ["treasure"]
    var TH := ["treasure", "hidden"]
    # Rare
    _add("seeker_lens", "Seeker Lens", "head", R, "Shots curve toward foes", { "homing": 1.5 }, [], { "pools": TR, "weight": 0.6 })
    _add("tracker_boots", "Tracker's Boots", "feet", R, "Shots drift toward foes, +5% speed", { "homing": 0.8, "speed": 0.05 }, [], { "pools": TR, "weight": 0.6 })
    _add("bone_orbit", "Bone Orbit", "trinket", R, "A bone circles you, striking what it touches", { "orbitals": 1 }, [], { "pools": TR, "weight": 0.6 })
    _add("powder_horn", "Powder Horn", "trinket", R, "Shots splash for 30 px when they land", { "splash": 30 }, [], { "pools": TR, "weight": 0.6 })
    _add("lead_shot", "Lead Shot", "ring", R, "+25% shot size, -10% shot speed", { "shot_size": 0.25, "shot_speed": -0.10 }, [], { "pools": TR, "weight": 0.6 })
    _add("wisp_lantern", "Wisp Lantern", "trinket", R, "Spectral shots: they pass through obstacles", { "spectral": 1 }, [], { "pools": TR, "weight": 0.5 })
    _add("rifled_sleeve", "Rifled Sleeve", "hands", R, "+25% shot speed, +10% range", { "shot_speed": 0.25, "range": 0.10 }, [], { "pools": TR, "weight": 0.7 })
    _add("splinter_charm", "Splinter Charm", "ring", R, "Shots break into 2 splinters, -5% damage", { "shards": 2, "dmg": -0.05 }, [], { "pools": TR, "weight": 0.5 })
    # Epic
    _add("cluster_rounds", "Cluster Rounds", "hands", E, "Shots burst into 3 shards", { "shards": 3 }, [], { "pools": TR, "weight": 0.4 })
    _add("big_iron", "Big Iron", "ring", E, "+60% shot size, -15% fire rate", { "shot_size": 0.6, "fire_rate": -0.15 }, [], { "pools": TH, "weight": 0.4 })
    _add("cerebral_spark", "Cerebral Spark", "head", E, "Shots hunt foes hard. -10% damage", { "homing": 3.0, "dmg": -0.10 }, [], { "pools": TR, "weight": 0.4 })
    _add("twin_moons", "Twin Moons", "trinket", E, "Two moons orbit you. -10 max HP", { "orbitals": 2, "max_hp": -10 }, [], { "pools": TR, "weight": 0.4 })
    _add("shrapnel_vest", "Shrapnel Vest", "chest", E, "2 shards and 20 px splash, -8% speed", { "shards": 2, "splash": 20, "speed": -0.08 }, [], { "pools": TR, "weight": 0.4 })
    _add("phantom_shroud", "Phantom Shroud", "chest", E, "Spectral, lightly homing shots. -15 max HP", { "spectral": 1, "homing": 1.0, "max_hp": -15 }, [], { "pools": TH, "weight": 0.4 })
    _add("detonator_cap", "Detonator Cap", "head", E, "Shots splash 60 px, -10% fire rate", { "splash": 60, "fire_rate": -0.10 }, [], { "pools": TR, "weight": 0.4 })
    _add("feral_fang", "Feral Fang", "ring", E, "Homing, +30% shot speed, -10 max HP", { "homing": 1.5, "shot_speed": 0.30, "max_hp": -10 }, [], { "pools": TR, "weight": 0.4 })
    # Legendary
    _add("mothers_blade", "Mother's Blade", "hands", L, "Shots return like boomerangs. +40% damage", { "boomerang": 1, "dmg": 0.40 }, [], { "pools": TR, "weight": 0.3 })
    _add("skull_choir", "Skull Choir", "trinket", L, "3 skulls orbit you and carry your element", { "orbitals": 3, "orbital_element": 1 }, [], { "pools": TR, "weight": 0.3 })
    _add("godhead", "Godhead", "head", L, "Shots seek, swell and burst in light", { "homing": 2.5, "splash": 40, "shot_size": 0.2 }, [], { "pools": TH, "weight": 0.3 })
    _add("hive_heart", "Hive Heart", "chest", L, "Shots burst into 4 shards. A drone orbits you", { "shards": 4, "orbitals": 1 }, [], { "pools": TH, "weight": 0.3 })

    # ======================= ACTIVE ITEMS (press "active"; a room clear refills one charge)
    _add("smelling_salts", "Smelling Salts", "active", C, "Use: heal 15. 2 charges", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "heal", "amount": 15 }] } })
    _add("flash_powder", "Flash Powder", "active", C, "Use: slow everything nearby. 2 charges", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "slow", "radius": 220 }] } })
    _add("tin_whistle", "Tin Whistle", "active", C, "Use: untouchable for 1.5 s. 2 charges", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "shield", "amount": 1.5 }] } })
    _add("pocket_storm", "Pocket Storm", "active", U, "Use: shock nova around you. 2 charges", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "nova", "element": "shock", "radius": 160, "potency": 6 }] } })
    _add("water_bucket", "Bucket of Water", "active", U, "Use: soak everything nearby. 3 charges", {}, [],
        { "active": { "charges": 3, "do": [{ "do": "spread", "element": "wet", "radius": 220, "potency": 5 }] } })
    _add("ember_flask", "Ember Flask", "active", U, "Use: fire burst on the nearest foe. 2 charges", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "nova", "at": "target", "element": "fire", "radius": 130, "potency": 8 }] } })
    _add("grease_gun", "Grease Gun", "active", R, "Use: oil everything nearby, then ignite it", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "spread", "element": "oil", "radius": 200, "potency": 5 }, { "do": "nova", "element": "fire", "radius": 200, "potency": 6 }] } })
    _add("frost_grenade", "Frost Grenade", "active", R, "Use: freezing blast on the nearest foe", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "spread", "at": "target", "element": "wet", "radius": 150, "potency": 5 }, { "do": "nova", "at": "target", "element": "ice", "radius": 150, "potency": 10 }] } })
    _add("dowsing_rod", "Dowsing Rod", "active", R, "Use: find 15 scrap and 10 XP. 1 charge", {}, [],
        { "active": { "charges": 1, "do": [{ "do": "scrap", "amount": 15 }, { "do": "xp", "amount": 10 }] } })
    _add("tesla_coil", "Tesla Coil", "active", E, "Use: lightning arcs from the 6 nearest foes", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "chain", "count": 6, "radius": 500, "potency": 8 }] } })
    _add("overpressure", "Overpressure Valve", "active", E, "Use: +60 pressure and a 1 s shield", {}, [],
        { "active": { "charges": 1, "do": [{ "do": "pressure", "amount": 60 }, { "do": "shield", "amount": 1.0 }] } })
    _add("blood_chalice", "Blood Chalice", "active", E, "Use: heal 40 and splash blood around", {}, [],
        { "active": { "charges": 1, "do": [{ "do": "heal", "amount": 40 }, { "do": "nova", "element": "blood", "radius": 160, "potency": 10 }] } })
    _add("pressure_bomb", "Pressure Bomb", "active", L, "Use: huge nova of your last vent, +20 scrap", {}, [],
        { "weight": 0.5, "active": { "charges": 1, "do": [{ "do": "nova", "element": "last", "radius": 320, "potency": 30 }, { "do": "scrap", "amount": 20 }] } })
    _add("prism_engine", "Prism Engine", "active", L, "Use: drench, shock and ignite all nearby", {}, [],
        { "weight": 0.5, "active": { "charges": 1, "do": [{ "do": "spread", "element": "wet", "radius": 260, "potency": 6 }, { "do": "spread", "element": "shock", "radius": 260, "potency": 8 }, { "do": "nova", "element": "fire", "radius": 260, "potency": 10 }] } })

    # --- Elemental families: one of each per element.
    for e in ELEMENTS.keys():
        var T: String = ELEMENT_TITLES[e]
        var en: String = e.capitalize()
        _add("charm_%s" % e, "%s Charm" % T, "trinket", C, "+10%% %s reaction potency" % en, { "potency_%s" % e: 0.10 }, [], { "element": e })
        _add("ring_%s" % e, "Ring of %s" % T, "ring", U, "+20%% %s damage" % en, { "dmg_%s" % e: 0.20 }, [], { "element": e })
        _add("vial_%s" % e, "%s Vial" % T, "trinket", U, "12%% of hits also apply %s" % en, {}, [{ "on": "hit", "chance": 0.12, "do": "apply", "element": e, "potency": 4 }], { "element": e })
        _add("gloves_%s" % e, "%s-touched Gloves" % T, "hands", R, "%s guns: +15%% fire rate, pierce +1" % en, { "fire_rate_%s" % e: 0.15, "pierce_%s" % e: 1 }, [], { "element": e })
        _add("coating_%s" % e, "%s Coating" % T, "mod", R, "This gun also applies %s with every hit" % en, { "extra_element": e }, [], { "element": e })
        _add("mantle_%s" % e, "Mantle of %s" % T, "chest", E, "+30%% potency for %s reactions, +15 max HP" % en, { "potency_%s" % e: 0.3, "max_hp": 15 }, [], { "element": e })

    _apply_looks()

    # --- Pools: an explicit "pools" in extra wins; everything else is sorted by shape.
    for id in catalog.keys():
        if not catalog[id].has("pools"):
            catalog[id]["pools"] = _auto_pools(catalog[id])


## Isaac-style pool membership derived from what an item does:
##   shop = economy, utility, defence, gun mods and actives; treasure = build-defining
##   (triggers, cond mods, bounce/pierce/chain/lifesteal...); boss = plain stat-ups;
##   hidden = legendaries and big drawbacks; challenge = offence; arena = commons,
##   uncommons and plain rares.
func _auto_pools(it: Dictionary) -> Array:
    var r := int(it["rarity"])
    var mods: Dictionary = it.get("mods", {})
    var has_trig: bool = not it.get("triggers", []).is_empty()
    var has_cond: bool = it.has("cond_mods")
    var drawback := false
    var mechanic := false
    var econ := false
    var defence := false
    var utility := false
    var offence := false
    var plain := not mods.is_empty() and not has_trig and not has_cond
    for k in mods.keys():
        var key: String = k
        var v := float(mods[k])
        if v < 0.0:
            drawback = true
            plain = false
        if key in MECHANIC_KEYS or key.begins_with("potency:") or key.begins_with("pierce_"):
            mechanic = true
        if key in ECONOMY_KEYS:
            econ = true
        if key in DEFENCE_KEYS:
            defence = true
        if key in UTILITY_KEYS:
            utility = true
        if key in ["dmg", "fire_rate", "crit", "crit_dmg", "bounce", "pierce", "proj_count", "g_dmg", "g_fire_rate", "g_count"] \
                or key.begins_with("dmg_") or key.begins_with("fire_rate_") or key.begins_with("vs_"):
            offence = true
        if not (key in BOSS_KEYS or key.begins_with("potency_") or key.begins_with("dmg_")):
            plain = false
    var out: Array = []
    if it.has("active"):
        out = ["shop", "treasure"]
        if r >= Rarity.RARE:
            out.append("hidden")
        return out
    if it["slot"] == "mod":
        out = ["shop", "challenge"]
        if r >= Rarity.RARE or has_trig:
            out.append("treasure")
        if r <= Rarity.UNCOMMON:
            out.append("arena")
        if r == Rarity.LEGENDARY:
            out.append("hidden")
        return out
    if econ or utility or (defence and r <= Rarity.RARE):
        out.append("shop")
    if has_trig or has_cond or mechanic or r == Rarity.LEGENDARY:
        out.append("treasure")
    if r == Rarity.LEGENDARY or (drawback and r >= Rarity.RARE):
        out.append("hidden")
    if plain:
        out.append("boss")
    if offence or (has_trig and not defence and not econ):
        out.append("challenge")
    if r <= Rarity.UNCOMMON or (r == Rarity.RARE and plain):
        out.append("arena")
    if out.is_empty():
        out.append("treasure")
    return out


# --- Looks (costumes on the figure) -----------------------------------------

## Default look per slot when an item has none. Offsets are in body-tile pixels from the
## figure's centre (the body tile is 16 px); scale 1 = the size of the body tile.
const SLOT_LOOKS := {
    "head": { "tile": Vector2i(33, 0), "offset": Vector2(0, -8.0), "scale": 0.6 },
    "chest": {},
    "hands": { "tile": Vector2i(41, 1), "offset": Vector2(6.5, 3.0), "scale": 0.35, "side": true },
    "feet": { "tile": Vector2i(40, 1), "offset": Vector2(0, 7.5), "scale": 0.5 },
    "ring": { "sparkle": true },
    "trinket": { "tile": Vector2i(44, 7), "offset": Vector2(-5.0, 4.0), "scale": 0.35, "side": true },
    "active": { "offset": Vector2(-6.5, -2.0), "scale": 0.45, "side": true, "pips": true },
    "mod": {},
}

## Explicit looks for rare-and-up items (tint may be a Color or an element key).
const LOOKS := {
    # Head
    "crown_of_focus": { "tile": Vector2i(43, 2) },
    "marksman_monocle": { "tile": Vector2i(37, 0), "scale": 0.5 },
    "storm_hood": { "tile": Vector2i(47, 2), "tint": "shock", "scale": 0.7 },
    "seer_circlet": { "tile": Vector2i(44, 2), "scale": 0.5 },
    "boiler_cap": { "tile": Vector2i(38, 0), "tint": Color(1.0, 0.55, 0.25) },
    "berserker_helm": { "tile": Vector2i(36, 0), "tint": Color(0.9, 0.3, 0.3), "scale": 0.7 },
    "skullcap_vented": { "tile": Vector2i(34, 12), "tint": Color(1.0, 0.6, 0.3), "aura": "fire" },
    "seeker_lens": { "tile": Vector2i(37, 0), "scale": 0.5, "tint": Color(0.6, 0.9, 1.0) },
    "cerebral_spark": { "tile": Vector2i(45, 2), "tint": Color(1.0, 0.6, 0.9) },
    "detonator_cap": { "tile": Vector2i(38, 0), "tint": Color(1.0, 0.4, 0.2) },
    "godhead": { "tile": Vector2i(44, 2), "tint": Color(1.0, 0.95, 0.6), "scale": 0.7, "aura": "holy" },
    # Chest
    "conductors_mail": { "tile": Vector2i(33, 1), "tint": "shock" },
    "leech_mail": { "tile": Vector2i(34, 1), "tint": "blood" },
    "spiked_cuirass": { "tile": Vector2i(36, 1) },
    "glacier_plate": { "tile": Vector2i(35, 1), "tint": "ice" },
    "ammo_harness": { "tile": Vector2i(32, 1), "tint": Color(0.85, 0.7, 0.4) },
    "shrapnel_vest": { "tile": Vector2i(32, 1), "tint": Color(0.7, 0.7, 0.75) },
    "phantom_shroud": { "tile": Vector2i(47, 1), "tint": Color(0.75, 0.8, 1.0, 0.6) },
    "phoenix_mantle": { "tile": Vector2i(38, 1), "tint": "fire", "aura": "fire" },
    "gilded_carapace": { "tile": Vector2i(36, 1), "tint": Color(1.0, 0.85, 0.3), "aura": Color(1.0, 0.85, 0.3) },
    "hive_heart": { "tile": Vector2i(34, 1), "tint": Color(0.95, 0.8, 0.3), "aura": Color(0.95, 0.75, 0.2) },
    # Hands
    "grip_of_pierce": { "tile": Vector2i(42, 1) },
    "ricochet_gloves": { "tile": Vector2i(42, 0) },
    "kindling_mitts": { "tile": Vector2i(41, 0), "tint": "fire" },
    "twin_triggers": { "tile": Vector2i(42, 1), "tint": Color(0.9, 0.5, 1.0) },
    "executioners_grip": { "tile": Vector2i(41, 1), "tint": Color(0.8, 0.2, 0.25) },
    "rifled_sleeve": { "tile": Vector2i(41, 0), "tint": Color(0.7, 0.75, 0.85) },
    "cluster_rounds": { "tile": Vector2i(45, 9), "tint": Color(1.0, 0.6, 0.3) },
    "hands_of_storm": { "tile": Vector2i(42, 0), "tint": "shock", "aura": "shock" },
    "mothers_blade": { "tile": Vector2i(35, 7), "tint": Color(0.95, 0.3, 0.35), "scale": 0.55, "aura": Color(0.9, 0.2, 0.25) },
    # Feet
    "frost_treads": { "tile": Vector2i(44, 1), "tint": "ice" },
    "anvil_boots": { "tile": Vector2i(43, 0), "tint": Color(0.6, 0.65, 0.75) },
    "greased_soles": { "tile": Vector2i(45, 1), "tint": "oil" },
    "tidewalkers": { "tile": Vector2i(44, 0), "tint": "wet" },
    "tracker_boots": { "tile": Vector2i(43, 1), "tint": Color(0.6, 0.9, 1.0) },
    "hover_greaves": { "tile": Vector2i(45, 0), "tint": Color(0.75, 0.6, 1.0) },
    "vent_striders": { "tile": Vector2i(43, 1), "tint": Color(1.0, 0.55, 0.25) },
    "seven_league": { "tile": Vector2i(44, 0), "tint": Color(0.6, 1.0, 0.9), "aura": "gale" },
    # Trinkets
    "steam_whistle": { "tile": Vector2i(46, 9), "tint": "wet" },
    "pressure_valve": { "tile": Vector2i(45, 16) },
    "alembic": { "tile": Vector2i(41, 11), "tint": Color(0.5, 1.0, 0.6) },
    "rabbit_foot": { "tile": Vector2i(45, 7), "tint": Color(1.0, 0.9, 0.6) },
    "grisly_trophy": { "tile": Vector2i(38, 11) },
    "static_jar": { "tile": Vector2i(40, 11), "tint": "shock" },
    "hot_rod": { "tile": Vector2i(44, 7), "tint": "fire" },
    "cold_snap": { "tile": Vector2i(44, 7), "tint": "ice" },
    "blood_pact": { "tile": Vector2i(40, 10), "tint": "blood" },
    "plague_censer": { "tile": Vector2i(42, 11), "tint": "poison" },
    "bone_orbit": { "tile": Vector2i(32, 12) },
    "powder_horn": { "tile": Vector2i(45, 9) },
    "wisp_lantern": { "tile": Vector2i(46, 9), "tint": Color(0.7, 0.85, 1.0) },
    "twin_moons": { "tile": Vector2i(43, 12), "tint": Color(0.85, 0.85, 1.0) },
    "heart_of_forge": { "tile": Vector2i(38, 10), "tint": "fire", "aura": "fire" },
    "permafrost_core": { "tile": Vector2i(32, 10), "tint": "ice", "aura": "ice" },
    "skull_choir": { "tile": Vector2i(34, 12), "tint": Color(0.9, 0.85, 1.0), "aura": "void" },
    # Rings (the sparkle default; legendaries add an aura)
    "signet_of_overload": { "sparkle": true, "aura": Color(1.0, 0.5, 0.2) },
    "storm_halo": { "sparkle": true, "tint": "shock", "aura": "shock" },
}


## Merge LOOKS and the element families into the catalog.
func _apply_looks() -> void:
    for id in LOOKS.keys():
        if catalog.has(id) and not catalog[id].has("look"):
            catalog[id]["look"] = LOOKS[id]
    for e in ELEMENTS.keys():
        if catalog.has("mantle_%s" % e):
            catalog["mantle_%s" % e]["look"] = { "tile": Vector2i(37, 1), "tint": e }
        if catalog.has("gloves_%s" % e):
            catalog["gloves_%s" % e]["look"] = { "tile": Vector2i(41, 1), "tint": e }
        if catalog.has("vial_%s" % e):
            catalog["vial_%s" % e]["look"] = { "tile": Vector2i(41, 11), "tint": e }


func _look_color(v, fallback: Color) -> Color:
    if v is Color:
        return v
    if v is String and ELEMENTS.has(v):
        return Element.COLORS[ELEMENTS[v]]
    return fallback


## An item's full look: the slot default with the item's own look on top, colours resolved.
func look_of(item: Dictionary) -> Dictionary:
    var slot: String = item.get("slot", "trinket")
    var out: Dictionary = SLOT_LOOKS.get(slot, {}).duplicate()
    var own: Dictionary = item.get("look", {})
    for k in own.keys():
        out[k] = own[k]
    out["tint"] = _look_color(out.get("tint"), icon_tint(item) if item.has("element") else rarity_color(item))
    if out.has("aura"):
        out["aura"] = _look_color(out["aura"], rarity_color(item))
    if slot == "active" and not out.has("tile"):
        out["tile"] = icon(item)
    return out


func set_color(sid: String) -> Color:
    if ELEMENTS.has(sid):
        return Element.COLORS[ELEMENTS[sid]]
    return SETS.get(sid, {}).get("color", Color.WHITE)


## The colour of a completed set (4 pieces, or all of a smaller set), or transparent.
func full_set_color(player: Player) -> Color:
    var counts := set_counts(player)
    for sid in counts.keys():
        var need := mini(4, SETS[sid]["items"].size())
        if counts[sid] >= need:
            return set_color(sid)
    return Color(0, 0, 0, 0)


## The id of the first completed set (4 pieces, or all of a smaller set), or "".
func full_set_id(player: Player) -> String:
    var counts := set_counts(player)
    for sid in counts.keys():
        var need := mini(4, SETS[sid]["items"].size())
        if counts[sid] >= need:
            return String(sid)
    return ""


# --- Forms: a paper-doll figure generated from the class and the gear (FigureGen) ----

## Theme points per mod key, read by FigureGen.item_themes. Element-suffixed keys
## (potency_fire, dmg_ice...) and vs_<state> keys map to their element on their own.
const THEME_KEYS := {
    "armor": "plate", "max_hp": "plate", "thorns": "plate",
    "regen": "holy", "lifesteal": "blood", "dmg": "blood",
    "speed": "scout", "dodge": "scout",
    "potency": "arcane", "state_duration": "arcane", "chain_jumps": "arcane",
    "vent_radius": "arcane", "vent_power": "arcane", "vent_charge": "arcane",
    "pressure_limit": "arcane", "homing": "arcane", "orbitals": "arcane",
    "orbital_element": "arcane", "spectral": "void",
    "fire_rate": "gunslinger", "proj_speed": "gunslinger", "proj_count": "gunslinger",
    "pierce": "gunslinger", "bounce": "gunslinger", "range": "gunslinger",
    "shot_speed": "gunslinger", "shot_size": "gunslinger", "crit": "gunslinger",
    "crit_dmg": "gunslinger", "shards": "gunslinger", "splash": "gunslinger",
    "boomerang": "gunslinger",
    "scrap_gain": "merchant", "luck": "merchant", "xp_gain": "merchant", "carry": "merchant",
}
## The theme of each hand-made set (its pieces lean on it; completing it adds 2.5).
## Elemental sets use their element.
const SET_THEMES := {
    "bulwark": "plate", "warden": "plate", "alchemist": "acid", "steamworks": "oil",
    "windrunner": "scout", "prospector": "merchant", "scavenger": "merchant",
    "gunslinger": "gunslinger", "overloader": "fire",
}

var _form_cache: Dictionary = {}   # player instance id -> { key, form }


## The player's current form: { id, name, frames ([idle, step] textures), texture (idle),
## tint (white: the texture is coloured), color (the figure's main colour), aura (the top
## theme's colour with a completed set or a worn legendary, else transparent) }. Cached
## per equipment / class / guns hash, so it is cheap per frame.
func form_for(player: Player) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return _form_from(FigureGen.generate_from({ "vagrant": FigureGen.CLASS_WEIGHT }, Color(0, 0, 0, 0)), false)
    var cid := String(player.get_meta("class_id", "vagrant"))
    var ids: Array = player.equipped_item_ids()
    var gun_els: Array = []
    for g in player.guns:
        gun_els.append(int(g.data.element) if g.data != null else 0)
    var key := hash([ids, cid, gun_els, player.color])
    var pid := player.get_instance_id()
    var cached: Dictionary = _form_cache.get(pid, {})
    if not cached.is_empty() and int(cached["key"]) == key:
        return cached["form"]
    var glow := full_set_id(player) != ""
    for id in ids:
        if int(get_item(String(id)).get("rarity", 0)) >= Rarity.LEGENDARY:
            glow = true
    var form := _form_from(FigureGen.generate(player), glow)
    _form_cache[pid] = { "key": key, "form": form }
    return form


func _form_from(fig: Dictionary, glow: bool) -> Dictionary:
    var frames: Array = fig["frames"]
    return {
        "id": fig["id"], "name": fig["name"], "frames": frames, "texture": frames[0],
        "tint": Color.WHITE, "color": fig["color"],
        "aura": fig["aura"] if glow else Color(0, 0, 0, 0),
    }


## Body tint: white, since the generated figure carries its own colours.
func body_tint(player: Player, base: Color) -> Color:
    return Color(form_for(player)["tint"], base.a)


## Draw the extra layers of `player`'s form on `canvas`. `center` is the body tile's
## centre, `unit` the screen pixels per body-tile pixel (2 in game), `facing` +1 right /
## -1 left. Call once with front = false before the body (form and item auras, ring
## sparkles, the active item slung on the back) and once with front = true after it
## (nothing today: the generated figure already wears its head).
func draw_costume(canvas: CanvasItem, player: Player, center: Vector2, unit: float, facing: float, front: bool) -> void:
    if front:
        return
    var t := float(Time.get_ticks_msec()) / 1000.0
    var form := form_for(player)
    var fa: Color = form["aura"]
    if fa.a > 0.0:
        var pulse := 0.5 + 0.5 * sin(t * 2.5)
        var big := unit * 34.0
        canvas.draw_texture_rect(Art.PARTICLES["light"], Rect2(center - Vector2(big, big) / 2.0, Vector2(big, big)), false, Color(fa, 0.3 + 0.15 * pulse))
        if full_set_id(player) != "":
            for i in 6:
                var sp := center + Vector2(unit * 13.0, 0).rotated(t * 1.2 + TAU * float(i) / 6.0) * Vector2(1.0, 0.6)
                canvas.draw_rect(Rect2(sp - Vector2(unit, unit) * 0.6, Vector2(unit, unit) * 1.2), Color(fa, 0.8))
    for key in Player.EQUIP_KEYS:
        if not player.equipment.has(key):
            continue
        var it := get_item(player.equipment[key])
        if it.is_empty():
            continue
        var lk := look_of(it)
        var tint: Color = lk["tint"]
        var slot := String(it.get("slot", ""))
        var second := String(key).ends_with("2")
        if lk.has("aura"):
            var ac: Color = lk["aura"]
            var s := unit * 26.0
            canvas.draw_texture_rect(Art.PARTICLES["light"], Rect2(center - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(ac, 0.22 + 0.08 * sin(t * 3.0)))
        if lk.get("sparkle", false):
            var phase := t * 0.8 + (PI if second else 0.0)
            for i in 3:
                var p := center + Vector2(unit * 10.0, 0).rotated(phase + TAU * float(i) / 3.0) * Vector2(1.0, 0.55)
                canvas.draw_rect(Rect2(p - Vector2(unit, unit) * 0.5, Vector2(unit, unit)), Color(tint, 0.75))
        if slot == "active" and lk.has("tile"):
            # Slung on the back: behind the figure, on the side away from where it faces.
            var size_b := 16.0 * unit * 0.5
            var at_b := center + Vector2(-facing * 6.0, -3.0) * unit
            canvas.draw_texture_rect(Art.tile(lk["tile"]), Rect2(at_b - Vector2(size_b, size_b) / 2.0, Vector2(size_b, size_b)), false, tint)
            var max_charges := active_max_charges(player)
            for c in max_charges:
                var pip := Rect2(at_b + Vector2(-size_b / 2.0 + float(c) * unit * 2.0, size_b / 2.0 + unit * 0.5), Vector2(unit * 1.5, unit * 1.5))
                canvas.draw_rect(pip, Color(1.0, 0.9, 0.4) if c < player.active_charges else Color(0.25, 0.22, 0.24))
