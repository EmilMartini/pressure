class_name EnemyProjectile
extends Node2D
## A shot fired by an enemy: flies straight, hits the nearest living player it touches,
## and is gone at the end of its life or when it leaves the room.

const TRAIL_POINTS := 6
const DEFAULT_COLOR := Color(1.0, 0.40, 0.30)

var damage := 6.0
var speed := 240.0
var element: int = Element.Kind.NONE
var lifetime := 3.0
var radius := 6.0
var direction := Vector2.RIGHT
var owner_enemy: Node2D = null
## Room floor in global coordinates. Left empty, it is taken from the parent's `rect`
## (a Room keeps its floor as a local Rect2) when the shot enters the tree.
var room_rect := Rect2()

var _trail: Array[Vector2] = []
var _age := 0.0


func _ready() -> void:
    add_to_group("enemy_projectiles")
    z_index = 9
    if not room_rect.has_area():
        var parent := get_parent()
        if parent is Node2D and "rect" in parent:
            var r = parent.rect
            if r is Rect2:
                var rr: Rect2 = r
                room_rect = Rect2((parent as Node2D).global_position + rr.position, rr.size)


func color() -> Color:
    if element == Element.Kind.NONE:
        return DEFAULT_COLOR
    return Element.COLORS.get(element, DEFAULT_COLOR)


func _physics_process(delta: float) -> void:
    _age += delta
    lifetime -= delta
    _trail.push_front(global_position)
    if _trail.size() > TRAIL_POINTS:
        _trail.pop_back()
    global_position += direction * speed * delta
    if lifetime <= 0.0:
        queue_free()
        return
    if room_rect.has_area() and not room_rect.grow(radius).has_point(global_position):
        queue_free()
        return
    var rm := Room.here
    if rm != null and rm.has_walls and rm.blocks_shot(global_position):
        var sc := get_tree().current_scene
        if sc != null and "fx" in sc and sc.fx != null:
            sc.fx.puff(Art.PARTICLES["circle"], global_position, Color(color(), 0.5), radius * 3.0, 0.2, true)
        queue_free()
        return
    var hit: Player = null
    var best := INF
    for p in get_tree().get_nodes_in_group("players"):
        if not is_instance_valid(p) or not p.alive:
            continue
        var d: float = p.global_position.distance_to(global_position)
        if d <= radius + 10.0 and d < best:
            best = d
            hit = p
    if hit != null:
        var attacker: Node2D = owner_enemy if is_instance_valid(owner_enemy) else null
        Telemetry.hurt_hint = "projectile:" + (Telemetry.enemy_label(attacker) if attacker != null else "unknown")
        hit.take_damage(damage, attacker)
        var scene := get_tree().current_scene
        if scene != null and "fx" in scene and scene.fx != null:
            scene.fx.puff(Art.PARTICLES["circle"], global_position, Color(color(), 0.7), radius * 4.0, 0.25, true)
        queue_free()
        return
    queue_redraw()


func _draw() -> void:
    var c := color()
    # Trail: fading dots back along the path.
    for i in _trail.size():
        var k := 1.0 - float(i + 1) / float(TRAIL_POINTS + 1)
        draw_circle(to_local(_trail[i]), radius * (0.3 + 0.6 * k), Color(c, 0.45 * k))
    # Glow, body, hot core.
    var pulse := 1.0 + 0.15 * sin(_age * 18.0)
    draw_circle(Vector2.ZERO, radius * 2.2 * pulse, Color(c, 0.18))
    draw_circle(Vector2.ZERO, radius * 1.4, Color(c, 0.45))
    draw_circle(Vector2.ZERO, radius, c)
    draw_circle(Vector2.ZERO, radius * 0.45, Color(1, 1, 1, 0.85))
