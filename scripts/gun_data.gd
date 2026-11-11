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
    # Arsenal expansion batch 2: thrown styles (Thrown) and the new gun behaviours.
    "knife": ["shot", "knives that stick, then fly back to you"],
    "disc": ["shot", "bounces between enemies, then returns"],
    "star": ["shot", "circles its target twice, then returns"],
    "grenade": ["shot", "rolls, bounces once, bursts on a fuse"],
    "javelin": ["shot", "a heavy javelin that pins its last foe"],
    "bola": ["shot", "wraps the first foe and stops it"],
    "anchor": ["shot", "thrown out, dragged back through the crowd"],
    "revolver": ["shot", "a magazine of quick shots, then a reload"],
    "bubble": ["shot", "slow bubbles that trap small foes"],
    "bow": ["shot", "arrows that pierce and push"],
    "sticky": ["shot", "darts that stick, then burst"],
    "reflect": ["beam", "a ray that reflects off walls"],
    "harpoon": ["shot", "a barbed shot that reels its foe in"],
    "sniper": ["shot", "slow shots; long hits always crit"],
    "hymn": ["shot", "hits harder as your health falls"],
    # Arsenal expansion batch 3: summon styles (Summon). Turrets keep "turret".
    "drone": ["summon", "a drone hovers by you and shoots its own target"],
    "familiar": ["summon", "a familiar runs at foes and bites"],
    "orbit": ["summon", "bodies circle you and hit what they touch"],
    "swarm": ["summon", "fliers strike once, then come back"],
    "golem": ["summon", "a slow golem walks with you and slams packs"],
    # Arsenal expansion batch 4: ground styles (GroundZone). Mines keep "mine", the nova "nova".
    "aura": ["ground", "a ring around you burns what comes near"],
    "pulse": ["ground", "a ring rolls out from you"],
    "trail": ["ground", "moving leaves a line that hurts foes crossing it"],
    "totem": ["ground", "plants a totem that hits all near it"],
    "field": ["ground", "spreads a zone under the closest pack"],
    "snare": ["ground", "sets traps in foes' paths"],
    "glyph": ["ground", "kills leave a glyph that hits the next foe"],
    "pod": ["ground", "pods that burst when a foe comes near"],
}

## Arsenal expansion 2.1: every weapon belongs to one of five families. The family comes
## from the archetype unless the entry names one. On screen a "gun" is a "weapon".
const FAMILIES := ["gun", "melee", "thrown", "summon", "ground"]
const FAMILY_OF := {
    "melee": "melee",
    "boomerang": "thrown", "mortar": "thrown", "thrower": "thrown",
    "knife": "thrown", "disc": "thrown", "star": "thrown", "grenade": "thrown", "javelin": "thrown",
    "bola": "thrown", "anchor": "thrown",
    "turret": "summon", "drone": "summon", "familiar": "summon", "orbit": "summon", "swarm": "summon",
    "golem": "summon",
    "nova": "ground", "mine": "ground", "aura": "ground", "pulse": "ground", "trail": "ground",
    "totem": "ground", "field": "ground", "snare": "ground", "glyph": "ground", "pod": "ground",
}
const FAMILY_NAMES := { "gun": "Gun", "melee": "Melee", "thrown": "Thrown", "summon": "Summon", "ground": "Ground" }
## Family -> the item tag a carried weapon counts toward (5.3, Brotato's classes).
const FAMILY_TAGS := { "gun": "gunslinger", "melee": "blade", "thrown": "thrown", "summon": "swarm", "ground": "ground" }
## Arsenal expansion 3.1: rarity is fixed per weapon (Common to Legendary, Items.Rarity);
## the power premium on the weight band is small on purpose.
const RARITY_PREMIUM := [1.00, 1.05, 1.10, 1.18, 1.25]
## Section 2.3: the seven melee swing styles (Melee draws and resolves them).
const MELEE_STYLES := ["sweep", "cleave", "thrust", "slam", "lash", "jab", "spin"]

@export var id: String = ""
@export var display_name: String = "Gun"
@export var archetype: String = ""          # a key of ARCHETYPES
## How a trigger pull works (see Gun.fire): "shot" (projectiles, flying by `behaviour`),
## "beam", "cone", "chain", "nova", "melee", "charge", "mine", "turret".
@export var mechanic: String = "shot"
## Arsenal expansion 2.1: family ("gun", "melee", "thrown", "summon", "ground"), rarity
## (0 Common to 4 Legendary), style (the sub-kind inside the family: a melee swing style,
## a thrown, summon or ground kind), cap (live bodies or effects per weapon, 0 = the
## family default) and unique (legendaries only: the id of their rule).
@export var family: String = "gun"
@export var rarity: int = 0
@export var style: String = ""
@export var cap: int = 0
@export var unique: String = ""
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
@export var magazine: int = 0               # revolver: shots before a reload
@export var reload_time: float = 0.0        # revolver: seconds to reload

const PULSE := 0.3        # orb pulse interval, s
const POOL_TICK := 0.5    # pool tick interval, s
const CHAIN_FALLOFF := 0.75
const SPIN_FLOOR := 0.4


## Summons: bodies this weapon keeps up, before items (Summon.cap_of adds those).
func summon_bodies() -> int:
    return cap if cap > 0 else int(Summon.STYLE_CAP.get(style, 1))


## Share of the per-body rate that lands on one target: swarm fliers spend most of their time
## flying back and respawning; orbits pass a still target now and then.
func summon_share() -> float:
    match style:
        "swarm":
            if behaviour == "latch":
                return 1.0   # leeches stay on until the foe dies
            return 1.0 / (1.0 + fire_rate * (Summon.SWARM_RESPAWN + 0.3))
        "orbit":
            # A body passes a still foe on its ring once a lap.
            return minf(1.0, projectile_speed / (TAU * maxf(20.0, aura_radius)) / maxf(0.1, fire_rate))
    return 1.0


func _bodies_word(noun: String) -> String:
    var n := summon_bodies()
    if n <= 1:
        return "A " + noun
    var words := ["", "One", "Two", "Three", "Four", "Five", "Six"]
    return "%s %ss" % [words[n] if n < words.size() else str(n), noun]


func family_name() -> String:
    return String(FAMILY_NAMES.get(family, "Gun"))


func family_tag() -> String:
    return String(FAMILY_TAGS.get(family, "gunslinger"))


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
        "melee":
            return dmg * rate * shots * Melee.single_mult(self)
        "beam", "cone", "chain", "nova", "mine":
            return dmg * rate * shots
        "turret":
            return dmg * rate * float(projectile_count)
        "summon":
            return dmg * rate * float(summon_bodies()) * summon_share()
        "ground":
            # Zones tick `fire_rate` times a second; traps fire once per lay (`lifetime` s).
            if style in ["snare", "glyph", "pod"]:
                return dmg / maxf(0.1, lifetime)
            return dmg * rate
    if magazine > 0 and rate > 0.0:
        # Revolver: the magazine at the trigger rate, then the reload.
        var mag := float(magazine)
        return dmg * shots * mag / (mag / rate + reload_time)
    match behaviour:
        "knife", "anchor":
            return dmg * rate * shots * 1.5   # out, and most of them back
        "disc":
            return dmg * rate * shots * 2.0   # out and back
        "star":
            return dmg * rate * shots * 3.0   # the throw and two laps
        "grenade", "javelin", "bola", "bubble", "harpoon", "converge":
            return dmg * rate * shots
        "sticky":
            return dmg * rate * shots * (1.0 + Thrown.STICKY_DART)
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
            return Melee.how(self)
        "charge":
            return "Charges %.1f s, then a rail through every enemy in line" % charge_time
        "mine":
            if behaviour == "chain":
                return "Tossed mines; when one bursts, the ones near it follow"
            if behaviour == "collapse":
                return "Tossed mines pull foes in, then crush them"
            return "Tosses mines that burst when an enemy steps near (%.0f s)" % linger
        "turret":
            if chain_jumps > 0:
                return "Deploys a post that arcs to %d foes for %.0f s" % [chain_jumps + 1, linger]
            return "Deploys a turret that fires on its own for %.0f s" % linger
        "drone":
            return "%s hover%s by you, %s" % [_bodies_word("drone"), "" if summon_bodies() > 1 else "s", "lobbing bombs" if behaviour == "lob" else ("raining on packs" if behaviour == "rain" else "zapping the closest foe")]
        "familiar":
            return "%s run%s at foes and bite%s" % [_bodies_word("familiar"), "" if summon_bodies() > 1 else "s", "" if summon_bodies() > 1 else "s"]
        "orbit":
            return "%s circle you %.0f px out, hitting what they touch" % [_bodies_word("orbiter"), aura_radius]
        "swarm":
            return "%s strike once, back after %.0f s" % [_bodies_word("flier"), Summon.SWARM_RESPAWN]
        "golem":
            return "A golem walks with you and slams packs (%.0f px)" % aura_radius
        "aura":
            return "A %.0f px ring around you hits foes inside %.0f times a second" % [aura_radius, fire_rate]
        "pulse":
            return "A ring rolls out %.0f px from you, shoving foes" % max_range
        "trail":
            return "Moving leaves a line that hurts foes on it (%.0f s)" % linger
        "totem":
            return "Plants up to %d totems at your feet; each hits foes within %.0f px" % [cap if cap > 0 else 2, aura_radius]
        "field":
            return "A %.0f px zone under the closest pack for %.0f s" % [aura_radius, linger]
        "snare":
            return "Sets up to %d traps in foes' paths; a trap holds what it bites" % (cap if cap > 0 else 3)
        "glyph":
            return "Kills leave a glyph that strikes the next foe on it"
        "pod":
            return "Sets pods that burst (%.0f px) when a foe comes near" % aura_radius
        "knife":
            return "%d knives stick for %.1f s, then fly back" % [projectile_count, Thrown.STICK]
        "disc":
            return "Bounces between %d foes, then comes back" % (ricochets + 1)
        "star":
            return "Circles its target twice, then comes back"
        "grenade":
            return "Rolls, bounces once, bursts after %.1f s (%.0f px)" % [linger, splash_radius]
        "javelin":
            return ("Pierces %d; the last foe hit is pinned for 1 s" % pierce) if pierce > 0 else "Sticks in a foe and pins it for 1 s"
        "bola":
            return "Wraps the first foe: it stops for 1.2 s"
        "anchor":
            return "Thrown out, then dragged back: pulls foes to you"
        "revolver":
            return "%d quick shots, then a %.1f s reload" % [magazine, reload_time]
        "bubble":
            return "Slow bubbles: small foes are trapped for 0.6 s"
        "bow":
            return "Arrows pierce %d and push foes along the line" % pierce
        "sticky":
            return "Darts stick, then burst after 1 s (%.0f px)" % splash_radius
        "reflect":
            return "Continuous ray that reflects off walls %d times" % ricochets
        "harpoon":
            return "A barbed shot that reels its foe to you"
        "sniper":
            return "Slow shots; hits past 300 px always crit"
        "hymn":
            return "Up to triple damage as your health falls"
    return ""
