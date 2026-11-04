class_name Player
extends CharacterBody2D
## One player: movement, aim modes, the carried arsenal, pressure gauge, focus, health.

signal died(player: Player)

const LAYER_PLAYERS := 1
const LAYER_WALLS := 4
const BASE_SPEED := 320.0
const SPEED_LOSS_PER_WEIGHT := 0.025
const PRESSURE_DECAY := 7.0        # per second, toward neutral
const PRESSURE_LIMIT := 100.0
const STALL_SECONDS := 3.0
const FOCUS_PER_HIT := 0.07
const FOCUS_DECAY := 0.12          # per second
const FOCUS_MISS_PENALTY := 0.15
const VENT_MIN := 20.0

const PLAYER_COLORS := [
    Color(0.40, 0.90, 0.55),
    Color(0.95, 0.55, 0.85),
    Color(0.95, 0.80, 0.35),
    Color(0.55, 0.75, 1.00),
]

var index := 0
var input: PlayerInput
var color := Color.WHITE
var radius := 14.0

var max_hp := 100.0
var hp := 100.0
var alive := true
var invuln := 0.0

var weight_capacity := 10
var guns: Array[Gun] = []
var primary: Gun = null

var auto_aim := true
var aim_dir := Vector2.RIGHT

var pressure := 0.0        # -100 cold .. +100 hot
var overheated := 0.0      # seconds left of stall
var frozen_up := 0.0       # seconds left of slow fire
var focus := 0.0           # 0..1, manual-aim reward
var kills := 0
var last_message := ""
var _message_time := 0.0


func _init(p_index: int, p_input: PlayerInput) -> void:
    index = p_index
    input = p_input
    color = PLAYER_COLORS[p_index % PLAYER_COLORS.size()]
    name = "Player%d" % (p_index + 1)


func _ready() -> void:
    add_to_group("players")
    collision_layer = LAYER_PLAYERS
    collision_mask = LAYER_WALLS
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    add_child(shape)
    z_index = 10


# --- Arsenal ---------------------------------------------------------------


func total_weight() -> int:
    var w := 0
    for g in guns:
        w += g.data.weight
    return w


func can_carry(data: GunData) -> bool:
    return total_weight() + data.weight <= weight_capacity


func add_gun(id: String) -> bool:
    var data := Guns.make(id)
    if not can_carry(data):
        say("Too heavy: %s needs %d, %d free" % [data.display_name, data.weight, weight_capacity - total_weight()])
        return false
    var gun := Gun.new(data, self)
    add_child(gun)
    guns.append(gun)
    if primary == null:
        primary = gun
    say("Picked up %s" % data.display_name)
    return true


func cycle_primary() -> void:
    if guns.size() < 2:
        return
    var i := guns.find(primary)
    primary = guns[(i + 1) % guns.size()]
    say("Primary: %s" % primary.data.display_name)


func element_kinds() -> Array:
    var kinds := []
    for g in guns:
        if not kinds.has(g.data.element):
            kinds.append(g.data.element)
    return kinds


# --- Pressure and focus ----------------------------------------------------


func add_pressure(amount: float) -> void:
    pressure = clampf(pressure + amount, -PRESSURE_LIMIT, PRESSURE_LIMIT)
    if pressure >= PRESSURE_LIMIT:
        overheated = STALL_SECONDS
        pressure = 45.0
        say("OVERHEAT")
    elif pressure <= -PRESSURE_LIMIT:
        frozen_up = STALL_SECONDS
        pressure = -45.0
        say("FROZEN UP")


func cooldown_multiplier() -> float:
    return 3.0 if frozen_up > 0.0 else 1.0


func focus_multiplier() -> float:
    return 1.0 + focus * 0.5


func on_projectile_hit(manual: bool) -> void:
    if manual and not auto_aim:
        focus = minf(1.0, focus + FOCUS_PER_HIT)


func on_projectile_missed() -> void:
    focus = maxf(0.0, focus - FOCUS_MISS_PENALTY)


func vent() -> void:
    if absf(pressure) < VENT_MIN:
        say("Nothing to vent")
        return
    var hot := pressure > 0.0
    var strength := absf(pressure)
    var vent_radius := 110.0 + strength * 1.6
    var kind: int = Element.Kind.FIRE if hot else Element.Kind.ICE
    var col: Color = Element.COLORS[kind]
    Elements.nova.emit(global_position, vent_radius, Color(col, 0.55))
    Elements.reaction_fired.emit("Fire Nova" if hot else "Frost Nova", global_position, col)
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        if e.global_position.distance_to(global_position) > vent_radius:
            continue
        e.take_damage(strength * 0.35, col)
        if is_instance_valid(e) and not e.is_queued_for_deletion():
            e.apply_element(kind, strength * 0.3)
    pressure = 0.0


# --- Health ----------------------------------------------------------------


func take_damage(amount: float) -> void:
    if not alive or invuln > 0.0:
        return
    hp -= amount
    invuln = 0.6
    if hp <= 0.0:
        hp = 0.0
        alive = false
        remove_from_group("players")
        say("DOWN")
        died.emit(self)
    queue_redraw()


func say(text: String) -> void:
    last_message = text
    _message_time = 2.5


# --- Frame -----------------------------------------------------------------


func _physics_process(delta: float) -> void:
    input.poll()
    if not alive:
        return

    var mv := input.move_vector()
    var speed := BASE_SPEED * maxf(0.4, 1.0 - SPEED_LOSS_PER_WEIGHT * total_weight())
    velocity = mv * speed
    move_and_slide()

    var a := input.aim_vector(self)
    if a != Vector2.ZERO:
        aim_dir = a
    elif mv != Vector2.ZERO:
        aim_dir = mv.normalized()

    if input.just_pressed("toggle_aim"):
        auto_aim = not auto_aim
        focus = 0.0
        say("Auto-aim" if auto_aim else "Manual aim")
    if input.just_pressed("vent"):
        vent()
    if input.just_pressed("swap"):
        cycle_primary()

    pressure = move_toward(pressure, 0.0, PRESSURE_DECAY * delta)
    overheated = maxf(0.0, overheated - delta)
    frozen_up = maxf(0.0, frozen_up - delta)
    invuln = maxf(0.0, invuln - delta)
    focus = maxf(0.0, focus - FOCUS_DECAY * delta)
    _message_time = maxf(0.0, _message_time - delta)
    if _message_time <= 0.0:
        last_message = ""

    _fire()
    queue_redraw()


func _fire() -> void:
    if overheated > 0.0:
        return
    var trigger := input.fire_held()
    for g in guns:
        if not g.can_fire():
            continue
        var is_primary := g == primary
        if is_primary and not trigger:
            continue
        var target := _nearest_enemy(g.data.max_range)
        if target == null:
            continue   # nothing in range: neither mode sprays at nothing
        if auto_aim:
            g.fire((target.global_position - global_position).normalized(), false)
        else:
            g.fire(aim_dir, true)


func _nearest_enemy(max_range: float) -> Node2D:
    var best: Node2D = null
    var best_d := max_range * max_range
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        var d: float = e.global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = e
    return best


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    if not alive:
        draw_circle(Vector2.ZERO, radius, Color(0.3, 0.3, 0.3, 0.6))
        return
    var body := color
    if invuln > 0.0 and fmod(invuln, 0.2) < 0.1:
        body = Color(body, 0.35)
    if overheated > 0.0:
        body = body.lerp(Color(1, 0.3, 0.1), 0.6)
    elif frozen_up > 0.0:
        body = body.lerp(Color(0.6, 0.9, 1.0), 0.6)
    draw_circle(Vector2.ZERO, radius, body)
    # Nose shows aim direction.
    var tip := aim_dir * (radius + 8.0)
    var side := aim_dir.orthogonal() * 7.0
    draw_colored_polygon(PackedVector2Array([tip, aim_dir * 4.0 + side, aim_dir * 4.0 - side]), Color.WHITE)
    if not auto_aim:
        draw_line(aim_dir * (radius + 10.0), aim_dir * 90.0, Color(1, 1, 1, 0.25 + focus * 0.5), 1.5)
    # Player number
    var font := ThemeDB.fallback_font
    draw_string(font, Vector2(-5, -radius - 6), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)
