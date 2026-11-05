extends Node
## Autoload "Rumble": controller vibration that follows the game's sound. A spectrum
## analyzer sits on the "Sfx" bus (added at runtime, never saved to the bus layout); each
## frame its low band (20-180 Hz) drives the strong motor and its mid / high band
## (180-3000 Hz) the weak one, mapped from dB to 0..1 above a noise floor with a soft
## knee, smoothed (fast attack, ~120 ms release) and scaled by Settings "vibration".
##
## Sound rumble goes to every pad that belongs to a joined player (group "players", their
## `input.device`), or to the first connected pad in menus with no players. On top of it:
##   pulse(device, weak, strong, secs)  a short extra buzz on one pad (-1 = every target)
##   boom(strength)                     a big one on every pad (boss deaths and the like)
## and automatic pulses when a player loses HP (only their pad) or goes down.
## Vibration stops when the value is near zero, while the tree is paused (unless Settings
## "vibration_paused"), and on exit.

const BUS := "Sfx"
const LOW_BAND := Vector2(20.0, 180.0)
const MID_BAND := Vector2(180.0, 3000.0)
## dB window per band: at or below the floor is 0, at the ceiling 1.
const LOW_FLOOR_DB := -50.0
const LOW_CEIL_DB := -14.0
const MID_FLOOR_DB := -46.0
const MID_CEIL_DB := -12.0
const KNEE := 0.18              # soft knee width, as a share of the 0..1 range
const MID_GAIN := 0.7           # the weak motor buzzes harder per unit; keep it lighter
const ATTACK_SECS := 0.012
const RELEASE_SECS := 0.12
const SEND_SECS := 0.1          # duration passed to start_joy_vibration
const RESEND_SECS := 0.05       # re-send at least this often while vibrating
const RESEND_DELTA := 0.03      # or when a motor changes by this much
const OFF_BELOW := 0.02
const SILENT_DB := -90.0        # bus peak under this: nothing is playing
const DAMAGE_STRONG := 0.6
const DAMAGE_SECS := 0.18
const DOWN_STRONG := 1.0
const DOWN_WEAK := 0.8
const DOWN_SECS := 0.55
const PREVIEW_SECS := 0.35

var _bus_idx := -1
var _effect: AudioEffectSpectrumAnalyzer = null
var _instance: AudioEffectSpectrumAnalyzerInstance = null
var _resolve_in := 0.0
var _low := 0.0
var _mid := 0.0
var _pulses: Array = []          # { device, weak, strong, left, secs }
var _sent: Dictionary = {}       # device -> [weak, strong, secs since sent]
var _hp: Dictionary = {}         # player instance id -> [hp, alive]
var _preview := 0.0              # after the setting changes, buzz even while paused


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    AudioServer.bus_layout_changed.connect(_on_buses_changed)
    if AudioServer.has_signal("bus_renamed"):
        AudioServer.bus_renamed.connect(func(_i: int, _a: StringName, _b: StringName): _on_buses_changed())
    Settings.changed.connect(_on_setting_changed)
    Input.joy_connection_changed.connect(_on_joy_connection_changed)
    # Settings creates the Sfx bus in its own _ready; attach once everything is up.
    call_deferred("_ensure_analyzer")


func _exit_tree() -> void:
    _stop_all()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
        _stop_all()


# --- Public ------------------------------------------------------------------


## An extra buzz on `device` (-1 = every pad currently receiving rumble) for `secs`,
## added on top of the sound rumble and fading out over its last half.
func pulse(device: int, weak: float, strong: float, secs: float) -> void:
    if secs <= 0.0 or (weak <= 0.0 and strong <= 0.0):
        return
    _pulses.append({ "device": device, "weak": clampf(weak, 0.0, 1.0), "strong": clampf(strong, 0.0, 1.0),
        "left": secs, "secs": secs })


## A big rumble on every pad, `strength` 0..1 (e.g. a boss dying).
func boom(strength: float = 1.0) -> void:
    var s := clampf(strength, 0.0, 1.0)
    pulse(-1, 0.6 * s, s, 0.25 + 0.45 * s)


## Settings strength 0..1 (0 = off).
func strength() -> float:
    return clampf(Settings.number("vibration"), 0.0, 1.0)


# --- Analyzer ----------------------------------------------------------------


func _on_buses_changed() -> void:
    _instance = null
    _effect = null
    _bus_idx = -1
    call_deferred("_ensure_analyzer")


## Find (or add) the spectrum analyzer on the Sfx bus and grab its instance.
func _ensure_analyzer() -> void:
    _bus_idx = AudioServer.get_bus_index(BUS)
    _instance = null
    if _bus_idx < 0:
        return
    var at := -1
    for i in AudioServer.get_bus_effect_count(_bus_idx):
        if AudioServer.get_bus_effect(_bus_idx, i) is AudioEffectSpectrumAnalyzer:
            at = i
            break
    if at < 0:
        var fx := AudioEffectSpectrumAnalyzer.new()
        fx.buffer_length = 0.5
        fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
        AudioServer.add_bus_effect(_bus_idx, fx)
        at = AudioServer.get_bus_effect_count(_bus_idx) - 1
    _effect = AudioServer.get_bus_effect(_bus_idx, at) as AudioEffectSpectrumAnalyzer
    if not AudioServer.is_bus_effect_enabled(_bus_idx, at):
        AudioServer.set_bus_effect_enabled(_bus_idx, at, true)
    _instance = AudioServer.get_bus_effect_instance(_bus_idx, at, 0) as AudioEffectSpectrumAnalyzerInstance


## Still pointing at our effect? Other code may add or move effects on the bus.
func _analyzer_valid() -> bool:
    if _instance == null or _effect == null or _bus_idx < 0 or _bus_idx >= AudioServer.bus_count:
        return false
    if AudioServer.get_bus_name(_bus_idx) != BUS:
        return false
    for i in AudioServer.get_bus_effect_count(_bus_idx):
        if AudioServer.get_bus_effect(_bus_idx, i) == _effect:
            return true
    return false


## True while something is actually sounding on the bus. An idle bus stops processing
## its effects and the analyzer would keep replaying its old history.
func _bus_active() -> bool:
    var peak := maxf(AudioServer.get_bus_peak_volume_left_db(_bus_idx, 0), AudioServer.get_bus_peak_volume_right_db(_bus_idx, 0))
    if peak > SILENT_DB:
        return true
    # A muted bus (Sound volume 0) reports no peak; fall back to the Sfx voices.
    if AudioServer.is_bus_mute(_bus_idx):
        var sfx := get_node_or_null("/root/Sfx")
        if sfx != null:
            for c in sfx.get_children():
                if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing and (c as AudioStreamPlayer).bus == BUS:
                    return true
    return false


## dB to 0..1 between `floor_db` and `ceil_db`, with a quadratic knee at the bottom so
## quiet sounds fade in instead of switching on.
static func _map(db: float, floor_db: float, ceil_db: float) -> float:
    var x := clampf((db - floor_db) / (ceil_db - floor_db), 0.0, 1.5)
    var y := x * x / (2.0 * KNEE) if x < KNEE else x - KNEE * 0.5
    return clampf(y / (1.0 - KNEE * 0.5), 0.0, 1.0)


func _band_db(band: Vector2) -> float:
    var m := _instance.get_magnitude_for_frequency_range(band.x, band.y, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
    return linear_to_db(maxf(maxf(m.x, m.y), 0.00001))


# --- Frame -------------------------------------------------------------------


func _process(delta: float) -> void:
    _preview = maxf(0.0, _preview - delta)
    _resolve_in -= delta
    if _resolve_in <= 0.0:
        _resolve_in = 1.0
        if not _analyzer_valid():
            _ensure_analyzer()
    # Sound -> band targets.
    var low_t := 0.0
    var mid_t := 0.0
    if _instance != null and _bus_idx >= 0 and _bus_idx < AudioServer.bus_count and _bus_active():
        low_t = _map(_band_db(LOW_BAND), LOW_FLOOR_DB, LOW_CEIL_DB)
        mid_t = _map(_band_db(MID_BAND), MID_FLOOR_DB, MID_CEIL_DB) * MID_GAIN
    _low = _smooth(_low, low_t, delta)
    _mid = _smooth(_mid, mid_t, delta)
    # Pulses age even while vibration is off, so they never pile up.
    for i in range(_pulses.size() - 1, -1, -1):
        var p: Dictionary = _pulses[i]
        p["left"] = float(p["left"]) - delta
        if float(p["left"]) <= 0.0:
            _pulses.remove_at(i)
    var targets := _targets()
    _watch_players(targets)
    var k := strength()
    var gated := k <= 0.0 or (get_tree().paused and not Settings.flag("vibration_paused") and _preview <= 0.0)
    if gated:
        _stop_all()
        return
    var want: Dictionary = {}
    for d in targets:
        var weak := _mid
        var strong := _low
        for p in _pulses:
            var pd := int(p["device"])
            if pd != -1 and pd != int(d):
                continue
            var f := clampf(float(p["left"]) / (float(p["secs"]) * 0.5), 0.0, 1.0)
            weak += float(p["weak"]) * f
            strong += float(p["strong"]) * f
        want[int(d)] = Vector2(clampf(weak * k, 0.0, 1.0), clampf(strong * k, 0.0, 1.0))
    # Pads that stopped being targets go quiet.
    for d in _sent.keys():
        if not want.has(int(d)):
            _stop(int(d))
    for d in want.keys():
        _send(int(d), want[d], delta)


func _smooth(cur: float, target: float, delta: float) -> float:
    var tau := ATTACK_SECS if target > cur else RELEASE_SECS
    return lerpf(cur, target, 1.0 - exp(-delta / tau))


func _send(device: int, v: Vector2, delta: float) -> void:
    if v.x < OFF_BELOW and v.y < OFF_BELOW:
        _stop(device)
        return
    var last: Array = _sent.get(device, [])
    if not last.is_empty():
        var age := float(last[2]) + delta
        if age < RESEND_SECS and absf(float(last[0]) - v.x) < RESEND_DELTA and absf(float(last[1]) - v.y) < RESEND_DELTA:
            last[2] = age
            return
    Input.start_joy_vibration(device, v.x, v.y, SEND_SECS)
    _sent[device] = [v.x, v.y, 0.0]


func _stop(device: int) -> void:
    if _sent.has(device):
        _sent.erase(device)
        Input.stop_joy_vibration(device)


func _stop_all() -> void:
    for d in _sent.keys():
        Input.stop_joy_vibration(int(d))
    _sent.clear()


# --- Players -----------------------------------------------------------------


func _players() -> Array:
    if not is_inside_tree():
        return []
    return get_tree().get_nodes_in_group("players")


## Pads to rumble: every connected pad owned by a joined player, else (menus, the hub
## with keyboard-only players) the first connected pad.
func _targets() -> Array:
    var pads := Input.get_connected_joypads()
    var out: Array = []
    for p in _players():
        var dev := _device_of(p)
        if dev >= 0 and pads.has(dev) and not out.has(dev):
            out.append(dev)
    if out.is_empty() and not pads.is_empty():
        out.append(int(pads[0]))
    return out


func _device_of(p: Node) -> int:
    if p == null or not is_instance_valid(p) or not "input" in p:
        return -1
    var inp: Variant = p.get("input")
    if inp == null or not (inp is Object) or not "device" in inp:
        return -1
    return int(inp.get("device"))


## Poll each player's HP: a drop pulses that player's pad, going down a bigger one.
func _watch_players(targets: Array) -> void:
    var seen: Dictionary = {}
    for p in _players():
        if not is_instance_valid(p) or not "hp" in p:
            continue
        var id: int = p.get_instance_id()
        seen[id] = true
        var hp := float(p.get("hp"))
        var alive := bool(p.get("alive")) if "alive" in p else hp > 0.0
        var max_hp := maxf(1.0, float(p.get("max_hp"))) if "max_hp" in p else 100.0
        if _hp.has(id):
            var prev: Array = _hp[id]
            var dev := _device_of(p)
            if dev >= 0 and targets.has(dev):
                if bool(prev[1]) and not alive:
                    pulse(dev, DOWN_WEAK, DOWN_STRONG, DOWN_SECS)
                elif hp < float(prev[0]) - 0.5 and alive:
                    var dmg := float(prev[0]) - hp
                    var s := clampf(0.5 + dmg / max_hp * 5.0, 0.5, 1.6)
                    pulse(dev, DAMAGE_STRONG * s * 0.35, DAMAGE_STRONG * s, DAMAGE_SECS)
        _hp[id] = [hp, alive]
    for id in _hp.keys():
        if not seen.has(id):
            _hp.erase(id)


# --- Signals -----------------------------------------------------------------


func _on_setting_changed(key: String) -> void:
    if key != "vibration":
        return
    if strength() <= 0.0:
        _stop_all()
        return
    # Let the player feel the new strength, even from the pause menu.
    _preview = PREVIEW_SECS
    pulse(-1, 0.35, 0.6, PREVIEW_SECS)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
    if not connected:
        _sent.erase(device)
