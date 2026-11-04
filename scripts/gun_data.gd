class_name GunData
extends Resource
## Static description of a gun. Instances are created by the Guns autoload.

@export var id: String = ""
@export var display_name: String = "Gun"
@export var element: Element.Kind = Element.Kind.NONE
@export var weight: int = 1
@export var damage: float = 5.0
@export var fire_rate: float = 4.0          # shots per second
@export var projectile_speed: float = 700.0
@export var projectile_count: int = 1
@export var spread_deg: float = 4.0         # total cone width
@export var max_range: float = 500.0
@export var lifetime: float = 1.0           # projectile life in seconds
@export var pressure_per_shot: float = 0.0  # signed; hot positive, cold negative
@export var reaction_mult: float = 1.0      # potency = damage * reaction_mult
@export var pierce: int = 0
@export var projectile_radius: float = 4.0


func color() -> Color:
    return Element.COLORS[element]
