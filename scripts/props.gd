class_name Props
extends RefCounted
## Places environmental props (see Prop) in a room. Room calls `Props.dress(room)` once
## it is built. Placement is seeded per room and floor, so a room looks the same on every
## visit, and props broken earlier stay broken (RoomData meta "props_gone").

const CENTRE_CLEAR := 140.0    # the middle of the room stays open
const DOOR_CLEAR := 110.0      # well past the 60 px minimum: entering players land here
const SPACING := 76.0          # between props
const PEDESTAL_CLEAR := 80.0

## Kinds by the floor they first appear on.
const BY_FLOOR := [
    ["crate", "barrel", "brazier", "fountain"],
    ["poison_pot", "wind_chime"],
    ["ice_crystal", "acid_vat", "lightning_rod"],
    ["stone_pillar", "blood_altar"],
]

## Relative pick weights (missing = 1.0).
const WEIGHTS := { "crate": 2.5, "barrel": 1.6, "poison_pot": 1.3, "fountain": 0.8, "blood_altar": 0.6 }

## Safe rooms only get props that cannot hurt or summon on their own.
const SAFE_KINDS := ["crate", "fountain", "brazier", "wind_chime", "ice_crystal", "lightning_rod", "stone_pillar"]


static func unlocked_kinds(floor_number: int) -> Array:
    var out: Array = []
    for i in mini(maxi(1, floor_number), BY_FLOOR.size()):
        out.append_array(BY_FLOOR[i])
    return out


static func dress(room) -> void:
    if room == null or not is_instance_valid(room) or not "data" in room or not "rect" in room:
        return
    var data: RoomData = room.data
    if data == null:
        return
    var count_lo := 0
    var count_hi := 0
    match data.type:
        RoomData.Type.ARENA:
            count_lo = 2
            count_hi = 6
        RoomData.Type.SHOP, RoomData.Type.TREASURE:
            count_lo = 1
            count_hi = 2
        _:
            return
    var floor_number := 1
    if "main" in room and room.main != null and "floor_number" in room.main:
        floor_number = int(room.main.floor_number)
    var kinds := unlocked_kinds(floor_number)
    if data.type != RoomData.Type.ARENA:
        kinds = kinds.filter(func(k): return SAFE_KINDS.has(k))
    if kinds.is_empty():
        return

    var rng := RandomNumberGenerator.new()
    rng.seed = hash(data.pos) * 31 + floor_number * 104729 + 17
    # Arenas get busier deeper down: floor 1 up to 4, floor 3+ up to 6.
    var hi := mini(count_hi, count_lo + 1 + floor_number) if data.type == RoomData.Type.ARENA else count_hi
    var count := rng.randi_range(count_lo, hi)

    var rect: Rect2 = room.rect
    var inner := rect.grow(-80.0)
    var doors: Array[Vector2] = []
    if room.has_method("door_world_position"):
        for d in data.doors.keys():
            var dp: Vector2 = room.door_world_position(d)
            doors.append((room as Node2D).to_local(dp) if room is Node2D else dp)
    var blocked: Array[Vector2] = []
    if "pedestals" in room:
        for p in room.pedestals:
            if is_instance_valid(p) and p is Node2D:
                blocked.append((p as Node2D).position)
    for o in data.stock:
        if o is Dictionary and o.has("pos"):
            blocked.append(o["pos"])

    var holder := Node2D.new()
    holder.name = "Props"
    room.add_child(holder)
    var gone: Array = data.get_meta("props_gone", [])
    var placed: Array[Vector2] = []
    for slot in count:
        var kind := _pick(kinds, rng)
        var pos := Vector2.ZERO
        var found := false
        for attempt in 40:
            var p := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
            if _ok(p, data.type, doors, blocked, placed):
                pos = p
                found = true
                break
        if not found:
            continue
        placed.append(pos)
        if gone.has(slot):
            continue   # broken on an earlier visit
        var prop := Prop.new(kind)
        prop.slot = slot
        prop.room = room
        prop.position = pos
        holder.add_child(prop)


static func _pick(kinds: Array, rng: RandomNumberGenerator) -> String:
    var total := 0.0
    for k in kinds:
        total += float(WEIGHTS.get(k, 1.0))
    var roll := rng.randf() * total
    for k in kinds:
        roll -= float(WEIGHTS.get(k, 1.0))
        if roll <= 0.0:
            return String(k)
    return String(kinds[kinds.size() - 1])


static func _ok(p: Vector2, type: int, doors: Array[Vector2], blocked: Array[Vector2], placed: Array[Vector2]) -> bool:
    if p.length() < CENTRE_CLEAR:
        return false
    # The pedestal / stairs row runs across the room at y ~ 90.
    if absf(p.y - 90.0) < 80.0 and absf(p.x) < 460.0:
        return false
    for d in doors:
        if p.distance_to(d) < DOOR_CLEAR:
            return false
        # Keep the straight lane from each door to the centre clear too.
        var lane := d.normalized()
        if p.dot(lane) > 0.0 and absf(p.dot(lane.orthogonal())) < 70.0:
            return false
    for b in blocked:
        if p.distance_to(b) < PEDESTAL_CLEAR:
            return false
    for q in placed:
        if p.distance_to(q) < SPACING:
            return false
    match type:
        RoomData.Type.SHOP:
            # Counter along the back wall and the side shelves: props go in the lower corners.
            if p.y < -150.0 or absf(p.x) < 300.0 or absf(p.x) > 440.0:
                return false
        RoomData.Type.TREASURE:
            if p.distance_to(Vector2(0, -170)) < 200.0 or absf(p.x) < 280.0:
                return false
    return true
