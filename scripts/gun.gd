class_name Gun
extends Node2D
## One carried gun, drawn orbiting the player and pointing at whatever it last shot.
## Tiers I to IV raise its numbers (merge a duplicate or visit the gunsmith), and a gun
## holds as many mods as its tier; mod effects stack, which is the point.

const MAX_TIER := 4
const TIER_NAMES := ["", " II", " III", " IV"]
## On-screen size of the orbiting gun icon at tier I (a 32 px tile resampled down).
const ICON_PX := 22

var data: GunData
var player: Player
var cooldown := 0.0
var tier := 1
var mods: Array = []   # item ids of the gun mods fitted to this gun

var _sprite: Sprite2D
var _aim := Vector2.RIGHT
var _recoil := 0.0
var _burst_left := 0      # burst shots still queued from the last trigger
var _burst_timer := 0.0
var _alt_flip := false    # alternating-element guns flip this per projectile
var _upright := false     # flask and orb icons stand upright instead of pointing


func _init(p_data: GunData, p_player: Player) -> void:
    data = p_data
    player = p_player
    name = data.id


func _ready() -> void:
    z_index = 1
    _upright = Art.gun_icon_upright(data.id)
    _sprite = Art.icon_sprite(Art.icon_sized(Art.gun_icon(data.id), ICON_PX), 1.0)
    add_child(_sprite)


func _process(delta: float) -> void:
    cooldown = maxf(0.0, cooldown - delta)
    _recoil = move_toward(_recoil, 0.0, 45.0 * delta)
    if _burst_left > 0:
        _burst_timer -= delta
        if _burst_timer <= 0.0:
            _burst_left -= 1
            _burst_timer = data.burst_gap
            # Each burst shot re-aims at whatever is nearest now.
            var tgt: Node2D = null
            if is_instance_valid(player):
                tgt = player.nearest_enemy(effective_range())
            if tgt != null:
                _aim = (tgt.global_position - global_position).normalized()
            _shoot(_aim)
    _sprite.position = -_aim * _recoil
    var left := _aim.x < 0.0
    _sprite.flip_h = left
    if _upright:
        _sprite.rotation = 0.0
    else:
        # The tiles lie diagonally with the business end up and to the right (-45 degrees);
        # mirrored for a left aim it points up-left (-135 degrees). Turn that end to the aim.
        _sprite.rotation = _aim.angle() + (PI * 0.75 if left else PI * 0.25)
    _sprite.scale = Vector2.ONE * (1.0 + 0.08 * float(tier - 1))


func display_name() -> String:
    return data.display_name + TIER_NAMES[tier - 1]


func can_fire() -> bool:
    return cooldown <= 0.0


## Summed mod value across every mod fitted to this gun.
func _gm(key: String) -> float:
    var v := 0.0
    for id in mods:
        v += float(Items.get_item(id).get("mods", {}).get(key, 0.0))
    return v


## Every extra element the fitted coatings add to each hit.
func extra_elements() -> Array:
    var out: Array = []
    for id in mods:
        var ex: String = Items.get_item(id).get("mods", {}).get("extra_element", "")
        if ex != "" and Items.ELEMENTS.has(ex):
            out.append(Items.ELEMENTS[ex])
    if data.extra_element != Element.Kind.NONE:
        out.append(data.extra_element)
    return out


func element_key() -> String:
    return Items.ELEMENT_KEYS.get(data.element, "none")


func tier_mult() -> float:
    return 1.0 + 0.35 * float(tier - 1)


func effective_range() -> float:
    return data.max_range * (1.0 + player.stat("range") + _gm("g_range"))


func fire_rate() -> float:
    var ek := element_key()
    return data.fire_rate * (1.0 + 0.12 * float(tier - 1)) * maxf(0.2, 1.0 + player.stat("fire_rate") + player.stat("fire_rate_" + ek) + _gm("g_fire_rate"))


## One trigger pull: the first shot leaves now, the rest of a burst follows in _process.
## The cooldown covers the whole burst, so fire_rate stays triggers per second.
func fire(dir: Vector2) -> void:
    _aim = dir
    _recoil = 5.0 + float(data.weight)
    var burst := maxi(1, data.burst_count)
    cooldown = maxf(1.0 / fire_rate(), data.burst_gap * float(burst - 1) + 0.05)
    _burst_left = burst - 1
    _burst_timer = data.burst_gap
    _shoot(dir)
    player.add_pressure(data.pressure_per_shot * (1.0 + _gm("g_pressure")))
    player.kick(dir, 1.0 + float(data.weight) * 0.5)


## Spawns one volley (projectile_count projectiles) toward `dir`.
func _shoot(dir: Vector2) -> void:
    var ek := element_key()
    var world := get_tree().current_scene
    var damage := data.damage * tier_mult() * maxf(0.1, 1.0 + player.stat("dmg") + player.stat("dmg_" + ek) + _gm("g_dmg"))
    var potency := damage * data.reaction_mult * (1.0 + player.stat("potency") + player.stat("potency_" + ek))
    var crit := randf() < player.stat("crit")
    if crit:
        var crit_mult := 2.0 + player.stat("crit_dmg")
        damage *= crit_mult
        potency *= 1.0 + (crit_mult - 1.0) * 0.5
    var count := data.projectile_count + int(player.stat("proj_count")) + int(_gm("g_count"))
    var pierce := data.pierce + int(player.stat("pierce")) + int(player.stat("pierce_" + ek)) + int(_gm("g_pierce")) + (1 if tier >= 3 else 0)
    var speed := data.projectile_speed * maxf(0.3, 1.0 + player.stat("proj_speed") + player.stat("shot_speed") + _gm("g_speed"))
    # Transformative gear (Isaac's tear modifiers), summed onto every shot.
    var homing := player.stat("homing")
    var splash := player.stat("splash")
    var shards := int(player.stat("shards"))
    var size_mult := maxf(0.3, 1.0 + player.stat("shot_size"))
    var spectral := player.stat("spectral") > 0.0
    var boomerang := player.stat("boomerang") > 0.0
    var bounces := int(player.stat("bounce"))
    damage *= 1.0 + 0.5 * (size_mult - 1.0)
    # Straight guns take on the shape the gear asks for; other behaviours keep theirs.
    var shape := data.behaviour
    if shape == "straight":
        if boomerang:
            shape = "boomerang"
        elif homing > 0.0:
            shape = "homing"
        elif shards > 0 and pierce == 0 and bounces == 0:
            shape = "flak"
    var lifetime := data.lifetime * (1.0 + player.stat("range") + _gm("g_range"))
    var extras := extra_elements()
    var muzzle := global_position + dir * 14.0
    # Lobbed shells land on the nearest enemy (or most of the way out when there is none).
    var lob_dist := 0.0
    if data.behaviour == "lob":
        var rng := effective_range()
        lob_dist = rng * 0.6
        var tgt := player.nearest_enemy(rng)
        if tgt != null:
            lob_dist = clampf(muzzle.distance_to(tgt.global_position), 60.0, rng)
    var shot_element: int = data.element
    for i in count:
        var angle := 0.0
        if count > 1:
            angle = lerpf(-data.spread_deg, data.spread_deg, float(i) / float(count - 1)) * 0.5
        angle += randf_range(-data.spread_deg, data.spread_deg) * 0.15
        var el: int = data.element
        if data.alt_element != Element.Kind.NONE:
            _alt_flip = not _alt_flip
            if _alt_flip:
                el = data.alt_element
        shot_element = el
        var p := Projectile.new()
        p.velocity = dir.rotated(deg_to_rad(angle)) * speed
        p.damage = damage
        p.element = el
        p.extra_elements = extras
        p.potency = potency
        p.lifetime = lifetime
        p.pierce = pierce
        p.bounces = bounces
        p.radius = data.projectile_radius * (1.4 if crit else 1.0) * (1.0 + 0.1 * float(tier - 1)) * size_mult
        p.color = Element.COLORS[el]
        p.crit = crit
        p.shooter = player
        p.gun_id = data.id
        p.behaviour = shape
        p.splash_radius = data.splash_radius * (1.0 + 0.1 * float(tier - 1)) + splash
        p.shard_count = data.shard_count + shards
        p.homing_turn = data.homing_turn + homing
        if spectral and shape != "lob":
            # Spectral: the obstacle grace never runs out, so walls of rock and crates are ignored.
            p.spectral = true
        if data.behaviour == "lob":
            p.lifetime = maxf(0.15, lob_dist * randf_range(0.9, 1.1) / maxf(1.0, speed))
            p.bounces = 0
        p.global_position = muzzle
        world.add_child(p)
    Sfx.shoot(shot_element, muzzle)
    if "fx" in world and world.fx != null:
        world.fx.puff(Art.PARTICLES["light"], muzzle, Color(Element.COLORS[shot_element], 0.9), 22.0 + float(data.weight) * 4.0, 0.08, true)
