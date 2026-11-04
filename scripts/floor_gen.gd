class_name FloorGen
extends RefCounted
## Generates an Isaac-style floor: a tree of rooms on a grid, specials on dead ends,
## and a hidden room reachable only through an elemental obstacle.

const GRID := 9
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const OBSTACLES := ["pool", "thicket", "valve", "ward", "rubble", "miasma"]


static func generate(floor_number: int, luck: float = 0.0) -> Dictionary:
    var target := 7 + floor_number * 2
    var start := Vector2i(GRID / 2, GRID / 2)
    var rooms: Dictionary = {}
    for attempt in 60:
        rooms = _grow(start, target)
        if rooms.size() >= target:
            break

    # Plain doors between every adjacent pair (the growth rule keeps it a tree).
    for p in rooms.keys():
        for d in DIRS:
            if rooms.has(p + d):
                rooms[p].doors[d] = { "to": p + d, "obstacle": "" }

    # Dead ends, farthest first, become the special rooms.
    var leaves: Array = []
    for p in rooms.keys():
        if p != start and rooms[p].doors.size() == 1:
            leaves.append(p)
    leaves.sort_custom(func(a, b): return _dist(a, start) > _dist(b, start))
    var fallback: Array = []
    for p in rooms.keys():
        if p != start and not leaves.has(p):
            fallback.append(p)
    fallback.sort_custom(func(a, b): return _dist(a, start) > _dist(b, start))
    var candidates: Array = leaves + fallback
    var specials := [RoomData.Type.BOSS, RoomData.Type.TREASURE, RoomData.Type.SHOP]
    if Progress.has("room:challenge"):
        specials.append(RoomData.Type.CHALLENGE)
    for i in mini(specials.size(), candidates.size()):
        rooms[candidates[i]].type = specials[i]

    _place_hidden_room(rooms, start)
    _stock_rooms(rooms, floor_number, luck)

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
    from.doors[-d] = { "to": best, "obstacle": unlocked_obstacles().pick_random() }
    hidden.doors[d] = { "to": best + d, "obstacle": "" }


## Obstacle kinds the save has unlocked; the pool is always available.
static func unlocked_obstacles() -> Array:
    var out: Array = []
    for kind in OBSTACLES:
        if Progress.has("obstacle:" + kind):
            out.append(kind)
    if out.is_empty():
        out.append("pool")
    return out


static func _stock_rooms(rooms: Dictionary, floor_number: int, luck: float = 0.0) -> void:
    for p in rooms.keys():
        var r: RoomData = rooms[p]
        match r.type:
            RoomData.Type.SHOP:
                # Brotato shop: four wares (guns or gear) you can reroll for scrap, then one
                # of each service. Wares carry "ware" so a reroll knows what to replace.
                var slots := 4 if Progress.has("shop:extra") else 3
                for i in slots:
                    r.stock.append(roll_ware(floor_number, luck, r.stock))
                r.stock.append(offer("reroll", "", reroll_price(floor_number, 0)))
                r.stock.append(offer("carry", "", 50 + floor_number * 18, 2))
                r.stock.append(offer("repair", "", 24 + floor_number * 10, 40))
                r.stock.append(offer("gunsmith", "", 45 + floor_number * 20))
            RoomData.Type.TREASURE:
                # A chest, Slay the Spire style: one pick from gear, a gun, or a run boon.
                # Chest size grows with the floor and a little luck.
                var tier := floor_number + (1 if randf() < 0.3 else 0)
                var min_rarity: int = clampi(tier, Items.Rarity.UNCOMMON, Items.Rarity.EPIC)
                r.stock.append(Items.offer(Items.roll(floor_number * 4 + tier * 2, maxi(min_rarity, Items.pool_min_rarity("treasure")), [], luck, "treasure"), 0))
                var pool: Array = Guns.ids()
                if not pool.is_empty():
                    r.stock.append(offer("gun", pool.pick_random(), 0))
                r.stock.append(boon_offer(tier))
                r.chest_tier = tier
            RoomData.Type.HIDDEN:
                r.stock.append(offer("carry", "", 0, 3))
                r.stock.append(Items.offer(Items.roll(floor_number * 4 + 4, Items.Rarity.RARE, [], luck, "hidden"), 0))
                r.loose_scrap = 20 + floor_number * 10
            RoomData.Type.CHALLENGE:
                r.stock.append(offer("sigil", "", 0))


## One shop ware: a gun (unlocked, not already on offer) or a piece of gear from the shop pool.
static func roll_ware(floor_number: int, luck: float, stock: Array) -> Dictionary:
    var on_offer: Array = []
    for o in stock:
        if not o["taken"] and o["kind"] in ["gun", "item"]:
            on_offer.append(o["id"])
    var guns: Array = Guns.ids().filter(func(id): return not on_offer.has(id))
    var o: Dictionary
    if randf() < 0.45 and not guns.is_empty():
        var id: String = guns.pick_random()
        o = offer("gun", id, gun_price(Guns.make(id), floor_number))
    else:
        var iid := Items.roll(floor_number * 4, Items.Rarity.COMMON, on_offer, luck, "shop")
        o = Items.offer(iid, Items.price(Items.get_item(iid), floor_number * 4))
    o["ware"] = true
    return o


## Reroll cost: Brotato's shape, a floor-based start that climbs with every use.
static func reroll_price(floor_number: int, uses: int) -> int:
    return 10 + floor_number * 6 + uses * (6 + floor_number * 3)


## Brotato's shape: base + difficulty + 8% of base per difficulty step.
static func gun_price(data: GunData, floor_number: int) -> int:
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
