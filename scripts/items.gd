extends Node
## Autoload "Items": the gear catalog and the effect engine.
##
## An item is data: a slot, a rarity, flat stat modifiers ("mods"), modifiers that only
## apply while a condition holds ("cond_mods"), and triggered effects ("triggers").
## Everything synergises through the same small vocabulary, so adding an item is a
## few lines in `_build_catalog` and never new code.
##
## Mods (fractions unless noted):
##   dmg, dmg_<el>, potency, potency_<el>, potency:<Reaction Name>, fire_rate,
##   fire_rate_<el>, proj_speed, range, pierce (int), pierce_<el> (int), proj_count (int),
##   max_hp (int), regen (hp/s), speed, carry (int), pressure_decay, pressure_limit (int),
##   vent_radius, vent_power, focus_gain, scrap_gain, crit, armor (int), dodge,
##   state_duration, vs_wet, vs_burning, vs_frozen, vs_shocked, vs_oiled, lifesteal (hp per
##   reaction), thorns (int), chain_jumps (int)
## Gun mods (slot "mod", apply to the gun they sit on): g_dmg, g_fire_rate, g_count (int),
##   g_pierce (int), g_range, g_speed, g_pressure, extra_element (el key)
## Triggers: { on, chance, if, do, element, potency, radius, amount, count }
##   on:  hit, kill, elite_kill, reaction, reaction:<Reaction Name>, vent, room_clear, hurt,
##        overheat, freeze_up
##   if:  target_wet, target_burning, target_frozen, target_shocked, target_oiled, hot,
##        cold, low_hp, manual, elite
##   do:  apply, nova, heal, scrap, pressure, shoot, shield, slow, chain
##   element: wet, shock, fire, ice, oil, or "last" (the element of the event)

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [
    Color(0.78, 0.78, 0.78),
    Color(0.35, 0.90, 0.40),
    Color(0.35, 0.60, 1.00),
    Color(0.75, 0.40, 1.00),
    Color(1.00, 0.55, 0.15),
]
const RARITY_PRICE := [16, 26, 42, 70, 115]
const SLOTS := ["head", "chest", "hands", "feet", "ring", "trinket", "mod"]
const SLOT_ICONS := {
    "head": Vector2i(33, 0), "chest": Vector2i(35, 1), "hands": Vector2i(41, 1),
    "feet": Vector2i(40, 0), "ring": Vector2i(43, 7), "trinket": Vector2i(44, 6), "mod": Vector2i(45, 16),
}
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
    "scavenger": { "name": "Scavenger", "items": ["scavenger_hood", "scrap_magnet", "mudwaders", "lucky_cog"],
        "bonuses": { 2: { "scrap_gain": 0.20 }, 3: { "carry": 2 } } },
    "overloader": { "name": "Overloader", "items": ["boiler_cap", "overclock", "signet_of_overload", "hot_rod"],
        "bonuses": { 2: { "pressure_limit": 20 }, 3: { "dmg": 0.15 } } },
    "warden": { "name": "Warden", "items": ["padded_vest", "rusted_helm", "worn_gloves", "leather_boots", "bone_ring"],
        "bonuses": { 2: { "max_hp": 15 }, 3: { "armor": 2 }, 4: { "regen": 1 } } },
}

var SETS: Dictionary = {}
var catalog: Dictionary = {}   # id -> item
var _by_rarity: Array = [[], [], [], [], []]
var _depth := 0


func _build_sets() -> void:
    SETS = BASE_SETS.duplicate(true)
    for e in ELEMENTS.keys():
        var en: String = e.capitalize()
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


func price(item: Dictionary, floor_number: int) -> int:
    return RARITY_PRICE[int(item.get("rarity", 0))] + floor_number * 6


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


## Random item id, rarity weighted by difficulty and capped by unlocks.
func roll(difficulty: int, min_rarity: int = Rarity.COMMON, exclude: Array = []) -> String:
    var cap := max_rarity_unlocked()
    var weights := [40.0, 30.0, 18.0, 9.0, 3.0]
    var total := 0.0
    for r in 5:
        if r < min_rarity or r > cap:
            weights[r] = 0.0
        else:
            weights[r] *= 1.0 + float(r) * float(difficulty) * 0.08
        total += weights[r]
    if total <= 0.0:
        weights[mini(min_rarity, cap)] = 1.0
        total = 1.0
    var pick := randf() * total
    var rarity := 0
    for r in 5:
        pick -= weights[r]
        if pick <= 0.0:
            rarity = r
            break
    for attempt in 5:
        var pool: Array = _by_rarity[rarity].filter(func(id): return not exclude.has(id))
        if not pool.is_empty():
            return pool.pick_random()
        rarity = maxi(0, rarity - 1)
    return "bone_ring"


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
    _depth += 1
    for id in player.equipped_item_ids():
        var item: Dictionary = catalog.get(id, {})
        for t in item.get("triggers", []):
            if not _event_matches(t["on"], event, ctx):
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
        "elite":
            return tv and target.is_elite
        "hot":
            return player.pressure > 30.0
        "cold":
            return player.pressure < -30.0
        "low_hp":
            return player.hp < player.max_hp * 0.4
        "manual":
            return not player.auto_aim
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
            if tv:
                Elements._chain_lightning(target, potency)


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

    # --- Head
    _add("rusted_helm", "Rusted Helm", "head", C, "+20 max HP", { "max_hp": 20 })
    _add("scavenger_hood", "Scavenger Hood", "head", U, "+25% scrap", { "scrap_gain": 0.25 })
    _add("crown_of_focus", "Crown of Focus", "head", R, "Focus builds 50% faster. +10% damage in manual aim.", { "focus_gain": 0.5 }, [], { "cond_mods": { "manual": { "dmg": 0.10 } } })
    _add("boiler_cap", "Boiler Cap", "head", E, "+40 pressure limit. Pressure fades 30% faster.", { "pressure_limit": 40, "pressure_decay": 0.3 })
    _add("skullcap_vented", "Skullcap of the Vented", "head", L, "Venting also fires 8 shots of the vented element.", {}, [{ "on": "vent", "do": "shoot", "element": "last", "count": 8, "potency": 8 }])

    # --- Chest
    _add("padded_vest", "Padded Vest", "chest", C, "2 armour", { "armor": 2 })
    _add("thorn_vest", "Thorn Vest", "chest", U, "Attackers take 6 damage", { "thorns": 6 })
    _add("tar_coat", "Tar-stained Coat", "chest", U, "When hurt, oil everything nearby", {}, [{ "on": "hurt", "do": "nova", "element": "oil", "radius": 140, "potency": 3 }])
    _add("conductors_mail", "Conductor's Mail", "chest", R, "Chain Lightning +40% potency and +2 jumps", { "potency:Chain Lightning": 0.4, "chain_jumps": 2 })
    _add("glacier_plate", "Glacier Plate", "chest", E, "4 armour. When hurt, frost nova.", { "armor": 4 }, [{ "on": "hurt", "do": "nova", "element": "ice", "radius": 130, "potency": 6 }])
    _add("phoenix_mantle", "Phoenix Mantle", "chest", L, "Below 40% HP, being hurt may heal 30 and erupt in fire", {}, [{ "on": "hurt", "if": "low_hp", "chance": 0.35, "do": "heal", "amount": 30 }, { "on": "hurt", "if": "low_hp", "chance": 0.35, "do": "nova", "element": "fire", "radius": 220, "potency": 14 }])

    # --- Hands
    _add("worn_gloves", "Worn Gloves", "hands", C, "+8% fire rate", { "fire_rate": 0.08 })
    _add("quick_hands", "Quick Hands", "hands", U, "+15% fire rate, +10% projectile speed", { "fire_rate": 0.15, "proj_speed": 0.10 })
    _add("grip_of_pierce", "Grip of Pierce", "hands", R, "All shots pierce +1", { "pierce": 1 })
    _add("twin_triggers", "Twin Triggers", "hands", E, "Every gun fires +1 projectile", { "proj_count": 1 })
    _add("hands_of_storm", "Hands of the Storm", "hands", L, "10% of hits arc chain lightning from the target", {}, [{ "on": "hit", "chance": 0.10, "do": "chain", "potency": 6 }])

    # --- Feet
    _add("leather_boots", "Leather Boots", "feet", C, "+8% move speed", { "speed": 0.08 })
    _add("mudwaders", "Mudwaders", "feet", U, "+12% move speed, 5% dodge", { "speed": 0.12, "dodge": 0.05 })
    _add("frost_treads", "Frost Treads", "feet", R, "Whatever hurts you gets frozen solid", {}, [{ "on": "hurt", "do": "apply", "element": "ice", "potency": 6 }, { "on": "hurt", "do": "apply", "element": "wet", "potency": 6 }])
    _add("hover_greaves", "Hover Greaves", "feet", E, "15% dodge, +10% move speed", { "dodge": 0.15, "speed": 0.10 })
    _add("seven_league", "Seven-League Boots", "feet", L, "+25% move speed. Clearing a room heals 20.", { "speed": 0.25 }, [{ "on": "room_clear", "do": "heal", "amount": 20 }])

    # --- Trinkets
    _add("scrap_magnet", "Scrap Magnet", "trinket", C, "+15% scrap", { "scrap_gain": 0.15 })
    _add("lucky_cog", "Lucky Cog", "trinket", U, "10% crit chance", { "crit": 0.10 })
    _add("steam_whistle", "Steam Whistle", "trinket", R, "Steam soaks everything nearby", {}, [{ "on": "reaction:Steam", "do": "nova", "element": "wet", "radius": 140, "potency": 3 }])
    _add("pressure_valve", "Pressure Valve", "trinket", R, "Pressure fades 60% faster", { "pressure_decay": 0.6 })
    _add("hot_rod", "Hot Rod", "trinket", E, "+30% damage while hot", {}, [], { "cond_mods": { "hot": { "dmg": 0.30 } } })
    _add("cold_snap", "Cold Snap", "trinket", E, "+30% reaction potency while cold", {}, [], { "cond_mods": { "cold": { "potency": 0.30 } } })
    _add("blood_pact", "Blood Pact", "trinket", E, "+25% damage, -20 max HP", { "dmg": 0.25, "max_hp": -20 })
    _add("heart_of_forge", "Heart of the Forge", "trinket", L, "Burning enemies explode on death", {}, [{ "on": "kill", "if": "target_burning", "do": "nova", "element": "fire", "radius": 140, "potency": 9 }])
    _add("permafrost_core", "Permafrost Core", "trinket", L, "Deep Freeze scatters ice shards", {}, [{ "on": "reaction:Deep Freeze", "do": "shoot", "element": "ice", "count": 5, "potency": 6 }])

    # --- Rings
    _add("bone_ring", "Bone Ring", "ring", C, "+10 max HP", { "max_hp": 10 })
    _add("ring_of_reach", "Ring of Reach", "ring", U, "+20% range", { "range": 0.20 })
    _add("band_of_lingering", "Band of Lingering", "ring", R, "Elements linger 50% longer on enemies", { "state_duration": 0.5 })
    _add("vampiric_loop", "Vampiric Loop", "ring", R, "Heal 2 per reaction", { "lifesteal": 2 })
    _add("ring_of_multiplicity", "Ring of Multiplicity", "ring", E, "20% of hits fire an extra shot of the same element", {}, [{ "on": "hit", "chance": 0.20, "do": "shoot", "element": "last", "count": 1, "potency": 5 }])
    _add("signet_of_overload", "Signet of Overload", "ring", L, "Overheating and freezing up detonate instead of stalling you", {}, [{ "on": "overheat", "do": "nova", "element": "fire", "radius": 300, "potency": 24 }, { "on": "freeze_up", "do": "nova", "element": "ice", "radius": 300, "potency": 24 }])

    # --- Gun mods
    _add("heavy_barrel", "Heavy Barrel", "mod", C, "This gun: +30% damage, -10% fire rate", { "g_dmg": 0.3, "g_fire_rate": -0.1 })
    _add("long_barrel", "Long Barrel", "mod", U, "This gun: +40% range, +30% speed", { "g_range": 0.4, "g_speed": 0.3 })
    _add("split_chamber", "Split Chamber", "mod", R, "This gun: +1 projectile, -20% damage", { "g_count": 1, "g_dmg": -0.2 })
    _add("piercing_rounds", "Piercing Rounds", "mod", R, "This gun: pierce +2", { "g_pierce": 2 })
    _add("overclock", "Overclock", "mod", E, "This gun: +40% fire rate, +50% pressure", { "g_fire_rate": 0.4, "g_pressure": 0.5 })

    # --- Elemental families: one of each per element.
    for e in ELEMENTS.keys():
        var T: String = ELEMENT_TITLES[e]
        var en: String = e.capitalize()
        _add("ring_%s" % e, "Ring of %s" % T, "ring", U, "+25%% %s damage" % en, { "dmg_%s" % e: 0.25 }, [], { "element": e })
        _add("vial_%s" % e, "%s Vial" % T, "trinket", U, "15%% of hits also apply %s" % en, {}, [{ "on": "hit", "chance": 0.15, "do": "apply", "element": e, "potency": 4 }], { "element": e })
        _add("gloves_%s" % e, "%s-touched Gloves" % T, "hands", R, "%s guns: +15%% fire rate, pierce +1" % en, { "fire_rate_%s" % e: 0.15, "pierce_%s" % e: 1 }, [], { "element": e })
        _add("coating_%s" % e, "%s Coating" % T, "mod", R, "This gun also applies %s with every hit" % en, { "extra_element": e }, [], { "element": e })
        _add("mantle_%s" % e, "Mantle of %s" % T, "chest", E, "+30%% potency for %s reactions, +15 max HP" % en, { "potency_%s" % e: 0.3, "max_hp": 15 }, [], { "element": e })
