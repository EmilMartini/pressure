class_name RoomData
extends RefCounted
## Persistent state of one room on the floor map. The Room node is rebuilt from this
## every time the party enters, so anything that must survive leaving lives here.

enum Type { START, ARENA, SHOP, TREASURE, CHALLENGE, HIDDEN, BOSS }

const TYPE_NAMES := {
    Type.START: "Entrance",
    Type.ARENA: "Arena",
    Type.SHOP: "Shop",
    Type.TREASURE: "Treasure",
    Type.CHALLENGE: "Challenge",
    Type.HIDDEN: "Hidden Cache",
    Type.BOSS: "Boss",
}

const TYPE_COLORS := {
    Type.START: Color(0.6, 0.6, 0.6),
    Type.ARENA: Color(0.75, 0.75, 0.8),
    Type.SHOP: Color(1.0, 0.85, 0.3),
    Type.TREASURE: Color(1.0, 0.6, 0.2),
    Type.CHALLENGE: Color(0.8, 0.4, 1.0),
    Type.HIDDEN: Color(0.4, 0.95, 0.95),
    Type.BOSS: Color(1.0, 0.3, 0.3),
}

var pos: Vector2i
var type: int = Type.ARENA
var cleared := false
var visited := false
var discovered := false   # drawn on the minimap
var started := false      # arena / challenge / boss fight has begun at least once

## dir (Vector2i) -> { "to": Vector2i, "obstacle": String }
## obstacle is "" for a plain door, else "pool" / "thicket" / "valve".
var doors: Dictionary = {}

## Pedestal offers: { "kind": "gun"|"carry"|"repair"|"stairs"|"sigil", "id": String,
##                    "price": int, "amount": int, "taken": bool }
var stock: Array = []

## Scrap pieces lying in the room (hidden caches), collected on entry.
var loose_scrap := 0

## Treasure rooms: how big the chest is (1 small, 2 medium, 3+ large).
var chest_tier := 1


func type_name() -> String:
    return TYPE_NAMES[type]


func color() -> Color:
    return TYPE_COLORS[type]


func is_safe() -> bool:
    return type in [Type.START, Type.SHOP, Type.TREASURE, Type.HIDDEN]
