extends Node
## Autoload "Items": the gear catalog and the effect engine.
##
## An item is data: a slot, a rarity, flat stat modifiers ("mods"), modifiers that only
## apply while a condition holds ("cond_mods"), and triggered effects ("triggers").
## Everything synergises through the same small vocabulary, so adding an item is a
## few lines in `_build_catalog` and never new code.
##
## Rarity gates power (Brotato style):
##   Common     one modest stat.
##   Uncommon   two small stats, or one stat and a mild drawback, or a weak trigger.
##   Rare       first mechanics: bounce, pierce, chain jumps, lifesteal, small conditionals.
##   Epic       strong with a cost or a condition; the only non-legendary +projectile.
##   Legendary  run-defining triggers and combos.
##
## Mods (fractions unless noted):
##   dmg, dmg_<el>, potency, potency_<el>, potency:<Reaction Name>, fire_rate,
##   fire_rate_<el>, proj_speed, range, pierce (int), pierce_<el> (int), proj_count (int),
##   max_hp (int), regen (hp/s), speed, carry (int), vent_charge (vent fills faster), pressure_limit (int, vent capacity),
##   vent_radius, vent_power, scrap_gain, crit, crit_dmg (added to the x2 base), armor (int),
##   dodge, state_duration, vs_wet, vs_burning, vs_frozen, vs_shocked, vs_oiled, lifesteal
##   (hp per reaction), thorns (int), chain_jumps (int), bounce (int), xp_gain,
##   luck (fraction: multiplies the rarity odds of item rolls and level-up rolls, see `roll`)
## Gun mods (slot "mod", apply to the gun they sit on): g_dmg, g_fire_rate, g_count (int),
##   g_pierce (int), g_range, g_speed, g_pressure, extra_element (el key)
##   Only g_* keys work on a gun mod (player-wide mods are summed from worn gear only),
##   but triggers on gun mods fire like any other gear.
## Cond mods: { "<condition>": { <mod>: value } }, active while the condition holds. Only
##   player conditions make sense here (hot, cold, low_hp, high_hp, full_hp, moving, still,
##   calm); target conditions never hold outside a trigger. Do not put max_hp or carry
##   in cond mods (they are only read on recalc).
## Triggers: { on, chance, every, if, do, element, potency, radius, amount, count }
##   on:  hit, kill, elite_kill, reaction, reaction:<Reaction Name>, vent, room_clear, hurt
##        (overheat, freeze_up are reserved: nothing fires them yet)
##   every: int N, the trigger only fires on every Nth matching event (counted per player,
##        per item, per trigger; checked before `chance`)
##   if:  target_wet, target_burning, target_frozen, target_shocked, target_oiled,
##        target_poisoned, target_marked (target carries any element state), elite,
##        hot, cold, low_hp (< 40%), high_hp (>= 80%), full_hp, moving, still,
##        calm (|pressure| <= 15)
##   do:  apply, nova, heal, scrap, pressure, shoot, shield, slow, chain,
##        spread (apply `element` to every enemy within `radius`, no damage),
##        xp (grant `amount` experience)
##   element: wet, shock, fire, ice, oil, poison, acid, blood, void, holy, gale, stone,
##        or "last" (the element of the event)
##   at: "target" centres nova/spread/slow on the event's target instead of `pos`.
##   chain with `count`: arcs from each of the `count` nearest enemies within `radius`.
## Shot modifiers (Isaac's tear effects; worn gear only, consumed in Gun._shoot):
##   homing (rad/s turn; straight guns become homing), splash (px, added to splash radius),
##   shards (int; straight guns without pierce/bounce become flak, others burst at end of
##   life), shot_size (fraction: radius x(1+v), damage x(1+v/2)), shot_speed (fraction,
##   stacks with proj_speed), spectral (int flag: shots ignore obstacles), boomerang (int
##   flag: straight guns become boomerangs; wins over homing and shards).
## Familiars (Player): orbitals (int: discs circling at 60 px, hit for half the average
##   gun damage every 0.5 s per enemy), orbital_element (int flag: they also apply the
##   first gun's element).
## Looks (costumes): look: { tile: Vector2i, tint: Color or el key, offset: Vector2 (in
##   body-tile pixels from the figure's centre), scale: float (1 = body tile size), aura:
##   Color or el key, side: bool (offset.x follows facing) }. Merged over SLOT_LOOKS; the
##   LOOKS table gives rare-and-up items theirs. A full set (4 pieces, or all if fewer)
##   tints the figure toward the set colour (SETS[sid].color, or the element colour) with
##   a stronger aura. Drawn by `draw_costume`, used by Player and the character sheet.
## Extra item keys: element (el key, for tint), cond_mods, look, price (int: overrides the
##   rarity base price for an item that is cheaper or pricier than its rarity),
##   pools (Array of POOLS names; when absent the pools are derived from the item's shape
##   by `_auto_pools`), weight (float, default 1.0: pick weight inside a pool, Isaac style;
##   below 1 for very strong items), active (see below).
## Active items (slot "active", Isaac's spacebar item):
##   active: { "charges": N, "do": [ trigger-like dicts: do/element/radius/potency/amount/
##   count/at ] }. Equipping fills the charges; each room clear refills one; each use spends
##   one. Actions run with ctx { pos: player, target: nearest enemy, element: the player's
##   last vented element }, so element "last" means "what you last vented" (fire if none).
## Pools (Isaac): shop, treasure, boss, hidden, challenge, arena. `roll(..., pool)` only
##   draws from that pool. Items already seen this run (`mark_seen`) are skipped until the
##   pool runs dry at every rarity; `new_run` clears them.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
## UI colour rule (GDD 6, "Rarity owns colour"): in UI, rarity owns colour (item and gun
## frames, card borders, name text, gems, pips, HUD gear boxes); an element is only ever
## a neutral badge (ItemCard.draw_element_badge). The World of Warcraft palette, exact.
## Print the rarity word too wherever this colour is the only cue.
const RARITY_COLORS := [
    Color("#FFFFFF"),   # Common
    Color("#1EFF00"),   # Uncommon
    Color("#0070DD"),   # Rare
    Color("#A335EE"),   # Epic
    Color("#FF8000"),   # Legendary
]
## The same palette for small text on the dark panels: Rare and Epic lifted (same hue)
## so 20 px text clears 4.5:1 contrast; frames, gems and pips keep RARITY_COLORS.
const RARITY_TEXT_COLORS := [
    Color("#FFFFFF"),
    Color("#1EFF00"),
    Color("#3D9BFF"),
    Color("#B866F5"),
    Color("#FF8000"),
]
const RARITY_PRICE := [22, 38, 62, 98, 150]
## Roll odds per rarity above common: [min difficulty, growth per difficulty, cap].
## chance = clamp(growth * (difficulty - min + 1) * (1 + luck), 0, cap).
const RARITY_ODDS := {
    Rarity.UNCOMMON: [1, 0.07, 0.55],
    Rarity.RARE: [3, 0.03, 0.25],
    Rarity.EPIC: [2, 0.012, 0.10],
    Rarity.LEGENDARY: [2, 0.004, 0.04],
}
## Core loop reset 6.2 and 6.4: shop prices per rarity on floor 1, times the depth multiplier
## m = 1 + 0.25 x (floor - 1); explicit rarity odds per floor (percent, Common to Legendary)
## for shop wares; treasure never Common, with its own Legendary share; luck multiplies the
## Rare, Epic and Legendary weights by 1 + luck (luck capped at LUCK_CAP).
const PRICE_BASE := [25, 40, 65, 100, 150]
const SHOP_ODDS := [
    [60, 30, 9, 1, 0],
    [45, 35, 15, 4, 1],
    [30, 38, 22, 8, 2],
    [20, 35, 28, 13, 4],
    [12, 30, 33, 18, 7],
]
const TREASURE_LEGENDARY := [4, 6, 9, 12, 15]
const LUCK_CAP := 0.6
## Curses (section 11.1): cursed loot and deal prices. A floor curse ends at the stairs; a run
## curse lasts the run. Main.curses holds the active ones.
const CURSES := {
    "darkness": { "name": "Darkness", "line": "Your sight shrinks by half" },
    "frailty": { "name": "Frailty", "line": "You take 25% more damage" },
    "greed": { "name": "Greed", "line": "No hearts drop" },
    "haste": { "name": "Haste", "line": "Enemies move 15% faster" },
    "brittle": { "name": "Brittle", "line": "Your Mending reserve is halved" },
}
const SLOTS := ["head", "chest", "hands", "feet", "ring", "trinket", "mod", "active"]
## Slot -> icon (path under Art.ICON_ROOT): the fallback for an item without its own icon
## and, dimmed, the placeholder of an empty gear slot.
const SLOT_ICONS := {
    "head": "item/armor/headgear/helmet_1.png", "chest": "item/armor/torso/leather_armor_1.png",
    "hands": "item/armor/hands/glove_1_new.png", "feet": "item/armor/feet/boots_1_brown_new.png",
    "ring": "item/ring/iron.png", "trinket": "item/amulet/bone_gray.png",
    "mod": "gui/spells/components/bolt.png", "active": "item/potion/clear.png",
}
## Old 1-bit sheet tiles per slot, used only when an icon file is missing.
const SLOT_TILES := {
    "head": Vector2i(33, 0), "chest": Vector2i(35, 1), "hands": Vector2i(41, 1),
    "feet": Vector2i(40, 0), "ring": Vector2i(43, 7), "trinket": Vector2i(44, 6), "mod": Vector2i(45, 16),
    "active": Vector2i(44, 9),
}
## Hand-made item id -> icon (path under Art.ICON_ROOT), each picked to match the name and
## slot. `_apply_icons` copies these into the items' "icon" field.
const ICONS := {
    # Head
    "rusted_helm": "item/armor/headgear/helmet_1.png",
    "iron_pot": "item/armor/headgear/helmet_5.png",
    "feather_cap": "item/armor/headgear/elven_leather_helm.png",
    "miners_lamp": "item/misc/misc_lamp_new.png",
    "leather_cap": "item/armor/artefact/urand_bear.png",
    "wide_brim": "item/armor/headgear/hat_2.png",
    "scavenger_hood": "item/armor/headgear/cap_1.png",
    "fume_mask": "item/armor/headgear/green_mask.png",
    "sniper_visor": "item/armor/headgear/helmet_1_visored.png",
    "hothead": "item/armor/headgear/cap_2.png",
    "divers_goggles": "item/armor/headgear/helmet_art_2.png",
    "thinking_cap": "item/armor/headgear/wizard_hat_1.png",
    "crown_of_focus": "item/armor/artefact/urand_dyrovepreva_new.png",
    "marksman_monocle": "item/armor/artefact/urand_bullseye.png",
    "storm_hood": "item/armor/headgear/cornuthaum.png",
    "seer_circlet": "item/armor/headgear/helmet_art_1.png",
    "boiler_cap": "item/armor/headgear/helmet_4_visor.png",
    "berserker_helm": "item/armor/headgear/helmet_4.png",
    "skullcap_vented": "item/armor/headgear/helmet_3_new.png",
    "seeker_lens": "item/armor/headgear/helmet_ego_1.png",
    "cerebral_spark": "item/armor/headgear/hat_3.png",
    "detonator_cap": "item/armor/headgear/helmet_ego_4.png",
    "godhead": "item/armor/artefact/urand_eternal_torment.png",
    # Chest
    "padded_vest": "item/armor/torso/leather_armor_1.png",
    "quilted_jerkin": "item/armor/torso/elven_leather_armor.png",
    "hide_vest": "item/armor/torso/animal_skin_1_new.png",
    "lab_apron": "item/armor/torso/robe_1_new.png",
    "patched_coat": "item/armor/torso/robe_2_new.png",
    "cargo_vest": "item/armor/torso/studded_leather_armor.png",
    "thorn_vest": "item/armor/torso/orcish_leather_armor.png",
    "tar_coat": "item/armor/artefact/urand_night_new.png",
    "riveted_plate": "item/armor/torso/plate_1.png",
    "bandolier": "item/armor/torso/banded_mail_1.png",
    "slipstream_cloak": "item/armor/back/cloak_3.png",
    "bellows": "item/armor/torso/splint_mail_1.png",
    "chain_shirt": "item/armor/torso/chain_mail_1.png",
    "conductors_mail": "item/armor/torso/blue_dragon_scale_mail_new.png",
    "leech_mail": "item/armor/artefact/urand_salamander.png",
    "spiked_cuirass": "item/armor/torso/orcish_plate_2.png",
    "glacier_plate": "item/armor/torso/ice_dragon_armor_new.png",
    "ammo_harness": "item/armor/torso/ring_mail_1_new.png",
    "phoenix_mantle": "item/armor/artefact/urand_flash.png",
    "gilded_carapace": "item/armor/torso/gold_dragon_armor_new.png",
    "shrapnel_vest": "item/armor/torso/crystal_plate_mail.png",
    "phantom_shroud": "item/armor/artefact/urand_augmentation.png",
    "hive_heart": "item/armor/artefact/urand_lear.png",
    # Hands
    "worn_gloves": "item/armor/hands/glove_1_new.png",
    "hair_trigger": "item/armor/hands/glove_3_new.png",
    "knuckle_wraps": "item/armor/hands/glove_3_old.png",
    "steady_gloves": "item/armor/hands/glove_2_new.png",
    "gardening_gloves": "item/armor/hands/glove_4_old.png",
    "lab_gloves": "item/armor/artefact/urand_fencer_new.png",
    "quick_hands": "item/armor/artefact/urand_fencer_old.png",
    "spiked_gauntlets": "item/armor/hands/glove_4_new.png",
    "fingerless_gloves": "gui/spells/components/hand_4.png",
    "chilled_knuckles": "item/armor/hands/glove_5.png",
    "scrappers_mitts": "item/armor/hands/glove_1_old.png",
    "grip_of_pierce": "gui/spells/earth/stone_arrow_new.png",
    "ricochet_gloves": "item/armor/hands/glove_4_gauntlets.png",
    "kindling_mitts": "item/armor/hands/glove_2_old.png",
    "twin_triggers": "item/weapon/ranged/hand_crossbow_3.png",
    "executioners_grip": "item/armor/artefact/urand_war.png",
    "hands_of_storm": "gui/spells/air/static_discharge_new.png",
    "rifled_sleeve": "gui/spells/components/hand_3.png",
    "cluster_rounds": "gui/spells/earth/shatter_new.png",
    "mothers_blade": "item/weapon/artefact/spwpn_sword_of_cerebov_new.png",
    # Feet
    "leather_boots": "item/armor/feet/boots_1_brown_new.png",
    "runner_wraps": "item/armor/feet/low_boots.png",
    "hobnail_boots": "item/armor/feet/boots_1_brown_old.png",
    "sturdy_boots": "item/armor/feet/boots_2_jackboots.png",
    "sandals": "item/armor/feet/boots_3_stripe_old.png",
    "treaders": "item/armor/feet/boots_3_stripe_new.png",
    "mudwaders": "item/armor/feet/boots_4_green.png",
    "jogging_shoes": "gui/spells/components/running.png",
    "puddle_jumpers": "gui/abilities/jump.png",
    "stompers": "item/armor/feet/boots_iron_2.png",
    "cinder_clogs": "gui/spells/fire/conjure_flame_new.png",
    "frost_treads": "gui/spells/ice/freeze_new.png",
    "anvil_boots": "item/armor/artefact/urand_assassin.png",
    "greased_soles": "gui/spells/earth/ledas_liquefaction.png",
    "tidewalkers": "gui/spells/ice/condensation_shield_old.png",
    "hover_greaves": "gui/spells/air/levitation.png",
    "vent_striders": "gui/spells/fire/ring_of_flames_new.png",
    "seven_league": "gui/spells/air/swiftness_new.png",
    "tracker_boots": "gui/spells/divination/detect_creatures.png",
    # Trinkets
    "scrap_magnet": "item/amulet/ring_red.png",
    "reagent_satchel": "item/misc/misc_bottle.png",
    "four_leaf_clover": "item/amulet/penta_green.png",
    "whetstone": "item/misc/misc_stone_new.png",
    "bandage_roll": "item/scroll/blank_paper.png",
    "brass_spyglass": "gui/spells/components/eye.png",
    "ticking_clock": "gui/spells/enchantment/slow_new.png",
    "lucky_cog": "item/amulet/face_1_gold.png",
    "coin_purse": "item/gold/gold_pile_10.png",
    "ledger": "item/book/parchment_old.png",
    "pocket_watch": "gui/spells/enchantment/extension.png",
    "spark_plug": "gui/spells/air/shock_new.png",
    "heat_gauge": "item/misc/misc_disc_new.png",
    "steam_whistle": "gui/abilities/evoke_fog.png",
    "pressure_valve": "gui/spells/fire/evaporate.png",
    "alembic": "item/potion/effervescent.png",
    "rabbit_foot": "item/amulet/penta_orange.png",
    "grisly_trophy": "item/amulet/artefact/urand_finger.png",
    "static_jar": "item/misc/misc_lamp_old.png",
    "hot_rod": "item/rod/rod_0_new.png",
    "cold_snap": "item/misc/misc_crystal_old.png",
    "blood_pact": "gui/spells/necromancy/sublimation_of_blood_old.png",
    "plague_censer": "item/misc/misc_lantern.png",
    "heart_of_forge": "item/misc/runes/rune_gehenna_new.png",
    "permafrost_core": "item/misc/runes/rune_cocytus_new.png",
    "bone_orbit": "item/misc/runes/rune_tartarus_new.png",
    "powder_horn": "gui/spells/components/horn.png",
    "wisp_lantern": "item/misc/misc_lamp_inert.png",
    "twin_moons": "gui/spells/conjuration/orb_of_destruction_big.png",
    "skull_choir": "gui/spells/necromancy/symbol_of_torment.png",
    # Rings
    "bone_ring": "item/ring/ring_ivory.png",
    "gasket_ring": "item/ring/steel.png",
    "copper_ring": "item/ring/copper.png",
    "tin_ring": "item/ring/silver.png",
    "jade_ring": "item/ring/jade.png",
    "oak_ring": "item/ring/wooden.png",
    "wishbone_ring": "item/ring/ring_twisted.png",
    "ring_of_reach": "item/ring/ring_gold_white.png",
    "catalyst_ring": "item/ring/emerald.png",
    "gilded_ring": "item/ring/ring_gold_yellow.png",
    "iron_band": "item/ring/iron.png",
    "ring_of_embers": "item/ring/tiger_eye.png",
    "band_of_lingering": "item/ring/moonstone.png",
    "vampiric_loop": "item/ring/ring_ruby.png",
    "quicksilver_band": "item/ring/diamond.png",
    "bloodstone": "item/ring/ruby.png",
    "echo_loop": "item/ring/opal.png",
    "ring_of_multiplicity": "item/ring/tourmaline.png",
    "frenzy_band": "item/ring/gold_red.png",
    "signet_of_overload": "item/ring/artefact/urand_mage.png",
    "storm_halo": "item/ring/ring_shiny.png",
    "lead_shot": "item/ring/artefact/urand_shadows_new.png",
    "splinter_charm": "item/ring/ring_engagement.png",
    "big_iron": "item/ring/artefact/urand_robustness.png",
    "feral_fang": "item/ring/artefact/urand_octoring.png",
    # Gun mods
    "sight_rail": "gui/spells/translocation/portal_projectile_new.png",
    "oiled_bolt": "gui/spells/components/bolt.png",
    "heavy_barrel": "gui/spells/earth/iron_shot_new.png",
    "long_barrel": "item/weapon/ranged/blowgun_1.png",
    "gun_oil": "item/potion/murky.png",
    "exhaust_pipes": "gui/spells/fire/fire_storm_new.png",
    "piercing_rounds": "item/weapon/ranged/silver_arrow.png",
    "pressure_coupler": "item/misc/key.png",
    "arc_emitter": "gui/spells/air/lightning_bolt_new.png",
    "overclock": "gui/spells/enchantment/haste_old.png",
    "split_chamber": "gui/spells/conjuration/dazzling_spray.png",
    "chain_reactor": "gui/spells/conjuration/iskenderuns_mystic_blast_new.png",
    # Active items
    "smelling_salts": "item/potion/cloudy.png",
    "flash_powder": "item/potion/potion_fizzy.png",
    "tin_whistle": "item/misc/misc_horn.png",
    "pocket_storm": "gui/spells/air/conjure_ball_lightning_new.png",
    "water_bucket": "gui/spells/components/bowl.png",
    "ember_flask": "item/potion/orange_old.png",
    "grease_gun": "gui/spells/fire/ignite_poison_new.png",
    "frost_grenade": "gui/spells/ice/ozocubus_refrigeration_new.png",
    "dowsing_rod": "item/rod/rod_forked.png",
    "tesla_coil": "gui/spells/air/static_discharge_old.png",
    "overpressure": "gui/abilities/shaft_self.png",
    "blood_chalice": "gui/spells/necromancy/sublimation_of_blood.png",
    "pressure_bomb": "gui/spells/fire/delayed_fireball.png",
    "prism_engine": "gui/spells/conjuration/fulminant_prism.png",
    # Core loop reset 3.2: new and merged items reuse the tiles their old ids freed.
    "iron_heart": "item/armor/torso/chain_mail_1.png",
    "plate_scrap": "item/armor/torso/plate_1.png",
    "light_boots": "item/armor/feet/low_boots.png",
    "slipstream_boots": "item/armor/feet/boots_4_green.png",
    "shoulder_charge": "item/armor/torso/banded_mail_1.png",
    "second_wind": "gui/spells/components/running.png",
    "pressure_kick": "item/armor/feet/boots_iron_2.png",
    "close_shave": "gui/abilities/jump.png",
    "rear_guard": "item/armor/torso/studded_leather_armor.png",
    "mortar_kit": "gui/spells/fire/fire_storm_new.png",
    "gravity_shot": "item/ring/artefact/urand_shadows_new.png",
    "long_fuse": "gui/spells/translocation/portal_projectile_new.png",
    "fork": "gui/spells/components/hand_4.png",
    "marking_rounds": "item/ring/artefact/urand_octoring.png",
    "rebound": "item/armor/hands/glove_4_new.png",
    "death_shards": "gui/spells/earth/shatter_new.png",
    "reaction_trail": "gui/spells/earth/ledas_liquefaction.png",
    "wide_arc": "item/ring/diamond.png",
    "split_reaction": "item/misc/misc_bottle.png",
    "overheat": "item/armor/torso/splint_mail_1.png",
    "ward_vent": "item/armor/torso/crystal_plate_mail.png",
    "mirror_hide": "item/armor/artefact/urand_augmentation.png",
    "scavengers_eye": "gui/spells/divination/detect_creatures.png",
    "second_nature": "item/ring/moonstone.png",
    "transmuter": "item/ring/emerald.png",
    "overcharge": "gui/spells/air/shock_new.png",
    "spreading_taint": "item/amulet/penta_green.png",
}
## Generated per-element families: "<family>_<el>" -> the element's tile when the pack has
## a matching colour, else `base` with a faint element tint of strength `tint`.
const FAMILY_ICONS := {
    "ring": { "base": "item/ring/steel.png", "tint": 0.45,
        "wet": "item/ring/ring_plain_blue.png", "shock": "item/ring/plain_yellow.png",
        "fire": "item/ring/plain_red.png", "ice": "item/ring/glass.png",
        "oil": "item/ring/plain_black.png", "poison": "item/ring/ring_plain_green.png",
        "acid": "item/ring/agate.png", "blood": "item/ring/coral.png",
        "void": "item/ring/ring_plain_magenta.png", "holy": "item/ring/gold.png",
        "gale": "item/ring/pearl.png", "stone": "item/ring/granite.png" },
    "vial": { "base": "item/potion/clear.png", "tint": 0.45,
        "wet": "item/potion/brilliant_blue_new.png", "shock": "item/potion/yellow_new.png",
        "fire": "item/potion/orange_new.png", "ice": "item/potion/sky_blue.png",
        "oil": "item/potion/black_new.png", "poison": "item/potion/emerald.png",
        "acid": "item/potion/potion_bubbly.png", "blood": "item/potion/ruby_new.png",
        "void": "item/potion/dark.png", "holy": "item/potion/white_new.png",
        "gale": "item/potion/cyan_new.png", "stone": "item/potion/brown_new.png" },
    "charm": { "base": "item/amulet/bone_gray.png", "tint": 0.45,
        "wet": "item/amulet/stone_2_blue.png", "shock": "item/amulet/celtic_yellow.png",
        "fire": "item/amulet/celtic_red.png", "ice": "item/amulet/stone_1_cyan.png",
        "oil": "item/amulet/cylinder_gray.png", "poison": "item/amulet/stone_1_green.png",
        "acid": "item/amulet/eye_green.png", "blood": "item/amulet/stone_2_red.png",
        "void": "item/amulet/stone_3_magenta.png", "holy": "item/amulet/crystal_white.png",
        "gale": "item/amulet/eye_cyan.png", "stone": "item/amulet/bone_gray.png" },
    "mantle": { "base": "item/armor/back/cloak_2.png", "tint": 0.45,
        "wet": "item/armor/torso/robe_ego_2.png", "shock": "item/armor/artefact/urand_starlight.png",
        "fire": "item/armor/artefact/urand_folly.png", "ice": "item/armor/torso/robe_1_old.png",
        "oil": "item/armor/back/cloak_1_leather.png", "poison": "item/armor/torso/robe_3.png",
        "acid": "item/armor/torso/robe_art_1.png", "blood": "item/armor/torso/robe_ego_1.png",
        "void": "item/armor/torso/robe_art_2.png", "holy": "item/armor/artefact/urand_misfortune.png",
        "gale": "item/armor/back/cloak_2.png", "stone": "item/armor/artefact/urand_thief.png" },
    # Scrolls of branding: coloured ribbons where the pack has the colour, a tinted plain
    # scroll for the rest.
    "coating": { "base": "item/scroll/scroll_new.png", "tint": 0.5,
        "wet": "item/scroll/scroll-blue.png", "shock": "item/scroll/scroll-yellow.png",
        "fire": "item/scroll/scroll-red.png", "ice": "item/scroll/scroll-cyan.png",
        "oil": "item/scroll/scroll-grey.png", "poison": "item/scroll/scroll-green.png",
        "void": "item/scroll/scroll-purple.png", "stone": "item/scroll/scroll-brown.png" },
    # No element-coloured gloves in the pack: a white gauntlet tinted by the element.
    "gloves": { "base": "item/armor/hands/gauntlet_1.png", "tint": 0.6 },
}
## Item pools, Isaac style. Which pool a room draws from shapes what it offers.
const POOLS := ["shop", "treasure", "boss", "hidden", "challenge", "arena"]
const ECONOMY_KEYS := ["scrap_gain", "luck", "xp_gain", "carry"]
const DEFENCE_KEYS := ["armor", "max_hp", "regen", "thorns", "dodge", "speed"]
const UTILITY_KEYS := ["range", "proj_speed", "pressure_limit", "vent_charge", "vent_radius", "vent_power"]
const MECHANIC_KEYS := ["bounce", "pierce", "chain_jumps", "proj_count", "lifesteal", "state_duration", "g_count", "g_pierce", "extra_element"]
const BOSS_KEYS := ["max_hp", "dmg", "armor", "potency", "fire_rate", "crit", "regen", "speed", "crit_dmg", "lifesteal", "state_duration", "luck"]
const ELEMENTS := {
    "wet": Element.Kind.WET, "shock": Element.Kind.SHOCK, "fire": Element.Kind.FIRE,
    "ice": Element.Kind.ICE, "oil": Element.Kind.OIL, "poison": Element.Kind.POISON,
    "acid": Element.Kind.ACID, "blood": Element.Kind.BLOOD, "void": Element.Kind.VOID,
    "holy": Element.Kind.HOLY, "gale": Element.Kind.GALE, "stone": Element.Kind.STONE,
}
const ELEMENT_KEYS := {
    Element.Kind.WET: "wet", Element.Kind.SHOCK: "shock", Element.Kind.FIRE: "fire",
    Element.Kind.ICE: "ice", Element.Kind.OIL: "oil", Element.Kind.POISON: "poison",
    Element.Kind.ACID: "acid", Element.Kind.BLOOD: "blood", Element.Kind.VOID: "void",
    Element.Kind.HOLY: "holy", Element.Kind.GALE: "gale", Element.Kind.STONE: "stone",
    Element.Kind.NONE: "none",
}
const ELEMENT_TITLES := {
    "wet": "Tide", "shock": "Storm", "fire": "Ember", "ice": "Frost", "oil": "Tar",
    "poison": "Venom", "acid": "Caustic", "blood": "Crimson", "void": "Abyssal",
    "holy": "Radiant", "gale": "Zephyr", "stone": "Granite",
}
var catalog: Dictionary = {}   # id -> item
var _by_rarity: Array = [[], [], [], [], []]
var _depth := 0
var _counters: Dictionary = {}   # "player:item:trigger" -> events seen, for `every`
var seen_run: Dictionary = {}    # item id -> true once it has appeared this run
var _last_vent: Dictionary = {}  # player instance id -> element kind last vented


## Core loop reset 3.2: every old item id -> its successor. Nothing was dropped without one.
## Saves (Progress), bot builds and telemetry readers run old ids through `migrate_id`.
const LEGACY_IDS := {
    "rusted_helm": "iron_heart", "leather_cap": "iron_heart", "quilted_jerkin": "iron_heart",
    "sturdy_boots": "iron_heart", "bone_ring": "iron_heart", "oak_ring": "iron_heart",
    "iron_band": "iron_heart", "chain_shirt": "iron_heart",
    "iron_pot": "plate_scrap", "padded_vest": "plate_scrap", "patched_coat": "plate_scrap",
    "hobnail_boots": "plate_scrap", "riveted_plate": "plate_scrap",
    "feather_cap": "light_boots", "leather_boots": "light_boots", "runner_wraps": "light_boots",
    "mudwaders": "slipstream_cloak",
    "hide_vest": "bandage_roll", "gardening_gloves": "bandage_roll", "sandals": "bandage_roll",
    "jade_ring": "bandage_roll", "jogging_shoes": "bandage_roll",
    "worn_gloves": "hair_trigger", "ticking_clock": "hair_trigger", "quick_hands": "hair_trigger",
    "fingerless_gloves": "hair_trigger", "bandolier": "hair_trigger",
    "knuckle_wraps": "whetstone",
    "lab_apron": "lab_gloves", "reagent_satchel": "lab_gloves", "catalyst_ring": "lab_gloves",
    "steady_gloves": "copper_ring", "sniper_visor": "copper_ring",
    "wide_brim": "brass_spyglass", "ring_of_reach": "brass_spyglass", "rifled_sleeve": "brass_spyglass",
    "four_leaf_clover": "wishbone_ring", "lucky_cog": "wishbone_ring", "gilded_ring": "wishbone_ring",
    "ledger": "wishbone_ring", "seer_circlet": "wishbone_ring",
    "cargo_vest": "scrap_magnet", "tin_ring": "scrap_magnet", "scavenger_hood": "scrap_magnet",
    "scrappers_mitts": "scrap_magnet",
    "miners_lamp": "thinking_cap", "treaders": "thinking_cap",
    "heat_gauge": "gasket_ring", "bellows": "gasket_ring", "hothead": "gasket_ring",
    "spiked_gauntlets": "thorn_vest", "stompers": "thorn_vest", "anvil_boots": "thorn_vest",
    "fume_mask": "alembic", "pocket_watch": "alembic", "band_of_lingering": "alembic",
    "divers_goggles": "sigil_wet", "ring_of_embers": "sigil_fire", "cinder_clogs": "sigil_fire",
    "lead_shot": "big_iron", "quicksilver_band": "tidewalkers",
    "vampiric_loop": "leech_mail", "grisly_trophy": "leech_mail",
    "tracker_boots": "seeker_lens", "cerebral_spark": "seeker_lens", "feral_fang": "seeker_lens",
    "cluster_rounds": "splinter_charm", "shrapnel_vest": "splinter_charm",
    "detonator_cap": "powder_horn", "phantom_shroud": "wisp_lantern", "twin_moons": "bone_orbit",
    "crown_of_focus": "ricochet_gloves", "ammo_harness": "twin_triggers",
    "chilled_knuckles": "vial_ice", "puddle_jumpers": "vial_wet", "spark_plug": "vial_shock",
    "greased_soles": "tar_coat", "storm_hood": "conductors_mail",
    "sight_rail": "long_barrel", "oiled_bolt": "gun_oil", "exhaust_pipes": "pressure_coupler",
    "smelling_salts": "blood_chalice", "tin_whistle": "blood_chalice", "dowsing_rod": "pocket_storm",
}
const LEGACY_FAMILIES := ["charm", "ring", "mantle", "gloves"]


## An old item id's successor, or the id itself. Needs no catalog (Progress loads first).
func legacy_successor(id: String) -> String:
    if LEGACY_IDS.has(id):
        return String(LEGACY_IDS[id])
    var fam := id.get_slice("_", 0)
    var el := id.substr(fam.length() + 1)
    if fam in LEGACY_FAMILIES and ELEMENTS.has(el):
        return "sigil_" + el
    return id


## An old item id's successor in today's catalog, or "" when unknown.
func migrate_id(id: String) -> String:
    var nid := legacy_successor(id)
    return nid if catalog.has(nid) else ""


## Stacking (3.1): "add" each copy adds the full effect, "dim" each copy adds 60% of the one
## before, "once" only the first counts (and it is never offered again once owned).
static func stack_factor(rule: String, n: int) -> float:
    if n <= 0:
        return 0.0
    match rule:
        "once":
            return 1.0
        "dim":
            return (1.0 - pow(0.6, float(n))) / 0.4
    return float(n)


## Caps so stacking can't break the game (3.1). Player.stat clamps these keys.
const STAT_CAPS := { "dodge": 0.40, "crit": 1.0, "speed": 0.60, "scrap_gain": 0.50, "luck": 0.60 }
## Each Vial's chance per copy is capped here (Items.fire scales chance triggers by count).
const VIAL_CHANCE_CAP := 0.60

## Tags and resonances (3.1, section 12; Emil's decision: sets became these). Owning 3 items
## with a tag forms its resonance; 5 doubles it and adds a visual tier.
const TAGS := ["vent", "guard", "gunslinger", "seeker", "alchemy", "swift", "fortune", "blade", "thrown", "swarm", "ground"]
const TAG_NAMES := { "vent": "Vent", "guard": "Guard", "gunslinger": "Gunslinger", "seeker": "Seeker",
    "alchemy": "Alchemy", "swift": "Swift", "fortune": "Fortune", "blade": "Blade", "thrown": "Thrown", "swarm": "Swarm", "ground": "Ground" }
const TAG_COLORS := {
    "vent": Color(1.00, 0.55, 0.25), "guard": Color(0.65, 0.72, 0.85), "gunslinger": Color(0.95, 0.80, 0.50),
    "seeker": Color(0.55, 0.85, 1.00), "alchemy": Color(0.50, 0.95, 0.55), "swift": Color(0.60, 1.00, 0.92),
    "fortune": Color(1.00, 0.85, 0.30), "blade": Color(0.82, 0.84, 0.92),
    "thrown": Color(0.80, 0.70, 0.55),
    "swarm": Color(0.70, 0.85, 0.55),
    "ground": Color(0.72, 0.62, 0.48),
}
const RESONANCE_AT := [3, 5]
## Tag -> [mods at 3, line at 3]. At 5 every number doubles. An element tag gives +25%
## reaction power for that element and your shots carry its glow.
const RESONANCES := {
    "vent": [{ "vent_charge": 0.30, "vent_radius": 0.25 }, "Vent fills 30% faster, +25% radius"],
    "guard": [{ "armor": 3, "guard_halve": 1 }, "+3 armour; the first hit each room is halved"],
    "gunslinger": [{ "first_gun_count": 1 }, "Your first gun fires 1 more shot"],
    "seeker": [{ "homing": 0.6 }, "All your shots home lightly"],
    "alchemy": [{ "state_duration": 0.40 }, "Elements last 40% longer"],
    "swift": [{ "dash_charges": 1 }, "+1 dash charge"],
    "fortune": [{ "shop_wares": 1, "luck": 0.10 }, "Shops stock 1 more ware"],
    # Arsenal expansion 5.3: at 5 it doubles and swings send a short wave past their reach.
    "blade": [{ "reach": 0.15, "swing_speed": 0.15 }, "Reach and swing speed +15%"],
    # Arsenal expansion 5.3: at 5 it doubles and thrown objects split in two on their last hit.
    "thrown": [{ "thrown_bounce": 1 }, "+1 bounce or return hit"],
    # Arsenal expansion 5.3: at 5 it doubles and summons carry your highest-tier weapon's element.
    "swarm": [{ "summon_cap": 1 }, "+1 to every summon cap"],
    # Arsenal expansion 5.3: at 5 it doubles and your zones react with each other where they touch.
    "ground": [{ "zone_life": 0.30, "zone_radius": 0.15 }, "Zones last 30% longer, radius +15%"],
}

## Synergies (section 12): two specific items (or an item and a tag's resonance), built on
## purpose. `needs`: item ids, "any:<prefix>" (any item whose id starts with it) or
## "res:<tag>" (that tag's resonance). `mods` join the player's stats while it holds; the
## flag `syn_<id>` switches its special rule on in the code that reads it. `color` is its
## signature: the shots and the figure take it on.
const SYNERGIES := [
    { "id": "hunting_shards", "name": "Hunting Shards", "needs": ["seeker_lens", "splinter_charm"], "line": "Your shards now hunt", "color": Color(0.55, 0.9, 1.0) },
    { "id": "reapers_return", "name": "Reaper's Return", "needs": ["mothers_blade", "grip_of_pierce"], "line": "Returning blades cut through everything", "color": Color(0.95, 0.3, 0.35) },
    { "id": "living_orbit", "name": "Living Orbit", "needs": ["bone_orbit", "any:vial_"], "line": "Your orbit carries your vial's element", "color": Color(0.6, 1.0, 0.6) },
    { "id": "wake_of_ruin", "name": "Wake of Ruin", "needs": ["slipstream_boots", "reaction_trail"], "line": "Your dash trail drenches what it passes", "color": Color(1.0, 0.55, 0.2) },
    { "id": "storm_lattice", "name": "Storm Lattice", "needs": ["wide_arc", "fork"], "line": "Chains fork at every jump", "color": Color(0.75, 0.85, 1.0) },
    { "id": "pinball", "name": "Pinball", "needs": ["ricochet_gloves", "gravity_shot"], "line": "Bouncing shots drag foes along", "mods": { "bounce": 1, "pull": 40 }, "color": Color(1.0, 0.5, 0.9) },
    { "id": "cluster_bomb", "name": "Cluster Bomb", "needs": ["splinter_charm", "powder_horn"], "line": "Splinters burst where they land", "color": Color(1.0, 0.7, 0.3) },
    { "id": "thunderhead", "name": "Thunderhead", "needs": ["conductors_mail", "overcharge"], "line": "Chain Lightning hits like a storm", "mods": { "potency:Chain Lightning": 0.6 }, "color": Color(0.7, 0.8, 1.0) },
    { "id": "hellfire", "name": "Hellfire", "needs": ["hot_rod", "overheat"], "line": "Burning foes take 30% more damage", "mods": { "vs_burning": 0.3 }, "color": Color(1.0, 0.4, 0.15) },
    { "id": "duelist", "name": "Duelist", "needs": ["marksman_monocle", "close_shave"], "line": "Every dash sharpens your aim: +15% crit", "mods": { "crit": 0.15 }, "color": Color(1.0, 0.9, 0.5) },
    { "id": "juggernaut", "name": "Juggernaut", "needs": ["shoulder_charge", "res:guard"], "line": "Your dash hits twice as hard", "mods": { "dash_hit": 1.0 }, "color": Color(0.8, 0.8, 0.9) },
    { "id": "crossfire", "name": "Crossfire", "needs": ["rear_guard", "twin_triggers"], "line": "Your guns fire two shots backward", "mods": { "rear_shots": 1 }, "color": Color(1.0, 0.75, 0.4) },
    { "id": "mirror_ward", "name": "Mirror Ward", "needs": ["mirror_hide", "ward_vent"], "line": "Two hits each room bounce back", "mods": { "mirror": 1 }, "color": Color(0.85, 0.85, 1.0) },
    { "id": "plague_bloom", "name": "Plague Bloom", "needs": ["spreading_taint", "plague_censer"], "line": "Elements leap to 2 more foes", "mods": { "taint": 1 }, "color": Color(0.55, 0.95, 0.35) },
    { "id": "echo_chamber", "name": "Echo Chamber", "needs": ["echo_loop", "split_reaction"], "line": "+20% reaction power", "mods": { "potency": 0.2 }, "color": Color(0.8, 0.6, 1.0) },
    { "id": "bone_storm", "name": "Bone Storm", "needs": ["bone_orbit", "skull_choir"], "line": "Two more bones join your orbit", "mods": { "orbitals": 2 }, "color": Color(0.95, 0.92, 0.8) },
    { "id": "blood_tithe", "name": "Blood Tithe", "needs": ["leech_mail", "blood_pact"], "line": "Reactions near you heal 1 more", "mods": { "lifesteal": 1 }, "color": Color(0.9, 0.15, 0.25) },
    { "id": "sunburst", "name": "Sunburst", "needs": ["godhead", "mortar_kit"], "line": "Your shots burst 30 px wider", "mods": { "splash": 30 }, "color": Color(1.0, 0.95, 0.6) },
    { "id": "long_shot", "name": "Long Shot", "needs": ["long_fuse", "brass_spyglass"], "line": "Far shots hit like boulders: +30% size", "mods": { "shot_size": 0.3, "range": 0.2 }, "color": Color(0.9, 0.8, 0.6) },
    { "id": "frostbite", "name": "Frostbite", "needs": ["transmuter", "frost_treads"], "line": "Frozen foes take 40% more damage", "mods": { "vs_frozen": 0.4 }, "color": Color(0.6, 0.9, 1.0) },
    # Arsenal expansion batch 5 (5.4): 30 more, 10 weapon pairs, 12 weapon + item, 8 item pairs.
    # A "gun:<id>" half is a carried weapon (Player.synergy_counts).
    { "id": "conductors_net", "name": "Conductor's Net", "needs": ["gun:storm_kunai", "gun:lightning_rods"], "line": "Shocked foes take 25% more damage", "mods": { "vs_shocked": 0.25 }, "color": Color(0.7, 0.8, 1.0) },
    { "id": "blizzard", "name": "Blizzard", "needs": ["gun:frost_totem", "gun:wind_chime"], "line": "Totems last 50% longer, reach 20% wider", "mods": { "totem_life": 0.5, "zone_radius": 0.2 }, "color": Color(0.75, 0.9, 1.0) },
    { "id": "big_and_little", "name": "Big and Little", "needs": ["gun:clay_golem", "gun:bone_club"], "line": "Melee and summons +20% damage", "mods": { "melee_dmg": 0.2, "summon_dmg": 0.2 }, "color": Color(0.85, 0.75, 0.6) },
    { "id": "reel_and_slash", "name": "Reel and Slash", "needs": ["gun:harpoon", "gun:tide_spear"], "line": "Melee reach +20%", "mods": { "reach": 0.2 }, "color": Color(0.5, 0.75, 1.0) },
    { "id": "fire_and_ice", "name": "Fire and Ice", "needs": ["gun:flare_pistol", "gun:frost_caster"], "line": "Frozen and burning foes take 20% more", "mods": { "vs_frozen": 0.2, "vs_burning": 0.2 }, "color": Color(0.9, 0.6, 0.8) },
    { "id": "storm_front", "name": "Storm Front", "needs": ["gun:arc_rifle", "gun:rain_drone"], "line": "Wet foes take 25% more damage", "mods": { "vs_wet": 0.25 }, "color": Color(0.55, 0.75, 1.0) },
    { "id": "blade_dance", "name": "Blade Dance", "needs": ["gun:twin_fangs", "gun:steel_knives"], "line": "Melee swings 20% faster", "mods": { "swing_speed": 0.2 }, "color": Color(0.85, 0.85, 0.95) },
    { "id": "halo_and_stones", "name": "Halo and Stones", "needs": ["gun:orbit_stones", "gun:ember_halo"], "line": "+1 summon, rings 15% wider", "mods": { "summon_cap": 1, "ring_radius": 0.15 }, "color": Color(1.0, 0.7, 0.4) },
    { "id": "tar_and_spark", "name": "Tar and Spark", "needs": ["gun:slick_wand", "gun:spark_mine"], "line": "Oiled foes take 30% more damage", "mods": { "vs_oiled": 0.3 }, "color": Color(0.6, 0.5, 0.3) },
    { "id": "sunlit_glyphs", "name": "Sunlit Glyphs", "needs": ["gun:radiant_ray", "gun:holy_glyph"], "line": "+20% reaction power", "mods": { "potency": 0.2 }, "color": Color(1.0, 0.95, 0.6) },
    { "id": "parry_wall", "name": "Parry Wall", "needs": ["gun:parry_blade", "ward_vent"], "line": "Your guard holds: +2 armor", "mods": { "armor": 2 }, "color": Color(0.8, 0.85, 0.95) },
    { "id": "killer_bees", "name": "Killer Bees", "needs": ["gun:wasp_nest", "seeker_lens"], "line": "Summons +25% damage", "mods": { "summon_dmg": 0.25 }, "color": Color(0.95, 0.85, 0.3) },
    { "id": "eagle_eye", "name": "Eagle Eye", "needs": ["gun:longshot", "marksman_monocle"], "line": "+15% crit chance", "mods": { "crit": 0.15 }, "color": Color(0.95, 0.9, 0.6) },
    { "id": "twin_rotors", "name": "Twin Rotors", "needs": ["gun:scout_drone", "fork"], "line": "+1 summon", "mods": { "summon_cap": 1 }, "color": Color(0.7, 0.9, 1.0) },
    { "id": "glacial_lance", "name": "Glacial Lance", "needs": ["gun:glacier_lance", "frost_treads"], "line": "Frozen foes take 35% more damage", "mods": { "vs_frozen": 0.35 }, "color": Color(0.6, 0.9, 1.0) },
    { "id": "ember_crown", "name": "Ember Crown", "needs": ["gun:ember_halo", "overheat"], "line": "Burning foes take 25% more damage", "mods": { "vs_burning": 0.25 }, "color": Color(1.0, 0.5, 0.2) },
    { "id": "powder_keg", "name": "Powder Keg", "needs": ["gun:clay_grenade", "powder_horn"], "line": "Your blasts burst 30 px wider", "mods": { "splash": 30 }, "color": Color(1.0, 0.7, 0.35) },
    { "id": "grave_garden", "name": "Grave Garden", "needs": ["gun:ash_garden", "deep_roots"], "line": "+1 to every trap and totem cap", "mods": { "trap_cap": 1 }, "color": Color(0.6, 0.8, 0.4) },
    { "id": "iron_rain", "name": "Iron Rain", "needs": ["gun:boulder_mortar", "brass_spyglass"], "line": "+20% range, shots 20% bigger", "mods": { "range": 0.2, "shot_size": 0.2 }, "color": Color(0.8, 0.75, 0.65) },
    { "id": "blood_moon", "name": "Blood Moon", "needs": ["gun:blood_rapier", "leech_mail"], "line": "Reactions near you heal 1 more", "mods": { "lifesteal": 1 }, "color": Color(0.9, 0.2, 0.3) },
    { "id": "storm_herald", "name": "Storm Herald", "needs": ["gun:storm_pike", "fork"], "line": "Chains reach 1 more foe", "mods": { "chain_jumps": 1 }, "color": Color(0.75, 0.85, 1.0) },
    { "id": "hunters_reel", "name": "Hunter's Reel", "needs": ["gun:harpoon", "hunters_oath"], "line": "Thrown +25% damage", "mods": { "thrown_dmg": 0.25 }, "color": Color(0.6, 0.8, 0.7) },
    { "id": "wildfire", "name": "Wildfire", "needs": ["flash_point", "cinder_heart"], "line": "Burning foes take 30% more damage", "mods": { "vs_burning": 0.3 }, "color": Color(1.0, 0.45, 0.15) },
    { "id": "relay_race", "name": "Relay Race", "needs": ["cross_training", "slingers_rhythm"], "line": "+15% damage", "mods": { "dmg": 0.15 }, "color": Color(0.9, 0.85, 0.7) },
    { "id": "warden_line", "name": "Warden Line", "needs": ["warden_drum", "groundwork"], "line": "Your zones last 30% longer", "mods": { "zone_life": 0.3 }, "color": Color(0.65, 0.8, 0.5) },
    { "id": "glass_cannon", "name": "Glass Cannon", "needs": ["glass_edge", "hollow_crown"], "line": "Crits hit 50% harder", "mods": { "crit_dmg": 0.5 }, "color": Color(0.85, 0.9, 1.0) },
    { "id": "storm_and_rime", "name": "Storm and Rime", "needs": ["storm_step", "rime_step"], "line": "+1 dash charge", "mods": { "dash_charges": 1 }, "color": Color(0.7, 0.9, 1.0) },
    { "id": "cold_iron", "name": "Cold Iron", "needs": ["cold_blood", "frostbite_steel"], "line": "Frozen foes take 30% more damage", "mods": { "vs_frozen": 0.3 }, "color": Color(0.65, 0.85, 0.95) },
    { "id": "rooted_rings", "name": "Rooted Rings", "needs": ["deep_roots", "widen"], "line": "Rings 20% wider, totems last 30% longer", "mods": { "ring_radius": 0.2, "totem_life": 0.3 }, "color": Color(0.6, 0.8, 0.45) },
    { "id": "pack_tactics", "name": "Pack Tactics", "needs": ["handlers_whistle", "pack_howl"], "line": "Summons +20% damage", "mods": { "summon_dmg": 0.2 }, "color": Color(0.85, 0.7, 0.5) },
]

## Synergy rules that fired this run (the --synergy-probe reads it): id -> times.
var syn_hits: Dictionary = {}


func note_syn(id: String) -> void:
    syn_hits[id] = int(syn_hits.get(id, 0)) + 1
    ProcFx.syn_proc(id)


## The local player's item counts, kept by Player.recalc_stats: a roll weights the missing
## half of a synergy you have started (x3), so a synergy is something you can build toward.
var held: Dictionary = {}
const SYNERGY_NUDGE := 3.0


## Tag -> number of owned items carrying it (each copy counts), plus one per carried weapon
## for its family tag (Arsenal expansion 5.3, Brotato's classes: three melee weapons, or
## two and a Blade item, form the Blade resonance).
func tag_counts(player: Player) -> Dictionary:
    var out: Dictionary = {}
    if player == null or not is_instance_valid(player):
        return out
    var counts: Dictionary = player.gear_counts()
    for id in counts.keys():
        for t in get_item(String(id)).get("tags", []):
            out[t] = int(out.get(t, 0)) + int(counts[id])
    for g in player.guns:
        if g != null and is_instance_valid(g) and g.data != null and g.data.family != "gun":
            var ft := g.data.family_tag()
            out[ft] = int(out.get(ft, 0)) + 1
    return out


## 0, 1 (3 items) or 2 (5 items): a tag's resonance tier for this many items.
static func resonance_tier(n: int) -> int:
    return 2 if n >= RESONANCE_AT[1] else (1 if n >= RESONANCE_AT[0] else 0)


## { tag: tier } for every resonance the player has formed.
func resonances(player: Player) -> Dictionary:
    var out: Dictionary = {}
    var tc := tag_counts(player)
    for t in tc.keys():
        var tier := resonance_tier(int(tc[t]))
        if tier > 0:
            out[t] = tier
    return out


## One resonance's mods at `tier` (an element tag: +25% reaction power for it, and a glow).
func resonance_mods(tag: String, tier: int) -> Dictionary:
    var out: Dictionary = {}
    var base: Dictionary = RESONANCES[tag][0] if RESONANCES.has(tag) else { "potency_" + tag: 0.25, "glow_" + tag: 1 }
    for k in base.keys():
        out[k] = float(base[k]) * float(tier)
    if tag == "blade" and tier >= 2:
        out["blade_wave"] = 1.0
    if tag == "thrown" and tier >= 2:
        out["thrown_split"] = 1.0
    if tag == "swarm" and tier >= 2:
        out["swarm_tether"] = 1.0
    if tag == "ground" and tier >= 2:
        out["ground_react"] = 1.0
    return out


func resonance_line(tag: String) -> String:
    if RESONANCES.has(tag):
        return String(RESONANCES[tag][1])
    return "+25%% %s reaction power, shots glow" % tag.capitalize()


func tag_name(tag: String) -> String:
    if TAG_NAMES.has(tag):
        return String(TAG_NAMES[tag])
    return tag.capitalize()


func tag_color(tag: String) -> Color:
    if TAG_COLORS.has(tag):
        return TAG_COLORS[tag]
    if ELEMENTS.has(tag):
        return Element.COLORS[ELEMENTS[tag]]
    return Color.WHITE


## Does a count map (and its resonances) meet one synergy need?
func _need_met(need: String, counts: Dictionary, res: Dictionary) -> bool:
    if need.begins_with("res:"):
        return res.has(need.substr(4))
    if need.begins_with("any:"):
        var pre := need.substr(4)
        for id in counts.keys():
            if String(id).begins_with(pre) and int(counts[id]) > 0:
                return true
        return false
    return int(counts.get(need, 0)) > 0


## Synergies a set of counts forms (ids), given its resonances.
func synergies_for(counts: Dictionary, res: Dictionary) -> Array:
    var out: Array = []
    for s in SYNERGIES:
        var ok := true
        for need in s["needs"]:
            if not _need_met(String(need), counts, res):
                ok = false
                break
        if ok:
            out.append(String(s["id"]))
    return out


func synergy(id: String) -> Dictionary:
    for s in SYNERGIES:
        if String(s["id"]) == id:
            return s
    return {}


## Resonance tiers a count map reaches (for cards that ask "what would taking this do").
func resonances_for(counts: Dictionary, player: Player = null) -> Dictionary:
    var tc: Dictionary = {}
    for id in counts.keys():
        for t in get_item(String(id)).get("tags", []):
            tc[t] = int(tc.get(t, 0)) + int(counts[id])
    if player != null and is_instance_valid(player):
        # Carried weapons count toward their family tag (5.3). Guns don't count toward
        # Gunslinger yet: with four slots nearly every build would form it (batch 1 note).
        for g in player.guns:
            if g != null and is_instance_valid(g) and g.data != null and g.data.family != "gun":
                var ft := g.data.family_tag()
                tc[ft] = int(tc.get(ft, 0)) + 1
    var out: Dictionary = {}
    for t in tc.keys():
        var tier := resonance_tier(int(tc[t]))
        if tier > 0:
            out[t] = tier
    return out


## The synergy taking `id` would form for this player (its dictionary), or {}.
func synergy_if_taken(player: Player, id: String) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {}
    var before: Dictionary = player.synergy_counts(player.gear_counts())
    var after := before.duplicate()
    after[id] = int(after.get(id, 0)) + 1
    var had := synergies_for(before, resonances_for(before))
    for sid in synergies_for(after, resonances_for(after)):
        if not had.has(sid):
            return synergy(String(sid))
    return {}


## True when `id` is one half of a synergy whose other half the local player holds.
func _completes_held(id: String) -> bool:
    if held.is_empty():
        return false
    for s in SYNERGIES:
        var needs: Array = s["needs"]
        if not needs.has(id):
            continue
        for need in needs:
            if String(need) != id and _need_met(String(need), held, {}):
                return true
    return false


## Kept so old callers (journal, figure) read something sensible: an item's first tag.
func set_of(item_id: String) -> String:
    var tags: Array = get_item(item_id).get("tags", [])
    return String(tags[0]) if not tags.is_empty() else ""


func _ready() -> void:
    _build_catalog()


# --- Queries ---------------------------------------------------------------


func get_item(id: String) -> Dictionary:
    return catalog.get(id, {})


func rarity_color(item: Dictionary) -> Color:
    return RARITY_COLORS[clampi(int(item.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)]


## An item's rarity colour for text (Rare and Epic lifted for small text).
func rarity_text_color(item: Dictionary) -> Color:
    return RARITY_TEXT_COLORS[clampi(int(item.get("rarity", 0)), 0, RARITY_TEXT_COLORS.size() - 1)]


## An item's rarity word ("Rare").
func rarity_name(item: Dictionary) -> String:
    return String(RARITY_NAMES[clampi(int(item.get("rarity", 0)), 0, RARITY_NAMES.size() - 1)])


## Guns have tiers, not rarities; in UI a tier wears the rarity palette:
## tier 1 Common, 2 Uncommon, 3 Rare, 4 Epic (Legendary is items only).
static func tier_rarity(tier: int) -> int:
    return clampi(tier - 1, Rarity.COMMON, Rarity.EPIC)


## Frame / border / gem colour of a gun tier (RARITY_COLORS through tier_rarity).
static func tier_color(tier: int) -> Color:
    return RARITY_COLORS[tier_rarity(tier)]


## Text colour of a gun tier (RARITY_TEXT_COLORS through tier_rarity).
static func tier_text_color(tier: int) -> Color:
    return RARITY_TEXT_COLORS[tier_rarity(tier)]


## Brotato-shaped: base + diff + base * 0.08 * diff. `floor_number` is the difficulty
## (callers pass main.difficulty()); the name is kept for compatibility.
func price(item: Dictionary, floor_number: int) -> int:
    var base := float(item.get("price", RARITY_PRICE[int(item.get("rarity", 0))]))
    var diff := float(maxi(0, floor_number))
    return int(roundf(base + 2.0 * diff + base * 0.10 * diff))


## Icon path of an item: its own "icon" field, else its slot's icon.
func icon_path(item: Dictionary) -> String:
    var own := String(item.get("icon", ""))
    if own != "":
        return own
    return String(SLOT_ICONS.get(item.get("slot", "trinket"), SLOT_ICONS["trinket"]))


## An item's icon texture (Dungeon Crawl tile; the old 1-bit slot tile if missing).
func icon(item: Dictionary) -> Texture2D:
    var slot := String(item.get("slot", "trinket"))
    return Art.icon(icon_path(item), SLOT_TILES.get(slot, SLOT_TILES["trinket"]))


## Modulate for an item's icon: white (the tiles are coloured already), or a faint
## element tint for the family items that share one base tile.
func icon_tint(item: Dictionary) -> Color:
    var amount := float(item.get("icon_tint", 0.0))
    if amount > 0.0 and item.has("element"):
        return Color.WHITE.lerp(Element.COLORS[ELEMENTS[item["element"]]], amount)
    return Color.WHITE


## The icon modulate for UI (cards, HUD, sheet, journal): the same family tint, capped
## at a faint wash so the icon never reads as a rarity colour. Never used on a frame.
## (The world sprite and the costume keep `icon_tint`.)
const UI_TINT_MAX := 0.25


func ui_icon_tint(item: Dictionary) -> Color:
    var amount := minf(float(item.get("icon_tint", 0.0)), UI_TINT_MAX)
    if amount > 0.0 and item.has("element"):
        return Color.WHITE.lerp(Element.COLORS[ELEMENTS[item["element"]]], amount)
    return Color.WHITE


## Placeholder icon of an empty slot ("ring1" and "trinket2" read as their slot).
func slot_icon(slot: String) -> Texture2D:
    var key := slot.rstrip("12")
    return Art.icon(String(SLOT_ICONS.get(key, SLOT_ICONS["trinket"])), SLOT_TILES.get(key, SLOT_TILES["trinket"]))


## Gives every item its "icon" (and "icon_tint" for tinted family pieces): hand-made
## items from ICONS, element families from FAMILY_ICONS. Anything left falls back to its
## slot icon in `icon_path`.
func _apply_icons() -> void:
    for id in catalog.keys():
        var it: Dictionary = catalog[id]
        if ICONS.has(id):
            it["icon"] = ICONS[id]
            continue
        var family := String(id).get_slice("_", 0)
        var el := String(it.get("element", ""))
        if el == "" or String(id) != "%s_%s" % [family, el]:
            continue
        if family == "sigil":
            family = "charm"   # the Sigils wear the old element charms' amulets
        if not FAMILY_ICONS.has(family):
            continue
        var fam: Dictionary = FAMILY_ICONS[family]
        if fam.has(el):
            it["icon"] = fam[el]
        else:
            it["icon"] = fam["base"]
            it["icon_tint"] = float(fam["tint"])


## Depth multiplier for prices and scrap (Core loop reset 6.1): 1.0, 1.25, 1.5, 1.75, 2.0.
static func depth_mult(floor_number: int) -> float:
    return 1.0 + 0.25 * float(maxi(1, floor_number) - 1)


## Shop price of a ware of `rarity` on `floor_number` (section 6.2): 25 / 40 / 65 / 100 / 150
## on floor 1, x m deeper.
func price_at(rarity: int, floor_number: int) -> int:
    return int(roundf(float(PRICE_BASE[clampi(rarity, 0, PRICE_BASE.size() - 1)]) * depth_mult(floor_number)))


## Rarity weights for a roll (section 6.4). `table`: "shop", "treasure" (never Common,
## Legendary from TREASURE_LEGENDARY), "boss" (never under Rare), "deal" (Epic or Legendary).
func rarity_weights(table: String, floor_number: int, luck: float = 0.0, weapon: bool = false) -> Array:
    var f := clampi(floor_number, 1, SHOP_ODDS.size()) - 1
    var w: Array = ((Guns.RARITY_ODDS[f] if weapon else SHOP_ODDS[f]) as Array).duplicate()
    match table:
        "treasure":
            var leg := float(Guns.TREASURE_LEGENDARY[f] if weapon else TREASURE_LEGENDARY[f])
            w = [0.0, float(w[0] + w[1]) - (leg - float(w[4])), float(w[2]), float(w[3]), leg]
        "boss":
            w = [0.0, 0.0, float(w[0] + w[1] + w[2]), float(w[3]), float(w[4])]
        "deal":
            w = [0.0, 0.0, 0.0, float(w[3]), maxf(1.0, float(w[4]))]
    var l := 1.0 + clampf(luck, 0.0, LUCK_CAP)
    for r in [Rarity.RARE, Rarity.EPIC, Rarity.LEGENDARY]:
        w[r] = float(w[r]) * l
    return w


## One rarity from `rarity_weights`, capped by the Shrine's rarity unlocks.
func roll_rarity(table: String, floor_number: int, luck: float = 0.0, weapon: bool = false) -> int:
    var w := rarity_weights(table, floor_number, luck, weapon)
    var total := 0.0
    for v in w:
        total += float(v)
    var at := randf() * total
    var r := 0
    for i in w.size():
        at -= float(w[i])
        if at < 0.0:
            r = i
            break
    return mini(r, max_rarity_unlocked())


## The floor's median shop rarity (the mystery ware rolls one above it).
func median_rarity(floor_number: int) -> int:
    var f := clampi(floor_number, 1, SHOP_ODDS.size()) - 1
    var acc := 0
    for i in (SHOP_ODDS[f] as Array).size():
        acc += int(SHOP_ODDS[f][i])
        if acc >= 50:
            return i
    return Rarity.COMMON


## Behaviour items change how you shoot or play (triggers, mechanics, actives); element
## changers carry an element. Treasure leans to behaviour, bosses offer one of each.
func is_behaviour(it: Dictionary) -> bool:
    if not (it.get("triggers", []) as Array).is_empty() or String(it.get("slot", "")) == "active":
        return true
    for k in (it.get("mods", {}) as Dictionary).keys():
        if k in MECHANIC_KEYS:
            return true
    return false


func is_element_changer(it: Dictionary) -> bool:
    return it.has("element") or (it.get("mods", {}) as Dictionary).has("extra_element")


## Strong with a clear drawback: any stat it lowers. These show the red Cursed chip too.
func is_tradeoff(it: Dictionary) -> bool:
    for v in (it.get("mods", {}) as Dictionary).values():
        if (v is float or v is int) and float(v) < 0.0:
            return true
    return false


func max_rarity_unlocked() -> int:
    if Progress.has("rarity:legendary"):
        return Rarity.LEGENDARY
    if Progress.has("rarity:epic"):
        return Rarity.EPIC
    return Rarity.RARE


## Chance that a roll at `difficulty` lands on `rarity` (checked from legendary down).
func rarity_chance(rarity: int, difficulty: int, luck: float = 0.0) -> float:
    if not RARITY_ODDS.has(rarity):
        return 0.0
    var odds: Array = RARITY_ODDS[rarity]
    var min_diff := int(odds[0])
    if difficulty < min_diff:
        return 0.0
    var growth := float(odds[1])
    var cap := float(odds[2])
    return clampf(growth * float(difficulty - min_diff + 1) * (1.0 + luck), 0.0, cap)


## Random item id. Tiered odds: each rarity above common has a min difficulty, a growth
## per difficulty and a cap, scaled by `luck`; checked from legendary down to uncommon,
## else common. `min_rarity` raises the floor; unlocks cap the result. `pool` limits the
## draw to one of POOLS ("" = any). Items seen this run are skipped; the roll steps down
## a rarity at a time, and only allows repeats once the pool is dry at every rarity.
func roll(difficulty: int, min_rarity: int = Rarity.COMMON, exclude: Array = [], luck: float = 0.0, pool: String = "") -> String:
    var cap := max_rarity_unlocked()
    var rarity: int = Rarity.COMMON
    for r in [Rarity.LEGENDARY, Rarity.EPIC, Rarity.RARE, Rarity.UNCOMMON]:
        if r > cap:
            continue
        if randf() < rarity_chance(r, difficulty, luck):
            rarity = r
            break
    rarity = mini(maxi(rarity, min_rarity), cap)
    for pass_pool in [pool, ""]:
        for allow_seen in [false, true]:
            var step := rarity
            while step >= 0:
                var ids := _candidates(step, pass_pool, exclude, allow_seen)
                if not ids.is_empty():
                    return _pick_weighted(ids)
                step -= 1
    return "iron_heart"


## Arsenal expansion 6.1: new items start locked ("locked": true) and open with an
## "item:<id>" unlock; everything older is in the pool from the start.
func unlocked(id: String) -> bool:
    return not bool(catalog.get(id, {}).get("locked", false)) or Progress.has("item:" + id)


func _candidates(rarity: int, pool: String, exclude: Array, allow_seen: bool) -> Array:
    return _by_rarity[rarity].filter(func(id):
        if exclude.has(id) or (not allow_seen and seen_run.has(id)) or not unlocked(String(id)):
            return false
        if String(catalog[id].get("stack", "add")) == "once" and int(held.get(id, 0)) > 0:
            return false
        return pool == "" or catalog[id].get("pools", POOLS).has(pool))


func _pick_weighted(ids: Array) -> String:
    var total := 0.0
    for id in ids:
        total += _weight(String(id))
    var at := randf() * total
    for id in ids:
        at -= _weight(String(id))
        if at <= 0.0:
            return id
    return ids[ids.size() - 1]


func _weight(id: String) -> float:
    var w := float(catalog[id].get("weight", 1.0))
    if _completes_held(id):
        w *= SYNERGY_NUDGE
    return w


## Isaac's pool quality: treasure and hidden rooms never offer commons.
func pool_min_rarity(pool: String) -> int:
    if pool == "treasure" or pool == "hidden":
        return Rarity.UNCOMMON
    return Rarity.COMMON


## Ids in a pool (any rarity), for debugging and UI.
func pool_items(pool: String) -> Array:
    var out: Array = []
    for id in catalog.keys():
        if catalog[id].get("pools", POOLS).has(pool):
            out.append(id)
    return out


## Start of a run: every item is back in its pool.
func new_run() -> void:
    Legendary.new_run()
    seen_run.clear()
    held.clear()
    syn_hits.clear()
    _counters.clear()
    _last_vent.clear()


## An item has appeared (offered, dropped or taken): it leaves the pools for this run.
func mark_seen(id: String) -> void:
    if id != "":
        seen_run[id] = true


func offer(id: String, price_scrap: int, pos = null) -> Dictionary:
    var o := { "kind": "item", "id": id, "price": price_scrap, "amount": 0, "taken": false }
    if pos != null:
        o["pos"] = pos
    return o


# --- Effect engine ---------------------------------------------------------


## Fire every trigger on the player's gear that matches `event`.
func fire(player: Player, event: String, ctx: Dictionary) -> void:
    if player == null or not is_instance_valid(player) or _depth > 2:
        return
    Legendary.on_event(player, event, ctx)
    if event == "vent":
        _last_vent[player.get_instance_id()] = int(ctx.get("element", Element.Kind.FIRE))
    elif event == "room_clear":
        recharge_active(player, 1)
    if event == "room_clear" or event == "room_enter":
        player.mirror_left = int(player.stat("mirror"))
        player.guard_left = 1 if player.stat("guard_halve") > 0.0 else 0
    _depth += 1
    var counts: Dictionary = player.gear_counts()
    for id in counts.keys():
        var item: Dictionary = catalog.get(id, {})
        var triggers: Array = item.get("triggers", [])
        if triggers.is_empty():
            continue
        # Stacking (3.1): a "once" item counts once; chance triggers scale their chance by
        # the copies (a Vial is capped at VIAL_CHANCE_CAP); "<key>_per" grows a number per
        # extra copy; anything else fires once per copy.
        var n: int = 1 if String(item.get("stack", "add")) == "once" else int(counts[id])
        for ti in triggers.size():
            var t: Dictionary = triggers[ti]
            if not _event_matches(t["on"], event, ctx):
                continue
            if t.get("melee", false) and Guns.family_of(String(ctx.get("gun", ""))) != "melee":
                continue   # a Blade item's trigger: only hits and kills by a melee weapon
            if t.has("family") and Guns.family_of(String(ctx.get("gun", ""))) != String(t["family"]):
                continue   # a family item's trigger (Thrown): only hits and kills by that family
            if t.has("every"):
                var ckey := "%d:%s:%d" % [player.get_instance_id(), id, ti]
                var seen: int = int(_counters.get(ckey, 0)) + 1
                _counters[ckey] = seen
                var every := maxi(2, int(t["every"]) + int(t.get("every_per", 0)) * (n - 1))
                if seen % every != 0:
                    continue
            var reps := n
            if t.has("chance"):
                var cap := VIAL_CHANCE_CAP if String(id).begins_with("vial_") else 1.0
                if randf() > minf(cap, float(t["chance"]) * float(n)):
                    continue
                reps = 1
            if t.has("if") and not condition(t["if"], player, ctx):
                continue
            var tt := t
            if _has_per(t):
                tt = _scaled(t, n)
                reps = 1
            if ProcFx.is_proc(t, event, n):
                ProcFx.item_proc(player, item, tt, ctx)   # light and sound, rate-limited
            for r in reps:
                _do(tt, player, ctx)
    # Level-up boons and Shrine talents that act like gear triggers (LevelUps echo boons,
    # Mastery.BRANCHES choices).
    for bi in player.boon_triggers.size():
        var t: Dictionary = player.boon_triggers[bi]
        if not _event_matches(t["on"], event, ctx):
            continue
        if t.has("every"):
            var bkey := "%d:boon:%d" % [player.get_instance_id(), bi]
            var bseen: int = int(_counters.get(bkey, 0)) + 1
            _counters[bkey] = bseen
            if bseen % maxi(2, int(t["every"])) != 0:
                continue
        if t.has("chance") and randf() > float(t["chance"]):
            continue
        if t.has("if") and not condition(t["if"], player, ctx):
            continue
        if t.has("talent"):
            Mastery.note_fired(String(t["talent"]))
        _do(t, player, ctx)
    _depth -= 1


func _has_per(t: Dictionary) -> bool:
    for k in t.keys():
        if String(k).ends_with("_per") and String(k) != "every_per":
            return true
    return false


## A trigger with its "<key>_per" numbers applied for `n` copies.
func _scaled(t: Dictionary, n: int) -> Dictionary:
    var out := t.duplicate()
    for k in t.keys():
        var key := String(k)
        if key.ends_with("_per") and key != "every_per":
            var base := key.substr(0, key.length() - 4)
            out[base] = float(t.get(base, 0.0)) + float(t[k]) * float(n - 1)
    return out


func _event_matches(on: String, event: String, ctx: Dictionary) -> bool:
    if on == event:
        return true
    if on.begins_with("reaction:") and event == "reaction":
        return ctx.get("reaction", "") == on.substr(9)
    return false


func condition(c: String, player: Player, ctx: Dictionary) -> bool:
    var target = ctx.get("target")
    var tv: bool = target != null and is_instance_valid(target) and target is Enemy
    match c:
        "target_wet":
            return tv and target.has_state(Element.Kind.WET)
        "target_burning":
            return tv and target.burn_time > 0.0
        "target_frozen":
            return tv and target.frozen_time > 0.0
        "target_shocked":
            return tv and target.has_state(Element.Kind.SHOCK)
        "target_oiled":
            return tv and target.has_state(Element.Kind.OIL)
        "target_poisoned":
            return tv and target.poison_time > 0.0
        "target_marked":
            return tv and not target.states.is_empty()
        "elite":
            return tv and target.is_elite
        "hot":
            return player.pressure > 30.0
        "cold":
            return player.pressure < -30.0
        "calm":
            return absf(player.pressure) <= 15.0
        "low_hp":
            return player.hp < player.max_hp * 0.4
        "high_hp":
            return player.hp >= player.max_hp * 0.8
        "full_hp":
            return player.hp >= player.max_hp - 0.5
        "moving":
            return player.velocity.length() > 20.0
        "still":
            return player.velocity.length() <= 20.0
    if c.begins_with("el_"):
        # A reaction event that involves this element (incoming or the state it met).
        var k: int = ELEMENTS.get(c.substr(3), -1)
        return k >= 0 and (int(ctx.get("element", -1)) == k or int(ctx.get("other", -1)) == k)
    return false


func _element_of(t: Dictionary, ctx: Dictionary, player: Player = null) -> int:
    var e: String = t.get("element", "wet")
    if e == "last":
        return int(ctx.get("element", Element.Kind.WET))
    if e == "vent" and player != null:
        return vent_element(player)
    if e == "gun" and player != null:
        return int(player.guns[0].data.element) if not player.guns.is_empty() and player.guns[0].data != null else Element.Kind.FIRE
    return ELEMENTS.get(e, Element.Kind.WET)


func _do(t: Dictionary, player: Player, ctx: Dictionary) -> void:
    var pos: Vector2 = ctx.get("pos", player.global_position)
    var target = ctx.get("target")
    var tv: bool = target != null and is_instance_valid(target) and target is Enemy and not target.is_queued_for_deletion()
    if t.get("at", "") == "target" and tv:
        pos = target.global_position
    var potency := float(t.get("potency", 5.0))
    match t["do"]:
        "apply":
            if tv:
                target.apply_element(_element_of(t, ctx, player), potency, player)
        "nova":
            nova(player, pos, _element_of(t, ctx, player), float(t.get("radius", 120.0)), potency)
        "heal":
            player.heal(float(t.get("amount", 10.0)), "active" if ctx.get("active", false) else "item")
        "scrap":
            player.main().add_scrap(int(t.get("amount", 5)))
        "pressure":
            player.add_pressure(float(t.get("amount", 0.0)))
        "shoot":
            shoot(player, pos, _element_of(t, ctx, player), int(t.get("count", 3)), potency, target if tv else null)
        "shield":
            player.invuln = maxf(player.invuln, float(t.get("amount", 1.0)))
        "slow":
            for e in _enemies_within(pos, float(t.get("radius", 160.0))):
                e.apply_slow(0.5, 2.5)
        "chain":
            if t.has("count"):
                var near := _enemies_within(pos, float(t.get("radius", 400.0)))
                near.sort_custom(func(a, b): return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
                for i in mini(int(t["count"]), near.size()):
                    if is_instance_valid(near[i]) and not near[i].is_queued_for_deletion():
                        Elements._chain_lightning(near[i], potency)
            elif tv:
                Elements._chain_lightning(target, potency)
        "spread":
            var kind := _element_of(t, ctx, player)
            var col: Color = Element.COLORS[kind]
            Elements.nova.emit(pos, float(t.get("radius", 140.0)), Color(col, 0.3))
            for e in _enemies_within(pos, float(t.get("radius", 140.0))):
                e.apply_element(kind, potency, player)
        "xp":
            player.gain_xp(float(t.get("amount", 5.0)))
        "buff":
            player.add_buff(String(t.get("key", "dmg")), float(t.get("amount", 0.1)), float(t.get("secs", 2.0)))
        "trail":
            # The dash leaves patches of an element along its line (Slipstream Boots).
            var el := _element_of(t, ctx, player)
            var dir: Vector2 = ctx.get("dir", Vector2.RIGHT)
            var parent := player.get_parent()
            for k in 4:
                Cloud.spawn(parent, pos + dir * 40.0 * float(k), el, 42.0, float(t.get("secs", 2.0)), 4.0, player)
            if player.stat("syn_wake_of_ruin") > 0.0:
                note_syn("wake_of_ruin")
                for e in _enemies_within(pos + dir * 60.0, 120.0):
                    e.apply_element(el, 6.0, player)
        "cloud":
            Cloud.spawn(player.get_parent(), pos, _element_of(t, ctx, player), float(t.get("radius", 60.0)), float(t.get("secs", 3.0)), maxf(3.0, potency * 0.5), player)
        "mark":
            if tv:
                target.marked_t = maxf(float(target.marked_t), float(t.get("secs", 4.0)))
        "split":
            var a := int(ctx.get("element", -1))
            var b := int(ctx.get("other", -1))
            for el2 in [a, b]:
                if el2 > Element.Kind.NONE:
                    shoot(player, pos, el2, int(t.get("count", 1)), potency, target if tv else null)
        "ward":
            player.ward_t = maxf(player.ward_t, float(t.get("secs", 3.0)))
        "recall":
            Thrown.recall_all(player, float(t.get("mult", 2.0)))
        "rally":
            Summon.rally(player, float(t.get("mult", 1.5)))
        "brood":
            Summon.brood(player, String(ctx.get("gun", "")), pos, int(t.get("count", 1)), float(t.get("secs", 4.0)))
        "swarm_call":
            Summon.brood(player, "", player.global_position, int(t.get("count", 6)), float(t.get("secs", 8.0)))
        "hair_trigger":
            GroundZone.spring_near(player, float(t.get("radius", 90.0)))
        "seed":
            GroundZone.seed_all(player)
        "spring_all":
            GroundZone.spring_all(player)
        "dash_refill":
            # Second Wind (Mastery): a kill gives back one dash charge.
            player.dash_charges = mini(player.dash_max_charges(), player.dash_charges + 1)


## The element a vent makes for this player: what they last vented, else hot fire / cold ice.
func vent_element(player: Player) -> int:
    if _last_vent.has(player.get_instance_id()):
        return int(_last_vent[player.get_instance_id()])
    return Element.Kind.ICE if player.pressure < 0.0 else Element.Kind.FIRE


# --- Active items ----------------------------------------------------------


## The player's active item, or {}.
func active_of(player: Player) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {}
    return catalog.get(player.equipment.get("active", ""), {})


func active_max_charges(player: Player) -> int:
    var it := active_of(player)
    if it.is_empty():
        return 0
    return int(it.get("active", {}).get("charges", 1))


## Refill `amount` charges (room clears refill one); equipping fills them all.
func recharge_active(player: Player, amount: int) -> void:
    var max_charges := active_max_charges(player)
    if max_charges <= 0:
        return
    # A spark cell (RoomPickup) can overcharge by one: a refill never takes that back.
    player.active_charges = maxi(player.active_charges, clampi(player.active_charges + amount, 0, max_charges))


## Spend one charge and run the active item's actions. False when there is nothing to use.
func use_active(player: Player) -> bool:
    var it := active_of(player)
    if it.is_empty() or not player.alive:
        return false
    if player.active_charges <= 0:
        Sfx.play("error")
        player.say("%s is recharging" % it["name"])
        return false
    player.active_charges -= 1
    var target = null
    if player.has_method("nearest_enemy"):
        target = player.nearest_enemy(900.0)
    var ctx := {
        "pos": player.global_position, "target": target,
        "element": int(_last_vent.get(player.get_instance_id(), Element.Kind.FIRE)),
    }
    ctx["active"] = true
    _depth += 1
    for action in it.get("active", {}).get("do", []):
        _do(action, player, ctx)
    _depth -= 1
    Sfx.play("active_use")
    player.say(it["name"])
    return true


func nova(player: Player, pos: Vector2, element: int, radius: float, potency: float) -> void:
    var col: Color = Element.COLORS[element]
    Elements.nova.emit(pos, radius, Color(col, 0.5))
    for e in _enemies_within(pos, radius):
        e.take_damage(potency, col, true, player)
        if is_instance_valid(e) and not e.is_queued_for_deletion():
            e.apply_element(element, potency, player)


func shoot(player: Player, pos: Vector2, element: int, count: int, potency: float, target: Node2D) -> void:
    var world := player.get_tree().current_scene
    for i in count:
        var dir := Vector2.RIGHT.rotated(randf() * TAU)
        if target != null:
            dir = (target.global_position - pos).normalized().rotated(randf_range(-0.35, 0.35))
        var p := Projectile.new()
        p.velocity = dir * 650.0
        p.damage = potency
        p.element = element
        p.potency = potency
        p.lifetime = 0.7
        p.radius = 5.0
        p.color = Element.COLORS[element]
        p.shooter = player
        p.global_position = pos
        world.add_child(p)


func _enemies_within(pos: Vector2, radius: float) -> Array:
    var out: Array = []
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e) and not e.is_queued_for_deletion() and e.global_position.distance_to(pos) <= radius:
            out.append(e)
    return out


# --- Catalog ---------------------------------------------------------------


func _add(id: String, name: String, slot: String, rarity: int, desc: String, mods: Dictionary = {}, triggers: Array = [], extra: Dictionary = {}) -> void:
    var item := { "id": id, "name": name, "slot": slot, "rarity": rarity, "desc": desc, "mods": mods, "triggers": triggers }
    for k in extra.keys():
        item[k] = extra[k]
    catalog[id] = item
    _by_rarity[rarity].append(id)


func _build_catalog() -> void:
    # Core loop reset 3.2: about 145 items, no slots. "slot" is only the body part an item
    # dresses (its look); mods sit on guns and actives in the one active slot. Every old id
    # maps to a successor in LEGACY_IDS. Lines follow 4.4: one line, at most 10 words and
    # two numbers, a verb first for behaviour, a signed number with a unit for stats.
    var C := Rarity.COMMON
    var U := Rarity.UNCOMMON
    var R := Rarity.RARE
    var E := Rarity.EPIC
    var L := Rarity.LEGENDARY
    var TR := ["treasure"]
    var TH := ["treasure", "hidden"]

    # ======================= PLAIN STATS (72 old items became these 19)
    _add("iron_heart", "Iron Heart", "chest", C, "+15 max HP", { "max_hp": 15 }, [], { "tags": ["guard"] })
    _add("plate_scrap", "Plate Scrap", "chest", C, "+3 armour", { "armor": 3 }, [], { "tags": ["guard"] })
    _add("light_boots", "Light Boots", "feet", C, "+6% move speed", { "speed": 0.06 }, [], { "tags": ["swift"] })
    _add("slipstream_cloak", "Slipstream Cloak", "chest", U, "+6% speed, +4% dodge", { "speed": 0.06, "dodge": 0.04 }, [], { "tags": ["swift"] })
    _add("bandage_roll", "Bandage Roll", "trinket", C, "+10% Mending reserve", { "mend": 0.10 }, [], { "tags": ["guard"] })
    _add("hair_trigger", "Hair Trigger", "hands", C, "+8% fire rate", { "fire_rate": 0.08 }, [], { "tags": ["gunslinger"] })
    _add("whetstone", "Whetstone", "trinket", C, "+8% damage", { "dmg": 0.08 }, [], { "tags": ["gunslinger"] })
    _add("lab_gloves", "Lab Gloves", "hands", C, "+8% reaction power", { "potency": 0.08 }, [], { "tags": ["alchemy"] })
    _add("copper_ring", "Copper Ring", "ring", C, "+4% crit chance", { "crit": 0.04 }, [], { "tags": ["gunslinger"] })
    _add("brass_spyglass", "Spyglass", "trinket", C, "+15% range", { "range": 0.15 }, [], { "tags": ["seeker"] })
    _add("wishbone_ring", "Wishbone", "ring", C, "+8% luck", { "luck": 0.08 }, [], { "tags": ["fortune"] })
    _add("rabbit_foot", "Rabbit's Foot", "trinket", R, "+20% luck", { "luck": 0.20 }, [], { "tags": ["fortune"], "price": 38 })
    _add("scrap_magnet", "Scrap Magnet", "trinket", C, "+10% scrap", { "scrap_gain": 0.10 }, [], { "tags": ["fortune"] })
    _add("coin_purse", "Coin Purse", "trinket", U, "+25% scrap, -10 max HP", { "scrap_gain": 0.25, "max_hp": -10 }, [], { "tags": ["fortune"] })
    _add("thinking_cap", "Thinking Cap", "head", U, "+15% XP", { "xp_gain": 0.15 }, [], { "tags": ["fortune"] })
    _add("gasket_ring", "Gasket", "ring", C, "+15 vent capacity", { "pressure_limit": 15 }, [], { "tags": ["vent"] })
    _add("pressure_valve", "Pressure Valve", "trinket", R, "Vent fills 40% faster, +15% vent power", { "vent_charge": 0.4, "vent_power": 0.15 }, [], { "tags": ["vent"] })
    _add("thorn_vest", "Thorn Vest", "chest", U, "Attackers take 6 damage", { "thorns": 6 }, [], { "tags": ["guard"] })
    _add("alembic", "Alembic", "trinket", R, "Elements last 25% longer", { "state_duration": 0.25 }, [], { "tags": ["alchemy"] })

    # ======================= TRADE-OFFS (one gain, one cost)
    _add("boiler_cap", "Boiler Cap", "head", E, "+40% vent power, -8% move speed", { "vent_power": 0.40, "speed": -0.08 }, [], { "tags": ["vent"] })
    _add("berserker_helm", "Berserker Helm", "head", E, "Below 40% HP: +50% damage", {}, [], { "tags": ["gunslinger"], "cond_mods": { "low_hp": { "dmg": 0.50 } } })
    _add("blood_pact", "Blood Pact", "trinket", E, "+30% damage, -25 max HP", { "dmg": 0.30, "max_hp": -25 }, [], { "tags": ["blood"] })
    _add("frenzy_band", "Frenzy Band", "ring", E, "+30% fire rate, -20 max HP", { "fire_rate": 0.30, "max_hp": -20 }, [], { "tags": ["gunslinger"] })
    _add("hot_rod", "Hot Rod", "trinket", E, "+35% damage while your gauge runs hot", {}, [], { "tags": ["vent", "fire"], "cond_mods": { "hot": { "dmg": 0.35 } } })
    _add("cold_snap", "Cold Snap", "trinket", E, "+35% reaction power while your gauge runs cold", {}, [], { "tags": ["vent", "ice"], "cond_mods": { "cold": { "potency": 0.35 } } })
    _add("hover_greaves", "Hover Greaves", "feet", E, "+15% dodge, -15 max HP", { "dodge": 0.15, "max_hp": -15 }, [], { "tags": ["swift"] })
    _add("executioners_grip", "Executioner's Grip", "hands", E, "+80% crit damage, -12% fire rate", { "crit_dmg": 0.8, "fire_rate": -0.12 }, [], { "tags": ["gunslinger"] })
    _add("big_iron", "Big Iron", "ring", E, "+60% shot size, -15% fire rate", { "shot_size": 0.6, "fire_rate": -0.15 }, [], { "tags": ["gunslinger"], "pools": TH, "weight": 0.4 })
    _add("tidewalkers", "Tidewalkers", "feet", R, "+20% reaction power while moving", {}, [], { "tags": ["swift", "alchemy"], "cond_mods": { "moving": { "potency": 0.20 } } })
    _add("bloodstone", "Bloodstone", "ring", R, "Below 40% HP: +25% damage", {}, [], { "tags": ["blood"], "cond_mods": { "low_hp": { "dmg": 0.25 } } })
    _add("seven_league", "Seven-League Boots", "feet", L, "+20% speed, +20% damage while moving", { "speed": 0.20 }, [], { "tags": ["swift"], "cond_mods": { "moving": { "dmg": 0.20 } } })
    _add("marksman_monocle", "Marksman's Monocle", "head", R, "+50% crit damage for 2 s after a dash", {}, [{ "on": "dash", "do": "buff", "key": "crit_dmg", "amount": 0.5, "secs": 2.0, "secs_per": 1.0 }], { "tags": ["gunslinger", "swift"] })

    # ======================= HEALING
    _add("leech_mail", "Leech Mail", "chest", R, "Reactions near you heal 1", { "lifesteal": 1 }, [], { "tags": ["blood", "guard"] })
    _add("phoenix_mantle", "Phoenix Mantle", "chest", L, "Hit below 40% HP: may heal 30 and erupt", { "max_hp": 20 }, [{ "on": "hurt", "if": "low_hp", "chance": 0.35, "do": "heal", "amount": 30 }, { "on": "hurt", "if": "low_hp", "chance": 0.35, "do": "nova", "element": "fire", "radius": 220, "potency": 14 }], { "tags": ["fire", "guard"], "stack": "once" })

    # ======================= BEHAVIOUR, KEPT AND MERGED
    _add("seeker_lens", "Seeker Lens", "head", R, "Shots curve toward enemies", { "homing": 1.5 }, [], { "tags": ["seeker"], "pools": TR, "weight": 0.6 })
    _add("godhead", "Godhead", "head", L, "Shots seek, swell and burst in light", { "homing": 2.5, "splash": 40, "shot_size": 0.2 }, [], { "tags": ["seeker", "holy"], "stack": "dim", "pools": TH, "weight": 0.3 })
    _add("splinter_charm", "Splinter Charm", "ring", R, "Shots break into 2 splinters", { "shards": 2 }, [], { "tags": ["gunslinger"], "pools": TR, "weight": 0.5 })
    _add("hive_heart", "Hive Heart", "chest", L, "Shots burst into 4 shards; a drone orbits you", { "shards": 4, "orbitals": 1 }, [], { "tags": ["gunslinger", "guard"], "stack": "once", "pools": TH, "weight": 0.3 })
    _add("powder_horn", "Powder Horn", "trinket", R, "Shots splash 30 px where they land", { "splash": 30 }, [], { "tags": ["gunslinger"], "pools": TR, "weight": 0.6 })
    _add("wisp_lantern", "Wisp Lantern", "trinket", R, "Shots pass through rocks and crates", { "spectral": 1 }, [], { "tags": ["seeker"], "stack": "once", "pools": TR, "weight": 0.5 })
    _add("bone_orbit", "Bone Orbit", "trinket", R, "A bone circles you, striking what it touches", { "orbitals": 1 }, [], { "tags": ["guard"], "pools": TR, "weight": 0.6 })
    _add("skull_choir", "Skull Choir", "trinket", L, "3 skulls orbit you, carrying your element", { "orbitals": 3, "orbital_element": 1 }, [], { "tags": ["guard", "void"], "stack": "once", "pools": TR, "weight": 0.3 })
    _add("ricochet_gloves", "Ricochet Gloves", "hands", R, "Shots bounce to 1 more enemy", { "bounce": 1 }, [], { "tags": ["gunslinger"] })
    _add("storm_halo", "Storm Halo", "ring", L, "Shots bounce twice; 30% of hits shock", { "bounce": 2 }, [{ "on": "hit", "chance": 0.30, "do": "apply", "element": "shock", "potency": 4 }], { "tags": ["shock", "gunslinger"], "stack": "once", "weight": 0.3 })
    _add("grip_of_pierce", "Grip of Pierce", "hands", R, "Shots pierce 1 more enemy", { "pierce": 1 }, [], { "tags": ["gunslinger"] })
    _add("twin_triggers", "Twin Triggers", "hands", E, "Every gun fires 1 more shot, -10% damage", { "proj_count": 1, "dmg": -0.10 }, [], { "tags": ["gunslinger"], "stack": "dim", "weight": 0.5 })
    _add("mothers_blade", "Mother's Blade", "hands", L, "Shots return like boomerangs, +40% damage", { "boomerang": 1, "dmg": 0.40 }, [], { "tags": ["gunslinger"], "stack": "once", "pools": TR, "weight": 0.3 })
    _add("static_jar", "Static Jar", "trinket", R, "15% of hits on Wet foes arc lightning", {}, [{ "on": "hit", "if": "target_wet", "chance": 0.15, "do": "chain", "potency": 4 }], { "tags": ["shock", "wet"] })
    _add("kindling_mitts", "Kindling Mitts", "hands", R, "18% of hits on Oiled foes ignite them", {}, [{ "on": "hit", "if": "target_oiled", "chance": 0.18, "do": "apply", "element": "fire", "potency": 5 }], { "tags": ["fire", "oil"] })
    _add("tar_coat", "Tar Coat", "chest", U, "When hurt, oil everything nearby", {}, [{ "on": "hurt", "do": "nova", "element": "oil", "radius": 140, "radius_per": 40, "potency": 3 }], { "tags": ["oil", "guard"] })
    _add("frost_treads", "Frost Treads", "feet", R, "Whatever hurts you freezes solid", {}, [{ "on": "hurt", "do": "apply", "element": "wet", "potency": 6 }, { "on": "hurt", "do": "apply", "element": "ice", "potency": 6 }], { "tags": ["ice", "guard"], "stack": "once" })
    _add("glacier_plate", "Glacier Plate", "chest", E, "+4 armour; when hurt, a frost nova", { "armor": 4 }, [{ "on": "hurt", "do": "nova", "element": "ice", "radius": 130, "radius_per": 30, "potency": 6 }], { "tags": ["ice", "guard"] })
    _add("spiked_cuirass", "Spiked Cuirass", "chest", R, "Attackers take 10 damage and may slow", { "thorns": 10 }, [{ "on": "hurt", "chance": 0.20, "do": "slow", "radius": 180 }], { "tags": ["guard"] })
    _add("conductors_mail", "Conductor's Mail", "chest", R, "Chain Lightning: +40% power, +2 jumps", { "potency:Chain Lightning": 0.4, "chain_jumps": 2 }, [], { "tags": ["shock"] })
    _add("hands_of_storm", "Storm Hands", "hands", L, "15% of hits arc lightning", { "chain_jumps": 2 }, [{ "on": "hit", "chance": 0.15, "do": "chain", "potency": 6 }], { "tags": ["shock"], "stack": "once" })
    _add("echo_loop", "Echo Loop", "ring", R, "Reactions may fling 2 elemental shards", {}, [{ "on": "reaction", "chance": 0.15, "do": "shoot", "element": "last", "count": 2, "count_per": 1, "potency": 4 }], { "tags": ["alchemy"] })
    _add("ring_of_multiplicity", "Ring of Multiplicity", "ring", E, "25% of hits fire an extra shot", {}, [{ "on": "hit", "chance": 0.25, "do": "shoot", "element": "last", "count": 1, "potency": 5 }], { "tags": ["gunslinger"] })
    _add("plague_censer", "Plague Censer", "trinket", E, "Reactions may spread poison around", {}, [{ "on": "reaction", "chance": 0.30, "do": "spread", "element": "poison", "radius": 150, "potency": 4 }], { "tags": ["poison", "alchemy"] })
    _add("heart_of_forge", "Forge Heart", "trinket", L, "Burning foes explode when they die", { "vs_burning": 0.15 }, [{ "on": "kill", "if": "target_burning", "do": "nova", "element": "fire", "radius": 140, "potency": 9 }], { "tags": ["fire"], "stack": "once" })
    _add("permafrost_core", "Permafrost Core", "trinket", L, "Frozen foes burst into ice shards on death", {}, [{ "on": "reaction:Deep Freeze", "do": "shoot", "element": "ice", "count": 5, "potency": 6 }, { "on": "kill", "if": "target_frozen", "do": "nova", "element": "ice", "radius": 120, "potency": 6 }], { "tags": ["ice"], "stack": "once" })
    _add("steam_whistle", "Steam Whistle", "trinket", R, "Steam soaks everything nearby", {}, [{ "on": "reaction:Steam", "do": "nova", "element": "wet", "radius": 140, "radius_per": 40, "potency": 3 }], { "tags": ["wet", "alchemy"] })
    _add("signet_of_overload", "Signet of Overload", "ring", L, "Venting detonates a huge nova", {}, [{ "on": "vent", "do": "nova", "element": "last", "radius": 300, "potency": 24 }], { "tags": ["vent"], "stack": "once" })
    _add("skullcap_vented", "Vented Skullcap", "head", L, "Venting fires 8 shots of its element", { "vent_radius": 0.15 }, [{ "on": "vent", "do": "shoot", "element": "last", "count": 8, "count_per": 4, "potency": 8 }], { "tags": ["vent"] })
    _add("vent_striders", "Vent Striders", "feet", E, "Venting shields you; +30% vent radius", { "vent_radius": 0.30 }, [{ "on": "vent", "do": "shield", "amount": 1.5 }], { "tags": ["vent", "guard"] })
    _add("gilded_carapace", "Gilded Carapace", "chest", L, "Elites pay 25 scrap, +25% luck", { "luck": 0.25 }, [{ "on": "elite_kill", "do": "scrap", "amount": 25 }], { "tags": ["fortune"], "stack": "once", "weight": 0.5 })

    # ======================= NEW BEHAVIOUR ITEMS (3.2): each changes how a gun, an element,
    # a reaction or the dash works, and shows on screen.
    # ======================= ARSENAL EXPANSION BATCH 1 (5.1, 5.2): Blade items. All start
    # locked and open through the melee unlocks in progress.gd ("item:<id>"). "melee": true
    # on a trigger means only hits and kills by a melee weapon fire it.
    var B := { "tags": ["blade"], "locked": true }
    var BO := { "tags": ["blade"], "locked": true, "stack": "once" }
    # Blade passives (12, behaviour).
    _add("long_reach", "Long Reach", "hands", C, "Melee reach +20%", { "reach": 0.20 }, [], B)
    _add("follow_through", "Follow-Through", "hands", R, "Finishers swing twice", { "finisher_twice": 1 }, [], BO)
    _add("riposte", "Riposte", "feet", R, "A dash makes your swings crit for 1 s", {}, [{ "on": "dash", "do": "buff", "key": "melee_crit", "amount": 1.0, "secs": 1.0, "secs_per": 0.5 }], { "tags": ["blade", "swift"], "locked": true })
    _add("bloodletter", "Bloodletter", "trinket", U, "Cleave hits open a bleed", { "cleave_bleed": 1 }, [], { "tags": ["blade", "blood"], "locked": true })
    _add("whirl", "Whirl", "ring", R, "Every 5th swing is a full spin", { "whirl": 1 }, [], BO)
    _add("shock_edge", "Shock Edge", "ring", U, "Every 6th melee hit bursts in a small shock ring", {}, [{ "on": "hit", "melee": true, "every": 6, "every_per": -1, "do": "nova", "element": "shock", "radius": 70, "potency": 5 }], { "tags": ["blade", "shock"], "locked": true })
    _add("frostbite_steel", "Frostbite Steel", "hands", U, "Melee hits on Wet foes chill them", {}, [{ "on": "hit", "melee": true, "if": "target_wet", "do": "apply", "element": "ice", "potency": 4 }], { "tags": ["blade", "ice"], "locked": true })
    _add("thunder_grip", "Thunder Grip", "hands", R, "15% of melee hits arc lightning", {}, [{ "on": "hit", "melee": true, "chance": 0.15, "do": "chain", "potency": 5 }], { "tags": ["blade", "shock"], "locked": true })
    _add("cutting_wind", "Cutting Wind", "chest", U, "Melee shoves 40% harder", { "melee_knock": 0.40 }, [], { "tags": ["blade", "gale"], "locked": true })
    _add("marked_steel", "Marked Steel", "ring", U, "Every 3rd melee hit marks the foe", {}, [{ "on": "hit", "melee": true, "every": 3, "every_per": -1, "do": "mark", "secs": 3.0 }], { "tags": ["blade", "alchemy"], "locked": true })
    _add("wildfire_edge", "Wildfire Edge", "trinket", R, "Melee hits on burning foes spread fire", {}, [{ "on": "hit", "melee": true, "if": "target_burning", "chance": 0.25, "do": "spread", "element": "fire", "radius": 70, "potency": 4 }], { "tags": ["blade", "fire"], "locked": true })
    _add("edge_runner", "Edge Runner", "feet", U, "While moving, swings 20% faster", {}, [], { "tags": ["blade", "swift"], "locked": true, "cond_mods": { "moving": { "swing_speed": 0.20 } } })
    # Melee mods (6): they fit any weapon; on a gun they do the gun part only.
    _add("edge_whetstone", "Edge Whetstone", "mod", C, "This weapon: +15% damage; melee +10% reach", { "g_dmg": 0.15, "g_reach": 0.10 }, [], B)
    _add("weighted_pommel", "Weighted Pommel", "mod", U, "This weapon: +25% damage, -10% speed", { "g_dmg": 0.25, "g_fire_rate": -0.10 }, [], B)
    _add("long_haft", "Long Haft", "mod", U, "This weapon: melee +25% reach, guns +15% range", { "g_reach": 0.25, "g_range": 0.15 }, [], B)
    _add("balanced_grip", "Balanced Grip", "mod", C, "This weapon: +15% swing or fire rate", { "g_fire_rate": 0.15 }, [], B)
    _add("twin_edge", "Twin Edge", "mod", R, "This weapon: +1 swing or shot, -15% damage", { "g_count": 1, "g_dmg": -0.15 }, [], B)
    _add("tempered_steel", "Tempered Steel", "mod", R, "This weapon: +10% damage, +1 pierce", { "g_dmg": 0.10, "g_pierce": 1 }, [], B)
    # Melee actives (2).
    _add("bulwark", "Bulwark", "active", U, "Use: block enemy shots for 2 s", {}, [],
        { "tags": ["blade", "guard"], "locked": true, "active": { "charges": 2, "do": [{ "do": "ward", "secs": 2.0 }] } })
    _add("whirlwind", "Whirlwind", "active", R, "Use: a spinning slash hits all within 140 px", {}, [],
        { "tags": ["blade"], "locked": true, "active": { "charges": 2, "do": [{ "do": "nova", "element": "gun", "radius": 140, "potency": 10 }] } })
    # Plain, element, healing and trade-off (10).
    _add("honed_edge", "Honed Edge", "hands", C, "+12% melee damage", { "melee_dmg": 0.12 }, [], B)
    _add("swift_strikes", "Swift Strikes", "hands", C, "+12% swing speed", { "swing_speed": 0.12 }, [], B)
    _add("sword_belt", "Sword Belt", "chest", U, "+8% melee damage, +8% reach", { "melee_dmg": 0.08, "reach": 0.08 }, [], B)
    _add("iron_wrists", "Iron Wrists", "hands", U, "+10% melee damage, +8% swing speed", { "melee_dmg": 0.10, "swing_speed": 0.08 }, [], B)
    _add("berserker_oath", "Berserker Oath", "head", R, "Melee +30% damage, guns -20% damage", { "melee_dmg": 0.30, "gun_dmg": -0.20 }, [], BO)
    _add("glass_blade", "Glass Blade", "trinket", U, "Melee +25% damage, -20 max health", { "melee_dmg": 0.25, "max_hp": -20 }, [], B)
    _add("rime_whetstone", "Rime Whetstone", "trinket", U, "Frozen foes take +25% from melee", { "melee_vs_frozen": 0.25 }, [], { "tags": ["blade", "ice"], "locked": true, "element": "ice" })
    _add("ember_whetstone", "Ember Whetstone", "trinket", U, "Burning foes take +25% from melee", { "melee_vs_burning": 0.25 }, [], { "tags": ["blade", "fire"], "locked": true, "element": "fire" })
    _add("soaked_edge", "Soaked Edge", "ring", C, "20% of melee hits soak the foe", {}, [{ "on": "hit", "melee": true, "chance": 0.20, "do": "apply", "element": "wet", "potency": 4 }], { "tags": ["blade", "wet"], "locked": true, "element": "wet" })
    _add("mending_steel", "Mending Steel", "chest", R, "Melee kills mend 1 health", {}, [{ "on": "kill", "melee": true, "do": "heal", "amount": 1 }], BO)

    # ======================= ARSENAL EXPANSION BATCH 2 (5.1, 5.2): Thrown items. All start
    # locked and open through the thrown unlocks in progress.gd. "family": "thrown" on a
    # trigger means only hits and kills by a thrown weapon fire it; "catch" is a returning
    # weapon reaching you.
    var TW := { "tags": ["thrown"], "locked": true }
    var TWO := { "tags": ["thrown"], "locked": true, "stack": "once" }
    # Thrown passives (12, behaviour).
    _add("return_grip", "Return Grip", "hands", R, "Returning weapons hit twice as hard", { "return_mult": 1.0 }, [], TWO)
    _add("fletching", "Fletching", "trinket", U, "+1 bounce on discs, +1 lap on stars", { "disc_bounce": 1 }, [], TW)
    _add("double_fuse", "Double Fuse", "trinket", R, "Grenades burst twice", { "grenade_twice": 1 }, [], TWO)
    _add("sticky_fingers", "Sticky Fingers", "hands", U, "Stuck knives poison foes that touch them", { "stuck_poison": 1 }, [], { "tags": ["thrown", "poison"], "locked": true, "stack": "once" })
    _add("overarm", "Overarm", "chest", C, "Lobs fly 30% faster", { "lob_speed": 0.30 }, [], TW)
    _add("quick_draw", "Quick Draw", "hands", C, "+15% throw rate", { "throw_rate": 0.15 }, [], TW)
    _add("deep_pockets", "Deep Pockets", "chest", U, "+3 stuck knives; they stay 50% longer", { "knife_cap": 3, "stuck_time": 0.5 }, [], TW)
    _add("heavy_hand", "Heavy Hand", "hands", U, "Pins and bolas hold 50% longer", { "pin_time": 0.5 }, [], TW)
    _add("rim_shot", "Rim Shot", "ring", U, "Discs grow 10% with every bounce", { "disc_grow": 0.10 }, [], TW)
    _add("catch_spark", "Catch Spark", "ring", R, "Catching a returning weapon: +8% damage for 2 s", {}, [{ "on": "catch", "do": "buff", "key": "dmg", "amount": 0.08, "secs": 2.0 }], TWO)
    _add("shrapnel_pouch", "Shrapnel Pouch", "trinket", U, "Grenades burst into 4 more shards", { "grenade_shards": 4 }, [], TW)
    _add("pin_cushion", "Pin Cushion", "trinket", R, "Stunned and pinned foes take +25% from thrown", { "vs_stunned": 0.25 }, [], TWO)
    # Thrown mods (6): they fit any weapon.
    _add("weighted_tip", "Weighted Tip", "mod", C, "This weapon: +20% damage, -10% speed", { "g_dmg": 0.20, "g_speed": -0.10 }, [], TW)
    _add("spin_grip", "Spin Grip", "mod", U, "This weapon: +1 bounce", { "g_bounce": 1 }, [], TW)
    _add("barbed_edge", "Barbed Edge", "mod", U, "This weapon: hits also bleed, -10% damage", { "extra_element": "blood", "g_dmg": -0.10 }, [], TW)
    _add("throwing_strap", "Throwing Strap", "mod", C, "This weapon: +25% range", { "g_range": 0.25 }, [], TW)
    _add("twin_throw", "Twin Throw", "mod", R, "This weapon: +1 throw or shot, -20% damage", { "g_count": 1, "g_dmg": -0.20 }, [], TW)
    _add("fletched_shaft", "Fletched Shaft", "mod", U, "This weapon: +25% speed, +1 pierce", { "g_speed": 0.25, "g_pierce": 1 }, [], TW)
    # Thrown actives (2).
    _add("recall", "Recall", "active", U, "Use: every knife flies back, hitting twice as hard", {}, [],
        { "tags": ["thrown"], "locked": true, "active": { "charges": 3, "do": [{ "do": "recall", "mult": 2.0 }] } })
    _add("knife_storm", "Knife Storm", "active", R, "Use: throw 8 blades at the nearest foe", {}, [],
        { "tags": ["thrown"], "locked": true, "active": { "charges": 2, "do": [{ "do": "shoot", "element": "gun", "count": 8, "potency": 8 }] } })
    # Element items: a state item and a reaction item each for Fire, Ice, Wet, Shock and Oil.
    _add("kindling_pouch", "Kindling Pouch", "trinket", U, "Thrown hits on oiled foes set them alight", {}, [{ "on": "hit", "family": "thrown", "if": "target_oiled", "chance": 0.5, "do": "apply", "element": "fire", "potency": 5 }], { "tags": ["thrown", "fire"], "locked": true, "element": "fire" })
    _add("frost_quiver", "Frost Quiver", "chest", U, "Frozen foes take +25% from thrown", { "thrown_vs_frozen": 0.25 }, [], { "tags": ["thrown", "ice"], "locked": true, "element": "ice" })
    _add("damp_satchel", "Damp Satchel", "chest", C, "20% of thrown hits soak the foe", {}, [{ "on": "hit", "family": "thrown", "chance": 0.20, "do": "apply", "element": "wet", "potency": 4 }], { "tags": ["thrown", "wet"], "locked": true, "element": "wet" })
    _add("copper_wire", "Copper Wire", "ring", U, "Thrown hits on wet foes may arc lightning", {}, [{ "on": "hit", "family": "thrown", "if": "target_wet", "chance": 0.25, "do": "chain", "potency": 5 }], { "tags": ["thrown", "shock"], "locked": true, "element": "shock" })
    _add("pitch_pot", "Pitch Pot", "trinket", C, "25% of thrown hits oil the foe", {}, [{ "on": "hit", "family": "thrown", "chance": 0.25, "do": "apply", "element": "oil", "potency": 4 }], { "tags": ["thrown", "oil"], "locked": true, "element": "oil" })
    _add("firebrand_sash", "Firebrand Sash", "chest", R, "Inferno throws 3 embers at foes nearby", {}, [{ "on": "reaction:Inferno", "do": "shoot", "element": "fire", "count": 3, "potency": 5 }], { "tags": ["thrown", "fire"], "locked": true, "element": "fire" })
    _add("rime_bandolier", "Rime Bandolier", "chest", U, "Thermal Shock chills foes nearby", {}, [{ "on": "reaction:Thermal Shock", "do": "spread", "element": "ice", "radius": 100, "potency": 4 }], { "tags": ["thrown", "ice"], "locked": true, "element": "ice" })
    _add("cold_current", "Cold Current", "feet", U, "Deep Freeze slows foes nearby", {}, [{ "on": "reaction:Deep Freeze", "do": "slow", "radius": 140 }], { "tags": ["thrown", "wet"], "locked": true, "element": "wet" })
    _add("storm_bangle", "Storm Bangle", "ring", R, "Plasma arcs to 2 more foes", {}, [{ "on": "reaction:Plasma", "do": "chain", "count": 2, "radius": 220, "potency": 5 }], { "tags": ["thrown", "shock"], "locked": true, "element": "shock" })
    _add("slick_spool", "Slick Spool", "trinket", U, "Black Ice oils foes nearby", {}, [{ "on": "reaction:Black Ice", "do": "spread", "element": "oil", "radius": 110, "potency": 4 }], { "tags": ["thrown", "oil"], "locked": true, "element": "oil" })
    # Behaviour, plain and trade-off (5).
    _add("magnet_glove", "Magnet Glove", "hands", U, "Returning weapons drag foes toward you", { "return_pull": 1 }, [], TWO)
    _add("second_throw", "Second Throw", "ring", R, "Every 5th thrown kill throws 2 blades onward", {}, [{ "on": "kill", "family": "thrown", "every": 5, "every_per": -1, "do": "shoot", "element": "gun", "count": 2, "potency": 8 }], TW)
    _add("fuse_cutter", "Fuse Cutter", "trinket", C, "Grenade fuses burn 40% faster", { "fuse_cut": 0.40 }, [], TWO)
    _add("hunters_oath", "Hunter's Oath", "head", R, "Thrown +30% damage, guns -20% damage", { "thrown_dmg": 0.30, "gun_dmg": -0.20 }, [], TWO)
    _add("throwing_gloves", "Throwing Gloves", "hands", C, "+12% thrown damage", { "thrown_dmg": 0.12 }, [], TW)

    # ======================= ARSENAL EXPANSION BATCH 3 (5.1, 5.2): Swarm items. All start
    # locked and open through the summon unlocks in progress.gd and the Summoner Trial.
    # "family": "summon" on a trigger: only hits and kills by a summon weapon (its bodies
    # and turrets) fire it. Summon stats: summon_dmg, summon_rate, summon_cap, summon_reach,
    # summon_speed, summon_size, drone_rate, swarm_respawn, turret_life, shared_mind, tether.
    var SW := { "tags": ["swarm"], "locked": true }
    var SWO := { "tags": ["swarm"], "locked": true, "stack": "once" }
    # Swarm passives (12, behaviour).
    _add("pack_leader", "Pack Leader", "head", R, "+1 to every summon cap", { "summon_cap": 1 }, [], SW)
    _add("shared_mind", "Shared Mind", "head", R, "Summons attack your first weapon's target", { "shared_mind": 1 }, [], SWO)
    _add("brood", "Brood", "trinket", R, "Summon kills hatch a wasp for 4 s", {}, [{ "on": "kill", "family": "summon", "do": "brood", "count": 1, "secs": 4.0 }], SWO)
    _add("overclock", "Overclock", "trinket", U, "Drones attack 25% faster", { "drone_rate": 0.25 }, [], SW)
    _add("tether", "Tether", "ring", R, "Summons apply your first weapon's element", { "tether": 1 }, [], SWO)
    _add("long_leash", "Long Leash", "hands", C, "Summons look 25% further for foes", { "summon_reach": 0.25 }, [], SW)
    _add("swift_wings", "Swift Wings", "feet", C, "Summons move 30% faster", { "summon_speed": 0.30 }, [], SW)
    _add("big_brood", "Big Brood", "chest", U, "Summons 25% bigger; orbits circle wider", { "summon_size": 0.25 }, [], SW)
    _add("feeding_frenzy", "Feeding Frenzy", "trinket", U, "Summon kills: summons +15% damage for 3 s", {}, [{ "on": "kill", "family": "summon", "do": "buff", "key": "summon_dmg", "amount": 0.15, "secs": 3.0 }], SWO)
    _add("quick_hatch", "Quick Hatch", "chest", U, "Swarm fliers return 40% sooner", { "swarm_respawn": 0.40 }, [], SW)
    _add("spark_collars", "Spark Collars", "ring", U, "15% of summon hits arc lightning", {}, [{ "on": "hit", "family": "summon", "chance": 0.15, "do": "chain", "potency": 4 }], { "tags": ["swarm", "shock"], "locked": true })
    _add("turret_oil", "Turret Oil", "trinket", C, "Turrets last 50% longer", { "turret_life": 0.50 }, [], SW)
    # Summon mods (6): they fit any weapon (a summon weapon's +1 shot is +1 body).
    _add("spare_rotor", "Spare Rotor", "mod", C, "This weapon: +20% fire rate, -10% damage", { "g_fire_rate": 0.20, "g_dmg": -0.10 }, [], SW)
    _add("brood_chamber", "Brood Chamber", "mod", R, "This weapon: +1 body or shot, -15% damage", { "g_count": 1, "g_dmg": -0.15 }, [], SW)
    _add("homing_chip", "Homing Chip", "mod", U, "This weapon: +30% speed, +10% range", { "g_speed": 0.30, "g_range": 0.10 }, [], SW)
    _add("venom_gland", "Venom Gland", "mod", U, "This weapon: hits also poison, -10% damage", { "extra_element": "poison", "g_dmg": -0.10 }, [], SW)
    _add("iron_shell", "Iron Shell", "mod", U, "This weapon: +25% damage, -15% fire rate", { "g_dmg": 0.25, "g_fire_rate": -0.15 }, [], SW)
    _add("swarm_beacon", "Swarm Beacon", "mod", R, "This weapon: +1 pierce, +15% range", { "g_pierce": 1, "g_range": 0.15 }, [], SW)
    # Summon actives (2).
    _add("rally", "Rally", "active", U, "Use: every summon dashes to the nearest foe and strikes", {}, [],
        { "tags": ["swarm"], "locked": true, "active": { "charges": 3, "do": [{ "do": "rally", "mult": 1.5 }] } })
    _add("call_the_swarm", "Call the Swarm", "active", R, "Use: six wasps fight beside you for 8 s", {}, [],
        { "tags": ["swarm"], "locked": true, "active": { "charges": 2, "do": [{ "do": "swarm_call", "count": 6, "secs": 8.0 }] } })
    # Element items: a state item and a reaction item each for Poison, Acid, Blood and Void.
    _add("venom_sac", "Venom Sac", "trinket", C, "20% of summon hits poison the foe", {}, [{ "on": "hit", "family": "summon", "chance": 0.20, "do": "apply", "element": "poison", "potency": 4 }], { "tags": ["swarm", "poison"], "locked": true, "element": "poison" })
    _add("tar_pit_censer", "Tar Pit Censer", "trinket", U, "Tar Pit poisons foes nearby", {}, [{ "on": "reaction:Tar Pit", "do": "spread", "element": "poison", "radius": 120, "potency": 4 }], { "tags": ["swarm", "poison"], "locked": true, "element": "poison" })
    _add("acid_spit", "Acid Spit", "ring", C, "20% of summon hits corrode the foe", {}, [{ "on": "hit", "family": "summon", "chance": 0.20, "do": "apply", "element": "acid", "potency": 4 }], { "tags": ["swarm", "acid"], "locked": true, "element": "acid" })
    _add("electrolyte", "Electrolyte", "ring", R, "Electrolysis arcs to 2 more foes", {}, [{ "on": "reaction:Electrolysis", "do": "chain", "count": 2, "radius": 220, "potency": 5 }], { "tags": ["swarm", "acid"], "locked": true, "element": "acid" })
    _add("blood_tick", "Blood Tick", "trinket", C, "20% of summon hits bleed the foe", {}, [{ "on": "hit", "family": "summon", "chance": 0.20, "do": "apply", "element": "blood", "potency": 4 }], { "tags": ["swarm", "blood"], "locked": true, "element": "blood" })
    _add("thin_blood_charm", "Thin Blood Charm", "chest", U, "Thin Blood bleeds foes nearby", {}, [{ "on": "reaction:Thin Blood", "do": "spread", "element": "blood", "radius": 110, "potency": 4 }], { "tags": ["swarm", "blood"], "locked": true, "element": "blood" })
    _add("void_collar", "Void Collar", "hands", U, "20% of summon hits mark the foe", {}, [{ "on": "hit", "family": "summon", "chance": 0.20, "do": "mark", "secs": 3.0 }], { "tags": ["swarm", "void"], "locked": true, "element": "void" })
    _add("whirlpool_bell", "Whirlpool Bell", "trinket", U, "Whirlpool slows foes nearby", {}, [{ "on": "reaction:Whirlpool", "do": "slow", "radius": 150 }], { "tags": ["swarm", "void"], "locked": true, "element": "void" })
    # Stat and trade-off (2).
    _add("kennel_keys", "Kennel Keys", "trinket", C, "+12% summon damage", { "summon_dmg": 0.12 }, [], SW)
    _add("hive_oath", "Hive Oath", "head", R, "Summons +30% damage, guns -20% damage", { "summon_dmg": 0.30, "gun_dmg": -0.20 }, [], SWO)

    # ======================= ARSENAL EXPANSION BATCH 4 (5.1, 5.2): Ground items. All start
    # locked and open through the ground unlocks in progress.gd and the Ground Trial.
    # "family": "ground" on a trigger: only hits and kills by a ground weapon (its zones,
    # traps and mines). Ground stats: ground_dmg, zone_radius, zone_life, zone_rate,
    # zone_slow, trap_cap, trap_radius, trap_echo, hold_time, lay_rate, ring_radius,
    # ring_move, totem_life, trail_life (GroundZone).
    var GR := { "tags": ["ground"], "locked": true }
    var GRO := { "tags": ["ground"], "locked": true, "stack": "once" }
    # Ground passives (12, behaviour).
    _add("deep_roots", "Deep Roots", "feet", U, "Totems last 50% longer", { "totem_life": 0.50 }, [], GR)
    _add("hair_trigger", "Hair Trigger", "trinket", R, "Traps also burst when you dash past", {}, [{ "on": "dash", "do": "hair_trigger", "radius": 90 }], GRO)
    _add("widen", "Widen", "ring", C, "Rings +20% radius", { "ring_radius": 0.20 }, [], GR)
    _add("echo_step", "Echo Step", "feet", U, "Trails last twice as long", { "trail_life": 1.0 }, [], GRO)
    _add("salted_earth", "Salted Earth", "hands", U, "Your zones slow foes 15%", { "zone_slow": 0.15 }, [], GRO)
    _add("tripwire", "Tripwire", "trinket", C, "Snares hold foes 50% longer", { "hold_time": 0.50 }, [], GR)
    _add("overgrowth", "Overgrowth", "chest", R, "+1 to every trap and totem cap", { "trap_cap": 1 }, [], GR)
    _add("ley_lines", "Ley Lines", "head", R, "Your zones tick 20% faster", { "zone_rate": 0.20 }, [], GR)
    _add("aftershock", "Aftershock", "trinket", R, "Traps burst again 0.5 s later at half damage", { "trap_echo": 1 }, [], GRO)
    _add("footwork", "Footwork", "feet", U, "While you move, rings hit 25% harder", { "ring_move": 0.25 }, [], GR)
    _add("soil_sense", "Soil Sense", "head", U, "Fields, traps and totems are laid 30% faster", { "lay_rate": 0.30 }, [], GR)
    _add("bloom", "Bloom", "chest", U, "Snares, pods and glyphs 30% wider", { "trap_radius": 0.30 }, [], GR)
    # Ground mods (6): they fit any weapon (a ground weapon's +1 shot is +1 trap, or a wider ring).
    _add("stake_kit", "Stake Kit", "mod", R, "This weapon: +1 trap or wider ring, -15% damage", { "g_count": 1, "g_dmg": -0.15 }, [], GR)
    _add("lodestone", "Lodestone", "mod", U, "This weapon: +25% range, +1 pierce", { "g_range": 0.25, "g_pierce": 1 }, [], GR)
    _add("slow_fuse", "Slow Fuse", "mod", U, "This weapon: +25% damage, -15% fire rate", { "g_dmg": 0.25, "g_fire_rate": -0.15 }, [], GR)
    _add("quick_set", "Quick Set", "mod", C, "This weapon: +20% fire rate, -10% damage", { "g_fire_rate": 0.20, "g_dmg": -0.10 }, [], GR)
    _add("brimstone", "Brimstone", "mod", U, "This weapon: hits also burn, -10% damage", { "extra_element": "fire", "g_dmg": -0.10 }, [], GR)
    _add("cool_stones", "Cool Stones", "mod", C, "This weapon: -40% pressure, -10% damage", { "g_pressure": -0.40, "g_dmg": -0.10 }, [], GR)
    # Ground actives (2).
    _add("seed", "Seed", "active", U, "Use: plant every trap and totem at once", {}, [],
        { "tags": ["ground"], "locked": true, "active": { "charges": 3, "do": [{ "do": "seed" }] } })
    _add("spring_all", "Spring All", "active", R, "Use: every trap and mine of yours bursts", {}, [],
        { "tags": ["ground"], "locked": true, "active": { "charges": 3, "do": [{ "do": "spring_all" }] } })
    # Element items: a state item and a reaction item each for Holy, Gale and Stone.
    _add("censer_ash", "Censer Ash", "trinket", C, "20% of ground hits bless the foe", {}, [{ "on": "hit", "family": "ground", "chance": 0.20, "do": "apply", "element": "holy", "potency": 4 }], { "tags": ["ground", "holy"], "locked": true, "element": "holy" })
    _add("sanctum_stone", "Sanctum Stone", "ring", R, "Smite strikes 2 more foes nearby", {}, [{ "on": "reaction:Smite", "do": "chain", "count": 2, "radius": 200, "potency": 5 }], { "tags": ["ground", "holy"], "locked": true, "element": "holy" })
    _add("wind_sock", "Wind Sock", "hands", C, "20% of ground hits catch the wind", {}, [{ "on": "hit", "family": "ground", "chance": 0.20, "do": "apply", "element": "gale", "potency": 4 }], { "tags": ["ground", "gale"], "locked": true, "element": "gale" })
    _add("gale_lantern", "Gale Lantern", "trinket", U, "Firestorm leaves a fire cloud", {}, [{ "on": "reaction:Firestorm", "do": "cloud", "element": "fire", "radius": 90, "secs": 3.0 }], { "tags": ["ground", "gale"], "locked": true, "element": "gale" })
    _add("grit_pouch", "Grit Pouch", "trinket", C, "20% of ground hits grind stone in", {}, [{ "on": "hit", "family": "ground", "chance": 0.20, "do": "apply", "element": "stone", "potency": 4 }], { "tags": ["ground", "stone"], "locked": true, "element": "stone" })
    _add("quarry_bell", "Quarry Bell", "trinket", U, "Mud slows foes nearby", {}, [{ "on": "reaction:Mud", "do": "slow", "radius": 150 }], { "tags": ["ground", "stone"], "locked": true, "element": "stone" })
    # Healing (2), inside the Mending budget.
    _add("mending_moss", "Mending Moss", "chest", R, "Ground kills mend 1 health", {}, [{ "on": "kill", "family": "ground", "do": "heal", "amount": 1 }], GRO)
    _add("root_sap", "Root Sap", "trinket", U, "+10% Mending reserve, zones last 10% longer", { "mend": 0.10, "zone_life": 0.10 }, [], GR)
    # Stat and trade-off (2).
    _add("groundskeeper_gloves", "Groundskeeper's Gloves", "hands", C, "+12% ground damage", { "ground_dmg": 0.12 }, [], GR)
    _add("earth_oath", "Earth Oath", "head", R, "Ground +30% damage, guns -20% damage", { "ground_dmg": 0.30, "gun_dmg": -0.20 }, [], GRO)

    # ======================= ARSENAL EXPANSION BATCH 5 (5.1): cross-family behaviour items,
    # trade-offs and actives, 30 in all. All start locked and open through the batch 5
    # milestones in progress.gd (three items each). Only existing trigger verbs.
    # Cross-family relays (5): kills by one family speed up the next one.
    _add("cross_training", "Cross Training", "hands", U, "Melee kills: guns +25% damage for 3 s", {}, [{ "on": "kill", "melee": true, "do": "buff", "key": "gun_dmg", "amount": 0.25, "secs": 3.0 }], { "tags": ["blade", "gunslinger"], "locked": true })
    _add("slingers_rhythm", "Slinger's Rhythm", "hands", U, "Thrown kills: melee +25% damage for 3 s", {}, [{ "on": "kill", "family": "thrown", "do": "buff", "key": "melee_dmg", "amount": 0.25, "secs": 3.0 }], { "tags": ["thrown", "blade"], "locked": true })
    _add("handlers_whistle", "Handler's Whistle", "trinket", U, "Gun kills: summons +25% damage for 3 s", {}, [{ "on": "kill", "family": "gun", "do": "buff", "key": "summon_dmg", "amount": 0.25, "secs": 3.0 }], { "tags": ["gunslinger", "swarm"], "locked": true })
    _add("groundwork", "Groundwork", "feet", U, "Summon kills: ground +25% damage for 3 s", {}, [{ "on": "kill", "family": "summon", "do": "buff", "key": "ground_dmg", "amount": 0.25, "secs": 3.0 }], { "tags": ["swarm", "ground"], "locked": true })
    _add("warden_drum", "Warden Drum", "trinket", U, "Ground kills: thrown +25% damage for 3 s", {}, [{ "on": "kill", "family": "ground", "do": "buff", "key": "thrown_dmg", "amount": 0.25, "secs": 3.0 }], { "tags": ["ground", "thrown"], "locked": true })
    # Cross-family behaviour (11).
    _add("tenth_strike", "Tenth Strike", "ring", R, "Every 10th hit bursts in a ring of its element", {}, [{ "on": "hit", "every": 10, "every_per": -2, "do": "nova", "element": "last", "radius": 90, "potency": 6 }], { "tags": ["alchemy"], "locked": true })
    _add("blade_echo", "Blade Echo", "ring", R, "20% of melee hits arc to 2 foes", {}, [{ "on": "hit", "melee": true, "chance": 0.20, "do": "chain", "count": 2, "radius": 160, "potency": 5 }], { "tags": ["blade", "shock"], "locked": true })
    _add("shrapnel_belt", "Shrapnel Belt", "chest", U, "Thrown kills fling 3 shards", {}, [{ "on": "kill", "family": "thrown", "do": "shoot", "element": "gun", "count": 3, "count_per": 1, "potency": 4 }], { "tags": ["thrown"], "locked": true })
    _add("storm_step", "Storm Step", "feet", R, "Dashing arcs lightning to 3 foes", {}, [{ "on": "dash", "do": "chain", "count": 3, "radius": 200, "potency": 6 }], { "tags": ["swift", "shock"], "locked": true, "element": "shock" })
    _add("rime_step", "Rime Step", "feet", U, "Dashing chills foes within 120 px", {}, [{ "on": "dash", "do": "nova", "element": "ice", "radius": 120, "potency": 4 }], { "tags": ["swift", "ice"], "locked": true, "element": "ice" })
    _add("aegis_trophy", "Aegis Trophy", "trinket", R, "Elite kills shield you", {}, [{ "on": "elite_kill", "do": "shield", "amount": 1.5 }], { "tags": ["guard"], "locked": true, "stack": "once" })
    _add("cinder_heart", "Cinder Heart", "chest", R, "Below 40% health, hits burn", {}, [{ "on": "hit", "if": "low_hp", "do": "apply", "element": "fire", "potency": 4 }], { "tags": ["fire", "guard"], "locked": true, "element": "fire", "stack": "once" })
    _add("cold_blood", "Cold Blood", "ring", U, "30% of hits on frozen foes bleed", {}, [{ "on": "hit", "if": "target_frozen", "chance": 0.30, "do": "apply", "element": "blood", "potency": 4 }], { "tags": ["ice", "blood"], "locked": true, "element": "blood" })
    _add("flash_point", "Flash Point", "trinket", R, "15% of hits on oiled foes erupt", {}, [{ "on": "hit", "if": "target_oiled", "chance": 0.15, "do": "nova", "element": "fire", "radius": 70, "potency": 6 }], { "tags": ["oil", "fire"], "locked": true, "element": "fire" })
    _add("pack_howl", "Pack Howl", "chest", R, "Summon kills mend 1 health", {}, [{ "on": "kill", "family": "summon", "do": "heal", "amount": 1 }], { "tags": ["swarm"], "locked": true, "stack": "once" })
    _add("catchers_mitt", "Catcher's Mitt", "hands", U, "Catching a thrown weapon: +20% damage for 2 s", {}, [{ "on": "catch", "do": "buff", "key": "dmg", "amount": 0.20, "secs": 2.0 }], { "tags": ["thrown", "swift"], "locked": true })
    # Trade-offs (8).
    _add("glass_edge", "Glass Edge", "hands", R, "Melee +35% damage, -20 max health", { "melee_dmg": 0.35, "max_hp": -20 }, [], { "tags": ["blade"], "locked": true, "stack": "once" })
    _add("throwers_oath", "Thrower's Oath", "head", R, "Thrown +30% damage, guns -20% damage", { "thrown_dmg": 0.30, "gun_dmg": -0.20 }, [], { "tags": ["thrown"], "locked": true, "stack": "once" })
    _add("lone_wolf", "Lone Wolf", "head", R, "Guns +25% damage, summons -30% damage", { "gun_dmg": 0.25, "summon_dmg": -0.30 }, [], { "tags": ["gunslinger"], "locked": true, "stack": "once" })
    _add("heavy_hands", "Heavy Hands", "hands", U, "Melee +20% damage, -8% move speed", { "melee_dmg": 0.20, "speed": -0.08 }, [], { "tags": ["blade"], "locked": true })
    _add("sharp_mind", "Sharp Mind", "head", R, "+25% reaction power, -10% damage", { "potency": 0.25, "dmg": -0.10 }, [], { "tags": ["alchemy"], "locked": true })
    _add("ground_pact", "Ground Pact", "feet", R, "Ground +30% damage, melee -20% damage", { "ground_dmg": 0.30, "melee_dmg": -0.20 }, [], { "tags": ["ground"], "locked": true, "stack": "once" })
    _add("hollow_crown", "Hollow Crown", "head", E, "+20% damage, -25 max health", { "dmg": 0.20, "max_hp": -25 }, [], { "tags": ["gunslinger", "blade"], "locked": true, "stack": "once" })
    _add("iron_lung", "Iron Lung", "chest", U, "+2 armor, -10% move speed", { "armor": 2, "speed": -0.10 }, [], { "tags": ["guard"], "locked": true })
    # Actives (6).
    _add("thunder_bell", "Thunder Bell", "active", R, "Use: lightning arcs to 6 foes", {}, [],
        { "tags": ["shock"], "locked": true, "active": { "charges": 3, "do": [{ "do": "chain", "count": 6, "radius": 260, "potency": 12 }] } })
    _add("frost_horn", "Frost Horn", "active", R, "Use: a freezing ring 220 px wide", {}, [],
        { "tags": ["ice"], "locked": true, "active": { "charges": 3, "do": [{ "do": "nova", "element": "ice", "radius": 220, "potency": 12 }] } })
    _add("war_cry", "War Cry", "active", U, "Use: +40% damage for 5 s", {}, [],
        { "tags": ["blade"], "locked": true, "active": { "charges": 2, "do": [{ "do": "buff", "key": "dmg", "amount": 0.40, "secs": 5.0 }] } })
    _add("miasma_flask", "Miasma Flask", "active", U, "Use: a poison cloud around you", {}, [],
        { "tags": ["poison"], "locked": true, "active": { "charges": 3, "do": [{ "do": "cloud", "element": "poison", "radius": 120, "secs": 4.0 }] } })
    _add("iron_skin", "Iron Skin", "active", U, "Use: shield yourself", {}, [],
        { "tags": ["guard"], "locked": true, "active": { "charges": 2, "do": [{ "do": "shield", "amount": 2.0 }] } })
    _add("shard_bomb", "Shard Bomb", "active", C, "Use: 8 shards of your element burst out", {}, [],
        { "tags": ["gunslinger"], "locked": true, "active": { "charges": 3, "do": [{ "do": "shoot", "element": "gun", "count": 8, "potency": 6 }] } })

    _add("slipstream_boots", "Slipstream Boots", "feet", R, "Dashing leaves a 2 s trail of your vent element", {}, [{ "on": "dash", "do": "trail", "element": "vent", "secs": 2.0, "secs_per": 1.0 }], { "tags": ["swift", "vent"] })
    _add("shoulder_charge", "Shoulder Charge", "chest", R, "Dashing through enemies hits them for gun damage", { "dash_hit": 1.0 }, [], { "tags": ["swift", "guard"] })
    _add("second_wind", "Second Wind", "feet", R, "+1 dash charge", { "dash_charges": 1 }, [], { "tags": ["swift"] })
    _add("pressure_kick", "Pressure Kick", "feet", U, "Each dash adds 15 pressure", {}, [{ "on": "dash", "do": "pressure", "amount": 15, "amount_per": 10 }], { "tags": ["swift", "vent"] })
    _add("close_shave", "Close Shave", "chest", R, "Dodge a hit with a dash: +30% damage for 3 s", {}, [{ "on": "perfect_dodge", "do": "buff", "key": "dmg", "amount": 0.3, "secs": 3.0, "secs_per": 1.0 }], { "tags": ["swift", "gunslinger"] })
    _add("rear_guard", "Rear Guard", "chest", R, "Your guns also fire one shot backward", { "rear_shots": 1 }, [], { "tags": ["gunslinger", "guard"] })
    _add("mortar_kit", "Mortar Kit", "trinket", R, "Every 5th hit bursts into a cloud of its element", {}, [{ "on": "hit", "every": 5, "every_per": -1, "do": "cloud", "element": "last", "at": "target", "radius": 60, "secs": 3.0 }], { "tags": ["alchemy", "gunslinger"] })
    _add("gravity_shot", "Gravity Shot", "ring", R, "Shots pull enemies within 40 px", { "pull": 40 }, [], { "tags": ["seeker"], "pools": TR, "weight": 0.6 })
    _add("long_fuse", "Long Fuse", "ring", U, "Shots grow up to +80% size in flight", { "grow": 0.8 }, [], { "tags": ["gunslinger"] })
    _add("fork", "Fork", "hands", R, "Chains and beams reach 1 more enemy", { "chain_jumps": 1, "fork": 1 }, [], { "tags": ["shock", "seeker"] })
    _add("marking_rounds", "Marking Rounds", "ring", R, "Every 6th hit marks; reactions hit marked foes +40%", {}, [{ "on": "hit", "every": 6, "every_per": -1, "do": "mark", "secs": 4.0 }], { "tags": ["alchemy", "seeker"] })
    _add("rebound", "Rebound", "hands", R, "Shots that hit a wall come back once", { "rebound": 1 }, [], { "tags": ["gunslinger"], "stack": "once" })
    _add("death_shards", "Death Shards", "trinket", U, "Kills fire 2 shards of your element", {}, [{ "on": "kill", "do": "shoot", "element": "gun", "count": 2, "count_per": 1, "potency": 5 }], { "tags": ["gunslinger"] })
    _add("reaction_trail", "Reaction Trail", "trinket", R, "Reactions leave a 2 s patch of their element", {}, [{ "on": "reaction", "chance": 0.2, "do": "cloud", "element": "last", "at": "target", "radius": 50, "secs": 2.0, "secs_per": 1.0 }], { "tags": ["alchemy"] })
    _add("wide_arc", "Wide Arc", "ring", E, "Chain Lightning jumps through any element", { "wide_arc": 1 }, [], { "tags": ["shock"], "stack": "once", "element": "shock" })
    _add("split_reaction", "Split Reaction", "trinket", R, "Reactions fire a shot of each element in them", {}, [{ "on": "reaction", "chance": 0.3, "do": "split", "count": 1, "count_per": 1, "potency": 5 }], { "tags": ["alchemy"] })
    _add("overheat", "Overheat", "chest", R, "After a vent, shots carry its element for 3 s", {}, [{ "on": "vent", "do": "buff", "key": "vent_shots", "amount": 1.0, "secs": 3.0, "secs_per": 1.0 }], { "tags": ["vent", "fire"] })
    _add("ward_vent", "Ward Vent", "chest", R, "Venting raises a 3 s ring that stops enemy shots", {}, [{ "on": "vent", "do": "ward", "secs": 3.0, "secs_per": 1.0 }], { "tags": ["vent", "guard"] })
    _add("mirror_hide", "Mirror Hide", "chest", R, "The first hit each room bounces back as a nova", { "mirror": 1 }, [], { "tags": ["guard"] })
    _add("scavengers_eye", "Scavenger's Eye", "head", R, "Secret rooms hold 1 more item", { "secret_loot": 1 }, [], { "tags": ["fortune", "seeker"] })
    _add("second_nature", "Second Nature", "ring", E, "Your first gun also applies your vent element", { "second_nature": 1 }, [], { "tags": ["vent", "alchemy"], "stack": "once" })
    _add("transmuter", "Transmuter", "trinket", E, "Your Wet hits freeze instead of soaking", { "transmute": 1 }, [], { "tags": ["ice", "wet"], "stack": "once", "element": "ice" })
    _add("overcharge", "Overcharge", "ring", E, "Chain Lightning strikes each target twice", { "overcharge": 1 }, [], { "tags": ["shock"], "element": "shock" })
    _add("spreading_taint", "Spreading Taint", "trinket", E, "Elements you apply spread to 1 nearby foe", { "taint": 1 }, [], { "tags": ["alchemy", "poison"] })

    # ======================= GUN MODS (g_* keys only; triggers work as usual)
    _add("long_barrel", "Long Barrel", "mod", U, "This gun: +30% range, +20% shot speed", { "g_range": 0.3, "g_speed": 0.2 }, [], { "tags": ["seeker"] })
    _add("gun_oil", "Gun Oil", "mod", C, "This gun: +15% fire rate", { "g_fire_rate": 0.15 }, [], { "tags": ["gunslinger"] })
    _add("heavy_barrel", "Heavy Barrel", "mod", U, "This gun: +20% damage, -8% fire rate", { "g_dmg": 0.20, "g_fire_rate": -0.08 }, [], { "tags": ["gunslinger"] })
    _add("pressure_coupler", "Pressure Coupler", "mod", R, "This gun: +40% pressure, +15% damage", { "g_pressure": 0.4, "g_dmg": 0.15 }, [], { "tags": ["vent"] })
    _add("piercing_rounds", "Piercing Rounds", "mod", R, "This gun: shots pierce 2 more", { "g_pierce": 2 }, [], { "tags": ["gunslinger"] })
    _add("arc_emitter", "Arc Emitter", "mod", R, "This gun: 12% of hits arc lightning", {}, [{ "on": "hit", "chance": 0.12, "do": "chain", "potency": 4 }], { "tags": ["shock"] })
    _add("overclock", "Overclock", "mod", E, "This gun: +40% fire rate, +50% pressure", { "g_fire_rate": 0.4, "g_pressure": 0.5 }, [], { "tags": ["vent", "gunslinger"] })
    _add("split_chamber", "Split Chamber", "mod", E, "This gun: 1 more shot, -20% damage", { "g_count": 1, "g_dmg": -0.2 }, [], { "tags": ["gunslinger"], "weight": 0.6 })
    _add("chain_reactor", "Chain Reactor", "mod", L, "Reactions may burst into more reactions", { "g_dmg": 0.10 }, [{ "on": "reaction", "chance": 0.25, "do": "nova", "element": "last", "radius": 120, "potency": 8 }], { "tags": ["alchemy"], "weight": 0.4 })

    # ======================= ACTIVE ITEMS (press "active"; a room clear refills one charge)
    _add("flash_powder", "Flash Powder", "active", C, "Use: slow everything nearby", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "slow", "radius": 220 }] } })
    _add("pocket_storm", "Pocket Storm", "active", U, "Use: a shock nova around you", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "nova", "element": "shock", "radius": 160, "potency": 6 }] } })
    _add("water_bucket", "Bucket of Water", "active", U, "Use: soak everything nearby", {}, [],
        { "active": { "charges": 3, "do": [{ "do": "spread", "element": "wet", "radius": 220, "potency": 5 }] } })
    _add("ember_flask", "Ember Flask", "active", U, "Use: a fire burst on the nearest foe", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "nova", "at": "target", "element": "fire", "radius": 130, "potency": 8 }] } })
    _add("grease_gun", "Grease Gun", "active", R, "Use: oil everything nearby, then ignite it", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "spread", "element": "oil", "radius": 200, "potency": 5 }, { "do": "nova", "element": "fire", "radius": 200, "potency": 6 }] } })
    _add("frost_grenade", "Frost Grenade", "active", R, "Use: a freezing blast on the nearest foe", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "spread", "at": "target", "element": "wet", "radius": 150, "potency": 5 }, { "do": "nova", "at": "target", "element": "ice", "radius": 150, "potency": 10 }] } })
    _add("tesla_coil", "Tesla Coil", "active", E, "Use: lightning arcs from the 6 nearest foes", {}, [],
        { "active": { "charges": 2, "do": [{ "do": "chain", "count": 6, "radius": 500, "potency": 8 }] } })
    _add("overpressure", "Overpressure Valve", "active", E, "Use: +60 pressure and a 1 s shield", {}, [],
        { "active": { "charges": 1, "do": [{ "do": "pressure", "amount": 60 }, { "do": "shield", "amount": 1.0 }] } })
    _add("blood_chalice", "Blood Chalice", "active", E, "Use: heal 40 and splash blood around", {}, [],
        { "active": { "charges": 1, "do": [{ "do": "heal", "amount": 40 }, { "do": "nova", "element": "blood", "radius": 160, "potency": 10 }] } })
    _add("pressure_bomb", "Pressure Bomb", "active", L, "Use: a huge nova of your last vent", {}, [],
        { "weight": 0.5, "active": { "charges": 1, "do": [{ "do": "nova", "element": "last", "radius": 320, "potency": 30 }, { "do": "scrap", "amount": 20 }] } })
    _add("prism_engine", "Prism Engine", "active", L, "Use: drench, shock and ignite all nearby", {}, [],
        { "weight": 0.5, "active": { "charges": 1, "do": [{ "do": "spread", "element": "wet", "radius": 260, "potency": 6 }, { "do": "spread", "element": "shock", "radius": 260, "potency": 8 }, { "do": "nova", "element": "fire", "radius": 260, "potency": 10 }] } })

    # --- Elemental families: a Sigil, a Vial and a Coating per element.
    for e in ELEMENTS.keys():
        var T: String = ELEMENT_TITLES[e]
        var en: String = e.capitalize()
        _add("sigil_%s" % e, "%s Sigil" % T, "trinket", U, "+15%% %s damage and %s reactions" % [en, en], { "dmg_%s" % e: 0.15, "potency_%s" % e: 0.15 }, [], { "element": e, "tags": [e] })
        _add("vial_%s" % e, "%s Vial" % T, "trinket", U, "15%% of hits also apply %s" % en, {}, [{ "on": "hit", "chance": 0.15, "do": "apply", "element": e, "potency": 4 }], { "element": e, "tags": [e] })
        _add("coating_%s" % e, "%s Coating" % T, "mod", R, "This gun also applies %s" % en, { "extra_element": e }, [], { "element": e, "tags": [e] })

    for id in catalog.keys():
        var it: Dictionary = catalog[id]
        if not it.has("stack"):
            it["stack"] = "add"
        if not it.has("tags"):
            it["tags"] = [String(it["element"])] if it.has("element") else []
        it["kind"] = "mod" if it["slot"] == "mod" else ("active" if it["slot"] == "active" else "passive")
    _apply_looks()
    _apply_icons()

    # --- Pools: an explicit "pools" in extra wins; everything else is sorted by shape.
    for id in catalog.keys():
        if not catalog[id].has("pools"):
            catalog[id]["pools"] = _auto_pools(catalog[id])


## Isaac-style pool membership derived from what an item does:
##   shop = economy, utility, defence, gun mods and actives; treasure = build-defining
##   (triggers, cond mods, bounce/pierce/chain/lifesteal...); boss = plain stat-ups;
##   hidden = legendaries and big drawbacks; challenge = offence; arena = commons,
##   uncommons and plain rares.
func _auto_pools(it: Dictionary) -> Array:
    var r := int(it["rarity"])
    var mods: Dictionary = it.get("mods", {})
    var has_trig: bool = not it.get("triggers", []).is_empty()
    var has_cond: bool = it.has("cond_mods")
    var drawback := false
    var mechanic := false
    var econ := false
    var defence := false
    var utility := false
    var offence := false
    var plain := not mods.is_empty() and not has_trig and not has_cond
    for k in mods.keys():
        var key: String = k
        var v := float(mods[k])
        if v < 0.0:
            drawback = true
            plain = false
        if key in MECHANIC_KEYS or key.begins_with("potency:") or key.begins_with("pierce_"):
            mechanic = true
        if key in ECONOMY_KEYS:
            econ = true
        if key in DEFENCE_KEYS:
            defence = true
        if key in UTILITY_KEYS:
            utility = true
        if key in ["dmg", "fire_rate", "crit", "crit_dmg", "bounce", "pierce", "proj_count", "g_dmg", "g_fire_rate", "g_count"] \
                or key.begins_with("dmg_") or key.begins_with("fire_rate_") or key.begins_with("vs_"):
            offence = true
        if not (key in BOSS_KEYS or key.begins_with("potency_") or key.begins_with("dmg_")):
            plain = false
    var out: Array = []
    if it.has("active"):
        out = ["shop", "treasure"]
        if r >= Rarity.RARE:
            out.append("hidden")
        return out
    if it["slot"] == "mod":
        out = ["shop", "challenge"]
        if r >= Rarity.RARE or has_trig:
            out.append("treasure")
        if r <= Rarity.UNCOMMON:
            out.append("arena")
        if r == Rarity.LEGENDARY:
            out.append("hidden")
        return out
    if econ or utility or (defence and r <= Rarity.RARE):
        out.append("shop")
    if has_trig or has_cond or mechanic or r == Rarity.LEGENDARY:
        out.append("treasure")
    if r == Rarity.LEGENDARY or (drawback and r >= Rarity.RARE):
        out.append("hidden")
    if plain:
        out.append("boss")
    if offence or (has_trig and not defence and not econ):
        out.append("challenge")
    if r <= Rarity.UNCOMMON or (r == Rarity.RARE and plain):
        out.append("arena")
    if out.is_empty():
        out.append("treasure")
    return out


# --- Looks (costumes on the figure) -----------------------------------------

## Default look per slot when an item has none. Offsets are in body-tile pixels from the
## figure's centre (the body tile is 16 px); scale 1 = the size of the body tile.
const SLOT_LOOKS := {
    "head": { "tile": Vector2i(33, 0), "offset": Vector2(0, -8.0), "scale": 0.6 },
    "chest": {},
    "hands": { "tile": Vector2i(41, 1), "offset": Vector2(6.5, 3.0), "scale": 0.35, "side": true },
    "feet": { "tile": Vector2i(40, 1), "offset": Vector2(0, 7.5), "scale": 0.5 },
    "ring": { "sparkle": true },
    "trinket": { "tile": Vector2i(44, 7), "offset": Vector2(-5.0, 4.0), "scale": 0.35, "side": true },
    "active": { "offset": Vector2(-6.5, -2.0), "scale": 0.45, "side": true, "pips": true },
    "mod": {},
}

## Explicit looks for rare-and-up items (tint may be a Color or an element key).
const LOOKS := {
    # Head
    "crown_of_focus": { "tile": Vector2i(43, 2) },
    "marksman_monocle": { "tile": Vector2i(37, 0), "scale": 0.5 },
    "storm_hood": { "tile": Vector2i(47, 2), "tint": "shock", "scale": 0.7 },
    "seer_circlet": { "tile": Vector2i(44, 2), "scale": 0.5 },
    "boiler_cap": { "tile": Vector2i(38, 0), "tint": Color(1.0, 0.55, 0.25) },
    "berserker_helm": { "tile": Vector2i(36, 0), "tint": Color(0.9, 0.3, 0.3), "scale": 0.7 },
    "skullcap_vented": { "tile": Vector2i(34, 12), "tint": Color(1.0, 0.6, 0.3), "aura": "fire" },
    "seeker_lens": { "tile": Vector2i(37, 0), "scale": 0.5, "tint": Color(0.6, 0.9, 1.0) },
    "cerebral_spark": { "tile": Vector2i(45, 2), "tint": Color(1.0, 0.6, 0.9) },
    "detonator_cap": { "tile": Vector2i(38, 0), "tint": Color(1.0, 0.4, 0.2) },
    "godhead": { "tile": Vector2i(44, 2), "tint": Color(1.0, 0.95, 0.6), "scale": 0.7, "aura": "holy" },
    # Chest
    "conductors_mail": { "tile": Vector2i(33, 1), "tint": "shock" },
    "leech_mail": { "tile": Vector2i(34, 1), "tint": "blood" },
    "spiked_cuirass": { "tile": Vector2i(36, 1) },
    "glacier_plate": { "tile": Vector2i(35, 1), "tint": "ice" },
    "ammo_harness": { "tile": Vector2i(32, 1), "tint": Color(0.85, 0.7, 0.4) },
    "shrapnel_vest": { "tile": Vector2i(32, 1), "tint": Color(0.7, 0.7, 0.75) },
    "phantom_shroud": { "tile": Vector2i(47, 1), "tint": Color(0.75, 0.8, 1.0, 0.6) },
    "phoenix_mantle": { "tile": Vector2i(38, 1), "tint": "fire", "aura": "fire" },
    "gilded_carapace": { "tile": Vector2i(36, 1), "tint": Color(1.0, 0.85, 0.3), "aura": Color(1.0, 0.85, 0.3) },
    "hive_heart": { "tile": Vector2i(34, 1), "tint": Color(0.95, 0.8, 0.3), "aura": Color(0.95, 0.75, 0.2) },
    # Hands
    "grip_of_pierce": { "tile": Vector2i(42, 1) },
    "ricochet_gloves": { "tile": Vector2i(42, 0) },
    "kindling_mitts": { "tile": Vector2i(41, 0), "tint": "fire" },
    "twin_triggers": { "tile": Vector2i(42, 1), "tint": Color(0.9, 0.5, 1.0) },
    "executioners_grip": { "tile": Vector2i(41, 1), "tint": Color(0.8, 0.2, 0.25) },
    "rifled_sleeve": { "tile": Vector2i(41, 0), "tint": Color(0.7, 0.75, 0.85) },
    "cluster_rounds": { "tile": Vector2i(45, 9), "tint": Color(1.0, 0.6, 0.3) },
    "hands_of_storm": { "tile": Vector2i(42, 0), "tint": "shock", "aura": "shock" },
    "mothers_blade": { "tile": Vector2i(35, 7), "tint": Color(0.95, 0.3, 0.35), "scale": 0.55, "aura": Color(0.9, 0.2, 0.25) },
    # Feet
    "frost_treads": { "tile": Vector2i(44, 1), "tint": "ice" },
    "anvil_boots": { "tile": Vector2i(43, 0), "tint": Color(0.6, 0.65, 0.75) },
    "greased_soles": { "tile": Vector2i(45, 1), "tint": "oil" },
    "tidewalkers": { "tile": Vector2i(44, 0), "tint": "wet" },
    "tracker_boots": { "tile": Vector2i(43, 1), "tint": Color(0.6, 0.9, 1.0) },
    "hover_greaves": { "tile": Vector2i(45, 0), "tint": Color(0.75, 0.6, 1.0) },
    "vent_striders": { "tile": Vector2i(43, 1), "tint": Color(1.0, 0.55, 0.25) },
    "seven_league": { "tile": Vector2i(44, 0), "tint": Color(0.6, 1.0, 0.9), "aura": "gale" },
    # Trinkets
    "steam_whistle": { "tile": Vector2i(46, 9), "tint": "wet" },
    "pressure_valve": { "tile": Vector2i(45, 16) },
    "alembic": { "tile": Vector2i(41, 11), "tint": Color(0.5, 1.0, 0.6) },
    "rabbit_foot": { "tile": Vector2i(45, 7), "tint": Color(1.0, 0.9, 0.6) },
    "grisly_trophy": { "tile": Vector2i(38, 11) },
    "static_jar": { "tile": Vector2i(40, 11), "tint": "shock" },
    "hot_rod": { "tile": Vector2i(44, 7), "tint": "fire" },
    "cold_snap": { "tile": Vector2i(44, 7), "tint": "ice" },
    "blood_pact": { "tile": Vector2i(40, 10), "tint": "blood" },
    "plague_censer": { "tile": Vector2i(42, 11), "tint": "poison" },
    "bone_orbit": { "tile": Vector2i(32, 12) },
    "powder_horn": { "tile": Vector2i(45, 9) },
    "wisp_lantern": { "tile": Vector2i(46, 9), "tint": Color(0.7, 0.85, 1.0) },
    "twin_moons": { "tile": Vector2i(43, 12), "tint": Color(0.85, 0.85, 1.0) },
    "heart_of_forge": { "tile": Vector2i(38, 10), "tint": "fire", "aura": "fire" },
    "permafrost_core": { "tile": Vector2i(32, 10), "tint": "ice", "aura": "ice" },
    "skull_choir": { "tile": Vector2i(34, 12), "tint": Color(0.9, 0.85, 1.0), "aura": "void" },
    # Rings (the sparkle default; legendaries add an aura)
    "signet_of_overload": { "sparkle": true, "aura": Color(1.0, 0.5, 0.2) },
    "storm_halo": { "sparkle": true, "tint": "shock", "aura": "shock" },
}


## Merge LOOKS and the element families into the catalog.
func _apply_looks() -> void:
    for id in LOOKS.keys():
        if catalog.has(id) and not catalog[id].has("look"):
            catalog[id]["look"] = LOOKS[id]
    for e in ELEMENTS.keys():
        if catalog.has("mantle_%s" % e):
            catalog["mantle_%s" % e]["look"] = { "tile": Vector2i(37, 1), "tint": e }
        if catalog.has("gloves_%s" % e):
            catalog["gloves_%s" % e]["look"] = { "tile": Vector2i(41, 1), "tint": e }
        if catalog.has("vial_%s" % e):
            catalog["vial_%s" % e]["look"] = { "tile": Vector2i(41, 11), "tint": e }


func _look_color(v, fallback: Color) -> Color:
    if v is Color:
        return v
    if v is String and ELEMENTS.has(v):
        return Element.COLORS[ELEMENTS[v]]
    return fallback


## An item's full look: the slot default with the item's own look on top, colours resolved.
func look_of(item: Dictionary) -> Dictionary:
    var slot: String = item.get("slot", "trinket")
    var out: Dictionary = SLOT_LOOKS.get(slot, {}).duplicate()
    var own: Dictionary = item.get("look", {})
    for k in own.keys():
        out[k] = own[k]
    out["tint"] = _look_color(out.get("tint"), icon_tint(item) if item.has("element") else rarity_color(item))
    if out.has("aura"):
        out["aura"] = _look_color(out["aura"], rarity_color(item))
    if slot == "active" and not out.has("tile"):
        out["icon"] = icon(item)
    return out


func set_color(sid: String) -> Color:
    return tag_color(sid)


## The colour of the player's strongest resonance (the figure's aura), or transparent.
func full_set_color(player: Player) -> Color:
    var t := full_set_id(player)
    return tag_color(t) if t != "" else Color(0, 0, 0, 0)


## The tag of the player's strongest resonance (most items), or "".
func full_set_id(player: Player) -> String:
    var best := ""
    var best_n := 0
    var tc := tag_counts(player)
    for t in tc.keys():
        if int(tc[t]) >= RESONANCE_AT[0] and int(tc[t]) > best_n:
            best = String(t)
            best_n = int(tc[t])
    return best


# --- Forms: a paper-doll figure generated from the class and the gear (FigureGen) ----

## Theme points per mod key, read by FigureGen.item_themes. Element-suffixed keys
## (potency_fire, dmg_ice...) and vs_<state> keys map to their element on their own.
const THEME_KEYS := {
    "armor": "plate", "max_hp": "plate", "thorns": "plate",
    "regen": "holy", "lifesteal": "blood", "dmg": "blood",
    "speed": "scout", "dodge": "scout",
    "potency": "arcane", "state_duration": "arcane", "chain_jumps": "arcane",
    "vent_radius": "arcane", "vent_power": "arcane", "vent_charge": "arcane",
    "pressure_limit": "arcane", "homing": "arcane", "orbitals": "arcane",
    "orbital_element": "arcane", "spectral": "void",
    "fire_rate": "gunslinger", "proj_speed": "gunslinger", "proj_count": "gunslinger",
    "pierce": "gunslinger", "bounce": "gunslinger", "range": "gunslinger",
    "shot_speed": "gunslinger", "shot_size": "gunslinger", "crit": "gunslinger",
    "crit_dmg": "gunslinger", "shards": "gunslinger", "splash": "gunslinger",
    "boomerang": "gunslinger",
    "scrap_gain": "merchant", "luck": "merchant", "xp_gain": "merchant", "carry": "merchant",
}
## The theme of each tag (its items lean on it; a resonance adds more). Element tags use
## their element.
const SET_THEMES := {
    "guard": "plate", "alchemy": "acid", "vent": "fire", "swift": "scout",
    "fortune": "merchant", "gunslinger": "gunslinger", "seeker": "arcane",
}

var _form_cache: Dictionary = {}   # player instance id -> { key, form }


## The player's current form: { id, name, frames ([idle, step] textures), texture (idle),
## tint (white: the texture is coloured), color (the figure's main colour), aura (the top
## theme's colour with a completed set or a worn legendary, else transparent) }. Cached
## per equipment / class / guns hash, so it is cheap per frame.
func form_for(player: Player) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return _form_from(FigureGen.generate_from({ "vagrant": FigureGen.CLASS_WEIGHT }, Color(0, 0, 0, 0)), false)
    var cid := String(player.get_meta("mark_id", "vagrant"))
    var ids: Array = player.equipped_item_ids()
    var gun_els: Array = []
    for g in player.guns:
        gun_els.append(int(g.data.element) if g.data != null else 0)
    var key := hash([player.gear_counts(), cid, gun_els, player.color])
    var pid := player.get_instance_id()
    var cached: Dictionary = _form_cache.get(pid, {})
    if not cached.is_empty() and int(cached["key"]) == key:
        return cached["form"]
    var glow := full_set_id(player) != ""
    for id in ids:
        if int(get_item(String(id)).get("rarity", 0)) >= Rarity.LEGENDARY:
            glow = true
    var form := _form_from(FigureGen.generate(player), glow)
    _form_cache[pid] = { "key": key, "form": form }
    return form


func _form_from(fig: Dictionary, glow: bool) -> Dictionary:
    var frames: Array = fig["frames"]
    return {
        "id": fig["id"], "name": fig["name"], "frames": frames, "texture": frames[0],
        "tint": Color.WHITE, "color": fig["color"],
        "aura": fig["aura"] if glow else Color(0, 0, 0, 0),
    }


## Body tint: white, since the generated figure carries its own colours.
func body_tint(player: Player, base: Color) -> Color:
    return Color(form_for(player)["tint"], base.a)


## Draw the extra layers of `player`'s form on `canvas`. `center` is the body tile's
## centre, `unit` the screen pixels per body-tile pixel (2 in game), `facing` +1 right /
## -1 left. Call once with front = false before the body (form and item auras, ring
## sparkles, the active item slung on the back) and once with front = true after it
## (nothing today: the generated figure already wears its head).
func draw_costume(canvas: CanvasItem, player: Player, center: Vector2, unit: float, facing: float, front: bool) -> void:
    if front:
        return
    var t := float(Time.get_ticks_msec()) / 1000.0
    var form := form_for(player)
    var fa: Color = form["aura"]
    if fa.a > 0.0:
        var pulse := 0.5 + 0.5 * sin(t * 2.5)
        var big := unit * 34.0
        canvas.draw_texture_rect(Art.PARTICLES["light"], Rect2(center - Vector2(big, big) / 2.0, Vector2(big, big)), false, Color(fa, 0.3 + 0.15 * pulse))
        if full_set_id(player) != "":
            for i in 6:
                var sp := center + Vector2(unit * 13.0, 0).rotated(t * 1.2 + TAU * float(i) / 6.0) * Vector2(1.0, 0.6)
                canvas.draw_rect(Rect2(sp - Vector2(unit, unit) * 0.6, Vector2(unit, unit) * 1.2), Color(fa, 0.8))
    # Synergy signatures (section 12): a ring of motes per synergy, in its colour, orbiting
    # the figure: obvious from across the room, under the hostile layer.
    var syns: Array = player.synergies
    for si in syns.size():
        var sc: Color = synergy(String(syns[si])).get("color", Color.WHITE)
        var rr := unit * (16.0 + 3.0 * float(si))
        for i in 4:
            var mp := center + Vector2(rr, 0).rotated(-t * (1.6 + 0.3 * float(si)) + TAU * float(i) / 4.0 + float(si)) * Vector2(1.0, 0.55)
            canvas.draw_rect(Rect2(mp - Vector2(unit, unit) * 0.7, Vector2(unit, unit) * 1.4), Color(sc, 0.9))
    var worn: Array = player.worn_look_ids()
    for wi in worn.size():
        var it := get_item(String(worn[wi]))
        if it.is_empty():
            continue
        var lk := look_of(it)
        var tint: Color = lk["tint"]
        var slot := String(it.get("slot", ""))
        var second := wi % 2 == 1
        if lk.has("aura"):
            var ac: Color = lk["aura"]
            var s := unit * 26.0
            canvas.draw_texture_rect(Art.PARTICLES["light"], Rect2(center - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(ac, 0.22 + 0.08 * sin(t * 3.0)))
        if lk.get("sparkle", false):
            var phase := t * 0.8 + (PI if second else 0.0)
            for i in 3:
                var p := center + Vector2(unit * 10.0, 0).rotated(phase + TAU * float(i) / 3.0) * Vector2(1.0, 0.55)
                canvas.draw_rect(Rect2(p - Vector2(unit, unit) * 0.5, Vector2(unit, unit)), Color(tint, 0.75))
        if slot == "active" and (lk.has("tile") or lk.has("icon")):
            # Slung on the back: behind the figure, on the side away from where it faces.
            var size_b := 16.0 * unit * 0.5
            var at_b := center + Vector2(-facing * 6.0, -3.0) * unit
            var rect_b := Rect2(at_b - Vector2(size_b, size_b) / 2.0, Vector2(size_b, size_b))
            if lk.has("icon"):
                Art.draw_icon(canvas, lk["icon"], rect_b, icon_tint(it))
            else:
                canvas.draw_texture_rect(Art.tile(lk["tile"]), rect_b, false, tint)
            var max_charges := active_max_charges(player)
            for c in max_charges:
                var pip := Rect2(at_b + Vector2(-size_b / 2.0 + float(c) * unit * 2.0, size_b / 2.0 + unit * 0.5), Vector2(unit * 1.5, unit * 1.5))
                canvas.draw_rect(pip, Color(1.0, 0.9, 0.4) if c < player.active_charges else Color(0.25, 0.22, 0.24))
