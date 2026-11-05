class_name SecretWall
extends StaticBody2D
## A stretch of wall that is not quite wall: the way into a hidden room (filling a door
## gap, kind "door") or the front of a secret alcove inside a room (kind "alcove"). It is
## drawn with the same bricks as the walls around it, lined up with them. The tells only
## show up close: a hairline crack that breathes a few dust motes into the room every few
## seconds, bricks a shade off, a hollow thunk when a shot lands on it, and the crack
## lighting up in the colour of whatever element splashes it. It gives way to one method:
##   roots   fire burns away the roots choking it (a hot vent counts)
##   frozen  ice, then stone within a few seconds, shatters it
##   acid    acid dissolves it
##   rusted  shock blows the rusted gate
##   mud     water erodes it (three soakings, or a puddle against it)
##   blast   any explosion: a vent of either kind, a barrel, a bomber, a reaction burst
##   rubble  (alcove fronts) any explosion, or two stone hits
## Nothing on screen names the method; the brick tint and crack colour hint at it.

signal cleared

const METHODS := {
    "roots": { "tint": Color(0.36, 0.40, 0.31), "crack": Color(0.13, 0.20, 0.08) },
    "frozen": { "tint": Color(0.39, 0.38, 0.44), "crack": Color(0.40, 0.55, 0.66) },
    "acid": { "tint": Color(0.43, 0.40, 0.31), "crack": Color(0.25, 0.28, 0.10) },
    "rusted": { "tint": Color(0.47, 0.33, 0.29), "crack": Color(0.30, 0.13, 0.07) },
    "mud": { "tint": Color(0.43, 0.34, 0.30), "crack": Color(0.19, 0.13, 0.09) },
    "blast": { "tint": Color(0.41, 0.33, 0.35), "crack": Color(0.09, 0.07, 0.08) },
    "rubble": { "tint": Color(0.41, 0.34, 0.34), "crack": Color(0.09, 0.07, 0.08) },
}
## Methods a hidden-room wall can use, with the elements the party needs for each.
const WALL_METHODS := {
    "roots": [Element.Kind.FIRE],
    "frozen": [Element.Kind.ICE, Element.Kind.STONE],
    "acid": [Element.Kind.ACID],
    "rusted": [Element.Kind.SHOCK],
    "mud": [Element.Kind.WET],
    "blast": [],
}
const BLAST_MIN := 90.0   # novas this big count as an explosion

var kind := "door"
var method := "blast"
var size := Vector2(150, 60)     # read by Materials._touch_obstacles too
var inward := Vector2.DOWN       # toward the room the tells show in

var _done := false
var _hits := 0
var _iced := 0.0
var _glow := 0.0
var _glow_col := Color.WHITE
var _dust_t := 2.0
var _thunk_cd := 0.0
var _crack := PackedVector2Array()
var _branch := PackedVector2Array()
var _over: Node2D
var _last_nova := Vector2.INF


func _init(p_kind: String, p_method: String, p_size: Vector2, p_inward: Vector2) -> void:
    kind = p_kind
    method = p_method if METHODS.has(p_method) else "blast"
    size = p_size
    inward = p_inward
    name = "SecretWall"


## The method a hidden-room wall uses this floor: one the party can manage, never empty.
static func pick_method(party: Array, rng: RandomNumberGenerator) -> String:
    var opts: Array = []
    for m in WALL_METHODS.keys():
        var ok := true
        for el in WALL_METHODS[m]:
            if not party.has(el):
                ok = false
        if ok:
            opts.append(m)
            if m == "roots":
                opts.append(m)   # fire is the classic: a little more often
    if opts.is_empty():
        return "blast"
    return String(opts[rng.randi() % opts.size()])


func _ready() -> void:
    add_to_group("obstacles")
    add_to_group("secret_walls")
    collision_layer = Player.LAYER_WALLS | Obstacle.LAYER_OBSTACLES
    collision_mask = 0
    var shape := CollisionShape2D.new()
    var r := RectangleShape2D.new()
    r.size = size
    shape.shape = r
    add_child(shape)
    var spec: Dictionary = METHODS[method]
    # The theme's wall tiles lined up with the world, picking the same variants as the
    # wall around it (Themes.wall_fill hashes world cells with the theme's wall seed), a
    # shade off: the method's tint relative to the old brick tint, at the same strength.
    var cam := get_viewport().get_camera_2d()
    var shade: Color = spec["tint"]
    var rel := Color(shade.r / Art.WALL_TINT.r, shade.g / Art.WALL_TINT.g, shade.b / Art.WALL_TINT.b)
    var fill := Themes.wall_fill(Rect2(-size / 2.0, size), cam.zoom.x if cam != null else 1.3, Color.WHITE.lerp(rel, 0.55))
    add_child(fill)
    _over = Node2D.new()
    _over.name = "Crack"
    _over.draw.connect(_draw_over)
    add_child(_over)
    _make_crack()
    _dust_t = randf_range(1.0, 3.0)
    Elements.nova.connect(_on_nova)
    Elements.reaction_fired.connect(_on_reaction)


func _make_crack() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(Vector2i(global_position.round()))
    var along := Vector2(1, 0) if size.x >= size.y else Vector2(0, 1)
    var across := along.orthogonal()
    var length := maxf(size.x, size.y) * 0.62
    var n := 7
    var off := 0.0
    for i in n + 1:
        var t := float(i) / float(n) - 0.5
        off = clampf(off + rng.randf_range(-3.0, 3.0), -minf(size.x, size.y) * 0.25, minf(size.x, size.y) * 0.25)
        _crack.append((along * t * length + across * off).round())
    var k := rng.randi_range(2, n - 2)
    _branch.append(_crack[k])
    _branch.append((_crack[k] + across * rng.randf_range(6.0, 10.0) * (1.0 if rng.randf() < 0.5 else -1.0) + along * 5.0).round())


## Projectiles test against obstacles through this (see Projectile). A shot that lands on
## the wall gets a hollow thunk back.
func overlaps(point: Vector2, margin: float) -> bool:
    if _done:
        return false
    var local := to_local(point)
    var hit := Rect2(-size / 2.0 - Vector2(margin, margin), size + Vector2(margin, margin) * 2.0).has_point(local)
    if hit and _thunk_cd <= 0.0:
        _thunk_cd = 0.35
        Sfx.play("door_lock", -14.0, 0.05)
    return hit


## An element lands on the wall: from a shot, a lobbed shell, or the floor beside it.
func apply_element(element: int, _potency: float = 1.0, _dir: Vector2 = Vector2.ZERO) -> bool:
    if _done or element == Element.Kind.NONE:
        return false
    _flash(Element.COLORS.get(element, Color.WHITE))
    match method:
        "roots":
            if element == Element.Kind.FIRE:
                _open()
        "acid":
            if element == Element.Kind.ACID:
                _open()
        "rusted":
            if element == Element.Kind.SHOCK:
                _open()
        "mud":
            if element == Element.Kind.WET:
                _hits += 1
                if _hits >= 3:
                    _open()
        "frozen":
            if element == Element.Kind.ICE:
                _iced = 6.0
            elif element == Element.Kind.STONE and _iced > 0.0:
                _open()
        "rubble":
            if element == Element.Kind.STONE:
                _hits += 1
                if _hits >= 2:
                    _open()
    return true


func is_open() -> bool:
    return _done


func _flash(c: Color) -> void:
    _glow = 0.45
    _glow_col = c


func _dist_to(p: Vector2) -> float:
    var local := to_local(p)
    var half := size / 2.0
    var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
    return closest.distance_to(local)


func _on_nova(pos: Vector2, radius: float, color: Color) -> void:
    if _done or radius < BLAST_MIN or _dist_to(pos) > radius * 0.9:
        return
    _last_nova = pos
    if method == "blast" or method == "rubble":
        _open()
        return
    _flash(Color(color, 1.0))


## A vent's nova arrives first (above), then its name: a hot vent is fire, a cold one ice.
func _on_reaction(reaction_name: String, pos: Vector2, _col: Color) -> void:
    if _done or _last_nova == Vector2.INF or pos.distance_to(_last_nova) > 2.0:
        return
    if reaction_name == "Fire Nova":
        apply_element(Element.Kind.FIRE)
    elif reaction_name == "Frost Nova":
        apply_element(Element.Kind.ICE)


func _process(delta: float) -> void:
    if _done:
        return
    _thunk_cd = maxf(0.0, _thunk_cd - delta)
    _iced = maxf(0.0, _iced - delta)
    if _glow > 0.0:
        _glow = maxf(0.0, _glow - delta)
        _over.queue_redraw()
    _dust_t -= delta
    if _dust_t <= 0.0:
        _dust_t = randf_range(2.5, 5.5)
        _breathe()


## The draft: a few motes of dust drift out of the crack into the room.
func _breathe() -> void:
    var fx := _fx()
    if fx == null or _crack.is_empty():
        return
    var depth := absf(size.dot(inward.abs())) * 0.5
    for n in randi_range(1, 3):
        var at: Vector2 = _crack[randi() % _crack.size()]
        var p := global_position + at + inward * (depth - 2.0)
        var v := inward * randf_range(7.0, 16.0) + inward.orthogonal() * randf_range(-5.0, 5.0)
        fx._px(p, v, randf_range(1.4, 2.2), 2.0, 0.32, Fx.B.DRIFT, Element.Kind.STONE, false, Vector2(randf() * TAU, 0))


func _open() -> void:
    if _done:
        return
    _done = true
    remove_from_group("obstacles")
    remove_from_group("secret_walls")
    var gp := global_position
    if kind == "door":
        Elements.reaction_fired.emit("Path opened!", gp, Color.WHITE)
    else:
        Sfx.play("path_open")
    Sfx.play("wall_reveal", 0.0, 0.03)   # the rumble of falling masonry
    var fx := _fx()
    if fx != null:
        var span := maxf(size.x, size.y)
        fx.smoke(gp + inward * 10.0, 26, span * 0.45, Fx.PAL_SMOKE)
        fx.shards(gp, 10, 22.0, Element.Kind.STONE)
        fx.pixels(Element.Kind.STONE, gp + inward * 12.0, 18, 140.0, span * 0.3)
    var scene := get_tree().current_scene
    if scene != null and scene.has_method("shake"):
        scene.shake(7.0)
    cleared.emit()
    queue_free()


func _fx() -> Fx:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        var f: Variant = scene.get("fx")
        if f is Fx and is_instance_valid(f):
            return f as Fx
    return null


func _draw_over() -> void:
    var spec: Dictionary = METHODS[method]
    var c: Color = spec["crack"]
    _over.draw_polyline(_crack, Color(c, 0.55), 1.0)
    _over.draw_line(_branch[0], _branch[1], Color(c, 0.4), 1.0)
    if _iced > 0.0:
        _over.draw_polyline(_crack, Color(Element.COLORS[Element.Kind.ICE], 0.5), 1.0)
    if _glow > 0.0:
        var a := clampf(_glow / 0.45, 0.0, 1.0)
        _over.draw_polyline(_crack, Color(_glow_col, 0.35 * a), 4.0)
        _over.draw_polyline(_crack, Color(_glow_col.lightened(0.4), 0.95 * a), 1.5)
        _over.draw_line(_branch[0], _branch[1], Color(_glow_col, 0.8 * a), 1.0)
