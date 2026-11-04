extends Node
## Autoload "Guns": the gun pool. `ids()` is what runs can offer (gated by Progress
## unlocks), `all_ids()` is everything that exists.
##
## Balance budget: dps = damage * fire_rate * projectile_count * burst_count * (1 + 0.5 * pierce)
## (splash, flak shards and boomerang return hits are bonus on top). Bands by weight:
## w1 15-20, w2 22-28, w3 30-38, w4 40-48, w5 50-60. Heavier guns carry more
## reaction_mult and bigger projectiles; light guns get speed and range. Pressure per
## trigger: hot (fire, shock, acid) +2..+6, cold (wet, ice) -2..-6, others -1..+1.

const ORDER := [
    "water_pistol", "arc_rifle", "flare_pistol", "slick_wand", "blowtorch", "frost_caster",
    "oil_slinger", "mist_sprayer", "ember_carbine", "hydro_cannon", "glacier_lance",
    "tar_mortar", "storm_pike", "venom_spitter", "acid_flask", "blood_lance", "void_orb",
    "radiant_ray", "gale_blaster", "stone_sling", "spark_needler", "cinder_flak",
    "rime_chakram", "plague_mortar", "blight_seeker", "etcher_beam", "corrosion_burst",
    "vein_pistol", "clot_orb", "rift_seeker", "null_wand", "sun_cannon", "prayer_burst",
    "zephyr_rang", "cyclone_flak", "boulder_mortar", "gravel_shotgun", "eclipse_carbine",
    "kettle_gun", "storm_seeker", "railgun", "napalm_lobber", "duality_burst",
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
        "water_pistol":   # wet, w1 pistol, dps 18.0
            g.display_name = "Water Pistol"
            g.archetype = "pistol"
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
        "arc_rifle":   # shock, w3 rifle, dps 31.4
            g.display_name = "Arc Rifle"
            g.archetype = "rifle"
            g.element = Element.Kind.SHOCK
            g.weight = 3
            g.damage = 9.5
            g.fire_rate = 2.2
            g.projectile_speed = 1200.0
            g.spread_deg = 1.0
            g.max_range = 650.0
            g.lifetime = 0.6
            g.pressure_per_shot = 4.0
            g.reaction_mult = 1.4
            g.pierce = 1
            g.projectile_radius = 5.0
        "flare_pistol":   # fire, w1 pistol, dps 17.1
            g.display_name = "Flare Pistol"
            g.archetype = "pistol"
            g.element = Element.Kind.FIRE
            g.weight = 1
            g.damage = 4.5
            g.fire_rate = 3.8
            g.projectile_speed = 700.0
            g.spread_deg = 5.0
            g.max_range = 450.0
            g.lifetime = 0.7
            g.pressure_per_shot = 3.0
            g.projectile_radius = 4.0
        "slick_wand":   # oil, w1 wand, dps 15.0
            g.display_name = "Slick Wand"
            g.archetype = "wand"
            g.element = Element.Kind.OIL
            g.weight = 1
            g.damage = 2.5
            g.fire_rate = 6.0
            g.projectile_speed = 650.0
            g.spread_deg = 4.0
            g.max_range = 420.0
            g.lifetime = 0.75
            g.pressure_per_shot = 0.0
            g.reaction_mult = 3.0
            g.projectile_radius = 4.0
        "blowtorch":   # fire, w2 flamer, dps 28.0
            g.display_name = "Blowtorch"
            g.archetype = "flamer"
            g.element = Element.Kind.FIRE
            g.weight = 2
            g.damage = 2.0
            g.fire_rate = 14.0
            g.projectile_speed = 420.0
            g.spread_deg = 22.0
            g.max_range = 190.0
            g.lifetime = 0.45
            g.pressure_per_shot = 2.0
            g.projectile_radius = 6.0
        "frost_caster":   # ice, w2 shotgun, dps 25.2
            g.display_name = "Frost Caster"
            g.archetype = "shotgun"
            g.element = Element.Kind.ICE
            g.weight = 2
            g.damage = 1.8
            g.fire_rate = 2.8
            g.projectile_speed = 620.0
            g.projectile_count = 5
            g.spread_deg = 50.0
            g.max_range = 300.0
            g.lifetime = 0.45
            g.pressure_per_shot = -4.0
            g.reaction_mult = 1.2
            g.projectile_radius = 4.0
        "oil_slinger":   # oil, w2 shotgun, dps 26.4
            g.display_name = "Oil Slinger"
            g.archetype = "shotgun"
            g.element = Element.Kind.OIL
            g.weight = 2
            g.damage = 2.2
            g.fire_rate = 2.4
            g.projectile_speed = 520.0
            g.projectile_count = 5
            g.spread_deg = 45.0
            g.max_range = 300.0
            g.lifetime = 0.55
            g.pressure_per_shot = 0.0
            g.projectile_radius = 5.0
        "mist_sprayer":   # wet, w2 smg, dps 26.4
            g.display_name = "Mist Sprayer"
            g.archetype = "smg"
            g.element = Element.Kind.WET
            g.weight = 2
            g.damage = 1.1
            g.fire_rate = 12.0
            g.projectile_speed = 380.0
            g.projectile_count = 2
            g.spread_deg = 24.0
            g.max_range = 220.0
            g.lifetime = 0.55
            g.pressure_per_shot = -2.0
            g.projectile_radius = 5.0
        "ember_carbine":   # fire, w3 rifle, dps 32.5
            g.display_name = "Ember Carbine"
            g.archetype = "rifle"
            g.element = Element.Kind.FIRE
            g.weight = 3
            g.damage = 6.5
            g.fire_rate = 5.0
            g.projectile_speed = 800.0
            g.spread_deg = 5.0
            g.max_range = 520.0
            g.lifetime = 0.65
            g.pressure_per_shot = 3.0
            g.projectile_radius = 4.0
        "hydro_cannon":   # wet, w5 cannon, dps 55.0
            g.display_name = "Hydro Cannon"
            g.archetype = "cannon"
            g.element = Element.Kind.WET
            g.weight = 5
            g.damage = 20.0
            g.fire_rate = 1.1
            g.projectile_speed = 800.0
            g.spread_deg = 2.0
            g.max_range = 650.0
            g.lifetime = 0.85
            g.pressure_per_shot = -6.0
            g.reaction_mult = 1.8
            g.pierce = 3
            g.projectile_radius = 9.0
            g.splash_radius = 50.0
        "glacier_lance":   # ice, w5 sniper, dps 54.6
            g.display_name = "Glacier Lance"
            g.archetype = "sniper"
            g.element = Element.Kind.ICE
            g.weight = 5
            g.damage = 26.0
            g.fire_rate = 1.05
            g.projectile_speed = 900.0
            g.spread_deg = 1.0
            g.max_range = 750.0
            g.lifetime = 0.85
            g.pressure_per_shot = -6.0
            g.reaction_mult = 1.7
            g.pierce = 2
            g.projectile_radius = 7.0
        "tar_mortar":   # oil, w4 mortar, dps 40.5
            g.display_name = "Tar Mortar"
            g.archetype = "mortar"
            g.element = Element.Kind.OIL
            g.weight = 4
            g.damage = 22.5
            g.fire_rate = 0.9
            g.projectile_speed = 420.0
            g.projectile_count = 2
            g.spread_deg = 30.0
            g.max_range = 420.0
            g.lifetime = 1.0
            g.pressure_per_shot = 0.5
            g.reaction_mult = 1.4
            g.projectile_radius = 7.0
            g.behaviour = "lob"
            g.splash_radius = 60.0
        "storm_pike":   # shock, w5 sniper, dps 54.0
            g.display_name = "Storm Pike"
            g.archetype = "sniper"
            g.element = Element.Kind.SHOCK
            g.weight = 5
            g.damage = 24.0
            g.fire_rate = 0.9
            g.projectile_speed = 1500.0
            g.spread_deg = 0.5
            g.max_range = 900.0
            g.lifetime = 0.7
            g.pressure_per_shot = 6.0
            g.reaction_mult = 2.0
            g.pierce = 3
            g.projectile_radius = 6.0
        "venom_spitter":   # poison, w2 smg, dps 24.0
            g.display_name = "Venom Spitter"
            g.archetype = "smg"
            g.element = Element.Kind.POISON
            g.weight = 2
            g.damage = 3.0
            g.fire_rate = 8.0
            g.projectile_speed = 520.0
            g.spread_deg = 10.0
            g.max_range = 420.0
            g.lifetime = 0.8
            g.pressure_per_shot = 0.5
            g.projectile_radius = 5.0
        "acid_flask":   # acid, w3 shotgun, dps 34.0
            g.display_name = "Acid Flask"
            g.archetype = "shotgun"
            g.element = Element.Kind.ACID
            g.weight = 3
            g.damage = 3.4
            g.fire_rate = 2.0
            g.projectile_speed = 480.0
            g.projectile_count = 5
            g.spread_deg = 50.0
            g.max_range = 320.0
            g.lifetime = 0.65
            g.pressure_per_shot = 2.0
            g.reaction_mult = 1.2
            g.projectile_radius = 5.0
        "blood_lance":   # blood, w4 sniper, dps 41.6
            g.display_name = "Blood Lance"
            g.archetype = "sniper"
            g.element = Element.Kind.BLOOD
            g.weight = 4
            g.damage = 13.0
            g.fire_rate = 1.6
            g.projectile_speed = 950.0
            g.spread_deg = 1.0
            g.max_range = 650.0
            g.lifetime = 0.7
            g.pressure_per_shot = 0.0
            g.reaction_mult = 1.4
            g.pierce = 2
            g.projectile_radius = 6.0
        "void_orb":   # void, w5 orb, dps 52.8
            g.display_name = "Void Orb"
            g.archetype = "orb"
            g.element = Element.Kind.VOID
            g.weight = 5
            g.damage = 16.0
            g.fire_rate = 1.1
            g.projectile_speed = 260.0
            g.spread_deg = 2.0
            g.max_range = 500.0
            g.lifetime = 2.0
            g.pressure_per_shot = -2.0
            g.reaction_mult = 2.2
            g.pierce = 4
            g.projectile_radius = 11.0
        "radiant_ray":   # holy, w3 beam, dps 37.5
            g.display_name = "Radiant Ray"
            g.archetype = "beam"
            g.element = Element.Kind.HOLY
            g.weight = 3
            g.damage = 5.0
            g.fire_rate = 5.0
            g.projectile_speed = 1300.0
            g.spread_deg = 1.0
            g.max_range = 700.0
            g.lifetime = 0.55
            g.pressure_per_shot = 2.0
            g.pierce = 1
            g.projectile_radius = 4.0
        "gale_blaster":   # gale, w2 smg, dps 26.0
            g.display_name = "Gale Blaster"
            g.archetype = "smg"
            g.element = Element.Kind.GALE
            g.weight = 2
            g.damage = 1.3
            g.fire_rate = 10.0
            g.projectile_speed = 700.0
            g.projectile_count = 2
            g.spread_deg = 30.0
            g.max_range = 260.0
            g.lifetime = 0.4
            g.pressure_per_shot = -1.0
            g.projectile_radius = 5.0
        "stone_sling":   # stone, w4 rifle, dps 45.0
            g.display_name = "Stone Sling"
            g.archetype = "rifle"
            g.element = Element.Kind.STONE
            g.weight = 4
            g.damage = 30.0
            g.fire_rate = 1.5
            g.projectile_speed = 650.0
            g.spread_deg = 3.0
            g.max_range = 520.0
            g.lifetime = 0.85
            g.pressure_per_shot = 0.0
            g.reaction_mult = 1.3
            g.projectile_radius = 7.0
        "spark_needler":   # shock, w1 smg, dps 16.8
            g.display_name = "Spark Needler"
            g.archetype = "smg"
            g.element = Element.Kind.SHOCK
            g.weight = 1
            g.damage = 1.4
            g.fire_rate = 12.0
            g.projectile_speed = 950.0
            g.spread_deg = 12.0
            g.max_range = 360.0
            g.lifetime = 0.4
            g.pressure_per_shot = 2.0
            g.projectile_radius = 3.0
        "cinder_flak":   # fire, w4 flak, dps 41.6
            g.display_name = "Cinder Flak"
            g.archetype = "flak"
            g.element = Element.Kind.FIRE
            g.weight = 4
            g.damage = 32.0
            g.fire_rate = 1.3
            g.projectile_speed = 600.0
            g.spread_deg = 4.0
            g.max_range = 420.0
            g.lifetime = 0.7
            g.pressure_per_shot = 5.0
            g.reaction_mult = 1.3
            g.projectile_radius = 7.0
            g.behaviour = "flak"
            g.shard_count = 6
        "rime_chakram":   # ice, w3 boomerang, dps 33.6
            g.display_name = "Rime Chakram"
            g.archetype = "boomerang"
            g.element = Element.Kind.ICE
            g.weight = 3
            g.damage = 7.0
            g.fire_rate = 1.6
            g.projectile_speed = 520.0
            g.spread_deg = 4.0
            g.max_range = 360.0
            g.lifetime = 1.1
            g.pressure_per_shot = -3.0
            g.reaction_mult = 1.3
            g.pierce = 4
            g.projectile_radius = 6.0
            g.behaviour = "boomerang"
        "plague_mortar":   # poison, w3 mortar, dps 33.6
            g.display_name = "Plague Mortar"
            g.archetype = "mortar"
            g.element = Element.Kind.POISON
            g.weight = 3
            g.damage = 24.0
            g.fire_rate = 1.4
            g.projectile_speed = 380.0
            g.spread_deg = 8.0
            g.max_range = 400.0
            g.lifetime = 1.0
            g.pressure_per_shot = 0.5
            g.reaction_mult = 1.4
            g.projectile_radius = 6.0
            g.behaviour = "lob"
            g.splash_radius = 55.0
        "blight_seeker":   # poison, w2 homing, dps 24.8
            g.display_name = "Blight Seeker"
            g.archetype = "homing"
            g.element = Element.Kind.POISON
            g.weight = 2
            g.damage = 4.5
            g.fire_rate = 5.5
            g.projectile_speed = 420.0
            g.spread_deg = 30.0
            g.max_range = 450.0
            g.lifetime = 1.4
            g.pressure_per_shot = 0.5
            g.projectile_radius = 4.0
            g.behaviour = "homing"
            g.homing_turn = 5.0
        "etcher_beam":   # acid, w2 beam, dps 27.0
            g.display_name = "Etcher Beam"
            g.archetype = "beam"
            g.element = Element.Kind.ACID
            g.weight = 2
            g.damage = 1.2
            g.fire_rate = 15.0
            g.projectile_speed = 1600.0
            g.spread_deg = 3.0
            g.max_range = 300.0
            g.lifetime = 0.2
            g.pressure_per_shot = 2.0
            g.pierce = 1
            g.projectile_radius = 2.5
        "corrosion_burst":   # acid, w4 burst, dps 43.2
            g.display_name = "Corrosion Burst"
            g.archetype = "burst"
            g.element = Element.Kind.ACID
            g.weight = 4
            g.damage = 8.0
            g.fire_rate = 1.8
            g.projectile_speed = 900.0
            g.spread_deg = 3.0
            g.max_range = 520.0
            g.lifetime = 0.6
            g.pressure_per_shot = 4.0
            g.reaction_mult = 1.2
            g.projectile_radius = 4.0
            g.burst_count = 3
            g.burst_gap = 0.07
        "vein_pistol":   # blood, w1 pistol, dps 16.6
            g.display_name = "Vein Pistol"
            g.archetype = "pistol"
            g.element = Element.Kind.BLOOD
            g.weight = 1
            g.damage = 3.6
            g.fire_rate = 4.6
            g.projectile_speed = 800.0
            g.spread_deg = 5.0
            g.max_range = 460.0
            g.lifetime = 0.6
            g.pressure_per_shot = 0.0
            g.projectile_radius = 4.0
        "clot_orb":   # blood, w3 orb, dps 31.9
            g.display_name = "Clot Orb"
            g.archetype = "orb"
            g.element = Element.Kind.BLOOD
            g.weight = 3
            g.damage = 8.5
            g.fire_rate = 1.5
            g.projectile_speed = 280.0
            g.spread_deg = 3.0
            g.max_range = 420.0
            g.lifetime = 1.6
            g.pressure_per_shot = 0.0
            g.reaction_mult = 1.8
            g.pierce = 3
            g.projectile_radius = 10.0
        "rift_seeker":   # void, w3 homing, dps 30.6
            g.display_name = "Rift Seeker"
            g.archetype = "homing"
            g.element = Element.Kind.VOID
            g.weight = 3
            g.damage = 8.5
            g.fire_rate = 2.4
            g.projectile_speed = 480.0
            g.spread_deg = 20.0
            g.max_range = 500.0
            g.lifetime = 1.3
            g.pressure_per_shot = -1.0
            g.reaction_mult = 1.4
            g.pierce = 1
            g.projectile_radius = 5.0
            g.behaviour = "homing"
            g.homing_turn = 4.0
        "null_wand":   # void, w2 wand, dps 22.5
            g.display_name = "Null Wand"
            g.archetype = "wand"
            g.element = Element.Kind.VOID
            g.weight = 2
            g.damage = 3.0
            g.fire_rate = 7.5
            g.projectile_speed = 600.0
            g.spread_deg = 4.0
            g.max_range = 420.0
            g.lifetime = 0.75
            g.pressure_per_shot = -1.0
            g.reaction_mult = 2.8
            g.projectile_radius = 4.0
        "sun_cannon":   # holy, w5 cannon, dps 52.0
            g.display_name = "Sun Cannon"
            g.archetype = "cannon"
            g.element = Element.Kind.HOLY
            g.weight = 5
            g.damage = 40.0
            g.fire_rate = 0.65
            g.projectile_speed = 420.0
            g.spread_deg = 1.0
            g.max_range = 520.0
            g.lifetime = 1.3
            g.pressure_per_shot = 2.0
            g.reaction_mult = 2.0
            g.pierce = 2
            g.projectile_radius = 12.0
            g.splash_radius = 70.0
        "prayer_burst":   # holy, w2 burst, dps 25.2
            g.display_name = "Prayer Burst"
            g.archetype = "burst"
            g.element = Element.Kind.HOLY
            g.weight = 2
            g.damage = 3.0
            g.fire_rate = 2.8
            g.projectile_speed = 1000.0
            g.spread_deg = 4.0
            g.max_range = 520.0
            g.lifetime = 0.55
            g.pressure_per_shot = 1.0
            g.projectile_radius = 3.5
            g.burst_count = 3
            g.burst_gap = 0.06
        "zephyr_rang":   # gale, w1 boomerang, dps 16.5
            g.display_name = "Zephyr Rang"
            g.archetype = "boomerang"
            g.element = Element.Kind.GALE
            g.weight = 1
            g.damage = 3.0
            g.fire_rate = 2.2
            g.projectile_speed = 600.0
            g.spread_deg = 4.0
            g.max_range = 340.0
            g.lifetime = 0.9
            g.pressure_per_shot = -1.0
            g.pierce = 3
            g.projectile_radius = 5.0
            g.behaviour = "boomerang"
        "cyclone_flak":   # gale, w3 flak, dps 31.2
            g.display_name = "Cyclone Flak"
            g.archetype = "flak"
            g.element = Element.Kind.GALE
            g.weight = 3
            g.damage = 12.0
            g.fire_rate = 2.6
            g.projectile_speed = 650.0
            g.spread_deg = 6.0
            g.max_range = 380.0
            g.lifetime = 0.55
            g.pressure_per_shot = -1.0
            g.reaction_mult = 1.2
            g.projectile_radius = 5.0
            g.behaviour = "flak"
            g.shard_count = 5
        "boulder_mortar":   # stone, w5 mortar, dps 55.0
            g.display_name = "Boulder Mortar"
            g.archetype = "mortar"
            g.element = Element.Kind.STONE
            g.weight = 5
            g.damage = 55.0
            g.fire_rate = 1.0
            g.projectile_speed = 340.0
            g.spread_deg = 4.0
            g.max_range = 460.0
            g.lifetime = 1.2
            g.pressure_per_shot = 1.0
            g.reaction_mult = 1.6
            g.projectile_radius = 10.0
            g.behaviour = "lob"
            g.splash_radius = 80.0
        "gravel_shotgun":   # stone, w3 shotgun, dps 34.3
            g.display_name = "Gravel Shotgun"
            g.archetype = "shotgun"
            g.element = Element.Kind.STONE
            g.weight = 3
            g.damage = 2.2
            g.fire_rate = 2.6
            g.projectile_speed = 600.0
            g.projectile_count = 6
            g.spread_deg = 55.0
            g.max_range = 280.0
            g.lifetime = 0.45
            g.pressure_per_shot = 0.0
            g.projectile_radius = 4.0
        "eclipse_carbine":   # holy, w4 rifle, dps 43.2
            g.display_name = "Eclipse Carbine"
            g.archetype = "rifle"
            g.element = Element.Kind.HOLY
            g.weight = 4
            g.damage = 9.0
            g.fire_rate = 4.8
            g.projectile_speed = 950.0
            g.spread_deg = 3.0
            g.max_range = 560.0
            g.lifetime = 0.6
            g.pressure_per_shot = 0.0
            g.reaction_mult = 1.3
            g.projectile_radius = 5.0
            g.alt_element = Element.Kind.VOID
        "kettle_gun":   # wet, w3 smg, dps 31.2
            g.display_name = "Kettle Gun"
            g.archetype = "smg"
            g.element = Element.Kind.WET
            g.weight = 3
            g.damage = 2.4
            g.fire_rate = 13.0
            g.projectile_speed = 700.0
            g.spread_deg = 14.0
            g.max_range = 320.0
            g.lifetime = 0.45
            g.pressure_per_shot = 0.0
            g.projectile_radius = 4.0
            g.alt_element = Element.Kind.FIRE
        "storm_seeker":   # shock, w4 homing, dps 42.9
            g.display_name = "Storm Seeker"
            g.archetype = "homing"
            g.element = Element.Kind.SHOCK
            g.weight = 4
            g.damage = 13.0
            g.fire_rate = 2.2
            g.projectile_speed = 650.0
            g.spread_deg = 16.0
            g.max_range = 520.0
            g.lifetime = 1.0
            g.pressure_per_shot = 3.0
            g.reaction_mult = 0.8
            g.pierce = 1
            g.projectile_radius = 5.0
            g.behaviour = "homing"
            g.homing_turn = 3.5
            g.extra_element = Element.Kind.WET
        "railgun":   # none, w5 sniper, dps 56.2
            g.display_name = "Railgun"
            g.archetype = "sniper"
            g.element = Element.Kind.NONE
            g.weight = 5
            g.damage = 30.0
            g.fire_rate = 0.75
            g.projectile_speed = 2200.0
            g.spread_deg = 0.5
            g.max_range = 1000.0
            g.lifetime = 0.5
            g.pressure_per_shot = 0.0
            g.reaction_mult = 0.0
            g.pierce = 3
            g.projectile_radius = 4.0
        "napalm_lobber":   # fire, w4 mortar, dps 44.0
            g.display_name = "Napalm Lobber"
            g.archetype = "mortar"
            g.element = Element.Kind.FIRE
            g.weight = 4
            g.damage = 40.0
            g.fire_rate = 1.1
            g.projectile_speed = 400.0
            g.spread_deg = 6.0
            g.max_range = 440.0
            g.lifetime = 1.1
            g.pressure_per_shot = 4.0
            g.reaction_mult = 1.0
            g.projectile_radius = 8.0
            g.behaviour = "lob"
            g.splash_radius = 65.0
            g.extra_element = Element.Kind.OIL
        "duality_burst":   # ice, w3 burst, dps 31.9
            g.display_name = "Duality Burst"
            g.archetype = "burst"
            g.element = Element.Kind.ICE
            g.weight = 3
            g.damage = 3.8
            g.fire_rate = 2.8
            g.projectile_speed = 850.0
            g.spread_deg = 3.0
            g.max_range = 480.0
            g.lifetime = 0.6
            g.pressure_per_shot = 0.0
            g.reaction_mult = 1.2
            g.projectile_radius = 4.0
            g.burst_count = 3
            g.burst_gap = 0.08
            g.alt_element = Element.Kind.FIRE
        _:
            push_error("Unknown gun id: %s" % id)
    return g
