class_name PostFx
extends CanvasLayer
## Screen-space post-processing that works on the Compatibility renderer (so the web
## build keeps it): bloom from a thresholded multi-tap blur of the screen, a little
## contrast and saturation, and a vignette. Sits below the HUD layer.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float bloom_strength : hint_range(0.0, 3.0) = 0.85;
uniform float threshold : hint_range(0.0, 1.0) = 0.5;
uniform float radius : hint_range(0.0, 0.03) = 0.009;
uniform float saturation : hint_range(0.0, 2.0) = 1.12;
uniform float contrast : hint_range(0.5, 2.0) = 1.08;
uniform float vignette : hint_range(0.0, 1.5) = 0.75;
uniform float crt_curve : hint_range(0.0, 0.3) = 0.06;
uniform float scanline : hint_range(0.0, 0.5) = 0.16;
uniform float aberration : hint_range(0.0, 3.0) = 0.9;
uniform float grain : hint_range(0.0, 0.2) = 0.035;

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
    // Chromatic aberration: red and blue sampled a hair apart, more toward the edges.
    vec2 ab = cc * aberration * px * 2.0;
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
    col += bloom * bloom_strength;
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


func _init() -> void:
    layer = 1
    process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
    var rect := ColorRect.new()
    rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var shader := Shader.new()
    shader.code = SHADER
    var mat := ShaderMaterial.new()
    mat.shader = shader
    rect.material = mat
    add_child(rect)
