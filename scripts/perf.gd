extends Node
## Temporary profiler: accumulates microseconds per label, printed by the bot's --perf probe.
## Also splits the frame: phys.scripts (all _physics_process callbacks of the ticks),
## phys.engine (physics server step after the callbacks), proc.scripts (all _process
## callbacks), frame.total (wall time between frames).
var totals: Dictionary = {}
var calls: Dictionary = {}
var _tick_start := 0
var _tick_end := 0
var _proc_start := 0
var _last_frame := 0


class Probe extends Node:
    var perf: Node
    var role := 0
    func _physics_process(_d: float) -> void:
        perf._phys(role)
    func _process(_d: float) -> void:
        perf._proc(role)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
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
            add("frame.total", now - _last_frame)
        _last_frame = now
        _proc_start = now
    else:
        add("proc.scripts", now - _proc_start)


func add(label: String, usec: int) -> void:
    totals[label] = int(totals.get(label, 0)) + usec
    calls[label] = int(calls.get(label, 0)) + 1


func report(frames: int) -> String:
    var keys := totals.keys()
    keys.sort_custom(func(a, b): return int(totals[a]) > int(totals[b]))
    var parts: Array = []
    for k in keys.slice(0, 18):
        parts.append("%s=%.2fms" % [k, float(totals[k]) / 1000.0 / float(maxi(frames, 1))])
    # Physics per tick (60 Hz), not per drawn frame.
    var ticks := int(calls.get("phys.scripts", 0))
    if ticks > 0:
        for k in keys:
            var ks := String(k)
            if ks.begins_with("phys.") or ks.contains("physics") or ks.contains("body_entered") or ks.contains("move_and_slide") or ks.contains("grid") or ks.contains("hits"):
                parts.append("tick:%s=%.3fms" % [ks, float(totals[k]) / 1000.0 / float(ticks)])
    totals.clear()
    calls.clear()
    return ", ".join(parts)
