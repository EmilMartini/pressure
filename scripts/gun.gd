class_name Gun
extends Node2D
## One carried gun. Spawns projectiles; the Player decides when and where it fires.
## Stats are the gun's base numbers shaped by the player's gear and this gun's mod.

var data: GunData
var player: Player
var cooldown := 0.0
var mod := ""   # item id of the gun mod fitted to this gun, or ""


func _init(p_data: GunData, p_player: Player) -> void:
    data = p_data
    player = p_player
    name = data.id


func _process(delta: float) -> void:
    cooldown = maxf(0.0, cooldown - delta)


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


func fire(dir: Vector2, manual: bool) -> void:
    var ek := element_key()
    cooldown = (1.0 / fire_rate()) * player.cooldown_multiplier()
    var world := get_tree().current_scene
    var damage := data.damage * maxf(0.1, 1.0 + player.stat("dmg") + player.stat("dmg_" + ek) + _gm("g_dmg"))
    var potency := damage * data.reaction_mult * (1.0 + player.stat("potency") + player.stat("potency_" + ek))
    if manual:
        potency *= player.focus_multiplier()
    var crit := randf() < player.stat("crit")
    if crit:
        damage *= 2.0
        potency *= 1.5
    var count := data.projectile_count + int(player.stat("proj_count")) + int(_gm("g_count"))
    var pierce := data.pierce + int(player.stat("pierce")) + int(player.stat("pierce_" + ek)) + int(_gm("g_pierce"))
    var speed := data.projectile_speed * (1.0 + player.stat("proj_speed") + _gm("g_speed"))
    var lifetime := data.lifetime * (1.0 + player.stat("range") + _gm("g_range"))
    var extra := Element.Kind.NONE
    if mod != "":
        var ex: String = Items.get_item(mod).get("mods", {}).get("extra_element", "")
        if ex != "":
            extra = Items.ELEMENTS[ex]
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
        p.radius = data.projectile_radius * (1.4 if crit else 1.0)
        p.color = data.color()
        p.manual = manual
        p.crit = crit
        p.shooter = player
        p.global_position = player.global_position + dir * (player.radius + 6.0)
        world.add_child(p)
    player.add_pressure(data.pressure_per_shot * (1.0 + _gm("g_pressure")))
    player.kick(dir, 2.0 + float(data.weight))
    Sfx.shoot(data.element)
    if "fx" in world and world.fx != null:
        world.fx.puff(Art.PARTICLES["light"], player.global_position + dir * (player.radius + 12.0), Color(data.color(), 0.9), 26.0 + float(data.weight) * 5.0, 0.08, true)
