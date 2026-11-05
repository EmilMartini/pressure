class_name PostFx
extends CanvasLayer
## Screen-space post-processing that works on the Compatibility renderer (so the web
## build keeps it). One pass, in this order:
##   1. distortions of the sample position: CRT curve (option, off by default), heat
##      shimmer, shockwave ring, small void rifts
##   2. PIXELATION: the position snaps to a grid of `pixel_size` logical screen pixels
##      (Settings "pixel_size", 2..4, default 3) and the world image is read once, at the
##      cell centre (nearest), so everything under this layer (floor, walls, sprites,
##      figures, particles, pedestal icons) shows at one pixel density. Every later step
##      reads per-cell values only, so cells stay crisp: bloom taps cell centres around
##      the cell, aberration offsets whole cells, grain and dither are hashed per cell.
##   3. bloom (thresholded ring taps on the cell grid), saturation, contrast, vignette
##   4. PALETTE: ENDESGA 64 by Endesga (lospec.com/palette-list/endesga-64) through a 32^3
##      lookup texture (res://assets/palette/endesga64_lut.png, built by
##      tools/make_palette_lut.gd: nearest palette colour in OKLab), after an ordered 2x2
##      (Bayer) dither on the cell grid. Settings "palette" turns both off.
##   5. scanlines per cell row (CRT option)
## Layer order: this layer is 1. Above it: the follow-viewport Crisp layer for world text
## (2, see Crisp), the run HUD (3), the tutorial UI (3), the hub UI (10), level-up (40),
## gun pick (45), pause / sheet (50), the flash (90). None of those are pixelated,
## quantized or bloomed. The menu puts its PostFx at -1, under its controls.
## The camera snaps its rendered position to the same grid (PixelCamera), so the world
## moves in whole cells and does not shimmer against the fixed screen grid.
##
## Impact hooks (static, safe to call when no PostFx is in the tree):
##   PostFx.shockwave(world_pos, strength, world_radius)  a ripple ring expanding over 0.4 s
##   PostFx.aberration_pulse(amount)                      chromatic aberration spike, 0.2 s
##   PostFx.bloom_pulse(amount)                           extra bloom, 0.25 s
##   PostFx.heat_pulse(amount, life)                      heat shimmer over the lower screen, 0.6 s
##   PostFx.set_rift(i, world_pos, world_radius, strength) a small slow lens pinch (void floors)
##   PostFx.set_spectacle(v)   run spectacle 0.35..1.3 -> show factor 1.0..1.35 on shockwave
##                             strength, aberration pulses and bloom_gain (not bloom_strength)
## Bloom: `bloom_strength` is set by Settings (0.85 on, 0 off); `bloom_gain` scales it by 1.25
## so the Settings toggle keeps working. The threshold sits low enough that bright element
## colours (fire, charge, glints) bloom; the HUD is on a layer above and never blooms.
## Pulses decay on real time, so they play out the same during a hit-stop.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D lut_tex : filter_nearest;
uniform float bloom_strength : hint_range(0.0, 3.0) = 0.85;
uniform float bloom_gain : hint_range(0.0, 3.0) = 1.25;
uniform float threshold : hint_range(0.0, 1.0) = 0.42;
uniform float radius : hint_range(0.0, 0.03) = 0.011;
uniform float saturation : hint_range(0.0, 2.0) = 1.1;
uniform float contrast : hint_range(0.5, 2.0) = 1.06;
uniform float vignette : hint_range(0.0, 1.5) = 0.75;
uniform float crt_curve : hint_range(0.0, 0.3) = 0.0;
uniform float scanline : hint_range(0.0, 0.5) = 0.0;
uniform float aberration : hint_range(0.0, 3.0) = 0.0;
uniform float grain : hint_range(0.0, 0.2) = 0.012;
// Pixel grid: cell size in logical screen pixels, and the logical screen size.
uniform float pixel_size = 3.0;
uniform vec2 view_size = vec2(1280.0, 720.0);
// Palette: 1 = quantize through the LUT; dither = ordered 2x2 spread (0 = none).
uniform float palette_on = 1.0;
uniform float dither = 0.04;
// Impact pulses, driven from GDScript.
uniform vec2 wave_center = vec2(0.5, 0.5);
uniform float wave_radius = 0.0;
uniform float wave_strength = 0.0;
uniform float wave_width = 0.05;
uniform float aberration_boost = 0.0;
uniform float bloom_boost = 0.0;
uniform float heat = 0.0;
// Small lens rifts: xy = screen UV, z = radius in screen heights, w = strength (0 = off).
uniform vec4 rift0 = vec4(0.0);
uniform vec4 rift1 = vec4(0.0);

// The centre of the grid cell holding `uv`.
vec2 cell_of(vec2 uv, vec2 cell) {
    return (floor(uv / cell) + 0.5) * cell;
}

vec3 bright(vec2 uv) {
    vec3 c = texture(screen_tex, uv).rgb;
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    return c * smoothstep(threshold, threshold + 0.35, l);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// A gentle swirl and pinch toward a rift centre.
vec2 rift(vec2 uv, vec4 r, vec2 aspect) {
    if (r.w <= 0.0) {
        return uv;
    }
    vec2 d = (uv - r.xy) * aspect;
    float k = 1.0 - smoothstep(0.0, r.z, length(d));
    float a = k * k * r.w * 1.6;
    vec2 rot = vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
    rot *= 1.0 - k * r.w * 0.35;
    return r.xy + rot / aspect;
}

void fragment() {
    vec2 cc = SCREEN_UV - vec2(0.5);
    float rr = dot(cc, cc);
    vec2 uv = SCREEN_UV + cc * rr * crt_curve;
    vec2 aspect = vec2(view_size.x / view_size.y, 1.0);
    vec2 cell = vec2(pixel_size) / view_size;
    // Heat shimmer: a faint horizontal wobble over the lower half after fire moments.
    if (heat > 0.0) {
        float low = smoothstep(0.45, 0.8, uv.y);
        uv.x += sin(uv.y * 140.0 + TIME * 11.0) * cos(uv.y * 37.0 - TIME * 5.0) * 0.0022 * heat * low;
    }
    uv = rift(uv, rift0, aspect);
    uv = rift(uv, rift1, aspect);
    // Shockwave: UVs pushed along the ring normal, outward ahead of it and inward behind.
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
    // The pixel grid: one sample per cell, at its centre.
    vec2 cid = floor(uv / cell);
    vec2 cuv = (cid + 0.5) * cell;
    // Chromatic aberration (pulses only by default), whole cells apart.
    float ab_amt = aberration + aberration_boost + ring_amt * 3.0;
    vec3 col;
    if (ab_amt > 0.02) {
        vec2 ab = floor(cc * ab_amt * 2.0 + 0.5) * cell;
        col = vec3(texture(screen_tex, cuv + ab).r, texture(screen_tex, cuv).g, texture(screen_tex, cuv - ab).b);
    } else {
        col = texture(screen_tex, cuv).rgb;
    }
    // Bloom from taps on the cell centres around this cell: the glow is made of pixels.
    float bk = bloom_strength * bloom_gain + bloom_boost;
    if (bk > 0.001) {
        vec3 bloom = bright(cuv) * 2.0;
        float total = 2.0;
        for (int ring = 1; ring <= 2; ring++) {
            float r = radius * float(ring);
            float w = 1.0 / float(ring);
            for (int i = 0; i < 8; i++) {
                float a = float(i) * 0.7853982 + float(ring) * 0.39;
                vec2 off = vec2(cos(a), sin(a)) * r / aspect;
                bloom += bright(cell_of(cuv + off, cell)) * w;
                total += w;
            }
        }
        col += bloom / total * bk;
    }
    col += vec3(ring_amt * 0.05);
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(l), col, saturation);
    col = (col - 0.5) * contrast + 0.5;
    vec2 d = cuv - vec2(0.5);
    col *= 1.0 - smoothstep(0.35, 1.0, length(d * vec2(1.0, 1.25)) * 1.25) * vignette;
    col += (hash(cid + vec2(floor(TIME * 12.0) * 7.0, 0.0)) - 0.5) * grain;
    // Palette: ordered 2x2 dither on the cell grid, then the nearest palette colour.
    if (palette_on > 0.5) {
        float b = mod(cid.x, 2.0) + mod(cid.y, 2.0) * 2.0;
        float bayer = b < 0.5 ? 0.0 : (b < 1.5 ? 2.0 : (b < 2.5 ? 3.0 : 1.0));
        col += (bayer / 4.0 - 0.375) * dither;
        ivec3 q = ivec3(floor(clamp(col, 0.0, 1.0) * 31.0 + 0.5));
        col = texelFetch(lut_tex, ivec2(q.b * 32 + q.r, q.g), 0).rgb;
    }
    // CRT option: a dark line under each row of cells.
    if (scanline > 0.0) {
        col *= 1.0 - scanline * step(0.67, fract(uv.y / cell.y));
    }
    // Black outside the curved picture.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        col = vec3(0.0);
    }
    COLOR = vec4(col, 1.0);
}
"""

const LUT: Texture2D = preload("res://assets/palette/endesga64_lut.png")

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
var _rifts: Array = [[Vector2.ZERO, 0.0, 0.0], [Vector2.ZERO, 0.0, 0.0]]   # world pos, world radius, strength
var _view := Vector2.ZERO


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
    _mat.set_shader_parameter("lut_tex", LUT)
    add_child(rect)
    _last_us = Time.get_ticks_usec()


func _enter_tree() -> void:
    instance = self


func _exit_tree() -> void:
    if instance == self:
        instance = null


## The world-space size of one screen cell for a camera zoom: what PixelCamera snaps to
## and what room tiles use as their texel size.
static func cell_world(zoom: float) -> float:
    return pixel_size() / maxf(zoom, 0.01)


## The cell size in logical screen pixels (Settings "pixel_size", 2..4).
static func pixel_size() -> float:
    return float(clampi(roundi(Settings.number("pixel_size")), 2, 4))


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


## Spike chromatic aberration by `amount` (1 = a cell at the screen edge) for 0.2 s.
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


## A small, slow lens pinch around a world position (slot 0 or 1). Strength 0 turns the
## slot off; 0.2..0.5 reads as a rift without hiding what is behind it.
static func set_rift(slot: int, world_pos: Vector2, world_radius: float, strength: float) -> void:
    if instance != null and is_instance_valid(instance) and slot >= 0 and slot < 2:
        instance._rifts[slot] = [world_pos, world_radius, strength]


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
    var vp := get_viewport()
    if vp != null:
        var size := vp.get_visible_rect().size
        if size != _view and size.y > 0.0:
            _view = size
            _mat.set_shader_parameter("view_size", size)
        _update_rifts(vp, size)
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


func _update_rifts(vp: Viewport, size: Vector2) -> void:
    if size.y <= 0.0:
        return
    var xf := vp.get_canvas_transform()
    var zoom := xf.get_scale().y
    for i in 2:
        var r: Array = _rifts[i]
        var strength := float(r[2])
        if strength <= 0.0:
            _mat.set_shader_parameter("rift%d" % i, Vector4.ZERO)
            continue
        var screen: Vector2 = xf * (r[0] as Vector2)
        _mat.set_shader_parameter("rift%d" % i, Vector4(screen.x / size.x, screen.y / size.y, float(r[1]) * zoom / size.y, strength))
