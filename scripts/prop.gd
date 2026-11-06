class_name Prop
extends StaticBody2D
## An environmental prop that reacts to every element: crates burn and break, oil barrels
## leak and blow, fountains boil, freeze, conduct and spray, braziers set things alight,
## crystals shatter into shards... Props sit in group "obstacles", so bullets, lobs and the
## floor's material layer (Materials._touch_obstacles) already reach them through
## `overlaps()` and `apply_element()`. Plain hits go through `take_damage()`.
##
## `apply_element(kind, potency, dir)` returns true when the element did something to the
## prop (a state, a reaction); Projectile then skips `take_damage`, so a stone or plain
## gun smashes a crate while a fire gun sets it alight instead.
##
## Props are children of a "Props" Node2D under the Room (see Props.dress). A broken prop
## emits `broke(pos, scrap)`, drops its scrap through the room and is remembered in the
## room's RoomData (meta "props_gone"), so it stays broken on re-entry.

signal broke(pos: Vector2, scrap: int)

const LAYER_OBSTACLES := 8   # Obstacle.LAYER_OBSTACLES: projectiles see it, bodies do not
const DROP_SCRAP_DIRECTLY := true   # _break() calls room._drop_scrap itself
const MAX_ENEMIES_FOR_SUMMON := 45

## tile: sheet coord; size: collision / hit rect; hp: INF = never breaks from damage;
## solid: on the walls layer (bodies path around it); scrap: [min, max] when broken.
const SPECS := {
    "crate": { "tile": Vector2i(23, 2), "tint": Color(0.72, 0.52, 0.32), "scale": 2.0, "size": Vector2(28, 28), "hp": 3.0, "solid": true, "scrap": [1, 3] },
    "barrel": { "tile": Vector2i(13, 13), "tint": Color(0.55, 0.38, 0.26), "scale": 2.0, "size": Vector2(24, 28), "hp": 6.0, "solid": true, "scrap": [1, 2] },
    "fountain": { "tile": Vector2i(8, 13), "tint": Color(0.62, 0.68, 0.76), "scale": 2.8, "size": Vector2(40, 36), "hp": INF, "solid": true, "scrap": [0, 0] },
    "brazier": { "tile": Vector2i(14, 10), "tint": Color(0.70, 0.55, 0.42), "scale": 2.2, "size": Vector2(26, 26), "hp": INF, "solid": true, "scrap": [0, 0] },
    "ice_crystal": { "tile": Vector2i(32, 10), "tint": Color(0.70, 0.92, 1.00), "scale": 2.2, "size": Vector2(24, 30), "hp": 4.0, "solid": true, "scrap": [0, 1] },
    "poison_pot": { "tile": Vector2i(34, 14), "tint": Color(0.50, 0.80, 0.35), "scale": 1.8, "size": Vector2(20, 22), "hp": 1.0, "solid": false, "scrap": [0, 1] },
    "acid_vat": { "tile": Vector2i(5, 14), "tint": Color(0.78, 0.95, 0.32), "scale": 2.4, "size": Vector2(32, 30), "hp": 2.0, "solid": true, "scrap": [1, 1] },
    "lightning_rod": { "tile": Vector2i(5, 15), "tint": Color(0.72, 0.72, 0.80), "scale": 2.4, "size": Vector2(16, 30), "hp": INF, "solid": true, "scrap": [0, 0] },
    "wind_chime": { "tile": Vector2i(44, 8), "tint": Color(0.75, 0.90, 0.85), "scale": 2.0, "size": Vector2(18, 20), "hp": 4.0, "solid": false, "scrap": [1, 1] },
    "blood_altar": { "tile": Vector2i(4, 11), "tint": Color(0.72, 0.36, 0.36), "scale": 2.8, "size": Vector2(44, 32), "hp": INF, "solid": true, "scrap": [0, 0] },
    "stone_pillar": { "tile": Vector2i(3, 12), "tint": Color(0.60, 0.56, 0.50), "scale": 2.6, "size": Vector2(32, 36), "hp": INF, "solid": true, "scrap": [2, 2] },
}

const C_FIRE := Color(1.00, 0.45, 0.15)
const FUSE_SECS := 0.6
const BLAST_RADIUS := 150.0
const C_STEAM := Color(0.90, 0.95, 1.00)

var kind := "crate"
var hp := 3.0
var max_hp := 3.0
var size := Vector2(28, 28)       # read by Materials._touch_obstacles too
var solid := true
var blocks_shots := false         # pillars stop every shot, piercing or not
var slot := -1                    # index in Props.dress, for "stays broken" bookkeeping
var room: Node2D = null
## Timed conditions: "wet", "oiled", "burning", "frozen", "charged", "corroded" -> seconds.
var states: Dictionary = {}
## Lasting condition: "" / "drained" / "cracked" / "bent" / "silenced" / "tipped".
var mode := ""
var off_time := 0.0               # brazier out / fountain frozen over: seconds until it works

var _timers: Dictionary = {}      # kind effects: "dissolve", "erode", "contaminated", "blessed", "fouled"
var _cd: Dictionary = {}          # per-effect cooldowns
var _contaminant: int = Element.Kind.POISON
var _gone := false
var _sprite: Sprite2D
var _over: Node2D
var _flash := 0.0
var _char := 0.0                  # 0..1 scorched look
var _tick := 0.0
var _fx_t := 0.0
var _leaks := 0
var _summons := 0
var _wind := Vector2.RIGHT
var _hum := 0.0


func _init(p_kind: String = "crate") -> void:
    kind = p_kind if SPECS.has(p_kind) else "crate"
    var spec: Dictionary = SPECS[kind]
    size = spec["size"]
    hp = float(spec["hp"])
    max_hp = hp
    solid = bool(spec["solid"])
    blocks_shots = kind == "stone_pillar"
    name = "Prop_" + kind


func _ready() -> void:
    add_to_group("obstacles")
    add_to_group("props")
    collision_layer = (Player.LAYER_WALLS if solid else 0) | LAYER_OBSTACLES
    collision_mask = 0
    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = size
    shape.shape = rect
    add_child(shape)
    var spec: Dictionary = SPECS[kind]
    _sprite = Art.sprite(spec["tile"], float(spec["scale"]), spec["tint"])
    if kind == "stone_pillar" or kind == "lightning_rod":
        _sprite.position = Vector2(0, -8)
    add_child(_sprite)
    _over = Node2D.new()
    _over.name = "Overlay"
    _over.z_index = 1
    _over.draw.connect(_draw_over)
    add_child(_over)
    _tick = randf()
    if room == null:
        var p := get_parent()
        if p != null and p.get_parent() is Node2D:
            room = p.get_parent() as Node2D


# --- Interface shared with Obstacle -----------------------------------------


## Circle (point + radius) against the prop's rect.
func overlaps(point: Vector2, margin: float) -> bool:
    if _gone:
        return false
    var local := to_local(point)
    var half := size / 2.0
    var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
    return closest.distance_squared_to(local) <= margin * margin


## An element lands on the prop. `dir` is the travel direction of whatever brought it
## (wind and spills follow it); without one it points away from the nearest player.
## Returns true when the element did something, false when it is just a hit.
func apply_element(element: int, _potency: float = 1.0, dir: Vector2 = Vector2.ZERO) -> bool:
    if _gone or element == Element.Kind.NONE:
        return false
    _wind = dir.normalized() if dir != Vector2.ZERO else _away_from_players()
    var used := false
    match kind:
        "crate":
            used = _crate(element)
        "barrel":
            used = _barrel(element)
        "fountain":
            used = _fountain(element)
        "brazier":
            used = _brazier(element)
        "ice_crystal":
            used = _crystal(element)
        "poison_pot":
            used = _pot(element)
        "acid_vat":
            used = _vat(element)
        "lightning_rod":
            used = _rod(element)
        "wind_chime":
            used = _chime(element)
        "blood_altar":
            used = _altar(element)
        "stone_pillar":
            used = _pillar(element)
    if used:
        _flash = 0.1
        Telemetry.prop(self, element)
    return used


## A plain hit (no element, or one that does nothing here). Crates, barrels, pots, vats,
## chimes and crystals take it; fountains, braziers, rods, altars and pillars shrug.
func take_damage(_amount: float) -> void:
    if _gone:
        return
    _flash = 0.12
    match kind:
        "crate":
            if states.has("frozen"):
                _fxc("shards", [global_position, 8, 22.0, Element.Kind.ICE])
                Sfx.play("react_freeze", -6.0)
                _break(_roll_scrap())
                return
            if states.has("burning"):
                return
            hp -= 1.0
            _chips(Element.Kind.OIL)
            Sfx.play("hit", -6.0)
            if hp <= 0.0:
                _break(_roll_scrap())
        "barrel":
            if states.has("frozen"):
                _chips(Element.Kind.ICE)
                return
            _leak(false)
        "ice_crystal":
            hp -= 0.25
            _chips(Element.Kind.ICE)
            if hp <= 0.0:
                _shatter(false)
        "poison_pot":
            _pot_break(Element.Kind.NONE)
        "acid_vat":
            hp -= 1.0
            _chips(Element.Kind.ACID)
            if hp <= 0.0:
                _vat_break()
        "wind_chime":
            hp -= 1.0
            _chips(Element.Kind.GALE)
            if hp <= 0.0:
                _break(_roll_scrap())
        _:
            _chips(Element.Kind.STONE)


func has_state(state: String) -> bool:
    return states.has(state)


func is_lit() -> bool:
    return kind == "brazier" and off_time <= 0.0


# --- Per kind ----------------------------------------------------------------


func _crate(el: int) -> bool:
    match el:
        Element.Kind.FIRE:
            if states.has("frozen"):
                states.erase("frozen")
                _steam_puff(0.6)
                return true
            if states.has("wet"):
                states["wet"] = float(states["wet"]) - 3.0   # fire dries it out, slowly
                _steam_puff(0.5)
                return true
            if not states.has("burning"):
                _ignite(2.2 if states.has("oiled") else 3.0)
            return true
        Element.Kind.SHOCK:
            if states.has("oiled") and not states.has("wet") and not states.has("burning"):
                _ignite(2.2)
                return true
            return false
        Element.Kind.OIL:
            _set_state("oiled", 20.0)
            return true
        Element.Kind.WET:
            if states.has("burning"):
                states.erase("burning")
                _steam_puff(0.8)
            _set_state("wet", 10.0)
            return true
        Element.Kind.ICE:
            if states.has("burning"):
                states.erase("burning")
                _steam_puff(0.8)
                return true
            _set_state("frozen", 12.0 if states.has("wet") else 8.0)
            return true
        Element.Kind.ACID:
            if not _timers.has("dissolve"):
                _timers["dissolve"] = 2.0
            _set_state("corroded", 2.0)
            return true
    return false


func _barrel(el: int) -> bool:
    match el:
        Element.Kind.FIRE:
            if states.has("frozen"):
                states.erase("frozen")
                _steam_puff(0.6)
                return true
            _light_fuse()
            return true
        Element.Kind.SHOCK:
            if states.has("frozen"):
                _chips(Element.Kind.SHOCK)
                return true
            _light_fuse()
            return true
        Element.Kind.ICE:
            _set_state("frozen", 14.0)
            return true
        Element.Kind.ACID:
            if states.has("frozen") or _timers.has("dissolve"):
                return true
            _set_state("corroded", 1.5)
            _timers["dissolve"] = 1.5
            _leak(true)
            return true
        Element.Kind.OIL:
            _set_state("oiled", 10.0)
            return true
        Element.Kind.WET:
            _set_state("wet", 8.0)
            return false   # still a hit: it leaks
    return false


func _fountain(el: int) -> bool:
    var gp := global_position
    if mode == "drained":
        return true
    var mats := _mats()
    match el:
        Element.Kind.FIRE:
            if off_time > 0.0:
                off_time = 0.0
                _cd["freeze"] = 5.0
                _steam_puff(0.8)
                return true
            if not _ready_cd("boil", 4.0):
                return true
            # Boils: a steam cloud off the pool that scalds everything near.
            Elements.reaction_fired.emit("Steam", gp, Element.COLORS[Element.Kind.WET])
            if mats != null:
                mats.stamp(Element.Kind.WET, gp, 90.0, 200)
                mats.stamp(Element.Kind.FIRE, gp, 90.0, 200)
            _fxc("smoke", [gp + Vector2(0, -10), 24, 60.0, Fx.PAL_STEAM])
            for e in _enemies_within(120.0):
                e.take_damage(10.0, C_STEAM, true, null)
                if _alive(e):
                    e.apply_slow(0.5, 2.5)
                    e.apply_element(Element.Kind.WET, 1.0)
        Element.Kind.ICE:
            if off_time > 0.0 or not _ready_cd("freeze", 12.0):
                return true
            off_time = 8.0
            _set_state("frozen", 8.0)
            Elements.reaction_fired.emit("Deep Freeze", gp, Element.COLORS[Element.Kind.ICE])
            if mats != null:
                mats.stamp(Element.Kind.WET, gp, 64.0, 200)
                mats.stamp(Element.Kind.ICE, gp, 80.0, 220)
        Element.Kind.SHOCK:
            if off_time > 0.0 or not _ready_cd("shock", 1.5):
                return true
            Elements.reaction_fired.emit("Chain Lightning", gp, Element.COLORS[Element.Kind.SHOCK])
            _set_state("charged", 1.0)
            if mats != null:
                mats.stamp(Element.Kind.WET, gp, 48.0, 160)
                mats.stamp(Element.Kind.SHOCK, gp, 60.0, 200)
            for e in _enemies_within(160.0):
                Elements.lightning_arc.emit(gp + Vector2(0, -10), e.global_position)
                e.take_damage(12.0, Element.COLORS[Element.Kind.SHOCK], true, null)
                if _alive(e):
                    e.apply_element(Element.Kind.SHOCK, 1.0)
        Element.Kind.OIL:
            if not _ready_cd("oil", 2.0):
                return true
            _set_state("oiled", 6.0)
            if mats != null:
                mats.stamp(Element.Kind.OIL, gp, 80.0, 180)
            _fxc("pixels", [Element.Kind.OIL, gp, 10, 90.0, 12.0])
        Element.Kind.POISON, Element.Kind.ACID:
            _contaminant = el
            _timers["contaminated"] = 6.0
            Elements.reaction_fired.emit("Contamination" if el == Element.Kind.POISON else "Caustic Splash", gp, Element.COLORS[el])
        Element.Kind.GALE:
            if off_time > 0.0 or not _ready_cd("spray", 1.0):
                return true
            _spray(_wind)
        Element.Kind.VOID:
            mode = "drained"
            _timers.erase("contaminated")
            _timers.erase("blessed")
            _timers.erase("fouled")
            Elements.reaction_fired.emit("Whirlpool", gp, Element.COLORS[Element.Kind.VOID])
            _fxc("spiral", [gp, 60.0, 24, Element.Kind.VOID])
        Element.Kind.STONE:
            if mode != "cracked":
                mode = "cracked"
                _chips(Element.Kind.STONE)
                if mats != null:
                    mats.stamp(Element.Kind.WET, gp, 40.0, 140)
        Element.Kind.HOLY:
            _timers["blessed"] = 6.0
            _fxc("rise", [gp, 16, 30.0])
        Element.Kind.BLOOD:
            _timers["fouled"] = 10.0
            if mats != null:
                mats.stamp(Element.Kind.BLOOD, gp, 70.0, 200)
    return true


func _brazier(el: int) -> bool:
    var gp := global_position
    var lit := off_time <= 0.0
    var mats := _mats()
    match el:
        Element.Kind.FIRE:
            if not lit and not states.has("wet"):
                off_time = 0.0
                _fxc("signature", [Element.Kind.FIRE, gp, 20.0, 0.8, Vector2.ZERO])
        Element.Kind.WET:
            _set_state("wet", 6.0)
            if lit:
                off_time = 20.0
                Elements.reaction_fired.emit("Steam", gp, C_STEAM)
                _steam_puff(1.0)
        Element.Kind.OIL:
            if lit and _ready_cd("flare", 3.0):
                Elements.reaction_fired.emit("Inferno", gp, C_FIRE)
                Elements.nova.emit(gp, 110.0, Color(C_FIRE, 0.6))
                if mats != null:
                    mats.ignite(gp, 110.0)
                    mats.ignite(gp, 30.0, true)
                for e in _enemies_within(110.0):
                    e.take_damage(8.0, C_FIRE, true, null)
                    if _alive(e):
                        e.add_burn(5.0, 3.0)
                _ignite_props_near(110.0)
        Element.Kind.GALE:
            if lit and _ready_cd("gale", 1.2):
                _ember_line(_wind, 240.0, false)
        Element.Kind.ICE:
            if lit:
                off_time = 20.0
                _set_state("frozen", 5.0)
                _steam_puff(0.5)
                _fxc("signature", [Element.Kind.ICE, gp, 24.0, 0.8, Vector2.ZERO])
        Element.Kind.STONE:
            if mode != "tipped":
                mode = "tipped"
                _sprite.rotation = PI * 0.5 if _wind.x >= 0.0 else -PI * 0.5
                if lit:
                    _ember_line(_wind, 90.0, true)
                off_time = 9999.0   # out until someone relights it with fire
        Element.Kind.VOID:
            if lit:
                off_time = 20.0
                _fxc("spiral", [gp, 40.0, 16, Element.Kind.VOID])
    return true


func _crystal(el: int) -> bool:
    var gp := global_position
    match el:
        Element.Kind.SHOCK:
            Elements.reaction_fired.emit("Cryoshock", gp, Element.COLORS[Element.Kind.ICE])
            _shatter(true)
            return true
        Element.Kind.FIRE:
            # Melts into a puddle.
            var mats := _mats()
            if mats != null:
                mats.stamp(Element.Kind.WET, gp, 70.0, 220)
            _steam_puff(0.7)
            _break(0)
            return true
        Element.Kind.STONE:
            hp -= 1.0
            _chips(Element.Kind.ICE)
            if hp <= 0.0:
                _shatter(false)
            return true
        Element.Kind.GALE:
            if _ready_cd("sing", 1.5):
                _hum = 1.2
                Sfx.play("nova_frost", -14.0)
                _fxc("linger", [gp, 40.0, 10, Element.Kind.ICE, true])
            return true
        Element.Kind.ACID:
            if not _timers.has("dissolve"):
                _timers["dissolve"] = 2.0
            _set_state("corroded", 2.0)
            return true
        Element.Kind.ICE, Element.Kind.WET:
            hp = minf(max_hp, hp + 0.5)
            return true
    return false


func _pot(el: int) -> bool:
    _pot_break(el)
    return true


func _vat(el: int) -> bool:
    var gp := global_position
    match el:
        Element.Kind.SHOCK:
            Elements.reaction_fired.emit("Electrolysis", gp, Element.COLORS[Element.Kind.ACID])
            Elements.nova.emit(gp, 90.0, Color(Element.COLORS[Element.Kind.SHOCK], 0.6))
            for e in _enemies_within(90.0):
                Elements.lightning_arc.emit(gp, e.global_position)
                e.take_damage(10.0, Element.COLORS[Element.Kind.SHOCK], true, null)
                if _alive(e):
                    e.corrode(6.0)
                    e.apply_element(Element.Kind.SHOCK, 1.0)
            _vat_break()
            return true
        Element.Kind.FIRE:
            Elements.reaction_fired.emit("Chemical Fire", gp, C_FIRE)
            Cloud.spawn(_world(), gp, Element.Kind.FIRE, 100.0, 5.0, 3.0, null)
            for e in _enemies_within(100.0):
                e.add_burn(6.0, 5.0)
                e.corrode(6.0)
            _vat_break()
            return true
        Element.Kind.STONE:
            # Tipped over: the acid runs out in a line.
            var mats := _mats()
            if mats != null:
                for i in 5:
                    mats.stamp(Element.Kind.ACID, gp + _wind * (20.0 + 26.0 * float(i)), 26.0, 200)
            _fxc("pixels", [Element.Kind.ACID, gp + _wind * 30.0, 14, 120.0, 10.0])
            _break(_roll_scrap())
            return true
        Element.Kind.ACID:
            return true
    return false


func _rod(el: int) -> bool:
    match el:
        Element.Kind.SHOCK:
            if mode != "bent" and _ready_cd("arc", 0.6):
                _arc_out()
        Element.Kind.WET:
            _set_state("wet", 10.0)
        Element.Kind.STONE:
            if mode != "bent":
                mode = "bent"
                _sprite.rotation = 0.5 if _wind.x >= 0.0 else -0.5
                _chips(Element.Kind.STONE)
    return true


func _chime(el: int) -> bool:
    match el:
        Element.Kind.GALE:
            if mode != "silenced" and _ready_cd("gust", 1.0):
                _gust()
            return true
        Element.Kind.VOID:
            if mode != "silenced":
                mode = "silenced"
                _fxc("spiral", [global_position, 30.0, 12, Element.Kind.VOID])
            return true
    return false


func _altar(el: int) -> bool:
    var gp := global_position
    match el:
        Element.Kind.BLOOD:
            if _ready_cd("heal", 10.0):
                for p in _players_within(120.0):
                    p.heal(15.0)
                    _fxc("rise", [p.global_position, 10, 12.0])
                Elements.nova.emit(gp, 120.0, Color(Element.COLORS[Element.Kind.BLOOD], 0.5))
                _fxc("signature", [Element.Kind.BLOOD, gp, 40.0, 1.0, Vector2.ZERO])
        Element.Kind.HOLY:
            if _ready_cd("purge", 4.0):
                Elements.nova.emit(gp, 200.0, Color(Element.COLORS[Element.Kind.HOLY], 0.6))
                _fxc("signature", [Element.Kind.HOLY, gp, 60.0, 1.2, Vector2.ZERO])
                for e in _enemies_within(200.0):
                    e.purge_states()
                    e.burn_time = 0.0
                    e.poison_time = 0.0
                    e.bleed_time = 0.0
                    e.corroded_time = 0.0
                    e.stun(1.0)
        Element.Kind.VOID:
            if _summons < 3 and _ready_cd("summon", 12.0):
                _summon_swarmers(2)
    return true


func _pillar(el: int) -> bool:
    var gp := global_position
    match el:
        Element.Kind.VOID:
            _fxc("spiral", [gp, 50.0, 20, Element.Kind.VOID])
            _crumble(2)
        Element.Kind.ACID:
            _set_state("corroded", 2.0)
            if _timers.has("erode"):
                _timers["erode"] = maxf(0.5, float(_timers["erode"]) - 0.5)
            else:
                _timers["erode"] = 8.0
        Element.Kind.STONE:
            if _timers.has("erode"):
                _timers["erode"] = float(_timers["erode"]) + 1.5
            _fxc("signature", [Element.Kind.STONE, gp, 20.0, 0.5, Vector2.ZERO])
    return true


# --- Effects -----------------------------------------------------------------


func _ignite(secs: float) -> void:
    _set_state("burning", secs)
    states.erase("frozen")
    Sfx.play("react_ignition", -8.0)
    _fxc("signature", [Element.Kind.FIRE, global_position, 20.0, 0.8, Vector2.ZERO])


## Oil runs out of the barrel: a slick on the floor and an oil cloud over it.
func _leak(big: bool) -> void:
    if not _ready_cd("leak", 0.2) and not big:
        return
    var gp := global_position
    var mats := _mats()
    var at := gp + _wind * 14.0
    if mats != null:
        mats.stamp(Element.Kind.OIL, at, 64.0 if big else 34.0, 220 if big else 140)
    Cloud.spawn(_world(), at, Element.Kind.OIL, 90.0 if big else 60.0, 6.0, 1.0, null)
    _fxc("pixels", [Element.Kind.OIL, at, 10 if big else 5, 90.0, 6.0])
    _set_state("oiled", 6.0)
    _leaks += 3 if big else 1
    if _leaks >= 6 and not _timers.has("dissolve"):
        _break(1)   # run dry


## A lit barrel bursts after FUSE_SECS, never on the frame it is hit: it flashes faster
## and faster and a ring grows out to the blast radius, so the blast is never a surprise
## (two player deaths in the 2026-11-06 telemetry ended on an unseen barrel). Chained
## barrels each light their own fuse, so a row goes off as a quick ripple.
func _light_fuse() -> void:
    if _gone or _timers.has("fuse"):
        return
    _timers["fuse"] = FUSE_SECS
    Crisp.attach(self, _draw_fuse_ring, 4)   # above every particle; goes with the barrel
    Sfx.play_at("tick", global_position, 2.0)
    Sfx.play_at("react_ignition", global_position, -4.0)


## Barrel blast: a fire nova, the floor alight, damage around, chains into other props.
func _explode() -> void:
    if _gone:
        return
    var gp := global_position
    _gone = true   # nothing re-enters while the blast runs
    Elements.reaction_fired.emit("Inferno", gp, C_FIRE)
    Elements.nova.emit(gp, 150.0, Color(C_FIRE, 0.7))
    Sfx.play("nova_fire")
    var mats := _mats()
    if mats != null:
        mats.stamp(Element.Kind.OIL, gp, 60.0, 180)
        mats.ignite(gp, 150.0, true)
    for e in _enemies_within(150.0):
        e.take_damage(25.0, C_FIRE, true, null)
        if e.body != null and e.body.has_parts():
            # A barrel going off against a boss is fuel: a fusion's worth on the part nearest.
            e.body.blast("Barrel Blast", gp, 3, 0.02)
        if _alive(e):
            e.add_burn(5.0, 3.0)
            e.apply_element(Element.Kind.FIRE, 1.0)
    for p in _players_within(BLAST_RADIUS):
        Telemetry.hurt_hint = "prop:" + kind
        p.take_damage(15.0, null, gp)
    _fxc("signature", [Element.Kind.FIRE, gp, 80.0, 1.6, Vector2.ZERO])
    _fxc("smoke", [gp, 18, 40.0, Fx.PAL_SMOKE])
    var scene := get_tree().current_scene
    if scene != null and scene.has_method("shake"):
        scene.shake(9.0)
    for other in _props_within(150.0):
        var away := (other.global_position - gp).normalized()
        other.call_deferred("apply_element", Element.Kind.FIRE, 1.0, away)
        other.call_deferred("take_damage", 25.0)
    _gone = false
    _break(_roll_scrap())


func _steam_puff(strength: float) -> void:
    _fxc("smoke", [global_position + Vector2(0, -8), int(10.0 * strength) + 4, 20.0 * strength + 6.0, Fx.PAL_STEAM])
    Sfx.play("react_steam", -10.0)


## Water sprayed 200 px downwind in a widening cone; enemies in it soaked and shoved.
func _spray(dir: Vector2) -> void:
    var gp := global_position
    Elements.reaction_fired.emit("Monsoon", gp, Element.COLORS[Element.Kind.GALE])
    var mats := _mats()
    for i in range(1, 7):
        var p := gp + dir * (33.0 * float(i))
        if mats != null:
            mats.stamp(Element.Kind.WET, p, 14.0 + 5.0 * float(i), 140)
        _fxc("pixels", [Element.Kind.WET, p, 4, 120.0, 6.0 + 3.0 * float(i)])
    for e in _enemies_within(200.0):
        var to := e.global_position - gp
        if to.length() < 1.0 or absf(dir.angle_to(to)) < 0.5:
            e.apply_element(Element.Kind.WET, 1.0)
            if _alive(e):
                e.shove(dir * 260.0)


## Embers blown along a line: oil on the floor catches, enemies on it burn.
## `spill` (tipped brazier) lays real fire on bare floor instead.
func _ember_line(dir: Vector2, length: float, spill: bool) -> void:
    var gp := global_position
    var mats := _mats()
    var steps := int(length / 30.0)
    for i in range(1, steps + 1):
        var p := gp + dir * (30.0 * float(i))
        if mats != null:
            mats.ignite(p, 22.0, spill)
        for n in 2:
            _fxc("ember", [p + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))])
    for e in _enemies_within(length + 20.0):
        var rel := e.global_position - gp
        var along := rel.dot(dir)
        if along < 0.0 or along > length:
            continue
        if absf(rel.dot(dir.orthogonal())) <= 28.0 + e.radius:
            e.add_burn(5.0, 3.0)
            if _alive(e):
                e.apply_element(Element.Kind.FIRE, 0.8)
    for other in _props_within(length + 20.0):
        var rel2 := other.global_position - gp
        var along2 := rel2.dot(dir)
        if along2 > 0.0 and along2 <= length and absf(rel2.dot(dir.orthogonal())) <= 32.0:
            other.call_deferred("apply_element", Element.Kind.FIRE, 0.8, dir)


func _ignite_props_near(r: float) -> void:
    for other in _props_within(r):
        if other.states.has("oiled") or other.kind == "barrel":
            other.call_deferred("apply_element", Element.Kind.FIRE, 1.0, (other.global_position - global_position).normalized())


## Ice crystal breaks: six freezing shards (shock), or a cold burst (chipped apart).
func _shatter(shoot: bool) -> void:
    var gp := global_position
    _fxc("shards", [gp, 8, 26.0, Element.Kind.ICE])
    Sfx.play("react_freeze", -4.0)
    if shoot and room != null:
        var base := randf() * TAU
        for i in 6:
            var s := Projectile.new()
            s.velocity = Vector2.RIGHT.rotated(base + TAU * float(i) / 6.0) * 460.0
            s.damage = 6.0
            s.element = Element.Kind.ICE
            s.potency = 1.5
            s.lifetime = 0.45
            s.radius = 3.0
            s.color = Element.COLORS[Element.Kind.ICE]
            s.shooter = null
            s.position = room.to_local(gp)
            room.add_child.call_deferred(s)
    else:
        for e in _enemies_within(110.0):
            e.apply_element(Element.Kind.ICE, 1.2)
    _break(_roll_scrap())


func _pot_break(el: int) -> void:
    if _gone:
        return
    var gp := global_position
    var w := _world()
    var mats := _mats()
    match el:
        Element.Kind.FIRE:
            Elements.reaction_fired.emit("Noxious Flame", gp, C_FIRE)
            for e in _enemies_within(110.0):
                e.add_burn(6.0, 3.0)
                if _alive(e):
                    e.add_poison(4.0, 5.0)
            Cloud.spawn(w, gp, Element.Kind.POISON, 110.0, 4.0, 2.0, null)
            if mats != null:
                mats.ignite(gp, 40.0, true)
        Element.Kind.WET:
            Elements.reaction_fired.emit("Contamination", gp, Element.COLORS[Element.Kind.POISON])
            if mats != null:
                mats.stamp(Element.Kind.WET, gp, 70.0, 200)
                mats.stamp(Element.Kind.POISON, gp, 70.0, 160)
            for e in _enemies_within(140.0):
                e.apply_element(Element.Kind.POISON, 1.0)
        Element.Kind.GALE:
            Elements.reaction_fired.emit("Plague Wind", gp, Element.COLORS[Element.Kind.POISON])
            Cloud.spawn(w, gp + _wind * 60.0, Element.Kind.POISON, 170.0, 5.0, 2.0, null)
            for e in _enemies_within(220.0):
                e.apply_element(Element.Kind.POISON, 1.0)
        _:
            Cloud.spawn(w, gp, Element.Kind.POISON, 90.0, 5.0, 2.0, null)
            if el != Element.Kind.NONE:
                Cloud.spawn(w, gp, el, 60.0, 3.0, 1.0, null)   # reacts with the gas if it can
    _fxc("signature", [Element.Kind.POISON, gp, 30.0, 1.0, Vector2.ZERO])
    _fxc("shards", [gp, 6, 14.0, Element.Kind.STONE])
    Sfx.play("hit", -4.0)
    _break(_roll_scrap())


func _vat_break() -> void:
    var mats := _mats()
    if mats != null:
        mats.stamp(Element.Kind.ACID, global_position, 64.0, 220)
    _fxc("signature", [Element.Kind.ACID, global_position, 40.0, 1.0, Vector2.ZERO])
    _break(_roll_scrap())


## Lightning rod: arcs to every enemy within 220 (300 when wet or standing in water).
func _arc_out() -> void:
    var gp := global_position
    var top := gp + Vector2(0, -size.y * 0.6)
    var reach := 220.0
    var mats := _mats()
    if states.has("wet"):
        reach = 300.0
    elif mats != null:
        var m := mats.material_at(gp + Vector2(0, size.y * 0.5 + 4.0))
        if m == Materials.WATER or m == Materials.CHARGED:
            reach = 300.0
    _set_state("charged", 0.6)
    Sfx.play("react_chain", -4.0)
    Elements.nova.emit(gp, reach, Color(Element.COLORS[Element.Kind.SHOCK], 0.35))
    for e in _enemies_within(reach):
        Elements.lightning_arc.emit(top, e.global_position)
        _fxc("signature", [Element.Kind.SHOCK, e.global_position, 16.0, 0.6, Vector2.ZERO])
        e.take_damage(8.0, Element.COLORS[Element.Kind.SHOCK], true, null)
        if _alive(e):
            e.apply_element(Element.Kind.SHOCK, 1.0)


## Wind chime: a push nova on enemies, and every cloud nearby spreads out.
func _gust() -> void:
    var gp := global_position
    _hum = 1.0
    Elements.nova.emit(gp, 180.0, Color(Element.COLORS[Element.Kind.GALE], 0.55))
    _fxc("signature", [Element.Kind.GALE, gp, 60.0, 1.2, _wind])
    Sfx.play("nova_frost", -10.0)
    for e in _enemies_within(180.0):
        var away := (e.global_position - gp).normalized()
        if away == Vector2.ZERO:
            away = _wind
        if e.has_method("shove"):
            e.shove(away * 420.0)
        else:
            e.global_position += away * 40.0
    for c in get_tree().get_nodes_in_group("clouds"):
        if not is_instance_valid(c) or c.is_queued_for_deletion() or not c is Cloud:
            continue
        var cl := c as Cloud
        var d := cl.global_position - gp
        if d.length() > 220.0 + cl.radius:
            continue
        var push := d.normalized() if d.length() > 1.0 else _wind
        cl.global_position += push * 50.0
        cl.radius = minf(cl.radius * 1.3, 220.0)
    var mats := _mats()
    if mats != null:
        mats.stamp(Element.Kind.GALE, gp, 120.0, 100)


func _summon_swarmers(n: int) -> void:
    if room == null or get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES_FOR_SUMMON:
        return
    var holder := room.get_node_or_null("Enemies")
    if holder == null or not holder is Node2D:
        return
    var gp := global_position
    Elements.nova.emit(gp, 70.0, Color(Element.COLORS[Element.Kind.VOID], 0.6))
    _fxc("spiral", [gp, 60.0, 20, Element.Kind.VOID])
    _summons += 1
    for i in n:
        var e := Enemy.new()
        e.configure("swarmer", 4)
        var off := Vector2.RIGHT.rotated(randf() * TAU) * (size.length() * 0.5 + 18.0)
        e.position = (holder as Node2D).to_local(gp + off)
        if room.has_method("_on_enemy_died"):
            e.died.connect(Callable(room, "_on_enemy_died"))
        holder.add_child.call_deferred(e)


func _crumble(scrap: int) -> void:
    _fxc("shards", [global_position, 10, 22.0, Element.Kind.STONE])
    _fxc("smoke", [global_position, 10, 24.0, Fx.PAL_SMOKE])
    Sfx.play("die_elite", -6.0)
    _break(scrap)


func _chips(pal: int) -> void:
    _fxc("pixels", [pal, global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-8.0, 4.0)), 4, 70.0, 4.0])


## Gone for good: debris, scrap, the signal, and remembered as broken in the room data.
func _break(scrap: int) -> void:
    if _gone:
        return
    _gone = true
    var gp := global_position
    remove_from_group("obstacles")
    remove_from_group("props")
    match kind:
        "crate":
            _fxc("shards", [gp, 7, 20.0, Element.Kind.OIL])   # planks
            _fxc("smoke", [gp, 6, 14.0, Fx.PAL_SMOKE])
            Sfx.play("die", -4.0)
        "barrel":
            _fxc("shards", [gp, 6, 18.0, Element.Kind.OIL])
        "ice_crystal":
            _fxc("pixels", [Element.Kind.ICE, gp, 12, 90.0, 8.0])
        "acid_vat":
            _fxc("shards", [gp, 6, 16.0, Element.Kind.ACID])
        "wind_chime":
            _fxc("shards", [gp, 5, 14.0, Element.Kind.GALE])
    _remember_gone()
    broke.emit(gp, scrap)
    if DROP_SCRAP_DIRECTLY and scrap > 0 and room != null and room.has_method("_drop_scrap"):
        room.call_deferred("_drop_scrap", gp, scrap, scrap)
    queue_free()


func _remember_gone() -> void:
    if slot < 0 or room == null or not "data" in room:
        return
    var d: Variant = room.get("data")
    if not d is Object or d == null:
        return
    var obj := d as Object
    var gone: Array = obj.get_meta("props_gone", [])
    if not gone.has(slot):
        gone.append(slot)
    obj.set_meta("props_gone", gone)


# --- Ticking -------------------------------------------------------------------


func _process(delta: float) -> void:
    if _gone:
        return
    _flash = maxf(0.0, _flash - delta)
    _hum = maxf(0.0, _hum - delta)
    off_time = maxf(0.0, off_time - delta)
    for k in _cd.keys():
        _cd[k] = float(_cd[k]) - delta
        if float(_cd[k]) <= 0.0:
            _cd.erase(k)
    for k in states.keys():
        states[k] = float(states[k]) - delta
        if float(states[k]) <= 0.0:
            states.erase(k)
            _state_ended(String(k))
            if _gone:
                return
    for k in _timers.keys():
        _timers[k] = float(_timers[k]) - delta
        if float(_timers[k]) <= 0.0:
            _timers.erase(k)
            _timer_ended(String(k))
            if _gone:
                return
    if states.has("burning"):
        _char = minf(1.0, _char + delta * 0.35)
    _tick -= delta
    var pulse := _tick <= 0.0
    if pulse:
        _tick = 0.25
    _fx_t -= delta
    var shed := _fx_t <= 0.0
    if shed:
        _fx_t = 0.08
    _ambient(pulse, shed)
    if blocks_shots:
        _stop_enemy_shots()
    _update_sprite()
    _over.queue_redraw()
    queue_redraw()


## Four times a second (`pulse`) and every 80 ms (`shed`): what the prop does on its own.
func _ambient(pulse: bool, shed: bool) -> void:
    var gp := global_position
    if states.has("burning"):
        if shed:
            _fxc("ember", [gp + Vector2(randf_range(-size.x * 0.4, size.x * 0.4), -size.y * 0.3)])
        if pulse:
            var mats := _mats()
            if mats != null:
                mats.ignite(gp, size.length() * 0.5 + 18.0)   # oil next to it catches
            for e in _enemies_within(size.length() * 0.5 + 14.0):
                e.add_burn(4.0, 2.0)
            if randf() < 0.5:
                _ignite_props_near(70.0)
                _fxc("smoke", [gp + Vector2(0, -size.y * 0.5), 2, 8.0, Fx.PAL_SMOKE])
    match kind:
        "brazier":
            if off_time > 0.0:
                return
            if shed:
                _fxc("ember", [gp + Vector2(randf_range(-6.0, 6.0), -14.0)])
            if pulse and randf() < 0.6:
                for e in _enemies_within(36.0):
                    e.add_burn(4.0, 2.5)
                    if _alive(e) and not e.has_state(Element.Kind.FIRE):
                        e.apply_element(Element.Kind.FIRE, 0.6)
                var mats2 := _mats()
                if mats2 != null and randf() < 0.3:
                    mats2.ignite(gp, 30.0)   # spilled oil at its foot goes up
        "fountain":
            if mode == "drained" or off_time > 0.0:
                return
            if shed and randf() < 0.35:
                _fxc("pixels", [Element.Kind.WET, gp + Vector2(0, -size.y * 0.45), 1, 40.0, 3.0])
            if not pulse:
                return
            if _timers.has("contaminated") and _ready_cd("spit", 1.0):
                Cloud.spawn(_world(), gp + Vector2.RIGHT.rotated(randf() * TAU) * 40.0, _contaminant, 70.0, 3.0, 1.0, null)
            if _timers.has("blessed"):
                for p in _players_within(100.0):
                    p.heal(0.5)   # 2/s
                if randf() < 0.5:
                    _fxc("rise", [gp, 2, 20.0])
            if _timers.has("fouled"):
                var mats3 := _mats()
                if mats3 != null and _ready_cd("foul", 1.0):
                    mats3.stamp(Element.Kind.BLOOD, gp, 60.0, 120)
                for e in _enemies_within(80.0):
                    e.add_bleed(3.0, 1.5)
            if mode == "cracked" and _ready_cd("seep", 3.0):
                var mats4 := _mats()
                if mats4 != null:
                    mats4.stamp(Element.Kind.WET, gp + Vector2(0, size.y * 0.5), 30.0, 90)
        "lightning_rod":
            if states.has("charged") and shed:
                _fxc("pixels", [Element.Kind.SHOCK, gp + Vector2(0, -size.y * 0.6), 1, 60.0, 2.0])
        "stone_pillar":
            if _timers.has("erode") and shed and randf() < 0.3:
                _fxc("pixels", [Element.Kind.ACID, gp + Vector2(randf_range(-12.0, 12.0), randf_range(-14.0, 10.0)), 1, 20.0, 2.0])


func _state_ended(state: String) -> void:
    if state == "burning":
        match kind:
            "crate":
                _break(_roll_scrap())   # burned down to planks


func _timer_ended(t: String) -> void:
    match t:
        "dissolve":
            _fxc("signature", [Element.Kind.ACID, global_position, 24.0, 0.8, Vector2.ZERO])
            if kind == "ice_crystal":
                var mats := _mats()
                if mats != null:
                    mats.stamp(Element.Kind.WET, global_position, 30.0, 100)
            _break(1 if kind == "crate" else 0)
        "erode":
            _crumble(1)
        "fuse":
            _explode()


## A pillar is cover against enemy shots too (they do not collide with walls by
## themselves, so the pillar removes the ones that reach it).
func _stop_enemy_shots() -> void:
    for s in get_tree().get_nodes_in_group("enemy_projectiles"):
        if not is_instance_valid(s) or s.is_queued_for_deletion() or not s is Node2D:
            continue
        if overlaps((s as Node2D).global_position, 4.0):
            _fxc("pixels", [Element.Kind.STONE, (s as Node2D).global_position, 3, 50.0, 2.0])
            s.queue_free()


# --- Drawing -------------------------------------------------------------------


func _update_sprite() -> void:
    if _sprite == null:
        return
    var spec: Dictionary = SPECS[kind]
    var c: Color = spec["tint"]
    if _char > 0.0:
        c = c.lerp(Color(0.18, 0.13, 0.11), _char * 0.8)
    if states.has("frozen"):
        c = c.lerp(Color(0.75, 0.92, 1.0), 0.5)
    if states.has("wet"):
        c = c.lerp(Color(0.45, 0.6, 0.9), 0.2)
    match kind:
        "fountain":
            if mode == "drained":
                c = c.darkened(0.45)
            elif _timers.has("contaminated"):
                c = c.lerp(Element.COLORS[_contaminant], 0.4)
            elif _timers.has("fouled"):
                c = c.lerp(Element.COLORS[Element.Kind.BLOOD], 0.4)
            elif _timers.has("blessed"):
                c = c.lerp(Element.COLORS[Element.Kind.HOLY], 0.5)
        "brazier":
            if off_time > 0.0:
                c = c.darkened(0.35)
        "wind_chime":
            if mode == "silenced":
                c = c.darkened(0.4)
            elif _hum > 0.0:
                _sprite.rotation = sin(_hum * 30.0) * 0.25 * _hum
        "ice_crystal":
            if _hum > 0.0:
                c = c.lerp(Color(1, 1, 1), 0.4 * _hum)
        "lightning_rod":
            if states.has("charged"):
                c = c.lerp(Element.COLORS[Element.Kind.SHOCK], 0.6)
        "stone_pillar":
            if _timers.has("erode"):
                c = c.lerp(Element.COLORS[Element.Kind.ACID], 0.25 * (1.0 - float(_timers["erode"]) / 8.0) + 0.1)
    if _flash > 0.0:
        c = c.lerp(Color(1, 1, 1), 0.6)
    _sprite.modulate = c


## Under the sprite: a ground shadow and the brazier / blessing glow.
func _draw() -> void:
    var half := size / 2.0
    draw_set_transform(Vector2(0, half.y - 1.0), 0.0, Vector2(1.0, 0.35))
    draw_circle(Vector2.ZERO, half.x + 5.0, Color(0, 0, 0, 0.35))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    _draw_rim()
    var glow: Texture2D = Art.PARTICLES["light"]
    if is_lit():
        var gs := 90.0 + sin(Time.get_ticks_msec() * 0.012) * 6.0
        draw_texture_rect(glow, Rect2(Vector2(-gs, -gs) / 2.0 + Vector2(0, -6), Vector2(gs, gs)), false, Color(1.0, 0.55, 0.2, 0.35))
    if kind == "fountain" and _timers.has("blessed"):
        draw_texture_rect(glow, Rect2(Vector2(-60, -60), Vector2(120, 120)), false, Color(1.0, 0.95, 0.7, 0.3))
    if kind == "fountain" and _timers.has("contaminated"):
        draw_circle(Vector2.ZERO, half.x + 8.0, Color(Element.COLORS[_contaminant], 0.18))


## A lit fuse: the barrel blinks white faster and faster (here, on the sprite), and a ring
## grows from the barrel to the blast radius over a faint disc of the whole danger zone
## (_draw_fuse_ring, on the Crisp layer so the player's own effects never hide it).
func _draw_fuse(half: Vector2) -> void:
    var left := float(_timers["fuse"])
    var k := clampf(1.0 - left / FUSE_SECS, 0.0, 1.0)
    if fmod(left * (8.0 + 22.0 * k), 1.0) < 0.5:
        _over.draw_rect(Rect2(-half, half * 2.0).grow(3.0), Color(1.0, 1.0, 0.9, 0.8))


func _draw_fuse_ring(cv: CanvasItem) -> void:
    if _gone or not _timers.has("fuse"):
        return
    var k := clampf(1.0 - float(_timers["fuse"]) / FUSE_SECS, 0.0, 1.0)
    cv.draw_circle(Vector2.ZERO, BLAST_RADIUS, Color(Hostile.RED, 0.06 + 0.1 * k))
    Hostile.dash_ring(cv, Vector2.ZERO, BLAST_RADIUS, 0.7 + 0.3 * k, 2.5)
    var r := lerpf(14.0, BLAST_RADIUS, k)
    cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.08, 0.0, 0.0, 0.7), 5.0)
    cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 0.9, 0.45), 2.5)


## A faint rim round the sprite (its silhouette one pixel off on each side, under it):
## dark below and to the sides, pale on top, so a prop reads as an object on the dark
## floor. Puzzle pieces (Secrets) get none: they stay part of the room.
func _draw_rim() -> void:
    if _sprite == null or _sprite.texture == null or not _sprite.visible:
        return
    var t := _sprite.texture
    var sx := _sprite.scale.x * (-1.0 if _sprite.flip_h else 1.0)
    draw_set_transform(_sprite.position, _sprite.rotation, Vector2(sx, _sprite.scale.y))
    var o := -t.get_size() / 2.0
    var dark := Color(0.02, 0.02, 0.03, 0.6)
    draw_texture(t, o + Vector2(-1, 0), dark)
    draw_texture(t, o + Vector2(1, 0), dark)
    draw_texture(t, o + Vector2(0, 1), dark)
    draw_texture(t, o + Vector2(0, -1), Color(0.92, 0.88, 0.80, 0.38))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Over the sprite: state overlays.
func _draw_over() -> void:
    var half := size / 2.0
    if _timers.has("fuse"):
        _draw_fuse(half)
    var r := Rect2(-half, size)
    var t := Time.get_ticks_msec() * 0.001
    if states.has("oiled"):
        _over.draw_rect(r.grow(-2.0), Color(0.10, 0.07, 0.05, 0.35))
        var y := -half.y * 0.3
        _over.draw_line(Vector2(-half.x * 0.6, y), Vector2(half.x * 0.2, y - 3.0), Color(0.75, 0.6, 0.85, 0.45), 2.0)
        _over.draw_line(Vector2(-half.x * 0.2, y + 6.0), Vector2(half.x * 0.5, y + 4.0), Color(0.5, 0.8, 0.7, 0.35), 1.0)
    if states.has("wet"):
        for i in 3:
            var x := -half.x * 0.6 + float(i) * half.x * 0.6
            var dy := fmod(t * 20.0 + float(i) * 7.0, 10.0)
            _over.draw_rect(Rect2(floorf(x), floorf(half.y - 4.0 + dy), 2.0, 3.0), Color(0.45, 0.7, 1.0, 0.8 - dy * 0.06))
        _over.draw_line(Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Color(0.45, 0.7, 1.0, 0.5), 2.0)
    if states.has("frozen"):
        _over.draw_rect(r.grow(2.0), Color(0.75, 0.92, 1.0, 0.22))
        _over.draw_rect(r.grow(2.0), Color(0.85, 0.97, 1.0, 0.85), false, 2.0)
        for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
            var cp: Vector2 = corner * (half + Vector2(2, 2))
            _over.draw_rect(Rect2(cp - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 1, 0.9))
    if states.has("corroded") or _timers.has("dissolve") or _timers.has("erode"):
        var ac: Color = Element.COLORS[Element.Kind.ACID]
        for i in 4:
            var px := Vector2(sin(float(i) * 2.3) * half.x * 0.7, cos(float(i) * 1.7) * half.y * 0.7)
            _over.draw_rect(Rect2(floorf(px.x), floorf(px.y), 3.0, 3.0), Color(ac, 0.7))
        if _timers.has("dissolve"):
            _over.draw_rect(r, Color(ac, 0.15 + 0.1 * sin(t * 12.0)))
    if states.has("charged"):
        var pts := PackedVector2Array()
        for i in 5:
            pts.append(Vector2(randf_range(-half.x, half.x), -half.y + float(i) * size.y / 4.0))
        _over.draw_polyline(pts, Color(1.0, 0.95, 0.4, 0.85), 1.5)
    if states.has("burning"):
        _pixel_flames(Vector2(0, -half.y * 0.2), size.x * 0.8, 18.0, 7)
    if is_lit():
        var top := Vector2(0, -half.y * 0.5)
        if mode == "tipped":
            top = Vector2(half.x * 0.6 * signf(_sprite.rotation), half.y * 0.3)
        _pixel_flames(top, 12.0, 14.0, 4)
    if hp < max_hp and max_hp < 100.0 and kind != "poison_pot":
        var dmg := 1.0 - hp / max_hp
        var cc := Color(0.08, 0.06, 0.06, 0.8)
        _over.draw_line(Vector2(-half.x * 0.5, -half.y * 0.6), Vector2(0, 0), cc, 1.5)
        if dmg > 0.4:
            _over.draw_line(Vector2(0, 0), Vector2(half.x * 0.4, half.y * 0.5), cc, 1.5)
        if dmg > 0.7:
            _over.draw_line(Vector2(half.x * 0.5, -half.y * 0.4), Vector2(0, 0), cc, 1.5)
    match kind:
        "fountain":
            if mode == "cracked":
                _over.draw_polyline(PackedVector2Array([Vector2(-half.x * 0.6, -4), Vector2(-4, 2), Vector2(2, -2), Vector2(half.x * 0.5, 6)]), Color(0.1, 0.08, 0.08, 0.8), 1.5)
            elif mode != "drained" and off_time <= 0.0:
                var wc: Color = Element.COLORS[Element.Kind.WET]
                if _timers.has("contaminated"):
                    wc = Element.COLORS[_contaminant]
                elif _timers.has("fouled"):
                    wc = Element.COLORS[Element.Kind.BLOOD]
                var h := 4.0 + 3.0 * absf(sin(t * 5.0))
                _over.draw_rect(Rect2(-1.0, -half.y * 0.5 - h, 2.0, h), Color(wc, 0.85))
        "blood_altar":
            if not _cd.has("heal"):
                var bc: Color = Element.COLORS[Element.Kind.BLOOD]
                _over.draw_rect(Rect2(-2.0, -half.y * 0.4, 4.0, 4.0), Color(bc, 0.6 + 0.3 * sin(t * 3.0)))
        "wind_chime":
            if mode == "silenced":
                _over.draw_line(Vector2(-6, -6), Vector2(6, 6), Color(Element.COLORS[Element.Kind.VOID], 0.8), 2.0)


func _pixel_flames(base: Vector2, w: float, h: float, count: int) -> void:
    for k in count:
        var x := base.x + randf_range(-w * 0.5, w * 0.5)
        var hh := randf_range(h * 0.3, h)
        var s := floorf(randf_range(2.0, 4.0))
        var c := Color(1.0, 0.85, 0.35, 0.85) if randi() % 3 == 0 else Color(1.0, 0.45, 0.15, 0.75)
        _over.draw_rect(Rect2(floorf(x), floorf(base.y - hh), s, s), c)
        _over.draw_rect(Rect2(floorf(x), floorf(base.y - hh * 0.4), s, s), Color(0.8, 0.2, 0.08, 0.6))


# --- Helpers -------------------------------------------------------------------


func _set_state(state: String, secs: float) -> void:
    states[state] = maxf(float(states.get(state, 0.0)), secs)


func _ready_cd(key: String, secs: float) -> bool:
    if _cd.has(key):
        return false
    _cd[key] = secs
    return true


func _roll_scrap() -> int:
    var range_v: Array = SPECS[kind]["scrap"]
    return randi_range(int(range_v[0]), int(range_v[1]))


func _mats() -> Materials:
    if room != null and "materials" in room:
        var m: Variant = room.get("materials")
        if m is Materials and is_instance_valid(m):
            return m as Materials
    return Materials.find(self)


func _world() -> Node:
    if room != null:
        return room
    return get_tree().current_scene


func _fxc(method: String, args: Array) -> void:
    var scene := get_tree().current_scene
    if scene == null or not "fx" in scene:
        return
    var f: Variant = scene.get("fx")
    if f is Object and is_instance_valid(f) and (f as Object).has_method(method):
        (f as Object).callv(method, args)


func _alive(e: Node) -> bool:
    return is_instance_valid(e) and not e.is_queued_for_deletion()


func _enemies_within(r: float) -> Array[Enemy]:
    var out: Array[Enemy] = []
    var gp := global_position
    for e in get_tree().get_nodes_in_group("enemies"):
        if not e is Enemy or not is_instance_valid(e) or e.is_queued_for_deletion():
            continue
        var en := e as Enemy
        if en.hp > 0.0 and en.global_position.distance_to(gp) <= r + en.radius:
            out.append(en)
    return out


func _players_within(r: float) -> Array[Player]:
    var out: Array[Player] = []
    var gp := global_position
    for p in get_tree().get_nodes_in_group("players"):
        if not p is Player or not is_instance_valid(p):
            continue
        var pl := p as Player
        if pl.alive and pl.global_position.distance_to(gp) <= r:
            out.append(pl)
    return out


func _props_within(r: float) -> Array[Prop]:
    var out: Array[Prop] = []
    var gp := global_position
    for p in get_tree().get_nodes_in_group("props"):
        if p == self or not p is Prop or not is_instance_valid(p) or p.is_queued_for_deletion():
            continue
        var pr := p as Prop
        if not pr._gone and pr.global_position.distance_to(gp) <= r:
            out.append(pr)
    return out


func _away_from_players() -> Vector2:
    var best: Player = null
    var best_d := INF
    for p in get_tree().get_nodes_in_group("players"):
        if p is Player and is_instance_valid(p):
            var d: float = (p as Player).global_position.distance_squared_to(global_position)
            if d < best_d:
                best_d = d
                best = p as Player
    if best == null:
        return Vector2.RIGHT
    var v := global_position - best.global_position
    return v.normalized() if v.length() > 1.0 else Vector2.RIGHT
