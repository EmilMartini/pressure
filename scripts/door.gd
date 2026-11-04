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

var _blocker_shape: CollisionShape2D
var _lock: Sprite2D
var _armed := false   # ignore overlaps until the room has settled


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


func _on_obstacle_cleared() -> void:
    obstacle = null
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
    match state:
        State.LOCKED:
            draw_rect(r, Color(0.30, 0.09, 0.10))
            draw_rect(r.grow(-5.0), Color(0.6, 0.15, 0.15), false, 2.0)
        State.OPEN:
            draw_rect(r, Color(0.02, 0.02, 0.03))
            draw_rect(r.grow(-4.0), Color(0.55, 0.75, 0.7, 0.5), false, 2.0)
        State.OBSTACLE:
            draw_rect(r, Color(0.02, 0.02, 0.03))
