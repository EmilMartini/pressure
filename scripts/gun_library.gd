extends Node
## Autoload "Guns": the gun pool. `ids()` is what runs can offer (gated by Progress
## unlocks), `all_ids()` is everything that exists. Ids never change (saves, unlocks,
## Mastery, the Journal and telemetry use them); names and mechanics may.
##
## Every archetype fires its own way (GunData.ARCHETYPES, Gun.fire), at most three guns
## share one, and no element has two guns of one archetype. Roles:
##   pistol    plain aimed shots, the long-reach starter            water, fire, blood
##   burst     three-round bursts                                   fire, holy+void
##   repeater  spins up from 40% to full rate while firing          shock, poison
##   shotgun   pellet spread, knockback, point blank                stone
##   sling     caroms off walls and enemies                         stone
##   helix     two elements twisted together, reacts with itself    ice+fire
##   wand      splits into bolts on the first hit                   oil, void
##   cannon    huge slow ball through everything, shoves            wet, holy
##   flak      proximity burst into shards                          fire, gale
##   homing    seekers spread over different enemies                poison, void, shock+wet
##   boomerang out and back through everything                      ice, gale
##   orb       slow orb pulsing damage around it                    void (pulls), blood
##   mortar    lobbed over cover, big splash                        stone, fire+oil
##   thrower   thrown flask, lingering pool                         acid, oil, poison
##   beam      continuous ray, ticks, sweeps toward the aim         holy, acid
##   sprayer   short cone that hits all in it, paints the floor     fire, wet, gale
##   chain     arc jumping between enemies                          shock, holy
##   nova      ring around you                                      ice
##   melee     sweep in front of you                                shock
##   charge    wind-up, then a rail through the line                ice, blood, none
##   mine      tossed mines that burst on contact                   oil, acid
##   turret    a turret that fires on its own                       wet+fire
##
## Balance, measured with `--gun-probe` (scripts/gun_probe.gd: each gun alone at tier I
## against pinned dummies, one at 75 px and a pack of eight at 95 px). Single-target dps
## bands by weight: w1 15-20, w2 22-28, w3 30-38, w4 40-48, w5 50-60. A gun that hits
## many (sprays, rings, sweeps, arcs, mines, pools, orbs, mortars) or reaches far sits
## lower on one target; the rule is that no gun beats another of its weight by more than 5%
## on both the single and the pack number. Heavier guns carry more reaction_mult and
## bigger shots.
## Guns that react with themselves (two elements) keep reaction_mult low: their reactions
## are most of their output. Pressure per trigger: hot (fire, shock, acid) positive, cold
## (wet, ice) negative; continuous guns (beam, spray) per tick, so per second it matches.

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

const K := Element.Kind

## id -> the GunData fields that differ from its defaults. `archetype` sets `mechanic`
## (GunData.ARCHETYPES) unless the entry names one.
const DEFS := {
    # --- Pistols: the starters, plain and reliable at range ---------------------------
    "water_pistol": { "display_name": "Water Pistol", "archetype": "pistol", "element": K.WET, "weight": 1,
        "damage": 3.0, "fire_rate": 6.0, "projectile_speed": 750.0, "spread_deg": 6.0, "max_range": 480.0,
        "lifetime": 0.7, "pressure_per_shot": -3.0 },
    "flare_pistol": { "display_name": "Flare Pistol", "archetype": "pistol", "element": K.FIRE, "weight": 1,
        "damage": 4.5, "fire_rate": 3.8, "projectile_speed": 700.0, "spread_deg": 5.0, "max_range": 450.0,
        "lifetime": 0.7, "pressure_per_shot": 3.0 },
    "vein_pistol": { "display_name": "Vein Pistol", "archetype": "pistol", "element": K.BLOOD, "weight": 1,
        "damage": 3.9, "fire_rate": 4.6, "projectile_speed": 800.0, "spread_deg": 5.0, "max_range": 460.0,
        "lifetime": 0.6 },

    # --- Wands: a bolt that splits on the first hit -----------------------------------
    "slick_wand": { "display_name": "Slick Wand", "archetype": "wand", "element": K.OIL, "weight": 1,
        "damage": 2.9, "fire_rate": 5.0, "projectile_speed": 620.0, "spread_deg": 4.0, "max_range": 420.0,
        "lifetime": 0.75, "reaction_mult": 3.0, "behaviour": "fork", "fork_count": 2 },
    "null_wand": { "display_name": "Null Wand", "archetype": "wand", "element": K.VOID, "weight": 2,
        "damage": 3.6, "fire_rate": 5.0, "projectile_speed": 600.0, "spread_deg": 4.0, "max_range": 420.0,
        "lifetime": 0.75, "pressure_per_shot": -1.0, "reaction_mult": 2.8, "behaviour": "fork", "fork_count": 3 },

    # --- Repeaters: spin up while firing ------------------------------------------------
    "spark_needler": { "display_name": "Spark Needler", "archetype": "repeater", "element": K.SHOCK, "weight": 1,
        "damage": 1.4, "fire_rate": 14.0, "projectile_speed": 950.0, "spread_deg": 12.0, "max_range": 360.0,
        "lifetime": 0.4, "pressure_per_shot": 1.6, "projectile_radius": 3.0, "spin_up": 1.5 },
    "venom_spitter": { "display_name": "Venom Spitter", "archetype": "repeater", "element": K.POISON, "weight": 2,
        "damage": 2.1, "fire_rate": 9.0, "projectile_speed": 520.0, "spread_deg": 10.0, "max_range": 420.0,
        "lifetime": 0.8, "pressure_per_shot": 0.4, "projectile_radius": 5.0, "spin_up": 1.5 },

    # --- Bursts --------------------------------------------------------------------------
    "ember_carbine": { "display_name": "Ember Carbine", "archetype": "burst", "element": K.FIRE, "weight": 3,
        "damage": 4.6, "fire_rate": 2.3, "projectile_speed": 850.0, "spread_deg": 4.0, "max_range": 520.0,
        "lifetime": 0.65, "pressure_per_shot": 4.0, "burst_count": 3, "burst_gap": 0.07 },
    "eclipse_carbine": { "display_name": "Eclipse Carbine", "archetype": "burst", "element": K.HOLY, "weight": 4,
        "damage": 3.5, "fire_rate": 2.1, "projectile_speed": 950.0, "spread_deg": 3.0, "max_range": 560.0,
        "lifetime": 0.6, "reaction_mult": 0.2, "projectile_radius": 5.0, "burst_count": 3, "burst_gap": 0.08,
        "alt_element": K.VOID },

    # --- Shotgun, sling, helix -----------------------------------------------------------
    "gravel_shotgun": { "display_name": "Gravel Shotgun", "archetype": "shotgun", "element": K.STONE, "weight": 3,
        "damage": 2.9, "fire_rate": 2.4, "projectile_speed": 620.0, "projectile_count": 6, "spread_deg": 32.0,
        "max_range": 260.0, "lifetime": 0.42, "knockback": 70.0,
        "pierce": 1 },
    "stone_sling": { "display_name": "Stone Sling", "archetype": "sling", "element": K.STONE, "weight": 4,
        "damage": 22.0, "fire_rate": 1.5, "projectile_speed": 620.0, "spread_deg": 3.0, "max_range": 480.0,
        "lifetime": 1.1, "reaction_mult": 1.3, "projectile_radius": 7.0, "behaviour": "ricochet", "ricochets": 3,
        "knockback": 150.0 },
    "duality_burst": { "display_name": "Duality Helix", "archetype": "helix", "element": K.ICE, "weight": 3,
        "damage": 2.6, "fire_rate": 2.6, "projectile_speed": 560.0, "projectile_count": 2, "spread_deg": 3.0,
        "max_range": 460.0, "lifetime": 0.85, "reaction_mult": 0.4, "projectile_radius": 4.0, "behaviour": "helix",
        "alt_element": K.FIRE },

    # --- Cannons: a huge slow ball that ploughs through ----------------------------------
    "hydro_cannon": { "display_name": "Hydro Cannon", "archetype": "cannon", "element": K.WET, "weight": 5,
        "damage": 50.0, "fire_rate": 0.85, "projectile_speed": 380.0, "spread_deg": 2.0, "max_range": 560.0,
        "lifetime": 1.6, "pressure_per_shot": -6.0, "reaction_mult": 1.8, "pierce": 99, "projectile_radius": 16.0,
        "knockback": 230.0 },
    "sun_cannon": { "display_name": "Sun Cannon", "archetype": "cannon", "element": K.HOLY, "weight": 5,
        "damage": 62.0, "fire_rate": 0.75, "projectile_speed": 340.0, "spread_deg": 1.0, "max_range": 520.0,
        "lifetime": 1.7, "pressure_per_shot": 2.0, "reaction_mult": 2.0, "pierce": 99, "projectile_radius": 16.0,
        "splash_radius": 60.0, "knockback": 170.0 },

    # --- Flak: a proximity fuse ----------------------------------------------------------
    "cinder_flak": { "display_name": "Cinder Flak", "archetype": "flak", "element": K.FIRE, "weight": 4,
        "damage": 27.0, "fire_rate": 1.4, "projectile_speed": 600.0, "spread_deg": 4.0, "max_range": 420.0,
        "lifetime": 0.7, "pressure_per_shot": 5.0, "reaction_mult": 1.3, "projectile_radius": 7.0,
        "behaviour": "flak", "shard_count": 6, "splash_radius": 40.0 },
    "cyclone_flak": { "display_name": "Cyclone Flak", "archetype": "flak", "element": K.GALE, "weight": 3,
        "damage": 13.0, "fire_rate": 2.0, "projectile_speed": 650.0, "spread_deg": 6.0, "max_range": 380.0,
        "lifetime": 0.55, "pressure_per_shot": -1.0, "reaction_mult": 1.2, "projectile_radius": 5.0,
        "behaviour": "flak", "shard_count": 5, "splash_radius": 35.0 },

    # --- Homing: seekers spread over targets ---------------------------------------------
    "blight_seeker": { "display_name": "Blight Seeker", "archetype": "homing", "element": K.POISON, "weight": 2,
        "damage": 2.0, "fire_rate": 2.4, "projectile_speed": 380.0, "projectile_count": 3, "spread_deg": 60.0,
        "max_range": 450.0, "lifetime": 1.5, "pressure_per_shot": 0.5, "behaviour": "homing", "homing_turn": 6.0 },
    "rift_seeker": { "display_name": "Rift Seeker", "archetype": "homing", "element": K.VOID, "weight": 3,
        "damage": 6.5, "fire_rate": 2.1, "projectile_speed": 460.0, "projectile_count": 2, "spread_deg": 50.0,
        "max_range": 500.0, "lifetime": 1.4, "pressure_per_shot": -1.0, "reaction_mult": 1.4, "pierce": 1,
        "projectile_radius": 5.0, "behaviour": "homing", "homing_turn": 5.0 },
    "storm_seeker": { "display_name": "Storm Seeker", "archetype": "homing", "element": K.SHOCK, "weight": 4,
        "damage": 4.4, "fire_rate": 2.0, "projectile_speed": 620.0, "projectile_count": 2, "spread_deg": 40.0,
        "max_range": 520.0, "lifetime": 1.0, "pressure_per_shot": 3.0, "reaction_mult": 0.25, "pierce": 1,
        "projectile_radius": 5.0, "behaviour": "homing", "homing_turn": 4.0, "extra_element": K.WET },

    # --- Boomerangs: out and back through everything -------------------------------------
    "rime_chakram": { "display_name": "Rime Chakram", "archetype": "boomerang", "element": K.ICE, "weight": 3,
        "damage": 8.5, "fire_rate": 1.6, "projectile_speed": 520.0, "spread_deg": 4.0, "max_range": 360.0,
        "lifetime": 1.1, "pressure_per_shot": -3.0, "reaction_mult": 1.3, "pierce": 99, "projectile_radius": 7.0,
        "behaviour": "boomerang" },
    "zephyr_rang": { "display_name": "Zephyr Rang", "archetype": "boomerang", "element": K.GALE, "weight": 1,
        "damage": 3.4, "fire_rate": 2.2, "projectile_speed": 600.0, "spread_deg": 4.0, "max_range": 340.0,
        "lifetime": 0.9, "pressure_per_shot": -1.0, "pierce": 99, "projectile_radius": 6.0, "behaviour": "boomerang" },

    # --- Orbs: slow, pulse damage around them --------------------------------------------
    "void_orb": { "display_name": "Void Orb", "archetype": "orb", "element": K.VOID, "weight": 5,
        "damage": 8.5, "fire_rate": 0.7, "projectile_speed": 80.0, "spread_deg": 2.0, "max_range": 420.0,
        "lifetime": 3.0, "pressure_per_shot": -2.0, "reaction_mult": 1.6, "projectile_radius": 11.0,
        "behaviour": "orb", "aura_radius": 70.0, "knockback": -90.0 },
    "clot_orb": { "display_name": "Clot Orb", "archetype": "orb", "element": K.BLOOD, "weight": 3,
        "damage": 4.5, "fire_rate": 0.9, "projectile_speed": 90.0, "spread_deg": 3.0, "max_range": 380.0,
        "lifetime": 2.0, "reaction_mult": 1.6, "projectile_radius": 9.0, "behaviour": "orb", "aura_radius": 60.0},

    # --- Mortars: lobbed over cover, big splash ------------------------------------------
    "boulder_mortar": { "display_name": "Boulder Mortar", "archetype": "mortar", "element": K.STONE, "weight": 5,
        "damage": 40.0, "fire_rate": 0.9, "projectile_speed": 340.0, "spread_deg": 4.0, "max_range": 460.0,
        "lifetime": 1.2, "pressure_per_shot": 1.0, "reaction_mult": 1.6, "projectile_radius": 10.0,
        "behaviour": "lob", "splash_radius": 70.0},
    "napalm_lobber": { "display_name": "Napalm Lobber", "archetype": "mortar", "element": K.FIRE, "weight": 4,
        "damage": 18.0, "fire_rate": 1.0, "projectile_speed": 400.0, "spread_deg": 6.0, "max_range": 440.0,
        "lifetime": 1.1, "pressure_per_shot": 4.0, "reaction_mult": 0.45, "projectile_radius": 8.0,
        "behaviour": "lob", "splash_radius": 60.0, "extra_element": K.OIL },

    # --- Throwers: a flask that leaves a pool --------------------------------------------
    "acid_flask": { "display_name": "Acid Flask", "archetype": "thrower", "element": K.ACID, "weight": 3,
        "damage": 2.7, "fire_rate": 0.8, "projectile_speed": 420.0, "spread_deg": 10.0, "max_range": 340.0,
        "lifetime": 0.8, "pressure_per_shot": 2.0, "reaction_mult": 1.4, "projectile_radius": 5.0,
        "behaviour": "pool", "aura_radius": 55.0, "linger": 3.0},
    "oil_slinger": { "display_name": "Oil Slinger", "archetype": "thrower", "element": K.OIL, "weight": 2,
        "damage": 1.6, "fire_rate": 0.8, "projectile_speed": 420.0, "spread_deg": 12.0, "max_range": 320.0,
        "lifetime": 0.8, "reaction_mult": 2.6, "projectile_radius": 6.0, "behaviour": "pool",
        "aura_radius": 65.0, "linger": 5.0 },
    "plague_mortar": { "display_name": "Plague Mortar", "archetype": "thrower", "element": K.POISON, "weight": 3,
        "damage": 1.8, "fire_rate": 0.7, "projectile_speed": 380.0, "spread_deg": 8.0, "max_range": 400.0,
        "lifetime": 1.0, "pressure_per_shot": 0.5, "reaction_mult": 1.4, "projectile_radius": 6.0,
        "behaviour": "pool", "aura_radius": 60.0, "linger": 3.5},

    # --- Beams: a continuous ray ---------------------------------------------------------
    "radiant_ray": { "display_name": "Radiant Ray", "archetype": "beam", "element": K.HOLY, "weight": 3,
        "damage": 3.2, "fire_rate": 10.0, "max_range": 460.0, "pressure_per_shot": 0.25, "pierce": 1,
        "projectile_radius": 3.0 },
    "etcher_beam": { "display_name": "Etcher Beam", "archetype": "beam", "element": K.ACID, "weight": 2,
        "damage": 2.1, "fire_rate": 10.0, "max_range": 320.0, "pressure_per_shot": 0.3, "projectile_radius": 2.5,
        "paint_every": 0.25,
        "pierce": 1 },

    # --- Sprayers: a short cone that hits all in it --------------------------------------
    "blowtorch": { "display_name": "Blowtorch", "archetype": "sprayer", "element": K.FIRE, "weight": 2,
        "damage": 2.0, "fire_rate": 8.0, "max_range": 150.0, "pressure_per_shot": 3.0, "arc_deg": 50.0,
        "paint_every": 0.3 },
    "mist_sprayer": { "display_name": "Mist Sprayer", "archetype": "sprayer", "element": K.WET, "weight": 2,
        "damage": 1.6, "fire_rate": 8.0, "max_range": 170.0, "pressure_per_shot": -2.0, "arc_deg": 70.0,
        "paint_every": 0.25 },
    "gale_blaster": { "display_name": "Gale Blaster", "archetype": "sprayer", "element": K.GALE, "weight": 2,
        "damage": 2.8, "fire_rate": 6.0, "max_range": 160.0, "pressure_per_shot": -1.0, "arc_deg": 60.0,
        "knockback": 60.0, "paint_every": 0.4 },

    # --- Chains: an arc that jumps -------------------------------------------------------
    "arc_rifle": { "display_name": "Arc Rifle", "archetype": "chain", "element": K.SHOCK, "weight": 3,
        "damage": 12.0, "fire_rate": 2.0, "max_range": 420.0, "pressure_per_shot": 4.0, "reaction_mult": 1.4,
        "chain_jumps": 4, "projectile_speed": 1200.0, "lifetime": 0.4, "projectile_radius": 5.0 },
    "prayer_burst": { "display_name": "Prayer Chain", "archetype": "chain", "element": K.HOLY, "weight": 2,
        "damage": 8.0, "fire_rate": 2.4, "max_range": 400.0, "pressure_per_shot": 1.0, "chain_jumps": 2,
        "projectile_speed": 1000.0, "lifetime": 0.45, "projectile_radius": 4.0 },

    # --- Nova, melee ---------------------------------------------------------------------
    "frost_caster": { "display_name": "Frost Caster", "archetype": "nova", "element": K.ICE, "weight": 2,
        "damage": 8.0, "fire_rate": 1.5, "max_range": 110.0, "pressure_per_shot": -4.0, "reaction_mult": 1.2,
        "knockback": 100.0},
    "storm_pike": { "display_name": "Storm Pike", "archetype": "melee", "element": K.SHOCK, "weight": 5,
        "damage": 28.0, "fire_rate": 1.6, "max_range": 90.0, "pressure_per_shot": 5.0, "reaction_mult": 1.6,
        "arc_deg": 150.0, "knockback": 170.0},

    # --- Charge: wind up, then a rail ----------------------------------------------------
    "glacier_lance": { "display_name": "Glacier Lance", "archetype": "charge", "element": K.ICE, "weight": 5,
        "damage": 70.0, "fire_rate": 1.4, "max_range": 650.0, "pressure_per_shot": -6.0, "reaction_mult": 1.7,
        "projectile_radius": 6.0, "charge_time": 0.7, "knockback": 80.0 },
    "railgun": { "display_name": "Railgun", "archetype": "charge", "element": K.NONE, "weight": 5,
        "damage": 95.0, "fire_rate": 1.5, "max_range": 900.0, "reaction_mult": 0.0, "projectile_radius": 4.0,
        "charge_time": 1.0, "knockback": 120.0 },
    "blood_lance": { "display_name": "Blood Lance", "archetype": "charge", "element": K.BLOOD, "weight": 4,
        "damage": 40.0, "fire_rate": 1.6, "max_range": 600.0, "reaction_mult": 1.4, "projectile_radius": 5.0,
        "charge_time": 0.5 },

    # --- Mines, turret -------------------------------------------------------------------
    "tar_mortar": { "display_name": "Tar Mortar", "archetype": "mine", "element": K.OIL, "weight": 4,
        "damage": 26.0, "fire_rate": 1.3, "max_range": 300.0, "pressure_per_shot": 0.5, "reaction_mult": 1.4,
        "aura_radius": 60.0, "linger": 8.0 },
    "corrosion_burst": { "display_name": "Corrosion Burst", "archetype": "mine", "element": K.ACID, "weight": 4,
        "damage": 17.0, "fire_rate": 1.4, "max_range": 300.0, "pressure_per_shot": 3.0, "reaction_mult": 1.2,
        "aura_radius": 55.0, "linger": 8.0 },
    "kettle_gun": { "display_name": "Kettle Gun", "archetype": "turret", "element": K.WET, "weight": 3,
        "damage": 2.4, "fire_rate": 6.0, "projectile_speed": 650.0, "spread_deg": 12.0, "max_range": 360.0,
        "lifetime": 0.6, "reaction_mult": 0.5, "projectile_radius": 4.0, "linger": 8.0,
        "alt_element": K.FIRE },
}


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
    if not DEFS.has(id):
        push_error("Unknown gun id: %s" % id)
        return g
    var def: Dictionary = DEFS[id]
    for key in def.keys():
        g.set(key, def[key])
    if not def.has("mechanic"):
        g.mechanic = String(GunData.ARCHETYPES.get(g.archetype, ["shot"])[0])
    return g
