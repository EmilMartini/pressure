extends Node
## Autoload "Guns": the gun pool. Later this becomes data files plus Isaac-style unlocks.

const ORDER := ["water_pistol", "arc_rifle", "blowtorch", "frost_caster", "oil_slinger"]


func ids() -> Array:
    return ORDER.duplicate()


func make(id: String) -> GunData:
    var g := GunData.new()
    g.id = id
    match id:
        "water_pistol":
            g.display_name = "Water Pistol"
            g.element = Element.Kind.WET
            g.weight = 1
            g.damage = 3.0
            g.fire_rate = 6.0
            g.projectile_speed = 750.0
            g.spread_deg = 6.0
            g.max_range = 480.0
            g.lifetime = 0.7
            g.pressure_per_shot = -3.0
            g.projectile_radius = 4.0
        "arc_rifle":
            g.display_name = "Arc Rifle"
            g.element = Element.Kind.SHOCK
            g.weight = 3
            g.damage = 9.0
            g.fire_rate = 2.2
            g.projectile_speed = 1200.0
            g.spread_deg = 1.0
            g.max_range = 650.0
            g.lifetime = 0.6
            g.pressure_per_shot = 9.0
            g.reaction_mult = 1.4
            g.pierce = 1
            g.projectile_radius = 5.0
        "blowtorch":
            g.display_name = "Blowtorch"
            g.element = Element.Kind.FIRE
            g.weight = 2
            g.damage = 2.0
            g.fire_rate = 14.0
            g.projectile_speed = 420.0
            g.spread_deg = 22.0
            g.max_range = 190.0
            g.lifetime = 0.45
            g.pressure_per_shot = 2.2
            g.projectile_radius = 6.0
        "frost_caster":
            g.display_name = "Frost Caster"
            g.element = Element.Kind.ICE
            g.weight = 2
            g.damage = 4.0
            g.fire_rate = 3.0
            g.projectile_speed = 600.0
            g.projectile_count = 3
            g.spread_deg = 30.0
            g.max_range = 400.0
            g.lifetime = 0.7
            g.pressure_per_shot = -6.0
            g.projectile_radius = 5.0
        "oil_slinger":
            g.display_name = "Oil Slinger"
            g.element = Element.Kind.OIL
            g.weight = 2
            g.damage = 1.0
            g.fire_rate = 2.5
            g.projectile_speed = 500.0
            g.projectile_count = 4
            g.spread_deg = 40.0
            g.max_range = 350.0
            g.lifetime = 0.7
            g.pressure_per_shot = 0.0
            g.projectile_radius = 5.0
        _:
            push_error("Unknown gun id: %s" % id)
    return g
