# PRESSURE — Game Design Document (living)

Working title. A controller-first, co-op, wave-based shooter where guns apply elements,
enemies die to *reactions* between elements, and nothing ever gets easy because threat
scales with your power instead of behind it.

Touchstones: Brotato (waves + shop), Vampire Survivors (hordes), Isaac (run map, unlocks,
synergies), Magicka / Genshin (elemental reactions), World of Warcraft (gear, dungeons,
raids, loot tables).

---

## 1. Design pillars

1. **Reactions, not raw damage.** Every gun applies an element. Combining two elements on an
   enemy fires a reaction, and reactions do the real damage. Raw damage is the chip.
2. **Power has a cost you manage every second.** Weight, pressure, and elite sequences mean
   more power always brings more decisions, never fewer.
3. **Difficulty follows you up.** Resistance drift, dungeon tiers keyed to gear score, and
   elite sequences grow with the player. There is no point where you stop paying attention.
4. **Built for the couch, then the internet.** Co-op from the first line of code.
   Browser-playable so friends can join without installing anything.

## 2. Core combat

### Controls
- Controller first, mouse and keyboard fully supported.
- Left stick / WASD moves. Right stick / mouse aims. Right trigger / left mouse fires the primary.
- **Aim mode toggle** (Y / Tab): auto-aim or manual.
- **Vent** (LB / Space) dumps the pressure gauge as a nova.
- **Swap primary** (X / Q) cycles which carried gun is on the trigger.

### Firing model
- Every gun you carry aims and fires on its own at the nearest enemy in range, Brotato
  style. Guns orbit the figure and point where they shoot, so your loadout is visible.
  With nothing to shoot, a gun in range of an obstacle fires its element at that instead,
  which is how hidden rooms open.
- Manual aim, the trigger and focus were cut: play showed they added input without adding
  decisions. The decisions are what you carry, what you wear, where you stand, and when you vent.

### Levels
- Kills give XP. Each level, once the room is clear, pick one of three upgrades from a
  Brotato-like catalog: damage, attack speed, crit chance and damage, bounces, pierce,
  projectiles, health, armour, dodge, regen, speed, range, potency, element duration, chain
  jumps, lifesteal, thorns, scrap, pressure limit and decay, vent size, carry, XP gain.
- Brotato-shaped curve: the cost of a level rises quadratically (20, 35, 56, 83, 116...)
  and each upgrade is small (+4% damage, +8 health, +3% crit), so a floor gives three to
  five levels and no single pick swings a run. Power comes from stacking many of them.
  XP per kill is 2 + 2 x scrap value, which lands around level 14 on floor 4.
- Measured loop (bot, naked start, explores every room, spends in shops): floor 2 at
  5 min, floor 3 at 10, floor 4 at 18 with level 19, ten guns and 141 max health, never
  in danger past floor 1; a human who skips rooms is faster and leaner. The arena feeds
  20 + 11 x difficulty enemy hp per second; every spawned group buys itself a pause of
  its hp over that rate. Floors 3 to 5 are the next tuning target once play says so.

### Gun tiers and mods
- Guns have tiers I to IV, Brotato style. Picking up a duplicate merges it into the one
  you carry one tier higher (no extra weight); the shop's Gunsmith raises your lowest-tier
  gun for scrap. Each tier adds 35% damage, 12% fire rate, a bigger projectile, and from
  tier III a point of pierce.
- A gun holds as many mods as its tier, and mod effects stack: four Coatings on one gun
  mean every hit applies five elements. That is meant to get absurd late in a run.
- Picking up a mod with more than one gun that has a free slot opens a small picker:
  one card per gun with its tier and the mods it already carries. With one candidate the
  mod goes straight on; with none, the pedestal says so and the mod stays.

### Weight
- No gun slots. A **carry budget** (starts at 10, bought up in the shop).
- Pistol 1, SMG 2, shotgun 3, flamethrower 5, lightning cannon 6, and so on.
- Total weight slows you (about 2.5% move speed per point). Many light guns = many small
  reactions everywhere. Few heavy guns = rare huge reactions. Both viable, both feel different.

### Elements and reactions
Twelve elements: **Wet, Shock, Fire, Ice, Oil, Poison, Acid, Blood, Void, Holy, Gale, Stone**.
Sixty-six pairs, sixty-five reactions (water and oil do not mix), all defined as
data in `scripts/elements.gd` using a small action vocabulary: damage, burst, apply an
element in a radius, burn, poison, bleed, corrode, freeze, stun, slow, pull, push, chain,
chain along a state, lingering cloud, purge, spread, decay, heal the source. Adding a
reaction is one line; adding an element is a colour, a pressure weight and its lines.

Status effects on enemies: burn, stacking poison (a poisoned corpse passes it on),
bleed (hurts while moving), corrosion (+50% damage taken), freeze (x3 damage, shatters),
stun, slow, shoves from pulls and pushes, and lingering clouds that keep applying an element.

**Patches, contained.** A few reactions leave something on the floor or in the air: Steam
leaves a puddle, Toxic Mist and Noxious Flame a poison cloud, Magma a lava pool, Blizzard an
ice cloud, Consecrate hallowed ground. A patch keeps applying its element to whoever is in
it, and anything of another element that enters it (a projectile, a vent, another patch)
plays that pair's reaction once over everyone inside, then the patch is used up. Lightning
through a steam puddle shocks everyone standing in it, fire into a poison cloud burns the
crowd, and then it is gone. A patch never spawns another patch, so there is no recursion.
Water is a puddle that drenches, not weather. Fire spreads only where there is fuel: a
burning enemy ignites oiled neighbours. An earlier version let clouds transform and chain
into each other; it produced spectacular nonsense, so it was pulled back to one step.

A few of the sixty-five: Wet + Void is a Whirlpool that drags everything in. Shock + Holy is
Smite, one enormous strike. Fire + Stone leaves a pool of Magma. Poison + Gale is a Plague
Wind. Void + Holy is Annihilation. Wet + Holy is Baptism: strips every state and punishes
each one. Fire the pair once and the journal's Reactions tab reveals what it does.

Rules: an enemy carries states for a few seconds. When a new element lands on an enemy that
already has a different state, the pair reacts, consumes the existing state, and the new one
is not applied. Same element refreshes the timer.

**Physical rules on top of the pairs** (what an element does to a body's condition):
- Water conducts: shock does +50% raw damage to a wet enemy. Water puts fire out: wet
  bodies take half fire damage, burn for half as long, and a wet hit extinguishes a burn.
- Oil feeds fire: +25% fire damage and burns last half again as long on an oiled body;
  a burning body ignites oiled neighbours; shock sparks oil (Ignition).
- Fire thaws: a fire hit ends a freeze. Cold cracks: stone and shock hit frozen bodies
  harder (Cryoshock stuns and cracks). Stone grounds shock, so that pair barely reacts.
- Wind fans: a gale hit on a burning body spreads the burn to neighbours; a gale carries
  poison, acid, blood and oil onto everyone nearby (Plague Wind, Acid Rain, Spray, Oil
  Spray) and pushes.
- Holy scours: +25% against poisoned or void-marked bodies; purges states (Baptism,
  Cleanse, Neutralize). Poison dissolves in water and spreads (Contamination).
- Stone weighs: a stone-marked body moves at three quarters speed. Acid corrodes: +50%
  damage taken while corroded. Void pulls, gale pushes, blood bleeds while they move.

### Pressure gauge (now: vent charge)
- One gauge per player, from **cold (-100)** through **neutral (0)** to **hot (+100)**.
  Fire and Shock guns push hot, Wet and Ice push cold, it drifts back toward neutral.
- **Vent** turns the gauge into a weapon: a fire nova when hot, a frost nova when cold,
  scaled by how far from neutral you are, and a vent sweeping through a cloud or puddle
  reacts with it.
- The overheat and freeze-up stalls were cut. Watching the bot play showed the gauge was
  being managed rather than used: a penalty you avoid is a chore, a charge you spend is a
  decision. Pressure is now purely the fuel for the one active ability.

### What keeps it hard
- **Resistance drift.** From wave 3, a growing share of enemies spawn immune to raw damage
  from one element you carry (shown as a ring in that colour). Reactions still work on them.
  Your mono-fire god build meets a wave that only shatters.
- **Reaction shields.** Elites and bosses carry a shield with crack pips. Any reaction cracks
  it; the one it is attuned to (shown as the element pair above its head) cracks it twice;
  raw damage leaks through at a fifth. Bosses re-attune at half health. Two earlier designs
  died here: "reactions in order" could not survive auto-fire, and "only the attuned
  reaction" turned bosses into lotteries once a run carried many elements. The shield is now
  a test of whether you are reacting at all, with a bonus for the right one.
- **Dungeon tiers** (see section 4). Difficulty keys to your gear score, like Mythic+ keystones.

## 3. Run structure: Brotato waves inside an Isaac map

The run is a **dungeon**: a node map of rooms, Isaac style. Most rooms are **arenas** that play
as a Brotato wave (timed, enemies pour in, survive). Clear it and the doors open. Between rooms
you pick the next node. Room types:

- **Arena** (wave room, the bread and butter)
- **Shop** (guns by weight, carry budget, upgrades; scrap is the currency)
- **Challenge room** (opt-in: a sequence elite gauntlet, a mono-element room, no-vent room, for a
  guaranteed gear drop)
- **Hidden room** (reached only by an environmental reaction: freeze a pool to cross it, burn a
  thicket, shock a door's water-logged lock. Reactions are a traversal tool, not just damage.)
- **Boss room** (end of each floor)

A dungeon is 5 floors. Floors get larger and add more room types and enemy kinds. A
distinct two-phase boss ends each floor (brute king, hive mother, storm warden, pyre
lord, void herald).

**Raids** are the endgame: a longer co-op dungeon with multiple bosses that have WoW-style
mechanics (split the party, soak zones, interrupt casts with a specific reaction, adds that
must die in element order). Designed for 2-4 players. Only reachable at a gear score threshold.

## 4. Meta progression — BUILT, rework pending

Principle: **every run starts naked, and nothing you own makes a run easier.** Meta
progression widens what can happen in a run and what you are allowed to attempt, never
your starting power. That keeps the "overpowered and bored" failure out by construction.

**Status (2026-11-05, measured from code and bot telemetry; see
`reports/Roguelite meta progression analysis.md`).** The built meta layer contradicts this
principle in one place: the Mastery tree sells permanent stat power (326 points, +21%
damage and +32 max HP at completion), while 39 of 43 guns and 12 of 13 classes start
locked, so a new save sees 4 guns that pair into 5 of the 65 reactions. The reference
games do the opposite: Hades keeps combat talents to about 18% of its Mirror cost as
swappable A/B pairs, Dead Cells caps permanent power at four flask charges, Risk of Rain 2
has none. The structural rework (recommendations R4 to R9 in the report) is next; the
measured defects (R1, R2, R3, R10) are fixed.

**Target pacing to tune against** (provisional until real-player telemetry exists): one
visible unlock per run for the first five runs, then one every one to two runs to run 20;
every element available by run 5; first win around runs 8 to 15; meta stat power at most
+10% damage and +20 max HP at completion, the rest of progression being options.

**Current counts:** 55 achievements with 61 unlock rewards (39 guns, 12 classes, 5
obstacle kinds, 2 rarity tiers, 2 shop upgrades, 1 room type); 43 guns; 238 items (55
common, 65 uncommon, 63 rare, 39 epic, 16 legendary); 13 classes; 65 reactions.

### Itemization model (Brotato tiers, Isaac pools) — BUILT
- Rarity is the quality axis and gates power: commons are one small stat, uncommons two,
  rares introduce mechanics (bounce, pierce, chain), epics add projectiles or big
  conditionals with a cost, legendaries are run-defining. Rarity odds use gates and caps
  by difficulty and scale with luck; prices are base + difficulty + 8% of base per step.
- Pools by room type, Isaac style, with per-item pick weights and no repeats within a
  run. Treasure rooms are the build-defining source, shops are utility, boss drops are
  stat-ups, hidden rooms are weird and strong.
- An active item slot with room-clear charges, Isaac's spacebar item.
- Level-ups use the same tiers keyed on level and luck; mechanical level-ups are rare.

### In-run gear (the WoW loot loop, inside one run) — BUILT, first batch
- Gear drops during the run and is lost at the end, like Isaac items. Elites drop an item
  55% of the time, bosses always drop rare or better, shops sell two, treasure rooms offer
  two guns and two items (take one), hidden rooms hold a rare, challenge rooms pay three
  to choose from. Replacing an equipped item puts the old one back on the floor.
- Slots: head, chest, hands, feet, two rings, two trinkets, and one mod per gun.
  Rarities common to legendary with WoW colours; epic and legendary are unlocked.
- **Items are data.** `scripts/items.gd` has a small vocabulary: flat stat mods, conditional
  mods (while hot, while cold, below 40% HP, in manual aim), and triggers (on hit, kill,
  reaction, a specific reaction, vent, room clear, hurt, overheat, freeze-up) that do things
  (apply an element, nova, heal, scrap, shoot, chain, slow, shield). Seventy items exist today:
  forty-five hand-written plus five families of five across the elements. Hundreds is an
  authoring job in that one file, and every new item automatically composes with every other.
- Synergy examples that already work: a Shock Coating on the Water Pistol makes every shot
  Chain Lightning on its own. Conductor's Mail plus Hands of the Storm turns hits into
  arcing chains. Heart of the Forge plus any fire gun makes kills explode in chains.
  Signet of Overload turns overheating into a weapon, so Overclock stops being a downside.
- **Sets.** Eight sets (five elemental families, Scavenger, Overloader, Warden) grant
  bonuses at 2, 3 and 4 pieces; gun mods count as pieces. The character sheet shows every
  set you have a piece of and which thresholds are active.
- Scrap in the run buys, repairs and rerolls. Nothing carries out except unlocks.

### Layer 1: the unlock pool (Isaac) — BUILT
- Every run starts with no guns and no gear. The entrance offers each player two random
  unlocked guns on pedestals; take one. The pool of guns a run can offer
  (shops, treasure, challenge rewards), the obstacle kinds in front of hidden rooms, the
  challenge room itself and a fourth shop slot are all unlocked by achievements.
- 55 achievements tracked across runs in the save file: kills, specific reaction counts,
  elites and bosses killed, floors cleared, hidden rooms opened, vents fired, gear equipped,
  runs won. Descriptions always state the real goal; only real reactions count (popups like
  "Shield cracked" do not). The "next goals" shown in the hub and the run-over screen are
  the closest to done that the current gun pool can actually progress.
- Unlocks pop as a toast when earned. The run-end screen lists what this run unlocked and
  the next three achievements with progress, so a lost run still shows a path.
- 43 guns exist; 4 start unlocked. The pool is the lever: adding a gun, obstacle or room
  type to the game should always come with the achievement that unlocks it.
- Epic and legendary gear unlock after 8 and 25 pieces equipped, and from then on can roll
  from floor 1 at low odds (epic 1.2% per difficulty step from difficulty 2, cap 10%;
  legendary 0.4%, cap 4%) instead of only from floor 2 and 3.
- Save file: `user://save.json` (on Windows: `%APPDATA%/Godot/app_userdata/Pressure/`).
  F9 wipes it for testing a first-ever run.

### Layer 1b: the Mastery tree — BUILT
- A permanent, idle-game sized tree: 212 nodes in 17 branches (offense, defense,
  pressure, economy, utility, and one per element). Each node is a small bonus, one to
  three percent or a point of a flat stat, and costs one to three mastery points.
- Points come from runs: one per floor reached, one per 150 kills, three for a win. They
  are spent at the hub's Shrine. Wipe save clears the tree too. Measured at bot pace a run
  pays a median of 1 point, so completion takes about 290 to 330 runs: far too slow, and
  the R7 rework will pay for performance, not only depth.
- Note the two meanings of floors: mastery pays per floor *reached*, achievements count
  floors *cleared* ("Clear 3 floors").
- The screen is a literal node graph, Path-of-Exile style: a core showing unspent points,
  seventeen spokes, each branch a chain of circles with side chains stepping out, edges
  that light up as you buy along them. The stick or d-pad walks the graph, A buys, the
  right stick pans, triggers zoom, shoulders jump between branches; mouse drag, wheel and
  click do the same.
- This is the one deliberate exception to "nothing makes a run easier": the bonuses are
  small enough to be felt over dozens of runs, not one, and the real growth stays in the
  unlock pool. If it ever trivialises floor 1, shrink the node values, not the tree.

### Layer 2: starting classes (Dark Souls, Isaac) — BUILT
- A class is only the first room. Each is a starting gun of its element, one themed
  starting item, a small permanent affinity (that element's reactions +20% potency, its
  guns +10% damage) and a quirk (the Pyromancer is frailer, the Frostbinder slower, the
  Templar regenerates, the Voidwalker is lucky). From there the run goes wherever the
  loot takes it, Dark Souls style: a Pyromancer who finds a hydro cannon becomes a
  steam build.
- The Vagrant is the naked start (pick of two guns, a little more carry and scrap) and
  is always unlocked; the twelve elemental classes unlock through achievements on their
  element's signature reaction, Isaac style. Later joiners in co-op get a random unlocked
  class. Picked on a card screen between Play and the first room.
- Items are visible on the figure (Isaac costumes, Brotato weapons): hats, plate, gloves,
  boots, charms, an aura for rings and legendaries, the active item on the back, and a
  completed set tints the whole figure (Guppy-style transformation). Twenty
  shot-modifier items (homing, shards, splash, boomerang, spectral, orbitals, shot size)
  are the tear-modifier layer.

### Layer 3: keystone tiers (WoW Mythic+)
- Clearing a dungeon earns a **keystone** one tier higher. Tiers add affixes: more
  resistances, longer elite sequences, a bleed on contact, rooms that lock elements out.
- Higher tiers drop from richer loot tables and unlock faster. This is the "gear score
  gates content" hook with the power creep removed: the number that grows is the difficulty
  you are allowed to attempt, and the reward for growing it is more chaos, not an easier game.

### Layer 4: the hall (small, cosmetic, satisfying)
- A hub room between runs that fills up: trophies from bosses on the wall, a bestiary with
  what you have learned about elites (their sequences shown once discovered), a reaction
  compendium, run history. Nothing in it changes gameplay.

### Save file
- Unlocks, characters, highest keystone per character, bestiary, stats and run history.

## 5. Co-op
- 2 to 4 players. **Couch co-op first** (one keyboard + mouse player, any number of pads;
  press Start on a pad to join). Works in the browser build too.
- **Online later**: host-authoritative with Godot's built-in multiplayer. One friend hosts the
  desktop build. Browser-to-browser needs a relay server and comes last.
- Architecture rule from day one: the host owns all enemies, waves, drops and reactions.
  Clients send input; everything else is replicated.

## 6. Tech
- **Godot 4.7, GDScript.** Web export is GDScript only, and Azeroth Survivors proves a
  no-install browser game is the right way to share.
- Compatibility renderer (WebGL 2) so the web build runs everywhere. The Web preset is
  single-threaded on purpose: that build needs no cross-origin isolation headers, so
  GitHub Pages (or any static host) can serve it. A push to main deploys it.
- Damage numbers on every hit, batched for damage over time; player names from the
  menu replace P1..P4.
- Art: Kenney CC0 packs, tinted dark. The 1-Bit Pack gives a single white-on-transparent
  sheet, so the whole look is a palette in `art.gd`: bone, blood, rust and stone, with a
  vignette over everything. No generative art.
- Effects: generated pixel particles (Noita-inspired, no sheets): a 700-slot ring
  buffer of 2 to 5 px squares in three-step element palettes, translucent so the fight
  stays readable, with a behaviour per element (fire rises and flickers, water falls and
  splashes, ice crumbles, sparks arc, oil sticks, void spirals in). Reactions map by
  what they do: a burst is a hollow pixel ring, a cloud lingers, a freeze is a shard
  star, pulls spiral in. Burning enemies shed embers, poisoned ones motes.
- Music: three CC0 synthwave tracks by Alex McCulloch (menu, run, boss).
- Text: the Kenney Pixel font everywhere, never under 20 px, and as few words as the
  screen can get away with.
- Code-driven scenes for now (everything is built in `_ready`), so the project is easy to
  read as plain scripts. Scenes get moved into the editor when they stabilise.

## 7. Milestones

| # | Milestone | Status |
|---|---|---|
| 0 | **Combat core** | Done. Guns, five reactions, pressure, vent, focus, resistance drift, sequence elites, couch co-op. |
| 1 | **Dungeon run** | Done (first pass). Generated floor of rooms, doors, arena waves, shop with scrap, treasure, challenge, hidden room behind an elemental obstacle, five bosses with phases, five floors, minimap. |
| 2 | Tuning & content | Human playtesting, 10+ guns, more enemy types, more obstacles and reactions, room layouts with cover |
| 3 | Meta progression | Unlock pool done (achievements, save file, gated guns/obstacles/rooms). Next: in-run gear with loot tables, characters, keystone tiers, the hall |
| 4 | Online co-op | Host-authoritative netcode for the desktop build |
| 5 | Raids | Multi-boss co-op dungeons with mechanics |
| 6 | Art, sound & juice | Done (first pass): Kenney 1-Bit sprites, particle reactions on an additive layer, scorches, corpses and bone bits, procedural animation (hop, spawn pop, hit squash, recoil, muzzle flash), camera shake, 46 Kenney sounds, main menu, codex, pause menu, Brotato-style HUD. Music still to do. |

### What the dungeon run does today
- A floor is a tree of 9 to 13 rooms on a grid. Dead ends become the boss, treasure, shop
  and challenge rooms. One hidden room hangs off an ordinary room behind an obstacle:
  a pool (freeze it), a thicket (burn it) or a rusted valve (Steam it: Wet, then Fire).
- Arena rooms lock their doors and run a timed wave; the timer grows with difficulty.
  Difficulty starts at 2, adds 4 per floor, and creeps up one step every second room
  cleared, so a floor is one difficulty band and the stairs are the jump.
- Every arena clear pays out a free gun or item on a pedestal, so power grows with the
  rooms whether or not the shop turns up. The minimap reveals rooms Isaac-style, as you
  reach their neighbours; special rooms are dressed so you know them on sight.
- Treasure rooms are chests: one pick from gear, a gun, or a run boon (Vitality, Pack
  Mule, Boiler, Hoard). Chest tier rises with the floor and a little luck, raising the
  gear rarity and the boon size. Shop prices are high enough that a floor's scrap buys one
  or two things, not the whole counter.
- Rooms are 1120 by 720 with the camera zoomed to 1.3x, so a room is about a screen and
  a half, close to Isaac's one-screen rooms with a little scroll.
- Enemies drop scrap. The shop sells three guns, a carry upgrade and a repair.
  Treasure rooms give a free pick of one gun from three. Challenge rooms start from a sigil,
  spawn two sequence elites plus adds, and pay out scrap and a free gun pick.
- The boss has a reaction sequence shield, re-shields with a new sequence at half health,
  and summons adds. Killing it spawns the stairs. Five floors, then the run is won.
- The trigger always fires along your aim even with no enemy in range, so obstacles can
  be shot deliberately. Interact with pedestals using E or the A button.

## 8. Balance probes (bot flags)

`godot --path . res://scenes/main.tscn -- --autotest` plus: `--secs=N` run length,
`--short` 70 s, `--class=<id>`, `--idle` (stand still in fights), `--loadout=a,b,c`
(start with these guns), `--veteran` (everything unlocked), `--mastery=N|full` (buy that
many mastery points of nodes on a throwaway file; the bot never touches the real tree),
`--arsenal` (every gun), `--gear` (equip shock gear at 45 s for the sheet screenshot).
Telemetry from bot runs is stored locally with `bot: true` and never uploaded.

## 9. Debug controls in this build
- `1`..`0` give player 1 any gun, unlocked or not
- `R` restarts the run
- `F1` toggles the help overlay
- `F9` wipes the save file
- `godot --path . -- --autotest` runs the self-test bot through the dungeon
