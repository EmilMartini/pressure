extends Node
## Identity proof and benchmark for the materials grid step. Drives two versions of
## scripts/materials.gd through the same seeded workload (every element stamped, dropped and
## ignited, gales, filled and still pools, wipes, raised ground, shocked floods that hit the
## STEP_CAP carry-over) with a real Fx node, and compares the grid's state hash after every
## step plus the global RNG position at the end. Also times the steps.
##
##   git show <rev>:scripts/materials.gd | sed -e '/^class_name Materials/d' ##       -e 's/var mats: Materials/var mats/' > autotest/materials_old.gd
##   godot --headless --path . res://tools/grid_replay.tscn -- --old=res://autotest/materials_old.gd
##
## (A scene, not `-s`, so the autoloads exist. The old copy must not declare `class_name
## Materials`.) Prints [REPLAY] per scenario and [REPLAY-CHECK] PASS/FAIL.

const STEPS := 360
const SCENARIOS := [
    { "seed": 1, "raise": false, "gas": false, "flood": false },
    { "seed": 2, "raise": true, "gas": true, "flood": false },
    { "seed": 3, "raise": false, "gas": true, "flood": true },
    { "seed": 4, "raise": true, "gas": false, "flood": true },
    { "seed": 5, "raise": false, "gas": false, "flood": true },
]
const ROOM := Rect2(-560, -360, 1120, 720)


func _ready() -> void:
    _go.call_deferred()


func _go() -> void:
    var old_path := ""
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--old="):
            old_path = a.substr(6)
    if old_path == "":
        print("[REPLAY-CHECK] FAIL: pass --old=res://path/to/old/materials.gd")
        get_tree().quit(1)
        return
    var old_script: GDScript = load(old_path)
    var new_script: GDScript = load("res://scripts/materials.gd")
    var ok := true
    var t_old := 0
    var t_new := 0
    var worst_old := 0
    var worst_new := 0
    for sc: Dictionary in SCENARIOS:
        var a := _run(old_script, sc)
        var b := _run(new_script, sc)
        var ha: Array = a["hashes"]
        var hb: Array = b["hashes"]
        var first_diff := -1
        for k in mini(ha.size(), hb.size()):
            if ha[k] != hb[k]:
                first_diff = k
                break
        var same: bool = first_diff < 0 and ha.size() == hb.size() and a["rng"] == b["rng"] and a["stats"] == b["stats"]
        ok = ok and same
        t_old += int(a["usec"])
        t_new += int(b["usec"])
        worst_old = maxi(worst_old, int(a["worst"]))
        worst_new = maxi(worst_new, int(b["worst"]))
        print("[REPLAY] seed=%d steps=%d %s first_diff=%d rng=%d/%d stats=%s/%s cells_stepped=%d step_ms old=%.3f new=%.3f worst_ms old=%.2f new=%.2f sweep_step_ms old=%.2f new=%.2f ops_ms old=%.3f new=%.3f" % [
            sc["seed"], ha.size(), "SAME" if same else "DIFFERENT", first_diff, a["rng"], b["rng"], str(a["stats"]), str(b["stats"]),
            a["cells"], float(a["usec"]) / 1000.0 / STEPS, float(b["usec"]) / 1000.0 / STEPS, float(a["worst"]) / 1000.0, float(b["worst"]) / 1000.0,
            float(a["sweep"]) / 1000.0 / (STEPS / 12), float(b["sweep"]) / 1000.0 / (STEPS / 12),
            float(a["ops"]) / 1000.0 / STEPS, float(b["ops"]) / 1000.0 / STEPS])
    print("[REPLAY-CHECK] %s scenarios=%d steps=%d mean_step_ms old=%.3f new=%.3f (%.0f%%) worst_ms old=%.2f new=%.2f" % [
        "PASS" if ok else "FAIL", SCENARIOS.size(), STEPS, float(t_old) / 1000.0 / (STEPS * SCENARIOS.size()),
        float(t_new) / 1000.0 / (STEPS * SCENARIOS.size()), 100.0 * float(t_new) / maxf(1.0, float(t_old)),
        worst_old / 1000.0, worst_new / 1000.0])
    if Perf.on:   # --perf: whatever Perf labels the new version adds, per step
        var parts := PackedStringArray()
        for k in Perf.totals:
            parts.append("%s=%.3fms/%d" % [k, float(Perf.totals[k]) / 1000.0 / (STEPS * SCENARIOS.size()), Perf.calls[k]])
        print("[REPLAY-LABELS] per step: " + ", ".join(parts))
    get_tree().quit(0 if ok else 1)


func _run(script: GDScript, sc: Dictionary) -> Dictionary:
    var holder_gs := GDScript.new()
    holder_gs.source_code = "extends Node2D\nvar fx\nvar current\n"
    holder_gs.reload()
    var holder: Node2D = holder_gs.new()
    add_child(holder)
    get_tree().current_scene = holder
    var fx := Fx.new()
    holder.add_child(fx)
    holder.set("fx", fx)
    seed(int(sc["seed"]) * 7919)
    var rng := RandomNumberGenerator.new()   # the workload: never touches the global RNG
    rng.seed = int(sc["seed"])
    script.set("gas_ignites", bool(sc["gas"]))
    script.set("stat_gas_lit", 0)
    script.set("stat_zapped", 0)
    var m: Node2D = script.new(ROOM)
    holder.add_child(m)
    m.set_process(false)
    if sc["raise"]:
        m.raise_rect(Rect2(-200, -120, 160, 90))
        m.raise_rect(Rect2(150, 60, 220, 60))
    if sc["flood"]:
        m.lay_still(Element.Kind.WET, m.indices_in(Rect2(-500, -300, 900, 520)), 0, 100000, 200)
    var hashes: Array = []
    var usec := 0
    var worst := 0
    var cells := 0
    var sweep_usec := 0
    var ops_usec := 0   # stamps, drops, fills and reads between steps
    var kinds := [Element.Kind.WET, Element.Kind.OIL, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.POISON,
        Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.FIRE,
        Element.Kind.SHOCK]
    for step in STEPS:
        var ops := rng.randi_range(0, 5)
        var t_ops := Time.get_ticks_usec()
        for o in ops:
            var p := Vector2(rng.randf_range(ROOM.position.x, ROOM.end.x), rng.randf_range(ROOM.position.y, ROOM.end.y))
            var r := rng.randi() % 10
            if r < 5:
                m.stamp(kinds[rng.randi() % kinds.size()], p, rng.randf_range(6.0, 140.0), rng.randi_range(20, 255), rng.randi() % 4 == 0)
            elif r == 5:
                for k in 8:
                    m.drop(kinds[rng.randi() % kinds.size()], p + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), rng.randi_range(20, 200), rng.randi() % 3 == 0)
            elif r == 6:
                m.heat_at(p)
                m.ignite(p, rng.randf_range(6.0, 60.0), rng.randi() % 2 == 0)
            elif r == 7:
                m.fill_rect([Element.Kind.WET, Element.Kind.OIL, Element.Kind.ICE][rng.randi() % 3], Rect2(p, Vector2(rng.randf_range(20, 160), rng.randf_range(20, 120))), rng.randi_range(40, 255), rng.randi_range(-1, 60))
            elif r == 8:
                var idx: PackedInt32Array = m.indices_in(Rect2(p, Vector2(rng.randf_range(20, 200), rng.randf_range(20, 120))))
                m.lay_still([Element.Kind.WET, Element.Kind.OIL, Element.Kind.ICE][rng.randi() % 3], idx, 0, rng.randi_range(1, idx.size() + 1), rng.randi_range(60, 255))
            elif rng.randi() % 4 == 0:
                m.clear_rect(Rect2(p, Vector2(rng.randf_range(10, 120), rng.randf_range(10, 80))))
            m.material_at(p)
            m.is_slippery(p)
        ops_usec += Time.get_ticks_usec() - t_ops
        cells += mini(int(m.get("_queue").size()) - int(m.get("_head")), 2500)
        var t := Time.get_ticks_usec()
        m._step()
        var dt := Time.get_ticks_usec() - t
        usec += dt
        worst = maxi(worst, dt)
        if (step + 1) % 12 == 0:
            sweep_usec += dt   # the 1 Hz sweep runs in this step
        hashes.append(m._state_hash())
    var out := { "hashes": hashes, "usec": usec, "worst": worst, "cells": cells, "rng": randi(), "sweep": sweep_usec, "ops": ops_usec,
        "stats": [script.get("stat_gas_lit"), script.get("stat_zapped")] }
    remove_child(holder)
    holder.free()
    return out
