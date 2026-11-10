class_name Drops
extends RefCounted
## Build-biased loot. Reads what the party carries (gun elements, tiers, element gear)
## and tilts item and gun rolls toward it: a frost build sees more frost. A fixed share
## of the probability mass always stays off-build so a run can still pivot.

const TOP_MULT := 2.5
const PARTNER_MULT := 1.6
const MOD_MULT := 2.0
const DUPLICATE_MULT := 1.4
const ITEM_OFF_BUILD := 0.25
const GUN_OFF_BUILD := 0.30
## Reaction actions that count as a strong pairing for "reaction_partners".
const STRONG_ACTIONS := ["burst", "chain", "burn", "freeze"]


## { "weights": {Element.Kind: share summing to 1}, "top": Element.Kind (NONE when
## nothing is carried), "top_key": item element key ("" for none),
## "reaction_partners": [Element.Kind], "archetypes": {archetype: count},
## "carried": {gun id: lowest tier carried} }.
static func party_profile(players: Array) -> Dictionary:
    var weights: Dictionary = {}
    var archetypes: Dictionary = {}
    var carried: Dictionary = {}
    for pl in players:
        if pl == null or not is_instance_valid(pl):
            continue
        for g in pl.guns:
            var gun: Gun = g
            if gun == null or gun.data == null:
                continue
            var w := pow(1.3, float(maxi(0, gun.tier - 1)))
            _add_weight(weights, int(gun.data.element), w)
            _add_weight(weights, int(gun.data.extra_element), w * 0.5)
            _add_weight(weights, int(gun.data.alt_element), w * 0.5)
            var arch := gun.data.archetype
            if arch != "":
                archetypes[arch] = int(archetypes.get(arch, 0)) + 1
            var gid := gun.data.id
            carried[gid] = mini(int(carried.get(gid, Gun.MAX_TIER)), gun.tier)
        var equipment: Dictionary = pl.equipment
        for slot in equipment.keys():
            var item: Dictionary = Items.get_item(String(equipment[slot]))
            if item.has("element"):
                _add_weight(weights, _kind_of(String(item["element"])), 0.6)
    var total := 0.0
    for k in weights.keys():
        total += float(weights[k])
    var top: int = Element.Kind.NONE
    var best := 0.0
    if total > 0.0:
        for k in weights.keys():
            weights[k] = float(weights[k]) / total
            if float(weights[k]) > best:
                best = float(weights[k])
                top = int(k)
    return {
        "weights": weights,
        "top": top,
        "top_key": "" if top == Element.Kind.NONE else String(Items.ELEMENT_KEYS.get(top, "")),
        "reaction_partners": reaction_partners(top),
        "archetypes": archetypes,
        "carried": carried,
    }


## Elements whose reaction with `kind` bursts, chains, burns or freezes.
static func reaction_partners(kind: int) -> Array:
    var out: Array = []
    if kind == Element.Kind.NONE:
        return out
    for def in Elements.DEFS:
        var a := int(def["a"])
        var b := int(def["b"])
        if a != kind and b != kind:
            continue
        var other := b if a == kind else a
        if other == kind or out.has(other):
            continue
        var strong := false
        for action in def["do"]:
            var act: Array = action
            var verb := String(act[0])
            for s in STRONG_ACTIONS:
                if verb.begins_with(s):
                    strong = true
        if strong:
            out.append(other)
    return out


## Like Items.roll, tilted toward the party's build. Marks the result seen.
static func roll_item(difficulty: int, min_rarity: int = Items.Rarity.COMMON, exclude: Array = [], luck: float = 0.0, pool: String = "", players: Array = []) -> String:
    var profile := party_profile(players)
    var cap: int = Items.max_rarity_unlocked()
    var rarity: int = Items.Rarity.COMMON
    for r in [Items.Rarity.LEGENDARY, Items.Rarity.EPIC, Items.Rarity.RARE, Items.Rarity.UNCOMMON]:
        if r > cap:
            continue
        if randf() < Items.rarity_chance(r, difficulty, luck):
            rarity = r
            break
    rarity = mini(maxi(rarity, min_rarity), cap)
    var picked := ""
    for pass_pool in [pool, ""]:
        if picked != "":
            break
        var source: Array = Items.catalog.keys() if pass_pool == "" else Items.pool_items(pass_pool)
        for allow_seen in [false, true]:
            if picked != "":
                break
            var step := rarity
            while step >= 0:
                var ids := _item_candidates(source, step, exclude, allow_seen)
                if not ids.is_empty():
                    picked = _pick_item(ids, profile)
                    break
                step -= 1
    if picked == "":
        picked = "bone_ring"
    Items.mark_seen(picked)
    return picked


## Core loop reset 5.1: an item of a set `rarity` (the caller rolled it from Items'
## tables), build-biased like roll_item. `want`: "" any, "behaviour", "element" or "stat"
## (neither); with `want_share` < 1 the filter only applies that often. Falls back down a
## rarity, then to any pool, then to seen items, never empty.
static func roll_item_at(rarity: int, exclude: Array = [], pool: String = "", players: Array = [], want: String = "", want_share: float = 1.0) -> String:
    var profile := party_profile(players)
    if want != "" and randf() >= want_share:
        want = ""
    var picked := ""
    for w in ([want, ""] if want != "" else [""]):
        for pass_pool in [pool, ""]:
            for allow_seen in [false, true]:
                if picked != "":
                    break
                var source: Array = Items.catalog.keys() if pass_pool == "" else Items.pool_items(pass_pool)
                var step := rarity
                while step >= 0 and picked == "":
                    var ids := _item_candidates(source, step, exclude, allow_seen)
                    if w != "":
                        ids = ids.filter(func(id): return _wants(Items.get_item(String(id)), w))
                    if not ids.is_empty():
                        picked = _pick_item(ids, profile)
                    step -= 1
    if picked == "":
        picked = "bone_ring"
    Items.mark_seen(picked)
    return picked


static func _wants(it: Dictionary, want: String) -> bool:
    match want:
        "behaviour":
            return Items.is_behaviour(it)
        "element":
            return Items.is_element_changer(it)
        "stat":
            return not Items.is_behaviour(it) and not Items.is_element_changer(it)
    return true


## A gun id from the unlocked guns minus `exclude`, tilted toward the build and toward
## guns the party could combine. "" when nothing is left.
static func roll_gun(players: Array, exclude: Array = []) -> String:
    var ids: Array = Guns.ids().filter(func(id): return not exclude.has(id))
    if ids.is_empty():
        return ""
    var profile := party_profile(players)
    var top := int(profile["top"])
    var partners: Array = profile["reaction_partners"]
    var carried: Dictionary = profile["carried"]
    var on: Array = []
    var on_w: Array = []
    var off: Array = []
    for id in ids:
        var data: GunData = Guns.make(String(id))
        var bias := 1.0
        if top != Element.Kind.NONE:
            var el := int(data.element)
            if el == top:
                bias *= TOP_MULT
            elif partners.has(el):
                bias *= PARTNER_MULT
        if carried.has(id) and int(carried[id]) < Gun.MAX_TIER:
            bias *= DUPLICATE_MULT
        if bias > 1.0:
            on.append(id)
            on_w.append(bias)
        else:
            off.append(id)
    var off_w: Array = []
    for id in off:
        off_w.append(1.0)
    return _split_pick(on, on_w, off, off_w, GUN_OFF_BUILD)


# --- Internals ---------------------------------------------------------------


static func _add_weight(weights: Dictionary, kind: int, w: float) -> void:
    if kind == Element.Kind.NONE:
        return
    weights[kind] = float(weights.get(kind, 0.0)) + w


static func _kind_of(key: String) -> int:
    return int(Items.ELEMENTS.get(key, Element.Kind.NONE))


static func _item_candidates(source: Array, rarity: int, exclude: Array, allow_seen: bool) -> Array:
    var out: Array = []
    for id in source:
        if exclude.has(id) or (not allow_seen and Items.seen_run.has(id)):
            continue
        var item: Dictionary = Items.get_item(String(id))
        if int(item.get("rarity", 0)) == rarity:
            out.append(id)
    return out


## Build bias for one item: element match, reaction partner, or mods that feed the top element.
static func _item_bias(item: Dictionary, profile: Dictionary) -> float:
    var top := int(profile["top"])
    if top == Element.Kind.NONE:
        return 1.0
    var key := String(profile["top_key"])
    var partners: Array = profile["reaction_partners"]
    var bias := 1.0
    if item.has("element"):
        var el := _kind_of(String(item["element"]))
        if el == top:
            bias = TOP_MULT
        elif partners.has(el):
            bias = PARTNER_MULT
    var mods: Dictionary = item.get("mods", {})
    for mk in mods.keys():
        var mkey := String(mk)
        var feeds := false
        if mkey == "extra_element":
            feeds = String(mods[mk]) == key
        elif mkey.ends_with("_" + key) and (mkey.begins_with("dmg_") or mkey.begins_with("potency_") or mkey.begins_with("fire_rate_") or mkey.begins_with("pierce_")):
            feeds = true
        if feeds:
            bias = maxf(bias, MOD_MULT)
    return bias


static func _pick_item(ids: Array, profile: Dictionary) -> String:
    var on: Array = []
    var on_w: Array = []
    var off: Array = []
    var off_w: Array = []
    for id in ids:
        var item: Dictionary = Items.get_item(String(id))
        var base := float(item.get("weight", 1.0))
        var bias := _item_bias(item, profile)
        if bias > 1.0:
            on.append(id)
            on_w.append(base * bias)
        else:
            off.append(id)
            off_w.append(base)
    return _split_pick(on, on_w, off, off_w, ITEM_OFF_BUILD)


## Weighted pick across on-build and off-build lists; off-build keeps at least `off_share`
## of the mass whenever both lists have entries.
static func _split_pick(on: Array, on_w: Array, off: Array, off_w: Array, off_share: float) -> String:
    var on_total := _sum(on_w)
    var off_total := _sum(off_w)
    if on.is_empty() or on_total <= 0.0:
        return _weighted(off, off_w)
    if off.is_empty() or off_total <= 0.0:
        return _weighted(on, on_w)
    var p_off := maxf(off_share, off_total / (on_total + off_total))
    if randf() < p_off:
        return _weighted(off, off_w)
    return _weighted(on, on_w)


static func _sum(ws: Array) -> float:
    var t := 0.0
    for w in ws:
        t += float(w)
    return t


static func _weighted(ids: Array, ws: Array) -> String:
    if ids.is_empty():
        return ""
    var at := randf() * _sum(ws)
    for i in ids.size():
        at -= float(ws[i])
        if at <= 0.0:
            return String(ids[i])
    return String(ids[ids.size() - 1])
