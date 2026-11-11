extends Node
## Autoload "Settings": player options saved to user://settings.json. `apply()` pushes
## everything live: audio bus volumes, window mode, vsync, and the PostFx uniforms. Other
## scripts read values with `Settings.get_value(key)` or the small helpers below.

signal changed(key: String)

const SAVE_PATH := "user://settings.json"

## Every key with its default. Volumes, shake and CRT intensity are 0..1.
const DEFAULTS := {
    "master_volume": 0.8,
    "music_volume": 0.7,
    "sfx_volume": 0.8,
    "fullscreen": false,
    "vsync": true,
    "fps_cap": "60",                  # "60" or "uncapped" (Engine.max_fps); bots and captures run uncapped
    "screen_shake": 1.0,
    "hit_stop": true,
    "flashes": true,                  # full-strength screen flashes and the pulsing low-health edge
    "damage_numbers": false,          # old on/off switch, read once to seed dmg_numbers (load)
    "dmg_numbers": "big",             # "all", "big" (merged crits and boss hits) or "off" (Fx.dmg_mode)
    "fight_text": "quiet",            # "quiet", "reactions" or "everything" (Fx.fight_text)
    "vent_mode": "auto",              # "auto" (fires on its own) or "button" (PlayerInput)
    "own_fx": 0.45,                   # opacity of your own effects (own_fx()), 1 = full (clarity pass: 0.45)
    "post_fx": true,
    "crt": false,                     # CRT curve, scanlines, a little aberration and grain
    "crt_intensity": 0.6,
    "bloom": true,
    "pixel_size": 3,                  # world pixel grid in screen pixels, 2..4
    "palette": true,                  # quantize the world to the palette, with dither
    "lighting": true,                 # art pass: region light, grade and dressing (ArtPass)
    "river_carry": true,              # rivers carry oil, blood, poisoned water, ash downstream (on: Emil, 2026-11-10)
    "fx_rev": 3,                      # post-fx defaults revision (FX_REV; migrations, see load)
    "controls_rev": 1,                # controls defaults revision (CONTROLS_REV)
    "aim_mode": "auto",               # "auto" (focus targeting), "assisted" or "manual" (Player.AIM_MODES)
    "manual_fire": "hold",            # manual aim: "hold" fire, or "toggle" constant fire
    "controls_hint": false,
    "pause_on_disconnect": true,
    "vibration": 0.6,                 # controller rumble strength, 0 = off (Rumble)
    "vibration_paused": false,        # keep rumbling while the game is paused
    "seen_explainer": false,
    "tutorial_done": false,
    "dash_learned": false,            # the first-room dash prompt is gone after the first dash

    "telemetry": "ask",               # anonymous play data: "ask", "on" or "off"
    "telemetry_device_id": "",        # random id, never a name
}

## PostFx shader values at full CRT intensity (see post_fx.gd); intensity scales them.
## Without the CRT option the picture is flat and crisp: no curve, no scanlines, no
## standing aberration (only the brief pulses), and a faint grain.
const CRT_FULL := { "crt_curve": 0.1, "scanline": 0.22, "aberration": 0.6, "grain": 0.04 }
const GRAIN_BASE := 0.012
const BLOOM_ON := 0.35   # was 0.85; clarity pass: the player's glow no longer floods the arena
## Bumped when post-fx defaults change in a way old settings files should pick up.
const FX_REV := 3
## Bumped when control or fight-text defaults change for older settings files.
## 1: Core loop reset (2026-11-10): auto aim, quiet fights, no damage numbers.
const CONTROLS_REV := 1
## Numeric keys that are not 0..1, with their range.
const RANGES := { "pixel_size": [2.0, 4.0], "fx_rev": [0.0, 1000.0], "controls_rev": [0.0, 1000.0] }

var values: Dictionary = {}
var save_path := SAVE_PATH


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # Bot runs use a throwaway options file per instance, never the player's: the hub
    # tutorial, explainer and play-data prompt are marked done and uploads stay off.
    if Main.bot_run():
        save_path = "user://settings_autotest%s.json" % Main._instance_tag()
    load_settings()
    if Main.bot_run():
        values["tutorial_done"] = true
        values["seen_explainer"] = true
        values["telemetry"] = "off"
    _ensure_buses()
    get_tree().node_added.connect(_on_node_added)
    Input.joy_connection_changed.connect(_on_joy_connection_changed)
    # Music and Sfx build their players in their own _ready; route them once all are up.
    call_deferred("apply")


# --- Access ------------------------------------------------------------------


func get_value(key: String) -> Variant:
    return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
    values[key] = v
    save()
    apply()
    changed.emit(key)
    Telemetry.setting_changed(key, v)


func flag(key: String) -> bool:
    return bool(get_value(key))


func number(key: String) -> float:
    return float(get_value(key))


## Opacity of the player's own effects (projectiles, beams, sprays, pools, clouds, mines,
## turrets, muzzle effects and the particle layers), the "Your effects" option: 1 at full,
## down to 0.25 at the lowest step, so enemy shots and hostile edges stand out more.
func own_fx() -> float:
    return lerpf(0.25, 1.0, clampf(number("own_fx"), 0.0, 1.0))


## Multiplier for camera shake (0 = off).
func shake_mult() -> float:
    return clampf(number("screen_shake"), 0.0, 1.0)


## The audio bus a player of this kind ("music", "sfx", anything else = Master) uses.
func bus_for(kind: String) -> String:
    match kind:
        "music":
            return "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
        "sfx":
            return "Sfx" if AudioServer.get_bus_index("Sfx") >= 0 else "Master"
    return "Master"


# --- Applying ----------------------------------------------------------------


func apply() -> void:
    _ensure_buses()
    _route_players()
    _set_bus("Master", number("master_volume"))
    _set_bus("Music", number("music_volume"))
    _set_bus("Sfx", number("sfx_volume"))
    if DisplayServer.get_name() != "headless":
        var want_full := flag("fullscreen")
        var mode := DisplayServer.window_get_mode()
        var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
        if want_full and not is_full:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        elif not want_full and is_full:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if flag("vsync") else DisplayServer.VSYNC_DISABLED)
    # Frame cap (Emil, 2026-11-09: the target is a steady 60). Runs started with user args
    # (bots, captures, --perf) stay uncapped to show headroom unless they pass --fps-cap.
    var args := OS.get_cmdline_user_args()
    var capped := String(get_value("fps_cap")) == "60" and (args.is_empty() or args.has("--fps-cap"))
    Engine.max_fps = 60 if capped else 0
    if is_inside_tree():
        _apply_post_fx_all(get_tree().root)


func _set_bus(bus_name: String, linear: float) -> void:
    var idx := AudioServer.get_bus_index(bus_name)
    if idx < 0:
        return
    linear = clampf(linear, 0.0, 1.0)
    AudioServer.set_bus_mute(idx, linear <= 0.001)
    AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


## Music and Sfx buses sending into Master (which carries the compressor and limiter).
func _ensure_buses() -> void:
    for bus_name in ["Music", "Sfx"]:
        if AudioServer.get_bus_index(bus_name) >= 0:
            continue
        AudioServer.add_bus()
        var idx := AudioServer.bus_count - 1
        AudioServer.set_bus_name(idx, bus_name)
        AudioServer.set_bus_send(idx, "Master")


## Music and Sfx create their AudioStreamPlayers on Master; move them onto their buses.
func _route_players() -> void:
    for pair in [["/root/Music", "music"], ["/root/Sfx", "sfx"]]:
        var owner_node := get_node_or_null(String(pair[0]))
        if owner_node == null:
            continue
        var bus := bus_for(String(pair[1]))
        for c in owner_node.get_children():
            if c is AudioStreamPlayer and (c as AudioStreamPlayer).bus == "Master":
                (c as AudioStreamPlayer).bus = bus


func _on_node_added(node: Node) -> void:
    if node is PostFx:
        # Its ColorRect and material are built in its _ready; set uniforms after that.
        call_deferred("_apply_post_fx", node)
    elif node is AudioStreamPlayer and node.get_parent() != null:
        var parent_name := String(node.get_parent().name)
        if parent_name == "Music" or parent_name == "Sfx":
            call_deferred("_route_players")


func _apply_post_fx_all(n: Node) -> void:
    if n is PostFx:
        _apply_post_fx(n)
        return
    for c in n.get_children():
        _apply_post_fx_all(c)


## Push the CRT, bloom and on/off settings into one PostFx layer.
func _apply_post_fx(post: Node) -> void:
    if post == null or not is_instance_valid(post):
        return
    var layer := post as CanvasLayer
    if layer != null:
        layer.visible = flag("post_fx")
    var k := clampf(number("crt_intensity"), 0.0, 1.0) if flag("crt") else 0.0
    var params := {
        "crt_curve": CRT_FULL["crt_curve"] * k,
        "scanline": CRT_FULL["scanline"] * k,
        "aberration": CRT_FULL["aberration"] * k,
        "grain": GRAIN_BASE + float(CRT_FULL["grain"]) * k,
        "bloom_strength": BLOOM_ON if flag("bloom") else 0.0,
        "pixel_size": float(clampi(roundi(number("pixel_size")), 2, 4)),
        "palette_on": 1.0 if flag("palette") else 0.0,
    }
    for c in post.get_children():
        if c is CanvasItem and (c as CanvasItem).material is ShaderMaterial:
            var mat := (c as CanvasItem).material as ShaderMaterial
            for key in params.keys():
                mat.set_shader_parameter(key, params[key])
    # Exported knobs, if the PostFx script grows any of the same names.
    for key in ["crt_curve", "scanline", "aberration", "grain"]:
        if key in post:
            post.set(key, params[key])
    if "bloom" in post:
        post.set("bloom", params["bloom_strength"])


## Auto-pause: a joined pad dropping mid-run opens the pause menu.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
    if connected or not flag("pause_on_disconnect") or not is_inside_tree():
        return
    var scene := get_tree().current_scene
    if scene == null or not "pause_menu" in scene:
        return
    if scene.has_method("is_device_joined") and not scene.is_device_joined(device):
        return
    if "autotest" in scene and scene.get("autotest") == true:
        return
    var pm: Variant = scene.get("pause_menu")
    if pm != null and is_instance_valid(pm) and not pm.visible and pm.has_method("show_menu"):
        pm.show_menu()


# --- Persistence -------------------------------------------------------------


func save() -> void:
    var f := FileAccess.open(save_path, FileAccess.WRITE)
    if f == null:
        push_warning("Could not write settings file: %s" % save_path)
        return
    f.store_string(JSON.stringify(values, "  "))
    f.close()


func load_settings() -> void:
    values = DEFAULTS.duplicate()
    if not FileAccess.file_exists(save_path):
        return
    var f := FileAccess.open(save_path, FileAccess.READ)
    if f == null:
        return
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    f.close()
    if not parsed is Dictionary:
        return
    var d: Dictionary = parsed
    for key in DEFAULTS.keys():
        if not d.has(key):
            continue
        var def: Variant = DEFAULTS[key]
        if def is bool:
            values[key] = bool(d[key])
        elif def is String:
            values[key] = String(d[key])
        elif RANGES.has(key):
            var rg: Array = RANGES[key]
            values[key] = roundi(clampf(float(d[key]), float(rg[0]), float(rg[1])))
        else:
            values[key] = clampf(float(d[key]), 0.0, 1.0)
    # Combat text diet (2026-11-11): the old on/off switch becomes "all" / "big hits".
    if not d.has("dmg_numbers") and bool(d.get("damage_numbers", false)):
        values["dmg_numbers"] = "all"
    # Post-fx defaults moved to a crisp pixel look: older files drop the CRT once.
    var rev := int(d.get("fx_rev", 0))
    if rev < FX_REV:
        if rev < 2:
            values["crt"] = false
        if rev < 3:
            # Clarity pass: your own effects step back so enemies and their shots read.
            values["own_fx"] = minf(float(values["own_fx"]), float(DEFAULTS["own_fx"]))
        values["fx_rev"] = FX_REV
        save()
    if int(d.get("controls_rev", 0)) < CONTROLS_REV:
        values["aim_mode"] = "auto"
        values["damage_numbers"] = false
        values["fight_text"] = "quiet"
        values["controls_rev"] = CONTROLS_REV
        save()


