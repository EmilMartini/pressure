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
    # Arsenal expansion batch 1: melee (section 4.2), the 23 new non-legendary ones.
    "tin_sabre", "ember_brand", "frost_hatchet", "tide_spear", "spark_knuckles", "bone_club",
    "thorn_whip", "pitch_cleaver", "gale_glaive", "etching_claws", "blood_rapier",
    "sanctified_mace", "hollow_sickle", "storm_lash", "parry_blade", "magma_maul", "rimefang",
    "venom_pike", "crimson_gauntlets", "riptide_whip", "thunder_halberd", "eclipse_scythe",
    "twin_fangs",
    # Arsenal expansion batch 2: thrown (section 4.3), the 16 new non-legendary ones.
    "steel_knives", "clay_grenade", "shock_bola", "frost_javelin", "fire_bottle", "tide_discus",
    "venom_fan", "holy_water", "wind_star", "void_grenade", "cluster_bomb", "etching_javelin",
    "halo_disc", "storm_kunai", "crossing_axes", "drowned_anchor",
    # ... and the 11 new non-legendary guns (section 4.1).
    "old_six", "rime_repeater", "bubble_gun", "ember_scattergun", "gale_longbow", "acid_darts",
    "glint_beam", "harpoon", "longshot", "blood_hymn", "singularity",
    # Arsenal expansion batch 3: summons (section 4.4), the 20 new non-legendary ones.
    "scout_drone", "ember_imp", "orbit_stones", "wasp_nest", "frost_sentry", "rain_drone",
    "tar_crawler", "storm_kite", "acid_slime", "holy_wisps", "leech_jar", "watchers_eye",
    "tesla_post", "blood_hound", "clay_golem", "mortar_drone", "frost_blades", "thunderhead",
    "sun_and_moon", "hive_queen",
]

## Arsenal expansion 4.1 to 4.5: every existing weapon's rarity (0 Common .. 4 Legendary)
## and, where it moved family, its style. New weapons carry both in their DEFS entry.
## Arc Rifle is Common because it is a fresh-save starter.
const RARITY_OF := {
    "water_pistol": 0, "flare_pistol": 0, "vein_pistol": 0, "slick_wand": 0, "spark_needler": 0,
    "venom_spitter": 0, "gravel_shotgun": 0, "etcher_beam": 0, "blowtorch": 0, "mist_sprayer": 0,
    "arc_rifle": 0, "null_wand": 1, "ember_carbine": 1, "cyclone_flak": 1, "blight_seeker": 1,
    "clot_orb": 1, "radiant_ray": 1, "gale_blaster": 1, "prayer_burst": 1, "stone_sling": 2,
    "hydro_cannon": 2, "cinder_flak": 2, "rift_seeker": 2, "storm_seeker": 2, "blood_lance": 2,
    "eclipse_carbine": 3, "duality_burst": 3, "sun_cannon": 3, "void_orb": 3, "glacier_lance": 3,
    "railgun": 3,
    "storm_pike": 3,
    "zephyr_rang": 0, "oil_slinger": 0, "rime_chakram": 1, "acid_flask": 1, "plague_mortar": 1,
    "boulder_mortar": 2, "napalm_lobber": 2,
    "kettle_gun": 2,
    "frost_caster": 0, "tar_mortar": 2, "corrosion_burst": 2,
}
const STYLE_OF := {
    "storm_pike": "sweep",
    "zephyr_rang": "boomerang", "rime_chakram": "boomerang", "oil_slinger": "pool", "acid_flask": "pool",
    "plague_mortar": "pool", "boulder_mortar": "lob", "napalm_lobber": "lob",
    "kettle_gun": "turret",
    "frost_caster": "pulse", "tar_mortar": "mine", "corrosion_burst": "mine",
}

const K := Element.Kind

## Arsenal expansion 3.2: weapon rarity odds per floor (percent, Common to Legendary) for
## the shop row; the boss row moves everything under Rare into Rare; treasure is never
## Common and has its own Legendary share (used from batch 5, when legendaries exist).
const RARITY_ODDS := [
    [65.0, 30.0, 5.0, 0.0, 0.0],
    [45.0, 35.0, 15.0, 4.0, 1.0],
    [30.0, 35.0, 23.0, 9.5, 2.5],
    [20.0, 32.0, 29.0, 15.0, 4.0],
    [12.0, 28.0, 33.0, 21.0, 6.0],
]
const TREASURE_LEGENDARY := [3.0, 5.0, 8.0, 11.0, 14.0]
## 3.2 deeper Commons: Common and Uncommon weapons in the shop and treasure arrive at tier II
## this often (by floor; floors 1 and 2 never).
const DEEP_TIER2 := [0.0, 0.0, 0.30, 0.50, 0.50]
## 3.4: the Gunsmith's price times the rarity factor of the weapon it raises.
const SMITH_FACTOR := [1.0, 1.2, 1.4, 1.7, 2.0]
## 3.4: duplicate weight by rarity (Drops.DUPLICATE_MULT in full for Common and Uncommon,
## half for Rare, a quarter for Epic; Legendaries never twice).
const DUPLICATE_SHARE := [1.0, 1.0, 0.5, 0.25, 0.0]
## 3.2 weapon sources: the chance one card of the row is a weapon.
const SHOP_WEAPON_SHARE := 0.70
const TREASURE_WEAPON := 0.35
const BOSS_WEAPON := 0.25
const BOSS_WEAPON_FROM := 2
const CHALLENGE_WEAPON := 0.30
const DEAL_WEAPON := 0.40


## Shop price of a weapon (3.4): PRICE_BASE[rarity] x (0.8 + 0.1 x weight) x depth.
func price(data: GunData, floor_number: int) -> int:
    var base := float(Items.PRICE_BASE[clampi(data.rarity, 0, Items.PRICE_BASE.size() - 1)])
    return int(roundf(base * (0.8 + 0.1 * float(data.weight)) * Items.depth_mult(floor_number)))


## Tier II now and then for a deep Common or Uncommon (3.2).
func deep_tier(rarity: int, floor_number: int) -> int:
    if rarity > Items.Rarity.UNCOMMON:
        return 1
    var p := float(DEEP_TIER2[clampi(floor_number, 1, DEEP_TIER2.size()) - 1])
    return 2 if randf() < p else 1

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

    # --- Melee (Arsenal expansion 2.3, 4.2) --------------------------------------------
    # Single-target dps about 130% of the gun band for the weight (the risk of standing
    # close), times the rarity premium: damage = band x 1.3 x premium / (rate x the style
    # and rule factor in Melee.single_mult). Hits past the first in a swing take 25%, at
    # most 12 a swing. Pressure per second about a gun's of the same weight.
    "tin_sabre": { "display_name": "Tin Sabre", "archetype": "melee", "style": "sweep", "rarity": 0, "element": K.NONE,
        "weight": 2, "damage": 20.0, "fire_rate": 1.6, "max_range": 100.0, "arc_deg": 130.0, "knockback": 60.0,
        "reaction_mult": 0.0 },
    "ember_brand": { "display_name": "Ember Brand", "archetype": "melee", "style": "sweep", "rarity": 0, "element": K.FIRE,
        "weight": 2, "damage": 11.0, "fire_rate": 1.5, "max_range": 100.0, "arc_deg": 130.0, "knockback": 50.0,
        "pressure_per_shot": 5.0, "reaction_mult": 1.2 },
    "frost_hatchet": { "display_name": "Frost Hatchet", "archetype": "melee", "style": "cleave", "rarity": 0, "element": K.ICE,
        "weight": 3, "damage": 39.0, "fire_rate": 0.95, "max_range": 110.0, "arc_deg": 200.0, "knockback": 150.0,
        "pressure_per_shot": -5.0, "reaction_mult": 0.9 },
    "tide_spear": { "display_name": "Tide Spear", "archetype": "melee", "style": "thrust", "rarity": 0, "element": K.WET,
        "weight": 2, "damage": 18.0, "fire_rate": 1.8, "max_range": 155.0, "arc_deg": 25.0, "knockback": 30.0,
        "pressure_per_shot": -2.5, "reaction_mult": 1.2 },
    "spark_knuckles": { "display_name": "Spark Knuckles", "archetype": "melee", "style": "jab", "rarity": 0, "element": K.SHOCK,
        "weight": 1, "damage": 4.9, "fire_rate": 3.4, "max_range": 72.0, "arc_deg": 70.0, "knockback": 10.0,
        "pressure_per_shot": 2.0, "reaction_mult": 2.0 },
    "bone_club": { "display_name": "Bone Club", "archetype": "melee", "style": "slam", "rarity": 0, "element": K.STONE,
        "weight": 3, "damage": 47.0, "fire_rate": 0.85, "max_range": 60.0, "aura_radius": 70.0, "knockback": 40.0,
        "pressure_per_shot": 1.0, "reaction_mult": 1.0 },
    "thorn_whip": { "display_name": "Thorn Whip", "archetype": "melee", "style": "lash", "rarity": 0, "element": K.POISON,
        "weight": 2, "damage": 24.5, "fire_rate": 1.2, "max_range": 175.0, "arc_deg": 60.0, "knockback": 20.0,
        "pressure_per_shot": 0.5, "reaction_mult": 1.2 },
    "pitch_cleaver": { "display_name": "Pitch Cleaver", "archetype": "melee", "style": "cleave", "rarity": 1, "element": K.OIL,
        "weight": 4, "damage": 65.0, "fire_rate": 0.9, "max_range": 115.0, "arc_deg": 200.0, "knockback": 150.0,
        "pressure_per_shot": 1.0, "reaction_mult": 1.2 },
    "gale_glaive": { "display_name": "Gale Glaive", "archetype": "melee", "style": "spin", "rarity": 1, "element": K.GALE,
        "weight": 3, "damage": 30.5, "fire_rate": 1.2, "max_range": 100.0, "arc_deg": 150.0, "knockback": 60.0,
        "pressure_per_shot": -2.0, "reaction_mult": 1.0 },
    "etching_claws": { "display_name": "Etching Claws", "archetype": "melee", "style": "jab", "rarity": 1, "element": K.ACID,
        "weight": 1, "damage": 3.3, "fire_rate": 3.5, "max_range": 76.0, "arc_deg": 70.0, "knockback": 10.0,
        "pressure_per_shot": 2.0, "reaction_mult": 1.8 },
    "blood_rapier": { "display_name": "Blood Rapier", "archetype": "melee", "style": "thrust", "rarity": 1, "element": K.BLOOD,
        "weight": 2, "damage": 11.4, "fire_rate": 2.0, "max_range": 150.0, "arc_deg": 25.0, "knockback": 20.0,
        "reaction_mult": 1.4 },
    "sanctified_mace": { "display_name": "Sanctified Mace", "archetype": "melee", "style": "slam", "rarity": 1, "element": K.HOLY,
        "weight": 3, "damage": 49.0, "fire_rate": 0.85, "max_range": 60.0, "aura_radius": 70.0, "knockback": 40.0,
        "pressure_per_shot": 1.0, "reaction_mult": 1.2 },
    "hollow_sickle": { "display_name": "Hollow Sickle", "archetype": "melee", "style": "spin", "rarity": 1, "element": K.VOID,
        "weight": 2, "damage": 26.0, "fire_rate": 1.25, "max_range": 100.0, "arc_deg": 150.0, "knockback": 40.0,
        "pressure_per_shot": -1.0, "reaction_mult": 1.2 },
    "storm_lash": { "display_name": "Storm Lash", "archetype": "melee", "style": "lash", "rarity": 1, "element": K.SHOCK,
        "weight": 2, "damage": 22.0, "fire_rate": 1.2, "max_range": 180.0, "arc_deg": 45.0, "knockback": 20.0,
        "pressure_per_shot": 3.0, "reaction_mult": 1.2 },
    "parry_blade": { "display_name": "Parry Blade", "archetype": "melee", "style": "sweep", "rarity": 2, "element": K.GALE,
        "weight": 3, "damage": 29.0, "fire_rate": 1.4, "max_range": 105.0, "arc_deg": 140.0, "knockback": 60.0,
        "pressure_per_shot": -2.0, "reaction_mult": 1.0 },
    "magma_maul": { "display_name": "Magma Maul", "archetype": "melee", "style": "slam", "rarity": 2, "element": K.FIRE,
        "weight": 5, "damage": 100.0, "fire_rate": 0.75, "max_range": 60.0, "aura_radius": 70.0, "knockback": 60.0,
        "pressure_per_shot": 10.0, "reaction_mult": 0.8 },
    "rimefang": { "display_name": "Rimefang", "archetype": "melee", "style": "thrust", "rarity": 2, "element": K.ICE,
        "weight": 4, "damage": 38.0, "fire_rate": 1.5, "max_range": 165.0, "arc_deg": 25.0, "knockback": 30.0,
        "pressure_per_shot": -4.0, "reaction_mult": 1.2 },
    "venom_pike": { "display_name": "Venom Pike", "archetype": "melee", "style": "thrust", "rarity": 2, "element": K.POISON,
        "weight": 3, "damage": 28.5, "fire_rate": 1.6, "max_range": 160.0, "arc_deg": 25.0, "knockback": 30.0,
        "pressure_per_shot": 0.5, "reaction_mult": 1.2 },
    "crimson_gauntlets": { "display_name": "Crimson Gauntlets", "archetype": "melee", "style": "jab", "rarity": 2, "element": K.BLOOD,
        "weight": 2, "damage": 8.1, "fire_rate": 3.2, "max_range": 75.0, "arc_deg": 70.0, "knockback": 10.0,
        "reaction_mult": 1.6 },
    "riptide_whip": { "display_name": "Riptide Whip", "archetype": "melee", "style": "lash", "rarity": 2, "element": K.WET,
        "weight": 2, "damage": 31.0, "fire_rate": 1.15, "max_range": 185.0, "arc_deg": 50.0, "knockback": 20.0,
        "pressure_per_shot": -3.0, "reaction_mult": 1.2 },
    "thunder_halberd": { "display_name": "Thunder Halberd", "archetype": "melee", "style": "thrust", "rarity": 3, "element": K.WET,
        "alt_element": K.SHOCK, "weight": 4, "damage": 13.5, "fire_rate": 1.4, "max_range": 160.0, "arc_deg": 25.0,
        "knockback": 30.0, "pressure_per_shot": 2.0, "reaction_mult": 0.3 },
    "eclipse_scythe": { "display_name": "Eclipse Scythe", "archetype": "melee", "style": "spin", "rarity": 3, "element": K.HOLY,
        "alt_element": K.VOID, "weight": 4, "damage": 29.0, "fire_rate": 1.2, "max_range": 100.0, "arc_deg": 150.0,
        "knockback": 60.0, "reaction_mult": 0.1 },
    "twin_fangs": { "display_name": "Twin Fangs", "archetype": "melee", "style": "sweep", "rarity": 3, "element": K.POISON,
        "alt_element": K.BLOOD, "weight": 3, "damage": 7.5, "fire_rate": 1.5, "max_range": 95.0, "arc_deg": 130.0,
        "knockback": 40.0, "pressure_per_shot": 0.5, "reaction_mult": 0.4 },

    # --- Thrown (Arsenal expansion 2.4, 4.3; Thrown) ---------------------------------
    # Single-target dps 95 to 105% of the gun band for the weight, times the rarity premium.
    # They win on returns, pins and pools, not on raw damage. `ricochets` is a disc's extra
    # jumps; `linger` is a grenade's fuse.
    "steel_knives": { "display_name": "Steel Knives", "archetype": "knife", "behaviour": "knife", "rarity": 0, "element": K.NONE,
        "weight": 1, "damage": 3.0, "fire_rate": 1.3, "projectile_speed": 620.0, "projectile_count": 3, "spread_deg": 24.0,
        "max_range": 380.0, "lifetime": 0.55, "projectile_radius": 4.0, "reaction_mult": 0.0 },
    "clay_grenade": { "display_name": "Clay Grenade", "archetype": "grenade", "behaviour": "grenade", "rarity": 0, "element": K.STONE,
        "weight": 2, "damage": 20.5, "fire_rate": 1.05, "projectile_speed": 430.0, "spread_deg": 6.0, "max_range": 260.0,
        "lifetime": 0.8, "linger": 0.8, "splash_radius": 60.0, "shard_count": 4, "projectile_radius": 6.0,
        "pressure_per_shot": 1.0, "reaction_mult": 1.2 },
    "shock_bola": { "display_name": "Shock Bola", "archetype": "bola", "behaviour": "bola", "rarity": 0, "element": K.SHOCK,
        "weight": 2, "damage": 17.0, "fire_rate": 1.4, "projectile_speed": 560.0, "spread_deg": 4.0, "max_range": 360.0,
        "lifetime": 0.65, "projectile_radius": 6.0, "pressure_per_shot": 3.0, "reaction_mult": 1.3 },
    "frost_javelin": { "display_name": "Frost Javelin", "archetype": "javelin", "behaviour": "javelin", "rarity": 0, "element": K.ICE,
        "weight": 3, "damage": 28.0, "fire_rate": 1.2, "projectile_speed": 480.0, "spread_deg": 2.0, "max_range": 460.0,
        "lifetime": 0.95, "pierce": 2, "projectile_radius": 6.0, "pressure_per_shot": -4.0, "reaction_mult": 1.3 },
    "fire_bottle": { "display_name": "Fire Bottle", "archetype": "thrower", "style": "pool", "behaviour": "pool", "rarity": 0, "element": K.FIRE,
        "weight": 2, "damage": 2.4, "fire_rate": 0.8, "projectile_speed": 420.0, "spread_deg": 10.0, "max_range": 330.0,
        "lifetime": 0.8, "projectile_radius": 5.0, "aura_radius": 55.0, "linger": 3.0, "pressure_per_shot": 3.0, "reaction_mult": 1.6 },
    "tide_discus": { "display_name": "Tide Discus", "archetype": "disc", "behaviour": "disc", "rarity": 1, "element": K.WET,
        "weight": 2, "damage": 10.0, "fire_rate": 1.3, "projectile_speed": 560.0, "spread_deg": 4.0, "max_range": 380.0,
        "lifetime": 0.7, "ricochets": 3, "projectile_radius": 6.0, "pressure_per_shot": -2.0, "reaction_mult": 1.3 },
    "venom_fan": { "display_name": "Venom Fan", "archetype": "knife", "behaviour": "knife", "rarity": 1, "element": K.POISON,
        "weight": 1, "damage": 3.0, "fire_rate": 1.2, "projectile_speed": 600.0, "projectile_count": 5, "spread_deg": 60.0,
        "max_range": 340.0, "lifetime": 0.5, "projectile_radius": 4.0, "pressure_per_shot": 0.5, "reaction_mult": 1.4 },
    "holy_water": { "display_name": "Holy Water", "archetype": "thrower", "style": "pool", "behaviour": "pool", "rarity": 1, "element": K.HOLY,
        "weight": 2, "damage": 1.8, "fire_rate": 0.8, "projectile_speed": 420.0, "spread_deg": 10.0, "max_range": 330.0,
        "lifetime": 0.8, "projectile_radius": 5.0, "aura_radius": 60.0, "linger": 3.5, "pressure_per_shot": 1.0, "reaction_mult": 1.6 },
    "wind_star": { "display_name": "Wind Star", "archetype": "star", "behaviour": "star", "rarity": 1, "element": K.GALE,
        "weight": 1, "damage": 8.0, "fire_rate": 1.1, "projectile_speed": 520.0, "spread_deg": 4.0, "max_range": 380.0,
        "lifetime": 1.2, "projectile_radius": 6.0, "pressure_per_shot": -1.0, "reaction_mult": 1.2 },
    "void_grenade": { "display_name": "Void Grenade", "archetype": "grenade", "behaviour": "grenade", "rarity": 1, "element": K.VOID,
        "weight": 2, "damage": 26.0, "fire_rate": 0.95, "projectile_speed": 400.0, "spread_deg": 6.0, "max_range": 260.0,
        "lifetime": 1.0, "linger": 1.0, "splash_radius": 70.0, "projectile_radius": 6.0, "pressure_per_shot": -1.0, "reaction_mult": 1.3 },
    "cluster_bomb": { "display_name": "Cluster Bomb", "archetype": "grenade", "behaviour": "grenade", "rarity": 2, "element": K.FIRE,
        "weight": 4, "damage": 33.0, "fire_rate": 0.9, "projectile_speed": 420.0, "spread_deg": 6.0, "max_range": 280.0,
        "lifetime": 0.8, "linger": 0.8, "splash_radius": 60.0, "projectile_radius": 7.0, "pressure_per_shot": 5.0, "reaction_mult": 1.3 },
    "etching_javelin": { "display_name": "Etching Javelin", "archetype": "javelin", "behaviour": "javelin", "rarity": 2, "element": K.ACID,
        "weight": 3, "damage": 22.0, "fire_rate": 1.3, "projectile_speed": 500.0, "spread_deg": 2.0, "max_range": 460.0,
        "lifetime": 0.95, "projectile_radius": 6.0, "pressure_per_shot": 2.0, "reaction_mult": 1.3 },
    "halo_disc": { "display_name": "Halo Disc", "archetype": "disc", "behaviour": "disc", "rarity": 2, "element": K.HOLY,
        "weight": 3, "damage": 15.0, "fire_rate": 1.2, "projectile_speed": 540.0, "spread_deg": 4.0, "max_range": 400.0,
        "lifetime": 0.75, "ricochets": 3, "projectile_radius": 7.0, "pressure_per_shot": 1.0, "reaction_mult": 1.3 },
    "storm_kunai": { "display_name": "Storm Kunai", "archetype": "knife", "behaviour": "knife", "rarity": 2, "element": K.SHOCK,
        "weight": 2, "damage": 4.0, "fire_rate": 1.3, "projectile_speed": 660.0, "projectile_count": 3, "spread_deg": 28.0,
        "max_range": 380.0, "lifetime": 0.55, "projectile_radius": 4.0, "pressure_per_shot": 2.0, "reaction_mult": 1.2 },
    "crossing_axes": { "display_name": "Crossing Axes", "archetype": "boomerang", "behaviour": "boomerang", "rarity": 3, "element": K.ICE,
        "alt_element": K.FIRE, "weight": 4, "damage": 19.0, "fire_rate": 1.1, "projectile_speed": 520.0, "projectile_count": 2,
        "spread_deg": 2.0, "max_range": 380.0, "lifetime": 1.1, "pierce": 3, "projectile_radius": 7.0, "reaction_mult": 0.12 },
    "drowned_anchor": { "display_name": "Drowned Anchor", "archetype": "anchor", "behaviour": "anchor", "rarity": 3, "element": K.WET,
        "extra_element": K.STONE, "weight": 5, "damage": 38.0, "fire_rate": 0.8, "projectile_speed": 460.0, "spread_deg": 2.0,
        "max_range": 360.0, "lifetime": 1.0, "pierce": 99, "projectile_radius": 10.0, "pressure_per_shot": -3.0, "reaction_mult": 0.4 },

    # --- New guns (Arsenal expansion 4.1, batch 2) -------------------------------------
    "old_six": { "display_name": "Old Six", "archetype": "revolver", "rarity": 0, "element": K.STONE, "weight": 2,
        "damage": 9.0, "fire_rate": 7.0, "projectile_speed": 820.0, "spread_deg": 5.0, "max_range": 460.0, "lifetime": 0.6,
        "magazine": 6, "reload_time": 1.4, "pressure_per_shot": 0.3, "reaction_mult": 1.0, "projectile_radius": 4.0 },
    "rime_repeater": { "display_name": "Rime Repeater", "archetype": "repeater", "rarity": 0, "element": K.ICE, "weight": 2,
        "damage": 2.6, "fire_rate": 9.0, "projectile_speed": 600.0, "spread_deg": 10.0, "max_range": 420.0, "lifetime": 0.7,
        "pressure_per_shot": -0.5, "projectile_radius": 4.0, "spin_up": 1.5, "reaction_mult": 1.0 },
    "bubble_gun": { "display_name": "Bubble Gun", "archetype": "bubble", "behaviour": "bubble", "rarity": 0, "element": K.WET, "weight": 1,
        "damage": 6.0, "fire_rate": 2.8, "projectile_speed": 260.0, "spread_deg": 8.0, "max_range": 380.0, "lifetime": 1.4,
        "pressure_per_shot": -2.0, "projectile_radius": 7.0, "reaction_mult": 1.2 },
    "ember_scattergun": { "display_name": "Ember Scattergun", "archetype": "shotgun", "rarity": 1, "element": K.FIRE, "weight": 3,
        "damage": 2.6, "fire_rate": 2.2, "projectile_speed": 620.0, "projectile_count": 6, "spread_deg": 36.0, "max_range": 240.0,
        "lifetime": 0.4, "knockback": 50.0, "pressure_per_shot": 4.0, "reaction_mult": 1.0 },
    "gale_longbow": { "display_name": "Gale Longbow", "archetype": "bow", "rarity": 1, "element": K.GALE, "weight": 2,
        "damage": 16.0, "fire_rate": 1.6, "projectile_speed": 900.0, "spread_deg": 2.0, "max_range": 560.0, "lifetime": 0.7,
        "pierce": 2, "knockback": 120.0, "pressure_per_shot": -1.0, "projectile_radius": 4.0, "reaction_mult": 1.2 },
    "acid_darts": { "display_name": "Acid Darts", "archetype": "sticky", "behaviour": "sticky", "rarity": 1, "element": K.ACID, "weight": 2,
        "damage": 6.5, "fire_rate": 2.0, "projectile_speed": 700.0, "spread_deg": 5.0, "max_range": 420.0, "lifetime": 0.6,
        "splash_radius": 45.0, "pressure_per_shot": 1.5, "projectile_radius": 4.0, "reaction_mult": 1.3 },
    "glint_beam": { "display_name": "Glint Beam", "archetype": "reflect", "rarity": 2, "element": K.ICE, "weight": 3,
        "damage": 3.7, "fire_rate": 10.0, "max_range": 440.0, "pressure_per_shot": -0.3, "pierce": 1, "projectile_radius": 3.0,
        "ricochets": 2, "reaction_mult": 1.0 },
    "harpoon": { "display_name": "Harpoon", "archetype": "harpoon", "behaviour": "harpoon", "rarity": 2, "element": K.OIL, "weight": 4,
        "damage": 37.0, "fire_rate": 1.3, "projectile_speed": 900.0, "spread_deg": 2.0, "max_range": 460.0, "lifetime": 0.55,
        "pressure_per_shot": 1.0, "projectile_radius": 5.0, "reaction_mult": 1.6 },
    "longshot": { "display_name": "Longshot", "archetype": "sniper", "rarity": 2, "element": K.NONE, "weight": 4,
        "damage": 30.0, "fire_rate": 1.0, "projectile_speed": 1300.0, "spread_deg": 1.0, "max_range": 760.0, "lifetime": 0.65,
        "projectile_radius": 4.0, "reaction_mult": 0.0 },
    "blood_hymn": { "display_name": "Blood Hymn", "archetype": "hymn", "rarity": 3, "element": K.BLOOD, "weight": 3,
        "damage": 9.3, "fire_rate": 3.0, "projectile_speed": 780.0, "spread_deg": 4.0, "max_range": 460.0, "lifetime": 0.65,
        "projectile_radius": 5.0, "reaction_mult": 1.3 },
    "singularity": { "display_name": "Singularity", "archetype": "shotgun", "behaviour": "converge", "rarity": 3, "element": K.VOID, "weight": 4,
        "damage": 5.3, "fire_rate": 1.4, "projectile_speed": 560.0, "projectile_count": 7, "spread_deg": 70.0, "max_range": 300.0,
        "lifetime": 0.7, "pressure_per_shot": -1.0, "projectile_radius": 4.0, "reaction_mult": 1.0 },
    # --- Summons (Arsenal expansion 4.4, batch 3) ------------------------------------
    # Single-target dps is 70% of the gun band for the weight times the rarity premium
    # (2.5: summons need no aim). For a summon `damage` is per bite, zap or strike,
    # `fire_rate` each body's attacks a second, `projectile_speed` how fast it moves (an
    # orbit's rim speed), `max_range` how far from itself a body looks, `aura_radius` an
    # orbit's ring, a rain or slam area, `cap` the bodies kept up.
    "scout_drone": { "display_name": "Scout Drone", "archetype": "drone", "behaviour": "zap", "rarity": 0, "element": K.SHOCK,
        "weight": 1, "cap": 1, "damage": 4.9, "fire_rate": 2.5, "projectile_speed": 260.0, "max_range": 300.0,
        "pressure_per_shot": 0.6, "reaction_mult": 1.0 },
    "ember_imp": { "display_name": "Ember Imp", "archetype": "familiar", "rarity": 0, "element": K.FIRE,
        "weight": 2, "cap": 1, "damage": 11.0, "fire_rate": 1.6, "projectile_speed": 230.0, "max_range": 280.0,
        "pressure_per_shot": 1.5, "reaction_mult": 1.2 },
    "orbit_stones": { "display_name": "Orbit Stones", "archetype": "orbit", "rarity": 0, "element": K.STONE,
        "weight": 2, "cap": 3, "damage": 10.7, "fire_rate": 1.5, "projectile_speed": 240.0, "max_range": 120.0,
        "aura_radius": 70.0, "knockback": 160.0, "reaction_mult": 1.2 },
    "wasp_nest": { "display_name": "Wasp Nest", "archetype": "swarm", "rarity": 0, "element": K.POISON,
        "weight": 2, "cap": 5, "damage": 9.8, "fire_rate": 2.0, "projectile_speed": 300.0, "max_range": 300.0,
        "pressure_per_shot": 0.3, "reaction_mult": 1.2 },
    "frost_sentry": { "display_name": "Frost Sentry", "archetype": "turret", "rarity": 0, "element": K.ICE,
        "weight": 3, "damage": 9.9, "fire_rate": 2.4, "projectile_speed": 600.0, "spread_deg": 4.0, "max_range": 380.0,
        "lifetime": 0.7, "linger": 8.0, "projectile_radius": 5.0, "pressure_per_shot": -1.5, "reaction_mult": 1.3 },
    "rain_drone": { "display_name": "Rain Drone", "archetype": "drone", "behaviour": "rain", "rarity": 1, "element": K.WET,
        "weight": 2, "cap": 1, "damage": 13.1, "fire_rate": 1.4, "projectile_speed": 240.0, "max_range": 300.0,
        "aura_radius": 50.0, "pressure_per_shot": -1.5, "reaction_mult": 1.3 },
    "tar_crawler": { "display_name": "Tar Crawler", "archetype": "familiar", "rarity": 1, "element": K.OIL,
        "weight": 2, "cap": 1, "damage": 12.3, "fire_rate": 1.5, "projectile_speed": 200.0, "max_range": 280.0,
        "pressure_per_shot": 0.8, "reaction_mult": 1.3 },
    "storm_kite": { "display_name": "Storm Kite", "archetype": "orbit", "rarity": 1, "element": K.GALE,
        "weight": 2, "cap": 1, "damage": 30.0, "fire_rate": 1.5, "projectile_speed": 400.0, "max_range": 140.0,
        "aura_radius": 90.0, "knockback": 80.0, "pressure_per_shot": -0.5, "reaction_mult": 1.2 },
    "acid_slime": { "display_name": "Acid Slime", "archetype": "familiar", "rarity": 1, "element": K.ACID,
        "weight": 2, "cap": 1, "damage": 7.7, "fire_rate": 1.4, "projectile_speed": 170.0, "max_range": 260.0,
        "pressure_per_shot": 1.0, "reaction_mult": 1.3 },
    "holy_wisps": { "display_name": "Holy Wisps", "archetype": "swarm", "rarity": 1, "element": K.HOLY,
        "weight": 1, "cap": 3, "damage": 12.0, "fire_rate": 2.0, "projectile_speed": 320.0, "max_range": 300.0,
        "pressure_per_shot": 0.3, "reaction_mult": 1.2 },
    "leech_jar": { "display_name": "Leech Jar", "archetype": "swarm", "behaviour": "latch", "rarity": 1, "element": K.BLOOD,
        "weight": 2, "cap": 3, "damage": 4.1, "fire_rate": 1.5, "projectile_speed": 260.0, "max_range": 280.0,
        "pressure_per_shot": 0.2, "reaction_mult": 1.2 },
    "watchers_eye": { "display_name": "Watcher's Eye", "archetype": "drone", "behaviour": "zap", "rarity": 2, "element": K.VOID,
        "weight": 3, "cap": 1, "damage": 16.4, "fire_rate": 1.6, "projectile_speed": 240.0, "max_range": 340.0,
        "pressure_per_shot": -0.5, "reaction_mult": 1.3 },
    "tesla_post": { "display_name": "Tesla Post", "archetype": "turret", "rarity": 2, "element": K.SHOCK,
        "weight": 3, "damage": 17.5, "fire_rate": 1.5, "max_range": 300.0, "chain_jumps": 2, "linger": 8.0,
        "pressure_per_shot": 2.0, "reaction_mult": 1.2 },
    "blood_hound": { "display_name": "Blood Hound", "archetype": "familiar", "rarity": 2, "element": K.BLOOD,
        "weight": 3, "cap": 1, "damage": 23.8, "fire_rate": 1.1, "projectile_speed": 240.0, "max_range": 300.0,
        "pressure_per_shot": 0.8, "reaction_mult": 1.3 },
    "clay_golem": { "display_name": "Clay Golem", "archetype": "golem", "rarity": 2, "element": K.STONE,
        "weight": 5, "cap": 1, "damage": 47.0, "fire_rate": 0.9, "projectile_speed": 120.0, "max_range": 240.0,
        "aura_radius": 70.0, "knockback": 200.0, "reaction_mult": 1.6 },
    "mortar_drone": { "display_name": "Mortar Drone", "archetype": "drone", "behaviour": "lob", "rarity": 2, "element": K.OIL,
        "weight": 4, "cap": 1, "damage": 31.0, "fire_rate": 1.0, "projectile_speed": 380.0, "spread_deg": 4.0, "max_range": 380.0,
        "lifetime": 0.9, "splash_radius": 55.0, "projectile_radius": 6.0, "pressure_per_shot": 1.5, "reaction_mult": 1.5 },
    "frost_blades": { "display_name": "Frost Blades", "archetype": "orbit", "rarity": 2, "element": K.ICE,
        "weight": 3, "cap": 2, "damage": 25.0, "fire_rate": 1.5, "projectile_speed": 300.0, "max_range": 120.0,
        "aura_radius": 60.0, "pressure_per_shot": -1.0, "reaction_mult": 1.3 },
    "thunderhead": { "display_name": "Thunderhead", "archetype": "drone", "behaviour": "rain", "rarity": 3, "element": K.SHOCK,
        "extra_element": K.WET, "weight": 4, "cap": 1, "damage": 15.0, "fire_rate": 1.2, "projectile_speed": 220.0,
        "max_range": 320.0, "aura_radius": 55.0, "pressure_per_shot": 1.0, "reaction_mult": 0.3 },
    "sun_and_moon": { "display_name": "Sun and Moon", "archetype": "familiar", "rarity": 3, "element": K.HOLY,
        "alt_element": K.VOID, "weight": 4, "cap": 2, "damage": 9.5, "fire_rate": 1.4, "projectile_speed": 240.0,
        "max_range": 300.0, "reaction_mult": 0.3 },
    "hive_queen": { "display_name": "Hive Queen", "archetype": "swarm", "rarity": 3, "element": K.POISON,
        "extra_element": K.GALE, "weight": 4, "cap": 4, "damage": 22.5, "fire_rate": 2.0, "projectile_speed": 320.0,
        "max_range": 320.0, "pressure_per_shot": 0.3, "reaction_mult": 0.3 },
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
    if not def.has("family"):
        g.family = String(GunData.FAMILY_OF.get(g.archetype, "gun"))
    if not def.has("rarity"):
        g.rarity = int(RARITY_OF.get(id, 0))
    if not def.has("style"):
        g.style = String(STYLE_OF.get(id, g.archetype))
    return g


func rarity_of(id: String) -> int:
    var def: Dictionary = DEFS.get(id, {})
    return int(def.get("rarity", RARITY_OF.get(id, 0)))


func family_of(id: String) -> String:
    var def: Dictionary = DEFS.get(id, {})
    if def.has("family"):
        return String(def["family"])
    return String(GunData.FAMILY_OF.get(String(def.get("archetype", "")), "gun"))
