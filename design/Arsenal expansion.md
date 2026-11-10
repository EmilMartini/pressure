# Arsenal expansion

Emil asked on 2026-11-10 for a much bigger arsenal, after the comparison with Enter the
Gungeon's 270+ weapons. He wants hundreds of items and weapons, weapon families beyond guns
(melee and others), and weapon rarity, so that finding a great weapon is rare and feels good.

This file records his decisions (top) and the full spec built on them (sections 0 to 10).
The spec was written on 2026-11-10 against main at `f4da3e0` after reading
`design/Core loop reset.md`, `GDD.md`, `gun_library.gd`, `gun_data.gd`, `gun.gd`, `focus.gd`,
`items.gd`, `drops.gd`, `progress.gd`, `lessons.gd` and the shop pricing in `floor_gen.gd`.
No game code changed in that session.

## Decisions (Emil, 2026-11-10)

| # | Decision |
|---|---|
| A1 | **Melee auto-swings at the nearest enemy**, like Brotato's melee: swords, axes, hammers, spears, whips and fists swing or thrust within a short reach. You play melee by positioning. |
| A2 | **Four new families** beside today's guns: melee; thrown and lobbed (boomerangs, knives, grenades, mortars, chakrams); summons and drones (turrets, familiars, orbiting blades, drones); auras and traps (damage zones, mines, totems, elemental fields you leave behind). |
| A3 | **Five rarity tiers for weapons:** Common, Uncommon, Rare, Epic, Legendary. A legendary shows up about once every few runs and has a unique, run-defining effect. Copies still merge into higher tiers, as today. |
| A4 | **Size:** about 150 weapons and about 300 items, up from 43 weapons and 145 items, built in tested batches. More can follow later. |
| A5 | **Mostly elemental.** Most weapons carry an element, so reactions stay the heart of the game. A few plain or Stone weapons give contrast, and some legendaries carry two elements. |
| A6 | **Mostly unlocked over time.** A fresh save starts with a core set, and the rest unlock through lessons, challenges and milestones, Isaac-style. |
| A7 | **Code-drawn art now, the art pack later.** Each family gets a consistent code-drawn look now. When Emil picks an art pack, its weapon sprites replace them. |

## Rules that still apply

- **The core loop reset holds:**
  - four weapon slots;
  - auto-aim targets the closest enemy (decision 21), and extra projectiles or beams go to different enemies;
  - pick 1 of N rewards;
  - items stack with no slots, on one readable card;
  - almost no text in fights.
- **Readability:** every weapon family must stay readable. Hostile things stay the clearest on screen, and your own effects stay quiet.
- **Balance:** each batch has to pass the stand-still and mover pressure checks, the economy and loot checks, the fusion probe and `tools/exe_smoke.sh`.
- **No windows:** sessions run headless only, and screenshots wait until Emil is away.
- **Art:** no generative AI art.

---

## 0. The spec on one page

| Area | What we build | Section |
|---|---|---|
| **One weapon, five families** | Every weapon is still a `Gun` in one of the four slots, fed by `Focus`. `GunData` gets a `family` (gun, melee, thrown, summon, ground) and a `rarity`. Twelve of today's 43 guns already belong to a new family (Storm Pike is melee, the boomerangs and flasks are thrown, the Kettle Gun is a summon, the mines and the nova are ground weapons) | 2 |
| **Melee** | Seven swing styles (sweep, cleave, thrust, slam, lash, jab, spin). It swings only when an enemy is within reach, hits up to 12 in its arc, and deals about 30% more than a gun of its weight because you must stand close | 2.3 |
| **Thrown and lobbed** | Knives that stick and come back, grenades, javelins, bolas, discs and stars on the projectile path, plus today's boomerangs, mortars and flasks. Lobbed things cast a small shadow, never a target marker | 2.4 |
| **Summons and drones** | Drones, familiars, orbiters, swarms, a golem and turrets. They pick the enemy closest to them, stay within 260 px of you, never block or draw enemies, and are capped at 16 bodies in all | 2.5 |
| **Auras and traps** | Rings around you, trails, totems, fields, snares, glyphs and mines. They are capped at 40 ground effects in all. Your ground effects have a dashed rim and a faint fill that never pulses, so they never look like a hostile hazard | 2.6 |
| **Rarity** | Rarity is a property of the weapon (Gungeon style). The tier, I to IV, still comes from merging copies (Brotato style). Rarity buys mostly behaviour and only a small power premium (0 to 25%). Weapons have their own odds table per floor, and luck works as it does for items | 3 |
| **Legendaries** | 18 of them, each with a rule that changes how you play (section 3.5). About 1 run in 3 that reaches floor 4 is offered one. A hidden drought rule guarantees one after four dry runs. The find gets a gold card, a bell, a top-band banner and a gold flash, all at the pickup and never mid-fight | 3.5, 3.6 |
| **The list** | 151 weapons: 46 guns, 28 melee, 26 thrown, 25 summons and 26 ground. By rarity: 39 Common, 38 Uncommon, 36 Rare, 20 Epic and 18 Legendary. Each has its own one-line reason to exist | 4 |
| **Items** | 145 become 300. 48 are family items, and four new tags (Blade, Thrown, Swarm, Ground) count your weapons as well as your items, Brotato-class style. About 70% of items change behaviour and 30% are stats. Synergies grow from 20 to 50, 10 of them weapon pairs | 5 |
| **Unlocks** | A fresh save starts with 8 weapons, today's 4 plus one starter per new family. The rest come from play goals, family mastery, death lessons, Trials, milestones and one feat per legendary. That is about 4 unlocks a run at first, falling to about 1 every 2 runs after 60 hours | 6 |
| **Looks** | `weapon_looks.gd` draws every weapon and effect in one style per family. One function swaps in an art-pack sprite when one exists | 7 |
| **Tests** | Today's checks, plus a family probe, a stand-still check per family, `--arsenal-perf` (40 enemies, 60 fps), `--loot-sim` for the legendary share, and `--legendary-probe` | 8 |
| **Batches** | 1: weapon system and melee. 2: thrown and new guns. 3: summons. 4: auras and traps. 5: legendaries, the last items, synergies and the unlock pacing | 9 |

---

## 1. What the best games do, as principles

| Game | What makes its weapons exciting | What we take |
|---|---|---|
| Enter the Gungeon | Every gun has a gimmick you can describe in one sentence. Quality letters D to S are fixed per gun, and the chest colour tells you the quality before you open it. Many guns are funny or rule-breaking rather than just stronger. Named pairs ("synergies") show a marker when you hold both | **One gimmick per weapon** and no stat-only twins. **Rarity is fixed per weapon** and readable before you read the card (the glow). **Weapon pairs** form synergies |
| The Binding of Isaac | Items visibly change your shots, and stacking them makes strange combinations. Each room type has its own item pool, so a treasure room feels different from a shop. The unlock list is long, with clear goals and a few secret ones, so every run moves something forward. Its legendary-feeling items change the rules (Brimstone, Mom's Knife) | **Legendaries change rules, not numbers.** **Pools per source** (treasure never Common, the boss pays Rare or better). **A long, visible unlock list** with some hidden feats |
| Brotato | Weapons belong to classes (blade, gun, elemental and so on), and carrying several of one class gives a set bonus. Copies merge into tiers I to IV. Higher tiers show up in the shop later in the run, and luck shifts the odds. Melee and ranged use different stats, and the shop tilts toward what you carry | **Family tags count weapons** toward resonances. **Merging stays.** **Commons arrive at tier II deeper**, so they stay useful. **Stats map per family**, and the build tilt includes family |
| Vampire Survivors | Every weapon fires on its own pattern with no aiming, so the choice is the build. A weapon plus its paired passive evolves into something new and spectacular. Many unlocks have secret conditions. Late runs turn into a spectacle | **Auto-fire patterns** differ by family, so four weapons give four rhythms. **Weapon plus item synergies** play the part of evolutions. We do **not** take the late-run visual flood, because the quiet-fight rule wins |

Three rules follow from this:
1. **A weapon has a reason to exist.** Its card line names a behaviour no other weapon of its family and rarity has. A new element on an old trick is not enough, unless the style is a family's basic one (the sweep, the knife, the drone) and the element changes how it plays.
2. **Rarity is felt before it is read.** The glow, the sound and the card frame tell you the rarity first. The higher the rarity, the stranger the rule.
3. **Variety comes from rhythm, not noise.** Four weapons from four families should feel like four rhythms (a swing, a throw, a buzzing drone, a ticking ring) without the screen getting louder.

---

## 2. The weapon system

### 2.1 One weapon, five families

The code keeps its names: a weapon is a `Gun` built from a `GunData` by the `Guns` autoload.
Ids, the `gun:` unlock keys, Mastery and telemetry stay as they are, so no save migration is
needed. On screen, "gun" becomes **"weapon"** everywhere: cards, the Build page, the hub and
the journal.

**New `GunData` fields:**

| Field | Meaning |
|---|---|
| `family` | `gun`, `melee`, `thrown`, `summon` or `ground`. Comes from the archetype through `GunData.FAMILY_OF`, unless the entry names one |
| `rarity` | 0 to 4 (Common to Legendary). Required for every weapon |
| `style` | The sub-kind inside the family: a melee swing style, a thrown kind, a summon kind or a ground kind (tables below) |
| `cap` | Live bodies or effects per weapon (summons, traps, knives in the floor) |
| `unique` | Legendaries only: the id of their rule in `legendary.gd` |

Existing fields keep their meanings: `max_range` is reach, throw distance or radius; `arc_deg`
is the swing arc; `linger` is how long a summon, trap or zone lasts. **Weight stays** (carry
budget and move speed, GDD "Weight"). **Pressure stays** by the element rule: hot elements
push the gauge up and cold ones pull it down, per swing, throw, summon shot or aura tick,
scaled so pressure per second matches a gun of the same weight.

**New mechanics** (`GunData.ARCHETYPES` and `Gun.fire`):

| Family | Mechanic | Styles | Code |
|---|---|---|---|
| Gun | `shot`, `beam`, `cone`, `chain`, `charge` (as today) | New behaviours: `revolver` (magazine and reload), `bubble`, `bow`, `sticky`, `reflect` (a beam that bounces off walls), `harpoon`, `sniper`, `hymn` | `gun.gd`, `projectile.gd`, `beam.gd` |
| Melee | `melee` (today: one sweep) | `sweep`, `cleave`, `thrust`, `slam`, `lash`, `jab`, `spin` | new `melee.gd` (swing shapes); `gun.gd` calls it |
| Thrown | `shot` with thrown behaviours | `boomerang`, `lob` and `pool` (today's), plus `knife`, `grenade`, `javelin`, `bola`, `disc`, `star`, `anchor` | `projectile.gd`, new `thrown.gd` for stick, recall and fuse logic |
| Summon | `summon` (and today's `turret`) | `drone`, `familiar`, `orbit`, `swarm`, `golem`, `turret`, `shade` | new `summon.gd` (one class with a kind); `turret.gd` stays |
| Ground | `ground` (and today's `mine` and `nova`) | `aura`, `pulse`, `trail`, `totem`, `field`, `snare`, `glyph`, `pod`, `mine` | new `ground_zone.gd`; `mine.gd` stays |

**Today's 43 guns by family:** guns 31; melee 1 (Storm Pike); thrown 7 (Zephyr Rang, Rime
Chakram, Oil Slinger, Acid Flask, Plague Mortar, Boulder Mortar, Napalm Lobber); summon 1
(Kettle Gun); ground 3 (Frost Caster as a `pulse`, Tar Mortar and Corrosion Burst as `mine`).
Their mechanics don't change. Only their family, and so their tag and look, does.

**The four slots and Focus.** Any mix of families goes in the four slots. `Focus` gives each
weapon its targets as today (closest first, at most 2 weapons on one enemy, extra projectiles
to different enemies). Each family uses them this way:
- **Guns and thrown weapons:** as today.
- **Melee:** takes no Focus slot. It swings at the closest enemy within reach, and the swing
  hits everything in its arc. With nothing in reach it does not swing, and the weapon turns
  to face the closest enemy so you can see it is ready.
- **Summons:** each body asks `Focus.pick_from(origin, reach, n)` with its own position, every
  0.2 s, and takes the enemy closest to *itself*. Bodies of one weapon take different targets
  when there are two or more to choose from. Summons don't count against the 2-per-enemy limit.
- **Ground weapons:** rings and trails need no target. Totems, fields, snares and mines are
  placed from the closest enemy (section 2.6).
- **Manual aim (RT):** guns and thrown weapons fire where you aim; melee swings that way when
  an enemy is within reach in that direction; summons and ground weapons ignore it.

### 2.2 How item stats reach each family

Brotato's lesson: a stat that does nothing for your weapons is a dead card. Every shared stat
maps to every family. Where a mapping would be silly, the card says so and the build tilt
(section 5.4) offers it less often.

| Stat | Guns | Melee | Thrown | Summons | Ground |
|---|---|---|---|---|---|
| Damage, crit, reaction power | yes | yes | yes | yes | yes |
| Fire rate | shots | swings | throws | summon attack rate | ticks, and how often traps are laid |
| +1 projectile | +1 shot | +1 swing (back and forth, as Storm Pike today) | +1 thrown | +1 to the cap | +1 to the trap cap; rings +15% radius |
| Pierce | pierce | +10% reach per point (today's rule) | pierce | the summons' shots pierce | +10% radius |
| Bounce | ricochet | cleave reaches 1 more enemy behind the first | +1 bounce or return hit | the summons' shots bounce | no effect (the card says so) |
| Range | range | half the bonus as reach | throw distance | leash and reach | half the bonus as radius |
| Shot speed | speed | swing speed (shorter wind-up) | flight speed | movement speed | no effect |
| Size | shot size | arc +5° per 10% | object size | body size, and contact reach for orbits | radius |
| Duration (states) | as today | as today | pools and stuck knives last longer | temporary summons last longer | zones last longer |

### 2.3 Melee

| Style | Reach | Arc | Swings a second | What makes it different | Weight |
|---|---|---|---|---|---|
| `sweep` | 90 to 110 px | 120 to 150° | 1.2 to 1.8 | The plain all-rounder in front of you | 2 to 3 |
| `cleave` | 100 to 120 | 200° | 0.8 to 1.1 | Wide and slow; hits behind you a little; big knockback | 3 to 5 |
| `thrust` | 140 to 170 | 25° | 1.4 to 2.2 | A long, narrow line that pierces everything in it | 2 to 4 |
| `slam` | a 70 px circle, 60 px ahead | circle | 0.7 to 1.0 | Area at a point; staggers ordinary enemies for 0.3 s (not elites or bosses) | 3 to 5 |
| `lash` | 160 to 190 | 60° | 1.0 to 1.4 | Long reach; the outer 30% (the tip) hits for x1.5, so it rewards keeping a distance | 2 to 3 |
| `jab` | 65 to 80 | 70° | 3.0 to 4.0 | Fast hits; every 4th is a finisher at x2.5 | 1 to 2 |
| `spin` | 100 | 150°, and every 3rd swing a full 360° | 1.0 to 1.4 | Sweeps that end in a spin around you | 2 to 4 |

- **Cleave:** the first enemy takes 100%, every other one in the arc takes 75%. At most 12
  enemies per swing, closest first (this bounds the cost at 40 enemies).
- **Power:** single-target damage per second is about 130% of a gun's band for the same weight
  (the band is in the `gun_library.gd` header). This pays for the risk of standing close. Pack
  damage is held to at most the best gun of that weight on the `--gun-probe` pack number.
- **How it reads:** the weapon is drawn at the figure, pointing at the closest enemy. A swing
  tilts back over 0.05 s, then draws a thin smear of the swing's shape in the element colour
  at 35% alpha for 0.1 s. Hits use today's hit feel (white hit frame, sized kick). Ordinary
  swings get no screen shake and no hit-stop; weight-5 finishers get the existing 0.02 s kick.
  The swing sound sits 10 dB under a gun shot.
- **Enemy shots:** melee does not block shots, except the weapons that say so (Parry Blade
  cuts them, Mirrorblade reflects them).
- **Standing still:** melee can't make standing still safe. It only reaches what reaches you,
  and the stand-still check runs with a melee-only build (section 8).

### 2.4 Thrown and lobbed

| Style | Path | Landing or return | Weapons |
|---|---|---|---|
| `boomerang` | Out to its reach, then back to you | Hits on both legs (today) | Zephyr Rang, Rime Chakram |
| `knife` | A straight fan | Sticks in the floor or in an enemy for 1.5 s, then flies back to you, hitting along the way. At most 12 stuck per weapon | Steel Knives, Venom Fan, Storm Kunai, Mother of Knives |
| `disc` | Bounces from enemy to enemy (3 to 5 jumps) | Then returns | Tide Discus, Halo Disc, Prism Disc |
| `star` | Flies to its target and circles it twice at 40 px | Then returns | Wind Star |
| `grenade` | Rolls and bounces once off walls or enemies | Bursts after a 0.8 s fuse | Clay Grenade, Void Grenade, Cluster Bomb |
| `javelin` | Straight and heavy, slower | Pierces; the last enemy hit is pinned for 1 s | Frost Javelin, Etching Javelin |
| `bola` | Straight | Wraps the first enemy: it stops for 1.2 s (elites 0.4 s) | Shock Bola |
| `lob` | An arc over cover (today's mortar) | Splash where it lands | Boulder Mortar, Napalm Lobber, Skyfall |
| `pool` | A short arc (today's flask) | Leaves a pool | Oil Slinger, Acid Flask, Plague Mortar, Fire Bottle, Holy Water |
| `anchor` | Thrown out, then dragged back on a chain | Pulls the enemies it hit back toward you | Drowned Anchor |

- **Return paths** fly at 1.2 times the outward speed, toward where you are *now*, so moving
  matters. A returning object that reaches you disappears quietly, with no catch effect and no
  sound.
- **Arcs:** a lob takes 0.5 to 0.9 s and draws a small, dark ground shadow (an ellipse, 25%
  alpha) under its path. **Never a landing marker:** a circle on the floor is how hostile
  lobbers warn you (`enemy` telegraphs), and ours must not look like one.
- **Power:** single-target damage per second is 95 to 105% of the gun band. Thrown weapons
  win on returns, pins and pools, not on raw damage.
- **Cost:** everything here runs on the `Projectile` path with the existing pooling. Stuck
  knives are inert sprites with one timer each.

### 2.5 Summons and drones

| Style | What it is | Cap per weapon | Lasts |
|---|---|---|---|
| `drone` | Hovers 40 to 60 px from you and shoots or beams its own target | 1 to 2 | The whole floor; it reappears in each room |
| `familiar` | Runs at enemies and bites (contact hits) | 1 to 3 | The whole floor |
| `orbit` | Circles you (40 to 110 px) and hits what it touches | 2 to 3 bodies | Always |
| `swarm` | Small fliers: each strikes once, then respawns at you after 2 s | 3 to 6 | Always |
| `golem` | A big, slow walker that follows you and slams packs | 1 | The whole floor |
| `turret` | Deployed toward the enemy, fires on its own (today's Kettle Gun) | 1 (+1 per extra projectile) | `linger` seconds |
| `shade` | Raised by a kill (legendaries only) | 6 | 8 s |

Rules that keep summons fair and cheap:
- **Leash:** no summon goes more than 260 px from you. Summons fight where you are, not
  off-screen.
- **They don't tank.** Enemies never target summons, and summons don't collide with enemies or
  block their shots. So summons can't make standing still safe; the threat stays on you.
- **They target by distance:** each body takes the enemy closest to itself (decision 21),
  retargeting every 0.2 s, never every frame.
- **Caps:** at most 16 summon bodies across all four slots (swarm fliers count). When a
  new one would pass the cap, the oldest temporary body (a shade or a turret) goes first; if
  there are none, the new body is not made. Co-op: 16 per player.
- **Power:** single-target damage per second is 65 to 75% of the gun band for the weight.
  Summons need no aim, so they pay for it in damage.
- **How they show:** small (10 to 18 px for drones, familiars and orbiters; 4 px swarm fliers;
  the golem 26 px), with an element-coloured core and a dark outline. Each sits on today's
  friend marker (GDD "Friend or foe"): a small ring in the player's colour under the body.
  They have no health bars and no text. Their shot sounds sit 6 dB under yours, with at most 4
  per 0.1 s.

### 2.6 Auras and traps (the ground family)

| Style | Placed | Size | Lasts | Cap per weapon |
|---|---|---|---|---|
| `aura` | A ring around you, on whenever an enemy is inside | 60 to 110 px | Always (ticks 2 to 4 a second) | 1 |
| `pulse` | A ring that rolls out from you (today's nova) | to 110 to 160 px | 0.4 s | n/a |
| `trail` | Behind you as you move: segments every 24 px | 18 px wide | 2 to 3 s | 30 segments |
| `totem` | At your feet | 90 to 130 px reach | 6 to 8 s | 2 to 3 |
| `field` | Under the closest pack: the densest point within 60 px of the closest enemy | 70 to 100 px | 3 to 5 s | 2 |
| `snare` | In the closest enemy's path (where it will be in 0.6 s), 40 to 220 px from you | 30 px | Until stepped on, at most 10 s | 3 to 4 |
| `glyph` | Where an enemy died | 30 to 40 px | Until stepped on, at most 8 s | 6 |
| `pod` | Like a snare, but it bursts when an enemy comes within 50 px | 50 px | 8 s | 4 |
| `mine` | Tossed toward the target (today) | `aura_radius` | `linger` | 6 (today's `MINE_CAP`) |

- **Global cap:** at most 40 of your ground effects alive at once (trail segments count as
  one per 3). The oldest goes first. Today's pools and dash-trail patches count too.
- **Ticks:** each zone gathers its enemies once per tick through one shared spatial query
  (`Strike.enemies_in_circle`), never per frame.
- **Standing still:** rings are small (they reach only what is already near you), and trails
  reward moving. The stand-still check runs with a ground-only build (section 8).
- **Power:** single-target damage per second is 55 to 65% of the gun band. They make up for it
  on packs and with states, and their pack number may reach 110% of the best gun of that
  weight.

**How the floor shows them**, the rule that keeps hostile hazards readable:

| | Your ground effects | Hostile hazards (unchanged) |
|---|---|---|
| Rim | Dashed or dotted, 1 px, 50% alpha | Solid and bright |
| Fill | At most 15% alpha, in the element colour | Strong, warning colours |
| Motion | None; it fades over its last 1 s | Pulses, grows toward the hit |
| Layer | The floor layer, under enemies and every hostile telegraph | Above |

A ring around you is drawn as a dashed circle only, with no fill. A totem is a small pillar
with an element gem. A trap is a jagged ring the size of the trap. A glyph is a three-stroke
rune. A trail is a dotted line.

### 2.7 Performance at 40 enemies

The target is the camera test's: 60 fps with the 1% low around 55 in a full floor-3 arena
(40 enemies), measured on Emil's PC only while it is idle. The headless `--perf` engine
timers (`render.cpu`, script time) are the day-to-day check.

| Budget | Limit |
|---|---|
| Melee | One cone query per swing and at most 12 hits. No per-frame work while idle |
| Thrown | The projectile path and pool. Stuck knives: one timer each, no physics |
| Summons | 16 bodies. Retarget every 0.2 s. Contact checks through one query per body per 0.1 s. One `_draw` per body, with no per-frame allocations |
| Ground | 40 effects. One spatial query per zone per tick. Trail segments merged and drawn as one polyline per weapon |
| All four families at once | At most 2 ms of extra script time per frame on `--arsenal-perf` (section 8) against today's storm build in the same arena |

### 2.8 Readability, with your effects kept quiet

- **Layer order, bottom to top:** floor, your ground effects, your summons, enemies, your shots
  and swings, hostile shots and telegraphs, the HUD. A summon never covers an enemy.
- The clarity pass's brightness caps apply to every new effect. No new effect may use the
  hostile warning palette (the telegraph reds and oranges at full saturation) as a fill.
- **No new fight text.** No summon names, no "trap set", no damage numbers beyond today's
  big-hit rule.
- **Sound:** swings 10 dB under gun shots, summons 6 dB under, ground ticks silent (a zone
  makes a sound only when it is placed).
- **A test, not taste:** `--read-shot` gets a family mode (section 8) that renders a floor-3
  fight per family and checks that hostile shots are never drawn under one of ours.

---

## 3. Rarity

### 3.1 What rarity means

**Rarity is fixed per weapon** (Gungeon style); the **tier** (I to IV) still comes from
merging copies and the Gunsmith (Brotato style). A weapon's rarity never changes.

| Rarity | Behaviour | Power premium on the band | Card frame |
|---|---|---|---|
| Common | One plain rule. The family's basic move with an element | x1.00 | Today's Common plate |
| Uncommon | One rule with a twist (a finisher, a split, a pull) | x1.05 | Uncommon |
| Rare | A mechanic that plays differently (cutting shots, reeling foes in, pins) | x1.10 | Rare |
| Epic | Two rules that work together, often with two elements that react with each other | x1.18 | Epic, pulsing at 1 Hz |
| Legendary | A unique rule that changes how the run plays, often by touching your other weapons | x1.25, plus the rule | Gold, section 3.6 |

The premium is small on purpose: the power curve follows measured damage (Core loop reset,
section 9), and a big premium would just shorten bosses. Rarity buys *strangeness*. The
existing rule holds inside each family, weight and rarity: no weapon beats another by more
than 5% on both the single and the pack number.

### 3.2 Where weapons come from, and the odds

Weapon cards replace item cards in these rows; they don't add cards (the cap of 15 cards a
floor stays).

| Source | Weapon cards | Rarity |
|---|---|---|
| First two arenas of floor 1 | Pick 1 of 2, twice (today) | Common or Uncommon only. One of the two is from a family you don't carry yet, when one is unlocked |
| Shop (1 per floor) | The 4th ware is a weapon 70% of the time, a mod 30% (today it is "a gun or a mod") | Shop table below |
| Treasure room | One of the 2 or 3 cards is a weapon 35% of the time | Never Common; Legendary as in the treasure column |
| Boss | From floor 2, one of the 3 cards is a weapon 25% of the time | Rare or better |
| Challenge room | One of the 3 is a weapon 30% of the time | Rare or better |
| Deal room | One of the 2 is a weapon 40% of the time | Epic or Legendary |

**Weapon odds by floor (shop):**

| Floor | Common | Uncommon | Rare | Epic | Legendary | Legendary in treasure |
|---|---|---|---|---|---|---|
| 1 | 65% | 30% | 5% | 0% | 0% | 3% |
| 2 | 45% | 35% | 15% | 4% | 1% | 5% |
| 3 | 30% | 35% | 23% | 9.5% | 2.5% | 8% |
| 4 | 20% | 32% | 29% | 15% | 4% | 11% |
| 5 | 12% | 28% | 33% | 21% | 6% | 14% |

Boss rows use the shop row with everything under Rare moved into Rare, as for items. The
tables live in `Guns.RARITY_ODDS` and `Guns.TREASURE_LEGENDARY`, next to `Items.SHOP_ODDS`,
and go through the same `rarity_weights` code path with a `weapon` flag. The Shrine's rarity
unlocks still cap the top rarity: no Legendary weapon drops before `rarity:legendary` is
unlocked.

**Deeper Commons** (Brotato): from floor 3, Common and Uncommon weapons in the shop and
treasure arrive at tier II 30% of the time on floor 3 and 50% on floors 4 and 5. A Common
stays worth taking late.

**Pick within a rarity:** today's build tilt (`Drops.roll_gun`: the top element x`TOP_MULT`,
reaction partners, duplicates) gains a family term. Families you carry weigh x1.5, and a
family you carry none of keeps the fixed off-build share (`GUN_OFF_BUILD`), so you still
meet new families.

### 3.3 Luck and the drought rule

- **Luck** multiplies the Rare, Epic and Legendary weights by `1 + luck`, as for items
  (capped at +60%).
- **The drought rule** (hidden): if your last 4 runs that reached floor 2 were not offered a
  Legendary weapon, the next run's first treasure room from floor 2 holds one. This makes
  Emil's "about once every few runs" a promise. It is stored as `Progress.legendary_drought`
  (a count of dry runs, reset when one is offered) and printed in the bot's `[LOOT]` line.

**Expected share** (Poisson estimate from the tables above: about 2 shop weapon cards a
floor with a reroll, 0.35 treasure cards and 0.25 boss cards from floor 2): a run that
reaches floor 5 sees on average about 0.45 Legendary weapon offers, so **about 1 run in 3 is
offered one** (36%). A run that dies on floor 2 or 3 sees one about 1 time in 8. With the
drought rule, the longest wait is five runs. `--loot-sim` checks this (section 8).

### 3.4 Merging and tiers

- A copy of a weapon you carry merges it one tier up (I to IV), as today, and the Gunsmith
  raises your lowest tier for scrap.
- **Copies by rarity:** the duplicate weight (`DUPLICATE_MULT`) applies in full to Common and
  Uncommon, at half to Rare and at a quarter to Epic. Legendaries never appear twice in a run,
  so a Legendary is tiered only at the Gunsmith.
- **Gunsmith price** is today's price times the rarity factor: Common 1.0, Uncommon 1.2, Rare
  1.4, Epic 1.7, Legendary 2.0.
- **Shop price** of a weapon is `PRICE_BASE[rarity] x (0.8 + 0.1 x weight) x depth`, so a heavy
  weapon costs a bit more than a light one of the same rarity. It replaces today's
  weight-only `gun_price`.
- A tier IV weapon gets a thin bright rim on its card plate and Build-page icon. That is the
  only tier mark beyond the pips.

### 3.5 The legendaries

Each one changes how the run plays. Each is unique in a run, unlocked by its own feat
(section 6), and offered at most once per run. One skipped goes back to the pool for the next
run. Lines are card-ready (at most 10 words, 60 characters).

| id | Name | Family | Element | The rule (card line) | Why it defines a run |
|---|---|---|---|---|---|
| `glass_of_ages` | Glass of Ages | Gun | Ice + Void | Stops foes in time; their damage lands all at once | Every other weapon's hits pile up on a frozen foe and land together: big, slow, readable bursts |
| `heart_of_the_forge` | Heart of the Forge | Gun | Fire + Stone | Each vent turns every weapon molten for 5 s | The vent becomes your power spike; you build toward pressure on purpose |
| `echo_engine` | Echo Engine | Gun | Gale | Your other weapons fire again from this one | The other three slots matter twice; a melee build gets ranged echoes |
| `the_conductor` | The Conductor | Gun | Shock | Arcs leap between every foe you hit last second | Turns a spread build (summons, swarms, discs) into a lightning net |
| `tidebreaker` | Tidebreaker | Melee | Wet + Ice | Every fourth swing sends a freezing wave across the room | Melee that reaches the whole room every few seconds |
| `mirrorblade` | Mirrorblade | Melee | Holy | Swings send enemy shots back at their owners | Ranged enemies become your ammunition; you walk into spitters |
| `the_long_coil` | The Long Coil | Melee | Poison + Acid | A whip that reaches across the room, leaving venom | Melee at gun range; lines of venom shape the room |
| `red_harvest` | Red Harvest | Melee | Blood | Each kill adds 2% damage until the room ends | Snowballs inside every crowd; the first kills matter most |
| `mother_of_knives` | Mother of Knives | Thrown | Blood | Knives stay down; each dash calls them all back | The dash becomes your biggest attack; you lay knives, then sweep |
| `skyfall` | Skyfall | Thrown | Stone + Fire | A meteor falls on the biggest pack every 6 s | A huge, telegraphed (to you) hit that clears packs and leaves magma |
| `prism_disc` | Prism Disc | Thrown | All twelve | Takes a new element at every bounce | Every bounce reacts with the last; a discovery machine |
| `second_sun` | The Second Sun | Summon | Holy + Fire | Your reactions fire a beam from your orbiting sun | Reaction builds get a second payoff on every reaction |
| `hollow_choir` | The Hollow Choir | Summon | Void | Each kill raises a shade that fights for 8 s | An army that grows in crowds and fades in boss fights |
| `phoenix_lantern` | Phoenix Lantern | Summon | Fire | Once a floor, the firebird saves you at 30% | You can take risks; it doesn't stack with Last Breath (whichever comes first) |
| `orrery` | Orrery | Summon | Every element you carry | An orbiting mote for every element you carry | Rewards carrying many elements instead of one |
| `stormcrown` | Stormcrown | Ground | Shock | While you move, lightning strikes the closest foe | Moving is attacking; the anti-stand-still weapon |
| `the_bell` | The Bell | Ground | Holy | Plant a bell; each toll applies all your elements | A spot in the room where every reaction you own happens |
| `event_horizon` | Event Horizon | Ground | Void | Foes within 180 px drift to you, taking +30% | Gathers the crowd into your melee, rings and traps |

**Balance:** a legendary alone at tier I may deal up to 1.6 times an Epic of its weight on the
pack number. Its rule counts in full in the power curve (it is not a synergy).
`--legendary-probe` checks that every rule fires and stays under that ceiling.

### 3.6 Celebrating a legendary, quietly

Every legendary moment happens at a pickup, out of the fight. Treasure rooms, shops and deal
rooms have no enemies, and the boss row appears after the boss dies. If any enemy is alive,
the moment waits in today's banner queue.

| Moment | What happens |
|---|---|
| Entering the room | The pedestal's legendary beam (today) plus one low bell, 8 dB under music, once. In a treasure room that holds a legendary, the plinth is black and gold, so it reads from the door, like Gungeon's black chest |
| Map | Once seen, the room's minimap icon gets a small gold star |
| The card | A gold frame with a slow shimmer sweep (1 Hz), "Legendary" as the rarity word, the name at 32 px, and the rule line in the Legendary text colour (at least 4.5:1 contrast). The 25-word rule holds |
| Taking it | A top-band banner, "LEGENDARY: The Long Coil" with its line under it (28 and 22 px, 2 s), a 0.1 s hit-stop, the synergy chime an octave lower with a bell over it, a gold flash on the figure, and a ring of gold motes for 2 s. The weapon's look shows at once |
| After | It wears one thin gold accent in fights (on the icon at the figure), under the brightness caps. The Build page lists it first. The journal records "First found: floor 3, run 41". The floor-end card names it |

There is no slow motion: that stays for resonances.

---

## 4. The full weapon list

**151 weapons:** 46 guns, 28 melee, 26 thrown, 25 summons and 26 ground. By rarity: 39
Common, 38 Uncommon, 36 Rare, 20 Epic and 18 Legendary. The 43 existing guns keep their ids
and numbers and get a rarity; **New** marks the 108 to build. W is weight. Lines are
card-ready.

### 4.1 Guns (46: 31 existing, 15 new)

| id | Name | Style | Element | Rarity | W | Behaviour | |
|---|---|---|---|---|---|---|---|
| `water_pistol` | Water Pistol | pistol | Wet | Common | 1 | Single aimed shots, long reach | |
| `flare_pistol` | Flare Pistol | pistol | Fire | Common | 1 | Slower, hotter shots, long reach | |
| `vein_pistol` | Vein Pistol | pistol | Blood | Common | 1 | Quick shots that open bleeds | |
| `slick_wand` | Slick Wand | wand | Oil | Common | 1 | A bolt that splits in two on the first hit | |
| `spark_needler` | Spark Needler | repeater | Shock | Common | 1 | Spins up to a stream of needles | |
| `venom_spitter` | Venom Spitter | repeater | Poison | Common | 2 | Spins up to a stream of poison | |
| `gravel_shotgun` | Gravel Shotgun | shotgun | Stone | Common | 3 | Pellet spread that knocks back | |
| `etcher_beam` | Etcher Beam | beam | Acid | Common | 2 | A short ray that paints acid on the floor | |
| `blowtorch` | Blowtorch | sprayer | Fire | Common | 2 | A short cone of flame that paints fire | |
| `mist_sprayer` | Mist Sprayer | sprayer | Wet | Common | 2 | A wide wet cone that soaks the floor | |
| `arc_rifle` | Arc Rifle | chain | Shock | Common | 3 | An arc that jumps between four foes | |
| `old_six` | Old Six | revolver | Stone | Common | 2 | Six quick shots, then a slow reload | New |
| `rime_repeater` | Rime Repeater | repeater | Ice | Common | 2 | Spins up; each hit chills a little more | New |
| `bubble_gun` | Bubble Gun | bubble | Wet | Common | 1 | Slow bubbles that trap small foes briefly | New |
| `null_wand` | Null Wand | wand | Void | Uncommon | 2 | A bolt that splits in three on the first hit | |
| `ember_carbine` | Ember Carbine | burst | Fire | Uncommon | 3 | Three-round bursts of fire | |
| `cyclone_flak` | Cyclone Flak | flak | Gale | Uncommon | 3 | Bursts into wind shards near a foe | |
| `blight_seeker` | Blight Seeker | homing | Poison | Uncommon | 2 | Three seekers spread over different foes | |
| `clot_orb` | Clot Orb | orb | Blood | Uncommon | 3 | A slow orb that pulses bleed around it | |
| `radiant_ray` | Radiant Ray | beam | Holy | Uncommon | 3 | A long ray that sweeps toward the aim | |
| `gale_blaster` | Gale Blaster | sprayer | Gale | Uncommon | 2 | A gust cone that shoves foes back | |
| `prayer_burst` | Prayer Chain | chain | Holy | Uncommon | 2 | A light arc that jumps between three foes | |
| `ember_scattergun` | Ember Scattergun | shotgun | Fire | Uncommon | 3 | Burning pellets; point-blank adds a second blast | New |
| `gale_longbow` | Gale Longbow | bow | Gale | Uncommon | 2 | Arrows pierce two and push foes along the line | New |
| `acid_darts` | Acid Darts | sticky | Acid | Uncommon | 2 | Darts stick, then burst after a second | New |
| `stone_sling` | Stone Sling | sling | Stone | Rare | 4 | A stone that caroms off walls and foes | |
| `hydro_cannon` | Hydro Cannon | cannon | Wet | Rare | 5 | A huge slow ball that ploughs through | |
| `cinder_flak` | Cinder Flak | flak | Fire | Rare | 4 | Bursts into burning shards near a foe | |
| `rift_seeker` | Rift Seeker | homing | Void | Rare | 3 | Two heavy seekers that pierce | |
| `storm_seeker` | Storm Seeker | homing | Shock + Wet | Rare | 4 | Seekers that soak and shock at once | |
| `blood_lance` | Blood Lance | charge | Blood | Rare | 4 | A quick wind-up, then a blood rail | |
| `glint_beam` | Glint Beam | reflect | Ice | Rare | 3 | A ray that reflects off walls twice | New |
| `harpoon` | Harpoon | harpoon | Oil | Rare | 4 | A barbed shot reels its foe in, oiled | New |
| `longshot` | Longshot | sniper | None | Rare | 4 | Slow shots; hits past 300 px always crit | New |
| `eclipse_carbine` | Eclipse Carbine | burst | Holy + Void | Epic | 4 | Bursts that alternate light and dark | |
| `duality_burst` | Duality Helix | helix | Ice + Fire | Epic | 3 | Two elements twisted together; every hit reacts | |
| `sun_cannon` | Sun Cannon | cannon | Holy | Epic | 5 | A slow sun that ploughs through and bursts | |
| `void_orb` | Void Orb | orb | Void | Epic | 5 | A slow orb that pulls foes in and pulses | |
| `glacier_lance` | Glacier Lance | charge | Ice | Epic | 5 | A long wind-up, then a freezing rail | |
| `railgun` | Railgun | charge | None | Epic | 5 | A long wind-up, then a rail across the room | |
| `blood_hymn` | Blood Hymn | hymn | Blood | Epic | 3 | Up to triple damage as your health falls | New |
| `singularity` | Singularity | shotgun | Void | Epic | 4 | Pellets curve inward to meet at one point | New |
| `glass_of_ages` | Glass of Ages | sniper | Ice + Void | Legendary | 4 | Stops foes in time; their damage lands all at once | New |
| `heart_of_the_forge` | Heart of the Forge | cannon | Fire + Stone | Legendary | 5 | Each vent turns every weapon molten for 5 s | New |
| `echo_engine` | Echo Engine | echo | Gale | Legendary | 3 | Your other weapons fire again from this one | New |
| `the_conductor` | The Conductor | chain | Shock | Legendary | 3 | Arcs leap between every foe you hit last second | New |

Arc Rifle moves to Common, because it is a fresh-save starter.

### 4.2 Melee (28: 1 existing, 27 new)

| id | Name | Style | Element | Rarity | W | Behaviour | |
|---|---|---|---|---|---|---|---|
| `tin_sabre` | Tin Sabre | sweep | None | Common | 2 | A plain, quick sweep in front of you | New, core |
| `ember_brand` | Ember Brand | sweep | Fire | Common | 2 | A burning sweep; the first foe hit takes double | New |
| `frost_hatchet` | Frost Hatchet | cleave | Ice | Common | 3 | A wide chop that chills all in front | New |
| `tide_spear` | Tide Spear | thrust | Wet | Common | 2 | A long thrust that soaks the whole line | New |
| `spark_knuckles` | Spark Knuckles | jab | Shock | Common | 1 | Fast jabs; every fourth is a shock finisher | New |
| `bone_club` | Bone Club | slam | Stone | Common | 3 | A slam that staggers small foes | New |
| `thorn_whip` | Thorn Whip | lash | Poison | Common | 2 | A long lash; the tip poisons twice as hard | New |
| `pitch_cleaver` | Pitch Cleaver | cleave | Oil | Uncommon | 4 | Chops oil foes; burning ones take +40% | New |
| `gale_glaive` | Gale Glaive | spin | Gale | Uncommon | 3 | Every third swing spins and throws foes back | New |
| `etching_claws` | Etching Claws | jab | Acid | Uncommon | 1 | Jabs strip armour; the finisher splashes acid | New |
| `blood_rapier` | Blood Rapier | thrust | Blood | Uncommon | 2 | Quick thrusts; bleeding foes are struck twice | New |
| `sanctified_mace` | Sanctified Mace | slam | Holy | Uncommon | 3 | Slams mark foes for your other weapons | New |
| `hollow_sickle` | Hollow Sickle | spin | Void | Uncommon | 2 | Spins drag nearby foes into the blade | New |
| `storm_lash` | Storm Lash | lash | Shock | Uncommon | 2 | The tip's crack arcs to one more foe | New |
| `parry_blade` | Parry Blade | sweep | Gale | Rare | 3 | Swings cut enemy shots out of the air | New |
| `magma_maul` | Magma Maul | slam | Fire | Rare | 5 | Slams crack a burning fissure for 3 s | New |
| `rimefang` | Rimefang | thrust | Ice | Rare | 4 | A long thrust; frozen foes in the line shatter | New |
| `venom_pike` | Venom Pike | thrust | Poison | Rare | 3 | A piercing thrust that leaves a poison line | New |
| `crimson_gauntlets` | Crimson Gauntlets | jab | Blood | Rare | 2 | Finishers burst a foe's whole bleed at once | New |
| `riptide_whip` | Riptide Whip | lash | Wet | Rare | 2 | The crack pulls the struck foe to you | New |
| `storm_pike` | Storm Pike | sweep | Shock | Epic | 5 | A heavy shock sweep that throws foes back | |
| `thunder_halberd` | Thunder Halberd | thrust | Shock + Wet | Epic | 4 | The thrust soaks; the follow-up sweep shocks | New |
| `eclipse_scythe` | Eclipse Scythe | spin | Holy + Void | Epic | 4 | Spins alternate light and dark and react | New |
| `twin_fangs` | Twin Fangs | sweep | Poison + Blood | Epic | 3 | Two blades strike the two closest foes at once | New |
| `tidebreaker` | Tidebreaker | cleave | Wet + Ice | Legendary | 5 | Every fourth swing sends a freezing wave across the room | New |
| `mirrorblade` | Mirrorblade | sweep | Holy | Legendary | 3 | Swings send enemy shots back at their owners | New |
| `the_long_coil` | The Long Coil | lash | Poison + Acid | Legendary | 3 | A whip that reaches across the room, leaving venom | New |
| `red_harvest` | Red Harvest | spin | Blood | Legendary | 4 | Each kill adds 2% damage until the room ends | New |

### 4.3 Thrown and lobbed (26: 7 existing, 19 new)

| id | Name | Style | Element | Rarity | W | Behaviour | |
|---|---|---|---|---|---|---|---|
| `zephyr_rang` | Zephyr Rang | boomerang | Gale | Common | 1 | Out and back, hitting everything twice | |
| `oil_slinger` | Oil Slinger | pool | Oil | Common | 2 | A flask that leaves a wide oil pool | |
| `steel_knives` | Steel Knives | knife | None | Common | 1 | Three knives that stick, then fly back to you | New, core |
| `clay_grenade` | Clay Grenade | grenade | Stone | Common | 2 | Bounces once, then bursts into gravel | New |
| `shock_bola` | Shock Bola | bola | Shock | Common | 2 | Wraps a foe; it stops and shocks those near | New |
| `frost_javelin` | Frost Javelin | javelin | Ice | Common | 3 | A javelin that pins its foe for a second | New |
| `fire_bottle` | Fire Bottle | pool | Fire | Common | 2 | Shatters into a burning pool | New |
| `rime_chakram` | Rime Chakram | boomerang | Ice | Uncommon | 3 | A heavy chakram, out and back through all | |
| `acid_flask` | Acid Flask | pool | Acid | Uncommon | 3 | A flask that leaves an acid pool | |
| `plague_mortar` | Plague Mortar | pool | Poison | Uncommon | 3 | A long lob that leaves a poison pool | |
| `tide_discus` | Tide Discus | disc | Wet | Uncommon | 2 | Bounces between four foes, then comes back | New |
| `venom_fan` | Venom Fan | knife | Poison | Uncommon | 1 | Five knives in a wide fan; each poisons | New |
| `holy_water` | Holy Water | pool | Holy | Uncommon | 2 | A blessed pool; reactions inside hit harder | New |
| `wind_star` | Wind Star | star | Gale | Uncommon | 1 | Circles its target twice before returning | New |
| `void_grenade` | Void Grenade | grenade | Void | Uncommon | 2 | Pulls foes together for a second, then bursts | New |
| `boulder_mortar` | Boulder Mortar | lob | Stone | Rare | 5 | Lobbed over cover, a big splash | |
| `napalm_lobber` | Napalm Lobber | lob | Fire + Oil | Rare | 4 | Lobbed fire that oils what it splashes | |
| `cluster_bomb` | Cluster Bomb | grenade | Fire | Rare | 4 | Bursts into five bomblets that scatter | New |
| `etching_javelin` | Etching Javelin | javelin | Acid | Rare | 3 | Sticks in a foe and melts its armour | New |
| `halo_disc` | Halo Disc | disc | Holy | Rare | 3 | Grows with every bounce between foes | New |
| `storm_kunai` | Storm Kunai | knife | Shock | Rare | 2 | Stuck knives arc lightning between them | New |
| `crossing_axes` | Crossing Axes | boomerang | Ice + Fire | Epic | 4 | Two axes cross paths and react where they meet | New |
| `drowned_anchor` | Drowned Anchor | anchor | Wet + Stone | Epic | 5 | A heavy anchor dragged back through the crowd | New |
| `mother_of_knives` | Mother of Knives | knife | Blood | Legendary | 2 | Knives stay down; each dash calls them all back | New |
| `skyfall` | Skyfall | lob | Stone + Fire | Legendary | 4 | A meteor falls on the biggest pack every 6 s | New |
| `prism_disc` | Prism Disc | disc | All twelve | Legendary | 2 | Takes a new element at every bounce | New |

### 4.4 Summons and drones (25: 1 existing, 24 new)

| id | Name | Style | Element | Rarity | W | Behaviour | |
|---|---|---|---|---|---|---|---|
| `scout_drone` | Scout Drone | drone | Shock | Common | 1 | Hovers by you and zaps the closest foe | New, core |
| `ember_imp` | Ember Imp | familiar | Fire | Common | 2 | An imp that runs at foes and bites | New |
| `orbit_stones` | Orbit Stones | orbit | Stone | Common | 2 | Three stones circle you, knocking foes back | New |
| `wasp_nest` | Wasp Nest | swarm | Poison | Common | 2 | Wasps sting once, then respawn after 2 s | New |
| `frost_sentry` | Frost Sentry | turret | Ice | Common | 3 | Deploys a sentry whose shots slow | New |
| `rain_drone` | Rain Drone | drone | Wet | Uncommon | 2 | Hovers over the closest pack and soaks it | New |
| `tar_crawler` | Tar Crawler | familiar | Oil | Uncommon | 2 | Crawls to foes, leaving an oil trail | New |
| `storm_kite` | Storm Kite | orbit | Gale | Uncommon | 2 | A kite on a string circles wide and cuts | New |
| `acid_slime` | Acid Slime | familiar | Acid | Uncommon | 2 | Splits in two on each hit, up to four | New |
| `holy_wisps` | Holy Wisps | swarm | Holy | Uncommon | 1 | Three wisps seek foes and burst in light | New |
| `leech_jar` | Leech Jar | swarm | Blood | Uncommon | 2 | Leeches latch on and bleed foes until they die | New |
| `kettle_gun` | Kettle Gun | turret | Wet + Fire | Rare | 3 | A turret that sprays steam on its own | |
| `watchers_eye` | Watcher's Eye | drone | Void | Rare | 3 | A floating eye beams and marks the closest foe | New |
| `tesla_post` | Tesla Post | turret | Shock | Rare | 3 | A post that arcs to three foes in reach | New |
| `blood_hound` | Blood Hound | familiar | Blood | Rare | 3 | Dashes through packs, leaving them bleeding | New |
| `clay_golem` | Clay Golem | golem | Stone | Rare | 5 | A slow golem walks with you and slams packs | New |
| `mortar_drone` | Mortar Drone | drone | Oil | Rare | 4 | Hovers high and lobs oil bombs over walls | New |
| `frost_blades` | Frost Blades | orbit | Ice | Rare | 3 | Two orbiting blades; a second touch freezes | New |
| `thunderhead` | Thunderhead | drone | Shock + Wet | Epic | 4 | A storm cloud follows you, raining shocks | New |
| `sun_and_moon` | Sun and Moon | familiar | Holy + Void | Epic | 4 | Two familiars; a foe bitten by both bursts | New |
| `hive_queen` | Hive Queen | swarm | Poison + Gale | Epic | 4 | Each kill adds a wasp, up to twelve | New |
| `second_sun` | The Second Sun | orbit | Holy + Fire | Legendary | 3 | Your reactions fire a beam from your orbiting sun | New |
| `hollow_choir` | The Hollow Choir | shade | Void | Legendary | 3 | Each kill raises a shade that fights for 8 s | New |
| `phoenix_lantern` | Phoenix Lantern | familiar | Fire | Legendary | 3 | Once a floor, the firebird saves you at 30% | New |
| `orrery` | Orrery | orbit | Every element you carry | Legendary | 3 | An orbiting mote for every element you carry | New |

### 4.5 Auras and traps (26: 3 existing, 23 new)

| id | Name | Style | Element | Rarity | W | Behaviour | |
|---|---|---|---|---|---|---|---|
| `frost_caster` | Frost Caster | pulse | Ice | Common | 2 | A cold ring bursts out around you | |
| `ember_halo` | Ember Halo | aura | Fire | Common | 2 | A ring of heat burns foes near you | New, core |
| `spark_trail` | Spark Trail | trail | Shock | Common | 1 | Moving leaves a line that shocks foes crossing it | New |
| `snap_trap` | Snap Trap | snare | Stone | Common | 2 | Sets traps in foes' paths that bite and hold | New |
| `frost_totem` | Frost Totem | totem | Ice | Common | 2 | Plants a totem that chills all near it | New |
| `tide_ring` | Tide Ring | pulse | Wet | Common | 2 | A slow wave rolls out, soaking and shoving | New |
| `plague_steps` | Plague Steps | trail | Poison | Uncommon | 1 | Your footsteps leave a toxic haze | New |
| `slick_field` | Slick Field | field | Oil | Uncommon | 2 | Spreads an oil slick under the closest pack | New |
| `wind_chime` | Wind Chime | totem | Gale | Uncommon | 2 | A chime that pushes foes away from it | New |
| `spark_mine` | Spark Mine | mine | Shock | Uncommon | 3 | When one mine blows, the ones near follow | New |
| `holy_glyph` | Holy Glyph | glyph | Holy | Uncommon | 2 | Kills leave a glyph that smites the next foe | New |
| `thirst` | Thirst | aura | Blood | Uncommon | 2 | Foes near you bleed and slow | New |
| `tar_mortar` | Tar Mortar | mine | Oil | Rare | 4 | Tossed tar mines that burst on contact | |
| `corrosion_burst` | Corrosion Burst | mine | Acid | Rare | 4 | Tossed acid mines that burst on contact | |
| `rift_snare` | Rift Snare | snare | Void | Rare | 3 | A rift holds a foe and the pack around it | New |
| `pyre_totem` | Pyre Totem | totem | Fire | Rare | 3 | A totem that throws fire at what comes near | New |
| `hoarfrost` | Hoarfrost | field | Ice | Rare | 3 | Freezes the floor under a pack; foes slip | New |
| `spike_glyphs` | Spike Glyphs | glyph | Stone | Rare | 3 | Dead foes leave spikes under the next ones | New |
| `corrosion_halo` | Corrosion Halo | aura | Acid | Rare | 3 | Nearby foes lose armour, faster the more they have | New |
| `lightning_rods` | Lightning Rods | totem | Shock | Rare | 3 | Plants rods; lightning arcs between near ones | New |
| `geyser_field` | Geyser Field | field | Wet + Fire | Epic | 4 | Geysers burst under packs into steam | New |
| `ash_garden` | Ash Garden | pod | Poison + Fire | Epic | 3 | Spore pods bloom into burning toxin | New |
| `collapse_mine` | Collapse Mine | mine | Void + Stone | Epic | 4 | Mines pull foes in, then crush them | New |
| `stormcrown` | Stormcrown | aura | Shock | Legendary | 3 | While you move, lightning strikes the closest foe | New |
| `the_bell` | The Bell | totem | Holy | Legendary | 4 | Plant a bell; each toll applies all your elements | New |
| `event_horizon` | Event Horizon | aura | Void | Legendary | 4 | Foes within 180 px drift to you, taking +30% | New |

**Elements.** 147 of the 151 carry an element; 4 are plain (Tin Sabre, Steel Knives, Longshot,
Railgun), and Stone gives the other contrast. Every element appears in at least three
families. Within a family, no element appears twice in one style, except where a
Legendary shares a style with a lower weapon.

**Near-duplicate check**, done while writing the list:
- Pairs that looked alike got different rules: the Parry Blade cuts shots and the
  Mirrorblade returns them; Holy Water buffs reactions and the Acid Flask lays acid; the
  Rime Repeater's chill stacks, while the Spark Needler and Venom Spitter just stream.
- Every style has a basic Common (the sweep, the knife, the drone, the aura). The Uncommons
  and above in that style each add a different rule.

---

## 5. Items: from 145 to 300

### 5.1 Categories

| Category | Today | Target | New | What the new ones are |
|---|---|---|---|---|
| Plain stats | 19 | 30 | 11 | Family stats: melee damage, reach, throw speed, summon damage, summon attack rate, zone radius, zone duration, and four mixed (for example "+10% damage, +5% reach") |
| Sigils | 12 | 12 | 0 | |
| Trade-offs and cursed | 13 | 25 | 12 | Family trade-offs ("Summons +1, your shots -15% damage"; "Melee +30%, guns -20%") and five new cursed pedestals |
| Healing | 2 | 6 | 4 | Inside the Mending and Leech budgets: one per new family ("melee kills mend 1, up to the floor budget") |
| Element items (the 12 Vials and more) | 12 | 36 | 24 | Two per element: a **state** item (Ice: frozen foes take +20% from melee) and a **reaction** item (Steam clouds drift toward foes) |
| Behaviour passives | 55 | 73 | 18 | Cross-family rules: "Kills by one family speed up the next family"; "Every 10th hit of any weapon repeats" |
| **Family passives** | 0 | 48 | 48 | 12 per new family, all behaviour (section 5.2) |
| Weapon mods | 21 | 45 | 24 | 6 per new family, and they fit any weapon: a melee mod on a gun does its gun version (Whetstone: +15% damage, and on melee also +10% reach) |
| Actives | 11 | 25 | 14 | Family actives: Recall (all thrown objects return), Rally (summons dash to your target), Bulwark (melee arc blocks shots for 2 s), Seed (plant every trap at once) |
| **All** | **145** | **300** | **155** | |

**Behaviour against stat:** about 210 items change behaviour (element items, behaviour and
family passives, actives and the behaviour mods), and about 90 are stats (plain stats, Sigils,
trade-offs, healing and the stat mods). That is about 70 to 30, up from about 60 to 40 today.
Isaac's lesson (items you can *see*) wins over Brotato's (many small numbers), and decision 12
already asks a strong item to change how you shoot.

All items keep today's rules: `add`, `dim` and `once` stacking, the caps in
`Items.STAT_CAPS`, one effect line of at most 10 words, and the 25-word card.

### 5.2 Family passives (12 per family), examples

| Family | Examples (card lines) |
|---|---|
| Blade (melee) | Long Reach: "Melee reach +20%". Follow-Through: "Finishers swing twice". Riposte: "A dash makes the next swing crit". Bloodletter: "Cleave hits open a bleed". Whirl: "Every 5th swing is a full spin" |
| Thrown | Return Grip: "Returning objects hit twice as hard". Fletching: "+1 bounce on discs and stars". Long Fuse 2: "Grenades burst twice". Sticky Fingers: "Stuck knives poison what touches them". Overarm: "Lobs fly 30% faster" |
| Swarm (summons) | Pack Leader: "+1 to every summon cap". Shared Mind: "Summons hit what you hit last". Brood: "Kills by summons spawn a wasp for 4 s". Overclock: "Drones fire 25% faster, then rest". Tether: "Summons apply your first weapon's element" |
| Ground (auras and traps) | Deep Roots: "Totems last 50% longer". Hair Trigger: "Traps also burst when you dash past". Widen: "Rings +20% radius". Echo Step: "Trails leave a second, delayed line". Salted Earth: "Your zones slow foes 15%" |

### 5.3 Tags and resonances

- Four new tags: **Blade**, **Thrown**, **Swarm** and **Ground**. Gunslinger becomes the guns'
  family tag.
- **Weapons count toward their family tag** (Brotato's classes): every carried weapon adds 1 to
  its family tag, as an item does. Three melee weapons, or two melee weapons and one Blade
  item, form the Blade resonance. That makes a family build a natural goal without forcing it.
- Resonances at 3 and 5 (today's thresholds and moment):

| Tag | At 3 | At 5 (doubles, plus) |
|---|---|---|
| Blade | Reach and swing speed +15% | Swings send a short wave 80 px past their reach |
| Thrown | +1 bounce or return hit | Thrown objects split in two on their last hit |
| Swarm | +1 to every summon cap | Summons apply the element of your highest-tier weapon |
| Ground | Zones last 30% longer, radius +15% | Your zones react with each other where they touch |
| Gunslinger | (today) +1 projectile on your first gun | (today) |

### 5.4 Synergies: from 20 to 50

| Kind | Count | Examples |
|---|---|---|
| Today's | 20 | Hunting Shards, Reaper's Return, Living Orbit, Pinball... |
| Weapon + weapon (Gungeon-style pairs) | 10 | **Conductor's Net:** Storm Kunai + Lightning Rods, stuck knives act as rods. **Blizzard:** Frost Totem + Wind Chime, totems near each other form a snowstorm. **Big and Little:** Clay Golem + Bone Club, the golem slams when you do. **Reel and Slash:** Harpoon + any thrust, reeled foes take a free thrust |
| Weapon + item (our evolutions, VS-style) | 12 | **Bulwark:** Parry Blade + Ward Vent, cut shots burst into your shards. **Killer Bees:** Wasp Nest + Seeker Lens, wasps home and poison twice. **Eagle Eye:** Longshot + Monocle, long crits pierce everything. **Twin Rotors:** Scout Drone + Fork, a second drone |
| Item + item (new families) | 8 | **Wildfire:** Overarm + any fire Vial, burning pools spread. **Iron Choir:** Pack Leader + Brood, wasps carry your vial |

- **Weapon synergies form at a weapon pickup too**, with today's banner, chime and signature
  look. Weapon cards say "Forms SYNERGY: name", and the synergy-card nudge
  (`Drops.SYNERGY_CARD_CHANCE`) offers weapon halves as well as item halves.
- **Rate:** the target stays one synergy in about 1 run in 3, and two in about 1 in 10.
  Because 50 synergies give more chances than 20, batch 5 lowers `SYNERGY_CARD_CHANCE`
  from 0.4 toward 0.25 if `--loot-sim` shows a synergy in more than 40% of runs.

---

## 6. Unlocks

### 6.1 A fresh save

**8 weapons:** today's four (`water_pistol`, `arc_rifle`, `flare_pistol`, `slick_wand`) plus
one Common starter per new family: **Tin Sabre** (melee), **Steel Knives** (thrown),
**Scout Drone** (summon) and **Ember Halo** (ground). The floor-1 gun picks offer a family you
don't carry, so most first runs meet two or three families. Items: today's starting pool, and
none of the 155 new items.

Everything else unlocks. Today's 39 locked guns keep their current conditions (achievements
and death lessons), so saves keep their progress.

### 6.2 Where unlocks come from

| Source | How it works | Opens | Count |
|---|---|---|---|
| **Play goals** (`progress.gd` achievements, the first block) | Cumulative stats from just playing: kills, rooms, reactions, vents, runs | Commons and Uncommons; one family item each | about 45 |
| **Family mastery** (new, `progress.gd`) | Kills with a family's weapons: 100, 300, 800, 2,000 and 5,000, separately per family. Each step opens the next weapon of that family, with two of its items | Uncommons to Epics, in family order | about 25 (5 per family) |
| **Death lessons** (`lessons.gd`) | Today's: the first death to a boss or region opens a counter. New bosses and regions add new counters | Rares that counter that killer | about 6 new |
| **Trials** (new hub board) | Isaac-style challenge runs with a fixed rule: "Blades only", "No guns", "Summoner: no weapon of yours may fire", "Ground: you can't attack", "One element", "Glass: 1 HP". Each Trial won opens one or two Rares or Epics and a matching item | Rares and Epics | 12 Trials, about 20 weapons |
| **Milestones** | Floors reached, region bosses beaten, wins, wins per Mark, first Vow | Rares, Epics, items, and the rarity caps (today's `rarity:` unlocks) | about 15 weapons and most items |
| **Legendary feats** | One feat per legendary (table below). The hub shows a vague hint until you are a third of the way there, then the plain goal (the death-lesson rule) | One legendary each | 18 |

Items ride along: almost every reward line opens a weapon plus one or two items, so the 155
new items unlock beside the 108 new weapons. Today's `rewards` arrays already take lists.

**Legendary feats:**

| Legendary | Feat |
|---|---|
| Glass of Ages | Freeze 30 foes that a Void weapon is pulling, in one run |
| Heart of the Forge | Vent 200 times |
| Echo Engine | Win a run carrying four different families |
| The Conductor | Fire 500 Chain Lightnings |
| Tidebreaker | Beat the Drowned Choir with a melee weapon in your first slot |
| Mirrorblade | Cut 300 enemy shots with the Parry Blade |
| The Long Coil | Kill 1,000 foes with whips |
| Red Harvest | Kill 60 foes in one room |
| Mother of Knives | Recall 2,000 knives |
| Skyfall | Beat a floor-5 boss with a lobbed weapon equipped |
| Prism Disc | Discover every two-element reaction |
| The Second Sun | Win with two summon weapons |
| The Hollow Choir | Have 12 summons out at once |
| Phoenix Lantern | Die on floor 4 or deeper five times |
| Orrery | Win carrying six different elements |
| Stormcrown | Dash 1,000 times |
| The Bell | Beat a boss using only ground weapons |
| Event Horizon | Win a run on Vow 1 |

### 6.3 Pacing

| Hours (runs of about 30 min) | Unlocks a run | What appears |
|---|---|---|
| 0 to 5 (runs 1 to 10) | about 4 | Every family's second and third weapon, every element, the first family items; the first Trial at run 6 |
| 5 to 20 (runs 10 to 40) | about 2 | Rares from family mastery and lessons, the Trials, the first Epics |
| 20 to 60 (runs 40 to 120) | about 1 | Epics, milestone items, the easier legendary feats (Heart of the Forge, Stormcrown, Red Harvest) |
| 60 to 120 (runs 120 to 240) | about 0.5 | The hard feats (Prism Disc, Event Horizon, Skyfall), the last Trials |

That is about 260 unlocks, close to the 108 weapons and 155 items. The rule: **every run
that lasts past floor 1 moves at least one visible goal forward**, and the end-of-run screen
shows the closest goal ("Blades: 640 of 800 kills").

**What's new:** a newly unlocked weapon or item has a "New" chip on its first card (out of
the fight) and a "New in the pool: 3" line at the hub's Archivist. Nothing appears mid-run.

---

## 7. Code-drawn looks

One module, `weapon_looks.gd`, draws every weapon's icon (cards, Build page, HUD strip) and
its in-world parts (the held weapon, the swing smear, thrown objects, summon bodies, ground
marks). Everything goes through `WeaponLooks.icon(id, size)` and `WeaponLooks.draw_*`
functions. **The art-pack swap:** `WeaponLooks.sprite_for(id, part)` returns a texture when
the pack has one and null otherwise, so sprites replace the code-drawn shapes one by one, with
no other code change. Today's gun icon tiles stay as the guns' look.

| Family | Silhouette | In the world | Motion |
|---|---|---|---|
| Guns | Today's tiles | Orbiting the figure, pointing at the target | Recoil (today) |
| Melee | Long shapes: a blade triangle, an axe head on a haft, a mace ball, a whip curve, a gauntlet block. 1 px dark outline, element-coloured edge | Held 18 px from the figure, pointing at the closest enemy | A 0.05 s tilt back, then the smear (section 2.3) |
| Thrown | The object itself: a knife, a disc, a bottle, a grenade, a javelin, a star | Spins in flight (discs and stars fast, knives slowly). Lobs cast a shadow | Stuck knives tilt 30° into the floor |
| Summons | Round bodies: an element-coloured core with a darker rim. Drones get two rotor ticks, familiars two eye dots, orbits a spike, swarms a 4 px speck, the golem a block of three stacked shapes | On the player-colour friend ring | A small bob (2 px, 1.5 Hz); no idle particles |
| Ground | Geometric marks: a dashed ring, a pillar with a gem, a jagged ring, a three-stroke rune, a dotted line | The floor layer (section 2.6) | None; a fade at the end |

- **Colour:** the element owns the colour in the world, and rarity owns it on cards (the GDD's
  "rarity owns colour" rule). The only rarity mark in the world is the Legendary's thin gold
  accent.
- **Two elements:** the main element fills the shape, and the second is the edge or the
  alternating stripe.
- **Size:** an icon reads at 22 px (the HUD) and at 96 px (the card). Every shape is checked at
  both sizes on the `--card-shot` sheets.

---

## 8. Balance and tests

Every batch runs these, headless, at most 4 instances (`--instance=N`), with timeouts.

| Check | How | Pass |
|---|---|---|
| **Weapon bands** | `--gun-probe` extended to every family (summons and zones get a 20 s window) | Single-target damage in its weight's band times the family share (melee 130%, thrown 100%, summons 70%, ground 60%) times the rarity premium; no weapon more than 5% over another of the same family, weight and rarity on both numbers |
| **Family probe** (new) | `--family-probe=<family>`: four weapons of one family at tier II, the human build's items, `--mastery=full`, kite bot, from floor 1 | At least 2 of 4 runs reach floor 3 for every family |
| **Stand-still dies** | Today's 4 idle runs with the human build, plus, per new family, 2 idle runs with four weapons of that family at tier II | All die by the end of floor 3. Ground and summon builds are the ones to watch |
| **Mover survives under pressure** | Today's 4 kite runs, plus 4 with a mixed loadout (one weapon per family) | At least 3 of 4 reach floor 4; from floor 3, time under 50% at least 0.10 |
| **Pressure, still against moving** | `[PRESSURE]` per floor | Idle takes at least 2x the mover's damage per minute on floors 2 and 3, for every family build |
| **Economy and loot** | `shop_leave` and `floor_loot` events | Today's targets (70% of visits spent down; free 2 to 4, bought 1 to 3, at most 15 cards a floor); weapons gained 2 on floor 1, then 0 to 1 a floor |
| **Power curve** | `boss` events | Bots: bosses take 25 to 60 s; no boss under 27 s (the pace guard) with a legendary carried |
| **Legendary share** | New `--loot-sim=N`: rolls every reward row of N simulated runs with no fights (a run reaches floor k with the bot's measured share), applying the drought rule over consecutive runs | A Legendary weapon offered in 30 to 40% of runs that reach floor 4, and 10 to 45% of all runs; never more than 5 dry runs in a row; any Legendary (weapon or item) in 50 to 70% of runs reaching floor 4 |
| **Legendary rules** | New `--legendary-probe[=id]` | `[LEGENDARY-PROBE] PASS 18 of 18`: each rule fires, and the pack number is at most 1.6 times an Epic of its weight |
| **Synergy rate** | `--loot-sim` and bot runs | One synergy in about 1 in 3 runs |
| **Fusion** | `--fusion-probe` with one weapon per family | `[FUSION-CHECK] PASS`, 0 `SCRIPT ERROR` |
| **Cards** | `--card-shot` with every weapon and item | `[CARDS] PASS n`; Emil reads one weapon contact sheet per batch |
| **Screen** | `--read-shot=family`: a floor-3 arena, 40 enemies, four weapons of one family at tier III (in a window, only while Emil is away) | No hostile shot or telegraph drawn under one of ours (layer check); the quiet-screen counter at most 6 a minute; brightness under the clarity caps |
| **Performance** | New `--arsenal-perf`: 40 enemies, the worst loadout per family (two summon weapons at cap, a ring, a trap weapon at cap) | Extra script time at most 2 ms a frame headless; on Emil's idle PC, 60 fps with the 1% low around 55 |
| **Saves** | Load a copy of Emil's save | Every old id loads; new weapons are locked except the core 8 |
| **Smoke** | `tools/exe_smoke.sh`, then the CI "Windows release" | `[SMOKE] ALL PASS` |

**Legendary share in plain words:** a player who gets to floor 4 most runs should see a
Legendary weapon about every third run, take one about every fourth, and never go more than
five runs without seeing one.

---

## 9. Build batches

Five sessions, each self-contained, each in a fresh session (to save usage), each ending
with section 8's checks and a push. Each adds its own unlocks to `progress.gd`, so nothing
new is reachable before its batch ships. Each writes a handoff note.

### Batch 1: The weapon system and melee

**Builds:**
- `GunData.family`, `rarity`, `style`, `cap` and `unique`, with `FAMILY_OF`. All 43 existing
  weapons get their rarity and family (section 4).
- Weapon rarity: `Guns.RARITY_ODDS`, treasure Legendary odds (unused until batch 5), luck,
  deeper tier-II Commons, prices by rarity and weight, Gunsmith factors, duplicate weights
  by rarity, and the family term in `Drops.roll_gun`.
- The weapon sources of section 3.2 (shop 70/30, treasure 35%, boss 25%, challenge 30%, deal
  40%).
- Cards: rarity word and frame on weapon cards, the family chip, "Weapon" on screen.
- The stat map (section 2.2) for all families. Batch 1 needs only the melee column; the
  others are stubs that later batches fill in.
- `melee.gd`: all seven styles, cleave with its 12-target cap, stagger, the tip bonus, the
  finisher, and the ready pose.
- `weapon_looks.gd` with the melee shapes and the `sprite_for` hook.
- **Melee weapons:** the 24 non-legendary ones (Storm Pike remapped, plus 23 new).
- **Items:** the Blade tag and resonance, 12 Blade passives, 6 melee mods, 2 melee actives,
  and 10 of the plain, element and trade-off items: 30 in all.
- **Unlocks:** Tin Sabre in the core set; play goals and melee family mastery for the rest.
- **Tests:** `--gun-probe` for families, `--family-probe=melee`, the melee stand-still check,
  `--arsenal-perf` (melee only for now).

**Files:** `gun_data.gd`, `gun_library.gd`, `gun.gd`, new `melee.gd`, new `weapon_looks.gd`,
`focus.gd` (melee ready pose), `drops.gd`, `items.gd`, `floor_gen.gd` (prices),
`item_card.gd`, `character_sheet.gd`, `hud.gd`, `progress.gd`, `gun_fx.gd`, `sfx.gd`,
`scripts/gun_probe.gd`, README (flags), GDD (weapon families).

**Done when** the 24 melee weapons are in the pool by their unlocks, every weapon shows its
rarity, the section 8 checks pass for melee, `[CARDS] PASS`, and `[SMOKE] ALL PASS`.

#### Batch 1 done (2026-11-10, VERSION 2026.11.10-arsenal1)

**Built:**
- `GunData.family`, `rarity`, `style`, `cap` and `unique`, with `FAMILY_OF`. All 43 older
  weapons have a rarity (`Guns.RARITY_OF`), and the 12 that changed family have a style
  (`Guns.STYLE_OF`).
- Weapon rarity: `Guns.RARITY_ODDS` and `TREASURE_LEGENDARY` go through
  `Items.rarity_weights(..., weapon)`, so luck and the Shrine cap apply. Also built: deep
  tier-II Commons, prices by rarity and weight (`Guns.price`), Gunsmith factors, duplicate
  weight by rarity, the family term (x1.5) in `Drops.roll_gun`, and no Legendary twice.
- Weapon sources: floor-1 picks (Common or Uncommon only, one from a family you don't
  carry), shop 70/30, treasure 35%, boss from floor 2 25%, challenge 30%, deal 40%. Deal
  weapon cards pay the deal price through the same `Room._pay_deal` as items.
- Cards:
  - the rarity owns the frame and the name colour;
  - the sub line reads "Rare melee weapon, tier II";
  - a family tag chip;
  - a thin rim at tier IV;
  - "weapon" on screen, where the text was "gun".
- `melee.gd`:
  - all seven styles: sweep, cleave, thrust, slam, lash, jab, spin;
  - at most 12 hits a swing, closest first;
  - slams stagger for 0.3 s; the tip of a lash hits x1.5; every 4th jab is a x2.5
    finisher; every 3rd spin is a full circle;
  - the ready pose, the swing tilt, and a smear at 35% for 0.1 s;
  - the swing sound sits 10 dB under a shot;
  - one rule per weapon (section 4.2);
  - melee takes no Focus slot and swings only at an enemy in reach.
- The stat map for melee (2.2): swing speed is fire rate plus half the shot speed; +1
  projectile is +1 swing; reach comes from pierce and half the range bonus; shot size
  widens the arc; bounce reaches one enemy past the reach. The other families' columns wait
  for their batches.
- `weapon_looks.gd`: code-drawn melee icons on 32 px tiles, used everywhere through
  `Art.gun_icon`, the smears, and the `sprite_for(id, part)` art-pack hook (looks for
  `res://assets/weapons/<id>_<part>.png`).
- **Weapons:** 23 new melee weapons, plus Storm Pike remapped to `sweep`. All 24
  non-legendary melee weapons are in, so the arsenal now has 66 weapons.
- **Items (30), all locked until unlocked:**
  - 12 Blade passives: Long Reach, Follow-Through, Riposte, Bloodletter, Whirl, Shock
    Edge, Frostbite Steel, Thunder Grip, Cutting Wind, Marked Steel, Wildfire Edge, Edge
    Runner;
  - 6 mods: Whetstone, Weighted Pommel, Long Haft, Balanced Grip, Twin Edge, Tempered
    Steel;
  - 2 actives: Bulwark, Whirlwind;
  - 10 others: Honed Edge, Swift Strikes, Sword Belt, Iron Wrists, Berserker Oath, Glass
    Blade, Rime Whetstone, Ember Whetstone, Soaked Edge, Mending Steel.
- The Blade tag and its resonance. A trigger can be marked `"melee": true`, and hit and
  kill events now carry the weapon id.
- **Unlocks:** Tin Sabre is in the core set. 9 play goals each open a Common or Uncommon
  with one item. 13 melee-mastery steps (`kills_melee`, 60 to 6,500) open the rest, each
  with one or two items. `item:<id>` is a new kind of unlock.
- **Tests:** `--family-probe=<family>`. `--gun-probe` now prints family, style and rarity.

**Deviations, and why:**
| Spec | Built | Why |
|---|---|---|
| Hits after the first in a swing take 75% | 25% (`Melee.FOLLOW`) | At 75%, `--gun-probe` put melee pack damage at 4 to 8 times the best gun of its weight. That breaks the spec's own rule that pack damage is at most the best gun's. At 25%, every melee weapon's pack is within the best gun of its weight. |
| Weapons count toward their family tag, Gunslinger included | Only non-gun weapons count | With four slots nearly every gun build would form Gunslinger, a balance shift to every existing build. Revisit in batch 2 with the pressure checks. |
| Melee mastery: 5 steps (100 to 5,000) | 13 steps (60 to 6,500) | Trials, milestones and lessons don't exist yet, so batch 1 has only play goals and mastery to open 23 weapons. Later batches may move the Rares and Epics to Trials. |
| The Gunsmith price uses the rarity of the weapon it raises | Priced when the shop is stocked, from your lowest-tier weapon then | The ware's price is fixed at stocking. |
| Storm Pike's mechanics unchanged | It now goes through `melee.gd`: a 12-hit cap, 25% on follow-up hits, and the smear | One swing path for all melee. Its single-target number is unchanged (42). |
| The two-element melee weapons at the premium band | Low base damage and reaction power (0.1 to 0.4) | They react with themselves, as the two-element guns do, and ran about 2x over at the band's damage. |
| Storm Lash and Riptide Whip at 60° arcs | 45° and 50°, and Storm Lash's damage at 22 | Their pack numbers were 8 to 25% over the best w2 gun. |
| Thorn Whip: "the tip poisons twice as hard" | The tip applies its poison a second time | It needed no new element code. |

**Not built (carried to later batches):** `--arsenal-perf` (no check yet for 40 enemies
with melee only); the screen layer check (`--read-shot=family`); the thrown, summon and
ground stat columns; the Trials. `--loot-sim` belongs to batch 5.

**Checks** (headless, at most 4 instances, 0 `SCRIPT ERROR` in every run):
| Check | Result | Pass |
|---|---|---|
| Weapon bands (`--gun-probe`, 24 melee) | Single-target damage is about 130% of each weight's measured gun band, times the rarity premium. Every pack number is at or under the best gun of its weight (w1 28 vs 29.5, w2 49 to 94 vs 87.5, w3 76 to 112 vs 121, w4 108 to 201 vs 204, w5 183 vs 267). The exception is Riptide Whip, 8% over at 94.9. | yes (one near miss, noted) |
| Family probe (`--family-probe=melee --kite --mastery=full`, 4 runs from floor 1) | 4 of 4 reach floor 5. Damage a minute 0.0 to 0.12 on floors 1 and 2, 0.09 to 0.50 on floor 3 | yes (needs 2 of 4 to reach floor 3) |
| Melee stand-still (`--idle --family-probe=melee --build=human6980 --mastery=full --start-floor=2`) | 2 of 2 die on floor 2, at 74 and 76 s; under 50% health 0.69 and 0.74 of the fight; 2.20 and 1.95 bars a minute | yes |
| Human-build stand-still (same, without the family probe) | 2 of 2 die on floor 2, at 80 and 119 s; 0.63 and 0.53; 1.90 and 1.76 a minute | yes (session 3: 93 to 122 s, 1.28 to 1.70) |
| Human-build mover (`--kite`) | 2 of 2 reach floor 4. Floor 3: 0.40 and 0.25 a minute, under 50% health 0.09 and 0.07 | yes (session 3: 0.54 to 1.00) |
| Economy | Shop visits spent down: 9 of 11 human-build (82%) and 30 of 41 melee (73%); target 70%. Weapons gained 0 to 1 a floor after floor 1. Cards shown 13 to 22 a floor (the session-3 deviation) | yes |
| Cards (`--card-shot`) | `[CARDS] PASS 389`, at most 23 words, at most 278 px tall | yes |
| Fusion probe | `[FUSION-CHECK] PASS` | yes |
| Hub walk | `[HUB-WALK] PASS`, `[HUB-FRESH] PASS` | yes |

**Worth watching:** melee movers take very little damage (four tier-II melee weapons and
the human build's items reach floor 5 in all 4 runs). Standing still still dies fast, so
the rule holds. But if Emil finds melee too safe while moving, the levers are the 130%
share (section 10) or `Melee.FOLLOW`.

**Screenshots for when Emil is away (window runs):**
- A card contact sheet (`--card-shot` in a window) of the 23 new melee icons at 96 px and
  22 px, the rarity frames, the Blade chip and a tier IV rim.
- One fight per style with `--family-probe=melee`: the sweep, cleave, thrust and slam
  smears; the lash tip; the jab finisher; the full spin. Also the ready pose and the tilt.
  Check that no smear covers an enemy telegraph.
- Parry Blade cutting enemy shots, and Magma Maul's fissure.
- A shop with a Rare weapon ware and its price, and a floor-3 tier-II Common.

### Batch 2: Thrown and lobbed, and the new guns

**Builds:**
- `thrown.gd`: knives (stick and recall, at most 12), discs, stars, grenades with the fuse,
  javelins with the pin, the bola, and the anchor. Lob shadows. Holy Water and the Fire
  Bottle on today's pool code.
- The thrown column of the stat map.
- **Thrown weapons:** the 16 new non-legendary ones, and the 7 existing ones remapped.
- **Guns:** the 11 new non-legendary guns (the revolver magazine, bubbles, the bow, sticky
  darts, the reflecting beam, the harpoon, the sniper, the hymn, Singularity's curving
  pellets).
- **Items:** the Thrown tag and resonance, 12 Thrown passives, 6 thrown mods, 2 actives
  (including Recall), and 15 more items (element items for Fire, Ice, Wet, Shock and Oil,
  and behaviour items): 35 in all.
- **Unlocks:** Steel Knives in the core set; play goals, thrown family mastery and the first
  three Trials ("Blades only", "No guns", "One element").

**Files:** new `thrown.gd`, `projectile.gd`, `beam.gd` (reflect), `gun.gd`, `gun_library.gd`,
`gun_data.gd`, `weapon_looks.gd`, `items.gd`, `progress.gd`, `hub.gd` (the Trials board),
`main.gd` (Trial rules), `scripts/gun_probe.gd`.

**Done when** the section 8 checks pass for thrown and for the guns, `--family-probe=thrown`
passes, and the Trials board opens three Trials.

#### Batch 2 done (2026-11-10, VERSION 2026.11.10-arsenal2)

**Built:**
- `thrown.gd` (`Thrown`): every throw is still a pooled `Projectile`; its behaviour picks a
  path in `Thrown`, which runs the tick, the touches and the look. Styles:
  - knives stick in a foe (they follow it) or the floor for 1.5 s, then fly back and hit
    on the way out of the foe and along the return. At most 12 stuck per weapon (the
    oldest leaves), plus `knife_cap`;
  - discs jump between foes (`ricochets` + bounce), then return;
  - stars fly to their target and circle it twice at 40 px, hitting it once a lap;
  - grenades roll to stop at their target, bounce once off a wall or foe, and burst when
    the fuse (`linger`) runs out; Void Grenade drags foes in over its fuse, Cluster Bomb
    scatters five bomblets;
  - javelins pierce and pin the last foe 1 s; Etching Javelin sticks and corrodes 3 s;
  - bolas stop the first foe 1.2 s (elites and bosses 0.4 s); Shock Bola shocks foes near;
  - the anchor goes out, is dragged back on a dashed chain and pulls what it hits to you.
- Returns fly at 1.2x toward where you are now (offset by where it left your hand), vanish
  quietly and fire a `catch` event. Boomerangs return this way too.
- Lob shadows are 25% alpha. There is still no landing marker.
- Holy Water and Fire Bottle run on today's pool code; Holy Water marks foes inside, so
  their reactions hit harder (`MARK_BONUS`).
- The thrown stat map (2.2): `thrown_dmg`, `throw_rate`. Bounce is +1 jump for discs (+1
  lap for stars) and +25% on the return hit for the rest. Duration keeps knives stuck and
  pools down longer.
- **Weapons:** 16 thrown weapons and 11 guns, so the arsenal now has 93 weapons. The gun
  behaviours:
  - a revolver magazine with a reload ring;
  - bubbles that trap small foes 0.6 s;
  - a bow that pierces 2 and pushes;
  - sticky darts that burst after 1 s;
  - Glint Beam reflects off walls twice (`Beam._reflect`);
  - a harpoon that reels its foe in;
  - Longshot: hits past 300 px always crit (`Projectile.far_crit`);
  - Blood Hymn: up to x3 as health falls;
  - Singularity: pellets curve in to meet at the target's distance;
  - Rime Repeater: potency grows with spin;
  - Ember Scattergun: a second blast when a foe is within 90 px.
- Code-drawn icons for every new weapon (`weapon_looks.gd`), by thrown style and by gun
  archetype. `WeaponLooks.draws` now covers any weapon without a gun tile.
- **Items (35), all locked until unlocked**, with the Thrown tag and its resonance. At 3:
  +1 bounce or return hit. At 5: doubled, and thrown objects split in two on their last
  hit. A trigger with `"family": "thrown"` fires only for thrown weapons.
  - 12 Thrown passives: Return Grip, Fletching, Double Fuse, Sticky Fingers, Overarm,
    Quick Draw, Deep Pockets, Heavy Hand, Rim Shot, Catch Spark, Shrapnel Pouch, Pin
    Cushion;
  - 6 mods: Weighted Tip, Spin Grip (`g_bounce`, new), Barbed Edge, Throwing Strap, Twin
    Throw, Fletched Shaft;
  - 2 actives: Recall (every knife flies back at x2) and Knife Storm;
  - 10 element items, a state item and a reaction item each for Fire, Ice, Wet, Shock and
    Oil: Kindling Pouch, Frost Quiver, Damp Satchel, Copper Wire, Pitch Pot, Firebrand
    Sash, Rime Bandolier, Cold Current, Storm Bangle, Slick Spool;
  - 5 behaviour and stat items: Magnet Glove, Second Throw, Fuse Cutter, Hunter's Oath,
    Throwing Gloves.
- **Unlocks:** Steel Knives is in the core set. 14 play goals open the thrown Commons and
  Uncommons, the gun Commons and Uncommons, and Longshot, each with one item. 8 thrown
  mastery steps (`kills_thrown`, 60 to 2,600) open the rest, with two to three items
  each. The first three Trials open Blood Hymn, Singularity, Glint Beam and Harpoon with
  three items.
- **Trials** (`trials.gd`, the TRIALS plinth in the Stair):
  - three Trials: Blades Only, No Guns and One Element;
  - the board opens after 5 runs;
  - Begin goes through the Gate's loadout, and backing out cancels the Trial;
  - the rule fixes the start weapons (`Trials.start`) and filters every weapon offered
    (`Drops.roll_gun`);
  - a win opens the rewards once (`Progress.world["trials_won"]`, announced like an
    achievement), and the history entry records the Trial;
  - bots use `--trial=<id>`, and `--trials-open` opens the board on a young save.
- `--family-probe=thrown` (Steel Knives, Clay Grenade, Shock Bola, Frost Javelin).

**Deviations, and why:**
| Spec | Built | Why |
|---|---|---|
| Returns fly toward where you are now | Toward where you are now plus the hand offset (where the throw left the orbiting weapon) | Aimed at your centre, a boomerang thrown while standing still misses the line it went out on: Rime Chakram's return hits went to 0. |
| Crossing Axes pierce everything | Pierce 3, reaction power 0.12 (two-element rule) | At pierce 99 and 0.3, the pack number was 322 against the best w4 gun's 204. Now 221 (8% over), single 46.3 (the Epic band is 47 to 57). |
| A grenade rolls a fixed way | Rolled to stop at its target | At a fixed roll (about 150 px), kiting bots kept foes beyond it, and the family probe reached floor 3 in 1 of 4 runs. Aimed, it reaches floor 3 in 3 of 4. |
| Halo Disc grows with every bounce | +12% size and +7% damage a bounce | At +20% its pack was 169 against 121. Now 130 (7% over). |
| Longshot in the band | 30 single at 75 px, 60 past 300 px | The rule doubles it at range; the close number sits under the band on purpose. |
| Blood Hymn in the band | 26.7 at full health, up to x3 near death | The rule triples it; full health sits at 70% of the Epic band. |
| The first Trial at run 6 (6.3) | All three Trials open after 5 runs | One threshold for the first three; batch 5 spaces the rest. |
| Wind Star hits the target on arrival | It starts circling 44 px out: two lap hits and the return | That reads as "circles it twice". The damage was raised to 8 to stay in band. |
| Thrown objects split in two at the 5 resonance | They fork (`Projectile._fork`) into two bolts at 60% | It reuses the existing fork path. |

**Checks** (headless, at most 4 instances, 0 `SCRIPT ERROR` in every run):
| Check | Result | Pass |
|---|---|---|
| Weapon bands (`--gun-probe`, 8 s, the 27 new weapons) | All thrown single numbers are within 95 to 105% of the band times the premium, except Crossing Axes (46.3, about 2% under) and the pools (by design). Packs: Halo Disc 130 and Crossing Axes 221 are 7 to 8% over the best gun of their weight; the rest are under. Guns are in band except Longshot and Blood Hymn (deviations above). Zephyr Rang 14.9 and Rime Chakram 26.6 now land their return hits. | yes (two near misses) |
| Family probe (`--family-probe=thrown --kite --mastery=full --secs=1800`, 4 runs) | 3 of 4 reach floor 3 (one dies on floor 5, two on floor 3); one dies on floor 2 | yes (needs 2 of 4) |
| Thrown stand-still (`--idle --family-probe=thrown --build=human6980 --mastery=full --start-floor=2`) | 2 of 2 die on floor 2, at 61 and 43 s; under 50% health 0.77 and 0.72; 2.41 and 3.69 bars a minute | yes |
| Human-build stand-still (same, no family probe) | 2 of 2 die on floor 2, at 95 and 115 s; 1.73 and 1.44 a minute | yes |
| Human-build mover (`--kite`) | 2 of 2 reach floor 4 (one dies on floor 5). Floor 3: 0.16 and 0.27 a minute, under 50% health 0.00 and 0.10 | yes, but floor 3's time under 50% is low (as in batch 1) |
| Pressure, still against moving (floor 2) | Thrown idle 2.41 to 3.69 against thrown kite 0.16 to 0.69; human idle 1.44 to 1.73 against kite 0.11 to 0.20 | yes (at least 2x) |
| Economy | Shop visits spent down: 7 of 9 human-build (78%), 15 of 18 thrown (83%). Weapons gained 0 to 1 a floor (the probes start with four). | yes |
| Cards (`--card-shot`) | `[CARDS] PASS 451`, at most 23 words, at most 278 px tall | yes |
| Fusion probe, idle bot | `[FUSION-CHECK] PASS` (also in every bot run); the standard idle bot dies on floor 1 at 35 s | yes |
| Hub walk | `[HUB-WALK] PASS`, `[HUB-FRESH] PASS`. With a kept save, the trials station passes: 3 Trials, 3 open with `--trials-open` and 0 open below 5 runs | yes |
| Trial starts (`--trial=no_guns`, `--trial=one_element`) | `[TRIAL] no_guns start weapons=steel_knives,tin_sabre`; `[TRIAL] one_element start weapons=water_pistol` | yes |
| Load check (`--editor --quit`) | 0 `SCRIPT ERROR` | yes |
| Smoke | `[SMOKE] ALL PASS` | yes |
| Emil's files | `save.json` and `mastery.json` were last written at 13:45, before this session, and the last `runs.jsonl` lines are his own (`bot:false`, the hitfeel build). Every bot used `--instance` | yes |

**Not built or not checked:**
- A Trial won end to end. The reward path is a few lines in `Progress.end_run`, but no
  bot cleared a full run under a Trial.
- `--arsenal-perf` and the `--read-shot=family` layer check, which carry over from batch 1.
- Guns count toward Gunslinger: unchanged, still off (batch 1's deviation).
- Legendaries (Mother of Knives, Skyfall, Prism Disc and the four gun legendaries) belong
  to batch 5.

**Worth watching:** thrown builds take more damage while moving than melee (0.3 to 1.3 bars
a minute on floors 2 and 3, against melee's 0.0 to 0.5). Thrown is not too safe, but it may feel
weak. The levers are the thrown share (100%) and the knives' 1.5 s stick.

**Screenshots for when Emil is away (window runs):**
- A card contact sheet (`--card-shot` in a window) with the 27 new icons at 96 px and
  22 px.
- A fight with `--family-probe=thrown`: knives stuck in foes and in the floor, then the
  recall; a disc's jumps; a grenade's roll and burst (check there is no floor circle); the
  javelin pin; the bola. Check that no thrown object covers an enemy telegraph.
- The Wind Star's laps, Crossing Axes meeting, and the Drowned Anchor's chain.
- Glint Beam reflecting off a wall, Singularity's pellets meeting, and the revolver's
  reload ring.
- Lobs (Boulder Mortar, the flasks): the 25% shadow only.
- The TRIALS plinth in the Stair, and its board both locked and open (`--hub-shot
  --trials-open --keep-save`).

### Batch 3: Summons and drones

**Builds:**
- `summon.gd`: drone, familiar, orbit, swarm, golem and shade kinds (shades wait for
  batch 5); the leash, `Focus.pick_from`, the 16-body cap, respawn at room start, the friend
  ring, and sound limits. Today's `turret.gd` joins the family cap.
- The summon column of the stat map.
- **Summon weapons:** the 20 new non-legendary ones, plus the Kettle Gun remapped.
- **Items:** the Swarm tag and resonance, 12 Swarm passives, 6 summon mods, 2 actives
  (including Rally), and 10 more items (element items for Poison, Acid, Blood and Void):
  30 in all.
- **Unlocks:** Scout Drone in the core set; summon family mastery; the Trial "Summoner".
- **Tests:** the summon stand-still check (summons must not keep the idle bot alive), and
  `--arsenal-perf` with two summon weapons at cap.

**Files:** new `summon.gd`, `turret.gd`, `focus.gd`, `gun.gd`, `gun_library.gd`,
`weapon_looks.gd`, `items.gd`, `progress.gd`, `player.gd` (summons cleared and respawned per
room), `room.gd`.

**Done when** the section 8 checks pass for summons, the idle summon build dies by the end of
floor 3, and `--arsenal-perf` holds with 16 bodies out.

### Batch 4: Auras and traps

**Builds:**
- `ground_zone.gd`: the aura, pulse, trail, totem, field, snare, glyph and pod kinds;
  placement from the closest enemy; the 40-effect global cap (counting today's pools and
  dash patches); one spatial query per tick; the floor look of section 2.6 (dashed rim, faint
  fill, no pulse, under enemies).
- The ground column of the stat map.
- **Ground weapons:** the 20 new non-legendary ones, plus Frost Caster, Tar Mortar and
  Corrosion Burst remapped.
- **Items:** the Ground tag and resonance, 12 Ground passives, 6 ground mods, 2 actives
  (including Seed), and 10 more items (element items for Holy, Gale and Stone, and healing):
  30 in all.
- **Unlocks:** Ember Halo in the core set; ground family mastery; the Trial "Ground: you
  can't attack".
- **Tests:** the ground stand-still check, `--read-shot=ground` (layer check), and
  `--arsenal-perf` with all four families at their caps.

**Files:** new `ground_zone.gd`, `mine.gd`, `cloud.gd` (shared cap), `gun.gd`,
`gun_library.gd`, `weapon_looks.gd`, `items.gd`, `progress.gd`, `strike.gd`
(`enemies_in_circle`), `room.gd`.

**Done when** the section 8 checks pass for ground weapons, the idle ground build dies by
the end of floor 3, and the screen check passes.

### Batch 5: Legendaries, the last items, synergies and pacing

**Builds:**
- `legendary.gd`: the 18 rules (section 3.5), hooked through `Items.fire` events (`hit`,
  `kill`, `vent`, `dash`, `reaction`). Shades in `summon.gd`. Phoenix Lantern beside Last
  Breath.
- The Legendary weapon odds turned on; the drought rule (`Progress.legendary_drought`); the
  celebration (section 3.6: the black-and-gold plinth, the bell, the gold card, the banner,
  the journal line, the minimap star).
- **Weapons:** the 18 legendaries, which brings the total to 151.
- **Items:** 30 more items (actives, cross-family behaviour items, trade-offs and cursed
  pedestals), which brings the total to 300.
- **Synergies:** 30 new, to 50 (10 weapon pairs, 12 weapon plus item, 8 item pairs); weapon
  halves on the synergy card; `SYNERGY_CARD_CHANCE` tuned by `--loot-sim`.
- **Unlocks:** the 18 legendary feats with hints, the remaining Trials (to 12), milestones,
  and the pacing check: a new `--unlock-sim` that replays the bot's stat gains per run and
  prints unlocks per run against section 6.3.
- **Tests:** `--legendary-probe`, `--loot-sim`, all of section 8 on the full arsenal.

**Files:** new `legendary.gd`, `summon.gd`, `items.gd`, `drops.gd`, `progress.gd`,
`pedestal.gd`, `item_card.gd`, `hud.gd`, `sfx.gd`, `journal.gd`, `minimap.gd`, `hub.gd`,
`player.gd`, `gun_library.gd`.

**Done when** `[LEGENDARY-PROBE] PASS 18 of 18`, the `--loot-sim` shares sit inside section 8's
targets, `--unlock-sim` gives about 4 unlocks a run at first and keeps unlocking past run 200,
and the full section 8 table passes.

**Budget guide:** batches 1 and 5 are the largest. If a batch runs long, the items are the part
to carry over: weapons and their checks come first.

---

## 10. Defaults Emil may want to change

| Default | Where | Why it might change |
|---|---|---|
| Rarity is fixed per weapon; tiers come from merging | 3.1 | Brotato instead ties rarity to tier |
| Rarity power premium x1.00 to x1.25 | 3.1 | Raise it if Rares don't feel worth it |
| A Legendary offered in about 1 run in 3 (reaching floor 4) | 3.3 | "Once every few runs" could mean rarer |
| The drought rule after 4 dry runs | 3.3 | Turn it off for pure luck |
| Melee at 130% of the gun band | 2.3 | If melee feels too risky or too safe |
| Summons never targeted by enemies | 2.5 | Some games let summons tank; that would weaken the stand-still rule |
| Weapons count toward family tags | 5.3 | If family resonances form too easily |
| 8 weapons on a fresh save | 6.1 | More if early runs feel samey |
| A weapon card in 35% of treasure rows | 3.2 | Higher means more weapon finds and fewer items |
