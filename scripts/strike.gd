class_name Strike
extends RefCounted
## What one hit is, shared by everything a gun makes: projectiles, beams, sprays, arcs,
## novas, sweeps, rails, mines, pools and orbs. A Strike carries the numbers a trigger
## pull computed (Gun.strike()); `hit()` is the single hit path (raw damage with the
## element-vs-state multipliers, then the element and any coatings, attributed to the gun
## in Telemetry, then on-hit item triggers), and the static helpers find what an area or a
## line touches without physics (EnemyGrid for enemies, overlaps() for obstacles and props).

var damage := 1.0
var potency := 1.0
var element: int = Element.Kind.NONE
var extras: Array = []        # coating elements, applied at 80% potency
var color := Color.WHITE
var crit := false
var shooter: Player = null
var gun_id := ""


func copy() -> Strike:
    var s := Strike.new()
    s.damage = damage
    s.potency = potency
    s.element = element
    s.extras = extras
    s.color = color
    s.crit = crit
    s.shooter = shooter
    s.gun_id = gun_id
    return s


## One hit on an enemy at `mult` of the strike's damage and potency, with an optional
## shove. Returns false when the enemy cannot be hit (emerging, gone).
func hit(enemy: Enemy, mult: float = 1.0, pos: Vector2 = Vector2.INF, knock: Vector2 = Vector2.ZERO) -> bool:
    if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.emerge > 0.0:
        return false
    deal(enemy, damage * mult, potency * mult, element, extras, color, crit, shooter, gun_id, enemy.global_position if pos == Vector2.INF else pos)
    if knock != Vector2.ZERO and is_instance_valid(enemy):
        enemy.shove(knock)
    return true


## The shared hit path (was Projectile._deal_hit): raw damage with the element-vs-state
## multipliers and the shooter's vs-state gear, then the element and its coatings.
static func deal(enemy: Enemy, dmg: float, pot: float, el: int, extra_els: Array, col: Color, is_crit: bool, src: Player, gid: String, pos: Vector2) -> void:
    var raw := dmg
    if enemy.immune_to == el and el != Element.Kind.NONE:
        raw = 0.0
    # How the element meets what the target already carries, before any gear bonuses:
    # water conducts, damp things burn badly, oil feeds fire, frozen things shatter.
    if raw > 0.0:
        if el == Element.Kind.SHOCK and enemy.has_state(Element.Kind.WET):
            raw *= 1.5
        if el == Element.Kind.FIRE and enemy.has_state(Element.Kind.WET):
            raw *= 0.5
        if el == Element.Kind.FIRE and enemy.has_state(Element.Kind.OIL):
            raw *= 1.25
        if el == Element.Kind.STONE and enemy.frozen_time > 0.0:
            raw *= 1.5
        if el == Element.Kind.HOLY and (enemy.poison_time > 0.0 or enemy.has_state(Element.Kind.VOID)):
            raw *= 1.25
    if src != null and raw > 0.0:
        if enemy.has_state(Element.Kind.WET):
            raw *= 1.0 + src.stat("vs_wet")
        if enemy.burn_time > 0.0:
            raw *= 1.0 + src.stat("vs_burning")
        if enemy.frozen_time > 0.0:
            raw *= 1.0 + src.stat("vs_frozen")
        if enemy.has_state(Element.Kind.SHOCK):
            raw *= 1.0 + src.stat("vs_shocked")
        if enemy.has_state(Element.Kind.OIL):
            raw *= 1.0 + src.stat("vs_oiled")
    if raw > 0.0:
        raw = enemy.resisted(el, raw)   # the region's soft resistance (Regions)
    Telemetry.begin_shot(gid, el)
    enemy.take_damage(raw, col, true, src, is_crit)
    if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
        enemy.apply_element(el, pot, src)
    for extra in extra_els:
        if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
            enemy.apply_element(extra, pot * 0.8, src)
    Telemetry.end_shot()
    if src != null:
        Items.fire(src, "hit", { "target": enemy, "pos": pos, "element": el })


## The element (and coatings) on a prop; a plain chip when none of them did anything.
func hit_prop(prop: Prop, pos: Vector2, dir: Vector2) -> void:
    if not is_instance_valid(prop) or prop.is_queued_for_deletion():
        return
    Sfx.hit_prop(prop.kind, pos)
    var used := prop.apply_element(element, potency, dir)
    for extra in extras:
        if is_instance_valid(prop) and not prop.is_queued_for_deletion():
            used = prop.apply_element(int(extra), potency * 0.8, dir) or used
    if not used and is_instance_valid(prop) and not prop.is_queued_for_deletion():
        prop.take_damage(damage)


## Obstacles (door blockers) and props within `r` of `pos` take the element. Used by the
## area mechanics; `seen` (optional) keeps one area from touching a thing twice.
func touch_world(tree: SceneTree, pos: Vector2, r: float, dir: Vector2, seen: Dictionary = {}) -> void:
    for ob in EnemyGrid.nodes(tree, &"obstacles"):
        if not is_instance_valid(ob) or ob.is_queued_for_deletion() or seen.has(ob):
            continue
        if not ob.overlaps(pos, r):
            continue
        seen[ob] = true
        if ob is Prop:
            hit_prop(ob as Prop, pos, dir)
        elif ob.has_method("apply_element"):
            ob.apply_element(element, potency)
            for extra in extras:
                if is_instance_valid(ob) and not ob.is_queued_for_deletion():
                    ob.apply_element(int(extra), potency * 0.8)


## Clouds within `r` of `pos` react with the element (once per cloud per `seen`).
func touch_clouds(tree: SceneTree, pos: Vector2, r: float, seen: Dictionary) -> void:
    if element == Element.Kind.NONE:
        return
    for c in EnemyGrid.nodes(tree, &"clouds"):
        if not is_instance_valid(c) or seen.has(c) or c.element == element:
            continue
        if c.global_position.distance_to(pos) <= c.radius + r:
            seen[c] = true
            Elements.react_cloud(c, element, potency, shooter)


## Lays the element on the floor (Materials) where an area lands.
func stamp(node: Node, pos: Vector2, r: float, big: bool) -> void:
    if element == Element.Kind.NONE:
        return
    var mats := Materials.find(node)
    if mats == null:
        return
    var amount := clampi(int(40.0 + potency * 6.0), 40, 200)
    if big:
        amount = mini(255, amount + 40)
    mats.stamp(element, pos, r, amount, big)


# --- Geometry -------------------------------------------------------------------


## Live, hittable enemies whose bodies touch the circle (pos, r).
static func enemies_in(tree: SceneTree, pos: Vector2, r: float) -> Array:
    var out: Array = []
    for e in EnemyGrid.overlapping(tree, pos, r):
        if is_instance_valid(e) and not e.is_queued_for_deletion() and e.emerge <= 0.0:
            out.append(e)
    return out


## Enemies whose bodies touch the cone from `pos` along `dir`, `reach` long and
## `half_angle` radians either side, nearest first.
static func enemies_in_cone(tree: SceneTree, pos: Vector2, dir: Vector2, reach: float, half_angle: float) -> Array:
    var out: Array = []
    for e in enemies_in(tree, pos, reach):
        var to: Vector2 = e.global_position - pos
        var d := to.length()
        if d < 1.0:
            out.append([0.0, e])
            continue
        # The body's width counts: a big enemy at the edge of the cone is still in it.
        var slack := asin(clampf(float(e.radius) / d, 0.0, 1.0))
        if absf(dir.angle_to(to)) <= half_angle + slack:
            out.append([d, e])
    out.sort_custom(func(a, b): return a[0] < b[0])
    var list: Array = []
    for pair in out:
        list.append(pair[1])
    return list


## Where a line from `from` along `dir` stops: the first interior wall, outer room edge,
## blocking prop (a pillar) or door obstacle within `length`. Returns [end, obstacle or null].
static func trace(tree: SceneTree, from: Vector2, dir: Vector2, length: float, stop_at_props := false) -> Array:
    var rm := Room.here
    var bounds := Rect2()
    if rm != null and is_instance_valid(rm):
        bounds = Rect2(rm.global_position + rm.rect.position, rm.rect.size).grow(8.0)
    var obs: Array = []
    for ob in EnemyGrid.nodes(tree, &"obstacles"):
        if not is_instance_valid(ob) or ob.is_queued_for_deletion():
            continue
        if ob is Prop and not stop_at_props and not (ob as Prop).blocks_shots:
            continue
        # Only things near the line are worth testing each step.
        var to: Vector2 = ob.global_position - from
        var along := clampf(to.dot(dir), 0.0, length)
        if (from + dir * along).distance_to(ob.global_position) < 90.0:
            obs.append(ob)
    var step := 6.0
    var n := int(ceilf(length / step))
    for k in range(1, n + 1):
        var p := from + dir * minf(length, float(k) * step)
        if bounds.size != Vector2.ZERO and not bounds.has_point(p):
            return [p, null]
        if rm != null and is_instance_valid(rm) and rm.has_walls and rm.blocks_shot(p):
            return [p, null]
        for ob in obs:
            if is_instance_valid(ob) and ob.overlaps(p, 2.0):
                return [p, ob]
    return [from + dir * length, null]


## Enemies whose bodies the segment a..b (with half-width `w`) passes through, nearest to
## `a` first.
static func enemies_on_line(tree: SceneTree, a: Vector2, b: Vector2, w: float) -> Array:
    var seg := b - a
    var length := seg.length()
    if length < 1.0:
        return []
    var dir := seg / length
    var mid := (a + b) * 0.5
    var out: Array = []
    for e in enemies_in(tree, mid, length * 0.5 + w):
        var to: Vector2 = e.global_position - a
        var along := to.dot(dir)
        if along < -float(e.radius) or along > length + float(e.radius):
            continue
        var off := absf(to.cross(dir))
        if off <= w + float(e.radius):
            out.append([along, e])
    out.sort_custom(func(x, y): return x[0] < y[0])
    var list: Array = []
    for pair in out:
        list.append(pair[1])
    return list


## The nearest live enemy to `pos` within `r` that is not in `skip`.
static func nearest(tree: SceneTree, pos: Vector2, r: float, skip: Dictionary) -> Enemy:
    var best: Enemy = null
    var best_d := r * r
    for e in EnemyGrid.nodes(tree, &"enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or not e is Enemy or skip.has(e) or e.emerge > 0.0:
            continue
        var d: float = e.global_position.distance_squared_to(pos)
        if d < best_d:
            best_d = d
            best = e
    return best


static func fx_of(node: Node) -> Fx:
    if node == null or not node.is_inside_tree():
        return null
    var scene := node.get_tree().current_scene
    if scene != null and "fx" in scene:
        return scene.fx
    return null


## Where gun-made things that stay in the world live: the room (freed with it), else the scene.
static func world_parent(node: Node) -> Node:
    var rm := Room.here
    if rm != null and is_instance_valid(rm) and rm.is_inside_tree():
        return rm
    return node.get_tree().current_scene
