class_name Crisp
extends Node2D
## World-space drawing that must stay sharp: text, prompts and item cards that belong to
## things in the world (pedestal labels, damage numbers, obstacle labels, hub station
## names). Each is a proxy node on a follow-viewport CanvasLayer at LAYER, above the
## PostFx (layer 1) so the pixel grid, palette and bloom never touch it, and below the
## HUD (3). The proxy copies its source's global transform and visibility every frame and
## calls `draw_fn(proxy)` to draw, so callers keep their drawing code and only swap the
## canvas they draw on.
##
##   var label := Crisp.attach(self, _draw_labels)   # func _draw_labels(cv: CanvasItem)
##
## The proxy frees itself with its source. Redrawn every frame (a handful of nodes).

const LAYER := 2

var source: CanvasItem
var draw_fn: Callable


## The scene's crisp layer, made on first use (a child of the current scene).
static func layer_for(n: Node) -> CanvasLayer:
    if n == null or not n.is_inside_tree():
        return null
    # The top scene node (Main, Hub, Tutorial) above `n`, found by walking up, so this also
    # works while the scene is still running its _ready (current_scene unset).
    var top := n.get_tree().root
    var root: Node = n
    while root.get_parent() != null and root.get_parent() != top:
        root = root.get_parent()
    if root.has_meta("crisp_layer"):
        var have: Variant = root.get_meta("crisp_layer")
        if is_instance_valid(have) and have is CanvasLayer:
            return have as CanvasLayer
    var l := CanvasLayer.new()
    l.name = "CrispLayer"
    l.layer = LAYER
    l.follow_viewport_enabled = true
    l.process_mode = Node.PROCESS_MODE_ALWAYS
    root.set_meta("crisp_layer", l)
    root.add_child.call_deferred(l)
    return l


## A proxy drawing `fn(proxy)` at `src`'s place on the crisp layer. Call from _ready or
## later (the source must be in the tree). Returns null outside a tree.
static func attach(src: CanvasItem, fn: Callable, z: int = 0) -> Crisp:
    var l := layer_for(src)
    if l == null:
        return null
    var c := Crisp.new()
    c.source = src
    c.draw_fn = fn
    c.z_index = z
    c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    l.add_child(c)
    src.tree_exiting.connect(c.queue_free)
    return c


func _init() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    name = "Crisp"


func _process(_delta: float) -> void:
    _follow()
    queue_redraw()


func _follow() -> void:
    if source == null or not is_instance_valid(source):
        queue_free()
        return
    if not is_inside_tree() or not source.is_inside_tree():
        return
    visible = source.is_visible_in_tree()
    if source is Node2D:
        global_transform = (source as Node2D).global_transform
    modulate = source.modulate


func _draw() -> void:
    if draw_fn.is_valid() and source != null and is_instance_valid(source) and source.is_inside_tree():
        draw_fn.call(self)
