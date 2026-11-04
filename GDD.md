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
- The **arsenal** (every gun you carry) auto-fires. In auto-aim mode each gun picks its own
  nearest target in range. In manual mode the arsenal fires along your aim, but only while an
  enemy is in range, so you are never spraying at nothing.
- One carried gun is the **primary**. It only fires on the trigger. The primary is where the
  deliberate reaction setups happen: wet them with the arsenal, shock them with the trigger.

### Rewarding manual aim
- **Target choice.** Auto-aim always picks the nearest enemy. Sequence elites need a specific
  reaction on *them*, so auto-aim wastes shots on chaff. Manual aim is how you set up reactions on purpose.
- **Focus.** Consecutive manual hits build a focus meter that multiplies reaction potency
  (up to +50%). Misses and time drain it. Auto-aim never builds focus.

### Weight
- No gun slots. A **carry budget** (starts at 10, bought up in the shop).
- Pistol 1, SMG 2, shotgun 3, flamethrower 5, lightning cannon 6, and so on.
- Total weight slows you (about 2.5% move speed per point). Many light guns = many small
  reactions everywhere. Few heavy guns = rare huge reactions. Both viable, both feel different.

### Elements and reactions
States an enemy can carry: **Wet, Shock, Fire, Ice, Oil** (more later: Acid, Void, Holy...).

| A | B | Reaction | Effect |
|---|---|---|---|
| Wet | Shock | Chain Lightning | Jumps between all wet enemies in range |
| Wet | Fire | Steam | Burst damage, cloud slows enemies inside |
| Wet | Ice | Deep Freeze | Enemy frozen solid, takes triple damage, shatters on death |
| Oil | Fire | Inferno | Heavy burn that spreads along oiled enemies |
| Oil | Shock | Ignition | Shock damage plus a lighter burn |

Rules: an enemy carries states for a few seconds. When a new element lands on an enemy that
already has a different state, the pair reacts, consumes the existing state, and the new one
is not applied. Same element refreshes the timer.

### Pressure gauge
- One gauge per player, from **cold (-100)** through **neutral (0)** to **hot (+100)**.
- Fire and Shock guns push hot. Wet and Ice guns push cold. Oil is neutral. It drifts back
  toward neutral slowly.
- **Overheat** (hits +100): all guns stall for 3 s. **Freeze-up** (hits -100): fire rate crawls for 3 s.
- A balanced loadout self-regulates, which rewards the synergies the game is about.
- **Vent** turns the gauge into a weapon: a fire nova when hot, a frost nova when cold,
  scaled by how far from neutral you are. Mono-element builds live on the vent button.

### What keeps it hard
- **Resistance drift.** From wave 3, a growing share of enemies spawn immune to raw damage
  from one element you carry (shown as a ring in that colour). Reactions still work on them.
  Your mono-fire god build meets a wave that only shatters.
- **Sequence elites.** Shielded elites take no damage until reactions land on them in the
  order shown above their head (e.g. Chain Lightning, then Deep Freeze). The late game becomes
  a puzzle at speed.
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

A dungeon is 3 floors. Floors get larger and add more room types. A boss ends each floor.

**Raids** are the endgame: a longer co-op dungeon with multiple bosses that have WoW-style
mechanics (split the party, soak zones, interrupt casts with a specific reaction, adds that
must die in element order). Designed for 2-4 players. Only reachable at a gear score threshold.

## 4. Meta progression

### Gear (WoW-style)
- Elites and bosses have **loot tables**. Gear drops persist between runs.
- Slots: Barrel, Core, Grip, Rig (armour), Trinket x2. Each gun also has a mod slot.
- Gear is mostly **horizontal**: new reactions, gun behaviours (pierce, ricochet, orbit), vent
  variants, pressure tolerance. Raw stat gear exists but is capped so the game never becomes trivial.
- **Scrap** unwanted gear into materials. **Upgrade** gear with materials, which raises gear score.
- **Gear score** sets your available **dungeon tier**. Higher tier: more resistances, longer
  sequences, faster waves, better loot. The hook: your power unlocks harder content, never an easier game.

### Unlocks (Isaac-style)
- The gun and gear pools start small. Achievements (first Chain Lightning kill, clear a dungeon
  with only cold guns, vent a 100-pressure nova, ...) add items to the pool.
- Early runs are simple on purpose. Late runs have a huge arsenal and wild reactions.
- Save file tracks: unlocks, gear inventory, materials, best tier cleared, stats.

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
- Compatibility renderer (WebGL 2) so the web build runs everywhere.
- Art: placeholder shapes now, Kenney CC0 asset packs next, no generative art.
- Code-driven scenes for now (everything is built in `_ready`), so the project is easy to
  read as plain scripts. Scenes get moved into the editor when they stabilise.

## 7. Milestones

| # | Milestone | Status |
|---|---|---|
| 0 | **Combat core** | Done. Guns, five reactions, pressure, vent, focus, resistance drift, sequence elites, couch co-op. |
| 1 | **Dungeon run** | Done (first pass). Generated floor of rooms, doors, arena waves, shop with scrap, treasure, challenge, hidden room behind an elemental obstacle, boss with re-shield phase, three floors, minimap. |
| 2 | Tuning & content | Human playtesting, 10+ guns, more enemy types, more obstacles and reactions, room layouts with cover |
| 3 | Gear & unlocks | Loot tables, inventory, scrap/upgrade, gear score, tiers, achievement unlocks, save file |
| 4 | Online co-op | Host-authoritative netcode for the desktop build |
| 5 | Raids | Multi-boss co-op dungeons with mechanics |
| 6 | Art & sound pass | Kenney packs, juice, music |

### What the dungeon run does today
- A floor is a tree of 9 to 13 rooms on a grid. Dead ends become the boss, treasure, shop
  and challenge rooms. One hidden room hangs off an ordinary room behind an obstacle:
  a pool (freeze it), a thicket (burn it) or a rusted valve (Steam it: Wet, then Fire).
- Arena rooms lock their doors and run a timed wave; the timer grows with difficulty.
  Difficulty = 3 per floor plus one per room cleared, so every clear makes the next room harder.
- Enemies drop scrap. The shop sells three guns, a carry upgrade and a repair.
  Treasure rooms give a free pick of one gun from three. Challenge rooms start from a sigil,
  spawn two sequence elites plus adds, and pay out scrap and a free gun pick.
- The boss has a reaction sequence shield, re-shields with a new sequence at half health,
  and summons adds. Killing it spawns the stairs. Three floors, then the run is won.
- The trigger always fires along your aim even with no enemy in range, so obstacles can
  be shot deliberately. Interact with pedestals using E or the A button.

## 8. Debug controls in this build
- `1`..`5` give player 1 a gun (Water Pistol, Arc Rifle, Blowtorch, Frost Caster, Oil Slinger)
- `R` restarts the run
- `F1` toggles the help overlay
- `godot --path . -- --autotest` runs the self-test bot through the dungeon
