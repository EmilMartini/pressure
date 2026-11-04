class_name Obstacle
extends StaticBody2D
## Blocks a doorway until the right element, or the right reaction, lands on it.
## Reactions are a traversal tool, not just damage.

signal cleared

const LAYER_OBSTACLES := 8

const KINDS := {
    "pool": {
        "label": "Deep water. Freeze it to cross.",
        "element": Element.Kind.ICE,
        "reaction": "",
        "color": Color(0.15, 0.40, 0.85),
    },
    "thicket": {
        "label": "Thorny thicket. Burn it down.",
        "element": Element.Kind.FIRE,
        "reaction": "",
        "color": Color(0.25, 0.55, 0.20),
    },
    "valve": {
        "label": "Rusted valve. Steam it open (Wet, then Fire).",
        "element": Element.Kind.NONE,
        "reaction": "Steam",
        "color": Color(0.45, 0.42, 0.40),
    },
}

var kind: String
var size: Vector2
var inward: Vector2
var states: Dictionary = {}


func _init(p_kind: String, p_size: Vector2, p_inward: Vector2) -> void:
    kind = p_kind
    size = p_size
    inward = p_inward
    name = "Obstacle"


func _ready() -> void:
    collision_layer = Player.LAYER_WALLS | LAYER_OBSTACLES
    collision_mask = 0
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = size
    shape.shape = rect
    add_child(shape)


func apply_element(element: int, _potency: float) -> void:
    var spec: Dictionary = KINDS[kind]
    if spec["reaction"] != "":
        for existing in states.keys():
            if existing != element and Elements.reaction_name(existing, element) == spec["reaction"]:
                _clear()
                return
        states[element] = 6.0
    elif element == spec["element"]:
        _clear()
    queue_redraw()


func _process(delta: float) -> void:
    for k in states.keys():
        states[k] -= delta
        if states[k] <= 0.0:
            states.erase(k)
            queue_redraw()


func _clear() -> void:
    Elements.reaction_fired.emit("Path opened!", global_position, Color.WHITE)
    Elements.nova.emit(global_position, 120.0, Color(1, 1, 1, 0.6))
    cleared.emit()
    queue_free()


func _draw() -> void:
    var spec: Dictionary = KINDS[kind]
    var r := Rect2(-size / 2.0, size)
    draw_rect(r, spec["color"])
    match kind:
        "pool":
            for i in 3:
                var y := -size.y / 3.0 + float(i) * size.y / 3.0
                draw_line(Vector2(-size.x * 0.35, y), Vector2(size.x * 0.35, y), Color(0.5, 0.75, 1.0, 0.6), 2.0)
        "thicket":
            for i in 7:
                var p := Vector2(randf_range(-size.x * 0.4, size.x * 0.4), randf_range(-size.y * 0.3, size.y * 0.3))
                draw_circle(p, 7.0, Color(0.15, 0.35, 0.12))
        "valve":
            draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 24, Color(0.7, 0.5, 0.3), 5.0)
            draw_line(Vector2(-10, -10), Vector2(10, 10), Color(0.7, 0.5, 0.3), 4.0)
    # Required element badge and label on the room side of the door.
    var badge_pos := inward * (size.length() * 0.5 + 22.0)
    if spec["reaction"] != "":
        draw_circle(badge_pos + Vector2(-7, 0), 6.0, Element.COLORS[Element.Kind.WET])
        draw_circle(badge_pos + Vector2(7, 0), 6.0, Element.COLORS[Element.Kind.FIRE])
    else:
        draw_circle(badge_pos, 7.0, Element.COLORS[spec["element"]])
    var i := 0
    for k in states.keys():
        draw_circle(badge_pos + Vector2(-10.0 + 10.0 * i, 14), 3.5, Element.COLORS[k])
        i += 1
    var font := ThemeDB.fallback_font
    var label_pos := badge_pos + inward * 26.0 + Vector2(-160, 5)
    draw_string(font, label_pos, spec["label"], HORIZONTAL_ALIGNMENT_CENTER, 320, 12, Color(1, 1, 1, 0.85))
