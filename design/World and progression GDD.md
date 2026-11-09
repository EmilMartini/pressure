# Pressure: world and progression design

Version 2, 2026-11-06. The design is agreed in outline and nothing in it is built yet. The current
game is described in `GDD.md`; this document describes where it goes next. Evidence comes from
`research_notes/World structure references/notes.md` (claims tagged there as verified, single
source or unverified), from `reports/Roguelite meta progression analysis.md`, and from the
designer's own telemetry.

---

## 0. Brief for agents

Read this section before starting any phase.

### How to use this document

- **Locked** means the designer decided it. Build it as written, unless the data says it fails;
  then report the data instead of quietly changing it.
- **Default** means the question is still open. Build the default, keep it easy to change, and
  list it in your report.
- Each phase in section 15 has a goal, a scope, the code to start from, acceptance checks and
  what is out of scope. Do one phase per task unless told otherwise.
- When a phase is done, update section 16 (decisions and open questions) and the relevant
  section of `GDD.md`.
- **Each phase runs in a fresh session**, decided by the designer on 2026-11-06. Start from this
  document, `GDD.md` and `README.md`, not from an old conversation. A long session re-reads its
  whole history on every message, which costs far more of the budget.
- Keep usage low: use a cheaper model for research, line reviews and simple checks; test small;
  don't re-run a measurement unless a result looks wrong.

### Standing rules from the designer

| Rule | What it means in practice |
|---|---|
| Data, not guesses | Measure before and after with bots and telemetry. Report numbers, not impressions. |
| Usage budget | The designer runs game phases on Tuesday or Wednesday, before the weekly reset, using what is left of the week. There is no fixed cap for the game, but report usage at the start and end of each phase. Keep agents few, runs short, edits targeted. Nothing runs overnight. |
| Bot load | At most 4 Godot instances at once per agent. Measure fps only while nothing else runs. |
| Difficulty | Like Hades: early runs are meant to fail, and meta progression carries the player. Fix unfair deaths (sudden bursts, unreadable threats), not overall difficulty. |
| Single player | Design and test for one player. Don't break the existing co-op code, and don't invest in it. |
| Art | No generative AI art. Only existing assets, verified CC0 assets credited with their source, or art drawn in code. |
| Writing | Claude may write player-facing text, but it must feel human (section 9). |
| Controller first | Every new screen and interaction works on a gamepad, with keyboard and mouse as well. |
| Readability | Anything that can hurt the player uses the hostile signature: black outline, red rim, drawn above player effects (`scripts/hostile.gd`, GDD "Friend or foe"). |

### Checks every phase runs

Godot 4.7.2 is installed through winget. `godot_console.exe` is a shim: launch parallel runs with
`&` and `wait`, never kill Godot by image name, and never poll with a tasklist loop.

```bash
G="$LOCALAPPDATA/Microsoft/WinGet/Links/godot_console.exe"
"$G" --headless --path . --editor --quit          # load check: no script errors
git checkout -- default_bus_layout.tres            # the editor sometimes rewrites it
```

```bash
# Bot runs: headless, fast-forwarded, each with its own --instance so the real save is never touched
"$G" --headless --fixed-fps 60 --path . res://scenes/main.tscn -- --autotest --one-floor --secs=420 --idle --loadout=frost_caster,blowtorch,mist_sprayer,gale_blaster,storm_pike,arc_rifle --instance=N
"$G" --headless --fixed-fps 60 --path . res://scenes/main.tscn -- --autotest --one-floor --secs=420 --fusion-probe --instance=N
```

```bash
# Frame rate: a real window, nothing else running; heavy fights should hold about 98-100 fps with vsync.
# Every windowed run goes through tools/bot_window.sh: the window opens without taking focus.
tools/bot_window.sh 240 autotest/perf.log 400000 --path . --audio-driver Dummy res://scenes/main.tscn -- --autotest --secs=75 --short --arsenal --gear --perf --instance=N
grep -E "PERF-SUMMARY|SCRIPT ERROR" autotest/perf.log
```

Real-window runs never take focus: `tools/bot_window.sh` sets `no_focus` for that launch only
(see README, "Real-window bot runs"). Never start a windowed Godot directly, and never add an
`override.cfg`. `--perf` prints one `[PERF-SUMMARY]` at the end (mean fps, 1% low, frames over
12.5/16/25/50 ms) and keeps chatty logs quiet: a print through the log pipe costs a 15 ms
hitch, so older per-2-s `[PERF]` numbers read low. Real-window fps is noisy when the PC is in
use (the same seed ranged 82 to 97 fps); compare CPU cost headless with `Perf` labels when
the simulation is identical.

Every bot log must have 0 `SCRIPT ERROR` lines. `README.md` lists every bot flag, including
`--build=storm`, `--start-floor`, `--old-balance`, `--mastery`, `--veteran`, `--gun-probe` and the
screenshot captures (`--hurt-shot`, `--read-shot`, `--payout-shot`, `--gear-shot`). The idle
six-gun bot must keep dying in the first region.

---

## 1. Vision

Pressure becomes a long game made of short runs: a descent into a dark, connected underworld of
elemental regions, built for a player who wants to break the game with element combinations.
A run takes 30 to 45 minutes. The whole game takes dozens of hours, because the world is wide,
not because a run is long.

Five pillars:

1. **Broken combinations stay the heart.** Every system feeds the reaction, fusion and cataclysm
   chain. Regions and bosses ask "which reaction cracks this?", not "do you have enough damage?".
2. **A world, not a list of floors.** Regions connect into a map you learn by heart. Each run takes
   a route through it, and shortcuts you open by hand change how you move through it.
3. **Death teaches.** Every death leaves something: knowledge, a lesson from an NPC, an unlocked
   tool, a shortcut that stays open. Nobody is expected to win early.
4. **One wanderer, many loadouts.** The player is always the same descender. Classes become
   loadouts chosen in the hub.
5. **Dark, gritty and alive.** A Firelink Shrine style hub full of people who remember you, and a
   world whose state changes as you push deeper.

---

## 2. Where the game is today

### Content

| Part | Today |
|---|---|
| Run | 5 floors, each a grid of rooms: start, arena, shop, treasure, challenge, hidden, boss. A winning run took about 42 minutes. |
| Combat | 12 elements, 65 reactions, 220 fusions, 176 cataclysms; 43 guns in 22 firing types; 172 items in 10 sets |
| Themes | 6 dungeon themes with ambience: crypt, ruins, frozen, forge, void, sanctum. Cosmetic only. |
| Bosses | 5: Brute King, Hive Mother, Storm Warden, Pyre Lord, Void Herald. Two phases split at half health, guard rallies from floor 2. |
| Classes | 13: the Vagrant plus one per element, each a starting gun, item and stat change |
| Hub | One room of stations: Armory, Shrine (talents), Mirror, Ledger (journal), Workshop, Gate |
| Meta | Embers buy Shrine talents; achievements unlock guns, classes and elements |
| Pacing | Elites carry elemental shields broken by one reaction. Embers flow too fast: a winning run paid 427 against 928 for the whole Shrine. Floor 2 is being retuned on 2026-11-06; check the balance section of `GDD.md` for the latest numbers. |

Almost all of the combat and content carries over. What changes is the shape around it: the
world, the hub, how a run starts, and how progress is earned.

### Code map

| System | Start here |
|---|---|
| Run flow, floor number, difficulty, bot autotest | `scripts/main.gd` (`FLOORS`, `floor_number`, `difficulty()`) |
| Floor layout generation | `scripts/floor_gen.gd`, `scripts/room_data.gd`, `scripts/room_layouts.gd` |
| Room logic, waves, spawning, boss sizing, floor damage | `scripts/room.gd`, `scripts/spawn_table.gd` |
| Enemies, bosses, phases, crowd control | `scripts/enemy.gd` |
| Themes and ambience | `scripts/themes.gd`, `scripts/ambience.gd`, art in `assets/dungeon` |
| Reactions, compounds, fusions, cataclysms | `scripts/elements.gd`, `scripts/fusions.gd`, `scripts/cloud.gd`, `scripts/fusion_fx.gd` |
| Floor materials (GPU drawn) | `scripts/materials.gd` |
| Hub and its stations | `scripts/hub.gd`, `scripts/mastery_screen.gd`, `scripts/journal.gd` |
| Classes | `scripts/classes.gd`, `scripts/class_select.gd` |
| Meta: Embers and talents | `scripts/mastery.gd` |
| Unlocks, achievements, save | `scripts/progress.gd` |
| Items, gear, drops | `scripts/items.gd`, `scripts/drops.gd`, `scripts/pedestal.gd` |
| Player, aim, input | `scripts/player.gd`, `scripts/player_input.gd` |
| Hostile readability | `scripts/hostile.gd`, `scripts/enemy_projectile.gd` |
| Figures (player and NPC look) | `scripts/figure_gen.gd`, `scripts/worn_gear.gd` |
| Tutorial | `scripts/tutorial.gd` |
| Telemetry | `scripts/telemetry.gd`; the designer's real runs are in `%APPDATA%/Godot/app_userdata/Pressure/telemetry/runs.jsonl` (read only) |

---

## 3. Run structure and length

**Locked: 5 regions per run, about 7 to 9 minutes each, 30 to 45 minutes in total.**

The evidence for this length:

| Game | Run length | What it teaches |
|---|---|---|
| Hades II | about 30 min per successful run | Long game, short runs |
| Halls of Torment | 30 min cap | A cap keeps sessions predictable |
| Brotato | about 25 to 30 min | Same |
| Pressure today | about 42 min for a win | Already in range |
| Returnal | 2 h or more near the end | Players asked for a save system |
| Risk of Rain 2 | Clear at stage 20, then endless loops | The end condition, not the content, makes runs long |

The world grows in breadth instead. Each run visits a route of 5 regions out of 11 or more, and
always ends at a fixed final boss, never in an endless loop.

A region replaces today's floor and keeps the room grid and room types:

| Piece | Count | Time |
|---|---|---|
| Arena waves | 3 to 4 | about 45 to 60 s each |
| Optional rooms | shop, treasure, challenge, secrets | the player's choice |
| Region boss | 1 | 25 to 50 s |
| Total | | about 7 to 9 minutes |

**Default:** no hard run timer; regions stay within budget through their room counts.

---

## 4. The world: the Descent

### Shape

**Locked:** the world is a graph of regions in five depths, two or three regions per depth. A run
goes down one region per depth. Dead Cells works this way, with 24 main and 12 boss biomes, of
which each run reaches one per stage.

The graph has two halves, as Hades II has two routes: a **wet and cold** side and a **hot and
dry** side. A run can cross between them at certain depths. This doubles the content without
lengthening any run.

```
Depth 1                  Ossuary Gate
                     /        |         \
Depth 2   Drowned Cistern  Rotting Gardens  Rust Ruins
              |       \        |        /       |
Depth 3   Frostvault    Pitch Mire     Abattoir
              |        /        \        |
Depth 4   Stormspire      The Forge      Chapel of Ash
                  \           |           /
Depth 5                    The Rift
```

The edges are illustrative and get fixed in phase 0. **Default:** the crossing points between
halves are ordinary edges; repaired lifts (section 8) add more of them.

### Regions

**Locked: this roster and these elements.**

| Depth | Region | Theme today | Resists | Weak to | Hazards | Boss |
|---|---|---|---|---|---|---|
| 1 | Ossuary Gate | crypt | nothing | nothing | bone piles, barrels | The Brute King (exists) |
| 2 | Drowned Cistern | new | Wet | Shock | rising water, conductive puddles everywhere | The Drowned Choir (new) |
| 2 | Rotting Gardens | new | Poison | Fire | spore clouds, gas that ignites | The Hive Mother (exists) |
| 2 | Rust Ruins | ruins | Stone | Acid | collapsing floors, rust dust | The Rusted Colossus (new) |
| 3 | Frostvault | frozen | Ice | Fire | ice sheets, cold that slows | The Frost Matron (new) |
| 3 | Pitch Mire | new | Oil | Fire, spread by Gale | tar that slows, oil that can be lit | The Tar Saint (new) |
| 3 | Abattoir | new | Blood | Holy | blood floors that heal enemies | The Butcher Abbot (new) |
| 4 | Stormspire | new | Shock | Stone (grounding) | lightning strikes on a rhythm | The Storm Warden (exists) |
| 4 | The Forge | forge | Fire | Wet, Ice | lava, steam vents | The Pyre Lord (exists) |
| 4 | Chapel of Ash | sanctum | Holy | Void | light pillars, consecrated ground | The Ashen Bishop (new) |
| 5 | The Rift | void | Void | Holy | gravity wells, collapsing space | The Void Herald (exists), then The Heart Below |

Secret regions are reached only through secret edges or puzzles: **The Hollow Wells** under the
hub, home of the Wellkeeper, and **The Gale Galleries** above the Stormspire, with Gale enemies
and a hidden boss.

Six of the eleven region themes exist as art. The others are built from the free Dungeon Crawl
tiles the game already uses, which include water, swamp, lava, gore and chapel sets.

**Default:** the final region always ends with The Heart Below (section 6), a boss built from the
player's own run.

---

## 5. Elemental resistances and weaknesses

**Locked: start with 60% damage for a resisted element and 140% for a weakness, then tune with
data.**

1. **Soft, never absolute.** A resisted element deals 60% damage, and its states last half as long.
   A weakness deals 140%, and its states last longer. Only boss phases can be immune. No build is
   useless in a region; it is only slower.
2. **Reactions break resistances.** Soaking a Forge enemy with water makes it *Exposed* to fire
   for a few seconds; electrifying a Cistern enemy turns its water resistance into a weakness.
   Noita already makes wetness change how things burn; Pressure makes it the main tool against a
   region.
3. **Regions bend drops, not builds.** A region's shops and spoils lean toward its weakness, so a
   build can adapt during the run without starting over.
4. **Readable at a glance.** Resistant enemies show a dull element badge and weak ones a cracked
   one. The Journal records each region's profile once discovered.
5. **Elite shields stay.** Elites keep "break this shield with reaction X", now matching the
   region.

**Default:** the player's own floor hazards don't change with the region.

---

## 6. Bosses: elemental creatures you can chain on

Today a boss is one sprite with two phases and one compound slot like any enemy: a bigger health
bar, not a creature. The goal is a fight people tell stories about: "I steamed the Pyre Lord's
armour, then lit the steam, and the storm cloud tore it off."

### Rules

**Default for all of these; the designer has not locked the boss design yet (section 16).**

1. **The body is a reaction surface.** A boss has two to four body parts, such as a molten core,
   armour plates, a crown or a spore sac. Each part holds its own element state and compound, so
   one boss can carry several chains at once, all the way to cataclysms.
2. **The boss feeds you its own counter.** Its attacks leave its element in the arena, and the
   fight teaches you to turn that into the next step of a chain against it.
3. **Stagger from reactions, not raw damage.** A stagger bar fills from reactions, more for higher
   tiers: a little for a reaction, more for a fusion, half the bar for a cataclysm. A staggered
   boss drops its guard for a few seconds and takes extra damage. Stagger adds to today's guard
   rallies rather than replacing them.
4. **Three phases, each a new problem.** At roughly two thirds and one third of health, each
   phase changes or adds an element, the arena or the rules, with a roar, an arena change and a
   new music layer.
5. **The arena is a weapon.** Every boss room has elemental tools: water vats to break, braziers
   to topple, pylons to charge, bells to ring.
6. **Readable.** Every attack uses the hostile signature and has a wind-up you can learn. No
   unavoidable damage.
7. **Presence.** A name card when the fight starts, its own music theme, a body three to six times
   a grunt's height, and hub NPCs who talk about it before and after. Bosses stay silent
   creatures.
8. **Death teaches.** Every boss has a lesson (section 10) that names its key chain.

Limits so chains don't trivialise bosses: each body part has its own fusion cooldown; bosses keep
the crowd-control diminishing returns at their resistance of 0.25, with stagger as the reward;
cataclysms keep the room limit of one per 1.5 seconds.

### Art

The free Dungeon Crawl set has only standard-size monster tiles, so bosses are built from several
tiles plus parts drawn in code, the way the figure generator builds the player. Each body part is
visibly separate so the player sees where each chain is building.

### Sketches

| Region | Boss | Body parts | Element and what it leaves | The chain it invites | Phases |
|---|---|---|---|---|---|
| Ossuary Gate | The Brute King (rework) | Bone armour plates, a crown | None; throws barrels | Teaches stagger: any reaction cracks a plate, and its barrels are your fuel | 1: smash. 2: plates fall; it swallows barrels and turns volatile. 3: enraged, crown exposed |
| Drowned Cistern | The Drowned Choir | A great bell with drowned singers fused to it | Wet; slowly floods the arena | Shock on the floodwater makes a Galvanic Sea against the singers, but you stand in it too: climb onto the platforms first | 1: songs that pull. 2: the arena floods. 3: the bell cracks and rings in shockwaves |
| Rotting Gardens | The Hive Mother (rework) | Spore sacs, a hive body | Poison; spore clouds | Fire on spores makes Smog, then shock on the Smog makes Firedamp: blow the sacs off her | 1: swarms. 2: she burrows; the sacs stay above ground. 3: the hive splits open |
| Rust Ruins | The Rusted Colossus | Iron plates, a magnetic core | Stone; collapsing floor | Acid dissolves the plates; shock on the bare core magnetises it so it pulls its own debris into itself | 1: stomps. 2: plates rust off; the core turns magnetic. 3: it rebuilds from the arena's scrap |
| Frostvault | The Frost Matron | Ice armour, a frozen heart, an icicle crown | Ice; ice floors, freezing breath | Fire melts the armour into water, shock on the water gives Cryoshock, and refreezing shatters the plates | 1: blizzard. 2: armour shatters into orbiting shards. 3: the heart is exposed and the room freezes over |
| Pitch Mire | The Tar Saint | A tar body, a burning halo | Oil; tar everywhere | Lit oil burns you both, so gale pushes the fire onto her. Firewhirls and conflagrations reward risky play | 1: tar rain. 2: the halo ignites and the arena becomes a fire trap. 3: she sinks and erupts from pools |
| Abattoir | The Butcher Abbot | Cleaver arms, a blood font | Blood; floors that heal him | Holy consecrates the blood floors and stops his healing; bleed on his arms turns his attacks on himself | 1: cleaves. 2: the font fills and he heals on blood. 3: he drinks the font and frenzies |
| Stormspire | The Storm Warden (rework) | Lightning rods, a storm core | Shock; strikes on a rhythm | Stone grounds the rods; his lightning on your steam makes Storm Clouds that hit him; water floors carry his strikes back | 1: pylons charge. 2: the arena rains lightning. 3: he becomes a moving storm you fuse against |
| The Forge | The Pyre Lord (rework, the showcase) | Molten core, slag armour, a fire crown | Fire; lava pools, flame waves | Water on the armour makes Steam on his body, shock on the Steam gives a Storm Cloud that tears the armour, and ice on the bare core gives an Obsidian shatter. Quench vats in the arena supply the water | 1: flame waves. 2: the armour cracks and the core is weak to ice. 3: the forge floods with lava; only quenched paths are safe |
| Chapel of Ash | The Ashen Bishop | Censer, light pillars, a mask | Holy; consecrated ground, blinding light | Void on the pillars makes an Eclipse that dims his light; breaking the mask reveals a void-weak face | 1: sermons, slow beams. 2: the pillars blind you and heal him. 3: the mask breaks; ash and void |
| The Rift | The Void Herald (rework) | Orbiting shards, a hollow centre | Void; gravity wells that bend your shots | Holy collapses the wells; a Rift compound on the shards pulls them into a cataclysm | 1: wells bend your shots. 2: it steals your most-used element. 3: the shards close in |
| The Rift, final | The Heart Below (new) | Built from your run | Resists your most-used element and uses it | Every win needs a second plan | Three phases built from your top three elements |

**Default:** no harder "awakened" boss versions until the endgame (section 12).

---

## 7. Aiming

Today guns auto-fire at the nearest enemy, and holding RT fires where the right stick or mouse
points. Multi-part bosses and mixed resistances make *where* you shoot matter: the chain you want
builds on one body part, resistant and weak enemies stand side by side, and beams, charge guns,
mines and sprays already depend on aim.

**Default: three aim modes in the options, with assisted twin-stick as the default.**

| Mode | How it plays |
|---|---|
| Assisted twin-stick (default) | Fires where the right stick or mouse points, with a soft lock that snaps to the nearest enemy or boss part inside a narrow cone. With no aim input for a moment, it falls back to auto-fire. |
| Manual | Fires only where you aim, with no assist. Hold to fire, or toggle constant fire. As in Enter the Gungeon. |
| Auto | Today's behaviour: nearest enemy, with RT to override. For accessibility and relaxed play, as in Brotato. |

In every mode, auto-fire never targets puzzles, props or obstacles, and boss parts are valid
soft-lock targets. The bot uses assisted mode with its own aim. Before fixing the default, compare
clear and boss times per mode with bots, and add telemetry for how often players aim manually.

---

## 8. Shortcuts, Dark Souls style

"You don't find shortcuts in Dark Souls, you find how one area is connected to the other." A
shortcut is a place in the world you open by hand, usually from the far side, and it stays open.
Nothing unlocks by counting clears.

**Locked:**

- **No waystones.** Every run starts at the top. Shortcuts work inside regions and between them.
- **Shortcuts open routes; they never skip bosses.** Dead Cells' runes open edges of the biome
  graph and never shorten the finale.
- **No free warping.** Dark Souls 2 critics say shortcuts lost their meaning once warping was free.

| Kind | Example | Effect in later runs |
|---|---|---|
| Gate opened from the far side | A chain-gate in the Ossuary, opened from inside its boss antechamber | You can walk from the region's entrance straight to the boss door. You skip the arenas, and their loot and XP with them. |
| Repaired lift | A broken lift in the Rust Ruins, fixed with a part from the Frostvault | A new edge in the graph: the Rust Ruins can lead down to the Frostvault |
| Bridge or sluice | Opening the Drowned Cistern's sluice | World state change: the Cistern is drained in later runs, with new rooms and fewer hazards but tougher enemies in the open |
| Secret edge | A breakable wall in the Chapel of Ash | A path to a secret region |

Each region has one or two shortcuts, found in play. The hub's world map shows every one you have
opened. **Default:** opened shortcuts never close again.

---

## 9. The hub: the Hollow

### Place

A ruined bell tower and crypt above the Descent, lit by a single fire. It starts nearly empty and
fills as you bring people home, like Firelink Shrine. It is a few connected rooms you walk
through: the fire, a forge, a library, a well, a chapel, and the stair down.

### The cast

Every station becomes a person with one job, one personality and lines that react to your runs.

| NPC | Job (replaces) | Personality | Where you meet them | What they ask for | What moves in with them |
|---|---|---|---|---|---|
| The Keeper | Shrine: Embers buy talents | Old, patient, tends the fire; speaks rarely and kindly | In the Hollow from the start | Nothing | The Shrine |
| The Gatewarden | Gate: start a run, Vows, the run history until the Archivist arrives | Grim veteran who lost a squad below; counts your deaths | In the Hollow from the start | Nothing | The Gate |
| The Archivist | Ledger and Journal; gives death lessons | Obsessive scholar of monsters, delighted by gruesome deaths | Chained in a side room of the Ossuary | A Torn Bestiary Page from your first elite kill | The Journal: reactions, fusions, enemies, region profiles, lessons |
| The Collector | Collection log | Haggles with corpses | The Rotting Gardens | Any Rare item | Every gun and item you've ever found, with completion rewards |
| The Smith | Armory: gun unlocks and Kits | Gruff, burned, proud of every gun | Trapped under rubble in the Forge | A Forge Hammer from the Rust Ruins | The Armory |
| The Tinker | Workshop: gun mods | Nervous, talks to their tools | Hiding in a lift shaft in the Rust Ruins | A gun at tier 3 or higher | The Workshop |
| The Cartographer | World map and shortcut hints | Restless, half-mad from the Rift | Lost at the top of the Stormspire | Map Fragments from three different regions | The world map |
| The Alchemist | Reaction lore, fusion and cataclysm hints | Cheerful heretic, scarred by her experiments | Experimenting on herself in the Abattoir | A cataclysm discovered in that same run | Fusion and cataclysm hints |
| The Wellkeeper | The Well and Relics | Silent, trades in favours | The Hollow Wells, a secret region | Nothing: she follows whoever reaches her | The Well |
| The Rival | A fellow descender | Arrogant, competes for kills; can die or be saved | In regions from depth 2 | Story-driven (section 12) | Lines and a personal story |

Art: the free Dungeon Crawl tiles include many humanoid figures, and the figure generator can
dress them in worn gear like the player.

### Recruiting

**Locked: the Keeper and the Gatewarden are there from the start, and the Archivist is the first
NPC to recruit.** The rest follow in later phases.

- **Features arrive with their NPC.** A fresh save has the Shrine, the Gate and a bare run history.
  The Journal, the collection log, the Armory and the rest open when their NPC moves in, so each
  appears when there's something in it.
- **Giving costs something.** The item leaves your run, so recruiting means choosing between a
  stronger run now and a richer hub later, as in Elden Ring and Dark Souls quests.
- **Some asks are specific, some open.** A specific item makes a small quest; an open ask teaches
  the system early.
- **They remember.** First meetings have their own lines, and a second meeting on a later run
  remembers the first.
- **Missed, never lost.** If you skip someone or die, they're still there next run.
- **Default:** NPCs don't die permanently, except the Rival as part of their story.

### Bonds

Once an NPC lives in the Hollow, you can keep giving them items. Each has tastes: the Smith likes
heavy guns and the Alchemist anything Acid. Gifts raise a bond level, and each level unlocks new
lines that tell their story in pieces, a Keepsake for the Relic slot (as Hades' keepsakes come
from nectar), or a better service such as an extra mod slot from the Tinker. Gifts become the
main sink for unwanted loot, replacing plain salvage to scrap. **Default:** five bond levels per
NPC, one gift per NPC per visit to the hub.

### Dialogue volume

Hades shipped over 300,000 words and 22,000 voiced lines so its cast would not repeat across many
runs. Pressure uses fewer NPCs with lines keyed to state: what killed you, where, how deep, how
many deaths, which boss is new, which shortcut you just opened, which loadout you wear. The first
target is **1,500 to 3,000 lines** across the cast, written in batches per phase. **Default:**
text only, with no voice.

### Writing rules: human, not generated

The designer's rule: Claude may write the lines, but they must never read like generated text.

**Before any lines, each NPC gets a voice sheet:**

- What they want, what they fear and what they hide.
- How they talk: sentence length, vocabulary, and one or two verbal habits. The Gatewarden counts
  things; the Smith names guns like animals.
- What they never say.
- Ten sample lines the designer approves. Every later batch is checked against them.

**Rules for every line:**

1. **Specific beats general.** Name the thing: "the Frost Matron", "your third death on the
   bridge", "that oil slinger". Never "the darkness", "the challenges ahead" or "your journey".
2. **Short.** Most lines are one or two sentences. Dark Souls NPCs say little and imply more.
3. **Subtext, not exposition.** Characters talk around the world and their feelings rather than
   explaining them.
4. **No generated-text tells.** Banned words: delve, tapestry, testament, journey, embark, realm,
   beacon, unwavering, profound, intricate, vibrant, whisper of. Banned constructions: "it's not
   just X, it's Y"; "in the depths of"; three adjectives in a row; rhetorical questions to the
   player; motivational endings such as "you've got this"; lines that end on a moral.
5. **People are uneven.** They interrupt themselves, repeat a word, get something wrong, lose their
   train of thought, joke badly, and don't always answer what was asked.
6. **Grit without melodrama.** Dark and dry, not epic. Humour comes from character, not jokes.
7. **No praising the player.** NPCs have their own concerns. Respect is shown, rarely said.
8. **React to the actual run.** Prefer lines that could only exist after this death, region or item.

Example: the Gatewarden after your third death to the Frost Matron.

| Generated-sounding | Human |
|---|---|
| "Do not despair, brave wanderer. The icy depths have tested you, but your journey is far from over. Rise again!" | "Third time. She's patient, that one. So was I, once." |
| "The Frost Matron's power is immense, yet even the coldest heart can be melted by fire." | "You know what melts? Everything. Eventually. Bring something warmer." |

**Review for every batch:**

1. One agent writes against the voice sheets and the approved samples.
2. A second agent, given only these rules and the voice sheets, flags every line that breaks a
   rule or could be moved to another NPC without anyone noticing. Flagged lines are rewritten or
   cut.
3. The designer reads at least 20 lines of each batch before it ships. Rejected lines go into the
   voice sheet as examples of what not to write.

The same rules cover all player-facing prose: item flavour, lore, region descriptions.

---

## 10. Death teaches: lessons and unlocks

### The loop

1. A boss or region kills you.
2. Back in the Hollow, the Archivist, or the NPC tied to that region, talks about it in character.
   They name the killer and hint at its weakness: "The Frost Matron? Ice bends to fire, child, but
   oil makes fire stay."
3. The first death to each boss unlocks a **lesson**: a counter tool joins the drop pool, such as
   the Oil Slinger after dying to the Frost Matron.
4. The Journal records the lesson, the boss's resistances and your best attempt.

The research found no game that does exactly this. The nearest are Halls of Torment's conditional
unlocks ("as the Archer, stand still for 3 minutes"), Dead Cells' blueprints, and Outer Wilds,
where knowledge itself is the progression. That makes it a strong hook.

### Rules

- One lesson per boss and per region hazard: about 20 to 30 in the first world.
- Lessons only unlock counters to what killed you: a gun, an item, a mod, a Mark or a shortcut
  hint. Never raw power.
- Today's achievement unlocks move to lessons or to loadout challenges (section 11), so every
  unlock has a story.
- **Default:** lessons trigger on bosses and region hazards, not on ordinary elites. The hint is
  vague after the first death and plain after the third.

---

## 11. Loadouts instead of classes

**Locked: one descender, starting as the Vagrant, with four loadout slots chosen at the Gate.**

| Slot | What it is | Comes from today's | Example |
|---|---|---|---|
| Kit | Your starting gun | Class starting gun | Flare Pistol |
| Mark | A rule-changing passive with its own trait pool | Class element and stat changes | Mark of the Pyre: burns spread when a burning enemy dies, and fire reactions grow faster; −10 max health |
| Relic | One item carried into the run | New, through the Well and Keepsakes | A ring saved from an earlier run |
| Vow | Optional difficulty modifiers for better rewards | New (meta report recommendation R9) | "Bosses enrage at half health" for +25% Embers |

The 12 elemental classes become 12 Marks. New Marks can change how a run plays, as Halls of
Torment's characters do, rather than only adding stats:

- **Mark of the Tide:** you can't fire while moving, but each volley doubles.
- **Mark of the Hollow:** no gun slots past three, but every reaction counts as one tier higher.

**The Well**, adapted from Halls of Torment: once per region you can drop one item into a well. If
you then die, the item is saved, and the Wellkeeper sells it back as a Relic.

**Unlocks:** each Mark and Kit unlocks through a challenge or a lesson tied to it, as Risk of
Rain 2 ties a challenge to each skill. For example, "kill the Frost Matron using only fire
reactions" unlocks the Mark of the Pyre.

**Defaults:** your appearance comes from gear, and the Mark adds a small accent such as a glow or
a cloak colour. One Relic slot, growing with the Wellkeeper's bond. Vows replace a classic
difficulty setting.

---

## 12. A living world

**Locked: these four ideas come first.**

1. **World state that changes.** Draining the Cistern, breaking the Forge's dam, putting out the
   Chapel's fire. Each change alters that region in later runs and can open or close routes. The
   hub's world map shows the current state.
2. **People who move.** Recruited NPCs also set up camps inside the Descent: a merchant at depth 3,
   the Tinker's workbench in the Rust Ruins. The world fills with your own history.
3. **The Rival.** A fellow descender who turns up in regions, competes for kills and loot, and
   remembers. Sometimes you save them, sometimes they die, sometimes they turn on you. A story
   told across many runs, as Thanatos's is in Hades.
4. **Elemental weather.** Fronts that sweep a region for a whole run: a blizzard through the
   Frostvault, a thunderstorm in the Stormspire, ash fall in the Chapel. They shift resistances and
   hazards using systems that already exist.

Parked for later:

5. **Border fights.** Where two regions meet, their enemies fight each other, and a wet enemy hitting
   a fire enemy makes steam.
6. **World-scale puzzles.** Today's hidden walls grow into elemental locks that need a specific
   fusion to open a secret region.
7. **Lore in the world.** Murals, corpses with notes and item flavour that piece together why the
   Descent exists, read through the Archivist.
8. **Endgame.** Vows as heat; after a first win the Rift opens deeper ("Pressure levels", like Dead
   Cells' boss cells); a daily descent with a fixed seed.

**Default:** the story is one question the whole game answers: what lies at the bottom of the
Descent, and why do people keep going down?

---

## 13. Meta progression and pacing

**Target: a first win after roughly 15 to 25 hours.** Hades' main story takes about 15 to 22
hours, typically after 20 to 30 runs. At 30 to 45 minutes per run, that is about 25 to 40 runs.

**Measured today:** one winning run paid 427 Embers against 928 for the whole Shrine, so the meta
would be finished in 2 or 3 runs. Most came from elites (94 at 2 each) and first discoveries
(34 at 3 each).

| Currency | Earned by | Spent on |
|---|---|---|
| Embers | Every run, scaled by depth reached | Shrine talents, from the Keeper |
| Lessons | Dying to new things (section 10) | Unlock counters automatically |
| Keys and parts | Found in regions | Shortcuts and lifts (section 8) |
| Favours | Recruiting and gifting NPCs | The Well, Relics and NPC services |

Four currencies is the upper limit. **Default:** Embers are kept on death, never dropped.

**Locked: difficulty by meta stage.**

| Meta stage | Expected result |
|---|---|
| Fresh save | Usually dies at depth 2 |
| About half the Shrine | Usually reaches depths 3 to 4 |
| Full Shrine plus a strong build | Can win, but not reliably |

Tune Embers per run so the Shrine fills in about 25 to 40 runs, measured with bots at each stage
(`--mastery=N` and `--mastery=full`).

**Measured proposal from 2026-11-06, built in phase 3 (measurements in its handoff).** In a bot win, elites paid 336 to 362 of the
Embers (2 each for 168 to 181 elites), so two wins bought the whole 928-Ember Shrine. Proposed
income per run:

| Source | Embers |
|---|---|
| Each room | 1 |
| Each elite, at most 10 per run | 1 |
| Each first discovery | 2 |
| Fusions and cataclysms | at most 6 per run |
| Each boss | 3 |
| Each bounty | 5 |
| Each floor past the first | 3 |
| A win | 20 |

Once first discoveries run out, this pays about 2 to 7 for a death on the first floor, 17 to 27
for a death on the second, about 56 for reaching the fourth, and about 107 for a win. The Shrine
then fills in about 35 to 45 runs. Reaching a first win after 20 to 40 hours would also need
Shrine costs roughly doubled. Phase 3 builds and measures this.

Caveat: bots play far better than humans past the second floor, so they can't place the meta
curve on their own. Human runs are the reference for the fresh-save target.

---

## 14. Scale

A first full version, roughly:

| Content | Exists | New |
|---|---|---|
| Regions | 6 themes, as art | 5 to 6 themes; 11 regions plus 2 secret regions |
| Bosses | 5 | 7 new, 5 reworked |
| Enemy kinds | 11 | 2 or 3 per new region, plus elemental variants of existing ones |
| NPCs | 0 | 10 |
| Dialogue lines | 0 | 1,500 to 3,000 |
| Marks | 13 classes to convert | 4 to 6 new rule-changing Marks |
| Shortcuts | 0 | 1 or 2 per region, about 15 to 20 |

At the designer's budget of about 20% of the weekly limit per day, one phase takes one to three
days of agent work.

---

## 15. Build phases

Each phase ships a playable game, passes the checks in section 0, and updates `GDD.md`.
**Default order:** 0, 0b, 1, 1b, 2, 3, 4, then 5 and 6 in batches. The designer can move 0b after
1 (section 16).

### Phase 0: Groundwork (DONE 2026-11-06)

- **Goal:** runs become routes through a region graph, and regions have elemental profiles.
- **Scope:**
  - A region data model: id, depth, theme, resists, weak to, hazards, boss, edges.
  - A run picks one region per depth along the graph's edges, replacing `floor_number` as the
    driver of layout and theme.
  - Difficulty follows depth.
  - The 6 existing themes become 6 regions: Ossuary Gate, Rust Ruins, Frostvault, The Forge,
    Chapel of Ash and The Rift, with their profiles from section 4.
  - Soft resistances (60% and 140%) on enemy damage and state duration, the Exposed state from
    reactions, and resistance badges on enemies.
  - A route choice at each region exit, shown as two or three doors.
- **Start from:** `main.gd`, `floor_gen.gd`, `room.gd`, `room_data.gd`, `themes.gd`, `enemy.gd`,
  `elements.gd`.
- **Acceptance:**
  - Bots complete a 5-region route.
  - A build with a region's weakness clears it measurably faster than one with its resistance.
  - The Exposed state measurably helps the resisted build.
  - The idle six-gun bot still dies in the first region.
  - The fusion-probe bot still clears the first region.
  - Heavy fights hold about 98 to 100 fps.
- **Out of scope:** new themes, new bosses, NPCs.

**Part 1 done (2026-11-06): regions and routes.**
- `scripts/regions.gd` holds the whole graph of section 4 (11 regions; the 5 without art have
  `built: false` and are never picked). Each region has id, name, depth, theme, resists, weak
  to, hazards, boss (the design's own), `boss_kind` (the boss fought today), signature
  `layouts` and edges. `Regions.validate()` checks the graph; every bot prints it in `[ROUTE]`.
- Edges fixed (default, easy to change): Ossuary Gate > Cistern, Gardens, Rust Ruins;
  Cistern > Frostvault, Pitch Mire; Gardens > Pitch Mire, Abattoir; Rust Ruins > Frostvault,
  Abattoir; Frostvault > Stormspire, Forge, Chapel of Ash; Pitch Mire > Stormspire, Forge;
  Abattoir > Forge, Chapel of Ash; every depth 4 region > The Rift. Rust Ruins > Frostvault
  and Frostvault > Forge are the crossings between the hot and cold halves.
- `Main.region_id` and `Main.route`: the region sets theme, boss and 35% of arena layouts
  (`RoomLayouts.FAVOUR_SHARE`); `Main.floor_number` is now the depth and still drives
  difficulty, floor size, prices and enemy kinds. The next region is a random built
  neighbour (`Main._next_region`); bots can fix one with `--route=a,b,c`.
- Stand-in bosses (default): Rust Ruins fights the Hive Mother, Frostvault the Storm Warden,
  Chapel of Ash the Pyre Lord, so depth 2 to 4 keep the bosses their floors had.
- HUD banner, `[FLOOR]`, `[DEATH]`, `[END]` and every telemetry event with a `floor` name the
  region; `run_end` stores the `route`.
- Measured: idle six-gun bot dies in Ossuary Gate (t=73, 2 rooms cleared); fusion probe clears
  it (Brute King in 14.5 s); `--build=storm --start-floor=2 --mastery=full` wins the Forge
  route (The Rift took it about 840 game seconds); a naked `--mastery=full` bot walked the
  whole Chapel route from Ossuary Gate into The Rift, and a storm bot from depth 4 cleared
  Chapel of Ash (stand-in Pyre Lord in 19.9 s); both hit their time cap (2700 s, 1500 s)
  inside The Rift, so no Chapel-route win is logged yet. Heavy fights averaged 99 fps
  (30 samples, min 92); 0 script errors.

**Part 2 done (2026-11-06): resistances, Exposed, badges, route doors.**
- `Regions.activate(id)` (from `Main.start_floor`) holds the active region's profile as
  `Element.Kind` lists. `Enemy.resist_mult(kind)` is 0.6 for a resisted element, 1.4 for a
  weakness and 1.0 otherwise. It scales gun hits (`Strike.deal`), the burn, poison and
  bleed ticks, and the duration of states of that element.
  - Default: state duration uses the same 60% / 140% as damage. Section 5 says "half as
    long" for a resisted state; that is a one-constant change if wanted.
  - Default: reaction, fusion and prop damage stays neutral, so reactions are the way
    through. Bosses take the region's profile like everyone else.
- **Exposed (default):** any reaction or fusion on an enemy makes it Exposed for 4 s
  (`Regions.EXPOSED_SECS`). While Exposed, the region's resistances count as weaknesses
  (140%). This is the "electrifying a Cistern enemy turns its water resistance into a
  weakness" rule, applied to every reaction. `--no-exposed` turns it off for A/B runs.
- **Badges:** small squares under every enemy in the hostile frame (black, red rim).
  - A resistance is a dull element colour barred in black.
  - A weakness is a bright colour with a black crack.
  - While Exposed, the resistance badges turn bright and cracked and blink white.

  `--hurt-shot --read-shot` with `--start-floor`/`--route` saves `read_flyers_*` with the
  badges and `read_doors_*` with the doors.
- **Route doors:** the boss room offers one stairs pedestal per built region one edge down.
  Each is labelled "Down to <region>" with its resists and weaknesses as element badges, and
  is taken with the usual interact button, so it works on a pad.
  - `Main.next_floor(to)` enters the chosen region.
  - Bots follow `--route`, else pick a door at random and print `[ROUTE-DOOR]`.
  - With six built regions only Frostvault has two doors (The Forge, Chapel of Ash). Every
    other exit has one door until phase 5 builds the rest; nothing in the code limits this.
- Bot tooling:
  - With `--build`, `--loadout=id@tier,...` replaces the build's guns.
  - `[DPS]` lines name the region and the Exposed count.
  - `[TICK]`/`[END]` print a `resist:` line with damage dealt at each rate.

**Measured (part 2):**
- Weakness against resistance, from the `--dps-probe` (8 dummies, 40 s, 3 seeds each, which
  gave identical numbers). The same two guns were swapped between the two regions, so gun
  differences cancel out:

  | Region | Fire guns (blowtorch + ember carbine) | Ice guns (frost caster + rime chakram) |
  |---|---|---|
  | Frostvault (resists Ice, weak to Fire) | 43 dps | 16 dps |
  | The Forge (resists Fire, weak to Wet and Ice) | 18 dps | 37 dps |

  Each build does about 2.3 times as much damage where it is the weakness (1.4 / 0.6).
- Real runs in The Forge, using the `storm` profile's gear and levels with equal-weight tier 2
  guns (2 seeds each). That gear favours fire, which biases the test toward the fire build:

  | Build | Damage per second | Gun damage that hit the region's weakness |
  |---|---|---|
  | Ice: frost caster, rime chakram, glacier lance | 680 and 688 | 68k |
  | Fire: flare pistol, blowtorch, ember carbine, cinder flak | 327 and 534 | 0 |

  For the fire build, 21k of its gun damage was resisted and 9k was Exposed. Both builds
  died at depth 4 (t = 34 to 100 s). Arenas spawn on timed waves, so kills per second were
  about the same (5.1 to 5.5): extra damage shows up as damage and survival, not as fewer
  seconds per arena.
- Exposed, using a resisted build that reacts (ice guns plus a water pistol, so Deep Freeze
  fires) in Frostvault with the `--dps-probe`, 3 seeds each:

  | Exposed | Damage per second |
  |---|---|
  | On | 145 |
  | Off (`--no-exposed`) | 118 to 119 |

  Exposed adds 22%. Ice guns alone, with no reaction, do 16.
- The idle six-gun bot dies in Ossuary Gate (t=78, 2 rooms cleared). The fusion probe clears
  it (Brute King in 20.6 s) and takes the single door to Rust Ruins.
- 5-region routes:
  - **Chapel of Ash win.** `--build=storm --start-floor=2 --mastery=full
    --route=...,chapel_of_ash,the_rift --secs=5000` won the route: Void Herald in 13.9 s, run
    over at t=2433 with "clear +10", 0 script errors. Stand-in Pyre Lord in Chapel of Ash
    died in 14.5 s.
  - **Random doors, storm build.** The bot took Rust Ruins > Frostvault > The Forge (chosen
    at random from Forge and Chapel) > The Rift, then hit the 5000 s cap in a Rift challenge
    room, with 0 errors.
  - **Random doors, naked bot from depth 1.** `--mastery=full` walked Ossuary Gate > Rust Ruins
    > Frostvault > The Forge > The Rift (Rift at t=1938, level 26). Then it hit a stack
    overflow: Inferno, Dark Flame and Black Hole apply or spread elements onto neighbours,
    whose reactions nest inside their own. In The Rift's packed late crowd this chained until
    the stack overflowed, and the error repeated every frame (a 48 GB log).
    - Fixed: `Elements.MAX_REACTION_DEPTH` (24). Past that depth an element lands as a plain
      state instead of reacting.
    - Rerun after the fix, 0 script errors in all three runs:
      - A naked `--mastery=full` bot took random doors through Ossuary Gate > Rust Ruins >
        Frostvault > Chapel of Ash > The Rift and won at t=2921 (Void Herald 58.2 s).
      - Two storm bots starting in The Rift won (Void Herald 16.9 s and 25.3 s).
      - The deepest nesting reached was 8 to 14 levels (`[FUSION-CHECK] max_depth`).
    - Open: one naked rerun stalled in a floor-1 shop for 2900 s. The bot pushed against an
      offer it couldn't reach, and the 12 s stuck-teleport only covers walking to doors. This
      was already in the code; part 2 didn't cause it.
- Heavy fights: `--arsenal --gear --perf`, 54 samples, average 98.3 fps, min 88 (one sample).
  Part 1 measured 99 and 92. No script errors.
- Editor load check clean.

### Phase 0b: Boss framework (DONE 2026-11-07)

- **Goal:** bosses become multi-part elemental creatures, with aim that can target their parts.
- **Scope:**
  - Body parts, each holding its own element state and compound, with their own fusion
    cooldowns.
  - A stagger bar filled by reactions by tier.
  - Three phases.
  - Arena tools.
  - Name cards and a music layer per phase.
  - The three aim modes (section 7), with soft lock on boss parts.
  - Rework all 5 existing bosses, the Pyre Lord first.
- **Start from:** `enemy.gd` (boss code, `_phase`, rallies), `room.gd` (boss sizing and rallies),
  `elements.gd` and `fusions.gd` (compound slots), `player.gd` and `player_input.gd` (aim),
  `music.gd`.
- **Acceptance:**
  - A fusion bot staggers and kills each reworked boss in 25 to 50 seconds.
  - The Pyre Lord's chain works on his body: steam, then a storm cloud, then an obsidian shatter.
  - Each boss reaches all three phases.
  - No fps loss in boss fights.
  - Screenshots show readable body parts and the hostile signature on every attack.

**Part 1 done (2026-11-06): the framework and the Pyre Lord.** `scripts/boss_body.gd`; the
write-up is in `GDD.md` under "Boss framework".
- **Framework, every boss:**
  - A stagger bar filled by reactions by tier, which drops the guard for 4 s.
  - Phases at health fractions per kind.
  - A name card at the start of the fight, then the name in the boss bar with phase pips.
- **Body parts:** each part holds its own states, compound and fusion cooldown. A hit lands
  on the part nearest to it. Parts are drawn on the Crisp layer, and the HUD shows a chip
  per part.
- **The Pyre Lord** has three parts: slag armour, a molten core and a fire crown.
  - Water steams the burning armour. Shock on the Steam makes a Storm Cloud that tears the
    armour off. Ice on the bare core, which holds Magma, gives an Obsidian shatter.
  - The armour ignores shock and ice until it is steamed, and the core takes only ice, so
    the chain reads clearly.
  - Three phases: flame waves; then the armour cracks open and the waves are faster; then
    the armour re-forms, three waves fire at once and lava wells up.
  - Every attack winds up and uses the hostile signature.
- The other four bosses use the framework without parts (stagger, name card, their two
  phases).

**Measured (part 1):**
- **Pyre Lord on real Forge floors.** The fusion bot is the storm build at depth 4 with
  water, shock, ice and fire guns at tier 2. It fought every arena, then the boss:

  | Run | Fight | Health | Phases | Staggers |
  |---|---|---|---|---|
  | 1 | 26.5 s | 25.0k | 3 of 3 | 2 |
  | 2 | 42.4 s | 27.1k | 3 of 3 | 4 |

  0 script errors. Before the health share (`BossBody.HP_SHARE`, 0.4), he had 72k to 73k
  health and the fights took 80.5 s and 93.4 s.
  Only two real-floor samples so far. `--boss-only` probes take longer (43 to 96 s) because
  that bot arrives at level 15 instead of 24, with the same health from `--boss-dps`. Use
  them for the chain and the frame rate, not for fight length.
- **The chain on his body**, logged by `[BOSS-CHAIN]` (`--boss-only --boss-dps=2200`, same
  bot): Steam on the armour at 0.5 s and 3.4 s, then a Storm Cloud on the armour at 3.4 s,
  which tore it off. It re-formed at 15.5 s, phase 2 cracked it at 31.9 s, and Obsidian hit
  the core at 36.5 s. One earlier fight logged 8 armour tears by Storm Cloud and 4
  Obsidian shatters.
- **The other bosses still die normally** (storm build, `--boss-only --boss-dps=1500`, 0
  errors):

  | Boss | Fight |
  |---|---|
  | Hive Mother | 49.2 s |
  | Storm Warden | 27.6 s |
  | Void Herald | 15.1 s |
  | Brute King (in the fusion-probe run) | 25.8 s, 3 staggers |

- **First region:**
  - The idle six-gun bot dies in Ossuary Gate (t=46).
  - The fusion probe clears it and reaches Rust Ruins.
- **Frame rate:**
  - The standard heavy-fight probe averaged 96.7 fps (median 98).
  - The Pyre Lord fight was compared with the old code: the committed version plus only the
    `--boss-only` jump, storm build guns, seconds 3 to 30 of the fight:

    | Code | Average fps |
    |---|---|
    | New | 83.8 and 87.7 |
    | Old | 82.1 and 84.3 |

    There is no loss. The first build drew a marching hostile ring on every patch of his fire
    trail and fell to 65.5; rings are now drawn only within 300 px of a player.
  - The absolute 84 to 88 is older than this phase. In a Forge boss room, render objects
    climb from about 2k to 18k within 30 s on the old code too, while a 72 s Hive Mother
    fight holds 98 fps. Open: find what accumulates there.
- **Screenshots:** `--boss-shot` saves `autotest/boss_pyre_lord_*.png`. The slag plates,
  crown and bare core read through a full whiteout of player effects. The flame-wave arcs,
  their wind-ups and the burning and lava ground are drawn black and red.
- The editor load check is clean.

**Part 2 starts here:**
- The three aim modes (section 7), with soft lock on boss parts. Today the bot hits
  whichever part its shots reach.
- Arena tools: quench vats in the Forge.
- A music layer per phase.
- Rework the other four bosses with parts, three phases each, and 25 to 50 s fusion-bot kills.
- The Forge boss-room frame rate above.

**Part 2 done (2026-11-06): the aim modes and the Brute King.** Write-up in `GDD.md`
("Firing model" and "Boss framework").
- **Aim modes** (section 7): assisted twin-stick (default), manual (hold or toggle) and
  auto, in Options. Soft lock on enemies and visible boss parts in a 12-degree cone.
  Telemetry records the mode and the seconds aimed and auto-fired. Bot flags `--aim=MODE`
  and `--bot-aim`.
- **The Brute King** on the framework: bone plates that any reaction cracks, a hide, a bone
  crown bared in phase 3. He throws barrels (landing circles); a barrel blast next to him
  is a Barrel Blast on his body; in phase 2 he swallows barrels and fire or shock sets off
  a Gut Blast. Three phases at 0.66 and 0.33.

**Measured (part 2):**
- **Aim modes, Pyre Lord** (`--boss-only --boss-dps=2200`, storm build, 0 errors). Every
  mode killed him through all three phases with Obsidian on the core:

  | Mode | Fight |
  |---|---|
  | Auto (`--aim=auto`) | 48.6 s |
  | Assisted, bot aiming at the part that takes most | 83.6 s |
  | Manual, bot aiming the same way (`--aim=manual`) | 97.6 s |

  That bot aimed at the crown while the armour stood, which is the wrong part. It now
  aims at intact armour first. The aimed runs have not been re-measured since.
  `--boss-only` lengths vary from 43 to 96 s on their own (part 1), so use these to show
  the modes work, not to rank them.
- **Default mode, existing bots.** With no aim input, assisted is the same code path as
  auto. The idle six-gun bot died in Ossuary Gate in 5 of 6 runs (t=55, 50, 44, 49, 171),
  the last two with the final code. In the
  fourth it got through and killed the old-health Brute King, which led to the health
  change below. The fusion probe cleared Ossuary Gate in every run that reached the boss.
- **Brute King, real Ossuary floors** (`--one-floor --fusion-probe=K`, 0 errors, all
  3 of 3 phases):

  | Floor-1 health | Fights (s), builds 1/2/3/0 |
  |---|---|
  | x1 (old formula) | 5.3 to 27.8 (phases at 1 to 4 s) |
  | x2.0 | 23.2, 24.5, 35.4, 38.4 |
  | x2.5 | 28.4, 27.7, 83.5, 55.9 |
  | x2.2 | 25.0, 19.4; then 69.1 and 5.0 (build 3), 37.1 (build 0) |
  | x2.2 with `BOSS_DECAY` (shipped) | 35.2, 33.4, 40.1, 61.9 |

  The 5.0 s kill (8.2k health) came from void reactions that take a share of max health
  (Decay 15%, Null Acid 12%, Exsanguinate 10%, the Hollow fusions 5%). Each body part
  reacts on its own, so the shares stacked. Bosses now take a tenth of that share
  (`Elements.BOSS_DECAY`, 0.1). With it the spread closed to 33 to 62 s, median 37.7. The
  Pyre Lord with it, on a real Forge floor: 37.6 s, 3 of 3 phases, Storm Cloud tears and
  Obsidian on the core. A second run died in a Forge arena at t=150.
  The chain shows in the logs: `TORN` (plates) at 1 to 3 s, `SWALLOWED`, `Gut Blast`
  (tier 4) and `Barrel Blast` on hide or crown in most fights. The plates still tear early,
  because the bot opens with a burst of reactions; a later pass could slow the first tear.
- **Frame rate,** Brute King fight, real window, vsync, `--fusion-probe=2 --boss-only`:
  boss-room ticks of 100/100/97/99 and 91/100/99/100 on the new code, against
  99/100/100/100 and 100 on `044bce2`. No loss.
- **Screenshots** (`--boss-shot`): the name card, the bone plates (black outline, red
  rim) and the helm read through a shock whiteout. The barrel landing circle and the
  barrel in flight are drawn black and red.
- Editor load check clean.

**Part 3 starts here:**
- Rework the Hive Mother, the Storm Warden and the Void Herald with parts and three phases
  each, measured on real floors. Their sketches are in section 6.
- Arena tools: quench vats in the Forge first.
- A music layer per phase (`music.gd`).
- Optional: bring the Brute King's fight spread nearer 25 to 50 s, slow his first plate
  tear, re-measure the aimed bot, and look at the Forge boss-room frame rate.
- Bot follow-up: in one of four runs, the `--fusion-probe=1` bot stood in an Ossuary Shop
  room from about t=200 to the end of the run.

**Part 3 done (2026-11-07): the Hive Mother, the Storm Warden, the Void Herald, quench vats
and a music layer per phase.** Write-up in `GDD.md` ("Boss framework"). All five bosses
now have body parts, a chain on their bodies and three phases.
- **The Hive Mother** (finished from last night's WIP commit `cc96eff`): spore sacs that
  Firedamp (fire, then shock on the Smog) tears off; she burrows in phase 2 with the sacs
  above ground and a marked eruption circle; the brood chamber opens in phase 3. Fixed: no
  contact damage while underground.
- **The Storm Warden:** charged lightning rods that Grounded (stone) tears; a storm core
  where Steam plus his own recharge strike, or your shock, is a Storm Cloud inside him
  (OVERLOAD). Rhythm strikes in phase 1, volleys plus self-recharge in phase 2, a moving
  storm in phase 3.
- **The Void Herald:** a ring of void shards that a Rift fusion collapses; gravity wells
  that bend your shots (holy collapses them) in phase 1; it steals your most-used element
  in phase 2; shards close in along marked paths in phase 3.
- **Framework additions:** `wear_by`, `payoff`, `burrows`; HUD chips say sealed and
  underground; `[BOSS-BODY]` prints max health; `[BOSS-MOVE]`, `[ARENA]`, `[MUSIC]` lines.
- **Quench vats** in the Pyre Lord's room. **Music per phase** from the existing boss
  pool: filtered, then the next track, then the next with a 6% pitch lift.

**Measured (part 3).** All runs 0 script errors. Real floors, storm build at each boss's
depth (recipes in `README.md`):

| Boss | Health share | Fights (s) | Phases | The chain in the logs |
|---|---|---|---|---|
| Hive Mother (depth 2, Rust Ruins) | 1.0 | 20.8, 30.3, 33.1, 30.3 | 3/3 all | Firedamp tore the sacs in 1 of 4 |
| | 1.2 | 24.1, 13.9, 29.6, 20.1 | 3/3 all | Firedamp tore the sacs in 4 of 4 |
| | **1.5** (shipped) | 25.0, 24.9, 33.4, 33.0 | 3/3 all | Firedamp in 1 of 4; burrows in phases 2 and 3 |
| Storm Warden (depth 3, Frostvault) | 1.0 | 24.0, 23.4, 25.4, 27.9 | 3/3 all | Grounded tore the rods in 3 of 4; Storm Cloud on the core once |
| | 1.3 | 24.9, 31.8, 17.5, 34.6 | 3/3 all | Grounded in 2; Steam on the core in 2 |
| | **1.5** (shipped) | 26.2, 28.4, 32.7 (a fourth run never reached the boss) | 3/3 all | Grounded tore the rods early in 3 of 3; 4 to 5 recharges a fight |
| Void Herald (depth 5, The Rift) | 1.0, shards worn by any fusion | 13.5, 25.4, 20.7, 25.6 | 3/3 all | Shards torn by Plasma, Galvanic Rot within 2 s |
| | 1.9, Rift fusions tear | 19.3, 25.7, 25.7 | 3/3 all | Grounded Rift once; a theft every fight |
| | **2.3** (shipped) | 32.9, 27.1, 29.8, 24.0 | 3/3 all | Venomous Rift collapsed the ring in 2 of 4; stole Shock, Fire, Shock, Poison |

- The storm build has no water gun, so the Warden's Storm Cloud on the core is rare for this
  bot (Steam comes from fire and ice). The chains show, but a water build would use them
  more.
- **Aim modes re-measured on the Pyre Lord** (`--boss-only --boss-dps=2200`, Pyre loadout,
  bot aiming at intact armour first), all 3/3 phases:

  | Mode | Fights | Average |
  |---|---|---|
  | Auto | 81.5, 70.3 s | 75.9 s |
  | Assisted, bot aiming | 79.5, 63.3 s | 71.4 s |
  | Manual | 79.3, 93.4 s | 86.4 s |

  Aiming at the armour first fixed the part 2 gap: assisted is now level with auto.
- **Quench vats,** Pyre Lord `--boss-only`: 22 and 23 bursts a fight from stray shots (auto
  fire never targets props), fights of 80.0 and 70.9 s, 3/3 phases, Obsidian on the core.
- **Music:** `[MUSIC]` shows boss2 > boss3 > boss (pitch 1.06) across the three phases, and
  a reset when the boss dies.
- **First region,** with the code of each commit: the idle six-gun bot died in Ossuary Gate
  in 7 of 10 runs (t=42, 120, 45, 154, 69, 49, 138); in the other 3 it killed the Brute King
  in 12 to 20 s. The old code (`67284c1`) died in 4 of 4 today, and in 5 of 6 in part 2.
  None of the part 3 code runs on that floor and runs are unseeded, so this reads as noise,
  but it is worth watching. The fusion probe cleared Ossuary Gate in 10 of 13 runs (Brute
  King 8.4 to 50.4 s, 3/3 phases) and never died there; the other 3 ran out the 420 s clock,
  one confirmed standing in the Shop (the stall above, now 3 of 13).
- **Frame rate** (real window, vsync, `--boss-only`, the storm build, against `67284c1`).
  The first run after a code change is often slow on both versions (warm-up), so medians
  leave it out:

  | Fight | New | Old |
  |---|---|---|
  | Hive Mother (avg, whole run) | 95.1, 96.8 | 97.5, 85.7 |
  | Storm Warden (avg; phase-3 trail halved after the first pair) | 92.7, 89.2 | 93.5, 91.7 |
  | Void Herald (median fps, first 20 s) | 77, 75, 81 | 78, 76, 76 |
  | Pyre Lord with vats (avg) | 70.1, 85.3, 87.3 | 70.4, 87.7, 85.6 |

  The Rift room is slow on both versions (about 75 to 80 fps). The Herald's parts cost a
  few fps there (79 and 82 without them); bending shots costs nothing measurable.
- **Screenshots** (`--boss-shot`): the sacs, the eruption circle, the rods and the storm
  core, the hollow centre, the gravity wells and the shard ring all draw with the black
  outline and red rim; poison rings, bolts and spirals carry the red rim. Vats show a blue
  water ring when full.
- Editor load check clean.

**Left after phase 0b** (none blocks phase 1):
- Arena tools for the other bosses: braziers, pylons, bells (section 6, rule 5). Only the
  Forge's quench vats exist.
- The Brute King's fight spread (idle-bot clears at 12 to 20 s) and his early first plate
  tear.
- Boss rooms slow over time (render objects climb to about 18k to 24k in 30 to 45 s on old
  and new code): Forge and Rift rooms run at 70 to 90 fps.
- The bot stall: the fusion probe stood in the Ossuary Shop until the clock ran out in 3
  of 13 runs, and one Frostvault run never reached the boss. Worth a bot fix before the
  next balance phase, since it hides results.
- Music layers are track changes, filter and pitch from the existing pool; real stems would
  need new CC0 or CC BY music.

### Clarity pass (DONE 2026-11-07)

Emil plays solo and could not tell elements, enemies and shots apart. Brotato and Noita read
clearly to him. This pass came before more content. No new art; the DCSS packs stay.

What changed:
1. **Nothing spawns on the player** (Brotato's rule). Every spawn keeps 170 px from players
   after clamping (`Room.SPAWN_MIN`; a ring point near a wall used to be clamped onto a player).
   A spawn telegraphs for 1 s (`Enemy.EMERGE_SECS`, was 0.75) under a marker: a dark disc,
   a red rim, red pixels closing in. A player within 80 px of a marker moves it
   (`Room.respawn_point`) and its telegraph starts over. Room spawns, elites, secret-room
   spawns and boss summons (`_pending`) all do this. Bot log: `[SPAWN-MOVED]` per move, and
   `[SPAWN-CHECK] PASS/FAIL` at the end: no body finished emerging within 60 px of a player.
2. **Quieter own effects.** Fields and gas draw full only at their rim; insides are at 15%
   (`fill` in the Materials shader). The field layer is at 80%, its glow at 25%. Bloom is
   0.35 (was 0.85). "Your effects" defaults to 0.45 (was 1.0); `FX_REV` 3 lowers saved
   values once. Enemy shots and hostile edges are on the Crisp layer, unfaded, so they stay
   the brightest thing on screen.
3. **Less combat text.**
   - Damage numbers show only for crits, and for hits at 2.5x the running average (at least
     25), so the cutoff follows the build.
   - Reaction names were already limited to fusions and cataclysms. Each name now shows at
     most once per 4 s.
   - A first discovery is a HUD toast ("New fusion: X") instead of "NEW" in the fight.
   - Toasts that arrive during a fight wait until the room is clear.
4. **Enemy outlines.** Bodies draw 15% larger than their hit circle, with an opaque dark
   outline 2 world px wide in 8 directions (was 1 texel in 4 directions at 85%).
5. **Flat floor.** Floor tiles and boss-room floor decals keep 50% saturation and 60%
   contrast around a dark middle (`Room.FLAT_FLOOR`, mid 0.08). A flat grey (mid 0.4) and
   mid 0.16 scored lower on enemy contrast: the DCSS bodies are mid-tone, so a dark floor
   separates them best.
6. **Badges** (region resistances) show only on the aimed enemy (`Player.aimed`), on elites
   and on bosses.

**Measured** with `--clarity-shot` (README, Self-test): a fixed seed, the storm build, the
player standing near the middle, shots at 5, 8 and 11 s (boss: 5, 9, 13 s, boss health x5).
Averages of seeds 7 and 11. "Before" is d301b70 (item 1 only), so spawn placement matches.

| Scene | Own effects, % of screen | Own effects, mean change | Enemy contrast, per pixel | Enemy contrast, means | Text items |
|---|---|---|---|---|---|
| Frostvault arena | 75.9 -> 49.4 | 50.1 -> 20.4 | 0.213 -> 0.227 | 0.185 -> 0.158 | 47.5 -> 14.2 |
| Rust Ruins arena | 10.5 -> 13.8 | 4.5 -> 5.3 | 0.260 -> 0.288 | 0.249 -> 0.282 | 30.7 -> 4.4 |
| Hive Mother | 12.5 -> 9.8 | 6.6 -> 4.1 | 0.367 -> 0.350 | 0.358 -> 0.336 | 33.8 -> 6.3 |

How to read the measurements:
- **Own effects, % of screen:** pixels that change by more than 0.1 when the player's
  shots, clouds, pools, sprays, beams, mines, particles and floor fields are hidden.
- **Own effects, mean change:** the average change over the whole screen, in % of full scale.
- **Enemy contrast, per pixel:** mean |luminance with the body - without it| over each
  enemy's disc. Floor texture counts towards it, so flattening the floor lowers it a little
  by itself.
- **Enemy contrast, means:** the same, using the disc's average luminance with and without
  the body.

In Frostvault the field layer was most of the white: with each layer hidden alone, its mean
change went from 47 to 27 at a 30% inside, before the 15% inside. Rust Ruins own effects
were small before and after; that difference is frame noise between seeds. Enemy contrast is
noisy from frame to frame (±0.05 between seeds). It went up in Rust Ruins, about level in
the Hive Mother fight, and down on the "means" measure in Frostvault, where the frost
monsters are pale. Screenshots: `autotest/clarity_<region>[_boss]_<before|after>_<n>.png`.

Checks:
- Idle bot, fusion probe (two loadouts) and a real-floor storm run to the Storm Warden: 0
  script errors, `[FUSION-CHECK] PASS`, `[SPAWN-CHECK] PASS` with close=0, and 6 to 10
  markers moved per run.
- Brute King boss-only and Hive Mother real-floor runs (on the item 1 code): PASS, 6 and 9
  moves.
- fps, real window, storm build in Frostvault, 110 s, run in both orders: old 69.3 and 68.8,
  new 68.5 and 68.7 (minimum 35/36 old, 38/37 new).

Left:
- Gas still leaves a grey grid in big steam clouds: neighbours' gas drifts into a cell's
  border at full strength (the drift loop after the rim fade in the Materials shader).
- Frostvault enemies are pale and the frozen floor is light. If they still blend for Emil,
  that is the case for a region-specific floor mid or an art change (out of scope here).
- A splitter's two swarmers still appear where it dies, without a telegraph (a death split,
  not a spawn).
- `Cloud`, `Pool` and `Spray` nodes are only faded by "Your effects", not drawn as rims.
- Spawn markers are prominent in big refills (8 to 10 at once in Frostvault). If that reads
  as noise, shrink them or hide the disc until the last half second.
- Not measured: whether text and badges are now too sparse for a new player (for example, an
  unaimed enemy's resistances can't be seen at a glance).

#### Frostvault clarity (2026-11-08)

Phase 4 measured own effects on 54% of the Frostvault screen against 14% in the Rust Ruins.
**Cause:** the frozen floor is one big ice sheet on the Materials grid (about 30,000 cells,
drawn by `Room.IceSheet` while still). One shock charges up to 2,500 connected ice cells at a
time. Each charged cell then (a) strobed near-white and added a soft glow into its
neighbours (the glow layer, which the 15% inside never touched), and (b) lost its "still"
flag for good, so the grid drew the whole sheet a second time over the sheet's own texture.
With the storm build the sheet was almost always charged, and the field layer changed a whole
rectangle of floor. Steam and gas were small next to it (`[CLARITY-CELLS]`).

**Fix (drawing only, gameplay unchanged):**
- Charged ice strobes and glows only on its own cell, at the sheet's rim and on 1 cell in 16
  inside (a sparse twinkle). The charge, its spread and its damage are unchanged.
- On light floors (`EnemyProjectile.LIGHT_FLOOR_THEMES`, so frozen) the grid draws only the
  rim of ice (`ice_fill` 0 in the Materials shader). The sheet's texture already shows the
  inside. Other floors keep the 15% inside.

**Measured** with `--clarity-shot --clarity-spitters=8 --clarity-parts`, storm build, seeds 7
and 11, two runs each (the same seed varies from run to run in a real window): 12 frames
before, 12 after.

| Scene | Own effects, % of screen | Own effects, mean change | Enemy contrast, per pixel / means | Spitter shot vs floor / vs own effects |
|---|---|---|---|---|
| Frostvault | 60.3 -> 25.0 | 18.6 -> 6.5 | 0.291 / 0.192 -> 0.275 / 0.183 | 0.408 / 0.408 -> 0.386 / 0.381 |
| Rust Ruins | 8.4 -> 7.1 | 4.4 -> 3.8 | 0.257 / 0.251 -> 0.324 / 0.316 | 0.371 / 0.367 -> 0.365 / 0.349 |
| Rotting Gardens | 12.1 -> 11.2 | 5.7 -> 5.4 | 0.336 / 0.331 -> 0.326 / 0.319 | 0.402 / 0.389 -> 0.379 / 0.365 |

Rust Ruins and Gardens "before" are seed 7 only (3 frames). Enemy and shot contrast are
measured against the floor with own effects hidden. The fix can't change them, so their
movement is frame noise (which enemies and shots are on screen, over which part of the floor).
Shots still read about the same against own effects as against bare floor.
The glow fix alone took Frostvault to 52.5% and a mean change of 12.6; the rim-only ice took
it the rest of the way. One shot caught as it despawned (contrast 0.02) is left out of the
shot averages. fps, real window, Frostvault storm run, 90 s, alternating: old 67.9 and 69.1
(min 39/30), new 67.8 and 67.9 (min 35/38).

`--clarity-parts` now also prints `noise=` (the change between two frames with nothing hidden:
GPU particles and shader time keep moving while paused) and `[CLARITY-CELLS]` (cells per
floor material), and saves `<shot>_mask.png` (red: changed by own effects, blue: moves
anyway). Noise ran 0.1 to 7.6 in Frostvault. It inflates every own-effects number a little,
and the per-category `fx`, `clouds` and `shots` numbers there are mostly noise. About a
quarter of the screen is left, mostly real effects (lightning, clouds, particles) plus that
noise. Captures: `autotest/clarity_frostvault_before7_3.png`, `clarity_frostvault_after27_3.png`
and their masks.

### Phase 1: The Hollow, part 1 (BUILT 2026-11-07, lines wait for approval)

- **Goal:** a walkable hub with people in it, and features that arrive with them.
- **Scope:**
  - A larger hub of several connected rooms.
  - A dialogue system with lines keyed to state.
  - The Keeper and the Gatewarden replace the Shrine and the Gate.
  - The Archivist is met in the Ossuary, recruited with a Torn Bestiary Page, and brings the
    Journal.
  - Voice sheets for these three, with designer-approved samples, before any lines are written.
  - A fresh save starts with only the Shrine, the Gate and a bare run history. Stations without an
    NPC yet keep working as they do today.
- **Start from:** `hub.gd`, `mastery_screen.gd`, `journal.gd`, `progress.gd`, `room.gd`
  (encounters), `figure_gen.gd` (NPC looks).
- **Acceptance:**
  - Every old station's function still works.
  - A fresh save starts with only the Shrine and the Gate.
  - Recruiting the Archivist opens the Journal.
  - The line batch passes the writing review (section 9).
  - Hub screenshots read well on a TV.

**Phase 1 handoff (2026-11-07, built while Emil was away; part 1 of 2: the line batch waits for
approval).**

Done:
- **The Hollow** (`scripts/hub.gd`): five rooms joined by doorways, the camera following the
  players. The Fire (the Keeper and a code-drawn fire), the Stair (the Gatewarden and the
  Gate arch), the Library (shelves, a desk, the Archivist once home), the Forge (Armory and
  Workshop plinths, a cold hearth and an anvil) and the Chapel (trophy wall and goals, the
  Mirror). Floors and walls use the crypt, forge, ruins and sanctum themes.
- **Dialogue** (`scripts/dialogue.gd`): lines with conditions on the save (where, talks,
  runs, deaths, last result, last floor and region, Embers, the Archivist's state, the page),
  a priority, `once`, and least-heard-first among equals. Counts live in the save (`npcs`,
  `seen_lines`; old saves load with neither). Run history entries now carry the region.
- **The talk box:** name in the NPC's colour, the line, then their services as buttons and
  Leave; pad, keyboard and mouse. The Keeper offers Talents; the Gatewarden Descend and Past
  runs; the Archivist Journal and Ledger.
- **The Archivist:** chained in the first region's treasure room (shop if none) every run
  until freed. The first elite killed in a run drops the Torn Bestiary Page as a pedestal;
  carrying it, the Archivist's prompt reads "Give: Torn Bestiary Page". Giving frees them
  (save state `recruited`), the toast says where to find them, and the Library desk is
  theirs from the next hub visit. Meeting without the page sets `met`, and the next line
  remembers it.
- **Features arrive with people:** the Journal is split by station (`Journal.set_view`): the
  Archivist has Reactions, Fusions, Cataclysms and Secrets; the Armory Arsenal and Gear; the
  trophy wall Achievements. Before the Archivist, the Gatewarden's Past runs is the bare
  history (last five runs and a count of deaths); after, it is the full ledger with totals.
- **Looks** (`scripts/npc.gd`): FigureGen theme blends at 3.5x with a rim in the NPC's
  colour (Keeper fire and vagrant, Gatewarden plate and stone, Archivist arcane and poison),
  chains and shackles drawn in code. No new art files.
- **Voice sheets** for the three: `design/Voice sheets, phase 1.md`, ten samples each, a
  Haiku review against section 9 (19 of 44 lines flagged; 10 fixed, 3 left for Emil).
  The game ships 14 plain lines tagged `"placeholder": true`.

Measured:
- `--recruit-probe` (fusion probe loadouts, 3 runs): page dropped at t=21, 23 and 48 s,
  taken 5 to 7 s later, the Archivist freed at t=99, 148 and 91 s; 0 script errors.
- `--hub-walk`, fresh save: `[HUB-FRESH] PASS` (on show: keeper, gatewarden, gate), and the
  Keeper's talents, the Gatewarden's past runs and Descend, and the Gate all open.
- `--hub-walk --keep-save` after a recruit run: all 8 stations on show; every step PASS,
  including the Archivist's Journal (Reactions, Fusions, Cataclysms, Secrets) and Ledger, the
  Armory (Arsenal, Gear), the Workshop (options), the Mirror (names) and the trophy wall.
- Screenshots (`--hub-shot`, 1280x720): NPCs were 40 px tall and the Archivist's name sat on
  the desk; NPCs are now 56 px, names 24 px over their heads, the prompt and verb above the
  name, the talk box text 28 px and its name 30 px. In the Stair the camera stops at the
  room's edge and the box covered the Gatewarden, so the box moves to the top of the screen
  when the speaker is in the lower half.
- Section 0 checks: editor load check clean. Idle six-gun bot (2 runs): 0 script errors, died
  in Ossuary Gate at t=145 and 44 s. Fusion probe (2 runs): 0 script errors, cleared Ossuary
  Gate (Brute King 12.7 and 69.9 s), `[FUSION-CHECK] PASS`, `[SPAWN-CHECK] PASS` close=0.
  Neither bot picks up the page (only `--recruit-probe` does), so their play is unchanged.

Left:
- **The real line batch.** Waits for Emil's approval of the voice sheets; then write the
  1,500 to 3,000 line target in batches, starting with these three, and run the section 9
  review on each batch. The boss name token (`{boss}`, sample Gatewarden 2) and the killer of
  the last run are not in the context yet; add them with the batch.
- Death-keyed lines need the killer in the run history (`Progress.end_run`); only the region
  and floor are stored now.
- The Archivist's Journal tabs for enemies, region profiles and lessons (section 9's cast
  table) do not exist yet; lessons are phase 3.
- Giving the page costs nothing yet: it has no other use. Section 9 wants giving to cost
  something; a page that can be read for a run bonus, or sold, would make it a choice.
- NPC pronouns are open (the samples avoid them).
- Hub screenshots were checked at 1280x720 only, not on a TV.

Defaults taken (listed in section 16 as AN to AR):
- Stations whose NPC isn't built (Armory, Workshop, Mirror, trophy wall) appear from the
  first run on, so a fresh save shows only the Shrine (Keeper) and the Gate (Gatewarden).
- The old Ledger station is gone: the Gatewarden keeps the bare history, the Archivist the
  full one. Players with old saves lose the reaction tabs until they free the Archivist.
- The page drops from the first elite killed in any region; the Archivist is only in the
  Ossuary. A page found deeper waits for the next run, since pages don't carry over.
- The Gate arch still starts a run without talking, next to the Gatewarden.

### Phase 1b: Bonds

- **Goal:** gifts deepen relationships and give unwanted loot a purpose.
- **Scope:**
  - Gifting from the hub.
  - NPC tastes.
  - Five bond levels per NPC.
  - Story lines in pieces.
  - Keepsakes for the Relic slot.
- **Acceptance:** every bond level is reachable; gift tastes are readable in the UI; the writing
  review passes.

### Phase 2: Loadouts (BUILT 2026-11-07)

- **Goal:** classes become loadouts on one descender.
- **Scope:**
  - The 13 classes become Kits and Marks.
  - The Gate offers the Kit, Mark, Relic and Vow slots.
  - The Well and the Wellkeeper.
  - The Vagrant as the only body, with a Mark accent.
  - Save migration: a player's unlocked classes become unlocked Marks.
- **Start from:** `classes.gd`, `class_select.gd`, `player.gd`, `items.gd`, `progress.gd`.
- **Acceptance:**
  - All 13 old classes play as Marks with the same numbers.
  - Old saves migrate.
  - Bot loadout probes pass.

**Phase 2 handoff (2026-11-07, built while Emil was away).**

Done:
- **Kits and Marks** (`scripts/loadout.gd`, replacing `classes.gd`): each old class is a
  Kit (its starting gun) and a Mark (element affinity +20% potency and +10% damage, its
  quirk, its starting item). Mark ids are the old class ids, so Shrine bounties and
  telemetry keep their keys. 13 Kits (Bare hands, the Vagrant's pick of two, plus the 12
  class guns) and 13 Marks (the Unmarked plus 12). Names are placeholders: Mark of the
  Pyre, the Drowned, the Storm, the Frost, the Pitch, the Plague, the Crucible, the Vein,
  the Void, the Vigil, the Gale, the Stone. "Tide" and "Hollow" are left free for the new
  Marks in section 11.
- **The Gate screen** (`scripts/loadout_screen.gd`, replacing `class_select.gd`): the
  Vagrant on the left with the Mark's accent, four slots and Descend on the right. Pad:
  up / down picks a slot, left / right or LB / RB changes it, A descends, B backs out.
  Keyboard: W / S, A / D or arrows, Enter, Esc. Mouse: a slot's arrows, the wheel over a
  slot, Descend. Locked Kits and Marks show their goal and block Descend. The Gate arch,
  the Gatewarden's Descend and the menu's Play all open it; the loadout is saved.
- **The Well:** every region's start room has one (`Pedestal.draw_well`, drawn in code).
  Once per region one worn item can go down it (`scripts/well_screen.gd`: a button per
  item and Keep them; pad, keyboard and mouse). However the run ends, the item waits for
  the Wellkeeper.
- **The Wellkeeper** (silent, no lines): moves into the Fire room the first time an item
  waits, beside a drawn well. Using her opens her stall: what waits, priced by rarity,
  and the Relics you own. A Relic is kept for every run and picked in the Relic slot.
- **Vows:** Iron (enemies +25% health) and Glass (-30 max HP), each +20% Embers on the
  whole run, shown as "vow +N" in the payout.
- **One body:** the figure is always the Vagrant theme plus worn gear and guns
  (`FigureGen.profile`); the Mark shows as a glowing brand on the chest
  (`Player._draw_mark`), in the run and in the Hollow.
- **Save migration** (version 3): each `class:<id>` unlock becomes `mark:<id>` and
  `kit:<gun>`; the achievements that unlocked a class now grant its Mark and Kit. New
  save keys: `loadout`, `relics`, `well_saved`.
- **The real save is now safe from bots:** any command-line argument after `--` points
  Progress at `user://save_autotest<_N>.json` before the autoload's first load. Before
  this, the autoload loaded (and could rewrite) `user://save.json` in every bot run.
- Bot flags: `--class=<old class>` (that Kit and Mark), `--kit=`, `--mark=`, `--relic=`,
  `--vow=`, `--well-probe`; `[GATE-LOADOUT]`, `[LOADOUT-STATS]`, `[WELL]`, `[MIGRATE]`,
  and in `--hub-walk` `[HUB-LOADOUT]` and `[HUB-RELIC]`.

Measured:
- **Same numbers:** all 13 old classes run as `--class=<id>` before the change (old
  `Classes.apply`) and after (Kit + Mark), `--one-floor --secs=300`: the `[LOADOUT-STATS]`
  line (max HP, carry, guns, items, every non-zero stat) is identical for all 13, with 0
  script errors in all 26 runs. Run results are one run each and vary with the seed:
  before, 4 of 13 reached floor 2; after, 1 of 13 did (plus 2 still on floor 1 at the
  time cap). The start is identical, so the difference is RNG, but it was not re-run.
- **Migration** on copies under `--instance`: a copy of Emil's save (version 2, 9
  classes) migrated to 9 Marks and 9 Kits, `[HUB-LOADOUT] marks open 9 / 13`, kits 9;
  a made-up version 2 save with all 13 classes opened 13 / 13 of both. The hub walk
  passed on both.
- **Loadout probes:** `--well-probe --class=pyromancer` dropped the Fire Charm at t=2
  and saved it at death; the hub walk on that instance (Embers set to 100 in its
  throwaway Shrine file) bought it back (`[HUB-RELIC] bought charm_fire, Embers left
  85`). `--class=stormcaller --vow=glass --relic=ring_fire` started at 70 HP wearing the
  ring, and paid "vow +3"; `--class=tidecaller --vow=iron` paid "vow +8". Fresh hub walk:
  `[HUB-FRESH] PASS`, 1 / 13 Marks open, Descend works.
- **Section 0 checks:** editor load check clean. Idle six-gun bot (7 runs): 0 script
  errors; 6 died in the Ossuary Gate (t=140, 117, 125, 46, 27 and 58 s) and 1 reached
  floor 2 at t=282. Its start is the Unmarked with the same stat line as the old
  Vagrant, so this looks like chance; worth watching in the next phase's runs. Fusion
  probe (3 runs): 0 script errors, Brute King 35.3 and 47.1 s, floor 2 reached,
  `[FUSION-CHECK] PASS`, `[SPAWN-CHECK] PASS` close=0. A `--well-probe` run that quit
  at floor 2 (no `_end_run`) still saved its item: Well items are kept on any exit
  from the run scene. Phase 1: `--recruit-probe` freed the Archivist at t=58,
  then `--hub-walk --keep-save` passed every step, Journal and Ledger included.
- Screenshots (`--menu-shot`, 1280x720): `classes.png` (the default loadout) and
  `loadout_mark.png` (a locked Mark with its goal, the brand on the Vagrant, Vow of Iron).

Incident: before the fix above, the "after" runs migrated Emil's real `save.json` at
startup (version 2 to 3). It was put back to version 2 by reversing exactly that change
(`mark:` back to `class:`, the `kit:` unlocks and the three new empty keys removed);
nothing else in it had changed, and `mastery.json` and `runs.jsonl` were untouched. The
game will migrate it again, properly, the first time Emil runs this build.

Left:
- **New Marks** (Tide, Hollow, and rule-changing traits such as the Pyre's spreading
  burns in section 11): not built. The 13 Marks are the old classes' numbers only.
- **Mark and Kit unlocks by challenge or lesson** (section 11): still the old class
  achievements. Lessons are phase 3.
- **The Hollow Wells region** where the Wellkeeper is found (section 9): not built; she
  arrives with the first saved item instead.
- **Relic slots growing with the Wellkeeper's bond** (default L): bonds are phase 1b.
  One slot for now.
- Only two Vows; the "bosses enrage at half health" example in section 11 is not built.
- The section 9 writing review of Mark names, Vow names and the new short texts (Well,
  stall, Gate). All are plain and functional, marked as placeholders in code.
- Not checked on a pad by hand or on a TV: the bots drive the screens through their own
  calls, not through pad input.
- Bot runs on the old code wrote `user://settings.json` once (17:28, before this phase's
  changes); `Settings` writes on load or on some bot path. Worth a look so bots never
  write the player's settings either.

Defaults taken (listed in section 16 as AS to AZ).

### Phase 3: Death teaches (BUILT 2026-11-07)

- **Goal:** unlocks come from dying and from challenges, and the meta curve hits its targets.
- **Scope:**
  - Lessons, hints and counter unlocks.
  - Today's achievement unlocks move to lessons or loadout challenges.
  - Embers income retuned.
- **Start from:** `progress.gd`, `mastery.gd`, `telemetry.gd`.
- **Acceptance:** a bot meta-curve check at fresh, half and full Shrine hits the targets in
  section 13, and the Shrine fills in 25 to 40 runs.

#### Phase 3 handoff

Commits: bfc071b (bot isolation), then the Phase 3 commit. Weekly usage 36% at the start,
37% at the end.

**Bot isolation (first).** `Main.bot_run()` (any user argument after `--`, or
`--autotest`) is checked in the `_ready` of Progress, Mastery, Settings and Telemetry before
their first load. Each then uses `save_`, `mastery_` or `settings_autotest<_N>.json` and
`telemetry/runs<_N>.jsonl`. Bot settings mark the tutorial, explainer and play-data prompt
done and keep uploads off; the gameplay keys (aim mode, hit-stop) are the defaults, the same
as Emil's file. Proof: the real `settings.json` (17:28:31), `save.json` (18:32:32),
`mastery.json` (2026-11-06 20:37:37) and `telemetry/runs.jsonl` (2026-11-06 20:49:23) kept
their timestamps across a load check, an idle bot and a hub walk. Later in the evening
(21:51) the real save, Shrine and play data changed again: those records are `bot:false`
with Emil's device id (his own Pyromancer run on the Phase 2 build), not a bot.

**Built.**
- **Lessons** (`scripts/lessons.gd`): 11, one per built boss kind (Brute King, Hive Mother,
  Storm Warden, Pyre Lord, Void Herald) and one per built region (Ossuary Gate, Rust Ruins,
  Frostvault, the Forge, Chapel of Ash, the Rift). A death in a boss room counts against the
  boss, anywhere else against the region (`Lessons.killer_key`). The first death unlocks the
  lesson's counter guns; deaths per key are saved (`lessons` in the save, no version bump:
  older saves load with none). Bots print `[LESSON]`.
- **Hints:** the Gatewarden (`warden_lesson`), or the Archivist once home
  (`archivist_lesson`), names the killer and gives the hint: vague, plain from the third
  death. Lines and lesson texts are placeholders (`placeholder: true`).
- **Unlocks moved:** 12 counter guns left their achievements for lessons (oil_slinger,
  cinder_flak, hydro_cannon, acid_flask, ember_carbine, rime_chakram, eclipse_carbine,
  glacier_lance, napalm_lobber, void_orb, stone_sling, sun_cannon). Those achievements stay
  as milestones with no reward, so saves keep their ids; guns already unlocked stay
  unlocked. `unlock_source` shows "Lesson: die to X". The 13 `class_*` achievements are now
  the loadout challenges: each opens a Mark and its Kit, and the loadout screen already shows
  the goal.
- **Embers** (`Mastery.PAY`): the section 13 proposal. Rooms 1, elites 1 (at most 10 a
  run), first discoveries 2, fusions 2 and cataclysms 3 (at most 6 a run together), bosses
  3, bounties 5, each floor past the first 3, a win 20. The Shrine costs are unchanged
  (928 in all; see the estimate below).

**Meta curve, measured** (kite bot, Unmarked, `--secs=3600`, every bot starts from an empty
save, so every reaction is a first discovery):

| Stage | Runs | Result | Embers per run (first discoveries in it) |
|---|---|---|---|
| Fresh | 4 | 2 died on floor 1 (t=56, 40), 1 won (t=2,783), 1 hit the wall-clock limit in the Rift on floor 5 | 6 (4), 1 (0), 190 (52), none |
| Half (`--mastery=464`, 419 spent) | 4 | 3 won, 1 died on floor 3 in the Frostvault (t=824) | 232 (94), 210 (72), 208 (70), 104 (48) |
| Full (`--mastery=full`) | 2 | 1 won (t=2,608), 1 at the 3,600 s cap in the Rift | 266 (128), 182 at the cap (84) |

Without first discoveries a win pays 138 (113 once the 5 bounties of a Mark are taken), a
floor-3 death 56 (46), a floor-1 death 1 to 2. A floor-2 death was not measured; the
proposal's 17 to 27 fits the floor-3 run's split.

Against the locked targets in section 13:
- **Fresh, "usually dies at depth 2": not hit by bots.** They split 2 of 4 on floor 1 and 2
  of 4 on floor 5. The caveat holds: a bot that survives floor 2 nearly always wins.
- **Half, "usually reaches depths 3 to 4": overshot.** 4 of 4 reached depth 3, and 3 won.
- **Full, "can win, not reliably": hit.** 1 of 2 won, and the other was still alive in the
  Rift at the time cap.
The targets are unchanged. Bots can't place the fresh and half stages, and human runs are
the reference (the 2026-11-06 humans died on floor 2 fresh).

**Shrine fill estimate** (928 Embers, half at 464):
- **At the human depths the targets describe:** about 22 to 36 runs.
  - Fresh to half takes 14 to 26 runs. That is floor-1 deaths at about 3 and floor-2
    deaths at about 22, so 12 to 22 a run on average. About 130 of the first-discovery
    Embers (65 reactions at 2) and the first bounties are paid on top, mostly early.
  - Half to full takes 8 to 10 runs at depth 3 to 4, about 46 to 60 a run.
  This is inside 25 to 40 except at its low end.
- **At bot depths:** about 10 runs, because bots win from a fresh Shrine. Fresh averaged
  66 a run and half 188.
- Doubling the costs, as section 13 floated for a 20-to-40-hour first win, would push the
  human estimate to 44 to 72 runs, outside 25 to 40. So the costs are left alone. Re-check
  with human runs on this build.

**Section 0 checks:**
- **Load check:** clean.
- **Idle six-gun bot:** 4 runs, 0 script errors. 3 died in the Ossuary Gate (t=72, 49 and
  24 s) and 1 reached floor 2 at t=246. Together with phase 2 that is 2 of 11 reaching floor
  2. The bot settings are the same in gameplay as the file it read before, so this looks
  like chance, but it is worth watching.
- **Fusion probe:** 0 script errors, floor 2 reached, `[FUSION-CHECK] PASS`,
  `[SPAWN-CHECK] PASS` close=0.
- **Recruit probe:** freed the Archivist at t=85.
- **Hub walks** with `--keep-save`, all PASS:
  - After an idle-bot death the Gatewarden said "Ossuary Gate. 1 on my count. The barrels
    down there aren't decoration."
  - With the Archivist home, every station passed.
- **Loadout probe:** `--class=stormcaller --vow=glass --relic=ring_fire` started at 70 HP
  wearing the ring and paid "vow +4".
- **Migration:** a copy of Emil's current save (version 3; he had already migrated it by
  playing) loaded with no lessons and passed the hub walk with 9 of 13 Marks open.

**Left:**
- **Remaining achievement unlocks:** the first block (an element a run), obstacles,
  secrets, rarities, the challenge room, the shop slots and the late gun tail are still
  achievements. The Mark challenges are reaction counts, not run challenges such as "kill
  the Frost Matron using only fire reactions".
- **The Journal:** no lessons tab, no boss resistances and no best attempt per boss
  (section 10, step 4).
- **What counts as the killer:** the room, not the damage source. Hazard lessons are per
  region, not per hazard (lava, gravity wells). Unbuilt regions and bosses have no
  lessons. There are 11 against section 10's 20 to 30.
- **Unchecked counters:** the Rift's counter, `eclipse_carbine`, is assumed to be Holy
  (its achievement was Annihilations) and was not checked.
- **Unmeasured Embers:** a floor-2 death, and any human run on this build.
- **Writing:** lesson names, hints and the two NPC lines are placeholders for the
  section 9 review.

**Defaults taken:** BA to BE in section 16.

### Phase 4: Shortcuts and world state (BUILT 2026-11-08, gates only)

- **Goal:** the world remembers what you opened.
- **Scope:**
  - Far-side gates, repaired lifts, bridges and sluices, and secret edges.
  - Persistent world state.
  - The Cartographer and the world map.
- **Acceptance:**
  - A shortcut opened in one run persists.
  - Travel time in a known region drops measurably.
  - No shortcut skips a boss.

#### Phase 4 handoff

Commits: the build label, the Frostvault shot fix, the gates and world state, then the
Cartographer and map. Weekly usage 37% at the start and 37% before the push.

**Prelude 1: build label.** `Telemetry.BUILD` = `VERSION+COMMIT`, now
`2026.11.08-p4+<hash>`. Each phase bumps `VERSION` by hand (date plus phase tag);
`COMMIT` stays `"dev"` in the repo and is stamped with the short hash by the Pages
workflow and `tools/export_exe.sh`. README, Telemetry, "Build label". Editor and bot runs
say `+dev`.

**Prelude 2: Frostvault enemy shots.** New `--clarity-spitters=N` on `--clarity-shot`
adds N spitters and `[CLARITY-SHOTS]` lines: the mean luminance change over each enemy
shot's disc, with the shot against without it, over the bare floor and over the floor
with the player's own effects. Storm build, 8 spitters, seeds 7 and 11 (and 7 with 5
spitters):

| Where | Floor behind shots (luminance) | Shot vs floor | Shot vs own effects |
|---|---|---|---|
| Rust Ruins | about 0.08 | 0.33 to 0.38 | 0.28 to 0.37 |
| Frostvault, before | about 0.25 | 0.30 to 0.34 | 0.30 to 0.37 |
| Frostvault, after | about 0.25 | 0.39 | 0.42 |

Nearly every Frostvault shot measured lower than the Rust Ruins ones: on a mid-grey floor
the red rim and the dark outline both sit near the floor's luminance. On themes in
`EnemyProjectile.LIGHT_FLOOR_THEMES` (frozen) the body is lifted further toward white and
the white core grows; same size, same black outline and red rim, still on the Crisp
layer. Spitter damage is unchanged. Captures: `autotest/clarity_frostvault_before11_2.png`
and `clarity_frostvault_after11_2.png` (regenerate with the recipe above). Not fixed and
worth a look: in the Frostvault the player's own effects change 54% of the screen against
14% in the Rust Ruins (ice reactions whiten everything). That, more than the shots, may be
what buried Emil's death there.

**Built.**
- **Far-side gates** (`scripts/shortcuts.gd`): one per built region (6). Each run lays the
  gate between the start room and the boss antechamber (the boss room's neighbour nearest
  the start) on a free wall of each. From the start side it is a barred chain-gate
  (`Obstacle` kind `chain_gate`, no element opens it); walking through it from the
  antechamber opens it for good, with a banner, a telemetry event and an immediate save.
  Later runs go entrance, gate, antechamber (its arena still fights), boss door.
- **World state in the save:** `Progress.world.shortcuts`, save version 4. Older saves
  migrate with an empty world (`[MIGRATE] save version 3 -> 4`).
- **Migration fix found by the test:** the Progress autoload loads before Items builds its
  catalog, so the load filter dropped every Relic, and the v4 migration saves at once:
  Emil's Ricochet Gloves would have been wiped on the first launch. The filter now waits
  for the catalog. On a copy of Emil's save: version 4, Relic kept, every other field the
  same apart from the hub walk's own talk counts; hub walk PASS.
- **The Cartographer** (`Npc` "cartographer", in the library, placeholder lines tagged in
  `scripts/dialogue.gd`) moves in when the first gate opens. Her service is the **world
  map** (`scripts/world_map.gd`): the Descent by depth with its edges, built regions named,
  the rest "unmapped", opened gates in gold and listed under it. The Back button holds the
  focus, so pad, keyboard and mouse all work, and Esc and B close it like every hub screen.
- **Boss check:** `Main.next_floor` asserts the floor's boss room is cleared and bots print
  `[BOSS-CHECK]`. `Shortcuts.plan` asserts the gate never ends in the boss room. The stairs
  only appear when the boss dies (`Room`), so a gate cannot reach past it.
- **Bot flags:** `--rush`, `--open-gates`, `--shortcuts=all`, `--keep-save`; lines
  `[SHORTCUT]`, `[TRAVEL]`, `[BOSS-CHECK]`, `[HUB-MAP]` (README, Self-test).

**Acceptance, measured.**
- **Persists:** run 1 (`--open-gates`, instance 1) opened the Ossuary gate at t=79 to 81;
  run 2 on the same save (`--keep-save`) found it open and walked through at t=3. The hub
  walk on that save met the Cartographer, and her map listed the gate.
- **Travel time drops** (Ossuary Gate, `--rush --build=storm --mastery=full`, seconds from
  floor start to the boss room):

  | Seed | Gate closed | Gate open |
  |---|---|---|
  | 3 | 80.7 | 29.6 (persisted save, other layout) |
  | 5 | 52.7 | 31.7 |
  | 7 | died in an arena at t=100 | 29.6 |
  | 9 | 141.8 | 27.5 |
  | 11 | 80.4 | - |
  | Mean | 88.9 (4 runs) | 29.6 (4 runs) |

  About two thirds less. Deeper regions with the gate open (seed 5): Rust Ruins 37.5,
  Frostvault 46.4, Chapel of Ash 53.2 and the Rift 63.7 s, all reaching their boss.
- **The cost is real:** with the gate open the Ossuary bot met the Brute King at level 1
  to 2 with almost no gear, and 3 of 4 died to him; with it closed 3 of 5 cleared floor 1.
  That is the section 8 trade (skip the arenas, their loot and XP). Watch whether human
  players take the gate too early.
- **No boss skipped:** `[BOSS-CHECK]` PASS at all 10 ways down measured (6 in the Ossuary
  and probes, then Rust Ruins, Frostvault, Chapel of Ash and the Rift), 0 FAIL; the gate
  was laid on all 20 floors generated in this phase's final logs.

**Section 0 checks.** Load check clean. Idle six-gun bot: 2 runs, 0 script errors, both
died in the Ossuary Gate (t=213 in the boss room, t=22). Fusion probe: 0 script errors,
floor 2 reached, `[FUSION-CHECK] PASS`, `[SPAWN-CHECK] PASS`. Recruit probe
(`--fusion-probe --recruit-probe`): Archivist freed at t=61. Loadout probe
(`--class=stormcaller --vow=glass --relic=ring_fire`): 70 HP, ring worn, "vow +2". Hub
walks PASS, including the Gatewarden's lesson line after an idle death ("Ossuary Gate. 1 on
my count. The barrels down there aren't decoration.") and the Cartographer's map. The real
`save.json`, `settings.json`, `mastery.json` and `telemetry/runs.jsonl` kept their
timestamps across every bot run of the phase.

**Left.**
- **Repaired lifts:** every pair of built regions one depth apart is already joined, so a
  lift has no new edge to add until phase 5 builds the Cistern, Gardens, Mire, Abattoir or
  Stormspire. The section 8 example (Rust Ruins to Frostvault) is an ordinary edge today.
- **Bridges and sluices:** the example is the Drowned Cistern (not built). The save can
  hold them (`Progress.world`); nothing reads anything but shortcuts yet.
- **Secret edges:** both secret regions are unbuilt.
- **A second shortcut per region:** one gate each today.
- **The Cartographer's own recruit** (lost at the top of the Stormspire, three Map
  Fragments) waits for the Stormspire. Her shortcut hint is one generic line.
- **Map:** no route history, no per-region detail, and no minimap line for the gate (the
  minimap shows only the gate's door stub). No bot walked the Forge's gate.
- **Writing:** the gate names, the obstacle label and the Cartographer's four lines are
  placeholders for the section 9 review.

**Defaults taken:** BF to BL in section 16.

### Phase 5: New regions

- **Goal:** fill the Descent.
- **Scope:** two regions with their themes, enemies, hazards and bosses per batch. **Default
  order:** Drowned Cistern and Rotting Gardens first, completing depth 2; then Pitch Mire,
  Abattoir and Stormspire; then the secret regions.
- **Acceptance:** each region has its profile, hazards and boss, and bots clear it inside its
  time budget.

#### Phase 5 batch 1, part 3 (2026-11-08): Choir ledges, fps and the Cistern's sluice

Weekly usage 38% at the start and 38% before each push. `VERSION` is `2026.11.08-p5c`.
Commits: the ledges and fps notes (05e2c9e), then the sluice.

**Built: the Choir's ledges** (BS). Three raised stone ledges, 96 x 72 px, in the
Choir's arena (`Room._build_choir_platforms`), placed near the corners and kept 170 px
off the doors; drawn in code as pale dressed stone with a dark front face and a cast
shadow (placeholder art). `Materials.raise_rect` marks their cells: `_put` refuses any
material there and `_nb` treats them as an edge, so water, gas, fire and charge never
land on or flow onto them. The flood still matters: shocking it charges the water you
stand in (4/s, half with your own shock), and the song still pulls you off a ledge.
Bots print `[CHOIR-LEDGES]` and `[CHOIR-FLOOD]` (phase 2 seconds, on a ledge, on charged
water).

**Fight length on real floors** (storm build, `--start-floor=2
--route=ossuary_gate,drowned_cistern --one-floor --secs=900`, health share 2.0):

| Seed | Choir | Phase 2 | On a ledge | On charged water | Clear checks |
|---|---|---|---|---|---|
| 1 | 29.4 s | 11.9 s | 0.0 s | 0.0 s | boss, fusion, spawn PASS |
| 2 | 44.2 s | 19.6 s | 0.9 s | 1.1 s | boss (gate open), fusion, spawn PASS |
| 3 | 30.0 s | 11.7 s | 0.0 s | 0.5 s | boss, fusion, spawn PASS |

Inside the 25 to 50 s target (it was 29.6 to 40.1 s). The bot doesn't seek the ledges,
so these numbers say the fight still works, not that humans will use the ledges.

**Frame rate, real window** (nothing else of ours running; `--perf`, means of the
per-second lines):

| Run | Mean fps | Min | Draw calls |
|---|---|---|---|
| Section 0 command (`--short --arsenal --gear`) | 97.5 | 85 | 470 |
| Choir, `--boss-only`, storm build, seed 2 | 83.3 | 56 | 1,870 |
| Hive Mother, same flags | 81.2 | 55 | 1,850 |
| Choir, `--boss-only`, no build (bot barely fires) | 99.7 | 98 | 1,660 |

The Choir is no worse than the Hive Mother. The arena alone, bell, singers and ledges
included, holds 100 fps; the drop comes with the floor-2 storm build firing: effect
particles sit at the 1,000 cap, primitives reach 25k to 35k and process time doubles
(10 to 20 to 36 ms). That's a late-build effects budget question for every boss, not a
Choir problem. Worth a dedicated pass (particle cap per build, chain lightning draws).

**Section 0 checks:** load check clean; idle six-gun bot died in the Ossuary Gate
(t=39); fusion probe cleared the Ossuary (Brute King 17.4 s) and reached floor 2; 0
script errors in every log; the real save, settings, mastery and `runs.jsonl` kept their
timestamps.

**Built: the Cistern's sluice** (section 8, "bridge or sluice"; `Shortcuts.SLUICE`).
- *Opened by hand:* once the Choir is dead, an iron wheel (pedestal kind `sluice`, drawn
  in code) stands in its arena before the stairs. Interact turns it: banner, telemetry
  `shortcut_opened`, and `Progress.open_shortcut`, which saves at once. It only exists
  after the boss dies, so it can't skip the Choir.
- *Stored* in `Progress.world.shortcuts` beside the gates (`drowned_cistern:sluice`). The
  save format is unchanged (version 4). On a copy of Emil's real save (still version 3):
  `[MIGRATE] save version 3 -> 4` (0 shortcuts), relic kept, and every field the same
  apart from version, the empty world and the hub walk's own talk counts. Hub walk PASS.
- *Drained in later runs* (`Shortcuts.drained`): no standing puddles, no drains, and the
  layout's deep pools stand dry (no wading); enemies other than the Choir get 1.3x health
  and 1.15x damage. The Choir still floods its own arena.
- *Map:* the hub list reads "Shortcuts open: Cistern grate, Cistern sluice", and the
  Cartographer's map draws gold waves beside the Cistern.
- Bots: `--open-gates` turns the wheel (`[SLUICE] opened`); each Cistern floor prints
  `[SLUICE] ... drained=`; `--shortcuts=all` opens it too.

**Measured** (storm build, `--start-floor=2 --route=ossuary_gate,drowned_cistern`):

| Run | Drained | Cistern clear | Choir | Water cells zapped | Boss check |
|---|---|---|---|---|---|
| seed 4, `--open-gates` (opened gate and sluice, sluice at t=350) | no | 351 s | 27.3 s | | PASS |
| seed 5, fresh save | no | 358 s | 34.4 s | | PASS |
| seed 5, `--keep-save` after the seed 4 run | yes | 382 s | 28.5 s | 6,957 (the Choir's flood only) | PASS |

Fewer water hazards (zapped cells 7k against 58k to 146k in wet runs) and a slower clear
(+24 s on the same seed) from the tougher enemies, which is the section 8 trade. One run
each, so the size of that trade is a first reading.

**Section 0 checks after the sluice:** load check clean; idle six-gun bot died in the
Ossuary Gate (t=20); fusion probe: 0 script errors and both checks PASS twice (one run
died to the Brute King at t=192, the re-run cleared him in 34.1 s and reached floor 2);
hub walks PASS; the real save, settings, mastery and `runs.jsonl` kept their timestamps.

**Left:** the late-build effects fps pass above; a bot that uses the ledges; a drained
look for the Cistern (dry basins draw as the layout's pools without water; no new rooms
yet); a screenshot of the wheel and the map; the sluice name, wheel label and hint are
placeholders for the section 9 review. Repaired lifts and secret edges still wait for
their regions.

#### Phase 5 batch 1, part 2 (2026-11-08): the Drowned Cistern

Weekly usage 38% at the start and 38% before the push. `VERSION` is `2026.11.08-p5b`.

**Built.** Write-up in `GDD.md` (section 3, "Drowned Cistern").
- `drowned_cistern` is `built: true`, theme `cistern`; the dormant puddle and drain code
  from part 1 now runs and worked first time (0 script errors). Its own edge leads on to
  the Frostvault, so no stand-in edge was needed.
- **The Drowned Choir** (`boss_kind` `drowned_choir`), the first new boss kind on
  `boss_body.gd`: singers and bell parts, three phases, stagger, hostile signature on the
  song ring, the pull and the shockwaves. It reuses the Pyre Lord's wave code for the
  phase 3 rings.
- Lessons `region:drowned_cistern` and `boss:drowned_choir`, gate "Cistern grate", all
  placeholders for the section 9 review. `[HAZARD]` now also counts `zapped` water cells.

**Measured** (storm build, `--start-floor=2 --route=ossuary_gate,drowned_cistern`, 0
script errors in every run):

| Run | Clear (to the boss's death) | Choir | Phases | Singers torn by | Water cells zapped |
|---|---|---|---|---|---|
| seed 1, health share 1.5 | 337 s | 24.1 s, 29.7k | 3/3 | Black Death | 82,200 |
| seed 2, 1.5 | 353 s | 20.3 s, 32.7k | 3/3 | Hollow Blight | 146,251 |
| seed 3, 1.5 | 351 s | 22.2 s, 33.4k | 3/3 | Galvanic Sea (twice) | 58,957 |
| seed 1, 2.0 | 357 s | 40.1 s, 37.2k | 3/3 | Chain Lightning | |
| seed 2, 2.0 | 347 s | 30.2 s, 35.6k | 3/3 | Chain Lightning | |
| seed 3, 2.0 | 356 s | 29.6 s, 42.8k | 3/3 | Galvanic Sea | |
| `--rush --open-gates --mastery=full`, seed 4 (opened the gate) | 143 s | 25.9 s, 24.6k | 3/3 | | |
| same, `--keep-save`, seed 5 (no free wall for the gate that floor) | 139 s | 26.3 s, 20.9k | 3/3 | | |

- At 1.5 the fights were 20 to 24 s, under the 25 to 50 s target, so the share is 2.0:
  29.6 to 40.1 s on real floors. Clears are inside the region budget, like the Gardens.
- `[FUSION-CHECK] PASS`, `[SPAWN-CHECK] PASS` (0 close) and `[BOSS-CHECK] PASS` (gate
  open and closed) in every Cistern run.

**Section 0 checks:** load check clean; idle six-gun bot died in the Ossuary Gate (t=49);
fusion probe cleared the Ossuary (Brute King 28.6 s); recruit probe freed the Archivist
(t=55) and the hub walk after it passed; loadout probe (`--class=pyromancer --vow=glass`)
60 HP, Flare Pistol and charm; hub walk after the gate run listed "Cistern grate"; the
real save, settings, mastery and `runs.jsonl` kept their timestamps. Frame rate was not
measured in a real window this batch.

**Left, in priority order:**
1. **The Cistern's sluice** (section 8): a world-state shortcut that drains the Cistern in
   later runs. Not started (budget).
2. **Choir platforms** (BS): the design wants raised platforms to stand on while the
   arena floods; today the flood just adds water.
3. **The Choir fight in a real window** (fps, and a look at the bell and singers art).
4. Items 3 to 5 of the part 1 list below still stand (Gardens > Frostvault stand-in edge,
   region enemies, Gardens fps).

#### Phase 5 batch 1 handoff (2026-11-08): the Rotting Gardens

Weekly usage 37% at the start, 38% before the push. The Gardens shipped alone: the brief
set a stop at 39%, and the Drowned Choir (a new boss) did not fit in what was left.
`VERSION` is `2026.11.08-p5a`.

**Built.** Write-up in `GDD.md` (section 3, "Rotting Gardens").
- **Region:** `rotting_gardens` is `built: true`, theme `garden`, resists Poison, weak to
  Fire, layouts overgrown, l_shape and diagonal. The Ossuary Gate now shows two route doors
  (Rotting Gardens, Rust Ruins).
- **Theme `garden`** in `scripts/themes.gd`: bog floor, slime walls, yellow trees, a snail
  statue and murky water, from the Dungeon Crawl tiles already in the repo. Footsteps and
  reverb in `sfx.gd`.
- **Spore pods** (`Ambience.add_vent(..., "spore")`, placed by `Room`): 2 to 3 per fight
  room, drawn in code. Every 3.5 to 5.5 s each puffs poison gas into the Materials grid.
- **Gas that ignites:** `Materials.gas_ignites`, set by `Regions.activate` from the region's
  hazards. While it is on, fire lights poison gas and burns along it like oil. Burning gas
  is an ordinary fire floor, so it already has the hostile signature and the floor damage
  rules (halved for a player carrying fire).
- **Boss:** the Hive Mother, now in her own region (her sacs, burrowing and Firedamp chain
  are unchanged).
- **Lesson** `region:rotting_gardens` (reward Blowtorch) and the far-side gate "Gardens
  trellis gate", both placeholders for the section 9 review.
- **Bot line** `[HAZARD] region=... gas_lit=N`.

**Measured** (all 0 script errors):

| Run | Clear (to the boss's death) | Hive Mother | Phases | Gas cells lit |
|---|---|---|---|---|
| Storm build, depth 2, seed 1 | 348 s | 33.4 s, 38.0k health | 3/3 | not counted yet |
| seed 2 | 341 s | 27.5 s, 34.1k | 3/3 | not counted yet |
| seed 3 | 347 s | 31.9 s, 32.6k | 3/3 | not counted yet |
| seed 4, after the Frostvault edge (walked on into the Frostvault) | 340 s | 19.8 s, 31.9k | 3/3 | 36,546 |
| seed 5, random doors from depth 2 (took the Frostvault door) | 349 s | 27.6 s, 27.4k | 3/3 | 18,157 |
| `--rush --open-gates --mastery=full` (opened the gate) | boss room at 164.7 s | 25.7 s, 20.9k | 3/3 | 24,189 |
| same, `--keep-save` (gate already open) | boss room at 73.6 s | 26.2 s, 14.6k | 3/3 | 3,170 |

- All clears are inside the 7 to 9 minute region budget (section 3). Six of the seven
  Hive Mother fights are inside 25 to 50 s; one took 19.8 s, as some did in the Rust Ruins
  in phase 0b. Her health share (1.5) is unchanged.
- The first three runs predate the `[HAZARD]` line and the Frostvault edge; their
  `[ROUTE]` line read "graph INVALID: rotting_gardens has no built way down", which led to
  the stand-in edge (BQ).
- `[FUSION-CHECK] PASS` and `[SPAWN-CHECK] PASS` in all three Gardens runs
  (max depth 5 to 6, spawns landed 2,081 to 2,269, 0 close).
- `[BOSS-CHECK] PASS` on every Gardens floor, with the gate open and closed.
- **Frame rate** (real window, vsync, storm build in the Gardens, `--perf`, 200 s): average
  97 fps over 87 samples with 10 or more enemies, min 81, 0 script errors. The Gardens
  boss fight itself was not sampled in a real window this batch.

**Section 0 checks:**
- Load check clean.
- Idle six-gun bot died in the Ossuary Gate (t=109, 2 rooms cleared).
- The fusion probe cleared the Ossuary (Brute King 56.2 s) and took the Rust Ruins door
  from the two offered.
- Recruit probe: the Archivist was freed at t=86, and the hub walk on that save found him
  and the Journal.
- Loadout probe: 70 HP, Ring of Fire worn.
- Hub walk after the idle death gave the Gatewarden's lesson line. A hub walk after the
  Gardens gate opened listed "Gardens trellis gate" on the map.
- The real `save.json`, `settings.json`, `mastery.json` and `telemetry/runs.jsonl` kept
  their timestamps.

**Left, in priority order:**
1. **Drowned Cistern.** Groundwork is in the tree but dormant (the region is still
   `built: false`, so nothing runs it):
   - theme `cistern` (limestone floor, shoal and brick walls, murky water, torches);
   - `Room` lays 3 to 5 standing puddles (240 s) in every room;
   - `Ambience` drains ("drain" vents, iron grates) pour water every 0.5 to 0.7 s while
     a fight runs, so the floor floods: rising water, conductive by the existing grid.
   Untested. To finish it:
   - set `drowned_cistern` to `built: true, theme: "cistern"`;
   - add its lesson and gate;
   - build **the Drowned Choir** on `boss_body.gd`: a bell part and singer parts.
     Galvanic Sea on the floodwater tears the singers. Phase 2 floods the arena, so stand
     on platforms; phase 3 cracks the bell into shockwaves. Use the hostile signature,
     add it to `NAMES`, `PHASES`, `PARTS`, `HP_SHARE` and `SpawnTable`, and measure on
     real floors.
2. **The Cistern's sluice** (section 8), once the Cistern exists.
3. **Gardens > Frostvault is a stand-in edge.** The Gardens' own edges are Pitch Mire and
   Abattoir, both unbuilt, so this batch added `frostvault` to the Gardens' edges (a
   crossing to the cold side) so a Gardens run has a door at its boss. Drop it when
   batch 2 builds either. `Regions.validate()` is clean with it.
4. **Gardens enemies:** none of their own yet; they use the depth's usual spawn table.
5. **The Gardens' Hive Mother fight** in a real window (fps), and a gas-count comparison
   with fire and without.

**Defaults taken:** BM to BQ in section 16.

### Phase 6: Living world

- **Goal:** the four locked ideas from section 12.
- **Scope:** world state changes beyond shortcuts, NPC camps in the Descent, the Rival, and
  elemental weather. Then the parked ideas, as the designer chooses.

---

## 16. Decisions and open questions

### Locked by the designer on 2026-11-06

| # | Decision |
|---|---|
| 1 | 5 regions per run at about 7 to 9 minutes each |
| 2 | Keep the region roster and elements in section 4 |
| 3 | Resistances start at 60% resisted and 140% weak, tuned with data |
| 4 | No waystones: every run starts at the top |
| 5 | The Keeper and the Gatewarden from the start; the Archivist is the first NPC recruited with an item |
| 6 | Loadout slots: Kit, Mark, Relic and Vow |
| 7 | The living world starts with world state, people who move, the Rival and elemental weather |
| 8 | Early runs are meant to fail; the meta curve in section 13 |
| 9 | NPC writing must feel human and pass the review in section 9 |

### Still open, with the default an agent should build

| # | Question | Default |
|---|---|---|
| A | Bosses: multi-part bodies with stagger? | Yes, as in section 6 |
| B | Boss rework before or after the hub? | Before: phase 0b comes before phase 1 |
| C | Which aim mode is the default? | Assisted twin-stick, confirmed with bot data |
| D | Stagger replaces guard rallies, or adds to them? | Adds |
| E | Hard run timer? | No |
| F | NPCs can die permanently? | No, except the Rival |
| G | Voice? | Text only |
| H | Fixed item asks or category asks? | A mix: specific for quests, category for the first NPCs |
| I | Bond levels and gift limits | Five levels, one gift per NPC per hub visit |
| J | Lessons on elites too? | Bosses and region hazards only |
| K | Marks change your look? | A small accent only |
| L | Relic slots | One, growing with the Wellkeeper's bond |
| M | Vows replace difficulty settings? | Yes |
| N | Opened shortcuts can close? | Never |
| O | Embers dropped on death? | No |
| P | The story's central question | What lies at the bottom of the Descent, and why do people keep going down? |
| Q | The graph's edges (phase 0) | As listed under Phase 0 part 1; crossings Rust Ruins > Frostvault and Frostvault > Forge |
| R | Boss for a region whose own boss isn't built | The boss its depth had before: Hive Mother, Storm Warden, Pyre Lord |
| S | How strongly a region colours its layouts | 35% of arenas use one of its signature layouts |
| T | What triggers Exposed, and what it does | Any reaction or fusion on the enemy; for 4 s its resistances count as weaknesses (140%) |
| U | How resistances scale state duration | The same 60% / 140% as damage (section 5 says "half as long" for resisted states) |
| V | Do reactions and fusions obey resistances? | No: reaction, fusion and prop damage is neutral; burn, poison and bleed ticks obey them |
| W | Route doors where only one built region lies below | One labelled door; phase 5 brings the 2 to 3 doors |
| X | Stagger: fill and effect (phase 0b) | 1.5% a reaction, 8% a fusion, 50% a cataclysm, half that in a patch over the boss; 4 s with no attacks, x1.5 damage and the shield open; then 5 s of rest |
| Y | Which part an element lands on | The part nearest the hit; area effects land on the part last hit; compounds stay on the part; part fusions skip the room-wide repeat gap |
| Z | Pyre Lord chain gates | Armour ignores shock and ice until steamed; the bare core takes only ice; Storm Cloud tears the armour, phase 2 cracks it, phase 3 re-forms it, and it re-forms after 12 s (8 s in phase 3) |
| AA | Pyre Lord health | 0.4 of the usual 30 s of arena output, for 25 to 50 s fights |
| AB | The other bosses until their rework | The framework without parts: stagger, name card, their two phases |
| AC | Aim mode default (C) | Assisted. With no aim input it is the auto path, so bots are unchanged; mode comparisons by bot so far are noisy |
| AD | Assisted fallback and soft lock | 1.2 s without aim input falls back to auto; 12-degree cone, wider for a big target close by; boss parts are targets |
| AE | Brute King health on floor 1 | The old formula x2.2 (`BossBody.FLOOR1_MULT`); floor-1 bosses are not sized from arena output |
| AG | Max-health damage on bosses | Bosses take a tenth of the decay share (`Elements.BOSS_DECAY`); parts made the shares stack |
| AF | Brute King plates | 4% wear a reaction, 8% a fusion, torn by a Barrel Blast; tearing them fills 35% of the stagger bar; gone from phase 2 |
| AH | Boss health shares (phase 0b part 3) | Hive Mother 1.5, Storm Warden 1.5, Void Herald 2.3 of the usual 30 s of arena output |
| AI | Hive Mother chain | Firedamp on the sacs tears them (4% health, 30% stagger); she burrows every 6 s in phase 2 and 8 s in phase 3, taking a quarter of hits while under with no sacs |
| AJ | Storm Warden chain | Three Grounded tear the rods; Storm Cloud on the core is an OVERLOAD (3% health, half the stagger bar); rods burst in phase 2, stay off in phase 3 |
| AK | Void Herald chain and theft | Any Rift fusion collapses the shards; the theft is the element with the most hits by the end of phase 1, immune for phase 2 only |
| AL | Gravity wells | 110 px, 6 s, pull 45 px/s, bend player shots; holy collapses them |
| AM | Music per phase | Track change, filter and a 6% pitch lift from the existing boss pool; no new audio |
| AN | Stations without an NPC yet (phase 1) | Armory, Workshop, Mirror and trophy wall work as before, shown from the first run on |
| AO | Where the run history lives before and after the Archivist | Gatewarden: last five runs and deaths; Archivist: the full ledger with totals |
| AP | Where the Archivist is chained | The Ossuary Gate's treasure room (shop if none), every run until freed |
| AQ | Which elite drops the Torn Bestiary Page | The first elite killed in a run, any region, while the Archivist is not home |
| AR | Placeholder lines before the voice sheets are approved | Ship plain functional lines tagged `placeholder` in `scripts/dialogue.gd` |
| AS | Where a class's starting item goes (phase 2) | The Mark: a Mark is affinity, quirk and starting item, so the class's Kit and Mark together are the old class exactly |
| AT | Which Kits exist and how they unlock | The 12 class guns plus Bare hands (the pick of two); a class's achievement unlocks its Mark and its Kit together. Base guns are not Kits on their own |
| AU | Where the Wells are | One in every region's start room, one item per region |
| AV | When a Well's item is saved | However the run ends (death, win or quitting to the Hollow) |
| AW | Where the Wellkeeper lives before her region exists | She moves into the Fire room the first time an item waits in the Well |
| AX | Relic price and how long a Relic lasts | 15, 30, 45, 60 or 75 Embers by rarity; bought once, kept for every run. A Relic in the same single slot as the Mark's item replaces it |
| AY | The first Vows | Iron (enemies +25% health) and Glass (-30 max HP), each +20% Embers on the whole run |
| AZ | Mark names (placeholders) | "Mark of the" plus a noun per element (Pyre, Drowned, Storm, Frost, Pitch, Plague, Crucible, Vein, Void, Vigil, Gale, Stone); the Vagrant's is "Unmarked". Tide and Hollow stay free for the new Marks |
| BA | What counts as the killer (phase 3) | The room: a death in a boss room is the boss's lesson, anywhere else the region's |
| BB | Which lessons exist | One per built boss kind and per built region (11); unbuilt ones wait for their region |
| BC | Lesson rewards | Counter guns moved from achievements (the boss's or region's weakness, or what tears its parts); their achievements stay as milestones |
| BD | Fusion and cataclysm pay | 2 and 3 Embers each, at most 6 a run together (section 13 gives only the cap) |
| BE | Shrine costs after the retune | Unchanged (928): the estimate at human depths is 22 to 36 runs; doubling would give 44 to 72 |
| BF | Where a far-side gate runs (phase 4) | Start room to the boss antechamber, laid each run on a free wall of each; no gate that run when the antechamber is the start room or next to it |
| BG | How a gate opens | Walking through it from the antechamber side; no lever or button. Saved at once, so a death right after keeps it |
| BH | The antechamber when you arrive by the gate | Still a normal room: its arena fights |
| BI | When the Cartographer arrives | With the first opened gate; her Stormspire recruit (three Map Fragments) waits for phase 5 |
| BJ | Lifts, sluices, secret edges | Deferred to phase 5: each needs a region that is not built |
| BK | Enemy shots on light floors | Themes in `EnemyProjectile.LIGHT_FLOOR_THEMES` (frozen) draw a brighter body and a larger white core |
| BL | Build label | `VERSION+COMMIT`: VERSION is the date plus phase tag, bumped each phase; COMMIT is stamped at export |
| BM | Where poison gas can burn (phase 5) | Only in a region with the hazard "gas that ignites" (the Rotting Gardens); elsewhere gas never burns as before |
| BN | Spore pods | 2 to 3 per Gardens fight room, a 30 px puff every 3.5 to 5.5 s; the gas itself never hurts the player, burning gas is a fire floor |
| BO | Rotting Gardens lesson reward | Blowtorch (its achievement stays as a milestone) |
| BQ | Gardens' way down until batch 2 | A stand-in edge Gardens > Frostvault; drop it when Pitch Mire or Abattoir is built |
| BP | Batch 1 when the budget is short | The Gardens ship alone; the Cistern's theme and hazards wait dormant in the tree |
| BR | Drowned Choir chain | Singers are innately wet: shock on them is Chain Lightning (12% wear), any fusion 15%, Galvanic Sea or Hurricane tears them at once. Health share 2.0 |
| BS | Choir platforms | Three 96 x 72 px raised ledges near the corners, 170 px off the doors; nothing lands or flows on them; the song can pull you off |
| BW | Cistern sluice | A wheel in the Choir's arena after the kill; drained Cistern: no puddles, drains or deep pools, non-boss enemies 1.3x health and 1.15x damage; the Choir's own flood stays |
| BV | Late-build fps | Accepted for now: boss fights with the floor-2 storm build run about 81 to 83 fps (Choir and Hive Mother alike); the arenas alone hold 100 |
| BT | Choir in the floor-number boss cycle | Not added to `SpawnTable.BOSSES` (that would change which boss appears past floor 5); the region picks it through `boss_kind` |
| BU | Cistern lesson rewards | Region: Storm Seeker. Boss: Storm Pike |

---

## Sources

From `research_notes/World structure references/notes.md`, which has the tags and links:

- Dead Cells biome graph, rune gates and blueprints (Dead Cells wiki).
- Run lengths for Hades II (Kotaku), Halls of Torment (Godot showcase), Brotato (Brotato wiki),
  Returnal (Inverse) and Risk of Rain 2.
- Dark Souls interconnection analysis (TheGamer) and the Dark Souls 2 warping critique (community
  sources).
- Hades dialogue volume (Cultured Vultures, GDC 2021 talk) and Hades II volume (GamesRadar).
- Halls of Torment marks, the well and conditional unlocks (Godot showcase and guides).
- Risk of Rain 2 skill loadouts and challenges (Risk of Rain 2 wiki).
- Noita wetness and immunities (Noita wiki) and Outer Wilds' knowledge progression (essay and
  review).

Gaps the research could not fill, to verify before relying on them: Elden Ring legacy dungeon
commentary, Enter the Gungeon loadouts, the number of Hades' death-reactive lines, Divinity:
Original Sin 2 and Monster Hunter resistance design, and Inscryption's structure.
