class_name EnemyGrid
extends RefCounted
## Hit tests without physics: a spatial hash of the live enemies, rebuilt at most once per
## physics tick on first use, so a Projectile asks "which enemy bodies does my circle touch"
## with a dictionary lookup or two and distance checks instead of being an Area2D with its
## own physics pairs. The test is circle against the enemy's body radius (its CircleShape2D)
## at the position cached at the rebuild, as the physics step saw it.
##
## Also a per-tick cache of node groups (`nodes`): the obstacle, cloud and player lists that
## every projectile and enemy used to fetch from the tree each tick are fetched once.

const CELL := 128.0

static var _frame := -1
static var _ens: Array = []                  # live enemies this tick, index-aligned with:
static var _pos := PackedVector2Array()      # their positions at the rebuild
static var _rad := PackedFloat32Array()      # their body radii
static var _cells: Dictionary = {}           # int cell key -> Array of indices
static var _max_r := 0.0
static var _groups: Dictionary = {}   # StringName -> Array, for the frame in _group_frame
static var _group_frame := -1


static func _key(cx: int, cy: int) -> int:
    return (cy << 16) ^ (cx & 0xFFFF)


static func _rebuild(tree: SceneTree) -> void:
    _cells.clear()
    _ens.clear()
    _pos.clear()
    _rad.clear()
    _max_r = 0.0
    for n in nodes(tree, &"enemies"):
        if not is_instance_valid(n) or n.is_queued_for_deletion() or not n is Enemy:
            continue
        var e := n as Enemy
        var p := e.global_position
        var k := _key(floori(p.x / CELL), floori(p.y / CELL))
        var bucket: Array = _cells.get(k, [])
        if bucket.is_empty():
            _cells[k] = bucket
        bucket.append(_ens.size())
        _ens.append(e)
        _pos.append(p)
        _rad.append(e.radius)
        _max_r = maxf(_max_r, e.radius)


## Enemies whose body circle overlaps the circle (pos, r): positions as of this tick's
## rebuild (where the physics step used to see them).
static func overlapping(tree: SceneTree, pos: Vector2, r: float) -> Array:
    var f := Engine.get_physics_frames()
    if f != _frame:
        _frame = f
        _rebuild(tree)
    var out: Array = []
    if _ens.is_empty():
        return out
    var reach := r + _max_r
    var x0 := floori((pos.x - reach) / CELL)
    var x1 := floori((pos.x + reach) / CELL)
    var y0 := floori((pos.y - reach) / CELL)
    var y1 := floori((pos.y + reach) / CELL)
    for cy in range(y0, y1 + 1):
        for cx in range(x0, x1 + 1):
            var bucket: Variant = _cells.get(_key(cx, cy))
            if bucket == null:
                continue
            for k: int in bucket:
                var rr := r + _rad[k]
                if _pos[k].distance_squared_to(pos) < rr * rr and is_instance_valid(_ens[k]):
                    out.append(_ens[k])
    return out


## The nodes of a group, fetched from the tree once per physics tick and once per frame.
## Callers check is_instance_valid as before (a node freed this tick may still be listed).
static func nodes(tree: SceneTree, group: StringName) -> Array:
    var f := Engine.get_physics_frames() * 1000003 + Engine.get_process_frames()
    if f != _group_frame:
        _group_frame = f
        _groups.clear()
    var have: Variant = _groups.get(group)
    if have != null:
        return have
    var list := tree.get_nodes_in_group(group)
    _groups[group] = list
    return list
