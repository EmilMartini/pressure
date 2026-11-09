class_name SpawnTable
extends RefCounted
## What spawns where: enemy groups gated by floor and weighted by difficulty, elite
## affixes and counts, and the boss for each floor. Difficulty runs about 2..22.

## Kind -> [first floor it appears on, base weight, weight gained per difficulty point].
const KINDS := {
    "grunt": [1, 10.0, -0.30],
    "runner": [1, 6.0, -0.10],
    "swarmer": [1, 3.0, 0.05],
    "brute": [2, 1.0, 0.15],
    "spitter": [1, 1.6, 0.20],   # from floor 1: standing still must cost something
    "charger": [2, 1.5, 0.15],
    "bomber": [2, 1.5, 0.12],
    "splitter": [3, 1.5, 0.15],
    "shaman": [3, 0.6, 0.05],
    "warden": [3, 0.5, 0.07],
    "wisp": [4, 2.0, 0.15],
}

## Kinds that are not easy fodder: weighted up from floor 4.
const HARD := ["brute", "spitter", "charger", "bomber", "splitter", "shaman", "warden", "wisp"]

const AFFIXES := ["regenerating", "hasted", "trail", "volatile"]
const DEEP_AFFIXES := ["barrage"]   # from floor 3 (difficulty 10): a ring of slow shots
const BOSSES := ["brute_king", "hive_mother", "storm_warden", "pyre_lord", "void_herald"]


## Kind names for one spawn group: 3..9 enemies, more with difficulty and players.
static func group(diff: int, floor_number: int, players: int) -> Array:
    var count := clampi(3 + diff / 4 + maxi(0, players - 1) + (1 if floor_number >= 4 else 0), 3, 9)
    var weights := {}
    for kind in KINDS.keys():
        var row: Array = KINDS[kind]
        if floor_number < int(row[0]):
            continue
        var w := maxf(0.5, float(row[1]) + float(row[2]) * float(diff))
        if floor_number >= 4 and HARD.has(kind):
            w *= 1.3
        weights[kind] = w
    var out: Array = []
    var shamans := 0
    var wardens := 0
    var max_wardens := 2 if floor_number >= 5 else 1
    var guard := 0
    while out.size() < count and guard < 50:
        guard += 1
        var kind := _pick(weights)
        if kind == "shaman":
            if shamans >= 1:
                continue
            shamans += 1
        elif kind == "warden":
            if wardens >= max_wardens:
                continue
            wardens += 1
        if kind == "swarmer":
            # Swarmers come in packs.
            var pack := mini(3 + diff / 8, count - out.size())
            for i in maxi(1, pack):
                out.append("swarmer")
            continue
        out.append(kind)
    while out.size() < 3:
        out.append("grunt")
    return out


static func _pick(weights: Dictionary) -> String:
    var total := 0.0
    for k in weights.keys():
        total += float(weights[k])
    var roll := randf() * total
    for k in weights.keys():
        roll -= float(weights[k])
        if roll <= 0.0:
            return String(k)
    return "grunt"


## One affix for an elite, or none on early difficulty.
static func elite_affix(diff: int) -> String:
    if diff < 6:
        return ""
    var pool: Array = AFFIXES.duplicate()
    if diff >= 10 and not Main.old_balance:
        pool.append_array(DEEP_AFFIXES)
        pool.append_array(DEEP_AFFIXES)   # weighted: the one that pushes you around
    return pool[randi() % pool.size()]


## The boss for a floor; past floor five the cycle repeats.
static func boss_for(floor_number: int) -> String:
    return BOSSES[posmod(maxi(1, floor_number) - 1, BOSSES.size())]


static func elite_count(diff: int) -> int:
    if diff >= 16:
        return 3
    if diff >= 8:
        return 2
    return 1
