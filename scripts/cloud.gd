class_name Cloud
extends Node2D
## A lingering patch of an element: keeps applying it to enemies inside while it lasts.
## Clouds merge with a nearby cloud of the same element and are capped in number, so a
## crowd full of reactions cannot snowball into hundreds of them.

const MAX_CLOUDS := 14
const MERGE_DISTANCE := 70.0

var element: int
var radius: float
var life: float
var potency: float
var source: Player
var cooldown := 0.0   # seconds until this cloud may react again
var _tick := 0.0
var _puff := 0.0


## Spawn a cloud, top up a nearby cloud of the same element, or react with a nearby
## cloud of a different element (two overlapping clouds are a reaction, not a stack).
static func spawn(parent: Node, pos: Vector2, p_element: int, p_radius: float, p_life: float, p_potency: float, p_source: Player) -> void:
    var tree := parent.get_tree()
    var clouds := tree.get_nodes_in_group("clouds")
    var oldest: Cloud = null
    for c in clouds:
        if not is_instance_valid(c):
            continue
        var near: bool = c.global_position.distance_to(pos) < MERGE_DISTANCE * 1.3
        if near and c.element == p_element:
            c.life = maxf(c.life, p_life)
            c.radius = maxf(c.radius, p_radius)
            c.potency = maxf(c.potency, p_potency)
            return
        if near and c.cooldown <= 0.0 and Elements.reaction_name(c.element, p_element) != "":
            Elements.react_cloud(c, p_element, p_potency, p_source)
            return
        if oldest == null or c.life < oldest.life:
            oldest = c
    if clouds.size() >= MAX_CLOUDS and oldest != null:
        oldest.queue_free()
    var cloud := Cloud.new(p_element, p_radius, p_life, p_potency, p_source)
    cloud.global_position = pos
    parent.add_child(cloud)


func _init(p_element: int, p_radius: float, p_life: float, p_potency: float, p_source: Player) -> void:
    element = p_element
    radius = p_radius
    life = p_life
    potency = p_potency
    source = p_source
    z_index = 3


func _ready() -> void:
    add_to_group("clouds")


## Become a cloud of another element after a reaction, and linger a little longer.
func transform_to(new_element: int) -> void:
    element = new_element
    life = maxf(life, 2.5)
    _tick = 0.0
    queue_redraw()


func _process(delta: float) -> void:
    life -= delta
    _tick -= delta
    _puff -= delta
    cooldown = maxf(0.0, cooldown - delta)
    if _tick <= 0.0:
        _tick = 0.6
        for e in get_tree().get_nodes_in_group("enemies"):
            if is_instance_valid(e) and not e.is_queued_for_deletion() and e.global_position.distance_to(global_position) <= radius:
                e.apply_element(element, potency, source if is_instance_valid(source) else null)
    if _puff <= 0.0:
        _puff = 0.15
        var scene := get_tree().current_scene
        if scene != null and "fx" in scene and scene.fx != null:
            var col: Color = Element.COLORS[element]
            var p := global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf() * radius * 0.8
            scene.fx.puff(Art.PARTICLES["smoke"], p, Color(col, 0.35), radius * 0.6, 0.8, false, Vector2(0, -15), 0.3)
    if life <= 0.0:
        queue_free()
    queue_redraw()


func _draw() -> void:
    var col: Color = Element.COLORS[element]
    draw_circle(Vector2.ZERO, radius, Color(col, 0.08))
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(col, 0.35), 2.0)
