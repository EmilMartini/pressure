class_name Door
extends Area2D
## A doorway in a room wall. Locked while a fight runs, open when the room is clear,
## or blocked by an elemental Obstacle on the way to a hidden room.

signal entered(dir: Vector2i)
signal obstacle_cleared(dir: Vector2i)

enum State { LOCKED, OPEN, OBSTACLE }

var dir: Vector2i
var state: int = State.OPEN
var size: Vector2
var obstacle: Obstacle = null
var secret: SecretWall = null   # a hidden room's way in, looking like plain wall
var opened_by := ""             # how the secret wall gave way: "blast", "dash" or an element

var _blocker_shape: CollisionShape2D
var _lock: Sprite2D
var _armed := false   # ignore overlaps until the room has settled
## Fun pass 1: the doorway into a floor's unvisited item room glows gold, a reward in sight.
var treasure := false
var _glow_t := 0.0


func _init(p_dir: Vector2i, gap: float, depth: float) -> void:
    dir = p_dir
    size = Vector2(gap, depth) if dir.y != 0 else Vector2(depth, gap)
    name = "Door_%d_%d" % [dir.x, dir.y]


func _ready() -> void:
    collision_layer = 0
    collision_mask = Player.LAYER_PLAYERS
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = size
    shape.shape = rect
    add_child(shape)
    body_entered.connect(_on_body_entered)

    var blocker := StaticBody2D.new()
    blocker.collision_layer = Player.LAYER_WALLS
    blocker.collision_mask = 0
    _blocker_shape = CollisionShape2D.new()
    var brect := RectangleShape2D.new()
    brect.size = size
    _blocker_shape.shape = brect
    blocker.add_child(_blocker_shape)
    add_child(blocker)
    _lock = Art.sprite(Art.TILES["lock"], 2.0, Color(0.85, 0.3, 0.3))
    add_child(_lock)
    _apply()
    # Rooms all live at the origin, so a player who just walked through a door is
    # still standing where this room's matching door is until the teleport lands.
    get_tree().create_timer(0.3).timeout.connect(func(): _armed = true)


func set_state(s: int) -> void:
    var was := state
    state = s
    _apply()
    if not is_inside_tree() or was == s:
        return
    if s == State.LOCKED:
        Sfx.play("door_lock")
        _lock.scale = Vector2(3.2, 3.2)
        _lock.modulate.a = 1.0
        create_tween().tween_property(_lock, "scale", Vector2(2.0, 2.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    elif was == State.LOCKED and s == State.OPEN:
        Sfx.play("door_open")
        _lock.visible = true
        var tw := create_tween()
        tw.tween_property(_lock, "modulate:a", 0.0, 0.35)
        tw.parallel().tween_property(_lock, "scale", Vector2(2.8, 2.8), 0.35)
        tw.tween_callback(func(): _lock.visible = state == State.LOCKED)


func set_obstacle(kind: String) -> void:
    state = State.OBSTACLE
    obstacle = Obstacle.new(kind, size, -Vector2(dir))
    add_child(obstacle)
    obstacle.cleared.connect(_on_obstacle_cleared)
    _apply()


## The doorway is bricked over by a SecretWall until the right element opens it.
func set_secret(method: String) -> void:
    state = State.OBSTACLE
    secret = SecretWall.new("door", method, size, -Vector2(dir))
    add_child(secret)
    secret.cleared.connect(_on_obstacle_cleared)
    _apply()


func _on_obstacle_cleared() -> void:
    if secret != null:
        opened_by = secret.opened_by
    obstacle = null
    secret = null
    set_state(State.OPEN)
    obstacle_cleared.emit(dir)


func _apply() -> void:
    if _blocker_shape != null:
        _blocker_shape.set_deferred("disabled", state != State.LOCKED)
    if _lock != null:
        _lock.visible = state == State.LOCKED
    queue_redraw()


func _on_body_entered(body: Node) -> void:
    if not _armed or state != State.OPEN or not body is Player or not body.alive:
        return
    # Trust the body's current position, not a stale overlap from before a teleport.
    var area := Rect2(global_position - size / 2.0, size).grow(18.0)
    if area.has_point(body.global_position):
        entered.emit(dir)


func _process(delta: float) -> void:
    if treasure:
        _glow_t += delta
        queue_redraw()


func _physics_process(_delta: float) -> void:
    # A player who walks into an open doorway after it armed also counts, even if the
    # overlap began earlier (for example while the door was still locked).
    if not _armed or state != State.OPEN:
        return
    var area := Rect2(global_position - size / 2.0, size)
    for body in get_overlapping_bodies():
        if body is Player and body.alive and area.has_point(body.global_position):
            entered.emit(dir)
            return


func _draw() -> void:
    var r := Rect2(-size / 2.0, size)
    if treasure:
        var k := 0.5 + 0.5 * sin(_glow_t * 3.0)
        draw_rect(r.grow(10.0), Color(1.0, 0.8, 0.3, 0.10 + 0.08 * k))
        draw_rect(r.grow(4.0), Color(1.0, 0.85, 0.4, 0.22 + 0.12 * k))
    match state:
        State.LOCKED:
            draw_rect(r, Color(0.02, 0.02, 0.03))
            _draw_gate("locked")
        State.OPEN:
            draw_rect(r, Color(0.02, 0.02, 0.03))
            _draw_gate("open")
        State.OBSTACLE:
            if secret == null:
                draw_rect(r, Color(0.02, 0.02, 0.03))
                _draw_gate("open")


## The theme's gate across the doorway (see Themes.door_tiles), one texel per pixel cell:
## the left and right tiles give their outer halves (the frame), the middle tile its full
## width; the depth crops the tile's foot. Side doors use the vertical gate tiles.
func _draw_gate(kind: String) -> void:
    var horizontal := dir.y != 0
    var tiles: Array = Themes.door_tiles(horizontal, kind)
    var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
    var tx := Themes.texel(cam.zoom.x if cam != null else 1.3)
    var tint: Color = Themes.def()["door_tint"]
    var along := (size.x if horizontal else size.y) / tx      # texels across the gap
    var depth := minf(32.0, (size.y if horizontal else size.x) / tx)
    var mid := minf(32.0, along)
    var edge := maxf(0.0, (along - mid) / 2.0)
    var parts := [[tiles[0], 0.0, edge], [tiles[1], 16.0 - mid / 2.0, mid], [tiles[2], 32.0 - edge, edge]]
    var at := -along / 2.0
    var c0 := (32.0 - depth) / 2.0   # side gates: the centred columns
    for part in parts:
        var w: float = part[2]
        if w > 0.01:
            var t: Texture2D = part[0]
            var s0: float = part[1]
            if horizontal:
                draw_texture_rect_region(t, Rect2(Vector2(at, -depth / 2.0) * tx, Vector2(w, depth) * tx), Rect2(s0, 0.0, w, depth), tint)
            else:
                draw_texture_rect_region(t, Rect2(Vector2(-depth / 2.0, at) * tx, Vector2(depth, w) * tx), Rect2(c0, s0, depth, w), tint)
        at += w
