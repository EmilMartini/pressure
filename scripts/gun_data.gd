class_name GunData
extends Resource
## Static description of a gun. Instances are created by the Guns autoload.
##
## Every archetype has its own way of firing (`mechanic`, and for projectile guns the
## projectile `behaviour`), so two guns of different archetypes never play the same; inside
## one archetype guns differ by element and numbers. See ARCHETYPES for the list and
## `how()` for the plain-words line the gun cards show.

## archetype -> [mechanic, one line on what it is for]. The card shows `how()`.
const ARCHETYPES := {
    "pistol": ["shot", "single aimed shots, long reach"],
    "burst": ["shot", "three-round bursts"],
    "repeater": ["shot", "spins up while it fires"],
    "shotgun": ["shot", "pellet spread that knocks back"],
    "sling": ["shot", "a stone that caroms off walls and enemies"],
    "helix": ["shot", "two elements twisted together, every hit reacts"],
    "wand": ["shot", "a bolt that splits on the first hit"],
    "cannon": ["shot", "a huge slow ball that ploughs through"],
    "flak": ["shot", "bursts into shards near the first enemy"],
    "homing": ["shot", "seekers that spread over different targets"],
    "boomerang": ["shot", "out and back, hitting everything twice"],
    "orb": ["shot", "a slow orb that pulses damage around it"],
    "mortar": ["shot", "lobbed over cover, big splash"],
    "thrower": ["shot", "a thrown flask that leaves a pool"],
    "beam": ["beam", "a continuous ray"],
    "sprayer": ["cone", "a short cone that hits everything in it"],
    "chain": ["chain", "an arc that jumps between enemies"],
    "nova": ["nova", "a ring around you"],
    "melee": ["melee", "a sweep in front of you"],
    "charge": ["charge", "charges up, then a rail through the line"],
    "mine": ["mine", "mines that burst when enemies step near"],
    "turret": ["turret", "deploys a turret that fires on its own"],
}

@export var id: String = ""
@export var display_name: String = "Gun"
@export var archetype: String = ""          # a key of ARCHETYPES
## How a trigger pull works (see Gun.fire): "shot" (projectiles, flying by `behaviour`),
## "beam", "cone", "chain", "nova", "melee", "charge", "mine", "turret".
@export var mechanic: String = "shot"
@export var element: Element.Kind = Element.Kind.NONE
@export var weight: int = 1
@export var damage: float = 5.0             # per projectile, beam or spray tick, arc, ring, sweep, rail, mine, pool tick, orb pulse
@export var fire_rate: float = 4.0          # triggers per second (a burst counts as one; beams and sprays: ticks)
@export var projectile_speed: float = 700.0
@export var projectile_count: int = 1
@export var spread_deg: float = 4.0         # total cone width
@export var max_range: float = 500.0        # auto-fire reach; beam, spray and sweep length; ring radius
@export var lifetime: float = 1.0           # projectile life in seconds
@export var pressure_per_shot: float = 0.0  # signed; hot positive, cold negative; per trigger
@export var reaction_mult: float = 1.0      # potency = damage * reaction_mult
@export var pierce: int = 0
@export var projectile_radius: float = 4.0

## How the projectile flies: "straight", "lob" (arcs over everything, splashes on
## landing), "homing" (turns toward its own target), "boomerang" (turns back at half
## life and returns to the shooter, can hit again), "flak" (bursts into shards near the
## first enemy), "orb" (slow, pulses damage in `aura_radius`), "pool" (lobbed, leaves a
## pool), "fork" (splits into `fork_count` bolts on the first hit), "ricochet" (caroms off
## walls and enemies `ricochets` times), "helix" (pairs twist around one line).
@export var behaviour: String = "straight"
@export var splash_radius: float = 0.0      # lob: full-damage landing splash; others: 50% splash when the shot ends on a hit
@export var burst_count: int = 1            # shots per trigger
@export var burst_gap: float = 0.06         # seconds between burst shots
@export var shard_count: int = 0            # flak shards (50% damage, same element)
@export var homing_turn: float = 0.0        # rad/s
@export var alt_element: Element.Kind = Element.Kind.NONE    # if set, every other projectile carries this element
@export var extra_element: Element.Kind = Element.Kind.NONE  # if set, every hit also applies this (at 80% potency)

## Mechanic numbers (0 = not used by this gun).
@export var knockback: float = 0.0          # shove per hit, px/s
@export var arc_deg: float = 0.0            # spray cone / sweep width (total)
@export var aura_radius: float = 0.0        # orb aura, pool size, mine blast
@export var linger: float = 0.0             # seconds a pool, mine or turret lasts
@export var chain_jumps: int = 0            # chain: enemies after the first
@export var charge_time: float = 0.0        # charge: wind-up before the rail
@export var spin_up: float = 0.0            # repeater: seconds of firing to reach full rate (starts at 40%)
@export var fork_count: int = 0             # wand: bolts the shot splits into
@export var ricochets: int = 0              # sling: rebounds off walls and enemies
@export var paint_every: float = 0.0        # spray / beam: seconds between floor stamps

const PULSE := 0.3        # orb pulse interval, s
const POOL_TICK := 0.5    # pool tick interval, s
const CHAIN_FALLOFF := 0.75
const SPIN_FLOOR := 0.4


func color() -> Color:
    return Element.COLORS[element]


## Budget dps against one target, from the gun's own numbers.
func dps() -> float:
    return dps_at(damage, fire_rate)


## Single-target dps at a given damage per hit and trigger rate (cards pass tier-scaled
## numbers). Splash, shards, chain jumps, area and return hits come on top; each archetype
## gives up single-target output for them (see gun_library.gd).
func dps_at(dmg: float, rate: float) -> float:
    var shots := float(projectile_count) * float(burst_count)
    match mechanic:
        "charge":
            return dmg * shots / maxf(0.05, charge_time + 1.0 / maxf(0.05, rate))
        "beam", "cone", "chain", "nova", "melee", "mine":
            return dmg * rate * shots
        "turret":
            return dmg * rate * float(projectile_count)
    match behaviour:
        "pool":
            # Pools overlap: each one ticks for `linger` seconds.
            return dmg / POOL_TICK * shots * minf(rate * linger, 3.0)
        "orb":
            return dmg / PULSE * shots * minf(rate * lifetime, 3.0)
        "boomerang":
            return dmg * rate * shots * 2.0   # out and back
    if pierce >= 10:
        return dmg * rate * shots   # through everything: one hit per body
    return dmg * rate * shots * (1.0 + 0.5 * float(mini(pierce, 4)))


## One plain-words line on how the gun fires, for the gun cards and the Journal.
func how() -> String:
    var el := String(Element.NAMES.get(element, ""))
    match archetype:
        "pistol":
            return "Single aimed shots"
        "burst":
            return "Bursts of %d" % burst_count
        "repeater":
            return "Spins up: starts at 40%% speed, full after %.1f s of firing" % spin_up
        "shotgun":
            return "%d pellets per shot, knocks back" % projectile_count
        "sling":
            return "Caroms off walls and enemies %d times, knocks back" % ricochets
        "helix":
            return "%s and %s bolts twist together: every hit reacts" % [el, Element.NAMES.get(alt_element, "")]
        "wand":
            return "Splits into %d bolts on the first hit" % fork_count
        "cannon":
            return "Huge slow ball: goes through everything, shoves it"
        "flak":
            return "Bursts into %d shards near the first enemy" % shard_count
        "homing":
            return "%d seekers a shot, each after a different enemy" % projectile_count if projectile_count > 1 else "Seekers, each after a different enemy"
        "boomerang":
            return "Flies out and back through everything"
        "orb":
            return "Slow orb: pulses damage %.0f px around it%s" % [aura_radius, ", pulls enemies in" if knockback < 0.0 else ""]
        "mortar":
            return "Lobbed over cover: %.0f px splash" % splash_radius
        "thrower":
            return "Thrown flask: a %.0f px pool for %.0f s, hurts all in it" % [aura_radius, linger]
        "beam":
            return "Continuous beam, %.0f hits a second, sweeps to the aim%s" % [fire_rate, ", passes through %d" % pierce if pierce > 0 else ""]
        "sprayer":
            return "Spray: hits all in a %.0f px, %.0f deg cone%s" % [max_range, arc_deg, ", pushes back" if knockback > 0.0 else ""]
        "chain":
            return "Arc: jumps to %d more enemies" % chain_jumps
        "nova":
            return "Ring around you: hits all within %.0f px, pushes out" % max_range
        "melee":
            return "Sweeps a %.0f deg arc, %.0f px reach, knocks back" % [arc_deg, max_range]
        "charge":
            return "Charges %.1f s, then a rail through every enemy in line" % charge_time
        "mine":
            return "Tosses mines that burst when an enemy steps near (%.0f s)" % linger
        "turret":
            return "Deploys a turret that fires on its own for %.0f s" % linger
    return ""
