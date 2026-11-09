class_name EnemyProjectile
extends Node2D
## A shot fired by an enemy: flies straight, hits the nearest living player it touches,
## and is gone at the end of its life or when it leaves the room.

const TRAIL_POINTS := 6
const DEFAULT_COLOR := Color(1.0, 0.40, 0.30)
## Themes whose floor sits at mid grey or lighter (measured: the Frostvault floor behind
## shots is about 0.25 luminance against 0.08 in the Rust Ruins). There the red rim melts
## into the floor and only the outline and core carry the shot, so the body is lifted
## further toward white and the white core grows: same size, same black outline and red
## rim, more of the disc far from the floor's luminance (design doc, Phase 4 prelude).
const LIGHT_FLOOR_THEMES := ["frozen"]

var damage := 6.0
var speed := 240.0
var element: int = Element.Kind.NONE
var lifetime := 3.0
var radius := 6.0
var direction := Vector2.RIGHT
var owner_enemy: Node2D = null
## The shooter's kind (Telemetry.enemy_label), kept from the moment it fired: the shooter
## is often dead by the time the shot lands, which used to log "projectile:unknown".
var shooter := ""
## Room floor in global coordinates. Left empty, it is taken from the parent's `rect`
## (a Room keeps its floor as a local Rect2) when the shot enters the tree.
var room_rect := Rect2()

var _trail: Array[Vector2] = []
var _age := 0.0
var _closest := INF   # closest pass to a player, measured from a hit (PressureMeter near misses)


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


## A shot that left play without hitting: a near miss if it passed close (PressureMeter).
func _missed() -> void:
    if _closest == INF:
        return
    var sc := get_tree().current_scene
    if sc != null and "pressure_meter" in sc and sc.pressure_meter != null:
        sc.pressure_meter.shot_missed(_closest)


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
        _missed()
        queue_free()
        return
    if room_rect.has_area() and not room_rect.grow(radius).has_point(global_position):
        _missed()
        queue_free()
        return
    var rm := Room.here
    if rm != null and rm.has_walls and rm.blocks_shot(global_position):
        var sc := get_tree().current_scene
        if sc != null and "fx" in sc and sc.fx != null:
            sc.fx.puff(Art.PARTICLES["circle"], global_position, Color(color(), 0.5), radius * 3.0, 0.2, true)
        _missed()
        queue_free()
        return
    var hit: Player = null
    var best := INF
    for p in get_tree().get_nodes_in_group("players"):
        if not is_instance_valid(p) or not p.alive:
            continue
        var d: float = p.global_position.distance_to(global_position)
        _closest = minf(_closest, d - radius - 10.0)
        if d <= radius + 10.0 and d < best:
            best = d
            hit = p
    if hit != null:
        var attacker: Node2D = owner_enemy if is_instance_valid(owner_enemy) else null
        var who := shooter
        if who == "":
            who = Telemetry.enemy_label(attacker) if attacker != null else "unknown"
        Telemetry.hurt_hint = "projectile:" + who
        # The hit comes from where the shot flew in from, not from the shooter.
        hit.take_damage(damage, attacker, global_position - direction * 40.0)
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
    # Glow under the body; the body itself is drawn sharp on the Crisp layer (draw_crisp).
    var pulse := 1.0 + 0.15 * sin(_age * 18.0)
    draw_circle(Vector2.ZERO, radius * 2.2 * pulse, Color(c, 0.18))
    draw_circle(Vector2.ZERO, radius * 1.4, Color(c, 0.45))


## The readable part, drawn by Fx on the Crisp layer above the player's own effects, in
## the hostile signature (Hostile) but as pixel art that matches the world: a disc of
## whole screen cells (Settings "pixel_size"), snapped to the PostFx grid and put through
## its palette, with a 1-cell near-black outline, a 1-cell red rim, the element colour
## lifted toward white and a white-hot core that pulses between two frames. Nothing the
## player fires is outlined dark or rimmed red, so an incoming shot reads in any cloud
## or blaze.
func draw_crisp(cv: CanvasItem, at: Vector2) -> void:
    var xf := cv.get_global_transform_with_canvas()
    var k := maxf(0.05, xf.get_scale().x)
    var ps := PostFx.pixel_size() if Settings.flag("post_fx") else 1.0
    var world_d := 2.0 * (maxf(radius * 0.85, 4.0) + 3.5)
    var n := ceili(world_d * k / ps)
    n += 1 - n % 2   # odd: a centre cell
    var hot := sin(_age * 18.0) > 0.0
    var tex := sprite(color(), n, hot, Themes.current in LIGHT_FLOOR_THEMES)
    # Top-left corner on the screen's cell grid, back in the canvas' units.
    var scr := xf * at - Vector2(n, n) * ps * 0.5
    scr = (scr / ps).round() * ps
    cv.draw_texture_rect(tex, Rect2(xf.affine_inverse() * scr, Vector2(n, n) * ps / k), false)


static var _sprites: Dictionary = {}


## A shot's pixel disc, `n` cells across (one texel per cell), cached per colour, size,
## frame and palette setting.
static func sprite(c: Color, n: int, hot: bool, light: bool = false) -> Texture2D:
    var pal := Settings.flag("palette") and Settings.flag("post_fx")
    var key := "%s:%d:%s:%s:%s" % [c.to_html(false), n, hot, pal, light]
    if _sprites.has(key):
        return _sprites[key]
    var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
    var r := float(n) * 0.5
    var body := c.lightened(0.62 if light else 0.3)
    var core_r := maxf(0.75, r * ((0.55 if hot else 0.45) if light else (0.42 if hot else 0.3)))
    for y in n:
        for x in n:
            var d := Vector2(float(x) + 0.5 - r, float(y) + 0.5 - r).length()
            var col := Color(0, 0, 0, 0)
            if d <= r:
                col = Color(Hostile.DARK, 1.0)
            if d <= r - 1.0:
                col = Hostile.RED
            if d <= r - 2.0:
                col = body
                if x < int(r) and y < int(r) and d > r - 3.0:
                    col = body.lightened(0.35)   # a lit upper-left edge
            if d <= core_r:
                col = Color(1.0, 1.0, 0.92)
            img.set_pixel(x, y, col)
    if pal:
        Art._quantize(img)
    var tex := ImageTexture.create_from_image(img)
    if _sprites.size() > 256:
        _sprites.clear()
    _sprites[key] = tex
    return tex
