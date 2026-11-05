class_name PostFx
extends CanvasLayer
## Screen-space post-processing that works on the Compatibility renderer (so the web
## build keeps it): bloom from a thresholded multi-tap blur of the screen, a little
## contrast and saturation, and a vignette. Sits below the HUD layer.
##
## Impact hooks (static, safe to call when no PostFx is in the tree):
##   PostFx.shockwave(world_pos, strength, world_radius)  a ripple ring expanding over 0.4 s
##   PostFx.aberration_pulse(amount)                      chromatic aberration spike, 0.2 s
##   PostFx.bloom_pulse(amount)                           extra bloom, 0.25 s
##   PostFx.heat_pulse(amount, life)                      heat shimmer over the lower screen, 0.6 s
##   PostFx.set_spectacle(v)   run spectacle 0.35..1.3 -> show factor 1.0..1.35 on shockwave
##                             strength, aberration pulses and bloom_gain (not bloom_strength)
## Bloom: `bloom_strength` is set by Settings (0.85 on, 0 off); `bloom_gain` scales it by 1.25
## so the Settings toggle keeps working. The threshold sits low enough that bright element
## colours (fire, charge, glints) bloom; the HUD is on a layer above and never blooms.
## Pulses decay on real time, so they play out the same during a hit-stop.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float bloom_strength : hint_range(0.0, 3.0) = 0.85;
uniform float bloom_gain : hint_range(0.0, 3.0) = 1.25;
uniform float threshold : hint_range(0.0, 1.0) = 0.42;
uniform float radius : hint_range(0.0, 0.03) = 0.009;
uniform float saturation : hint_range(0.0, 2.0) = 1.12;
uniform float contrast : hint_range(0.5, 2.0) = 1.08;
uniform float vignette : hint_range(0.0, 1.5) = 0.75;
uniform float crt_curve : hint_range(0.0, 0.3) = 0.06;
uniform float scanline : hint_range(0.0, 0.5) = 0.16;
uniform float aberration : hint_range(0.0, 3.0) = 0.9;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
// Impact pulses, driven from GDScript.
uniform vec2 wave_center = vec2(0.5, 0.5);
uniform float wave_radius = 0.0;
uniform float wave_strength = 0.0;
uniform float wave_width = 0.05;
uniform float aberration_boost = 0.0;
uniform float bloom_boost = 0.0;
uniform float heat = 0.0;

vec3 bright(vec2 uv) {
    vec3 c = texture(screen_tex, uv).rgb;
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    return c * smoothstep(threshold, threshold + 0.35, l);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    // CRT: a slight barrel curve on the sample position.
    vec2 cc = SCREEN_UV - vec2(0.5);
    float rr = dot(cc, cc);
    vec2 uv = SCREEN_UV + cc * rr * crt_curve;
    vec2 px = SCREEN_PIXEL_SIZE;
    vec2 aspect = vec2(px.y / px.x, 1.0);
    // Heat shimmer: a faint horizontal wobble over the lower half after fire moments.
    if (heat > 0.0) {
        float low = smoothstep(0.45, 0.8, uv.y);
        uv.x += sin(uv.y * 140.0 + TIME * 11.0) * cos(uv.y * 37.0 - TIME * 5.0) * 0.0016 * heat * low;
    }
    // Shockwave: UVs pushed along the ring normal, outward ahead of it and inward behind,
    // so the picture ripples like a pressure front. wave_center is screen UV, wave_radius
    // and wave_width are in screen heights.
    float ring_amt = 0.0;
    if (wave_strength > 0.0) {
        vec2 wd = (uv - wave_center) * aspect;
        float dist = length(wd);
        float x = (dist - wave_radius) / wave_width;
        float prof = -x * exp(-x * x * 1.5);
        ring_amt = exp(-x * x * 2.0) * wave_strength;
        vec2 dir = dist > 0.0001 ? wd / dist : vec2(0.0);
        uv += dir / aspect * prof * wave_strength * 0.018;
    }
    // Chromatic aberration: red and blue sampled a hair apart, more toward the edges,
    // spiked by aberration_boost and along the shockwave ring.
    vec2 ab = cc * (aberration + aberration_boost + ring_amt * 3.0) * px * 2.0;
    vec3 col = vec3(texture(screen_tex, uv + ab).r, texture(screen_tex, uv).g, texture(screen_tex, uv - ab).b);
    vec3 bloom = bright(uv) * 2.0;
    float total = 2.0;
    for (int ring = 1; ring <= 2; ring++) {
        float r = radius * float(ring);
        float w = 1.0 / float(ring);
        for (int i = 0; i < 8; i++) {
            float a = float(i) * 0.7853982 + float(ring) * 0.39;
            vec2 off = vec2(cos(a), sin(a)) * r / aspect;
            bloom += bright(uv + off) * w;
            total += w;
        }
    }
    bloom /= total;
    col += bloom * (bloom_strength * bloom_gain + bloom_boost);
    col += vec3(ring_amt * 0.05);
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(l), col, saturation);
    col = (col - 0.5) * contrast + 0.5;
    // Scanlines, a faint phosphor triad, grain, and the vignette.
    float line = 0.5 + 0.5 * sin(uv.y / px.y * 3.14159);
    col *= 1.0 - scanline * line;
    float triad = mod(floor(uv.x / px.x), 3.0);
    col *= vec3(triad == 0.0 ? 1.03 : 0.985, triad == 1.0 ? 1.03 : 0.985, triad == 2.0 ? 1.03 : 0.985);
    col += (hash(uv * 1000.0 + vec2(TIME * 7.0)) - 0.5) * grain;
    vec2 d = uv - vec2(0.5);
    float v = 1.0 - smoothstep(0.35, 1.0, length(d * vec2(1.0, 1.25)) * 1.25) * vignette;
    col *= v;
    // Black outside the curved picture.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        col = vec3(0.0);
    }
    COLOR = vec4(col, 1.0);
}
"""

const WAVE_LIFE := 0.4
const ABERRATION_LIFE := 0.2
const BLOOM_LIFE := 0.25
const HEAT_LIFE := 0.6

## The PostFx currently in the tree (the latest one to enter), for the static hooks.
static var instance: PostFx = null
## Show factor from the run's spectacle (1.0 at 0.35 .. 1.35 at 1.3); kept static so a
## PostFx created later starts with it.
static var show_k := 1.0
const BLOOM_GAIN := 1.25

var _mat: ShaderMaterial
var _last_us := 0
var _wave_t := 0.0          # seconds left
var _wave_max := 0.0        # final radius, screen heights
var _wave_str := 0.0
var _ab_t := 0.0
var _ab_amt := 0.0
var _bloom_t := 0.0
var _bloom_amt := 0.0
var _heat_t := 0.0
var _heat_life := HEAT_LIFE
var _heat_amt := 0.0


func _init() -> void:
    layer = 1
    process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
    var rect := ColorRect.new()
    rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var shader := Shader.new()
    shader.code = SHADER
    _mat = ShaderMaterial.new()
    _mat.shader = shader
    rect.material = _mat
    _mat.set_shader_parameter("bloom_gain", BLOOM_GAIN * show_k)
    add_child(rect)
    _last_us = Time.get_ticks_usec()


func _enter_tree() -> void:
    instance = self


func _exit_tree() -> void:
    if instance == self:
        instance = null


# --- Static hooks ------------------------------------------------------------


## A ripple ring expanding from a world position over 0.4 s. `strength` about 0.3 for a
## small burst up to 1.5 for a boss death; `world_radius` is how far the ring travels.
static func shockwave(world_pos: Vector2, strength: float, world_radius: float = 220.0) -> void:
    if instance != null and is_instance_valid(instance):
        instance._shockwave(world_pos, strength, world_radius)


## Run spectacle (0.35 .. 1.3): scales shockwaves, aberration pulses and the bloom gain
## from 1.0 to 1.35. The Settings-driven bloom_strength is left alone.
static func set_spectacle(v: float) -> void:
    show_k = lerpf(1.0, 1.35, clampf((v - 0.35) / 0.95, 0.0, 1.0))
    if instance != null and is_instance_valid(instance) and instance._mat != null:
        instance._mat.set_shader_parameter("bloom_gain", BLOOM_GAIN * show_k)


## Spike chromatic aberration by `amount` (1 = doubles the default) for 0.2 s.
static func aberration_pulse(amount: float) -> void:
    if instance != null and is_instance_valid(instance):
        instance._ab_amt = maxf(instance._ab_amt * instance._ab_t / ABERRATION_LIFE, amount * show_k)
        instance._ab_t = ABERRATION_LIFE


## Extra bloom by `amount` (0.5 to 1.5 reads well) for 0.25 s.
static func bloom_pulse(amount: float) -> void:
    if instance != null and is_instance_valid(instance):
        instance._bloom_amt = maxf(instance._bloom_amt * instance._bloom_t / BLOOM_LIFE, amount)
        instance._bloom_t = BLOOM_LIFE


## Heat shimmer by `amount` (0..1) fading over `life` seconds (fire moments, from Fx).
static func heat_pulse(amount: float, life: float = HEAT_LIFE) -> void:
    if instance != null and is_instance_valid(instance):
        var live := instance._heat_amt * (instance._heat_t / instance._heat_life) if instance._heat_life > 0.0 else 0.0
        instance._heat_amt = clampf(maxf(live, amount), 0.0, 1.0)
        instance._heat_life = maxf(life, 0.05)
        instance._heat_t = instance._heat_life


func _shockwave(world_pos: Vector2, strength_in: float, world_radius: float) -> void:
    var strength := strength_in * show_k
    # A weaker wave does not cut off a stronger one still travelling.
    var live := _wave_str * (_wave_t / WAVE_LIFE)
    if strength < live:
        return
    var vp := get_viewport()
    if vp == null or _mat == null:
        return
    var size := vp.get_visible_rect().size
    if size.y <= 0.0:
        return
    var xf := vp.get_canvas_transform()
    var screen := xf * world_pos
    var uv := Vector2(screen.x / size.x, screen.y / size.y)
    var zoom := xf.get_scale().y
    _mat.set_shader_parameter("wave_center", uv)
    _wave_max = clampf(world_radius * zoom / size.y, 0.05, 0.9)
    _wave_str = clampf(strength, 0.0, 2.0)
    _wave_t = WAVE_LIFE


func _process(_delta: float) -> void:
    if _mat == null:
        return
    # Real time, unaffected by Engine.time_scale (hit-stop).
    var now := Time.get_ticks_usec()
    var dt := minf(float(now - _last_us) / 1000000.0, 0.1)
    _last_us = now
    if _wave_t > 0.0:
        _wave_t = maxf(0.0, _wave_t - dt)
        var k := 1.0 - _wave_t / WAVE_LIFE
        var grow := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
        var fade := (1.0 - k) * (1.0 - k)
        _mat.set_shader_parameter("wave_radius", _wave_max * grow)
        _mat.set_shader_parameter("wave_strength", _wave_str * fade if _wave_t > 0.0 else 0.0)
    if _ab_t > 0.0:
        _ab_t = maxf(0.0, _ab_t - dt)
        _mat.set_shader_parameter("aberration_boost", _ab_amt * _ab_t / ABERRATION_LIFE)
    if _bloom_t > 0.0:
        _bloom_t = maxf(0.0, _bloom_t - dt)
        _mat.set_shader_parameter("bloom_boost", _bloom_amt * _bloom_t / BLOOM_LIFE)
    if _heat_t > 0.0:
        _heat_t = maxf(0.0, _heat_t - dt)
        _mat.set_shader_parameter("heat", _heat_amt * _heat_t / _heat_life)
