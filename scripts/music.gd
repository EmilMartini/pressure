extends Node
## Autoload "Music": a playlist player. Each mood has a pool of tracks; play(mood) picks
## one from a shuffle bag (never the one that just played in that pool), crossfades to it,
## and when it nears its end moves on to the next pick instead of looping the same file.
## Deeper floors lean the run pool toward its later tracks (set_floor). An intensity knob
## (set_intensity, 0 calm .. 1 fight) closes a low-pass filter and dips the level a little
## when the room is calm. Missing files are skipped, never an error.
## Tracks by Kevin MacLeod (incompetech.com), CC BY 4.0; see assets/music/CREDITS.txt.

const DIR := "res://assets/music/"
const POOLS := {
    "menu": ["menu.ogg", "menu2.ogg"],
    "hub": ["hub.ogg", "menu2.ogg", "menu.ogg"],
    "run": ["run.ogg", "run2.ogg", "run3.ogg", "run4.ogg", "run5.ogg", "run6.ogg"],
    "boss": ["boss.ogg", "boss2.ogg", "boss3.ogg"],
    "ambient": ["ambient.ogg", "menu2.ogg"],
}
const VOLUME_DB := -10.0
const DUCK_DB := -22.0
const SILENT_DB := -50.0
const CROSSFADE := 2.0
const BUS := "Music"
## Intensity 0 dips the level by this much and closes the low-pass to CUTOFF_CALM.
const CALM_DB := -4.0
const CUTOFF_CALM := 1100.0
const CUTOFF_OPEN := 20000.0

var enabled := true
var current := ""         # mood playing ("" when stopped)
var track := ""           # file name playing
var floor_number := 1
var intensity := 1.0      # target, 0..1
var _intensity_now := 1.0 # smoothed
var _volume_db := VOLUME_DB
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _ducked := false
var _tweens: Array = [null, null]
var _bags: Dictionary = {}    # mood -> Array[String] still to play this cycle
var _last: Dictionary = {}    # mood -> file played last in that pool
var _streams: Dictionary = {} # path -> AudioStream
var _advancing := false       # the active track already handed over to the next
var _lpf: AudioEffectLowPassFilter
var _amp: AudioEffectAmplify
var _dip_db := 0.0        # short duck from Sfx on big moments (dip), eases back to 0
var _dip_hold := 0.0
var phase_cap := 1.0      # boss phase 1 holds the filter a little closed (boss_phase)
var _pitch := 1.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _setup_bus()
    for i in 2:
        var p := AudioStreamPlayer.new()
        p.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else "Master"
        p.volume_db = SILENT_DB
        p.finished.connect(_on_finished.bind(i))
        add_child(p)
        _players.append(p)
    _apply_intensity()


# --- Public API ----------------------------------------------------------------


## Switch to a mood's pool. Same mood as now: keeps the track that is playing.
func play(mood: String, fade: float = CROSSFADE) -> void:
    if mood != "boss" and (phase_cap < 1.0 or _pitch != 1.0):
        boss_phase(0)   # a boss fight's layering never follows you out of it
    if not enabled or mood == current or not POOLS.has(mood):
        return
    var file := _pick(mood)
    if file == "":
        stop(fade)
        return
    current = mood
    _start(file, fade)
    if mood == "boss":
        _preload_pool(mood)


## Skip to the next pick of the current pool.
func next(fade: float = CROSSFADE) -> void:
    if current == "":
        return
    var file := _pick(current)
    if file != "":
        _start(file, fade)


func stop(fade: float = 1.2) -> void:
    current = ""
    track = ""
    _advancing = true
    for i in 2:
        _fade(i, SILENT_DB, fade, true)


func duck(on: bool) -> void:
    _ducked = on
    if current != "":
        _fade(_active, _target_db(), 0.4)


## Pull the music down by `db` for `seconds`, then ease back (Sfx calls this on boss
## deaths, unlock fanfares and the like). Rides on the intensity amplify, never the bus.
func dip(db: float, seconds: float) -> void:
    _dip_db = minf(_dip_db, -absf(db))
    _dip_hold = maxf(_dip_hold, seconds)
    _apply_intensity()


## Base music level in dB (default VOLUME_DB). The user's volume slider lives on the bus.
func set_volume_db(db: float) -> void:
    _volume_db = db
    if current != "":
        _fade(_active, _target_db(), 0.3)


## Deeper floors make the run pool prefer its later tracks.
func set_floor(n: int) -> void:
    floor_number = maxi(1, n)


## A music layer per boss phase (design section 6, rule 4), from what this player has: phase
## 1 holds the filter a little closed, phase 2 crossfades to the next boss track wide open,
## phase 3 crossfades again and lifts the pitch a touch. 0 ends the fight's layering.
func boss_phase(n: int) -> void:
    match n:
        0:
            phase_cap = 1.0
            _set_pitch(1.0)
        1:
            phase_cap = 0.7
            _set_pitch(1.0)
        2:
            phase_cap = 1.0
            next(0.6)
        _:
            phase_cap = 1.0
            next(0.5)
            _set_pitch(1.06)
    _apply_intensity()
    if BossBody.log_enabled:
        print("[MUSIC] boss phase=%d track=%s pitch=%.2f cap=%.2f" % [n, track, _pitch, phase_cap])


func _set_pitch(v: float) -> void:
    _pitch = v
    for p in _players:
        p.pitch_scale = v


## 0 = calm (filtered and a little quieter), 1 = full fight (default). Eased over ~1 s.
func set_intensity(v: float) -> void:
    intensity = clampf(v, 0.0, 1.0)


# --- Picking ---------------------------------------------------------------------


func _available(mood: String) -> Array[String]:
    var out: Array[String] = []
    var files: Array = POOLS.get(mood, [])
    for f in files:
        var fname := String(f)
        if ResourceLoader.exists(DIR + fname):
            out.append(fname)
    return out


## Shuffle bag per pool: every track plays once per cycle, never the same one twice in a
## row; the run pool weights later tracks more on deeper floors.
func _pick(mood: String) -> String:
    var avail := _available(mood)
    if avail.is_empty():
        return ""
    var last := String(_last.get(mood, ""))
    var bag: Array = _bags.get(mood, [])
    # Drop entries whose file vanished.
    for i in range(bag.size() - 1, -1, -1):
        if not avail.has(String(bag[i])):
            bag.remove_at(i)
    if bag.is_empty() or (bag.size() == 1 and String(bag[0]) == last and avail.size() > 1):
        bag = []
        for f in avail:
            if f != last or avail.size() == 1:
                bag.append(f)
    var files: Array = POOLS[mood]
    var n := files.size()
    var depth := clampf(float(floor_number - 1) / 4.0, 0.0, 1.0)
    var weights: Array[float] = []
    var total := 0.0
    for f in bag:
        var w := 1.0
        if mood == "run" and n > 1:
            var t := float(files.find(f)) / float(n - 1)
            w = lerpf(1.0 + 2.0 * (1.0 - t), 1.0 + 3.0 * t, depth)
        if String(f) == last and bag.size() > 1:
            w = 0.0
        weights.append(w)
        total += w
    var idx := 0
    if total > 0.0:
        var r := randf() * total
        for i in weights.size():
            r -= weights[i]
            if r <= 0.0:
                idx = i
                break
    var chosen := String(bag[idx])
    bag.remove_at(idx)
    _bags[mood] = bag
    _last[mood] = chosen
    return chosen


## The rest of a pool loads in the background while its first track plays: a boss's phase
## change switches track mid-fight, and loading an ogg there was a 15 ms hitch.
func _preload_pool(mood: String) -> void:
    for f in _available(mood):
        var path := DIR + String(f)
        if not _streams.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
            ResourceLoader.load_threaded_request(path)


func _stream(file: String) -> AudioStream:
    var path := DIR + file
    if _streams.has(path):
        return _streams[path]
    if not ResourceLoader.exists(path):
        return null
    var res: Resource = null
    if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
        res = ResourceLoader.load_threaded_get(path)   # preloaded (waits if still loading)
    else:
        res = load(path)
    var s := res as AudioStream
    if s == null:
        return null
    # Playlist: tracks end and hand over instead of looping.
    if "loop" in s:
        s.set("loop", false)
    _streams[path] = s
    return s


# --- Playback --------------------------------------------------------------------


func _start(file: String, fade: float) -> void:
    var stream := _stream(file)
    if stream == null:
        return
    track = file
    _advancing = false
    _active = 1 - _active
    var p := _players[_active]
    p.stream = stream
    p.pitch_scale = _pitch
    p.volume_db = SILENT_DB
    p.play()
    _fade(_active, _target_db(), fade)
    _fade(1 - _active, SILENT_DB, fade, true)


func _on_finished(i: int) -> void:
    if i != _active or current == "" or _advancing:
        return
    _advancing = true
    next(0.6)


func _process(delta: float) -> void:
    # Real time, so a hit-stop or pause does not stall the music logic.
    var real := delta / maxf(Engine.time_scale, 0.001)
    if not is_equal_approx(_intensity_now, intensity):
        _intensity_now = move_toward(_intensity_now, intensity, real * 1.2)
        _apply_intensity()
    if _dip_hold > 0.0:
        _dip_hold -= real
    elif _dip_db < 0.0:
        _dip_db = minf(0.0, _dip_db + real * 10.0)
        _apply_intensity()
    # Hand over to the next track a crossfade before this one ends.
    if current == "" or _advancing or _players.is_empty():
        return
    var p := _players[_active]
    if not p.playing or p.stream == null:
        return
    var length := p.stream.get_length()
    if length > CROSSFADE * 3.0 and length - p.get_playback_position() <= CROSSFADE:
        _advancing = true
        next(CROSSFADE)


func _target_db() -> float:
    return _volume_db + (DUCK_DB - VOLUME_DB if _ducked else 0.0)


func _fade(i: int, to_db: float, seconds: float, stop_after: bool = false) -> void:
    if _tweens[i] != null and _tweens[i].is_valid():
        _tweens[i].kill()
    var p := _players[i]
    var tw := create_tween()
    tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
    tw.set_ignore_time_scale(true)
    tw.tween_property(p, "volume_db", to_db, maxf(seconds, 0.01))
    if stop_after:
        tw.tween_callback(p.stop)
    _tweens[i] = tw


# --- Bus -------------------------------------------------------------------------


## A Music bus sending into Master, with a low-pass and an amplify for intensity. The
## user's music volume is the bus volume (Settings); intensity never touches it.
func _setup_bus() -> void:
    var idx := AudioServer.get_bus_index(BUS)
    if idx < 0:
        AudioServer.add_bus()
        idx = AudioServer.bus_count - 1
        AudioServer.set_bus_name(idx, BUS)
        AudioServer.set_bus_send(idx, "Master")
    for e in AudioServer.get_bus_effect_count(idx):
        var fx := AudioServer.get_bus_effect(idx, e)
        if fx is AudioEffectLowPassFilter and _lpf == null:
            _lpf = fx
        elif fx is AudioEffectAmplify and _amp == null:
            _amp = fx
    if _lpf == null:
        _lpf = AudioEffectLowPassFilter.new()
        _lpf.cutoff_hz = CUTOFF_OPEN
        AudioServer.add_bus_effect(idx, _lpf)
    if _amp == null:
        _amp = AudioEffectAmplify.new()
        AudioServer.add_bus_effect(idx, _amp)


func _apply_intensity() -> void:
    var k := minf(_intensity_now, phase_cap)
    if _lpf != null:
        _lpf.cutoff_hz = CUTOFF_CALM * pow(CUTOFF_OPEN / CUTOFF_CALM, k)
    if _amp != null:
        _amp.volume_db = lerpf(CALM_DB, 0.0, k) + _dip_db
