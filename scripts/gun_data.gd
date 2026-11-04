class_name GunData
extends Resource
## Static description of a gun. Instances are created by the Guns autoload.

@export var id: String = ""
@export var display_name: String = "Gun"
@export var archetype: String = ""          # flavour label: pistol, rifle, shotgun, smg, sniper...
@export var element: Element.Kind = Element.Kind.NONE
@export var weight: int = 1
@export var damage: float = 5.0
@export var fire_rate: float = 4.0          # triggers per second (a burst counts as one trigger)
@export var projectile_speed: float = 700.0
@export var projectile_count: int = 1
@export var spread_deg: float = 4.0         # total cone width
@export var max_range: float = 500.0
@export var lifetime: float = 1.0           # projectile life in seconds
@export var pressure_per_shot: float = 0.0  # signed; hot positive, cold negative; per trigger
@export var reaction_mult: float = 1.0      # potency = damage * reaction_mult
@export var pierce: int = 0
@export var projectile_radius: float = 4.0

## How the projectile flies: "straight", "lob" (arcs over everything, splashes on
## landing), "homing" (turns toward the nearest enemy), "boomerang" (turns back at half
## life and returns to the shooter, can hit again), "flak" (bursts into shards).
@export var behaviour: String = "straight"
@export var splash_radius: float = 0.0      # lob: full-damage landing splash; others: 50% splash when the shot ends on a hit
@export var burst_count: int = 1            # shots per trigger
@export var burst_gap: float = 0.06         # seconds between burst shots
@export var shard_count: int = 0            # flak shards (50% damage, same element)
@export var homing_turn: float = 0.0        # rad/s
@export var alt_element: Element.Kind = Element.Kind.NONE    # if set, every other projectile carries this element
@export var extra_element: Element.Kind = Element.Kind.NONE  # if set, every hit also applies this (at 80% potency)


func color() -> Color:
    return Element.COLORS[element]


## Budget dps: damage * fire_rate * projectile_count * burst_count * (1 + 0.5 * pierce).
## Ignores splash, shards and boomerang return hits.
func dps() -> float:
    return damage * fire_rate * float(projectile_count) * float(burst_count) * (1.0 + 0.5 * float(pierce))
