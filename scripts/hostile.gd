class_name Hostile
extends RefCounted
## Friend or foe (GDD "Friend or foe"): everything that can hurt the player wears one
## signature the player's own effects never use. A near-black outline with a hot red rim
## for shots, a marching black and red dashed edge for areas (blast zones, lit fuses, floor
## that burns or shocks near the player), always on the Crisp layer: above every particle,
## cloud and bloom of the player's guns, and never pixelated, bloomed or palette-shifted.
## The player's own projectiles, beams, sprays, pools and clouds are never outlined dark
## or rimmed red, and can be dimmed with the "Your effects" option (Settings.own_fx).

const RED := Color(1.0, 0.12, 0.10)
const DARK := Color(0.05, 0.0, 0.03)
## Marching speed of dashed edges, in dash lengths per second.
const MARCH := 2.0


## One world pixel cell (Settings "pixel_size" screen pixels) in `cv`'s local units, so
## hostile edges are drawn in whole cells like the pixelated world under them.
static func cell(cv: CanvasItem) -> float:
    var ps := PostFx.pixel_size() if Settings.flag("post_fx") else 1.0
    return ps / maxf(0.05, cv.get_global_transform_with_canvas().get_scale().x)


## `pts` (local to `cv`) moved onto the screen's cell grid (the PostFx pixel grid): onto
## the grid lines for even widths, onto cell centres (`half`) for a 1-cell line.
static func snap(cv: CanvasItem, pts: PackedVector2Array, half: bool = false) -> PackedVector2Array:
    var xf := cv.get_global_transform_with_canvas()
    var inv := xf.affine_inverse()
    var ps := PostFx.pixel_size() if Settings.flag("post_fx") else 1.0
    var out := PackedVector2Array()
    out.resize(pts.size())
    for i in pts.size():
        out[i] = inv * (((xf * pts[i]) / ps).floor() * ps + (Vector2(ps, ps) * 0.5 if half else Vector2.ZERO))
    return out


## The phase (0..1) of the march, shared so every hostile edge moves together.
static func march() -> float:
    return fmod(float(Time.get_ticks_msec()) / 1000.0 * MARCH, 1.0)


## A black and red dashed ring at `at`, radius `r`, opacity `a`: a dark band under the
## whole circle and red dashes over half of it, marching round, in whole screen cells
## snapped to the pixel grid. `width` above 2 draws 2-cell dashes (an armed bomber).
static func dash_ring(cv: CanvasItem, at: Vector2, r: float, a: float, width: float = 2.0) -> void:
    if a <= 0.0 or r <= 0.0:
        return
    var n := clampi(int(r / 4.0), 12, 64)
    n += n % 2
    var step := TAU / float(n)
    var off := march() * step * 2.0
    var c := cell(cv)
    var ring := PackedVector2Array()
    for k in n * 2 + 1:
        ring.append(at + Vector2.from_angle(TAU * float(k) / float(n * 2)) * r)
    cv.draw_polyline(snap(cv, ring), Color(DARK, 0.85 * a), c * 2.0)
    var pts := PackedVector2Array()
    for k in n >> 1:
        var a0 := off + step * float(k * 2)
        var segs := 3
        for s in segs:
            pts.append(at + Vector2.from_angle(a0 + step * float(s) / float(segs)) * r)
            pts.append(at + Vector2.from_angle(a0 + step * float(s + 1) / float(segs)) * r)
    cv.draw_multiline(snap(cv, pts, true), Color(RED, a), c * (2.0 if width > 2.0 else 1.0))
