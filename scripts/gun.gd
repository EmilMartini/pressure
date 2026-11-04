class_name Gun
extends Node2D
## One carried gun. Spawns projectiles; the Player decides when and where it fires.

var data: GunData
var player: Player
var cooldown := 0.0


func _init(p_data: GunData, p_player: Player) -> void:
    data = p_data
    player = p_player
    name = data.id


func _process(delta: float) -> void:
    cooldown = maxf(0.0, cooldown - delta)


func can_fire() -> bool:
    return cooldown <= 0.0


func fire(dir: Vector2, manual: bool) -> void:
    cooldown = (1.0 / data.fire_rate) * player.cooldown_multiplier()
    var world := get_tree().current_scene
    var potency := data.damage * data.reaction_mult
    if manual:
        potency *= player.focus_multiplier()
    for i in data.projectile_count:
        var angle := 0.0
        if data.projectile_count > 1:
            angle = lerpf(-data.spread_deg, data.spread_deg, float(i) / float(data.projectile_count - 1)) * 0.5
        angle += randf_range(-data.spread_deg, data.spread_deg) * 0.15
        var p := Projectile.new()
        p.velocity = dir.rotated(deg_to_rad(angle)) * data.projectile_speed
        p.damage = data.damage
        p.element = data.element
        p.potency = potency
        p.lifetime = data.lifetime
        p.pierce = data.pierce
        p.radius = data.projectile_radius
        p.color = data.color()
        p.manual = manual
        p.shooter = player
        p.global_position = player.global_position + dir * (player.radius + 6.0)
        world.add_child(p)
    player.add_pressure(data.pressure_per_shot)
    player.kick(dir, 2.0 + float(data.weight))
    Sfx.shoot(data.element)
    if "fx" in world and world.fx != null:
        world.fx.puff(Art.PARTICLES["light"], player.global_position + dir * (player.radius + 12.0), Color(data.color(), 0.9), 26.0 + float(data.weight) * 5.0, 0.08, true)
