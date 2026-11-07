class_name Room
extends Node2D
## One room of the dungeon, rebuilt from its RoomData every time the party enters.
## Owns walls, doors, pedestals, the enemies and pickups inside, and the fight logic
## for arena waves, challenges and the boss. Its size comes from RoomData (three classes);
## its interior (walls, chasms, pools, slicks, ice, grass, a secret alcove) from
## RoomLayouts, laid on a 20 px nav grid that spawns, shots, sight lines, enemy pathing
## (a flow field toward the party) and the bot's routes read. A hidden puzzle, if the
## room has one, is a Secrets child.

signal door_entered(dir: Vector2i)

const SIZE := Vector2(1120, 720)   # the normal size; RoomData.room_size() picks per room
const WALL := 60.0
const GAP := 150.0
const NAV := RoomLayouts.CELL       # navigation / layout grid
const WADE := 0.6                   # speed in deep water
## The room the party is in (Projectile, Player, Enemy read its walls and paths).
static var here: Room = null
## Kinds that leave blood on the floor when they die.
const BLOODY_KINDS := ["grunt", "runner", "brute", "swarmer", "spitter", "charger", "splitter", "shaman", "elite", "boss"]

var data: RoomData
var main: Main
var room_size := SIZE
var rect := Rect2(-SIZE / 2.0, SIZE)
var enemies: Node2D
var pickups: Node2D
var materials: Materials            # floor material layer (oil, water, fire, gas...)
var doors: Dictionary = {}          # dir -> Door
var pedestals: Array[Pedestal] = []

var active := false                 # a fight is running
var wave_time_left := 0.0
var wave_duration := 0.0
var boss: Enemy = null
var low_hp := 1.0                   # bots: lowest health fraction of player 1 during this fight
## Spoils (wave-end payout): elites that drop loot during an arena wave bank it here instead
## of leaving a pedestal mid-fight; the wave's end lays everything out as one pick.
var banked: Array = []              # item offers banked by elites this wave
var cleared_at := -1.0              # main._clock when the fight ended (bot dwell logs)
var spoils_shown := 0               # offers in the wave-end choice (telemetry)
const SPOILS_MAX := 4               # cards in the wave-end choice; banked loot past it is salvaged
const SALVAGE_RATE := 0.3           # salvaged loot pays this share of its shop price in scrap

var _elites_alive := 0
var _spawn_timer := 0.0
var _elite_timer := INF
var _elite_timer2 := INF
var _add_timer := 0.0
var _add_time_left := 0.0
var _dealt0 := 0.0                  # Enemy.dealt_total when the arena wave began
var _boss_secs := 0.0               # game seconds since the boss rose
var _boss_p2 := -1.0                # game seconds when it reached phase two

## Floors 2+: the boss is sized to what the party's build actually deals. Its health is at
## least BOSS_DPS_SECS seconds of the party's measured arena output (damage per second of
## the floor's last arenas, every tier and DoT included), never under the old formula and
## at most BOSS_HP_MAX_MULT times it. Floor 1 keeps the formula alone.
const BOSS_DPS_SECS := 30.0
const BOSS_HP_MAX_MULT := 9.0
## Floors 2+: the boss rallies at two thirds and one third of its health. A rally guard holds
## RALLY_SECS (it breaks early when its adds die) and calls RALLY_GROUPS spawn groups; the
## boss room also keeps BOSS_CROWD of the arena crowd alive.
const RALLY_AT := [0.66, 0.33]
const RALLY_SECS := 8.0
const RALLY_GROUPS := 3
const BOSS_CROWD := 0.4

# Layout: interior walls, chasms and terrain on a NAV grid (see RoomLayouts).
var layout_name := "open"
var nav_w := 0
var nav_h := 0
var cells := PackedByteArray()
var terrain := PackedByteArray()
var has_walls := false       # interior walls: they stop shots and sight lines
var has_blockers := false    # anything walkers must path around
var secrets: Secrets = null
var reserved: Array = []     # [pos, radius]: spots puzzle pieces hold
var _keep: Array = []        # [pos, radius]: spots the layout keeps open
var _walls_body: StaticBody2D
var _deep_rects: Array[Rect2] = []
var _deep_idx := PackedInt32Array()   # Materials cells of the deep pools
var _deep_cursor := 0
var _deep_t := 0.0
var _flow := PackedInt32Array()
var _flow_t := 0.0
var _goal_cache: Dictionary = {}   # goal cell -> [msec, PackedInt32Array]
var _alcove_inner := Rect2()
var _styles := PackedByteArray()     # RoomLayouts S_* per cell (rubble edges are softer)
var theme := "crypt"                 # Themes key for this floor (the look and the ambience)
var ambience: Ambience = null


func _init(p_data: RoomData, p_main: Main) -> void:
    data = p_data
    main = p_main
    name = "Room"
    room_size = data.room_size()
    rect = Rect2(-room_size / 2.0, room_size)


func _enter_tree() -> void:
    here = self


func _exit_tree() -> void:
    if here == self:
        here = null


func _ready() -> void:
    Telemetry.room_enter(self)
    theme = String(Regions.get_region(main.region_id)["theme"]) if main != null else "crypt"
    Themes.current = theme
    enemies = Node2D.new()
    enemies.name = "Enemies"
    add_child(enemies)
    pickups = Node2D.new()
    pickups.name = "Pickups"
    add_child(pickups)
    _build_floor()
    materials = Materials.new(rect)   # z -1: over floor and decals, under bodies
    add_child(materials)
    _build_walls()
    _build_doors()
    _build_pedestals()
    _build_layout()     # interior walls, chasms, pools, slicks, ice, grass; the nav grid
    if data.secret != "":
        secrets = Secrets.new(self)
        add_child(secrets)
    Props.dress(self)   # crates, barrels, fountains, braziers... that react to every element
    ambience = Ambience.new(self, theme)
    _dress_theme()      # wall decor, lights and the floor's own extras (moss, ice, lava)
    add_child(ambience)
    Crisp.attach(self, _draw_crisp)

    data.visited = true
    data.discovered = true
    for d in data.doors.keys():
        if data.doors[d]["obstacle"] == "":
            main.rooms[data.doors[d]["to"]].discovered = true
    if data.loose_scrap > 0:
        _drop_scrap(Vector2(0, 80), data.loose_scrap, 8)
        data.loose_scrap = 0
    if data.is_safe():
        data.cleared = true
    if data.type == RoomData.Type.START and main.floor_number == 1 and data.stock.is_empty():
        for pl in main.players:
            if pl.guns.is_empty():
                add_gun_choice()
    if not data.cleared:
        match data.type:
            RoomData.Type.ARENA:
                _begin_arena()
            RoomData.Type.BOSS:
                _begin_boss()
            # A challenge waits for someone to touch the sigil.
    _apply_doors()


func _process(delta: float) -> void:
    _handle_interact()
    _tick_layout(delta)
    if not active:
        return
    if main.autotest and not main.players.is_empty():
        var pl0: Player = main.players[0]
        low_hp = minf(low_hp, pl0.hp / maxf(1.0, pl0.max_hp))
    match data.type:
        RoomData.Type.ARENA:
            _tick_arena(delta)
        RoomData.Type.CHALLENGE:
            _tick_challenge(delta)
        RoomData.Type.BOSS:
            _tick_boss(delta)


# --- Fights ------------------------------------------------------------------


func _begin_arena() -> void:
    data.started = true
    active = true
    var diff := main.difficulty()
    wave_duration = clampf(18.0 + 2.2 * float(diff), 18.0, 60.0)
    wave_time_left = wave_duration
    _spawn_timer = 0.8
    _elite_timer = wave_duration * 0.45 if diff >= 2 else INF
    _elite_timer2 = wave_duration * 0.78 if main.floor_number >= 2 else INF
    _dealt0 = Enemy.dealt_total
    main.announce("Survive %d seconds" % int(wave_duration))
    Sfx.play("wave_start")


func _tick_arena(delta: float) -> void:
    var diff := main.difficulty()
    Music.set_intensity(clampf(float(enemies.get_child_count()) / 6.0, 0.15, 1.0))
    var before := ceili(wave_time_left)
    wave_time_left -= delta
    if wave_time_left <= 3.0 and ceili(wave_time_left) != before:
        Sfx.play("tick", 0.0, 0.0)
    _spawn_timer -= delta
    _elite_timer -= delta
    if _spawn_timer <= 0.0:
        # A crowd target, not a spawn rate: the room keeps about crowd_target() enemies
        # alive and refills as fast as the party clears them. A starter faces a handful;
        # a six-gun build that melts everything gets a constant horde (many enemies, not
        # tankier ones). The first seconds of a wave ramp up from a third of the target.
        var ramp := clampf((wave_duration - wave_time_left) / 8.0, 0.35, 1.0)
        var target := int(round(float(crowd_target(diff)) * ramp))
        var alive := enemies.get_child_count()
        if alive < target:
            _spawn_group()
            # Far below target: refill quickly; close to it: trickle.
            _spawn_timer = 0.3 if alive < target * 0.6 else 0.7
        else:
            _spawn_timer = 0.5
    if _elite_timer <= 0.0:
        _elite_timer = INF
        _spawn_elite(SpawnTable.elite_count(diff))
    _elite_timer2 -= delta
    if _elite_timer2 <= 0.0:
        _elite_timer2 = INF
        _spawn_elite(SpawnTable.elite_count(diff))
    if wave_time_left <= 0.0:
        main.note_arena_dps((Enemy.dealt_total - _dealt0) / maxf(1.0, wave_duration))
        Telemetry.wave_end(self, _floor_pedestals(), _floor_scrap())
        _finish_fight(6)
        _arena_reward()


## Every arena pays out once, at the wave's end, as one clear choice (Brotato's crates
## opened between waves, Isaac's pedestals): a free gun and a free item, plus one card for
## each elite that dropped loot during the wave (banked, never a pedestal mid-fight), up to
## SPOILS_MAX. Take one; the rest are salvaged for scrap, and so is the whole row if the
## party walks out without choosing (salvage_spoils). Power still grows with every room
## whether or not the shop turns up.
func _arena_reward() -> void:
    var owned := 0
    for pl in main.players:
        owned += pl.guns.size()
    var cards: Array = []
    # Duplicates are welcome (a copy merges into the carried gun, one tier up); only guns
    # maxed out everywhere are skipped.
    var gun_id := Drops.roll_gun(main.players, _maxed_gun_ids())
    if gun_id != "":
        cards.append(FloorGen.offer("gun", gun_id, 0))
    # A naked start needs guns first: until the party carries three, both cards are guns.
    var few_guns := owned < 3 * main.players.size()
    if few_guns:
        var other := Drops.roll_gun(main.players, _maxed_gun_ids() + [gun_id])
        if other != "":
            cards.append(FloorGen.offer("gun", other, 0))
    else:
        cards.append(Items.offer(Drops.roll_item(main.difficulty(), Items.Rarity.COMMON, [], main.party_luck(), "arena", main.players), 0))
    var extra := 0
    for o in banked:
        if cards.size() < SPOILS_MAX:
            cards.append(o)
        else:
            extra += _salvage_value(o)
    var n_banked := banked.size()
    banked = []
    for o in cards:
        o["spoils"] = true
        o.erase("pos")
        data.stock.append(o)
    spoils_shown = cards.size()
    Telemetry.spoils_offer(self, cards, n_banked)
    _build_pedestals()
    if extra > 0:
        main.add_scrap(extra)
        main.announce("Spoils: choose 1 of %d   (+%d scrap salvaged)" % [cards.size(), extra])
    else:
        main.announce("Spoils: choose 1 of %d" % cards.size())


## Scrap a piece of loot is worth when salvaged.
func _salvage_value(o: Dictionary) -> int:
    match String(o.get("kind", "")):
        "item":
            return maxi(1, int(roundf(float(Items.price(Items.get_item(o["id"]), main.floor_number * 4)) * SALVAGE_RATE)))
        "gun":
            return maxi(1, int(roundf(float(FloorGen.gun_price(Guns.make(o["id"]), main.floor_number)) * SALVAGE_RATE)))
    return 0


## Salvage every spoils card still standing (the rest of the row after a pick, or all of
## it when the party leaves): scrap for each, said out loud, never lost silently.
func salvage_spoils(reason: String) -> void:
    var total := 0
    var ids: Array = []
    for o in data.stock:
        if o.get("spoils", false) and not o["taken"]:
            o["taken"] = true
            total += _salvage_value(o)
            ids.append(String(o["id"]))
    if ids.is_empty():
        return
    main.add_scrap(total)
    Telemetry.salvage(ids, total, reason)
    var msg := "Salvaged %d spoils: +%d scrap" % [ids.size(), total]
    if reason == "left":
        msg = "Left %d spoils behind: salvaged for +%d scrap" % [ids.size(), total]
    main.announce(msg)
    for pl in main.players:
        if pl.alive:
            pl.say("+%d scrap" % total)
            break
    _build_pedestals()


## Item pedestals standing on the floor right now (offers not yet taken).
func _floor_pedestals() -> int:
    var n := 0
    for ped in pedestals:
        if is_instance_valid(ped) and not ped.empty() and ped.kind() in ["gun", "item"]:
            n += 1
    return n


## Scrap pieces lying on the floor right now.
func _floor_scrap() -> int:
    var n := 0
    for c in pickups.get_children():
        if c is Scrap:
            n += 1
    return n


## Gun ids the party carries only at max tier (no point offering another copy).
func _maxed_gun_ids() -> Array:
    var below: Dictionary = {}
    var maxed: Array = []
    for pl in main.players:
        for g in pl.guns:
            var gun: Gun = g
            if gun.tier < Gun.MAX_TIER:
                below[gun.data.id] = true
            elif not maxed.has(gun.data.id):
                maxed.append(gun.data.id)
    return maxed.filter(func(id): return not below.has(id))


func begin_challenge() -> void:
    data.started = true
    active = true
    _elites_alive = 2
    for i in 2:
        _spawn_elite(1)
    _add_time_left = 25.0
    _add_timer = 0.0
    main.announce("Challenge: kill both elites")
    _apply_doors()


func _tick_challenge(delta: float) -> void:
    _add_time_left -= delta
    _add_timer -= delta
    if _add_time_left > 0.0 and _add_timer <= 0.0:
        _add_timer = 1.6
        _spawn_group()
    if _elites_alive <= 0:
        var picked: Array = []
        for i in 3:
            var id := Drops.roll_item(main.difficulty() + 2, Items.Rarity.UNCOMMON, picked, main.party_luck(), "challenge", main.players)
            picked.append(id)
            data.stock.append(Items.offer(id, 0))
        _finish_fight(20)
        _build_pedestals()


func _begin_boss() -> void:
    data.started = true
    active = true
    # The boss rises on the far side of the room from wherever the party came in, never
    # on top of a player who just stepped through the door.
    var party := Vector2.ZERO
    var n := 0
    for pl in main.players:
        if pl.alive:
            party += pl.global_position - global_position
            n += 1
    if n > 0:
        party /= float(n)
    var away := -party.normalized() if party.length() > 10.0 else Vector2.DOWN
    var boss_pos := away * 230.0
    for pl in main.players:
        if pl.alive and (pl.global_position - global_position).distance_to(boss_pos) < 320.0:
            boss_pos = away * 300.0
    boss_pos = nearest_open(boss_pos, 40.0)
    boss = _spawn_enemy("boss", boss_pos)
    boss.set_boss(String(Regions.get_region(main.region_id)["boss_kind"]))
    if boss.boss_kind == "pyre_lord":
        # The arena is a weapon (design section 6): quench vats in the four corners.
        for off in [Vector2(-280, -170), Vector2(280, -170), Vector2(-280, 170), Vector2(280, 170)]:
            var vat := Prop.new("quench_vat")
            vat.room = self
            vat.position = nearest_open(off, 40.0)
            add_child(vat)
    if main.floor_number >= 2 and not Main.old_balance:
        var want := BOSS_DPS_SECS * main.floor_arena_dps() * BossBody.hp_share(boss.boss_kind)
        boss.max_hp = clampf(want, boss.max_hp, boss.max_hp * BOSS_HP_MAX_MULT)
        boss.hp = boss.max_hp
        boss.rally_secs = RALLY_SECS
        boss.rally_at = RALLY_AT.duplicate()
        boss.rallied.connect(_on_boss_rallied)
    elif not Main.old_balance:
        boss.max_hp *= BossBody.floor1_mult(boss.boss_kind)
        boss.hp = boss.max_hp
    Telemetry.boss_start(boss)
    var pairs := Elements.available_reactions(main.party_elements())
    var hits := 5 + main.difficulty() / 3
    if not pairs.is_empty():
        var first: Vector2i = pairs.pick_random()
        boss.set_shield(first, hits)
        var others: Array = pairs.filter(func(p): return p != first)
        boss.reshield_weakness = others.pick_random() if not others.is_empty() else first
        boss.reshield_hits = hits
    _add_timer = 5.0
    main.announce("BOSS: crack the shield with its reaction")
    Sfx.play("boss")
    Music.play("boss", 1.0)
    Music.boss_phase(1)
    main.shake(10.0)


func _tick_boss(delta: float) -> void:
    var was := _boss_secs
    _boss_secs += delta
    if main.autotest and OS.get_cmdline_user_args().has("--boss-shot") and boss != null and is_instance_valid(boss):
        # Readability shots: the name card, then the fight every few seconds (real window).
        for at in [1.5, 6.0, 12.0, 18.0, 24.0, 30.0, 38.0]:
            if was < at and _boss_secs >= at:
                main._screenshot("res://autotest/boss_%s_%02d.png" % [boss.boss_kind, int(at)])
    if _boss_p2 < 0.0 and boss != null and is_instance_valid(boss) and boss.hp <= boss.max_hp * 0.5:
        _boss_p2 = _boss_secs
    _add_timer -= delta
    if _add_timer <= 0.0:
        _add_timer = maxf(4.0, 8.0 - 0.3 * float(main.difficulty()))
        _spawn_group()
    if main.floor_number >= 2 and not Main.old_balance and boss != null and is_instance_valid(boss):
        # Floors 2+: the boss room keeps a share of the arena crowd alive, so a build that
        # melts hordes meets one here too, not a lone target.
        _spawn_timer -= delta
        if _spawn_timer <= 0.0:
            _spawn_timer = 0.7
            if enemies.get_child_count() < int(float(crowd_target(main.difficulty())) * BOSS_CROWD):
                _spawn_group()
    if boss == null or not is_instance_valid(boss):
        boss = null
        # The route choice: one stairs door per built region one edge down (design
        # section 4), or a single way out at the bottom.
        var ways: Array = Regions.next_options(main.region_id) if main.floor_number < Main.FLOORS else []
        if ways.is_empty():
            data.stock.append(FloorGen.offer("stairs", "", 0))
        for id in ways:
            data.stock.append(FloorGen.offer("stairs", String(id), 0))
        _finish_fight(30)
        _build_pedestals()
        Music.boss_phase(0)
        Music.play("run", 2.0)


## A rally on floors 2+: the boss calls RALLY_GROUPS groups and holds its guard while they
## live (Enemy.rally_secs).
func _on_boss_rallied(b: Enemy) -> void:
    if not active or not is_instance_valid(b) or b.hp <= 0.0:
        return
    var adds: Array = []
    for i in RALLY_GROUPS:
        _spawn_group(adds)
    b.set_ward_adds(adds)
    main.announce("The boss rallies: kill its guard")
    Sfx.play("boss_phase")


func _finish_fight(bonus_scrap: int) -> void:
    active = false
    cleared_at = main._clock
    Telemetry.room_clear(self)
    Music.set_intensity(0.2)
    data.cleared = true
    for e in enemies.get_children():
        e.vanish()
    for sh in get_tree().get_nodes_in_group("enemy_projectiles"):
        sh.queue_free()
    _drop_scrap(Vector2.ZERO, bonus_scrap, 6)
    # Everything left on the floor flies to the party: no walking the room for scrap.
    for c in pickups.get_children():
        if c is Scrap:
            c.vacuum = true
    main.on_room_cleared(self)
    Sfx.play("cleared")
    for pl in main.players:
        if pl.alive:
            Items.fire(pl, "room_clear", { "pos": pl.global_position })
    _apply_doors()


# --- Spawning ----------------------------------------------------------------


## How many enemies an arena keeps alive: grows with difficulty and with the guns and
## elements the party fields (a full build covers six targets and locks groups down).
func crowd_target(diff: int) -> int:
    var base := 6.0 + 1.1 * float(diff)
    var guns := 0
    for pl in main.players:
        guns += (pl as Player).guns.size()
    var build := 1.0 + 0.22 * float(maxi(0, guns - 1)) + 0.12 * float(maxi(0, party_elements_count() - 1))
    return clampi(int(base * build), 5, 130)


## Enemy hit points per second the arena feeds the party at a difficulty. Sized for a
## party with six gun slots and tiers; party_power() scales enemy hp on top of it.
static func hp_inflow_target(diff: int) -> float:
    var d := float(diff)
    return 22.0 + 11.0 * d + 0.6 * maxf(0.0, d - 6.0) * maxf(0.0, d - 6.0)   # gentle first rooms, steep late


## Party gun dps a difficulty expects, the yardstick for party_power().
static func expected_dps(diff: int) -> float:
    return 45.0 + 22.0 * float(diff)


## Brotato-style soft scaling: carried gun dps (budget dps x tier) against what the
## difficulty expects, clamped to 0.8..2.2. Enemy max hp is multiplied by its sqrt.
func party_power() -> float:
    var total := 0.0
    for pl in main.players:
        for g in pl.guns:
            var gun: Gun = g
            total += gun.data.dps() * gun.tier_mult()
    # Every extra element adds reaction pairs that hit whole groups and lock them down;
    # gun DPS alone undercounts that by a lot (telemetry: reactions were 41% of damage).
    var ratio := total / expected_dps(main.difficulty())
    ratio *= 1.0 + 0.22 * float(maxi(0, party_elements_count() - 1))
    return clampf(ratio, 0.8, 3.5)


func party_elements_count() -> int:
    var seen := {}
    for pl in main.players:
        for g in pl.guns:
            seen[(g as Gun).data.element] = true
    return seen.size()


## Bodies per second scale with how many guns the party fields: six guns cover six
## targets at once, so the room needs more of them to press a full build.
func party_guns_factor() -> float:
    var n := 0
    for pl in main.players:
        n += (pl as Player).guns.size()
    return 1.0 + 0.14 * float(maxi(0, n - 1))


## Late floors hit harder: contact, shot and blast damage, summons included. Floor 1 is x1.0
## (tuned on its own); floors 2 to 5 were x1.0, 1.15, 1.3, 1.5 (blasts flat) and are now
## FLOOR_DAMAGE (GDD "Late-floor balance": with Leech capped, a replay of run 4487a37a's own
## hits puts its low point on floors 2 to 5 near 51, 62, 42 and 28%).
const FLOOR_DAMAGE := [1.0, 1.0, 1.15, 1.55, 1.55, 1.55]


static func floor_damage_mult(floor_number: int) -> float:
    if Main.old_balance:
        return 1.0 + 0.15 * float(maxi(0, floor_number - 2)) + (0.05 if floor_number >= 5 else 0.0)
    return float(FLOOR_DAMAGE[clampi(floor_number, 0, FLOOR_DAMAGE.size() - 1)]) * (1.0 + 0.1 * float(maxi(0, floor_number - 5)))


func _spawn_group(out: Array = []) -> float:
    var diff := main.difficulty()
    var total_hp := 0.0
    var ring := randf() < 0.55 and main.floor_number >= 1
    var anchor: Player = null
    if ring:
        var alive: Array = main.players.filter(func(q): return q.alive)
        if not alive.is_empty():
            anchor = alive.pick_random()
    var group_i := 0
    var group: Array = SpawnTable.group(diff, main.floor_number, main.players.size())
    for type in group:
        var pos := _spawn_point()
        if anchor != null:
            # Brotato spawns anywhere on screen: here half the groups close in from a ring
            # around a player, so standing in the middle is not a safe corner.
            var ang := TAU * float(group_i) / float(maxi(1, group.size())) + randf_range(-0.3, 0.3)
            var ringp := (anchor.global_position - global_position) + Vector2.RIGHT.rotated(ang) * randf_range(190.0, 300.0)
            var inner := rect.grow(-60.0)
            pos = Vector2(clampf(ringp.x, inner.position.x, inner.end.x), clampf(ringp.y, inner.position.y, inner.end.y))
        group_i += 1
        # Clamping pulls a ring point near a wall towards a player standing there: the
        # distance is checked after it (never on top of anyone, Brotato's rule).
        if not is_open(pos + global_position, 22.0) or not spawn_clear(pos + global_position):
            pos = _spawn_point()
        var e := _spawn_enemy(type, pos)
        e.emerge = Enemy.EMERGE_SECS
        total_hp += e.max_hp
        out.append(e)
        if e.immune_to == Element.Kind.NONE and diff >= 2 and randf() < minf(0.5, 0.05 * float(diff)):
            # Never immune to the party's only element: that would be unkillable.
            var kinds := main.party_elements()
            if kinds.size() >= 2:
                e.immune_to = kinds.pick_random()
    return total_hp


func _spawn_enemy(type: String, pos: Vector2) -> Enemy:
    var e := Enemy.new()
    e.configure(type, main.difficulty())
    # A stronger build meets more enemies, not tankier ones: health grows at most 25%;
    # the rest of the party's power goes into the bodies budget (party_guns_factor).
    e.max_hp *= clampf(1.0 + 0.12 * (party_power() - 1.0), 0.9, 1.25)
    e.hp = e.max_hp
    e.damage_mult = floor_damage_mult(main.floor_number)
    e.contact_damage *= e.damage_mult
    e.position = pos
    e.died.connect(_on_enemy_died)
    enemies.add_child(e)
    return e


func _spawn_elite(count: int) -> void:
    var diff := main.difficulty()
    var hits := 2 + diff / 4
    var pairs := Elements.available_reactions(main.party_elements())
    for i in count:
        var e := _spawn_enemy("elite", _spawn_point())
        e.emerge = Enemy.EMERGE_SECS
        e.set_affix(SpawnTable.elite_affix(diff))
        if not pairs.is_empty():
            e.set_shield(pairs.pick_random(), hits)
        Telemetry.elite_spawned(e)
        Elements.reaction_fired.emit("ELITE", e.global_position, Color(1.0, 0.85, 0.3))


## No spawn lands closer than this to a living player (checked after any clamping).
const SPAWN_MIN := 170.0


## True when no living player stands within `min_d` of `gpos` (global).
func spawn_clear(gpos: Vector2, min_d: float = SPAWN_MIN) -> bool:
    for pl in main.players:
        if pl.alive and pl.global_position.distance_to(gpos) < min_d:
            return false
    return true


## A spawn point in room space: open floor on the edge 260 px from every player, else open
## floor inside 220 px away, else the farthest open point tried (never the nearest edge).
func _spawn_point() -> Vector2:
    var best := Vector2.ZERO
    var best_d := -1.0
    for attempt in 16:
        var p := _perimeter_point()
        if not is_open(p + global_position, 22.0):
            continue
        var d := _party_dist(p + global_position)
        if d >= 260.0:
            return p
        if d > best_d:
            best_d = d
            best = p
    # A layout can wall off most of the edge: any open floor away from the party.
    var inner := rect.grow(-60.0)
    for attempt in 30:
        var q := Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
        if not is_open(q + global_position, 22.0):
            continue
        var d := _party_dist(q + global_position)
        if d >= 220.0:
            return q
        if d > best_d:
            best_d = d
            best = q
    if best_d >= 0.0:
        return best
    return nearest_open(_perimeter_point() + global_position, 22.0) - global_position


## Distance from `gpos` (global) to the nearest living player (INF with none).
func _party_dist(gpos: Vector2) -> float:
    var d := INF
    for pl in main.players:
        if pl.alive:
            d = minf(d, pl.global_position.distance_to(gpos))
    return d


## A telegraphed spawn a player walked onto moves here (global): see Enemy.EMERGE_SECS.
func respawn_point() -> Vector2:
    return _spawn_point() + global_position


func _perimeter_point() -> Vector2:
    var inner := rect.grow(-50.0)
    match randi() % 4:
        0:
            return Vector2(randf_range(inner.position.x, inner.end.x), inner.position.y)
        1:
            return Vector2(randf_range(inner.position.x, inner.end.x), inner.end.y)
        2:
            return Vector2(inner.position.x, randf_range(inner.position.y, inner.end.y))
    return Vector2(inner.end.x, randf_range(inner.position.y, inner.end.y))


func _on_enemy_died(e: Enemy) -> void:
    main.total_kills += 1
    Telemetry.kill(e)
    Progress.add("kills")
    if e.kind_name == "boss":
        Progress.add("bosses")
        if main.autotest:
            var pl: Player = main.players[0]
            print("[BOSS] floor=%d kind=%s secs=%.1f phase2=%.1f max_hp=%.0f arena_dps=%.0f player_hp=%.0f/%.0f low=%.2f" % [
                main.floor_number, e.boss_kind, _boss_secs, _boss_p2, e.max_hp, main.floor_arena_dps(), pl.hp, pl.max_hp, low_hp])
            if e.body != null:
                print("[BOSS-BODY] kind=%s secs=%.1f max_hp=%.0f %s" % [e.boss_kind, _boss_secs, e.max_hp, e.body.summary()])
            if OS.get_cmdline_user_args().has("--boss-only"):
                main._print_stats("END")
                main.get_tree().quit()
        if e.boss_kind != "":
            Progress.add("boss:" + e.boss_kind)   # the Shrine's first-kill bounties
    elif e.is_elite:
        Progress.add("elites")
    if e.last_hit_by != null and is_instance_valid(e.last_hit_by):
        e.last_hit_by.gain_xp(2.0 + 2.0 * float(e.scrap_value))
    _drop_scrap(e.global_position, e.scrap_value, mini(e.scrap_value, 5))
    if materials != null:
        if e.kind_name in BLOODY_KINDS:
            materials.stamp(Element.Kind.BLOOD, e.global_position, e.radius * 0.8, 90)
        if e.has_state(Element.Kind.OIL):
            materials.stamp(Element.Kind.OIL, e.global_position, e.radius * 1.5, 120)
        if e.burn_time > 0.0:
            materials.ignite(e.global_position, e.radius * 1.5)
    if e.is_elite and data.type == RoomData.Type.CHALLENGE:
        _elites_alive -= 1
    # Loot: bosses always drop rare or better, elites drop sometimes.
    var inner := rect.grow(-90.0)
    var drop_pos := nearest_open(Vector2(clampf(e.global_position.x, inner.position.x, inner.end.x), clampf(e.global_position.y, inner.position.y, inner.end.y)), 26.0)
    if e.kind_name == "boss":
        data.stock.append(Items.offer(Drops.roll_item(main.difficulty() + 4, Items.Rarity.RARE, [], main.party_luck(), "boss", main.players), 0, Vector2(0, 150)))
        _build_pedestals()
    elif e.is_elite and randf() < 0.55:
        var loot := Items.offer(Drops.roll_item(main.difficulty(), Items.Rarity.COMMON, [], main.party_luck(), "", main.players), 0)
        if data.type == RoomData.Type.ARENA and active:
            # Banked for the wave's end (one choice there), not a pedestal mid-fight.
            banked.append(loot)
            Elements.reaction_fired.emit("SPOILS +1", e.global_position, Color(1.0, 0.85, 0.3))
            Telemetry.event("spoils_banked", { "floor": main.floor_number, "id": String(loot["id"]) })
        else:
            loot["pos"] = drop_pos
            data.stock.append(loot)
            _build_pedestals()


func _drop_scrap(pos: Vector2, total: int, pieces: int) -> void:
    if total <= 0:
        return
    pieces = maxi(1, pieces)
    var each := total / pieces
    var rem := total - each * pieces
    for i in pieces:
        var s := Scrap.new(each + (1 if i < rem else 0), main)
        s.position = pos
        pickups.add_child(s)


func collect_all_scrap() -> void:
    for s in pickups.get_children():
        if s is Scrap:
            main.add_scrap(s.value)


# --- Doors and walls -------------------------------------------------------


func _build_doors() -> void:
    for d in data.doors.keys():
        var door := Door.new(d, GAP, WALL)
        door.position = Vector2(d) * (room_size / 2.0 + Vector2(WALL / 2.0, WALL / 2.0))
        add_child(door)
        doors[d] = door
        door.entered.connect(func(dir: Vector2i): door_entered.emit(dir))
        var ob: String = data.doors[d]["obstacle"]
        if ob == "secret":
            door.set_secret(_secret_method(d))
            door.obstacle_cleared.connect(_on_obstacle_cleared)
        elif ob != "":
            door.set_obstacle(ob)
            door.obstacle_cleared.connect(_on_obstacle_cleared)


## The method a hidden room's secret wall opens to: chosen the first time the party sees
## it, from what the party can make then (fire, ice + stone, acid, shock, water, a blast).
func _secret_method(d: Vector2i) -> String:
    var m := String(data.doors[d].get("secret", ""))
    if m == "":
        var rng := RandomNumberGenerator.new()
        rng.seed = data.layout_seed + 31337
        m = SecretWall.pick_method(main.party_elements(), rng)
        data.doors[d]["secret"] = m
    return m


func _on_obstacle_cleared(dir: Vector2i) -> void:
    var was_secret := String(data.doors[dir]["obstacle"]) == "secret"
    data.doors[dir]["obstacle"] = ""
    main.rooms[data.doors[dir]["to"]].discovered = true
    if was_secret:
        Telemetry.event("hidden_room_found", { "floor": main.floor_number })
        call_deferred("_add_door_cap", dir)
        _redraw_layout()
    _apply_doors()


func _apply_doors() -> void:
    var open := not active and (data.cleared or data.type == RoomData.Type.CHALLENGE)
    for d in doors.keys():
        var door: Door = doors[d]
        if door.state == Door.State.OBSTACLE:
            continue
        door.set_state(Door.State.OPEN if open else Door.State.LOCKED)


func door_world_position(dir: Vector2i) -> Vector2:
    return doors[dir].global_position


## Where the party appears when entering from a given side of this room.
func entry_position(side: Vector2i) -> Vector2:
    return Vector2(side) * (room_size / 2.0 - Vector2(90.0, 90.0))


func _build_walls() -> void:
    var body := StaticBody2D.new()
    body.name = "Walls"
    body.collision_layer = Player.LAYER_WALLS
    body.collision_mask = 0
    add_child(body)
    _walls_body = body
    var half := room_size / 2.0
    for d in FloorGen.DIRS:
        var has_door := data.doors.has(d)
        # A secret wall gets no cap behind it: the wall line stays flat, as if no door.
        var capped := has_door and String(data.doors[d]["obstacle"]) != "secret"
        if d.y != 0:
            var y := float(d.y) * (half.y + WALL / 2.0)
            if has_door:
                var seg := (room_size.x + 2.0 * WALL - GAP) / 2.0
                _wall(body, Vector2(-(GAP / 2.0 + seg / 2.0), y), Vector2(seg, WALL))
                _wall(body, Vector2(GAP / 2.0 + seg / 2.0, y), Vector2(seg, WALL))
                if capped:
                    _add_door_cap(d)
            else:
                _wall(body, Vector2(0, y), Vector2(room_size.x + 2.0 * WALL, WALL))
        else:
            var x := float(d.x) * (half.x + WALL / 2.0)
            if has_door:
                var seg := (room_size.y + 2.0 * WALL - GAP) / 2.0
                _wall(body, Vector2(x, -(GAP / 2.0 + seg / 2.0)), Vector2(WALL, seg))
                _wall(body, Vector2(x, GAP / 2.0 + seg / 2.0), Vector2(WALL, seg))
                if capped:
                    _add_door_cap(d)
            else:
                _wall(body, Vector2(x, 0), Vector2(WALL, room_size.y + 2.0 * WALL))
    _add_cracks()


## The block behind a doorway that keeps players from walking past the door trigger.
func _add_door_cap(d: Vector2i) -> void:
    if _walls_body == null or not is_instance_valid(_walls_body):
        return
    var half := room_size / 2.0
    if d.y != 0:
        _wall(_walls_body, Vector2(0, float(d.y) * (half.y + WALL * 1.5)), Vector2(GAP + WALL, WALL))
    else:
        _wall(_walls_body, Vector2(float(d.x) * (half.x + WALL * 1.5), 0), Vector2(WALL, GAP + WALL))


## Hairline cracks here and there in the walls, so a crack alone gives no secret away.
func _add_cracks() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = data.layout_seed + 77
    var half := room_size / 2.0
    var layer := CrackLayer.new()
    layer.name = "Cracks"
    layer.z_index = -1
    for k in rng.randi_range(3, 6):
        var side: Vector2i = FloorGen.DIRS[rng.randi() % 4]
        var span := (half.x if side.y != 0 else half.y) - 60.0
        var along := rng.randf_range(-span, span)
        if data.doors.has(side) and absf(along) < GAP:
            continue
        var c := Vector2(along, float(side.y) * (half.y + WALL / 2.0)) if side.y != 0 else Vector2(float(side.x) * (half.x + WALL / 2.0), along)
        var dir := Vector2(1, 0) if side.y != 0 else Vector2(0, 1)
        var pts := PackedVector2Array()
        var off := 0.0
        var n := rng.randi_range(4, 7)
        for i in n + 1:
            off = clampf(off + rng.randf_range(-3.0, 3.0), -14.0, 14.0)
            pts.append((c + dir * (float(i) / float(n) - 0.5) * rng.randf_range(50.0, 80.0) + dir.orthogonal() * off).round())
        layer.lines.append(pts)
    add_child(layer)


class CrackLayer extends Node2D:
    var lines: Array = []
    func _draw() -> void:
        for l in lines:
            draw_polyline(l, Color(0.09, 0.07, 0.08, 0.5), 1.0)


## A solid wall block: collision plus the theme's wall tiles, lined up with the world so
## neighbouring walls and secret walls join seamlessly. `tint` multiplies the theme tint
## (pillars a shade lighter).
func _wall(body: StaticBody2D, center: Vector2, size: Vector2, tint: Color = Color.WHITE) -> void:
    var shape := CollisionShape2D.new()
    var r := RectangleShape2D.new()
    r.size = size
    shape.shape = r
    shape.position = center
    body.add_child(shape)
    var bricks := Themes.wall_fill(Rect2(center - size / 2.0, size), _zoom(), tint, theme)
    bricks.z_index = -1
    add_child(bricks)


## The run camera's zoom (tiles are drawn one texel per screen pixel cell at it).
func _zoom() -> float:
    if main != null and "camera" in main and main.camera != null:
        return main.camera.zoom.x
    return 1.3


## Special rooms tint the theme's floor a little, so a shop reads warm and a boss red.
const FLOOR_TINTS := {
    RoomData.Type.SHOP: Color(1.22, 1.06, 0.84),
    RoomData.Type.TREASURE: Color(1.22, 1.12, 0.78),
    RoomData.Type.BOSS: Color(1.18, 0.72, 0.72),
    RoomData.Type.CHALLENGE: Color(1.06, 0.84, 1.18),
    RoomData.Type.HIDDEN: Color(0.80, 1.06, 1.06),
}


## A decorative sprite from the sheet, placed in room space.
func _prop(coord: Vector2i, pos: Vector2, scale: float, tint: Color, z: int = -1) -> Sprite2D:
    var s := Art.sprite(coord, scale, tint)
    s.position = pos
    s.z_index = z
    add_child(s)
    return s


## Dressing per room type, so a shop reads as a shop before you see a price.
func _dress_room() -> void:
    var half := room_size / 2.0
    match data.type:
        RoomData.Type.SHOP:
            # A counter along the back wall with a hooded keeper behind it, lanterns at the ends.
            for i in 7:
                _prop(Vector2i(16, 5), Vector2(-240.0 + float(i) * 80.0, -half.y + 110.0), 2.5, Color(0.45, 0.35, 0.25))
            _prop(Vector2i(26, 0), Vector2(0, -half.y + 70.0), 3.0, Color(0.75, 0.68, 0.6), 1)
            _prop(Vector2i(14, 10), Vector2(-300, -half.y + 80.0), 2.5, Color(1.0, 0.75, 0.3), 1)
            _prop(Vector2i(14, 10), Vector2(300, -half.y + 80.0), 2.5, Color(1.0, 0.75, 0.3), 1)
            for i in 4:
                _prop(Vector2i(3, 7), Vector2(-half.x + 60.0, -200.0 + float(i) * 120.0), 2.5, Color(0.5, 0.42, 0.35))
                _prop(Vector2i(3, 7), Vector2(half.x - 60.0, -200.0 + float(i) * 120.0), 2.5, Color(0.5, 0.42, 0.35))
        RoomData.Type.TREASURE:
            # The chest, sized by tier, on a dais with gold scattered around it.
            var tier := data.chest_tier
            _prop(Vector2i(9, 11), Vector2(0, -170.0), 3.5 + float(tier), Color(1.0, 0.8, 0.35), 1)
            for i in 8 + tier * 4:
                var a := randf() * TAU
                _prop(Vector2i(45, 16), Vector2(cos(a) * randf_range(90, 220), -170.0 + sin(a) * randf_range(50, 120)), 1.2, Color(0.9, 0.75, 0.3))
            for i in 2:
                _prop(Vector2i(13, 3), Vector2(-200.0 + float(i) * 400.0, -half.y + 90.0), 3.0, Color(0.55, 0.5, 0.45))
        RoomData.Type.BOSS:
            for i in 14:
                var d := _prop(Vector2i(38, 11), Vector2(randf_range(-half.x + 80, half.x - 80), randf_range(-half.y + 80, half.y - 80)), 2.0, Color(0.55, 0.3, 0.3))
                d.rotation = randf() * TAU
            for i in 2:
                _prop(Vector2i(13, 3), Vector2(-280.0 + float(i) * 560.0, -half.y + 90.0), 3.5, Color(0.45, 0.3, 0.3))
        RoomData.Type.CHALLENGE:
            # Weapon racks on the side walls.
            for i in 5:
                _prop(Vector2i(32 + i, 6), Vector2(-half.x + 50.0, -160.0 + float(i) * 80.0), 2.2, Color(0.7, 0.6, 0.8))
                _prop(Vector2i(37 + (i % 2), 7), Vector2(half.x - 50.0, -160.0 + float(i) * 80.0), 2.2, Color(0.7, 0.6, 0.8))
        RoomData.Type.HIDDEN:
            for i in 6:
                _prop(Vector2i(10, 7), Vector2(randf_range(-half.x + 100, half.x - 100), randf_range(-half.y + 100, half.y - 100)), 2.5, Color(0.5, 0.55, 0.5))
        RoomData.Type.START:
            for i in 2:
                _prop(Vector2i(14, 10), Vector2(-120.0 + float(i) * 240.0, -half.y + 70.0), 2.5, Color(1.0, 0.75, 0.3), 1)


## The theme's floor tiles, one variant per tile cell from a seed fixed per room, so the
## floor does not shuffle on re-entry.
func _build_floor() -> void:
    var floor_seed := (hash(data.pos) + main.floor_number * 7919) & 0xFFFFFF
    var floor_fill := Themes.floor_fill(rect, _zoom(), floor_seed, FLOOR_TINTS.get(data.type, Color.WHITE), theme)
    floor_fill.z_index = -2
    add_child(floor_fill)
    _dress_room()


## The theme's dressing (see Themes, Ambience): statues, altars or trees set into the top
## wall between its lights (torches, flame braziers), and the floor's own extras, seeded
## per room so a revisit looks the same: dry moss that burns (ruins), an ice sheet
## (frozen), lava pools (forge, fight rooms only), small rifts (void).
func _dress_theme() -> void:
    var td := Themes.def(theme)
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(data.pos) * 13 + main.floor_number * 31 + 5
    var half := room_size / 2.0
    var tx := Themes.texel(_zoom())
    var tile := 32.0 * tx
    var decor: Array = td["decor"]
    var light := String(td["light"])
    var tint: Color = td["decor_tint"]
    # Slots along the top wall, clear of a doorway; lights and decor alternate.
    var n := maxi(2, int(room_size.x / 200.0))
    var k := rng.randi() % 2
    for i in n:
        var x := -half.x + room_size.x * (float(i) + 0.5) / float(n)
        if data.doors.has(Vector2i.UP) and absf(x) < GAP / 2.0 + tile * 0.6:
            continue
        var foot := Vector2(x, -half.y + 4.0)
        if light != "" and k % 2 == 0:
            ambience.add_light(foot - Vector2(0, tile * 0.5 + 4.0), light)
        elif not decor.is_empty():
            var spr := Sprite2D.new()
            spr.texture = Themes.tex(String(decor[rng.randi() % decor.size()]))
            spr.scale = Vector2(tx, tx)
            spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
            spr.position = ((foot - Vector2(0, tile * 0.5)) / tx).round() * tx
            spr.modulate = tint
            spr.z_index = -1
            add_child(spr)
        k += 1
    # Torches on the side walls too, where no door is.
    if light == "torch":
        for sx in [-1, 1]:
            var side := Vector2i(sx, 0)
            for fy in [-0.45, 0.45]:
                if data.doors.has(side) and absf(fy * half.y) < GAP / 2.0 + tile * 0.6:
                    continue
                ambience.add_light(Vector2(float(sx) * (half.x + WALL * 0.5), fy * half.y), "torch")
    var fight := not data.is_safe()
    match theme:
        "ruins":
            _moss_patches(rng)
        "frozen":
            if data.type != RoomData.Type.START and rng.randf() < 0.5:
                _ice_patch(rng)
        "forge":
            if fight:
                for i in rng.randi_range(1, 2):
                    var at := _free_spot(rng, 70.0)
                    if at != Vector2.INF:
                        var lr := Rect2(((at - Vector2(30, 20)) / tx).round() * tx, (Vector2(60, 40) / tx).round() * tx)
                        ambience.add_lava(lr)
                        reserve(at, 50.0)
        "void":
            for i in rng.randi_range(1, 2):
                var at := _free_spot(rng, 50.0)
                if at != Vector2.INF:
                    ambience.add_rift(at)
                    reserve(at, 30.0)


## A random open spot clear of doors, keep zones, puzzle pieces and props, or INF.
func _free_spot(rng: RandomNumberGenerator, r: float) -> Vector2:
    var props: Array[Vector2] = []
    for c in find_children("*", "", true, false):
        if c is Prop:
            props.append((c as Node2D).global_position - global_position)
    for attempt in 24:
        var at := Vector2(rng.randf_range(rect.position.x + r + 40.0, rect.end.x - r - 40.0), rng.randf_range(rect.position.y + r + 40.0, rect.end.y - r - 40.0))
        if not spot_ok(at, r):
            continue
        var clear := true
        for pp in props:
            if pp.distance_to(at) < r + 30.0:
                clear = false
                break
        if clear:
            return at
    return Vector2.INF


## Dry moss in a few patches (ruins): a thin oil film under tufts, so fire runs through it
## like the layout's grass.
func _moss_patches(rng: RandomNumberGenerator) -> void:
    if materials == null:
        return
    var grass := GrassLayer.new()
    grass.room = self
    grass.name = "Moss"
    grass.z_index = -1
    grass.tuft_a = Color(0.46, 0.56, 0.26, 0.9)
    grass.tuft_b = Color(0.56, 0.50, 0.24, 0.9)
    for i in rng.randi_range(2, 4):
        var at := _free_spot(rng, 40.0)
        if at == Vector2.INF:
            continue
        var wr := Rect2((at - Vector2(40, 26)).snapped(Vector2(NAV, NAV)), Vector2(80, 52))
        materials.lay_still(Element.Kind.OIL, materials.indices_in(wr), 0, 1 << 30, 30)
        grass.beds.append(wr)
        for t in int(wr.get_area() / 150.0):
            var q := Vector2(rng.randf_range(wr.position.x + 3.0, wr.end.x - 3.0), rng.randf_range(wr.position.y + 3.0, wr.end.y - 3.0)).round()
            if is_open(q, 2.0):
                grass.tufts.append(q)
    if not grass.tufts.is_empty():
        add_child(grass)


## A pre-laid ice sheet (frozen floor), drawn and melted like the layout's.
func _ice_patch(rng: RandomNumberGenerator) -> void:
    if materials == null:
        return
    var at := _free_spot(rng, 80.0)
    if at == Vector2.INF:
        return
    var wr := Rect2((at - Vector2(80, 50)).snapped(Vector2(NAV, NAV)), Vector2(160, 100))
    var idx := PackedInt32Array()
    for i in materials.indices_in(wr):
        if is_open(materials._cell_world(i), 3.0):
            idx.append(i)
    if idx.is_empty():
        return
    materials.lay_still(Element.Kind.ICE, idx, 0, idx.size(), 200)
    var sheet := IceSheet.new()
    sheet.name = "ThemeIce"
    sheet.setup(materials, idx)
    add_child(sheet)


# --- Pedestals and interaction ---------------------------------------------


func _build_pedestals() -> void:
    for p in pedestals:
        if is_instance_valid(p):
            p.queue_free()
    pedestals.clear()
    # Taken offers keep their plinth (bare) so the row stays put; stairs and sigils never do.
    var offers: Array = data.stock.filter(func(o): return not o["taken"] or o["kind"] in ["gun", "item", "boon", "gunsmith", "carry", "repair"])
    for o in offers:
        if o["kind"] == "item" and not o["taken"]:
            Items.mark_seen(o["id"])   # Isaac: an item on show leaves the run's pool
    var row: Array = offers.filter(func(o): return not o.has("pos"))
    var n := row.size()
    var per_row := 4
    var rows := int(ceil(float(n) / float(per_row)))
    for i in n:
        var ped := Pedestal.new(row[i])
        var r := i / per_row
        var in_row := mini(per_row, n - r * per_row)
        var c := i % per_row
        ped.position = Vector2((float(c) - float(in_row - 1) / 2.0) * 210.0, 90.0 + (float(r) - float(rows - 1) / 2.0) * 220.0)
        if data.type == RoomData.Type.ARENA:
            # Arena layouts only keep the centre open; the spoils row steps off any wall.
            ped.position = nearest_open(ped.position, 34.0)
        add_child(ped)
        pedestals.append(ped)
    for o in offers:
        if o.has("pos"):
            var ped := Pedestal.new(o)
            ped.position = o["pos"]
            add_child(ped)
            pedestals.append(ped)


## Two distinct unlocked guns to choose between, for one unarmed player.
func add_gun_choice() -> void:
    var offered: Array = []
    for o in data.stock:
        if o["kind"] == "gun" and not o["taken"]:
            offered.append(o["id"])
    var pool: Array = Guns.ids().filter(func(id): return not offered.has(id))
    pool.shuffle()
    if pool.size() < 2:
        pool = Guns.ids()
        pool.shuffle()
    for i in mini(2, pool.size()):
        var o := FloorGen.offer("gun", pool[i], 0)
        o["choice"] = true
        data.stock.append(o)
    main.announce("Choose your first gun")
    _build_pedestals()


## Put a gun on the floor at a position (dropped from the character sheet).
func add_floor_gun(id: String, pos: Vector2) -> void:
    var inner := rect.grow(-90.0)
    var p := nearest_open(Vector2(clampf(pos.x, inner.position.x, inner.end.x), clampf(pos.y, inner.position.y, inner.end.y)), 26.0)
    var o := FloorGen.offer("gun", id, 0)
    o["pos"] = p
    data.stock.append(o)
    _build_pedestals()


func has_gun_choice() -> bool:
    for o in data.stock:
        if o["kind"] == "gun" and o.get("choice", false) and not o["taken"]:
            return true
    return false


func _handle_interact() -> void:
    for ped in pedestals:
        if not is_instance_valid(ped):
            continue
        var near := main.nearest_alive_player(ped.global_position)
        ped.highlighted = not ped.empty() and near != null and near.global_position.distance_to(ped.global_position) <= Pedestal.RANGE
        if near != null:
            ped.prompt_key = near.input.prompt("interact")
            ped.prompt_kind = near.input.last_kind
    for pl in main.players:
        if pl.alive and pl.input.take_pressed("swap"):
            # Ring / trinket pedestal with both of the pair worn: replace the other one.
            var near_ped := _nearest_pedestal(pl)
            if near_ped != null and near_ped.kind() == "item":
                var slot := String(near_ped.item().get("slot", ""))
                if pl.jewel_key(slot) != "":
                    pl.cycle_jewel(slot)
                    Sfx.play("ui_move")
        if not pl.alive or not pl.input.take_pressed("interact"):
            continue
        var best: Pedestal = null
        var best_d := Pedestal.RANGE
        for ped in pedestals:
            if not is_instance_valid(ped) or ped.empty():
                continue
            var d := ped.global_position.distance_to(pl.global_position)
            if d < best_d:
                best_d = d
                best = ped
        if best != null:
            activate(best, pl)


## The live pedestal within reach of `pl`, nearest first, or null.
func _nearest_pedestal(pl: Player) -> Pedestal:
    var best: Pedestal = null
    var best_d := Pedestal.RANGE
    for ped in pedestals:
        if not is_instance_valid(ped) or ped.empty():
            continue
        var d := ped.global_position.distance_to(pl.global_position)
        if d < best_d:
            best_d = d
            best = ped
    return best


## Finish buying a mod once the gun is known.
func _fit_mod(pl: Player, gun: Gun, o: Dictionary) -> void:
    if not is_instance_valid(gun) or main.scrap < o["price"]:
        return
    main.scrap -= o["price"]
    Telemetry.mod_fitted(o, self)
    pl.equip_mod_on(gun, o["id"])
    Progress.add("items_picked")
    Sfx.play("buy")
    o["taken"] = true
    if o["price"] == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE] and not o.get("secret", false):
        for other in data.stock:
            if other["kind"] in ["gun", "item", "boon"] and not other.get("secret", false):
                other["taken"] = true
    if o.get("spoils", false):
        salvage_spoils("picked")
    _build_pedestals()


func activate(ped: Pedestal, pl: Player) -> void:
    var o := ped.offer
    var tel_snap: Dictionary = Telemetry.offer_snapshot(o, self)
    match o["kind"]:
        "gun":
            var gdata := Guns.make(o["id"])
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            if not pl.can_carry(gdata):
                pl.say("Too heavy: %s is %d, %d free" % [gdata.display_name, gdata.weight, pl.weight_capacity - pl.total_weight()])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            pl.add_gun(o["id"])
            Sfx.play("buy")
            o["taken"] = true
            if o.get("spoils", false):
                salvage_spoils("picked")
            if o.get("choice", false):
                # Entrance pick: once everyone is armed, the rest of the choices vanish.
                var all_armed := true
                for other_pl in main.players:
                    if other_pl.alive and other_pl.guns.is_empty():
                        all_armed = false
                if all_armed:
                    for other in data.stock:
                        if other.get("choice", false):
                            other["taken"] = true
            elif o["price"] == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE] and not o.get("secret", false):
                for other in data.stock:
                    if other["kind"] in ["gun", "item", "boon"] and not other.get("secret", false):
                        other["taken"] = true
        "item":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            var item := Items.get_item(o["id"])
            if item["slot"] == "mod":
                var candidates: Array = pl.mod_candidates()
                if candidates.is_empty():
                    pl.say("No free mod slot: upgrade a gun" if not pl.guns.is_empty() else "No gun to fit it to")
                    Sfx.play("error")
                    return
                if candidates.size() == 1 or main.autotest:
                    _fit_mod(pl, candidates[0], o)
                else:
                    # More than one gun could take it: let the player choose.
                    main.gun_pick.pick(pl, candidates, o["id"], func(g): if g != null: _fit_mod(pl, g, o))
                return
            main.scrap -= o["price"]
            var replaced := pl.equip(o["id"], pl.jewel_key(String(item["slot"])))
            Progress.add("items_picked")
            Sfx.play("buy")
            o["taken"] = true
            if o.get("spoils", false):
                salvage_spoils("picked")
            if o["price"] == 0 and data.type in [RoomData.Type.TREASURE, RoomData.Type.CHALLENGE] and not o.get("secret", false):
                for other in data.stock:
                    if other["kind"] in ["gun", "item", "boon"] and not other.get("secret", false):
                        other["taken"] = true
            if replaced != "":
                # The old piece takes the plinth the new one came from.
                o["id"] = replaced
                o["price"] = 0
                o["taken"] = false
        "boon":
            match o["id"]:
                "vitality":
                    pl.max_hp_base += o["amount"]
                    pl.recalc_stats()
                    pl.heal(o["amount"])
                "haul":
                    pl.weight_capacity_base += o["amount"]
                    pl.recalc_stats()
                "boiler":
                    pl.pressure_limit_bonus += o["amount"]
                "hoard":
                    main.add_scrap(o["amount"])
            pl.say("%s" % FloorGen.BOONS[o["id"]]["name"])
            Sfx.play("buy")
            o["taken"] = true
            if data.type == RoomData.Type.TREASURE and not o.get("secret", false):
                for other in data.stock:
                    if other["kind"] in ["gun", "item", "boon"] and not other.get("secret", false):
                        other["taken"] = true
        "gunsmith":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            var upgraded := pl.upgrade_lowest_gun()
            if upgraded == null:
                pl.say("Nothing to upgrade")
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            Sfx.play("buy")
            o["taken"] = true
        "carry":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            pl.weight_capacity_base += o["amount"]
            pl.recalc_stats()
            pl.say("Carry capacity %d" % pl.weight_capacity)
            Sfx.play("buy")
            o["taken"] = true
        "repair":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            pl.hp = minf(pl.max_hp, pl.hp + o["amount"])
            pl.say("Repaired")
            Sfx.play("buy")
            o["taken"] = true
        "reroll":
            if main.scrap < o["price"]:
                pl.say("Need %d scrap" % o["price"])
                Sfx.play("error")
                return
            main.scrap -= o["price"]
            o["amount"] += 1   # uses so far
            o["price"] = FloorGen.reroll_price(main.floor_number, o["amount"])
            for i in data.stock.size():
                var w: Dictionary = data.stock[i]
                if w.get("ware", false) and not w["taken"]:
                    data.stock[i] = FloorGen.roll_ware(main.floor_number, main.party_luck(), data.stock, main.players)
            pl.say("Rerolled")
            Sfx.play("buy")
        "stairs":
            Sfx.play("stairs")
            main.next_floor(String(o["id"]))
            return
        "sigil":
            o["taken"] = true
            Sfx.play("confirm")
            begin_challenge()
    Telemetry.offer_used(tel_snap, self)
    _build_pedestals()


# --- Layout and navigation ---------------------------------------------------


## Spots the layout keeps open: the centre, the reward / pedestal row, the chest, every
## pedestal already standing.
func _keep_zones() -> Array:
    var keep: Array = [[Vector2.ZERO, 120.0], [Vector2(0, 90), 100.0]]
    var half := room_size / 2.0
    match data.type:
        RoomData.Type.TREASURE:
            keep.append([Vector2(0, -170), 110.0])
        RoomData.Type.SHOP:
            for x in [-240.0, 0.0, 240.0]:
                keep.append([Vector2(x, -half.y + 100.0), 90.0])
        RoomData.Type.BOSS:
            keep.append([Vector2(0, 150), 80.0])
    if data.type != RoomData.Type.ARENA:
        for x in [-315.0, -210.0, -105.0, 105.0, 210.0, 315.0]:
            keep.append([Vector2(x, 90.0), 90.0])
    for p in pedestals:
        if is_instance_valid(p):
            keep.append([p.position, 100.0])
    return keep


func _build_layout() -> void:
    # The spots kept open are fixed on the first visit, so pedestals dropped later (always
    # on open floor) never reshape the room on a revisit.
    if data.has_meta("layout_keep"):
        _keep = data.get_meta("layout_keep")
    else:
        _keep = _keep_zones()
        data.set_meta("layout_keep", _keep)
    var door_pts: Array = []
    for d in data.doors.keys():
        door_pts.append(Vector2(d) * (room_size / 2.0 + Vector2(WALL / 2.0, WALL / 2.0)))
    var plan := RoomLayouts.build(data.layout, data.layout_seed, room_size, _keep, door_pts, data.alcove)
    layout_name = plan.name
    nav_w = plan.w
    nav_h = plan.h
    cells = plan.cells
    terrain = plan.terrain
    var alcove: Dictionary = plan.alcove
    if not alcove.is_empty():
        _alcove_inner = alcove["inner"]
        if data.alcove_open:
            _open_alcove_cells()
    _recount_blockers()

    var under := LayoutLayer.new()
    under.room = self
    under.mode = 0
    under.name = "LayoutUnder"
    under.z_index = -2
    add_child(under)
    var over := LayoutLayer.new()
    over.room = self
    over.mode = 1
    over.name = "LayoutOver"
    over.z_index = -1
    add_child(over)
    _styles = plan.style

    # Walls and pillars: the same bricks as the outer walls; rubble: loose stone.
    for st in [RoomLayouts.S_WALL, RoomLayouts.S_PILLAR, RoomLayouts.S_RUBBLE]:
        for r in RoomLayouts.rects_of(cells, nav_w, nav_h, RoomLayouts.WALL, plan.style, st):
            var wr := _cell_rect(r)
            if st == RoomLayouts.S_RUBBLE:
                _rubble(wr)
            else:
                _wall(_walls_body, wr.get_center(), wr.size, Color(1.12, 1.12, 1.12) if st == RoomLayouts.S_PILLAR else Color.WHITE)
    var chasm_rects := RoomLayouts.rects_of(cells, nav_w, nav_h, RoomLayouts.CHASM)
    if not chasm_rects.is_empty():
        var pit := StaticBody2D.new()
        pit.name = "Chasms"
        pit.collision_layer = Player.LAYER_WALLS   # walkers stop at the lip; shots fly over
        pit.collision_mask = 0
        add_child(pit)
        for r in chasm_rects:
            var wr := _cell_rect(r)
            var shape := CollisionShape2D.new()
            var rs := RectangleShape2D.new()
            rs.size = wr.size
            shape.shape = rs
            shape.position = wr.get_center()
            pit.add_child(shape)

    # Terrain lies on the Materials grid, so it reacts like anything else on the floor.
    _deep_rects.clear()
    _deep_idx = PackedInt32Array()
    for r in RoomLayouts.rects_of(terrain, nav_w, nav_h, RoomLayouts.T_DEEP):
        _deep_rects.append(_cell_rect(r))
    if materials != null:
        for wr in _deep_rects:
            _deep_idx.append_array(materials.indices_in(wr))
        materials.lay_still(Element.Kind.WET, _deep_idx, 0, _deep_idx.size(), 90)
        for r in RoomLayouts.rects_of(terrain, nav_w, nav_h, RoomLayouts.T_OIL):
            materials.fill_rect(Element.Kind.OIL, _cell_rect(r), 150, 255)
        var ice_idx := PackedInt32Array()
        for r in RoomLayouts.rects_of(terrain, nav_w, nav_h, RoomLayouts.T_ICE):
            ice_idx.append_array(materials.indices_in(_cell_rect(r)))
        if not ice_idx.is_empty():
            # An ice sheet: still ice on the grid, drawn by one texture that loses each
            # cell as it melts or cracks away.
            materials.lay_still(Element.Kind.ICE, ice_idx, 0, ice_idx.size(), 200)
            var sheet := IceSheet.new()
            sheet.name = "IceSheet"
            sheet.setup(materials, ice_idx)
            add_child(sheet)
        var grass_rects := RoomLayouts.rects_of(terrain, nav_w, nav_h, RoomLayouts.T_GRASS)
        if not grass_rects.is_empty():
            var grass := GrassLayer.new()
            grass.room = self
            grass.name = "Grass"
            grass.z_index = -1
            var rng := RandomNumberGenerator.new()
            rng.seed = data.layout_seed + 5
            for r in grass_rects:
                var wr := _cell_rect(r)
                materials.lay_still(Element.Kind.OIL, materials.indices_in(wr), 0, 1 << 30, 30)
                for k in int(wr.get_area() / 260.0):
                    grass.tufts.append(Vector2(rng.randf_range(wr.position.x + 3.0, wr.end.x - 3.0), rng.randf_range(wr.position.y + 3.0, wr.end.y - 3.0)).round())
            add_child(grass)

    if not plan.props.is_empty():
        var holder := Node2D.new()
        holder.name = "LayoutProps"
        add_child(holder)
        for pr in plan.props:
            var prop := Prop.new(String(pr["kind"]))
            prop.room = self
            prop.position = pr["pos"]
            holder.add_child(prop)
            reserve(pr["pos"], 40.0)

    if not alcove.is_empty() and not data.alcove_open:
        var front: Rect2 = alcove["front"]
        var sw := SecretWall.new("alcove", "rubble", front.size, alcove["out"])
        sw.position = front.get_center()
        add_child(sw)
        sw.cleared.connect(_on_alcove_opened)
        reserve(_alcove_inner.get_center(), 110.0)

    # Lit tops, bevels and outlines of everything solid, over the wall tiles and over a
    # secret wall (z 0, added after it) so a secret front gets exactly the same edges.
    var edges := LayoutLayer.new()
    edges.room = self
    edges.mode = 2
    edges.name = "LayoutEdges"
    add_child(edges)


func _cell_rect(r: Rect2i) -> Rect2:
    return Rect2(rect.position + Vector2(r.position) * NAV, Vector2(r.size) * NAV)


func _rubble(wr: Rect2) -> void:
    var shape := CollisionShape2D.new()
    var rs := RectangleShape2D.new()
    rs.size = wr.size
    shape.shape = rs
    shape.position = wr.get_center()
    _walls_body.add_child(shape)
    # Loose stone: the theme's wall tiles, darker, broken up by a few dark seams.
    var heap := Themes.wall_fill(wr, _zoom(), Color(0.72, 0.68, 0.66), theme)
    heap.z_index = -1
    add_child(heap)
    var seams := RubbleSeams.new()
    seams.area = wr
    seams.z_index = -1
    add_child(seams)


## Dark seams over a rubble heap, so it reads as broken stone and not as a wall.
class RubbleSeams extends Node2D:
    var area := Rect2()
    func _draw() -> void:
        var k := 0
        var y := area.position.y + 7.0
        while y < area.end.y - 3.0:
            var x := area.position.x + 5.0 + float(k % 3) * 4.0
            while x < area.end.x - 6.0:
                draw_rect(Rect2(Vector2(x, y), Vector2(6, 2)).intersection(area), Color(0.02, 0.02, 0.03, 0.75))
                x += 14.0
            k += 1
            y += 9.0
        draw_rect(area, Color(0.02, 0.02, 0.03, 0.6), false, 2.0)


func _recount_blockers() -> void:
    has_walls = false
    has_blockers = false
    for c in cells:
        if c == RoomLayouts.WALL or c == RoomLayouts.BREAK:
            has_walls = true
        if c != RoomLayouts.OPEN:
            has_blockers = true
    _goal_cache.clear()
    _flow = PackedInt32Array()


func _open_alcove_cells() -> void:
    for i in cells.size():
        if cells[i] == RoomLayouts.BREAK or cells[i] == RoomLayouts.POCKET:
            cells[i] = RoomLayouts.OPEN


## The alcove's front gave way: the pocket joins the room and pays out once.
func _on_alcove_opened() -> void:
    data.alcove_open = true
    _open_alcove_cells()
    _recount_blockers()
    _redraw_layout()
    Secrets.record("alcove", main.floor_number)
    if data.alcove_paid:
        return
    data.alcove_paid = true
    var c := _alcove_inner.get_center()
    _drop_scrap(c, 12 + 6 * main.floor_number, 5)
    if randf() < 0.5:
        var o := Items.offer(Drops.roll_item(main.difficulty(), Items.Rarity.COMMON, [], main.party_luck(), "", main.players), 0, c)
        o["secret"] = true
        data.stock.append(o)
        call_deferred("_build_pedestals")


## Deep pools are topped up a slice at a time (a frozen or boiled pool comes back as
## water within a couple of seconds), and the walkers' flow field is refreshed while
## anything is chasing anyone.
func _tick_layout(delta: float) -> void:
    if not _deep_idx.is_empty() and materials != null:
        _deep_t -= delta
        if _deep_t <= 0.0:
            _deep_t = 0.1
            materials.lay_still(Element.Kind.WET, _deep_idx, _deep_cursor, 700, 90)
            _deep_cursor += 700
            if _deep_cursor >= _deep_idx.size():
                _deep_cursor = 0
    if has_blockers and enemies != null and enemies.get_child_count() > 0:
        _flow_t -= delta
        if _flow_t <= 0.0:
            _flow_t = 0.3
            _update_flow()


func cell_index(pos: Vector2) -> int:
    if nav_w <= 0:
        return -1
    var l := pos - global_position - rect.position
    var cx := floori(l.x / NAV)
    var cy := floori(l.y / NAV)
    if cx < 0 or cy < 0 or cx >= nav_w or cy >= nav_h:
        return -1
    return cy * nav_w + cx


## What the layout has at a point (RoomLayouts.OPEN, WALL, CHASM...); WALL off the grid.
func cell_at(pos: Vector2) -> int:
    var i := cell_index(pos)
    if i < 0:
        return RoomLayouts.WALL
    return cells[i]


## Floor a body of `radius` can stand on: inside the room, no wall, chasm or closed alcove.
func is_open(pos: Vector2, radius: float = 20.0) -> bool:
    var local := pos - global_position
    if not rect.grow(-radius).has_point(local):
        return false
    if not has_blockers:
        return true
    var r := maxf(radius, 1.0)
    var y := local.y - r
    while true:
        var x := local.x - r
        while true:
            if cell_at(global_position + Vector2(x, y)) != RoomLayouts.OPEN:
                return false
            if x >= local.x + r:
                break
            x = minf(x + NAV, local.x + r)
        if y >= local.y + r:
            break
        y = minf(y + NAV, local.y + r)
    return true


## Open floor whose cells around `pos` carry no terrain (no pool, slick, ice or grass).
func is_dry(pos: Vector2, radius: float) -> bool:
    if terrain.is_empty():
        return true
    var local := pos - global_position
    for oy in [-radius, 0.0, radius]:
        for ox in [-radius, 0.0, radius]:
            var i := cell_index(global_position + local + Vector2(ox, oy))
            if i >= 0 and terrain[i] != RoomLayouts.T_NONE:
                return false
    return true


func is_deep(pos: Vector2) -> bool:
    if _deep_rects.is_empty():
        return false
    var i := cell_index(pos)
    if i < 0 or terrain[i] != RoomLayouts.T_DEEP or materials == null:
        return false
    var m := materials.material_at(pos)
    return m == Materials.WATER or m == Materials.POISON or m == Materials.CHARGED


## Interior wall at this point: shots stop here (chasms they fly over).
func blocks_shot(pos: Vector2) -> bool:
    return has_walls and cell_at(pos) == RoomLayouts.WALL


## No wall between a and b (sight, shots); with `walk`, no chasm either.
func line_clear(a: Vector2, b: Vector2, walk: bool = false) -> bool:
    if not has_blockers or (not walk and not has_walls):
        return true
    var n := int(a.distance_to(b) / 14.0)
    for k in range(1, n):
        var i := cell_index(a.lerp(b, float(k) / float(n)))
        if i < 0:
            continue   # past the floor's edge: a doorway or the outer wall, not the layout
        var c := cells[i]
        if c == RoomLayouts.WALL or c == RoomLayouts.BREAK:
            return false
        if walk and c != RoomLayouts.OPEN:
            return false
    return true


## Puzzle pieces claim their spot so props keep away.
func reserve(pos: Vector2, radius: float) -> void:
    reserved.append([pos, radius])


func _near_door(pos: Vector2, dist: float) -> bool:
    for d in data.doors.keys():
        if pos.distance_to(Vector2(d) * (room_size / 2.0)) < dist:
            return true
    return false


func _near_reserved(pos: Vector2, r: float) -> bool:
    for q in reserved:
        var qp: Vector2 = q[0]
        if pos.distance_to(qp) < float(q[1]) + r:
            return true
    return false


## A spot for a puzzle piece: open (and dry unless `dry` is false), off the doors, the keep
## zones and other pieces.
func spot_ok(pos: Vector2, r: float, dry: bool = true) -> bool:
    if not is_open(pos, r) or (dry and not is_dry(pos, r)) or _near_door(pos, 190.0) or _near_reserved(pos, r):
        return false
    for k in _keep:
        var kp: Vector2 = k[0]
        if pos.distance_to(kp) < float(k[1]) + r:
            return false
    return true


## As spot_ok, but keep zones and shallow terrain are allowed (statues, trails); deep
## water too when `deep` is true.
func spot_ok_loose(pos: Vector2, r: float, deep: bool = false) -> bool:
    if not is_open(pos, r) or _near_door(pos, 150.0) or _near_reserved(pos, r):
        return false
    var i := cell_index(pos)
    return deep or i < 0 or terrain.is_empty() or terrain[i] != RoomLayouts.T_DEEP


## For Props.dress: open, dry floor clear of puzzle pieces.
func prop_ok(pos: Vector2) -> bool:
    return is_open(pos, 34.0) and is_dry(pos, 30.0) and not _near_reserved(pos, 30.0)


## The closest standable point to `pos` (spiralling out), else the centre.
func nearest_open(pos: Vector2, radius: float = 24.0) -> Vector2:
    if is_open(pos, radius):
        return pos
    for ring in range(1, 16):
        var dist := float(ring) * 20.0
        var steps := 8 + ring * 2
        for k in steps:
            var q := pos + Vector2.RIGHT.rotated(TAU * float(k) / float(steps)) * dist
            if is_open(q, radius):
                return q
    return Vector2.ZERO


## Multi-source BFS from every living player: walkers descend it around walls and pits.
func _update_flow() -> void:
    var seeds := PackedInt32Array()
    for pl in main.players:
        if pl.alive:
            var i := cell_index(pl.global_position)
            if i >= 0:
                seeds.append(i)
    _flow = _bfs(seeds)


func _bfs(seeds: PackedInt32Array) -> PackedInt32Array:
    var dist := PackedInt32Array()
    dist.resize(nav_w * nav_h)
    dist.fill(1 << 20)
    var queue := PackedInt32Array()
    for s in seeds:
        if dist[s] != 0:
            dist[s] = 0
            queue.append(s)
    var head := 0
    while head < queue.size():
        var i := queue[head]
        head += 1
        var cx := i % nav_w
        var cy := i / nav_w
        var nd := dist[i] + 1
        for oy in range(-1, 2):
            for ox in range(-1, 2):
                if ox == 0 and oy == 0:
                    continue
                var nx := cx + ox
                var ny := cy + oy
                if nx < 0 or ny < 0 or nx >= nav_w or ny >= nav_h:
                    continue
                var j := ny * nav_w + nx
                if cells[j] != RoomLayouts.OPEN or dist[j] <= nd:
                    continue
                if ox != 0 and oy != 0 and (cells[cy * nav_w + nx] != RoomLayouts.OPEN or cells[ny * nav_w + cx] != RoomLayouts.OPEN):
                    continue   # no cutting corners
                dist[j] = nd
                queue.append(j)
    return dist


## Step down a distance field from `from`: the direction to the best neighbouring cell.
func _descend(dist: PackedInt32Array, from: Vector2) -> Vector2:
    var i := cell_index(from)
    if i < 0 or dist.size() != nav_w * nav_h:
        return Vector2.ZERO
    var cx := i % nav_w
    var cy := i / nav_w
    var best := dist[i]
    var best_j := -1
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            if ox == 0 and oy == 0:
                continue
            var nx := cx + ox
            var ny := cy + oy
            if nx < 0 or ny < 0 or nx >= nav_w or ny >= nav_h:
                continue
            var j := ny * nav_w + nx
            if dist[j] >= best:
                continue
            if ox != 0 and oy != 0 and (cells[cy * nav_w + nx] != RoomLayouts.OPEN or cells[ny * nav_w + cx] != RoomLayouts.OPEN):
                continue
            best = dist[j]
            best_j = j
    if best_j < 0:
        return Vector2.ZERO
    var target := global_position + rect.position + Vector2(float(best_j % nav_w) + 0.5, float(best_j / nav_w) + 0.5) * NAV
    var v := target - from
    return v.normalized() if v.length() > 0.5 else Vector2.ZERO


## Which way a walker should go to reach the nearest player: ZERO when the way is
## straight (or the room has nothing in it), else around walls and chasms.
func nav_dir(from: Vector2) -> Vector2:
    if not has_blockers or _flow.is_empty():
        return Vector2.ZERO
    return _descend(_flow, from)


## Which way to walk from `from` to `to` (the bot): straight when nothing is in the way.
func path_dir(from: Vector2, to: Vector2) -> Vector2:
    var direct := (to - from).normalized()
    if not has_blockers or line_clear(from, to, true):
        return direct
    var inner := rect.grow(-NAV * 0.5)
    var local := to - global_position
    var goal := global_position + Vector2(clampf(local.x, inner.position.x, inner.end.x), clampf(local.y, inner.position.y, inner.end.y))
    var gi := cell_index(goal)
    if gi < 0:
        return direct
    var now := Time.get_ticks_msec()
    var entry: Array = _goal_cache.get(gi, [])
    if entry.is_empty() or now - int(entry[0]) > 1500:
        if _goal_cache.size() > 6:
            _goal_cache.clear()
        entry = [now, _bfs(PackedInt32Array([gi]))]
        _goal_cache[gi] = entry
    var d := _descend(entry[1], from)
    return d if d != Vector2.ZERO else direct


## Drawing for the layout (see Themes for the value ladder): mode 0 under the floor
## materials (deep pools, grass beds), mode 1 over them and under the wall tiles (chasms,
## drop shadows, the outline where the outer walls meet the floor), mode 2 over the wall
## tiles and secret walls (lit tops, bevels and outlines of interior walls, pillars,
## rubble and an alcove front; the lit top of the bottom wall).
class LayoutLayer extends Node2D:
    var room: Room
    var mode := 0
    func _draw() -> void:
        room._draw_layout(self, mode)


func _draw_layout(cv: Node2D, mode: int) -> void:
    var cs := NAV
    var td := Themes.def(theme)
    var tx := Themes.texel(_zoom())
    for i in cells.size():
        var cx := i % nav_w
        var cy := i / nav_w
        var p := rect.position + Vector2(cx, cy) * cs
        if mode == 0:
            if terrain[i] == RoomLayouts.T_GRASS:
                cv.draw_rect(Rect2(p, Vector2(cs, cs)), Color(0.40, 0.34, 0.16, 0.22))
            elif terrain[i] == RoomLayouts.T_DEEP:
                # The pool itself (its still water is not drawn by the Materials grid).
                Themes.draw_pool_cell(cv, p, cs, tx, not _terrain_is(cx, cy - 1, RoomLayouts.T_DEEP),
                    not _terrain_is(cx, cy + 1, RoomLayouts.T_DEEP), not _terrain_is(cx - 1, cy, RoomLayouts.T_DEEP),
                    not _terrain_is(cx + 1, cy, RoomLayouts.T_DEEP), td, cv.global_position, (i * 2654435761) & 0xFFFF)
        elif mode == 1:
            if cells[i] == RoomLayouts.CHASM:
                Themes.draw_chasm_cell(cv, p, cs, tx, not _cell_is(cx, cy - 1, RoomLayouts.CHASM),
                    not _cell_is(cx, cy + 1, RoomLayouts.CHASM), not _cell_is(cx - 1, cy, RoomLayouts.CHASM),
                    not _cell_is(cx + 1, cy, RoomLayouts.CHASM), td)
            elif not _solid_cell(cx, cy):
                # Outer walls cast theirs through Room._draw; only interior solids here.
                var above := cy > 0 and _solid_cell(cx, cy - 1)
                var left := cx > 0 and _solid_cell(cx - 1, cy)
                var corner := cx > 0 and cy > 0 and _solid_cell(cx - 1, cy - 1)
                if above or left or corner:
                    Themes.draw_floor_shadow(cv, p, cs, tx, above, left, corner)
        elif _solid_cell(cx, cy):
            var up := not _solid_or_out(cx, cy - 1)
            var dn := not _solid_or_out(cx, cy + 1)
            var lf := not _solid_or_out(cx - 1, cy)
            var rt := not _solid_or_out(cx + 1, cy)
            if up or dn or lf or rt:
                var soft := i < _styles.size() and _styles[i] == RoomLayouts.S_RUBBLE
                Themes.draw_block_edges(cv, p, cs, tx, up, dn, lf, rt, td, soft)
    if mode == 1:
        _draw_outer_edges(cv, tx, td, false)
    elif mode == 2:
        _draw_outer_edges(cv, tx, td, true)


## Where the outer walls meet the floor: an outline on the floor side all round (mode 1,
## under wall decor and torches), and the lit top of the bottom wall (mode 2, over a secret
## wall). A secret wall still standing counts as wall, so the line runs on across it.
func _draw_outer_edges(cv: Node2D, tx: float, td: Dictionary, lit: bool) -> void:
    var ol: Color = td.get("outline", Color(0.02, 0.02, 0.03))
    var hi: Color = td.get("edge", Color(0.7, 0.7, 0.7))
    var r := rect
    for d in FloorGen.DIRS:
        var horizontal: bool = d.y != 0
        var length := r.size.x if horizontal else r.size.y
        var spans: Array = [[-length / 2.0, length / 2.0]]
        if data.doors.has(d) and String(data.doors[d]["obstacle"]) != "secret":
            spans = [[-length / 2.0, -GAP / 2.0], [GAP / 2.0, length / 2.0]]
        for s in spans:
            var a: float = s[0]
            var b: float = s[1]
            if lit:
                if d == Vector2i.DOWN:
                    cv.draw_rect(Rect2(a, r.end.y, b - a, tx), Color(hi, 0.95))
                    cv.draw_rect(Rect2(a, r.end.y + tx, b - a, tx), Color(hi, 0.42))
                continue
            if d == Vector2i.UP:
                cv.draw_rect(Rect2(a, r.position.y, b - a, tx), ol)
            elif d == Vector2i.DOWN:
                cv.draw_rect(Rect2(a, r.end.y - tx, b - a, tx), ol)
            elif d == Vector2i.LEFT:
                cv.draw_rect(Rect2(r.position.x, a, tx, b - a), ol)
            else:
                cv.draw_rect(Rect2(r.end.x - tx, a, tx, b - a), ol)


## Solid for the edge drawing: interior walls, pillars, rubble, a closed alcove front.
func _solid_cell(cx: int, cy: int) -> bool:
    if cx < 0 or cy < 0 or cx >= nav_w or cy >= nav_h:
        return false
    var v := cells[cy * nav_w + cx]
    return v == RoomLayouts.WALL or v == RoomLayouts.BREAK


## Like _solid_cell, with the outer walls (outside the grid) solid too, so an interior
## wall that touches them joins them without an edge.
func _solid_or_out(cx: int, cy: int) -> bool:
    if cx < 0 or cy < 0 or cx >= nav_w or cy >= nav_h:
        return true
    return _solid_cell(cx, cy)


## Redraws the layout layers after the solid shape changed (an alcove front or a secret
## door wall gave way).
func _redraw_layout() -> void:
    for n in ["LayoutOver", "LayoutEdges"]:
        var l := get_node_or_null(NodePath(n)) as CanvasItem
        if l != null:
            l.queue_redraw()


func _cell_is(cx: int, cy: int, v: int) -> bool:
    if cx < 0 or cy < 0 or cx >= nav_w or cy >= nav_h:
        return false
    return cells[cy * nav_w + cx] == v


func _terrain_is(cx: int, cy: int, v: int) -> bool:
    if cx < 0 or cy < 0 or cx >= nav_w or cy >= nav_h:
        return false
    return terrain[cy * nav_w + cx] == v


## An ice sheet laid by the layout: one pale texture over the Materials grid (a pixel per
## grid cell) instead of thousands of drawn cells. A slice of cells is checked every tick;
## a cell that is no longer ice (melted, eaten by acid) is cleared from the texture.
class IceSheet extends Sprite2D:
    var mats: Materials
    var idx := PackedInt32Array()
    var gone := PackedByteArray()
    var img: Image
    var tex: ImageTexture
    var _cursor := 0
    var _t := 0.0

    func setup(p_mats: Materials, p_idx: PackedInt32Array) -> void:
        mats = p_mats
        idx = p_idx
        gone.resize(idx.size())
        gone.fill(0)
        img = Image.create(mats._w, mats._h, false, Image.FORMAT_RGBA8)
        img.fill(Color(0, 0, 0, 0))
        for k in idx.size():
            var i := idx[k]
            # A mixed hash, not i * constant: the linear one drew bold diagonal stripes.
            var h := hash(i * 7919 + 104729) & 0xFF
            var c := Color(0.72, 0.88, 1.0, 0.22) if h > 22 else Color(0.92, 0.98, 1.0, 0.42)
            img.set_pixel(i % mats._w, i / mats._w, c)
        tex = ImageTexture.create_from_image(img)
        texture = tex
        centered = false
        position = mats._origin
        scale = Vector2(Materials.CELL, Materials.CELL)
        texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        z_index = -1

    func _process(delta: float) -> void:
        _t -= delta
        if _t > 0.0 or mats == null or not is_instance_valid(mats):
            return
        _t = 0.2
        var changed := false
        var end := mini(idx.size(), _cursor + 1200)
        for k in range(_cursor, end):
            if gone[k] == 0 and mats.mat[idx[k]] != Materials.ICE:
                gone[k] = 1
                img.set_pixel(idx[k] % mats._w, idx[k] / mats._w, Color(0, 0, 0, 0))
                changed = true
        _cursor = 0 if end >= idx.size() else end
        if changed:
            tex.update(img)


## Dry grass: tufts over a thin oil film. A tuft whose oil is gone (burnt, eaten) is char.
class GrassLayer extends Node2D:
    var room: Room
    var tufts: Array[Vector2] = []
    var beds: Array[Rect2] = []       # faint base patches under the tufts (theme moss)
    var tuft_a := Color(0.62, 0.55, 0.30, 0.9)
    var tuft_b := Color(0.50, 0.46, 0.26, 0.9)
    var burnt := PackedByteArray()
    var _t := 0.0

    func _ready() -> void:
        burnt.resize(tufts.size())
        burnt.fill(0)

    func _process(delta: float) -> void:
        _t -= delta
        if _t > 0.0 or room == null or room.materials == null:
            return
        _t = 0.5
        var changed := false
        for i in tufts.size():
            if burnt[i] == 0 and room.materials.material_at(room.global_position + tufts[i]) != Materials.OIL:
                burnt[i] = 1
                changed = true
        if changed:
            queue_redraw()

    func _draw() -> void:
        for b in beds:
            draw_rect(b.grow(-4.0), Color(tuft_a, 0.14))
            draw_rect(b.grow(-12.0), Color(tuft_a, 0.12))
        for i in tufts.size():
            var p := tufts[i]
            if burnt.size() > i and burnt[i] == 1:
                draw_rect(Rect2(p - Vector2(1, 0), Vector2(3, 2)), Color(0.08, 0.07, 0.06, 0.7))
                continue
            var h := (i * 7919) % 3
            var c := tuft_a if h != 0 else tuft_b
            draw_line(p, p + Vector2(-2, -5), c, 1.0)
            draw_line(p, p + Vector2(0, -6 - h), c, 1.0)
            draw_line(p, p + Vector2(2, -4), c, 1.0)


# --- Drawing ---------------------------------------------------------------


func _draw() -> void:
    # Inner shadow along the walls so the floor reads as sunken.
    draw_rect(rect.grow(-10.0), Color(0, 0, 0, 0.35), false, 20.0)
    draw_rect(Rect2(rect.position, Vector2(rect.size.x, 26.0)), Color(0, 0, 0, 0.22))


## Text that stays sharp above the pixel grid (see Crisp): the room's name on the floor.
func _draw_crisp(cv: CanvasItem) -> void:
    cv.draw_string(Art.FONT, Vector2(-200, -rect.size.y / 2.0 + 44), data.type_name().to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 400, 30, Color(data.color(), 0.3))
