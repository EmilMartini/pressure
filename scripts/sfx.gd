extends Node
## Autoload "Sfx": one-shot sounds by name, with variants, pitch wobble, a per-name
## rate limit and a per-name voice cap, behind a compressor and limiter on Master so
## stacked shots never clip. Sounds are CC0 by Kenney.

const POOL_SIZE := 24
const MIN_INTERVAL := 0.05
const DEFAULT_VOICES := 3

## name -> list of stream files. Several entries = random variant.
const BANK := {
    "shoot_wet": ["shoot_wet"],
    "shoot_oil": ["shoot_oil"],
    "shoot_shock": ["shoot_shock_a", "shoot_shock_b"],
    "shoot_fire": ["shoot_fire"],
    "shoot_ice": ["shoot_ice"],
    "hit": ["hit_a", "hit_b", "hit_c"],
    "die": ["die_a", "die_b", "die_c"],
    "die_elite": ["die_elite"],
    "die_boss": ["die_boss"],
    "react_chain": ["react_chain"],
    "react_steam": ["react_steam"],
    "react_freeze": ["react_freeze"],
    "react_inferno": ["react_inferno"],
    "react_ignition": ["react_ignition"],
    "nova_fire": ["nova_fire"],
    "nova_frost": ["nova_frost"],
    "shield_break": ["shield_break"],
    "shield_restore": ["shield_restore"],
    "path_open": ["path_open"],
    "hurt": ["hurt"],
    "down": ["down"],
    "scrap": ["scrap"],
    "buy": ["buy"],
    "error": ["error"],
    "confirm": ["confirm"],
    "door_lock": ["door_lock"],
    "door_open": ["door_open"],
    "cleared": ["cleared"],
    "stairs": ["stairs"],
    "elite": ["elite"],
    "boss": ["boss"],
    "unlock": ["unlock"],
    "overheat": ["overheat"],
    "frozen": ["frozen"],
    "ui_move": ["ui_move"],
    "ui_confirm": ["ui_confirm"],
    "ui_back": ["ui_back"],
    "ui_open": ["ui_open"],
    "wave_start": ["wave_start"],
    "tick": ["tick"],
}

## Per-name volume trim in dB.
const TRIM := {
    "shoot_wet": -14.0, "shoot_oil": -14.0, "shoot_shock": -13.0, "shoot_fire": -18.0, "shoot_ice": -13.0,
    "hit": -14.0, "die": -8.0, "scrap": -10.0, "tick": -6.0, "react_chain": -6.0, "react_steam": -8.0,
    "react_inferno": -4.0, "react_ignition": -6.0, "nova_fire": -3.0, "nova_frost": -4.0, "hurt": -4.0,
}

## Base pitch per name; shots get a wider wobble so repeats do not phase.
const PITCH := { "shoot_oil": 0.6, "shoot_wet": 1.15, "shoot_fire": 1.4 }
const WOBBLE := { "shoot_wet": 0.18, "shoot_oil": 0.18, "shoot_shock": 0.12, "shoot_fire": 0.2, "shoot_ice": 0.15, "hit": 0.2 }

## Max simultaneous voices per name; the oldest is stolen past this.
const VOICES := { "shoot_wet": 2, "shoot_oil": 2, "shoot_shock": 2, "shoot_fire": 1, "shoot_ice": 2, "hit": 3, "die": 3, "scrap": 2, "react_chain": 2 }

const REACTION_SOUNDS := {
    "Chain Lightning": "react_chain",
    "Steam": "react_steam",
    "Deep Freeze": "react_freeze",
    "Inferno": "react_inferno",
    "Ignition": "react_ignition",
    "Fire Nova": "nova_fire",
    "Frost Nova": "nova_frost",
    "Shield broken!": "shield_break",
    "Shield cracked": "hit",
    "Shield restored!": "shield_restore",
    "Path opened!": "path_open",
    "ELITE": "elite",
}

var enabled := true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _player_name: Dictionary = {}   # player -> name it is playing
var _next := 0
var _last_played: Dictionary = {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var master := AudioServer.get_bus_index("Master")
    var comp := AudioEffectCompressor.new()
    comp.threshold = -14.0
    comp.ratio = 4.0
    comp.attack_us = 15.0
    comp.release_ms = 120.0
    AudioServer.add_bus_effect(master, comp)
    var lim := AudioEffectLimiter.new()
    lim.ceiling_db = -1.5
    AudioServer.add_bus_effect(master, lim)
    for i in POOL_SIZE:
        var p := AudioStreamPlayer.new()
        p.bus = "Master"
        add_child(p)
        _players.append(p)
    for name in BANK.keys():
        var list: Array = []
        for file in BANK[name]:
            var s := load("res://assets/audio/%s.ogg" % file)
            if s != null:
                list.append(s)
        _streams[name] = list


func play(name: String, volume_db: float = 0.0, pitch_wobble: float = -1.0) -> void:
    if not enabled or not _streams.has(name) or _streams[name].is_empty():
        return
    var now := Time.get_ticks_msec() / 1000.0
    if now - float(_last_played.get(name, -1.0)) < MIN_INTERVAL:
        return
    _last_played[name] = now
    var p := _voice_for(name)
    p.stream = _streams[name].pick_random()
    p.volume_db = volume_db + float(TRIM.get(name, 0.0))
    var wobble: float = pitch_wobble if pitch_wobble >= 0.0 else float(WOBBLE.get(name, 0.08))
    p.pitch_scale = float(PITCH.get(name, 1.0)) * (1.0 + randf_range(-wobble, wobble))
    p.play()
    _player_name[p] = name


## A free pool player, or the oldest voice of the same name past its cap.
func _voice_for(name: String) -> AudioStreamPlayer:
    var cap: int = VOICES.get(name, DEFAULT_VOICES)
    var same: Array = []
    for p in _players:
        if p.playing and _player_name.get(p, "") == name:
            same.append(p)
    if same.size() >= cap:
        var oldest: AudioStreamPlayer = same[0]
        for p in same:
            if p.get_playback_position() > oldest.get_playback_position():
                oldest = p
        return oldest
    for i in POOL_SIZE:
        var p := _players[(_next + i) % POOL_SIZE]
        if not p.playing:
            _next = (_next + i + 1) % POOL_SIZE
            return p
    var p := _players[_next]
    _next = (_next + 1) % POOL_SIZE
    return p


## Cut every voice; used on room transitions so nothing carries over.
func stop_all() -> void:
    for p in _players:
        p.stop()
    _player_name.clear()


func reaction(reaction_name: String) -> void:
    if REACTION_SOUNDS.has(reaction_name):
        play(REACTION_SOUNDS[reaction_name])


func shoot(element: int) -> void:
    match element:
        Element.Kind.WET:
            play("shoot_wet")
        Element.Kind.SHOCK:
            play("shoot_shock")
        Element.Kind.FIRE:
            play("shoot_fire")
        Element.Kind.ICE:
            play("shoot_ice")
        Element.Kind.OIL:
            play("shoot_oil")
