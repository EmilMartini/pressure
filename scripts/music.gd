extends Node
## Autoload "Music": looping tracks with crossfades and a duck while paused.
## Tracks by Kevin MacLeod (incompetech.com), CC BY 4.0; see assets/music/CREDITS.txt.

const TRACKS := {
    "menu": "res://assets/music/menu.mp3",
    "run": "res://assets/music/run.mp3",
    "boss": "res://assets/music/boss.mp3",
    "ambient": "res://assets/music/ambient.mp3",
}
const VOLUME_DB := -10.0
const DUCK_DB := -22.0
const SILENT_DB := -50.0

var enabled := true
var current := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _ducked := false
var _tweens: Array = [null, null]


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    for i in 2:
        var p := AudioStreamPlayer.new()
        p.bus = "Master"
        p.volume_db = SILENT_DB
        add_child(p)
        _players.append(p)


func play(track: String, fade: float = 1.6) -> void:
    if not enabled or track == current or not TRACKS.has(track):
        return
    var stream = load(TRACKS[track])
    if stream == null:
        return
    if stream is AudioStreamMP3:
        stream.loop = true
    current = track
    var old := _players[_active]
    _active = 1 - _active
    var new := _players[_active]
    new.stream = stream
    new.volume_db = SILENT_DB
    new.play()
    _fade(_active, _target_db(), fade)
    _fade(1 - _active, SILENT_DB, fade, true)


func stop(fade: float = 1.2) -> void:
    current = ""
    for i in 2:
        _fade(i, SILENT_DB, fade, true)


func duck(on: bool) -> void:
    _ducked = on
    if current != "":
        _fade(_active, _target_db(), 0.4)


func _target_db() -> float:
    return DUCK_DB if _ducked else VOLUME_DB


func _fade(i: int, to_db: float, seconds: float, stop_after: bool = false) -> void:
    if _tweens[i] != null and _tweens[i].is_valid():
        _tweens[i].kill()
    var p := _players[i]
    var tw := create_tween()
    tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
    tw.tween_property(p, "volume_db", to_db, seconds)
    if stop_after:
        tw.tween_callback(p.stop)
    _tweens[i] = tw
