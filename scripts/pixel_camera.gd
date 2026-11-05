class_name PixelCamera
extends Camera2D
## A follow camera whose rendered position lands on the post-process pixel grid (see
## PostFx): the world moves in whole cells, so tiles and sprites never shimmer against
## the fixed screen grid. The follow itself stays smooth: `target` is chased by an
## unsnapped position every frame, and only what is rendered (position and the shake
## offset) is snapped. Physics never reads the camera.
##
## Callers set `target` (where to look) and `shake` (a world offset) instead of position
## and offset, and call `snap_now()` where they used reset_smoothing().

var target := Vector2.ZERO
var shake := Vector2.ZERO
var follow := true            # false: jump straight to the target every frame
var follow_speed := 7.0

var _pos := Vector2.ZERO      # smoothed, unsnapped


func _init() -> void:
    # After Main / Tutorial have set the target this frame.
    process_priority = 100
    position_smoothing_enabled = false


func _ready() -> void:
    _pos = target
    _apply()


## Jump to the target now (room entry, captures).
func snap_now() -> void:
    _pos = target
    _apply()
    reset_smoothing()


func _process(delta: float) -> void:
    if follow:
        _pos = _pos.lerp(target, 1.0 - exp(-follow_speed * delta))
    else:
        _pos = target
    _apply()


func _apply() -> void:
    var c := PostFx.cell_world(zoom.x)
    position = (_pos / c).round() * c
    offset = (shake / c).round() * c
