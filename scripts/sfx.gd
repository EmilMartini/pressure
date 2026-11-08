extends Node
## Autoload "Sfx": every sound in the game by name. A name maps to a few variants (BANK),
## each play picks one at random with a little pitch and volume wobble, and three guards
## keep a busy room from turning into mush: a per-name rate limit (MIN_INTERVAL), a voice
## cap per name (VOICES) and per family (GROUP_VOICES, the oldest voice is stolen), and a
## density dip (repeats of one name inside DENSITY_WINDOW come out a little quieter).
## A compressor and limiter on Master catch whatever still stacks up.
##
## World sounds (shots, hits, deaths, reactions, props, steps) play on AudioStreamPlayer2D
## voices on the "World" bus (a light per-theme reverb, sending into "Sfx") when a
## position is given: they pan with the camera and fade out over about a screen
## (MAX_DISTANCE). Everything else plays flat on "Sfx".
##
## Also here: the per-theme ambient bed (set by Ambience, crossfaded, ducked while enemies
## are up), footsteps polled from the players' movement, the low-health heartbeat, and
## short music/ambience dips on big moments (DUCK). Sources and licences:
## assets/audio/CREDITS.txt (CC0 throughout).

const DIR := "res://assets/audio/%s.ogg"
const POOL_2D := 28
const POOL_FLAT := 14
const MIN_INTERVAL := 0.05
const DEFAULT_VOICES := 3
const MAX_DISTANCE := 1400.0
const ATTENUATION := 1.0
const PANNING := 0.55
const DENSITY_WINDOW := 0.3
const NO_POS := Vector2(INF, INF)

## name -> stream files (without .ogg). Several entries = random variant.
const BANK := {
    # Shots, one voice per element
    "shoot_fire": ["shot_fire_1", "shot_fire_2", "shot_fire_3", "shot_fire_4"],
    "shoot_wet": ["shot_wet_1", "shot_wet_2", "shot_wet_3", "shot_wet_4"],
    "shoot_shock": ["shot_shock_1", "shot_shock_2", "shot_shock_3", "shot_shock_4"],
    "shoot_ice": ["shot_ice_1", "shot_ice_2", "shot_ice_3", "shot_ice_4"],
    "shoot_oil": ["shot_oil_1", "shot_oil_2", "shot_oil_3", "shot_oil_4"],
    "shoot_poison": ["shot_poison_1", "shot_poison_2", "shot_poison_3", "shot_poison_4"],
    "shoot_acid": ["shot_acid_1", "shot_acid_2", "shot_acid_3", "shot_acid_4"],
    "shoot_blood": ["shot_blood_1", "shot_blood_2", "shot_blood_3", "shot_blood_4"],
    "shoot_void": ["shot_void_1", "shot_void_2", "shot_void_3"],
    "shoot_holy": ["shot_holy_1", "shot_holy_2", "shot_holy_3", "shot_holy_4"],
    "shoot_gale": ["shot_gale_1", "shot_gale_2", "shot_gale_3", "shot_gale_4"],
    "shoot_stone": ["shot_stone_1", "shot_stone_2", "shot_stone_3", "shot_stone_4"],
    # Reaction layers: one per element, and a weight by size
    "rx_fire": ["rx_fire_1", "rx_fire_2"], "rx_wet": ["rx_wet_1", "rx_wet_2"],
    "rx_shock": ["rx_shock_1", "rx_shock_2"], "rx_ice": ["rx_ice_1", "rx_ice_2"],
    "rx_oil": ["rx_oil_1", "rx_oil_2"], "rx_poison": ["rx_poison_1", "rx_poison_2"],
    "rx_acid": ["rx_acid_1", "rx_acid_2"], "rx_blood": ["rx_blood_1", "rx_blood_2"],
    "rx_void": ["rx_void_1", "rx_void_2"], "rx_holy": ["rx_holy_1", "rx_holy_2"],
    "rx_gale": ["rx_gale_1", "rx_gale_2"], "rx_stone": ["rx_stone_1", "rx_stone_2"],
    "burst_small": ["burst_small_1", "burst_small_2"],
    "burst_med": ["burst_med_1", "burst_med_2"],
    "burst_large": ["burst_large_1", "burst_large_2"],
    # Signature reactions and events (names kept from the first sound pass)
    "react_chain": ["sig_chain"],
    "react_steam": ["sig_steam"],
    "react_freeze": ["sig_freeze"],
    "react_inferno": ["sig_inferno"],
    "react_ignition": ["sig_ignition"],
    "nova_fire": ["sig_explode"],
    "nova_frost": ["nova_frost_b"],
    "vent_hot": ["vent_hot"],
    "vent_cold": ["vent_cold"],
    "shield_break": ["shield_shatter"],
    "shield_crack": ["shield_crack"],
    "shield_restore": ["shield_up"],
    "path_open": ["path_stone"],
    "elite": ["elite_sting"],
    # Impacts
    "hit": ["hit_wall_1", "hit_wall_2", "hit_wall_3"],
    "hit_flesh": ["hit_flesh_1", "hit_flesh_2", "hit_flesh_3", "hit_flesh_4"],
    "hit_armour": ["hit_armour_1", "hit_armour_2", "hit_armour_3"],
    "hit_shield": ["hit_shield_1", "hit_shield_2", "hit_shield_3"],
    "hit_wall": ["hit_wall_1", "hit_wall_2", "hit_wall_3"],
    "hit_wood": ["hit_wood_1", "hit_wood_2", "hit_wood_3"],
    "hit_barrel": ["hit_barrel_1", "hit_barrel_2", "hit_barrel_3"],
    "hit_stone": ["hit_stone_1", "hit_stone_2", "hit_stone_3"],
    "hit_crystal": ["hit_crystal_1", "hit_crystal_2", "hit_crystal_3"],
    "hit_metal": ["hit_metal_1", "hit_metal_2", "hit_metal_3"],
    "hit_water": ["hit_water_1", "hit_water_2", "hit_water_3"],
    # Breaking things ("die" / "die_elite" are the crate and masonry calls in props and
    # secrets; enemies use die_enemy)
    "die": ["break_wood_1", "break_wood_2", "break_wood_3"],
    "die_elite": ["break_stone_1", "break_stone_2"],
    # Enemy deaths by size, bosses
    "death_small": ["death_small_1", "death_small_2", "death_small_3", "death_small_4"],
    "death_med": ["death_med_1", "death_med_2", "death_med_3"],
    "death_large": ["death_large_1", "death_large_2", "death_large_3"],
    "death_elite": ["death_elite_1", "death_elite_2"],
    "die_boss": ["death_boss"],
    "boss": ["boss_roar"],
    "boss_phase": ["boss_phase"],
    # Player
    "hurt": ["hurt_1", "hurt_2", "hurt_3"],
    # "You were hit": the hurt punch an octave and a bit down under the normal one, a
    # heavier thud than any enemy hit (hit_flesh is high and short). Floor hazards hiss
    # (sizzle_*) instead.
    "hurt_low": ["hurt_1", "hurt_2", "hurt_3"],
    "sizzle_fire": ["vent_hot"],
    "sizzle_shock": ["shot_shock_1", "shot_shock_3"],
    "down": ["player_down"],
    "revive": ["revive"],
    "level_up": ["level_up"],
    "pickup_gun": ["pickup_gun"],
    "item_0": ["item_0"], "item_1": ["item_1"], "item_2": ["item_2"], "item_3": ["item_3"], "item_4": ["item_4"],
    "active_use": ["active_use"],
    "overheat": ["overheat"],
    "frozen": ["frozen"],
    "scrap": ["scrap"],
    # World and UI
    "drip": ["drip_1", "drip_2", "drip_3"],
    "door_lock": ["door_slam"],
    "door_open": ["door_heavy"],
    "cleared": ["gong"],
    "stairs": ["stairs"],
    "wave_start": ["wave_start"],
    "tick": ["tick"],
    "buy": ["coins_1", "coins_2", "coins_3"],
    "confirm": ["confirm"],
    "error": ["error"],
    "deny": ["deny"],
    "unlock": ["fanfare"],
    "secret_found": ["secret_chime"],
    "wall_reveal": ["wall_rumble"],
    "ui_move": ["ui_move"],
    "ui_confirm": ["ui_confirm"],
    "ui_back": ["ui_back"],
    "ui_open": ["ui_open"],
    # Footsteps per floor surface
    "step_stone": ["step_stone_1", "step_stone_2", "step_stone_3", "step_stone_4"],
    "step_moss": ["step_moss_1", "step_moss_2", "step_moss_3", "step_moss_4"],
    "step_snow": ["step_snow_1", "step_snow_2", "step_snow_3", "step_snow_4"],
    "step_ash": ["step_ash_1", "step_ash_2", "step_ash_3", "step_ash_4"],
    "step_glass": ["step_glass_1", "step_glass_2", "step_glass_3", "step_glass_4"],
}

## Per-name volume trim in dB (new files are levelled to about -16 dB RMS).
const TRIM := {
    "shoot_fire": -17.0, "shoot_wet": -13.0, "shoot_shock": -16.0, "shoot_ice": -16.0, "shoot_oil": -17.0,
    "shoot_poison": -16.0, "shoot_acid": -15.0, "shoot_blood": -15.0, "shoot_void": -18.0, "shoot_holy": -16.0,
    "shoot_gale": -16.0, "shoot_stone": -17.0,
    "rx_fire": -9.0, "rx_wet": -9.0, "rx_shock": -9.0, "rx_ice": -6.0, "rx_oil": -10.0, "rx_poison": -10.0,
    "rx_acid": -7.0, "rx_blood": -9.0, "rx_void": -10.0, "rx_holy": -10.0, "rx_gale": -9.0, "rx_stone": -6.0,
    "burst_small": -13.0, "burst_med": -10.0, "burst_large": -7.0,
    "react_chain": -6.0, "react_steam": -6.0, "react_freeze": -5.0, "react_inferno": -4.0, "react_ignition": -6.0,
    "nova_fire": -3.0, "nova_frost": 0.0, "vent_hot": -4.0, "vent_cold": -2.0,
    "shield_break": -3.0, "shield_crack": -6.0, "shield_restore": -6.0, "path_open": -4.0, "elite": -4.0,
    "hit": -12.0, "hit_flesh": -17.0, "hit_armour": -14.0, "hit_shield": -13.0, "hit_wall": -18.0,
    "hit_wood": -13.0, "hit_barrel": -13.0, "hit_stone": -14.0, "hit_crystal": -11.0, "hit_metal": -12.0, "hit_water": -12.0,
    "die": -8.0, "die_elite": -6.0,
    "death_small": -10.0, "death_med": -9.0, "death_large": -7.0, "death_elite": -5.0, "die_boss": -1.0,
    "boss": -2.0, "boss_phase": -3.0,
    "hurt": -3.0, "hurt_low": -4.0, "sizzle_fire": -10.0, "sizzle_shock": -9.0, "down": -3.0, "revive": -4.0, "level_up": -5.0, "pickup_gun": -4.0,
    "item_0": -7.0, "item_1": -6.0, "item_2": -5.0, "item_3": -3.0, "item_4": -4.0, "active_use": -6.0,
    "scrap": -10.0, "tick": -6.0, "drip": -16.0, "door_lock": -6.0, "door_open": -6.0, "cleared": -6.0,
    "buy": -6.0, "deny": -8.0, "unlock": -4.0, "secret_found": -2.0, "wall_reveal": -4.0,
    "step_stone": -15.0, "step_moss": -13.0, "step_snow": -15.0, "step_ash": -15.0, "step_glass": -14.0,
}

## Base pitch per name; shots and hits get a wider wobble so repeats do not phase.
const PITCH := { "shoot_oil": 0.95, "shoot_void": 1.0, "hurt_low": 0.58, "sizzle_fire": 1.5, "sizzle_shock": 1.3 }
const WOBBLE := {
    "shoot_fire": 0.14, "shoot_wet": 0.14, "shoot_shock": 0.1, "shoot_ice": 0.12, "shoot_oil": 0.12,
    "shoot_poison": 0.14, "shoot_acid": 0.12, "shoot_blood": 0.12, "shoot_void": 0.1, "shoot_holy": 0.06,
    "shoot_gale": 0.14, "shoot_stone": 0.12, "hit_flesh": 0.15, "hit_armour": 0.1, "hit_wall": 0.15,
    "hit": 0.15, "death_small": 0.1, "death_med": 0.08, "step_stone": 0.1, "step_moss": 0.1,
    "step_snow": 0.1, "step_ash": 0.1, "step_glass": 0.08, "drip": 0.2,
    "die_boss": 0.0, "boss": 0.0, "unlock": 0.0, "secret_found": 0.0, "level_up": 0.0, "heartbeat": 0.0,
}

## Max simultaneous voices per name; the oldest is stolen past this.
const VOICES := {
    "shoot_fire": 2, "shoot_wet": 2, "shoot_shock": 2, "shoot_ice": 2, "shoot_oil": 2, "shoot_poison": 2,
    "shoot_acid": 2, "shoot_blood": 2, "shoot_void": 2, "shoot_holy": 2, "shoot_gale": 2, "shoot_stone": 2,
    "hit_flesh": 3, "hit_armour": 2, "hit_shield": 2, "hit_wall": 2, "hit": 2, "die": 3, "scrap": 2,
    "react_chain": 2, "death_small": 3, "death_med": 3, "death_large": 2, "step_stone": 2, "step_moss": 2,
    "step_snow": 2, "step_ash": 2, "step_glass": 2, "drip": 2, "burst_small": 2, "burst_med": 2, "burst_large": 2,
}
## Shared caps per family (name prefix), so twelve shot voices never pile up at once.
const GROUP_VOICES := { "shoot_": 6, "hit_": 5, "rx_": 6, "burst_": 3, "death_": 5, "step_": 4 }
## Per-name rate limits longer than MIN_INTERVAL.
const INTERVAL := { "hit_flesh": 0.035, "hit_wall": 0.08, "hit": 0.06, "drip": 0.15, "tick": 0.0, "hurt": 0.12, "hurt_low": 0.12, "sizzle_fire": 0.2, "sizzle_shock": 0.2 }

## Event reactions and the signature ones: dedicated, layered sounds instead of the
## composed element layers.
const SIGNATURE := {
    "Chain Lightning": ["react_chain", "burst_small"],
    "Steam": ["react_steam"],
    "Deep Freeze": ["react_freeze"],
    "Inferno": ["react_inferno", "burst_med"],
    "Ignition": ["react_ignition"],
    "Fire Nova": ["vent_hot"],
    "Frost Nova": ["vent_cold"],
    "Shield broken!": ["shield_break"],
    "Shield cracked": ["shield_crack"],
    "Shield restored!": ["shield_restore"],
    "Path opened!": ["path_open"],
    "ELITE": ["elite"],
}

## Short music and ambience dips: name -> [dB, seconds held].
const DUCK := {
    "die_boss": [-10.0, 1.6], "boss": [-6.0, 1.2], "boss_phase": [-6.0, 1.0], "elite": [-4.0, 0.8],
    "unlock": [-6.0, 1.2], "secret_found": [-7.0, 1.6], "level_up": [-4.0, 0.8], "react_inferno": [-3.0, 0.4],
    "burst_large": [-3.0, 0.35], "nova_fire": [-3.0, 0.4], "down": [-6.0, 1.0], "revive": [-5.0, 1.0],
    "wall_reveal": [-5.0, 1.4], "shield_break": [-3.0, 0.5],
}

## Footstep surface and reverb per floor theme (Themes ids).
const STEP := { "crypt": "step_stone", "ruins": "step_moss", "frozen": "step_snow", "forge": "step_ash", "void": "step_glass", "sanctum": "step_stone", "garden": "step_moss", "cistern": "step_stone" }
const REVERB := {
    "crypt": [0.62, 0.14], "ruins": [0.45, 0.1], "frozen": [0.55, 0.12], "forge": [0.4, 0.08],
    "void": [0.85, 0.2], "sanctum": [0.6, 0.12], "garden": [0.45, 0.1], "cistern": [0.8, 0.18],
}
const STRIDE := 46.0
const AMB_DB := -9.0
const AMB_FIGHT_DB := -15.0
const AMB_FADE := 1.6
const HEART_DB := -3.0
## Low health: the heartbeat starts under HEART_LOW of max HP and is at full rate and
## volume by HEART_CRIT (DangerFx pulses the screen edge and the pad on its beats).
const HEART_LOW := 0.35
const HEART_CRIT := 0.15

var enabled := true
var theme := ""                         # floor theme of the ambience playing ("" = none)
var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer2D] = []
var _players_flat: Array[AudioStreamPlayer] = []
var _voice_name: Dictionary = {}        # player -> name it is playing
var _next_2d := 0
var _next_flat := 0
var _last_played: Dictionary = {}
var _recent: Dictionary = {}            # name -> [count, window start]
var _weights: Dictionary = {}           # reaction name -> 0 small, 1 medium, 2 large
var _defs: Dictionary = {}              # reaction name -> its Element.DEFS entry
var _amb: Array[AudioStreamPlayer] = []
var _amb_active := 0
var _amb_owner: Node = null
var _amb_release := -1.0
var _amb_tweens: Array = [null, null]
var _amb_level := AMB_DB
var _dip_db := 0.0
var _dip_hold := 0.0
var _heart: AudioStreamPlayer
var _heart_on := false
var _steps: Dictionary = {}             # player id -> distance walked since the last step
var _seen: Dictionary = {}              # player id -> time first seen (no pickup sounds at spawn)
var _reverb: AudioEffectReverb


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _setup_buses()
    for i in POOL_2D:
        var p2d := AudioStreamPlayer2D.new()
        p2d.bus = "World"
        p2d.max_distance = MAX_DISTANCE
        p2d.attenuation = ATTENUATION
        p2d.panning_strength = PANNING
        add_child(p2d)
        _players_2d.append(p2d)
    for i in POOL_FLAT:
        var pf := AudioStreamPlayer.new()
        pf.bus = "Sfx"
        add_child(pf)
        _players_flat.append(pf)
    for snd in BANK.keys():
        var list: Array = []
        for file in BANK[snd]:
            var path := DIR % file
            if ResourceLoader.exists(path):
                var s := load(path) as AudioStream
                if s != null:
                    list.append(s)
        _streams[snd] = list
    for i in 2:
        var a := AudioStreamPlayer.new()
        a.bus = "Ambience"
        a.volume_db = -60.0
        add_child(a)
        _amb.append(a)
    _heart = AudioStreamPlayer.new()
    _heart.bus = "Sfx"
    _heart.volume_db = -60.0
    var hs := _loop_stream("heartbeat")
    if hs != null:
        _heart.stream = hs
    add_child(_heart)
    for d in Element.DEFS:
        _weights[String(d["name"])] = _weight_of(d)
        _defs[String(d["name"])] = d


# --- Public API ----------------------------------------------------------------


## Play a sound by name. With `at` set it plays in the world (panned, fades with
## distance); without, it plays flat. Unknown names are ignored.
func play(name: String, volume_db: float = 0.0, pitch_wobble: float = -1.0, at: Vector2 = NO_POS) -> void:
    if not enabled or not _streams.has(name) or _streams[name].is_empty():
        return
    var now := Time.get_ticks_msec() / 1000.0
    var gap := float(INTERVAL.get(name, MIN_INTERVAL))
    if now - float(_last_played.get(name, -1.0)) < gap:
        return
    _last_played[name] = now
    # Density: each repeat inside the window comes out a little quieter.
    var rec: Array = _recent.get(name, [0, now])
    if now - float(rec[1]) > DENSITY_WINDOW:
        rec = [0, now]
    rec[0] = int(rec[0]) + 1
    _recent[name] = rec
    var density := -minf(6.0, 1.5 * float(int(rec[0]) - 1))
    var wobble: float = pitch_wobble if pitch_wobble >= 0.0 else float(WOBBLE.get(name, 0.05))
    var vol := volume_db + float(TRIM.get(name, 0.0)) + density - randf() * 1.2
    var pitch := float(PITCH.get(name, 1.0)) * (1.0 + randf_range(-wobble, wobble))
    var stream: AudioStream = _streams[name].pick_random()
    if is_finite(at.x) and _world_ok():
        var p2 := _voice_2d(name)
        p2.stream = stream
        p2.global_position = at
        p2.volume_db = vol
        p2.pitch_scale = pitch
        p2.play()
        _voice_name[p2] = name
    else:
        var pf := _voice_flat(name)
        pf.stream = stream
        pf.volume_db = vol
        pf.pitch_scale = pitch
        pf.play()
        _voice_name[pf] = name
    if DUCK.has(name):
        var dk: Array = DUCK[name]
        dip(float(dk[0]), float(dk[1]))


func play_at(name: String, pos: Vector2, volume_db: float = 0.0, pitch_wobble: float = -1.0) -> void:
    play(name, volume_db, pitch_wobble, pos)


## Cut every one-shot voice; used on room transitions so nothing carries over. The
## ambient bed and the heartbeat keep going.
func stop_all() -> void:
    for p in _players_2d:
        p.stop()
    for p in _players_flat:
        p.stop()
    _voice_name.clear()


## A reaction fired. Signature reactions and events have their own layered sound; the
## rest are composed from the two elements' layers plus a weight by size.
func reaction(reaction_name: String, at: Vector2 = NO_POS) -> void:
    if SIGNATURE.has(reaction_name):
        var list: Array = SIGNATURE[reaction_name]
        for i in list.size():
            play(String(list[i]), 0.0 if i == 0 else -3.0, -1.0, at)
        return
    var d: Dictionary = _defs.get(reaction_name, {})
    if d.is_empty():
        return
    var now := Time.get_ticks_msec() / 1000.0
    var key := "rx:" + reaction_name
    if now - float(_last_played.get(key, -1.0)) < 0.09:
        return
    _last_played[key] = now
    var a := _el_key(int(d["a"]))
    var b := _el_key(int(d["b"]))
    play("rx_" + a, 0.0, 0.06, at)
    play("rx_" + b, -2.0, 0.08, at)
    var w := int(_weights.get(reaction_name, 0))
    play(["burst_small", "burst_med", "burst_large"][w], -2.0 if w == 0 else 0.0, 0.05, at)


## A gun fired an element.
func shoot(element: int, at: Vector2 = NO_POS) -> void:
    var key := "shoot_" + _el_key(element)
    play(key if _streams.has(key) else "shoot_shock", 0.0, -1.0, at)


## An enemy took a direct hit: flesh, armour (wardens, elites) or its attuned shield.
func hit_enemy(e: Node2D) -> void:
    if e == null:
        return
    var snd := "hit_flesh"
    var vol := 0.0
    var shield: Variant = e.get("shield_hp")
    if shield != null and int(shield) > 0:
        snd = "hit_shield"
    elif e.has_method("is_armoured") and bool(e.call("is_armoured")):
        snd = "hit_armour"
    elif bool(e.get("is_elite")):
        snd = "hit_armour"
        vol = -4.0
        play("hit_flesh", -3.0, -1.0, e.global_position)
    play(snd, vol, -1.0, e.global_position)


## An enemy died: the size class picks the voice; bosses get the full roar.
func die_enemy(e: Node2D) -> void:
    if e == null:
        return
    var kind := String(e.get("kind_name")) if e.get("kind_name") != null else ""
    if kind == "boss":
        play("die_boss")
        return
    var pos := e.global_position
    if kind == "elite" or bool(e.get("is_elite")):
        play("death_elite", 0.0, -1.0, pos)
        return
    var r := float(e.get("radius")) if e.get("radius") != null else 12.0
    if r <= 10.0:
        play("death_small", 0.0, -1.0, pos)
    elif r <= 15.0:
        play("death_med", 0.0, -1.0, pos)
    else:
        play("death_large", 0.0, -1.0, pos)


## A shot hit a prop: the material picks the knock.
func hit_prop(kind: String, at: Vector2) -> void:
    var snd := "hit_wood"
    match kind:
        "barrel":
            snd = "hit_barrel"
        "stone_pillar", "statue", "rubble", "boulder":
            snd = "hit_stone"
        "ice_crystal", "crystal":
            snd = "hit_crystal"
        "lightning_rod", "brazier", "cage":
            snd = "hit_metal"
        "fountain":
            snd = "hit_water"
        _:
            if kind.contains("stone") or kind.contains("statue"):
                snd = "hit_stone"
            elif kind.contains("crystal") or kind.contains("ice"):
                snd = "hit_crystal"
    play(snd, 0.0, -1.0, at)


## A player picked something up; quiet while players are still spawning (loadouts).
func pickup(snd: String, who: Node2D) -> void:
    if who != null and _age(who) < 1.0:
        return
    play(snd, 0.0, 0.0, who.global_position if who != null else NO_POS)


## An item went on: richer the rarer it is (0 common .. 4 legendary).
func item_pickup(rarity: int, who: Node2D) -> void:
    pickup("item_%d" % clampi(rarity, 0, 4), who)


## Briefly pull the music and the ambient bed down (big moments).
func dip(db: float, seconds: float) -> void:
    _dip_db = minf(_dip_db, -absf(db))
    _dip_hold = maxf(_dip_hold, seconds)
    var music := get_node_or_null("/root/Music")
    if music != null and music.has_method("dip"):
        music.dip(db, seconds)


## The ambient bed for a floor theme. Ambience calls this from its _ready; the same
## theme keeps playing across rooms, a new one crossfades in.
func set_ambience(new_theme: String, owner_node: Node = null) -> void:
    _amb_owner = owner_node
    _amb_release = -1.0
    _set_reverb(new_theme)
    if new_theme == theme and _amb[_amb_active].playing:
        return
    theme = new_theme
    var s := _loop_stream("amb_" + new_theme)
    if s == null:
        return
    _amb_active = 1 - _amb_active
    var p := _amb[_amb_active]
    p.stream = s
    p.volume_db = -60.0
    p.play(randf() * maxf(0.0, s.get_length() - 1.0))
    _amb_fade(_amb_active, _amb_level, AMB_FADE)
    _amb_fade(1 - _amb_active, -60.0, AMB_FADE, true)


## Ambience node leaving: fade the bed unless another one takes over right away.
func release_ambience(owner_node: Node) -> void:
    if owner_node == _amb_owner:
        _amb_release = 0.3


# --- Polling: footsteps, heartbeat, ambience level ------------------------------


func _process(delta: float) -> void:
    var real := delta / maxf(Engine.time_scale, 0.001)
    if _amb_release >= 0.0:
        _amb_release -= real
        if _amb_release < 0.0:
            theme = ""
            for i in 2:
                _amb_fade(i, -60.0, 1.2, true)
    if _dip_hold > 0.0:
        _dip_hold -= real
    elif _dip_db < 0.0:
        _dip_db = minf(0.0, _dip_db + real * 10.0)
    var tree := get_tree()
    if tree.paused:
        _set_heart(false, 1.0)
        return
    var fight := tree.get_nodes_in_group("enemies").size() > 0
    var want := (AMB_FIGHT_DB if fight else AMB_DB)
    _amb_level = move_toward(_amb_level, want, real * 4.0)
    if theme != "":
        var a := _amb[_amb_active]
        if a.playing and (_amb_tweens[_amb_active] == null or not _amb_tweens[_amb_active].is_valid()):
            a.volume_db = _amb_level + _dip_db
    _poll_players(delta, tree)


func _poll_players(delta: float, tree: SceneTree) -> void:
    var low := 1.0
    var any := false
    var now := Time.get_ticks_msec() / 1000.0
    for n in tree.get_nodes_in_group("players"):
        var p := n as CharacterBody2D
        if p == null or not is_instance_valid(p):
            continue
        var id := p.get_instance_id()
        if not _seen.has(id):
            _seen[id] = now
        if p.get("alive") != null and not bool(p.get("alive")):
            continue
        any = true
        var mhp: Variant = p.get("max_hp")
        if mhp != null and float(mhp) > 0.0:
            low = minf(low, float(p.get("hp")) / float(mhp))
        # Footsteps: one per stride of real movement, on the theme's surface.
        var speed := p.velocity.length()
        if speed < 25.0 or theme == "":
            _steps[id] = minf(float(_steps.get(id, 0.0)), STRIDE * 0.6)
            continue
        var walked := float(_steps.get(id, 0.0)) + speed * delta
        if walked >= STRIDE:
            walked = 0.0
            play(String(STEP.get(theme, "step_stone")), lerpf(-3.0, 0.0, clampf(speed / 260.0, 0.0, 1.0)), -1.0, p.global_position)
        _steps[id] = walked
    _set_heart(any and low < HEART_LOW, low)


func _set_heart(on: bool, hp_frac: float) -> void:
    if _heart.stream == null:
        return
    if on:
        var k := clampf((HEART_LOW - hp_frac) / (HEART_LOW - HEART_CRIT), 0.0, 1.0)
        _heart.pitch_scale = lerpf(1.0, 1.45, k)
        var target := HEART_DB + lerpf(-6.0, 0.0, k)
        if not _heart.playing:
            _heart.volume_db = -30.0
            _heart.play()
        _heart.volume_db = move_toward(_heart.volume_db, target, 1.0)
    elif _heart.playing:
        _heart.volume_db -= 1.5
        if _heart.volume_db < -40.0:
            _heart.stop()
    _heart_on = on


## 0..1, the heartbeat's loudness envelope right now (1 on each lub and dub, decaying fast),
## or -1 when it is not beating. The loop (heartbeat.ogg, 1.8 s) holds two lub-dubs: beats
## at 0.0 and 0.3 s of every 0.9 s, the second (dub) the louder.
func heart_env() -> float:
    if not _heart_on or _heart.stream == null or not _heart.playing:
        return -1.0
    var t := fmod(_heart.get_playback_position(), 0.9)
    var lub := 0.75 * exp(-t * 9.0)
    var dub := exp(-(t - 0.3) * 9.0) if t >= 0.3 else 0.0
    return clampf(maxf(lub, dub), 0.0, 1.0)


# --- Internals ---------------------------------------------------------------------


## World voices need a 2D world (always true in game; menus without one play flat).
func _world_ok() -> bool:
    return get_viewport() != null and get_viewport().get_camera_2d() != null


func _el_key(kind: int) -> String:
    return String(Element.NAMES.get(kind, "Shock")).to_lower()


## 0 small, 1 medium, 2 large, from the reaction's actions.
func _weight_of(d: Dictionary) -> int:
    var score := 0.0
    for act in d.get("do", []):
        var a: Array = act
        match String(a[0]):
            "burst":
                score += float(a[2]) + float(a[1]) / 100.0
            "damage":
                score += float(a[1])
            "pull", "push", "chain", "chain_state":
                score += 1.5
            "decay":
                score += 2.0
            "cloud", "apply", "spread", "freeze", "stun":
                score += 0.5
    if score < 2.0:
        return 0
    return 1 if score < 4.0 else 2


func _age(who: Node) -> float:
    var now := Time.get_ticks_msec() / 1000.0
    return now - float(_seen.get(who.get_instance_id(), now))


func _loop_stream(file: String) -> AudioStream:
    var path := DIR % file
    if not ResourceLoader.exists(path):
        return null
    var s := (load(path) as AudioStream)
    if s == null:
        return null
    s = s.duplicate() as AudioStream
    if "loop" in s:
        s.set("loop", true)
    return s


func _family_of(snd: String) -> String:
    for g in GROUP_VOICES.keys():
        if snd.begins_with(String(g)):
            return String(g)
    return ""


## Voice to use for `name` from a pool: the oldest of the same name past its cap, the
## oldest of its family past the family cap, else a free one, else round robin.
func _pick_voice(pool: Array, snd: String, next: int) -> Array:
    var cap: int = VOICES.get(snd, DEFAULT_VOICES)
    var fam := _family_of(snd)
    var all: Array = []
    all.append_array(_players_2d)
    all.append_array(_players_flat)
    var same: Array = []
    var kin: Array = []
    for v in all:
        if not v.playing:
            continue
        var n := String(_voice_name.get(v, ""))
        if n == snd:
            same.append(v)
        if fam != "" and n.begins_with(fam):
            kin.append(v)
    var steal: Array = []
    if same.size() >= cap:
        steal = same
    elif fam != "" and kin.size() >= int(GROUP_VOICES[fam]):
        steal = kin
    if not steal.is_empty():
        var oldest: Variant = steal[0]
        for v in steal:
            if v.get_playback_position() > oldest.get_playback_position():
                oldest = v
        # Same pool when both are positional or both flat (pool.has() on a typed array of the
        # other kind logs an engine error).
        if pool.size() > 0 and (oldest is AudioStreamPlayer2D) == (pool[0] is AudioStreamPlayer2D):
            return [oldest, next]
        oldest.stop()
    var size := pool.size()
    for i in size:
        var cand: Variant = pool[(next + i) % size]
        if not cand.playing:
            return [cand, (next + i + 1) % size]
    return [pool[next], (next + 1) % size]


func _voice_2d(snd: String) -> AudioStreamPlayer2D:
    var r := _pick_voice(_players_2d, snd, _next_2d)
    _next_2d = int(r[1])
    return r[0] as AudioStreamPlayer2D


func _voice_flat(snd: String) -> AudioStreamPlayer:
    var r := _pick_voice(_players_flat, snd, _next_flat)
    _next_flat = int(r[1])
    return r[0] as AudioStreamPlayer


func _amb_fade(i: int, to_db: float, seconds: float, stop_after: bool = false) -> void:
    if _amb_tweens[i] != null and _amb_tweens[i].is_valid():
        _amb_tweens[i].kill()
    var p := _amb[i]
    var tw := create_tween()
    tw.set_ignore_time_scale(true)
    tw.tween_property(p, "volume_db", to_db, maxf(seconds, 0.01))
    if stop_after:
        tw.tween_callback(p.stop)
    _amb_tweens[i] = tw


func _set_reverb(t: String) -> void:
    if _reverb == null or not REVERB.has(t):
        return
    var r: Array = REVERB[t]
    _reverb.room_size = float(r[0])
    _reverb.wet = float(r[1])


## Master keeps its compressor and limiter; World (reverb) and Ambience send into Sfx so
## the Sfx volume setting covers them. default_bus_layout.tres declares the same buses;
## this only fills in what is missing.
func _setup_buses() -> void:
    var master := AudioServer.get_bus_index("Master")
    var has_comp := false
    var has_lim := false
    for e in AudioServer.get_bus_effect_count(master):
        var fx := AudioServer.get_bus_effect(master, e)
        has_comp = has_comp or fx is AudioEffectCompressor
        has_lim = has_lim or fx is AudioEffectLimiter or fx is AudioEffectHardLimiter
    if not has_comp:
        var comp := AudioEffectCompressor.new()
        comp.threshold = -14.0
        comp.ratio = 4.0
        comp.attack_us = 15.0
        comp.release_ms = 120.0
        AudioServer.add_bus_effect(master, comp)
    if not has_lim:
        var lim := AudioEffectLimiter.new()
        lim.ceiling_db = -1.5
        AudioServer.add_bus_effect(master, lim)
    if AudioServer.get_bus_index("Sfx") < 0:
        AudioServer.add_bus()
        AudioServer.set_bus_name(AudioServer.bus_count - 1, "Sfx")
        AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
    for bus_name in ["World", "Ambience"]:
        if AudioServer.get_bus_index(bus_name) < 0:
            AudioServer.add_bus()
            AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
            AudioServer.set_bus_send(AudioServer.bus_count - 1, "Sfx")
    var world := AudioServer.get_bus_index("World")
    for e in AudioServer.get_bus_effect_count(world):
        var wfx := AudioServer.get_bus_effect(world, e)
        if wfx is AudioEffectReverb:
            _reverb = wfx
    if _reverb == null:
        _reverb = AudioEffectReverb.new()
        _reverb.room_size = 0.55
        _reverb.damping = 0.6
        _reverb.spread = 0.8
        _reverb.hipass = 0.15
        _reverb.dry = 1.0
        _reverb.wet = 0.12
        AudioServer.add_bus_effect(world, _reverb)
