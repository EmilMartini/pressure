class_name Gun
extends Node2D
## One carried gun, drawn orbiting the player and pointing at whatever it last shot.
## Tiers I to IV raise its numbers (merge a duplicate or visit the gunsmith), and a gun
## holds as many mods as its tier; mod effects stack, which is the point.

const MAX_TIER := 4
const TIER_NAMES := ["", " II", " III", " IV"]

var data: GunData
var player: Player
var cooldown := 0.0
var tier := 1
var mods: Array = []   # item ids of the gun mods fitted to this gun

var _sprite: Sprite2D
var _aim := Vector2.RIGHT
var _recoil := 0.0


func _init(p_data: GunData, p_player: Player) -> void:
    data = p_data
    player = p_player
    name = data.id


func _ready() -> void:
    z_index = 1
    _sprite = Art.sprite(Art.gun_tile(data.id), 1.5, data.color())
    add_child(_sprite)


func _process(delta: float) -> void:
    cooldown = maxf(0.0, cooldown - delta)
    _recoil = move_toward(_recoil, 0.0, 45.0 * delta)
    _sprite.position = -_aim * _recoil
    _sprite.rotation = _aim.angle()
    _sprite.flip_v = _aim.x < 0.0
    _sprite.scale = Vector2.ONE * (1.5 + 0.12 * float(tier - 1))


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
    return out


func element_key() -> String:
    return Items.ELEMENT_KEYS[data.element]


func tier_mult() -> float:
    return 1.0 + 0.35 * float(tier - 1)


func effective_range() -> float:
    return data.max_range * (1.0 + player.stat("range") + _gm("g_range"))


func fire_rate() -> float:
    var ek := element_key()
    return data.fire_rate * (1.0 + 0.12 * float(tier - 1)) * maxf(0.2, 1.0 + player.stat("fire_rate") + player.stat("fire_rate_" + ek) + _gm("g_fire_rate"))


func fire(dir: Vector2) -> void:
    var ek := element_key()
    _aim = dir
    _recoil = 5.0 + float(data.weight)
    cooldown = 1.0 / fire_rate()
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
    var speed := data.projectile_speed * (1.0 + player.stat("proj_speed") + _gm("g_speed"))
    var lifetime := data.lifetime * (1.0 + player.stat("range") + _gm("g_range"))
    var extras := extra_elements()
    var muzzle := global_position + dir * 14.0
    for i in count:
        var angle := 0.0
        if count > 1:
            angle = lerpf(-data.spread_deg, data.spread_deg, float(i) / float(count - 1)) * 0.5
        angle += randf_range(-data.spread_deg, data.spread_deg) * 0.15
        var p := Projectile.new()
        p.velocity = dir.rotated(deg_to_rad(angle)) * speed
        p.damage = damage
        p.element = data.element
        p.extra_elements = extras
        p.potency = potency
        p.lifetime = lifetime
        p.pierce = pierce
        p.bounces = int(player.stat("bounce"))
        p.radius = data.projectile_radius * (1.4 if crit else 1.0) * (1.0 + 0.1 * float(tier - 1))
        p.color = data.color()
        p.crit = crit
        p.shooter = player
        p.global_position = muzzle
        world.add_child(p)
    player.add_pressure(data.pressure_per_shot * (1.0 + _gm("g_pressure")))
    player.kick(dir, 1.0 + float(data.weight) * 0.5)
    Sfx.shoot(data.element)
    if "fx" in world and world.fx != null:
        world.fx.puff(Art.PARTICLES["light"], muzzle, Color(data.color(), 0.9), 22.0 + float(data.weight) * 4.0, 0.08, true)
