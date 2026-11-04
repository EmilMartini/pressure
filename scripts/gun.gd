class_name Gun
extends Node2D
## One carried gun, drawn orbiting the player and pointing at whatever it last shot.
## Spawns projectiles; the Player decides when and where it fires. Stats are the gun's
## base numbers shaped by the player's gear, level-ups, mastery and this gun's mod.

var data: GunData
var player: Player
var cooldown := 0.0
var mod := ""   # item id of the gun mod fitted to this gun, or ""

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


func can_fire() -> bool:
    return cooldown <= 0.0


func _gm(key: String) -> float:
    if mod == "":
        return 0.0
    return float(Items.get_item(mod).get("mods", {}).get(key, 0.0))


func element_key() -> String:
    return Items.ELEMENT_KEYS[data.element]


func effective_range() -> float:
    return data.max_range * (1.0 + player.stat("range") + _gm("g_range"))


func fire_rate() -> float:
    var ek := element_key()
    return data.fire_rate * maxf(0.2, 1.0 + player.stat("fire_rate") + player.stat("fire_rate_" + ek) + _gm("g_fire_rate"))


func fire(dir: Vector2) -> void:
    var ek := element_key()
    _aim = dir
    _recoil = 5.0 + float(data.weight)
    cooldown = (1.0 / fire_rate()) * player.cooldown_multiplier()
    var world := get_tree().current_scene
    var damage := data.damage * maxf(0.1, 1.0 + player.stat("dmg") + player.stat("dmg_" + ek) + _gm("g_dmg"))
    var potency := damage * data.reaction_mult * (1.0 + player.stat("potency") + player.stat("potency_" + ek))
    var crit := randf() < player.stat("crit")
    if crit:
        var crit_mult := 2.0 + player.stat("crit_dmg")
        damage *= crit_mult
        potency *= 1.0 + (crit_mult - 1.0) * 0.5
    var count := data.projectile_count + int(player.stat("proj_count")) + int(_gm("g_count"))
    var pierce := data.pierce + int(player.stat("pierce")) + int(player.stat("pierce_" + ek)) + int(_gm("g_pierce"))
    var speed := data.projectile_speed * (1.0 + player.stat("proj_speed") + _gm("g_speed"))
    var lifetime := data.lifetime * (1.0 + player.stat("range") + _gm("g_range"))
    var extra := Element.Kind.NONE
    if mod != "":
        var ex: String = Items.get_item(mod).get("mods", {}).get("extra_element", "")
        if ex != "":
            extra = Items.ELEMENTS[ex]
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
        p.extra_element = extra
        p.potency = potency
        p.lifetime = lifetime
        p.pierce = pierce
        p.bounces = int(player.stat("bounce"))
        p.radius = data.projectile_radius * (1.4 if crit else 1.0)
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
