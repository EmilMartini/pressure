class_name FloorGen
extends RefCounted
## Generates an Isaac-style floor: a tree of rooms on a grid, specials on dead ends,
## and a hidden room behind a secret wall that looks like any other wall. Each room also
## gets a size, an interior layout, maybe a hidden puzzle and, rarely, a secret alcove.

const GRID := 9
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const ARENAS := 6   # arena rooms a floor (Core loop reset 5.0: 4; fun pass 1: 6, shorter rooms)
const OBSTACLES := ["pool", "thicket", "valve", "ward", "rubble", "miasma"]


## A floor for a region (Regions): its depth sets the size and the stock's level, its
## signature layouts colour the arenas. `players` (optional) biases the stock toward the
## party's build through Drops.
static func generate(region_id: String, luck: float = 0.0, players: Array = []) -> Dictionary:
    var floor_number := Regions.depth_of(region_id)
    var target := 7 + floor_number * 2
    if not Main.old_balance:
        # Core loop reset 5.0: four arenas a floor, plus the start and the special rooms.
        target = 1 + ARENAS + (4 if Progress.has("room:challenge") or force_challenge != "" else 3)
    var start := Vector2i(GRID / 2, GRID / 2)
    var rooms: Dictionary = {}
    if not Main.old_balance:
        target -= 1   # the treasure room is added next to the start (fun pass 1)
    for attempt in 60:
        rooms = _grow(start, target)
        if rooms.size() >= target:
            break
    # Fun pass 1: every floor's item room is one door from the start, so a reward is in
    # sight the moment a floor opens. A free cell touching only the start room.
    var treasure_near := false
    if not Main.old_balance:
        var cells: Array = []
        for d in DIRS:
            var n: Vector2i = start + d
            if _in_grid(n) and not rooms.has(n) and _neighbor_count(rooms, n) == 1:
                cells.append(n)
        if not cells.is_empty():
            var tp: Vector2i = cells.pick_random()
            rooms[tp] = _new_room(tp, RoomData.Type.TREASURE)
            treasure_near = true

    # Plain doors between every adjacent pair (the growth rule keeps it a tree).
    for p in rooms.keys():
        for d in DIRS:
            if rooms.has(p + d):
                rooms[p].doors[d] = { "to": p + d, "obstacle": "" }

    # Dead ends, farthest first, become the special rooms.
    var leaves: Array = []
    for p in rooms.keys():
        if p != start and rooms[p].doors.size() == 1 and rooms[p].type != RoomData.Type.TREASURE:
            leaves.append(p)
    leaves.sort_custom(func(a, b): return _dist(a, start) > _dist(b, start))
    var fallback: Array = []
    for p in rooms.keys():
        if p != start and not leaves.has(p) and rooms[p].type != RoomData.Type.TREASURE:
            fallback.append(p)
    fallback.sort_custom(func(a, b): return _dist(a, start) > _dist(b, start))
    var candidates: Array = leaves + fallback
    var specials := [RoomData.Type.BOSS, RoomData.Type.TREASURE, RoomData.Type.SHOP]
    if treasure_near:
        specials.erase(RoomData.Type.TREASURE)
    if Progress.has("room:challenge") or force_challenge != "":
        specials.append(RoomData.Type.CHALLENGE)
    for i in mini(specials.size(), candidates.size()):
        rooms[candidates[i]].type = specials[i]

    if Main.old_balance:
        _place_hidden_room(rooms, start)
    elif force_secret or floor_number >= 2 or randf() < SECRET_FLOOR1_CHANCE:
        _place_secret_room(rooms, start)
    if not Main.old_balance and floor_number >= DEAL_FROM_FLOOR and randf() < DEAL_CHANCE:
        _place_deal_room(rooms)
    _shape_rooms(rooms, start, Regions.get_region(region_id).get("layouts", []))
    _stock_rooms(rooms, floor_number, luck, players)

    rooms[start].discovered = true
    for d in rooms[start].doors.keys():
        rooms[rooms[start].doors[d]["to"]].discovered = true
    return rooms


static func _grow(start: Vector2i, target: int) -> Dictionary:
    var rooms: Dictionary = {}
    rooms[start] = _new_room(start, RoomData.Type.START)
    var queue: Array = [start]
    var guard := 0
    while rooms.size() < target and guard < 2000:
        guard += 1
        if queue.is_empty():
            queue.append(rooms.keys().pick_random())
        var cur: Vector2i = queue.pop_front()
        for d in DIRS:
            if rooms.size() >= target:
                break
            var n: Vector2i = cur + d
            if not _in_grid(n) or rooms.has(n):
                continue
            if _neighbor_count(rooms, n) > 1:
                continue
            if randf() < 0.5:
                continue
            rooms[n] = _new_room(n, RoomData.Type.ARENA)
            queue.append(n)
    return rooms


static func _place_hidden_room(rooms: Dictionary, start: Vector2i) -> void:
    # An empty cell next to an ordinary room, reached through an obstacle door.
    var best: Vector2i = Vector2i(-1, -1)
    var best_score := -1
    for p in rooms.keys():
        var r: RoomData = rooms[p]
        if r.type in [RoomData.Type.BOSS, RoomData.Type.START]:
            continue
        for d in DIRS:
            var n: Vector2i = p + d
            if not _in_grid(n) or rooms.has(n):
                continue
            var score := _neighbor_count(rooms, n) * 2 + _dist(n, start) + randi() % 3
            if score > best_score:
                best_score = score
                best = n
    if best.x < 0:
        return
    var hidden := _new_room(best, RoomData.Type.HIDDEN)
    rooms[best] = hidden
    # Link it from one adjacent room through an obstacle; the way back is a plain door.
    var links: Array = []
    for d in DIRS:
        var p: Vector2i = best + d
        if rooms.has(p) and rooms[p].type not in [RoomData.Type.BOSS, RoomData.Type.START, RoomData.Type.HIDDEN]:
            links.append(d)
    if links.is_empty():
        rooms.erase(best)
        return
    var d: Vector2i = links.pick_random()
    var from: RoomData = rooms[best + d]
    # A secret wall: no door shows, no outline on the map. The method that opens it
    # ("secret") is picked when the party first stands in that room (Room._secret_method).
    from.doors[-d] = { "to": best, "obstacle": "secret", "secret": "" }
    hidden.doors[d] = { "to": best + d, "obstacle": "" }


## Secrets pass (2026-11-11): one secret room a floor, SECRET_FLOOR1_CHANCE on floor 1 and
## always from floor 2. Isaac's rule: the empty cell touching the most rooms (2 or more where
## the floor has one), never next to the boss room; every room it touches gets a cracked wall
## into it, so it can be found from any side. The bot probe `--secret-seek` sets force_secret.
const SECRET_FLOOR1_CHANCE := 0.6
static var force_secret := false


static func _secret_link_ok(r: RoomData) -> bool:
    return r.type not in [RoomData.Type.BOSS, RoomData.Type.HIDDEN, RoomData.Type.DEAL]


static func _place_secret_room(rooms: Dictionary, start: Vector2i) -> void:
    var best: Array = []
    var best_score := -1.0
    var seen := {}
    for p in rooms.keys():
        for d in DIRS:
            var n: Vector2i = p + d
            if not _in_grid(n) or rooms.has(n) or seen.has(n):
                continue
            seen[n] = true
            var links := 0
            var near_boss := false
            for d2 in DIRS:
                var q: Vector2i = n + d2
                if rooms.has(q):
                    if (rooms[q] as RoomData).type == RoomData.Type.BOSS:
                        near_boss = true
                    elif _secret_link_ok(rooms[q]):
                        links += 1
            if near_boss or links == 0:
                continue
            # Touching more rooms wins; among equals, a little farther from the start.
            var score := float(mini(links, 3)) * 10.0 + minf(float(_dist(n, start)), 6.0) * 0.5
            if score > best_score + 0.01:
                best_score = score
                best = [n]
            elif absf(score - best_score) <= 0.01:
                best.append(n)
    if best.is_empty():
        return
    var cell: Vector2i = best.pick_random()
    var hidden := _new_room(cell, RoomData.Type.HIDDEN)
    rooms[cell] = hidden
    for d in DIRS:
        var q: Vector2i = cell + d
        if rooms.has(q) and _secret_link_ok(rooms[q]):
            # The cracked wall on the neighbour's side; plain doors back out of the secret room.
            (rooms[q] as RoomData).doors[-d] = { "to": cell, "obstacle": "secret", "secret": "blast" }
            hidden.doors[d] = { "to": q, "obstacle": "" }


## Size class, layout, seed and puzzle for every room; one floor in four (one in two with
## the "secret:alcove" unlock) hides an alcove in an arena too.
static func _shape_rooms(rooms: Dictionary, start: Vector2i, favour: Array = []) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = randi()
    var used: Array = []
    for p in rooms.keys():
        var r: RoomData = rooms[p]
        r.layout_seed = rng.randi()
        match r.type:
            RoomData.Type.ARENA:
                var roll := rng.randf()
                r.size_class = 0 if roll < 0.25 else (1 if roll < 0.7 else 2)
            RoomData.Type.TREASURE:
                r.size_class = rng.randi_range(0, 1)
            RoomData.Type.CHALLENGE:
                r.size_class = rng.randi_range(1, 2)
            RoomData.Type.HIDDEN:
                r.size_class = 0
            RoomData.Type.BOSS:
                r.size_class = 2
            _:
                r.size_class = 1
        var lr := RandomNumberGenerator.new()
        lr.seed = r.layout_seed
        r.layout = "open" if p == start else RoomLayouts.pick(r.type, r.size_class, lr, favour)
        r.secret = Secrets.pick(r.type, lr, used, r.layout) if p != start else ""
        if r.secret != "":
            used.append(r.secret)
    var alcove_chance := 0.5 if Progress.has("secret:alcove") else 0.25
    if rng.randf() < alcove_chance:
        var arenas: Array = []
        for p in rooms.keys():
            if rooms[p].type == RoomData.Type.ARENA and rooms[p].secret == "":
                arenas.append(p)
        if not arenas.is_empty():
            rooms[arenas[rng.randi() % arenas.size()]].alcove = true


## Obstacle kinds the save has unlocked; the pool is always available. (Hidden rooms now
## sit behind secret walls; the visible obstacles are kept for tests and future use.)
static func unlocked_obstacles() -> Array:
    var out: Array = []
    for kind in OBSTACLES:
        if Progress.has("obstacle:" + kind):
            out.append(kind)
    if out.is_empty():
        out.append("pool")
    return out


static func _stock_rooms(rooms: Dictionary, floor_number: int, luck: float = 0.0, players: Array = []) -> void:
    if not Main.old_balance:
        _stock_rooms_reset(rooms, floor_number, luck, players)
        return
    for p in rooms.keys():
        var r: RoomData = rooms[p]
        match r.type:
            RoomData.Type.SHOP:
                # Brotato shop: four wares (guns or gear) you can reroll for scrap, then one
                # of each service. Wares carry "ware" so a reroll knows what to replace.
                var slots := 4 if Progress.has("shop:extra") else 3
                for i in slots:
                    r.stock.append(roll_ware(floor_number, luck, r.stock, players))
                r.stock.append(offer("reroll", "", reroll_price(floor_number, 0)))
                r.stock.append(offer("carry", "", 50 + floor_number * 18, 2))
                r.stock.append(offer("repair", "", 24 + floor_number * 10, 40))
                # Shrine talent Heirloom: the gunsmith of floors 1..N works for free.
                var free_smith := floor_number <= int(Mastery.bonus("free_gunsmith"))
                r.stock.append(offer("gunsmith", "", 0 if free_smith else 45 + floor_number * 20))
            RoomData.Type.TREASURE:
                # A chest, Slay the Spire style: one pick from gear, a gun, or a run boon.
                # Chest size grows with the floor and a little luck.
                var tier := floor_number + (1 if randf() < 0.3 else 0)
                var min_rarity: int = clampi(tier, Items.Rarity.UNCOMMON, Items.Rarity.EPIC)
                r.stock.append(Items.offer(Drops.roll_item(floor_number * 4 + tier * 2, maxi(min_rarity, Items.pool_min_rarity("treasure")), [], luck, "treasure", players), 0))
                var gun_id := Drops.roll_gun(players, [])
                if gun_id != "":
                    r.stock.append(offer("gun", gun_id, 0))
                r.stock.append(boon_offer(tier))
                r.chest_tier = tier
            RoomData.Type.HIDDEN:
                r.stock.append(offer("carry", "", 0, 3))
                r.stock.append(Items.offer(Drops.roll_item(floor_number * 4 + 4, Items.Rarity.RARE, [], luck, "hidden", players), 0))
                r.loose_scrap = 20 + floor_number * 10
            RoomData.Type.CHALLENGE:
                r.stock.append(offer("sigil", "", 0))


# --- Core loop reset: loot, economy and risk rooms (sections 5.1, 6, 11.1) ------------------

## Shop: SHOP_ITEMS item wares and one gun or gun mod; from floor 2 a MYSTERY_CHANCE that a
## mystery ware takes an item ware's place (MYSTERY_PRICE x m, one rarity over the median).
const SHOP_ITEMS := 3
const MYSTERY_CHANCE := 0.3
const MYSTERY_PRICE := 60
const SHOP_GUN_SHARE := 0.70   # the fourth ware: a weapon, else a mod (Arsenal expansion 3.2)
## Services, x m: repair heals REPAIR_PCT of max health.
const REPAIR_PRICE := 30
const REPAIR_PCT := 40
const CARRY_PRICE := 40
const GUNSMITH_PRICE := 45
## Treasure: pick 1 of 2 on floors 1 and 2, 1 of 3 from TREASURE_THREE_FROM; BEHAVIOUR_SHARE of
## the cards lean to behaviour items; from CURSED_FROM a CURSED_CHANCE that one card is cursed
## loot (one rarity higher, a floor curse).
const TREASURE_THREE_FROM := 3
const BEHAVIOUR_SHARE := 0.6
const CURSED_FROM := 2
const CURSED_CHANCE := 0.25
## Secret room (secrets pass, 2026-11-11): always a pick of 1 of SECRET_CARDS, Rare or better on
## the boss table, one card a weapon SECRET_WEAPON of the time, plus one heart. The old scrap pile
## (SECRET_PILE x m, half the secrets) is gone: scrap already piles up on floors 4 and 5.
const SECRET_PILE := 25
const SECRET_CARDS := 2
const SECRET_WEAPON := 0.35
## Deal room: from DEAL_FROM_FLOOR, DEAL_CHANCE a floor, a door off the boss room. Two Epic or
## Legendary cards priced in max health (DEAL_HP), money (DEAL_MONEY_SHARE of scrap held, at
## least DEAL_MONEY_MIN x m) or a run curse; and a DEAL_HEAL_PCT heal for DEAL_HEAL_PRICE x m.
const DEAL_FROM_FLOOR := 2
const DEAL_CHANCE := 0.4
const DEAL_HP := [15, 25]   # Epic, Legendary
const DEAL_HP_FLOOR := 40.0
const DEAL_MONEY_SHARE := 0.6
const DEAL_MONEY_MIN := 80
const DEAL_HEAL_PCT := 25
const DEAL_HEAL_PRICE := 40


static func _m(floor_number: int) -> float:
    return Items.depth_mult(floor_number)


static func _stock_rooms_reset(rooms: Dictionary, floor_number: int, luck: float, players: Array) -> void:
    for p in rooms.keys():
        var r: RoomData = rooms[p]
        match r.type:
            RoomData.Type.SHOP:
                stock_shop(r, floor_number, luck, players, locked_in)
                locked_in = []
            RoomData.Type.TREASURE:
                var n := 3 if floor_number >= TREASURE_THREE_FROM else 2
                var cards: Array = []
                var ids: Array = []
                for i in n:
                    var rar := Items.roll_rarity("treasure", floor_number, luck)
                    var id := Drops.roll_item_at(rar, ids + _mod_ids(), "treasure", players, "behaviour", BEHAVIOUR_SHARE)
                    if i == n - 1 and randf() < Drops.SYNERGY_CARD_CHANCE:
                        var sc := Drops.synergy_card(ids)
                        if sc != "":
                            id = sc   # section 12: the missing half of a started synergy
                    ids.append(id)
                    cards.append(Items.offer(id, 0))
                if floor_number >= CURSED_FROM and randf() < CURSED_CHANCE:
                    var c: Dictionary = cards[randi() % cards.size()]
                    var up := mini(int(Items.get_item(String(c["id"]))["rarity"]) + 1, Items.max_rarity_unlocked())
                    c["id"] = Drops.roll_item_at(up, ids + _mod_ids(), "treasure", players)
                    c["curse"] = String(Items.CURSES.keys().pick_random())
                    c["curse_span"] = "floor"
                var due := Legendary.drought_due(floor_number)   # Arsenal 3.3: the drought rule
                if due or randf() < Guns.TREASURE_WEAPON:
                    var plain: Array = cards.filter(func(c): return not c.has("curse"))
                    if not plain.is_empty():
                        var at := cards.find(plain.pick_random())
                        var want := Items.Rarity.LEGENDARY if due else Items.roll_rarity("treasure", floor_number, luck, true)
                        var wid := Drops.roll_gun(players, [], want, Items.Rarity.LEGENDARY if due else Items.Rarity.UNCOMMON)
                        if due and wid == "":
                            wid = Drops.roll_gun(players, [], Items.roll_rarity("treasure", floor_number, luck, true), Items.Rarity.UNCOMMON)
                        if wid != "":
                            cards[at] = weapon_offer(wid, floor_number)
                for c in cards:
                    c["group"] = "treasure"
                    r.stock.append(c)
                r.chest_tier = n
            RoomData.Type.HIDDEN:
                stock_secret(r, floor_number, luck, players)
            RoomData.Type.CHALLENGE:
                r.challenge_kind = force_challenge if force_challenge != "" else ("elite" if randf() < 0.5 else "timed")
                r.stock.append(offer("sigil", "", 0))
            RoomData.Type.DEAL:
                stock_deal(r, floor_number, luck, players)


## A secret room's stock: a heart and a pick of 1 of SECRET_CARDS (more with Scavenger's Eye).
static func stock_secret(r: RoomData, floor_number: int, luck: float, players: Array) -> void:
    r.hearts = 1
    var eye := 0   # Scavenger's Eye: 1 more card a copy
    for pl in players:
        if pl != null and is_instance_valid(pl):
            eye = maxi(eye, int(pl.stat("secret_loot")))
    var ids: Array = []
    var cards: Array = []
    for i in SECRET_CARDS + eye:
        var rar := mini(maxi(Items.Rarity.RARE, Items.roll_rarity("boss", floor_number, luck)), Items.max_rarity_unlocked())
        var id := Drops.roll_item_at(rar, ids + _mod_ids(), "hidden", players)
        ids.append(id)
        cards.append(Items.offer(id, 0))
    if randf() < SECRET_WEAPON and not cards.is_empty():
        var wid := Drops.roll_gun(players, [], Items.roll_rarity("boss", floor_number, luck, true), Items.Rarity.RARE)
        if wid != "":
            cards[cards.size() - 1] = weapon_offer(wid, floor_number)
    for o in cards:
        o["group"] = "secret"
        r.stock.append(o)


## Bot probe `--challenge=timed|elite`: every floor has a challenge room of that kind.
static var force_challenge := ""


## Wares locked in the last floor's shop (Main sets it before generate; the shop takes them).
static var locked_in: Array = []


## Gun mod ids (kept out of item wares and reward cards: the fourth shop ware sells them).
static var _mods_cache: Array = []


static func _mod_ids() -> Array:
    if _mods_cache.is_empty():
        for id in Items.catalog.keys():
            if String(Items.catalog[id].get("slot", "")) == "mod":
                _mods_cache.append(id)
    return _mods_cache


## Fill a shop: wares locked in the last floor's shop first (`carried`, repriced for this
## floor), then item wares, the gun or mod ware, and the services.
static func stock_shop(r: RoomData, floor_number: int, luck: float, players: Array, carried: Array = []) -> void:
    for w in carried:
        var o: Dictionary = (w as Dictionary).duplicate()
        o["price"] = ware_price(o, floor_number)
        o["taken"] = false
        r.stock.append(o)
    var have_gunware := false
    var items := 0
    for o in r.stock:
        if o.get("gunware", false):
            have_gunware = true
        elif o.get("ware", false):
            items += 1
    var extra := 0   # Fortune resonance: a 5th ware
    for pl in players:
        if pl != null and is_instance_valid(pl):
            extra = maxi(extra, int(pl.stat("shop_wares")))
    while items < SHOP_ITEMS + extra:
        r.stock.append(roll_item_ware(floor_number, luck, r.stock, players, floor_number >= 2 and randf() < MYSTERY_CHANCE))
        items += 1
    if not have_gunware:
        r.stock.append(roll_gun_ware(floor_number, luck, r.stock, players))
    r.stock.append(offer("reroll", "", reroll_price(floor_number, 0)))
    r.stock.append(offer("carry", "", int(roundf(CARRY_PRICE * _m(floor_number))), 2))
    var rep := offer("repair", "", int(roundf(REPAIR_PRICE * _m(floor_number))), REPAIR_PCT)
    rep["pct"] = true
    r.stock.append(rep)
    var free_smith := floor_number <= int(Mastery.bonus("free_gunsmith"))
    r.stock.append(offer("gunsmith", "", 0 if free_smith else int(roundf(GUNSMITH_PRICE * _m(floor_number) * smith_factor(players)))))


## Arsenal expansion 3.4: the Gunsmith costs more for a rarer weapon. Priced when the shop
## opens, from the lowest-tier weapon it would raise.
static func smith_factor(players: Array) -> float:
    for pl in players:
        if pl == null or not is_instance_valid(pl):
            continue
        var best: Gun = null
        for g in pl.guns:
            if g.tier < Gun.MAX_TIER and (best == null or g.tier < best.tier):
                best = g
        if best != null:
            return float(Guns.SMITH_FACTOR[clampi(best.data.rarity, 0, 4)])
    return 1.0


## A weapon card: free (the caller prices it), at tier II now and then for a deep Common.
static func weapon_offer(id: String, floor_number: int) -> Dictionary:
    var o := offer("gun", id, 0)
    var t := Guns.deep_tier(Guns.rarity_of(id), floor_number)
    if t > 1:
        o["tier"] = t
    return o


## Price of a ware on `floor_number`: items by rarity, guns by weight, the mystery ware flat.
static func ware_price(o: Dictionary, floor_number: int) -> int:
    if o.get("mystery", false):
        return int(roundf(MYSTERY_PRICE * _m(floor_number)))
    if String(o["kind"]) == "gun":
        return gun_price(Guns.make(String(o["id"])), floor_number)
    return Items.price_at(int(Items.get_item(String(o["id"])).get("rarity", 0)), floor_number)


static func _on_offer(stock: Array) -> Array:
    var on_offer: Array = []
    for o in stock:
        if not o["taken"] and o["kind"] in ["gun", "item"]:
            on_offer.append(o["id"])
    return on_offer


static func roll_item_ware(floor_number: int, luck: float, stock: Array, players: Array, mystery: bool = false) -> Dictionary:
    var rar := Items.roll_rarity("shop", floor_number, luck)
    if mystery:
        rar = mini(Items.median_rarity(floor_number) + 1, Items.max_rarity_unlocked())
    var id := Drops.roll_item_at(rar, _on_offer(stock) + _mod_ids(), "shop", players)
    var o := Items.offer(id, 0)
    o["ware"] = true
    if mystery:
        o["mystery"] = true
    o["price"] = ware_price(o, floor_number)
    return o


static func roll_gun_ware(floor_number: int, luck: float, stock: Array, players: Array) -> Dictionary:
    var o: Dictionary = {}
    var on_offer := _on_offer(stock)
    var gun_id := ""
    if randf() < SHOP_GUN_SHARE:
        gun_id = Drops.roll_gun(players, on_offer, Items.roll_rarity("shop", floor_number, luck, true))
    if gun_id != "":
        o = weapon_offer(gun_id, floor_number)
    else:
        var rar := Items.roll_rarity("shop", floor_number, luck)
        var mods: Array = _mod_ids().filter(func(id): return int(Items.get_item(String(id)).get("rarity", 0)) <= rar and not on_offer.has(id))
        if mods.is_empty():
            mods = _mod_ids()
        o = Items.offer(String(mods.pick_random()), 0)
    o["ware"] = true
    o["gunware"] = true
    o["price"] = ware_price(o, floor_number)
    return o


## A fresh ware in place of `old` (a reroll): same kind of slot, new roll.
static func reroll_ware(old: Dictionary, floor_number: int, luck: float, stock: Array, players: Array) -> Dictionary:
    if old.get("gunware", false):
        return roll_gun_ware(floor_number, luck, stock, players)
    return roll_item_ware(floor_number, luck, stock, players, floor_number >= 2 and randf() < MYSTERY_CHANCE)


## Deal room stock: two Epic or Legendary cards, each with its own price kind, and the heal.
static func stock_deal(r: RoomData, floor_number: int, luck: float, players: Array) -> void:
    var kinds := ["hp", "money", "curse"]
    kinds.shuffle()
    var ids: Array = []
    var weapon_at := randi() % 2 if randf() < Guns.DEAL_WEAPON else -1
    for i in 2:
        var o: Dictionary = {}
        if i == weapon_at:
            var wid := Drops.roll_gun(players, [], Items.roll_rarity("deal", floor_number, luck, true), Items.Rarity.EPIC)
            if wid != "" and Guns.rarity_of(wid) >= Items.Rarity.EPIC:
                o = offer("gun", wid, 0)
        if o.is_empty():
            var rar := Items.roll_rarity("deal", floor_number, luck)
            var id := Drops.roll_item_at(rar, ids + _mod_ids(), "", players)
            ids.append(id)
            o = Items.offer(id, 0)
        o["group"] = "deal"
        o["deal"] = String(kinds[i])
        if o["deal"] == "curse":
            o["curse"] = String(Items.CURSES.keys().pick_random())
            o["curse_span"] = "run"
        r.stock.append(o)
    var heal := offer("repair", "", int(roundf(DEAL_HEAL_PRICE * _m(floor_number))), DEAL_HEAL_PCT)
    heal["pct"] = true
    r.stock.append(heal)


## Max health a deal card costs (Epic or Legendary).
static func deal_hp(o: Dictionary) -> int:
    var rar := Guns.rarity_of(String(o["id"])) if String(o.get("kind", "")) == "gun" else int(Items.get_item(String(o["id"])).get("rarity", 0))
    return DEAL_HP[1] if rar >= Items.Rarity.LEGENDARY else DEAL_HP[0]


## Scrap a money deal costs with `scrap` in hand.
static func deal_money(scrap: int, floor_number: int) -> int:
    return maxi(int(roundf(DEAL_MONEY_MIN * _m(floor_number))), int(roundf(float(scrap) * DEAL_MONEY_SHARE)))


## The deal room: a free grid cell beside the boss room, one door to it.
static func _place_deal_room(rooms: Dictionary) -> void:
    var boss := Vector2i(-99, -99)
    for p in rooms.keys():
        if (rooms[p] as RoomData).type == RoomData.Type.BOSS:
            boss = p
    if not rooms.has(boss):
        return
    var dirs := DIRS.duplicate()
    dirs.shuffle()
    for d in dirs:
        var c: Vector2i = boss + d
        if not _in_grid(c) or rooms.has(c):
            continue
        var deal := _new_room(c, RoomData.Type.DEAL)
        rooms[c] = deal
        rooms[boss].doors[d] = { "to": c, "obstacle": "" }
        deal.doors[-d] = { "to": boss, "obstacle": "" }
        return


## One shop ware (old balance): a gun or a piece of gear from the shop pool.
static func roll_ware(floor_number: int, luck: float, stock: Array, players: Array = []) -> Dictionary:
    var on_offer: Array = []
    for o in stock:
        if not o["taken"] and o["kind"] in ["gun", "item"]:
            on_offer.append(o["id"])
    var gun_id := Drops.roll_gun(players, on_offer) if randf() < 0.45 else ""
    var o: Dictionary
    if gun_id != "":
        o = offer("gun", gun_id, gun_price(Guns.make(gun_id), floor_number))
    else:
        var iid := Drops.roll_item(floor_number * 4, Items.Rarity.COMMON, on_offer, luck, "shop", players)
        o = Items.offer(iid, Items.price(Items.get_item(iid), floor_number * 4))
    o["ware"] = true
    return o


## Reroll cost. Core loop reset 6.3: (8 + 6 x n) x m, n the rerolls already made this visit.
static func reroll_price(floor_number: int, uses: int) -> int:
    if not Main.old_balance:
        return int(roundf(float(8 + 6 * uses) * _m(floor_number)))
    return 10 + floor_number * 6 + uses * (6 + floor_number * 3)


## Weapon price. Arsenal expansion 3.4: by rarity and weight (Guns.price); was
## (20 + 10 x weight) x m.
static func gun_price(data: GunData, floor_number: int) -> int:
    if not Main.old_balance:
        return Guns.price(data, floor_number)
    var base := 16 + data.weight * 9
    var diff := floor_number * 4
    return base + 2 * diff + int(float(base) * 0.10 * float(diff))


const BOONS := {
    "vitality": { "name": "Vitality", "desc": "+20 max HP for this run", "amount": 20 },
    "haul": { "name": "Pack Mule", "desc": "+2 carry capacity", "amount": 2 },
    "boiler": { "name": "Boiler", "desc": "+25 pressure limit", "amount": 25 },
    "hoard": { "name": "Hoard", "desc": "A pile of scrap", "amount": 60 },
}


## A run-long boon offer; bigger chests pay more.
static func boon_offer(tier: int) -> Dictionary:
    var id: String = BOONS.keys().pick_random()
    var o := offer("boon", id, 0, int(BOONS[id]["amount"] * (1.0 + 0.5 * float(tier - 1))))
    return o


static func offer(kind: String, id: String, price: int, amount: int = 0) -> Dictionary:
    return { "kind": kind, "id": id, "price": price, "amount": amount, "taken": false }


static func _new_room(pos: Vector2i, type: int) -> RoomData:
    var r := RoomData.new()
    r.pos = pos
    r.type = type
    return r


static func _in_grid(p: Vector2i) -> bool:
    return p.x >= 0 and p.y >= 0 and p.x < GRID and p.y < GRID


static func _neighbor_count(rooms: Dictionary, p: Vector2i) -> int:
    var n := 0
    for d in DIRS:
        if rooms.has(p + d):
            n += 1
    return n


static func _dist(a: Vector2i, b: Vector2i) -> int:
    return absi(a.x - b.x) + absi(a.y - b.y)
