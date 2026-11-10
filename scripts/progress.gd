extends Node
## Autoload "Progress": the save file. Isaac-style meta progression: every run starts
## naked, and achievements grow the pool of what a run can contain. Nothing here makes
## a run easier; it only makes runs different. It also counts what the current run did
## (`run_stats`, `run_discoveries`), which the Shrine pays Embers for (see Mastery).

signal unlocked(unlock_id: String, achievement_name: String)

const SAVE_PATH := "user://save.json"

## Always available, run one included.
const BASE_UNLOCKS := ["gun:water_pistol", "gun:arc_rifle", "gun:flare_pistol", "gun:slick_wand", "gun:tin_sabre", "gun:steel_knives", "obstacle:pool", "mark:vagrant"]

## stat: the Progress stat that counts toward it. goal: the number to reach.
## Phase 3: the counter guns below moved to lessons (scripts/lessons.gd): oil_slinger,
## cinder_flak, hydro_cannon, acid_flask, ember_carbine, rime_chakram, eclipse_carbine,
## glacier_lance, napalm_lobber, void_orb, stone_sling and sun_cannon. Their achievements
## stay as milestones (empty rewards) so saves keep their ids. The class_* entries are the
## loadout challenges: each opens a Mark and its Kit (GDD section 11).
const ACHIEVEMENTS := [
    # Ordered by effort. The first block teaches the basics, Risk of Rain 2 style, and
    # hands out one new element per run (report R8): every goal in it is cumulative and
    # comes from simply playing, so by about run 5 every element is in the pool.
    # Expected run from the bot data (Set A floor-1 runs: 6 distinct reactions, 7 vents,
    # 3 rooms, 0-3 elites, ~100 reactions): ice 1, acid 1-2, poison 2, gale 2-3, blood
    # 2-4, stone 3, void 3, holy 5 (holy waited until a median run of ~45 before).
    # Ids are the old ones wherever the reward stayed put, so saves keep their progress;
    # the old goals behind those ids (375 / 625 kills, 75 Steams, 60 / 240 Chain
    # Lightnings, 900 reactions, 12 runs, 240 Deep Freezes) are gone.
    { "id": "first_blood", "name": "First Blood", "desc": "Kill 50 enemies",
        "stat": "kills", "goal": 50, "rewards": ["gun:blowtorch"] },
    { "id": "conductor", "name": "Chemistry", "desc": "Discover 3 different reactions",
        "stat": "reactions_discovered", "goal": 3, "rewards": ["gun:frost_caster"] },
    { "id": "bloodied", "name": "Blow-off", "desc": "Vent 10 times",
        "stat": "vents", "goal": 10, "rewards": ["gun:etcher_beam"] },
    { "id": "regular", "name": "Regular", "desc": "Start 2 runs",
        "stat": "runs_started", "goal": 2, "rewards": ["gun:spark_needler"] },
    { "id": "chemist", "name": "Housekeeper", "desc": "Clear 5 rooms",
        "stat": "rooms", "goal": 5, "rewards": ["gun:venom_spitter"] },
    { "id": "stormcaller", "name": "Field Notes", "desc": "Discover 6 different reactions",
        "stat": "reactions_discovered", "goal": 6, "rewards": ["gun:gale_blaster", "obstacle:miasma"] },
    { "id": "butcher", "name": "Headhunter", "desc": "Kill 3 elites",
        "stat": "elites", "goal": 3, "rewards": ["gun:blood_lance"] },
    { "id": "veteran", "name": "Persistent", "desc": "Start 3 runs",
        "stat": "runs_started", "goal": 3, "rewards": ["gun:gravel_shotgun"] },
    { "id": "catalyst", "name": "Catalyst", "desc": "Fire 250 reactions",
        "stat": "reactions", "goal": 250, "rewards": ["gun:null_wand"] },
    { "id": "zealot", "name": "Pilgrim", "desc": "Start 5 runs",
        "stat": "runs_started", "goal": 5, "rewards": ["gun:radiant_ray", "obstacle:ward"] },
    # Then exploration and the first specific reactions. Reaction goals were 50 to 90 and
    # swung 5-10x between runs (142 Infernos in one run against a median of 4); they are
    # now about one to three median runs of their pairing (Set A medians per run: Chain
    # Lightning 25, Ignition 17, Steam 4, Inferno 4, Deep Freeze 3, Black Ice 1).
    { "id": "plumber", "name": "Plumber", "desc": "Open a hidden room",
        "stat": "hidden_rooms", "goal": 1, "rewards": ["obstacle:valve", "gun:mist_sprayer"] },
    { "id": "curious", "name": "Curious", "desc": "Find a secret",
        "stat": "secrets_found", "goal": 1, "rewards": ["secret:lantern"] },
    { "id": "arsonist", "name": "Arsonist", "desc": "Fire 30 Infernos or Ignitions",
        "stat": "reactions_fire", "goal": 30, "rewards": ["obstacle:thicket"] },
    { "id": "kettle", "name": "Kettle", "desc": "Fire 10 Steams",
        "stat": "reaction:Steam", "goal": 10, "rewards": [] },
    { "id": "sparkplug", "name": "Sparkplug", "desc": "Fire 25 Ignitions",
        "stat": "reaction:Ignition", "goal": 25, "rewards": [] },
    { "id": "class_tarsmith", "name": "Pitch Black", "desc": "Fire 30 Ignitions",
        "stat": "reaction:Ignition", "goal": 30, "rewards": ["mark:tarsmith", "kit:slick_wand"] },
    { "id": "class_stormcaller", "name": "Lightning Rod", "desc": "Fire 40 Chain Lightnings",
        "stat": "reaction:Chain Lightning", "goal": 40, "rewards": ["mark:stormcaller", "kit:spark_needler"] },
    { "id": "class_pyromancer", "name": "Firestarter", "desc": "Fire 15 Infernos",
        "stat": "reaction:Inferno", "goal": 15, "rewards": ["mark:pyromancer", "kit:flare_pistol"] },
    { "id": "class_tidecaller", "name": "High Tide", "desc": "Fire 20 Steams",
        "stat": "reaction:Steam", "goal": 20, "rewards": ["mark:tidecaller", "kit:water_pistol"] },
    { "id": "class_frostbinder", "name": "Cold Hands", "desc": "Fire 15 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 15, "rewards": ["mark:frostbinder", "kit:frost_caster"] },
    { "id": "venter", "name": "Venter", "desc": "Vent 30 novas",
        "stat": "vents", "goal": 30, "rewards": [] },
    { "id": "alchemist", "name": "Alchemist", "desc": "Fire 25 Infernos",
        "stat": "reaction:Inferno", "goal": 25, "rewards": ["obstacle:rubble"] },
    { "id": "collector", "name": "Collector", "desc": "Equip 8 pieces of gear",
        "stat": "items_picked", "goal": 8, "rewards": ["rarity:epic"] },
    { "id": "slayer", "name": "Slayer", "desc": "Kill 12 elites",
        "stat": "elites", "goal": 12, "rewards": [] },
    { "id": "plasma", "name": "Plasma Physicist", "desc": "Fire 15 Plasmas",
        "stat": "reaction:Plasma", "goal": 15, "rewards": ["gun:storm_seeker"] },
    { "id": "black_ice", "name": "Black Ice", "desc": "Fire 15 Black Ices",
        "stat": "reaction:Black Ice", "goal": 15, "rewards": [] },
    { "id": "thermal", "name": "Thermal", "desc": "Fire 20 Thermal Shocks",
        "stat": "reaction:Thermal Shock", "goal": 20, "rewards": ["gun:duality_burst"] },
    # Off-element reactions: each needs a gun of both elements, which the first block now
    # delivers by about run 5. No bot data yet for these signatures: 20 for the gun, 25
    # for the class (the class follows the gun on the same reaction).
    { "id": "polluter", "name": "Polluter", "desc": "Fire 20 Contaminations",
        "stat": "reaction:Contamination", "goal": 20, "rewards": ["gun:blight_seeker"] },
    { "id": "fumigator", "name": "Fumigator", "desc": "Fire 20 Noxious Flames",
        "stat": "reaction:Noxious Flame", "goal": 20, "rewards": ["gun:plague_mortar"] },
    { "id": "hemophile", "name": "Hemophile", "desc": "Fire 20 Thin Bloods",
        "stat": "reaction:Thin Blood", "goal": 20, "rewards": ["gun:clot_orb"] },
    { "id": "maelstrom", "name": "Maelstrom", "desc": "Fire 20 Whirlpools",
        "stat": "reaction:Whirlpool", "goal": 20, "rewards": ["gun:rift_seeker"] },
    { "id": "baptist", "name": "Baptist", "desc": "Fire 20 Baptisms",
        "stat": "reaction:Baptism", "goal": 20, "rewards": ["gun:prayer_burst"] },
    { "id": "windbreaker", "name": "Windbreaker", "desc": "Fire 20 Monsoons",
        "stat": "reaction:Monsoon", "goal": 20, "rewards": ["gun:cyclone_flak"] },
    { "id": "class_voidwalker", "name": "Event Horizon", "desc": "Fire 20 Singularities",
        "stat": "reaction:Singularity", "goal": 20, "rewards": ["mark:voidwalker", "kit:null_wand"] },
    { "id": "class_alchemist", "name": "Splash Zone", "desc": "Fire 20 Caustic Splashes",
        "stat": "reaction:Caustic Splash", "goal": 20, "rewards": ["mark:alchemist", "kit:etcher_beam"] },
    { "id": "class_stonewarden", "name": "Bog Standard", "desc": "Fire 20 Muds",
        "stat": "reaction:Mud", "goal": 20, "rewards": ["mark:stonewarden", "kit:gravel_shotgun"] },
    { "id": "class_plaguewright", "name": "Patient Zero", "desc": "Fire 25 Contaminations",
        "stat": "reaction:Contamination", "goal": 25, "rewards": ["mark:plaguewright", "kit:venom_spitter"] },
    { "id": "class_bloodletter", "name": "Leech", "desc": "Fire 25 Thin Bloods",
        "stat": "reaction:Thin Blood", "goal": 25, "rewards": ["mark:bloodletter", "kit:vein_pistol"] },
    { "id": "class_templar", "name": "Anointed", "desc": "Fire 25 Baptisms",
        "stat": "reaction:Baptism", "goal": 25, "rewards": ["mark:templar", "kit:prayer_burst"] },
    { "id": "class_windrunner", "name": "Rainmaker", "desc": "Fire 25 Monsoons",
        "stat": "reaction:Monsoon", "goal": 25, "rewards": ["mark:windrunner", "kit:zephyr_rang"] },
    { "id": "annihilator", "name": "Annihilator", "desc": "Fire 15 Annihilations",
        "stat": "reaction:Annihilation", "goal": 15, "rewards": [] },
    # Depth, bosses and the long tail.
    { "id": "tourist", "name": "Tourist", "desc": "Clear 3 floors",
        "stat": "floors", "goal": 3, "rewards": ["gun:vein_pistol"] },
    { "id": "floor_breaker", "name": "Floor Breaker", "desc": "Kill 2 bosses",
        "stat": "bosses", "goal": 2, "rewards": ["room:challenge", "gun:tar_mortar"] },
    { "id": "delver", "name": "Delver", "desc": "Find 10 secrets",
        "stat": "secrets_found", "goal": 10, "rewards": ["secret:alcove"] },
    { "id": "reactionary", "name": "Reactionary", "desc": "Discover 20 different reactions",
        "stat": "reactions_discovered", "goal": 20, "rewards": ["shop:items"] },
    # The tier ladder: fusions (a reaction's compound + a third element) and cataclysms (a
    # fusion field + a fourth). Discoveries also pay Embers (Mastery.PAY); these are the
    # milestones, with nothing to unlock.
    { "id": "fusion", "name": "Third Element", "desc": "Discover a fusion",
        "stat": "fusions_discovered", "goal": 1, "rewards": [] },
    { "id": "alchemy", "name": "Alchemy", "desc": "Discover 15 different fusions",
        "stat": "fusions_discovered", "goal": 15, "rewards": [] },
    { "id": "cataclysm", "name": "Fourth Element", "desc": "Set off a cataclysm",
        "stat": "cataclysms_discovered", "goal": 1, "rewards": [] },
    { "id": "end_times", "name": "End Times", "desc": "Discover 8 different cataclysms",
        "stat": "cataclysms_discovered", "goal": 8, "rewards": [] },
    { "id": "exterminator", "name": "Exterminator", "desc": "Kill 1500 enemies",
        "stat": "kills", "goal": 1500, "rewards": ["gun:corrosion_burst"] },
    { "id": "pressure_cooker", "name": "Pressure Cooker", "desc": "Fire 75 Steams",
        "stat": "reaction:Steam", "goal": 75, "rewards": ["gun:kettle_gun"] },
    { "id": "deep_freezer", "name": "Deep Freezer", "desc": "Fire 50 Deep Freezes",
        "stat": "reaction:Deep Freeze", "goal": 50, "rewards": [] },
    { "id": "pyromaniac", "name": "Pyromaniac", "desc": "Fire 90 Infernos",
        "stat": "reaction:Inferno", "goal": 90, "rewards": [] },
    { "id": "hoarder", "name": "Hoarder", "desc": "Equip 25 pieces of gear",
        "stat": "items_picked", "goal": 25, "rewards": ["rarity:legendary"] },
    { "id": "abyss", "name": "Abyss", "desc": "Kill 6 bosses",
        "stat": "bosses", "goal": 6, "rewards": [] },
    { "id": "mason", "name": "Mason", "desc": "Kill 50 elites",
        "stat": "elites", "goal": 50, "rewards": [] },
    { "id": "riddler", "name": "Riddler", "desc": "Solve every kind of secret",
        "stat": "secret_kinds", "goal": 10, "rewards": ["secret:hoard"] },
    { "id": "explorer", "name": "Explorer", "desc": "Clear 20 floors",
        "stat": "floors", "goal": 20, "rewards": ["gun:zephyr_rang"] },
    { "id": "survivor", "name": "Survivor", "desc": "Clear the dungeon",
        "stat": "runs_won", "goal": 1, "rewards": ["gun:storm_pike", "shop:extra"] },
    { "id": "sunbreaker", "name": "Sunbreaker", "desc": "Kill 12 bosses",
        "stat": "bosses", "goal": 12, "rewards": [] },
    { "id": "reaper", "name": "Reaper", "desc": "Kill 3750 enemies",
        "stat": "kills", "goal": 3750, "rewards": ["gun:railgun"] },
    { "id": "spelunker", "name": "Spelunker", "desc": "Clear 50 floors",
        "stat": "floors", "goal": 50, "rewards": ["gun:boulder_mortar"] },
    # Arsenal expansion batch 1 (6.2): melee. Play goals open the Commons and two Uncommons,
    # each with one Blade item; melee mastery (kills by melee weapons) opens the rest in
    # family order, each with one or two Blade items. Tin Sabre is in BASE_UNLOCKS.
    { "id": "melee_play_1", "name": "Bladesmith", "desc": "Kill 150 enemies",
        "stat": "kills", "goal": 150, "rewards": ["gun:tide_spear", "item:honed_edge"] },
    { "id": "melee_play_2", "name": "Knuckle Down", "desc": "Clear 12 rooms",
        "stat": "rooms", "goal": 12, "rewards": ["gun:spark_knuckles", "item:swift_strikes"] },
    { "id": "melee_play_3", "name": "Hot Iron", "desc": "Vent 25 times",
        "stat": "vents", "goal": 25, "rewards": ["gun:ember_brand", "item:sword_belt"] },
    { "id": "melee_play_4", "name": "Thornwork", "desc": "Set off 400 reactions",
        "stat": "reactions", "goal": 400, "rewards": ["gun:thorn_whip", "item:soaked_edge"] },
    { "id": "melee_play_5", "name": "Bone Idle", "desc": "Start 4 runs",
        "stat": "runs_started", "goal": 4, "rewards": ["gun:bone_club", "item:balanced_grip"] },
    { "id": "melee_play_6", "name": "Hatchet Job", "desc": "Kill 8 elites",
        "stat": "elites", "goal": 8, "rewards": ["gun:frost_hatchet", "item:edge_whetstone"] },
    { "id": "melee_play_7", "name": "Reaper's Apprentice", "desc": "Clear 6 floors",
        "stat": "floors", "goal": 6, "rewards": ["gun:hollow_sickle", "item:iron_wrists"] },
    { "id": "melee_play_8", "name": "Etcher", "desc": "Kill 600 enemies",
        "stat": "kills", "goal": 600, "rewards": ["gun:etching_claws", "item:edge_runner"] },
    { "id": "melee_play_9", "name": "Fencer", "desc": "Discover 9 different reactions",
        "stat": "reactions_discovered", "goal": 9, "rewards": ["gun:blood_rapier", "item:long_reach"] },
    { "id": "melee_mastery_1", "name": "Blades I", "desc": "Kill 60 enemies with melee weapons",
        "stat": "kills_melee", "goal": 60, "rewards": ["gun:pitch_cleaver", "item:bloodletter", "item:cutting_wind"] },
    { "id": "melee_mastery_2", "name": "Blades II", "desc": "Kill 150 enemies with melee weapons",
        "stat": "kills_melee", "goal": 150, "rewards": ["gun:gale_glaive", "item:rime_whetstone", "item:weighted_pommel"] },
    { "id": "melee_mastery_3", "name": "Blades III", "desc": "Kill 300 enemies with melee weapons",
        "stat": "kills_melee", "goal": 300, "rewards": ["gun:sanctified_mace", "item:marked_steel", "item:mending_steel"] },
    { "id": "melee_mastery_4", "name": "Blades IV", "desc": "Kill 500 enemies with melee weapons",
        "stat": "kills_melee", "goal": 500, "rewards": ["gun:storm_lash", "item:thunder_grip", "item:long_haft"] },
    { "id": "melee_mastery_5", "name": "Blades V", "desc": "Kill 800 enemies with melee weapons",
        "stat": "kills_melee", "goal": 800, "rewards": ["gun:parry_blade", "item:riposte", "item:bulwark"] },
    { "id": "melee_mastery_6", "name": "Blades VI", "desc": "Kill 1200 enemies with melee weapons",
        "stat": "kills_melee", "goal": 1200, "rewards": ["gun:venom_pike", "item:wildfire_edge", "item:ember_whetstone"] },
    { "id": "melee_mastery_7", "name": "Blades VII", "desc": "Kill 1600 enemies with melee weapons",
        "stat": "kills_melee", "goal": 1600, "rewards": ["gun:riptide_whip", "item:shock_edge", "item:tempered_steel"] },
    { "id": "melee_mastery_8", "name": "Blades VIII", "desc": "Kill 2000 enemies with melee weapons",
        "stat": "kills_melee", "goal": 2000, "rewards": ["gun:rimefang", "item:follow_through", "item:berserker_oath"] },
    { "id": "melee_mastery_9", "name": "Blades IX", "desc": "Kill 2600 enemies with melee weapons",
        "stat": "kills_melee", "goal": 2600, "rewards": ["gun:crimson_gauntlets", "item:twin_edge"] },
    { "id": "melee_mastery_10", "name": "Blades X", "desc": "Kill 3200 enemies with melee weapons",
        "stat": "kills_melee", "goal": 3200, "rewards": ["gun:magma_maul", "item:whirl", "item:whirlwind"] },
    { "id": "melee_mastery_11", "name": "Blades XI", "desc": "Kill 4000 enemies with melee weapons",
        "stat": "kills_melee", "goal": 4000, "rewards": ["gun:thunder_halberd", "item:glass_blade"] },
    { "id": "melee_mastery_12", "name": "Blades XII", "desc": "Kill 5000 enemies with melee weapons",
        "stat": "kills_melee", "goal": 5000, "rewards": ["gun:twin_fangs", "item:frostbite_steel"] },
    { "id": "melee_mastery_13", "name": "Blades XIII", "desc": "Kill 6500 enemies with melee weapons",
        "stat": "kills_melee", "goal": 6500, "rewards": ["gun:eclipse_scythe"] },
    # Arsenal expansion batch 2 (6.2): thrown and the new guns. Play goals open the Commons
    # and Uncommons, each with one Thrown item; thrown mastery (kills by thrown weapons)
    # opens the rest in family order. Steel Knives is in BASE_UNLOCKS; three Rares and Epics
    # come from the first Trials (Trials.DEFS).
    { "id": "thrown_play_1", "name": "Knife Thrower", "desc": "Kill 200 enemies",
        "stat": "kills", "goal": 200, "rewards": ["gun:clay_grenade", "item:throwing_gloves"] },
    { "id": "thrown_play_2", "name": "Tangled", "desc": "Clear 15 rooms",
        "stat": "rooms", "goal": 15, "rewards": ["gun:shock_bola", "item:quick_draw"] },
    { "id": "thrown_play_3", "name": "Long Arm", "desc": "Kill 10 elites",
        "stat": "elites", "goal": 10, "rewards": ["gun:frost_javelin", "item:damp_satchel"] },
    { "id": "thrown_play_4", "name": "Firebug", "desc": "Vent 30 times",
        "stat": "vents", "goal": 30, "rewards": ["gun:fire_bottle", "item:pitch_pot"] },
    { "id": "thrown_play_5", "name": "Discus", "desc": "Set off 500 reactions",
        "stat": "reactions", "goal": 500, "rewards": ["gun:tide_discus", "item:overarm"] },
    { "id": "thrown_play_6", "name": "Fan Dancer", "desc": "Start 6 runs",
        "stat": "runs_started", "goal": 6, "rewards": ["gun:venom_fan", "item:fuse_cutter"] },
    { "id": "thrown_play_7", "name": "Star Gazer", "desc": "Discover 10 different reactions",
        "stat": "reactions_discovered", "goal": 10, "rewards": ["gun:wind_star", "item:throwing_strap"] },
    { "id": "gun_play_1", "name": "Six Shooter", "desc": "Kill 300 enemies",
        "stat": "kills", "goal": 300, "rewards": ["gun:old_six", "item:weighted_tip"] },
    { "id": "gun_play_2", "name": "Cold Hands", "desc": "Clear 25 rooms",
        "stat": "rooms", "goal": 25, "rewards": ["gun:rime_repeater", "item:frost_quiver"] },
    { "id": "gun_play_3", "name": "Bubbles", "desc": "Start 3 runs",
        "stat": "runs_started", "goal": 3, "rewards": ["gun:bubble_gun", "item:cold_current"] },
    { "id": "gun_play_4", "name": "Close Quarters", "desc": "Kill 15 elites",
        "stat": "elites", "goal": 15, "rewards": ["gun:ember_scattergun", "item:kindling_pouch"] },
    { "id": "gun_play_5", "name": "Archer", "desc": "Clear 8 floors",
        "stat": "floors", "goal": 8, "rewards": ["gun:gale_longbow", "item:fletched_shaft"] },
    { "id": "gun_play_6", "name": "Dartboard", "desc": "Kill 900 enemies",
        "stat": "kills", "goal": 900, "rewards": ["gun:acid_darts", "item:slick_spool"] },
    { "id": "gun_play_7", "name": "Marksman", "desc": "Beat 6 bosses",
        "stat": "bosses", "goal": 6, "rewards": ["gun:longshot", "item:barbed_edge"] },
    { "id": "thrown_mastery_1", "name": "Throws I", "desc": "Kill 60 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 60, "rewards": ["gun:holy_water", "item:sticky_fingers", "item:heavy_hand"] },
    { "id": "thrown_mastery_2", "name": "Throws II", "desc": "Kill 150 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 150, "rewards": ["gun:void_grenade", "item:shrapnel_pouch", "item:rime_bandolier"] },
    { "id": "thrown_mastery_3", "name": "Throws III", "desc": "Kill 300 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 300, "rewards": ["gun:etching_javelin", "item:deep_pockets", "item:recall"] },
    { "id": "thrown_mastery_4", "name": "Throws IV", "desc": "Kill 500 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 500, "rewards": ["gun:halo_disc", "item:rim_shot", "item:fletching"] },
    { "id": "thrown_mastery_5", "name": "Throws V", "desc": "Kill 800 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 800, "rewards": ["gun:storm_kunai", "item:copper_wire", "item:spin_grip"] },
    { "id": "thrown_mastery_6", "name": "Throws VI", "desc": "Kill 1200 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 1200, "rewards": ["gun:cluster_bomb", "item:double_fuse", "item:storm_bangle"] },
    { "id": "thrown_mastery_7", "name": "Throws VII", "desc": "Kill 1800 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 1800, "rewards": ["gun:crossing_axes", "item:magnet_glove", "item:firebrand_sash", "item:catch_spark"] },
    { "id": "thrown_mastery_8", "name": "Throws VIII", "desc": "Kill 2600 enemies with thrown weapons",
        "stat": "kills_thrown", "goal": 2600, "rewards": ["gun:drowned_anchor", "item:second_throw", "item:knife_storm", "item:twin_throw"] },
]

var save_path := SAVE_PATH
var unlocks: Dictionary = {}          # unlock id -> true
var stats: Dictionary = {}            # stat -> int
var achievements_done: Dictionary = {}
var history: Array = []               # { won, floor, kills, unlocks }
var run_unlocks: Array = []           # unlock ids earned during the current run
var run_stats: Dictionary = {}        # stat -> amount added during the current run
var run_discoveries: Array = []       # reactions fired for the first time ever, this run
var run_fusion_discoveries: Array = []      # fusions (tier 3) set off for the first time ever, this run
var run_cataclysm_discoveries: Array = []   # cataclysms (tier 4) likewise
var names: Array = ["", "", "", ""]   # player names; empty falls back to P1..P4
## Hollow NPCs (design/World and progression GDD.md, section 9): id -> { "state": "" / "met"
## / "recruited", "talks": lines heard }. The Keeper and the Gatewarden are always home;
## everyone else moves in when recruited, and their station arrives with them.
var npcs: Dictionary = {}
var seen_lines: Dictionary = {}       # Dialogue line id -> times shown
## Player 1's loadout at the Gate (Loadout): { kit, mark, relic, vow }, kept between runs.
var loadout: Dictionary = {}
## Relics owned (item ids, bought from the Wellkeeper), and items saved in a Well that wait
## for the Wellkeeper to sell them back.
var relics: Array = []
var well_saved: Array = []
## Deaths per lesson key (Lessons.killer_key): the first unlocks the lesson's counters.
var lessons: Dictionary = {}
## The lesson the last run taught, for the payout and the Hollow ("" if none).
var run_lesson := ""
## The Trial of the run in progress (Trials), "" for a normal run. Not saved: the hub's
## board sets it at Descend, the run's end clears it. Wins live in world["trials_won"].
var trial := ""
var run_trial_won := ""
## World state (Shortcuts, phase 4): { "shortcuts": { id: { "run": runs started when it
## opened } } }. Opened shortcuts never close. Version 4 of the save; older saves load
## with an empty world.
var world: Dictionary = {}
const SAVE_VERSION := 5   # 5: items without slots (Core loop reset 3.3)


func _ready() -> void:
    # Bot and capture runs (any user argument after `--`) never read or write the player's
    # save, not even here before main.gd or hub.gd pick their own file: loading migrates
    # and settles, and both write.
    if Main.bot_run():
        save_path = "user://save_autotest%s.json" % Main._instance_tag()
    load_save()


# --- Queries ---------------------------------------------------------------


func has(unlock_id: String) -> bool:
    return unlocks.has(unlock_id)


## The name shown for player `i` (0-based): what they typed, else P1..P4.
func player_name(i: int) -> String:
    if i >= 0 and i < names.size() and names[i] != "":
        return names[i]
    return "P%d" % (i + 1)


func set_player_name(i: int, n: String) -> void:
    if i < 0 or i >= names.size():
        return
    names[i] = n.strip_edges().left(12)
    save()


func stat(key: String) -> int:
    return int(stats.get(key, 0))


## Human name for an unlock id.
func unlock_label(unlock_id: String) -> String:
    var parts := unlock_id.split(":")
    match parts[0]:
        "gun":
            return Guns.make(parts[1]).display_name
        "item":
            return String(Items.get_item(parts[1]).get("name", parts[1]))
        "obstacle":
            return { "pool": "Pool obstacles", "thicket": "Thicket obstacles", "valve": "Valve obstacles",
                "ward": "Ward obstacles", "rubble": "Rubble obstacles", "miasma": "Miasma obstacles" }.get(parts[1], parts[1])
        "room":
            return "Challenge rooms" if parts[1] == "challenge" else parts[1]
        "mark":
            return Loadout.mark_name(parts[1])
        "kit":
            return "the %s Kit" % Loadout.kit_name(parts[1])
        "shop":
            return "Fourth shop slot" if parts[1] == "extra" else "Third shop item"
        "rarity":
            return "%s gear" % parts[1].capitalize()
        "secret":
            return { "lantern": "More hidden puzzles", "alcove": "More secret alcoves",
                "hoard": "Richer puzzle rewards" }.get(parts[1], parts[1])
    return unlock_id


## Which achievement grants an unlock, as "Name: how", or "Starting pool" for base content.
func unlock_source(unlock_id: String) -> String:
    for a in ACHIEVEMENTS:
        if a["rewards"].has(unlock_id):
            return "%s: %s" % [a["name"], a["desc"]]
    var lesson := Lessons.source_of(unlock_id)
    if lesson != "":
        return "Lesson: die to %s" % Lessons.lesson_name(lesson)
    if BASE_UNLOCKS.has(unlock_id):
        return "Starting pool"
    return "Not yet obtainable"


## The next few achievements still open, with progress, for the run-end screen.
func next_goals(count: int) -> Array:
    var rows: Array = []
    for a in ACHIEVEMENTS:
        if achievements_done.has(a["id"]) or not can_progress(a):
            continue
        var prog := mini(stat(a["stat"]), int(a["goal"]))
        rows.append({ "name": a["name"], "desc": a["desc"], "progress": prog, "goal": a["goal"],
            "frac": float(prog) / float(maxi(1, int(a["goal"]))) })
    # Closest to done first; among equals, the smaller goal.
    rows.sort_custom(func(x, y):
        if not is_equal_approx(float(x["frac"]), float(y["frac"])):
            return float(x["frac"]) > float(y["frac"])
        return int(x["goal"]) < int(y["goal"]))
    return rows.slice(0, count)


## Whether the current pool can move this achievement at all: a reaction goal needs a
## gun of each of its two elements unlocked.
func can_progress(a: Dictionary) -> bool:
    var st: String = a["stat"]
    if not st.begins_with("reaction:"):
        return true
    var d: Dictionary = Elements.def_by_name(st.substr(9))
    if d.is_empty():
        return true
    var have := {}
    for gid in Guns.ids():
        have[Guns.make(gid).element] = true
    return have.has(d["a"]) and have.has(d["b"])


## Icon of an achievement: its first reward's icon (the gun, the class, else a book or
## scroll; see Art.reward_icon_path).
func achievement_icon_path(a: Dictionary) -> String:
    var rewards: Array = a.get("rewards", [])
    return Art.reward_icon_path(String(rewards[0]) if not rewards.is_empty() else "")


func achievement_icon(a: Dictionary) -> Texture2D:
    var rewards: Array = a.get("rewards", [])
    if not rewards.is_empty() and String(rewards[0]).begins_with("gun:"):
        return Art.gun_icon(String(rewards[0]).substr(4))   # code-drawn weapons too
    return Art.icon(achievement_icon_path(a))


func achievements_count() -> int:
    return achievements_done.size()


# --- Recording -------------------------------------------------------------


func add(key: String, amount: int = 1) -> void:
    stats[key] = stat(key) + amount
    run_stats[key] = int(run_stats.get(key, 0)) + amount
    _check_achievements()


func add_reaction(reaction_name: String) -> void:
    match reaction_name:
        "ELITE", "Shield broken!", "Shield restored!":
            return
        "Path opened!":
            add("hidden_rooms")
            return
        "Fire Nova", "Frost Nova":
            add("vents")
            return
    if Elements.def_by_name(reaction_name).is_empty():
        return   # "Shield cracked", "ENRAGED" and other popups are not reactions
    stats["reactions"] = stat("reactions") + 1
    if reaction_name in ["Inferno", "Ignition"]:
        stats["reactions_fire"] = stat("reactions_fire") + 1
    if stat("reaction:" + reaction_name) == 0:
        stats["reactions_discovered"] = stat("reactions_discovered") + 1
        run_discoveries.append(reaction_name)
    add("reaction:" + reaction_name)


func discovered(reaction_name: String) -> bool:
    return stat("reaction:" + reaction_name) > 0


## A fusion (tier 3) or cataclysm (tier 4) fired. Returns true the first time ever on this
## save (a discovery: the Journal reveals it and the Shrine pays for it).
func add_fusion(fusion_name: String, tier: int) -> bool:
    var cata := tier >= Fusions.TIER_CATACLYSM
    stats["cataclysms" if cata else "fusions"] = stat("cataclysms" if cata else "fusions") + 1
    var first := stat("fusion:" + fusion_name) == 0
    if first:
        if cata:
            stats["cataclysms_discovered"] = stat("cataclysms_discovered") + 1
            run_cataclysm_discoveries.append(fusion_name)
        else:
            stats["fusions_discovered"] = stat("fusions_discovered") + 1
            run_fusion_discoveries.append(fusion_name)
    add("fusion:" + fusion_name)
    return first


func fusion_discovered(fusion_name: String) -> bool:
    return stat("fusion:" + fusion_name) > 0


## How much of `key` the current run added.
func run_stat(key: String) -> int:
    return int(run_stats.get(key, 0))


func start_run() -> void:
    run_unlocks = []
    run_stats = {}
    run_discoveries = []
    run_fusion_discoveries = []
    run_cataclysm_discoveries = []
    add("runs_started")


func end_run(won: bool, floor_number: int, kills: int, embers: int = 0, region: String = "", killer: String = "") -> void:
    run_lesson = ""
    if not won and killer != "":
        lessons[killer] = int(lessons.get(killer, 0)) + 1
        if int(lessons[killer]) == 1 and Lessons.has_lesson(killer):
            run_lesson = killer
            var lname := "Lesson: %s" % Lessons.lesson_name(killer)
            for r in Lessons.LESSONS[killer]["rewards"]:
                if not unlocks.has(r):
                    unlocks[r] = true
                    run_unlocks.append(r)
                    unlocked.emit(r, lname)
    run_trial_won = ""
    if trial != "" and won:
        # A Trial won (Trials): its rewards open once, announced like an achievement.
        var tw: Dictionary = world.get("trials_won", {})
        if not bool(tw.get(trial, false)):
            tw[trial] = true
            world["trials_won"] = tw
            run_trial_won = trial
            var tname := "Trial: %s" % Trials.name_of(trial)
            for r in Trials.DEFS[trial]["rewards"]:
                if not unlocks.has(r):
                    unlocks[r] = true
                    run_unlocks.append(r)
                    unlocked.emit(r, tname)
    var entry := { "won": won, "floor": floor_number, "kills": kills, "unlocks": run_unlocks.duplicate(), "embers": embers, "region": region, "killer": killer }
    if trial != "":
        entry["trial"] = trial
    trial = ""
    history.append(entry)
    if history.size() > 50:
        history.pop_front()
    if won:
        add("runs_won")
    save()


func _check_achievements() -> void:
    for a in ACHIEVEMENTS:
        if achievements_done.has(a["id"]):
            continue
        if stat(a["stat"]) >= a["goal"]:
            _grant(a)


func _grant(a: Dictionary) -> void:
    achievements_done[a["id"]] = true
    for r in a["rewards"]:
        if not unlocks.has(r):
            unlocks[r] = true
            run_unlocks.append(r)
            unlocked.emit(r, a["name"])
    if (a["rewards"] as Array).is_empty():
        unlocked.emit("", a["name"])   # a milestone: announced, nothing to unlock
    save()


# --- Persistence -----------------------------------------------------------


func save() -> void:
    var data := {
        "version": SAVE_VERSION,
        "unlocks": unlocks.keys(),
        "stats": stats,
        "achievements": achievements_done.keys(),
        "history": history,
        "names": names,
        "npcs": npcs,
        "seen_lines": seen_lines,
        "loadout": loadout,
        "relics": relics,
        "well_saved": well_saved,
        "lessons": lessons,
        "world": world,
    }
    var f := FileAccess.open(save_path, FileAccess.WRITE)
    if f == null:
        push_warning("Could not write save file: %s" % save_path)
        return
    f.store_string(JSON.stringify(data, "  "))
    f.close()


func load_save() -> void:
    unlocks = {}
    stats = {}
    achievements_done = {}
    history = []
    npcs = {}
    seen_lines = {}
    loadout = {}
    relics = []
    well_saved = []
    lessons = {}
    world = {}
    for u in BASE_UNLOCKS:
        unlocks[u] = true
    if not FileAccess.file_exists(save_path):
        return
    var f := FileAccess.open(save_path, FileAccess.READ)
    if f == null:
        return
    var parsed = JSON.parse_string(f.get_as_text())
    f.close()
    if not parsed is Dictionary:
        return
    var migrated := 0
    for u in parsed.get("unlocks", []):
        var uid := String(u)
        if uid.begins_with("class:"):
            # Version 2 and older: a class becomes its Mark and its Kit (Loadout).
            var lo := Loadout.from_class(uid.substr(6))
            unlocks["mark:" + String(lo["mark"])] = true
            if String(lo["kit"]) != "":
                unlocks["kit:" + String(lo["kit"])] = true
            migrated += 1
            continue
        if uid == "item:whetstone":
            # Batch 1's whetstone mod shared the old trinket's id; the mod is edge_whetstone
            # now and the trinket is open to all again, so the unlock moves to the mod.
            uid = "item:edge_whetstone"
            print("[MIGRATE] unlock item:whetstone -> item:edge_whetstone")
            migrated += 1
        unlocks[uid] = true
    for k in parsed.get("stats", {}).keys():
        stats[k] = int(parsed["stats"][k])
    for a in parsed.get("achievements", []):
        achievements_done[a] = true
    history = parsed.get("history", [])
    var saved_lessons = parsed.get("lessons", {})
    if saved_lessons is Dictionary:
        for k in saved_lessons.keys():
            lessons[String(k)] = int(saved_lessons[k])
    var saved_world = parsed.get("world", {})
    if saved_world is Dictionary:
        world = saved_world
    if int(parsed.get("version", 1)) < 4:
        # Version 3 and older had no world state: nothing opened yet. Written back at once
        # so the file says version 4.
        print("[MIGRATE] save version %d -> %d: world state added (%d shortcuts)" % [int(parsed.get("version", 1)), SAVE_VERSION, (world.get("shortcuts", {}) as Dictionary).size()])
        migrated += 1
    var saved_npcs = parsed.get("npcs", {})
    if saved_npcs is Dictionary:
        npcs = saved_npcs
    var saved_seen = parsed.get("seen_lines", {})
    if saved_seen is Dictionary:
        seen_lines = saved_seen
    var saved_loadout = parsed.get("loadout", {})
    if saved_loadout is Dictionary:
        loadout = saved_loadout
    # Version 5 (Core loop reset 3.3): old item ids run through Items.LEGACY_IDS. Two Relics
    # that map to one item collapse; the dropped one's Relic price is refunded in Embers
    # once Mastery has loaded. A Well item that is already a Relic leaves the Well.
    var refunds: Array = []
    var first_old: Dictionary = {}
    var mapped := 0
    for key in ["relics", "well_saved"]:
        var arr = parsed.get(key, [])
        if arr is Array:
            var clean: Array = []
            for id in arr:
                var nid := Items.legacy_successor(String(id))
                if nid != String(id):
                    mapped += 1
                    print("[MIGRATE] %s %s -> %s" % [key, String(id), nid])
                if clean.has(nid) or (key == "well_saved" and relics.has(nid)):
                    if key == "relics":
                        refunds.append([String(first_old.get(nid, nid)), String(id), nid])
                    continue
                if key == "relics":
                    first_old[nid] = String(id)
                # The Progress autoload loads before Items has built its catalog: only drop
                # unknown ids once the catalog exists, or a load that saves at once (a
                # migration) would wipe every Relic.
                if Items.catalog.is_empty() or not Items.get_item(nid).is_empty():
                    clean.append(nid)
            set(key, clean)
    var lrelic := String(loadout.get("relic", ""))
    if lrelic != "" and Items.legacy_successor(lrelic) != lrelic:
        loadout["relic"] = Items.legacy_successor(lrelic)
        mapped += 1
    if int(parsed.get("version", 1)) < 5:
        print("[MIGRATE] save version %d -> 5: items without slots, %d old item ids mapped" % [int(parsed.get("version", 1)), mapped])
        migrated += 1
    if not refunds.is_empty():
        _refund_relics.call_deferred(refunds)
    var saved_names: Array = parsed.get("names", [])
    for i in mini(4, saved_names.size()):
        names[i] = str(saved_names[i]).strip_edges().left(12)
    if migrated > 0 and int(parsed.get("version", 1)) < 3:
        print("[MIGRATE] save version %d: %d classes became Marks and Kits" % [int(parsed.get("version", 1)), migrated])
    _settle(migrated > 0)


## Save migration, run on every load (version 1 saves included): an achievement that is
## done always has all its rewards, and one whose goal the save already meets (goals were
## lowered and some ids got new, easier goals in version 2) is granted quietly, with no
## toast and nothing added to the next run's report.
func _settle(touched := false) -> void:
    for a in ACHIEVEMENTS:
        var id := String(a["id"])
        if not achievements_done.has(id):
            if stat(String(a["stat"])) < int(a["goal"]):
                continue
            achievements_done[id] = true
            touched = true
        for r in a["rewards"]:
            if not unlocks.has(r):
                unlocks[r] = true
                touched = true
    if touched:
        save()


# --- The Well and Relics (Loadout) -----------------------------------------


## Version 5: two old Relics that became one item. Refunds the dropped one's Relic price
## (priced at the item it became) once Items and Mastery have loaded.
func _refund_relics(refunds: Array) -> void:
    var total := 0
    for r in refunds:
        var n := Loadout.relic_price(String(r[2]))
        total += n
        print("[MIGRATE] relic %s+%s -> %s, refunded %d" % [r[0], r[1], r[2], n])
    if total > 0:
        Mastery.embers += total
        Mastery.save()


## Items dropped in a Well this run wait for the Wellkeeper, however the run ended. Her
## station moves into the Hollow the first time something waits.
func keep_well_items(items: Array) -> void:
    if items.is_empty():
        return
    for id in items:
        if not relics.has(id) and not well_saved.has(id):
            well_saved.append(String(id))
    if npc_state("wellkeeper") != "recruited":
        npcs["wellkeeper"] = { "state": "recruited", "talks": npc_talks("wellkeeper") }
    save()


## Buy a saved item back as a Relic: it leaves the Well and is yours for every run.
func buy_relic(item_id: String) -> bool:
    if not well_saved.has(item_id):
        return false
    var price := Loadout.relic_price(item_id)
    if Mastery.embers < price:
        return false
    Mastery.embers -= price
    Mastery.save()
    Mastery.changed.emit()
    well_saved.erase(item_id)
    relics.append(item_id)
    save()
    return true


# --- Hollow NPCs -----------------------------------------------------------


const HOME_NPCS := ["keeper", "gatewarden"]


func npc_state(id: String) -> String:
    if HOME_NPCS.has(id):
        return "recruited"
    return String((npcs.get(id, {}) as Dictionary).get("state", ""))


func set_npc_state(id: String, state: String) -> void:
    var d: Dictionary = npcs.get(id, {})
    d["state"] = state
    npcs[id] = d
    save()


func npc_home(id: String) -> bool:
    return npc_state(id) == "recruited"


func npc_talks(id: String) -> int:
    return int((npcs.get(id, {}) as Dictionary).get("talks", 0))


## A line was shown: count it for the NPC and the line (Dialogue picks fresh lines first).
func note_line(npc: String, line_id: String) -> void:
    var d: Dictionary = npcs.get(npc, {})
    d["talks"] = int(d.get("talks", 0)) + 1
    npcs[npc] = d
    seen_lines[line_id] = int(seen_lines.get(line_id, 0)) + 1
    save()


## Shortcuts (Shortcuts): opened for good, saved at once.
func shortcut_open(id: String) -> bool:
    return (world.get("shortcuts", {}) as Dictionary).has(id)


## Opens `id`; true if it was closed until now.
func open_shortcut(id: String) -> bool:
    if shortcut_open(id):
        return false
    var sc: Dictionary = world.get("shortcuts", {})
    sc[id] = { "run": stat("runs_started") }
    world["shortcuts"] = sc
    # The Cartographer moves into the Hollow with the first shortcut (her own recruit, at
    # the top of the Stormspire, waits for that region: phase 5).
    if npc_state("cartographer") == "":
        var d: Dictionary = npcs.get("cartographer", {})
        d["state"] = "recruited"
        npcs["cartographer"] = d
    save()
    return true


## Runs that did not end at the bottom (abandoned runs count): the Gatewarden's tally.
func deaths() -> int:
    return maxi(0, stat("runs_started") - stat("runs_won"))


## Wipe everything: back to a first-ever run.
func reset() -> void:
    if FileAccess.file_exists(save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    load_save()
