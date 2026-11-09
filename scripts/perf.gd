extends Node
## Bot profiler, active only with `--perf` (nothing runs otherwise). Cheap while the run
## lasts: it stores each frame's wall time in a packed array and adds microseconds per label
## (`Perf.add`, behind `Perf.on`), and prints everything once at the end (`summary`), so the
## measurement itself causes no hitches. Splits each frame into phys.scripts (all
## _physics_process callbacks of the ticks), phys.engine (physics server step after the
## callbacks), proc.scripts (all _process callbacks) and frame.total (wall time between frames).
## A frame of 16 ms or more is a spike: the labels that cost the most in it are kept (first
## 200) and printed at the end as [SPIKE] lines.
var on := false
var totals: Dictionary = {}
var calls: Dictionary = {}
var frames := PackedInt32Array()   # wall time per frame, usec
var _skip := 60                     # first frames after load are not counted
var _tick_start := 0
var _tick_end := 0
var _proc_start := 0
var _last_frame := 0
var _ft: Dictionary = {}            # this frame's labels
var _spikes: PackedStringArray = []


class Probe extends Node:
    var perf: Node
    var role := 0
    func _physics_process(_d: float) -> void:
        perf._phys(role)
    func _process(_d: float) -> void:
        perf._proc(role)


func _ready() -> void:
    on = OS.get_cmdline_user_args().has("--perf")
    if not on:
        return
    process_mode = Node.PROCESS_MODE_ALWAYS
    frames.resize(0)
    for role in 2:
        var p := Probe.new()
        p.perf = self
        p.role = role
        p.process_mode = Node.PROCESS_MODE_ALWAYS
        p.process_physics_priority = -1000000 if role == 0 else 1000000
        p.process_priority = -1000000 if role == 0 else 1000000
        add_child(p)


func _phys(role: int) -> void:
    var now := Time.get_ticks_usec()
    if role == 0:
        if _tick_end > 0 and _tick_end > _proc_start:
            add("phys.engine", now - _tick_end)   # back-to-back ticks: the step between them
            _tick_end = 0
        _tick_start = now
    else:
        add("phys.scripts", now - _tick_start)
        _tick_end = now


func _proc(role: int) -> void:
    var now := Time.get_ticks_usec()
    if role == 0:
        if _tick_end > 0:
            add("phys.engine", now - _tick_end)
            _tick_end = 0
        if _last_frame > 0:
            var ft := now - _last_frame
            if _skip > 0:
                _skip -= 1
            else:
                frames.append(ft)
                if ft >= 16000 and _spikes.size() < 200:
                    var ks := _ft.keys()
                    ks.sort_custom(func(a, c): return _ft[a] > _ft[c])
                    var parts := PackedStringArray()
                    for k in ks.slice(0, 8):
                        parts.append("%s=%.1f" % [k, _ft[k] / 1000.0])
                    _spikes.append("[SPIKE] frame=%d ft=%.1f %s" % [frames.size(), ft / 1000.0, " ".join(parts)])
        _ft.clear()
        _last_frame = now
        _proc_start = now
    else:
        add("proc.scripts", now - _proc_start)


## Microseconds against a label (call only when `Perf.on`).
func add(label: String, usec: int) -> void:
    _ft[label] = int(_ft.get(label, 0)) + usec
    totals[label] = int(totals.get(label, 0)) + usec
    calls[label] = int(calls.get(label, 0)) + 1


## The whole run: mean fps, 1% low (mean of the slowest 1% of frames), frame-time buckets,
## per-label cost, then the spike lines.
func summary() -> String:
    var n := frames.size()
    if n == 0:
        return "[PERF-SUMMARY] no frames"
    var sorted := frames.duplicate()
    sorted.sort()
    var total := 0
    for ft in frames:
        total += ft
    var worst := maxi(1, n / 100)
    var wsum := 0
    for k in worst:
        wsum += sorted[n - 1 - k]
    var b := [0, 0, 0, 0]   # >=12.5, >=16, >=25, >=50 ms
    var lost := 0           # wall time past 10 ms in frames of 12.5 ms or more
    for ft in frames:
        if ft >= 12500:
            b[0] += 1
            lost += ft - 10000
        if ft >= 16000:
            b[1] += 1
        if ft >= 25000:
            b[2] += 1
        if ft >= 50000:
            b[3] += 1
    var lines := PackedStringArray()
    lines.append("[PERF-SUMMARY] frames=%d secs=%.1f mean_fps=%.1f low1_fps=%.1f median_ms=%.2f p99_ms=%.1f max_ms=%.1f over12=%d over16=%d over25=%d over50=%d lost_s=%.2f" % [
        n, total / 1e6, n / (total / 1e6), 1e6 / (float(wsum) / worst), sorted[n / 2] / 1000.0,
        sorted[mini(n - 1, n * 99 / 100)] / 1000.0, sorted[n - 1] / 1000.0, b[0], b[1], b[2], b[3], lost / 1e6])
    var hist := PackedInt32Array()
    hist.resize(41)
    for ft in frames:
        hist[mini(40, ft / 1000)] += 1
    var hs := PackedStringArray()
    for k in 41:
        if hist[k] > 0:
            hs.append("%d:%d" % [k, hist[k]])
    lines.append("[PERF-HIST] refresh=%.0f ms:frames %s" % [DisplayServer.screen_get_refresh_rate(), " ".join(hs)])
    var keys := totals.keys()
    keys.sort_custom(func(a, c): return int(totals[a]) > int(totals[c]))
    var parts := PackedStringArray()
    for k in keys.slice(0, 30):
        parts.append("%s=%.3fms/%d" % [k, float(totals[k]) / 1000.0 / float(n), calls[k]])
    lines.append("[PERF-LABELS] per frame: " + ", ".join(parts))
    lines.append_array(_spikes)
    return "\n".join(lines)
