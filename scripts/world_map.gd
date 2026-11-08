class_name WorldMap
extends Control
## The Cartographer's world map in the Hollow (design section 8 and Phase 4): the Descent
## by depth, its edges, the regions that exist today, and every shortcut opened so far.
## Drawn in code. It takes no input of its own: the panel's Back button has the focus, so a
## gamepad, the keyboard and the mouse all leave it the same way.

const ROW := 84.0
const TOP := 34.0
const GATE := Color(1.0, 0.82, 0.35)


func _init() -> void:
    custom_minimum_size = Vector2(900, TOP + ROW * float(Regions.DEPTHS - 1) + 60.0)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


## Each region's centre on the map.
func _spots() -> Dictionary:
    var by_depth: Dictionary = {}
    for id in Regions.REGIONS.keys():
        var d := Regions.depth_of(String(id))
        if not by_depth.has(d):
            by_depth[d] = []
        by_depth[d].append(String(id))
    var out: Dictionary = {}
    var w := custom_minimum_size.x
    for d in by_depth.keys():
        var ids: Array = by_depth[d]
        for i in ids.size():
            out[ids[i]] = Vector2(w * (float(i) + 0.5) / float(ids.size()), TOP + ROW * float(int(d) - 1))
    return out


func _draw() -> void:
    var spots := _spots()
    var font: Font = Art.FONT_BODY
    for id in spots.keys():
        var built := bool(Regions.REGIONS[id]["built"])
        for n in Regions.REGIONS[id]["edges"]:
            if not spots.has(n):
                continue
            var both: bool = built and bool(Regions.REGIONS[n]["built"])
            draw_line(spots[id] + Vector2(0, 12), spots[n] - Vector2(0, 14), Color(0.85, 0.8, 0.7, 0.55 if both else 0.15), 2.0 if both else 1.0)
    for id in spots.keys():
        var at: Vector2 = spots[id]
        var built := bool(Regions.REGIONS[id]["built"])
        var col := Color(0.93, 0.89, 0.80) if built else Color(0.55, 0.52, 0.48, 0.6)
        var label := Regions.display_name(id) if built else "unmapped"
        var gate := Shortcuts.gate_id(id)
        var open := built and Shortcuts.is_open(gate)
        draw_rect(Rect2(at - Vector2(84, 12), Vector2(168, 26)), Color(0.05, 0.04, 0.06, 0.9))
        draw_rect(Rect2(at - Vector2(84, 12), Vector2(168, 26)), GATE if open else Color(col, 0.6), false, 2.0 if open else 1.0)
        draw_string(font, at + Vector2(-84, 7), label, HORIZONTAL_ALIGNMENT_CENTER, 168, 18, col)
        if open:
            # A gate mark: two posts and a bar, beside the region.
            var g := at + Vector2(96, 0)
            draw_line(g + Vector2(-6, -9), g + Vector2(-6, 9), GATE, 3.0)
            draw_line(g + Vector2(6, -9), g + Vector2(6, 9), GATE, 3.0)
            draw_line(g + Vector2(-6, -3), g + Vector2(6, -3), GATE, 2.0)
            draw_line(g + Vector2(-6, 3), g + Vector2(6, 3), GATE, 2.0)
        if built and id == String(Shortcuts.DEFS[Shortcuts.SLUICE]["region"]) and Shortcuts.is_open(Shortcuts.SLUICE):
            # The sluice: three falling waves on the region's other side.
            var s := at + Vector2(-100, 0)
            for k in 3:
                var y := -7.0 + 7.0 * float(k)
                draw_polyline(PackedVector2Array([s + Vector2(-8, y), s + Vector2(-3, y - 3), s + Vector2(2, y), s + Vector2(7, y - 3)]), GATE, 2.0)
    draw_string(font, Vector2(0, custom_minimum_size.y - 8), "Depth 1 at the top, the Rift at the bottom. Gold: a gate or sluice you opened.", HORIZONTAL_ALIGNMENT_CENTER, custom_minimum_size.x, 16, Color(0.7, 0.66, 0.6))
