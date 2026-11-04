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
    "ward": {
        "label": "Unholy ward. Holy light breaks it.",
        "element": Element.Kind.HOLY,
        "reaction": "",
        "color": Color(0.30, 0.12, 0.40),
    },
    "rubble": {
        "label": "Collapsed rubble. Acid eats through it.",
        "element": Element.Kind.ACID,
        "reaction": "",
        "color": Color(0.40, 0.36, 0.30),
    },
    "miasma": {
        "label": "Choking miasma. Blow it away with a gale.",
        "element": Element.Kind.GALE,
        "reaction": "",
        "color": Color(0.25, 0.40, 0.22),
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


## Projectiles test against obstacles directly: a moving Area2D does not reliably
## report overlaps with a StaticBody2D, so Projectile calls this each physics frame.
func overlaps(point: Vector2, margin: float) -> bool:
    var local := to_local(point)
    return Rect2(-size / 2.0 - Vector2(margin, margin), size + Vector2(margin, margin) * 2.0).has_point(local)


func _ready() -> void:
    add_to_group("obstacles")
    collision_layer = Player.LAYER_WALLS | LAYER_OBSTACLES
    collision_mask = 0
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = size
    shape.shape = rect
    add_child(shape)
    var spec: Dictionary = KINDS[kind]
    match kind:
        "thicket":
            var along := Vector2(1, 0) if size.x > size.y else Vector2(0, 1)
            for i in 3:
                var t := Art.sprite(Art.TILES["tree_a"] if i % 2 == 0 else Art.TILES["tree_b"], 2.2, Color(0.45, 0.62, 0.35))
                t.position = along * (float(i) - 1.0) * 40.0
                add_child(t)
        "valve":
            var cog := Art.sprite(Art.TILES["cog"], 2.6, Color(0.75, 0.6, 0.4))
            add_child(cog)
        "ward":
            var skull := Art.sprite(Art.TILES["decals"][0], 2.6, Color(0.8, 0.5, 1.0))
            add_child(skull)
        "rubble":
            var along := Vector2(1, 0) if size.x > size.y else Vector2(0, 1)
            for i in 3:
                var r := Art.sprite(Art.TILES["decals"][3 + (i % 2)], 2.2, Color(0.6, 0.55, 0.45))
                r.position = along * (float(i) - 1.0) * 36.0
                add_child(r)
        "miasma":
            var m := Art.sprite(Art.TILES["decals"][5], 2.6, Color(0.5, 0.9, 0.4))
            add_child(m)


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
    if kind == "pool":
        var along := Vector2(1, 0) if size.x > size.y else Vector2(0, 1)
        var across := along.orthogonal()
        var len := maxf(size.x, size.y)
        for i in 3:
            var off := across * (float(i) - 1.0) * (minf(size.x, size.y) / 3.5)
            draw_line(off - along * len * 0.35, off + along * len * 0.35, Color(0.45, 0.7, 1.0, 0.5), 2.0)
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
    var label_pos := badge_pos + inward * 26.0 + Vector2(-180, 6)
    draw_string(Art.FONT_BODY, label_pos + Vector2(1, 1), spec["label"], HORIZONTAL_ALIGNMENT_CENTER, 360, 17, Color(0, 0, 0, 0.8))
    draw_string(Art.FONT_BODY, label_pos, spec["label"], HORIZONTAL_ALIGNMENT_CENTER, 360, 17, Color(0.92, 0.9, 0.85))
