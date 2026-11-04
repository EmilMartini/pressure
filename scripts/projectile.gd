class_name Projectile
extends Area2D
## A bullet. Deals raw damage, then applies its element (which may react).

const LAYER_ENEMIES := 2

var velocity := Vector2.ZERO
var damage := 1.0
var element: int = Element.Kind.NONE
var potency := 1.0
var lifetime := 1.0
var pierce := 0
var radius := 4.0
var color := Color.WHITE
var manual := false
var shooter: Player = null

var _hit: Dictionary = {}


func _ready() -> void:
    collision_layer = 0
    collision_mask = LAYER_ENEMIES | Obstacle.LAYER_OBSTACLES
    monitorable = false
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    add_child(shape)
    body_entered.connect(_on_body_entered)
    z_index = 5


func _physics_process(delta: float) -> void:
    position += velocity * delta
    lifetime -= delta
    for ob in get_tree().get_nodes_in_group("obstacles"):
        if is_instance_valid(ob) and not ob.is_queued_for_deletion() and ob.overlaps(global_position, radius):
            _on_body_entered(ob)
            return
    if lifetime <= 0.0:
        if manual and shooter != null and _hit.is_empty():
            shooter.on_projectile_missed()
        queue_free()


func _draw() -> void:
    draw_circle(Vector2.ZERO, radius, color)
    draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 1, 1, 0.8))


func _on_body_entered(body: Node) -> void:
    if body is Obstacle:
        body.apply_element(element, potency)
        if shooter != null:
            shooter.on_projectile_hit(manual)
        queue_free()
        return
    if not body is Enemy or _hit.has(body):
        return
    var enemy := body as Enemy
    _hit[enemy] = true
    var raw := damage
    if enemy.immune_to == element:
        raw = 0.0
    enemy.take_damage(raw, color)
    if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
        enemy.apply_element(element, potency)
    if shooter != null:
        shooter.on_projectile_hit(manual)
    if pierce > 0:
        pierce -= 1
    else:
        queue_free()
