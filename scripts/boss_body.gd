class_name BossBody
extends RefCounted
## The boss framework (design/World and progression GDD.md, section 6, phase 0b part 1).
## Every boss gets one: a stagger bar, phases at health fractions and a name card. A boss
## with PARTS also gets a body made of parts, each holding its own element states, compound
## and fusion cooldown, so one boss can carry several chains at once.
##
## How parts work without touching the element code: the Enemy's own `states`, `compound`,
## `compound_time`, `compound_origin` and `fusion_cd` always hold the FOCUSED part. A hit
## focuses the part nearest to where it landed (Strike.deal calls focus_at); area effects
## land on the part last focused. tick() runs the clocks of the parts that are not focused.
## On a parted boss every compound sits on the part, even one that would be a cloud or a
## floor patch on a plain enemy (Elements._leave_compound), so Steam stays on the armour.

# --- Stagger (rule 3: reactions fill it, more for higher tiers) ------------------------------
## Bar share per product tier: a reaction, a fusion, a cataclysm (half the bar).
const STAGGER_FILL := { 2: 0.015, 3: 0.08, 4: 0.5 }
## A product in a patch or field over the boss (not on one of its parts) fills this share.
const STAGGER_PATCH_SHARE := 0.5
const STAGGER_REST := 5.0       # s after a stagger ends before the bar fills again
const STAGGER_SECS := 4.0       # the guard is down this long: no moves, no attacks
const STAGGER_TAKEN := 1.5      # damage taken while staggered
const STAGGER_HOLD := 4.0       # s without a reaction before the bar drains
const STAGGER_DRAIN := 0.05     # bar per s once draining
## Per-part fusion cooldown on a parted boss (a plain enemy uses Fusions.FUSION_COOLDOWN).
const PART_FUSION_CD := 1.5

# --- Parts ----------------------------------------------------------------------------------
const INNATE_WAIT := 1.2        # s a burning part stays out before it re-ignites
const HOLD_WAIT := 2.0          # s before a part that holds a compound re-forms it
const ARMOUR_REGROW := 12.0     # s before torn armour re-forms (phase 3: ARMOUR_REGROW_LATE)
const ARMOUR_REGROW_LATE := 8.0
## Armour lost per product on an armour part; a fusion in `tears` tears it at once.
const ARMOUR_WEAR := { 2: 0.0, 3: 0.1, 4: 0.5 }
## Obsidian on the bare core: the glass shatters for this share of max health on top.
const SHATTER_SHARE := 0.03

const NAMES := {
    "brute_king": "The Brute King",
    "hive_mother": "The Hive Mother",
    "storm_warden": "The Storm Warden",
    "pyre_lord": "The Pyre Lord",
    "void_herald": "The Void Herald",
}

## Share of Room.BOSS_DPS_SECS of arena output a boss is sized to (floors 2+). The Pyre
## Lord's chain gates (armour, core) and his phases add fixed time, so he gets less health;
## bots: 72k health took 80 to 93 s, the target is 25 to 50 s.
const HP_SHARE := {
    "pyre_lord": 0.4,
    "hive_mother": 1.5,   # her chain is quick to set up; at 1.0 to 1.2 bot fights took 14 to 33 s
    "storm_warden": 1.5,
    "void_herald": 2.3,   # at 1.0 to 1.9 the bot fights took 14 to 29 s   # at 1.0 to 1.3 the bot fights took 17 to 35 s
}


static func hp_share(boss_kind: String) -> float:
    return float(HP_SHARE.get(boss_kind, 1.0))


## Floor 1 keeps the old health formula (Room), times this. The Brute King's fight is his
## plates, barrels and three phases; at the old health the fusion bot killed him in 5 to 28 s.
const FLOOR1_MULT := {
    "brute_king": 2.2,
}


static func floor1_mult(boss_kind: String) -> float:
    return float(FLOOR1_MULT.get(boss_kind, 1.0))


## Health fractions where a new phase starts. Bosses not listed keep today's two phases.
const PHASES := {
    "pyre_lord": [0.66, 0.33],
    "brute_king": [0.66, 0.33],
    "hive_mother": [0.66, 0.33],
    "storm_warden": [0.66, 0.33],
    "void_herald": [0.66, 0.33],
}

## Body parts per boss kind. `offset` and `r` are in units of the boss radius. `innate`: an
## element the part keeps re-lighting. `armour`: it wears down and tears (`tears`: fusions
## that tear it at once). `covered_by`: hidden while that part is intact. `holds`: a compound
## the part re-forms by itself while uncovered. `taken`: damage taken by hits on it.
## `inert`: elements that neither stay on the part nor react with it (they still fuse its
## compound). `only`: the part ignores every other element entirely, compound included.
## Together they make the chain readable: burning slag only steams, the core only glasses.
## `wear`: armour wear per product tier (default ARMOUR_WEAR). `tear_stagger`: stagger bar
## added when the part tears. `stays_off`: from this phase on a torn part never re-forms.
## `from_phase`: the part is hidden (not hittable) before this phase. `burrows`: hidden while
## the boss is underground (Enemy.burrowed). `tear_damage`: share of max health a tear deals.
## `wear_by`: armour wear for one named product (overrides `wear`). `payoff`: product -> share
## of max health it deals on this part, with a cataclysm's worth of stagger.
const PARTS := {
    # The Void Herald: a ring of void shards orbits a hollow centre. Shock on a shard is a
    # Singularity that leaves a Rift on the ring; a fusion of that Rift pulls the shards in
    # on themselves and the centre is bare (other products only wear them). Phase 3 the shards come back and close in.
    "void_herald": [
        { "id": "shards", "name": "Orbiting shards", "offset": Vector2(0.0, 0.0), "r": 1.15,
            "innate": Element.Kind.VOID, "armour": true, "wear": { 2: 0.0, 3: 0.04, 4: 0.3 },
            "tears": ["Drowned Rift", "Accretion", "Frozen Rift", "Smothered Rift", "Venomous Rift",
                "Caustic Rift", "Sanguine Rift", "Exorcised Rift", "Howling Rift", "Grounded Rift"],
            "tear_stagger": 0.35, "tear_damage": 0.03, "taken": 0.8 },
        { "id": "hollow", "name": "Hollow centre", "offset": Vector2(0.0, 0.0), "r": 0.55,
            "covered_by": "shards", "taken": 1.6 },
    ],
    # The Storm Warden: his lightning rods keep their charge. Stone on a charged rod is
    # Grounded (three tear them, as do fusions on the glass it leaves). The bare storm core
    # holds no charge of its own: steam it, and his own recharge strike, or your shock, sets
    # off a Storm Cloud inside him. Phase 2 the rods burst; phase 3 they stay off.
    "storm_warden": [
        { "id": "rods", "name": "Lightning rods", "offset": Vector2(0.0, -0.2), "r": 1.0,
            "innate": Element.Kind.SHOCK, "armour": true, "wear": { 2: 0.0, 3: 0.2, 4: 0.6 },
            "wear_by": { "Grounded": 0.34 }, "tear_stagger": 0.3, "stays_off": 3, "taken": 0.7 },
        { "id": "storm_core", "name": "Storm core", "offset": Vector2(0.0, 0.1), "r": 0.6,
            "covered_by": "rods", "taken": 1.5, "inert": [Element.Kind.SHOCK],
            "payoff": { "Storm Cloud": 0.03 } },
    ],
    # The Hive Mother: her spore sacs keep re-poisoning. Fire on them makes Smog on the sacs,
    # shock on the Smog is Firedamp, which blows them off (a burst and a third of the stagger
    # bar). Shock does nothing to a sac without Smog. In phase 2 she burrows and the sacs stay
    # above ground; in phase 3 the hive splits open on a soft brood chamber.
    "hive_mother": [
        { "id": "sacs", "name": "Spore sacs", "offset": Vector2(0.0, -0.75), "r": 0.7,
            "innate": Element.Kind.POISON, "armour": true, "tears": ["Firedamp"],
            "wear": { 2: 0.0, 3: 0.12, 4: 0.6 }, "tear_stagger": 0.3, "tear_damage": 0.04,
            "taken": 1.0, "inert": [Element.Kind.SHOCK] },
        { "id": "hive", "name": "Hive body", "offset": Vector2(0.0, 0.25), "r": 0.9,
            "taken": 0.8, "burrows": true },
        { "id": "brood", "name": "Brood chamber", "offset": Vector2(0.0, 0.25), "r": 0.5,
            "from_phase": 3, "taken": 1.8, "burrows": true },
    ],
    # The Brute King teaches stagger: any reaction on his bone plates cracks one, tearing
    # them staggers him, and the barrels he throws are fuel (a barrel blast is a fusion's
    # worth on his body; a swallowed barrel set off by fire or shock is a Gut Blast).
    "brute_king": [
        { "id": "plates", "name": "Bone plates", "offset": Vector2(0.0, 0.1), "r": 1.0,
            "armour": true, "wear": { 2: 0.04, 3: 0.08, 4: 0.5 }, "tears": ["Barrel Blast"],
            "tear_stagger": 0.35, "stays_off": 2, "taken": 0.7 },
        { "id": "hide", "name": "Hide", "offset": Vector2(0.0, 0.1), "r": 0.8,
            "covered_by": "plates", "taken": 1.25 },
        { "id": "crown", "name": "Bone crown", "offset": Vector2(0.0, -1.15), "r": 0.45,
            "from_phase": 3, "taken": 2.0 },
    ],
    "pyre_lord": [
        { "id": "armour", "name": "Slag armour", "offset": Vector2(0.0, 0.15), "r": 1.0,
            "innate": Element.Kind.FIRE, "armour": true, "tears": ["Storm Cloud"], "taken": 1.0,
            "inert": [Element.Kind.SHOCK, Element.Kind.ICE] },
        { "id": "core", "name": "Molten core", "offset": Vector2(0.0, 0.1), "r": 0.55,
            "covered_by": "armour", "holds": "MAGMA", "taken": 1.6, "only": [Element.Kind.ICE] },
        { "id": "crown", "name": "Fire crown", "offset": Vector2(0.0, -1.2), "r": 0.5,
            "innate": Element.Kind.FIRE, "taken": 1.2 },
    ],
}

## Bots print [BOSS-CHAIN], [STAGGER] and [BOSS-PHASE] lines (set by Main._setup_autotest).
static var log_enabled := false

var e: Enemy
var kind := ""
var parts: Array = []         # state dicts, see _make_part
var cur := -1                 # the focused part (its state lives in the Enemy's fields)
var stagger := 0.0            # 0..1
var stagger_t := 0.0          # > 0 while staggered
var staggers := 0
var _since_fill := 99.0
var _rest := 0.0              # > 0: the bar is resting after a stagger
var phase_at: Array = [0.5]
var age := 0.0                # seconds since the fight began (name card, logs)
var phase_times: Array = [0.0]
## name -> count of products on the body (the bot log's chain line).
var chain := {}


func _init(enemy: Enemy, boss_kind: String) -> void:
    e = enemy
    kind = boss_kind
    phase_at = PHASES.get(kind, [0.5]).duplicate()
    for d in PARTS.get(kind, []):
        parts.append(_make_part(d))
    if not parts.is_empty():
        cur = 0
        _load(0)


static func display_name(boss_kind: String) -> String:
    return NAMES.get(boss_kind, "The Boss")


func has_parts() -> bool:
    return not parts.is_empty()


func staggered() -> bool:
    return stagger_t > 0.0


func phases() -> int:
    return phase_at.size() + 1


func _make_part(d: Dictionary) -> Dictionary:
    var p := d.duplicate()
    p["states"] = {}
    p["compound"] = ""
    p["compound_time"] = 0.0
    p["origin"] = ""
    p["fusion_cd"] = 0.0
    p["integrity"] = 1.0
    p["broken"] = false
    p["regrow"] = 0.0
    p["wait"] = 0.0
    p["flash"] = 0.0
    var innate: int = int(d.get("innate", Element.Kind.NONE))
    if innate != Element.Kind.NONE:
        p["states"][innate] = 99.0
    return p


# --- Focus: which part an element lands on --------------------------------------------------


func part_world(i: int) -> Vector2:
    var p: Dictionary = parts[i]
    return e.global_position + Vector2(p["offset"]) * e.radius


func visible(i: int) -> bool:
    var p: Dictionary = parts[i]
    if p["broken"] or e._phase < int(p.get("from_phase", 0)):
        return false
    if p.get("burrows", false) and e.burrowed():
        return false
    var cover := String(p.get("covered_by", ""))
    if cover != "":
        for q in parts:
            if q["id"] == cover and not q["broken"]:
                return false
    return true


## Focus the visible part nearest to `world_pos` (edge distance, so a big part wins ties).
func focus_at(world_pos: Vector2) -> void:
    if parts.is_empty():
        return
    var best := -1
    var best_d := INF
    for i in parts.size():
        if not visible(i):
            continue
        var d := world_pos.distance_to(part_world(i)) - float(parts[i]["r"]) * e.radius
        if d < best_d:
            best_d = d
            best = i
    if best >= 0:
        focus(best)


func focus(i: int) -> void:
    if i == cur or i < 0 or i >= parts.size():
        return
    _store()
    cur = i
    _load(i)


func _store() -> void:
    if cur < 0:
        return
    var p: Dictionary = parts[cur]
    p["states"] = e.states
    p["compound"] = e.compound
    p["compound_time"] = e.compound_time
    p["origin"] = e.compound_origin
    p["fusion_cd"] = e.fusion_cd


func _load(i: int) -> void:
    var p: Dictionary = parts[i]
    e.states = p["states"]
    e.compound = p["compound"]
    e.compound_time = p["compound_time"]
    e.compound_origin = p["origin"]
    e.fusion_cd = p["fusion_cd"]


## The focused part ignores `kind` entirely (its `only` list), compound included.
func sealed(kind: int) -> bool:
    if cur < 0:
        return false
    var only: Array = parts[cur].get("only", [])
    return not only.is_empty() and not only.has(kind)


## `kind` neither stays on nor reacts with the focused part (it may still fuse a compound).
func inert(kind: int) -> bool:
    return cur >= 0 and (sealed(kind) or Array(parts[cur].get("inert", [])).has(kind))


func part_id() -> String:
    return String(parts[cur]["id"]) if cur >= 0 else ""


## Damage taken by a direct hit on the focused part, and the stagger bonus.
func taken_mult(direct: bool) -> float:
    var m := STAGGER_TAKEN if stagger_t > 0.0 else 1.0
    if direct and cur >= 0:
        m *= float(parts[cur].get("taken", 1.0))
    return m


# --- Clocks ---------------------------------------------------------------------------------


## Runs after the Enemy ticked its own (focused) clocks this frame.
func tick(delta: float) -> void:
    age += delta
    _rest = maxf(0.0, _rest - delta)
    if stagger_t > 0.0:
        stagger_t = maxf(0.0, stagger_t - delta)
    else:
        _since_fill += delta
        if _since_fill > STAGGER_HOLD:
            stagger = maxf(0.0, stagger - STAGGER_DRAIN * delta)
    if parts.is_empty():
        return
    _store()
    for i in parts.size():
        var p: Dictionary = parts[i]
        p["flash"] = maxf(0.0, float(p["flash"]) - delta)
        if i != cur:
            var st: Dictionary = p["states"]
            for k in st.keys():
                st[k] = float(st[k]) - delta
                if float(st[k]) <= 0.0:
                    st.erase(k)
            if p["compound"] != "":
                p["compound_time"] = float(p["compound_time"]) - delta
                if float(p["compound_time"]) <= 0.0:
                    p["compound"] = ""
            p["fusion_cd"] = maxf(0.0, float(p["fusion_cd"]) - delta)
        if p["broken"]:
            p["regrow"] = float(p["regrow"]) - delta
            if float(p["regrow"]) <= 0.0:
                _reform(i)
            continue
        if not visible(i):
            continue
        var innate: int = int(p.get("innate", Element.Kind.NONE))
        var holds := String(p.get("holds", ""))
        if innate != Element.Kind.NONE and not p["states"].has(innate) and p["compound"] == "":
            p["wait"] = float(p["wait"]) + delta
            if float(p["wait"]) >= INNATE_WAIT:
                p["wait"] = 0.0
                p["states"][innate] = 99.0
        elif holds != "" and p["compound"] == "" and float(p["fusion_cd"]) <= 0.0:
            p["wait"] = float(p["wait"]) + delta
            if float(p["wait"]) >= HOLD_WAIT:
                p["wait"] = 0.0
                p["compound"] = holds
                p["origin"] = String(Fusions.compound(holds).get("members", [""])[0])
                p["compound_time"] = 99.0
        else:
            p["wait"] = 0.0
    if not visible(cur):
        for i in parts.size():
            if visible(i):
                cur = i
                break
    _load(cur)


# --- Products on the body -------------------------------------------------------------------


## A reaction (tier 2), fusion (3) or cataclysm (4) on this boss. `on_part`: it happened on
## the focused part (a fusion of the part's own compound, or a reaction with its states).
func on_product(product: String, tier: int, on_part: bool) -> void:
    add_stagger(tier, 1.0 if on_part or parts.is_empty() else STAGGER_PATCH_SHARE)
    if not on_part or cur < 0 or e.hp <= 0.0:
        return
    var p: Dictionary = parts[cur]
    p["flash"] = 0.35
    var key := "%s@%s" % [product, p["id"]]
    chain[key] = int(chain.get(key, 0)) + 1
    if log_enabled:
        print("[BOSS-CHAIN] t=%.1f part=%s %s tier=%d phase=%d" % [age, p["id"], product, tier, e._phase])
    if p.get("armour", false):
        var tears: Array = p.get("tears", [])
        var wear: Dictionary = p.get("wear", ARMOUR_WEAR)
        var wear_by: Dictionary = p.get("wear_by", {})
        var lost := 1.0 if tears.has(product) else float(wear_by.get(product, wear.get(tier, 0.0)))
        p["integrity"] = float(p["integrity"]) - lost
        if float(p["integrity"]) <= 0.0:
            tear(cur, product)
    elif Dictionary(p.get("payoff", {})).has(product):
        Elements.reaction_fired.emit("OVERLOAD!", part_world(cur), Color(0.95, 0.95, 0.5))
        add_stagger(4)
        e.take_damage(e.max_hp * float(p["payoff"][product]), Color(0.95, 0.95, 0.5), false)
    elif product == "Obsidian" and p.get("holds", "") == "MAGMA":
        # The glassed core shatters: the payoff of the whole chain.
        Elements.reaction_fired.emit("SHATTERED!", part_world(cur), Color(0.75, 0.6, 1.0))
        add_stagger(4)
        e.take_damage(e.max_hp * SHATTER_SHARE, Color(0.75, 0.6, 1.0), false)


func add_stagger(tier: int, share: float = 1.0) -> void:
    fill(float(STAGGER_FILL.get(tier, 0.0)) * share)


## Adds `amount` (0..1) to the stagger bar; a full bar staggers.
func fill(amount: float) -> void:
    if stagger_t > 0.0 or _rest > 0.0 or e.hp <= 0.0:
        return
    _since_fill = 0.0
    stagger += amount
    if stagger >= 1.0:
        stagger = 0.0
        stagger_t = STAGGER_SECS
        _rest = STAGGER_SECS + STAGGER_REST
        staggers += 1
        e.velocity = Vector2.ZERO
        Elements.reaction_fired.emit("STAGGERED", e.global_position + Vector2(0, -e.radius * 2.0), Color(1.0, 0.9, 0.4))
        Sfx.play("boss_phase")
        var fx := Strike.fx_of(e)
        if fx != null:
            fx._shake(7.0)
        if log_enabled:
            print("[STAGGER] t=%.1f kind=%s n=%d hp=%.2f" % [age, kind, staggers, e.hp / e.max_hp])


## Armour torn off: the part is gone until it re-forms; what it covered is bare.
func tear(i: int, by: String) -> void:
    var p: Dictionary = parts[i]
    if p["broken"]:
        return
    p["broken"] = true
    p["integrity"] = 0.0
    p["states"] = {}
    p["compound"] = ""
    p["regrow"] = ARMOUR_REGROW_LATE if e._phase >= 3 else ARMOUR_REGROW
    if e._phase >= int(p.get("stays_off", 99)):
        p["regrow"] = INF
    if i == cur:
        _load(i)
    fill(float(p.get("tear_stagger", 0.0)))
    if p.has("tear_damage"):
        e.take_damage(e.max_hp * float(p["tear_damage"]), Color(0.75, 0.9, 0.4), false)
    Elements.reaction_fired.emit("%s torn off!" % p["name"], part_world(i), Color(1.0, 0.75, 0.4))
    Elements.nova.emit(part_world(i), e.radius * 2.5, Color(1.0, 0.55, 0.2, 0.7))
    Sfx.play("die_elite")
    var fx := Strike.fx_of(e)
    if fx != null:
        fx._shake(6.0)
    if log_enabled:
        print("[BOSS-CHAIN] t=%.1f part=%s TORN by=%s phase=%d" % [age, p["id"], by, e._phase])


func _reform(i: int) -> void:
    var p: Dictionary = parts[i]
    p["broken"] = false
    p["integrity"] = 1.0
    p["states"] = {}
    var innate: int = int(p.get("innate", Element.Kind.NONE))
    if innate != Element.Kind.NONE:
        p["states"][innate] = 99.0
    Elements.reaction_fired.emit("%s re-forms" % p["name"], part_world(i), Color(1.0, 0.5, 0.25))
    # Whatever it covers loses its compound under the new plates.
    for q in parts:
        if String(q.get("covered_by", "")) == p["id"]:
            q["compound"] = ""
    if log_enabled:
        print("[BOSS-CHAIN] t=%.1f part=%s REFORMED phase=%d" % [age, p["id"], e._phase])


func part_index(id: String) -> int:
    for i in parts.size():
        if parts[i]["id"] == id:
            return i
    return -1


# --- Phases ---------------------------------------------------------------------------------


## The phase health fraction `f` belongs in (1 = the first).
func phase_for(f: float) -> int:
    var n := 1
    for at in phase_at:
        if f <= float(at):
            n += 1
    return n


## A new phase began (Enemy._tick_boss_passive). Boss-specific changes to the body.
func on_phase(n: int) -> void:
    phase_times.append(age)
    Music.boss_phase(n)
    if log_enabled:
        print("[BOSS-PHASE] t=%.1f kind=%s phase=%d hp=%.2f" % [age, kind, n, e.hp / e.max_hp])
    match kind:
        "brute_king":
            var pl := part_index("plates")
            if n == 2 and pl >= 0:
                # The plates fall away for good; he starts swallowing his barrels.
                if parts[pl]["broken"]:
                    parts[pl]["regrow"] = INF
                else:
                    tear(pl, "phase 2")
            elif n == 3:
                Elements.reaction_fired.emit("The crown is bare", part_world(part_index("crown")), Color(1.0, 0.85, 0.5))
        "hive_mother":
            if n == 2:
                Elements.reaction_fired.emit("She digs in", e.global_position + Vector2(0, -e.radius * 1.8), Color(0.75, 0.9, 0.4))
            elif n == 3:
                Elements.reaction_fired.emit("The hive splits open", part_world(part_index("brood")), Color(0.95, 0.95, 0.5))
        "storm_warden":
            var rd := part_index("rods")
            if n == 2 and rd >= 0:
                tear(rd, "phase 2")   # the rods burst and the arena rains lightning
            elif n == 3 and rd >= 0:
                parts[rd]["regrow"] = INF if parts[rd]["broken"] else parts[rd]["regrow"]
                if not parts[rd]["broken"]:
                    tear(rd, "phase 3")
                Elements.reaction_fired.emit("He becomes the storm", e.global_position + Vector2(0, -e.radius * 1.8), Color(0.95, 0.95, 0.5))
        "void_herald":
            var sh := part_index("shards")
            if n == 3 and sh >= 0 and parts[sh]["broken"]:
                _reform(sh)   # the shards come back, and close in
        "pyre_lord":
            var a := part_index("armour")
            if n == 2 and a >= 0:
                # The armour cracks open: the core is bare and weak to ice.
                tear(a, "phase 2")
            elif n == 3 and a >= 0:
                # The forge floods: the slag re-forms at once, so the chain starts over.
                if parts[a]["broken"]:
                    _reform(a)


## A blast at `at` hit this boss (a barrel he threw, his own swallowed barrels): counts as a
## product of `tier` on the part nearest to it, plus `share` of his health.
func blast(product: String, at: Vector2, tier: int, share: float) -> void:
    if e.hp <= 0.0:
        return
    focus_at(at)
    on_product(product, tier, true)
    e.take_damage(e.max_hp * share, Color(1.0, 0.6, 0.25), false)


func any_visible() -> bool:
    for i in parts.size():
        if visible(i):
            return true
    return parts.is_empty()


## The bot log's summary of the fight.
func summary() -> String:
    var keys := chain.keys()
    keys.sort()
    var bits: Array = []
    for k in keys:
        bits.append("%s=%d" % [k, chain[k]])
    var pt: Array = []
    for t in phase_times:
        pt.append("%.1f" % t)
    return "phases=%d/%d at=[%s] staggers=%d chain={%s}" % [phase_times.size(), phases(), ",".join(pt), staggers, ", ".join(bits)]
