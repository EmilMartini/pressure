class_name DangerFx
extends CanvasLayer
## Screen-edge danger overlay over the world, under the HUD: you always know you were hit
## and how close to death you are.
##   Hit:        a red flash on the screen edges, strongest on the side the hit came
##               from (a floor tick or a hit with no source glows all round), scaled by
##               the share of max HP it took.
##   Low health: under Sfx.HEART_LOW (35%) the edges glow red and pulse with the
##               heartbeat (Sfx.heart_env), with a rumble on each beat; under
##               Sfx.HEART_CRIT (15%) it is deeper and reaches further in.
## With the "Screen flashes" option off, the hit flash is a third as strong and slower,
## and the low-health edge holds steady instead of pulsing (it is still there).
## Players connect their `hurt` signal here (Main._spawn_player). Runs on real time.

const SHADER := """
shader_type canvas_item;
uniform float low = 0.0;
uniform float crit = 0.0;
uniform float hit = 0.0;
uniform vec2 hit_dir = vec2(0.0);
uniform vec2 aspect = vec2(1.78, 1.0);

void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    vec2 q = abs(p);
    // Super-ellipse distance: 0 in the centre, 1 at the edges, a little more in the corners.
    float d = pow(pow(q.x, 4.0) + pow(q.y, 4.0), 0.25);
    float a = 0.0;
    // Low health: a band that reaches further in as health falls.
    float band = smoothstep(0.72 - 0.22 * crit, 1.08, d);
    a += low * band;
    // Hit: wider band, weighted toward the side the hit came from.
    float w = 1.0;
    if (dot(hit_dir, hit_dir) > 0.0) {
        vec2 n = normalize(p * aspect + vec2(0.0001));
        w = mix(0.2, 1.0, smoothstep(-0.3, 0.85, dot(n, hit_dir)));
    }
    a += hit * w * smoothstep(0.5, 1.05, d);
    COLOR = vec4(mix(vec3(0.75, 0.02, 0.03), vec3(0.35, 0.0, 0.02), crit * band), clamp(a, 0.0, 0.85));
}
"""

const HIT_LIFE := 0.35
const RUMBLE_STRONG := 0.45

var main: Main
var _rect: ColorRect
var _mat: ShaderMaterial
var _hit := 0.0
var _hit_life := HIT_LIFE
var _hit_dir := Vector2.ZERO
var _low := 0.0
var _last_env := 0.0


func _init(m: Main) -> void:
    main = m
    name = "DangerFx"
    layer = 3   # added before the HUD's layer 3 node, so it draws under the HUD
    process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
    _rect = ColorRect.new()
    _rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sh := Shader.new()
    sh.code = SHADER
    _mat = ShaderMaterial.new()
    _mat.shader = sh
    _rect.material = _mat
    _rect.visible = false
    add_child(_rect)


## A hit landed on `p`: flash the edges toward where it came from.
func on_hurt(p: Player, amount: float, from: Vector2, _source: String) -> void:
    if not is_instance_valid(p):
        return
    var share := amount / maxf(1.0, p.max_hp)
    var strength := clampf(0.35 + share * 3.0, 0.35, 0.8)
    _hit_life = HIT_LIFE
    if not Settings.flag("flashes"):
        strength *= 0.35
        _hit_life = HIT_LIFE * 2.0
    _hit = maxf(_hit, strength)
    _hit_dir = Vector2.ZERO
    if from != Vector2.INF and from.distance_to(p.global_position) > 4.0:
        # World and screen share axes (y down, the camera never rotates).
        _hit_dir = (from - p.global_position).normalized()


func _process(delta: float) -> void:
    var real := delta / maxf(Engine.time_scale, 0.001)
    _hit = maxf(0.0, _hit - real * 0.8 / _hit_life)
    var frac := 1.0
    var worst: Player = null
    if main != null and not main.game_over:
        for p in main.players:
            if is_instance_valid(p) and p.alive:
                var f := p.hp / maxf(1.0, p.max_hp)
                if f < frac:
                    frac = f
                    worst = p
    var low_k := clampf((Sfx.HEART_LOW - frac) / (Sfx.HEART_LOW - Sfx.HEART_CRIT), 0.0, 1.0) if frac < Sfx.HEART_LOW else -1.0
    var crit := clampf((Sfx.HEART_CRIT - frac) / Sfx.HEART_CRIT * 3.0, 0.0, 1.0)
    var target := 0.0
    if low_k >= 0.0 and not get_tree().paused:   # menus and level-ups: the edge fades out
        var steady := 0.22 + 0.25 * low_k
        if Settings.flag("flashes"):
            var env := Sfx.heart_env()
            if env < 0.0:
                env = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * lerpf(1.1, 1.6, low_k))
            target = steady * 0.7 + (0.25 + 0.2 * low_k) * env
            # A rumble on each beat, on the pad of the player in danger.
            if env > 0.8 and _last_env <= 0.8 and worst != null and not get_tree().paused:
                Rumble.pulse(worst.input.device if worst.input.device >= 0 else -1, 0.0, RUMBLE_STRONG * lerpf(0.6, 1.0, low_k), 0.1)
            _last_env = env
        else:
            target = steady
    _low = move_toward(_low, target, real * 3.0)
    _rect.visible = _low > 0.005 or _hit > 0.005
    if _rect.visible:
        var vp := get_viewport().get_visible_rect().size
        _mat.set_shader_parameter("low", _low)
        _mat.set_shader_parameter("crit", crit if low_k >= 0.0 else 0.0)
        _mat.set_shader_parameter("hit", _hit)
        _mat.set_shader_parameter("hit_dir", _hit_dir)
        _mat.set_shader_parameter("aspect", Vector2(vp.x / maxf(1.0, vp.y), 1.0))
