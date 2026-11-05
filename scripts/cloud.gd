class_name Cloud
extends Node2D
## A lingering patch of an element: a cloud in the air, or a puddle on the floor for Wet.
## It keeps applying its element to enemies inside while it lasts, reacts once with any
## other element that enters it, and is then used up. Patches merge with a nearby patch of
## the same element and are capped in number, so reactions cannot snowball.

const MAX_CLOUDS := 8
const MERGE_DISTANCE := 70.0

var element: int
var radius: float
var life: float
var potency: float
var source: Player
var cooldown := 0.0   # seconds until this cloud may react again
var age := 0.0
## Tier 2 compound patch (Fusions.COMPOUNDS id, element NONE): applies nothing, fuses with
## the first new element that enters it. `origin` is the reaction that left it.
var compound := ""
var origin := ""
## Tier 3 fusion field (the fusion's name, element = its payload): applies the payload every
## FIELD_TICK at context tier 3 and can set off one cataclysm.
var field_name := ""
var cataclysms_left := 0
var _life0 := 1.0
var _tick := 0.0
var _puff := 0.0


## Spawn a cloud, top up a nearby cloud of the same element, or react with a nearby
## cloud of a different element (two overlapping clouds are a reaction, not a stack).
## Compound patches and fields never take part: they only react with elements that enter
## them (a projectile, a vent, a landing shell), so a cloud spawned by a reaction cannot
## climb the ladder by itself.
static func spawn(parent: Node, pos: Vector2, p_element: int, p_radius: float, p_life: float, p_potency: float, p_source: Player) -> void:
    var tree := parent.get_tree()
    var clouds := tree.get_nodes_in_group("clouds")
    var oldest: Cloud = null
    for c in clouds:
        if not is_instance_valid(c):
            continue
        if c.compound != "" or c.field_name != "":
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


## A compound patch (tier 2 product). A patch of the same compound nearby is refreshed
## instead; at most Fusions.MAX_COMPOUND_PATCHES per room (the oldest goes), and they count
## toward MAX_CLOUDS. Returns true when a patch was made or refreshed.
static func spawn_compound(parent: Node, pos: Vector2, cid: String, p_origin: String, p_radius: float, p_life: float, p_potency: float, p_source: Player) -> bool:
    if parent == null or not parent.is_inside_tree():
        return false
    var clouds := parent.get_tree().get_nodes_in_group("clouds")
    var mine: Array = []
    for c in clouds:
        if not is_instance_valid(c) or c.is_queued_for_deletion() or c.compound == "":
            continue
        if c.compound == cid and c.global_position.distance_to(pos) < MERGE_DISTANCE * 1.3:
            c.life = maxf(c.life, p_life)
            c.origin = p_origin
            return true
        mine.append(c)
    if mine.size() >= Fusions.MAX_COMPOUND_PATCHES:
        _free_oldest(mine)
    _make_room(clouds)
    var cloud := Cloud.new(Element.Kind.NONE, p_radius, p_life, p_potency, p_source)
    cloud.compound = cid
    cloud.origin = p_origin
    cloud.global_position = pos
    parent.add_child(cloud)
    return true


## A fusion field (tier 3, signature fusions only). At most Fusions.MAX_FIELDS per room: a
## new one replaces the oldest.
static func spawn_field(parent: Node, pos: Vector2, fusion_name: String, payload: int, p_radius: float, p_life: float, p_potency: float, p_source: Player) -> void:
    if parent == null or not parent.is_inside_tree():
        return
    var clouds := parent.get_tree().get_nodes_in_group("clouds")
    var fields: Array = []
    for c in clouds:
        if is_instance_valid(c) and not c.is_queued_for_deletion() and c.field_name != "":
            fields.append(c)
    if fields.size() >= Fusions.MAX_FIELDS:
        var oldest: Cloud = null
        for c in fields:
            if oldest == null or c.age > oldest.age:
                oldest = c
        oldest.remove_from_group("clouds")
        oldest.queue_free()
    _make_room(clouds)
    var cloud := Cloud.new(payload, p_radius, p_life, p_potency, p_source)
    cloud.field_name = fusion_name
    cloud.cataclysms_left = Fusions.FIELD_CATACLYSMS
    cloud._tick = Fusions.FIELD_TICK
    cloud.global_position = pos
    parent.add_child(cloud)


## The patch with the least life left in `list` goes.
static func _free_oldest(list: Array) -> void:
    var oldest: Cloud = null
    for c in list:
        if oldest == null or c.life < oldest.life:
            oldest = c
    if oldest != null:
        oldest.remove_from_group("clouds")
        oldest.queue_free()


## Keeps the room under MAX_CLOUDS: a plain cloud or compound patch makes way (fields last).
static func _make_room(clouds: Array) -> void:
    var live: Array = []
    for c in clouds:
        if is_instance_valid(c) and not c.is_queued_for_deletion() and c.is_in_group("clouds"):
            live.append(c)
    if live.size() < MAX_CLOUDS:
        return
    var plain: Array = []
    for c in live:
        if c.field_name == "":
            plain.append(c)
    _free_oldest(plain if not plain.is_empty() else live)


func _init(p_element: int, p_radius: float, p_life: float, p_potency: float, p_source: Player) -> void:
    element = p_element
    radius = p_radius
    life = p_life
    _life0 = maxf(p_life, 0.1)
    potency = p_potency
    source = p_source
    z_index = 3


func _ready() -> void:
    add_to_group("clouds")
    if is_puddle():
        # The floor's material layer gets the same water, so the two systems agree.
        var mats := Materials.find(self)
        if mats != null:
            mats.stamp(Element.Kind.WET, global_position, radius * 0.4, 40)


func is_puddle() -> bool:
    return element == Element.Kind.WET


## Used up by a reaction: a last puff, then gone.
func dissipate() -> void:
    cooldown = 99.0
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene and scene.fx != null:
        var col: Color = Fusions.compound(compound).get("color", Color.WHITE) if compound != "" else Element.COLORS[element]
        scene.fx.puff(Art.PARTICLES["smoke"], global_position, Color(col, 0.5), radius * 1.4, 0.6, false, Vector2(0, -30), 0.3)
    remove_from_group("clouds")
    queue_free()


func _process(delta: float) -> void:
    life -= delta
    age += delta
    _tick -= delta
    _puff -= delta
    cooldown = maxf(0.0, cooldown - delta)
    if _tick <= 0.0 and element != Element.Kind.NONE:
        _tick = Fusions.FIELD_TICK if field_name != "" else 0.6
        # A field's payload runs at context tier 3: the reactions it sets off deal their
        # damage and leave nothing, and nothing it does can fuse.
        var prev := Elements.ctx_tier
        if field_name != "":
            Elements.ctx_tier = maxi(prev, Fusions.TIER_FUSION)
        var r2 := radius * radius
        for e in get_tree().get_nodes_in_group("enemies"):
            if is_instance_valid(e) and not e.is_queued_for_deletion() and e.global_position.distance_squared_to(global_position) <= r2:
                e.apply_element(element, potency, source if is_instance_valid(source) else null)
        Elements.ctx_tier = prev
    if compound != "":
        if life <= 0.0:
            queue_free()
        queue_redraw()
        return
    if _puff <= 0.0 and not is_puddle():
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
    if compound != "":
        _draw_compound()
        return
    var col: Color = Element.COLORS[element]
    if field_name != "":
        _draw_field_ring(col)
    if is_puddle():
        # A flat sheet of water with a couple of ripples; it drenches, it does not drift.
        draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
        draw_circle(Vector2.ZERO, radius, Color(col, 0.18))
        draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(col, 0.5), 2.0)
        var t := Time.get_ticks_msec() / 1000.0
        for i in 2:
            var r := fmod(t * 0.6 + float(i) * 0.5, 1.0) * radius
            draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0.8, 0.9, 1.0, 0.35 * (1.0 - r / radius)), 1.5)
        draw_set_transform_matrix(Transform2D.IDENTITY)
        return
    # A loose field of drifting pixels instead of a disc, so what is inside stays visible.
    var core := col.lightened(0.45)
    var edge := col.darkened(0.4)
    var tt := Time.get_ticks_msec() / 1000.0
    var fade := clampf(life, 0.0, 1.0)
    var count := clampi(int(radius / 7.0), 10, 20)
    for i in count:
        var fi := float(i)
        var rr := radius * 0.9 * sqrt(fmod(fi * 0.618 + 0.13, 1.0))
        var q := Vector2.RIGHT.rotated(fi * 2.399 + tt * 0.15 * (1.0 if i % 2 == 0 else -1.0)) * rr
        q += Vector2(sin(tt * 0.7 + fi * 1.3), cos(tt * 0.5 + fi * 2.1)) * radius * 0.1
        q.y -= fmod(tt * 6.0 + fi * 3.7, 10.0)   # a slow upward creep
        var sz := 2.0 + float(i % 3)
        var c: Color = core if (i + int(tt * 3.0)) % 6 == 0 else (edge if i % 4 == 1 else col)
        c.a = (0.3 + 0.15 * float(i % 2)) * fade
        draw_rect(Rect2(floorf(q.x - sz * 0.5), floorf(q.y - sz * 0.5), sz, sz), c)
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(col, 0.22 * fade), 1.0)


## A compound patch: a faint flat disc in the compound's colour (floor compounds) or a few
## slow motes (cloud compounds), and a dashed rim that says "primed, add a third element".
func _draw_compound() -> void:
    var c: Dictionary = Fusions.compound(compound)
    var col: Color = c.get("color", Color.WHITE)
    var fade := clampf(life / 0.6, 0.0, 1.0)
    var t := Time.get_ticks_msec() / 1000.0
    var floor_kind := String(c.get("where", "")).contains("floor")
    draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5 if floor_kind else 0.8))
    draw_circle(Vector2.ZERO, radius, Color(col, 0.10 * fade))
    var dashes := 16
    for i in dashes:
        var a0 := TAU * float(i) / float(dashes) + t * 0.4
        draw_arc(Vector2.ZERO, radius, a0, a0 + TAU / float(dashes) * 0.5, 4, Color(col, 0.5 * fade), 1.5)
    draw_set_transform_matrix(Transform2D.IDENTITY)
    if not floor_kind:
        for i in 8:
            var fi := float(i)
            var q := Vector2.RIGHT.rotated(fi * 2.399 + t * 0.3) * radius * 0.75 * sqrt(fmod(fi * 0.618 + 0.2, 1.0))
            q.y -= fmod(t * 5.0 + fi * 3.0, 8.0)
            draw_rect(Rect2(floorf(q.x - 1.5), floorf(q.y - 1.5), 3.0, 3.0), Color(col.lightened(0.3), 0.45 * fade))


## A fusion field: a double ring that breathes, in the payload's colour, under the cloud.
func _draw_field_ring(col: Color) -> void:
    var t := Time.get_ticks_msec() / 1000.0
    var fade := clampf(life / 0.6, 0.0, 1.0)
    var k := 0.5 + 0.5 * sin(t * 5.0)
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, Color(col.lightened(0.3), (0.35 + 0.25 * k) * fade), 2.0)
    draw_arc(Vector2.ZERO, radius * (0.92 - 0.04 * k), t * 0.8, t * 0.8 + TAU * 0.7, 40, Color(col, 0.3 * fade), 1.0)
    # Remaining life as a short arc on the rim.
    draw_arc(Vector2.ZERO, radius + 4.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(life / _life0, 0.0, 1.0), 32, Color(1, 1, 1, 0.35 * fade), 1.0)
