extends Node
## Autoload "Sfx": one-shot sounds by name, with variants, pitch wobble and a per-name
## rate limit so fourteen blowtorch shots a second do not stack into noise.
## Sounds are CC0 by Kenney (Sci-fi Sounds, Impact Sounds, Interface Sounds, RPG Audio).

const POOL_SIZE := 20
const MIN_INTERVAL := 0.045

## name -> list of stream paths. Several entries = random variant.
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

## Per-name volume trim in dB and pitch wobble.
const TRIM := {
    "shoot_wet": -14.0, "shoot_oil": -12.0, "shoot_shock": -10.0, "shoot_fire": -16.0, "shoot_ice": -10.0,
    "hit": -12.0, "die": -6.0, "scrap": -8.0, "tick": -6.0, "react_chain": -4.0, "react_steam": -6.0,
}

const REACTION_SOUNDS := {
    "Chain Lightning": "react_chain",
    "Steam": "react_steam",
    "Deep Freeze": "react_freeze",
    "Inferno": "react_inferno",
    "Ignition": "react_ignition",
    "Fire Nova": "nova_fire",
    "Frost Nova": "nova_frost",
    "Shield broken!": "shield_break",
    "Shield restored!": "shield_restore",
    "Path opened!": "path_open",
    "ELITE": "elite",
}

var enabled := true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
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


func play(name: String, volume_db: float = 0.0, pitch_wobble: float = 0.08) -> void:
    if not enabled or not _streams.has(name) or _streams[name].is_empty():
        return
    var now := Time.get_ticks_msec() / 1000.0
    if now - float(_last_played.get(name, -1.0)) < MIN_INTERVAL:
        return
    _last_played[name] = now
    var p := _players[_next]
    _next = (_next + 1) % POOL_SIZE
    p.stream = _streams[name].pick_random()
    p.volume_db = volume_db + float(TRIM.get(name, 0.0))
    p.pitch_scale = 1.0 + randf_range(-pitch_wobble, pitch_wobble)
    p.play()


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
