class_name Enemy
extends CharacterBody2D
## An enemy: chases the nearest player, carries element states, reacts, can be
## immune to one element's raw damage, and elites carry a shield attuned to one reaction.
## Kinds behave differently (ranged, chargers, healers, bombers, armour...), elites can
## carry an affix, and bosses pick one of five scripted patterns with set_boss().

signal died(enemy: Enemy)
signal rallied(enemy: Enemy)   # a boss raised its rally guard (see rally_secs)

const LAYER_ENEMIES := 2
## Flyers are drawn bigger than their body (sprite scale only: collision and hit radius
## stay) over a soft shadow on the floor below, so bats and wisps read as flying and are
## not lost among the player's effects. A bat (radius 6) draws 24 px, a wisp (9) 32 px,
## next to a 29 px grunt (11).
const FLYER_SCALE := { "swarmer": 1.5, "wisp": 1.35 }
const LAYER_WALLS := 4

## Per kind: [hp base, hp per difficulty, speed, radius, contact damage base, scrap].
const STATS := {
    "grunt": [26.0, 5.5, 115.0, 11.0, 8.0, 1],
    "runner": [12.0, 2.7, 215.0, 8.0, 5.0, 1],
    "brute": [110.0, 19.0, 70.0, 20.0, 16.0, 3],
    "swarmer": [7.0, 1.35, 190.0, 6.0, 4.0, 1],
    "spitter": [35.0, 6.8, 75.0, 12.0, 6.0, 2],
    "charger": [53.0, 9.5, 100.0, 14.0, 12.0, 3],
    "splitter": [70.0, 12.0, 95.0, 15.0, 9.0, 3],
    "shaman": [41.0, 8.0, 85.0, 11.0, 5.0, 4],
    "bomber": [29.0, 5.4, 160.0, 10.0, 6.0, 2],
    "warden": [190.0, 32.0, 60.0, 22.0, 14.0, 5],
    "wisp": [19.0, 4.0, 170.0, 9.0, 6.0, 2],
    "elite": [300.0, 60.0, 95.0, 17.0, 14.0, 10],
    "lobber": [40.0, 7.5, 80.0, 13.0, 6.0, 2],
    "boss": [1800.0, 420.0, 85.0, 30.0, 20.0, 40],
}

## Sprite tiles (column, row) in the 1-bit sheet; boss kinds are keyed by boss_kind.
const KIND_TILES := {
    "grunt": Vector2i(29, 6),
    "runner": Vector2i(26, 8),
    "brute": Vector2i(30, 6),
    "swarmer": Vector2i(31, 5),
    "spitter": Vector2i(25, 8),
    "charger": Vector2i(29, 7),
    "splitter": Vector2i(27, 8),
    "shaman": Vector2i(26, 9),
    "bomber": Vector2i(23, 8),
    "warden": Vector2i(24, 7),
    "wisp": Vector2i(27, 6),
    "elite": Vector2i(28, 5),
    "lobber": Vector2i(28, 6),
    "boss": Vector2i(30, 8),
    "brute_king": Vector2i(30, 8),
    "hive_mother": Vector2i(26, 5),
    "storm_warden": Vector2i(24, 8),
    "pyre_lord": Vector2i(25, 9),
    "void_herald": Vector2i(31, 9),
    "drowned_choir": Vector2i(27, 6),
}

const KIND_COLORS := {
    "grunt": Color(0.82, 0.78, 0.70),
    "runner": Color(0.66, 0.54, 0.76),
    "brute": Color(0.62, 0.30, 0.30),
    "swarmer": Color(0.78, 0.62, 0.40),
    "spitter": Color(0.50, 0.78, 0.45),
    "charger": Color(0.85, 0.48, 0.30),
    "splitter": Color(0.55, 0.80, 0.75),
    "shaman": Color(0.55, 0.85, 0.55),
    "bomber": Color(0.95, 0.50, 0.25),
    "warden": Color(0.60, 0.62, 0.70),
    "wisp": Color(0.70, 0.85, 1.00),
    "elite": Color(0.88, 0.45, 0.78),
    "lobber": Color(0.86, 0.70, 0.32),
    "boss": Color(0.92, 0.22, 0.30),
    "brute_king": Color(0.90, 0.35, 0.28),
    "hive_mother": Color(0.60, 0.85, 0.35),
    "storm_warden": Color(0.95, 0.90, 0.40),
    "pyre_lord": Color(1.00, 0.50, 0.20),
    "void_herald": Color(0.65, 0.35, 0.95),
    "drowned_choir": Color(0.45, 0.68, 0.88),
}

const AFFIXES := ["regenerating", "hasted", "trail", "volatile", "barrage", "sower", "mortar", "tether"]

## Key threats of Core loop reset section 8 (damage as a share of a 100 HP bar, times the
## floor's damage multiplier). The lobber hangs back and lobs a shell at where you stand: a
## ring fills in for the whole flight, then a burst. Chargers wind up 0.6 s behind a red line
## the length of their run, charge 500 px at 600 px/s and are stunned 1 s by a wall. Runners
## crouch 0.35 s, then lunge 120 px. At most MAX_RINGS hostile rings over a player at once.
const LOBBER_EVERY := 2.4
const LOBBER_WARN := 1.1
const LOBBER_R := 48.0
const LOBBER_DMG := 10.0
const CHARGE_SPEED := 600.0
const CHARGE_LEN := 500.0
const CHARGE_DMG := 15.0
const CHARGE_STUN := 1.0
const RUNNER_CROUCH := 0.35
const MELEE_CROUCH := 0.2      # grunts, swarmers and splitters before their lunge
const RUNNER_LUNGE := 120.0
const RUNNER_LUNGE_SPEED := 500.0
const SPIT_DMG_DEEP := 8.0      # a spitter shot from floor 3 (difficulty 10)
const MAX_RINGS := 2
## Zoning elites: the Sower drops SOW_N circles round itself every SOW_EVERY s (they fill
## over SOW_WARN s, then hurt for SOW_LIFE s); the Mortar lobs 3 shells around you; the
## Tether links to a player who stays within TETHER_R for TETHER_ARM s (the beam grows for
## TETHER_GROW s first) and drains until range or sight breaks.
const SOW_EVERY := 4.0
const SOW_N := 3
const SOW_R := 70.0
const SOW_WARN := 0.8
const SOW_LIFE := 5.0
const SOW_DMG := 5.0            # per 0.5 s
const MORTAR_EVERY := 3.4
const TETHER_R := 300.0
const TETHER_BREAK := 340.0
const TETHER_ARM := 2.0
const TETHER_GROW := 1.0
const TETHER_DPS := 3.0

## Depth pressure (difficulty pass, 2026-11-09). Bots on floors 2 to 5 stood in a crowd of
## melee that walked into their fire; one ranged kind fired one straight shot. By difficulty
## (floor 2 is 6 to 9, floor 3 is 10, floor 4 is 14, floor 5 is 18):
## - runners from FLANK_DIFF swing wide and close in from the side, not straight down the guns;
## - spitters from FAN_DIFF fire a three-shot fan aimed half-way ahead of a moving target,
##   each shot FAN_DMG of the old one, every 2 s instead of 1.6;
## - spitters from LOB_DIFF lob every third volley: a ring marks the landing spot for
##   SHELL_WARN s (hostile signature), then SHELL_R bursts. Killing the spitter cancels it;
## - spitters from FAN_DIFF arrive shooting: the first fan leaves 0.25 s after they emerge;
## - elites may roll "barrage" (SpawnTable): a ring of slow shots, glowing BARRAGE_WARN s first.
const FLANK_DIFF := 6
const FAN_DIFF := 8
const LOB_DIFF := 14
const FAN_SPREAD := 0.22
const FAN_DMG := 0.7          # x a single shot, per fan shot: the fan moves you, it does not out-damage the old shot
const LEAD := 0.5
const SHELL_WARN := 1.0
const SHELL_R := 56.0
const SHELL_DMG := 1.4         # x a spitter shot
const BARRAGE_EVERY := 3.4
const BARRAGE_WARN := 0.6
const BARRAGE_SHOTS := 10
const BARRAGE_SPEED := 165.0
const BOSS_KINDS := ["brute_king", "hive_mother", "storm_warden", "pyre_lord", "void_herald", "drowned_choir"]

## Spawns are telegraphed (Brotato's rule, design doc "Clarity pass"): a body emerges over
## EMERGE_SECS under a marker on the floor, harmless and untargetable. A player who comes within
## SPAWN_SHOVE of a marker moves it (Room.respawn_point, or another spot by the boss for its
## summons) and its telegraph starts over, so nothing ever arrives on top of anyone.
## The bot prints [SPAWN-MOVED] per move and [SPAWN-CHECK] at the end: no body may finish
## emerging within SPAWN_ASSERT of a player.
const EMERGE_SECS := 1.0
const SPAWN_SHOVE := 80.0
const SPAWN_ASSERT := 60.0
static var spawn_moved := 0
static var spawn_landed := 0
static var spawn_close := 0
static var spawn_log := false   # Main sets it for the bot

const BOMB_DAMAGE := 18.0
const BOMB_RADIUS := 90.0
const BOMB_TRIGGER := 40.0
## Fairness (Core loop reset 8): a lit fuse burns BOMB_FUSE s, and a bomber or volatile elite
## killed next to you only hurts you if its ring has shown for RING_SHOWN s.
const BOMB_FUSE := 0.6
const RING_SHOWN := 0.6
var _ring_vis := 0.0
const WARDEN_ARMOUR := 0.4
const SHAMAN_ARMOUR := 0.7
const MAX_ENEMIES_FOR_SUMMON := 45

# Charger modes (also used by the brute king).
const MODE_CHASE := 0
const MODE_TELEGRAPH := 1
const MODE_DASH := 2
const MODE_COOL := 3

var kind_name := "grunt"
var max_hp := 20.0
var hp := 20.0
var speed := 110.0
var radius := 12.0
var contact_damage := 8.0
var damage_mult := 1.0   # late-floor pressure, set by the room on spawn; scales shots too
var base_color := Color(0.85, 0.30, 0.30)
var immune_to: int = Element.Kind.NONE
## Exposed (Regions): a reaction here made the region's resistances count as weaknesses.
var exposed_time := 0.0
var is_elite := false
var scrap_value := 1
var last_hit_by: Player = null

## Elite affix: "" | "regenerating" | "hasted" | "trail" | "volatile". Set with set_affix().
var affix := ""
## Boss pattern: "" (plain chase) or one of BOSS_KINDS. Set with set_boss().
var boss_kind := ""
## The boss framework (BossBody): stagger, phases, name card and, for some kinds, body parts
## whose element state is swapped into `states`/`compound` below. null on everything else.
var body: BossBody = null

## Attuned shield: only the one reaction it is attuned to cracks it, one hit per crack.
var weakness := Vector2i(-1, -1)
var shield_hp := 0
var shield_max := 0
var reshield_weakness := Vector2i(-1, -1)   # bosses re-shield at half health
var reshield_hits := 0

var states: Dictionary = {}           # Element.Kind -> seconds remaining
## Tier 2 compound slot (Fusions.COMPOUNDS id): a reaction on this body primed it; the next
## new element fuses it (tier 3). One slot; a newer compound replaces the older.
var compound := ""
var compound_time := 0.0
var compound_origin := ""     # the reaction that left it (its two elements refresh, not fuse)
var fusion_cd := 0.0          # after a fusion: no new fusion and no new compound here
var _dot_tags := { "burn": [], "poison": [], "bleed": [] }   # Telemetry.dot_tag() of whoever set each DoT
var burn_dps := 0.0
var burn_time := 0.0
var marked_t := 0.0               # Marking Rounds: seconds this foe stays marked
const MARK_BONUS := 1.4
const TAINT_CHANCE := 0.25
const TAINT_RANGE := 120.0
static var _tainting := false
var frozen_time := 0.0
var slow_time := 0.0
var _lunge_t := 0.0
## Emerging: a telegraphed spawn. The enemy fades in where it will appear and cannot
## move or hurt for this long; shots can already hit it (killing it early is the reward).
var emerge := 0.0
## Focus targeting (Focus): damage already on its way here (shots in flight), and until when.
var _pending_dmg := 0.0
var _pending_until := 0.0
## A boss's entrance (BossShow): it rises through `emerge` (so nothing aims at it or
## touches it) with its own animation instead of the spawn marker.
var intro := false
var _intro_len := 2.5
var _intro_a := 1.0
var _lunge_cd := 0.0
var slow_factor := 1.0
var poison_dps := 0.0
var poison_time := 0.0
var poison_stacks := 0
var bleed_dps := 0.0
var bleed_time := 0.0
var corroded_time := 0.0
var stun_time := 0.0
var shove_vel := Vector2.ZERO
var armour_time := 0.0      # shaman blessing: incoming damage x0.7
var haste_aura_time := 0.0  # near a hasted elite: +15% speed

var _contact_cd := 0.0
var _spread_cd := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _shield_flash := 0.0
var _sprite: Sprite2D
var _shape: CircleShape2D
var _sprite_scale := 1.0
var _anim_t := 0.0
var _fx_t := 0.0   # status animation clock, runs even while frozen
var _shed_ms := 0  # last time a status shed a pixel into Fx (embers, poison motes)
var _dot_accum := 0.0   # damage-over-time waiting to be shown as one number
var _dot_color := Color.WHITE
var _dot_timer := 0.0
var _spawn_t := 0.0
var _squash := 0.0
var _floor_t := randf() * 0.25   # next floor-material check, staggered across enemies
var _on_ice := false
var _wading := false               # deep water in a room layout: slowed
var _nav_t := randf() * 0.25       # next sight-line check, staggered
var _nav_blocked := false          # a wall or chasm between us and the target: follow the room's flow

var _wave := 0
var _dead := false
var _exploded := false
var _reshield_at: Array = [0.5]   # fractions of max hp where the reshield fires
var _react_window := 0.0   # a reaction just fired: armour does not apply
var _since_hit := 99.0
var _strafe_sign := 1.0
var _strafe_t := 0.0

# Behaviour timers.
var _shoot_t := 0.0
var _volley := 0
var _shells: Array = []     # lobs in flight: [{ "at": Vector2 (global), "t", "warn", "r", "dmg" }]
var _zones: Array = []      # Sower circles: [{ "at": Vector2 (global), "age": float, "tick": float }]
var _sow_t := 2.0
var _mortar_t := 2.0
var _tether_t := 0.0        # seconds a player has stayed in range (arming)
var _tether_state := 0      # 0 idle, 1 the beam grows, 2 linked
var _tether_k := 0.0
var _tether_tick := 0.0
var _tether_to: Player = null
var _crouch_t := 0.0        # runner: crouching before a lunge
var _react_n := 0           # reactions on this enemy inside the last second (Elements.try_react)
var _react_last := -10.0
## Damage dealt inside a formed synergy or a level-5 resonance (Core loop reset 9): Main
## counts it at half when it measures the build. Synergies arrive in session 4; they raise
## synergy_depth around their damage.
static var synergy_depth := 0
static var synergy_dealt := 0.0
var _barrage_t := 0.0
var _pulse_t := 0.0
var _pulse_fx := 0.0
var _mode := MODE_CHASE
var _mode_t := 0.0
var _dash_dir := Vector2.RIGHT
var _fuse := -1.0
var _teleport_cd := 0.0
var _wisp_phase := 0.0
var _trail_t := 0.0

# Boss state.
var _phase := 1
var _t1 := 0.0
var _t2 := 0.0
var _t3 := 0.0
var _summoned_60 := false
var _summoned_30 := false
var _burst_left := 0
var _burst_t := 0.0
var _spiral_left := 0.0
var _spiral_angle := 0.0
var _ring_warn := 0.0
var _tele_warn := 0.0
var _tele_pos := Vector2.ZERO
var _pending: Array = []    # [{ "pos": Vector2, "t": float, "type": String }] summons being telegraphed
## Rally (floors 2+, set by the room): at each health fraction in rally_at the boss raises a
## guard and calls a wave of adds. Guarded it takes RALLY_LEAK of every hit until the adds
## are dead or the guard times out, so the fight turns to the horde for a while instead of
## to more health.
var rally_secs := 0.0
var rally_at: Array = []
var _ward_t := 0.0
var _ward_adds: Array = []
const RALLY_LEAK := 0.05

## Damage every enemy has actually lost (overkill trimmed), all sources: the room reads it to
## measure the party's output per arena second, which sizes the boss (Room._begin_boss).
static var dealt_total := 0.0
var _barrels: Array = []    # Brute King: barrels in flight [{ "from", "to", "t", "dur" }]
var _swallowed := 0         # Brute King: barrels in his gut (phase 2+); fire or shock sets them off
var _gut_warn := 0.0        # Brute King: > 0 while a Gut Blast winds up
const BRUTE_BARREL_CAP := 4
const BARREL_HIT_R := 34.0
const GUT_RADIUS := 130.0
const GUT_WARN := 1.1
var _burrow_state := 0       # Hive Mother: 1 digging in (wind-up), 2 underground, 0 above
var _burrow_t := 0.0
var _burrow_at := Vector2.ZERO
var _spore_t := 3.0
const BURROW_WARN := 0.8
const BURROW_UNDER := 2.6
const BURROW_MARK := 1.2       # the eruption circle shows this long before she bursts up
const ERUPT_R := 72.0
var _strikes: Array = []     # Storm Warden: [{ "pos", "warn", "flash", "self" }] lightning strikes
var _strike_t := 1.5
var _storm_trail := 0.0
const STRIKE_R := 58.0
const STRIKE_SELF_R := 1.6     # x radius: a recharge strike on himself
var _wells: Array = []        # Void Herald: gravity wells [{ "pos", "r", "warn", "t" }]
var _volleys: Array = []      # Void Herald phase 3: shards closing in [{ "from", "to", "warn", "t", "hit" }]
var _fed := {}                # Void Herald: element -> hits, for the theft in phase 2
var _stolen: int = Element.Kind.NONE
const WELL_R := 110.0
const WELL_WARN := 1.0
const WELL_LIFE := 6.0
const WELL_PULL := 45.0
const SHARD_WARN := 1.0
const SHARD_TRAVEL := 0.55
var _hazards: Array = []    # [{ "pos": Vector2, "t": float }] boss fire patches that hurt players
var _hazard_tick := 0.0


func configure(type: String, wave: int) -> void:
    kind_name = type
    _wave = wave
    var s: Array = STATS.get(type, STATS["grunt"])
    max_hp = float(s[0]) + float(s[1]) * float(wave)
    speed = float(s[2])
    radius = float(s[3])
    var per := 0.35
    if type == "elite" or type == "boss":
        per = 0.6
        is_elite = true
    if type == "boss":
        per = 0.8   # boss contact: 20 + 0.8 per difficulty
    contact_damage = float(s[4]) + per * float(wave)
    scrap_value = int(s[5])
    base_color = KIND_COLORS.get(type, base_color)
    match type:
        "swarmer":
            scrap_value = randi() % 2
        "wisp":
            immune_to = Element.ALL.pick_random()
            _wisp_phase = randf() * TAU
        "spitter":
            # Deeper down they arrive shooting: a build that melts a crowd on landing still
            # has a fan in the air to step out of (the emerge marker is the warning).
            _shoot_t = 0.25 if wave >= FAN_DIFF and not Main.old_balance else randf_range(0.6, 1.6)
        "shaman":
            _pulse_t = randf_range(1.0, 3.0)
        "lobber":
            _shoot_t = randf_range(1.0, 2.0)
    _strafe_sign = 1.0 if randf() < 0.5 else -1.0
    hp = max_hp


## Elite affix; "" clears it. Call after configure (before or after adding to the tree).
func set_affix(name: String) -> void:
    affix = name if AFFIXES.has(name) else ""
    if affix == "barrage":
        _barrage_t = 2.0
    _sow_t = 2.0
    _mortar_t = 2.0
    _ensure_crisp()
    queue_redraw()


var _crisp_on := false


## The hostile overlay (telegraphs, blast rings, lob marks) for kinds that draw one. Elites
## take their affix after entering the tree, so set_affix asks again (a volatile elite's
## blast ring was never drawn before the difficulty pass).
func _ensure_crisp() -> void:
    if _crisp_on or not is_inside_tree():
        return
    if kind_name in ["bomber", "charger", "boss", "lobber"] or affix in ["volatile", "barrage", "sower", "mortar", "tether"]             or (kind_name == "spitter" and _wave >= _lob_diff()):
        _crisp_on = true
        Crisp.attach(self, _draw_hostile, 3)


## Boss pattern. Call after configure("boss", wave), before or after adding to the tree.
func set_boss(kind: String) -> void:
    boss_kind = kind if BOSS_KINDS.has(kind) else ""
    base_color = KIND_COLORS.get(boss_kind if boss_kind != "" else kind_name, base_color)
    _reshield_at = [0.5]
    _t1 = 2.0
    _t2 = 3.0
    _t3 = 4.0
    match boss_kind:
        "brute_king":
            speed = 95.0
            radius = 44.0
        "hive_mother":
            speed = 65.0
            radius = 44.0
            _t1 = 2.0
            _t2 = 3.5
        "storm_warden":
            speed = 70.0
            radius = 42.0
            _t1 = 2.5
            _t2 = 6.0
        "pyre_lord":
            speed = 80.0
            radius = 46.0
            _t1 = 0.5
            _t2 = 5.0
            _t3 = 3.0
        "void_herald":
            speed = 70.0
            radius = 42.0
            _reshield_at = [0.66, 0.33]
            _t1 = 2.0
            _t2 = 5.0
        "drowned_choir":
            speed = 55.0
            radius = 46.0
            _t1 = 2.5
            _t2 = 4.0
            _t3 = 2.0
    # Presence (vision gap analysis, slam dunk 1): every boss is at least three times the
    # player's radius (14). Contact reach stays near the old body (contact_reach()).
    body = BossBody.new(self, boss_kind) if kind_name == "boss" else null
    if _shape != null:
        _shape.radius = radius
    _setup_sprite()
    queue_redraw()


func _ready() -> void:
    add_to_group("enemies")
    collision_layer = LAYER_ENEMIES
    collision_mask = LAYER_WALLS | LAYER_ENEMIES
    var shape := CollisionShape2D.new()
    _shape = CircleShape2D.new()
    _shape.radius = radius
    shape.shape = _shape
    add_child(shape)
    z_index = 8
    _setup_sprite()
    _ensure_crisp()
    var fx := _fx()
    if fx != null:
        fx.puff(Art.PARTICLES["smoke"], global_position, Color(0.1, 0.08, 0.1, 0.7), radius * 4.5, 0.5, false, Vector2(0, -20))


func _setup_sprite() -> void:
    if not is_inside_tree():
        return
    var key := boss_kind if boss_kind != "" else kind_name
    if KIND_COLORS.has(key):
        base_color = KIND_COLORS[key]
    else:
        base_color = Art.ENEMY_TINT.get(kind_name, base_color)
    var coord: Vector2i = KIND_TILES[key] if KIND_TILES.has(key) else Art.TILES.get(kind_name, Art.TILES["grunt"])
    # Clarity pass: bodies draw 15% larger than their hit circle, with a thick dark outline.
    _sprite_scale = radius / 6.0 * float(FLYER_SCALE.get(kind_name, 1.0)) * 1.15
    if kind_name in SpawnTable.KEY:
        _sprite_scale *= 1.15   # key threats stand out of the crowd (section 8: 1.2x a grunt)
    if _sprite == null:
        _sprite = Art.sprite(coord, 0.01, base_color)
        add_child(_sprite)
    else:
        _sprite.texture = Art.tile(coord)
        _sprite.modulate = base_color


func _fx() -> Fx:
    var scene := get_tree().current_scene
    if scene != null and "fx" in scene:
        return scene.fx
    return null


## Where projectiles, clouds and other loose effects go: the current room, else our parent.
func _world() -> Node:
    var scene := get_tree().current_scene
    if scene != null and "current" in scene and scene.current != null:
        return scene.current
    return get_parent()


## The room's floor area in global coordinates, if the room exposes one.
func _room_rect() -> Rect2:
    var w := _world()
    if w != null and w is Node2D and "rect" in w:
        var r = w.rect
        if r is Rect2:
            var rr: Rect2 = r
            return Rect2((w as Node2D).global_position + rr.position, rr.size)
    return Rect2()


# --- States and reactions --------------------------------------------------


func has_state(kind: int) -> bool:
    return states.has(kind)


func clear_state(kind: int) -> void:
    states.erase(kind)
    queue_redraw()


func shielded() -> bool:
    return shield_hp > 0


func set_shield(pair: Vector2i, hits: int) -> void:
    weakness = pair
    shield_hp = hits
    shield_max = hits
    queue_redraw()


func weakness_name() -> String:
    if weakness.x < 0:
        return ""
    return Elements.reaction_name(weakness.x, weakness.y)


## Lands an element on this enemy. If a different state is already present and the
## pair reacts, the reaction fires and the old state is consumed. Returns the reaction name.
func apply_element(kind: int, potency: float, source: Player = null) -> String:
    if kind == Element.Kind.NONE or emerge > 0.0:
        return ""
    if source != null and is_instance_valid(source):
        # Transmuter: your Wet hits freeze instead of soaking.
        if kind == Element.Kind.WET and source.stat("transmute") > 0.0:
            kind = Element.Kind.ICE
        # Spreading Taint: a share of what you apply jumps to the nearest foes.
        var taint := int(source.stat("taint"))
        if taint > 0 and not _tainting and randf() < TAINT_CHANCE:
            _tainting = true
            var near := EnemyGrid.overlapping(get_tree(), global_position, TAINT_RANGE)
            var n := 0
            for e in near:
                if n >= taint:
                    break
                if e != self and is_instance_valid(e) and not e.is_queued_for_deletion():
                    e.apply_element(kind, potency * 0.6, source)
                    Elements.lightning_arc.emit(global_position, e.global_position)
                    n += 1
            _tainting = false
    if source != null:
        last_hit_by = source
    if boss_kind == "void_herald" and source != null:
        _fed[kind] = int(_fed.get(kind, 0)) + 1
    if boss_kind == "brute_king" and _swallowed > 0 and _gut_warn <= 0.0 and hp > 0.0 \
            and (kind == Element.Kind.FIRE or kind == Element.Kind.SHOCK):
        # The barrels in his gut catch: he braces, then bursts (telegraphed ring).
        _gut_warn = GUT_WARN
        Elements.reaction_fired.emit("His gut catches!", global_position + Vector2(0, -radius * 1.6), Color(1.0, 0.6, 0.25))
        Sfx.play_at("react_ignition", global_position, 0.0)
    # What the element does to the body's condition before any pair reaction:
    # water puts fire out, fire thaws ice, wind fans a burning body onto its neighbours.
    if kind == Element.Kind.WET and burn_time > 0.0:
        burn_time = 0.0
        Elements.nova.emit(global_position, radius * 2.0, Color(0.9, 0.95, 1.0, 0.5))
    if kind == Element.Kind.FIRE and frozen_time > 0.0:
        frozen_time = 0.0
    if kind == Element.Kind.GALE and burn_time > 0.0:
        for e in get_tree().get_nodes_in_group("enemies"):
            if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                    and e.global_position.distance_to(global_position) <= 110.0:
                e.add_burn(burn_dps * 0.7, 2.5)
    # Tier 3 before any pair reaction: a compound on this body meets a new element.
    # A boss part may shrug an element off (BossBody.inert / sealed).
    if compound != "" and (body == null or not body.sealed(kind)):
        var cid := compound
        if Fusions.fusion(cid, kind, compound_origin).is_empty():
            # One of its own elements: the compound is fed, not fused.
            compound_time = maxf(compound_time, float(Fusions.compound(cid).get("lifetime_enemy", 0.0)))
        elif fusion_cd <= 0.0:
            compound = ""
            var fused := Elements.try_fuse(self, cid, compound_origin, kind, potency, source)
            if fused != "":
                if body != null and is_instance_valid(self):
                    if body.has_parts():
                        fusion_cd = BossBody.PART_FUSION_CD
                    body.on_product(fused, int(Fusions.by_name(fused).get("tier", Fusions.TIER_FUSION)), true)
                expose()
                queue_redraw()
                return fused
            compound = cid   # over the room's budget: the element lands plainly, the compound stays
    if body != null and body.inert(kind):
        return ""
    for existing in (states.keys() if Elements.may_react() else []):
        if existing == kind:
            continue
        var reaction := Elements.reaction_name(existing, kind)
        if reaction == "":
            continue
        states.erase(existing)
        if source != null:
            potency *= 1.0 + source.stat("potency:" + reaction)
        if marked_t > 0.0:
            potency *= MARK_BONUS   # Marking Rounds
        _react_window = 0.3
        expose()
        _on_reaction_pair(existing, kind)
        Elements.try_react(self, existing, kind, potency)
        if body != null and is_instance_valid(self) and hp > 0.0:
            body.on_product(reaction, Fusions.TIER_REACTION, true)
        if source != null and is_instance_valid(source):
            source.on_reaction(reaction, global_position)
            Items.fire(source, "reaction", { "target": self, "reaction": reaction, "element": kind, "other": existing, "pos": global_position })
        if is_instance_valid(self):
            queue_redraw()
        return reaction
    var duration: float = Element.DURATION[kind] * resist_mult(kind)
    if source != null:
        duration *= 1.0 + source.stat("state_duration")
    states[kind] = duration
    queue_redraw()
    return ""


## The region's soft resistance to `kind` on this body (Regions.RESISTED / WEAK, 1.0 for
## anything else); a resisted element counts as a weakness while the body is Exposed.
func resist_mult(kind: int) -> float:
    if kind == Element.Kind.NONE:
        return 1.0
    if Regions.active_weak.has(kind):
        return Regions.WEAK
    if Regions.active_resists.has(kind):
        return Regions.WEAK if exposed_time > 0.0 else Regions.RESISTED
    return 1.0


## `amount` of `kind` damage after the region's resistance, counted for the bot logs.
func resisted(kind: int, amount: float) -> float:
    var m := resist_mult(kind)
    var out := amount * m
    var bucket := "plain"
    if m > 1.0:
        bucket = "exposed" if Regions.active_resists.has(kind) else "weak"
    elif m < 1.0:
        bucket = "resisted"
    Regions.stat_dmg[bucket] += out
    return out


## A reaction or fusion on this body: Exposed for Regions.EXPOSED_SECS, if the region
## resists anything (and `--no-exposed` is off).
func expose() -> void:
    if not Regions.exposed_enabled or Regions.active_resists.is_empty() or hp <= 0.0:
        return
    if exposed_time <= 0.0:
        Regions.stat_exposed += 1
    exposed_time = Regions.EXPOSED_SECS
    queue_redraw()


## A reaction left its compound on this body. False while the post-fusion cooldown runs.
func set_compound(cid: String, origin: String, life: float) -> bool:
    if fusion_cd > 0.0 or life <= 0.0 or _dead:
        return false
    compound = cid
    compound_origin = origin
    compound_time = life
    queue_redraw()
    return true


## Fusions crack 2 pips, cataclysms 3 (Fusions.SHIELD_CRACKS).
func crack_shield(n: int) -> void:
    if not shielded() or n <= 0:
        return
    shield_hp = maxi(0, shield_hp - n)
    _shield_flash = 0.4
    if shield_hp <= 0:
        Elements.reaction_fired.emit("Shield broken!", global_position, Color.WHITE)
    else:
        Elements.reaction_fired.emit("Shield cracked", global_position, Color(1, 1, 1, 0.9))


## Any reaction cracks a shield; the one it is attuned to cracks it twice.
func _on_reaction_pair(a: int, b: int) -> void:
    if not shielded():
        return
    shield_hp -= 2 if Element.pair_key(a, b) == weakness else 1
    _shield_flash = 0.4
    if shield_hp <= 0:
        shield_hp = 0
        Elements.reaction_fired.emit("Shield broken!", global_position, Color.WHITE)
    else:
        Elements.reaction_fired.emit("Shield cracked", global_position, Color(1, 1, 1, 0.9))


## Armoured bodies (wardens, the storm warden) shrug off raw hits until they carry an element.
func is_armoured() -> bool:
    return kind_name == "warden" or boss_kind == "storm_warden"


func take_damage(amount: float, color: Color, flash: bool = true, source: Player = null, crit: bool = false) -> void:
    if hp <= 0.0 or emerge > 0.0:
        return   # a spawn marker is not a target yet
    if source != null:
        last_hit_by = source
    if body != null:
        amount *= body.taken_mult(flash)   # the part hit, and the stagger bonus
        if _burrow_state == 2 and not body.any_visible():
            amount *= 0.25   # underground with her sacs gone: little gets through
    if shielded() and (body == null or not body.staggered()):
        # A shield blocks most raw damage, never all of it: reactions are the fast way in.
        # A staggered boss has dropped its guard.
        _shield_flash = maxf(_shield_flash, 0.15)
        amount *= 0.2
    if flash and is_armoured() and states.is_empty() and _react_window <= 0.0:
        amount *= WARDEN_ARMOUR
    if armour_time > 0.0:
        amount *= SHAMAN_ARMOUR
    if frozen_time > 0.0:
        amount *= 1.6   # shatter bonus; it was x3, which made freeze builds trivial
    if corroded_time > 0.0:
        amount *= 1.5
    if _ward_t > 0.0:
        amount *= RALLY_LEAK
        _shield_flash = maxf(_shield_flash, 0.15)
    elif rally_secs > 0.0 and not rally_at.is_empty() and hp - amount <= max_hp * float(rally_at[0]):
        # A rally threshold stops the hit there: no burst skips a rally.
        amount = maxf(0.0, hp - max_hp * float(rally_at[0]))
        rally_at.pop_front()
        _ward_t = rally_secs
        rallied.emit.call_deferred(self)
    hp -= amount
    dealt_total += amount + minf(hp, 0.0)
    if synergy_depth > 0:
        synergy_dealt += amount + minf(hp, 0.0)
    Telemetry.hit(amount + minf(hp, 0.0), color, flash, source)
    _since_hit = 0.0
    if flash:
        var fx := _fx()
        if fx != null:
            fx.number(global_position + Vector2(0, -radius), amount, color if color != Color.WHITE else Color(0.95, 0.9, 0.85), crit)
    else:
        _dot_accum += amount
        _dot_color = color
    if flash:
        _flash = 0.12
        _flash_color = color
        _squash = 1.0
        Sfx.hit_enemy(self)
    if hp <= 0.0:
        _die()
        return
    if reshield_hits > 0 and not _reshield_at.is_empty() and hp <= max_hp * float(_reshield_at[0]):
        _reshield_at.pop_front()
        set_shield(reshield_weakness, reshield_hits)
        if kind_name == "boss": Sfx.play("boss_phase")
        if _reshield_at.is_empty():
            reshield_hits = 0
        _shield_flash = 0.5
        Elements.reaction_fired.emit("Shield restored!", global_position, Color.WHITE)
    if flash and kind_name == "wisp" and _teleport_cd <= 0.0:
        _teleport_cd = 1.0
        _blink(150.0)
    queue_redraw()


func heal(amount: float, _source: String = "") -> void:
    if hp <= 0.0:
        return
    hp = minf(max_hp, hp + amount)
    queue_redraw()


## Removed without dying: no scrap, no kill credit (room cleared, party left).
func vanish() -> void:
    _dead = true
    remove_from_group("enemies")
    queue_free()


## Crowd control has diminishing returns (WoW style): within DR_WINDOW seconds of the
## first freeze or stun, the next lasts half, then a quarter, then the enemy is immune
## until the window runs out. Elites shrug off half, bosses three quarters. Without this,
## six elements lock a room down for good and standing still wins.
const DR_WINDOW := 7.0
const SLOW_FLOOR := 0.5   # nothing slows an enemy below half speed
var _dr_count := { "freeze": 0, "stun": 0 }
var _dr_left := { "freeze": 0.0, "stun": 0.0 }


func cc_resist() -> float:
    if kind_name == "boss":
        return 0.25
    if is_elite:
        return 0.5
    if kind_name in ["brute", "warden"]:
        return 0.7
    return 1.0


## How much of a freeze or stun lands now, and count it toward diminishing returns.
func _cc_scale(kind: String) -> float:
    if _dr_left[kind] <= 0.0:
        _dr_count[kind] = 0
    var step: int = _dr_count[kind]
    var k: float = [1.0, 0.5, 0.25, 0.0][mini(step, 3)]
    _dr_count[kind] = step + 1
    if step == 0:
        _dr_left[kind] = DR_WINDOW
    return k * cc_resist()


func freeze(seconds: float) -> void:
    var s := seconds * _cc_scale("freeze")
    if s < 0.15:
        return
    frozen_time = maxf(frozen_time, s)
    queue_redraw()


func apply_slow(factor: float, seconds: float) -> void:
    # Resistance pulls the factor back toward full speed; the floor caps any slow at 50%.
    factor = maxf(SLOW_FLOOR, lerpf(1.0, factor, cc_resist()))
    slow_factor = minf(slow_factor, factor) if slow_time > 0.0 else factor
    slow_time = maxf(slow_time, seconds)


func add_burn(dps: float, seconds: float) -> void:
    if has_state(Element.Kind.OIL):
        seconds *= 1.5   # oil keeps it burning
    if has_state(Element.Kind.WET):
        seconds *= 0.5   # damp bodies burn badly
    _tag_dot("burn", burn_time)
    burn_dps = maxf(burn_dps, dps)
    burn_time = maxf(burn_time, seconds)
    queue_redraw()


func add_poison(dps: float, seconds: float) -> void:
    _tag_dot("poison", poison_time)
    poison_stacks = mini(6, poison_stacks + 1)
    poison_dps = maxf(poison_dps, dps)
    poison_time = maxf(poison_time, seconds)


func add_bleed(dps: float, seconds: float) -> void:
    _tag_dot("bleed", bleed_time)
    bleed_dps = maxf(bleed_dps, dps)
    bleed_time = maxf(bleed_time, seconds)


## Telemetry: a damage-over-time ticks under the tier (and fusion) that last set it, unless a
## lower tier tops up one that is still running.
func _tag_dot(key: String, left: float) -> void:
    var tag: Array = Telemetry.dot_tag()
    var old: Array = _dot_tags[key]
    if left <= 0.0 or old.is_empty() or int(tag[0]) >= int(old[0]):
        _dot_tags[key] = tag


func corrode(seconds: float) -> void:
    corroded_time = maxf(corroded_time, seconds)


func stun(seconds: float) -> void:
    var s := seconds * _cc_scale("stun")
    if s < 0.15:
        return
    stun_time = maxf(stun_time, s)


## A one-off kick, decays over a few frames. Heavy enemies move less.
func shove(v: Vector2) -> void:
    shove_vel += v * cc_resist()


## Strip every element state; returns how many were removed.
func purge_states() -> int:
    var n := states.size()
    states.clear()
    queue_redraw()
    return n


func _die() -> void:
    if _dead:
        return
    _dead = true
    hp = minf(hp, 0.0)
    if frozen_time > 0.0:
        Elements.nova.emit(global_position, radius * 2.5, Color(Element.COLORS[Element.Kind.ICE], 0.6))
    if last_hit_by != null and is_instance_valid(last_hit_by):
        var ctx := { "target": self, "pos": global_position, "elite": is_elite }
        Items.fire(last_hit_by, "kill", ctx)
        if is_elite:
            Items.fire(last_hit_by, "elite_kill", ctx)
    # Plague: a poisoned corpse passes it on.
    if poison_time > 0.0:
        for e in get_tree().get_nodes_in_group("enemies"):
            if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                    and e.global_position.distance_to(global_position) <= 110.0:
                e.add_poison(poison_dps, 3.0)
        Elements.nova.emit(global_position, 110.0, Color(Element.COLORS[Element.Kind.POISON], 0.5))
    remove_from_group("enemies")
    if (kind_name == "bomber" or affix == "volatile") and not _exploded:
        if Main.old_balance:
            _explode(BOMB_DAMAGE, BOMB_RADIUS)
        else:
            # Killed before its fuse ran: the corpse's fuse burns BOMB_FUSE s behind the full
            # ring, then it blows (Core loop reset 8: every damaging area shows 0.6 s first).
            _fuse = BOMB_FUSE
            _corpse = true
    if kind_name == "splitter":
        for i in 2:
            var off := Vector2.RIGHT.rotated(randf() * TAU) * radius
            _summon("swarmer", global_position + off, false)
    var fx := _fx()
    if fx != null:
        fx.corpse(_sprite.texture, global_position, _sprite_scale, _sprite.modulate, _sprite.flip_h)
        fx.bones(global_position, base_color.darkened(0.2), 4 if is_elite else 2)
        if burn_time > 0.0:
            fx.scorch(global_position, radius * 4.0)
        fx._shake(6.0 if kind_name == "boss" else (2.5 if is_elite else 0.8))
    match kind_name:
        "boss":
            Sfx.play("die_boss")
            var rm := Room.here
            if rm != null and is_instance_valid(rm) and rm.show != null and is_instance_valid(rm.show):
                rm.show.death(global_position, radius)
        _:
            Sfx.die_enemy(self)
    died.emit(self)
    if _corpse:
        collision_layer = 0
        collision_mask = 0
        if _sprite != null:
            _sprite.modulate = Color(0.35, 0.3, 0.3, 0.8)
        return
    queue_free()


var _corpse := false   # a killed bomber whose blast is still to come


## Hostile tells on the Crisp layer, above the player's own effects (Hostile): blast
## rings and the dash telegraph of chargers and the brute king.
func _draw_hostile(cv: CanvasItem) -> void:
    if kind_name == "bomber" or affix == "volatile":
        _draw_blast_ring(cv)
    for sh in _shells:
        # Where a lob lands: dark under red, filling in as it falls.
        var r := float(sh["r"])
        var k := 1.0 - float(sh["t"]) / float(sh["warn"])
        var at := to_local(Vector2(sh["at"]))
        cv.draw_circle(at, r * k, Color(Hostile.RED, 0.18))
        cv.draw_arc(at, r, 0.0, TAU, 32, Color(Hostile.DARK, 0.8), 6.0)
        cv.draw_arc(at, r, 0.0, TAU, 32, Color(Hostile.RED, 0.45 + 0.5 * k), 2.5)
    for z in _zones:
        # Sower circles: fill in while harmless, then a solid marching ring while they hurt.
        var age := float(z["age"])
        var zat := to_local(Vector2(z["at"]))
        var fill := clampf(age / SOW_WARN, 0.0, 1.0)
        var fade := clampf((SOW_WARN + SOW_LIFE - age) / 0.4, 0.0, 1.0)
        cv.draw_circle(zat, SOW_R * fill, Color(Hostile.RED, (0.12 if age < SOW_WARN else 0.22) * fade))
        Hostile.dash_ring(cv, zat, SOW_R, (0.6 if age < SOW_WARN else 0.95) * fade, 2.0 if age < SOW_WARN else 3.0)
    if _tether_state > 0 and _tether_to != null and is_instance_valid(_tether_to):
        var to := to_local(_tether_to.global_position)
        var tip := to * (_tether_k if _tether_state == 1 else 1.0)
        var ta := 0.55 + 0.35 * absf(sin(_fx_t * 14.0))
        cv.draw_line(Vector2.ZERO, tip, Color(Hostile.DARK, 0.8), 7.0 if _tether_state == 2 else 4.0)
        cv.draw_line(Vector2.ZERO, tip, Color(Hostile.RED, ta), 3.0 if _tether_state == 2 else 1.5)
    if affix == "barrage" and _barrage_t <= BARRAGE_WARN and hp > 0.0 and emerge <= 0.0:
        var kb := 1.0 - _barrage_t / BARRAGE_WARN
        var ab := 0.45 + 0.4 * absf(sin(_fx_t * 18.0))
        cv.draw_arc(Vector2.ZERO, radius * (2.2 - 0.6 * kb), 0.0, TAU, 32, Color(Hostile.DARK, 0.8), 5.0)
        cv.draw_arc(Vector2.ZERO, radius * (2.2 - 0.6 * kb), 0.0, TAU, 32, Color(Hostile.RED, ab), 2.0)
    if boss_kind == "pyre_lord":
        _draw_pyre_hostile(cv)
    elif boss_kind == "brute_king":
        _draw_brute_hostile(cv)
    elif boss_kind == "hive_mother":
        _draw_hive_hostile(cv)
    elif boss_kind == "storm_warden":
        _draw_warden_hostile(cv)
    elif boss_kind == "void_herald":
        _draw_herald_hostile(cv)
    elif boss_kind == "drowned_choir":
        _draw_choir_hostile(cv)
    if kind_name == "boss" and _phase >= 2 and not intro and hp > 0.0:
        _draw_boss_cracks(cv)
    if body != null and body.has_parts():
        _draw_parts(cv)
    if _mode == MODE_TELEGRAPH and emerge <= 0.0 and hp > 0.0:
        var length := (420.0 * 0.5 if Main.old_balance else CHARGE_LEN) if kind_name == "charger" else 300.0
        var a := 0.45 + 0.4 * absf(sin(_fx_t * 20.0))
        var w := radius * (0.6 if kind_name == "charger" else 1.6)
        var tip := _dash_dir * length
        cv.draw_line(Vector2.ZERO, tip, Color(Hostile.DARK, 0.6 * a), w + 4.0)
        cv.draw_line(Vector2.ZERO, tip, Color(Hostile.RED, a), w)
        cv.draw_line(Vector2.ZERO, tip, Color(1, 0.9, 0.8, a), 1.5)


## Bombers (and volatile elites) show their blast radius on the Crisp layer once a player
## is near enough to be caught: a thin ring that firms up as the player closes in, solid
## and filled while the fuse burns. Their blast, on reaching you or on dying next to you,
## was the largest single source of damage taken in the 2026-11-06 telemetry (23%).
func _draw_blast_ring(cv: CanvasItem) -> void:
    if _exploded or not is_inside_tree():
        return
    var near := INF
    for p in get_tree().get_nodes_in_group("players"):
        var pl := p as Node2D
        if pl != null:
            near = minf(near, pl.global_position.distance_to(global_position))
    var reach := BOMB_RADIUS + 14.0
    var k := clampf(1.0 - (near - reach) / 110.0, 0.0, 1.0)
    if _fuse >= 0.0:
        k = 1.0
    if k <= 0.0:
        return
    if _fuse >= 0.0:
        cv.draw_circle(Vector2.ZERO, BOMB_RADIUS, Color(Hostile.RED, 0.16))
    Hostile.dash_ring(cv, Vector2.ZERO, BOMB_RADIUS, 0.8 * k, 1.5 if _fuse < 0.0 else 2.5)


## Bomber blast: hurts players, and lands Fire on nearby enemies so reactions go off.
func _explode(dmg: float, rad: float) -> void:
    if _exploded:
        return
    _exploded = true
    var pos := global_position
    Elements.nova.emit(pos, rad, Color(Element.COLORS[Element.Kind.FIRE], 0.7))
    Sfx.play("nova_fire")
    var fx := _fx()
    if fx != null:
        fx.blast(pos, rad, Element.COLORS[Element.Kind.FIRE])
        fx._shake(4.0)
    # Blasts scale with the floor like contact and shots (they were flat 18 and the top
    # damage source of floors 2 to 4 in run 4487a37a).
    var hit := dmg if Main.old_balance else dmg * damage_mult
    var fair := Main.old_balance or _fuse > -0.99 or _ring_vis >= RING_SHOWN   # _fuse is -1 until lit
    for p in get_tree().get_nodes_in_group("players"):
        if fair and is_instance_valid(p) and p.alive and p.global_position.distance_to(pos) <= rad + p.radius:
            p.take_damage(hit, self)
    var potency := 5.0 + 0.3 * float(_wave)
    for e in get_tree().get_nodes_in_group("enemies"):
        if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                and e.global_position.distance_to(pos) <= rad:
            e.apply_element(Element.Kind.FIRE, potency, null)
    var mats := Materials.find(self)
    if mats != null:
        mats.ignite(pos, rad)          # fuel in the blast catches
        mats.ignite(pos, 20.0, true)   # and the crater burns briefly


## What the floor does to us, a few times a second (see Materials).
func _feel_floor() -> void:
    _on_ice = false
    var rm := Room.here
    _wading = rm != null and is_instance_valid(rm) and rm.is_deep(global_position)
    var mats := Materials.find(self)
    if mats == null:
        return
    match mats.material_at(global_position):
        Materials.FIRE:
            add_burn(4.0, 1.5)
        Materials.WATER:
            if not has_state(Element.Kind.WET):
                apply_element(Element.Kind.WET, 1.0, null)
        Materials.CHARGED:
            take_damage(3.0, Element.COLORS[Element.Kind.SHOCK], true)
            if not _dead and hp > 0.0 and not has_state(Element.Kind.SHOCK):
                apply_element(Element.Kind.SHOCK, 1.0, null)
        Materials.POISON:
            add_poison(2.0, 2.0)
        Materials.ACID:
            corrode(1.0)
        Materials.OIL:
            if burn_time > 0.0:
                mats.ignite(global_position, radius)   # a burning body lights the oil it walks in
            elif not has_state(Element.Kind.OIL):
                apply_element(Element.Kind.OIL, 1.0, null)
        Materials.ICE:
            _on_ice = true


## A bomber that reached a player: blows up, no scrap.
func _detonate() -> void:
    scrap_value = 0
    _explode(BOMB_DAMAGE, BOMB_RADIUS)
    hp = 0.0
    _die()


## Spawns another enemy beside this one, in the same container, reporting its death to
## whoever listens to ours (the room). Added deferred: this can run inside a physics callback.
func _summon(type: String, pos: Vector2, check_cap: bool = true) -> Enemy:
    var parent := get_parent()
    if parent == null:
        return null
    if check_cap and get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES_FOR_SUMMON:
        return null
    var rr := _room_rect()
    if rr.has_area():
        var inner := rr.grow(-40.0)
        pos = Vector2(clampf(pos.x, inner.position.x, inner.end.x), clampf(pos.y, inner.position.y, inner.end.y))
    var e := Enemy.new()
    e.configure(type, _wave)
    if not Main.old_balance:
        # Summons hit as hard as the floor's own spawns (they were always x1.0).
        e.damage_mult = damage_mult
        e.contact_damage *= damage_mult
    if parent is Node2D:
        e.position = (parent as Node2D).to_local(pos)
    else:
        e.position = pos
    for c in died.get_connections():
        var cb: Callable = c["callable"]
        if not e.died.is_connected(cb):
            e.died.connect(cb)
    parent.add_child.call_deferred(e)
    return e


func _shoot(dir: Vector2, spd: float, dmg: float, element: int, life: float = 3.0, rad: float = 6.0) -> void:
    var w := _world()
    if w == null:
        return
    var p := EnemyProjectile.new()
    p.damage = dmg * damage_mult
    p.speed = spd
    p.element = element
    p.lifetime = life
    p.radius = rad
    p.direction = dir.normalized()
    p.owner_enemy = self
    p.shooter = Telemetry.enemy_label(self)
    w.add_child(p)
    p.global_position = global_position + p.direction * radius * 0.8


func _projectile_damage(base: float) -> float:
    return base + 0.35 * float(_wave)


## Jumps up to `dist` px in a random direction, kept inside the room.
func _blink(dist: float) -> void:
    var to := global_position + Vector2.RIGHT.rotated(randf() * TAU) * dist
    var rr := _room_rect()
    if rr.has_area():
        var inner := rr.grow(-50.0)
        to = Vector2(clampf(to.x, inner.position.x, inner.end.x), clampf(to.y, inner.position.y, inner.end.y))
    _teleport_to(to)


func _teleport_to(to: Vector2) -> void:
    Elements.nova.emit(global_position, radius * 2.5, Color(base_color, 0.5))
    set_deferred("global_position", to)
    _spawn_t = 0.3
    var fx := _fx()
    if fx != null:
        fx.puff(Art.PARTICLES["smoke"], to, Color(base_color, 0.6), radius * 3.0, 0.4, false, Vector2(0, -10))


# --- Frame -----------------------------------------------------------------


## The entrance begins: the boss rises for `secs` as a non-target (BossShow).
func start_intro(secs: float) -> void:
    intro = true
    _intro_len = secs
    emerge = secs
    _intro_sprite()


## Contact damage reach from the centre: a boss's drawn body is bigger than what hurts.
func contact_reach() -> float:
    return radius * 0.8 if kind_name == "boss" else radius


func _physics_process(delta: float) -> void:
    if marked_t > 0.0:
        marked_t -= delta
    if _corpse:
        _fuse -= delta
        _fx_t += delta
        queue_redraw()
        if _fuse <= 0.0:
            _corpse = false
            _explode(BOMB_DAMAGE, BOMB_RADIUS)
            queue_free()
        return
    if intro:
        emerge -= delta
        _fx_t += delta
        _intro_sprite()
        if emerge <= 0.0:
            emerge = 0.0
            intro = false
            _intro_a = 1.0
            _landed(global_position)
        queue_redraw()
        return
    if emerge > 0.0:
        emerge -= delta
        _guard_spawn()
        if emerge <= 0.0:
            _landed(global_position)
        queue_redraw()
        return
    for kind in states.keys():
        states[kind] -= delta
        if states[kind] <= 0.0:
            states.erase(kind)
    _fx_t += delta
    _dot_timer -= delta
    if _dot_timer <= 0.0 and _dot_accum >= 0.5:
        var fx := _fx()
        if fx != null:
            fx.number(global_position + Vector2(0, -radius), _dot_accum, _dot_color, false, true)
        _dot_accum = 0.0
        _dot_timer = 0.5
    if compound != "":
        compound_time -= delta
        if compound_time <= 0.0:
            compound = ""
    fusion_cd = maxf(0.0, fusion_cd - delta)
    if body != null:
        body.tick(delta)
    if burn_time > 0.0:
        burn_time -= delta
        Telemetry.dot_begin(_dot_tags["burn"])
        take_damage(resisted(Element.Kind.FIRE, burn_dps * delta), Element.COLORS[Element.Kind.FIRE], false)
        Telemetry.dot_end()
        if hp <= 0.0:
            return
        # Fire spreads when there is fuel: an oiled neighbour catches.
        _spread_cd -= delta
        if _spread_cd <= 0.0:
            _spread_cd = 0.5
            for e in get_tree().get_nodes_in_group("enemies"):
                if e != self and is_instance_valid(e) and not e.is_queued_for_deletion() \
                        and e.burn_time <= 0.0 and e.has_state(Element.Kind.OIL) \
                        and e.global_position.distance_to(global_position) <= 80.0:
                    e.apply_element(Element.Kind.FIRE, burn_dps, last_hit_by)
    if poison_time > 0.0:
        poison_time -= delta
        Telemetry.dot_begin(_dot_tags["poison"])
        take_damage(resisted(Element.Kind.POISON, poison_dps * float(poison_stacks) * delta), Element.COLORS[Element.Kind.POISON], false)
        Telemetry.dot_end()
        if hp <= 0.0:
            return
        if poison_time <= 0.0:
            poison_stacks = 0
            poison_dps = 0.0
    if bleed_time > 0.0:
        bleed_time -= delta
        if velocity.length() > 10.0:
            Telemetry.dot_begin(_dot_tags["bleed"])
            take_damage(resisted(Element.Kind.BLOOD, bleed_dps * delta), Element.COLORS[Element.Kind.BLOOD], false)
            Telemetry.dot_end()
            if hp <= 0.0:
                return
    frozen_time = maxf(0.0, frozen_time - delta)
    stun_time = maxf(0.0, stun_time - delta)
    _dr_left["freeze"] = maxf(0.0, _dr_left["freeze"] - delta)
    _dr_left["stun"] = maxf(0.0, _dr_left["stun"] - delta)
    _lunge_cd = maxf(0.0, _lunge_cd - delta)
    _lunge_t = maxf(0.0, _lunge_t - delta)
    corroded_time = maxf(0.0, corroded_time - delta)
    exposed_time = maxf(0.0, exposed_time - delta)
    slow_time = maxf(0.0, slow_time - delta)
    armour_time = maxf(0.0, armour_time - delta)
    haste_aura_time = maxf(0.0, haste_aura_time - delta)
    _react_window = maxf(0.0, _react_window - delta)
    _teleport_cd = maxf(0.0, _teleport_cd - delta)
    _pulse_fx = maxf(0.0, _pulse_fx - delta)
    _since_hit += delta
    _contact_cd = maxf(0.0, _contact_cd - delta)
    _flash = maxf(0.0, _flash - delta)
    _shield_flash = maxf(0.0, _shield_flash - delta)

    _floor_t -= delta
    if _floor_t <= 0.0:
        _floor_t = 0.25
        _feel_floor()
        if _dead or hp <= 0.0:
            return

    _tick_affix(delta)
    _tick_shells(delta)
    if kind_name == "bomber" or affix == "volatile":
        var pl := _nearest_player()
        var near := pl.global_position.distance_to(global_position) if pl != null else INF
        _ring_vis = _ring_vis + delta if near <= BOMB_RADIUS + 124.0 else 0.0
    if kind_name == "boss":
        _tick_boss_passive(delta)
        if _dead:
            return

    var prev_vel := velocity
    var target := _nearest_player()
    if frozen_time > 0.0 or stun_time > 0.0 or target == null or (body != null and body.staggered()):
        velocity = Vector2.ZERO
    else:
        velocity = _think(delta, target)
        if _dead:
            return
    if _on_ice and frozen_time <= 0.0:
        var keep := pow(Materials.ICE_KEEP, delta * 60.0)
        velocity = prev_vel * keep + velocity * (1.0 - keep)
    velocity += shove_vel
    shove_vel = shove_vel.move_toward(Vector2.ZERO, 900.0 * delta)
    move_and_slide()
    if kind_name == "charger" and _mode == MODE_DASH and not Main.old_balance:
        for i in get_slide_collision_count():
            if get_slide_collision(i).get_collider() is StaticBody2D:
                # Charged into a wall: stunned, the opening to hit it.
                stun_time = maxf(stun_time, CHARGE_STUN)
                _mode = MODE_COOL
                _mode_t = 0.4
                _squash = 1.0
                Sfx.play_at("hit_wall", global_position, -2.0)
                break

    if target != null and _contact_cd <= 0.0 and is_instance_valid(target) and _burrow_state != 2:
        var reach := contact_reach() + target.radius + 2.0
        if global_position.distance_squared_to(target.global_position) <= reach * reach:
            var hit := contact_damage
            if kind_name == "charger" and _mode == MODE_DASH and not Main.old_balance:
                hit = CHARGE_DMG * damage_mult
                Telemetry.hurt_hint = "charge:" + Telemetry.enemy_label(self)
            target.take_damage(hit, self)
            _contact_cd = 0.8
    _update_sprite()
    queue_redraw()


## Around the room's walls and chasms: when the straight line to the target is blocked,
## the direction down the room's flow field (see Room.nav_dir); ZERO to go straight.
func _nav_dir(delta: float, target: Player) -> Vector2:
    var rm := Room.here
    if rm == null or not is_instance_valid(rm) or not rm.has_blockers:
        return Vector2.ZERO
    _nav_t -= delta
    if _nav_t <= 0.0:
        _nav_t = 0.3
        _nav_blocked = not rm.line_clear(global_position, target.global_position, true)
    if not _nav_blocked:
        return Vector2.ZERO
    return rm.nav_dir(global_position)


func _speed_mult() -> float:
    var m := slow_factor if slow_time > 0.0 else 1.0
    if _wading:
        m *= Room.WADE
    if has_state(Element.Kind.STONE):
        m *= 0.75   # weighed down
    if affix == "hasted":
        m *= 1.35
    if haste_aura_time > 0.0:
        m *= 1.15
    if Main.curses.has("haste"):
        m *= 1.15   # Haste curse (Core loop reset 11.1)
    if boss_kind == "pyre_lord" and _phase >= 2:
        m *= 1.25
    if boss_kind == "storm_warden" and _phase >= 3:
        m *= 1.6
    return m


## Desired velocity for this frame, per kind. Also fires shots, pulses, fuses.
func _think(delta: float, target: Player) -> Vector2:
    var to_target := target.global_position - global_position
    var dist := to_target.length()
    var dir := to_target / dist if dist > 0.01 else Vector2.RIGHT
    var around := _nav_dir(delta, target)
    if around != Vector2.ZERO:
        dir = around
    var mult := _speed_mult()
    if kind_name == "boss":
        return _think_boss(delta, target, dir, dist, mult)
    match kind_name:
        "spitter":
            _shoot_t -= delta
            if _shoot_t <= 0.0 and dist < 560.0:
                _shoot_t = 1.6 if _wave < FAN_DIFF else 2.0
                var el: int = immune_to if immune_to != Element.Kind.NONE else Element.Kind.NONE
                _volley += 1
                if _wave >= _lob_diff() and _volley % 3 == 0:
                    _lob(target)
                elif _wave >= FAN_DIFF and not Main.old_balance:
                    # Half-way lead: a target running in a straight line or a circle gets
                    # caught; one that changes direction does not.
                    var ahead := target.global_position + target.velocity * (dist / 250.0) * LEAD
                    var aim := (ahead - global_position).normalized()
                    for a in [-FAN_SPREAD, 0.0, FAN_SPREAD]:
                        _shoot(aim.rotated(a), 250.0, _fan_damage(), el, 3.0, 6.0)
                else:
                    _shoot(dir, 250.0, _projectile_damage(6.0), el, 3.0, 6.0)
                _squash = 0.6
            return _keep_range(delta, dir, dist, 220.0, 300.0) * speed * mult
        "charger":
            if Main.old_balance:
                return _charge_ai(delta, dir, dist, mult, 0.6, 420.0, 0.5, 1.5, 260.0)
            return _charge_ai(delta, dir, dist, mult, 0.6, CHARGE_SPEED, CHARGE_LEN / CHARGE_SPEED, 1.5, 380.0)
        "lobber":
            _shoot_t -= delta
            if _shoot_t <= 0.0 and dist < 560.0:
                if rings_over(target.global_position) < MAX_RINGS:
                    _shoot_t = LOBBER_EVERY
                    _lob_at(target.global_position, LOBBER_WARN, LOBBER_R, LOBBER_DMG)
                    _squash = 0.7
                else:
                    _shoot_t = 0.3   # a third ring waits
            return _keep_range(delta, dir, dist, 260.0, 380.0) * speed * mult
        "shaman":
            _pulse_t -= delta
            if _pulse_t <= 0.0:
                _pulse_t = 3.0
                _shaman_pulse()
            return _keep_range(delta, dir, dist, 260.0, 340.0) * speed * mult
        "bomber":
            if _fuse >= 0.0:
                _fuse -= delta
                if _fuse <= 0.0:
                    _detonate()
                    return Vector2.ZERO
                return dir * speed * 0.3 * mult
            if dist <= BOMB_TRIGGER + target.radius:
                _fuse = 0.3 if Main.old_balance else BOMB_FUSE
                Sfx.play("tick")
            return dir * speed * mult
        "wisp":
            _wisp_phase += delta * 5.0
            var wobble := sin(_wisp_phase) * 1.1 + sin(_wisp_phase * 0.37) * 0.5
            return dir.rotated(wobble) * speed * mult
    if kind_name == "runner" and not Main.old_balance:
        # Crouch, then lunge 120 px: melee no longer only walks down the gun line.
        if _crouch_t > 0.0:
            _crouch_t -= delta
            if _crouch_t <= 0.0:
                _lunge_t = RUNNER_LUNGE / RUNNER_LUNGE_SPEED
                _lunge_cd = 2.2
                _dash_dir = dir
            return Vector2.ZERO
        if _lunge_t > 0.0:
            return _dash_dir * RUNNER_LUNGE_SPEED
        if _lunge_cd <= 0.0 and dist < 160.0 and dist > radius + target.radius + 12.0:
            _crouch_t = RUNNER_CROUCH
            _squash = 0.8
            return Vector2.ZERO
    if kind_name == "runner" and _wave >= FLANK_DIFF and dist > 90.0 and not Main.old_balance:
        # Flankers: swing up to about 60 degrees off the line, less as they close in.
        var swing := clampf((dist - 90.0) / 260.0, 0.0, 1.0) * 1.05 * _strafe_sign
        return dir.rotated(swing) * speed * mult
    if kind_name in ["grunt", "swarmer", "splitter"]:
        # Lunge: close the last stretch in a burst, so a wall of bullets has to stop
        # them rather than merely slow them.
        if _crouch_t > 0.0:
            # A short tinted crouch first (Core loop reset 8: every hit a player can read).
            _crouch_t -= delta
            if _crouch_t <= 0.0:
                _lunge_t = 0.32
            return Vector2.ZERO
        if _lunge_t <= 0.0 and _lunge_cd <= 0.0 and dist < 150.0 and dist > radius + target.radius + 6.0:
            _lunge_cd = 1.6
            _squash = 0.8
            if Main.old_balance:
                _lunge_t = 0.32
            else:
                _crouch_t = MELEE_CROUCH
                return Vector2.ZERO
        if _lunge_t > 0.0:
            return dir * minf(speed * 2.6, 300.0) * maxf(mult, 0.7)
    return dir * speed * mult


## Approach when far, back off when near, strafe in between. Returns a direction (0..1 length).
func _keep_range(delta: float, dir: Vector2, dist: float, near: float, far: float) -> Vector2:
    _strafe_t -= delta
    if _strafe_t <= 0.0:
        _strafe_t = randf_range(1.5, 3.0)
        _strafe_sign = -_strafe_sign
    if dist > far:
        return dir
    if dist < near:
        return -dir
    return dir.orthogonal() * _strafe_sign * 0.5


## Chase, telegraph (stand still, aim), dash, cool down. Shared by charger and brute king.
func _charge_ai(delta: float, dir: Vector2, dist: float, mult: float, warn: float, dash_speed: float, dash_time: float, cool: float, trigger: float) -> Vector2:
    _mode_t -= delta
    match _mode:
        MODE_TELEGRAPH:
            if _mode_t <= 0.0:
                _mode = MODE_DASH
                _mode_t = dash_time
                Sfx.play("hit")
            return Vector2.ZERO
        MODE_DASH:
            if _mode_t <= 0.0:
                _mode = MODE_COOL
                _mode_t = cool
            return _dash_dir * dash_speed
        MODE_COOL:
            if _mode_t <= 0.0:
                _mode = MODE_CHASE
            return dir * speed * 0.4 * mult
    if dist <= trigger:
        _mode = MODE_TELEGRAPH
        _mode_t = warn
        _dash_dir = dir
        return Vector2.ZERO
    return dir * speed * mult


func _shaman_pulse() -> void:
    _pulse_fx = 0.6
    Elements.nova.emit(global_position, 160.0, Color(0.5, 1.0, 0.5, 0.5))
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.is_queued_for_deletion() or e.kind_name == "boss":
            continue
        if e.global_position.distance_to(global_position) <= 160.0:
            e.heal(e.max_hp * 0.10)
            e.armour_time = maxf(e.armour_time, 2.0)


## A lobbed shell: lands where the target is heading, after SHELL_WARN s of warning.
func _lob(target: Player) -> void:
    var at := target.global_position + target.velocity * 0.25
    var rr := _room_rect()
    if rr.has_area():
        at = Vector2(clampf(at.x, rr.position.x + 20.0, rr.end.x - 20.0), clampf(at.y, rr.position.y + 20.0, rr.end.y - 20.0))
    _shells.append({ "at": at, "t": SHELL_WARN, "warn": SHELL_WARN, "r": SHELL_R, "dmg": _projectile_damage(6.0) * SHELL_DMG })
    Sfx.play("tick")


## A shell at `at` (global, kept inside the room): a ring for `warn` s, then a burst of
## radius `r` dealing `dmg` (times the floor's damage multiplier).
func _lob_at(at: Vector2, warn: float, r: float, dmg: float) -> void:
    var rr := _room_rect()
    if rr.has_area():
        at = Vector2(clampf(at.x, rr.position.x + 20.0, rr.end.x - 20.0), clampf(at.y, rr.position.y + 20.0, rr.end.y - 20.0))
    _shells.append({ "at": at, "t": warn, "warn": warn, "r": r, "dmg": dmg })
    Sfx.play("tick")


## Hostile rings (shells in flight, Sower circles) whose area covers `pos` (global).
func rings_over(pos: Vector2) -> int:
    var n := 0
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or not (e is Enemy):
            continue
        for sh in e._shells:
            if Vector2(sh["at"]).distance_to(pos) <= float(sh["r"]) + 16.0:
                n += 1
        for z in e._zones:
            if Vector2(z["at"]).distance_to(pos) <= SOW_R + 16.0:
                n += 1
    return n


func _lob_diff() -> int:
    return LOB_DIFF if Main.old_balance else 8   # section 8: the spitter's lob from difficulty 8


## A spitter's fan shot: 8 of a 100 HP bar from floor 3 (section 8), else the old scaling.
func _fan_damage() -> float:
    var d := _projectile_damage(6.0) * FAN_DMG
    if _wave >= 10 and not Main.old_balance:
        d = maxf(d, SPIT_DMG_DEEP)
    return d


## Reactions on this enemy inside a second of each other: x1, x0.75, x0.56 ... never under
## x0.4 (Core loop reset 9). Elements.try_react multiplies the reaction's potency by it.
func react_decay() -> float:
    var now := _game_now()
    if now - _react_last > 1.0:
        _react_n = 0
    _react_last = now
    var m := maxf(0.4, pow(0.75, float(_react_n)))
    _react_n += 1
    return m


func _tick_shells(delta: float) -> void:
    if _shells.is_empty():
        return
    for i in range(_shells.size() - 1, -1, -1):
        var sh: Dictionary = _shells[i]
        sh["t"] = float(sh["t"]) - delta
        if float(sh["t"]) > 0.0:
            continue
        _shells.remove_at(i)
        var at: Vector2 = sh["at"]
        var r := float(sh["r"])
        var col := Color(0.55, 0.85, 0.35) if kind_name == "spitter" else Color(0.95, 0.65, 0.3)
        Elements.nova.emit(at, r, Color(col, 0.6))
        var fx := _fx()
        if fx != null:
            fx.blast(at, r, col)
        for p in get_tree().get_nodes_in_group("players"):
            if is_instance_valid(p) and p.alive and p.global_position.distance_to(at) <= r + p.radius:
                Telemetry.hurt_hint = "shell:" + Telemetry.enemy_label(self)
                p.take_damage(float(sh["dmg"]) * damage_mult, self, at)
    queue_redraw()


func _barrage() -> void:
    var off := randf() * TAU
    for i in BARRAGE_SHOTS:
        _shoot(Vector2.RIGHT.rotated(off + TAU * float(i) / float(BARRAGE_SHOTS)), BARRAGE_SPEED, _projectile_damage(5.0), Element.Kind.NONE, 3.2, 7.0)
    _squash = 0.8


func _tick_affix(delta: float) -> void:
    _tick_zones(delta)
    match affix:
        "sower":
            _sow_t -= delta
            if _sow_t <= 0.0:
                _sow_t = SOW_EVERY
                var off := randf() * TAU
                for i in SOW_N:
                    var at := global_position + Vector2.from_angle(off + TAU * float(i) / float(SOW_N)) * randf_range(80.0, 150.0)
                    var rr := _room_rect()
                    if rr.has_area():
                        at = Vector2(clampf(at.x, rr.position.x + 30.0, rr.end.x - 30.0), clampf(at.y, rr.position.y + 30.0, rr.end.y - 30.0))
                    if rings_over(at) >= MAX_RINGS:
                        continue
                    _zones.append({ "at": at, "age": 0.0, "tick": 0.0 })
                _squash = 0.7
        "mortar":
            _mortar_t -= delta
            var pl := _nearest_player()
            if _mortar_t <= 0.0 and pl != null and pl.global_position.distance_to(global_position) < 620.0:
                _mortar_t = MORTAR_EVERY
                var at := pl.global_position
                var side := Vector2.from_angle(randf() * TAU)
                for o in [Vector2.ZERO, side * 105.0, -side * 105.0]:
                    if rings_over(at + o) < MAX_RINGS:
                        _lob_at(at + o, LOBBER_WARN, LOBBER_R, LOBBER_DMG)
                _squash = 0.8
        "tether":
            _tick_tether(delta)
        "barrage":
            _barrage_t -= delta
            if _barrage_t <= 0.0:
                _barrage_t = BARRAGE_EVERY
                _barrage()
            if _barrage_t <= BARRAGE_WARN:
                queue_redraw()
        "regenerating":
            if _since_hit >= 2.0 and hp < max_hp:
                heal(max_hp * 0.02 * delta)
        "hasted":
            for e in get_tree().get_nodes_in_group("enemies"):
                if e != self and is_instance_valid(e) and e.global_position.distance_to(global_position) <= 150.0:
                    e.haste_aura_time = 0.25
        "trail":
            _trail_t -= delta
            if _trail_t <= 0.0:
                _trail_t = 0.8
                var el: int = immune_to if immune_to != Element.Kind.NONE else Element.Kind.OIL
                var w := _world()
                if w != null:
                    Cloud.spawn(w, global_position, el, 60.0, 4.0, 4.0, null)


## Sower circles: fill for SOW_WARN s (no harm), then hurt every 0.5 s for SOW_LIFE s.
func _tick_zones(delta: float) -> void:
    if _zones.is_empty():
        return
    for i in range(_zones.size() - 1, -1, -1):
        var z: Dictionary = _zones[i]
        z["age"] = float(z["age"]) + delta
        if float(z["age"]) > SOW_WARN + SOW_LIFE:
            _zones.remove_at(i)
            continue
        if float(z["age"]) < SOW_WARN:
            continue
        z["tick"] = float(z["tick"]) - delta
        if float(z["tick"]) > 0.0:
            continue
        z["tick"] = 0.5
        for p in get_tree().get_nodes_in_group("players"):
            if is_instance_valid(p) and p.alive and p.global_position.distance_to(Vector2(z["at"])) <= SOW_R + p.radius * 0.5:
                Telemetry.hurt_hint = "sower:" + Telemetry.enemy_label(self)
                p.take_damage(SOW_DMG * damage_mult, self, Vector2(z["at"]))
    queue_redraw()


## The Tether: stay within TETHER_R for TETHER_ARM s and a beam grows from it for
## TETHER_GROW s, then drains TETHER_DPS of a 100 HP bar a second until you break range
## (TETHER_BREAK) or sight.
func _tick_tether(delta: float) -> void:
    var pl := _nearest_player()
    var rm := Room.here
    var seen := pl != null and (rm == null or not is_instance_valid(rm) or rm.line_clear(global_position, pl.global_position))
    var d := pl.global_position.distance_to(global_position) if pl != null else INF
    match _tether_state:
        0:
            _tether_t = _tether_t + delta if (seen and d <= TETHER_R) else maxf(0.0, _tether_t - delta)
            if _tether_t >= TETHER_ARM:
                _tether_state = 1
                _tether_k = 0.0
                _tether_to = pl
                Sfx.play("tick")
        1, 2:
            var lost := _tether_to == null or not is_instance_valid(_tether_to) or not _tether_to.alive
            if not lost:
                lost = _tether_to.global_position.distance_to(global_position) > TETHER_BREAK
            if not lost and rm != null and is_instance_valid(rm):
                lost = not rm.line_clear(global_position, _tether_to.global_position)
            if lost:
                _tether_state = 0
                _tether_t = 0.0
                _tether_to = null
            elif _tether_state == 1:
                _tether_k += delta / TETHER_GROW
                if _tether_k >= 1.0:
                    _tether_state = 2
                    _tether_tick = 0.0
            else:
                _tether_tick -= delta
                if _tether_tick <= 0.0:
                    _tether_tick = 0.5
                    Telemetry.hurt_hint = "tether:" + Telemetry.enemy_label(self)
                    _tether_to.take_damage(TETHER_DPS * 0.5 * damage_mult, self)
    queue_redraw()


# --- Bosses ----------------------------------------------------------------


## Phase change, scripted summons and hazards; runs even while the boss is frozen.
func _tick_boss_passive(delta: float) -> void:
    var next_phase := body.phase_for(hp / max_hp) if body != null else (2 if hp <= max_hp * 0.5 else 1)
    if next_phase > _phase:
        _phase = next_phase
        if _phase == 2:
            Telemetry.boss_phase2(self)
        Elements.reaction_fired.emit("ENRAGED" if _phase == 2 else "PHASE %d" % _phase, global_position, Color(1.0, 0.3, 0.2))
        Sfx.play("boss_phase")
        var fx := _fx()
        if fx != null:
            fx._shake(8.0)
        if body != null:
            body.on_phase(_phase)
    if _ward_t > 0.0:
        _ward_t -= delta
        _ward_adds = _ward_adds.filter(func(e): return is_instance_valid(e) and not e.is_queued_for_deletion() and e.hp > 0.0)
        if _ward_adds.is_empty() and _ward_t < rally_secs - 1.5:
            _ward_t = 0.0
        if _ward_t <= 0.0:
            _ward_t = 0.0
            Elements.reaction_fired.emit("Guard broken!", global_position, Color.WHITE)
        queue_redraw()
    # Telegraphed summons land when their timer runs out; a player on a marker moves it.
    for i in range(_pending.size() - 1, -1, -1):
        var s: Dictionary = _pending[i]
        if _party_near(s["pos"], SPAWN_SHOVE):
            var was: Vector2 = s["pos"]
            s["pos"] = _summon_spot()
            s["t"] = float(s.get("warn", EMERGE_SECS))
            _moved(was, s["pos"])
        s["t"] = float(s["t"]) - delta
        if float(s["t"]) <= 0.0:
            _pending.remove_at(i)
            var spawned := _summon(String(s["type"]), s["pos"])
            if spawned != null:
                _landed(s["pos"])
                Elements.nova.emit(s["pos"], 30.0, Color(base_color, 0.6))
    match boss_kind:
        "brute_king":
            for i in range(_barrels.size() - 1, -1, -1):
                var b: Dictionary = _barrels[i]
                b["t"] = float(b["t"]) + delta
                if float(b["t"]) >= float(b["dur"]):
                    _barrels.remove_at(i)
                    _land_barrel(b["to"])
            if not _summoned_60 and hp <= max_hp * 0.6:
                _summoned_60 = true
                _queue_summons("grunt", 3, 0.8)
            if not _summoned_30 and hp <= max_hp * 0.3:
                _summoned_30 = true
                _queue_summons("grunt", 3, 0.8)
        "storm_warden":
            _tick_strikes(delta)
        "void_herald":
            _tick_herald(delta)
        "drowned_choir":
            _tick_choir(delta)
        "pyre_lord":
            _hazard_tick -= delta
            for i in range(_hazards.size() - 1, -1, -1):
                var hz: Dictionary = _hazards[i]
                hz["t"] = float(hz["t"]) - delta
                if float(hz["t"]) <= 0.0:
                    _hazards.remove_at(i)
            if _hazard_tick <= 0.0:
                _hazard_tick = 0.5
                for p in get_tree().get_nodes_in_group("players"):
                    if not is_instance_valid(p) or not p.alive:
                        continue
                    for hz in _hazards:
                        if float(hz.get("warn", 0.0)) <= 0.0 and p.global_position.distance_to(hz["pos"]) <= float(hz.get("r", 55.0)):
                            p.take_damage(5.0 + 0.25 * float(_wave), self)
                            break
            for hz in _hazards:
                hz["warn"] = maxf(0.0, float(hz.get("warn", 0.0)) - delta)
            for i in range(_quenched.size() - 1, -1, -1):
                _quenched[i]["t"] = float(_quenched[i]["t"]) - delta
                if float(_quenched[i]["t"]) <= 0.0:
                    _quenched.remove_at(i)
            _tick_flame_waves(delta)


## The adds that hold a rally guard up: once they are all dead the guard breaks.
func set_ward_adds(adds: Array) -> void:
    _ward_adds = adds.duplicate()


func _queue_summons(type: String, count: int, warn: float) -> void:
    warn = maxf(warn, EMERGE_SECS)
    for i in count:
        var a := TAU * float(i) / float(count) + randf() * 0.5
        var pos := global_position + Vector2.RIGHT.rotated(a) * (radius + 60.0)
        if _party_near(pos, SPAWN_SHOVE * 2.0):
            pos = _summon_spot()
        _pending.append({ "pos": pos, "t": warn, "warn": warn, "type": type })


## True when a living player stands within `d` of `gpos`.
func _party_near(gpos: Vector2, d: float) -> bool:
    for p in get_tree().get_nodes_in_group("players"):
        if is_instance_valid(p) and p.alive and p.global_position.distance_to(gpos) < d:
            return true
    return false


## A summon marker's spot: around this body, clear of every player, inside the room; else
## the room's own spawn point.
func _summon_spot() -> Vector2:
    var rr := _room_rect()
    var a0 := randf() * TAU
    for k in 10:
        var pos := global_position + Vector2.RIGHT.rotated(a0 + TAU * float(k) / 10.0) * (radius + 60.0 + 30.0 * float(k % 3))
        if rr.has_area() and not rr.grow(-40.0).has_point(pos):
            continue
        if not _party_near(pos, SPAWN_SHOVE * 2.0):
            return pos
    var w := _world()
    if w != null and w.has_method("respawn_point"):
        return w.respawn_point()
    return global_position


## While emerging: a player who walks onto the marker moves it, and the telegraph restarts.
func _guard_spawn() -> void:
    if not _party_near(global_position, SPAWN_SHOVE):
        return
    var w := _world()
    if w == null or not w.has_method("respawn_point"):
        return
    var was := global_position
    global_position = w.respawn_point()
    emerge = EMERGE_SECS
    _moved(was, global_position)


func _moved(from: Vector2, to: Vector2) -> void:
    spawn_moved += 1
    if spawn_log:
        print("[SPAWN-MOVED] %s (%.0f, %.0f) -> (%.0f, %.0f)" % [kind_name, from.x, from.y, to.x, to.y])


## A body arrived: the bot's check that nothing lands on a player.
func _landed(at: Vector2) -> void:
    spawn_landed += 1
    if _party_near(at, SPAWN_ASSERT):
        spawn_close += 1
        if spawn_log:
            print("[SPAWN-CLOSE] %s landed within %.0f px of a player at (%.0f, %.0f)" % [kind_name, SPAWN_ASSERT, at.x, at.y])


## The spawn marker (emerging bodies and boss summons): a dark disc on the floor with a red
## rim and red pixels closing in. k: 0 just placed .. 1 arriving.
static func draw_spawn_marker(cv: CanvasItem, at: Vector2, size: float, k: float, t: float) -> void:
    var r := size * (2.2 - 1.2 * k)
    cv.draw_circle(at, size * 1.25, Color(0.05, 0.0, 0.0, 0.35 + 0.2 * k))
    cv.draw_arc(at, size * 1.25, 0.0, TAU, 24, Color(0, 0, 0, 0.8), 4.0)
    cv.draw_arc(at, size * 1.25, 0.0, TAU, 24, Color(1.0, 0.22, 0.18, 0.75 + 0.25 * k), 2.0)
    for i in 10:
        var a := TAU * float(i) / 10.0 + t * 3.0
        cv.draw_rect(Rect2(at + Vector2.RIGHT.rotated(a) * r - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.25, 0.2, 0.6 + 0.4 * k))


# --- The Pyre Lord (design section 6: molten core, slag armour, fire crown) -----------------

## Flame waves: arcs of fire that roll out from where he stood, never full rings, so a
## sidestep always dodges them. Each one winds up for WAVE_WARN with its arc shown.
const WAVE_SPEED := 230.0
const WAVE_REACH := 360.0
const WAVE_BAND := 16.0
const WAVE_WARN := 0.9
var _waves: Array = []      # [{ "o": origin, "a": angle, "hw": half width, "r", "warn", "speed", "hit": {} }]
var _quenched: Array = []   # [{ "pos", "r", "t" }] ground a quench vat soaked: no fire or lava lands there
const QUENCH_SAFE := 8.0
var _lava_t := 2.0


func _think_pyre(delta: float, target: Player, dir: Vector2, mult: float) -> Vector2:
    _t1 -= delta
    _t2 -= delta
    _t3 -= delta
    if _t1 <= 0.0:
        # A trail of burning ground behind him.
        _t1 = [1.2, 0.9, 0.7][clampi(_phase - 1, 0, 2)]
        var w := _world()
        if w != null and not _is_quenched(global_position):
            Cloud.spawn(w, global_position, Element.Kind.FIRE, 60.0, 5.0, 5.0, null)
        _add_hazard({ "pos": global_position, "t": 5.0, "r": 55.0 })
    if _t2 <= 0.0:
        _t2 = 8.0
        _queue_summons("bomber", 2 if _phase == 1 else 3, 0.9)
    if _t3 <= 0.0:
        var aim := (target.global_position - global_position).angle()
        match _phase:
            1:
                _t3 = 4.0
                _add_wave(aim, 0.8, WAVE_SPEED)
            2:
                _t3 = 2.8
                _add_wave(aim, 0.9, WAVE_SPEED * 1.2)
            _:
                _t3 = 3.2
                for k in 3:
                    _add_wave(aim + TAU * float(k) / 3.0, 0.7, WAVE_SPEED * 1.1)
    if _phase >= 3:
        # The forge floods: lava wells up near the player, shown a second before it burns.
        _lava_t -= delta
        if _lava_t <= 0.0:
            _lava_t = 2.2
            var at := target.global_position + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 90.0)
            _add_hazard({ "pos": at, "t": 7.0, "r": 60.0, "warn": 1.0, "lava": true })
    while _hazards.size() > 16:
        _hazards.pop_front()
    for wv in _waves:
        if float(wv["warn"]) > 0.0:
            return Vector2.ZERO   # he plants his feet for the wind-up
    return dir * speed * mult


func _add_hazard(hz: Dictionary) -> void:
    if not _is_quenched(hz["pos"]):
        _hazards.append(hz)


func _is_quenched(at: Vector2) -> bool:
    for q in _quenched:
        if at.distance_to(q["pos"]) <= float(q["r"]):
            return true
    return false


## A quench vat burst at `at`: his fire and lava within `r` go out, and the ground stays
## safe for QUENCH_SAFE s (in phase 3, the only safe paths through the flood).
func quench(at: Vector2, r: float) -> void:
    if boss_kind != "pyre_lord":
        return
    _hazards = _hazards.filter(func(hz): return Vector2(hz["pos"]).distance_to(at) > r + float(hz.get("r", 55.0)) * 0.5)
    for q in _quenched:
        if Vector2(q["pos"]).distance_to(at) < 10.0:
            q["t"] = QUENCH_SAFE
            return
    _quenched.append({ "pos": at, "r": r, "t": QUENCH_SAFE })


func _add_wave(angle: float, half_width: float, wave_speed: float) -> void:
    _waves.append({ "o": global_position, "a": angle, "hw": half_width, "r": radius, "warn": WAVE_WARN, "speed": wave_speed, "hit": {} })


func _tick_flame_waves(delta: float) -> void:
    for i in range(_waves.size() - 1, -1, -1):
        var wv: Dictionary = _waves[i]
        if float(wv["warn"]) > 0.0:
            # A stagger or a freeze holds the wave in his hands; it never fires unseen.
            if not (body != null and body.staggered()) and frozen_time <= 0.0 and stun_time <= 0.0:
                wv["warn"] = float(wv["warn"]) - delta
            continue
        wv["r"] = float(wv["r"]) + float(wv["speed"]) * delta
        if float(wv["r"]) > WAVE_REACH:
            _waves.remove_at(i)
            continue
        for p in get_tree().get_nodes_in_group("players"):
            if not is_instance_valid(p) or not p.alive or wv["hit"].has(p):
                continue
            var to: Vector2 = p.global_position - Vector2(wv["o"])
            if absf(to.length() - float(wv["r"])) <= WAVE_BAND * 0.5 + 8.0 \
                    and absf(angle_difference(float(wv["a"]), to.angle())) <= float(wv["hw"]):
                wv["hit"][p] = true
                p.take_damage(12.0 + 0.6 * float(_wave), self)


## Waves, their wind-ups and the burning and flooding ground, in the hostile signature.
func _draw_pyre_hostile(cv: CanvasItem) -> void:
    var near: Array = []
    for p in get_tree().get_nodes_in_group("players"):
        if p is Node2D:
            near.append((p as Node2D).global_position)
    for hz in _hazards:
        # Like burning floor, a patch is outlined only where a player could step into it.
        var close := false
        for pp in near:
            if Vector2(pp).distance_to(hz["pos"]) <= 300.0:
                close = true
                break
        if not close:
            continue
        var lp := to_local(hz["pos"])
        var warn := float(hz.get("warn", 0.0))
        if warn > 0.0:
            Hostile.dash_ring(cv, lp, float(hz["r"]) * (1.0 - 0.3 * warn), 0.6 + 0.4 * absf(sin(_fx_t * 12.0)), 3.0)
        else:
            Hostile.dash_ring(cv, lp, float(hz["r"]), 0.7 * clampf(float(hz["t"]), 0.0, 1.0))
    for wv in _waves:
        var o := to_local(wv["o"])
        var a := float(wv["a"])
        var hw := float(wv["hw"])
        if float(wv["warn"]) > 0.0:
            var k := 0.5 + 0.5 * absf(sin(_fx_t * 14.0))
            _hostile_arc(cv, o, radius + 22.0, a, hw, 6.0, k)
            _hostile_arc(cv, o, WAVE_REACH, a, hw, 3.0, 0.35 * k)
            cv.draw_line(o + Vector2.from_angle(a - hw) * (radius + 22.0), o + Vector2.from_angle(a - hw) * WAVE_REACH, Color(Hostile.RED, 0.3 * k), 1.0)
            cv.draw_line(o + Vector2.from_angle(a + hw) * (radius + 22.0), o + Vector2.from_angle(a + hw) * WAVE_REACH, Color(Hostile.RED, 0.3 * k), 1.0)
        else:
            _hostile_arc(cv, o, float(wv["r"]), a, hw, WAVE_BAND, 1.0)


func _hostile_arc(cv: CanvasItem, at: Vector2, r: float, a: float, hw: float, width: float, alpha: float) -> void:
    var n := 18
    var pts := PackedVector2Array()
    for k in n + 1:
        pts.append(at + Vector2.from_angle(a - hw + 2.0 * hw * float(k) / float(n)) * r)
    cv.draw_polyline(pts, Color(Hostile.DARK, 0.85 * alpha), width + 4.0)
    cv.draw_polyline(pts, Color(Hostile.RED, alpha), maxf(2.0, width * 0.5))
    cv.draw_polyline(pts, Color(1.0, 0.75, 0.35, alpha), 1.0)


## The body parts, their element states and compounds, on the Crisp layer with the hostile
## tells: a boss is hostile, and its parts must read through the player's own fusion effects.
func _draw_parts(cv: CanvasItem) -> void:
    if body == null or hp <= 0.0 or (emerge > 0.0 and not (intro and _intro_len - emerge >= BossShow.REVEAL)):
        return
    var R := radius
    for i in body.parts.size():
        var p: Dictionary = body.parts[i]
        var at: Vector2 = Vector2(p["offset"]) * R
        var pr: float = float(p["r"]) * R
        var flash := float(p["flash"]) / 0.35
        var vis := body.visible(i)
        match String(p["id"]):
            "armour":
                if p["broken"]:
                    continue
                # Slag plates round the body; one falls away per sixth of wear, the gaps glow.
                var plates := ceili(float(p["integrity"]) * 6.0)
                for k in 6:
                    var a0 := -PI * 0.5 + float(k) * TAU / 6.0 + 0.08
                    var a1 := a0 + TAU / 6.0 - 0.16
                    if k < plates:
                        cv.draw_arc(at, pr, a0, a1, 8, Hostile.DARK, 10.0)
                        cv.draw_arc(at, pr, a0, a1, 8, Color(0.34, 0.24, 0.20).lerp(Color.WHITE, flash * 0.6), 6.0)
                        cv.draw_arc(at, pr + 3.0, a0, a1, 8, Color(Hostile.RED, 0.9), 1.0)
                    else:
                        cv.draw_arc(at, pr, a0, a1, 8, Color(1.0, 0.55, 0.15, 0.55 + 0.3 * sin(_fx_t * 8.0)), 3.0)
                    cv.draw_arc(at, pr, a1, a1 + 0.16, 3, Color(1.0, 0.45, 0.1, 0.9), 4.0)
            "plates":
                if p["broken"]:
                    continue
                # Bone plates round the body; one cracks off per sixth of wear.
                var bones := ceili(float(p["integrity"]) * 6.0)
                for k in bones:
                    var a0 := -PI * 0.5 + float(k) * TAU / 6.0 + 0.1
                    var a1 := a0 + TAU / 6.0 - 0.2
                    cv.draw_arc(at, pr, a0, a1, 8, Hostile.DARK, 11.0)
                    cv.draw_arc(at, pr, a0, a1, 8, Color(0.86, 0.82, 0.70).lerp(Color.WHITE, flash * 0.6), 6.0)
                    cv.draw_arc(at, pr + 3.5, a0, a1, 8, Color(Hostile.RED, 0.9), 1.0)
            "hide", "hive", "bell":
                pass   # the sprite is the body (the Choir's bell is drawn in _draw_boss)
            "singers":
                if p["broken"]:
                    continue
                # Drowned singers fused round the bell: one drops away per fifth of wear.
                var heads := ceili(float(p["integrity"]) * 5.0)
                var wet := _part_has(i, Element.Kind.WET)
                for k in heads:
                    var a := PI * 0.15 + float(k) * PI * 0.175 + 0.05 * sin(_fx_t * 2.0 + float(k))
                    var hp0 := at + Vector2(cos(a), sin(a) * 0.6) * pr
                    var mouth := 0.5 + 0.5 * absf(sin(_fx_t * 3.0 + float(k)))
                    cv.draw_circle(hp0, 9.0, Hostile.DARK)
                    cv.draw_arc(hp0, 9.0, 0.0, TAU, 14, Color(Hostile.RED, 0.9), 1.0)
                    var skin := Color(0.50, 0.66, 0.70) if wet else Color(0.62, 0.62, 0.58)
                    cv.draw_circle(hp0, 7.0, skin.lerp(Color.WHITE, flash * 0.6))
                    cv.draw_circle(hp0 + Vector2(0, 2.0), 2.0 + mouth, Hostile.DARK)
            "rods":
                if p["broken"]:
                    continue
                # Two lightning rods over his shoulders; they lean as the grounding wears them.
                var lean := (1.0 - float(p["integrity"])) * 0.5
                var charged := _part_has(i, Element.Kind.SHOCK)
                for sd in [-1.0, 1.0]:
                    var foot := at + Vector2(sd * pr * 0.55, pr * 0.35)
                    var tip := foot + Vector2(sd * pr * 0.25, -pr * 1.35).rotated(sd * lean)
                    cv.draw_line(foot, tip, Hostile.DARK, 10.0)
                    cv.draw_line(foot, tip, Color(Hostile.RED, 0.9), 7.0)
                    cv.draw_line(foot, tip, Color(0.55, 0.58, 0.66).lerp(Color.WHITE, flash * 0.6), 5.0)
                    var glow := Color(1.0, 0.95, 0.4) if charged else Color(0.45, 0.45, 0.5)
                    var tr := 6.0 + (1.5 * sin(_fx_t * 14.0 + sd) if charged else 0.0)
                    cv.draw_circle(tip, tr + 2.5, Hostile.DARK)
                    cv.draw_circle(tip, tr, glow.lerp(Color.WHITE, flash * 0.6))
                    cv.draw_arc(tip, tr + 2.5, 0.0, TAU, 14, Color(Hostile.RED, 0.9), 1.0)
            "shards":
                if p["broken"]:
                    continue
                # Void shards orbiting the hollow; one drops away per fifth of wear.
                var n_sh := ceili(float(p["integrity"]) * 5.0)
                var orbit := pr * (0.8 if _phase >= 3 else 1.0)
                for k in n_sh:
                    var ang := _fx_t * 1.4 + TAU * float(k) / 5.0
                    var c := at + Vector2.from_angle(ang) * orbit
                    _draw_shard(cv, c, ang, 9.0, flash)
            "hollow":
                if not vis:
                    continue
                var hr := pr * (1.0 + 0.1 * sin(_fx_t * 6.0))
                cv.draw_circle(at, hr + 3.0, Hostile.DARK)
                cv.draw_arc(at, hr + 3.0, 0.0, TAU, 24, Hostile.RED, 1.5)
                cv.draw_circle(at, hr, Color(0.55, 0.3, 0.85).lerp(Color.WHITE, flash))
                cv.draw_circle(at, hr * 0.6, Color(0.04, 0.0, 0.08))
            "storm_core":
                if not vis:
                    continue
                var steamed := (String(p["compound"]) if i != body.cur else compound) == "STEAM"
                var cr := pr * (1.0 + 0.08 * sin(_fx_t * 9.0))
                cv.draw_circle(at, cr + 3.0, Hostile.DARK)
                cv.draw_arc(at, cr + 3.0, 0.0, TAU, 24, Hostile.RED, 1.5)
                cv.draw_circle(at, cr, Color(0.55, 0.7, 1.0).lerp(Color.WHITE, flash))
                cv.draw_circle(at, cr * 0.45, Color(1.0, 1.0, 0.7, 0.9))
                if steamed:
                    cv.draw_circle(at, cr * 1.35, Color(0.9, 0.9, 0.95, 0.35))
            "sacs":
                if p["broken"]:
                    continue
                # Swollen sacs on her back; one bursts per third of wear.
                var n_sacs := ceili(float(p["integrity"]) * 3.0)
                for k in n_sacs:
                    var c := at + Vector2((float(k) - 1.0) * pr * 0.75, absf(float(k) - 1.0) * pr * 0.25)
                    var sr := pr * (0.5 if k == 1 else 0.42) * (1.0 + 0.06 * sin(_fx_t * 5.0 + float(k)))
                    cv.draw_circle(c, sr + 2.5, Hostile.DARK)
                    cv.draw_circle(c, sr, Color(0.55, 0.72, 0.25).lerp(Color.WHITE, flash * 0.6))
                    cv.draw_circle(c + Vector2(-sr * 0.3, -sr * 0.3), sr * 0.35, Color(0.8, 0.95, 0.5, 0.8))
                    cv.draw_arc(c, sr + 2.5, 0.0, TAU, 18, Color(Hostile.RED, 0.9), 1.0)
            "brood":
                if not vis:
                    continue
                cv.draw_circle(at, pr + 3.0, Hostile.DARK)
                cv.draw_arc(at, pr + 3.0, 0.0, TAU, 24, Hostile.RED, 1.5)
                cv.draw_circle(at, pr, Color(0.95, 0.85, 0.45).lerp(Color.WHITE, flash))
                cv.draw_circle(at, pr * 0.5, Color(1.0, 1.0, 0.75, 0.9))
            "core":
                if not vis:
                    continue
                var pulse := 0.5 + 0.5 * sin(_fx_t * 6.0)
                cv.draw_circle(at, pr + 4.0, Hostile.DARK)
                cv.draw_arc(at, pr + 4.0, 0.0, TAU, 28, Hostile.RED, 1.5)
                cv.draw_circle(at, pr, Color(1.0, 0.45 + 0.2 * pulse, 0.1).lerp(Color.WHITE, flash))
                cv.draw_circle(at, pr * 0.55, Color(1.0, 0.9, 0.5, 0.9))
            "crown":
                var bone := boss_kind == "brute_king"
                if bone and not vis:
                    # A bone helm until phase 3 bares the crown.
                    cv.draw_circle(at, pr * 0.9 + 2.0, Hostile.DARK)
                    cv.draw_circle(at, pr * 0.9, Color(0.62, 0.58, 0.50))
                    cv.draw_arc(at, pr * 0.9 + 2.0, 0.0, TAU, 20, Color(Hostile.RED, 0.9), 1.0)
                    continue
                var top := at.y - pr * 0.4
                var pts := PackedVector2Array([Vector2(-pr, top + pr), Vector2(-pr, top), Vector2(-pr * 0.5, top + pr * 0.5), Vector2(0, top - pr * 0.4), Vector2(pr * 0.5, top + pr * 0.5), Vector2(pr, top), Vector2(pr, top + pr)])
                var shifted := PackedVector2Array()
                for q in pts:
                    shifted.append(Vector2(at.x + q.x, q.y))
                cv.draw_polyline(shifted, Hostile.DARK, 5.0)
                cv.draw_colored_polygon(shifted, Color(0.15, 0.06, 0.04))
                cv.draw_polyline(shifted, (Color(0.95, 0.88, 0.6) if bone else Color(1.0, 0.6, 0.2)).lerp(Color.WHITE, flash), 2.0)
        if not vis:
            continue
        # The part's element states as pips beside it, its compound as a ring of motes.
        var st: Dictionary = p["states"] if i != body.cur else states
        var cid: String = String(p["compound"]) if i != body.cur else compound
        var n := 0
        for k in st.keys():
            var pip := at + Vector2(pr + 7.0, -pr * 0.5 + 8.0 * float(n))
            cv.draw_rect(Rect2(pip - Vector2(3.5, 3.5), Vector2(7, 7)), Color(0.05, 0.02, 0.02))
            cv.draw_rect(Rect2(pip - Vector2(2.5, 2.5), Vector2(5, 5)), Element.COLORS[k])
            n += 1
        if cid != "":
            var cc: Color = Fusions.compound(cid).get("color", Color.WHITE)
            var ring := pr + 5.0
            cv.draw_arc(at, ring, 0.0, TAU, 28, Color(cc, 0.55), 1.5)
            for k in 4:
                var am := _fx_t * 3.2 + TAU * float(k) / 4.0
                var mp := at + Vector2(cos(am), sin(am) * 0.6) * ring
                cv.draw_rect(Rect2(floorf(mp.x - 2.0), floorf(mp.y - 2.0), 4.0, 4.0), cc.lightened(0.3))
    if body.staggered():
        cv.draw_arc(Vector2.ZERO, R * 1.45, 0.0, TAU, 40, Color(1.0, 0.9, 0.4, 0.5 + 0.4 * absf(sin(_fx_t * 10.0))), 2.0)
        for k in 4:
            var a := _fx_t * 4.0 + float(k) * TAU / 4.0
            cv.draw_circle(Vector2(cos(a), sin(a) * 0.35) * R * 1.1 + Vector2(0, -R * 1.9), 3.0, Color(1, 0.9, 0.4))


func _think_boss(delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    match boss_kind:
        "brute_king":
            return _think_brute(delta, target, dir, dist, mult)
        "hive_mother":
            return _think_hive(delta, target, dir, dist, mult)
        "storm_warden":
            return _think_warden(delta, target, dir, dist, mult)
        "pyre_lord":
            return _think_pyre(delta, target, dir, mult)
        "void_herald":
            return _think_herald(delta, target, dir, dist, mult)
        "drowned_choir":
            return _think_choir(delta, target, dir, dist, mult)
    return dir * speed * mult


# --- The Storm Warden ------------------------------------------------------------


## Part `i` holds element `kind` (the focused part's states live on the Enemy).
func _part_has(i: int, kind: int) -> bool:
    return (states if i == body.cur else Dictionary(body.parts[i]["states"])).has(kind)


## Phase 1: the pylons charge. Lightning strikes on a rhythm where you stand (a marked
## circle first), bolt bursts, a telegraphed jump. Phase 2: the rods burst and the arena
## rains lightning, three strikes round you and a recharge strike on himself, which sets off
## a Storm Cloud in a steamed core. Phase 3: he is a moving storm: fast, leaving charged air,
## a strike on you every second and a recharge every few.
func _think_warden(delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    _t1 -= delta
    _t2 -= delta
    _strike_t -= delta
    var dmg := _projectile_damage(6.0)
    if _t1 <= 0.0 and _burst_left <= 0:
        _t1 = [3.0, 2.6, 2.4][clampi(_phase - 1, 0, 2)]
        _burst_left = 5 if _phase < 3 else 3
        _burst_t = 0.0
    if _burst_left > 0:
        _burst_t -= delta
        if _burst_t <= 0.0:
            _burst_t = 0.12
            _burst_left -= 1
            _shoot(dir, 300.0, dmg, Element.Kind.SHOCK, 3.0, 6.0)
            if _phase == 2:
                _shoot(dir.rotated(0.3), 300.0, dmg, Element.Kind.SHOCK, 3.0, 6.0)
                _shoot(dir.rotated(-0.3), 300.0, dmg, Element.Kind.SHOCK, 3.0, 6.0)
    if _strike_t <= 0.0:
        var tp := target.global_position
        match _phase:
            1:
                _strike_t = 1.6
                _add_strike(tp, 1.0, false)
            2:
                _strike_t = 2.6
                for k in 3:
                    _add_strike(_pick_point_near(tp, 0.0 if k == 0 else 70.0, 0.0 if k == 0 else 140.0), 1.2, false)
                _add_strike(global_position, 1.2, true)
            _:
                _strike_t = 1.0
                _add_strike(tp, 0.9, false)
                _t3 -= 1.0
                if _t3 <= 0.0:
                    _t3 = 3.0
                    _add_strike(global_position, 1.0, true)
    if _phase >= 3:
        _tele_warn = 0.0
        # Charged air behind him: shock for your own chains (steam, water) to catch.
        _storm_trail -= delta
        if _storm_trail <= 0.0:
            _storm_trail = 1.6
            var w := _world()
            if w != null:
                Cloud.spawn(w, global_position, Element.Kind.SHOCK, 50.0, 2.5, 1.0, null)
        return _keep_range(delta, dir, dist, 140.0, 220.0) * speed * mult
    # The jump, telegraphed by a crackling circle where he will land.
    if _tele_warn > 0.0:
        _tele_warn -= delta
        if _tele_warn <= 0.0:
            _teleport_to(_tele_pos)
            Sfx.play("react_chain")
        return Vector2.ZERO
    if _t2 <= 0.0:
        _t2 = 6.0 if _phase == 1 else 5.0
        _tele_pos = _pick_point_near(target.global_position, 200.0, 340.0)
        _tele_warn = 0.8
        return Vector2.ZERO
    for sk in _strikes:
        if sk["self"] and float(sk["warn"]) > 0.0:
            return Vector2.ZERO   # he holds still for his own recharge
    return _keep_range(delta, dir, dist, 160.0, 280.0) * speed * mult


func _add_strike(at: Vector2, warn: float, on_self: bool) -> void:
    _strikes.append({ "pos": at, "warn": warn, "warn0": warn, "flash": 0.0, "self": on_self })
    while _strikes.size() > 12:
        _strikes.pop_front()


func _tick_strikes(delta: float) -> void:
    for i in range(_strikes.size() - 1, -1, -1):
        var sk: Dictionary = _strikes[i]
        if float(sk["warn"]) > 0.0:
            if sk["self"]:
                sk["pos"] = global_position
            sk["warn"] = float(sk["warn"]) - delta
            if float(sk["warn"]) <= 0.0:
                _land_strike(sk)
        else:
            sk["flash"] = float(sk["flash"]) - delta
            if float(sk["flash"]) <= 0.0:
                _strikes.remove_at(i)


func _land_strike(sk: Dictionary) -> void:
    sk["flash"] = 0.18
    var at: Vector2 = sk["pos"]
    var r := radius * STRIKE_SELF_R if sk["self"] else STRIKE_R
    for p in get_tree().get_nodes_in_group("players"):
        if is_instance_valid(p) and p.alive and p.global_position.distance_to(at) <= r + 10.0:
            p.take_damage(_projectile_damage(10.0) * damage_mult, self, at)
    Elements.nova.emit(at, r, Color(1.0, 0.95, 0.5, 0.7))
    Sfx.play_at("react_chain", at, 0.0)
    if sk["self"] and body != null and hp > 0.0:
        # The recharge: a steamed core takes the bolt as a Storm Cloud inside him.
        var c := body.part_index("storm_core")
        if c >= 0 and body.visible(c):
            body.focus(c)
            apply_element(Element.Kind.SHOCK, 1.0, null)
        if BossBody.log_enabled:
            print("[BOSS-MOVE] t=%.1f kind=storm_warden recharge phase=%d" % [body.age, _phase])


func _draw_warden_hostile(cv: CanvasItem) -> void:
    for sk in _strikes:
        var at := to_local(sk["pos"])
        var r := radius * STRIKE_SELF_R if sk["self"] else STRIKE_R
        if float(sk["warn"]) > 0.0:
            var k := 1.0 - float(sk["warn"]) / float(sk["warn0"])
            cv.draw_arc(at, r, 0.0, TAU, 32, Color(Hostile.DARK, 0.8), 6.0)
            cv.draw_arc(at, r, 0.0, TAU, 32, Color(Hostile.RED, 0.45 + 0.5 * k), 2.5)
            cv.draw_circle(at, r * k, Color(Hostile.RED, 0.18))
        else:
            # The bolt: a jagged line from the sky, black with a red core.
            var pts := PackedVector2Array()
            var top := at + Vector2(0, -260.0)
            for j in 7:
                var f := float(j) / 6.0
                var jig := 0.0 if j == 0 or j == 6 else randf_range(-14.0, 14.0)
                pts.append(top.lerp(at, f) + Vector2(jig, 0.0))
            cv.draw_polyline(pts, Hostile.DARK, 7.0)
            cv.draw_polyline(pts, Hostile.RED, 3.0)
            cv.draw_polyline(pts, Color(1.0, 0.95, 0.8), 1.0)


# --- The Drowned Choir (phase 5, the Drowned Cistern) -------------------------------


## A great bell with drowned singers fused to it. Wet bolts throughout. Phases 1 and 2:
## songs that pull (a marked ring first, then a pull toward the bell). Phase 2: the arena
## floods (water lands round the room, conductive for your shock and its). Phase 3: the bell
## cracks and rings in shockwaves (full rings that wind up first; a stagger holds them).
const SONG_WARN := 1.1
const SONG_SECS := 1.8
const SONG_R := 330.0
const SONG_PULL := 70.0
var _song_warn := 0.0
var _song_t := 0.0
var _flood_t := 0.0
var _flood_log := Vector3.ZERO   # bots: phase 2 seconds, on a ledge, on charged water
var _flood_logged := false


func _think_choir(delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    _t1 -= delta
    _t2 -= delta
    _t3 -= delta
    if _t1 <= 0.0:
        _t1 = [2.8, 2.6, 3.0][clampi(_phase - 1, 0, 2)]
        var n := 3 if _phase == 1 else 5
        for k in n:
            var a := (float(k) - float(n - 1) * 0.5) * 0.22
            _shoot(dir.rotated(a), 210.0, _projectile_damage(5.0), Element.Kind.WET, 3.5, 7.0)
    if _phase < 3 and _t2 <= 0.0 and _song_warn <= 0.0 and _song_t <= 0.0:
        _t2 = 6.5 if _phase == 1 else 5.5
        _song_warn = SONG_WARN
        if BossBody.log_enabled and body != null:
            print("[BOSS-MOVE] t=%.1f kind=drowned_choir song phase=%d" % [body.age, _phase])
    if _phase >= 3 and _t3 <= 0.0:
        _t3 = 3.2
        _add_wave(0.0, PI, 190.0)
        if BossBody.log_enabled and body != null:
            print("[BOSS-MOVE] t=%.1f kind=drowned_choir ring phase=%d" % [body.age, _phase])
    if _song_warn > 0.0 or _song_t > 0.0:
        return Vector2.ZERO   # it holds still to sing
    return _keep_range(delta, dir, dist, 150.0, 260.0) * speed * mult


func _tick_choir(delta: float) -> void:
    _tick_flame_waves(delta)
    if _song_warn > 0.0:
        if not (body != null and body.staggered()):
            _song_warn -= delta
        if _song_warn <= 0.0:
            _song_t = SONG_SECS
            Sfx.play_at("react_chain", global_position, -6.0)
    elif _song_t > 0.0:
        _song_t -= delta
        if body != null and body.staggered():
            _song_t = 0.0
        for p in get_tree().get_nodes_in_group("players"):
            if is_instance_valid(p) and p.alive and p is CharacterBody2D:
                var to: Vector2 = global_position - p.global_position
                if to.length() <= SONG_R and to.length() > radius + 30.0:
                    (p as CharacterBody2D).move_and_collide(to.normalized() * SONG_PULL * delta)
    if BossBody.log_enabled and not _flood_logged:
        if _phase == 2:
            var rm := Room.here
            for p in get_tree().get_nodes_in_group("players"):
                if is_instance_valid(p) and p.alive and p is Player:
                    _flood_log.x += delta
                    if rm != null and is_instance_valid(rm) and rm.on_platform(p.global_position):
                        _flood_log.y += delta
                    if (p as Player).hazard_mat == Materials.CHARGED:
                        _flood_log.z += delta
                    break
        elif _phase >= 3 and _flood_log.x > 0.0:
            _flood_logged = true
            print("[CHOIR-FLOOD] phase2=%.1fs on_ledge=%.1fs on_charged=%.1fs" % [_flood_log.x, _flood_log.y, _flood_log.z])
    if _phase == 2:
        _flood_t -= delta
        if _flood_t <= 0.0:
            _flood_t = 0.7
            var m := Materials.find(self)
            if m != null:
                m.stamp(Element.Kind.WET, _pick_point_near(global_position, 60.0, 320.0), 45.0, 130)


func _draw_choir_hostile(cv: CanvasItem) -> void:
    if _song_warn > 0.0:
        var k := 0.5 + 0.5 * absf(sin(_fx_t * 12.0))
        Hostile.dash_ring(cv, Vector2.ZERO, SONG_R, 0.5 + 0.4 * k, 3.0)
    elif _song_t > 0.0:
        for j in 3:
            var f := fmod(_fx_t * 0.9 + float(j) / 3.0, 1.0)
            Hostile.dash_ring(cv, Vector2.ZERO, lerpf(SONG_R, radius + 30.0, f), 0.7 * (1.0 - f) + 0.2, 2.5)
    for wv in _waves:
        var o := to_local(wv["o"])
        if float(wv["warn"]) > 0.0:
            var k := 0.5 + 0.5 * absf(sin(_fx_t * 14.0))
            _hostile_arc(cv, o, radius + 22.0, 0.0, PI, 6.0, k)
            _hostile_arc(cv, o, WAVE_REACH, 0.0, PI, 3.0, 0.35 * k)
        else:
            _hostile_arc(cv, o, float(wv["r"]), 0.0, PI, WAVE_BAND, 1.0)


# --- The Void Herald --------------------------------------------------------------


## Phase 1: gravity wells (a marked circle first) that pull you and bend your shots; holy
## collapses them. Spiral volleys and wisps as before. Phase 2: it steals the element you
## hit it with most: immune to it, and its spirals carry it. Phase 3: the theft ends and the
## shards close in: rings of shards that fly at where you stood, their paths marked first.
func _think_herald(delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    _t1 -= delta
    _t2 -= delta
    _t3 -= delta
    if _t1 <= 0.0 and _spiral_left <= 0.0:
        _t1 = [5.0, 3.8, 4.5][clampi(_phase - 1, 0, 2)]
        _spiral_left = 2.5
        _burst_t = 0.0
    if _spiral_left > 0.0:
        _spiral_left -= delta
        _burst_t -= delta
        _spiral_angle += delta * 3.2
        if _burst_t <= 0.0:
            _burst_t = 0.12
            var arms := 2 if _phase == 1 else 3
            var el: int = _stolen if _stolen != Element.Kind.NONE else Element.Kind.VOID
            for i in arms:
                _shoot(Vector2.RIGHT.rotated(_spiral_angle + TAU * float(i) / float(arms)), 180.0, _projectile_damage(6.0), el, 4.0, 7.0)
    if _t2 <= 0.0:
        _t2 = 7.0
        _queue_summons("wisp", 2 if _phase == 1 else 3, 0.8)
    if _t3 <= 0.0:
        if _phase >= 3:
            _t3 = 3.5
            _close_in(target.global_position)
        else:
            _t3 = 6.0 if _phase == 1 else 5.0
            var live := 0
            for w in _wells:
                if float(w["t"]) > 0.0:
                    live += 1
            if live < (2 if _phase == 1 else 3):
                _wells.append({ "pos": _pick_point_near(target.global_position, 40.0, 140.0), "r": WELL_R, "warn": WELL_WARN, "t": WELL_LIFE })
    return _keep_range(delta, dir, dist, 160.0, 260.0) * speed * mult


## Phase 2: the element the party fed it most is now its own.
func _steal() -> void:
    var best: int = Element.Kind.NONE
    var most := 0
    for k in _fed.keys():
        if int(k) != Element.Kind.NONE and int(_fed[k]) > most:
            most = int(_fed[k])
            best = int(k)
    if best == Element.Kind.NONE:
        best = Element.Kind.FIRE
    _stolen = best
    immune_to = best
    Elements.reaction_fired.emit("It steals your %s" % Element.NAMES[best], global_position + Vector2(0, -radius * 1.8), Element.COLORS[best])
    if BossBody.log_enabled and body != null:
        print("[BOSS-MOVE] t=%.1f kind=void_herald steals=%s phase=%d" % [body.age, Element.NAMES[best], _phase])


## Six shards on a ring round `at` fly in at it after their paths show.
func _close_in(at: Vector2) -> void:
    var off := randf() * TAU
    for k in 6:
        var from := at + Vector2.from_angle(off + TAU * float(k) / 6.0) * 240.0
        _volleys.append({ "from": from, "to": at + (at - from) * 0.4, "warn": SHARD_WARN, "t": 0.0, "hit": false })
    while _volleys.size() > 18:
        _volleys.pop_front()
    if BossBody.log_enabled and body != null:
        print("[BOSS-MOVE] t=%.1f kind=void_herald close_in phase=%d" % [body.age, _phase])


func _tick_herald(delta: float) -> void:
    if _phase == 2 and _stolen == Element.Kind.NONE:
        _steal()
    elif _phase >= 3 and _stolen != Element.Kind.NONE:
        Elements.reaction_fired.emit("It lets go of your %s" % Element.NAMES[_stolen], global_position + Vector2(0, -radius * 1.8), Element.COLORS[_stolen])
        _stolen = Element.Kind.NONE
        immune_to = Element.Kind.NONE
    Projectile.wells = _wells
    Projectile.well_owner = self
    for i in range(_wells.size() - 1, -1, -1):
        var w: Dictionary = _wells[i]
        if float(w["warn"]) > 0.0:
            w["warn"] = float(w["warn"]) - delta
            continue
        w["t"] = float(w["t"]) - delta
        if float(w["t"]) <= 0.0:
            _wells.remove_at(i)
            continue
        for p in get_tree().get_nodes_in_group("players"):
            if is_instance_valid(p) and p.alive and p is CharacterBody2D:
                var d: float = p.global_position.distance_to(w["pos"])
                if d <= float(w["r"]) and d > 12.0:
                    (p as CharacterBody2D).move_and_collide((Vector2(w["pos"]) - p.global_position).normalized() * WELL_PULL * delta)
    var dmg := _projectile_damage(8.0) * damage_mult
    for i in range(_volleys.size() - 1, -1, -1):
        var v: Dictionary = _volleys[i]
        if float(v["warn"]) > 0.0:
            v["warn"] = float(v["warn"]) - delta
            continue
        v["t"] = float(v["t"]) + delta / SHARD_TRAVEL
        if float(v["t"]) >= 1.0:
            _volleys.remove_at(i)
            continue
        if v["hit"]:
            continue
        var at: Vector2 = Vector2(v["from"]).lerp(v["to"], float(v["t"]))
        for p in get_tree().get_nodes_in_group("players"):
            if is_instance_valid(p) and p.alive and p.global_position.distance_to(at) <= 16.0:
                p.take_damage(dmg, self, at)
                v["hit"] = true
                break


func _exit_tree() -> void:
    if Projectile.well_owner == self:
        Projectile.wells = []
        Projectile.well_owner = null


func _draw_shard(cv: CanvasItem, c: Vector2, ang: float, sz: float, flash: float) -> void:
    var pts := PackedVector2Array([c + Vector2(sz * 1.4, 0).rotated(ang), c + Vector2(0, sz * 0.6).rotated(ang), c + Vector2(-sz * 1.4, 0).rotated(ang), c + Vector2(0, -sz * 0.6).rotated(ang)])
    var big := PackedVector2Array()
    for q in pts:
        big.append(c + (q - c) * 1.35)
    cv.draw_colored_polygon(big, Hostile.DARK)
    cv.draw_colored_polygon(pts, Color(0.6, 0.35, 0.95).lerp(Color.WHITE, flash * 0.6))
    big.append(big[0])
    cv.draw_polyline(big, Color(Hostile.RED, 0.9), 1.0)


func _draw_herald_hostile(cv: CanvasItem) -> void:
    for w in _wells:
        var at := to_local(w["pos"])
        var r := float(w["r"])
        if float(w["warn"]) > 0.0:
            var k := 1.0 - float(w["warn"]) / WELL_WARN
            cv.draw_arc(at, r, 0.0, TAU, 32, Color(Hostile.DARK, 0.8), 6.0)
            cv.draw_arc(at, r, 0.0, TAU, 32, Color(Hostile.RED, 0.45 + 0.5 * k), 2.5)
            cv.draw_circle(at, r * k, Color(Hostile.RED, 0.15))
        else:
            # A dark well with arcs spiralling into it.
            cv.draw_circle(at, r, Color(0.05, 0.0, 0.08, 0.35))
            cv.draw_arc(at, r, 0.0, TAU, 32, Hostile.DARK, 4.0)
            cv.draw_arc(at, r + 2.0, 0.0, TAU, 32, Color(Hostile.RED, 0.8), 1.5)
            for j in 3:
                var a0 := -_fx_t * 2.5 + TAU * float(j) / 3.0
                var rr := r * (0.35 + 0.5 * fmod(_fx_t * 0.6 + float(j) / 3.0, 1.0))
                cv.draw_arc(at, rr, a0, a0 + 1.6, 10, Color(Hostile.RED, 0.7), 2.0)
    for v in _volleys:
        var f := to_local(v["from"])
        var t := to_local(v["to"])
        var ang := (t - f).angle()
        if float(v["warn"]) > 0.0:
            var k := 1.0 - float(v["warn"]) / SHARD_WARN
            cv.draw_line(f, t, Color(Hostile.DARK, 0.7), 5.0)
            cv.draw_line(f, t, Color(Hostile.RED, 0.35 + 0.5 * k), 1.5)
            _draw_shard(cv, f, ang, 8.0, 0.0)
        elif not v["hit"]:
            _draw_shard(cv, f.lerp(t, float(v["t"])), ang, 9.0, 0.0)


# --- The Hive Mother --------------------------------------------------------------


func burrowed() -> bool:
    return _burrow_state == 2


## Phase 1: swarms, poison rings and spore clouds (poison you can light into Smog). Phase 2
## adds a burrow: she digs in, her sacs stay above ground, and she bursts up under you
## inside a marked circle. Phase 3: the hive splits open, faster rings, more swarmers.
func _think_hive(delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    var ph := clampi(_phase - 1, 0, 2)
    if _sprite != null:
        _sprite.self_modulate.a = 0.25 if _burrow_state == 2 else 1.0
    if _burrow_state > 0:
        _burrow_t -= delta
        if _burrow_state == 1 and _burrow_t <= 0.0:
            _burrow_state = 2
            _burrow_t = BURROW_UNDER
            Elements.nova.emit(global_position, radius * 1.6, Color(0.45, 0.35, 0.2, 0.7))
            Sfx.play_at("hit_wall", global_position, 0.0)
        elif _burrow_state == 2:
            if _burrow_t > BURROW_MARK:
                _burrow_at = _pick_point_near(target.global_position, 0.0, 40.0)
            elif _burrow_t <= 0.0:
                _erupt()
        return Vector2.ZERO
    _t1 -= delta
    _t2 -= delta
    _t3 -= delta
    _spore_t -= delta
    if _t1 <= 0.0:
        _t1 = [4.0, 4.0, 3.2][ph]
        _queue_summons("swarmer", [3, 4, 5][ph], 0.7)
    _ring_warn = maxf(0.0, _t2) if _t2 < 0.6 else 0.0
    if _t2 <= 0.0:
        _t2 = [5.0, 4.2, 3.2][ph]
        _ring_warn = 0.0
        var n: int = [8, 10, 12][ph]
        var off := randf() * TAU
        for i in n:
            _shoot(Vector2.RIGHT.rotated(off + TAU * float(i) / float(n)), 170.0, _projectile_damage(7.0), Element.Kind.POISON, 4.0, 7.0)
        _squash = 1.0
    if _spore_t <= 0.0 and body != null and body.visible(body.part_index("sacs")):
        # The sacs puff spores: poison in the air, which fire turns into Smog against her.
        _spore_t = 6.0
        var w := _world()
        if w != null:
            Cloud.spawn(w, body.part_world(body.part_index("sacs")) + Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 30.0)), Element.Kind.POISON, 70.0, 6.0, 1.0, null)
    if _phase >= 2 and _t3 <= 0.0 and _mode == MODE_CHASE:
        _t3 = 6.0 if _phase == 2 else 8.0
        _burrow_state = 1
        _burrow_t = BURROW_WARN
        _squash = 1.0
        return Vector2.ZERO
    return _keep_range(delta, dir, dist, 200.0, 320.0) * speed * mult


## She bursts up at the marked spot: players inside the circle are hurt and thrown clear.
func _erupt() -> void:
    _burrow_state = 0
    if BossBody.log_enabled and body != null:
        print("[BOSS-MOVE] t=%.1f kind=hive_mother erupt phase=%d" % [body.age, _phase])
    _teleport_to(_burrow_at)
    for p in get_tree().get_nodes_in_group("players"):
        if is_instance_valid(p) and p.alive and p.global_position.distance_to(_burrow_at) <= ERUPT_R + 12.0:
            p.take_damage(_projectile_damage(11.0) * damage_mult, self, _burrow_at)
    Elements.nova.emit(_burrow_at, ERUPT_R, Color(0.55, 0.75, 0.3, 0.8))
    Sfx.play("nova_fire")
    var fx := _fx()
    if fx != null:
        fx._shake(6.0)
    _squash = 1.0


func _draw_hive_hostile(cv: CanvasItem) -> void:
    if _burrow_state == 1:
        var k := 1.0 - _burrow_t / BURROW_WARN
        var a := 0.5 + 0.4 * absf(sin(_fx_t * 16.0))
        cv.draw_arc(Vector2.ZERO, radius * (1.6 - 0.5 * k), 0.0, TAU, 32, Color(Hostile.DARK, 0.8), 5.0)
        cv.draw_arc(Vector2.ZERO, radius * (1.6 - 0.5 * k), 0.0, TAU, 32, Color(Hostile.RED, a), 2.0)
    elif _burrow_state == 2:
        # A churned mound where she went down, and the eruption circle once it is set.
        cv.draw_circle(Vector2(0, radius * 0.4), radius * 0.9, Color(0.18, 0.13, 0.08, 0.85))
        cv.draw_arc(Vector2(0, radius * 0.4), radius * 0.9, 0.0, TAU, 24, Hostile.DARK, 2.0)
        if _burrow_t <= BURROW_MARK:
            var k := 1.0 - _burrow_t / BURROW_MARK
            var at := to_local(_burrow_at)
            cv.draw_arc(at, ERUPT_R, 0.0, TAU, 32, Color(Hostile.DARK, 0.8), 6.0)
            cv.draw_arc(at, ERUPT_R, 0.0, TAU, 32, Color(Hostile.RED, 0.45 + 0.5 * k), 2.5)
            cv.draw_circle(at, ERUPT_R * k, Color(Hostile.RED, 0.18))


# --- The Brute King ---------------------------------------------------------------


## Phase 1 smashes (charges) and throws a barrel; phase 2 throws two and swallows the ones
## near him; phase 3 is enraged: faster, shorter charges, the crown bare.
func _think_brute(delta: float, target: Player, dir: Vector2, dist: float, mult: float) -> Vector2:
    _t1 -= delta
    if _gut_warn > 0.0:
        _gut_warn -= delta
        if _gut_warn <= 0.0:
            _gut_blast()
        return Vector2.ZERO
    var lure := Vector2.INF
    if _phase >= 2 and _swallowed < 3:
        lure = _swallow_near()
    if _t1 <= 0.0 and _mode == MODE_CHASE:
        _t1 = [4.5, 4.0, 3.5][clampi(_phase - 1, 0, 2)]
        for k in (1 if _phase == 1 else 2):
            _throw_barrel(_pick_point_near(target.global_position, 20.0 + 70.0 * float(k), 100.0 + 70.0 * float(k)))
    if lure != Vector2.INF and _mode == MODE_CHASE:
        return (lure - global_position).normalized() * speed * mult
    if _phase < 3:
        return _charge_ai(delta, dir, dist, mult, 0.8, 480.0, 0.6, 2.5 if _phase == 1 else 1.8, 340.0)
    return _charge_ai(delta, dir, dist, mult, 0.5, 540.0, 0.6, 1.2, 420.0)


func _throw_barrel(to: Vector2) -> void:
    var live := _barrels.size()
    for pr in get_tree().get_nodes_in_group("props"):
        if pr is Prop and pr.kind == "barrel" and pr.has_meta("brute") and not pr.is_queued_for_deletion():
            live += 1
    if live >= BRUTE_BARREL_CAP:
        return
    _barrels.append({ "from": global_position + Vector2(0, -radius), "to": to, "t": 0.0, "dur": 1.0 })
    _squash = 1.0
    Sfx.play_at("hit_wall", global_position, -4.0)


## A thrown barrel lands: a thud that hurts inside its marked circle, and a barrel to use.
func _land_barrel(to: Vector2) -> void:
    for p in get_tree().get_nodes_in_group("players"):
        if is_instance_valid(p) and p.alive and p.global_position.distance_to(to) <= BARREL_HIT_R + 12.0:
            p.take_damage(_projectile_damage(9.0) * damage_mult, self, to)
    Elements.nova.emit(to, BARREL_HIT_R, Color(0.6, 0.42, 0.3, 0.6))
    Sfx.play_at("hit_wall", to, -2.0)
    var rm := Room.here
    if rm == null or not is_instance_valid(rm) or hp <= 0.0:
        return
    var b := Prop.new("barrel")
    b.room = rm
    b.set_meta("brute", true)
    rm.add_child(b)
    b.global_position = to


## Phase 2+: swallows an unlit barrel within reach. Returns the nearest barrel worth walking
## to (Vector2.INF if none), so he goes for his fuel and the player can set it off first.
func _swallow_near() -> Vector2:
    var best := Vector2.INF
    var best_d := 300.0
    for pr in get_tree().get_nodes_in_group("props"):
        if not pr is Prop or pr.kind != "barrel" or pr.is_queued_for_deletion() or pr._gone or pr._timers.has("fuse"):
            continue
        var d: float = pr.global_position.distance_to(global_position)
        if d <= radius + 26.0:
            pr.queue_free()
            _swallowed += 1
            _squash = 1.0
            Elements.reaction_fired.emit("Swallows a barrel", global_position + Vector2(0, -radius * 1.6), Color(1.0, 0.7, 0.4))
            Sfx.play_at("hit_wall", global_position, 0.0)
            if BossBody.log_enabled and body != null:
                print("[BOSS-CHAIN] t=%.1f part=hide SWALLOWED n=%d phase=%d" % [body.age, _swallowed, _phase])
            return Vector2.INF
        if d < best_d:
            best_d = d
            best = pr.global_position
    return best


func _gut_blast() -> void:
    var n := _swallowed
    _swallowed = 0
    for p in get_tree().get_nodes_in_group("players"):
        if is_instance_valid(p) and p.alive and p.global_position.distance_to(global_position) <= GUT_RADIUS + 12.0:
            p.take_damage(_projectile_damage(12.0) * damage_mult, self, global_position)
    Elements.nova.emit(global_position, GUT_RADIUS, Color(1.0, 0.5, 0.2, 0.8))
    Sfx.play("nova_fire")
    var fx := _fx()
    if fx != null:
        fx._shake(7.0)
    if body != null:
        body.blast("Gut Blast", global_position, 4, 0.03 * float(n))


func _draw_brute_hostile(cv: CanvasItem) -> void:
    for b in _barrels:
        var k := float(b["t"]) / float(b["dur"])
        var to := to_local(b["to"])
        cv.draw_arc(to, BARREL_HIT_R, 0.0, TAU, 24, Color(Hostile.DARK, 0.75), 5.0)
        cv.draw_arc(to, BARREL_HIT_R, 0.0, TAU, 24, Color(Hostile.RED, 0.4 + 0.5 * k), 2.0)
        cv.draw_circle(to, BARREL_HIT_R * k, Color(Hostile.RED, 0.18))
        var at := to_local(b["from"]).lerp(to, k) + Vector2(0, -sin(k * PI) * 90.0)
        cv.draw_rect(Rect2(at - Vector2(9, 11), Vector2(18, 22)), Hostile.DARK)
        cv.draw_rect(Rect2(at - Vector2(7, 9), Vector2(14, 18)), Color(0.55, 0.38, 0.26))
        cv.draw_rect(Rect2(at - Vector2(9, 11), Vector2(18, 22)), Hostile.RED, false, 1.0)
    if _gut_warn > 0.0:
        var k := 1.0 - _gut_warn / GUT_WARN
        var a := 0.5 + 0.4 * absf(sin(_fx_t * 18.0))
        cv.draw_arc(Vector2.ZERO, GUT_RADIUS, 0.0, TAU, 40, Color(Hostile.DARK, 0.8), 6.0)
        cv.draw_arc(Vector2.ZERO, GUT_RADIUS, 0.0, TAU, 40, Color(Hostile.RED, a), 2.5)
        cv.draw_circle(Vector2.ZERO, GUT_RADIUS * k, Color(Hostile.RED, 0.15))
    elif _swallowed > 0 and hp > 0.0:
        # A swollen gut that glows: fire or shock sets it off.
        var g := Vector2(0, radius * 0.25)
        cv.draw_circle(g, radius * 0.3 + 2.0, Hostile.DARK)
        cv.draw_circle(g, radius * 0.3, Color(1.0, 0.45 + 0.15 * sin(_fx_t * 6.0), 0.15))
        cv.draw_arc(g, radius * 0.3 + 2.0, 0.0, TAU, 20, Hostile.RED, 1.0)


func _pick_point_near(around: Vector2, min_d: float, max_d: float) -> Vector2:
    var rr := _room_rect()
    var inner := rr.grow(-70.0) if rr.has_area() else Rect2()
    var p := around
    for attempt in 10:
        p = around + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(min_d, max_d)
        if not inner.has_area() or inner.has_point(p):
            return p
    if inner.has_area():
        p = Vector2(clampf(p.x, inner.position.x, inner.end.x), clampf(p.y, inner.position.y, inner.end.y))
    return p


func _update_sprite() -> void:
    var c := base_color
    if states.has(Element.Kind.WET):
        c = c.lerp(Element.COLORS[Element.Kind.WET], 0.4)
    if states.has(Element.Kind.OIL):
        c = c.lerp(Color(0.15, 0.1, 0.08), 0.5)
    if states.has(Element.Kind.SHOCK) and randf() < 0.5:
        c = c.lerp(Element.COLORS[Element.Kind.SHOCK], 0.5)
    if poison_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.POISON], 0.45)
    if corroded_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.ACID], 0.3)
    if bleed_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.BLOOD], 0.3)
    if frozen_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.ICE], 0.75)
    if stun_time > 0.0 and fmod(stun_time, 0.2) < 0.1:
        c = c.lerp(Color.WHITE, 0.5)
    if burn_time > 0.0:
        c = c.lerp(Element.COLORS[Element.Kind.FIRE], 0.35)
    if _mode == MODE_TELEGRAPH and fmod(_mode_t, 0.16) < 0.08:
        c = c.lerp(Color(1, 0.3, 0.2), 0.7)
    if _crouch_t > 0.0:
        c = c.lerp(Color(1, 0.3, 0.2), 0.6)
    if _fuse >= 0.0 and fmod(_fuse, 0.1) < 0.05:
        c = c.lerp(Color(1, 1, 0.6), 0.8)
    if kind_name == "boss" and _phase >= 2:
        # The phase shows on the body: a colour shift toward its own glow.
        c = c.lerp(BossShow.accent(boss_kind), 0.15 if _phase == 2 else 0.35)
    if _flash > 0.0:
        c = c.lerp(Color.WHITE, 0.8)
    _sprite.modulate = c
    if absf(velocity.x) > 1.0:
        _sprite.flip_h = velocity.x < 0.0
    # Animation: spawn pop, hop while walking, squash on hit, stiff when frozen.
    var delta := get_physics_process_delta_time()
    _spawn_t = minf(1.0, _spawn_t + delta * 3.0)
    _squash = maxf(0.0, _squash - delta * 6.0)
    var moving := velocity.length() > 5.0
    if moving:
        _anim_t += delta * (9.0 + speed * 0.02)
    var hop := absf(sin(_anim_t)) * 3.0 if moving else 0.0
    if FLYER_SCALE.has(kind_name):
        hop = 1.5 + 1.5 * sin(_fx_t * 5.0 + float(get_instance_id() % 7))   # a hover, not a hop
    var s := _sprite_scale * (_spawn_t + 0.35 * sin(_spawn_t * PI))
    _sprite.scale = Vector2(s * (1.0 + 0.4 * _squash), s * (1.0 - 0.4 * _squash))
    if kind_name == "boss":
        # Idle breathing: a slow heave, quicker as the phases climb.
        var br := sin(_fx_t * (2.2 + 0.7 * float(_phase - 1)))
        _sprite.scale *= Vector2(1.0 - 0.025 * br, 1.0 + 0.045 * br)
    _sprite.position = Vector2(0, -hop)
    _sprite.rotation = (sin(_anim_t) * 0.12 if moving else 0.0)


func _nearest_player() -> Player:
    var best: Player = null
    var best_d := INF
    for p in EnemyGrid.nodes(get_tree(), &"players"):   # cached: every enemy asks every tick
        if not is_instance_valid(p):
            continue
        var d: float = p.global_position.distance_squared_to(global_position)
        if d < best_d:
            best_d = d
            best = p
    return best


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    if intro and _intro_a < 0.05:
        return
    if emerge > 0.0 and not intro:
        # Telegraph: the spawn marker, the body faint until it arrives.
        var k := clampf(1.0 - emerge / EMERGE_SECS, 0.0, 1.0)
        draw_spawn_marker(self, Vector2.ZERO, maxf(radius, 9.0), k, _fx_t)
        if _sprite != null:
            _sprite.modulate.a = 0.25 + 0.6 * k
        _fx_t += get_process_delta_time()
        return
    if _sprite != null and _sprite.modulate.a < 1.0:
        _sprite.modulate.a = 1.0
    if FLYER_SCALE.has(kind_name):
        # In the air: a flat, soft shadow on the floor well below the body.
        draw_set_transform(Vector2(0, radius * 1.5 + 5.0), 0.0, Vector2(1.0, 0.4))
        draw_circle(Vector2.ZERO, radius * 1.3, Color(0, 0, 0, 0.25))
        draw_circle(Vector2.ZERO, radius * 0.85, Color(0, 0, 0, 0.4))
        draw_set_transform_matrix(Transform2D.IDENTITY)
    elif kind_name == "boss":
        # A wide soft body shadow; during the Brute King's fall it grows as he nears.
        var sk := _intro_a if intro else 1.0
        draw_set_transform(Vector2(0, radius * 0.7), 0.0, Vector2(1.0, 0.42))
        draw_circle(Vector2.ZERO, radius * 1.6 * sk, Color(0, 0, 0, 0.14))
        draw_circle(Vector2.ZERO, radius * 1.25 * sk, Color(0, 0, 0, 0.2))
        draw_circle(Vector2.ZERO, radius * 0.9 * sk, Color(0, 0, 0, 0.3))
        draw_set_transform_matrix(Transform2D.IDENTITY)
    else:
        draw_circle(Vector2(0, radius * 0.6), radius * 0.9, Color(0, 0, 0, 0.35))
    _draw_outline()
    _draw_kind()
    if is_elite:
        draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
    if immune_to != Element.Kind.NONE:
        draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Element.COLORS[immune_to], 3.0)
        draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color(0, 0, 0, 0.4), 1.0)
    if shielded():
        draw_arc(Vector2.ZERO, radius + 11.0, 0.0, TAU, 40, Color(1, 1, 1, 0.45 + _shield_flash), 2.5)
    if _ward_t > 0.0:
        # Rally guard: a thick gold ring that pulses while the adds live.
        var pulse := 0.5 + 0.5 * sin(_fx_t * 8.0)
        draw_arc(Vector2.ZERO, radius + 16.0, 0.0, TAU, 48, Color(1.0, 0.8, 0.3, 0.45 + 0.4 * pulse), 4.0)
    if armour_time > 0.0:
        draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 24, Color(0.5, 1.0, 0.5, 0.6), 2.0)
    if affix != "":
        _draw_affix()
    if compound != "" and (body == null or not body.has_parts()):
        # Primed: a thin rim and three motes orbiting in the compound's colour, brightening
        # as it is about to fade, so "add a third element here" reads at a glance.
        var cc: Color = Fusions.compound(compound).get("color", Color.WHITE)
        var ending := compound_time < 0.6
        var pulse := 0.55 + 0.25 * sin(_fx_t * (14.0 if ending else 6.0))
        draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 28, Color(cc, 0.35 * pulse), 1.0)
        for k in 3:
            var am := _fx_t * 3.2 + TAU * float(k) / 3.0
            var mp := Vector2(cos(am) * (radius + 7.0), sin(am) * (radius + 7.0) * 0.55)
            draw_rect(Rect2(floorf(mp.x - 1.5), floorf(mp.y - 1.5), 3.0, 3.0), Color(cc.lightened(0.25), 0.9 * pulse))

    # Element states drawn on the body.
    if states.has(Element.Kind.WET):
        for i in 2:
            var dx := -radius * 0.4 + float(i) * radius * 0.8
            draw_circle(Vector2(dx, radius * 0.6 + fmod(_anim_t * 6.0 + i * 3.0, 6.0)), 2.2, Color(Element.COLORS[Element.Kind.WET], 0.9))
    if states.has(Element.Kind.SHOCK):
        # One or two jagged 1 px arcs crawling over the body, a white pixel at each tip.
        for k in 1 + randi() % 2:
            var a0 := randf() * TAU
            var p0 := Vector2.RIGHT.rotated(a0) * radius * randf_range(0.7, 1.2)
            var p2 := Vector2.RIGHT.rotated(a0 + randf_range(0.6, 1.4)) * radius * randf_range(0.7, 1.2)
            var p1 := (p0 + p2) * 0.5 + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
            draw_polyline(PackedVector2Array([p0, p1, p2]), Color(1.0, 0.95, 0.4, 0.7), 1.0)
            draw_rect(Rect2(floorf(p2.x - 1.0), floorf(p2.y - 1.0), 2.0, 2.0), Color(1, 1, 0.9, 0.75))
    # Statuses shed pixels into the world effects layer about ten times a second.
    if burn_time > 0.0 or poison_time > 0.0:
        var now := Time.get_ticks_msec()
        if now - _shed_ms >= 100:
            _shed_ms = now
            var fx := _fx()
            if fx != null:
                if burn_time > 0.0:
                    fx.ember(global_position + Vector2(randf_range(-radius * 0.5, radius * 0.5), -radius * randf_range(0.6, 1.2)))
                if poison_time > 0.0 and randf() < 0.3 + 0.15 * float(poison_stacks):
                    fx.mote(Element.Kind.POISON, global_position + Vector2(randf_range(-radius, radius), randf_range(-radius, radius * 0.3)))
    if burn_time > 0.0:
        _draw_pixel_flame(Vector2(0, -radius * 0.2), radius * 1.1, radius * 1.6, 8)
    if frozen_time > 0.0:
        # A crystalline outline: pale pixels around the body, one glint running round.
        var n := 14
        var glint := int(_fx_t * 10.0) % n
        draw_circle(Vector2.ZERO, radius + 2.0, Color(0.7, 0.95, 1.0, 0.12))
        for k in n:
            var a1 := TAU * float(k) / float(n)
            var q := Vector2(cos(a1), sin(a1)) * (radius + 3.0 + (1.5 if k % 3 == 0 else 0.0))
            var sz := 3.0 if k % 2 == 0 else 2.0
            var cc := Color(1, 1, 1, 0.75) if k == glint else (Color(0.85, 0.97, 1.0, 0.6) if k % 2 == 0 else Color(0.55, 0.8, 0.95, 0.5))
            draw_rect(Rect2(floorf(q.x - sz * 0.5), floorf(q.y - sz * 0.5), sz, sz), cc)
    if poison_time > 0.0:
        for k in poison_stacks:
            var a2 := _anim_t * 0.7 + float(k) * 1.1
            var q2 := Vector2(cos(a2) * radius * 1.1, -radius * 0.5 - fmod(a2 * 4.0, 14.0))
            draw_rect(Rect2(floorf(q2.x - 1.5), floorf(q2.y - 1.5), 3.0, 3.0), Color(0.45, 0.9, 0.2, 0.55))
            draw_rect(Rect2(floorf(q2.x - 0.5), floorf(q2.y - 0.5), 1.0, 1.0), Color(0.75, 1.0, 0.5, 0.75))
    if bleed_time > 0.0:
        draw_circle(Vector2(radius * 0.5, radius * 0.9), 2.5, Element.COLORS[Element.Kind.BLOOD])
        draw_circle(Vector2(-radius * 0.3, radius * 1.0), 2.0, Element.COLORS[Element.Kind.BLOOD])
    if corroded_time > 0.0:
        draw_arc(Vector2.ZERO, radius + 1.0, 0.0, TAU, 20, Color(Element.COLORS[Element.Kind.ACID], 0.7), 1.5)
    if stun_time > 0.0:
        for i in 3:
            var a := _anim_t * 0.3 + float(i) * TAU / 3.0 + stun_time * 6.0
            draw_circle(Vector2(cos(a), sin(a) * 0.4) * radius * 1.2 + Vector2(0, -radius - 4.0), 2.5, Color(1, 1, 0.6))
    # Generic markers for element states beyond the ones drawn above.
    var i := 0
    for kind in (states.keys() if body == null or not body.has_parts() else []):
        if kind in [Element.Kind.WET, Element.Kind.SHOCK]:
            continue
        draw_circle(Vector2(-radius + 4.0 + 7.0 * i, -radius - 8.0), 3.0, Element.COLORS[kind])
        i += 1

    # Attuned shield: the reaction pair it is weak to, and how many cracks remain.
    if shielded():
        var sy := -radius - 26.0
        draw_circle(Vector2(0, sy), 9.0, Color(0, 0, 0, 0.65))
        draw_circle(Vector2(-4.0, sy), 6.0, Element.COLORS[weakness.x])
        draw_circle(Vector2(4.0, sy), 6.0, Element.COLORS[weakness.y])
        for k in shield_max:
            var px := (float(k) - float(shield_max - 1) / 2.0) * 9.0
            draw_rect(Rect2(px - 3.0, sy + 11.0, 6.0, 4.0), Color(1, 1, 1, 0.95) if k < shield_hp else Color(1, 1, 1, 0.25))

    if (hp < max_hp and hp > 0.0) or is_elite:
        var w := radius * 2.2
        draw_rect(Rect2(-w / 2.0, radius + 5.0, w, 4.0), Color(0, 0, 0, 0.7))
        draw_rect(Rect2(-w / 2.0, radius + 5.0, w * maxf(0.0, hp) / max_hp, 4.0), Color(0.9, 0.2, 0.2))
    # Clarity pass: badges only where you look (the aimed enemy) and on elites and bosses.
    if (not Regions.active_resists.is_empty() or not Regions.active_weak.is_empty())             and (is_elite or kind_name == "boss" or _aimed()):
        _draw_resist_badges()


func _aimed() -> bool:
    for p in get_tree().get_nodes_in_group("players"):
        if is_instance_valid(p) and p.get("aimed") == self:
            return true
    return false


## The region's resistances as small badges under the body (design section 5): a dull
## element square barred in black for a resistance, a bright one split by a black crack for
## a weakness. Exposed turns the resistance badges bright and cracked, blinking white. The
## frame is the hostile signature (black, red rim), so the badge reads as the enemy's own.
func _draw_resist_badges() -> void:
    var kinds: Array = []
    for k in Regions.active_resists:
        kinds.append([k, exposed_time > 0.0, true])
    for k in Regions.active_weak:
        kinds.append([k, true, false])
    var s := 8.0
    var gap := 3.0
    var x0 := floorf(-(float(kinds.size()) * (s + 2.0) + float(kinds.size() - 1) * gap) / 2.0)
    var y0 := floorf(radius + 11.0)
    for i in kinds.size():
        var k: int = kinds[i][0]
        var cracked: bool = kinds[i][1]
        var exposed: bool = cracked and kinds[i][2]
        var x := x0 + float(i) * (s + 2.0 + gap)
        draw_rect(Rect2(x - 1.0, y0 - 1.0, s + 4.0, s + 4.0), Hostile.RED)
        draw_rect(Rect2(x, y0, s + 2.0, s + 2.0), Hostile.DARK)
        var c: Color = Element.COLORS[k]
        if not cracked:
            c = c.lerp(Color(0.4, 0.4, 0.4), 0.25).darkened(0.4)
        elif exposed and int(_fx_t * 8.0) % 2 == 0:
            c = c.lerp(Color.WHITE, 0.6)
        draw_rect(Rect2(x + 1.0, y0 + 1.0, s, s), c)
        if cracked:
            # A jagged black crack corner to corner.
            draw_rect(Rect2(x + 2.0, y0 + 1.0, 1.0, 3.0), Hostile.DARK)
            draw_rect(Rect2(x + 3.0, y0 + 4.0, 2.0, 1.0), Hostile.DARK)
            draw_rect(Rect2(x + 5.0, y0 + 5.0, 1.0, 2.0), Hostile.DARK)
            draw_rect(Rect2(x + 6.0, y0 + 7.0, 2.0, 1.0), Hostile.DARK)
        else:
            draw_rect(Rect2(x + 1.0, y0 + 4.0, s, 2.0), Hostile.DARK)


## A flickering flame of `count` pixel squares rising from `base` (local), `w` wide, `h` tall.
## A dark 1 px outline round the sprite (its silhouette drawn black one pixel off on
## each side, under it), so the tint reads against lit floors and particles; the player's
## rim is bright instead, which keeps the player on top of the hierarchy.
const OUTLINE_DIRS := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
    Vector2(-0.7, -0.7), Vector2(0.7, -0.7), Vector2(-0.7, 0.7), Vector2(0.7, 0.7)]


func _draw_outline() -> void:
    if _sprite == null or _sprite.texture == null:
        return
    var t := _sprite.texture
    var sx := _sprite.scale.x * (-1.0 if _sprite.flip_h else 1.0)
    draw_set_transform(_sprite.position, _sprite.rotation, Vector2(sx, _sprite.scale.y))
    var o := -t.get_size() / 2.0
    # Clarity pass: 2 world px all round (8 directions), opaque, so a body reads on any floor.
    var c := Color(0.02, 0.01, 0.03, _intro_a if intro else 1.0)
    var k := 2.0 / maxf(0.05, absf(_sprite.scale.y))
    for d in OUTLINE_DIRS:
        draw_texture(t, o + d * k, c)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pixel_flame(base: Vector2, w: float, h: float, count: int) -> void:
    var tick := int(_fx_t * 15.0)
    for k in count:
        var rise := fmod(_fx_t * 1.6 + float(k) * 0.618, 1.0)   # 0 at the base, 1 at the tip
        var x := sin(_fx_t * 9.0 + float(k) * 2.1) * w * 0.4 * (1.0 - rise)
        var pos := base + Vector2(x, -rise * h)
        var sz := floorf(4.0 - 2.5 * rise + 0.5)
        var col: Color
        if rise < 0.35:
            col = Color(1.0, 0.88, 0.35, 0.7) if (k + tick) % 3 == 0 else Color(1.0, 0.45, 0.15, 0.6)
        elif rise < 0.75:
            col = Color(1.0, 0.45, 0.15, 0.55) if (k + tick) % 2 == 0 else Color(0.72, 0.14, 0.08, 0.5)
        else:
            col = Color(0.72, 0.14, 0.08, 0.4)
        draw_rect(Rect2(floorf(pos.x - sz * 0.5), floorf(pos.y - sz * 0.5), sz, sz), col)
    # A 2 px hot core at the base, the only opaque bit.
    draw_rect(Rect2(floorf(base.x - 1.0), floorf(base.y - 1.0), 2.0, 2.0), Color(1.0, 0.95, 0.6, 0.9))


## Per-kind tells: charge lines, fuses, armour plates, heal pulses, boss telegraphs.
func _draw_kind() -> void:
    # The dash telegraph is drawn on the Crisp layer (_draw_hostile).
    match kind_name:
        "bomber":
            # Lit fuse on the head; while armed, the blast radius flashes.
            draw_line(Vector2(0, -radius), Vector2(3, -radius - 6), Color(0.6, 0.5, 0.4), 1.5)
            draw_circle(Vector2(3, -radius - 6), 2.0 + absf(sin(_fx_t * 12.0)), Color(1, 0.8, 0.3))
            if _fuse >= 0.0:
                draw_arc(Vector2.ZERO, BOMB_RADIUS, 0.0, TAU, 40, Color(1, 0.4, 0.2, 0.7), 2.0)
                draw_circle(Vector2.ZERO, BOMB_RADIUS, Color(1, 0.4, 0.2, 0.12))
        "warden":
            if states.is_empty():
                for k in 4:
                    var a0 := float(k) * TAU / 4.0 + 0.2
                    draw_arc(Vector2.ZERO, radius + 2.0, a0, a0 + TAU / 4.0 - 0.4, 8, Color(0.75, 0.78, 0.85, 0.9), 3.0)
        "shaman":
            if _pulse_fx > 0.0:
                var r := 160.0 * (1.0 - _pulse_fx / 0.6)
                draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.5, 1.0, 0.5, _pulse_fx), 2.0)
            draw_circle(Vector2(0, -radius - 3.0), 2.5, Color(0.5, 1.0, 0.5, 0.6 + 0.4 * sin(_fx_t * 4.0)))
        "spitter":
            if _shoot_t < 0.35:
                draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - _shoot_t / 0.35) + 2.0, Color(0.6, 1.0, 0.4, 0.5))
        "wisp":
            draw_circle(Vector2.ZERO, radius * 1.6, Color(base_color, 0.12 + 0.08 * sin(_fx_t * 6.0)))
        "boss":
            _draw_boss()


func _draw_affix() -> void:
    var pos := Vector2(radius + 6.0, -radius - 4.0)
    draw_circle(pos, 6.0, Color(0, 0, 0, 0.6))
    match affix:
        "regenerating":
            var c := Color(0.4, 1.0, 0.4)
            draw_line(pos + Vector2(-3.5, 0), pos + Vector2(3.5, 0), c, 2.0)
            draw_line(pos + Vector2(0, -3.5), pos + Vector2(0, 3.5), c, 2.0)
            if _since_hit >= 2.0 and hp < max_hp:
                draw_arc(Vector2.ZERO, radius + 7.0, _fx_t * 2.0, _fx_t * 2.0 + 1.5, 12, Color(c, 0.6), 2.0)
        "hasted":
            var c := Color(0.5, 0.9, 1.0)
            draw_line(pos + Vector2(-3, -3), pos + Vector2(0, 0), c, 2.0)
            draw_line(pos + Vector2(0, 0), pos + Vector2(-3, 3), c, 2.0)
            draw_line(pos + Vector2(1, -3), pos + Vector2(4, 0), c, 2.0)
            draw_line(pos + Vector2(4, 0), pos + Vector2(1, 3), c, 2.0)
            draw_arc(Vector2.ZERO, 150.0, 0.0, TAU, 48, Color(c, 0.12), 1.5)
        "trail":
            var el: int = immune_to if immune_to != Element.Kind.NONE else Element.Kind.OIL
            var c: Color = Element.COLORS[el]
            draw_circle(pos + Vector2(-2, 1), 2.5, c)
            draw_circle(pos + Vector2(2.5, -1.5), 1.8, c)
        "volatile":
            var c := Color(1.0, 0.45 + 0.3 * sin(_fx_t * 8.0), 0.2)
            draw_circle(pos, 3.5, c)
            draw_line(pos + Vector2(0, -3.5), pos + Vector2(2, -6), Color(1, 0.9, 0.5), 1.5)
        "sower":
            var c := Color(1.0, 0.35, 0.3)
            for k in 3:
                draw_circle(pos + Vector2.from_angle(TAU * float(k) / 3.0 - PI / 2.0) * 3.0, 1.8, c)
        "mortar":
            var c := Color(0.95, 0.65, 0.3)
            draw_arc(pos + Vector2(0, 2), 4.0, PI, TAU, 8, c, 2.0)
            draw_circle(pos + Vector2(0, -2.5), 1.8, c)
        "tether":
            var c := Color(1.0, 0.3, 0.45)
            draw_line(pos + Vector2(-4, 3), pos + Vector2(4, -3), c, 2.0)
            draw_circle(pos + Vector2(-4, 3), 1.6, c)
            draw_circle(pos + Vector2(4, -3), 1.6, c)


## The entrance animation per boss (BossShow.REVEAL is the moment it is there).
func _intro_sprite() -> void:
    if _sprite == null:
        return
    var el := _intro_len - emerge
    var rv := BossShow.REVEAL
    var s := _sprite_scale
    var pos := Vector2.ZERO
    var a := 1.0
    var col := base_color
    var sx := 1.0
    var sy := 1.0
    match boss_kind:
        "brute_king":
            # He drops from above and lands at the roar.
            var f := clampf(el / rv, 0.0, 1.0)
            pos.y = -440.0 * (1.0 - f * f)
            a = clampf(el / 0.2, 0.0, 1.0)
            var land := el - rv
            if land >= 0.0 and land < 0.35:
                var q := 1.0 - land / 0.35
                sx = 1.0 + 0.3 * q
                sy = 1.0 - 0.3 * q
        "hive_mother", "drowned_choir":
            # Out of the ground (the hive) or up out of the water (the choir).
            var f := clampf((el - 0.2) / (rv - 0.2), 0.0, 1.0)
            pos.y = (1.0 - f) * radius * 1.1
            s *= 0.35 + 0.65 * f
            a = f
        "storm_warden":
            # Nothing, then the strike, and he is there.
            a = 1.0 if el >= rv else 0.0
        "pyre_lord":
            # A cold, dark shape that ignites at the roar.
            a = clampf((el - 0.15) / 0.5, 0.0, 1.0)
            col = Color(0.14, 0.09, 0.08).lerp(base_color, clampf((el - rv) / 0.45, 0.0, 1.0))
        "void_herald":
            # It folds in out of nothing.
            a = clampf((el - 0.25) / (rv - 0.25), 0.0, 1.0)
            s *= 1.7 - 0.7 * a
    if el >= rv:
        var br := sin(_fx_t * 2.2)
        sx *= 1.0 - 0.025 * br
        sy *= 1.0 + 0.045 * br
    _intro_a = a
    _sprite.scale = Vector2(s * sx, s * sy)
    _sprite.position = pos
    _sprite.rotation = 0.0
    _sprite.modulate = Color(col, a)


## Phase 2 and 3: cracks across the body glowing in its colour (BossShow.accent), more and
## brighter in phase 3. Drawn on the Crisp layer, over the sprite.
func _draw_boss_cracks(cv: CanvasItem) -> void:
    var ac := BossShow.accent(boss_kind)
    var glow := 0.55 + 0.35 * sin(_fx_t * (6.0 if _phase >= 3 else 3.5))
    var R := radius
    var n := 3 if _phase == 2 else 6
    for k in n:
        var a0 := float(k) * 2.39996 + 0.4
        var pts := PackedVector2Array([
            Vector2.from_angle(a0) * R * 0.12,
            Vector2.from_angle(a0 + 0.35) * R * 0.5,
            Vector2.from_angle(a0 - 0.12) * R * 0.92])
        cv.draw_polyline(pts, Color(0.05, 0.02, 0.02, 0.85), 5.0)
        cv.draw_polyline(pts, Color(ac, glow), 2.0)


func _draw_boss() -> void:
    # Phase two: a red pulse around the body.
    if _phase >= 2:
        draw_arc(Vector2.ZERO, radius + 16.0, 0.0, TAU, 48, Color(1, 0.2, 0.15, 0.35 + 0.25 * sin(_fx_t * 6.0)), 3.0)
    # Telegraphed summons: a closing ring where each will appear.
    for s in _pending:
        var k := 1.0 - clampf(float(s["t"]) / float(s.get("warn", EMERGE_SECS)), 0.0, 1.0)
        draw_spawn_marker(self, to_local(s["pos"]), 10.0, k, _fx_t)
    match boss_kind:
        "brute_king":
            # A crown.
            var top := -radius - 10.0
            var pts := PackedVector2Array([Vector2(-10, top + 8), Vector2(-10, top), Vector2(-5, top + 4), Vector2(0, top - 2), Vector2(5, top + 4), Vector2(10, top), Vector2(10, top + 8)])
            draw_colored_polygon(pts, Color(1.0, 0.8, 0.3))
        "hive_mother":
            for k in 5:
                var a := float(k) * TAU / 5.0 + _fx_t * 0.3
                draw_circle(Vector2.RIGHT.rotated(a) * (radius + 6.0), 4.0, Color(0.7, 0.9, 0.4, 0.8))
            if _ring_warn > 0.0:
                var r := radius + 70.0 * (1.0 - _ring_warn / 0.6)
                draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(Element.COLORS[Element.Kind.POISON], 0.8), 3.0)
        "storm_warden":
            if states.is_empty():
                for k in 6:
                    var a0 := float(k) * TAU / 6.0 + _fx_t * 0.5
                    draw_arc(Vector2.ZERO, radius + 4.0, a0, a0 + 0.7, 6, Color(0.85, 0.85, 0.6, 0.9), 3.5)
            if _tele_warn > 0.0:
                var lp := to_local(_tele_pos)
                var c: Color = Element.COLORS[Element.Kind.SHOCK]
                draw_arc(lp, radius + 10.0, 0.0, TAU, 32, Color(c, 0.9), 2.5)
                for k in 4:
                    var a := randf() * TAU
                    var p := lp + Vector2.RIGHT.rotated(a) * radius
                    draw_line(p, p + Vector2.RIGHT.rotated(a + randf_range(-1.0, 1.0)) * 12.0, c, 2.0)
                draw_line(Vector2.ZERO, lp, Color(c, 0.25), 2.0)
            if _burst_left > 0:
                draw_circle(Vector2.ZERO, radius * 0.5, Color(Element.COLORS[Element.Kind.SHOCK], 0.35))
        "pyre_lord":
            for hz in _hazards:
                var lava := bool(hz.get("lava", false))
                draw_circle(to_local(hz["pos"]), float(hz.get("r", 55.0)), Color(1.0, 0.35 if lava else 0.35, 0.1, (0.28 if lava and float(hz.get("warn", 0.0)) <= 0.0 else 0.10) * clampf(float(hz["t"]), 0.0, 1.0)))
            var fk := 1.0
            if intro:
                fk = clampf((_intro_len - emerge - BossShow.REVEAL) / 0.5, 0.0, 1.0)
            if fk > 0.02:
                _draw_pixel_flame(Vector2(0, -radius * 0.5), radius * 1.6 * fk, radius * 2.2 * fk, 14 if _phase >= 2 else 10)
        "drowned_choir":
            # The great bell: a bronze bell over the body; it cracks in phase 3.
            var top := -radius * 1.55
            draw_set_transform(Vector2(0, top), 0.0, Vector2.ONE * (radius / 34.0))
            top = 0.0
            var bell := PackedVector2Array([Vector2(-8, top), Vector2(8, top), Vector2(16, top + 14), Vector2(22, top + 34), Vector2(30, top + 42), Vector2(-30, top + 42), Vector2(-22, top + 34), Vector2(-16, top + 14)])
            var tone := Color(0.62, 0.50, 0.30)
            if _phase >= 3 and _t3 < 0.5:
                tone = tone.lerp(Color(1.0, 0.95, 0.6), 1.0 - maxf(_t3, 0.0) / 0.5)
            draw_colored_polygon(bell, tone)
            var rim := bell.duplicate()
            rim.append(bell[0])
            draw_polyline(rim, Color(0.15, 0.12, 0.08), 2.0)
            draw_circle(Vector2(0, top + 44), 5.0, Color(0.35, 0.30, 0.2))
            if _phase >= 3:
                draw_polyline(PackedVector2Array([Vector2(-4, top + 4), Vector2(3, top + 16), Vector2(-5, top + 26), Vector2(4, top + 40)]), Color(0.1, 0.08, 0.05), 2.0)
            draw_set_transform_matrix(Transform2D.IDENTITY)
        "void_herald":
            var pull_r := 260.0 if _phase == 1 else 320.0
            var c: Color = Element.COLORS[Element.Kind.VOID]
            draw_arc(Vector2.ZERO, pull_r, 0.0, TAU, 64, Color(c, 0.18), 2.0)
            var r := pull_r * (1.0 - fmod(_fx_t * 0.5, 1.0))
            draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(c, 0.25), 1.5)
            if _spiral_left > 0.0 or _t1 < 0.6:
                for k in 3:
                    var a := _spiral_angle + float(k) * TAU / 3.0
                    draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(a) * (radius + 14.0), Color(c, 0.7), 3.0)


# --- Focus targeting (Core loop reset 7.2) ------------------------------------

## Key threats: the enemies a player must answer first (shooters, chargers, zoners).
const KEY_THREATS := ["spitter", "charger", "shaman", "bomber", "warden", "lobber", "zoner"]


func is_key_threat() -> bool:
    return kind_name in KEY_THREATS or affix in ["volatile", "barrage", "sower", "mortar", "tether"]


## Winding up an attack right now (charge telegraph, ring, teleport or gut-blast warning).
func winding_up() -> bool:
    return _mode == MODE_TELEGRAPH or _ring_warn > 0.0 or _tele_warn > 0.0 or _gut_warn > 0.0 \
            or _crouch_t > 0.0 or not _shells.is_empty() or _tether_state > 0


## Shots in flight toward this enemy (Focus skips it once they cover its health).
func pending_damage() -> float:
    if _game_now() > _pending_until:
        _pending_dmg = 0.0
    return _pending_dmg


func add_pending(amount: float, eta: float) -> void:
    var now := _game_now()
    if now > _pending_until:
        _pending_dmg = 0.0
    _pending_dmg += amount
    _pending_until = maxf(_pending_until, now + eta)


## Game seconds (physics frames), so fast-forwarded bot runs time the same as play.
static func _game_now() -> float:
    return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
