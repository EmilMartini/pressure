extends Node
## Autoload "Guns": the gun pool. `ids()` is what runs can offer (gated by Progress
## unlocks), `all_ids()` is everything that exists.

const ORDER := [
    "water_pistol", "arc_rifle", "blowtorch", "frost_caster", "oil_slinger",
    "mist_sprayer", "ember_carbine", "hydro_cannon", "glacier_lance", "tar_mortar", "storm_pike",
    "venom_spitter", "acid_flask", "blood_lance", "void_orb", "radiant_ray", "gale_blaster", "stone_sling",
]


func all_ids() -> Array:
    return ORDER.duplicate()


## Guns the current save has unlocked.
func ids() -> Array:
    var out: Array = []
    for id in ORDER:
        if Progress.has("gun:" + id):
            out.append(id)
    return out


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
        "mist_sprayer":
            g.display_name = "Mist Sprayer"
            g.element = Element.Kind.WET
            g.weight = 2
            g.damage = 1.5
            g.fire_rate = 12.0
            g.projectile_speed = 380.0
            g.projectile_count = 2
            g.spread_deg = 24.0
            g.max_range = 220.0
            g.lifetime = 0.55
            g.pressure_per_shot = -1.5
            g.projectile_radius = 5.0
        "ember_carbine":
            g.display_name = "Ember Carbine"
            g.element = Element.Kind.FIRE
            g.weight = 3
            g.damage = 5.0
            g.fire_rate = 5.0
            g.projectile_speed = 800.0
            g.spread_deg = 5.0
            g.max_range = 520.0
            g.lifetime = 0.65
            g.pressure_per_shot = 4.0
            g.projectile_radius = 4.0
        "hydro_cannon":
            g.display_name = "Hydro Cannon"
            g.element = Element.Kind.WET
            g.weight = 5
            g.damage = 14.0
            g.fire_rate = 1.1
            g.projectile_speed = 900.0
            g.spread_deg = 2.0
            g.max_range = 700.0
            g.lifetime = 0.8
            g.pressure_per_shot = -12.0
            g.reaction_mult = 1.6
            g.pierce = 3
            g.projectile_radius = 8.0
        "glacier_lance":
            g.display_name = "Glacier Lance"
            g.element = Element.Kind.ICE
            g.weight = 5
            g.damage = 12.0
            g.fire_rate = 1.3
            g.projectile_speed = 700.0
            g.spread_deg = 2.0
            g.max_range = 600.0
            g.lifetime = 0.9
            g.pressure_per_shot = -11.0
            g.reaction_mult = 1.5
            g.pierce = 2
            g.projectile_radius = 7.0
        "tar_mortar":
            g.display_name = "Tar Mortar"
            g.element = Element.Kind.OIL
            g.weight = 4
            g.damage = 2.0
            g.fire_rate = 1.0
            g.projectile_speed = 450.0
            g.projectile_count = 7
            g.spread_deg = 60.0
            g.max_range = 380.0
            g.lifetime = 0.8
            g.pressure_per_shot = 0.0
            g.projectile_radius = 6.0
        "storm_pike":
            g.display_name = "Storm Pike"
            g.element = Element.Kind.SHOCK
            g.weight = 6
            g.damage = 22.0
            g.fire_rate = 0.8
            g.projectile_speed = 1500.0
            g.spread_deg = 0.5
            g.max_range = 900.0
            g.lifetime = 0.7
            g.pressure_per_shot = 18.0
            g.reaction_mult = 2.0
            g.pierce = 5
            g.projectile_radius = 6.0
        "venom_spitter":
            g.display_name = "Venom Spitter"
            g.element = Element.Kind.POISON
            g.weight = 2
            g.damage = 2.0
            g.fire_rate = 8.0
            g.projectile_speed = 520.0
            g.spread_deg = 10.0
            g.max_range = 420.0
            g.lifetime = 0.8
            g.pressure_per_shot = 0.0
            g.projectile_radius = 5.0
        "acid_flask":
            g.display_name = "Acid Flask"
            g.element = Element.Kind.ACID
            g.weight = 3
            g.damage = 4.0
            g.fire_rate = 2.0
            g.projectile_speed = 480.0
            g.projectile_count = 5
            g.spread_deg = 50.0
            g.max_range = 320.0
            g.lifetime = 0.65
            g.pressure_per_shot = 1.0
            g.projectile_radius = 5.0
        "blood_lance":
            g.display_name = "Blood Lance"
            g.element = Element.Kind.BLOOD
            g.weight = 4
            g.damage = 10.0
            g.fire_rate = 1.6
            g.projectile_speed = 950.0
            g.spread_deg = 1.0
            g.max_range = 650.0
            g.lifetime = 0.7
            g.pressure_per_shot = 0.0
            g.reaction_mult = 1.3
            g.pierce = 2
            g.projectile_radius = 6.0
        "void_orb":
            g.display_name = "Void Orb"
            g.element = Element.Kind.VOID
            g.weight = 5
            g.damage = 6.0
            g.fire_rate = 1.2
            g.projectile_speed = 350.0
            g.spread_deg = 2.0
            g.max_range = 500.0
            g.lifetime = 1.4
            g.pressure_per_shot = -4.0
            g.reaction_mult = 1.5
            g.projectile_radius = 9.0
        "radiant_ray":
            g.display_name = "Radiant Ray"
            g.element = Element.Kind.HOLY
            g.weight = 3
            g.damage = 5.0
            g.fire_rate = 5.0
            g.projectile_speed = 1300.0
            g.spread_deg = 1.0
            g.max_range = 700.0
            g.lifetime = 0.55
            g.pressure_per_shot = 6.0
            g.pierce = 1
            g.projectile_radius = 4.0
        "gale_blaster":
            g.display_name = "Gale Blaster"
            g.element = Element.Kind.GALE
            g.weight = 2
            g.damage = 1.5
            g.fire_rate = 10.0
            g.projectile_speed = 700.0
            g.projectile_count = 2
            g.spread_deg = 30.0
            g.max_range = 260.0
            g.lifetime = 0.4
            g.pressure_per_shot = -2.0
            g.projectile_radius = 5.0
        "stone_sling":
            g.display_name = "Stone Sling"
            g.element = Element.Kind.STONE
            g.weight = 4
            g.damage = 11.0
            g.fire_rate = 1.4
            g.projectile_speed = 600.0
            g.spread_deg = 3.0
            g.max_range = 500.0
            g.lifetime = 0.85
            g.pressure_per_shot = 0.0
            g.reaction_mult = 1.2
            g.projectile_radius = 7.0
        _:
            push_error("Unknown gun id: %s" % id)
    return g
