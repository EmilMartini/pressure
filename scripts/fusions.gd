class_name Fusions
extends RefCounted
## Compounds, fusions and cataclysms: the tiers above the 65 pair reactions in elements.gd.
## Pure data plus static lookups; nothing here touches the scene. GDD.md, "Compounds and
## fusions", is the design write-up.
##
## THE TIER LADDER (strictly increasing, hard ceiling MAX_TIER = 4):
##   tier 1  an element state on an enemy (Element.DURATION).
##   tier 2  a pair reaction (Element.DEFS). It plays its actions as today AND leaves the
##           compound REACTION_COMPOUND[name] on the target and/or as a patch.
##   tier 3  a fusion: a compound meets an element that is not one of its canonical
##           ingredients. It consumes the compound. Instant fusions leave nothing; the
##           signature fusions flagged `leaves_field` leave a FUSION FIELD (a patch with the
##           fusion's name that keeps applying its `payload` element for `life` seconds).
##   tier 4  a cataclysm: a fusion field meets a fourth element. It consumes the field and
##           leaves nothing, ever.
## A product is only ever one tier above what made it, and anything that happens inside the
## resolution of a tier N effect (secondary reactions from its applies, its spreads, its
## field's payload ticks) runs with CONTEXT tier N and may only create products of a tier
## above N. Since nothing exists above MAX_TIER, every chain terminates. Concretely:
##   - a reaction fired by a fusion's or cataclysm's apply/spread, or by a field's payload,
##     deals its damage but leaves no compound (tier 2 <= context 3 or 4);
##   - compounds never react with each other, fields never react with each other;
##   - no fusion or cataclysm action list contains "cloud": lingering is done by fields only.
##
## ACTION VOCABULARY: exactly the one Elements._act already runs (see elements.gd), with two
## conventions the integrator resolves through `prepared_actions()` before calling _act:
##   - a radius of RADIUS_FROM_PATCH (-1) means "the patch this fusion happened in, x1.25"
##     (FALLBACK_PATCH_RADIUS when the compound was on an enemy); used by Firedamp, Censer,
##     Plague Pyre and Haemolysis so a bigger cloud is a bigger blast;
##   - in a patch or field context, "heal_source" counts as an area action (runs once, not
##     once per enemy inside), like burst and pull already do in Elements.react_cloud.
## No new action types.
##
## DAMAGE: run the actions with potency * entry["mult"] (reactions are x1.0). Control
## seconds (freeze, stun) and the decay fraction are NOT multiplied; freeze and stun still go
## through Enemy._cc_scale, so the diminishing returns already in enemy.gd apply unchanged.

# --- Tiers ----------------------------------------------------------------------------------
const TIER_STATE := 1
const TIER_REACTION := 2
const TIER_FUSION := 3
const TIER_CATACLYSM := 4
const MAX_TIER := 4

# --- Multipliers (potency x mult) -------------------------------------------------------------
const REACTION_MULT := 1.0
const FUSION_MULT_MIN := 1.8           # neutralized fusions
const FUSION_MULT_PATCH := 1.9         # generated fusions of a cloud or floor compound (easy to hit)
const FUSION_MULT_ENEMY := 2.2         # generated fusions of an enemy-only compound (same target, 1.5-3 s)
const FUSION_MULT_MAX := 2.5           # signatures range 1.9 .. 2.5 by how hard the setup is
const CATACLYSM_MULT_FIZZLE := 3.0
const CATACLYSM_MULT_SURGE := 3.2
const CATACLYSM_MULT_MIN := 3.0
const CATACLYSM_MULT_MAX := 4.0
const PATCH_SCALE := 0.7               # per-enemy potency when a fusion or cataclysm plays over a patch or field (as react_cloud)

# --- Anti-recursion and budgets ------------------------------------------------------------------
const COMPOUND_SLOTS := 1              # per enemy; a newer compound replaces the older one
const MAX_COMPOUND_PATCHES := 4        # per room, on top of Cloud.MAX_CLOUDS (they count toward it too)
const FUSION_COOLDOWN := 0.8           # s per enemy after a fusion: no new fusion AND no new compound on it
const MAX_FUSIONS_PER_SEC := 6         # per room; past it the element lands as a plain element and the compound stays
const MAX_SECONDARY_APPLIES := 10      # element applications (apply/spread, all enemies) one fusion may cause
const MAX_SECONDARY_APPLIES_CATACLYSM := 16
const MAX_APPLY_KINDS := 1             # a fusion or cataclysm applies at most one element kind in total
const FUSION_RADIUS_CAP := 260.0       # every radius in a tier 3 action list
const CATACLYSM_RADIUS_CAP := 320.0    # every radius in a tier 4 action list
const CONTROL_CAP := 3.0               # s, freeze/stun before diminishing returns, any tier
const DECAY_CAP := 0.2                 # max-HP fraction one decay action may take, any tier
const RADIUS_FROM_PATCH := -1.0
const FALLBACK_PATCH_RADIUS := 140.0
const PATCH_RADIUS_SCALE := 1.25

# --- Fields and cataclysms ----------------------------------------------------------------------------
const MAX_FIELDS := 3                  # simultaneous fusion fields per room; a new one replaces the oldest
const FIELD_ARM_TIME := 0.4            # s before a fresh field can cataclysm (the shot that made it cannot)
const FIELD_CATACLYSMS := 1            # a field cataclysms once, then it is gone
const CATACLYSM_ROOM_COOLDOWN := 1.5   # s between two cataclysms anywhere in the room
const FIELD_TICK := 0.5                # s between payload applications inside a field

# --- Repetition (keeps one combination from dominating) -----------------------------------------------
const REPEAT_WINDOW := 8.0             # s, room-wide, per fusion or cataclysm name
const REPEAT_DECAY := 0.8              # each repeat inside the window multiplies mult by this (was 0.85; bots: Wildfire 19% of a loadout)
const REPEAT_FLOOR := 0.3              # never below this share of the listed mult (was 0.55)
## s, room-wide: the same fusion cannot fire twice this close together; the element lands as
## itself and the compound stays (another element can still fuse it). Bots: a wet + shock
## build made Wildfire 1.3 times a second, 20-32% of its fusion damage, without it.
const REPEAT_GAP := 1.0

## Shield cracks per tier (a pair reaction cracks 1, its attuned pair 2, as today).
const SHIELD_CRACKS := { 2: 1, 3: 2, 4: 3 }

## Generated-rule tables (documented in GDD.md). An element cancels a compound whose canonical
## ingredient it opposes (neutralize), and fizzles a field whose payload it opposes.
const CANCELS := {
    Element.Kind.WET: [Element.Kind.OIL, Element.Kind.STONE],
    Element.Kind.SHOCK: [Element.Kind.STONE, Element.Kind.OIL],
    Element.Kind.FIRE: [Element.Kind.WET, Element.Kind.ICE],
    Element.Kind.ICE: [Element.Kind.FIRE],
    Element.Kind.OIL: [Element.Kind.WET],
    Element.Kind.POISON: [Element.Kind.HOLY],
    Element.Kind.ACID: [Element.Kind.STONE, Element.Kind.HOLY],
    Element.Kind.BLOOD: [Element.Kind.HOLY],
    Element.Kind.VOID: [Element.Kind.HOLY],
    Element.Kind.HOLY: [Element.Kind.VOID],
    Element.Kind.GALE: [Element.Kind.STONE],
    Element.Kind.STONE: [Element.Kind.ACID],
}


## Rule inputs the generated rows were built from (kept here so a retune can regenerate them).
## ROLE: an element's signature contribution to a generated fusion (compose / amplify).
const ROLE := {
    Element.Kind.WET: [["apply", Element.Kind.WET, 160.0], ["slow", 0.6, 2.0, 160.0]],
    Element.Kind.SHOCK: [["chain", 2.5], ["stun", 0.6]],
    Element.Kind.FIRE: [["burn", 2.0, 4.0], ["burst", 120.0, 1.2]],
    Element.Kind.ICE: [["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]],
    Element.Kind.OIL: [["apply", Element.Kind.OIL, 180.0], ["slow", 0.6, 2.5, 180.0]],
    Element.Kind.POISON: [["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]],
    Element.Kind.ACID: [["corrode", 6.0], ["burst", 120.0, 1.2]],
    Element.Kind.BLOOD: [["bleed", 2.0, 5.0], ["heal_source", 3.0]],
    Element.Kind.VOID: [["pull", 200.0, 380.0], ["decay", 0.05]],
    Element.Kind.HOLY: [["purge", 2.0], ["heal_source", 3.0]],
    Element.Kind.GALE: [["push", 200.0, 400.0], ["burst", 180.0, 1.0]],
    Element.Kind.STONE: [["stun", 1.0], ["damage", 2.5]],
}

## CATA_ROLE: an element's contribution to a generated cataclysm (surge), added to an echo
## burst of the field (field radius x1.25, capped, x2.0).
const CATA_ROLE := {
    Element.Kind.WET: [["apply", Element.Kind.WET, 260.0], ["push", 240.0, 450.0]],
    Element.Kind.SHOCK: [["chain", 4.0], ["stun", 1.0]],
    Element.Kind.FIRE: [["apply", Element.Kind.FIRE, 240.0], ["burn", 3.0, 5.0]],
    Element.Kind.ICE: [["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]],
    Element.Kind.OIL: [["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]],
    Element.Kind.POISON: [["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]],
    Element.Kind.ACID: [["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]],
    Element.Kind.BLOOD: [["bleed", 3.0, 6.0], ["heal_source", 6.0]],
    Element.Kind.VOID: [["pull", 260.0, 600.0], ["decay", 0.08]],
    Element.Kind.HOLY: [["purge", 3.0], ["heal_source", 6.0]],
    Element.Kind.GALE: [["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]],
    Element.Kind.STONE: [["stun", 1.5], ["damage", 4.0]],
}


# --- Compounds (tier 2 products) -------------------------------------------------------

## id -> compound. `a` and `b` are the canonical ingredients (the fusion table covers every
## other element). `where`: "enemy" (a state on the reaction's target), "cloud" or "floor" (a
## patch at the target), or both ("enemy+cloud", "enemy+floor"). Lifetimes are 0 where the
## compound does not live. `members` lists the reactions that produce it; `kin` elements are the
## other ingredients of those reactions and amplify generated fusions. `core` is what the compound
## itself contributes to a generated fusion.
const COMPOUNDS := {
    "STEAM": {
        "name": "Steam", "a": Element.Kind.WET, "b": Element.Kind.FIRE, "color": Color(0.811, 0.787, 0.83),
        "where": "cloud", "lifetime_enemy": 0.0, "lifetime_cloud": 4.0, "patch_radius": 130.0,
        "flavour": "A scalding fog that hangs where the water boiled.", "noun": "Vapour",
        "members": ["Steam", "Thermal Shock"], "kin": [Element.Kind.ICE],
        "core": [["burst", 130.0, 1.2], ["slow", 0.6, 2.0, 130.0]],
    },
    "MUD": {
        "name": "Mud", "a": Element.Kind.WET, "b": Element.Kind.STONE, "color": Color(0.453, 0.44, 0.415),
        "where": "floor", "lifetime_enemy": 0.0, "lifetime_cloud": 5.0, "patch_radius": 140.0,
        "flavour": "Churned earth that sucks at every step.", "noun": "Mire",
        "members": ["Mud", "Petrichor", "Erosion"], "kin": [Element.Kind.POISON, Element.Kind.ACID],
        "core": [["slow", 0.5, 3.0, 140.0], ["damage", 1.5]],
    },
    "PLASMA": {
        "name": "Plasma", "a": Element.Kind.SHOCK, "b": Element.Kind.FIRE, "color": Color(1.0, 0.784, 0.347),
        "where": "enemy", "lifetime_enemy": 1.5, "lifetime_cloud": 0.0, "patch_radius": 0.0,
        "flavour": "A body crackling white-hot, one spark from going off.", "noun": "Flare",
        "members": ["Plasma", "Ignition", "Electrolysis"], "kin": [Element.Kind.OIL, Element.Kind.ACID],
        "core": [["burst", 110.0, 2.0]],
    },
    "STORMFRONT": {
        "name": "Stormfront", "a": Element.Kind.SHOCK, "b": Element.Kind.GALE, "color": Color(0.808, 0.875, 0.611),
        "where": "enemy+cloud", "lifetime_enemy": 2.0, "lifetime_cloud": 3.5, "patch_radius": 150.0,
        "flavour": "Charged air that hums before it strikes.", "noun": "Squall",
        "members": ["Thunderstorm", "Chain Lightning", "Monsoon"], "kin": [Element.Kind.WET],
        "core": [["burst", 150.0, 1.0], ["stun", 0.5]],
    },
    "BRINE": {
        "name": "Brine", "a": Element.Kind.WET, "b": Element.Kind.ACID, "color": Color(0.55, 0.814, 0.607),
        "where": "floor", "lifetime_enemy": 0.0, "lifetime_cloud": 4.5, "patch_radius": 130.0,
        "flavour": "A hissing, corrosive slurry.", "noun": "Brine",
        "members": ["Caustic Splash", "Contamination", "Dissolve", "Acid Rain"], "kin": [Element.Kind.OIL, Element.Kind.POISON, Element.Kind.GALE],
        "core": [["corrode", 4.0], ["burst", 120.0, 1.0]],
    },
    "MAGMA": {
        "name": "Magma", "a": Element.Kind.FIRE, "b": Element.Kind.STONE, "color": Color(0.908, 0.396, 0.161),
        "where": "floor", "lifetime_enemy": 0.0, "lifetime_cloud": 5.0, "patch_radius": 120.0,
        "flavour": "Molten rock, crusting at the edges.", "noun": "Slag",
        "members": ["Magma"], "kin": [],
        "core": [["burn", 1.5, 3.0], ["damage", 2.0]],
    },
    "GLASS": {
        "name": "Glass", "a": Element.Kind.SHOCK, "b": Element.Kind.STONE, "color": Color(0.803, 0.843, 0.674),
        "where": "enemy", "lifetime_enemy": 2.5, "lifetime_cloud": 0.0, "patch_radius": 0.0,
        "flavour": "Sand fused by lightning into a brittle shell.", "noun": "Glass",
        "members": ["Grounded", "Brittle", "Cryoshock"], "kin": [Element.Kind.ICE, Element.Kind.ACID],
        "core": [["damage", 2.5], ["burst", 90.0, 1.0]],
    },
    "TAR": {
        "name": "Tar", "a": Element.Kind.OIL, "b": Element.Kind.STONE, "color": Color(0.286, 0.237, 0.198),
        "where": "floor", "lifetime_enemy": 0.0, "lifetime_cloud": 5.0, "patch_radius": 140.0,
        "flavour": "Black, sticky, and very flammable.", "noun": "Pitch",
        "members": ["Asphalt", "Tar Pit", "Slick", "Black Ice"], "kin": [Element.Kind.ICE, Element.Kind.POISON, Element.Kind.BLOOD],
        "core": [["slow", 0.5, 3.0, 140.0], ["stun", 0.5]],
    },
    "NAPALM": {
        "name": "Napalm", "a": Element.Kind.FIRE, "b": Element.Kind.OIL, "color": Color(0.834, 0.395, 0.144),
        "where": "enemy+floor", "lifetime_enemy": 2.5, "lifetime_cloud": 4.0, "patch_radius": 110.0,
        "flavour": "Fuel that clings and keeps burning.", "noun": "Pyre",
        "members": ["Inferno", "Chemical Fire", "Anointing", "Oil Spray"], "kin": [Element.Kind.ACID, Element.Kind.HOLY, Element.Kind.GALE],
        "core": [["burn", 2.0, 3.0], ["burst", 110.0, 1.0]],
    },
    "CINDER": {
        "name": "Cinder", "a": Element.Kind.FIRE, "b": Element.Kind.GALE, "color": Color(0.907, 0.591, 0.378),
        "where": "cloud", "lifetime_enemy": 0.0, "lifetime_cloud": 3.5, "patch_radius": 150.0,
        "flavour": "Glowing grit carried on a hot wind.", "noun": "Ash",
        "members": ["Firestorm", "Sandstorm"], "kin": [Element.Kind.STONE],
        "core": [["burst", 150.0, 1.0], ["burn", 1.0, 2.0]],
    },
    "SMOG": {
        "name": "Smog", "a": Element.Kind.FIRE, "b": Element.Kind.POISON, "color": Color(0.582, 0.588, 0.263),
        "where": "cloud", "lifetime_enemy": 0.0, "lifetime_cloud": 4.5, "patch_radius": 140.0,
        "flavour": "Acrid, choking smoke that pools low.", "noun": "Pall",
        "members": ["Noxious Flame", "Virulence"], "kin": [Element.Kind.ACID],
        "core": [["poison", 1.5, 4.0], ["burst", 130.0, 0.8]],
    },
    "MIASMA": {
        "name": "Miasma", "a": Element.Kind.POISON, "b": Element.Kind.GALE, "color": Color(0.565, 0.847, 0.456),
        "where": "cloud", "lifetime_enemy": 0.0, "lifetime_cloud": 4.5, "patch_radius": 160.0,
        "flavour": "A sick green air that clings to the living.", "noun": "Blight",
        "members": ["Plague Wind", "Sepsis", "Galvanic Rot"], "kin": [Element.Kind.SHOCK, Element.Kind.BLOOD],
        "core": [["poison", 1.5, 5.0], ["slow", 0.7, 2.0, 160.0]],
    },
    "RIME": {
        "name": "Rime", "a": Element.Kind.WET, "b": Element.Kind.ICE, "color": Color(0.584, 0.834, 1.0),
        "where": "enemy", "lifetime_enemy": 3.0, "lifetime_cloud": 0.0, "patch_radius": 0.0,
        "flavour": "A hard glaze of ice over everything.", "noun": "Rime",
        "members": ["Deep Freeze", "Glacier", "Frostbite", "Hemostasis"], "kin": [Element.Kind.POISON, Element.Kind.BLOOD, Element.Kind.STONE],
        "core": [["damage", 2.0], ["slow", 0.5, 2.0, 0.0]],
    },
    "BLIZZARD": {
        "name": "Blizzard", "a": Element.Kind.ICE, "b": Element.Kind.GALE, "color": Color(0.82, 0.952, 0.982),
        "where": "cloud", "lifetime_enemy": 0.0, "lifetime_cloud": 4.0, "patch_radius": 160.0,
        "flavour": "Whirling snow that bites and blinds.", "noun": "Whiteout",
        "members": ["Blizzard", "Absolute Zero"], "kin": [Element.Kind.VOID],
        "core": [["slow", 0.5, 3.0, 160.0], ["burst", 160.0, 0.8]],
    },
    "NOVA": {
        "name": "Nova", "a": Element.Kind.FIRE, "b": Element.Kind.HOLY, "color": Color(1.0, 0.77, 0.443),
        "where": "enemy", "lifetime_enemy": 2.0, "lifetime_cloud": 0.0, "patch_radius": 0.0,
        "flavour": "Radiance gathering under the skin.", "noun": "Radiance",
        "members": ["Holy Fire", "Smite", "Neutralize"], "kin": [Element.Kind.SHOCK, Element.Kind.ACID],
        "core": [["burst", 120.0, 1.5]],
    },
    "HALLOW": {
        "name": "Hallow", "a": Element.Kind.HOLY, "b": Element.Kind.STONE, "color": Color(0.845, 0.786, 0.594),
        "where": "floor", "lifetime_enemy": 0.0, "lifetime_cloud": 5.0, "patch_radius": 140.0,
        "flavour": "Sanctified ground that remembers.", "noun": "Sanctum",
        "members": ["Consecrate", "Sanctuary", "Divine Wind"], "kin": [Element.Kind.ICE, Element.Kind.GALE],
        "core": [["burst", 140.0, 1.0], ["heal_source", 2.0]],
    },
    "CHRISM": {
        "name": "Chrism", "a": Element.Kind.WET, "b": Element.Kind.HOLY, "color": Color(0.685, 0.82, 0.941),
        "where": "floor", "lifetime_enemy": 0.0, "lifetime_cloud": 4.0, "patch_radius": 120.0,
        "flavour": "Holy water, still glowing.", "noun": "Font",
        "members": ["Baptism", "Cleanse"], "kin": [Element.Kind.POISON],
        "core": [["purge", 1.5], ["burst", 120.0, 0.8]],
    },
    "HEMO": {
        "name": "Hemo", "a": Element.Kind.WET, "b": Element.Kind.BLOOD, "color": Color(0.676, 0.234, 0.401),
        "where": "enemy+floor", "lifetime_enemy": 2.5, "lifetime_cloud": 4.0, "patch_radius": 110.0,
        "flavour": "Thin, spreading blood that will not clot.", "noun": "Gore",
        "members": ["Thin Blood", "Spray", "Martyrdom"], "kin": [Element.Kind.HOLY, Element.Kind.GALE],
        "core": [["bleed", 1.5, 4.0], ["heal_source", 2.0]],
    },
    "CLOT": {
        "name": "Clot", "a": Element.Kind.ACID, "b": Element.Kind.BLOOD, "color": Color(0.611, 0.266, 0.135),
        "where": "enemy", "lifetime_enemy": 2.0, "lifetime_cloud": 0.0, "patch_radius": 0.0,
        "flavour": "Seared, hardened blood clotting in the wound.", "noun": "Scab",
        "members": ["Coagulant", "Cauterize", "Bludgeon", "Defibrillate"], "kin": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.STONE],
        "core": [["damage", 2.5], ["bleed", 1.0, 3.0]],
    },
    "RIFT": {
        "name": "Rift", "a": Element.Kind.SHOCK, "b": Element.Kind.VOID, "color": Color(0.708, 0.544, 0.837),
        "where": "cloud", "lifetime_enemy": 0.0, "lifetime_cloud": 3.0, "patch_radius": 120.0,
        "flavour": "A pinhole in space that will not stay shut.", "noun": "Rift",
        "members": ["Singularity", "Whirlpool", "Black Hole", "Gravity Well", "Vacuum"], "kin": [Element.Kind.WET, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.STONE],
        "core": [["pull", 200.0, 360.0], ["burst", 90.0, 1.5]],
    },
    "VOIDSTUFF": {
        "name": "Voidstuff", "a": Element.Kind.POISON, "b": Element.Kind.VOID, "color": Color(0.444, 0.424, 0.542),
        "where": "enemy", "lifetime_enemy": 2.0, "lifetime_cloud": 0.0, "patch_radius": 0.0,
        "flavour": "Matter that has started to forget itself.", "noun": "Null",
        "members": ["Decay", "Null Acid", "Exsanguinate"], "kin": [Element.Kind.ACID, Element.Kind.BLOOD],
        "core": [["decay", 0.05], ["damage", 1.0]],
    },
    "ECLIPSE": {
        "name": "Eclipse", "a": Element.Kind.VOID, "b": Element.Kind.HOLY, "color": Color(0.456, 0.334, 0.526),
        "where": "enemy+cloud", "lifetime_enemy": 1.5, "lifetime_cloud": 3.0, "patch_radius": 120.0,
        "flavour": "Light and its absence, held in a shaking balance.", "noun": "Penumbra",
        "members": ["Annihilation", "Dark Flame"], "kin": [Element.Kind.FIRE],
        "core": [["burst", 130.0, 1.8]],
    },
}

## Reaction name -> compound id. Every one of the 65 reactions leaves exactly one compound.
const REACTION_COMPOUND := {
    "Chain Lightning": "STORMFRONT",
    "Steam": "STEAM",
    "Deep Freeze": "RIME",
    "Contamination": "BRINE",
    "Caustic Splash": "BRINE",
    "Thin Blood": "HEMO",
    "Whirlpool": "RIFT",
    "Baptism": "CHRISM",
    "Monsoon": "STORMFRONT",
    "Mud": "MUD",
    "Plasma": "PLASMA",
    "Cryoshock": "GLASS",
    "Galvanic Rot": "MIASMA",
    "Electrolysis": "PLASMA",
    "Defibrillate": "CLOT",
    "Singularity": "RIFT",
    "Smite": "NOVA",
    "Thunderstorm": "STORMFRONT",
    "Grounded": "GLASS",
    "Thermal Shock": "STEAM",
    "Inferno": "NAPALM",
    "Noxious Flame": "SMOG",
    "Chemical Fire": "NAPALM",
    "Cauterize": "CLOT",
    "Dark Flame": "ECLIPSE",
    "Holy Fire": "NOVA",
    "Firestorm": "CINDER",
    "Magma": "MAGMA",
    "Black Ice": "TAR",
    "Frostbite": "RIME",
    "Brittle": "GLASS",
    "Hemostasis": "RIME",
    "Absolute Zero": "BLIZZARD",
    "Sanctuary": "HALLOW",
    "Blizzard": "BLIZZARD",
    "Glacier": "RIME",
    "Ignition": "PLASMA",
    "Tar Pit": "TAR",
    "Dissolve": "BRINE",
    "Slick": "TAR",
    "Black Hole": "RIFT",
    "Anointing": "NAPALM",
    "Oil Spray": "NAPALM",
    "Asphalt": "TAR",
    "Virulence": "SMOG",
    "Sepsis": "MIASMA",
    "Decay": "VOIDSTUFF",
    "Cleanse": "CHRISM",
    "Plague Wind": "MIASMA",
    "Petrichor": "MUD",
    "Coagulant": "CLOT",
    "Null Acid": "VOIDSTUFF",
    "Neutralize": "NOVA",
    "Acid Rain": "BRINE",
    "Erosion": "MUD",
    "Exsanguinate": "VOIDSTUFF",
    "Martyrdom": "HEMO",
    "Spray": "HEMO",
    "Bludgeon": "CLOT",
    "Annihilation": "ECLIPSE",
    "Vacuum": "RIFT",
    "Gravity Well": "RIFT",
    "Divine Wind": "HALLOW",
    "Consecrate": "HALLOW",
    "Sandstorm": "CINDER",
}


# --- Fusions (tier 3) ------------------------------------------------------------------

## compound id -> element kind -> fusion. `rule` says where it came from: "signature" (hand
## designed), "compose" (core + the element's role), "amplify" (kin element: core and role with
## longer durations), "neutralize" (the element cancels an ingredient: one hard burst).
## Only signature fusions with `leaves_field` open a fusion field (see CATACLYSMS).
const FUSIONS := {
    "STEAM": {
        Element.Kind.SHOCK: { "name": "Storm Cloud", "desc": "The steam takes a charge and hangs there, arcing into everything inside", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["chain", 3.0], ["chain_state", Element.Kind.WET, 1.5], ["stun", 0.6]], "leaves_field": true, "field": {"life": 5.0, "radius": 180.0, "payload": Element.Kind.SHOCK}, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["react_chain", "rx_shock", "burst_small"] },
        Element.Kind.ICE: { "name": "Hailstorm", "desc": "The steam freezes in the air and comes down as hail", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["burst", 180.0, 1.6], ["slow", 0.5, 3.0, 180.0], ["freeze", 1.2]], "leaves_field": true, "field": {"life": 4.0, "radius": 180.0, "payload": Element.Kind.ICE}, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE], "size": "large", "fx": "magic"}, "sound": ["nova_frost", "rx_ice", "burst_large"] },
        Element.Kind.OIL: { "name": "Smothered Vapour", "desc": "Oil cancels the steam: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Vapour", "desc": "The steam carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.2], ["slow", 0.6, 2.0, 130.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Acid Deluge", "desc": "The steam condenses into a corroding rain over a wide area", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["burst", 240.0, 1.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 6.0]], "leaves_field": true, "field": {"life": 4.5, "radius": 220.0, "payload": Element.Kind.ACID}, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID], "size": "huge", "fx": "circle"}, "sound": ["react_steam", "rx_acid", "burst_large"] },
        Element.Kind.BLOOD: { "name": "Sanguine Vapour", "desc": "The steam opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.2], ["slow", 0.6, 2.0, 130.0], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Vapour", "desc": "The steam collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.2], ["slow", 0.6, 2.0, 130.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Vapour", "desc": "The steam is scoured clean, punishing every state", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.2], ["slow", 0.6, 2.0, 130.0], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Vapour", "desc": "The steam is flung outward in a blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 180.0, 2.2], ["slow", 0.6, 2.0, 130.0], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Vapour", "desc": "Stone cancels the steam: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "MUD": {
        Element.Kind.SHOCK: { "name": "Charged Mire", "desc": "The mud discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["damage", 1.5], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.FIRE: { "name": "Kiln", "desc": "The mud bakes hard around everyone standing in it", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["stun", 2.0], ["damage", 3.0], ["burst", 150.0, 1.2]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["die_elite", "rx_fire", "burst_med"] },
        Element.Kind.ICE: { "name": "Permafrost", "desc": "The mire freezes solid underfoot", "tier": 3, "mult": 1.9, "rule": "signature", "do": [["freeze", 2.0], ["slow", 0.5, 4.0, 170.0]], "leaves_field": true, "field": {"life": 5.0, "radius": 170.0, "payload": Element.Kind.ICE}, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE], "size": "large", "fx": "magic"}, "sound": ["react_freeze", "rx_ice", "burst_large"] },
        Element.Kind.OIL: { "name": "Smothered Mire", "desc": "Oil cancels the mud: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Mire", "desc": "The mud carries a deep poison from body to body, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["slow", 0.5, 4.5, 140.0], ["damage", 1.5], ["poison", 2.0, 9.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Etched Mire", "desc": "Acid cancels the mud: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Mire", "desc": "The mud opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["damage", 1.5], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Quicksand", "desc": "The mud opens and swallows: everything is dragged to the middle", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["pull", 220.0, 420.0], ["slow", 0.5, 4.0, 200.0], ["damage", 2.0]], "leaves_field": true, "field": {"life": 4.0, "radius": 200.0, "payload": Element.Kind.VOID}, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["nova_frost", "rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Mire", "desc": "The mud is scoured clean, punishing every state", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["damage", 1.5], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Mire", "desc": "The mud is flung outward in a blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["damage", 1.5], ["push", 200.0, 400.0], ["burst", 180.0, 1.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
    },
    "PLASMA": {
        Element.Kind.WET: { "name": "Quenched Flare", "desc": "Wet cancels the plasma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.ICE: { "name": "Snuffed Flare", "desc": "Ice cancels the plasma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Smothered Flare", "desc": "Oil cancels the plasma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Flare", "desc": "The plasma carries a deep poison from body to body", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["burst", 110.0, 2.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Flare", "desc": "The plasma corrodes and splashes, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["burst", 120.0, 3.2], ["corrode", 9.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Flare", "desc": "The plasma opens wounds that feed you", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["burst", 110.0, 2.0], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Collapse", "desc": "The plasma folds in on itself: everything is pulled in, then it implodes", "tier": 3, "mult": 2.5, "rule": "signature", "do": [["pull", 260.0, 560.0], ["burst", 130.0, 3.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.VOID], "size": "huge", "fx": "twirl"}, "sound": ["die_boss", "rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Starfall", "desc": "The plasma ignites into a falling star", "tier": 3, "mult": 2.3, "rule": "signature", "do": [["burst", 200.0, 3.0], ["purge", 1.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.HOLY], "size": "large", "fx": "light"}, "sound": ["shield_break", "rx_holy", "burst_large"] },
        Element.Kind.GALE: { "name": "Ball Lightning", "desc": "A drifting ball of plasma that arcs to everything it shocks", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["apply", Element.Kind.SHOCK, 240.0], ["chain_state", Element.Kind.SHOCK, 2.0], ["burst", 120.0, 1.5]], "leaves_field": true, "field": {"life": 4.0, "radius": 160.0, "payload": Element.Kind.SHOCK}, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE], "size": "huge", "fx": "smoke"}, "sound": ["react_chain", "rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Flare", "desc": "Stone cancels the plasma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "STORMFRONT": {
        Element.Kind.WET: { "name": "Hurricane", "desc": "Rain drives into the storm: everything is soaked, shocked and thrown", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["apply", Element.Kind.WET, 260.0], ["chain", 3.0], ["push", 200.0, 420.0]], "leaves_field": true, "field": {"life": 4.5, "radius": 220.0, "payload": Element.Kind.WET}, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET], "size": "huge", "fx": "smoke"}, "sound": ["react_chain", "rx_wet", "burst_large"] },
        Element.Kind.FIRE: { "name": "Wildfire", "desc": "Lightning on a dry wind: fire runs across the whole crowd", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["apply", Element.Kind.FIRE, 240.0], ["burst", 200.0, 1.5]], "leaves_field": true, "field": {"life": 4.0, "radius": 200.0, "payload": Element.Kind.FIRE}, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE], "size": "huge", "fx": "flame"}, "sound": ["nova_fire", "rx_fire", "burst_large"] },
        Element.Kind.ICE: { "name": "Frozen Squall", "desc": "The stormfront locks the target in ice", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["stun", 0.5], ["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Smothered Squall", "desc": "Oil cancels the stormfront: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Squall", "desc": "The stormfront carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["stun", 0.5], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Squall", "desc": "The stormfront corrodes and splashes", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 2.2], ["stun", 0.5], ["corrode", 6.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Squall", "desc": "The stormfront opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["stun", 0.5], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Squall", "desc": "The stormfront collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["stun", 0.5], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Squall", "desc": "The stormfront is scoured clean, punishing every state", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["stun", 0.5], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.STONE: { "name": "Grounded Squall", "desc": "Stone cancels the stormfront: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "BRINE": {
        Element.Kind.SHOCK: { "name": "Galvanic Sea", "desc": "The whole slurry conducts: lightning through every body in it, eating them as it goes", "tier": 3, "mult": 2.3, "rule": "signature", "do": [["chain", 4.0], ["chain_state", Element.Kind.ACID, 2.0], ["corrode", 6.0]], "leaves_field": true, "field": {"life": 4.0, "radius": 180.0, "payload": Element.Kind.SHOCK}, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["react_chain", "rx_shock", "burst_small"] },
        Element.Kind.FIRE: { "name": "Searing Brine", "desc": "The brine ignites in a burning blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["corrode", 4.0], ["burst", 120.0, 2.2], ["burn", 2.0, 4.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["rx_fire", "burst_med"] },
        Element.Kind.ICE: { "name": "Brinicle", "desc": "A spear of salt ice forms through the target", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["freeze", 2.0], ["damage", 3.5], ["corrode", 5.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.ICE], "size": "small", "fx": "magic"}, "sound": ["react_freeze", "rx_ice", "burst_small"] },
        Element.Kind.OIL: { "name": "Smothered Brine", "desc": "Oil cancels the brine: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Brine", "desc": "The brine carries a deep poison from body to body, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["corrode", 6.0], ["burst", 120.0, 1.0], ["poison", 2.0, 9.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Brine", "desc": "The brine opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["corrode", 4.0], ["burst", 120.0, 1.0], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Brine", "desc": "The brine collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["corrode", 4.0], ["burst", 120.0, 1.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Exorcised Brine", "desc": "Holy cancels the brine: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Brine", "desc": "The brine is flung outward in a blast, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["corrode", 6.0], ["burst", 180.0, 2.0], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Brine", "desc": "Stone cancels the brine: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "MAGMA": {
        Element.Kind.WET: { "name": "Quenched Slag", "desc": "Wet cancels the magma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Slag", "desc": "The magma discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 1.5, 3.0], ["damage", 2.0], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["rx_shock", "burst_small"] },
        Element.Kind.ICE: { "name": "Obsidian", "desc": "The lava glasses over and shatters into stone shards", "tier": 3, "mult": 2.4, "rule": "signature", "do": [["burst", 160.0, 3.0], ["apply", Element.Kind.STONE, 180.0], ["stun", 1.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.ICE], "size": "large", "fx": "magic"}, "sound": ["die_elite", "rx_ice", "burst_large"] },
        Element.Kind.OIL: { "name": "Eruption", "desc": "Fuel in the lava: it erupts, and keeps erupting", "tier": 3, "mult": 2.3, "rule": "signature", "do": [["burst", 180.0, 3.0], ["apply", Element.Kind.FIRE, 180.0]], "leaves_field": true, "field": {"life": 4.0, "radius": 180.0, "payload": Element.Kind.FIRE}, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["react_inferno", "rx_oil", "burst_large"] },
        Element.Kind.POISON: { "name": "Venomous Slag", "desc": "The magma carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 1.5, 3.0], ["damage", 2.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Etched Slag", "desc": "Acid cancels the magma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Slag", "desc": "The magma opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 1.5, 3.0], ["damage", 2.0], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.BLOOD], "size": "small", "fx": "circle"}, "sound": ["rx_blood", "burst_small"] },
        Element.Kind.VOID: { "name": "Hollow Slag", "desc": "The magma collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 1.5, 3.0], ["damage", 2.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Slag", "desc": "The magma is scoured clean, punishing every state", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 1.5, 3.0], ["damage", 2.0], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.HOLY], "size": "small", "fx": "light"}, "sound": ["rx_holy", "burst_small"] },
        Element.Kind.GALE: { "name": "Pyroclast", "desc": "Wind lifts the lava into a scorching blast", "tier": 3, "mult": 2.3, "rule": "signature", "do": [["burst", 220.0, 2.5], ["push", 220.0, 420.0], ["burn", 2.0, 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["nova_fire", "rx_gale", "burst_large"] },
    },
    "GLASS": {
        Element.Kind.WET: { "name": "Drowned Glass", "desc": "The glass soaks the crowd and bogs it down", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["burst", 90.0, 1.0], ["apply", Element.Kind.WET, 160.0], ["slow", 0.6, 2.0, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.FIRE: { "name": "Burning Lens", "desc": "The glass focuses the fire into one searing beam", "tier": 3, "mult": 2.3, "rule": "signature", "do": [["damage", 6.0], ["burn", 2.0, 4.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.FIRE], "size": "small", "fx": "flame"}, "sound": ["react_ignition", "rx_fire", "burst_small"] },
        Element.Kind.ICE: { "name": "Frozen Glass", "desc": "The glass locks the target in ice, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["damage", 2.5], ["burst", 90.0, 1.0], ["freeze", 1.88], ["slow", 0.5, 3.75, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Smothered Glass", "desc": "Oil cancels the glass: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Glass", "desc": "The glass carries a deep poison from body to body", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["burst", 90.0, 1.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Etched Glass", "desc": "Acid cancels the glass: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Glass", "desc": "The glass opens wounds that feed you", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["burst", 90.0, 1.0], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.BLOOD], "size": "small", "fx": "circle"}, "sound": ["rx_blood", "burst_small"] },
        Element.Kind.VOID: { "name": "Hollow Glass", "desc": "The glass collapses inward and eats a slice of health", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["burst", 90.0, 1.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Glass", "desc": "The glass is scoured clean, punishing every state", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["burst", 90.0, 1.0], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.HOLY], "size": "small", "fx": "light"}, "sound": ["rx_holy", "burst_small"] },
        Element.Kind.GALE: { "name": "Glass Storm", "desc": "The shell shatters into a whirl of shards that cut everyone nearby", "tier": 3, "mult": 2.4, "rule": "signature", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.BLOOD, 200.0], ["bleed", 2.0, 4.0]], "leaves_field": true, "field": {"life": 4.0, "radius": 200.0, "payload": Element.Kind.GALE}, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["shield_break", "rx_gale", "burst_large"] },
    },
    "TAR": {
        Element.Kind.WET: { "name": "Quenched Pitch", "desc": "Wet cancels the tar: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Pitch", "desc": "The tar discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["stun", 0.6], ["chain", 2.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.FIRE: { "name": "Pitch Fire", "desc": "The tar goes up in a black, clinging blaze", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["burn", 3.0, 5.0], ["apply", Element.Kind.FIRE, 200.0], ["slow", 0.5, 3.0, 160.0]], "leaves_field": true, "field": {"life": 5.0, "radius": 180.0, "payload": Element.Kind.FIRE}, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE], "size": "large", "fx": "flame"}, "sound": ["react_inferno", "rx_fire", "burst_large"] },
        Element.Kind.ICE: { "name": "Frozen Pitch", "desc": "The tar locks the target in ice, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["slow", 0.5, 4.5, 140.0], ["stun", 0.62], ["freeze", 1.88]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Pitch", "desc": "The tar carries a deep poison from body to body, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["slow", 0.5, 4.5, 140.0], ["stun", 0.62], ["poison", 2.0, 9.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Etched Pitch", "desc": "Acid cancels the tar: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Pitch", "desc": "The tar opens wounds that feed you, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["slow", 0.5, 4.5, 140.0], ["stun", 0.62], ["bleed", 2.0, 7.5], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Pitch", "desc": "The tar collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["stun", 0.5], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Pitch", "desc": "The tar is scoured clean, punishing every state", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["stun", 0.5], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Pitch", "desc": "The tar is flung outward in a blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 140.0], ["stun", 0.5], ["push", 200.0, 400.0], ["burst", 180.0, 1.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
    },
    "NAPALM": {
        Element.Kind.WET: { "name": "Flashover", "desc": "Water on burning fuel: it explodes outward", "tier": 3, "mult": 2.4, "rule": "signature", "do": [["burst", 200.0, 3.0], ["push", 200.0, 400.0], ["apply", Element.Kind.FIRE, 200.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.WET], "size": "large", "fx": "smoke"}, "sound": ["react_ignition", "rx_wet", "burst_large"] },
        Element.Kind.SHOCK: { "name": "Charged Pyre", "desc": "The napalm discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 2.0, 3.0], ["burst", 110.0, 1.0], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.ICE: { "name": "Snuffed Pyre", "desc": "Ice cancels the napalm: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Pyre", "desc": "The napalm carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 2.0, 3.0], ["burst", 110.0, 1.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Pyre", "desc": "The napalm corrodes and splashes, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["burn", 2.0, 4.5], ["burst", 120.0, 2.2], ["corrode", 9.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Pyre", "desc": "The napalm opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 2.0, 3.0], ["burst", 110.0, 1.0], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Pyre", "desc": "The napalm collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 2.0, 3.0], ["burst", 110.0, 1.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Pyre", "desc": "The napalm is scoured clean, punishing every state, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["burn", 2.0, 4.5], ["burst", 110.0, 1.0], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Firewhirl", "desc": "The burning fuel spins up into a tornado of fire", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["pull", 200.0, 360.0], ["burst", 180.0, 2.5], ["apply", Element.Kind.FIRE, 200.0]], "leaves_field": true, "field": {"life": 4.0, "radius": 180.0, "payload": Element.Kind.FIRE}, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["nova_fire", "rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Petrified Pyre", "desc": "The napalm sets into a crushing, stunning blow", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burn", 2.0, 3.0], ["burst", 110.0, 1.0], ["stun", 1.0], ["damage", 2.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "CINDER": {
        Element.Kind.WET: { "name": "Quenched Ash", "desc": "Wet cancels the cinder: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Ash", "desc": "The cinder discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["burn", 1.0, 2.0], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.ICE: { "name": "Snuffed Ash", "desc": "Ice cancels the cinder: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Firefall", "desc": "Oil caught in the cinders comes down as burning rain", "tier": 3, "mult": 2.1, "rule": "signature", "do": [["burst", 220.0, 2.0], ["apply", Element.Kind.FIRE, 220.0], ["burn", 2.0, 4.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["nova_fire", "rx_oil", "burst_large"] },
        Element.Kind.POISON: { "name": "Venomous Ash", "desc": "The cinder carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["burn", 1.0, 2.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Ash", "desc": "The cinder corrodes and splashes", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 2.2], ["burn", 1.0, 2.0], ["corrode", 6.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Ash", "desc": "The cinder opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["burn", 1.0, 2.0], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Ash", "desc": "The cinder collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["burn", 1.0, 2.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Ash", "desc": "The cinder is scoured clean, punishing every state", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 150.0, 1.0], ["burn", 1.0, 2.0], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.STONE: { "name": "Grounded Ash", "desc": "Stone cancels the cinder: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "SMOG": {
        Element.Kind.WET: { "name": "Quenched Pall", "desc": "Wet cancels the smog: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Firedamp", "desc": "A spark in the smog: the whole cloud detonates, and a bigger cloud is a bigger blast", "tier": 3, "mult": 2.4, "rule": "signature", "do": [["burst", -1.0, 3.0], ["burn", 2.0, 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.SHOCK], "size": "large", "fx": "spark"}, "sound": ["react_ignition", "rx_shock", "burst_large"] },
        Element.Kind.ICE: { "name": "Snuffed Pall", "desc": "Ice cancels the smog: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Slick Pall", "desc": "The smog slicks everything nearby", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 4.0], ["burst", 130.0, 0.8], ["apply", Element.Kind.OIL, 180.0], ["slow", 0.6, 2.5, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.ACID: { "name": "Caustic Pall", "desc": "The smog corrodes and splashes, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["poison", 1.5, 6.0], ["burst", 130.0, 2.0], ["corrode", 9.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Pall", "desc": "The smog opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 4.0], ["burst", 130.0, 0.8], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Pall", "desc": "The smog collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 4.0], ["burst", 130.0, 0.8], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Censer", "desc": "The smoke turns to incense: it scours states and mends you", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["purge", 2.5], ["heal_source", 5.0], ["burst", -1.0, 1.5]], "leaves_field": true, "field": {"life": 4.0, "radius": 160.0, "payload": Element.Kind.HOLY}, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY], "size": "large", "fx": "light"}, "sound": ["shield_break", "rx_holy", "burst_large"] },
        Element.Kind.GALE: { "name": "Howling Pall", "desc": "The smog is flung outward in a blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 4.0], ["burst", 180.0, 1.8], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Petrified Pall", "desc": "The smog sets into a crushing, stunning blow", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 4.0], ["burst", 130.0, 0.8], ["stun", 1.0], ["damage", 2.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "MIASMA": {
        Element.Kind.WET: { "name": "Drowned Blight", "desc": "The miasma soaks the crowd and bogs it down", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 5.0], ["slow", 0.6, 2.0, 160.0], ["apply", Element.Kind.WET, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Blight", "desc": "The miasma discharges along every wet body and stuns, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["poison", 1.5, 7.5], ["slow", 0.7, 3.0, 160.0], ["chain", 2.5], ["stun", 0.75]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.FIRE: { "name": "Plague Pyre", "desc": "The tainted air catches: a burning, poisoned flash", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["burn", 2.5, 4.0], ["poison", 2.0, 5.0], ["burst", -1.0, 1.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.FIRE], "size": "large", "fx": "flame"}, "sound": ["react_inferno", "rx_fire", "burst_large"] },
        Element.Kind.ICE: { "name": "Frozen Blight", "desc": "The miasma locks the target in ice", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 5.0], ["slow", 0.5, 2.5, 160.0], ["freeze", 1.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Slick Blight", "desc": "The miasma slicks everything nearby", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 5.0], ["slow", 0.6, 2.5, 180.0], ["apply", Element.Kind.OIL, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.ACID: { "name": "Caustic Blight", "desc": "The miasma corrodes and splashes", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 5.0], ["slow", 0.7, 2.0, 160.0], ["corrode", 6.0], ["burst", 120.0, 1.2]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Black Death", "desc": "The sickness takes to the blood and leaps body to body", "tier": 3, "mult": 2.1, "rule": "signature", "do": [["poison", 3.0, 6.0], ["bleed", 2.0, 5.0], ["spread", Element.Kind.POISON, 220.0]], "leaves_field": true, "field": {"life": 5.0, "radius": 200.0, "payload": Element.Kind.POISON}, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD], "size": "large", "fx": "circle"}, "sound": ["react_steam", "rx_blood", "burst_large"] },
        Element.Kind.VOID: { "name": "Hollow Blight", "desc": "The miasma collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["poison", 1.5, 5.0], ["slow", 0.7, 2.0, 160.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Exorcised Blight", "desc": "Holy cancels the miasma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.STONE: { "name": "Grounded Blight", "desc": "Stone cancels the miasma: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "RIME": {
        Element.Kind.SHOCK: { "name": "Shatter Arc", "desc": "Lightning cracks the glaze and jumps to every frozen body", "tier": 3, "mult": 2.4, "rule": "signature", "do": [["damage", 5.0], ["chain_state", Element.Kind.ICE, 2.5], ["stun", 1.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["react_freeze", "rx_shock", "burst_small"] },
        Element.Kind.FIRE: { "name": "Flashed Rime", "desc": "Fire cancels the rime: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["rx_fire", "burst_med"] },
        Element.Kind.OIL: { "name": "Smothered Rime", "desc": "Oil cancels the rime: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Rime", "desc": "The rime carries a deep poison from body to body, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["damage", 2.0], ["slow", 0.5, 3.0, 0.0], ["poison", 2.0, 9.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Rime", "desc": "The rime corrodes and splashes", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.0], ["slow", 0.5, 2.0, 0.0], ["corrode", 6.0], ["burst", 120.0, 1.2]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Rime", "desc": "The rime opens wounds that feed you, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["damage", 2.0], ["slow", 0.5, 3.0, 0.0], ["bleed", 2.0, 7.5], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.BLOOD], "size": "small", "fx": "circle"}, "sound": ["rx_blood", "burst_small"] },
        Element.Kind.VOID: { "name": "Hollow Rime", "desc": "The rime collapses inward and eats a slice of health", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.0], ["slow", 0.5, 2.0, 0.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Rime", "desc": "The rime is scoured clean, punishing every state", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.0], ["slow", 0.5, 2.0, 0.0], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.HOLY], "size": "small", "fx": "light"}, "sound": ["rx_holy", "burst_small"] },
        Element.Kind.GALE: { "name": "Ice Shrapnel", "desc": "The glaze is blown apart into freezing shrapnel", "tier": 3, "mult": 2.3, "rule": "signature", "do": [["burst", 180.0, 2.0], ["apply", Element.Kind.ICE, 180.0], ["slow", 0.5, 2.5, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["nova_frost", "rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Rime", "desc": "Stone cancels the rime: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ICE, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "BLIZZARD": {
        Element.Kind.WET: { "name": "Drowned Whiteout", "desc": "The blizzard soaks the crowd and bogs it down", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 160.0], ["burst", 160.0, 0.8], ["apply", Element.Kind.WET, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Whiteout", "desc": "The blizzard discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 160.0], ["burst", 160.0, 0.8], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.FIRE: { "name": "Thaw Flood", "desc": "The blizzard melts at once: a wave of water that soaks and shoves", "tier": 3, "mult": 2.0, "rule": "signature", "do": [["apply", Element.Kind.WET, 260.0], ["push", 240.0, 480.0], ["burst", 200.0, 1.5]], "leaves_field": true, "field": {"life": 4.0, "radius": 220.0, "payload": Element.Kind.WET}, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE], "size": "huge", "fx": "flame"}, "sound": ["react_steam", "rx_fire", "burst_large"] },
        Element.Kind.OIL: { "name": "Slick Whiteout", "desc": "The blizzard slicks everything nearby", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 180.0], ["burst", 160.0, 0.8], ["apply", Element.Kind.OIL, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.POISON: { "name": "Venomous Whiteout", "desc": "The blizzard carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 160.0], ["burst", 160.0, 0.8], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Whiteout", "desc": "The blizzard corrodes and splashes", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 160.0], ["burst", 160.0, 2.0], ["corrode", 6.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Whiteout", "desc": "The blizzard opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 160.0], ["burst", 160.0, 0.8], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Hollow Whiteout", "desc": "The blizzard collapses inward and eats a slice of health, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["slow", 0.5, 4.5, 160.0], ["burst", 160.0, 0.8], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Hallowed Whiteout", "desc": "The blizzard is scoured clean, punishing every state", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["slow", 0.5, 3.0, 160.0], ["burst", 160.0, 0.8], ["purge", 2.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.STONE: { "name": "Avalanche", "desc": "Snow and rock come down together", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["burst", 200.0, 2.5], ["stun", 1.5], ["push", 200.0, 380.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.STONE], "size": "large", "fx": "circle"}, "sound": ["die_elite", "rx_stone", "burst_large"] },
    },
    "NOVA": {
        Element.Kind.WET: { "name": "Quenched Radiance", "desc": "Wet cancels the nova: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Judgement", "desc": "A bolt from above, then every holy-marked body nearby is struck too", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["damage", 10.0], ["chain_state", Element.Kind.HOLY, 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["shield_break", "rx_shock", "burst_small"] },
        Element.Kind.ICE: { "name": "Snuffed Radiance", "desc": "Ice cancels the nova: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Slick Radiance", "desc": "The nova slicks everything nearby", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["burst", 120.0, 1.5], ["apply", Element.Kind.OIL, 180.0], ["slow", 0.6, 2.5, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.POISON: { "name": "Venomous Radiance", "desc": "The nova carries a deep poison from body to body", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["burst", 120.0, 1.5], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Radiance", "desc": "The nova corrodes and splashes, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["burst", 120.0, 2.7], ["corrode", 9.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Radiance", "desc": "The nova opens wounds that feed you", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["burst", 120.0, 1.5], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Black Sun", "desc": "The radiance inverts into a dark star that devours what it lights", "tier": 3, "mult": 2.4, "rule": "signature", "do": [["burst", 220.0, 3.0], ["decay", 0.08]], "leaves_field": true, "field": {"life": 4.0, "radius": 180.0, "payload": Element.Kind.VOID}, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["die_boss", "rx_void", "burst_large"] },
        Element.Kind.GALE: { "name": "Howling Radiance", "desc": "The nova is flung outward in a blast", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["burst", 180.0, 2.5], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Petrified Radiance", "desc": "The nova sets into a crushing, stunning blow", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["burst", 120.0, 1.5], ["stun", 1.0], ["damage", 2.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "HALLOW": {
        Element.Kind.WET: { "name": "Drowned Sanctum", "desc": "The hallow soaks the crowd and bogs it down", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 140.0, 1.0], ["heal_source", 2.0], ["apply", Element.Kind.WET, 160.0], ["slow", 0.6, 2.0, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Sanctum", "desc": "The hallow discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 140.0, 1.0], ["heal_source", 2.0], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.FIRE: { "name": "Searing Sanctum", "desc": "The hallow ignites in a burning blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 140.0, 2.2], ["heal_source", 2.0], ["burn", 2.0, 4.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["rx_fire", "burst_med"] },
        Element.Kind.ICE: { "name": "Frozen Sanctum", "desc": "The hallow locks the target in ice, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["burst", 140.0, 1.0], ["heal_source", 2.0], ["freeze", 1.88], ["slow", 0.5, 3.75, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Slick Sanctum", "desc": "The hallow slicks everything nearby", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 140.0, 1.0], ["heal_source", 2.0], ["apply", Element.Kind.OIL, 180.0], ["slow", 0.6, 2.5, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.POISON: { "name": "Venomous Sanctum", "desc": "The hallow carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 140.0, 1.0], ["heal_source", 2.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Etched Sanctum", "desc": "Acid cancels the hallow: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Blood Altar", "desc": "Blood on hallowed ground: an altar that wounds them and feeds you", "tier": 3, "mult": 1.9, "rule": "signature", "do": [["heal_source", 8.0], ["burst", 160.0, 2.0], ["bleed", 2.0, 4.0]], "leaves_field": true, "field": {"life": 5.0, "radius": 160.0, "payload": Element.Kind.HOLY}, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["shield_break", "rx_blood", "burst_med"] },
        Element.Kind.VOID: { "name": "Darkened Sanctum", "desc": "Void cancels the hallow: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.VOID], "size": "medium", "fx": "twirl"}, "sound": ["rx_void", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Sanctum", "desc": "The hallow is flung outward in a blast, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["burst", 180.0, 2.0], ["heal_source", 2.0], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
    },
    "CHRISM": {
        Element.Kind.SHOCK: { "name": "Charged Font", "desc": "The chrism discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["purge", 1.5], ["burst", 120.0, 0.8], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.FIRE: { "name": "Searing Font", "desc": "The chrism ignites in a burning blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["purge", 1.5], ["burst", 120.0, 2.0], ["burn", 2.0, 4.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["rx_fire", "burst_med"] },
        Element.Kind.ICE: { "name": "Frozen Font", "desc": "The chrism locks the target in ice", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["purge", 1.5], ["burst", 120.0, 0.8], ["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Smothered Font", "desc": "Oil cancels the chrism: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Font", "desc": "The chrism carries a deep poison from body to body, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["purge", 1.5], ["burst", 120.0, 0.8], ["poison", 2.0, 9.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Font", "desc": "The chrism corrodes and splashes", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["purge", 1.5], ["burst", 120.0, 2.0], ["corrode", 6.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Communion", "desc": "Holy water and blood: every state is scoured and you are mended", "tier": 3, "mult": 1.9, "rule": "signature", "do": [["heal_source", 8.0], ["purge", 2.0], ["bleed", 1.5, 4.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.BLOOD], "size": "small", "fx": "circle"}, "sound": ["shield_break", "rx_blood", "burst_small"] },
        Element.Kind.VOID: { "name": "Darkened Font", "desc": "Void cancels the chrism: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.VOID], "size": "medium", "fx": "twirl"}, "sound": ["rx_void", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Font", "desc": "The chrism is flung outward in a blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["purge", 1.5], ["burst", 180.0, 1.8], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Font", "desc": "Stone cancels the chrism: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.HOLY, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "HEMO": {
        Element.Kind.SHOCK: { "name": "Charged Gore", "desc": "The hemo discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["bleed", 1.5, 4.0], ["heal_source", 2.0], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["rx_shock", "burst_small"] },
        Element.Kind.FIRE: { "name": "Searing Gore", "desc": "The hemo ignites in a burning blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["bleed", 1.5, 4.0], ["heal_source", 2.0], ["burn", 2.0, 4.0], ["burst", 120.0, 1.2]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["rx_fire", "burst_med"] },
        Element.Kind.ICE: { "name": "Frozen Gore", "desc": "The hemo locks the target in ice", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["bleed", 1.5, 4.0], ["heal_source", 2.0], ["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Smothered Gore", "desc": "Oil cancels the hemo: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Gore", "desc": "The hemo carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["bleed", 1.5, 4.0], ["heal_source", 2.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Haemolysis", "desc": "The blood boils away from the inside", "tier": 3, "mult": 2.1, "rule": "signature", "do": [["bleed", 3.0, 5.0], ["corrode", 6.0], ["burst", -1.0, 1.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.ACID], "size": "large", "fx": "circle"}, "sound": ["hit", "rx_acid", "burst_large"] },
        Element.Kind.VOID: { "name": "Hollow Gore", "desc": "The hemo collapses inward and eats a slice of health", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["bleed", 1.5, 4.0], ["heal_source", 2.0], ["pull", 200.0, 380.0], ["decay", 0.05]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.VOID], "size": "large", "fx": "twirl"}, "sound": ["rx_void", "burst_large"] },
        Element.Kind.HOLY: { "name": "Exorcised Gore", "desc": "Holy cancels the hemo: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Gore", "desc": "The hemo is flung outward in a blast, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["bleed", 1.5, 6.0], ["heal_source", 2.0], ["push", 200.0, 400.0], ["burst", 180.0, 1.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Gore", "desc": "Stone cancels the hemo: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.WET, Element.Kind.BLOOD, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "CLOT": {
        Element.Kind.WET: { "name": "Drowned Scab", "desc": "The clot soaks the crowd and bogs it down", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["bleed", 1.0, 3.0], ["apply", Element.Kind.WET, 160.0], ["slow", 0.6, 2.0, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Scab", "desc": "The clot discharges along every wet body and stuns, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["damage", 2.5], ["bleed", 1.0, 4.5], ["chain", 2.5], ["stun", 0.75]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["rx_shock", "burst_small"] },
        Element.Kind.FIRE: { "name": "Searing Scab", "desc": "The clot ignites in a burning blast, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["damage", 2.5], ["bleed", 1.0, 4.5], ["burn", 2.0, 6.0], ["burst", 120.0, 1.2]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["rx_fire", "burst_med"] },
        Element.Kind.ICE: { "name": "Frozen Scab", "desc": "The clot locks the target in ice", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["bleed", 1.0, 3.0], ["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Slick Scab", "desc": "The clot slicks everything nearby", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["bleed", 1.0, 3.0], ["apply", Element.Kind.OIL, 180.0], ["slow", 0.6, 2.5, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.POISON: { "name": "Venomous Scab", "desc": "The clot carries a deep poison from body to body", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["bleed", 1.0, 3.0], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.VOID: { "name": "Heartstop", "desc": "The clot is pulled into the heart: the target stops dead", "tier": 3, "mult": 2.4, "rule": "signature", "do": [["stun", 2.0], ["decay", 0.08], ["damage", 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.VOID], "size": "small", "fx": "twirl"}, "sound": ["die_elite", "rx_void", "burst_small"] },
        Element.Kind.HOLY: { "name": "Exorcised Scab", "desc": "Holy cancels the clot: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Scab", "desc": "The clot is flung outward in a blast", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["damage", 2.5], ["bleed", 1.0, 3.0], ["push", 200.0, 400.0], ["burst", 180.0, 1.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Scab", "desc": "Stone cancels the clot: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.ACID, Element.Kind.BLOOD, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "RIFT": {
        Element.Kind.WET: { "name": "Drowned Rift", "desc": "The rift soaks the crowd and bogs it down, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["pull", 200.0, 360.0], ["burst", 90.0, 1.5], ["apply", Element.Kind.WET, 160.0], ["slow", 0.6, 3.0, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.WET], "size": "large", "fx": "smoke"}, "sound": ["rx_wet", "burst_large"] },
        Element.Kind.FIRE: { "name": "Accretion", "desc": "Fire falls into the rift and spins into a burning disk", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["pull", 240.0, 480.0], ["burn", 2.5, 4.0], ["apply", Element.Kind.FIRE, 160.0]], "leaves_field": true, "field": {"life": 4.0, "radius": 200.0, "payload": Element.Kind.FIRE}, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE], "size": "huge", "fx": "flame"}, "sound": ["nova_fire", "rx_fire", "burst_large"] },
        Element.Kind.ICE: { "name": "Frozen Rift", "desc": "The rift locks the target in ice", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["pull", 200.0, 360.0], ["burst", 90.0, 1.5], ["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.ICE], "size": "large", "fx": "magic"}, "sound": ["rx_ice", "burst_large"] },
        Element.Kind.OIL: { "name": "Smothered Rift", "desc": "Oil cancels the rift: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.OIL], "size": "medium", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Venomous Rift", "desc": "The rift carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["pull", 200.0, 360.0], ["burst", 90.0, 1.5], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.POISON], "size": "large", "fx": "smoke"}, "sound": ["rx_poison", "burst_large"] },
        Element.Kind.ACID: { "name": "Caustic Rift", "desc": "The rift corrodes and splashes", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["pull", 200.0, 360.0], ["burst", 120.0, 2.7], ["corrode", 6.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.ACID], "size": "large", "fx": "circle"}, "sound": ["rx_acid", "burst_large"] },
        Element.Kind.BLOOD: { "name": "Sanguine Rift", "desc": "The rift opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["pull", 200.0, 360.0], ["burst", 90.0, 1.5], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.BLOOD], "size": "large", "fx": "circle"}, "sound": ["rx_blood", "burst_large"] },
        Element.Kind.HOLY: { "name": "Exorcised Rift", "desc": "Holy cancels the rift: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.HOLY], "size": "medium", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Rift", "desc": "The rift is flung outward in a blast, and it lasts longer (kin element)", "tier": 3, "mult": 1.9, "rule": "amplify", "do": [["pull", 200.0, 360.0], ["burst", 180.0, 2.5], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Grounded Rift", "desc": "Stone cancels the rift: it collapses into one hard burst", "tier": 3, "mult": 1.8, "rule": "neutralize", "do": [["burst", 110.0, 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "VOIDSTUFF": {
        Element.Kind.WET: { "name": "Drowned Null", "desc": "The voidstuff soaks the crowd and bogs it down", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["decay", 0.05], ["damage", 1.0], ["apply", Element.Kind.WET, 160.0], ["slow", 0.6, 2.0, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Null", "desc": "The voidstuff discharges along every wet body and stuns", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["decay", 0.05], ["damage", 1.0], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.SHOCK], "size": "small", "fx": "spark"}, "sound": ["rx_shock", "burst_small"] },
        Element.Kind.FIRE: { "name": "Searing Null", "desc": "The voidstuff ignites in a burning blast", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["decay", 0.05], ["damage", 1.0], ["burn", 2.0, 4.0], ["burst", 120.0, 1.2]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.FIRE], "size": "medium", "fx": "flame"}, "sound": ["rx_fire", "burst_med"] },
        Element.Kind.ICE: { "name": "Frozen Null", "desc": "The voidstuff locks the target in ice", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["decay", 0.05], ["damage", 1.0], ["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Slick Null", "desc": "The voidstuff slicks everything nearby", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["decay", 0.05], ["damage", 1.0], ["apply", Element.Kind.OIL, 180.0], ["slow", 0.6, 2.5, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.ACID: { "name": "Caustic Null", "desc": "The voidstuff corrodes and splashes, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["decay", 0.05], ["damage", 1.0], ["corrode", 9.0], ["burst", 120.0, 1.2]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Null", "desc": "The voidstuff opens wounds that feed you, and it lasts longer (kin element)", "tier": 3, "mult": 2.2, "rule": "amplify", "do": [["decay", 0.05], ["damage", 1.0], ["bleed", 2.0, 7.5], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.BLOOD], "size": "small", "fx": "circle"}, "sound": ["rx_blood", "burst_small"] },
        Element.Kind.HOLY: { "name": "Unmaking", "desc": "Light meets matter that has forgotten itself: it is erased", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["decay", 0.15], ["purge", 2.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.HOLY], "size": "small", "fx": "light"}, "sound": ["die_boss", "rx_holy", "burst_small"] },
        Element.Kind.GALE: { "name": "Howling Null", "desc": "The voidstuff is flung outward in a blast", "tier": 3, "mult": 2.2, "rule": "compose", "do": [["decay", 0.05], ["damage", 1.0], ["push", 200.0, 400.0], ["burst", 180.0, 1.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Fossilize", "desc": "The fading body sets into stone", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["stun", 2.0], ["decay", 0.08], ["damage", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.VOID, Element.Kind.STONE], "size": "small", "fx": "circle"}, "sound": ["die_elite", "rx_stone", "burst_small"] },
    },
    "ECLIPSE": {
        Element.Kind.WET: { "name": "Drowned Penumbra", "desc": "The eclipse soaks the crowd and bogs it down", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.8], ["apply", Element.Kind.WET, 160.0], ["slow", 0.6, 2.0, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.WET], "size": "medium", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Charged Penumbra", "desc": "The eclipse discharges along every wet body and stuns", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.8], ["chain", 2.5], ["stun", 0.6]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.SHOCK], "size": "medium", "fx": "spark"}, "sound": ["rx_shock", "burst_med"] },
        Element.Kind.FIRE: { "name": "Corona", "desc": "A ring of fire flares around the eclipse", "tier": 3, "mult": 2.2, "rule": "signature", "do": [["burst", 220.0, 3.0], ["burn", 2.0, 4.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.FIRE], "size": "large", "fx": "flame"}, "sound": ["nova_fire", "rx_fire", "burst_large"] },
        Element.Kind.ICE: { "name": "Frozen Penumbra", "desc": "The eclipse locks the target in ice", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.8], ["freeze", 1.5], ["slow", 0.5, 2.5, 140.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.ICE], "size": "medium", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Slick Penumbra", "desc": "The eclipse slicks everything nearby", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.8], ["apply", Element.Kind.OIL, 180.0], ["slow", 0.6, 2.5, 180.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.OIL], "size": "large", "fx": "smoke"}, "sound": ["rx_oil", "burst_large"] },
        Element.Kind.POISON: { "name": "Venomous Penumbra", "desc": "The eclipse carries a deep poison from body to body", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.8], ["poison", 2.0, 6.0], ["spread", Element.Kind.POISON, 160.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.POISON], "size": "medium", "fx": "smoke"}, "sound": ["rx_poison", "burst_med"] },
        Element.Kind.ACID: { "name": "Caustic Penumbra", "desc": "The eclipse corrodes and splashes", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 3.0], ["corrode", 6.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.ACID], "size": "medium", "fx": "circle"}, "sound": ["rx_acid", "burst_med"] },
        Element.Kind.BLOOD: { "name": "Sanguine Penumbra", "desc": "The eclipse opens wounds that feed you", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.8], ["bleed", 2.0, 5.0], ["heal_source", 3.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.BLOOD], "size": "medium", "fx": "circle"}, "sound": ["rx_blood", "burst_med"] },
        Element.Kind.GALE: { "name": "Howling Penumbra", "desc": "The eclipse is flung outward in a blast", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 180.0, 2.8], ["push", 200.0, 400.0]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.GALE], "size": "large", "fx": "smoke"}, "sound": ["rx_gale", "burst_large"] },
        Element.Kind.STONE: { "name": "Petrified Penumbra", "desc": "The eclipse sets into a crushing, stunning blow", "tier": 3, "mult": 1.9, "rule": "compose", "do": [["burst", 130.0, 1.8], ["stun", 1.0], ["damage", 2.5]], "leaves_field": false, "visuals": {"sigs": [Element.Kind.VOID, Element.Kind.HOLY, Element.Kind.STONE], "size": "medium", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
}


# --- Cataclysms (tier 4, the ceiling) -----------------------------------------------------

## field fusion name -> element kind -> cataclysm. `rule`: "signature", "surge" (an echo burst of
## the field plus the element's cataclysm role), "fizzle" (the element cancels the field's payload:
## a small burst). The fusion element and the field's payload never react with their own field.
## A cataclysm consumes the field and leaves nothing: no compound, no field, no cloud.
const CATACLYSMS := {
    "Storm Cloud": {
        Element.Kind.WET: { "name": "Supercell", "desc": "The cloud drinks the water and becomes a supercell: everything soaked, everything struck", "tier": 4, "mult": 3.5, "rule": "signature", "do": [["apply", Element.Kind.WET, 300.0], ["chain", 5.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["react_chain", "rx_wet", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Thunderhead", "desc": "The storm cloud erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Smothered Thunderhead", "desc": "Oil cancels the storm cloud: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Pestilent Thunderhead", "desc": "The storm cloud erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Thunderhead", "desc": "The storm cloud erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Thunderhead", "desc": "The storm cloud erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Eye of the Storm", "desc": "The storm folds around a hole: dragged into the eye and struck there", "tier": 4, "mult": 3.6, "rule": "signature", "do": [["pull", 300.0, 650.0], ["chain", 4.0], ["burst", 160.0, 3.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["die_boss", "rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Thunderhead", "desc": "The storm cloud erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Raging Thunderhead", "desc": "The storm cloud erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Grounded Thunderhead", "desc": "Stone cancels the storm cloud: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.SHOCK, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "Hailstorm": {
        Element.Kind.SHOCK: { "name": "Thundering Hail", "desc": "The hailstorm erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Hail", "desc": "The hailstorm erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Hail", "desc": "The hailstorm erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Hail", "desc": "The hailstorm erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Hail", "desc": "The hailstorm erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Hail", "desc": "The hailstorm erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Hail", "desc": "The hailstorm erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Polar Vortex", "desc": "The hail spins into a freezing vortex that drags everything in", "tier": 4, "mult": 3.2, "rule": "signature", "do": [["apply", Element.Kind.ICE, 300.0], ["pull", 280.0, 500.0], ["slow", 0.5, 4.0, 300.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["nova_frost", "rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Meteor Hail", "desc": "The hail turns to stone and falls like meteors", "tier": 4, "mult": 3.4, "rule": "signature", "do": [["burst", 280.0, 3.0], ["stun", 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["die_elite", "rx_stone", "burst_large", "die_boss"] },
    },
    "Acid Deluge": {
        Element.Kind.SHOCK: { "name": "Thundering Deluge", "desc": "The acid deluge erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.FIRE: { "name": "Chemical Firestorm", "desc": "The acid rain catches: a corroding firestorm over the whole field", "tier": 4, "mult": 3.6, "rule": "signature", "do": [["burst", 300.0, 3.0], ["apply", Element.Kind.FIRE, 300.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["react_inferno", "rx_fire", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Deluge", "desc": "The acid deluge erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Deluge", "desc": "The acid deluge erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Deluge", "desc": "The acid deluge erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Deluge", "desc": "The acid deluge erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Deluge", "desc": "The acid deluge erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Exorcised Deluge", "desc": "Holy cancels the acid deluge: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Raging Deluge", "desc": "The acid deluge erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Grounded Deluge", "desc": "Stone cancels the acid deluge: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.FIRE, Element.Kind.ACID, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "Permafrost": {
        Element.Kind.SHOCK: { "name": "Thundering Tundra", "desc": "The permafrost erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.FIRE: { "name": "Methane Bloom", "desc": "Thawed ground releases its gas, and the fire finds it", "tier": 4, "mult": 3.5, "rule": "signature", "do": [["burst", 280.0, 3.5], ["burn", 2.5, 4.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["nova_fire", "rx_fire", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Tundra", "desc": "The permafrost erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Tundra", "desc": "The permafrost erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Tundra", "desc": "The permafrost erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Tundra", "desc": "The permafrost erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Tundra", "desc": "The permafrost erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Tundra", "desc": "The permafrost erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Raging Tundra", "desc": "The permafrost erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 212.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.ICE, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
    },
    "Quicksand": {
        Element.Kind.SHOCK: { "name": "Thundering Quag", "desc": "The quicksand erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.FIRE: { "name": "Blazing Quag", "desc": "The quicksand erupts into a firestorm over everything inside", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.FIRE, 240.0], ["burn", 3.0, 5.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["rx_fire", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Quag", "desc": "The quicksand erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Quag", "desc": "The quicksand erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Quag", "desc": "The quicksand erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Quag", "desc": "The quicksand erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Quag", "desc": "The quicksand erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Exorcised Quag", "desc": "Holy cancels the quicksand: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.GALE: { "name": "Raging Quag", "desc": "The quicksand erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Sinkhole", "desc": "The ground gives way: everything falls in and is buried", "tier": 4, "mult": 3.4, "rule": "signature", "do": [["pull", 300.0, 700.0], ["stun", 2.0], ["damage", 5.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.STONE, Element.Kind.VOID, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["die_elite", "rx_stone", "burst_large", "die_boss"] },
    },
    "Ball Lightning": {
        Element.Kind.WET: { "name": "Drowning Orb", "desc": "The ball lightning erupts into a tidal wave that soaks and throws", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.WET, 260.0], ["push", 240.0, 450.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Orb", "desc": "The ball lightning erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Smothered Orb", "desc": "Oil cancels the ball lightning: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Pestilent Orb", "desc": "The ball lightning erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Orb", "desc": "The ball lightning erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Orb", "desc": "The ball lightning erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Pulsar", "desc": "The ball collapses into a spinning star that whips lightning around the room", "tier": 4, "mult": 3.6, "rule": "signature", "do": [["pull", 260.0, 600.0], ["chain", 5.0], ["chain_state", Element.Kind.SHOCK, 3.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["react_chain", "rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Orb", "desc": "The ball lightning erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Grounded Orb", "desc": "Stone cancels the ball lightning: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.GALE, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "Hurricane": {
        Element.Kind.SHOCK: { "name": "Perfect Storm", "desc": "Every soaked body in the storm is struck at once", "tier": 4, "mult": 3.8, "rule": "signature", "do": [["chain", 6.0], ["stun", 1.5], ["push", 300.0, 600.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["react_chain", "rx_shock", "burst_large", "die_boss"] },
        Element.Kind.FIRE: { "name": "Hypercane", "desc": "Heat feeds the hurricane until it tears itself apart", "tier": 4, "mult": 3.5, "rule": "signature", "do": [["burst", 300.0, 3.0], ["push", 300.0, 700.0], ["apply", Element.Kind.WET, 300.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["react_steam", "rx_fire", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Cyclone", "desc": "The hurricane erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Smothered Cyclone", "desc": "Oil cancels the hurricane: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Pestilent Cyclone", "desc": "The hurricane erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Cyclone", "desc": "The hurricane erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Cyclone", "desc": "The hurricane erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Cyclone", "desc": "The hurricane erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Cyclone", "desc": "The hurricane erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Grounded Cyclone", "desc": "Stone cancels the hurricane: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.WET, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "Wildfire": {
        Element.Kind.WET: { "name": "Quenched Blaze", "desc": "Wet cancels the wildfire: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.ICE: { "name": "Snuffed Blaze", "desc": "Ice cancels the wildfire: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Conflagration", "desc": "Fuel on a running fire: the whole field goes up", "tier": 4, "mult": 3.6, "rule": "signature", "do": [["apply", Element.Kind.FIRE, 320.0], ["burn", 4.0, 6.0], ["burst", 240.0, 2.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["react_inferno", "rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Blaze", "desc": "The wildfire erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Blaze", "desc": "The wildfire erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Blaze", "desc": "The wildfire erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Blaze", "desc": "The wildfire erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Blaze", "desc": "The wildfire erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Crushing Blaze", "desc": "The wildfire erupts into a rockfall that pins the crowd", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["stun", 1.5], ["damage", 4.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_large", "die_boss"] },
    },
    "Galvanic Sea": {
        Element.Kind.FIRE: { "name": "Blazing Shallows", "desc": "The galvanic sea erupts into a firestorm over everything inside", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.FIRE, 240.0], ["burn", 3.0, 5.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["rx_fire", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Shallows", "desc": "The galvanic sea erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Smothered Shallows", "desc": "Oil cancels the galvanic sea: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Pestilent Shallows", "desc": "The galvanic sea erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Shallows", "desc": "The galvanic sea erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Maelstrom", "desc": "The charged sea drains into a hole, dragging and dissolving everything", "tier": 4, "mult": 3.8, "rule": "signature", "do": [["pull", 320.0, 800.0], ["chain", 5.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["die_boss", "rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Shallows", "desc": "The galvanic sea erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Raging Shallows", "desc": "The galvanic sea erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Grounded Shallows", "desc": "Stone cancels the galvanic sea: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.WET, Element.Kind.ACID, Element.Kind.SHOCK, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "Eruption": {
        Element.Kind.WET: { "name": "Phreatic Blast", "desc": "Water meets the eruption: a steam explosion that levels the field", "tier": 4, "mult": 3.6, "rule": "signature", "do": [["burst", 300.0, 4.0], ["push", 300.0, 650.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["nova_fire", "rx_wet", "burst_large", "die_boss"] },
        Element.Kind.SHOCK: { "name": "Thundering Caldera", "desc": "The eruption erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Obsidian Rain", "desc": "The eruption glasses in the air and rains black blades", "tier": 4, "mult": 3.4, "rule": "signature", "do": [["burst", 280.0, 3.0], ["stun", 1.5], ["bleed", 2.5, 5.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["die_elite", "rx_ice", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Caldera", "desc": "The eruption erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Caldera", "desc": "The eruption erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Caldera", "desc": "The eruption erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Caldera", "desc": "The eruption erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Caldera", "desc": "The eruption erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Raging Caldera", "desc": "The eruption erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.STONE, Element.Kind.OIL, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
    },
    "Glass Storm": {
        Element.Kind.WET: { "name": "Drowning Shardstorm", "desc": "The glass storm erupts into a tidal wave that soaks and throws", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.WET, 260.0], ["push", 240.0, 450.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_large", "die_boss"] },
        Element.Kind.FIRE: { "name": "Molten Glass", "desc": "The shards melt mid-flight and stick, burning", "tier": 4, "mult": 3.4, "rule": "signature", "do": [["burn", 3.5, 5.0], ["bleed", 3.0, 5.0], ["burst", 260.0, 2.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["react_ignition", "rx_fire", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Shardstorm", "desc": "The glass storm erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Shardstorm", "desc": "The glass storm erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Shardstorm", "desc": "The glass storm erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Shardstorm", "desc": "The glass storm erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Shardstorm", "desc": "The glass storm erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Shardstorm", "desc": "The glass storm erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Shardstorm", "desc": "The glass storm erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.STONE, Element.Kind.GALE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
    },
    "Pitch Fire": {
        Element.Kind.WET: { "name": "Quenched Bitumen", "desc": "Wet cancels the pitch fire: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Thundering Bitumen", "desc": "The pitch fire erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Snuffed Bitumen", "desc": "Ice cancels the pitch fire: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.POISON: { "name": "Pestilent Bitumen", "desc": "The pitch fire erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Bitumen", "desc": "The pitch fire erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Bitumen", "desc": "The pitch fire erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Bitumen", "desc": "The pitch fire erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Bitumen", "desc": "The pitch fire erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Black Tornado", "desc": "The burning tar is torn up into a black tornado", "tier": 4, "mult": 3.5, "rule": "signature", "do": [["pull", 260.0, 500.0], ["apply", Element.Kind.FIRE, 300.0], ["burst", 260.0, 2.5]], "visuals": {"sigs": [Element.Kind.OIL, Element.Kind.STONE, Element.Kind.FIRE, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["nova_fire", "rx_gale", "burst_large", "die_boss"] },
    },
    "Firewhirl": {
        Element.Kind.WET: { "name": "Quenched Whirl", "desc": "Wet cancels the firewhirl: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.SHOCK: { "name": "Thundering Whirl", "desc": "The firewhirl erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Snuffed Whirl", "desc": "Ice cancels the firewhirl: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.POISON: { "name": "Pestilent Whirl", "desc": "The firewhirl erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Whirl", "desc": "The firewhirl erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Whirl", "desc": "The firewhirl erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Hellmouth", "desc": "The fire tornado bores down into the void, and the void opens", "tier": 4, "mult": 3.8, "rule": "signature", "do": [["pull", 320.0, 800.0], ["burst", 200.0, 4.0], ["burn", 3.0, 5.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["die_boss", "rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Whirl", "desc": "The firewhirl erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Crushing Whirl", "desc": "The firewhirl erupts into a rockfall that pins the crowd", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["stun", 1.5], ["damage", 4.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.OIL, Element.Kind.GALE, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_large", "die_boss"] },
    },
    "Censer": {
        Element.Kind.WET: { "name": "Drowning Incense", "desc": "The censer erupts into a tidal wave that soaks and throws", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.WET, 260.0], ["push", 240.0, 450.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_large", "die_boss"] },
        Element.Kind.SHOCK: { "name": "Thundering Incense", "desc": "The censer erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Incense", "desc": "The censer erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Incense", "desc": "The censer erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Incense", "desc": "The censer erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Sacrament", "desc": "Blood in the incense: a rite that scours them and restores you", "tier": 4, "mult": 3.0, "rule": "signature", "do": [["heal_source", 12.0], ["purge", 3.0], ["burst", 260.0, 2.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["shield_break", "rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Darkened Incense", "desc": "Void cancels the censer: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_med"] },
        Element.Kind.GALE: { "name": "Raging Incense", "desc": "The censer erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Crushing Incense", "desc": "The censer erupts into a rockfall that pins the crowd", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["stun", 1.5], ["damage", 4.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.POISON, Element.Kind.HOLY, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_large", "die_boss"] },
    },
    "Black Death": {
        Element.Kind.WET: { "name": "Drowning Pestilence", "desc": "The black death erupts into a tidal wave that soaks and throws", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.WET, 260.0], ["push", 240.0, 450.0]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_large", "die_boss"] },
        Element.Kind.SHOCK: { "name": "Thundering Pestilence", "desc": "The black death erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.FIRE: { "name": "Great Fire", "desc": "The plague is burned out, and the city with it", "tier": 4, "mult": 3.4, "rule": "signature", "do": [["apply", Element.Kind.FIRE, 320.0], ["burn", 3.0, 6.0], ["burst", 260.0, 1.5]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["react_inferno", "rx_fire", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Pestilence", "desc": "The black death erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Pestilence", "desc": "The black death erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Pestilence", "desc": "The black death erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Extinction", "desc": "The plague forgets its hosts, and they forget themselves", "tier": 4, "mult": 3.4, "rule": "signature", "do": [["decay", 0.2], ["spread", Element.Kind.POISON, 300.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["die_boss", "rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Exorcised Pestilence", "desc": "Holy cancels the black death: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_med"] },
        Element.Kind.STONE: { "name": "Crushing Pestilence", "desc": "The black death erupts into a rockfall that pins the crowd", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["stun", 1.5], ["damage", 4.0]], "visuals": {"sigs": [Element.Kind.POISON, Element.Kind.GALE, Element.Kind.BLOOD, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_large", "die_boss"] },
    },
    "Thaw Flood": {
        Element.Kind.SHOCK: { "name": "Live Water", "desc": "The flood is electrified: every body standing in it is struck", "tier": 4, "mult": 3.6, "rule": "signature", "do": [["chain", 6.0], ["chain_state", Element.Kind.WET, 3.5], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["react_chain", "rx_shock", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Flash Freeze", "desc": "The flood freezes in an instant, with everything in it", "tier": 4, "mult": 3.2, "rule": "signature", "do": [["apply", Element.Kind.ICE, 320.0], ["freeze", 2.5], ["slow", 0.5, 4.0, 320.0]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["react_freeze", "rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Smothered Flood", "desc": "Oil cancels the thaw flood: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_med"] },
        Element.Kind.POISON: { "name": "Pestilent Flood", "desc": "The thaw flood erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Flood", "desc": "The thaw flood erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Flood", "desc": "The thaw flood erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Abyssal Flood", "desc": "The thaw flood erupts into an implosion that eats a share of everything", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["pull", 260.0, 600.0], ["decay", 0.08]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["rx_void", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Seraphic Flood", "desc": "The thaw flood erupts into a rapture that scours every state", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 275.0, 2.0], ["purge", 3.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["rx_holy", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Grounded Flood", "desc": "Stone cancels the thaw flood: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.ICE, Element.Kind.GALE, Element.Kind.FIRE, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_med"] },
    },
    "Black Sun": {
        Element.Kind.WET: { "name": "Drowning Dark Star", "desc": "The black sun erupts into a tidal wave that soaks and throws", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.WET, 260.0], ["push", 240.0, 450.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_large", "die_boss"] },
        Element.Kind.SHOCK: { "name": "Thundering Dark Star", "desc": "The black sun erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Dark Star", "desc": "The black sun erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Dark Star", "desc": "The black sun erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Dark Star", "desc": "The black sun erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Dark Star", "desc": "The black sun erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Dark Star", "desc": "The black sun erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Syzygy", "desc": "Light and dark sun align: one blinding, room-wide detonation", "tier": 4, "mult": 4.0, "rule": "signature", "do": [["burst", 320.0, 4.5]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["die_boss", "rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Raging Dark Star", "desc": "The black sun erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Crushing Dark Star", "desc": "The black sun erupts into a rockfall that pins the crowd", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 225.0, 2.0], ["stun", 1.5], ["damage", 4.0]], "visuals": {"sigs": [Element.Kind.FIRE, Element.Kind.HOLY, Element.Kind.VOID, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_large", "die_boss"] },
    },
    "Blood Altar": {
        Element.Kind.WET: { "name": "Drowning Altar", "desc": "The blood altar erupts into a tidal wave that soaks and throws", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.WET, 260.0], ["push", 240.0, 450.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_large", "die_boss"] },
        Element.Kind.SHOCK: { "name": "Thundering Altar", "desc": "The blood altar erupts into a storm of chained lightning", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["chain", 4.0], ["stun", 1.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.SHOCK], "size": "cataclysm", "fx": "spark"}, "sound": ["rx_shock", "burst_large", "die_boss"] },
        Element.Kind.FIRE: { "name": "Blazing Altar", "desc": "The blood altar erupts into a firestorm over everything inside", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.FIRE, 240.0], ["burn", 3.0, 5.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.FIRE], "size": "cataclysm", "fx": "flame"}, "sound": ["rx_fire", "burst_large", "die_boss"] },
        Element.Kind.ICE: { "name": "Glacial Altar", "desc": "The blood altar erupts into a flash freeze over the whole field", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.ICE, 240.0], ["slow", 0.5, 3.0, 240.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_large", "die_boss"] },
        Element.Kind.OIL: { "name": "Black Altar", "desc": "The blood altar erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Altar", "desc": "The blood altar erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Altar", "desc": "The blood altar erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.VOID: { "name": "Blood Moon", "desc": "The altar darkens: it drinks from everyone in reach and gives it to you", "tier": 4, "mult": 3.4, "rule": "signature", "do": [["decay", 0.15], ["heal_source", 15.0], ["bleed", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.VOID], "size": "cataclysm", "fx": "twirl"}, "sound": ["die_boss", "rx_void", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Raging Altar", "desc": "The blood altar erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 200.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.HOLY, Element.Kind.STONE, Element.Kind.BLOOD, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
    },
    "Accretion": {
        Element.Kind.WET: { "name": "Quenched Disk", "desc": "Wet cancels the accretion: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.WET], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_wet", "burst_med"] },
        Element.Kind.ICE: { "name": "Snuffed Disk", "desc": "Ice cancels the accretion: it fizzles out in one small burst", "tier": 4, "mult": 3.0, "rule": "fizzle", "do": [["burst", 120.0, 1.5]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.ICE], "size": "cataclysm", "fx": "magic"}, "sound": ["rx_ice", "burst_med"] },
        Element.Kind.OIL: { "name": "Black Disk", "desc": "The accretion erupts into a black flood that slicks the room", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.OIL, 260.0], ["slow", 0.5, 3.0, 260.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.OIL], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_oil", "burst_large", "die_boss"] },
        Element.Kind.POISON: { "name": "Pestilent Disk", "desc": "The accretion erupts into a plague that leaps body to body", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["spread", Element.Kind.POISON, 260.0], ["poison", 3.0, 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.POISON], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_poison", "burst_large", "die_boss"] },
        Element.Kind.ACID: { "name": "Dissolving Disk", "desc": "The accretion erupts into a corroding downpour", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["apply", Element.Kind.ACID, 240.0], ["corrode", 8.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.ACID], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_acid", "burst_large", "die_boss"] },
        Element.Kind.BLOOD: { "name": "Crimson Disk", "desc": "The accretion erupts into a red rain that feeds you", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["bleed", 3.0, 6.0], ["heal_source", 6.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.BLOOD], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_blood", "burst_large", "die_boss"] },
        Element.Kind.HOLY: { "name": "Quasar", "desc": "The disk ignites into a quasar: everything is pulled into the beam", "tier": 4, "mult": 4.0, "rule": "signature", "do": [["pull", 320.0, 700.0], ["burst", 240.0, 4.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.HOLY], "size": "cataclysm", "fx": "light"}, "sound": ["die_boss", "rx_holy", "burst_large", "die_boss"] },
        Element.Kind.GALE: { "name": "Raging Disk", "desc": "The accretion erupts into a gale that throws everything out", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["push", 260.0, 600.0], ["slow", 0.6, 2.0, 260.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.GALE], "size": "cataclysm", "fx": "smoke"}, "sound": ["rx_gale", "burst_large", "die_boss"] },
        Element.Kind.STONE: { "name": "Crushing Disk", "desc": "The accretion erupts into a rockfall that pins the crowd", "tier": 4, "mult": 3.2, "rule": "surge", "do": [["burst", 250.0, 2.0], ["stun", 1.5], ["damage", 4.0]], "visuals": {"sigs": [Element.Kind.SHOCK, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.STONE], "size": "cataclysm", "fx": "circle"}, "sound": ["rx_stone", "burst_large", "die_boss"] },
    },
}



# --- Lookups ----------------------------------------------------------------------------------

## name -> {"entry", "tier", "source" (compound id or field fusion name), "element"}; built once.
static var _index: Dictionary = {}
static var _fusion_names: Array = []
static var _cataclysm_names: Array = []
## reaction name -> [a, b] from Element.DEFS; built once.
static var _origin_pairs: Dictionary = {}


## The compound a reaction leaves, or "" for an unknown reaction name.
static func compound_for(reaction_name: String) -> String:
    return REACTION_COMPOUND.get(reaction_name, "")


static func compound(compound_id: String) -> Dictionary:
    return COMPOUNDS.get(compound_id, {})


## The fusion of a compound with an element, or {} when they do not fuse (one of its canonical
## ingredients, or an unknown id). Pass the reaction that made the compound as
## `origin_reaction`: an element that was one of that reaction's own two ingredients refreshes
## instead of fusing (Petrichor, poison + stone, leaves Mud; poison on that Mud is not a third
## element, so it does not fuse).
static func fusion(compound_id: String, element_kind: int, origin_reaction: String = "") -> Dictionary:
    var row: Dictionary = FUSIONS.get(compound_id, {})
    if not row.has(element_kind):
        return {}
    if origin_reaction != "" and _origin_has(origin_reaction, element_kind):
        return {}
    return row[element_kind]


## The cataclysm of a fusion field with a fourth element, or {} when that element does not
## react with the field (the element that made the fusion, or the field's own payload).
static func cataclysm(field_fusion_name: String, element_kind: int) -> Dictionary:
    var row: Dictionary = CATACLYSMS.get(field_fusion_name, {})
    return row.get(element_kind, {})


## True when this fusion leaves a fusion field.
static func leaves_field(fusion_name: String) -> bool:
    return CATACLYSMS.has(fusion_name)


## {"life", "radius", "payload"} of the field a fusion leaves, or {}.
static func field_of(fusion_name: String) -> Dictionary:
    var info := by_name(fusion_name)
    if info.is_empty():
        return {}
    return info["entry"].get("field", {})


## Any fusion or cataclysm by name: {"entry", "tier", "source", "element"}, or {}.
static func by_name(name: String) -> Dictionary:
    _build_index()
    return _index.get(name, {})


## Every tier 3 fusion name (220), in table order, for the Journal.
static func all_fusion_names() -> Array:
    _build_index()
    return _fusion_names.duplicate()


## Every tier 4 cataclysm name, in table order, for the Journal.
static func all_cataclysm_names() -> Array:
    _build_index()
    return _cataclysm_names.duplicate()


## Whether something of `product_tier` may be created inside the resolution of an effect of
## `context_tier` (0 = a plain hit). The ladder only climbs, and stops at MAX_TIER.
static func can_produce(product_tier: int, context_tier: int) -> bool:
    return product_tier > context_tier and product_tier <= MAX_TIER


static func shield_cracks(tier: int) -> int:
    return SHIELD_CRACKS.get(clampi(tier, TIER_REACTION, MAX_TIER), 1)


## The repetition factor for the n-th repeat (0 = first) of one name inside REPEAT_WINDOW.
static func repeat_mult(repeats: int) -> float:
    return maxf(REPEAT_FLOOR, pow(REPEAT_DECAY, maxi(0, repeats)))


## The entry's actions ready for Elements._act: RADIUS_FROM_PATCH resolved against
## `patch_radius` (0 = the compound was on an enemy), radii capped by tier, freeze and stun
## capped at CONTROL_CAP, decay at DECAY_CAP. Returns copies; the table is never mutated.
static func prepared_actions(entry: Dictionary, patch_radius: float = 0.0) -> Array:
    var tier: int = entry.get("tier", TIER_FUSION)
    var cap := CATACLYSM_RADIUS_CAP if tier >= TIER_CATACLYSM else FUSION_RADIUS_CAP
    var base := patch_radius if patch_radius > 0.0 else FALLBACK_PATCH_RADIUS
    var from_patch := base * PATCH_RADIUS_SCALE
    var out: Array = []
    for act in entry.get("do", []):
        var a: Array = act.duplicate()
        match a[0]:
            "burst", "pull", "push":
                a[1] = minf(cap, from_patch if float(a[1]) < 0.0 else float(a[1]))
            "apply", "spread":
                a[2] = minf(cap, from_patch if float(a[2]) < 0.0 else float(a[2]))
            "slow":
                a[3] = minf(cap, from_patch if float(a[3]) < 0.0 else float(a[3]))
            "freeze", "stun":
                a[1] = minf(CONTROL_CAP, float(a[1]))
            "decay":
                a[1] = minf(DECAY_CAP, float(a[1]))
        out.append(a)
    return out


## Checks the tables against the rules above. Empty when everything holds.
static func validate() -> PackedStringArray:
    var errors := PackedStringArray()
    var reaction_names := {}
    for d in Element.DEFS:
        reaction_names[d["name"]] = true
        var cid: String = REACTION_COMPOUND.get(d["name"], "")
        if not COMPOUNDS.has(cid):
            errors.append("reaction %s has no compound" % d["name"])
    if REACTION_COMPOUND.size() != Element.DEFS.size():
        errors.append("REACTION_COMPOUND has %d entries for %d reactions" % [REACTION_COMPOUND.size(), Element.DEFS.size()])
    var compound_names := {}
    for cid in COMPOUNDS:
        var c: Dictionary = COMPOUNDS[cid]
        compound_names[c["name"]] = true
        var on_enemy: bool = String(c["where"]).contains("enemy")
        var patch: bool = String(c["where"]).contains("cloud") or String(c["where"]).contains("floor")
        if on_enemy != (float(c["lifetime_enemy"]) >= 1.5 and float(c["lifetime_enemy"]) <= 3.0):
            errors.append("%s: lifetime_enemy" % cid)
        if patch != (float(c["lifetime_cloud"]) >= 3.0 and float(c["lifetime_cloud"]) <= 5.0):
            errors.append("%s: lifetime_cloud" % cid)
        var row: Dictionary = FUSIONS.get(cid, {})
        for k in Element.ALL:
            var ingredient: bool = k == c["a"] or k == c["b"]
            if ingredient == row.has(k):
                errors.append("%s x %s: coverage" % [cid, Element.NAMES[k]])
    var seen := {}
    for cid in FUSIONS:
        for k in FUSIONS[cid]:
            var e: Dictionary = FUSIONS[cid][k]
            _check_entry(e, TIER_FUSION, "%s x %s" % [cid, Element.NAMES[k]], errors)
            if e.get("leaves_field", false) != CATACLYSMS.has(e["name"]):
                errors.append("%s: leaves_field and CATACLYSMS disagree" % e["name"])
            if e.get("leaves_field", false):
                var f: Dictionary = e["field"]
                if float(f["life"]) < 3.0 or float(f["life"]) > 5.0 or float(f["radius"]) > FUSION_RADIUS_CAP:
                    errors.append("%s: field life or radius" % e["name"])
            _check_name(e["name"], seen, reaction_names, compound_names, errors)
    for fname in CATACLYSMS:
        var info := by_name(fname)
        if info.is_empty():
            errors.append("field %s is not a fusion" % fname)
            continue
        var row: Dictionary = CATACLYSMS[fname]
        if row.size() < 4:
            errors.append("field %s reacts with only %d elements" % [fname, row.size()])
        var payload: int = info["entry"]["field"]["payload"]
        if row.has(info["element"]) or row.has(payload):
            errors.append("field %s reacts with its own element or payload" % fname)
        for k in row:
            _check_entry(row[k], TIER_CATACLYSM, "%s x %s" % [fname, Element.NAMES[k]], errors)
            _check_name(row[k]["name"], seen, reaction_names, compound_names, errors)
    return errors


# --- Internals ----------------------------------------------------------------------------------


static func _build_index() -> void:
    if not _index.is_empty():
        return
    for cid in FUSIONS:
        for k in FUSIONS[cid]:
            var e: Dictionary = FUSIONS[cid][k]
            _index[e["name"]] = { "entry": e, "tier": TIER_FUSION, "source": cid, "element": k }
            _fusion_names.append(e["name"])
    for fname in CATACLYSMS:
        for k in CATACLYSMS[fname]:
            var e: Dictionary = CATACLYSMS[fname][k]
            _index[e["name"]] = { "entry": e, "tier": TIER_CATACLYSM, "source": fname, "element": k }
            _cataclysm_names.append(e["name"])


static func _origin_has(reaction_name: String, element_kind: int) -> bool:
    if _origin_pairs.is_empty():
        for d in Element.DEFS:
            _origin_pairs[d["name"]] = [d["a"], d["b"]]
    var pair: Array = _origin_pairs.get(reaction_name, [])
    return pair.has(element_kind)


static func _check_entry(e: Dictionary, tier: int, where: String, errors: PackedStringArray) -> void:
    if int(e["tier"]) != tier:
        errors.append("%s: tier" % where)
    var mult := float(e["mult"])
    var lo := FUSION_MULT_MIN if tier == TIER_FUSION else CATACLYSM_MULT_MIN
    var hi := FUSION_MULT_MAX if tier == TIER_FUSION else CATACLYSM_MULT_MAX
    if mult < lo or mult > hi:
        errors.append("%s: mult %.2f outside %.1f..%.1f" % [where, mult, lo, hi])
    var cap := FUSION_RADIUS_CAP if tier == TIER_FUSION else CATACLYSM_RADIUS_CAP
    var kinds := {}
    for a in e["do"]:
        match a[0]:
            "cloud":
                errors.append("%s: no cloud actions above tier 2" % where)
            "burst", "pull", "push":
                if float(a[1]) > cap:
                    errors.append("%s: %s radius over cap" % [where, a[0]])
            "apply", "spread":
                kinds[int(a[1])] = true
                if float(a[2]) > cap:
                    errors.append("%s: %s radius over cap" % [where, a[0]])
            "slow":
                if float(a[3]) > cap:
                    errors.append("%s: slow radius over cap" % where)
            "freeze", "stun":
                if float(a[1]) > CONTROL_CAP:
                    errors.append("%s: control over cap" % where)
            "decay":
                if float(a[1]) > DECAY_CAP:
                    errors.append("%s: decay over cap" % where)
    if kinds.size() > MAX_APPLY_KINDS:
        errors.append("%s: applies %d element kinds" % [where, kinds.size()])


static func _check_name(name: String, seen: Dictionary, reactions: Dictionary, compounds: Dictionary, errors: PackedStringArray) -> void:
    if seen.has(name):
        errors.append("duplicate name %s" % name)
    if reactions.has(name) or compounds.has(name):
        errors.append("%s collides with a reaction or compound name" % name)
    seen[name] = true
