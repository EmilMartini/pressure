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
    # Spitters and chargers are key threats now (KEY below), on their own budget.
    "bomber": [2, 1.5, 0.12],
    "splitter": [3, 1.5, 0.15],
    "shaman": [3, 0.6, 0.05],
    "warden": [3, 0.5, 0.07],
    "wisp": [4, 2.0, 0.15],
}

## Kinds that are not easy fodder: weighted up from floor 4.
const HARD := ["brute", "spitter", "charger", "bomber", "splitter", "shaman", "warden", "wisp"]

## Key threats (Core loop reset, section 8): the few dangerous enemies in a room that you
## must prioritise and dodge, on their own budget beside the crowd. Kind -> [first floor,
## first arena on that floor (0-based), weight]. Floor 1 stays gentle: lobbers and chargers
## only from its third arena. Room refills them on their own timer (Room._tick_keys).
const KEY := {
    "spitter": [1, 0, 1.0],
    "lobber": [1, 2, 1.1],
    "charger": [1, 2, 0.9],
}
## Key threats alive at once (elites count against it): floor 1 one, then two from its
## third arena; floors 2 and 3 two to three; floors 4 and 5 three to four.
static func key_budget(floor_number: int, arena_i: int) -> int:
    match floor_number:
        1:
            return 1 if arena_i < 2 else 2
        2:
            return 2 if arena_i < 2 else 3
        3:
            return 3
        4:
            return 3 if arena_i < 2 else 4
    return 4


## One key threat kind for an arena, or "" when none is open yet.
static func key_kind(floor_number: int, arena_i: int) -> String:
    var weights := {}
    for kind in KEY.keys():
        var row: Array = KEY[kind]
        if floor_number < int(row[0]) or (floor_number == int(row[0]) and arena_i < int(row[1])):
            continue
        weights[kind] = float(row[2])
    if weights.is_empty():
        return ""
    return _pick(weights)


const AFFIXES := ["regenerating", "hasted", "trail", "volatile"]
const DEEP_AFFIXES := ["barrage"]   # from floor 3 (difficulty 10): a ring of slow shots
## Zoning elites (section 8): the Sower from floor 2, the Mortar and the Tether from floor 3.
const ZONE_AFFIXES := { "sower": 2, "mortar": 3, "tether": 3 }
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
static func elite_affix(diff: int, floor_number: int = 0) -> String:
    if diff < 6:
        return ""
    var pool: Array = AFFIXES.duplicate()
    if diff >= 10 and not Main.old_balance:
        pool.append_array(DEEP_AFFIXES)
        pool.append_array(DEEP_AFFIXES)   # weighted: the one that pushes you around
    if not Main.old_balance:
        # Zoning affixes, each weighted double: they are what makes an elite move you.
        for a in ZONE_AFFIXES.keys():
            if floor_number >= int(ZONE_AFFIXES[a]):
                pool.append(a)
                pool.append(a)
    return pool[randi() % pool.size()]


## The boss for a floor; past floor five the cycle repeats.
static func boss_for(floor_number: int) -> String:
    return BOSSES[posmod(maxi(1, floor_number) - 1, BOSSES.size())]


static func elite_count(diff: int, floor_number: int = 0) -> int:
    if floor_number > 0 and not Main.old_balance:
        # Core loop reset 8: elites are key threats inside the floor's budget (2 to 3 alive on
        # floors 2 and 3, 3 to 4 on floors 4 and 5); two elite timers a wave.
        return 1 if floor_number <= 3 else 2
    if diff >= 16:
        return 3
    if diff >= 8:
        return 2
    return 1
